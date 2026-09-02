import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
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

function runHelper(helperPath, cwd, args, environment = {}) {
  return spawnSync(helperPath, args, {
    cwd,
    encoding: 'utf8',
    env: { ...process.env, ...environment },
  });
}

function run(cwd, ...args) {
  return runHelper(helper, cwd, args);
}

function runWithPath(cwd, pathEntry, ...args) {
  return runHelper(helper, cwd, args, {
    PATH: `${pathEntry}:${process.env.PATH}`,
  });
}

function versionPreload() {
  const preload = join(tempDir(), 'version-preload.cjs');
  writeFileSync(preload, `'use strict';
const version = process.env.JOSHIX_TEST_NODE_VERSION;
if (version) {
  Object.defineProperty(process.versions, 'node', {
    configurable: true,
    value: version,
  });
}
if (process.env.JOSHIX_TEST_UNRELATED_WARNING === '1') {
  setImmediate(() => process.emitWarning(
    'task-context unrelated warning sentinel',
    'ExperimentalWarning',
  ));
}
`);
  return preload;
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

function appendKeyed(root, folder, speaker, content, idempotencyKey) {
  const contentFile = join(tempDir(), 'keyed-message.md');
  writeFileSync(contentFile, content);
  const result = run(
    root,
    'append',
    folder,
    '--speaker',
    speaker,
    '--content-file',
    contentFile,
    '--idempotency-key',
    idempotencyKey,
  );
  return { result, id: Number(result.stdout.trim()) };
}

function spawnHelper(cwd, args) {
  return new Promise((resolvePromise) => {
    const child = spawn(helper, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('close', (status) => resolvePromise({ status, stdout, stderr }));
  });
}

test('the task-context command is executable in the working tree', () => {
  assert.notEqual(statSync(helper).mode & 0o111, 0);
});

test('both help flags execute directly from unrelated directories', () => {
  for (const flag of ['--help', '-h']) {
    const result = run(tempDir(), flag);
    assertSuccess(result);
    assert.match(result.stdout, /Usage: task-context/);
    assert.equal(result.stderr, '');
  }
});

test('direct execution supports helper and argument paths with spaces', () => {
  const parent = tempDir();
  const root = join(parent, 'repo with spaces');
  mkdirSync(root);
  git(root, 'init', '--quiet');
  git(root, 'config', 'user.email', 'task-context@example.com');
  git(root, 'config', 'user.name', 'Task Context Test');

  const copiedHelper = join(parent, 'helper dir with spaces', 'task context.mjs');
  mkdirSync(dirname(copiedHelper), { recursive: true });
  copyFileSync(helper, copiedHelper);
  chmodSync(copiedHelper, 0o755);

  const folder = '.joshix/tasks/task folder with spaces';
  const initialized = runHelper(copiedHelper, root, ['init', folder]);
  assertSuccess(initialized);
  assert.equal(initialized.stderr, '');

  const contentFile = join(parent, 'message files', 'message with spaces.md');
  mkdirSync(dirname(contentFile), { recursive: true });
  writeFileSync(contentFile, 'space-safe content');
  const appended = runHelper(copiedHelper, root, [
    'append',
    folder,
    '--speaker',
    'User',
    '--content-file',
    contentFile,
  ]);
  assertSuccess(appended);
  assert.equal(appended.stderr, '');
});

for (const version of ['18.0.0', '22.12.0']) {
  test(`version gate rejects simulated Node ${version} before SQLite loads`, () => {
    const result = runHelper(helper, repoRoot, ['--help'], {
      JOSHIX_TEST_NODE_VERSION: version,
      NODE_OPTIONS: `--require=${versionPreload()}`,
    });
    assert.notEqual(result.status, 0);
    assert.equal(
      result.stderr,
      `task-context: Node 22.13.0 or newer is required; found ${version}. Upgrade Node and retry.\n`,
    );
    assert.doesNotMatch(result.stderr, /SQLite/);
  });
}

test('SQLite warning is hidden while an unrelated warning remains visible', () => {
  const result = runHelper(helper, repoRoot, ['--help'], {
    JOSHIX_TEST_UNRELATED_WARNING: '1',
    NODE_OPTIONS: `--require=${versionPreload()}`,
  });
  assertSuccess(result);
  assert.doesNotMatch(result.stderr, /SQLite is an experimental feature/);
  assert.match(result.stderr, /task-context unrelated warning sentinel/);
});

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
    'elapsed',
    'export',
    'check',
  ]) {
    assert.match(result.stdout, new RegExp(`\\b${command}\\b`));
  }
  assert.match(result.stdout, /literal substring, ASCII case-insensitive/);
  assert.match(
    result.stdout,
    /elapsed \.joshix\/tasks\/example --now 2026-09-02T11:40:00\.000Z/,
  );
  assert.equal(existsSync(join(cwd, '.agents')), false);
  assert.equal(existsSync(join(cwd, '.joshix')), false);
});

