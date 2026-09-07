#!/usr/bin/env node

import { spawn, spawnSync } from 'node:child_process';
import {
  existsSync,
  lstatSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import {
  isAbsolute,
  join,
  normalize,
  relative,
  resolve,
  sep,
} from 'node:path';
import { fileURLToPath } from 'node:url';

const INSTALLED_EXECUTABLES = null;
const SQLITE_WARNING = 'SQLite is an experimental feature and might change at any time';
let DatabaseSync;

const REQUIRED_OPTIONS = new Set(['--provider', '--repo-root', '--task-folder']);
const PROVIDERS = new Set(['claude', 'codex']);
const MAX_REVIEW_BYTES = 512 * 1024;
const MAX_DIAGNOSTIC_BYTES = 16 * 1024;
const TERMINATION_GRACE_MS = 2_000;
const TIMESTAMP_DEFAULT = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
const VERSION_ONE_COLUMNS = ['id', 'created_at', 'speaker', 'content'];
const VERSION_TWO_COLUMNS = [...VERSION_ONE_COLUMNS, 'idempotency_key'];
const CANONICAL_INSTRUCTION = [
  'Challenge assumptions in the spec, plan, and implementation when they create concrete risk.',
  'Read the shared chat and repository guidance.',
  'Establish the latest applicable owner decisions, accepted limitations, and superseded choices before reviewing the current artifact.',
  'Evaluate within that scope; prior approval is not proof of correctness, but a knowingly accepted limitation is not an overlooked defect.',
  'Before reopening a settled issue, identify the prior decision and new evidence that its resolution was incorrect, invalidated by later changes, or left a defect outside the accepted limitation.',
  'Repeating an accepted risk or preferring another design is insufficient.',
  'Initial spec and plan reviews cover the artifact.',
  'Follow-ups examine corrections and their consequences, including interactions with unchanged parts; do not restart broad review because wording was clarified or relitigate unrelated settled issues without new evidence.',
  "Review code for concrete correctness risks, regressions, and missing requirements throughout the task's scope, including outside the latest correction.",
  'Read the existing history as needed; no mandatory decision recap or new decision artifact is required.',
].join(' ');

export const REVIEW_SCHEMA = Object.freeze({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  type: 'object',
  additionalProperties: false,
  required: ['status', 'findings'],
  properties: {
    status: { enum: ['approved', 'issues'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'severity', 'evidence', 'recommendation'],
        properties: {
          title: { type: 'string', minLength: 1 },
          severity: { type: 'string', minLength: 1 },
          evidence: { type: 'string', minLength: 1 },
          recommendation: { type: 'string', minLength: 1 },
        },
      },
    },
  },
  allOf: [{
    if: { properties: { status: { const: 'approved' } } },
    then: { properties: { findings: { type: 'array', maxItems: 0 } } },
    else: { properties: { findings: { type: 'array', minItems: 1 } } },
  }],
});

class BridgeError extends Error {
  constructor(kind, message) {
    super(message);
    this.kind = kind;
  }
}

async function loadDatabaseSync() {
  const originalEmitWarning = process.emitWarning;
  function filteredEmitWarning(warning, typeOrOptions, code, ctor) {
    const message = warning instanceof Error ? warning.message : String(warning);
    const type = warning instanceof Error
      ? warning.name
      : typeof typeOrOptions === 'string'
        ? typeOrOptions
        : typeOrOptions?.type;
    if (type === 'ExperimentalWarning' && message === SQLITE_WARNING) return;
    return originalEmitWarning.call(process, warning, typeOrOptions, code, ctor);
  }

  process.emitWarning = filteredEmitWarning;
  try {
    ({ DatabaseSync } = await import('node:sqlite'));
  } finally {
    if (process.emitWarning === filteredEmitWarning) {
      process.emitWarning = originalEmitWarning;
    }
  }
}

function exactKeys(value, expected) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return JSON.stringify(actual) === JSON.stringify(wanted);
}

