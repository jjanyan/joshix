import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  exactExecutable,
  executableOnPath,
  requireSafeNodeShebangPath,
} from '../../skills/requesting-code-review/scripts/install-reviewer-host.mjs';
import { DatabaseSync } from 'node:sqlite';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const launcherSource = join(
  repoRoot,
  'skills/requesting-code-review/scripts/reviewer-host-launcher.mjs',
);
const installerSource = join(
  repoRoot,
  'skills/requesting-code-review/scripts/install-reviewer-host.mjs',
);
const temporaryDirectories = [];
const approvedReview = { status: 'approved', findings: [] };
const VERSION_TWO_COLUMNS = ['id', 'created_at', 'speaker', 'content', 'idempotency_key'];
const realGitPath = exactExecutable(executableOnPath('git'), 'Git');

function tempDir() {
  const directory = mkdtempSync(join(tmpdir(), 'joshix-review-bridge-'));
  temporaryDirectories.push(directory);
  return realpathSync(directory);
}

after(() => {
  for (const directory of temporaryDirectories) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function writeExecutable(path, source) {
  writeFileSync(path, source);
  chmodSync(path, 0o700);
}

const fakeProviderSource = `#!/usr/bin/env node
const fs = require('node:fs');
const config = JSON.parse(fs.readFileSync(process.env.FAKE_PROVIDER_CONFIG, 'utf8'));
const providerArgs = process.argv.slice(2);
fs.appendFileSync(process.env.FAKE_PROVIDER_LOG, JSON.stringify({
  pid: process.pid,
  args: providerArgs,
  git: Object.fromEntries(Object.entries(process.env).filter(([key]) => key.startsWith('GIT_'))),
}) + '\\n');
const schemaIndex = providerArgs.indexOf('--json-schema');
const outputSchemaIndex = providerArgs.indexOf('--output-schema');
const schema = schemaIndex !== -1
  ? JSON.parse(providerArgs[schemaIndex + 1])
  : outputSchemaIndex !== -1
    ? JSON.parse(fs.readFileSync(providerArgs[outputSchemaIndex + 1], 'utf8'))
    : null;
if (schema && Object.hasOwn(schema, 'allOf')) {
  process.stderr.write('provider schema rejected top-level allOf');
  process.exit(1);
}
if (config.waitForSignal) {
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => {
      fs.appendFileSync(process.env.FAKE_PROVIDER_SIGNAL_LOG, signal + '\\n');
      setTimeout(() => process.exit(0), 10);
    });
  }
  setInterval(() => {}, 1000);
} else {
  if (config.stderrHead) fs.writeSync(2, config.stderrHead);
  if (config.stderrText) fs.writeSync(2, config.stderrText);
  if (config.stderrBytes) fs.writeSync(2, 'd'.repeat(config.stderrBytes));
  if (config.stderrTail) fs.writeSync(2, config.stderrTail);
  for (let index = 0; index < (config.ordinaryEventCount || 0); index += 1) {
    process.stdout.write(JSON.stringify({ type: 'progress', index }) + '\\n');
  }
  if (config.rawLine !== undefined) {
    fs.writeSync(1, config.rawLine + '\\n');
  } else if (config.result !== undefined) {
    const finalIndex = providerArgs.indexOf('--output-last-message');
    if (finalIndex !== -1) {
      fs.writeFileSync(providerArgs[finalIndex + 1], JSON.stringify(config.result));
    } else {
      fs.writeSync(1, JSON.stringify({ type: 'result', structured_output: config.result }) + '\\n');
    }
  }
  process.exit(config.exitCode || 0);
}
`;

const fakeGitSource = `#!/usr/bin/env node
const fs = require('node:fs');
fs.appendFileSync(process.env.FAKE_GIT_LOG, JSON.stringify({
  args: process.argv.slice(2),
  git: Object.fromEntries(Object.entries(process.env).filter(([key]) => key.startsWith('GIT_'))),
}) + '\\n');
const outputBytes = Number(process.env.FAKE_GIT_OUTPUT_BYTES || 0);
process.stdout.write(outputBytes ? 'g'.repeat(outputBytes) : 'git-read-ok\\n');
`;

function createTask(root, {
  version = 1,
  folder = '.joshix/tasks/2026-09-04-review-fixture',
} = {}) {
  const task = join(root, folder);
  mkdirSync(task, { recursive: true });
  writeFileSync(join(task, 'current.md'), '# fixture\n');
  const db = new DatabaseSync(join(task, 'history.sqlite'));
  db.exec(`
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      speaker TEXT NOT NULL,
      content TEXT NOT NULL${version === 2 ? ', idempotency_key TEXT' : ''}
    );
    CREATE INDEX messages_created_at_idx ON messages(created_at);
    PRAGMA user_version = ${version};
  `);
  db.close();
  return folder;
}

function readJsonLines(path) {
  const text = readFileSync(path, 'utf8');
  return text.trim() ? text.trim().split('\n').map((line) => JSON.parse(line)) : [];
}

function walkFiles(root, prefix = '') {
  if (!existsSync(root)) return [];
  const files = [];
  for (const name of readdirSync(root).sort()) {
    const path = join(root, name);
    const local = prefix ? `${prefix}/${name}` : name;
    if (statSync(path).isDirectory()) files.push(...walkFiles(path, local));
    else files.push(local);
  }
  return files;
}

function embeddedExecutables(launcher) {
  const source = readFileSync(launcher, 'utf8');
  const match = source.match(
    /^const INSTALLED_EXECUTABLES = Object\.freeze\((\{.*\})\);$/m,
  );
  assert.ok(match, 'installed bridge must embed its executable configuration');
  return JSON.parse(match[1]);
}

function installFixture({
  legacy = false,
  unknownSibling = false,
  dollarPath = false,
  installDirName = 'installed-reviewer',
  nativeClaude = false,
} = {}) {
  const root = tempDir();
  const fakeBin = join(root, dollarPath ? 'fake-$&-bin' : 'fake-bin');
  const installRoot = join(root, installDirName);
  mkdirSync(fakeBin);
  writeExecutable(
    join(fakeBin, 'claude'),
    nativeClaude ? '#!/bin/sh\nexit 0\n' : fakeProviderSource,
  );
  writeExecutable(join(fakeBin, 'codex'), fakeProviderSource);
  writeExecutable(join(fakeBin, 'git'), fakeGitSource);
  if (legacy) {
    mkdirSync(join(installRoot, 'lib/skills/requesting-code-review'), { recursive: true });
    writeFileSync(join(installRoot, 'config.json'), '{}');
    writeFileSync(join(installRoot, 'lib/reviewer-runner.mjs'), 'legacy');
    writeFileSync(
      join(installRoot, 'lib/skills/requesting-code-review/review-result.schema.json'),
      '{}',
    );
    if (unknownSibling) writeFileSync(join(installRoot, 'keep-me.txt'), 'owner data');
  }

  const result = spawnSync(process.execPath, [
    installerSource, '--install-dir', installRoot,
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fakeBin}:${process.env.PATH}`,
      HOME: root,
      XDG_DATA_HOME: join(root, 'xdg'),
    },
  });
  return { root, fakeBin, installRoot, result };
}

function createFixture(options = {}) {
  const result = Object.hasOwn(options, 'result') ? options.result : approvedReview;
  const {
    rawLine,
    ordinaryEventCount,
    stderrBytes,
    stderrHead,
    stderrTail,
    stderrText,
    exitCode,
    providerFailure,
    gitOutputBytes,
  } = options;
  const temporaryRoot = tempDir();
  const root = options.repoName ? join(temporaryRoot, options.repoName) : temporaryRoot;
  if (root !== temporaryRoot) mkdirSync(root);
  const initialized = spawnSync(realGitPath, ['init', '--quiet', root], {
    encoding: 'utf8',
    shell: false,
  });
  assert.equal(initialized.status, 0, `Git repository initialization failed: ${initialized.stderr}`);
  const taskFolder = createTask(root, {
    folder: options.taskFolder,
    version: options.version,
  });
  const provider = join(root, 'fake-provider');
  const git = options.realGit ? realGitPath : join(root, 'fake-git');
  const providerLog = join(root, 'provider.log');
  const gitLog = join(root, 'git.log');
  const signalLog = join(root, 'signal.log');
  const configPath = join(root, 'provider.json');
  const launcher = join(root, 'joshix-review');
  writeExecutable(provider, fakeProviderSource);
  let providerCommand = provider;
  if (providerFailure === 'missing') providerCommand = join(root, 'missing-provider');
  if (providerFailure === 'eacces') {
    providerCommand = join(root, 'non-executable-provider');
    writeFileSync(providerCommand, fakeProviderSource, { mode: 0o600 });
  }
  if (providerFailure === 'enotdir') {
    const blocker = join(root, 'regular-file');
    writeFileSync(blocker, 'not a directory');
    providerCommand = join(blocker, 'provider');
  }
  if (!options.realGit) writeExecutable(git, fakeGitSource);
  writeFileSync(providerLog, '');
  writeFileSync(gitLog, '');
  writeFileSync(signalLog, '');
  writeFileSync(configPath, JSON.stringify({
    result, rawLine, ordinaryEventCount, stderrBytes, stderrHead, stderrTail,
    stderrText, exitCode,
  }));

  const configured = readFileSync(launcherSource, 'utf8').replace(
    'const INSTALLED_EXECUTABLES = null;',
    `const INSTALLED_EXECUTABLES = Object.freeze(${JSON.stringify({
      node: process.execPath,
      claude: options.providerViaNode
        ? { command: process.execPath, prefixArgs: [providerCommand] }
        : { command: providerCommand, prefixArgs: [] },
      codex: options.providerViaNode
        ? { command: process.execPath, prefixArgs: [providerCommand] }
        : { command: providerCommand, prefixArgs: [] },
      git,
    })});`,
  );
  assert.notEqual(configured, readFileSync(launcherSource, 'utf8'), 'launcher exposes the installer replacement point');
  writeExecutable(launcher, configured);

  const environment = {
    ...process.env,
    FAKE_PROVIDER_CONFIG: configPath,
    FAKE_PROVIDER_LOG: providerLog,
    FAKE_PROVIDER_SIGNAL_LOG: signalLog,
    FAKE_GIT_LOG: gitLog,
    FAKE_GIT_OUTPUT_BYTES: String(gitOutputBytes ?? 0),
    GIT_DIR: '/tmp/hostile-git-dir',
    GIT_WORK_TREE: '/tmp/hostile-work-tree',
    GIT_INDEX_FILE: '/tmp/hostile-index',
    GIT_CONFIG_COUNT: '99',
    NODE_OPTIONS: '--trace-warnings',
  };

  function run(args, options = {}) {
    return spawnSync(process.execPath, [launcher, ...args], {
      cwd: root,
      encoding: 'utf8',
      env: environment,
      ...options,
    });
  }

  function review(providerName = 'claude', extra = []) {
    const processResult = run([
      'review',
      '--provider', providerName,
      '--repo-root', root,
      '--task-folder', taskFolder,
      ...extra,
    ]);
    if (!processResult.stdout.trim()) {
      throw new Error(`bridge produced no result (status ${processResult.status}, signal ${processResult.signal}): ${processResult.stderr}`);
    }
    return { processResult, result: JSON.parse(processResult.stdout) };
  }

  function messages() {
    const db = new DatabaseSync(join(root, taskFolder, 'history.sqlite'), { readOnly: true });
    const rows = db.prepare('SELECT id, speaker, content FROM messages ORDER BY id').all()
      .map((row) => ({ ...row }));
    db.close();
    return rows;
  }

  return {
    root,
    taskFolder,
    launcher,
    provider,
    git,
    environment,
    configPath,
    providerLog,
    gitLog,
    signalLog,
    run,
    review,
    messages,
    providerCalls: () => readJsonLines(providerLog),
    gitCalls: () => readJsonLines(gitLog),
  };
}

test('a successful review spawns once, appends once, and returns the history id', () => {
  const fixture = createFixture();
  const { processResult, result } = fixture.review('claude');

  assert.equal(processResult.status, 0, `${processResult.stderr}\n${processResult.stdout}`);
  assert.doesNotMatch(processResult.stderr, /SQLite is an experimental feature/);
  assert.deepEqual(result, { ok: true, historyId: 1, review: approvedReview });
  assert.equal(fixture.providerCalls().length, 1);
  assert.deepEqual(fixture.messages(), [{
    id: 1,
    speaker: 'Claude Reviewer',
    content: JSON.stringify(approvedReview),
  }]);
});

test('provider prefix arguments are transported literally ahead of provider arguments', () => {
  for (const providerName of ['claude', 'codex']) {
    const fixture = createFixture({ providerViaNode: true });
    const { processResult } = fixture.review(providerName);
    assert.equal(processResult.status, 0, processResult.stderr);
    const args = fixture.providerCalls()[0].args;
    assert.equal(args[0], providerName === 'claude' ? '-p' : 'exec');
  }
});

test('a review preserves and appends to the historical v2 task schema', () => {
  const fixture = createFixture({ version: 2 });
  const { processResult, result } = fixture.review('claude');

  assert.equal(processResult.status, 0, `${processResult.stderr}\n${processResult.stdout}`);
  assert.deepEqual(result, { ok: true, historyId: 1, review: approvedReview });

  const check = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
    'check',
  ]);
  assert.equal(check.status, 0, check.stderr);
  assert.deepEqual(JSON.parse(check.stdout), {
    ok: true,
    integrity: 'ok',
    schemaVersion: 2,
  });

  const db = new DatabaseSync(join(fixture.root, fixture.taskFolder, 'history.sqlite'), {
    readOnly: true,
  });
  const columns = db.prepare('PRAGMA table_info(messages)').all().map((row) => row.name);
  const rows = db.prepare('SELECT id, speaker, content, idempotency_key FROM messages').all();
  db.close();
  assert.deepEqual(columns, VERSION_TWO_COLUMNS);
  assert.deepEqual(rows.map((row) => ({ ...row })), [{
    id: 1,
    speaker: 'Claude Reviewer',
    content: JSON.stringify(approvedReview),
    idempotency_key: null,
  }]);
});

test('a second review is a fresh process with no resume arguments', () => {
  const fixture = createFixture();
  assert.equal(fixture.review('claude').processResult.status, 0);
  assert.equal(fixture.review('claude').processResult.status, 0);

  const calls = fixture.providerCalls();
  assert.equal(calls.length, 2);
  assert.notEqual(calls[0].pid, calls[1].pid);
  for (const call of calls) {
    assert.equal(call.args.some((arg) => /resume|session-id/.test(arg)), false);
  }
  assert.deepEqual(fixture.messages().map(({ id }) => id), [1, 2]);
});

test('a malformed result never retries or appends', () => {
  const fixture = createFixture({ result: undefined, rawLine: '{not-json}' });
  const { processResult, result } = fixture.review('claude');

  assert.equal(processResult.status, 1);
  assert.equal(result.ok, false);
  assert.equal(result.kind, 'malformed-result');
  assert.equal(fixture.providerCalls().length, 1);
  assert.deepEqual(fixture.messages(), []);
});

test('ordinary verbose events and large stderr do not terminate a valid provider', () => {
  const fixture = createFixture({ ordinaryEventCount: 25000, stderrBytes: 2 * 1024 * 1024 });
  const { processResult, result } = fixture.review('claude');

  assert.equal(processResult.status, 0, processResult.stderr);
  assert.equal(result.ok, true);
  assert.equal(readFileSync(fixture.signalLog, 'utf8'), '');
  assert.equal(fixture.providerCalls().length, 1);
});

test('a failing provider returns only the rolling 16 KiB diagnostic tail', () => {
  const fixture = createFixture({
    result: undefined,
    exitCode: 3,
    stderrHead: 'DIAGNOSTIC-HEAD\n',
    stderrBytes: 2 * 1024 * 1024,
    stderrTail: '\nDIAGNOSTIC-TAIL',
  });
  const { processResult, result } = fixture.review('claude');

  assert.equal(processResult.status, 1);
  assert.equal(result.kind, 'provider-exit');
  assert.equal(result.exitCode, 3);
  assert.equal(Buffer.byteLength(result.message, 'utf8') <= 16 * 1024, true);
  assert.doesNotMatch(result.message, /DIAGNOSTIC-HEAD/);
  assert.match(result.message, /DIAGNOSTIC-TAIL$/);
  assert.equal(fixture.providerCalls().length, 1);
  assert.deepEqual(fixture.messages(), []);
});

test('only an oversized completed review is rejected after normal provider exit', () => {
  const huge = {
    status: 'issues',
    findings: [{
      title: 'large',
      severity: 'important',
      evidence: 'x'.repeat(512 * 1024),
      recommendation: 'condense explicitly',
    }],
  };
  const fixture = createFixture({ result: huge });
  const { processResult, result } = fixture.review('claude');

  assert.equal(processResult.status, 1);
  assert.equal(result.kind, 'oversized-result');
  assert.equal(readFileSync(fixture.signalLog, 'utf8'), '');
  assert.deepEqual(fixture.messages(), []);
});

test('history append failure returns the valid review without claiming persistence', () => {
  const fixture = createFixture();
  const db = new DatabaseSync(join(fixture.root, fixture.taskFolder, 'history.sqlite'));
  db.exec(`
    CREATE TRIGGER reject_review BEFORE INSERT ON messages
    BEGIN SELECT RAISE(ABORT, 'fixture rejects append'); END;
  `);
  db.close();

  const { processResult, result } = fixture.review('claude');

  assert.equal(processResult.status, 1);
  assert.equal(result.kind, 'history-append');
  assert.deepEqual(result.review, approvedReview);
  assert.deepEqual(fixture.messages(), []);
});

test('prompt advertises every complete task-read and git-read form exactly once', () => {
  const fixture = createFixture();
  assert.equal(fixture.review('claude').processResult.status, 0);
  const args = fixture.providerCalls()[0].args;
  const prompt = args[args.indexOf('-p') + 1];
  const taskPrefix = `${fixture.launcher} task-read --repo-root ${fixture.root} --task-folder ${fixture.taskFolder}`;
  const gitPrefix = `${fixture.launcher} git-read --repo-root ${fixture.root}`;
  const forms = [
    `Task history: ${taskPrefix} recent [--limit N] [--full]`,
    `Task history: ${taskPrefix} since-id ID [--full]`,
    `Task history: ${taskPrefix} since-time ISO-8601 [--full]`,
    `Task history: ${taskPrefix} search LITERAL`,
    `Task history: ${taskPrefix} get ID [ID...]`,
    `Task history: ${taskPrefix} check`,
    `Git evidence: ${gitPrefix} status`,
    `Git evidence: ${gitPrefix} diff`,
    `Git evidence: ${gitPrefix} diff --cached`,
    `Git evidence: ${gitPrefix} diff -- PATH...`,
    `Git evidence: ${gitPrefix} diff --cached -- PATH...`,
    `Git evidence: ${gitPrefix} diff REVISION`,
    `Git evidence: ${gitPrefix} diff REVISION -- PATH...`,
    `Git evidence: ${gitPrefix} log`,
    `Git evidence: ${gitPrefix} show REVISION [-- PATH...]`,
  ];
  for (const form of forms) {
    assert.equal(prompt.split('\n').filter((line) => line === form).length, 1, form);
  }
});

test('Claude and Codex profiles are fresh, restricted, and read-only', () => {
  const claude = createFixture();
  assert.equal(claude.review('claude').processResult.status, 0);
  const claudeArgs = claude.providerCalls()[0].args;
  assert.deepEqual(claudeArgs.slice(0, 2), ['-p', claudeArgs[1]]);
  for (const token of [
    '--restricted', '--tools', 'Read,Grep,Glob,Bash', '--allowedTools',
    '--disallowedTools', 'Write,Edit,MultiEdit,NotebookEdit,Task,Agent',
    '--permission-mode', 'dontAsk', '--permission-prompts', 'none',
    '--no-session-persistence', '--verbose', '--output-format', 'stream-json', '--json-schema',
  ]) assert.equal(claudeArgs.includes(token), true, token);

  const codex = createFixture();
  assert.equal(codex.review('codex').processResult.status, 0);
  const codexArgs = codex.providerCalls()[0].args;
  assert.deepEqual(codexArgs.slice(0, 9), [
    'exec', '--ignore-user-config', '--ephemeral', '--ignore-rules',
    '--sandbox', 'read-only', '--cd', codex.root, '--json',
  ]);
  assert.equal(codexArgs.includes('--output-schema'), true);
  assert.equal(codexArgs.includes('--output-last-message'), true);
});

test('Claude Bash permissions end repository and task paths at command tokens', () => {
  const fixture = createFixture();
  assert.equal(fixture.review('claude').processResult.status, 0);
  const args = fixture.providerCalls()[0].args;
  const allowed = args[args.indexOf('--allowedTools') + 1].split(',');
  const taskPrefix = `${fixture.launcher} task-read --repo-root ${fixture.root} --task-folder ${fixture.taskFolder}`;
  const gitPrefix = `${fixture.launcher} git-read --repo-root ${fixture.root}`;
  assert.deepEqual(allowed, [
    'Read',
    'Grep',
    'Glob',
    `Bash(${taskPrefix} recent:*)`,
    `Bash(${taskPrefix} since-id:*)`,
    `Bash(${taskPrefix} since-time:*)`,
    `Bash(${taskPrefix} search:*)`,
    `Bash(${taskPrefix} get:*)`,
    `Bash(${taskPrefix} check)`,
    `Bash(${gitPrefix} status)`,
    `Bash(${gitPrefix} diff:*)`,
    `Bash(${gitPrefix} log)`,
    `Bash(${gitPrefix} show:*)`,
  ]);
});

test('both providers receive a flat schema accepted by their structured-output APIs', () => {
  for (const providerName of ['claude', 'codex']) {
    const fixture = createFixture();
    const { processResult, result } = fixture.review(providerName);
    assert.equal(
      processResult.status,
      0,
      `${providerName}: ${processResult.stderr}\n${processResult.stdout}`,
    );
    assert.equal(result.ok, true);
  }
});

test('provider environment removes inherited execution and Git redirection state', () => {
  const fixture = createFixture();
  assert.equal(fixture.review('codex').processResult.status, 0);
  const gitEnvironment = fixture.providerCalls()[0].git;
  assert.deepEqual(gitEnvironment, {
    GIT_OPTIONAL_LOCKS: '0',
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_TERMINAL_PROMPT: '0',
    GIT_CONFIG_COUNT: '2',
    GIT_CONFIG_KEY_0: 'core.fsmonitor',
    GIT_CONFIG_VALUE_0: 'false',
    GIT_CONFIG_KEY_1: 'core.hooksPath',
    GIT_CONFIG_VALUE_1: '/dev/null',
  });
});

test('git-read rejects write- and execution-capable arguments before spawning git', () => {
  const fixture = createFixture();
  for (const args of [
    ['diff', '--output=/tmp/leak'],
    ['diff', '-c', 'diff.external=/tmp/run'],
    ['show', '--textconv', 'HEAD'],
    ['show', 'HEAD', '--', '../outside'],
    ['status', ';', 'touch', '/tmp/leak'],
    ['diff', '--', '/tmp/outside'],
    ['diff', '--', 'line\nbreak'],
  ]) {
    const result = fixture.run([
      'git-read', '--repo-root', fixture.root, ...args,
    ]);
    assert.notEqual(result.status, 0, args.join(' '));
  }
  assert.equal(fixture.gitCalls().length, 0);
});

test('git-read translates only the fixed safe grammar', () => {
  const fixture = createFixture();
  const forms = [
    ['status'],
    ['diff'],
    ['diff', '--cached'],
    ['diff', '--', 'src/a.js'],
    ['diff', '--cached', '--', 'src/a.js'],
    ['diff', 'HEAD^'],
    ['diff', 'HEAD^', '--', 'src/a.js'],
    ['log'],
    ['show', 'HEAD', '--', 'src/a.js'],
  ];
  for (const form of forms) {
    const result = fixture.run(['git-read', '--repo-root', fixture.root, ...form]);
    assert.equal(result.status, 0, `${form.join(' ')}: ${result.stderr}`);
  }
  const calls = fixture.gitCalls();
  assert.equal(calls.length, forms.length);
  for (const call of calls) {
    assert.deepEqual(call.args.slice(0, 11), [
      '--no-pager',
      '-c', 'color.ui=false',
      '-c', 'core.pager=cat',
      '-c', 'core.fsmonitor=false',
      '-c', 'core.hooksPath=/dev/null',
      '-c', 'diff.external=',
    ]);
  }
});

test('git-read streams output beyond Node spawnSync default buffering', () => {
  const outputBytes = (1024 * 1024) + 17;
  const fixture = createFixture({ gitOutputBytes: outputBytes });
  const result = fixture.run([
    'git-read', '--repo-root', fixture.root, 'diff',
  ], { maxBuffer: 2 * 1024 * 1024 });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(Buffer.byteLength(result.stdout), outputBytes);
});

test('git-read receives the same sanitized Git environment as providers', () => {
  const fixture = createFixture();
  const result = fixture.run(['git-read', '--repo-root', fixture.root, 'status']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(fixture.gitCalls()[0].git, {
    GIT_OPTIONAL_LOCKS: '0',
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_TERMINAL_PROMPT: '0',
    GIT_CONFIG_COUNT: '2',
    GIT_CONFIG_KEY_0: 'core.fsmonitor',
    GIT_CONFIG_VALUE_0: 'false',
    GIT_CONFIG_KEY_1: 'core.hooksPath',
    GIT_CONFIG_VALUE_1: '/dev/null',
  });
});

test('real git-read disables repository helpers and leaves the index untouched', () => {
  const fixture = createFixture({ realGit: true });
  const runGit = (args) => {
    const result = spawnSync(realGitPath, args, {
      cwd: fixture.root,
      encoding: 'utf8',
      shell: false,
    });
    assert.equal(result.status, 0, `${args.join(' ')}\n${result.stderr}`);
  };

  writeFileSync(join(fixture.root, '.gitattributes'), [
    'external.txt diff=external',
    'textconv.txt diff=textual',
    '',
  ].join('\n'));
  writeFileSync(join(fixture.root, 'external.txt'), 'external before\n');
  writeFileSync(join(fixture.root, 'textconv.txt'), 'textconv before\n');
  runGit(['add', '.gitattributes', 'external.txt', 'textconv.txt']);
  runGit(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '--quiet', '-m', 'fixture']);

  const marker = join(fixture.root, 'git-helper-ran');
  const helper = join(fixture.root, 'git-helper');
  const helperSource = `#!/bin/sh\nprintf invoked >> ${marker}\nexit 0\n`;
  writeExecutable(helper, helperSource);
  const hooks = join(fixture.root, 'hooks');
  mkdirSync(hooks);
  writeExecutable(join(hooks, 'post-index-change'), helperSource);
  runGit(['config', 'core.fsmonitor', helper]);
  runGit(['config', 'core.hooksPath', hooks]);
  runGit(['config', 'diff.external.command', helper]);
  runGit(['config', 'diff.textual.textconv', helper]);

  writeFileSync(join(fixture.root, 'external.txt'), 'external after\n');
  writeFileSync(join(fixture.root, 'textconv.txt'), 'textconv after\n');
  const index = join(fixture.root, '.git/index');
  const beforeBytes = readFileSync(index);
  const beforeMtime = statSync(index, { bigint: true }).mtimeNs;

  for (const args of [
    ['git-read', '--repo-root', fixture.root, 'status'],
    ['git-read', '--repo-root', fixture.root, 'diff', '--', 'external.txt', 'textconv.txt'],
    ['git-read', '--repo-root', fixture.root, 'show', 'HEAD', '--', 'external.txt', 'textconv.txt'],
  ]) {
    const result = fixture.run(args);
    assert.equal(result.status, 0, `${args.join(' ')}\n${result.stderr}`);
  }

  assert.equal(existsSync(marker), false);
  assert.deepEqual(readFileSync(index), beforeBytes);
  assert.equal(statSync(index, { bigint: true }).mtimeNs, beforeMtime);
});

test('task-read is confined to the exact repository task root and has no append operation', () => {
  const fixture = createFixture();
  const historyPath = join(fixture.root, fixture.taskFolder, 'history.sqlite');
  const longContent = `${'x'.repeat(260)} unique-search-value`;
  const db = new DatabaseSync(historyPath);
  const inserted = db.prepare(
    'INSERT INTO messages (created_at, speaker, content) VALUES (?, ?, ?)',
  ).run('2000-01-01T00:00:00.000Z', 'User', longContent);
  db.close();
  const firstId = Number(inserted.lastInsertRowid);
  const review = fixture.review('claude');
  assert.equal(review.processResult.status, 0);
  const reviewId = review.result.historyId;

  const recentPreview = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
    'recent', '--limit', '2',
  ]);
  assert.equal(recentPreview.status, 0, recentPreview.stderr);
  const previewRows = JSON.parse(recentPreview.stdout);
  assert.deepEqual(previewRows.map((row) => row.id), [firstId, reviewId]);
  assert.equal(previewRows[0].preview, `${'x'.repeat(240)}…`);

  const recentFull = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
    'recent', '--limit', '2', '--full',
  ]);
  assert.equal(recentFull.status, 0, recentFull.stderr);
  assert.equal(JSON.parse(recentFull.stdout)[0].content, longContent);

  const sinceId = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
    'since-id', String(firstId), '--full',
  ]);
  assert.deepEqual(JSON.parse(sinceId.stdout).map((row) => row.id), [reviewId]);

  const sinceTime = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
    'since-time', '2020-01-01T00:00:00.000Z', '--full',
  ]);
  assert.deepEqual(JSON.parse(sinceTime.stdout).map((row) => row.id), [reviewId]);

  const search = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
    'search', 'UNIQUE-SEARCH-VALUE',
  ]);
  assert.deepEqual(JSON.parse(search.stdout).map((row) => row.id), [firstId]);

  const get = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
    'get', String(reviewId), String(firstId),
  ]);
  const getRows = JSON.parse(get.stdout);
  assert.deepEqual(getRows.map((row) => row.id), [firstId, reviewId]);
  assert.equal(getRows[0].content, longContent);
  assert.deepEqual(JSON.parse(getRows[1].content), approvedReview);

  const check = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
    'check',
  ]);
  assert.deepEqual(JSON.parse(check.stdout), {
    ok: true,
    integrity: 'ok',
    schemaVersion: 1,
  });

  for (const tail of [
    ['append'],
    ['recent', '--limit', '0'],
  ]) {
    const result = fixture.run([
      'task-read', '--repo-root', fixture.root, '--task-folder', fixture.taskFolder,
      ...tail,
    ]);
    assert.notEqual(result.status, 0);
  }
  const escaped = fixture.run([
    'task-read', '--repo-root', fixture.root, '--task-folder', '../outside', 'check',
  ]);
  assert.notEqual(escaped.status, 0);
});

