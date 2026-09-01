import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  appendFileSync,
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, dirname, join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { discoverDefaultReviewerBinary } from '../../skills/requesting-code-review/scripts/reviewer-runner.mjs';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const runner = join(repoRoot, 'skills/requesting-code-review/scripts/reviewer-runner.mjs');
const schema = join(repoRoot, 'skills/requesting-code-review/review-result.schema.json');
const taskContextHelper = join(repoRoot, 'skills/task-context/scripts/task-context.mjs');
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const temporaryDirectories = [];

function tempDir() {
  const directory = mkdtempSync(join(tmpdir(), 'joshix-reviewer-runner-'));
  temporaryDirectories.push(directory);
  return directory;
}

after(() => {
  for (const directory of temporaryDirectories) {
    rmSync(directory, { recursive: true, force: true });
  }
});

const fakeProviderSource = `#!/usr/bin/env node
import { existsSync, readFileSync, truncateSync, writeFileSync } from 'node:fs';

const scenario = process.env.JOSHIX_FAKE_SCENARIO;
const stateFile = process.env.JOSHIX_FAKE_STATE;
const argvFile = process.env.JOSHIX_FAKE_ARGV;
const provider = process.env.JOSHIX_FAKE_PROVIDER;
const args = process.argv.slice(2);
const resumeIndex = provider === 'codex' ? args.indexOf('resume') : args.indexOf('--resume');
const resumed = resumeIndex >= 0;
const fixedSession = '01990f47-3d62-7b22-8f5a-123456789abc';
const sessionId = provider === 'claude'
  ? args[resumeIndex >= 0 ? resumeIndex + 1 : args.indexOf('--session-id') + 1]
  : (resumed ? args.at(-2) : fixedSession);
const attempt = existsSync(stateFile) ? Number(readFileSync(stateFile, 'utf8')) + 1 : 1;
writeFileSync(stateFile, String(attempt));
writeFileSync(argvFile, JSON.stringify(args));

const review = { status: 'approved', findings: [] };
function emit(value) {
  if (provider === 'codex') {
    const index = args.indexOf('--output-last-message');
    writeFileSync(args[index + 1], typeof value === 'string' ? value : JSON.stringify(value));
    process.stdout.write(JSON.stringify({ type: 'thread.started', thread_id: sessionId }) + '\\n');
    process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
  } else {
    process.stdout.write(JSON.stringify({ type: 'result', structured_output: value }) + '\\n');
  }
}

if (scenario === 'missing-binary') process.exit(99);
if (scenario === 'unauthorized') {
  process.stderr.write('Authentication required');
  process.exit(2);
}
if (scenario === 'unauthorized-with-stdout') {
  process.stdout.write('Authentication required\\n');
  process.stderr.write('Authentication required');
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
  process.exit(2);
}
if (scenario === 'missing-session-then-success' && attempt === 1 && resumed) {
  process.stderr.write('Session not found');
  process.exit(1);
}
if (scenario === 'timeout') {
  setTimeout(() => emit(review), 5000);
} else if (scenario === 'raw-output-limit') {
  process.stdout.write('x'.repeat(10000));
} else if (scenario === 'final-review-limit') {
  emit(JSON.stringify(review) + ' '.repeat(10000));
} else if (scenario === 'sparse-final-review-limit') {
  const args = process.argv.slice(2);
  const index = args.indexOf('--output-last-message');
  writeFileSync(args[index + 1], '{');
  truncateSync(args[index + 1], 1024 * 1024 * 1024);
  process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
} else if (scenario === 'task-context-command') {
  process.stdout.write(JSON.stringify({ type: 'tool', command: 'task-context.mjs append .joshix/tasks/example' }) + '\\n');
  emit(review);
} else if (scenario === 'task-context-read') {
  process.stdout.write(JSON.stringify({
    type: 'assistant', message: { content: [{
      type: 'tool_use', name: 'Read', input: { file_path: '.joshix/tasks/example/current.md' }
    }] }
  }) + '\\n');
  emit(review);
} else if (scenario === 'task-context-source-read') {
  process.stdout.write(JSON.stringify({
    type: 'assistant', message: { content: [{
      type: 'tool_use', name: 'Read',
      input: { file_path: 'skills/task-context/scripts/task-context.mjs' }
    }] }
  }) + '\\n');
  emit(review);
} else if (scenario === 'task-context-helper-exec') {
  process.stdout.write(JSON.stringify({
    type: 'assistant', message: { content: [{
      type: 'tool_use', name: 'Bash',
      input: { command: 'node skills/task-context/scripts/task-context.mjs recent /tmp/example' }
    }] }
  }) + '\\n');
  emit(review);
} else if (scenario === 'task-context-helper-exec-single-quoted') {
  process.stdout.write(JSON.stringify({
    type: 'assistant', message: { content: [{
      type: 'tool_use', name: 'Bash',
      input: { command: "node 'skills/task-context/scripts/task-context.mjs' recent /tmp/example" }
    }] }
  }) + '\\n');
  emit(review);
} else if (scenario === 'task-context-helper-exec-double-quoted') {
  process.stdout.write(JSON.stringify({
    type: 'assistant', message: { content: [{
      type: 'tool_use', name: 'Bash',
      input: { command: 'node "skills/task-context/scripts/task-context.mjs" recent /tmp/example' }
    }] }
  }) + '\\n');
  emit(review);
} else if (scenario === 'task-context-skill-call') {
  process.stdout.write(JSON.stringify({
    type: 'assistant', message: { content: [{
      type: 'tool_use', name: 'Skill', input: { skill: 'joshix:task-context' }
    }] }
  }) + '\\n');
  emit(review);
} else if (scenario === 'exact-task-context-notice') {
  process.stdout.write(JSON.stringify({
    type: 'assistant', message: 'Using shared task: .joshix/tasks/example/'
  }) + '\\n');
  emit(review);
} else if (scenario === 'task-context-review-reference') {
  emit({ status: 'issues', findings: [{
    id: 'F1', title: 'Reference', severity: 'important', criticality: 'ordinary',
    surface: 'task-wide', decisionLevel: 'dev',
    evidence: 'skills/task-context/scripts/task-context.mjs documents shared task context.',
    recommendation: 'keep the code reference'
  }] });
} else if (scenario === 'task-context-tool-result-reference') {
  process.stdout.write(JSON.stringify({
    type: 'assistant', message: { content: [{
      type: 'tool_result',
      content: 'The documented pointer is History: .joshix/tasks/<task>/.'
    }] }
  }) + '\\n');
  emit(review);
} else if (scenario === 'codex-final-notice') {
  emit({ status: 'issues', findings: [{
    id: 'F1', title: 'Attachment', severity: 'important', criticality: 'ordinary',
    surface: 'task-wide', decisionLevel: 'dev',
    evidence: 'Using shared task: .joshix/tasks/example/',
    recommendation: 'reject this review'
  }] });
} else if (scenario === 'stderr-guidance-mention') {
  process.stderr.write('Loaded skills/task-context/SKILL.md with shared task context guidance.');
  emit(review);
} else if (scenario === 'codex-startup-guidance-mention') {
  process.stdout.write(JSON.stringify({
    type: 'config.loaded', guidance: 'Loaded skills/task-context/SKILL.md with shared task context guidance.'
  }) + '\\n');
  emit(review);
} else if (scenario === 'system-hook-mention') {
  process.stdout.write(JSON.stringify({
    type: 'system', subtype: 'hook_response',
    output: 'Instruction: never read top-level shared task context.'
  }) + '\\n');
  emit(review);
} else if (scenario === 'split-utf8') {
  const unicodeReview = { status: 'issues', findings: [{
    id: 'F1', title: 'Unicode 🚀', severity: 'important', criticality: 'ordinary',
    surface: 'task-wide', decisionLevel: 'dev', evidence: 'Café bytes stay intact.',
    recommendation: 'Preserve the exact UTF-8 review.'
  }] };
  const payload = Buffer.from(JSON.stringify({ type: 'result', structured_output: unicodeReview }) + '\\n');
  const marker = Buffer.from('🚀');
  const splitAt = payload.indexOf(marker) + 1;
  process.stdout.write(payload.subarray(0, splitAt));
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
  process.stdout.write(payload.subarray(splitAt));
} else if (scenario === 'codex-valid-final-nonzero') {
  emit(review);
  process.stderr.write('MCP shutdown failed: Authentication required');
  process.exit(1);
} else if (scenario === 'codex-schema-invalid-unauthorized') {
  emit({ status: 'approved' });
  process.stderr.write('Authentication required');
  process.exit(2);
} else if (scenario === 'codex-schema-invalid-transient') {
  emit({ status: 'approved' });
  process.stderr.write('Temporary provider overload; try again');
  process.exit(1);
} else if (scenario === 'codex-valid-final-signal') {
  emit(review);
  process.kill(process.pid, 'SIGTERM');
} else if (scenario === 'transient-nonzero-then-success' && attempt === 1) {
  process.stderr.write('Temporary provider overload; try again');
  process.exit(1);
} else if (scenario === 'persistent-transient-nonzero') {
  process.stderr.write('Temporary provider overload; try again');
  process.exit(1);
} else if (scenario === 'malformed-then-success' && attempt === 1) {
  emit('{not json');
} else if (scenario === 'persistent-malformed') {
  emit('{not json');
} else {
  emit(review);
}
`;