export function validReview(value) {
  if (!exactKeys(value, ['status', 'findings'])) return false;
  if (!['approved', 'issues'].includes(value.status) || !Array.isArray(value.findings)) {
    return false;
  }
  if (value.status === 'approved' && value.findings.length !== 0) return false;
  if (value.status === 'issues' && value.findings.length === 0) return false;
  return value.findings.every((finding) => (
    exactKeys(finding, ['title', 'severity', 'evidence', 'recommendation'])
    && ['title', 'severity', 'evidence', 'recommendation'].every((field) => (
      typeof finding[field] === 'string' && finding[field].length > 0
    ))
  ));
}

function noControlCharacters(value, label) {
  if (typeof value !== 'string' || value.includes('\0') || value.includes('\n') || value.includes('\r')) {
    throw new BridgeError('invalid-request', `${label} contains an invalid character`);
  }
  return value;
}

function permissionSafePath(value, label) {
  noControlCharacters(value, label);
  if (/[\s,]/u.test(value)) {
    throw new BridgeError('invalid-request', `${label} cannot contain whitespace or commas`);
  }
  return value;
}

function inside(parent, child) {
  const local = relative(parent, child);
  return local === '' || (
    local !== '..'
    && !local.startsWith(`..${sep}`)
    && !isAbsolute(local)
  );
}

function canonicalRepository(input) {
  permissionSafePath(input, 'repository root');
  if (!isAbsolute(input)) throw new BridgeError('invalid-request', '--repo-root must be absolute');
  let stats;
  try {
    stats = lstatSync(input);
  } catch {
    throw new BridgeError('invalid-request', 'repository root does not exist');
  }
  if (stats.isSymbolicLink() || !stats.isDirectory()) {
    throw new BridgeError('invalid-request', 'repository root must be a non-symlink directory');
  }
  const canonical = realpathSync(input);
  if (canonical !== resolve(input) || !existsSync(join(canonical, '.git'))) {
    throw new BridgeError('invalid-request', 'repository root must be a canonical Git top level');
  }
  return canonical;
}

function safeTaskFolder(repoRoot, folder) {
  permissionSafePath(folder, 'task folder');
  if (isAbsolute(folder)) throw new BridgeError('invalid-request', 'task folder must be repository-relative');
  const normalized = normalize(folder);
  if (
    normalized !== folder
    || !folder.startsWith(`.joshix${sep}tasks${sep}`)
    || folder.split(/[\\/]/).includes('..')
  ) {
    throw new BridgeError('invalid-request', 'task folder must be under .joshix/tasks');
  }
  const task = resolve(repoRoot, folder);
  if (!inside(repoRoot, task)) throw new BridgeError('invalid-request', 'task folder escaped repository');

  let cursor = repoRoot;
  for (const segment of folder.split(/[\\/]/)) {
    cursor = join(cursor, segment);
    if (existsSync(cursor) && lstatSync(cursor).isSymbolicLink()) {
      throw new BridgeError('invalid-request', 'task folder must not traverse symbolic links');
    }
  }
  return task;
}

function schemaState(db) {
  const integrity = db.prepare('PRAGMA integrity_check').get().integrity_check;
  const version = db.prepare('PRAGMA user_version').get().user_version;
  const columns = db.prepare('PRAGMA table_info(messages)').all().map(({ name }) => name);
  const indexColumns = db.prepare('PRAGMA index_info(messages_created_at_idx)').all()
    .map(({ name }) => name);
  const tableSql = db.prepare(
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'messages'",
  ).get()?.sql ?? '';
  return {
    integrity,
    version,
    columns,
    indexColumns,
    tableSql,
  };
}

function knownTaskSchema(state) {
  if (
    state.integrity !== 'ok'
    || JSON.stringify(state.indexColumns) !== JSON.stringify(['created_at'])
    || !state.tableSql.includes(TIMESTAMP_DEFAULT)
  ) return false;
  if (state.version === 1) {
    return JSON.stringify(state.columns) === JSON.stringify(VERSION_ONE_COLUMNS);
  }
  if (state.version === 2) {
    return JSON.stringify(state.columns) === JSON.stringify(VERSION_TWO_COLUMNS);
  }
  return false;
}

