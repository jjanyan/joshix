#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from 'node:fs';
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const SCHEMA_VERSION = 1;
const PREVIEW_LENGTH = 240;
const DEFAULT_RECENT_LIMIT = 20;
const HELP = `Usage: task-context <command> <task-folder> [options]

Commands:
  init <task-folder>
  append <task-folder> --speaker <name> --content-file <path>
  recent <task-folder> [--limit <1-1000>] [--full]
  since-id <task-folder> <id> [--full]
  since-time <task-folder> <ISO-8601 timestamp> [--full]
  get <task-folder> <id> [id ...]
  search <task-folder> <text>  (literal substring, ASCII case-insensitive)
  export <task-folder> --format markdown
  check <task-folder>
`;
const EXPECTED_COLUMNS = [
  { name: 'id', type: 'INTEGER', notnull: 0, pk: 1 },
  { name: 'created_at', type: 'TEXT', notnull: 1, pk: 0 },
  { name: 'speaker', type: 'TEXT', notnull: 1, pk: 0 },
  { name: 'content', type: 'TEXT', notnull: 1, pk: 0 },
];
const TIMESTAMP_DEFAULT = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
const SCHEMA = `
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  speaker TEXT NOT NULL,
  content TEXT NOT NULL
);
CREATE INDEX messages_created_at_idx ON messages(created_at);
PRAGMA user_version = 1;
`;

function fail(message) {
  throw new Error(message);
}

function git(cwd, args, allowFailure = false) {
  try {
    return execFileSync('git', ['-C', cwd, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', allowFailure ? 'ignore' : 'pipe'],
    }).trim();
  } catch (error) {
    if (allowFailure) return null;
    throw error;
  }
}

function gitRoot(cwd) {
  const root = git(cwd, ['rev-parse', '--show-toplevel'], true);
  return root ? realpathSync(root) : null;
}

function nearestExistingDirectory(candidate) {
  let current = resolve(candidate);
  while (!existsSync(current)) current = dirname(current);
  return current;
}

function canonicalizeNewPath(candidate) {
  const absolute = resolve(candidate);
  let ancestor = dirname(absolute);
  const suffix = [basename(absolute)];
  while (!existsSync(ancestor)) {
    suffix.unshift(basename(ancestor));
    ancestor = dirname(ancestor);
  }
  return join(realpathSync(ancestor), ...suffix);
}

function isDirectChild(parent, child) {
  const candidate = relative(parent, child);
  return candidate !== ''
    && !candidate.startsWith(`..${sep}`)
    && candidate !== '..'
    && !isAbsolute(candidate)
    && !candidate.includes(sep);
}

function refuseSymbolicLink(candidate) {
  if (existsSync(candidate) && lstatSync(candidate).isSymbolicLink()) {
    fail(`Refusing symbolic link in task context path: ${candidate}`);
  }
}

function validateTaskFiles(task) {
  for (const candidate of [
    task,
    join(task, 'history.sqlite'),
    join(task, 'current.md'),
    join(task, 'files'),
  ]) {
    refuseSymbolicLink(candidate);
  }
}

function resolveTask(folder, cwd = process.cwd()) {
  if (!folder) fail('A task folder is required.');

  const root = gitRoot(cwd);
  if (!isAbsolute(folder)) {
    if (!root) fail('Outside Git, provide an explicit absolute task path.');
    const task = resolve(root, folder);
    const taskRoot = join(root, '.agents/tasks');
    if (!isDirectChild(taskRoot, task)) {
      fail('Relative task paths must name a folder under .agents/tasks/.');
    }
    return { task, root };
  }

  const task = canonicalizeNewPath(folder);
  const targetRoot = gitRoot(nearestExistingDirectory(dirname(task)));
  if (targetRoot) {
    const taskRoot = join(targetRoot, '.agents/tasks');
    if (!isDirectChild(taskRoot, task)) {
      fail('Git-backed task paths must name a folder under .agents/tasks/.');
    }
    return { task, root: targetRoot };
  }

  if (root) {
    fail('Refusing to create a task outside a repository while running inside one.');
  }

  return { task, root: null };
}

function ensurePrivacy(root) {
  const tracked = git(root, ['ls-files', '--', '.agents/tasks']);
  if (tracked) {
    fail(`Refusing to initialize while task context contains tracked paths:\n${tracked}`);
  }

  const taskRoot = join(root, '.agents/tasks');
  refuseSymbolicLink(join(root, '.agents'));
  refuseSymbolicLink(taskRoot);
  mkdirSync(taskRoot, { recursive: true });
  const ignorePath = join(taskRoot, '.gitignore');
  refuseSymbolicLink(ignorePath);
  const existing = existsSync(ignorePath) ? readFileSync(ignorePath, 'utf8') : '';
  const lines = existing.replaceAll('\r\n', '\n').split('\n');
  while (lines.at(-1) === '') lines.pop();
  if (lines.at(-1) !== '*') lines.push('*');
  const expected = `${lines.join('\n')}\n`;
  if (existing !== expected) writeFileSync(ignorePath, expected);

  for (const candidate of [
    '.agents/tasks/.gitignore',
    '.agents/tasks/.privacy-check/history.sqlite',
  ]) {
    if (git(root, ['check-ignore', '--no-index', candidate], true) === null) {
      fail(`Privacy verification failed for ${candidate}.`);
    }
  }
}