test('invalid review arguments and history failures happen before provider spawn', () => {
  const fixture = createFixture();
  const unknown = fixture.run([
    'review', '--provider', 'claude', '--repo-root', fixture.root,
    '--task-folder', fixture.taskFolder, '--prompt-file', '/tmp/nope',
  ]);
  assert.equal(unknown.status, 1);
  assert.equal(JSON.parse(unknown.stdout).kind, 'invalid-request');

  const missing = fixture.run([
    'review', '--provider', 'claude', '--repo-root', fixture.root,
    '--task-folder', '.joshix/tasks/missing',
  ]);
  assert.equal(missing.status, 1);
  assert.equal(JSON.parse(missing.stdout).kind, 'history-read');
  assert.equal(fixture.providerCalls().length, 0);
});

test('review rejects whitespace or commas in repository and task paths before spawning', () => {
  for (const repoName of ['repo with space', 'repo,with-comma']) {
    const fixture = createFixture({ repoName });
    const { processResult, result } = fixture.review('claude');
    assert.equal(processResult.status, 1, repoName);
    assert.equal(result.kind, 'invalid-request', repoName);
    assert.match(result.message, /whitespace or commas/);
    assert.equal(fixture.providerCalls().length, 0);
  }

  for (const taskFolder of [
    '.joshix/tasks/review with space',
    '.joshix/tasks/review,with-comma',
  ]) {
    const fixture = createFixture({ taskFolder });
    const { processResult, result } = fixture.review('claude');
    assert.equal(processResult.status, 1, taskFolder);
    assert.equal(result.kind, 'invalid-request', taskFolder);
    assert.match(result.message, /whitespace or commas/);
    assert.equal(fixture.providerCalls().length, 0);
  }
});