function openTaskDatabase(repoRoot, taskFolder, { readOnly = false } = {}) {
  const task = safeTaskFolder(repoRoot, taskFolder);
  const databasePath = join(task, 'history.sqlite');
  if (!existsSync(databasePath) || lstatSync(databasePath).isSymbolicLink()) {
    throw new BridgeError('history-read', 'task history database is missing or symbolic');
  }
  let db;
  try {
    db = new DatabaseSync(databasePath, { readOnly });
    if (!knownTaskSchema(schemaState(db))) {
      throw new BridgeError('history-read', 'task history database failed integrity or schema validation');
    }
    return db;
  } catch (error) {
    db?.close();
    if (error instanceof BridgeError) throw error;
    throw new BridgeError('history-read', error.message);
  }
}

function parseExactOptions(argv, required) {
  if (argv.length % 2 !== 0) {
    throw new BridgeError('invalid-request', 'every option requires one value');
  }
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!required.has(name)) throw new BridgeError('invalid-request', `unknown option: ${name}`);
    if (values.has(name)) throw new BridgeError('invalid-request', `duplicate option: ${name}`);
    if (typeof value !== 'string' || value.startsWith('--')) {
      throw new BridgeError('invalid-request', `missing value for ${name}`);
    }
    values.set(name, value);
  }
  for (const name of required) {
    if (!values.has(name)) throw new BridgeError('invalid-request', `missing option: ${name}`);
  }
  return values;
}

export function parseReviewOptions(argv) {
  const values = parseExactOptions(argv, REQUIRED_OPTIONS);
  const provider = values.get('--provider');
  if (!PROVIDERS.has(provider)) throw new BridgeError('invalid-request', 'unknown provider');
  const repoRoot = canonicalRepository(values.get('--repo-root'));
  const taskFolder = values.get('--task-folder');
  safeTaskFolder(repoRoot, taskFolder);
  return { provider, repoRoot, taskFolder };
}

export function sanitizedProviderEnvironment(environment = process.env) {
  const clean = { ...environment };
  delete clean.NODE_OPTIONS;
  delete clean.NODE_PATH;
  for (const key of Object.keys(clean)) {
    if (key.startsWith('GIT_')) delete clean[key];
  }
  Object.assign(clean, {
    GIT_OPTIONAL_LOCKS: '0',
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_TERMINAL_PROMPT: '0',
    GIT_CONFIG_COUNT: '2',
    GIT_CONFIG_KEY_0: 'core.fsmonitor',
    GIT_CONFIG_VALUE_0: 'false',
    GIT_CONFIG_KEY_1: 'core.hooksPath',
    GIT_CONFIG_VALUE_1: '/dev/null',
  });
  return clean;
}

export function sanitizedGitEnvironment(environment = process.env) {
  return sanitizedProviderEnvironment(environment);
}

export function reviewPrompt({ installedExecutable, repoRoot, taskFolder, schema }) {
  const taskPrefix = `${installedExecutable} task-read --repo-root ${repoRoot} --task-folder ${taskFolder}`;
  const gitPrefix = `${installedExecutable} git-read --repo-root ${repoRoot}`;
  return [
    CANONICAL_INSTRUCTION,
    '',
    'Mechanical metadata:',
    `Repository root: ${repoRoot}`,
    `Task folder: ${taskFolder}`,
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
    'Repository and task access are read-only.',
    `Response schema: ${JSON.stringify(schema)}`,
  ].join('\n');
}

export function claudeAllowedTools({ installedExecutable, repoRoot, taskFolder }) {
  const taskPrefix = `${installedExecutable} task-read --repo-root ${repoRoot} --task-folder ${taskFolder}`;
  const gitPrefix = `${installedExecutable} git-read --repo-root ${repoRoot}`;
  return [
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
  ].join(',');
}

export function claudeArguments({
  installedExecutable,
  repoRoot,
  taskFolder,
  prompt,
  providerSchema,
}) {
  return [
    '-p', prompt,
    '--restricted',
    '--tools', 'Read,Grep,Glob,Bash',
    '--allowedTools', claudeAllowedTools({ installedExecutable, repoRoot, taskFolder }),
    '--disallowedTools', 'Write,Edit,MultiEdit,NotebookEdit,Task,Agent',
    '--permission-mode', 'dontAsk',
    '--permission-prompts', 'none',
    '--no-session-persistence',
    '--verbose',
    '--output-format', 'stream-json',
    '--json-schema', JSON.stringify(providerSchema),
  ];
}

