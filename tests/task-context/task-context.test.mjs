import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const helper = join(repoRoot, 'skills/task-context/scripts/task-context.mjs');
const temporaryDirectories = [];

function tempDir() {
  const directory = mkdtempSync(join(tmpdir(), 'joshix-task-context-'));
  temporaryDirectories.push(directory);
  return directory;
}

after(() => {
  for (const directory of temporaryDirectories) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function git(cwd, ...args) {
  return execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8' }).trim();
}

function initRepo() {
  const cwd = tempDir();
  git(cwd, 'init', '--quiet');
  git(cwd, 'config', 'user.email', 'task-context@example.com');
  git(cwd, 'config', 'user.name', 'Task Context Test');
  return cwd;
}

function run(cwd, ...args) {
  return spawnSync(
    process.execPath,
    ['--disable-warning=ExperimentalWarning', helper, ...args],
    { cwd, encoding: 'utf8' },
  );
}

function runWithPath(cwd, pathEntry, ...args) {
  return spawnSync(
    process.execPath,
    ['--disable-warning=ExperimentalWarning', helper, ...args],
    {
      cwd,
      encoding: 'utf8',
      env: { ...process.env, PATH: `${pathEntry}:${process.env.PATH}` },
    },
  );
}

function assertSuccess(result) {
  assert.equal(result.status, 0, result.stderr);
}

function stdoutJson(result) {
  assertSuccess(result);
  return JSON.parse(result.stdout);
}

function appendMessage(root, folder, speaker, content) {
  const contentFile = join(tempDir(), 'message.md');
  writeFileSync(contentFile, content);
  const result = run(
    root,
    'append',
    folder,
    '--speaker',
    speaker,
    '--content-file',
    contentFile,
  );
  assertSuccess(result);
  return Number(result.stdout.trim());
}

test('help lists the complete command surface without requiring a task folder', () => {
  const cwd = tempDir();

  const result = run(cwd, '--help');

  assertSuccess(result);
  assert.match(result.stdout, /Usage: task-context <command> <task-folder>/);
  for (const command of [
    'init',
    'append',
    'recent',
    'since-id',
    'since-time',
    'get',
    'search',
    'export',
    'check',
  ]) {
    assert.match(result.stdout, new RegExp(`\\b${command}\\b`));
  }
  assert.match(result.stdout, /literal substring, ASCII case-insensitive/);
  assert.equal(existsSync(join(cwd, '.agents')), false);
});

test('init resolves relative paths from the Git root and protects them before use', () => {
  const root = initRepo();
  const nested = join(root, 'src/deep');
  mkdirSync(nested, { recursive: true });

  const result = run(nested, 'init', '.agents/tasks/2026-07-22-CJ-66');
  assertSuccess(result);

  const task = join(root, '.agents/tasks/2026-07-22-CJ-66');
  assert.equal(readFileSync(join(root, '.agents/tasks/.gitignore'), 'utf8'), '*\n');
  assert.equal(
    git(root, 'check-ignore', '--no-index', '.agents/tasks/.gitignore'),
    '.agents/tasks/.gitignore',
  );
  assert.equal(
    git(root, 'check-ignore', '--no-index', '.agents/tasks/2026-07-22-CJ-66/history.sqlite'),
    '.agents/tasks/2026-07-22-CJ-66/history.sqlite',
  );
  assert.equal(git(root, 'status', '--porcelain', '--', '.agents/tasks'), '');
  assert.equal(
    readFileSync(join(task, 'current.md'), 'utf8').includes('history_through: 0'),
    true,
  );

  const db = new DatabaseSync(join(task, 'history.sqlite'), { readOnly: true });
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, 1);
  assert.deepEqual(
    db.prepare(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'index') AND name IN ('messages', 'messages_created_at_idx') ORDER BY name",
    ).all().map(({ name }) => name),
    ['messages', 'messages_created_at_idx'],
  );
  db.close();
});