test('review rejects a moved launcher path containing whitespace or commas before spawning', () => {
  const fixture = createFixture();
  for (const name of ['moved launcher', 'moved,launcher']) {
    const launcher = join(fixture.root, name);
    copyFileSync(fixture.launcher, launcher);
    chmodSync(launcher, 0o700);
    const result = spawnSync(process.execPath, [
      launcher,
      'review', '--provider', 'claude', '--repo-root', fixture.root,
      '--task-folder', fixture.taskFolder,
    ], {
      cwd: fixture.root,
      encoding: 'utf8',
      env: fixture.environment,
    });
    assert.equal(result.status, 1, name);
    const response = JSON.parse(result.stdout);
    assert.equal(response.kind, 'invalid-request');
    assert.match(response.message, /installed launcher path.*whitespace or commas/);
  }
  assert.equal(fixture.providerCalls().length, 0);
});

test('provider failures are direct and never relaunch', () => {
  const auth = createFixture({
    result: undefined,
    exitCode: 7,
    stderrText: 'authentication required',
  });
  const authResult = auth.review('claude');
  assert.equal(authResult.result.kind, 'authentication');
  assert.equal(authResult.result.exitCode, 7);
  assert.equal(auth.providerCalls().length, 1);

  const nonzero = createFixture({ result: undefined, exitCode: 3 });
  const nonzeroResult = nonzero.review('claude');
  assert.deepEqual(nonzeroResult.result, {
    ok: false,
    kind: 'provider-exit',
    message: 'provider exited 3',
    exitCode: 3,
  });
  assert.equal(nonzero.providerCalls().length, 1);
  assert.deepEqual(nonzero.messages(), []);

  const missing = createFixture({ result: undefined });
  const missingResult = missing.review('codex');
  assert.equal(missingResult.result.kind, 'missing-result');
  assert.equal(missing.providerCalls().length, 1);
});