function appendDiagnosticTail(current, chunk) {
  const combined = Buffer.concat([current, Buffer.from(chunk)]);
  return combined.length <= MAX_DIAGNOSTIC_BYTES
    ? combined
    : combined.subarray(combined.length - MAX_DIAGNOSTIC_BYTES);
}

function diagnosticTextTail(buffer, limit) {
  // Re-encode once so replacement characters and multibyte boundaries count
  // toward the returned UTF-8 budget, even if a retained tail starts mid-codepoint.
  const text = Buffer.from(buffer.toString('utf8').trim());
  let start = Math.max(0, text.length - limit);
  while (start < text.length && (text[start] & 0xc0) === 0x80) start += 1;
  return text.subarray(start).toString('utf8');
}

function failureDiagnostics(stdout, stderr, limit = MAX_DIAGNOSTIC_BYTES) {
  const sources = [['stdout', stdout], ['stderr', stderr]]
    .filter(([, tail]) => tail.toString('utf8').trim());
  if (!sources.length) return '';
  const labelBytes = sources.reduce((total, [name]) => total + Buffer.byteLength(`${name}:\n`), 0)
    + (sources.length - 1) * 2;
  const available = limit - labelBytes;
  const budgets = sources.map(([, tail]) => Math.min(tail.length, Math.floor(available / sources.length)));
  let remaining = available - budgets.reduce((total, size) => total + size, 0);
  for (let index = 0; index < sources.length; index += 1) {
    const extra = Math.min(remaining, sources[index][1].length - budgets[index]);
    budgets[index] += extra;
    remaining -= extra;
  }
  return sources.map(([name, tail], index) => `${name}:\n${diagnosticTextTail(tail, budgets[index])}`)
    .join('\n\n');
}

function providerFailure({ spawnError, exitCode, signal, stdoutTail, diagnosticTail, terminalError }) {
  const signalSuffix = signal ? ` (provider terminated by ${signal})` : '';
  const message = failureDiagnostics(stdoutTail, diagnosticTail,
    MAX_DIAGNOSTIC_BYTES - Buffer.byteLength(signalSuffix));
  if (spawnError) {
    const unavailable = new Set(['ENOENT', 'EACCES', 'ENOEXEC']).has(spawnError.code);
    return {
      ok: false,
      kind: unavailable ? 'unavailable' : 'internal',
      message: spawnError.message,
    };
  }
  if (signal) {
    return {
      ok: false,
      kind: 'provider-exit',
      message: message
        ? `${message}${signalSuffix}`
        : `provider terminated by ${signal}`,
    };
  }
  const authentication = /authentication required|not logged in|please run \/login|unauthorized/i;
  if ([stdoutTail, diagnosticTail].some((tail) => authentication.test(tail.toString('utf8')))) {
    return {
      ok: false, kind: 'authentication', message, exitCode,
      guidance: 'Authentication failed. Was this launcher the only command in its shell call? '
        + 'If not, retry it once as a standalone command. If it was already standalone, '
        + 'or the standalone retry fails, stop and report the error to the user; '
        + 'the account may actually be logged out.',
    };
  }
  return {
    ok: false,
    kind: 'provider-exit',
    message: message || (terminalError ? 'provider reported a terminal error' : `provider exited ${exitCode}`),
    ...(Number.isInteger(exitCode) ? { exitCode } : {}),
  };
}

function terminalFailure(event) {
  if (!event || typeof event !== 'object') return null;
  const failed = (event.type === 'result'
    && (event.is_error === true || /^error(?:_|$)/.test(event.subtype ?? '')))
    || event.type === 'error' || event.type === 'turn.failed';
  if (!failed) return null;
  const values = [event.result, event.message, event.error, event.errors].flat();
  return values.map((value) => typeof value === 'string' ? value : value?.message)
    .filter((value) => typeof value === 'string' && value.trim()).join('\n');
}

function terminalCandidate(event) {
  if (!event || typeof event !== 'object') return null;
  if (validReview(event)) return event;
  if (event.type !== 'result') return null;
  return event.structured_output
    ?? event.structuredOutput
    ?? event.review
    ?? event.result
    ?? undefined;
}

