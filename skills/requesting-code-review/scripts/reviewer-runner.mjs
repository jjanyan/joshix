#!/usr/bin/env node

import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import {
  accessSync,
  closeSync,
  constants as fsConstants,
  existsSync,
  fstatSync,
  mkdtempSync,
  openSync,
  readFileSync,
  realpathSync,
  readSync,
  rmSync,
  statSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import {
  delimiter,
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import { StringDecoder } from 'node:string_decoder';
import { fileURLToPath } from 'node:url';

const FAILURE_MESSAGES = {
  unavailable: 'reviewer executable is unavailable',
  unauthorized: 'reviewer authorization failed',
  timeout: 'reviewer exceeded the wall-clock limit',
  oversized: 'reviewer output exceeded the configured limit',
  'session-unavailable': 'reviewer session is unavailable',
  nonzero: 'reviewer exited unsuccessfully',
  malformed: 'reviewer returned an invalid structured review',
  configuration: 'reviewer runner configuration is invalid',
  internal: 'reviewer runner failed locally',
};
const REVIEW_KEYS = ['findings', 'status'];
const FINDING_KEYS = [
  'criticality',
  'decisionLevel',
  'evidence',
  'id',
  'recommendation',
  'severity',
  'surface',
  'title',
];
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TASK_CONTEXT_HELPER = fileURLToPath(
  new URL('../../task-context/scripts/task-context.mjs', import.meta.url),
);
const CODEX_EXEC_HELP_FLAGS = [
  '--ignore-rules',
  '--sandbox',
  '--cd',
  '--json',
  '--output-schema',
  '--output-last-message',
];
const CODEX_RESUME_HELP_FLAGS = [
  '--ignore-rules',
  '--json',
  '--output-schema',
  '--output-last-message',
];
const CLAUDE_HELP_FLAGS = [
  '--allowedTools',
  '--disallowedTools',
  '--permission-mode',
  '--session-id',
  '--resume',
  '--output-format',
  '--json-schema',
];
const PROVIDER_HELP_TIMEOUT_MS = 5000;
const PROVIDER_HELP_MAX_BYTES = 64 * 1024;
const PROVIDER_CANDIDATE_LIMIT = 32;

function executableNames(command, platform, pathExt) {
  if (platform !== 'win32' || extname(command)) return [command];
  const extensions = (pathExt || '.COM;.EXE;.BAT;.CMD')
    .split(';')
    .filter(Boolean);
  return extensions.map((extension) => `${command}${extension.toLowerCase()}`);
}

function pathCandidates(command, {
  path = process.env.PATH ?? '',
  pathExt = process.env.PATHEXT,
  platform = process.platform,
} = {}) {
  const candidates = [];
  const seen = new Set();
  const pathDelimiter = platform === 'win32' ? ';' : delimiter;
  for (const directory of path.split(pathDelimiter)) {
    if (candidates.length >= PROVIDER_CANDIDATE_LIMIT) break;
    for (const name of executableNames(command, platform, pathExt)) {
      const candidate = resolve(directory || '.', name);
      try {
        accessSync(candidate, fsConstants.X_OK);
        if (!statSync(candidate).isFile()) continue;
        const identity = realpathSync(candidate);
        const key = platform === 'win32' ? identity.toLowerCase() : identity;
        if (seen.has(key)) continue;
        seen.add(key);
        candidates.push(candidate);
      } catch {
        // Missing, non-executable, and dangling PATH entries are not candidates.
      }
      if (candidates.length >= PROVIDER_CANDIDATE_LIMIT) break;
    }
  }
  return candidates;
}

function windowsNpmShimLauncher(candidate) {
  const text = readBoundedUtf8(candidate, PROVIDER_HELP_MAX_BYTES);
  if (text === null) return null;
  const targets = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line.includes('%_prog%') || !line.includes('%*')) continue;
    const match = line.match(/%dp0%[\\/]([^"\r\n]+?\.(?:c|m)?js)["']?/i);
    if (match) targets.push(match[1]);
  }
  const uniqueTargets = [...new Set(targets)];
  if (uniqueTargets.length !== 1) return null;

  const script = resolve(dirname(candidate), uniqueTargets[0].replace(/[\\/]+/g, sep));
  const local = relative(dirname(candidate), script);
  if (local === '..' || local.startsWith(`..${sep}`) || isAbsolute(local)) return null;
  try {
    if (!statSync(script).isFile()) return null;
  } catch {
    return null;
  }
  return { command: process.execPath, prefixArgs: [script], source: candidate };
}

function candidateLauncher(candidate, platform) {
  const extension = extname(candidate).toLowerCase();
  if (platform === 'win32' && ['.bat', '.cmd'].includes(extension)) {
    return windowsNpmShimLauncher(candidate);
  }
  return { command: candidate, prefixArgs: [], source: candidate };
}

function helpHasFlags(launcher, args, flags) {
  const result = spawnSync(launcher.command, [...launcher.prefixArgs, ...args], {
    encoding: 'utf8',
    maxBuffer: PROVIDER_HELP_MAX_BYTES,
    shell: false,
    timeout: PROVIDER_HELP_TIMEOUT_MS,
    windowsHide: true,
  });
  if (result.error || result.status !== 0) return false;
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  const optionTokens = new Set(output.match(/--[a-z0-9][a-z0-9-]*/gi) ?? []);
  return flags.every((flag) => optionTokens.has(flag));
}

function codexCandidateIsCompatible(launcher) {
  return helpHasFlags(launcher, ['exec', '--help'], CODEX_EXEC_HELP_FLAGS)
    && helpHasFlags(launcher, [
      'exec', '--sandbox', 'read-only', '--cd', process.cwd(),
      'resume', '--help',
    ], CODEX_RESUME_HELP_FLAGS);
}

function providerCandidateIsCompatible(provider, launcher) {
  return provider === 'codex'
    ? codexCandidateIsCompatible(launcher)
    : helpHasFlags(launcher, ['--help'], CLAUDE_HELP_FLAGS);
}

export function discoverDefaultReviewerBinary(
  provider,
  environment = process.env,
  platform = process.platform,
) {
  const candidates = pathCandidates(provider, {
    path: environment.PATH ?? '',
    pathExt: environment.PATHEXT,
    platform,
  });
  for (const candidate of candidates) {
    const launcher = candidateLauncher(candidate, platform);
    if (launcher && providerCandidateIsCompatible(provider, launcher)) {
      return { binary: launcher.command, candidates, launcher };
    }
  }
  return { binary: null, candidates, launcher: null };
}

export function resolveDefaultReviewerBinary(provider, environment = process.env) {
  return discoverDefaultReviewerBinary(provider, environment).binary;
}

function claudeReadTools() {
  return [
    'Read', 'Grep', 'Glob',
    `Bash(${TASK_CONTEXT_HELPER} recent:*)`,
    `Bash(${TASK_CONTEXT_HELPER} since-id:*)`,
    `Bash(${TASK_CONTEXT_HELPER} since-time:*)`,
    `Bash(${TASK_CONTEXT_HELPER} search:*)`,
    `Bash(${TASK_CONTEXT_HELPER} get:*)`,
    `Bash(${TASK_CONTEXT_HELPER} check:*)`,
  ].join(',');
}

function claudeProfile({ prompt, schemaText, sessionId, resume }) {
  return [
    '-p', prompt,
    ...(resume ? ['--resume', sessionId] : ['--session-id', sessionId]),
    '--allowedTools', claudeReadTools(),
    '--disallowedTools', 'Write,Edit,MultiEdit,NotebookEdit,Task,Agent',
    '--permission-mode', 'dontAsk',
    '--verbose',
    '--output-format', 'stream-json',
    '--json-schema', schemaText,
  ];
}

function readBoundedUtf8(file, maxBytes) {
  const descriptor = openSync(file, 'r');
  try {
    const stats = fstatSync(descriptor);
    if (!stats.isFile() || stats.size > maxBytes) return null;
    const buffer = Buffer.allocUnsafe(maxBytes + 1);
    let length = 0;
    while (length < buffer.length) {
      const count = readSync(descriptor, buffer, length, buffer.length - length, null);
      if (count === 0) break;
      length += count;
    }
    if (length > maxBytes) return null;
    return buffer.subarray(0, length).toString('utf8');
  } finally {
    closeSync(descriptor);
  }
}

function claudeCompatibleSchema(schemaText) {
  const schema = JSON.parse(schemaText);
  delete schema.$schema;
  return JSON.stringify(schema);
}

function codexProfile({ prompt, repoRoot, schemaFile, finalFile, sessionId }) {
  if (sessionId) {
    return [
      'exec', '--sandbox', 'read-only', '--cd', repoRoot,
      'resume', '--ignore-rules',
      '--json', '--output-schema', schemaFile,
      '--output-last-message', finalFile,
      sessionId, prompt,
    ];
  }
  return [
    'exec', '--ignore-rules',
    '--sandbox', 'read-only', '--cd', repoRoot,
    '--json', '--output-schema', schemaFile,
    '--output-last-message', finalFile,
    prompt,
  ];
}

function sameKeys(value, expected) {
  return JSON.stringify(Object.keys(value).sort()) === JSON.stringify(expected);
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function isValidReview(review) {
  if (!review || typeof review !== 'object' || Array.isArray(review)) return false;
  if (!sameKeys(review, REVIEW_KEYS)) return false;
  if (!['approved', 'issues'].includes(review.status) || !Array.isArray(review.findings)) {
    return false;
  }
  return review.findings.every((finding) => (
    finding
    && typeof finding === 'object'
    && !Array.isArray(finding)
    && sameKeys(finding, FINDING_KEYS)
    && isNonEmptyString(finding.id)
    && isNonEmptyString(finding.title)
    && ['critical', 'important', 'minor'].includes(finding.severity)
    && isNonEmptyString(finding.criticality)
    && isNonEmptyString(finding.surface)
    && ['dev', 'policy', 'product'].includes(finding.decisionLevel)
    && isNonEmptyString(finding.evidence)
    && isNonEmptyString(finding.recommendation)
  ));
}

function normalizeJson(value) {
  if (Array.isArray(value)) return value.map(normalizeJson);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, normalizeJson(value[key])]),
  );
}

function sameJsonStructure(left, right) {
  return JSON.stringify(normalizeJson(left)) === JSON.stringify(normalizeJson(right));
}

function parseCandidate(value) {
  if (typeof value !== 'string') return value;
  return JSON.parse(value);
}

function findReview(value) {
  if (isValidReview(value)) return value;
  if (!value || typeof value !== 'object') return null;
  for (const key of ['structured_output', 'structuredOutput', 'review', 'result']) {
    if (!(key in value)) continue;
    let candidate;
    try {
      candidate = parseCandidate(value[key]);
    } catch {
      continue;
    }
    const found = findReview(candidate);
    if (found) return found;
  }
  return null;
}

function positiveInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new Error(`${name} requires a positive integer.`);
  }
  return parsed;
}