test('init preserves an existing ignore file and appends a final wildcard', () => {
  const root = initRepo();
  mkdirSync(join(root, '.agents/tasks'), { recursive: true });
  writeFileSync(join(root, '.agents/tasks/.gitignore'), '# local note\nkeep-me\n');

  assertSuccess(run(root, 'init', '.agents/tasks/2026-07-22-local'));

  assert.equal(
    readFileSync(join(root, '.agents/tasks/.gitignore'), 'utf8'),
    '# local note\nkeep-me\n*\n',
  );
});

test('append does not rewrite an already-correct privacy ignore file', () => {
  const root = initRepo();
  const folder = '.agents/tasks/2026-07-22-no-ignore-rewrite';
  assertSuccess(run(root, 'init', folder));
  const ignorePath = join(root, '.agents/tasks/.gitignore');
  chmodSync(ignorePath, 0o444);

  const id = appendMessage(root, folder, 'User', 'preserve the ignore file');

  assert.equal(id, 1);
  assert.equal(readFileSync(ignorePath, 'utf8'), '*\n');
});

test('init refuses tracked task artifacts without changing the index', () => {
  const root = initRepo();
  mkdirSync(join(root, '.agents/tasks/existing'), { recursive: true });
  writeFileSync(join(root, '.agents/tasks/existing/leak.txt'), 'tracked');
  git(root, 'add', '-f', '.agents/tasks/existing/leak.txt');
  const before = git(root, 'diff', '--cached', '--name-only');

  const result = run(root, 'init', '.agents/tasks/2026-07-22-blocked');

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /tracked path/i);
  assert.equal(git(root, 'diff', '--cached', '--name-only'), before);
  assert.equal(
    existsSync(join(root, '.agents/tasks/2026-07-22-blocked/history.sqlite')),
    false,
  );
});

test('init writes no conversation data when git ignore verification fails', () => {
  const root = initRepo();
  const fakeBin = tempDir();
  const realGit = execFileSync('which', ['git'], { encoding: 'utf8' }).trim();
  const fakeGit = join(fakeBin, 'git');
  writeFileSync(
    fakeGit,
    `#!/bin/sh\nif [ "$3" = "check-ignore" ]; then exit 1; fi\nexec "${realGit}" "$@"\n`,
  );
  chmodSync(fakeGit, 0o755);

  const folder = '.agents/tasks/2026-07-22-ignore-failure';
  const result = runWithPath(root, fakeBin, 'init', folder);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /privacy verification failed/i);
  assert.equal(existsSync(join(root, folder, 'history.sqlite')), false);
  assert.equal(existsSync(join(root, folder, 'current.md')), false);
});

test('relative init outside Git fails but an absolute path is an explicit opt-in', () => {
  const cwd = tempDir();
  const relative = run(cwd, 'init', '.agents/tasks/2026-07-22-no-git');
  assert.notEqual(relative.status, 0);
  assert.match(relative.stderr, /absolute task path/i);

  const task = join(cwd, 'shared-task');
  const absolute = run(cwd, 'init', task);
  assertSuccess(absolute);
  assert.equal(
    readFileSync(join(task, 'current.md'), 'utf8').includes('# shared task'),
    true,
  );
});

test('Git-backed absolute paths cannot escape to a non-Git directory', () => {
  const root = initRepo();
  const outsideTask = join(tempDir(), 'escaped-task');

  const result = run(root, 'init', outsideTask);

  assert.notEqual(result.status, 0);
  assert.match(
    result.stderr,
    /Refusing to create a task outside a repository while running inside one/,
  );
  assert.equal(existsSync(outsideTask), false);
});

test('an absolute task path may target another Git repository task root', () => {
  const sourceRoot = initRepo();
  const targetRoot = initRepo();
  const targetTask = join(targetRoot, '.agents/tasks/2026-07-22-other-repo');

  const result = run(sourceRoot, 'init', targetTask);

  assertSuccess(result);
  assert.equal(existsSync(join(targetTask, 'history.sqlite')), true);
  assert.equal(existsSync(join(sourceRoot, '.agents/tasks')), false);
});

test('init refuses symlinked task paths before writing through them', () => {
  const root = initRepo();
  const outside = tempDir();
  mkdirSync(join(root, '.agents'), { recursive: true });
  symlinkSync(outside, join(root, '.agents/tasks'), 'dir');

  const result = run(root, 'init', '.agents/tasks/2026-07-22-symlink');

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /symbolic link/i);
  assert.equal(existsSync(join(outside, '.gitignore')), false);
  assert.equal(existsSync(join(outside, '2026-07-22-symlink')), false);
});