function runProvider(command, args, { cwd, environment, provider, finalFile }) {
  return new Promise((resolvePromise) => {
    let diagnosticTail = Buffer.alloc(0);
    let terminalTail = Buffer.alloc(0);
    let plainStdoutTail = Buffer.alloc(0);
    let terminalError = false;
    let pending = '';
    let candidate;
    let candidateObserved = false;
    let spawnError = null;
    let cancelledSignal = null;
    let cleanupTimer = null;

    const child = spawn(command, args, {
      cwd,
      env: environment,
      shell: false,
      detached: process.platform !== 'win32',
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    function consumeLine(line) {
      if (!line.trim()) return;
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        plainStdoutTail = appendDiagnosticTail(plainStdoutTail, `${line}\n`);
        if (provider === 'claude') candidateObserved = true;
        return;
      }
      const failure = terminalFailure(event);
      if (failure !== null) {
        terminalError = true;
        if (failure) terminalTail = appendDiagnosticTail(terminalTail, `${failure}\n`);
        return;
      }
      const observed = terminalCandidate(event);
      if (observed !== null) {
        candidateObserved = true;
        candidate = observed;
      }
    }

    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => {
      pending += chunk;
      for (;;) {
        const newline = pending.indexOf('\n');
        if (newline === -1) break;
        consumeLine(pending.slice(0, newline));
        pending = pending.slice(newline + 1);
      }
    });
    child.stderr.on('data', (chunk) => {
      diagnosticTail = appendDiagnosticTail(diagnosticTail, chunk);
    });
    child.on('error', (error) => { spawnError = error; });

    function forward(signal) {
      if (cancelledSignal) return;
      cancelledSignal = signal;
      try {
        if (process.platform === 'win32') child.kill(signal);
        else process.kill(-child.pid, signal);
      } catch {
        try { child.kill(signal); } catch { /* child already exited */ }
      }
      cleanupTimer = setTimeout(() => {
        try {
          if (process.platform === 'win32') child.kill('SIGKILL');
          else process.kill(-child.pid, 'SIGKILL');
        } catch { /* child already exited */ }
      }, TERMINATION_GRACE_MS);
      cleanupTimer.unref();
    }

    const onInterrupt = () => forward('SIGINT');
    const onTerminate = () => forward('SIGTERM');
    process.on('SIGINT', onInterrupt);
    process.on('SIGTERM', onTerminate);

    child.on('close', (exitCode, signal) => {
      if (pending) consumeLine(pending);
      if (cleanupTimer) clearTimeout(cleanupTimer);
      process.off('SIGINT', onInterrupt);
      process.off('SIGTERM', onTerminate);

      if (cancelledSignal) {
        resolvePromise({ ok: false, kind: 'cancelled', signal: cancelledSignal });
        return;
      }
      if (spawnError || signal || exitCode !== 0 || terminalError) {
        resolvePromise(providerFailure({
          spawnError, exitCode, signal, diagnosticTail, terminalError,
          stdoutTail: terminalTail.length ? terminalTail
            : exitCode !== 0 ? plainStdoutTail : Buffer.alloc(0),
        }));
        return;
      }

      if (provider === 'codex') {
        if (!existsSync(finalFile)) {
          resolvePromise({ ok: false, kind: 'missing-result', message: 'provider returned no final review' });
          return;
        }
        const raw = readFileSync(finalFile, 'utf8').trim();
        if (!raw) {
          resolvePromise({ ok: false, kind: 'missing-result', message: 'provider returned no final review' });
          return;
        }
        candidateObserved = true;
        try { candidate = JSON.parse(raw); } catch { candidate = undefined; }
      }

      if (!candidateObserved) {
        resolvePromise({ ok: false, kind: 'missing-result', message: 'provider returned no final review' });
      } else if (!validReview(candidate)) {
        resolvePromise({ ok: false, kind: 'malformed-result', message: 'provider returned an invalid review' });
      } else {
        resolvePromise({ ok: true, review: candidate });
      }
    });
  });
}

function installedExecutable() {
  return fileURLToPath(import.meta.url);
}