function parseArgs(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!name?.startsWith('--') || value === undefined || value.startsWith('--')) {
      throw new Error('Every option requires one value.');
    }
    if (values.has(name)) throw new Error(`Duplicate option: ${name}`);
    values.set(name, value);
  }
  const required = [
    '--provider',
    '--repo-root',
    '--prompt-file',
    '--schema-file',
    '--timeout-ms',
    '--max-events',
    '--max-output-bytes',
    '--max-review-bytes',
  ];
  const allowed = new Set([...required, '--session-id']);
  const unknown = [...values.keys()].filter((name) => !allowed.has(name));
  if (unknown.length > 0) throw new Error(`Unknown option: ${unknown[0]}`);
  for (const name of required) {
    if (!values.has(name)) throw new Error(`Missing option: ${name}`);
  }

  const provider = values.get('--provider');
  if (!['claude', 'codex'].includes(provider)) {
    throw new Error('--provider must be claude or codex.');
  }
  const repoRoot = values.get('--repo-root');
  const promptFile = values.get('--prompt-file');
  const schemaFile = values.get('--schema-file');
  const sessionId = values.get('--session-id') ?? null;
  if (sessionId !== null && !UUID_PATTERN.test(sessionId)) {
    throw new Error('--session-id requires a UUID.');
  }
  for (const [name, path] of [
    ['--repo-root', repoRoot],
    ['--prompt-file', promptFile],
    ['--schema-file', schemaFile],
  ]) {
    if (!isAbsolute(path)) throw new Error(`${name} requires an absolute path.`);
    if (!existsSync(path)) throw new Error(`${name} does not exist.`);
  }
  if (!statSync(repoRoot).isDirectory()) {
    throw new Error('--repo-root requires a directory.');
  }
  for (const [name, path] of [
    ['--prompt-file', promptFile],
    ['--schema-file', schemaFile],
  ]) {
    if (!statSync(path).isFile()) throw new Error(`${name} requires a regular file.`);
  }
  return {
    provider,
    repoRoot,
    promptFile,
    schemaFile,
    sessionId,
    timeoutMs: positiveInteger(values.get('--timeout-ms'), '--timeout-ms'),
    maxEvents: positiveInteger(values.get('--max-events'), '--max-events'),
    maxOutputBytes: positiveInteger(values.get('--max-output-bytes'), '--max-output-bytes'),
    maxReviewBytes: positiveInteger(values.get('--max-review-bytes'), '--max-review-bytes'),
  };
}

