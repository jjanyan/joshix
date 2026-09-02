#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  accessSync,
  closeSync,
  constants as fsConstants,
  lstatSync,
  openSync,
  readFileSync,
  realpathSync,
} from 'node:fs';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const LIMITS = Object.freeze({
  timeoutMs: 1_200_000,
  maxEvents: 20_000,
  maxOutputBytes: 8 * 1024 * 1024,
  maxReviewBytes: 512 * 1024,
});
const REQUIRED = new Set([
  '--provider', '--repo-root', '--prompt-file', '--result-schema',
  '--timeout-ms', '--max-events', '--max-output-bytes', '--max-review-bytes',
]);
const ALLOWED = new Set([...REQUIRED, '--session-id']);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const FAILURE_MESSAGES = Object.freeze({
  launcher: 'reviewer launcher validation failed',
  sandboxed: 'reviewer launcher remained sandboxed',
  'configuration-stale': 'reviewer host configuration is stale',
});

class LauncherError extends Error {
  constructor(message, kind = 'launcher') {
    super(message);
    this.kind = kind;
  }
}

function inside(parent, child) {
  const local = relative(parent, child);
  return local === '' || (!local.startsWith(`..${sep}`) && local !== '..' && !isAbsolute(local));
}

function nonSymlink(path, type) {
  let stats;
  try {
    stats = lstatSync(path);
  } catch {
    throw new LauncherError(`${type} does not exist`);
  }
  if (stats.isSymbolicLink()) throw new LauncherError(`${type} must not be a symlink`);
  return stats;
}

function uniquePairs(argv) {
  if (argv.length % 2 !== 0) throw new LauncherError('every option requires one value');
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!ALLOWED.has(name)) throw new LauncherError(`unknown option: ${name}`);
    if (values.has(name)) throw new LauncherError(`duplicate option: ${name}`);
    if (typeof value !== 'string' || value.startsWith('--')) {
      throw new LauncherError(`missing value for ${name}`);
    }
    values.set(name, value);
  }
  for (const name of REQUIRED) {
    if (!values.has(name)) throw new LauncherError(`missing option: ${name}`);
  }
  return values;
}

function boundedInteger(values, option, maximum) {
  const value = Number(values.get(option));
  if (!Number.isSafeInteger(value) || value < 1 || value > maximum) {
    throw new LauncherError(`${option} must be between 1 and ${maximum}`);
  }
  return value;
}