async function performReview(options) {
  if (!INSTALLED_EXECUTABLES) {
    return { ok: false, kind: 'unavailable', message: 'review bridge is not installed' };
  }
  const executable = installedExecutable();
  try {
    permissionSafePath(executable, 'installed launcher path');
  } catch (error) {
    return {
      ok: false,
      kind: error instanceof BridgeError ? error.kind : 'invalid-request',
      message: error.message,
    };
  }
  let db;
  try {
    db = openTaskDatabase(options.repoRoot, options.taskFolder);
  } catch (error) {
    return {
      ok: false,
      kind: error instanceof BridgeError ? error.kind : 'history-read',
      message: error.message,
    };
  }

  let temporary;
  try {
    temporary = mkdtempSync(join(tmpdir(), 'joshix-review-'));
    const schemaFile = join(temporary, 'review-schema.json');
    const finalFile = join(temporary, 'final-review.json');
    const providerSchema = { ...REVIEW_SCHEMA };
    delete providerSchema.$schema;
    delete providerSchema.allOf;
    writeFileSync(schemaFile, JSON.stringify(providerSchema), { mode: 0o600 });
    const prompt = reviewPrompt({
      installedExecutable: executable,
      repoRoot: options.repoRoot,
      taskFolder: options.taskFolder,
      schema: REVIEW_SCHEMA,
    });

    const entry = INSTALLED_EXECUTABLES[options.provider];
    const prefixArgs = entry?.prefixArgs ?? [];
    let args;
    if (options.provider === 'claude') {
      args = [
        ...prefixArgs,
        ...claudeArguments({
          installedExecutable: executable,
          repoRoot: options.repoRoot,
          taskFolder: options.taskFolder,
          prompt,
          providerSchema,
        }),
      ];
    } else {
      args = [
        ...prefixArgs,
        'exec', '--ignore-user-config', '--ephemeral', '--ignore-rules',
        '--sandbox', 'read-only', '--cd', options.repoRoot,
        '--json', '--output-schema', schemaFile,
        '--output-last-message', finalFile,
        prompt,
      ];
    }

    const providerResult = await runProvider(entry?.command ?? '', args, {
      cwd: options.repoRoot,
      environment: sanitizedProviderEnvironment(),
      provider: options.provider,
      finalFile,
    });
    if (!providerResult.ok) return providerResult;

    const compact = JSON.stringify(providerResult.review);
    if (Buffer.byteLength(compact, 'utf8') > MAX_REVIEW_BYTES) {
      return { ok: false, kind: 'oversized-result', message: 'completed review exceeds 512 KiB' };
    }

    try {
      const speaker = options.provider === 'claude' ? 'Claude Reviewer' : 'Codex Reviewer';
      const result = db.prepare(
        'INSERT INTO messages (speaker, content) VALUES (?, ?)',
      ).run(speaker, compact);
      return {
        ok: true,
        historyId: Number(result.lastInsertRowid),
        review: providerResult.review,
      };
    } catch (error) {
      return {
        ok: false,
        kind: 'history-append',
        message: error.message,
        review: providerResult.review,
      };
    }
  } catch (error) {
    return { ok: false, kind: 'internal', message: error.message };
  } finally {
    db.close();
    if (temporary) rmSync(temporary, { recursive: true, force: true });
  }
}

function taskOptions(argv) {
  if (argv.length < 5 || argv[0] !== '--repo-root' || argv[2] !== '--task-folder') {
    throw new BridgeError('invalid-request', 'task-read requires --repo-root and --task-folder before the command');
  }
  const repoRoot = canonicalRepository(argv[1]);
  const taskFolder = argv[3];
  safeTaskFolder(repoRoot, taskFolder);
  return { repoRoot, taskFolder, command: argv[4], args: argv.slice(5) };
}

function positiveInteger(value, label, { minimum = 0, maximum = Number.MAX_SAFE_INTEGER } = {}) {
  if (!/^(0|[1-9]\d*)$/.test(value ?? '')) {
    throw new BridgeError('invalid-request', `${label} must be an integer`);
  }
  const integer = Number(value);
  if (!Number.isSafeInteger(integer) || integer < minimum || integer > maximum) {
    throw new BridgeError('invalid-request', `${label} is out of range`);
  }
  return integer;
}

function present(rows, full) {
  return rows.map(({ id, created_at: createdAt, speaker, content }) => (
    full
      ? { id, createdAt, speaker, content }
      : {
          id,
          createdAt,
          speaker,
          preview: [...content].length <= 240 ? content : `${[...content].slice(0, 240).join('')}…`,
        }
  ));
}