function fixture(provider, scenario) {
  const root = tempDir();
  const binDir = join(root, 'bin');
  mkdirSync(binDir);
  const binary = join(binDir, provider);
  writeFileSync(binary, fakeProviderSource);
  chmodSync(binary, 0o755);
  const promptFile = join(root, 'prompt.md');
  writeFileSync(promptFile, 'Review literally: $(touch SHOULD_NOT_EXIST); *; `uname`');
  return {
    root,
    binary,
    promptFile,
    stateFile: join(root, 'state'),
    argvFile: join(root, 'argv.json'),
    marker: join(root, 'SHOULD_NOT_EXIST'),
    scenario,
    provider,
  };
}

function runFixture(fix, overrides = {}) {
  const binaryVariable = fix.provider === 'claude'
    ? 'JOSHIX_REVIEWER_CLAUDE_BIN'
    : 'JOSHIX_REVIEWER_CODEX_BIN';
  const result = spawnSync(runner, [
    '--provider', fix.provider,
    '--repo-root', fix.root,
    '--prompt-file', fix.promptFile,
    '--schema-file', schema,
    '--timeout-ms', String(overrides.timeoutMs ?? 1000),
    '--max-events', String(overrides.maxEvents ?? 20),
    '--max-output-bytes', String(overrides.maxOutputBytes ?? 2048),
    '--max-review-bytes', String(overrides.maxReviewBytes ?? 1024),
    ...(overrides.sessionId ? ['--session-id', overrides.sessionId] : []),
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
    env: {
      ...process.env,
      ...(overrides.path ? { PATH: overrides.path } : {}),
      [binaryVariable]: overrides.binary ?? fix.binary,
      JOSHIX_FAKE_SCENARIO: fix.scenario,
      JOSHIX_FAKE_STATE: fix.stateFile,
      JOSHIX_FAKE_ARGV: fix.argvFile,
      JOSHIX_FAKE_PROVIDER: fix.provider,
    },
  });
  const envelope = JSON.parse(result.stdout);
  return { result, envelope };
}

