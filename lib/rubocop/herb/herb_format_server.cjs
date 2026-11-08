// A long-running process that formats HTML+ERB sources with herb-format (@herb-tools/formatter).
//
// It is spawned by RuboCop::Herb::HerbFormatClient and talks JSON Lines over stdin/stdout:
//
//   startup:  {"ready": true}  or  {"error": "..."}
//   request:  {"path": "/abs/path/to/file.html.erb", "source": "..."}
//   response: {"fixes": [{"start", "end", "replacement"}]}  or  {"error": "..."}
//
// The fixes are the differences between the source and the source formatted by herb-format,
// as replacements of the source (positions are 0-based character (code point) offsets).
// They are split by the lines matched ignoring the whitespace around them, so that each changed part
// (e.g. a reindented line) is reported separately.
// No fixes are returned for the files herb-format does not format: when the formatter is not enabled
// for the file in .herb.yml, and when herb-format skips the file (e.g. parse errors, `<%# herb:formatter ignore %>`).
//
// It is built on node_server.cjs, which describes the protocol and the resolution of the packages.
"use strict";

const { configDir, requireFromProject, replacement, serve } = require("./node_server.cjs");

// The maximum size of the table to compute the longest common subsequence of lines.
// The differences in larger parts of the files are reported as one fix not to spend time and memory
const MAX_LCS_TABLE_SIZE = 4_000_000;

function loadPackages(projectRoot) {
  const { exports: formatter, require: formatterRequire } = requireFromProject(projectRoot, "@herb-tools/formatter");

  // Resolve the other packages from the formatter so that the versions match
  return {
    formatter,
    rewriterLoader: formatterRequire("@herb-tools/rewriter/loader"),
    nodeWasm: formatterRequire("@herb-tools/node-wasm"),
    config: formatterRequire("@herb-tools/config"),
    version: formatterRequire("@herb-tools/formatter/package.json").version
  };
}

// Loads the rewriters configured in .herb.yml (`formatter.rewriter.pre` and `formatter.rewriter.post`)
// from the built-in and custom ones (`.herb/rewriters/`), as herb-format does.
// Rewriters not found or failing to initialize are skipped with a warning, as herb-format does.
// The custom rewriters are loaded from `baseDir` (the directory of .herb.yml).
async function loadRewriters(loader, config, baseDir) {
  const names = config.formatter?.rewriter ?? {};
  const pre = names.pre ?? [];
  const post = names.post ?? [];
  if (pre.length === 0 && post.length === 0) return { preRewriters: [], postRewriters: [] };

  const { rewriters: customRewriters } = await new loader.CustomRewriterLoader({ baseDir, silent: true })
    .loadRewritersWithInfo();
  const rewriterClasses = new Map();
  for (const RewriterClass of [...loader.builtinRewriters, ...customRewriters]) {
    rewriterClasses.set(new RewriterClass().name, RewriterClass);
  }

  async function instantiate(name, kind, isKind) {
    const RewriterClass = rewriterClasses.get(name);
    if (!RewriterClass) {
      console.warn(`herb-format: ${kind}-format rewriter "${name}" not found. Skipping.`);
      return null;
    }
    if (!isKind(RewriterClass)) {
      console.warn(`herb-format: rewriter "${name}" is not a ${kind}-format rewriter. Skipping.`);
      return null;
    }

    const rewriter = new RewriterClass();
    try {
      await rewriter.initialize({ baseDir });
      return rewriter;
    } catch (error) {
      console.warn(`herb-format: failed to initialize ${kind}-format rewriter "${name}": ${error}`);
      return null;
    }
  }

  const preRewriters = await Promise.all(pre.map((name) => instantiate(name, "pre", loader.isASTRewriterClass)));
  const postRewriters = await Promise.all(post.map((name) => instantiate(name, "post", loader.isStringRewriterClass)));
  return { preRewriters: preRewriters.filter(Boolean), postRewriters: postRewriters.filter(Boolean) };
}

async function setup(projectRoot) {
  const packages = loadPackages(projectRoot);
  const { Herb } = packages.nodeWasm;
  const { Config } = packages.config;
  const { Formatter } = packages.formatter;

  await Herb.load();

  const config = await Config.load(projectRoot, {
    version: packages.version,
    createIfMissing: false,
    exitOnError: false,
    silent: true
  });
  const rewriters = await loadRewriters(packages.rewriterLoader, config, configDir(Config, config, projectRoot));

  return {
    config,
    herb: Herb,
    formatter: Formatter.from(Herb, config, rewriters)
  };
}