function failure(kind, attempts) {
  return {
    ok: false,
    attempts,
    failure: { kind, message: FAILURE_MESSAGES[kind] },
  };
}

function classifyNonzero(output, hadSession) {
  if (
    hadSession
    && /(?:session|conversation|thread).*(?:not found|missing|expired|invalid)|unknown (?:session|conversation|thread)/i.test(output)
  ) {
    return { kind: 'session-unavailable', retryable: true };
  }
  if (/auth(?:entication|orization)?|unauthorized|permission denied|log in|login/i.test(output)) {
    return { kind: 'unauthorized', retryable: false };
  }
  const retryable = /temporary|temporarily|overload|rate.?limit|try again|connection reset/i.test(output);
  return { kind: 'nonzero', retryable };
}

function parseClaudeReview(stdout) {
  let malformedEvent = false;
  let review = null;
  for (const line of stdout.split('\n').filter(Boolean)) {
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      malformedEvent = true;
      continue;
    }
    review = findReview(event) ?? review;
  }
  return malformedEvent ? null : review;
}

async function runAttempt(options, prompt, schemaText) {
  const { provider } = options;
  let observedSessionId = provider === 'claude'
    ? (options.sessionId ?? randomUUID())
    : options.sessionId;
  let temporaryDirectory = null;
  let finalFile = null;
  if (provider === 'codex') {
    temporaryDirectory = mkdtempSync(join(tmpdir(), 'joshix-review-'));
    finalFile = join(temporaryDirectory, 'review.json');
  }

  const { launcher } = options;
  const args = provider === 'claude'
    ? claudeProfile({
      prompt,
      schemaText: claudeCompatibleSchema(schemaText),
      sessionId: observedSessionId,
      resume: Boolean(options.sessionId),
    })
    : codexProfile({
      prompt,
      repoRoot: options.repoRoot,
      schemaFile: options.schemaFile,
      finalFile,
      sessionId: options.sessionId,
    });

  try {
    const result = await new Promise((resolvePromise) => {
      let stdout = '';
      let stderr = '';
      let pendingStdout = '';
      let eventCount = 0;
      let malformedEventStream = false;
      let rawBytes = 0;
      let terminalFailure = null;
      let spawnError = null;
      let child;
      const stdoutDecoder = new StringDecoder('utf8');
      const stderrDecoder = new StringDecoder('utf8');

      function stop(kind, retryable = false) {
        if (terminalFailure) return;
        terminalFailure = { kind, retryable };
        child?.kill('SIGKILL');
      }

      function processEventLine(line) {
        if (line.length === 0) return;
        eventCount += 1;
        if (eventCount > options.maxEvents) {
          stop('oversized');
          return;
        }
        try {
          const event = JSON.parse(line);
          if (provider === 'codex' && event.type === 'thread.started') {
            if (!UUID_PATTERN.test(event.thread_id)) {
              stop('malformed', true);
              return;
            }
            if (observedSessionId && observedSessionId !== event.thread_id) {
              stop('malformed', true);
              return;
            }
            observedSessionId = event.thread_id;
          }
        } catch {
          malformedEventStream = true;
        }
      }

      try {
        child = spawn(launcher.command, [...launcher.prefixArgs, ...args], {
          cwd: options.repoRoot,
          shell: false,
          stdio: ['ignore', 'pipe', 'pipe'],
        });
      } catch (error) {
        resolvePromise({ spawnError: error });
        return;
      }

      function acceptStdout(text) {
        stdout += text;
        pendingStdout += text;
        const lines = pendingStdout.split('\n');
        pendingStdout = lines.pop();
        for (const line of lines) processEventLine(line);
      }

      function acceptStderr(text) {
        stderr += text;
      }

      const timer = setTimeout(() => stop('timeout'), options.timeoutMs);
      child.stdout.on('data', (chunk) => {
        rawBytes += chunk.length;
        if (rawBytes > options.maxOutputBytes) {
          stop('oversized');
          return;
        }
        acceptStdout(stdoutDecoder.write(chunk));
      });
      child.stderr.on('data', (chunk) => {
        rawBytes += chunk.length;
        if (rawBytes > options.maxOutputBytes) {
          stop('oversized');
          return;
        }
        acceptStderr(stderrDecoder.write(chunk));
      });
      child.on('error', (error) => { spawnError = error; });
      child.on('close', (code, signal) => {
        clearTimeout(timer);
        acceptStdout(stdoutDecoder.end());
        acceptStderr(stderrDecoder.end());
        processEventLine(pendingStdout);
        resolvePromise({
          code,
          signal,
          stdout,
          stderr,
          terminalFailure,
          spawnError,
          malformedEventStream,
        });
      });
    });

    if (result.terminalFailure) return result.terminalFailure;
    if (result.spawnError) {
      return {
        kind: result.spawnError.code === 'ENOENT' ? 'unavailable' : 'internal',
        retryable: false,
      };
    }
    if (result.signal || !Number.isInteger(result.code)) {
      return { kind: 'nonzero', retryable: false };
    }
    let review;
    if (provider === 'codex') {
      if (result.malformedEventStream) return { kind: 'malformed', retryable: true };
      let finalFailure = null;
      if (!existsSync(finalFile)) {
        finalFailure = { kind: 'malformed', retryable: true };
      } else {
        const finalText = readBoundedUtf8(finalFile, options.maxReviewBytes);
        if (finalText === null) {
          finalFailure = { kind: 'oversized', retryable: false };
        } else {
          try {
            review = JSON.parse(finalText);
          } catch {
            finalFailure = { kind: 'malformed', retryable: true };
          }
        }
      }
      if (!finalFailure && !isValidReview(review)) {
        finalFailure = { kind: 'malformed', retryable: true };
      }
      if (finalFailure) {
        if (result.code !== 0 && finalFailure.kind !== 'oversized') {
          return classifyNonzero(`${result.stdout}\n${result.stderr}`, Boolean(options.sessionId));
        }
        return finalFailure;
      }
    } else {
      if (result.code !== 0) {
        return classifyNonzero(`${result.stdout}\n${result.stderr}`, Boolean(options.sessionId));
      }
      if (result.malformedEventStream) return { kind: 'malformed', retryable: true };
      review = parseClaudeReview(result.stdout);
    }
    if (!isValidReview(review)) return { kind: 'malformed', retryable: true };
    if (!observedSessionId || !UUID_PATTERN.test(observedSessionId)) {
      return { kind: 'malformed', retryable: true };
    }
    if (Buffer.byteLength(JSON.stringify(review)) > options.maxReviewBytes) {
      return { kind: 'oversized', retryable: false };
    }
    return {
      ok: true,
      sessionId: observedSessionId,
      review,
      ...(result.code !== 0 ? { diagnostic: { providerExitCode: result.code } } : {}),
    };
  } finally {
    if (temporaryDirectory) {
      rmSync(temporaryDirectory, { recursive: true, force: true });
    }
  }
}