function discoveryProvider(directory, provider, mode) {
  mkdirSync(directory, { recursive: true });
  const binary = join(directory, provider);
  const log = join(directory, 'calls.log');
  const codexInitialHelp = [
    '--ignore-rules', '--sandbox', '--cd',
    '--json', '--output-schema', '--output-last-message',
  ].join(' ');
  const codexResumeHelp = '--ignore-rules --json --output-schema --output-last-message';
  const claudeHelp = '--allowedTools --disallowedTools --permission-mode --session-id --resume --output-format --json-schema';
  const source = `#!${process.execPath}
import { appendFileSync, writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
const resumeIndex = args.indexOf('resume');
const isCodexInitialHelp = args[0] === 'exec' && args[1] === '--help';
const isCodexResumeHelp = args[0] === 'exec' && resumeIndex >= 0 && args.at(-1) === '--help';
const isClaudeHelp = args[0] === '--help';
const isHelp = ${JSON.stringify(provider)} === 'codex'
  ? isCodexInitialHelp || isCodexResumeHelp
  : isClaudeHelp;
const label = isCodexInitialHelp ? 'help-exec' : isCodexResumeHelp ? 'help-resume' : isClaudeHelp ? 'help' : 'review';
appendFileSync(${JSON.stringify(log)}, label + '\\n');
if (isHelp) {
  if (${JSON.stringify(mode)} === 'broken') process.exit(1);
  if (${JSON.stringify(mode)} === 'slow') {
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 2500));
  }
  const fullHelp = isCodexInitialHelp
    ? ${JSON.stringify(codexInitialHelp)}
    : isCodexResumeHelp
      ? ${JSON.stringify(codexResumeHelp)}
      : ${JSON.stringify(claudeHelp)};
  const reportedHelp = ${JSON.stringify(mode)} === 'incomplete'
    ? '--sandbox --json'
    : ${JSON.stringify(mode)} === 'resume-incomplete' && isCodexResumeHelp
      ? '--json'
      : ${JSON.stringify(mode)} === 'decoy'
        ? '--allowedTooling --resume-latest --sandboxing --json-schema-version --output-schema-version'
        : fullHelp;
  process.stdout.write(reportedHelp);
  process.exit(0);
}
if (${JSON.stringify(provider)} === 'codex') {
  const finalIndex = args.indexOf('--output-last-message');
  if (finalIndex < 0) process.exit(7);
  writeFileSync(args[finalIndex + 1], JSON.stringify({ status: 'approved', findings: [] }));
  process.stdout.write(JSON.stringify({ type: 'thread.started', thread_id: '01990f47-3d62-7b22-8f5a-123456789abc' }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
} else {
  process.stdout.write(JSON.stringify({ type: 'result', structured_output: { status: 'approved', findings: [] } }) + '\\n');
}
`;
  writeFileSync(binary, source);
  chmodSync(binary, 0o755);
  return { binary, log };
}