test('init resolves relative paths from the Git root and protects them before use', () => {
  const root = initRepo();
  const nested = join(root, 'src/deep');
  mkdirSync(nested, { recursive: true });

  const result = run(nested, 'init', '.joshix/tasks/2026-07-22-CJ-66');
  assertSuccess(result);
  assert.equal(result.stderr, '');

  const task = join(root, '.joshix/tasks/2026-07-22-CJ-66');
  assert.equal(readFileSync(join(root, '.joshix/tasks/.gitignore'), 'utf8'), '*\n');
  assert.equal(
    git(root, 'check-ignore', '--no-index', '.joshix/tasks/.gitignore'),
    '.joshix/tasks/.gitignore',
  );
  assert.equal(
    git(root, 'check-ignore', '--no-index', '.joshix/tasks/2026-07-22-CJ-66/history.sqlite'),
    '.joshix/tasks/2026-07-22-CJ-66/history.sqlite',
  );
  assert.equal(git(root, 'status', '--porcelain', '--', '.joshix/tasks'), '');
  assert.equal(
    readFileSync(join(task, 'current.md'), 'utf8').includes('history_through: 0'),
    true,
  );

  const db = new DatabaseSync(join(task, 'history.sqlite'), { readOnly: true });
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, 2);
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
  mkdirSync(join(root, '.joshix/tasks'), { recursive: true });
  writeFileSync(join(root, '.joshix/tasks/.gitignore'), '# local note\nkeep-me\n');

  assertSuccess(run(root, 'init', '.joshix/tasks/2026-07-22-local'));

  assert.equal(
    readFileSync(join(root, '.joshix/tasks/.gitignore'), 'utf8'),
    '# local note\nkeep-me\n*\n',
  );
});

test('append does not rewrite an already-correct privacy ignore file', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-07-22-no-ignore-rewrite';
  assertSuccess(run(root, 'init', folder));
  const ignorePath = join(root, '.joshix/tasks/.gitignore');
  chmodSync(ignorePath, 0o444);

  const id = appendMessage(root, folder, 'User', 'preserve the ignore file');

  assert.equal(id, 1);
  assert.equal(readFileSync(ignorePath, 'utf8'), '*\n');
});

test('init refuses tracked task artifacts without changing the index', () => {
  const root = initRepo();
  mkdirSync(join(root, '.joshix/tasks/existing'), { recursive: true });
  writeFileSync(join(root, '.joshix/tasks/existing/leak.txt'), 'tracked');
  git(root, 'add', '-f', '.joshix/tasks/existing/leak.txt');
  const before = git(root, 'diff', '--cached', '--name-only');

  const result = run(root, 'init', '.joshix/tasks/2026-07-22-blocked');

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /tracked path/i);
  assert.equal(git(root, 'diff', '--cached', '--name-only'), before);
  assert.equal(
    existsSync(join(root, '.joshix/tasks/2026-07-22-blocked/history.sqlite')),
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

  const folder = '.joshix/tasks/2026-07-22-ignore-failure';
  const result = runWithPath(root, fakeBin, 'init', folder);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /privacy verification failed/i);
  assert.equal(existsSync(join(root, folder, 'history.sqlite')), false);
  assert.equal(existsSync(join(root, folder, 'current.md')), false);
});