export function parseReviewOperation(argv) {
  const [operation, ...tail] = [...argv];
  if (operation !== 'review') throw new LauncherError('operation must be review');
  const values = uniquePairs(tail);
  const provider = values.get('--provider');
  if (!['claude', 'codex'].includes(provider)) throw new LauncherError('unknown provider');
  if (values.get('--result-schema') !== 'review-result-v1') {
    throw new LauncherError('unknown result schema');
  }

  const repoInput = values.get('--repo-root');
  if (!isAbsolute(repoInput)) throw new LauncherError('--repo-root must be absolute');
  const repoStats = nonSymlink(repoInput, 'repository root');
  if (!repoStats.isDirectory()) throw new LauncherError('repository root must be a directory');
  const repoRoot = realpathSync(repoInput);
  if (repoRoot !== resolve(repoInput)) throw new LauncherError('repository root must be canonical');
  const gitMarker = resolve(repoRoot, '.git');
  try {
    lstatSync(gitMarker);
  } catch {
    throw new LauncherError('repository root must be a Git top level');
  }

  const promptInput = values.get('--prompt-file');
  if (!isAbsolute(promptInput)) throw new LauncherError('--prompt-file must be absolute');
  const promptStats = nonSymlink(promptInput, 'prompt file');
  if (!promptStats.isFile()) throw new LauncherError('prompt file must be a regular file');
  const promptFile = realpathSync(promptInput);
  if (!inside(repoRoot, promptFile)) throw new LauncherError('prompt file must be inside repository');

  const sessionId = values.get('--session-id') ?? null;
  if (sessionId !== null && !UUID_PATTERN.test(sessionId)) {
    throw new LauncherError('--session-id must be a UUID');
  }

  return {
    provider,
    repoRoot,
    promptFile,
    resultSchema: 'review-result-v1',
    timeoutMs: boundedInteger(values, '--timeout-ms', LIMITS.timeoutMs),
    maxEvents: boundedInteger(values, '--max-events', LIMITS.maxEvents),
    maxOutputBytes: boundedInteger(values, '--max-output-bytes', LIMITS.maxOutputBytes),
    maxReviewBytes: boundedInteger(values, '--max-review-bytes', LIMITS.maxReviewBytes),
    sessionId,
  };
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

export function trustedExecutableOwner(uid, currentUid) {
  return uid === 0 || uid === currentUid;
}

function requireOwnerSafe(
  path,
  type,
  { executable = false, ownerOnly = false, trustedExecutable = false } = {},
) {
  const stats = nonSymlink(path, type);
  if (!stats.isFile()) throw new LauncherError(`${type} must be a regular file`);
  if ((stats.mode & (ownerOnly ? 0o077 : 0o022)) !== 0) {
    throw new LauncherError(`${type} has unsafe permissions`);
  }
  if (
    typeof process.getuid === 'function'
    && !(trustedExecutable
      ? trustedExecutableOwner(stats.uid, process.getuid())
      : stats.uid === process.getuid())
  ) {
    throw new LauncherError(`${type} has the wrong owner`);
  }
  if (executable) {
    try {
      accessSync(path, fsConstants.X_OK);
    } catch {
      throw new LauncherError(`${type} is not executable`);
    }
  }
  return stats;
}

function requireTrustedFile(entry, installRoot, name, options = {}) {
  if (!entry || typeof entry.path !== 'string' || !isAbsolute(entry.path)) {
    throw new LauncherError(`${name} path is invalid`);
  }
  if (!inside(installRoot, resolve(entry.path))) {
    throw new LauncherError(`${name} escaped the install root`);
  }
  requireOwnerSafe(entry.path, name, options);
  if (realpathSync(entry.path) !== resolve(entry.path)) {
    throw new LauncherError(`${name} path is not canonical`);
  }
  if (!SHA256_PATTERN.test(entry.sha256 ?? '') || sha256(entry.path) !== entry.sha256) {
    throw new LauncherError(`${name} digest mismatch`);
  }
}

function loadManifest(launcherPath, requestedProvider) {
  const installRoot = dirname(dirname(launcherPath));
  const configPath = resolve(installRoot, 'config.json');
  requireOwnerSafe(configPath, 'launcher config', { ownerOnly: true });
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(configPath, 'utf8'));
  } catch {
    throw new LauncherError('launcher config is invalid');
  }
  if (manifest?.schemaVersion !== 1 || manifest.installRoot !== installRoot) {
    throw new LauncherError('launcher config identity is invalid');
  }
  if (realpathSync(installRoot) !== installRoot) throw new LauncherError('install root is not canonical');
  requireTrustedFile(manifest.launcher, installRoot, 'launcher', { executable: true });
  requireTrustedFile(manifest.runner, installRoot, 'runner');
  requireTrustedFile(manifest.reviewSchema, installRoot, 'review schema');
  requireTrustedFile(manifest.taskContextHelper, installRoot, 'task context helper', { executable: true });
  if (manifest.launcher.path !== launcherPath) throw new LauncherError('launcher path changed');

  if (typeof manifest.node !== 'string' || !isAbsolute(manifest.node)) {
    throw new LauncherError('Node path is invalid');
  }
  requireOwnerSafe(manifest.node, 'Node executable', { executable: true, trustedExecutable: true });
  if (realpathSync(manifest.node) !== manifest.node || realpathSync(process.execPath) !== manifest.node) {
    throw new LauncherError('Node executable changed', 'configuration-stale');
  }
  for (const provider of [requestedProvider]) {
    const entry = manifest.providers?.[provider];
    const path = entry?.path;
    if (typeof path !== 'string' || !isAbsolute(path)) {
      throw new LauncherError(`${provider} path is invalid`, 'configuration-stale');
    }
    try {
      const keys = Object.keys(entry);
      if (keys.some((key) => !['path', 'interpreter'].includes(key))) throw new Error('unknown provider field');
      if (entry.interpreter !== undefined && entry.interpreter !== manifest.node) {
        throw new Error('provider interpreter changed');
      }
      requireOwnerSafe(path, `${provider} executable`, {
        executable: true,
        trustedExecutable: true,
      });
      if (realpathSync(path) !== path) throw new Error('changed');
    } catch {
      throw new LauncherError(`${provider} executable changed`, 'configuration-stale');
    }
  }
  return { installRoot, manifest };
}

function failureEnvelope(error, provider = 'unknown', elapsedMs = 0) {
  const kind = error instanceof LauncherError ? error.kind : 'launcher';
  return {
    ok: false,
    provider,
    attempts: 0,
    failure: { kind, message: FAILURE_MESSAGES[kind] ?? FAILURE_MESSAGES.launcher },
    diagnostic: {
      stage: 'launcher',
      classification: kind,
      exitStatus: null,
      signal: null,
      elapsedMs: Math.max(0, Math.round(elapsedMs)),
      excerpt: error instanceof Error ? error.message.slice(0, 512) : 'unknown launcher failure',
    },
  };
}

