#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import {
  accessSync,
  chmodSync,
  closeSync,
  constants as fsConstants,
  existsSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  realpathSync,
  renameSync,
  rmSync,
  writeSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { basename, delimiter, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const sourceFile = fileURLToPath(import.meta.url);
const sourceRoot = resolve(dirname(sourceFile), '../../..');
const sourceLauncher = join(dirname(sourceFile), 'reviewer-host-launcher.mjs');
const sourceRunner = join(dirname(sourceFile), 'reviewer-runner.mjs');
const sourceSchema = join(dirname(sourceFile), '../review-result.schema.json');
const sourceTaskContext = join(sourceRoot, 'skills/task-context/scripts/task-context.mjs');

function inside(parent, child) {
  const local = relative(parent, child);
  return local === '' || (!local.startsWith(`..${sep}`) && local !== '..' && !isAbsolute(local));
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
}

function parseArgs(argv) {
  if (argv.length === 0) return {};
  if (argv.length !== 2 || argv[0] !== '--install-dir' || !isAbsolute(argv[1])) {
    throw new Error('usage: install-reviewer-host.mjs [--install-dir ABSOLUTE_PATH]');
  }
  return { installDir: argv[1] };
}

function hasGitMarker(path) {
  let cursor = resolve(path);
  for (;;) {
    if (existsSync(join(cursor, '.git'))) return true;
    const parent = dirname(cursor);
    if (parent === cursor) return false;
    cursor = parent;
  }
}

function forbiddenCachePath(path) {
  return /(?:^|[\\/])\.(?:codex|claude)[\\/]plugins[\\/]cache(?:[\\/]|$)/.test(path);
}

function executableOnPath(name) {
  for (const directory of (process.env.PATH ?? '').split(delimiter)) {
    const candidate = resolve(directory || '.', name);
    try {
      const stats = lstatSync(candidate);
      if (!stats.isFile() && !stats.isSymbolicLink()) continue;
      accessSync(candidate, fsConstants.X_OK);
      const canonical = realpathSync(candidate);
      const target = lstatSync(canonical);
      if (target.isFile()) return canonical;
    } catch {
      // Keep searching PATH.
    }
  }
  throw new Error(`${name} executable was not found on PATH`);
}

function safeExternalExecutable(path, label, installRoot, { shebangInterpreter = false } = {}) {
  const canonical = realpathSync(path);
  if (inside(sourceRoot, canonical) || inside(installRoot, canonical) || forbiddenCachePath(canonical)) {
    throw new Error(`${label} executable is in a mutable or privileged source tree`);
  }
  if (/\0/.test(canonical) || (shebangInterpreter && /\s/.test(canonical))) {
    throw new Error(`${label} executable path cannot contain whitespace`);
  }
  const stats = lstatSync(canonical);
  if (!stats.isFile() || (stats.mode & 0o022) !== 0) {
    throw new Error(`${label} executable has unsafe permissions`);
  }
  if (typeof process.getuid === 'function' && ![0, process.getuid()].includes(stats.uid)) {
    throw new Error(`${label} executable has the wrong owner`);
  }
  accessSync(canonical, fsConstants.X_OK);
  return canonical;
}

function firstLine(path) {
  const descriptor = openSync(path, fsConstants.O_RDONLY);
  try {
    const bytes = Buffer.alloc(512);
    const count = readSync(descriptor, bytes, 0, bytes.length, 0);
    return bytes.subarray(0, count).toString('utf8').split(/\r?\n/, 1)[0];
  } finally {
    closeSync(descriptor);
  }
}

function providerEntry(path, node, label) {
  const line = firstLine(path);
  if (!line.startsWith('#!')) return { path };
  if (/^#!\/usr\/bin\/env[ \t]+(?:-S[ \t]+)?node[ \t]*$/.test(line)) {
    return { path, interpreter: node };
  }
  if (/^#!\/usr\/bin\/env(?:[ \t]|$)/.test(line)) {
    throw new Error(`${label} uses an unsupported PATH-resolved interpreter`);
  }
  return { path };
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function atomicWrite(path, content, mode) {
  const directory = dirname(path);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  chmodSync(directory, 0o700);
  const temporary = join(directory, `.${basename(path)}.${randomUUID()}.tmp`);
  const descriptor = openSync(temporary, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY, mode);
  try {
    const bytes = Buffer.isBuffer(content) ? content : Buffer.from(content);
    let offset = 0;
    while (offset < bytes.length) offset += writeSync(descriptor, bytes, offset);
    fsyncSync(descriptor);
    chmodSync(temporary, mode);
  } finally {
    closeSync(descriptor);
  }
  renameSync(temporary, path);
}

function shebang(node) {
  return `#!/usr/bin/env -S -u NODE_OPTIONS -u NODE_PATH ${node}`;
}

function launcherContent(node) {
  const source = readFileSync(sourceLauncher, 'utf8');
  return source.replace(/^#![^\n]*/, shebang(node));
}

function preflightShebang(installRoot, node) {
  const probe = join(installRoot, `.env-probe-${randomUUID()}`);
  atomicWrite(probe, `${shebang(node)}\nprocess.stdout.write(process.execPath);\n`, 0o500);
  try {
    const result = spawnSync(probe, [], {
      encoding: 'utf8',
      env: { ...process.env, NODE_OPTIONS: '', NODE_PATH: '' },
      shell: false,
    });
    if (result.status !== 0 || realpathSync(result.stdout.trim()) !== node) {
      throw new Error('/usr/bin/env does not support the required -S/-u interpreter boundary');
    }
  } finally {
    rmSync(probe, { force: true });
  }
}

function authStatus(provider, entry) {
  const args = provider === 'claude' ? ['auth', 'status'] : ['login', 'status'];
  const command = entry.interpreter ?? entry.path;
  const prefix = entry.interpreter ? [entry.path] : [];
  const result = spawnSync(command, [...prefix, ...args], {
    encoding: 'utf8', shell: false, timeout: 10_000,
  });
  if (result.status === 0) return 'available';
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  if (/not logged|unauthoriz|authentication required|please (?:run )?\/?login/i.test(output)) {
    return 'unavailable';
  }
  return 'unknown';
}

function codexReviewerState() {
  const config = join(process.env.HOME || homedir(), '.codex/config.toml');
  if (!existsSync(config)) return { state: 'absent', migrationNotice: null };
  const match = readFileSync(config, 'utf8').match(/^\s*approvals_reviewer\s*=\s*["']([^"']+)["']/m);
  if (!match) return { state: 'absent', migrationNotice: null };
  return {
    state: match[1],
    migrationNotice: match[1] === 'guardian_subagent'
      ? 'Replace legacy approvals_reviewer = "guardian_subagent" with "auto_review" if automatic escalation review is desired.'
      : null,
  };
}

function codexRule(launcher) {
  return [
    'prefix_rule(',
    `    pattern = [${JSON.stringify(launcher)}, "review"],`,
    '    decision = "allow",',
    '    justification = "Run the bounded read-only joshix reviewer launcher outside the workspace sandbox",',
    `    match = [${JSON.stringify(`${launcher} review --provider claude`)}],`,
    `    not_match = [${JSON.stringify(`${launcher} setup`)}],`,
    ')',
  ].join('\n');
}

function main() {
  try {
    if (process.platform === 'win32') throw new Error('native Windows installation is unsupported');
    const options = parseArgs(process.argv.slice(2));
    const defaultRoot = isAbsolute(process.env.XDG_DATA_HOME ?? '')
      ? join(process.env.XDG_DATA_HOME, 'joshix/reviewer-host')
      : join(process.env.HOME || homedir(), '.local/share/joshix/reviewer-host');
    const requestedRoot = resolve(options.installDir ?? defaultRoot);
    if (hasGitMarker(requestedRoot) || forbiddenCachePath(requestedRoot)) {
      throw new Error('install directory must be outside Git worktrees and plugin caches');
    }
    mkdirSync(requestedRoot, { recursive: true, mode: 0o700 });
    chmodSync(requestedRoot, 0o700);
    const installRoot = realpathSync(requestedRoot);

    const node = safeExternalExecutable(process.execPath, 'Node', installRoot, { shebangInterpreter: true });
    const claude = safeExternalExecutable(executableOnPath('claude'), 'Claude', installRoot);
    const codex = safeExternalExecutable(executableOnPath('codex'), 'Codex', installRoot);
    const providers = {
      claude: providerEntry(claude, node, 'Claude'),
      codex: providerEntry(codex, node, 'Codex'),
    };
    preflightShebang(installRoot, node);

    const launcherPath = join(installRoot, 'bin/joshix-review');
    const runnerPath = join(installRoot, 'lib/skills/requesting-code-review/scripts/reviewer-runner.mjs');
    const schemaPath = join(installRoot, 'lib/skills/requesting-code-review/review-result.schema.json');
    const helperPath = join(installRoot, 'lib/skills/task-context/scripts/task-context.mjs');
    const runnerBytes = readFileSync(sourceRunner);
    const schemaBytes = readFileSync(sourceSchema);
    const helperBytes = Buffer.from(
      readFileSync(sourceTaskContext, 'utf8').replace(/^#![^\n]*/, shebang(node)),
    );
    const launcherBytes = Buffer.from(launcherContent(node));

    atomicWrite(runnerPath, runnerBytes, 0o400);
    atomicWrite(schemaPath, schemaBytes, 0o400);
    atomicWrite(helperPath, helperBytes, 0o500);

    const manifest = {
      schemaVersion: 1,
      installRoot,
      node,
      launcher: { path: launcherPath, sha256: sha256(launcherBytes) },
      runner: { path: runnerPath, sha256: sha256(runnerBytes) },
      reviewSchema: { path: schemaPath, sha256: sha256(schemaBytes) },
      taskContextHelper: { path: helperPath, sha256: sha256(helperBytes) },
      providers,
    };
    atomicWrite(join(installRoot, 'config.json'), `${JSON.stringify(manifest, null, 2)}\n`, 0o600);
    atomicWrite(launcherPath, launcherBytes, 0o500);

    const reviewer = codexReviewerState();
    process.stdout.write(`${JSON.stringify({
      installRoot,
      launcher: launcherPath,
      auth: {
        claude: authStatus('claude', providers.claude),
        codex: authStatus('codex', providers.codex),
      },
      codexApprovalsReviewer: reviewer.state,
      migrationNotice: reviewer.migrationNotice,
      codexRule: codexRule(launcherPath),
      claudePermission: `Bash(${launcherPath} review:*)`,
    })}\n`);
  } catch (error) {
    fail(error instanceof Error ? error.message : 'reviewer host installation failed');
  }
}

main();