test('relative init outside Git fails but an absolute path is an explicit opt-in', () => {
  const cwd = tempDir();
  const relative = run(cwd, 'init', '.joshix/tasks/2026-07-22-no-git');
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

test('Git-backed task paths reject the legacy .agents task root', () => {
  const root = initRepo();
  const legacyTask = join('.agents', 'tasks', '2026-07-23-legacy');
  const result = run(root, 'init', legacyTask);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /under \.joshix\/tasks\//);
  assert.equal(existsSync(join(root, legacyTask)), false);
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
  const targetTask = join(targetRoot, '.joshix/tasks/2026-07-22-other-repo');

  const result = run(sourceRoot, 'init', targetTask);

  assertSuccess(result);
  assert.equal(existsSync(join(targetTask, 'history.sqlite')), true);
  assert.equal(existsSync(join(sourceRoot, '.joshix/tasks')), false);
});

test('init refuses symlinked task paths before writing through them', () => {
  const root = initRepo();
  const outside = tempDir();
  mkdirSync(join(root, '.joshix'), { recursive: true });
  symlinkSync(outside, join(root, '.joshix/tasks'), 'dir');

  const result = run(root, 'init', '.joshix/tasks/2026-07-22-symlink');

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /symbolic link/i);
  assert.equal(existsSync(join(outside, '.gitignore')), false);
  assert.equal(existsSync(join(outside, '2026-07-22-symlink')), false);
});

test('repeated init preserves the exact folder, messages, files, and summary', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-07-22-CJ-66';
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
  const task = join(root, '.joshix/tasks/2026-07-22-invalid');
  mkdirSync(join(root, '.joshix/tasks'), { recursive: true });
  writeFileSync(join(root, '.joshix/tasks/.gitignore'), '*\n');
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
  const task = join(root, '.joshix/tasks/2026-07-22-wrong-index');
  mkdirSync(task, { recursive: true });
  writeFileSync(join(root, '.joshix/tasks/.gitignore'), '*\n');
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
  const folder = '.joshix/tasks/2026-07-22-history';
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

test('append without an idempotency key remains backward compatible', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-08-31-unkeyed-idempotency';
  assertSuccess(run(root, 'init', folder));

  assert.equal(appendMessage(root, folder, 'Reviewer', 'same review'), 1);
  assert.equal(appendMessage(root, folder, 'Reviewer', 'same review'), 2);
});

test('a repeated identical idempotency key returns the original message id', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-08-31-keyed-idempotency';
  assertSuccess(run(root, 'init', folder));
  const key = 'task|gate|1|same-model|sha256:abc';

  const first = appendKeyed(root, folder, 'Reviewer', '{"status":"approved"}', key);
  const second = appendKeyed(root, folder, 'Reviewer', '{"status":"approved"}', key);

  assertSuccess(first.result);
  assertSuccess(second.result);
  assert.equal(first.id, 1);
  assert.equal(second.id, 1);
  const db = new DatabaseSync(join(root, folder, 'history.sqlite'), { readOnly: true });
  assert.equal(db.prepare('SELECT count(*) AS count FROM messages').get().count, 1);
  db.close();
});

test('different content cannot reuse an idempotency key', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-08-31-key-collision';
  assertSuccess(run(root, 'init', folder));
  const key = 'task|gate|1|same-model|sha256:def';
  assertSuccess(appendKeyed(root, folder, 'Reviewer', 'first', key).result);

  const collision = appendKeyed(root, folder, 'Reviewer', 'different', key).result;

  assert.notEqual(collision.status, 0);
  assert.match(collision.stderr, /Idempotency key already belongs to different content\./);
});

