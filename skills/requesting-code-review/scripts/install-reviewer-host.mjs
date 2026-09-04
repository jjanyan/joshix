#!/usr/bin/env node

import { randomUUID } from 'node:crypto';
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
  realpathSync,
  renameSync,
  rmSync,
  writeSync,
} from 'node:fs';
import { homedir } from 'node:os';
import {
  basename,
  delimiter,
  dirname,
  isAbsolute,
  join,
  resolve,
} from 'node:path';
import { fileURLToPath } from 'node:url';

const sourceFile = fileURLToPath(import.meta.url);
const sourceLauncher = join(dirname(sourceFile), 'reviewer-host-launcher.mjs');

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

export function executableOnPath(name) {
  for (const directory of (process.env.PATH ?? '').split(delimiter)) {
    const candidate = resolve(directory || '.', name);
    try {
      accessSync(candidate, fsConstants.X_OK);
      const canonical = realpathSync(candidate);
      if (lstatSync(canonical).isFile()) return canonical;
    } catch {
      // Continue to the next PATH entry.
    }
  }
  throw new Error(`${name} executable was not found on PATH`);
}

export function exactExecutable(path, label) {
  const canonical = realpathSync(path);
  const stats = lstatSync(canonical);
  if (!stats.isFile()) throw new Error(`${label} executable is not a file`);
  accessSync(canonical, fsConstants.X_OK);
  return canonical;
}

function firstLine(path) {
  return readFileSync(path, 'utf8').split(/\r?\n/, 1)[0];
}

function providerCommand(path, node) {
  const line = firstLine(path);
  if (/^#!\/usr\/bin\/env[ \t]+(?:-S[ \t]+)?node(?:[ \t]|$)/.test(line)) {
    return { command: node, prefixArgs: [path] };
  }
  return { command: path, prefixArgs: [] };
}

export function requireSafeNodeShebangPath(path) {
  if (/[\s$\\"'#]/u.test(path)) {
    throw new Error('Node executable path cannot contain whitespace or env -S metacharacters');
  }
}

function requirePermissionSafeLauncher(path) {
  if (/[\s,]/u.test(path)) {
    throw new Error('launcher path cannot contain whitespace or commas');
  }
}

function atomicWrite(path, content, mode) {
  const directory = dirname(path);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  chmodSync(directory, 0o700);
  const temporary = join(directory, `.${basename(path)}.${randomUUID()}.tmp`);
  const descriptor = openSync(
    temporary,
    fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY,
    mode,
  );
  try {
    const bytes = Buffer.from(content);
    let offset = 0;
    while (offset < bytes.length) {
      offset += writeSync(descriptor, bytes, offset, bytes.length - offset);
    }
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
  chmodSync(temporary, mode);
  renameSync(temporary, path);
}

function configuredLauncher({ node, claude, codex, git }) {
  requireSafeNodeShebangPath(node);
  const source = readFileSync(sourceLauncher, 'utf8');
  const configured = source.replace(
    'const INSTALLED_EXECUTABLES = null;',
    () => `const INSTALLED_EXECUTABLES = Object.freeze(${JSON.stringify({
      node,
      claude,
      codex,
      git,
    })});`,
  );
  if (configured === source) throw new Error('launcher configuration marker is missing');
  return configured.replace(
    /^#![^\n]*/,
    () => `#!/usr/bin/env -S -u NODE_OPTIONS -u NODE_PATH ${node}`,
  );
}

function codexRule(launcher) {
  return [
    'prefix_rule(',
    `    pattern = [${JSON.stringify(launcher)}, "review"],`,
    '    decision = "allow",',
    '    justification = "Run the read-only joshix review bridge",',
    ')',
  ].join('\n');
}

function main() {
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

  const node = exactExecutable(process.execPath, 'Node');
  const claudePath = exactExecutable(executableOnPath('claude'), 'Claude');
  const codexPath = exactExecutable(executableOnPath('codex'), 'Codex');
  const git = exactExecutable(executableOnPath('git'), 'Git');
  const launcherPath = join(installRoot, 'bin/joshix-review');
  requirePermissionSafeLauncher(launcherPath);
  const content = configuredLauncher({
    node,
    claude: providerCommand(claudePath, node),
    codex: providerCommand(codexPath, node),
    git,
  });

  atomicWrite(launcherPath, content, 0o700);

  // Remove only the exact generated paths from the previous layout, and only
  // after the replacement executable is safely in place.
  rmSync(join(installRoot, 'config.json'), { force: true });
  rmSync(join(installRoot, 'lib'), { recursive: true, force: true });

  process.stdout.write(`${JSON.stringify({
    installRoot,
    launcher: launcherPath,
    codexRule: codexRule(launcherPath),
    claudePermission: `Bash(${launcherPath} review:*)`,
  })}\n`);
}

if (
  process.argv[1]
  && realpathSync(process.argv[1]) === realpathSync(sourceFile)
) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : 'reviewer host installation failed'}\n`);
    process.exitCode = 1;
  }
}