test('repeated init preserves the exact folder, messages, files, and summary', () => {
  const root = initRepo();
  const folder = '.agents/tasks/2026-07-22-CJ-66';
  assertSuccess(run(root, 'init', folder));
  const task = join(root, folder);
  writeFileSync(join(task, 'files/evidence.txt'), 'evidence');
  writeFileSync(join(task, 'current.md'), 'custom summary\n');
  const writeDb = new DatabaseSync(join(task, 'history.sqlite'));
  writeDb
    .prepare('INSERT INTO messages (speaker, content) VALUES (?, ?)')
    .run('User', 'preserve me');
  writeDb.close();

  assertSuccess(run(root, 'init', folder));

  assert.equal(readFileSync(join(task, 'files/evidence.txt'), 'utf8'), 'evidence');
  assert.equal(readFileSync(join(task, 'current.md'), 'utf8'), 'custom summary\n');
  const readDb = new DatabaseSync(join(task, 'history.sqlite'), { readOnly: true });
  assert.equal(readDb.prepare('SELECT count(*) AS count FROM messages').get().count, 1);
  readDb.close();
  assert.equal(existsSync(`${task}-2`), false);
});

test('repeated init preserves an invalid existing database for diagnosis', () => {
  const root = initRepo();
  const task = join(root, '.agents/tasks/2026-07-22-invalid');
  mkdirSync(join(root, '.agents/tasks'), { recursive: true });
  writeFileSync(join(root, '.agents/tasks/.gitignore'), '*\n');
  mkdirSync(task, { recursive: true });
  const invalid = Buffer.from('not a sqlite database');
  writeFileSync(join(task, 'history.sqlite'), invalid);

  const result = run(root, 'init', task);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /database|integrity|schema/i);
  assert.deepEqual(readFileSync(join(task, 'history.sqlite')), invalid);
  assert.equal(existsSync(join(task, 'files')), false);
  assert.equal(existsSync(join(task, 'current.md')), false);
});

test('repeated init rejects a same-named index on the wrong column', () => {
  const root = initRepo();
  const task = join(root, '.agents/tasks/2026-07-22-wrong-index');
  mkdirSync(task, { recursive: true });
  writeFileSync(join(root, '.agents/tasks/.gitignore'), '*\n');
  const databasePath = join(task, 'history.sqlite');
  const db = new DatabaseSync(databasePath);
  db.exec(`
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      speaker TEXT NOT NULL,
      content TEXT NOT NULL
    );
    CREATE INDEX messages_created_at_idx ON messages(speaker);
    PRAGMA user_version = 1;
  `);
  db.close();
  const before = readFileSync(databasePath);

  const result = run(root, 'init', task);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /integrity|schema/i);
  assert.deepEqual(readFileSync(databasePath), before);
});

test('append preserves arbitrary Markdown and assigns ordered IDs and UTC timestamps', () => {
  const root = initRepo();
  const folder = '.agents/tasks/2026-07-22-history';
  assertSuccess(run(root, 'init', folder));
  const content = 'Quotes: \'single\' and "double"\n\n```js\nconst snowman = "☃️";\n```\n';

  assert.equal(appendMessage(root, folder, 'User', content), 1);
  assert.equal(appendMessage(root, folder, 'Claude', 'second'), 2);

  const db = new DatabaseSync(join(root, folder, 'history.sqlite'), { readOnly: true });
  const rows = db.prepare('SELECT * FROM messages ORDER BY id').all();
  db.close();
  assert.equal(rows[0].content, content);
  assert.deepEqual(rows.map(({ id }) => id), [1, 2]);
  assert.match(
    rows[0].created_at,
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/,
  );
});