function runTaskRead(argv) {
  const options = taskOptions(argv);
  const db = openTaskDatabase(options.repoRoot, options.taskFolder, { readOnly: true });
  try {
    let rows;
    if (options.command === 'recent') {
      const args = [...options.args];
      let limit = 20;
      let full = false;
      while (args.length) {
        const token = args.shift();
        if (token === '--full' && !full) full = true;
        else if (token === '--limit' && args.length) {
          limit = positiveInteger(args.shift(), 'limit', { minimum: 1, maximum: 1000 });
        } else throw new BridgeError('invalid-request', `invalid recent option: ${token}`);
      }
      rows = db.prepare(`
        SELECT * FROM (
          SELECT * FROM messages ORDER BY id DESC LIMIT ?
        ) ORDER BY id
      `).all(limit);
      process.stdout.write(`${JSON.stringify(present(rows, full), null, 2)}\n`);
      return;
    }
    if (options.command === 'since-id') {
      const args = [...options.args];
      const id = positiveInteger(args.shift(), 'id');
      const full = args.length === 1 && args[0] === '--full';
      if (args.length && !full) throw new BridgeError('invalid-request', 'invalid since-id options');
      rows = db.prepare('SELECT * FROM messages WHERE id > ? ORDER BY id').all(id);
      process.stdout.write(`${JSON.stringify(present(rows, full), null, 2)}\n`);
      return;
    }
    if (options.command === 'since-time') {
      const args = [...options.args];
      const input = args.shift();
      const time = new Date(input);
      if (!input || Number.isNaN(time.valueOf())) throw new BridgeError('invalid-request', 'invalid timestamp');
      const full = args.length === 1 && args[0] === '--full';
      if (args.length && !full) throw new BridgeError('invalid-request', 'invalid since-time options');
      rows = db.prepare('SELECT * FROM messages WHERE created_at >= ? ORDER BY id').all(time.toISOString());
      process.stdout.write(`${JSON.stringify(present(rows, full), null, 2)}\n`);
      return;
    }
    if (options.command === 'search') {
      if (options.args.length !== 1) throw new BridgeError('invalid-request', 'search requires one literal');
      rows = db.prepare(
        'SELECT * FROM messages WHERE instr(lower(content), lower(?)) > 0 ORDER BY id',
      ).all(options.args[0]);
      process.stdout.write(`${JSON.stringify(present(rows, false), null, 2)}\n`);
      return;
    }
    if (options.command === 'get') {
      if (options.args.length === 0) throw new BridgeError('invalid-request', 'get requires at least one id');
      const ids = options.args.map((value) => positiveInteger(value, 'id', { minimum: 1 }));
      const placeholders = ids.map(() => '?').join(',');
      rows = db.prepare(`SELECT * FROM messages WHERE id IN (${placeholders}) ORDER BY id`).all(...ids);
      process.stdout.write(`${JSON.stringify(present(rows, true), null, 2)}\n`);
      return;
    }
    if (options.command === 'check') {
      if (options.args.length) throw new BridgeError('invalid-request', 'check accepts no arguments');
      const state = schemaState(db);
      process.stdout.write(`${JSON.stringify({
        ok: knownTaskSchema(state),
        integrity: state.integrity,
        schemaVersion: state.version,
      }, null, 2)}\n`);
      return;
    }
    throw new BridgeError('invalid-request', `unknown task-read command: ${options.command}`);
  } finally {
    db.close();
  }
}

const SAFE_GIT_PREFIX = [
  '--no-pager',
  '-c', 'color.ui=false',
  '-c', 'core.pager=cat',
  '-c', 'core.fsmonitor=false',
  '-c', 'core.hooksPath=/dev/null',
  '-c', 'diff.external=',
];

function safeRevision(value) {
  noControlCharacters(value, 'revision');
  if (!value || value.startsWith('-')) throw new BridgeError('invalid-request', 'invalid revision');
  return value;
}

function safePaths(values) {
  if (values.length === 0) throw new BridgeError('invalid-request', 'path filter is empty');
  return values.map((value) => {
    noControlCharacters(value, 'path');
    if (
      !value
      || isAbsolute(value)
      || value.split(/[\\/]/).includes('..')
    ) throw new BridgeError('invalid-request', `unsafe path: ${value}`);
    return value;
  });
}