test('distinct idempotency keys append distinct messages', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-08-31-distinct-idempotency';
  assertSuccess(run(root, 'init', folder));

  const first = appendKeyed(root, folder, 'Reviewer', 'review', 'key-one');
  const second = appendKeyed(root, folder, 'Reviewer', 'review', 'key-two');

  assertSuccess(first.result);
  assertSuccess(second.result);
  assert.deepEqual([first.id, second.id], [1, 2]);
});

test('init migrates a valid version 1 database to version 2 without data loss', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-08-31-version-1';
  const task = join(root, folder);
  mkdirSync(task, { recursive: true });
  writeFileSync(join(root, '.joshix/tasks/.gitignore'), '*\n');
  const db = new DatabaseSync(join(task, 'history.sqlite'));
  db.exec(`
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      speaker TEXT NOT NULL,
      content TEXT NOT NULL
    );
    CREATE INDEX messages_created_at_idx ON messages(created_at);
    INSERT INTO messages (speaker, content) VALUES ('User', 'preserve me');
    PRAGMA user_version = 1;
  `);
  db.close();

  assertSuccess(run(root, 'init', folder));

  const migrated = new DatabaseSync(join(task, 'history.sqlite'), { readOnly: true });
  assert.equal(migrated.prepare('PRAGMA user_version').get().user_version, 2);
  assert.equal(
    migrated.prepare('SELECT content FROM messages WHERE id = 1').get().content,
    'preserve me',
  );
  assert.deepEqual(
    migrated.prepare('PRAGMA table_info(messages)').all().map(({ name }) => name),
    ['id', 'created_at', 'speaker', 'content', 'idempotency_key'],
  );
  assert.equal(
    migrated.prepare("SELECT sql FROM sqlite_master WHERE name = 'messages_idempotency_key_idx'").get().sql.includes('WHERE idempotency_key IS NOT NULL'),
    true,
  );
  migrated.close();
});

test('concurrent init serializes and rechecks a version 1 migration', async () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-08-31-concurrent-version-1';
  const task = join(root, folder);
  mkdirSync(task, { recursive: true });
  writeFileSync(join(root, '.joshix/tasks/.gitignore'), '*\n');
  const databasePath = join(task, 'history.sqlite');
  const setup = new DatabaseSync(databasePath);
  setup.exec(`
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      speaker TEXT NOT NULL,
      content TEXT NOT NULL
    );
    CREATE INDEX messages_created_at_idx ON messages(created_at);
    INSERT INTO messages (speaker, content) VALUES ('User', 'preserve concurrently');
    PRAGMA user_version = 1;
  `);
  setup.close();

  const blocker = new DatabaseSync(databasePath);
  blocker.exec('BEGIN IMMEDIATE');
  const first = spawnHelper(root, ['init', folder]);
  const second = spawnHelper(root, ['init', folder]);
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 100));
  blocker.exec('COMMIT');
  blocker.close();

  const results = await Promise.all([first, second]);
  for (const result of results) assertSuccess(result);
  const migrated = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(migrated.prepare('PRAGMA user_version').get().user_version, 2);
  assert.equal(
    migrated.prepare('SELECT content FROM messages WHERE id = 1').get().content,
    'preserve concurrently',
  );
  migrated.close();
});

test('repeated init leaves a valid version 2 database unchanged', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-08-31-version-2';
  assertSuccess(run(root, 'init', folder));
  appendKeyed(root, folder, 'Reviewer', 'preserve', 'stable-key');
  const databasePath = join(root, folder, 'history.sqlite');
  const before = readFileSync(databasePath);

  assertSuccess(run(root, 'init', folder));

  assert.deepEqual(readFileSync(databasePath), before);
});

