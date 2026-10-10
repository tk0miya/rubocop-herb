// A long-running process that lints HTML+ERB sources with herb-lint (@herb-tools/linter).
//
// It is spawned by RuboCop::Herb::HerbLintClient and talks JSON Lines over stdin/stdout:
//
//   startup:  {"ready": true}  or  {"error": "..."}
//   request:  {"path": "/abs/path/to/file.html.erb", "source": "..."}
//   response: {"offenses": [{"rule", "message", "severity", "location": {"start", "end"}}]}  or  {"error": "..."}
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
    reportedRules: new Set(),
    logLevel: SEVERITY_LEVELS[config.linter?.logLevel] ?? SEVERITY_LEVELS.hint
  };
}

function lint(state, { path: filePath, source }) {
  const { config, linter } = state;
  const fileName = path.relative(state.projectRoot, filePath);
  if (!config.isLinterEnabled || !config.isLinterEnabledForPath(fileName)) return [];

  const result = linter.lint(source, { fileName, projectPath: state.projectRoot });
  return result.offenses
    .filter((offense) => (SEVERITY_LEVELS[offense.severity] ?? SEVERITY_LEVELS.hint) >= state.logLevel)
    .filter((offense) => {
      // Rules like herb-config-framework-option are reported only once per run
      if (!state.oncePerRunRules.has(offense.rule)) return true;
      if (state.reportedRules.has(offense.rule)) return false;

      state.reportedRules.add(offense.rule);
      return true;
    })
    .map((offense) => ({
      rule: offense.rule,
      message: offense.message,
      severity: offense.severity,
      location: { start: offense.location.start, end: offense.location.end }
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
