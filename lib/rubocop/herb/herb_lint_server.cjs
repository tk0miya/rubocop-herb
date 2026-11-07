// A long-running process that lints HTML+ERB sources with herb-lint (@herb-tools/linter).
//
// It is spawned by RuboCop::Herb::HerbLintClient and talks JSON Lines over stdin/stdout:
//
//   startup:  {"ready": true}  or  {"error": "..."}
//   request:  {"path": "/abs/path/to/file.html.erb", "source": "...", "unsafeFixes": false}
//   response: {"offenses": [{"rule", "message", "severity", "location": {"start", "end"}, "fix"}]}  or  {"error": "..."}
//
// The fix of an offense is the autofix of herb-lint as a replacement of the source
// ({"start", "end", "replacement"}; positions are 0-based character (code point) offsets),
// or null if the offense is not autocorrectable. Unsafe fixes (applied by `herb-lint --fix-unsafely`)
// are included only if the request asks for them with "unsafeFixes".
//
// herb-lint packages are resolved from the project root given as the first argument,
// so the version installed in the project is used.
"use strict";

const path = require("node:path");
const { createRequire } = require("node:module");
const { createInterface } = require("node:readline");

const SEVERITY_LEVELS = { error: 4, warning: 3, info: 2, hint: 1 };

// stdout is the channel to the client; keep its writer and send console output of
// herb-lint and custom rules to stderr not to break the protocol
const writeStdout = process.stdout.write.bind(process.stdout);
console.log = console.info = console.debug = console.error;

function write(message) {
  writeStdout(JSON.stringify(message) + "\n");
}

function loadPackages(projectRoot) {
  const projectRequire = createRequire(path.join(projectRoot, "package.json"));
  let linterPath;
  try {
    linterPath = projectRequire.resolve("@herb-tools/linter");
  } catch {
    throw new Error(`@herb-tools/linter is not installed in ${projectRoot}`);
  }

  // Resolve the other packages from the linter so that the versions match
  const linterRequire = createRequire(linterPath);
  return {
    linter: linterRequire(linterPath),
    loader: linterRequire("@herb-tools/linter/loader"),
    nodeWasm: linterRequire("@herb-tools/node-wasm"),
    config: linterRequire("@herb-tools/config"),
    version: linterRequire("@herb-tools/linter/package.json").version
  };
}

async function setup(projectRoot) {
  const packages = loadPackages(projectRoot);
  const { Herb } = packages.nodeWasm;
  const { Config } = packages.config;
  const { Linter, rules } = packages.linter;

  await Herb.load();

  const config = await Config.load(projectRoot, {
    version: packages.version,
    createIfMissing: false,
    exitOnError: false,
    silent: true
  });
  const { rules: customRules } = await packages.loader.loadCustomRules({ baseDir: projectRoot, silent: true });

  return {
    projectRoot,
    config,
    linter: Linter.from(Herb, config, customRules),
    oncePerRunRules: new Set(rules.filter((rule) => rule.reportsOncePerRun === true).map((rule) => rule.ruleName)),
    // The files where the rules reported once per run were reported, by rule name
    reportedRules: new Map(),
    logLevel: SEVERITY_LEVELS[config.linter?.logLevel] ?? SEVERITY_LEVELS.hint
  };
}

// Whether the rule of the offense can fix it, as herb-lint judges for `--fix` and `--fix-unsafely`.
// The same judgement as `fixabilityFor` of @herb-tools/linter, written here not to depend on its export
function fixability(linter, offense) {
  const ruleClass = linter.rules.find((rule) => rule.ruleName === offense.rule);
  if (!ruleClass) return { fixable: false, unsafe: false };
  if (ruleClass.autofixRequiresContext === true && !offense.autofixContext) return { fixable: false, unsafe: false };

  const unsafe = ruleClass.unsafeAutocorrectable === true || offense.autofixContext?.unsafe === true;
  return { fixable: ruleClass.autocorrectable === true || unsafe, unsafe };
}

// The smallest replacement turning `before` into `after`, in code points (characters of Ruby strings)
function replacement(before, after) {
  const beforeChars = Array.from(before);
  const afterChars = Array.from(after);
  let start = 0;
  while (start < beforeChars.length && start < afterChars.length && beforeChars[start] === afterChars[start]) start++;
  let end = 0;
  while (end < beforeChars.length - start && end < afterChars.length - start &&
         beforeChars[beforeChars.length - 1 - end] === afterChars[afterChars.length - 1 - end]) end++;
  return { start, end: beforeChars.length - end, replacement: afterChars.slice(start, afterChars.length - end).join("") };
}

// The autofix of the offense as a replacement of the source, or null if it is not autocorrectable.
// Offenses are fixed one by one so that each offense gets its own replacement.
function fix(linter, offense, source, context, unsafeFixes) {
  const { fixable, unsafe } = fixability(linter, offense);
  if (!fixable || (unsafe && !unsafeFixes)) return null;

  let result;
  try {
    result = linter.autofix(source, context, [offense], { includeUnsafe: unsafeFixes });
  } catch {
    return null;
  }
  if (result.fixed.length === 0 || result.source === source) return null;

  return replacement(source, result.source);
}

function lint(state, { path: filePath, source, unsafeFixes = false }) {
  const { config, linter } = state;
  const fileName = path.relative(state.projectRoot, filePath);
  if (!config.isLinterEnabled || !config.isLinterEnabledForPath(fileName)) return [];

  const context = { fileName, projectPath: state.projectRoot };
  const result = linter.lint(source, context);
  return result.offenses
    .filter((offense) => (SEVERITY_LEVELS[offense.severity] ?? SEVERITY_LEVELS.hint) >= state.logLevel)
    .filter((offense) => {
      // Rules like herb-config-framework-option are reported only once per run, on the first file.
      // They are reported again when the first file is linted again (e.g. in the iterations of autocorrection,
      // rubocop --server and rubocop --lsp); otherwise they would disappear from it
      if (!state.oncePerRunRules.has(offense.rule)) return true;

      const reportedFile = state.reportedRules.get(offense.rule);
      if (reportedFile !== undefined) return reportedFile === filePath;

      state.reportedRules.set(offense.rule, filePath);
      return true;
    })
    .map((offense) => ({
      rule: offense.rule,
      message: offense.message,
      severity: offense.severity,
      location: { start: offense.location.start, end: offense.location.end },
      fix: fix(linter, offense, source, context, unsafeFixes)
    }));
}

async function main() {
  const projectRoot = path.resolve(process.argv[2] || process.cwd());

  let state;
  try {
    state = await setup(projectRoot);
  } catch (error) {
    write({ error: error.message });
    process.exit(1);
  }
  write({ ready: true });

  for await (const line of createInterface({ input: process.stdin })) {
    try {
      write({ offenses: lint(state, JSON.parse(line)) });
    } catch (error) {
      write({ error: error.message });
    }
  }
}

main();
