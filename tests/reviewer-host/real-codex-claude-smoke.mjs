#!/usr/bin/env node

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  accessSync,
  constants as fsConstants,
  lstatSync,
  mkdtempSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const taskContext = join(sourceRoot, 'skills/task-context/scripts/task-context.mjs');

function providerInvocation(entry) {
  if (!entry || !isAbsolute(entry.path)) throw new Error('installed Codex provider path is missing or invalid');
  const path = realpathSync(entry.path);
  accessSync(path, fsConstants.X_OK);
  if (entry.interpreter !== undefined) {
    if (!isAbsolute(entry.interpreter)) throw new Error('installed Codex interpreter path is invalid');
    const interpreter = realpathSync(entry.interpreter);
    accessSync(interpreter, fsConstants.X_OK);
    return { command: interpreter, prefixArgs: [path] };
  }
  return { command: path, prefixArgs: [] };
}

function codexInvocation(manifest) {
  if (!process.env.CODEX_BIN) return providerInvocation(manifest.providers?.codex);
  if (!isAbsolute(process.env.CODEX_BIN)) throw new Error('CODEX_BIN must be absolute for the real smoke');
  const command = realpathSync(process.env.CODEX_BIN);
  accessSync(command, fsConstants.X_OK);
  return { command, prefixArgs: [] };
}

function defaultLauncher() {
  if (process.env.JOSHIX_REVIEW_LAUNCHER) {
    if (!isAbsolute(process.env.JOSHIX_REVIEW_LAUNCHER)) {
      throw new Error('JOSHIX_REVIEW_LAUNCHER must be absolute');
    }
    return realpathSync(process.env.JOSHIX_REVIEW_LAUNCHER);
  }
  const dataRoot = isAbsolute(process.env.XDG_DATA_HOME ?? '')
    ? process.env.XDG_DATA_HOME
    : join(process.env.HOME || homedir(), '.local/share');
  return realpathSync(join(dataRoot, 'joshix/reviewer-host/bin/joshix-review'));
}

function hashFile(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function hashRepository(root) {
  const digest = createHash('sha256');
  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (directory === root && entry.name === '.git') continue;
      const path = join(directory, entry.name);
      const local = relative(root, path);
      const stats = lstatSync(path);
      digest.update(`${local}\0${stats.mode & 0o777}\0`);
      if (entry.isDirectory()) visit(path);
      else if (entry.isSymbolicLink()) digest.update(`link:${readlinkSync(path)}\0`);
      else digest.update(readFileSync(path));
    }
  }
  visit(root);
  return digest.digest('hex');
}

function parseEnvelope(text) {
  const trimmed = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const candidates = [trimmed, ...trimmed.split(/\r?\n/).filter((line) => line.trim().startsWith('{'))];
  for (const candidate of candidates) {
    try {
      const value = JSON.parse(candidate);
      if (value && typeof value === 'object' && 'ok' in value) return value;
    } catch {
      // Try the next bounded final-message representation.
    }
  }
  throw new Error(`Codex did not return one launcher envelope: ${trimmed.slice(0, 500)}`);
}

function runFreshCodex({ codex, fixtureRoot, launcher, promptFile, resultFile, sessionId = null }) {
  const launchArgs = [
    'review',
    '--provider', 'claude',
    '--repo-root', fixtureRoot,
    '--prompt-file', promptFile,
    '--result-schema', 'review-result-v1',
    '--timeout-ms', '120000',
    '--max-events', '500',
    '--max-output-bytes', '524288',
    '--max-review-bytes', '65536',
    ...(sessionId ? ['--session-id', sessionId] : []),
  ];
  const prompt = [
    'This is a transport smoke test, not a development task.',
    'Do not initialize or append joshix task context and do not edit any file.',
    'Use the shell tool to invoke this exact executable and argv array once:',
    JSON.stringify([launcher, ...launchArgs]),
    'Do not invoke Node, Claude, Codex, a wrapper, or any fallback directly.',
    'Return only the launcher stdout as one JSON object, with no Markdown.',
  ].join('\n');
  const result = spawnSync(codex.command, [
    ...codex.prefixArgs,
    'exec',
    '--sandbox', 'workspace-write',
    '--cd', fixtureRoot,
    '--output-last-message', resultFile,
    prompt,
  ], {
    encoding: 'utf8',
    timeout: 240_000,
    maxBuffer: 2 * 1024 * 1024,
    shell: false,
  });
  const combined = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  if (result.error) throw result.error;
  assert.equal(result.status, 0, combined);
  assert.doesNotMatch(combined, /approval (?:is )?required|waiting for approval|approve this command/i);
  return parseEnvelope(readFileSync(resultFile, 'utf8'));
}

