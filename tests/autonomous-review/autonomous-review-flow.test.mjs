import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const joshixRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const runner = join(joshixRoot, 'skills/requesting-code-review/scripts/reviewer-runner.mjs');
const taskContext = join(joshixRoot, 'skills/task-context/scripts/task-context.mjs');
const schema = join(joshixRoot, 'skills/requesting-code-review/review-result.schema.json');
const recordSchemaPath = join(dirname(schema), 'review-record.schema.json');
const FIXED_CODEX_SESSION = '01990f47-3d62-7b22-8f5a-123456789abc';
const temporaryDirectories = [];

function temporaryDirectory() {
  const directory = mkdtempSync(join(tmpdir(), 'joshix-autonomous-flow-'));
  temporaryDirectories.push(directory);
  return directory;
}

after(() => {
  for (const directory of temporaryDirectories) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function run(file, args, options = {}) {
  return spawnSync(file, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    env: { ...process.env, ...options.env },
  });
}

function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function validateSchema(value, schemaValue, schemaDirectory, path = 'record') {
  if (schemaValue.$ref) {
    const referenced = JSON.parse(readFileSync(join(schemaDirectory, schemaValue.$ref), 'utf8'));
    validateSchema(value, referenced, schemaDirectory, path);
    return;
  }
  if (schemaValue.const !== undefined) assert.deepEqual(value, schemaValue.const, `${path} const`);
  if (schemaValue.enum) assert.ok(schemaValue.enum.includes(value), `${path} enum`);
  if (schemaValue.type) {
    const types = Array.isArray(schemaValue.type) ? schemaValue.type : [schemaValue.type];
    const actual = value === null
      ? 'null'
      : Array.isArray(value)
        ? 'array'
        : Number.isInteger(value)
          ? 'integer'
          : typeof value;
    assert.ok(types.includes(actual) || (actual === 'integer' && types.includes('number')), `${path} type`);
  }
  if (typeof value === 'string') {
    if (schemaValue.minLength !== undefined) assert.ok(value.length >= schemaValue.minLength, `${path} minLength`);
    if (schemaValue.pattern) assert.match(value, new RegExp(schemaValue.pattern), `${path} pattern`);
  }
  if (typeof value === 'number') {
    if (schemaValue.minimum !== undefined) assert.ok(value >= schemaValue.minimum, `${path} minimum`);
    if (schemaValue.maximum !== undefined) assert.ok(value <= schemaValue.maximum, `${path} maximum`);
  }
  if (Array.isArray(value) && schemaValue.items) {
    value.forEach((item, index) => validateSchema(item, schemaValue.items, schemaDirectory, `${path}[${index}]`));
  }
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    for (const key of schemaValue.required ?? []) assert.ok(key in value, `${path}.${key} required`);
    if (schemaValue.additionalProperties === false) {
      for (const key of Object.keys(value)) assert.ok(key in (schemaValue.properties ?? {}), `${path}.${key} additional`);
    }
    for (const [key, propertySchema] of Object.entries(schemaValue.properties ?? {})) {
      if (key in value) validateSchema(value[key], propertySchema, schemaDirectory, `${path}.${key}`);
    }
  }
  for (const branch of schemaValue.allOf ?? []) {
    let conditionMatches = true;
    if (branch.if) {
      try {
        validateSchema(value, branch.if, schemaDirectory, path);
      } catch {
        conditionMatches = false;
      }
    }
    if (conditionMatches && branch.then) validateSchema(value, branch.then, schemaDirectory, path);
  }
}