// The lines of the text, keeping their line breaks
function splitLines(text) {
  return text.match(/[^\n]*\n|[^\n]+$/g) ?? [];
}

// The pairs of the indices of the lines matched by the longest common subsequence of `a` and `b`,
// or null if the table to compute it is too large
function matchLines(a, b) {
  const rows = a.length + 1;
  const columns = b.length + 1;
  if (rows * columns > MAX_LCS_TABLE_SIZE) return null;

  // lengths[i * columns + j]: the length of the LCS of a[i..] and b[j..]
  const lengths = new Uint32Array(rows * columns);
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      lengths[i * columns + j] = a[i] === b[j]
        ? lengths[(i + 1) * columns + j + 1] + 1
        : Math.max(lengths[(i + 1) * columns + j], lengths[i * columns + j + 1]);
    }
  }

  const matches = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      matches.push([i, j]);
      i++;
      j++;
    } else if (lengths[(i + 1) * columns + j] >= lengths[i * columns + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return matches;
}

// The changed parts of the lines: [beforeStart, beforeEnd, afterStart, afterEnd] in line indices.
// Lines are matched ignoring the whitespace around them, so that a line only reindented
// (the most common change of formatting) is a part by itself
function changedParts(before, after) {
  // Skip the lines unchanged at the start and the end not to compare them
  let start = 0;
  while (start < before.length && start < after.length && before[start] === after[start]) start++;
  let end = 0;
  while (end < before.length - start && end < after.length - start &&
         before[before.length - 1 - end] === after[after.length - 1 - end]) end++;

  const beforeEnd = before.length - end;
  const afterEnd = after.length - end;
  const trim = (line) => line.trim();
  const matches = matchLines(before.slice(start, beforeEnd).map(trim), after.slice(start, afterEnd).map(trim)) ?? [];

  const parts = [];
  let i = start;
  let j = start;
  for (const [matchedBefore, matchedAfter] of [...matches, [beforeEnd - start, afterEnd - start]]) {
    const nextI = start + matchedBefore;
    const nextJ = start + matchedAfter;
    // The lines between the matched ones
    if (i < nextI || j < nextJ) parts.push([i, nextI, j, nextJ]);
    // The matched lines, if they differ in the whitespace around them
    if (nextI < beforeEnd && before[nextI] !== after[nextJ]) parts.push([nextI, nextI + 1, nextJ, nextJ + 1]);
    i = nextI + 1;
    j = nextJ + 1;
  }
  return parts;
}

// The fixes turning `source` into `formatted`, one for each changed part of the lines
function fixes(source, formatted) {
  const before = splitLines(source);
  const after = splitLines(formatted);

  // The character offsets of the lines in the source
  const offsets = [0];
  for (const line of before) offsets.push(offsets[offsets.length - 1] + Array.from(line).length);

  const result = [];
  for (const [beforeStart, beforeEnd, afterStart, afterEnd] of changedParts(before, after)) {
    const fix = replacement(before.slice(beforeStart, beforeEnd).join(""), after.slice(afterStart, afterEnd).join(""));
    const current = { start: offsets[beforeStart] + fix.start, end: offsets[beforeStart] + fix.end,
                      replacement: fix.replacement };

    // Join the fixes touching each other (e.g. a line break removed at the end of a line and
    // the indentation of the next line), as RuboCop cannot apply both of them at the same position
    const previous = result[result.length - 1];
    if (previous && previous.end === current.start) {
      previous.end = current.end;
      previous.replacement += current.replacement;
    } else {
      result.push(current);
    }
  }
  return result;
}

function format(state, { path: filePath, source }) {
  const { config, formatter, herb } = state;
  // The patterns of .herb.yml are relative to its directory, which may be above the project root,
  // so pass the absolute path for the configuration to resolve it
  if (!config.isFormatterEnabledForPath(filePath)) return [];

  const result = formatter.formatWithResult(source, {}, filePath);
  if (result.skipped) return [];

  // herb-format ends the files with a newline
  const formatted = result.output === "" || result.output.endsWith("\n") ? result.output : result.output + "\n";
  if (formatted === source) return [];

  // Do not break the template, in case the formatter fails to keep it (it is in experimental preview)
  const parseErrors = (text) => herb.parse(text, config.parserOptions).recursiveErrors().length;
  if (parseErrors(formatted) > parseErrors(source)) return [];

  return fixes(source, formatted);
}

serve(setup, (state, request) => ({ fixes: format(state, request) }));