function main() {
  if (process.platform === 'win32') throw new Error('real host smoke requires Unix process permissions');
  const launcher = defaultLauncher();
  const installRoot = dirname(dirname(launcher));
  const manifest = JSON.parse(readFileSync(join(installRoot, 'config.json'), 'utf8'));
  assert.equal(manifest.launcher.path, launcher);
  const codex = codexInvocation(manifest);

  const temporaryRoot = realpathSync(mkdtempSync(join(tmpdir(), 'joshix-real-review-smoke-')));
  try {
    const fixtureRoot = join(temporaryRoot, 'repo');
    mkdirSync(fixtureRoot);
    execFileSync('git', ['init', '--quiet'], { cwd: fixtureRoot });
    writeFileSync(join(fixtureRoot, 'AGENTS.md'), [
      '# Transport smoke fixture',
      '',
      'For this fixture only, do not initialize or append task context and do not edit files.',
      'Run only the exact reviewer-launch command supplied by the user.',
      '',
    ].join('\n'));

    const taskFolder = '.joshix/tasks/real-codex-claude-smoke';
    const initialized = spawnSync(taskContext, ['init', taskFolder], {
      cwd: fixtureRoot,
      encoding: 'utf8',
      shell: false,
    });
    assert.equal(initialized.status, 0, initialized.stderr);
    const contextFile = join(fixtureRoot, 'review-context.txt');
    writeFileSync(contextFile, 'The reviewer must stay read-only and return an approved structured review.\n');
    const appended = spawnSync(taskContext, [
      'append', taskFolder,
      '--speaker', 'User',
      '--content-file', contextFile,
      '--idempotency-key', 'real-codex-claude-smoke-context-v1',
    ], { cwd: fixtureRoot, encoding: 'utf8', shell: false });
    assert.equal(appended.status, 0, appended.stderr);

    const promptFile = join(fixtureRoot, 'review-prompt.md');
    writeFileSync(promptFile, [
      'You are the persistent reviewer peer for this task. Remain read-only.',
      `Task folder: ${taskFolder}/`,
      `Read helper: ${manifest.taskContextHelper.path}`,
      'Gate: smoke',
      'Round: 1',
      'Review target: transport permissions only',
      'Diff/log evidence: none',
      'Focused verification: fixture initialized',
      '',
      'Read current.md and task history as needed. Attempt one harmless repository write',
      'to SHOULD_NOT_EXIST and one task-context append; both must be denied. Then return',
      'an approved structured review with no findings. Never claim either write succeeded.',
    ].join('\n'));

    const databasePath = join(fixtureRoot, taskFolder, 'history.sqlite');
    const hashRepositoryBefore = hashRepository(fixtureRoot);
    const hashTaskDatabaseBefore = hashFile(databasePath);
    const first = runFreshCodex({
      codex,
      fixtureRoot,
      launcher,
      promptFile,
      resultFile: join(temporaryRoot, 'first-codex-final.json'),
    });
    assert.equal(first.ok, true);
    assert.equal(first.provider, 'claude');
    assert.equal(first.session.mode, 'started');
    writeFileSync(join(temporaryRoot, 'claude-session.txt'), `${first.session.id}\n`);

    const second = runFreshCodex({
      codex,
      fixtureRoot,
      launcher,
      promptFile,
      resultFile: join(temporaryRoot, 'second-codex-final.json'),
      sessionId: first.session.id,
    });
    assert.equal(second.ok, true);
    assert.equal(second.provider, 'claude');
    assert.equal(second.session.id, first.session.id);
    assert.equal(second.session.mode, 'resumed');
    const sameModelFallbackObserved = first.provider !== 'claude' || second.provider !== 'claude';
    assert.equal(sameModelFallbackObserved, false);
    assert.equal(hashRepository(fixtureRoot), hashRepositoryBefore);
    assert.equal(hashFile(databasePath), hashTaskDatabaseBefore);
    assert.equal(lstatSync(join(temporaryRoot, 'claude-session.txt')).isFile(), true);
    console.log('STATUS: PASSED');
  } finally {
    rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.stack : error);
  console.log('STATUS: FAILED');
  process.exitCode = 1;
}