test('concurrent duplicate appends leave one keyed row', async () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-08-31-concurrent-duplicate';
  assertSuccess(run(root, 'init', folder));
  const contentFile = join(tempDir(), 'concurrent-review.json');
  writeFileSync(contentFile, '{"status":"approved","findings":[]}');
  const args = [
    'append', folder,
    '--speaker', 'Reviewer',
    '--content-file', contentFile,
    '--idempotency-key', 'task|gate|1|cross-provider|sha256:123',
  ];

  const results = await Promise.all([
    spawnHelper(root, args),
    spawnHelper(root, args),
  ]);

  for (const result of results) assertSuccess(result);
  assert.deepEqual(results.map(({ stdout }) => Number(stdout.trim())), [1, 1]);
  const db = new DatabaseSync(join(root, folder, 'history.sqlite'), { readOnly: true });
  assert.equal(db.prepare('SELECT count(*) AS count FROM messages').get().count, 1);
  db.close();
});

test('append rechecks privacy and refuses task data tracked after initialization', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-07-22-recheck';
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
  const folder = '.joshix/tasks/2026-07-22-retrieval';
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
  const folder = '.joshix/tasks/2026-07-22-time-search';
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

function seedTimedMessages(root, folder, rows) {
  assertSuccess(run(root, 'init', folder));
  const db = new DatabaseSync(join(root, folder, 'history.sqlite'));
  try {
    const insert = db.prepare('INSERT INTO messages (created_at, speaker, content) VALUES (?, ?, ?)');
    for (const row of rows) insert.run(row.createdAt, row.speaker, row.content ?? row.speaker);
  } finally {
    db.close();
  }
}

test('elapsed derives active time from adjacent history while excluding owner gaps', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-09-02-elapsed-basic';
  seedTimedMessages(root, folder, [
    { createdAt: '2026-09-02T10:00:00.000Z', speaker: 'User' },
    { createdAt: '2026-09-02T10:05:00.000Z', speaker: 'Codex' },
    { createdAt: '2026-09-02T10:35:00.000Z', speaker: 'Reviewer' },
    { createdAt: '2026-09-02T11:35:00.000Z', speaker: 'User' },
  ]);

  assert.deepEqual(stdoutJson(run(
    root,
    'elapsed', folder,
    '--now', '2026-09-02T11:40:00.000Z',
  )), {
    activeMs: 2_400_000,
    activeDuration: '40m',
    state: 'open',
    approximate: true,
    warning: null,
  });
});

test('elapsed subtracts matched and genuinely open external waits', () => {
  const root = initRepo();
  const matched = '.joshix/tasks/2026-09-02-elapsed-matched';
  seedTimedMessages(root, matched, [
    { createdAt: '2026-09-02T10:00:00.000Z', speaker: 'User' },
    { createdAt: '2026-09-02T10:05:00.000Z', speaker: 'Codex' },
    { createdAt: '2026-09-02T10:10:00.000Z', speaker: 'TaskMeta', content: '{"type":"joshix.external-wait","state":"paused","key":"db"}' },
    { createdAt: '2026-09-02T10:25:00.000Z', speaker: 'TaskMeta', content: '{"type":"joshix.external-wait","state":"resumed","key":"db"}' },
    { createdAt: '2026-09-02T10:35:00.000Z', speaker: 'Codex' },
  ]);
  const matchedResult = stdoutJson(run(root, 'elapsed', matched, '--now', '2026-09-02T10:40:00.000Z'));
  assert.equal(matchedResult.activeMs, 1_500_000);
  assert.equal(matchedResult.state, 'open');
  assert.equal(matchedResult.warning, null);

  const open = '.joshix/tasks/2026-09-02-elapsed-open-wait';
  seedTimedMessages(root, open, [
    { createdAt: '2026-09-02T10:00:00.000Z', speaker: 'User' },
    { createdAt: '2026-09-02T10:05:00.000Z', speaker: 'Codex' },
    { createdAt: '2026-09-02T10:10:00.000Z', speaker: 'TaskMeta', content: '{"type":"joshix.external-wait","state":"paused","key":"db"}' },
  ]);
  const openResult = stdoutJson(run(root, 'elapsed', open, '--now', '2026-09-02T10:40:00.000Z'));
  assert.equal(openResult.activeMs, 600_000);
  assert.equal(openResult.state, 'closed');
  assert.match(openResult.warning, /external wait remains open/i);
});

