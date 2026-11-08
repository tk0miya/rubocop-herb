// Shared parts of the servers running Herb tools (herb_lint_server.cjs and herb_format_server.cjs).
//
// A server is spawned by RuboCop::Herb::NodeServerClient and talks JSON Lines over stdin/stdout:
//
//   startup:  {"ready": true}  or  {"error": "..."}
//   request:  a JSON object per line
//   response: a JSON object per line, or {"error": "..."}
//
// The packages of Herb tools are resolved from the project root given as the first argument,
// so the versions installed in the project are used.
"use strict";

const path = require("node:path");
const { createRequire } = require("node:module");
const { createInterface } = require("node:readline");

// stdout is the channel to the client; keep its writer and send console output of
// Herb tools and their plugins (e.g. custom rules) to stderr not to break the protocol
const writeStdout = process.stdout.write.bind(process.stdout);
console.log = console.info = console.debug = console.error;

function write(message) {
  writeStdout(JSON.stringify(message) + "\n");
}

// Requires the package installed in the project, and returns it with a require function
// resolving packages from it (to load its dependencies in the versions matching it)
function requireFromProject(projectRoot, name) {
  const projectRequire = createRequire(path.join(projectRoot, "package.json"));
  let packagePath;
  try {
    packagePath = projectRequire.resolve(name);
  } catch {
    throw new Error(`${name} is not installed in ${projectRoot}`);
  }

  const packageRequire = createRequire(packagePath);
  return { exports: packageRequire(packagePath), require: packageRequire };
}

// The directory of .herb.yml, to which the configuration of Herb tools (e.g. the patterns in .herb.yml and
// the directory of custom rules) is relative. It may be above the project root (e.g. a monorepo).
// Without .herb.yml, Herb falls back to the first directory with a project indicator (e.g. Gemfile)
// or the current directory; the project root is used instead
function configDir(Config, config, projectRoot) {
  return Config.exists(config.projectPath) ? config.projectPath : projectRoot;
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

// Starts the server: `setup(projectRoot)` builds the state on startup, and `handle(state, request)`
// returns the response to a request
async function serve(setup, handle) {
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
      write(handle(state, JSON.parse(line)));
    } catch (error) {
      write({ error: error.message });
    }
  }
}

module.exports = { configDir, requireFromProject, replacement, serve };