function readCalls(provider) {
  return existsSync(provider.log)
    ? readFileSync(provider.log, 'utf8').trim().split('\n').filter(Boolean)
    : [];
}

function runDefaultDiscovery(provider, pathEntries) {
  const fix = fixture(provider, 'success');
  const env = {
    ...process.env,
    PATH: pathEntries.join(delimiter),
    JOSHIX_FAKE_SCENARIO: fix.scenario,
    JOSHIX_FAKE_STATE: fix.stateFile,
    JOSHIX_FAKE_ARGV: fix.argvFile,
    JOSHIX_FAKE_PROVIDER: fix.provider,
  };
  delete env[provider === 'codex' ? 'JOSHIX_REVIEWER_CODEX_BIN' : 'JOSHIX_REVIEWER_CLAUDE_BIN'];
  const result = spawnSync(process.execPath, [runner,
    '--provider', provider,
    '--repo-root', fix.root,
    '--prompt-file', fix.promptFile,
    '--schema-file', schema,
    '--timeout-ms', '1000',
    '--max-events', '20',
    '--max-output-bytes', '2048',
    '--max-review-bytes', '1024',
  ], { cwd: repoRoot, encoding: 'utf8', env });
  return { result, envelope: JSON.parse(result.stdout) };
}

for (const provider of ['claude', 'codex']) {
  test(`default ${provider} discovery skips broken and incompatible PATH candidates`, () => {
    const root = tempDir();
    const broken = discoveryProvider(join(root, 'broken'), provider, 'broken');
    const incomplete = discoveryProvider(join(root, 'incomplete'), provider, 'incomplete');
    const decoy = discoveryProvider(join(root, 'decoy'), provider, 'decoy');
    const resumeIncomplete = provider === 'codex'
      ? discoveryProvider(join(root, 'resume-incomplete'), provider, 'resume-incomplete')
      : null;
    const working = discoveryProvider(join(root, 'working'), provider, 'working');
    const candidates = [broken, incomplete, decoy, resumeIncomplete, working].filter(Boolean);
    const { result, envelope } = runDefaultDiscovery(
      provider,
      candidates.map(({ binary }) => dirname(binary)),
    );

    assert.equal(result.status, 0, result.stderr);
    assert.equal(envelope.ok, true);
    assert.deepEqual(readCalls(broken), [provider === 'codex' ? 'help-exec' : 'help']);
    assert.deepEqual(readCalls(incomplete), [provider === 'codex' ? 'help-exec' : 'help']);
    assert.deepEqual(readCalls(decoy), [provider === 'codex' ? 'help-exec' : 'help']);
    if (resumeIncomplete) assert.deepEqual(readCalls(resumeIncomplete), ['help-exec', 'help-resume']);
    assert.deepEqual(
      readCalls(working),
      provider === 'codex' ? ['help-exec', 'help-resume', 'review'] : ['help', 'review'],
    );
  });
}