test('an externally signal-killed provider reports the signal accurately', async () => {
  const fixture = createFixture();
  writeFileSync(fixture.configPath, JSON.stringify({ waitForSignal: true }));

  const child = spawn(process.execPath, [
    fixture.launcher,
    'review', '--provider', 'claude', '--repo-root', fixture.root,
    '--task-folder', fixture.taskFolder,
  ], {
    cwd: fixture.root,
    env: fixture.environment,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const closed = new Promise((resolvePromise) => child.on('close', resolvePromise));

  for (let count = 0; count < 100 && fixture.providerCalls().length === 0; count += 1) {
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
  }
  const providerPid = fixture.providerCalls()[0]?.pid;
  assert.equal(Number.isInteger(providerPid), true, 'provider did not start');
  process.kill(providerPid, 'SIGKILL');
  const status = await closed;

  assert.equal(status, 1, stderr);
  assert.deepEqual(JSON.parse(stdout), {
    ok: false,
    kind: 'provider-exit',
    message: 'provider terminated by SIGKILL',
  });
  assert.deepEqual(fixture.messages(), []);
  assert.equal(fixture.providerCalls().length, 1);
});

test('spawn failures have stable unavailable and internal results without append', () => {
  for (const providerFailure of ['missing', 'eacces']) {
    const fixture = createFixture({ providerFailure });
    const { processResult, result } = fixture.review('claude');
    assert.equal(processResult.status, 1, providerFailure);
    assert.equal(result.kind, 'unavailable', providerFailure);
    assert.equal(fixture.providerCalls().length, 0);
    assert.deepEqual(fixture.messages(), []);
  }

  const internal = createFixture({ providerFailure: 'enotdir' });
  const internalResult = internal.review('claude');
  assert.equal(internalResult.processResult.status, 1);
  assert.equal(internalResult.result.kind, 'internal');
  assert.equal(internal.providerCalls().length, 0);
  assert.deepEqual(internal.messages(), []);
});

test('unexpected review setup failures still return one direct JSON result', () => {
  const fixture = createFixture();
  const processResult = fixture.run([
    'review', '--provider', 'claude', '--repo-root', fixture.root,
    '--task-folder', fixture.taskFolder,
  ], {
    env: { ...fixture.environment, TMPDIR: join(fixture.root, 'missing-tmp') },
  });

  assert.equal(processResult.status, 1);
  const result = JSON.parse(processResult.stdout);
  assert.equal(result.ok, false);
  assert.equal(result.kind, 'internal');
  assert.match(result.message, /ENOENT/);
  assert.equal(processResult.stdout.trim().split('\n').length, 1);
  assert.equal(fixture.providerCalls().length, 0);
  assert.deepEqual(fixture.messages(), []);
});

test('explicit SIGINT is forwarded and returns cancellation without append', async () => {
  const fixture = createFixture();
  writeFileSync(fixture.configPath, JSON.stringify({ waitForSignal: true }));

  const child = spawn(process.execPath, [
    fixture.launcher,
    'review', '--provider', 'claude', '--repo-root', fixture.root,
    '--task-folder', fixture.taskFolder,
  ], {
    cwd: fixture.root,
    env: fixture.environment,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });

  for (let count = 0; count < 100 && fixture.providerCalls().length === 0; count += 1) {
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
  }
  child.kill('SIGINT');
  const status = await new Promise((resolvePromise) => child.on('close', resolvePromise));

  assert.equal(status, 130, stderr);
  assert.deepEqual(JSON.parse(stdout), { ok: false, kind: 'cancelled', signal: 'SIGINT' });
  assert.equal(readFileSync(fixture.signalLog, 'utf8').trim(), 'SIGINT');
  assert.deepEqual(fixture.messages(), []);
  assert.equal(fixture.providerCalls().length, 1);
});

test('explicit SIGTERM is forwarded and returns cancellation without append', async () => {
  const fixture = createFixture();
  writeFileSync(fixture.configPath, JSON.stringify({ waitForSignal: true }));

  const child = spawn(process.execPath, [
    fixture.launcher,
    'review', '--provider', 'claude', '--repo-root', fixture.root,
    '--task-folder', fixture.taskFolder,
  ], {
    cwd: fixture.root,
    env: fixture.environment,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });

  for (let count = 0; count < 100 && fixture.providerCalls().length === 0; count += 1) {
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
  }
  child.kill('SIGTERM');
  const status = await new Promise((resolvePromise) => child.on('close', resolvePromise));

  assert.equal(status, 143, stderr);
  assert.deepEqual(JSON.parse(stdout), { ok: false, kind: 'cancelled', signal: 'SIGTERM' });
  assert.equal(readFileSync(fixture.signalLog, 'utf8').trim(), 'SIGTERM');
  assert.deepEqual(fixture.messages(), []);
  assert.equal(fixture.providerCalls().length, 1);
});

test('installer produces one configured owner-only executable', () => {
  const fixture = installFixture();
  assert.equal(fixture.result.status, 0, fixture.result.stderr);
  assert.deepEqual(walkFiles(fixture.installRoot), ['bin/joshix-review']);
  const launcher = join(fixture.installRoot, 'bin/joshix-review');
  assert.equal(statSync(launcher).mode & 0o777, 0o700);
  const installed = readFileSync(launcher, 'utf8');
  for (const path of [
    realpathSync(process.execPath),
    realpathSync(join(fixture.fakeBin, 'claude')),
    realpathSync(join(fixture.fakeBin, 'codex')),
    realpathSync(join(fixture.fakeBin, 'git')),
  ]) assert.equal(installed.includes(path), true, path);
  assert.deepEqual(embeddedExecutables(launcher), {
    node: realpathSync(process.execPath),
    claude: {
      command: realpathSync(process.execPath),
      prefixArgs: [realpathSync(join(fixture.fakeBin, 'claude'))],
    },
    codex: {
      command: realpathSync(process.execPath),
      prefixArgs: [realpathSync(join(fixture.fakeBin, 'codex'))],
    },
    git: realpathSync(join(fixture.fakeBin, 'git')),
  });
  const output = JSON.parse(fixture.result.stdout);
  assert.match(output.claudePermission, /Bash\(.*\/joshix-review review:\*\)/);
  assert.match(output.codexRule, /pattern = \[".*\/joshix-review", "review"\]/);
});

test('installer keeps a direct provider executable out of the Node prefix branch', () => {
  const fixture = installFixture({ nativeClaude: true });
  assert.equal(fixture.result.status, 0, fixture.result.stderr);
  const installed = embeddedExecutables(join(fixture.installRoot, 'bin/joshix-review'));
  assert.deepEqual(installed.claude, {
    command: realpathSync(join(fixture.fakeBin, 'claude')),
    prefixArgs: [],
  });
});

test('Node shebang paths reject env -S metacharacters', () => {
  for (const character of [' ', '\t', '$', '\\', '"', "'", '#']) {
    assert.throws(
      () => requireSafeNodeShebangPath(`/safe/node${character}path`),
      /whitespace or env -S metacharacters/,
      JSON.stringify(character),
    );
  }
  assert.doesNotThrow(() => requireSafeNodeShebangPath('/Users/josh/.volta/node-24/bin/node'));
});

test('installed launcher strips Node injection variables before its interpreter starts', () => {
  const fixture = installFixture();
  assert.equal(fixture.result.status, 0, fixture.result.stderr);
  const launcher = join(fixture.installRoot, 'bin/joshix-review');
  const sentinel = join(fixture.root, 'node-options-ran');
  const injection = join(fixture.root, 'node-options-injection.cjs');
  writeFileSync(injection, [
    "const { writeFileSync } = require('node:fs');",
    `writeFileSync(${JSON.stringify(sentinel)}, 'ran');`,
    '',
  ].join('\n'));

  const result = spawnSync(launcher, ['unknown-operation'], {
    cwd: fixture.root,
    encoding: 'utf8',
    env: {
      ...process.env,
      NODE_OPTIONS: `--require=${injection}`,
      NODE_PATH: fixture.root,
    },
    shell: false,
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /unknown operation/);
  assert.equal(existsSync(sentinel), false);
});

test('installer removes only the exact obsolete generated layout on upgrade', () => {
  const fixture = installFixture({ legacy: true, unknownSibling: true });
  assert.equal(fixture.result.status, 0, fixture.result.stderr);
  assert.deepEqual(walkFiles(fixture.installRoot), ['bin/joshix-review', 'keep-me.txt']);
  assert.equal(readFileSync(join(fixture.installRoot, 'keep-me.txt'), 'utf8'), 'owner data');
});

test('installer embeds dollar sequences in executable paths literally', () => {
  const fixture = installFixture({ dollarPath: true });
  assert.equal(fixture.result.status, 0, fixture.result.stderr);
  const installed = readFileSync(join(fixture.installRoot, 'bin/joshix-review'), 'utf8');
  for (const name of ['claude', 'codex', 'git']) {
    assert.equal(installed.includes(realpathSync(join(fixture.fakeBin, name))), true, name);
  }
});

test('installer rejects launcher paths containing whitespace or commas', () => {
  for (const installDirName of ['installed reviewer', 'installed,reviewer']) {
    const fixture = installFixture({ installDirName });
    assert.equal(fixture.result.status, 1, installDirName);
    assert.match(fixture.result.stderr, /launcher path cannot contain whitespace or commas/);
    assert.equal(existsSync(join(fixture.installRoot, 'bin/joshix-review')), false);
  }
});