function writeSuccessProvider(file, provider, marker = null) {
  writeFileSync(file, `#!/usr/bin/env node
import { appendFileSync, writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
const resumeIndex = ${JSON.stringify(provider)} === 'codex' ? args.indexOf('resume') : args.indexOf('--resume');
const resumed = resumeIndex >= 0;
const sessionId = ${JSON.stringify(provider)} === 'codex'
  ? (resumed ? args.at(-2) : ${JSON.stringify(FIXED_CODEX_SESSION)})
  : args[resumed ? resumeIndex + 1 : args.indexOf('--session-id') + 1];
${marker ? `appendFileSync(${JSON.stringify(marker)}, JSON.stringify({ provider: ${JSON.stringify(provider)}, sessionId, resumed }) + '\\n');` : ''}
const review = { status: 'approved', findings: [] };
if (${JSON.stringify(provider)} === 'codex') {
  writeFileSync(args[args.indexOf('--output-last-message') + 1], JSON.stringify(review));
  process.stdout.write(JSON.stringify({ type: 'thread.started', thread_id: sessionId }) + '\\n');
  process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');
} else {
  process.stdout.write(JSON.stringify({ type: 'result', structured_output: review }) + '\\n');
}
`);
  chmodSync(file, 0o755);
}

function boundedRunnerArgs(provider, repo, promptFile, sessionId = null) {
  return [
    '--provider', provider,
    '--repo-root', repo,
    '--prompt-file', promptFile,
    '--schema-file', schema,
    '--timeout-ms', '1000',
    '--max-events', '20',
    '--max-output-bytes', '4096',
    '--max-review-bytes', '2048',
    ...(sessionId ? ['--session-id', sessionId] : []),
  ];
}

function persistDirectReview({
  repo,
  taskName,
  gate,
  prompt,
  review,
  requestedProvider,
  usedProvider,
  path,
  session,
  round = 1,
  fallback = null,
  attempts = { requested: 1, fallback: 0 },
  existing = false,
  expectedReviewRows = 1,
}) {
  const taskFolder = `.joshix/tasks/${taskName}`;
  const taskDirectory = join(repo, taskFolder);
  const snapshot = join(taskDirectory, 'current.md');
  if (!existing) {
    const initialized = run(taskContext, ['init', taskFolder], { cwd: repo });
    assert.equal(initialized.status, 0, initialized.stderr);
    writeFileSync(snapshot, [
      '---', 'history_through: 0', '---', '',
      '## Workflow declaration',
      '- Surfaces: `fixture — ordinary — review transport`',
      '- Complexity: `trivial`',
      '- Effort: `five minutes`',
      '- Outcome/scope: `Exercise one review gate.`',
      '- Active time: `one minute; open`',
      '- Review: `pending`',
      '- Deferred: `0; none`',
      '',
    ].join('\n'));
  }
  const promptDigest = digest(prompt);
  const record = {
    schemaVersion: 2,
    gate,
    round,
    reviewer: {
      requestedProvider,
      usedProvider,
      path,
      attempts,
      fallback,
      session,
    },
    promptDigest: `sha256:${promptDigest}`,
    review,
  };
  const recordSchema = JSON.parse(readFileSync(recordSchemaPath, 'utf8'));
  validateSchema(record, recordSchema, dirname(schema));
  const recordFile = join(repo, `${taskName}-${gate}-record.json`);
  writeFileSync(recordFile, `${JSON.stringify(record)}\n`);
  const key = digest([taskFolder, gate, round, path, promptDigest].join('\0'));
  const args = [
    'append', taskFolder,
    '--speaker', 'Reviewer',
    '--content-file', recordFile,
    '--idempotency-key', key,
  ];
  const first = run(taskContext, args, { cwd: repo });
  const duplicate = run(taskContext, args, { cwd: repo });
  assert.equal(first.status, 0, first.stderr);
  assert.equal(duplicate.stdout, first.stdout);
  const historyId = Number(first.stdout.trim());
  const temporarySnapshot = join(taskDirectory, '.current.md.tmp');
  const nextSnapshot = readFileSync(snapshot, 'utf8')
    .replace(/history_through: \d+/, `history_through: ${historyId}`)
    .replace(
      /- Review: `[^`]*`/,
      `- Review: \`${gate}; round ${round}; ${path}; ${usedProvider} session ${session.id}; history ${historyId}\``,
    );
  writeFileSync(temporarySnapshot, nextSnapshot);
  renameSync(temporarySnapshot, snapshot);
  const rows = JSON.parse(run(taskContext, ['recent', taskFolder, '--full'], { cwd: repo }).stdout);
  assert.equal(rows.filter((row) => row.speaker === 'Reviewer').length, expectedReviewRows);
  assert.match(readFileSync(snapshot, 'utf8'), new RegExp(`Review: .*history ${historyId}`));
  return { record, historyId, taskFolder };
}