test('default Claude discovery tolerates a cold help probe above two seconds', () => {
  const root = tempDir();
  const working = discoveryProvider(join(root, 'working'), 'claude', 'slow');
  const { result, envelope } = runDefaultDiscovery('claude', [dirname(working.binary)]);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(envelope.ok, true);
  assert.deepEqual(readCalls(working), ['help', 'review']);
});

test('Windows npm cmd shim resolves to Node plus a safe absolute script prefix', () => {
  const root = tempDir();
  const bin = join(root, 'bin');
  mkdirSync(bin);
  const script = join(bin, 'codex-cli.js');
  writeFileSync(script, `
const args = process.argv.slice(2);
if (args[0] === 'exec' && args[1] === '--help') {
  process.stdout.write('--ignore-rules --sandbox --cd --json --output-schema --output-last-message');
  process.exit(0);
}
if (args[0] === 'exec' && args.includes('resume') && args.at(-1) === '--help') {
  process.stdout.write('--ignore-rules --json --output-schema --output-last-message');
  process.exit(0);
}
process.exit(9);
`);
  const shim = join(bin, 'codex.cmd');
  writeFileSync(shim, '@ECHO off\r\n"%_prog%" "%dp0%\\codex-cli.js" %*\r\n');
  chmodSync(shim, 0o755);

  const discovery = discoverDefaultReviewerBinary(
    'codex',
    { PATH: bin, PATHEXT: '.CMD' },
    'win32',
  );
  assert.equal(discovery.candidates.length, 1);
  assert.equal(discovery.launcher.command, process.execPath);
  assert.deepEqual(discovery.launcher.prefixArgs, [script]);
  const result = spawnSync(
    discovery.launcher.command,
    [...discovery.launcher.prefixArgs, 'exec', '--help'],
    { encoding: 'utf8', shell: false },
  );
  assert.equal(result.status, 0, result.stderr);
});