function readSchemaState(db) {
  const integrity = db.prepare('PRAGMA integrity_check').get().integrity_check;
  const version = db.prepare('PRAGMA user_version').get().user_version;
  const columns = db
    .prepare('PRAGMA table_info(messages)')
    .all()
    .map(({ name, type, notnull, pk }) => ({ name, type, notnull, pk }));
  const indexColumns = db
    .prepare('PRAGMA index_info(messages_created_at_idx)')
    .all()
    .map(({ name }) => name);
  const tableSql = db
    .prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'messages'")
    .get()?.sql ?? '';

  return {
    integrity,
    version,
    columns,
    hasIndex: JSON.stringify(indexColumns) === JSON.stringify(['created_at']),
    hasAutomaticTimestamp: tableSql.includes(TIMESTAMP_DEFAULT),
  };
}

function isExpectedSchema(state) {
  return state.integrity === 'ok'
    && state.version === SCHEMA_VERSION
    && state.hasIndex
    && state.hasAutomaticTimestamp
    && JSON.stringify(state.columns) === JSON.stringify(EXPECTED_COLUMNS);
}

function validateExistingDatabase(databasePath) {
  const db = new DatabaseSync(databasePath, { readOnly: true });
  try {
    if (!isExpectedSchema(readSchemaState(db))) {
      fail('Existing task database failed integrity or schema validation.');
    }
  } finally {
    db.close();
  }
}

function titleFor(task) {
  return basename(task)
    .replace(/^\d{4}-\d{2}-\d{2}-/, '')
    .replaceAll('-', ' ');
}

function currentTemplate(task) {
  return `---\nupdated_at: ${new Date().toISOString()}\nhistory_through: 0\n---\n\n# ${titleFor(task)}\n\n## Objective\n\n## Current state\n\n## Decisions\n\n## Open questions or blockers\n\n## Next actions\n\n## Relevant files\n`;
}

function initialize(folder) {
  const { task, root } = resolveTask(folder);
  if (root) ensurePrivacy(root);
  validateTaskFiles(task);

  const databasePath = join(task, 'history.sqlite');
  if (existsSync(databasePath)) {
    validateExistingDatabase(databasePath);
  } else {
    mkdirSync(join(task, 'files'), { recursive: true });
    const db = new DatabaseSync(databasePath);
    try {
      db.exec(SCHEMA);
    } finally {
      db.close();
    }
  }

  mkdirSync(join(task, 'files'), { recursive: true });
  const summaryPath = join(task, 'current.md');
  if (!existsSync(summaryPath)) {
    writeFileSync(summaryPath, currentTemplate(task));
  }

  process.stdout.write(`${task}\n`);
}

function databaseFor(folder, options = {}) {
  const { verifyPrivacy = false, ...databaseOptions } = options;
  const { task, root } = resolveTask(folder);
  if (verifyPrivacy && root) ensurePrivacy(root);
  validateTaskFiles(task);
  const databasePath = join(task, 'history.sqlite');
  if (!existsSync(databasePath)) {
    fail(`Missing task database: ${databasePath}`);
  }
  return { task, db: new DatabaseSync(databasePath, databaseOptions) };
}

function option(args, name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  if (!args[index + 1] || args[index + 1].startsWith('--')) {
    fail(`${name} requires a value.`);
  }
  const value = args[index + 1];
  args.splice(index, 2);
  return value;
}

function flag(args, name) {
  const index = args.indexOf(name);
  if (index === -1) return false;
  args.splice(index, 1);
  return true;
}

function assertNoArgs(args) {
  if (args.length > 0) {
    fail(`Unexpected arguments: ${args.join(' ')}`);
  }
}

function preview(content) {
  const points = [...content];
  return points.length <= PREVIEW_LENGTH
    ? content
    : `${points.slice(0, PREVIEW_LENGTH).join('')}…`;
}