async function main() {
  let options;
  let prompt;
  let schemaText;
  let schema;
  try {
    options = parseArgs(process.argv.slice(2));
    prompt = readFileSync(options.promptFile, 'utf8');
    schemaText = readFileSync(options.schemaFile, 'utf8');
    schema = JSON.parse(schemaText);
  } catch {
    process.stdout.write(`${JSON.stringify({
      provider: options?.provider ?? 'unknown',
      ...failure('configuration', 0),
    })}\n`);
    process.exitCode = 1;
    return;
  }

  let canonicalSchema;
  try {
    canonicalSchema = JSON.parse(readFileSync(
      new URL('../review-result.schema.json', import.meta.url),
      'utf8',
    ));
  } catch {
    process.stdout.write(`${JSON.stringify({
      provider: options.provider,
      ...failure('internal', 0),
    })}\n`);
    process.exitCode = 1;
    return;
  }
  if (!sameJsonStructure(schema, canonicalSchema)) {
    process.stdout.write(`${JSON.stringify({
      provider: options.provider,
      ...failure('configuration', 0),
    })}\n`);
    process.exitCode = 1;
    return;
  }

  const override = options.provider === 'claude'
    ? process.env.JOSHIX_REVIEWER_CLAUDE_BIN
    : process.env.JOSHIX_REVIEWER_CODEX_BIN;
  const discovery = override
    ? { launcher: { command: override, prefixArgs: [], source: override } }
    : discoverDefaultReviewerBinary(options.provider);
  if (!discovery.launcher) {
    process.stdout.write(`${JSON.stringify({
      provider: options.provider,
      ...failure('unavailable', 0),
    })}\n`);
    process.exitCode = 1;
    return;
  }
  options = { ...options, launcher: discovery.launcher };

  try {
    let sessionMode = options.sessionId ? 'resumed' : 'started';
    for (let attempts = 1; attempts <= 2; attempts += 1) {
      const result = await runAttempt(options, prompt, schemaText);
      if (result.ok) {
        process.stdout.write(`${JSON.stringify({
          ok: true,
          provider: options.provider,
          attempts,
          session: { id: result.sessionId, mode: sessionMode },
          review: result.review,
          ...(result.diagnostic ? { diagnostic: result.diagnostic } : {}),
        })}\n`);
        return;
      }
      if (result.kind === 'session-unavailable' && options.sessionId && attempts === 1) {
        options = { ...options, sessionId: null };
        sessionMode = 'replaced';
        continue;
      }
      if (!result.retryable || attempts === 2) {
        process.stdout.write(`${JSON.stringify({
          provider: options.provider,
          ...failure(result.kind, attempts),
        })}\n`);
        process.exitCode = 1;
        return;
      }
    }
  } catch {
    process.stdout.write(`${JSON.stringify({
      provider: options?.provider ?? 'unknown',
      ...failure('internal', 0),
    })}\n`);
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