export function gitArguments(argv) {
  const [operation, ...tail] = argv;
  if (operation === 'status' && tail.length === 0) {
    return [...SAFE_GIT_PREFIX, 'status', '--short', '--untracked-files=all'];
  }
  if (operation === 'log' && tail.length === 0) {
    return [...SAFE_GIT_PREFIX, 'log', '--max-count=50', '--oneline', '--decorate'];
  }
  if (operation === 'show') {
    if (tail.length === 1) {
      return [...SAFE_GIT_PREFIX, 'show', '--no-ext-diff', '--no-textconv', safeRevision(tail[0])];
    }
    const separator = tail.indexOf('--');
    if (separator === 1 && tail.length > 2) {
      return [
        ...SAFE_GIT_PREFIX, 'show', '--no-ext-diff', '--no-textconv',
        safeRevision(tail[0]), '--', ...safePaths(tail.slice(2)),
      ];
    }
    throw new BridgeError('invalid-request', 'invalid show form');
  }
  if (operation === 'diff') {
    const base = [...SAFE_GIT_PREFIX, 'diff', '--no-ext-diff', '--no-textconv'];
    if (tail.length === 0) return base;
    if (tail.length === 1 && tail[0] === '--cached') return [...base, '--cached'];
    if (tail[0] === '--' && tail.length > 1) return [...base, '--', ...safePaths(tail.slice(1))];
    if (tail[0] === '--cached' && tail[1] === '--' && tail.length > 2) {
      return [...base, '--cached', '--', ...safePaths(tail.slice(2))];
    }
    if (tail.length === 1) return [...base, safeRevision(tail[0])];
    if (tail[1] === '--' && tail.length > 2) {
      return [...base, safeRevision(tail[0]), '--', ...safePaths(tail.slice(2))];
    }
    throw new BridgeError('invalid-request', 'invalid diff form');
  }
  throw new BridgeError('invalid-request', `unknown git-read command: ${operation ?? ''}`);
}

function runGitRead(argv) {
  if (argv.length < 3 || argv[0] !== '--repo-root') {
    throw new BridgeError('invalid-request', 'git-read requires --repo-root before the command');
  }
  const translated = gitArguments(argv.slice(2));
  const repoRoot = canonicalRepository(argv[1]);
  if (!INSTALLED_EXECUTABLES?.git) {
    throw new BridgeError('unavailable', 'Git executable is not installed');
  }
  const result = spawnSync(INSTALLED_EXECUTABLES.git, translated, {
    cwd: repoRoot,
    env: sanitizedGitEnvironment(),
    shell: false,
    stdio: ['ignore', 'inherit', 'inherit'],
  });
  if (result.error) throw new BridgeError('unavailable', result.error.message);
  if (result.status !== 0) process.exitCode = result.status ?? 1;
}

function printReviewResult(result) {
  process.stdout.write(`${JSON.stringify(result)}\n`);
  if (result.ok) process.exitCode = 0;
  else if (result.kind === 'cancelled') process.exitCode = result.signal === 'SIGINT' ? 130 : 143;
  else process.exitCode = 1;
}

async function main(argv) {
  const [operation, ...tail] = argv;
  if (operation === 'review') {
    let options;
    try {
      options = parseReviewOptions(tail);
    } catch (error) {
      printReviewResult({
        ok: false,
        kind: error instanceof BridgeError ? error.kind : 'invalid-request',
        message: error.message,
      });
      return;
    }
    try {
      printReviewResult(await performReview(options));
    } catch (error) {
      printReviewResult({ ok: false, kind: 'internal', message: error.message });
    }
    return;
  }
  if (operation === 'task-read') {
    runTaskRead(tail);
    return;
  }
  if (operation === 'git-read') {
    runGitRead(tail);
    return;
  }
  throw new BridgeError('invalid-request', `unknown operation: ${operation ?? ''}`);
}

if (
  process.argv[1]
  && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))
) {
  try {
    await loadDatabaseSync();
    await main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`joshix-review: ${error.message}\n`);
    process.exitCode = 1;
  }
}