test('explicit Codex override bypasses PATH discovery and remains authoritative', () => {
  const root = tempDir();
  const pathCandidate = discoveryProvider(join(root, 'path-candidate'), 'codex', 'working');
  const fix = fixture('codex', 'success');
  const { result, envelope } = runFixture(fix, {
    path: `${dirname(pathCandidate.binary)}${delimiter}${process.env.PATH ?? ''}`,
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(envelope.ok, true);
  assert.deepEqual(readCalls(pathCandidate), []);
  assert.equal(Number(readFileSync(fix.stateFile, 'utf8')), 1);
});

for (const provider of ['claude', 'codex']) {
  test(`default ${provider} discovery reports unavailable when every PATH candidate is unusable`, () => {
    const root = tempDir();
    const broken = discoveryProvider(join(root, 'broken'), provider, 'broken');
    const incomplete = discoveryProvider(join(root, 'incomplete'), provider, 'incomplete');
    const { result, envelope } = runDefaultDiscovery(provider, [
      dirname(broken.binary),
      dirname(incomplete.binary),
    ]);

    assert.equal(result.status, 1, result.stderr);
    assert.equal(envelope.ok, false);
    assert.equal(envelope.attempts, 0);
    assert.equal(envelope.failure.kind, 'unavailable');
    assert.deepEqual(readCalls(broken), [provider === 'codex' ? 'help-exec' : 'help']);
    assert.deepEqual(readCalls(incomplete), [provider === 'codex' ? 'help-exec' : 'help']);
  });
}

const cases = [
  ['success', 1, true],
  ['transient-nonzero-then-success', 2, true],
  ['malformed-then-success', 2, true],
  ['task-context-command', 1, true],
  ['task-context-read', 1, true],
  ['task-context-source-read', 1, true],
  ['task-context-helper-exec', 1, true],
  ['task-context-helper-exec-single-quoted', 1, true],
  ['task-context-helper-exec-double-quoted', 1, true],
  ['task-context-skill-call', 1, true],
  ['exact-task-context-notice', 1, true],
  ['task-context-review-reference', 1, true],
  ['task-context-tool-result-reference', 1, true],
  ['codex-final-notice', 1, true],
  ['stderr-guidance-mention', 1, true],
  ['codex-startup-guidance-mention', 1, true],
  ['system-hook-mention', 1, true],
  ['split-utf8', 1, true],
  ['codex-valid-final-nonzero', 1, true],
  ['codex-schema-invalid-unauthorized', 1, false],
  ['codex-schema-invalid-transient', 2, false],
  ['codex-valid-final-signal', 1, false],
  ['missing-binary', 1, false],
  ['unauthorized', 1, false],
  ['unauthorized-with-stdout', 1, false],
  ['timeout', 1, false],
  ['raw-output-limit', 1, false],
  ['final-review-limit', 1, false],
  ['sparse-final-review-limit', 1, false],
  ['persistent-transient-nonzero', 2, false],
  ['persistent-malformed', 2, false],
];

for (const [scenario, attempts, success] of cases) {
  test(`${scenario} returns a bounded envelope after ${attempts} attempt(s)`, () => {
    const provider = scenario.includes('final-review-limit') || scenario.startsWith('codex-')
      ? 'codex'
      : 'claude';
    const fix = fixture(provider, scenario);
    const overrides = scenario === 'missing-binary'
      ? { binary: join(fix.root, 'does-not-exist') }
      : scenario === 'timeout'
        ? { timeoutMs: 50 }
        : scenario === 'raw-output-limit'
          ? { maxOutputBytes: 128 }
          : scenario.includes('final-review-limit')
            ? { maxReviewBytes: 128, maxOutputBytes: 20000 }
            : {};
    const { result, envelope } = runFixture(fix, overrides);

    assert.equal(result.status, success ? 0 : 1, result.stderr);
    assert.equal(envelope.ok, success);
    assert.equal(envelope.provider, provider);
    assert.equal(envelope.attempts, attempts);
    if (success) {
      assert.match(envelope.session.id, UUID_PATTERN);
      assert.equal(envelope.session.mode, 'started');
      if (scenario === 'task-context-review-reference') {
        assert.equal(envelope.review.status, 'issues');
        assert.match(envelope.review.findings[0].evidence, /skills\/task-context\/scripts\/task-context\.mjs/);
      } else if (scenario === 'codex-final-notice') {
        assert.equal(envelope.review.status, 'issues');
        assert.match(envelope.review.findings[0].evidence, /Using shared task:/);
      } else if (scenario === 'split-utf8') {
        assert.equal(envelope.review.status, 'issues');
        assert.equal(envelope.review.findings[0].title, 'Unicode 🚀');
        assert.equal(envelope.review.findings[0].evidence, 'Café bytes stay intact.');
        assert.doesNotMatch(JSON.stringify(envelope.review), /�/);
      } else {
        assert.deepEqual(envelope.review, { status: 'approved', findings: [] });
      }
      assert.equal(envelope.failure, undefined);
      if (scenario === 'codex-valid-final-nonzero') {
        assert.deepEqual(envelope.diagnostic, { providerExitCode: 1 });
        assert.doesNotMatch(result.stdout, /Authentication required/);
      }
    } else {
      assert.equal(typeof envelope.failure.kind, 'string');
      assert.equal(typeof envelope.failure.message, 'string');
      if (scenario.includes('unauthorized')) {
        assert.equal(envelope.failure.kind, 'unauthorized');
      }
      if (scenario === 'codex-valid-final-signal') {
        assert.equal(envelope.failure.kind, 'nonzero');
      }
      if (scenario === 'codex-schema-invalid-transient') {
        assert.equal(envelope.failure.kind, 'nonzero');
      }
      assert.doesNotMatch(result.stdout, /Temporary provider|Authentication required|not json/);
    }
  });
}

for (const provider of ['claude', 'codex']) {
  test(`${provider} profile uses literal argv and a read-only permission boundary`, () => {
    const fix = fixture(provider, 'success');
    const { result } = runFixture(fix);
    assert.equal(result.status, 0, result.stderr);
    const argv = JSON.parse(readFileSync(fix.argvFile, 'utf8'));
    const prompt = readFileSync(fix.promptFile, 'utf8');

    assert.equal(argv.filter((argument) => argument === prompt).length, 1);
    assert.equal(existsSync(fix.marker), false);
    if (provider === 'claude') {
      assert.deepEqual(argv.slice(0, 2), ['-p', prompt]);
      assert.ok(argv.includes('--allowedTools'));
      const allowedTools = argv[argv.indexOf('--allowedTools') + 1];
      for (const command of ['recent', 'since-id', 'since-time', 'search', 'get', 'check']) {
        assert.ok(allowedTools.includes(`Bash(${taskContextHelper} ${command}:*)`));
      }
      assert.ok(allowedTools.startsWith('Read,Grep,Glob,'));
      assert.ok(!allowedTools.split(',').includes('Bash'));
      assert.doesNotMatch(allowedTools, /git diff|git log|\b(?:append|init|export)\b/);
      assert.doesNotMatch(allowedTools, /(?:^|,)(?:Write|Edit|MultiEdit|NotebookEdit)(?:,|$)/);
      assert.ok(argv.includes('--disallowedTools'));
      assert.ok(argv.includes('--permission-mode'));
      assert.ok(argv.includes('dontAsk'));
      assert.ok(argv.includes('--session-id'));
      assert.match(argv[argv.indexOf('--session-id') + 1], UUID_PATTERN);
      assert.ok(!argv.includes('--no-session-persistence'));
      assert.ok(argv.includes('--json-schema'));
      const schemaArgument = JSON.parse(argv[argv.indexOf('--json-schema') + 1]);
      assert.equal(schemaArgument.$schema, undefined);
      assert.equal(schemaArgument.type, 'object');
    } else {
      assert.deepEqual(argv.slice(0, 6), [
        'exec', '--ignore-rules', '--sandbox', 'read-only', '--cd', fix.root,
      ]);
      assert.ok(!argv.includes('--ephemeral'));
      assert.ok(!argv.includes('--ignore-user-config'));
      assert.ok(argv.includes('--output-schema'));
      assert.ok(argv.includes('--output-last-message'));
      assert.equal(argv.at(-1), prompt);
    }
  });
}

for (const provider of ['claude', 'codex']) {
  test(`${provider} starts and resumes one reviewer session`, () => {
    const firstFix = fixture(provider, 'success');
    const first = runFixture(firstFix);
    assert.equal(first.result.status, 0, first.result.stderr);
    assert.equal(first.envelope.session.mode, 'started');
    assert.match(first.envelope.session.id, UUID_PATTERN);

    const secondFix = fixture(provider, 'success');
    const second = runFixture(secondFix, { sessionId: first.envelope.session.id });
    assert.equal(second.result.status, 0, second.result.stderr);
    assert.deepEqual(second.envelope.session, {
      id: first.envelope.session.id,
      mode: 'resumed',
    });
    const argv = JSON.parse(readFileSync(secondFix.argvFile, 'utf8'));
    const prompt = readFileSync(secondFix.promptFile, 'utf8');
    if (provider === 'claude') {
      assert.deepEqual(argv.slice(0, 4), ['-p', prompt, '--resume', first.envelope.session.id]);
      assert.ok(!argv.includes('--session-id'));
    } else {
      const resumeIndex = argv.indexOf('resume');
      assert.deepEqual(argv.slice(0, resumeIndex), [
        'exec', '--sandbox', 'read-only', '--cd', secondFix.root,
      ]);
      assert.equal(argv.at(-2), first.envelope.session.id);
      assert.equal(argv.at(-1), prompt);
    }
  });

  test(`${provider} missing session is replaced without changing reviewer role`, () => {
    const oldSessionId = '22222222-2222-4222-8222-222222222222';
    const fix = fixture(provider, 'missing-session-then-success');
    const { result, envelope } = runFixture(fix, { sessionId: oldSessionId });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(envelope.provider, provider);
    assert.equal(envelope.attempts, 2);
    assert.equal(envelope.session.mode, 'replaced');
    assert.match(envelope.session.id, UUID_PATTERN);
    assert.notEqual(envelope.session.id, oldSessionId);
    assert.equal(Number(readFileSync(fix.stateFile, 'utf8')), 2);
  });
}

test('invalid CLI input fails before launching a provider', () => {
  const result = spawnSync(runner, ['--provider', 'other'], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  assert.equal(result.status, 1);
  const envelope = JSON.parse(result.stdout);
  assert.equal(envelope.ok, false);
  assert.equal(envelope.failure.kind, 'configuration');
  assert.equal(envelope.failure.message, 'reviewer runner configuration is invalid');
  assert.equal(envelope.attempts, 0);
});

function runPreflightFixture(fix, { repoRootPath = fix.root, promptPath = fix.promptFile, schemaPath = schema }) {
  return spawnSync(runner, [
    '--provider', fix.provider,
    '--repo-root', repoRootPath,
    '--prompt-file', promptPath,
    '--schema-file', schemaPath,
    '--timeout-ms', '1000',
    '--max-events', '20',
    '--max-output-bytes', '2048',
    '--max-review-bytes', '1024',
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
    env: {
      ...process.env,
      JOSHIX_REVIEWER_CLAUDE_BIN: fix.binary,
      JOSHIX_FAKE_SCENARIO: fix.scenario,
      JOSHIX_FAKE_STATE: fix.stateFile,
      JOSHIX_FAKE_ARGV: fix.argvFile,
      JOSHIX_FAKE_PROVIDER: fix.provider,
    },
  });
}

for (const [label, paths] of [
  ['repo root is a regular file', (fix) => ({ repoRootPath: fix.promptFile })],
  ['prompt is a directory', (fix) => ({ promptPath: fix.root })],
]) {
  test(`${label} is rejected before launching a provider`, () => {
    const fix = fixture('claude', 'success');
    const result = runPreflightFixture(fix, paths(fix));
    assert.equal(result.status, 1, result.stderr);
    const envelope = JSON.parse(result.stdout);
    assert.equal(envelope.failure.kind, 'configuration');
    assert.equal(envelope.attempts, 0);
    assert.equal(existsSync(fix.stateFile), false);
    assert.equal(existsSync(fix.argvFile), false);
  });
}

test('a structurally unrelated JSON schema is rejected before launching a provider', () => {
  const fix = fixture('claude', 'success');
  const unrelatedSchema = join(fix.root, 'unrelated.schema.json');
  writeFileSync(unrelatedSchema, JSON.stringify({ type: 'object' }));
  const result = runPreflightFixture(fix, { schemaPath: unrelatedSchema });
  assert.equal(result.status, 1, result.stderr);
  const envelope = JSON.parse(result.stdout);
  assert.equal(envelope.failure.kind, 'configuration');
  assert.equal(envelope.attempts, 0);
  assert.equal(existsSync(fix.stateFile), false);
  assert.equal(existsSync(fix.argvFile), false);
});

for (const [label, mutate] of [
  ['status const', (value) => { value.properties.status.const = 'approved'; }],
  ['findings maxItems', (value) => { value.properties.findings.maxItems = 0; }],
  ['finding string pattern', (value) => {
    value.properties.findings.items.properties.evidence.pattern = 'a^';
  }],
]) {
  test(`a near-canonical schema with ${label} is rejected before launching a provider`, () => {
    const fix = fixture('claude', 'success');
    const constrainedSchema = join(fix.root, 'constrained.schema.json');
    const value = JSON.parse(readFileSync(schema, 'utf8'));
    mutate(value);
    writeFileSync(constrainedSchema, JSON.stringify(value));
    const result = runPreflightFixture(fix, { schemaPath: constrainedSchema });
    assert.equal(result.status, 1, result.stderr);
    const envelope = JSON.parse(result.stdout);
    assert.equal(envelope.failure.kind, 'configuration');
    assert.equal(envelope.attempts, 0);
    assert.equal(existsSync(fix.stateFile), false);
    assert.equal(existsSync(fix.argvFile), false);
  });
}