function present(rows, full) {
  return rows.map(({ id, created_at: createdAt, speaker, content }) => (
    full
      ? { id, createdAt, speaker, content }
      : { id, createdAt, speaker, preview: preview(content) }
  ));
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function append(folder, args) {
  const speaker = option(args, '--speaker');
  const contentFile = option(args, '--content-file');
  assertNoArgs(args);
  if (!speaker || !contentFile) {
    fail('append requires --speaker and --content-file.');
  }

  const content = readFileSync(resolve(contentFile), 'utf8');
  const { db } = databaseFor(folder, { verifyPrivacy: true });
  try {
    const result = db
      .prepare('INSERT INTO messages (speaker, content) VALUES (?, ?)')
      .run(speaker, content);
    process.stdout.write(`${result.lastInsertRowid}\n`);
  } finally {
    db.close();
  }
}

function query(folder, sql, parameters, full) {
  const { db } = databaseFor(folder, { readOnly: true });
  try {
    printJson(present(db.prepare(sql).all(...parameters), full));
  } finally {
    db.close();
  }
}

function recent(folder, args) {
  const full = flag(args, '--full');
  const rawLimit = option(args, '--limit');
  assertNoArgs(args);
  const limit = rawLimit === null ? DEFAULT_RECENT_LIMIT : Number(rawLimit);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000) {
    fail('--limit must be an integer from 1 to 1000.');
  }
  query(
    folder,
    'SELECT * FROM (SELECT * FROM messages ORDER BY id DESC LIMIT ?) ORDER BY id',
    [limit],
    full,
  );
}

function sinceId(folder, args) {
  const full = flag(args, '--full');
  const rawId = args.shift();
  assertNoArgs(args);
  const id = Number(rawId);
  if (!Number.isSafeInteger(id) || id < 0) {
    fail('since-id requires a non-negative integer ID.');
  }
  query(folder, 'SELECT * FROM messages WHERE id > ? ORDER BY id', [id], full);
}

function sinceTime(folder, args) {
  const full = flag(args, '--full');
  const rawTime = args.shift();
  assertNoArgs(args);
  const parsed = new Date(rawTime);
  if (!rawTime || Number.isNaN(parsed.valueOf())) {
    fail('since-time requires an ISO 8601 timestamp.');
  }
  query(
    folder,
    'SELECT * FROM messages WHERE created_at > ? ORDER BY id',
    [parsed.toISOString()],
    full,
  );
}

function getMessages(folder, args) {
  if (args.length === 0) {
    fail('get requires at least one message ID.');
  }
  const ids = args.map(Number);
  if (ids.some((id) => !Number.isSafeInteger(id) || id < 1)) {
    fail('get IDs must be positive integers.');
  }
  const placeholders = ids.map(() => '?').join(', ');
  query(
    folder,
    `SELECT * FROM messages WHERE id IN (${placeholders}) ORDER BY id`,
    ids,
    true,
  );
}

function escapeLike(value) {
  return value
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
}

function search(folder, args) {
  const queryText = args.shift();
  assertNoArgs(args);
  if (queryText === undefined) {
    fail('search requires a literal query.');
  }
  query(
    folder,
    "SELECT * FROM messages WHERE content LIKE ? ESCAPE '\\' ORDER BY id",
    [`%${escapeLike(queryText)}%`],
    false,
  );
}

function exportMarkdown(folder, args) {
  const format = option(args, '--format');
  assertNoArgs(args);
  if (format !== 'markdown') {
    fail('export requires --format markdown.');
  }

  const { db } = databaseFor(folder, { readOnly: true });
  try {
    const rows = db.prepare('SELECT * FROM messages ORDER BY id').all();
    const body = rows
      .map(({ id, created_at: createdAt, speaker, content }) => (
        `## ${id} · ${speaker} · ${createdAt}\n\n${content}`
      ))
      .join('\n\n');
    process.stdout.write(`# Task history\n\n${body}${body ? '\n' : ''}`);
  } finally {
    db.close();
  }
}

function check(folder, args) {
  assertNoArgs(args);
  const { db } = databaseFor(folder, { readOnly: true });
  let state;
  try {
    state = readSchemaState(db);
  } finally {
    db.close();
  }
  const ok = isExpectedSchema(state);
  printJson({
    ok,
    integrity: state.integrity,
    schemaVersion: state.version,
  });
  if (!ok) process.exitCode = 1;
}

function main(argv) {
  if (argv.length === 1 && ['--help', '-h'].includes(argv[0])) {
    process.stdout.write(HELP);
    return;
  }

  const [command, folder, ...args] = argv;
  if (!command || !folder) {
    fail('A command and task folder are required.');
  }

  const commands = {
    init: () => {
      assertNoArgs(args);
      initialize(folder);
    },
    append: () => append(folder, args),
    recent: () => recent(folder, args),
    'since-id': () => sinceId(folder, args),
    'since-time': () => sinceTime(folder, args),
    get: () => getMessages(folder, args),
    search: () => search(folder, args),
    export: () => exportMarkdown(folder, args),
    check: () => check(folder, args),
  };
  if (!commands[command]) {
    fail(`Unknown command: ${command}`);
  }
  commands[command]();
}

try {
  main(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`task-context: ${error.message}\n`);
  process.exitCode = 1;
}
