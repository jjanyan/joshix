import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { discoverDefaultReviewerBinary } from '../../skills/requesting-code-review/scripts/reviewer-runner.mjs';

function help(binary, args) {
  return spawnSync(binary, args, { encoding: 'utf8' });
}

function isUnavailable(result) {
  return result.error?.code === 'ENOENT' || /\bENOENT\b/.test(result.stderr ?? '');
}

test('installed Claude CLI supports the pinned read-only profile', (context) => {
  const discovery = discoverDefaultReviewerBinary('claude');
  if (discovery.candidates.length === 0) {
    context.skip('Claude CLI is not installed');
    return;
  }
  assert.notEqual(
    discovery.binary,
    null,
    `Installed Claude candidates do not support the pinned profile: ${discovery.candidates.join(', ')}`,
  );
  const result = help(
    discovery.launcher.command,
    [...discovery.launcher.prefixArgs, '--help'],
  );
  if (isUnavailable(result)) {
    context.skip('Claude CLI is not installed');
    return;
  }
  assert.equal(result.status, 0, result.stderr);
  const output = `${result.stdout}\n${result.stderr}`;
  for (const flag of [
    '--allowedTools',
    '--disallowedTools',
    '--permission-mode',
    '--session-id',
    '--resume',
    '--output-format',
    '--json-schema',
  ]) assert.match(output, new RegExp(flag.replaceAll('-', '\\-')));
});

test('installed Codex CLI supports the pinned read-only profile', (context) => {
  const discovery = discoverDefaultReviewerBinary('codex');
  if (discovery.candidates.length === 0) {
    context.skip('Codex CLI is not installed');
    return;
  }
  assert.notEqual(
    discovery.binary,
    null,
    `Installed Codex candidates do not support the pinned profile: ${discovery.candidates.join(', ')}`,
  );
  const result = help(
    discovery.launcher.command,
    [...discovery.launcher.prefixArgs, 'exec', '--help'],
  );
  assert.equal(result.status, 0, result.stderr);
  const output = `${result.stdout}\n${result.stderr}`;
  for (const flag of [
    '--ignore-rules',
    '--sandbox',
    '--cd',
    '--json',
    '--output-schema',
    '--output-last-message',
  ]) assert.match(output, new RegExp(flag.replaceAll('-', '\\-')));

  const resume = help(
    discovery.launcher.command,
    [
      ...discovery.launcher.prefixArgs,
      'exec', '--sandbox', 'read-only', '--cd', process.cwd(),
      'resume', '--help',
    ],
  );
  assert.equal(resume.status, 0, resume.stderr);
  const resumeOutput = `${resume.stdout}\n${resume.stderr}`;
  for (const flag of [
    '--ignore-rules',
    '--json',
    '--output-schema',
    '--output-last-message',
  ]) assert.match(resumeOutput, new RegExp(flag.replaceAll('-', '\\-')));
});