test('append rechecks privacy and refuses task data tracked after initialization', () => {
  const root = initRepo();
  const folder = '.agents/tasks/2026-07-22-recheck';
  assertSuccess(run(root, 'init', folder));
  appendMessage(root, folder, 'User', 'first');
  git(root, 'add', '-f', `${folder}/history.sqlite`);
  const contentFile = join(tempDir(), 'blocked-message.md');
  writeFileSync(contentFile, 'must not be appended');

  const result = run(
    root,
    'append',
    folder,
    '--speaker',
    'Codex',
    '--content-file',
    contentFile,
  );

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /tracked path/i);
  const db = new DatabaseSync(join(root, folder, 'history.sqlite'), { readOnly: true });
  assert.equal(db.prepare('SELECT count(*) AS count FROM messages').get().count, 1);
  db.close();
});

test('retrieval defaults to bounded previews and full content is explicit', () => {
  const root = initRepo();
  const folder = '.agents/tasks/2026-07-22-retrieval';
  assertSuccess(run(root, 'init', folder));
  appendMessage(root, folder, 'User', 'A'.repeat(300));
  appendMessage(root, folder, 'Codex', 'middle');
  appendMessage(root, folder, 'User', 'last');

  const recent = stdoutJson(run(root, 'recent', folder, '--limit', '2'));
  assert.deepEqual(recent.map(({ id }) => id), [2, 3]);
  assert.equal(recent[0].content, undefined);
  assert.equal(recent[0].preview, 'middle');

  const allPreviews = stdoutJson(run(root, 'recent', folder, '--limit', '3'));
  assert.equal(allPreviews[0].content, undefined);
  assert.equal([...allPreviews[0].preview].length, 241);
  assert.equal(allPreviews[0].preview.endsWith('…'), true);

  const full = stdoutJson(run(root, 'since-id', folder, '0', '--full'));
  assert.equal(full[0].content.length, 300);
  assert.equal(full[0].preview, undefined);
  assert.deepEqual(
    stdoutJson(run(root, 'get', folder, '3', '1')).map(({ id }) => id),
    [1, 3],
  );
});

test('since-time normalizes offsets and search is literal and ASCII case-insensitive', async () => {
  const root = initRepo();
  const folder = '.agents/tasks/2026-07-22-time-search';
  assertSuccess(run(root, 'init', folder));
  appendMessage(root, folder, 'User', 'literal 100% value');
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
  const secondId = appendMessage(root, folder, 'Codex', 'literal snake_case value');

  const db = new DatabaseSync(join(root, folder, 'history.sqlite'), { readOnly: true });
  const firstTime = db
    .prepare('SELECT created_at FROM messages WHERE id = 1')
    .get().created_at;
  db.close();
  const offsetTime = new Date(firstTime).toISOString().replace('Z', '+00:00');

  assert.deepEqual(
    stdoutJson(run(root, 'since-time', folder, offsetTime)).map(({ id }) => id),
    [secondId],
  );
  assert.deepEqual(
    stdoutJson(run(root, 'search', folder, '100%')).map(({ id }) => id),
    [1],
  );
  assert.deepEqual(
    stdoutJson(run(root, 'search', folder, 'snake_case')).map(({ id }) => id),
    [2],
  );
  assert.deepEqual(
    stdoutJson(run(root, 'search', folder, 'SNAKE_CASE')).map(({ id }) => id),
    [2],
  );
  assert.deepEqual(
    stdoutJson(run(root, 'search', folder, '%_')).map(({ id }) => id),
    [],
  );
});

test('export preserves ordering and bodies, and check is read-only', () => {
  const root = initRepo();
  const folder = '.agents/tasks/2026-07-22-export';
  assertSuccess(run(root, 'init', folder));
  appendMessage(root, folder, 'User', 'first\nline');
  appendMessage(root, folder, 'Codex', 'second');
  const task = join(root, folder);
  const before = readFileSync(join(task, 'history.sqlite'));

  const exported = run(root, 'export', folder, '--format', 'markdown');
  assertSuccess(exported);
  assert.match(exported.stdout, /## 1 · User · .*\n\nfirst\nline/);
  assert.ok(exported.stdout.indexOf('## 1') < exported.stdout.indexOf('## 2'));
  assert.deepEqual(stdoutJson(run(root, 'check', folder)), {
    ok: true,
    integrity: 'ok',
    schemaVersion: 1,
  });
  assert.deepEqual(readFileSync(join(task, 'history.sqlite')), before);
});
