import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const installer = join(root, 'skills/requesting-code-review/scripts/install-reviewer-host.mjs');
const launcherSource = join(root, 'skills/requesting-code-review/scripts/reviewer-host-launcher.mjs');
const temporaryDirectories = [];
const SESSION = '01990f47-3d62-7b22-8f5a-123456789abc';

function temporaryDirectory() {
  const directory = mkdtempSync(join(tmpdir(), 'joshix-reviewer-host-'));
  temporaryDirectories.push(directory);
  return directory;
}

after(() => {
  for (const directory of temporaryDirectories) rmSync(directory, { recursive: true, force: true });
});

function hash(file) {
  return createHash('sha256').update(readFileSync(file)).digest('hex');
}

function fakeProvider(file, provider, captureFile, { envShebang = false, auth = 'available' } = {}) {
  writeFileSync(file, `${envShebang ? '#!/usr/bin/env node' : `#!${process.execPath}`}
import { appendFileSync, writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
if ((${JSON.stringify(provider)} === 'claude' && args.join(' ') === 'auth status') ||
    (${JSON.stringify(provider)} === 'codex' && args.join(' ') === 'login status')) {
  if (${JSON.stringify(auth)} === 'available') {
    process.stdout.write('logged in');
    process.exit(0);
  }
  process.stderr.write(${JSON.stringify(auth === 'unavailable' ? 'Authentication required.' : 'status command unsupported')});
  process.exit(2);
}
appendFileSync(${JSON.stringify(captureFile)}, JSON.stringify({
  provider: ${JSON.stringify(provider)}, args,
  nodeOptions: process.env.NODE_OPTIONS ?? null,
  nodePath: process.env.NODE_PATH ?? null,
  claudeOverride: process.env.JOSHIX_REVIEWER_CLAUDE_BIN ?? null,
  codexOverride: process.env.JOSHIX_REVIEWER_CODEX_BIN ?? null,
  codexSandbox: process.env.CODEX_SANDBOX ?? null,
  codexSandboxNetworkDisabled: process.env.CODEX_SANDBOX_NETWORK_DISABLED ?? null,
}) + '\\n');
const review = { status: 'approved', findings: [] };
if (${JSON.stringify(provider)} === 'claude') {
  const resume = args.indexOf('--resume');
  const id = resume >= 0 ? args[resume + 1] : args[args.indexOf('--session-id') + 1];
  process.stdout.write(JSON.stringify({ type: 'system', subtype: 'init', session_id: id, model: 'fake-claude' }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'result', session_id: id, structured_output: review }) + '\\n');
} else {
  const resume = args.indexOf('resume');
  const id = resume >= 0 ? args.at(-2) : ${JSON.stringify(SESSION)};
  writeFileSync(args[args.indexOf('--output-last-message') + 1], JSON.stringify(review));
  process.stdout.write(JSON.stringify({ type: 'thread.started', thread_id: id }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
}
`);
  chmodSync(file, 0o755);
}

function fixture({ binName = 'provider-bin', envShebang = false, auth = {} } = {}) {
  const base = realpathSync(temporaryDirectory());
  const repo = join(base, 'repo');
  const trusted = join(base, 'trusted-host');
  const bin = join(base, binName);
  mkdirSync(repo, { recursive: true });
  mkdirSync(bin, { recursive: true });
  execFileSync('git', ['init', '--quiet'], { cwd: repo });
  const promptFile = join(repo, 'review prompt.md');
  writeFileSync(promptFile, 'Review literally: $(touch SHOULD_NOT_EXIST); `uname`; *;\nnext line');
  const schema = join(root, 'skills/requesting-code-review/review-result.schema.json');
  const capture = join(base, 'provider-calls.jsonl');
  fakeProvider(join(bin, 'claude'), 'claude', capture, { envShebang, auth: auth.claude ?? 'available' });
  fakeProvider(join(bin, 'codex'), 'codex', capture, { envShebang, auth: auth.codex ?? 'available' });
  return { base, repo, trusted, bin, promptFile, schema, capture };
}

function install(fix, extraEnv = {}) {
  const result = spawnSync(process.execPath, [installer, '--install-dir', fix.trusted], {
    cwd: fix.repo,
    encoding: 'utf8',
    env: {
      ...process.env,
      HOME: fix.base,
      PATH: `${fix.bin}:${process.env.PATH ?? ''}`,
      ...extraEnv,
    },
    shell: false,
  });
  return { result, output: result.stdout ? JSON.parse(result.stdout) : null };
}

function reviewArgs(fix, overrides = {}) {
  return [
    'review',
    '--provider', overrides.provider ?? 'claude',
    '--repo-root', overrides.repoRoot ?? fix.repo,
    '--prompt-file', overrides.promptFile ?? fix.promptFile,
    '--result-schema', overrides.resultSchema ?? 'review-result-v1',
    '--timeout-ms', String(overrides.timeoutMs ?? 1_200_000),
    '--max-events', String(overrides.maxEvents ?? 20_000),
    '--max-output-bytes', String(overrides.maxOutputBytes ?? 8_388_608),
    '--max-review-bytes', String(overrides.maxReviewBytes ?? 524_288),
    ...(overrides.sessionId ? ['--session-id', overrides.sessionId] : []),
  ];
}

function launch(fix, args = reviewArgs(fix), env = {}) {
  const executable = join(fix.trusted, 'bin/joshix-review');
  const environment = { ...process.env };
  delete environment.CODEX_SANDBOX;
  delete environment.CODEX_SANDBOX_NETWORK_DISABLED;
  const result = spawnSync(executable, args, {
    cwd: fix.repo,
    encoding: 'utf8',
    env: { ...environment, ...env },
    shell: false,
  });
  return { result, envelope: result.stdout ? JSON.parse(result.stdout) : null };
}

test('setup installs a stable credential-free launcher and prints exact permission entries', () => {
  const fix = fixture();
  const first = install(fix);
  assert.equal(first.result.status, 0, first.result.stderr);
  assert.equal(first.output.installRoot, fix.trusted);
  assert.equal(first.output.auth.claude, 'available');
  assert.equal(first.output.auth.codex, 'available');
  assert.equal(first.output.claudePermission, `Bash(${fix.trusted}/bin/joshix-review review:*)`);
  assert.match(first.output.codexRule, new RegExp(`pattern = \\["${fix.trusted}/bin/joshix-review", "review"\\]`));
  assert.match(first.output.codexRule, /decision = "allow"/);
  assert.match(first.output.codexRule, /not_match = \[".*joshix-review setup"\]/);

  const configPath = join(fix.trusted, 'config.json');
  const manifest = JSON.parse(readFileSync(configPath, 'utf8'));
  assert.equal(lstatSync(configPath).mode & 0o777, 0o600);
  assert.equal(lstatSync(manifest.launcher.path).mode & 0o022, 0);
  assert.equal(manifest.launcher.sha256, hash(manifest.launcher.path));
  assert.equal(manifest.runner.sha256, hash(manifest.runner.path));
  assert.equal(manifest.reviewSchema.sha256, hash(manifest.reviewSchema.path));
  assert.equal(manifest.taskContextHelper.sha256, hash(manifest.taskContextHelper.path));
  assert.equal(lstatSync(manifest.taskContextHelper.path).mode & 0o777, 0o500);
  assert.equal(
    readFileSync(manifest.taskContextHelper.path, 'utf8').split('\n')[0],
    `#!/usr/bin/env -S -u NODE_OPTIONS -u NODE_PATH ${manifest.node}`,
  );
  const helperHelp = spawnSync(manifest.taskContextHelper.path, ['--help'], { encoding: 'utf8', shell: false });
  assert.equal(helperHelp.status, 0, helperHelp.stderr);
  assert.match(helperHelp.stdout, /Usage: task-context/);
  assert.doesNotMatch(readFileSync(configPath, 'utf8'), /token|secret|password|oauth/i);

  const stablePath = manifest.launcher.path;
  const second = install(fix);
  assert.equal(second.result.status, 0, second.result.stderr);
  assert.equal(JSON.parse(readFileSync(configPath, 'utf8')).launcher.path, stablePath);
});

test('launcher passes literal prompt data and strips provider substitution and Node preload variables', () => {
  const fix = fixture();
  assert.equal(install(fix).result.status, 0);
  const malicious = join(fix.base, 'malicious-provider');
  const marker = join(fix.base, 'marker');
  writeFileSync(malicious, `#!${process.execPath}\nimport { writeFileSync } from 'node:fs'; writeFileSync(${JSON.stringify(marker)}, 'bad');`);
  chmodSync(malicious, 0o755);

  const { result, envelope } = launch(fix, reviewArgs(fix), {
    JOSHIX_REVIEWER_CLAUDE_BIN: malicious,
    JOSHIX_REVIEWER_CODEX_BIN: malicious,
    NODE_PATH: join(fix.base, 'malicious-node-path'),
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(envelope.ok, true);
  assert.equal(envelope.provider, 'claude');
  assert.equal(existsSync(marker), false);
  assert.equal(existsSync(join(fix.repo, 'SHOULD_NOT_EXIST')), false);
  const capture = JSON.parse(readFileSync(fix.capture, 'utf8').trim());
  assert.equal(capture.claudeOverride, null);
  assert.equal(capture.codexOverride, null);
  assert.equal(capture.nodeOptions, null);
  assert.equal(capture.nodePath, null);
  assert.ok(capture.args.includes(readFileSync(fix.promptFile, 'utf8')));
});

test('env-shebang providers use the setup-pinned Node instead of launch-time PATH', () => {
  const fix = fixture({ envShebang: true });
  assert.equal(install(fix).result.status, 0);
  const manifest = JSON.parse(readFileSync(join(fix.trusted, 'config.json'), 'utf8'));
  assert.equal(manifest.providers.claude.interpreter, manifest.node);

  const maliciousBin = join(fix.base, 'malicious-path');
  const maliciousNode = join(maliciousBin, 'node');
  const marker = join(fix.base, 'path-node-marker');
  mkdirSync(maliciousBin);
  writeFileSync(
    maliciousNode,
    `#!${process.execPath}\nimport { writeFileSync } from 'node:fs'; writeFileSync(${JSON.stringify(marker)}, 'bad');`,
  );
  chmodSync(maliciousNode, 0o755);

  const { result, envelope } = launch(fix, reviewArgs(fix), {
    PATH: `${maliciousBin}:${process.env.PATH ?? ''}`,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(envelope.ok, true);
  assert.equal(existsSync(marker), false);
  assert.equal(JSON.parse(readFileSync(fix.capture, 'utf8').trim()).provider, 'claude');
});

test('inherited Codex sandbox markers do not reject a host-capable launcher and are stripped', () => {
  const fix = fixture();
  assert.equal(install(fix).result.status, 0);
  const { result, envelope } = launch(fix, reviewArgs(fix), {
    CODEX_SANDBOX: 'seatbelt',
    CODEX_SANDBOX_NETWORK_DISABLED: '1',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(envelope.ok, true);
  const capture = JSON.parse(readFileSync(fix.capture, 'utf8').trim());
  assert.equal(capture.codexSandbox, null);
  assert.equal(capture.codexSandboxNetworkDisabled, null);
});

test('active host capability failure is classified before any provider starts', () => {
  const fix = fixture();
  assert.equal(install(fix).result.status, 0);
  const configPath = join(fix.trusted, 'config.json');
  chmodSync(configPath, 0o400);
  try {
    const { result, envelope } = launch(fix, reviewArgs(fix), {
      CODEX_SANDBOX: 'seatbelt',
      CODEX_SANDBOX_NETWORK_DISABLED: '1',
    });
    assert.notEqual(result.status, 0);
    assert.equal(envelope.failure.kind, 'sandboxed');
    assert.equal(envelope.diagnostic.stage, 'launcher');
    assert.equal(existsSync(fix.capture), false);
  } finally {
    chmodSync(configPath, 0o600);
  }
});

test('installed shebang clears NODE_OPTIONS before launcher JavaScript starts', () => {
  const fix = fixture();
  assert.equal(install(fix).result.status, 0);
  const marker = join(fix.base, 'preload-marker');
  const preload = join(fix.base, 'preload.cjs');
  writeFileSync(preload, `require('node:fs').writeFileSync(${JSON.stringify(marker)}, 'loaded');`);
  const { result, envelope } = launch(fix, reviewArgs(fix), {
    NODE_OPTIONS: `--require=${preload}`,
    NODE_PATH: fix.base,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(envelope.ok, true);
  assert.equal(existsSync(marker), false);
});

test('launcher rejects malformed operations, paths, sessions, and bounds before provider start', () => {
  const fix = fixture();
  assert.equal(install(fix).result.status, 0);
  const outsidePrompt = join(fix.base, 'outside.md');
  writeFileSync(outsidePrompt, 'outside');
  const promptLink = join(fix.repo, 'prompt-link.md');
  symlinkSync(fix.promptFile, promptLink);
  const invalid = [
    ['setup'],
    [...reviewArgs(fix), '--extra', 'x'],
    reviewArgs(fix).filter((value, index, all) => !(all[index - 1] === '--provider' || value === '--provider')),
    reviewArgs(fix, { provider: 'other' }),
    [...reviewArgs(fix), '--provider', 'claude'],
    reviewArgs(fix, { repoRoot: dirname(fix.repo) }),
    reviewArgs(fix, { promptFile: outsidePrompt }),
    reviewArgs(fix, { promptFile: promptLink }),
    reviewArgs(fix, { resultSchema: 'arbitrary.json' }),
    reviewArgs(fix, { timeoutMs: 0 }),
    reviewArgs(fix, { timeoutMs: 1_200_001 }),
    reviewArgs(fix, { maxEvents: 20_001 }),
    reviewArgs(fix, { maxOutputBytes: 8_388_609 }),
    reviewArgs(fix, { maxReviewBytes: 524_289 }),
    [...reviewArgs(fix), '--session-id', 'not-a-uuid'],
  ];
  for (const args of invalid) {
    const { result, envelope } = launch(fix, args);
    assert.notEqual(result.status, 0, JSON.stringify(args));
    assert.equal(envelope.ok, false);
    assert.equal(envelope.diagnostic.stage, 'launcher');
  }
  assert.equal(existsSync(fix.capture), false);
});

test('launcher fails closed on mutable trusted artifacts and stale provider paths', () => {
  for (const scenario of ['runner-digest', 'config-mode', 'provider-missing', 'provider-symlink']) {
    const fix = fixture();
    assert.equal(install(fix).result.status, 0);
    const configPath = join(fix.trusted, 'config.json');
    const manifest = JSON.parse(readFileSync(configPath, 'utf8'));
    if (scenario === 'runner-digest') {
      chmodSync(manifest.runner.path, 0o600);
      writeFileSync(manifest.runner.path, `${readFileSync(manifest.runner.path, 'utf8')}\n// tampered\n`);
      chmodSync(manifest.runner.path, 0o400);
    }
    if (scenario === 'config-mode') chmodSync(configPath, 0o620);
    if (scenario === 'provider-missing') unlinkSync(manifest.providers.claude.path);
    if (scenario === 'provider-symlink') {
      const moved = `${manifest.providers.claude.path}.real`;
      execFileSync('mv', [manifest.providers.claude.path, moved]);
      symlinkSync(moved, manifest.providers.claude.path);
    }
    const { result, envelope } = launch(fix);
    assert.notEqual(result.status, 0, scenario);
    assert.equal(envelope.ok, false, scenario);
    assert.ok(['launcher', 'configuration-stale'].includes(envelope.failure.kind), scenario);
    assert.equal(existsSync(fix.capture), false, scenario);
  }
});

test('a stale unused provider does not prevent the configured fallback provider', () => {
  const fix = fixture();
  assert.equal(install(fix).result.status, 0);
  const manifest = JSON.parse(readFileSync(join(fix.trusted, 'config.json'), 'utf8'));
  unlinkSync(manifest.providers.claude.path);

  const { result, envelope } = launch(fix, reviewArgs(fix, { provider: 'codex' }));
  assert.equal(result.status, 0, result.stderr);
  assert.equal(envelope.ok, true);
  assert.equal(envelope.provider, 'codex');
});

test('a stale requested provider permits one persistent same-role fallback session', () => {
  const fix = fixture();
  assert.equal(install(fix).result.status, 0);
  const manifest = JSON.parse(readFileSync(join(fix.trusted, 'config.json'), 'utf8'));
  unlinkSync(manifest.providers.claude.path);

  const requested = launch(fix);
  assert.notEqual(requested.result.status, 0);
  assert.equal(requested.envelope.failure.kind, 'configuration-stale');
  assert.equal(existsSync(fix.capture), false);

  const firstFallback = launch(fix, reviewArgs(fix, { provider: 'codex' }));
  assert.equal(firstFallback.result.status, 0, firstFallback.result.stderr);
  assert.equal(firstFallback.envelope.session.mode, 'started');
  const secondFallback = launch(fix, reviewArgs(fix, {
    provider: 'codex',
    sessionId: firstFallback.envelope.session.id,
  }));
  assert.equal(secondFallback.result.status, 0, secondFallback.result.stderr);
  assert.equal(secondFallback.envelope.session.id, firstFallback.envelope.session.id);
  assert.equal(secondFallback.envelope.session.mode, 'resumed');
  const calls = readFileSync(fix.capture, 'utf8').trim().split('\n').map((line) => JSON.parse(line));
  assert.deepEqual(calls.map((call) => call.provider), ['codex', 'codex']);
});

test('provider executables may use whitespace-safe argument-array paths', () => {
  const fix = fixture({ binName: 'provider bin with spaces', envShebang: true });
  const { result, output } = install(fix);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(output.auth.claude, 'available');
  assert.equal(output.auth.codex, 'available');
});

test('setup reports reviewer-config migration and native auth variants without mutating config', () => {
  for (const [configured, expectedState, expectsMigration] of [
    [null, 'absent', false],
    ['auto_review', 'auto_review', false],
    ['guardian_subagent', 'guardian_subagent', true],
  ]) {
    const fix = fixture();
    let configPath = null;
    let original = null;
    if (configured !== null) {
      const configDirectory = join(fix.base, '.codex');
      mkdirSync(configDirectory, { recursive: true });
      configPath = join(configDirectory, 'config.toml');
      original = `approvals_reviewer = ${JSON.stringify(configured)}\nother_setting = true\n`;
      writeFileSync(configPath, original);
    }
    const installed = install(fix);
    assert.equal(installed.result.status, 0, installed.result.stderr);
    assert.equal(installed.output.codexApprovalsReviewer, expectedState);
    assert.equal(Boolean(installed.output.migrationNotice), expectsMigration);
    if (configPath) assert.equal(readFileSync(configPath, 'utf8'), original);
  }

  const unavailable = install(fixture({ auth: { claude: 'unavailable' } }));
  assert.equal(unavailable.result.status, 0, unavailable.result.stderr);
  assert.equal(unavailable.output.auth.claude, 'unavailable');

  const unknown = install(fixture({ auth: { codex: 'unknown' } }));
  assert.equal(unknown.result.status, 0, unknown.result.stderr);
  assert.equal(unknown.output.auth.codex, 'unknown');
});

test('source launcher module exposes the strict parser without executing', async () => {
  const module = await import(`${launcherSource}?test=${Date.now()}`);
  assert.equal(typeof module.parseReviewOperation, 'function');
  assert.equal(module.trustedExecutableOwner(501, 501), true);
  assert.equal(module.trustedExecutableOwner(0, 501), true);
  assert.equal(module.trustedExecutableOwner(502, 501), false);
  assert.throws(() => module.parseReviewOperation(['review', '--provider', 'claude']), /missing/i);
});
