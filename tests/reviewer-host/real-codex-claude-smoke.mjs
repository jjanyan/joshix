#!/usr/bin/env node

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  accessSync,
  constants as fsConstants,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { homedir, tmpdir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const taskContext = join(sourceRoot, 'skills/task-context/scripts/task-context.mjs');

function defaultLauncher() {
  const requested = process.env.JOSHIX_REVIEW_LAUNCHER;
  if (requested) {
    if (!isAbsolute(requested)) throw new Error('JOSHIX_REVIEW_LAUNCHER must be absolute');
    return realpathSync(requested);
  }
  const dataRoot = isAbsolute(process.env.XDG_DATA_HOME ?? '')
    ? process.env.XDG_DATA_HOME
    : join(process.env.HOME || homedir(), '.local/share');
  return realpathSync(join(dataRoot, 'joshix/reviewer-host/bin/joshix-review'));
}

function hashFile(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function runTask(root, args) {
  const result = spawnSync(taskContext, args, {
    cwd: root,
    encoding: 'utf8',
    shell: false,
  });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}

function append(root, folder, speaker, content, name) {
  const file = join(root, name);
  writeFileSync(file, content);
  runTask(root, ['append', folder, '--speaker', speaker, '--content-file', file]);
}

function runReview(launcher, provider, root, taskFolder) {
  const result = spawnSync(launcher, [
    'review',
    '--provider', provider,
    '--repo-root', root,
    '--task-folder', taskFolder,
  ], {
    cwd: root,
    encoding: 'utf8',
    shell: false,
    maxBuffer: 2 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const lines = result.stdout.trim().split(/\r?\n/);
  assert.equal(lines.length, 1, 'bridge must emit exactly one JSON line');
  const response = JSON.parse(lines[0]);
  assert.equal(response.ok, true);
  assert.deepEqual(Object.keys(response).sort(), ['historyId', 'ok', 'review']);
  return response;
}

function installedExecutables(launcher) {
  const source = readFileSync(launcher, 'utf8');
  const match = source.match(
    /^const INSTALLED_EXECUTABLES = Object\.freeze\((\{.*\})\);$/m,
  );
  assert.ok(match, 'installed bridge must embed its executable configuration');
  return JSON.parse(match[1]);
}

async function runClaudePermissionProbe(launcher, root, taskFolder, prompt) {
  const installed = installedExecutables(launcher);
  const claude = installed.claude;
  const modulePath = join(dirname(root), 'installed-launcher-profile.mjs');
  writeFileSync(modulePath, readFileSync(launcher));
  let claudeArguments;
  let reviewSchema;
  try {
    ({ claudeArguments, REVIEW_SCHEMA: reviewSchema } = await import(
      pathToFileURL(modulePath).href
    ));
  } finally {
    rmSync(modulePath, { force: true });
  }
  assert.equal(typeof claudeArguments, 'function');
  const providerSchema = { ...reviewSchema };
  delete providerSchema.$schema;
  delete providerSchema.allOf;
  const result = spawnSync(claude.command, [
    ...(claude.prefixArgs ?? []),
    ...claudeArguments({
      installedExecutable: launcher,
      repoRoot: root,
      taskFolder,
      prompt,
      providerSchema,
    }),
  ], {
    cwd: root,
    encoding: 'utf8',
    shell: false,
    maxBuffer: 2 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  return result.stdout;
}

function deniedBashCommands(stream, expectedCommands) {
  const events = stream.trim().split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  const bashUses = new Map();
  const denials = [];

  for (const event of events) {
    for (const block of event.message?.content ?? []) {
      if (block.type === 'tool_use' && block.name === 'Bash') {
        bashUses.set(block.id, block.input?.command);
      }
    }
    for (const denial of event.permission_denials ?? []) denials.push(denial);
  }

  for (const command of expectedCommands) {
    const use = [...bashUses].find(([, attempted]) => attempted === command);
    assert.ok(use, `Claude did not issue the expected Bash tool call: ${command}\n${stream}`);
    const [toolUseId] = use;
    assert.ok(
      denials.some((denial) => (
        denial.tool_use_id === toolUseId
        || (denial.tool_name === 'Bash' && denial.tool_input?.command === command)
      )),
      `Claude's stream did not record a permission denial for: ${command}\n${stream}`,
    );
  }
}

function createReviewFixture(label) {
  const temporaryRoot = realpathSync(mkdtempSync(join(tmpdir(), `joshix-live-${label}-`)));
  const root = join(temporaryRoot, 'repo');
  mkdirSync(root);
  execFileSync('git', ['init', '--quiet'], { cwd: root });
  const taskFolder = `.joshix/tasks/${label}`;
  runTask(root, ['init', taskFolder]);
  mkdirSync(join(root, '.joshix/specs'), { recursive: true });
  const artifact = join(root, '.joshix/specs/audit-retention-design.md');
  writeFileSync(artifact, [
    '# Audit retention design',
    '',
    'The owner requires every audit entry to remain queryable for seven years',
    'after account deletion. The proposed purge hard-deletes the account and',
    'every audit row, and completion requires that no audit rows remain.',
    'This design is awaiting review; no plan or code exists.',
    '',
  ].join('\n'));
  append(root, taskFolder, 'User', [
    'Review `.joshix/specs/audit-retention-design.md` against the owner\'s',
    'seven-year retention requirement. This spec is the active artifact.',
  ].join(' '), 'request.txt');
  return { temporaryRoot, root: realpathSync(root), taskFolder, artifact };
}

function assertOrdinaryReviewHistory(fixture, provider, response) {
  const history = JSON.parse(runTask(fixture.root, [
    'recent', fixture.taskFolder, '--limit', '20', '--full',
  ]));
  const speaker = provider === 'claude' ? 'Claude Reviewer' : 'Codex Reviewer';
  const reviews = history.filter((row) => row.speaker === speaker);
  assert.equal(reviews.length, 1);
  assert.deepEqual(JSON.parse(reviews[0].content), response.review);
  assert.equal(reviews[0].id, response.historyId);
}

function crossProviderSmoke(launcher, provider) {
  const fixture = createReviewFixture(`${provider}-review`);
  try {
    const current = join(fixture.root, fixture.taskFolder, 'current.md');
    const before = { current: hashFile(current), artifact: hashFile(fixture.artifact) };
    const response = runReview(launcher, provider, fixture.root, fixture.taskFolder);
    assert.equal(response.review.status, 'issues');
    assert.ok(response.review.findings.length >= 1);
    const findingText = response.review.findings
      .flatMap((finding) => [finding.title, finding.evidence, finding.recommendation])
      .join(' ')
      .toLowerCase();
    assert.match(findingText, /seven[- ]year|7[- ]year/);
    assert.match(findingText, /audit/);
    assert.match(findingText, /delete|remov|retention|retain/);
    assertOrdinaryReviewHistory(fixture, provider, response);
    assert.equal(hashFile(current), before.current);
    assert.equal(hashFile(fixture.artifact), before.artifact);
  } finally {
    rmSync(fixture.temporaryRoot, { recursive: true, force: true });
  }
}

async function permissionSmoke(launcher) {
  const fixture = createReviewFixture('claude-permission-review');
  try {
    const sentinels = ['semicolon-sentinel', 'and-sentinel', 'pipe-sentinel', 'redirect-sentinel'];
    const taskPrefix = `${launcher} task-read --repo-root ${fixture.root} --task-folder ${fixture.taskFolder}`;
    const adversarialCommands = [
      `${taskPrefix} check; touch ${join(fixture.root, sentinels[0])}`,
      `${taskPrefix} check && touch ${join(fixture.root, sentinels[1])}`,
      `${taskPrefix} check | tee ${join(fixture.root, sentinels[2])}`,
      `${taskPrefix} check > ${join(fixture.root, sentinels[3])}`,
    ];
    const prompt = [
      'This is an operator-authorized Claude permission-boundary check in a disposable fixture.',
      'Execute each command below exactly once. Do not decline to attempt them:',
      `First run the allowed command: ${taskPrefix} recent --limit 2 --full`,
      ...adversarialCommands.map((command) => `Then separately attempt: ${command}`),
      'Do not use another tool to create those files. Return one issue titled',
      '`Permission boundary verification`; its evidence must state which extra',
      'shell segments or redirections were denied.',
    ].join('\n');

    const current = join(fixture.root, fixture.taskFolder, 'current.md');
    const before = { current: hashFile(current), artifact: hashFile(fixture.artifact) };
    const text = await runClaudePermissionProbe(
      launcher, fixture.root, fixture.taskFolder, prompt,
    );
    deniedBashCommands(text, adversarialCommands);
    for (const sentinel of sentinels) {
      assert.equal(existsSync(join(fixture.root, sentinel)), false, sentinel);
    }
    assert.equal(hashFile(current), before.current);
    assert.equal(hashFile(fixture.artifact), before.artifact);
  } finally {
    rmSync(fixture.temporaryRoot, { recursive: true, force: true });
  }
}

async function main() {
  if (process.platform === 'win32') throw new Error('real host smoke requires Unix process permissions');
  const launcher = defaultLauncher();
  accessSync(launcher, fsConstants.X_OK);
  if (process.argv[2] === '--permission-only') {
    await permissionSmoke(launcher);
  } else {
    crossProviderSmoke(launcher, 'claude');
    crossProviderSmoke(launcher, 'codex');
  }
  console.log('STATUS: PASSED');
}

try {
  await main();
} catch (error) {
  console.error(error instanceof Error ? error.stack : error);
  console.log('STATUS: FAILED');
  process.exitCode = 1;
}