function sanitizedEnvironment() {
  const environment = { ...process.env };
  delete environment.NODE_OPTIONS;
  delete environment.NODE_PATH;
  delete environment.CODEX_SANDBOX;
  delete environment.CODEX_SANDBOX_NETWORK_DISABLED;
  for (const key of Object.keys(environment)) {
    if (/^JOSHIX_REVIEWER_.*_BIN$/.test(key)) delete environment[key];
  }
  return environment;
}

function knownSandboxEnvironment(environment) {
  return Boolean(environment.CODEX_SANDBOX)
    || environment.CODEX_SANDBOX_NETWORK_DISABLED === '1';
}

function requireHostCapability(installRoot, environment) {
  let descriptor;
  try {
    descriptor = openSync(resolve(installRoot, 'config.json'), fsConstants.O_RDWR);
  } catch (error) {
    const denied = ['EACCES', 'EPERM', 'EROFS'].includes(error?.code);
    const kind = denied && knownSandboxEnvironment(environment)
      ? 'sandboxed'
      : 'configuration-stale';
    throw new LauncherError('launcher could not verify host write capability', kind);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function oneEnvelope(stdout, provider, limit) {
  if (typeof stdout !== 'string' || Buffer.byteLength(stdout) > limit + 65_536) {
    throw new LauncherError('runner envelope exceeded the launcher bound');
  }
  const lines = stdout.trim().split(/\r?\n/).filter(Boolean);
  if (lines.length !== 1) throw new LauncherError('runner returned multiple envelopes');
  let envelope;
  try {
    envelope = JSON.parse(lines[0]);
  } catch {
    throw new LauncherError('runner returned malformed JSON');
  }
  if (!envelope || typeof envelope !== 'object' || envelope.provider !== provider) {
    throw new LauncherError('runner envelope provider mismatch');
  }
  return envelope;
}

async function main() {
  const started = performance.now();
  let provider = 'unknown';
  try {
    const options = parseReviewOperation(process.argv.slice(2));
    provider = options.provider;
    const launcherPath = realpathSync(process.argv[1]);
    const { installRoot, manifest } = loadManifest(launcherPath, options.provider);
    requireHostCapability(installRoot, process.env);
    for (const path of [installRoot, manifest.node, manifest.providers[provider].path]) {
      if (inside(options.repoRoot, path)) throw new LauncherError('trusted path is inside repository');
    }
    const runnerArgs = [
      '--provider', options.provider,
      '--reviewer-binary', manifest.providers[options.provider].interpreter
        ?? manifest.providers[options.provider].path,
      ...(manifest.providers[options.provider].interpreter
        ? ['--reviewer-script', manifest.providers[options.provider].path]
        : []),
      '--repo-root', options.repoRoot,
      '--prompt-file', options.promptFile,
      '--schema-file', manifest.reviewSchema.path,
      '--timeout-ms', String(options.timeoutMs),
      '--max-events', String(options.maxEvents),
      '--max-output-bytes', String(options.maxOutputBytes),
      '--max-review-bytes', String(options.maxReviewBytes),
      ...(options.sessionId ? ['--session-id', options.sessionId] : []),
    ];
    const result = spawnSync(manifest.node, [manifest.runner.path, ...runnerArgs], {
      cwd: options.repoRoot,
      env: sanitizedEnvironment(),
      encoding: 'utf8',
      maxBuffer: options.maxOutputBytes + 65_536,
      timeout: options.timeoutMs + 5_000,
      shell: false,
    });
    if (result.error) {
      const detail = `${result.error.message ?? ''}\n${result.stderr ?? ''}`;
      const kind = /operation not permitted|sandbox|deny|not permitted/i.test(detail)
        ? 'sandboxed'
        : 'launcher';
      throw new LauncherError('runner process failed', kind);
    }
    const envelope = oneEnvelope(result.stdout, options.provider, options.maxOutputBytes);
    process.stdout.write(`${JSON.stringify(envelope)}\n`);
    process.exitCode = Number.isInteger(result.status) ? result.status : 1;
  } catch (error) {
    process.stdout.write(`${JSON.stringify(failureEnvelope(error, provider, performance.now() - started))}\n`);
    process.exitCode = 1;
  }
}

function isDirectExecution() {
  if (!process.argv[1]) return false;
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isDirectExecution()) await main();