test('elapsed ignores a forgotten pause after later activity and fails unknown on malformed metadata', () => {
  const root = initRepo();
  const stale = '.joshix/tasks/2026-09-02-elapsed-stale-wait';
  seedTimedMessages(root, stale, [
    { createdAt: '2026-09-02T10:00:00.000Z', speaker: 'User' },
    { createdAt: '2026-09-02T10:05:00.000Z', speaker: 'TaskMeta', content: '{"type":"joshix.external-wait","state":"paused","key":"db"}' },
    { createdAt: '2026-09-02T10:20:00.000Z', speaker: 'Codex' },
    { createdAt: '2026-09-02T11:20:00.000Z', speaker: 'Reviewer' },
  ]);
  const staleResult = stdoutJson(run(root, 'elapsed', stale, '--now', '2026-09-02T11:25:00.000Z'));
  assert.equal(staleResult.activeMs, 5_100_000);
  assert.equal(staleResult.state, 'open');
  assert.match(staleResult.warning, /unmatched external pause was ignored after later activity/i);

  const malformed = '.joshix/tasks/2026-09-02-elapsed-malformed';
  seedTimedMessages(root, malformed, [
    { createdAt: '2026-09-02T10:00:00.000Z', speaker: 'User' },
    { createdAt: '2026-09-02T10:05:00.000Z', speaker: 'TaskMeta', content: '{"type":"joshix.external-wait","state":"resumed","key":"missing"}' },
  ]);
  const malformedResult = stdoutJson(run(root, 'elapsed', malformed, '--now', '2026-09-02T10:10:00.000Z'));
  assert.equal(malformedResult.activeMs, null);
  assert.equal(malformedResult.state, 'unknown');
  assert.match(malformedResult.warning, /resume/i);
});

test('elapsed is read-only and reports malformed history instead of false precision', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-09-02-elapsed-integrity';
  seedTimedMessages(root, folder, [
    { createdAt: '2026-09-02T10:00:00.000Z', speaker: 'User' },
    { createdAt: '2026-09-02T10:05:00.000Z', speaker: 'TaskMeta', content: '{"type":"joshix.external-wait","state":"paused","key":"db"}' },
    { createdAt: '2026-09-02T10:06:00.000Z', speaker: 'TaskMeta', content: '{"type":"joshix.external-wait","state":"paused","key":"db"}' },
  ]);
  const databasePath = join(root, folder, 'history.sqlite');
  const before = readFileSync(databasePath);

  const duplicatePause = stdoutJson(run(root, 'elapsed', folder, '--now', '2026-09-02T10:10:00.000Z'));
  assert.equal(duplicatePause.activeMs, null);
  assert.equal(duplicatePause.state, 'unknown');
  assert.match(duplicatePause.warning, /duplicate pause/i);
  assert.deepEqual(readFileSync(databasePath), before);

  const malformedFolder = '.joshix/tasks/2026-09-02-elapsed-malformed-time';
  seedTimedMessages(root, malformedFolder, [
    { createdAt: 'not-a-time', speaker: 'User' },
  ]);
  const malformedTime = stdoutJson(run(root, 'elapsed', malformedFolder, '--now', '2026-09-02T10:10:00.000Z'));
  assert.equal(malformedTime.activeMs, null);
  assert.equal(malformedTime.state, 'unknown');
  assert.match(malformedTime.warning, /timestamps/i);
});

test('export preserves ordering and bodies, and check is read-only', () => {
  const root = initRepo();
  const folder = '.joshix/tasks/2026-07-22-export';
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
    schemaVersion: 2,
  });
  assert.deepEqual(readFileSync(join(task, 'history.sqlite')), before);
});