test('low-trivial flow falls back, records once, snapshots atomically, and runs one final gate', () => {
  const repo = temporaryDirectory();
  execFileSync('git', ['init', '--quiet'], { cwd: repo });
  execFileSync('git', ['config', 'user.email', 'review-flow@example.com'], { cwd: repo });
  execFileSync('git', ['config', 'user.name', 'Review Flow'], { cwd: repo });
  writeFileSync(join(repo, 'AGENTS.md'), 'joshix-workflow-policy: workflow-policy.md\n');
  writeFileSync(join(repo, 'workflow-policy.md'), [
    'Tiers highest to lowest: guarded, ordinary, presentation.',
    'Styling is presentation and gets one review.',
    'Completion check: git diff --check.',
    'Repository safety rules are unconditional.',
    '',
  ].join('\n'));
  writeFileSync(join(repo, 'app.css'), '.photo { opacity: 0.99; }\n');
  execFileSync('git', ['add', 'AGENTS.md', 'workflow-policy.md', 'app.css'], { cwd: repo });
  execFileSync('git', ['commit', '--quiet', '-m', 'fixture'], { cwd: repo });

  // The requested result is one line; ceremony remains absent for trivial work.
  writeFileSync(join(repo, 'app.css'), '.photo { opacity: 1; }\n');
  assert.equal(existsSync(join(repo, '.joshix/specs')), false);
  assert.equal(existsSync(join(repo, '.joshix/plans')), false);
  assert.match(execFileSync('git', ['diff', '--numstat'], { cwd: repo, encoding: 'utf8' }), /^1\s+1\s+app\.css$/m);

  const prompt = [
    'You are the persistent reviewer peer for this task. Remain read-only.',
    'Task folder: .joshix/tasks/low-trivial/',
    'Gate: whole-change',
    'Review target: app.css',
    'Return only an approved result matching the supplied schema.',
  ].join('\n');
  const promptFile = join(repo, 'review-prompt.md');
  writeFileSync(promptFile, prompt);
  const missingClaude = join(repo, 'missing-claude');
  const requested = run(runner, [
    '--provider', 'claude',
    '--repo-root', repo,
    '--prompt-file', promptFile,
    '--schema-file', schema,
    '--timeout-ms', '1000',
    '--max-events', '20',
    '--max-output-bytes', '4096',
    '--max-review-bytes', '2048',
  ], {
    cwd: repo,
    env: { JOSHIX_REVIEWER_CLAUDE_BIN: missingClaude },
  });
  assert.equal(requested.status, 1);
  assert.equal(JSON.parse(requested.stdout).failure.kind, 'unavailable');

  const fakeCodex = join(repo, 'fake-codex');
  writeSuccessProvider(fakeCodex, 'codex');
  const fallback = run(runner, boundedRunnerArgs('codex', repo, promptFile), {
    cwd: repo,
    env: { JOSHIX_REVIEWER_CODEX_BIN: fakeCodex },
  });
  assert.equal(fallback.status, 0, fallback.stderr);
  const fallbackEnvelope = JSON.parse(fallback.stdout);
  assert.deepEqual(fallbackEnvelope.review, { status: 'approved', findings: [] });

  const taskFolder = '.joshix/tasks/low-trivial';
  const initialized = run(taskContext, ['init', taskFolder], { cwd: repo });
  assert.equal(initialized.status, 0, initialized.stderr);
  const taskDirectory = join(repo, taskFolder);
  const snapshot = join(taskDirectory, 'current.md');
  writeFileSync(snapshot, [
    '---',
    'history_through: 0',
    '---',
    '',
    '## Workflow declaration',
    '- Surfaces: `photo-style — presentation — removes flicker`',
    '- Complexity: `trivial`',
    '- Effort: `five minutes`',
    '- Outcome/scope: `Change one opacity value only.`',
    '- Active time: `four minutes; closed`',
    '- Review: `pending`',
    '- Deferred: `0; none`',
    '',
  ].join('\n'));
  const promptDigest = digest(prompt);
  const record = {
    schemaVersion: 2,
    gate: 'whole-change',
    round: 1,
    reviewer: {
      requestedProvider: 'claude',
      usedProvider: 'codex',
      path: 'same-model-cli',
      attempts: { requested: 1, fallback: 1 },
      fallback: { reason: 'unavailable' },
      session: fallbackEnvelope.session,
    },
    promptDigest: `sha256:${promptDigest}`,
    review: fallbackEnvelope.review,
  };
  const recordSchema = JSON.parse(readFileSync(recordSchemaPath, 'utf8'));
  assert.doesNotThrow(() => validateSchema(record, recordSchema, dirname(schema)));
  assert.throws(() => validateSchema({ ...record, round: 3 }, recordSchema, dirname(schema)));
  const recordFile = join(repo, 'review-record.json');
  writeFileSync(recordFile, `${JSON.stringify(record)}\n`);
  const keyMaterial = [taskFolder, record.gate, record.round, record.reviewer.path, promptDigest].join('\0');
  const idempotencyKey = digest(keyMaterial);
  const appendArgs = [
    'append', taskFolder,
    '--speaker', 'Reviewer',
    '--content-file', recordFile,
    '--idempotency-key', idempotencyKey,
  ];
  const firstAppend = run(taskContext, appendArgs, { cwd: repo });
  const duplicateAppend = run(taskContext, appendArgs, { cwd: repo });
  assert.equal(firstAppend.status, 0, firstAppend.stderr);
  assert.equal(duplicateAppend.status, 0, duplicateAppend.stderr);
  assert.equal(duplicateAppend.stdout, firstAppend.stdout);

  const historyId = Number(firstAppend.stdout.trim());
  const recent = run(taskContext, ['recent', taskFolder, '--full'], { cwd: repo });
  assert.equal(recent.status, 0, recent.stderr);
  const reviewRows = JSON.parse(recent.stdout).filter((row) => row.speaker === 'Reviewer');
  assert.equal(reviewRows.length, 1);
  assert.deepEqual(JSON.parse(reviewRows[0].content), record);

  const temporarySnapshot = join(taskDirectory, '.current.md.tmp');
  const updatedSnapshot = readFileSync(snapshot, 'utf8')
    .replace('history_through: 0', `history_through: ${historyId}`)
    .replace(
      '- Review: `pending`',
      `- Review: \`whole-change; round 1; same-model-cli; codex session ${fallbackEnvelope.session.id}; history ${historyId}\``,
    );
  writeFileSync(temporarySnapshot, updatedSnapshot);
  renameSync(temporarySnapshot, snapshot);
  assert.equal(existsSync(temporarySnapshot), false);
  const finalSnapshot = readFileSync(snapshot, 'utf8');
  for (const preserved of [
    '- Surfaces: `photo-style — presentation — removes flicker`',
    '- Complexity: `trivial`',
    '- Effort: `five minutes`',
    '- Outcome/scope: `Change one opacity value only.`',
    '- Active time: `four minutes; closed`',
    '- Deferred: `0; none`',
  ]) assert.match(finalSnapshot, new RegExp(preserved.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(finalSnapshot, new RegExp(`Review: .*history ${historyId}`));

  let finalGateRuns = 0;
  execFileSync('git', ['diff', '--check'], { cwd: repo });
  finalGateRuns += 1;
  assert.equal(finalGateRuns, 1);
});

test('fixed provider selection uses the other provider without repository opt-in', () => {
  const repo = temporaryDirectory();
  execFileSync('git', ['init', '--quiet'], { cwd: repo });
  const promptFile = join(repo, 'prompt.md');
  writeFileSync(promptFile, 'Return an approved structured review.');
  const sameModelMarker = join(repo, 'same-model-invoked');
  const fakeClaude = join(repo, 'fake-claude');
  const fakeCodex = join(repo, 'fake-codex');
  writeSuccessProvider(fakeClaude, 'claude');
  writeSuccessProvider(fakeCodex, 'codex', sameModelMarker);
  const result = run(runner, boundedRunnerArgs('claude', repo, promptFile), {
    cwd: repo,
    env: {
      JOSHIX_REVIEWER_CLAUDE_BIN: fakeClaude,
      JOSHIX_REVIEWER_CODEX_BIN: fakeCodex,
    },
  });
  assert.equal(result.status, 0, result.stderr);
  const envelope = JSON.parse(result.stdout);
  assert.equal(envelope.provider, 'claude');
  assert.equal(envelope.session.mode, 'started');
  assert.equal(existsSync(sameModelMarker), false);
  persistDirectReview({
    repo,
    taskName: 'cross-provider-direct',
    gate: 'whole-change',
    prompt: readFileSync(promptFile, 'utf8'),
    review: envelope.review,
    requestedProvider: 'claude',
    usedProvider: 'claude',
    path: 'cross-provider-cli',
    session: envelope.session,
  });
});

test('one persistent reviewer session is reused across task gates', () => {
  const repo = temporaryDirectory();
  execFileSync('git', ['init', '--quiet'], { cwd: repo });
  const promptFile = join(repo, 'prompt.md');
  writeFileSync(promptFile, [
    'You are the persistent reviewer peer for this task. Remain read-only.',
    'Task folder: .joshix/tasks/persistent-peer/',
    'Read current.md and query task history as needed.',
    'Return an approved structured review.',
  ].join('\n'));
  const reviewerLog = join(repo, 'reviewer-invocations.jsonl');
  const sameModelMarker = join(repo, 'same-model-invoked');
  const fakeClaude = join(repo, 'fake-claude');
  const fakeCodex = join(repo, 'fake-codex');
  writeSuccessProvider(fakeClaude, 'claude', reviewerLog);
  writeSuccessProvider(fakeCodex, 'codex', sameModelMarker);
  const environment = {
    JOSHIX_REVIEWER_CLAUDE_BIN: fakeClaude,
    JOSHIX_REVIEWER_CODEX_BIN: fakeCodex,
  };

  const first = run(runner, boundedRunnerArgs('claude', repo, promptFile), {
    cwd: repo,
    env: environment,
  });
  assert.equal(first.status, 0, first.stderr);
  const firstEnvelope = JSON.parse(first.stdout);
  assert.equal(firstEnvelope.session.mode, 'started');
  const firstRecord = persistDirectReview({
    repo,
    taskName: 'persistent-peer',
    gate: 'plan',
    prompt: readFileSync(promptFile, 'utf8'),
    review: firstEnvelope.review,
    requestedProvider: 'claude',
    usedProvider: 'claude',
    path: 'cross-provider-cli',
    session: firstEnvelope.session,
  });

  const second = run(
    runner,
    boundedRunnerArgs('claude', repo, promptFile, firstEnvelope.session.id),
    { cwd: repo, env: environment },
  );
  assert.equal(second.status, 0, second.stderr);
  const secondEnvelope = JSON.parse(second.stdout);
  assert.deepEqual(secondEnvelope.session, {
    id: firstEnvelope.session.id,
    mode: 'resumed',
  });
  persistDirectReview({
    repo,
    taskName: 'persistent-peer',
    gate: 'whole-change',
    prompt: readFileSync(promptFile, 'utf8'),
    review: secondEnvelope.review,
    requestedProvider: 'claude',
    usedProvider: 'claude',
    path: 'cross-provider-cli',
    session: secondEnvelope.session,
    existing: true,
    expectedReviewRows: 2,
  });
  const invocations = readFileSync(reviewerLog, 'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(invocations.map(({ sessionId }) => sessionId), [
    firstEnvelope.session.id,
    firstEnvelope.session.id,
  ]);
  assert.deepEqual(invocations.map(({ resumed }) => resumed), [false, true]);
  assert.equal(existsSync(sameModelMarker), false);
  const rows = JSON.parse(run(taskContext, ['recent', firstRecord.taskFolder, '--full'], { cwd: repo }).stdout);
  assert.equal(rows.filter((row) => row.speaker === 'Reviewer').length, 2);
});

test('provider failure starts one same-role fallback session and reuses it at later gates', () => {
  const repo = temporaryDirectory();
  execFileSync('git', ['init', '--quiet'], { cwd: repo });
  const promptFile = join(repo, 'prompt.md');
  writeFileSync(promptFile, 'Return an approved structured review.');
  const crossAttempts = join(repo, 'cross-attempts');
  const fakeClaude = join(repo, 'fake-claude');
  writeFileSync(fakeClaude, `#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
const marker = ${JSON.stringify(crossAttempts)};
const count = existsSync(marker) ? Number(readFileSync(marker, 'utf8')) + 1 : 1;
writeFileSync(marker, String(count));
process.stderr.write('Authentication required');
process.exit(2);
`);
  chmodSync(fakeClaude, 0o755);
  const fakeCodex = join(repo, 'fake-codex');
  const fallbackLog = join(repo, 'fallback-invocations.jsonl');
  writeSuccessProvider(fakeCodex, 'codex', fallbackLog);
  const environment = {
    JOSHIX_REVIEWER_CLAUDE_BIN: fakeClaude,
    JOSHIX_REVIEWER_CODEX_BIN: fakeCodex,
  };

  const failedCross = run(runner, boundedRunnerArgs('claude', repo, promptFile), { cwd: repo, env: environment });
  assert.equal(failedCross.status, 1);
  assert.equal(JSON.parse(failedCross.stdout).failure.kind, 'unauthorized');
  const fallback = run(runner, boundedRunnerArgs('codex', repo, promptFile), { cwd: repo, env: environment });
  assert.equal(fallback.status, 0, fallback.stderr);
  const fallbackEnvelope = JSON.parse(fallback.stdout);
  assert.equal(fallbackEnvelope.session.mode, 'started');
  const first = persistDirectReview({
    repo,
    taskName: 'disabled-cross-provider',
    gate: 'slice-one',
    prompt: readFileSync(promptFile, 'utf8'),
    review: fallbackEnvelope.review,
    requestedProvider: 'claude',
    usedProvider: 'codex',
    path: 'same-model-cli',
    fallback: { reason: 'unauthorized' },
    attempts: { requested: 1, fallback: 1 },
    session: fallbackEnvelope.session,
  });
  assert.equal(first.record.reviewer.fallback.reason, 'unauthorized');

  // Later coordinator selection consults the authoritative prior record.
  const priorRows = JSON.parse(run(taskContext, ['recent', first.taskFolder, '--full'], { cwd: repo }).stdout);
  const priorRecord = JSON.parse(priorRows.find((row) => row.speaker === 'Reviewer').content);
  const laterProvider = priorRecord.reviewer.usedProvider;
  const laterSession = priorRecord.reviewer.session.id;
  const later = run(
    runner,
    boundedRunnerArgs(laterProvider, repo, promptFile, laterSession),
    { cwd: repo, env: environment },
  );
  assert.equal(later.status, 0, later.stderr);
  const laterEnvelope = JSON.parse(later.stdout);
  assert.deepEqual(laterEnvelope.session, { id: laterSession, mode: 'resumed' });
  persistDirectReview({
    repo,
    taskName: 'disabled-cross-provider',
    gate: 'whole-change',
    prompt: readFileSync(promptFile, 'utf8'),
    review: laterEnvelope.review,
    requestedProvider: 'codex',
    usedProvider: 'codex',
    path: 'same-model-cli',
    session: laterEnvelope.session,
    existing: true,
    expectedReviewRows: 2,
  });
  assert.equal(readFileSync(crossAttempts, 'utf8'), '1');
  const fallbackInvocations = readFileSync(fallbackLog, 'utf8').trim().split('\n').map((line) => JSON.parse(line));
  assert.deepEqual(fallbackInvocations.map(({ sessionId }) => sessionId), [laterSession, laterSession]);
  assert.deepEqual(fallbackInvocations.map(({ resumed }) => resumed), [false, true]);
});

test('version 1 review history starts a fresh session on its recorded provider', () => {
  const repo = temporaryDirectory();
  execFileSync('git', ['init', '--quiet'], { cwd: repo });
  const taskName = 'legacy-upgrade';
  const taskFolder = `.joshix/tasks/${taskName}`;
  const initialized = run(taskContext, ['init', taskFolder], { cwd: repo });
  assert.equal(initialized.status, 0, initialized.stderr);

  const legacyRecord = {
    schemaVersion: 1,
    gate: 'slice-one',
    round: 1,
    reviewer: {
      requestedProvider: 'claude',
      usedProvider: 'claude',
      path: 'cross-provider-cli',
      attempts: { requested: 1, fallback: 0 },
      fallback: null,
    },
    promptDigest: `sha256:${digest('legacy review prompt')}`,
    review: { status: 'approved', findings: [] },
  };
  const legacyFile = join(repo, 'legacy-review-record.json');
  writeFileSync(legacyFile, `${JSON.stringify(legacyRecord)}\n`);
  const legacyAppend = run(taskContext, [
    'append', taskFolder,
    '--speaker', 'Reviewer',
    '--content-file', legacyFile,
    '--idempotency-key', digest('legacy-review-record'),
  ], { cwd: repo });
  assert.equal(legacyAppend.status, 0, legacyAppend.stderr);
  const legacyHistoryId = Number(legacyAppend.stdout.trim());
  writeFileSync(join(repo, taskFolder, 'current.md'), [
    '---', `history_through: ${legacyHistoryId}`, '---', '',
    '## Workflow declaration',
    '- Surfaces: `fixture — ordinary — review transport`',
    '- Complexity: `trivial`',
    '- Effort: `five minutes`',
    '- Outcome/scope: `Exercise review history upgrade.`',
    '- Active time: `one minute; open`',
    `- Review: \`slice-one; round 1; cross-provider-cli; history ${legacyHistoryId}\``,
    '- Deferred: `0; none`',
    '',
  ].join('\n'));

  const promptFile = join(repo, 'prompt.md');
  writeFileSync(promptFile, 'Return an approved structured review.');
  const reviewerLog = join(repo, 'legacy-provider-invocations.jsonl');
  const fakeClaude = join(repo, 'fake-claude');
  writeSuccessProvider(fakeClaude, 'claude', reviewerLog);
  const result = run(runner, boundedRunnerArgs('claude', repo, promptFile), {
    cwd: repo,
    env: { JOSHIX_REVIEWER_CLAUDE_BIN: fakeClaude },
  });
  assert.equal(result.status, 0, result.stderr);
  const envelope = JSON.parse(result.stdout);
  assert.equal(envelope.provider, legacyRecord.reviewer.usedProvider);
  assert.equal(envelope.session.mode, 'started');
  persistDirectReview({
    repo,
    taskName,
    gate: 'whole-change',
    prompt: readFileSync(promptFile, 'utf8'),
    review: envelope.review,
    requestedProvider: 'claude',
    usedProvider: 'claude',
    path: 'cross-provider-cli',
    session: envelope.session,
    existing: true,
    expectedReviewRows: 2,
  });

  const rows = JSON.parse(run(taskContext, ['recent', taskFolder, '--full'], { cwd: repo }).stdout)
    .filter((row) => row.speaker === 'Reviewer');
  assert.equal(rows.length, 2);
  assert.deepEqual(JSON.parse(rows[0].content), legacyRecord);
  const upgraded = JSON.parse(rows[1].content);
  assert.equal(upgraded.schemaVersion, 2);
  assert.equal(upgraded.reviewer.usedProvider, 'claude');
  assert.equal(upgraded.reviewer.session.mode, 'started');
  const invocation = JSON.parse(readFileSync(reviewerLog, 'utf8').trim());
  assert.equal(invocation.resumed, false);
});
