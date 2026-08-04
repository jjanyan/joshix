import assert from 'node:assert/strict';
import { access, lstat, mkdtemp, readFile, symlink, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { inflateSync } from 'node:zlib';
import test from 'node:test';
import { rendererArguments } from '../../skills/using-joshix/scripts/render-mermaid.mjs';

const repoRoot = resolve(import.meta.dirname, '../..');
const helper = join(repoRoot, 'skills/using-joshix/scripts/render-mermaid.mjs');
const darkConfig = join(repoRoot, 'skills/using-joshix/references/mermaid-dark-config.json');
const darkCss = join(repoRoot, 'skills/using-joshix/references/mermaid-dark.css');
const source = 'flowchart LR\n  P["Plan"] --> R["Render"] --> I["Inspect"]\n';
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function runRenderer({ executable = helper, args = [], stdin = '' }) {
  return new Promise((resolveRun, reject) => {
    const child = spawn(process.execPath, [executable, ...args], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const stdout = [];
    const stderr = [];

    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.on('error', reject);
    child.on('close', (code) => {
      resolveRun({
        code,
        stdout: Buffer.concat(stdout).toString('utf8'),
        stderr: Buffer.concat(stderr).toString('utf8'),
      });
    });
    child.stdin.end(stdin);
  });
}

function firstPixel(png) {
  let offset = pngSignature.length;
  let bitDepth;
  let colorType;
  let interlace;
  const compressed = [];

  while (offset < png.length) {
    const length = png.readUInt32BE(offset);
    const type = png.subarray(offset + 4, offset + 8).toString('ascii');
    const data = png.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      bitDepth = data[8];
      colorType = data[9];
      interlace = data[12];
    }
    if (type === 'IDAT') compressed.push(data);
    offset += 12 + length;
  }

  assert.equal(bitDepth, 8, 'expected 8-bit PNG output');
  assert.ok(colorType === 2 || colorType === 6, 'expected RGB or RGBA PNG output');
  assert.equal(interlace, 0, 'expected non-interlaced PNG output');
  return inflateSync(Buffer.concat(compressed)).subarray(1, 4);
}

async function renderAndAssertPng(stdin, name) {
  const directory = await mkdtemp(join(tmpdir(), 'joshix-mermaid-test-'));
  const output = join(directory, `${name}.png`);
  const result = await runRenderer({ args: ['--output', output], stdin });

  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, `${output}\n`);
  const png = await readFile(output);
  assert.deepEqual(png.subarray(0, 8), pngSignature);
  assert.deepEqual(firstPixel(png), Buffer.from([0x17, 0x17, 0x17]));
}

test('renders raw Mermaid stdin to the requested PNG path', { timeout: 120_000 }, async () => {
  await renderAndAssertPng(source, 'raw');
});

test('renders exactly one fenced Mermaid block', { timeout: 120_000 }, async () => {
  await renderAndAssertPng(`\`\`\`mermaid\n${source}\`\`\`\n`, 'fenced');
});

test('bundles the dark rendering assets used by the helper', async () => {
  await access(darkConfig, constants.R_OK);
  await access(darkCss, constants.R_OK);
  assert.match(await readFile(darkConfig, 'utf8'), /"background": "#171717"/);
  assert.match(await readFile(darkCss, 'utf8'), /svg \{ background: #171717; \}/);
});

test('passes both bundled dark assets to Mermaid CLI', () => {
  const args = rendererArguments('/tmp/diagram.png');
  assert.equal(args[args.indexOf('--configFile') + 1], darkConfig);
  assert.equal(args[args.indexOf('--cssFile') + 1], darkCss);
  assert.equal(args.includes('--width'), false);
});

test('renders when invoked through a symlinked script path', { skip: process.platform === 'win32', timeout: 120_000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'joshix-mermaid-test-'));
  const scripts = join(directory, 'scripts');
  const output = join(directory, 'symlinked.png');
  await symlink(dirname(helper), scripts);

  const result = await runRenderer({
    executable: join(scripts, 'render-mermaid.mjs'),
    args: ['--output', output],
    stdin: source,
  });

  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, `${output}\n`);
  assert.deepEqual((await readFile(output)).subarray(0, 8), pngSignature);
});

test('rejects missing, non-PNG, and existing output paths', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'joshix-mermaid-test-'));
  const existing = join(directory, 'existing.png');
  await writeFile(existing, 'keep');

  for (const args of [[], ['--output', join(directory, 'diagram.svg')], ['--output', existing]]) {
    const result = await runRenderer({ args, stdin: source });
    assert.notEqual(result.code, 0);
    assert.equal(result.stdout, '');
  }
});

test('rejects a dangling symlink output path without replacing it', { skip: process.platform === 'win32' }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'joshix-mermaid-test-'));
  const output = join(directory, 'dangling.png');
  await symlink(join(directory, 'missing.png'), output);

  const result = await runRenderer({ args: ['--output', output], stdin: source });

  assert.notEqual(result.code, 0);
  assert.equal(result.stdout, '');
  assert.ok((await lstat(output)).isSymbolicLink());
});

test('classifies only fallback bootstrap failures as provisioning failures', async () => {
  const program = `
    import { isProvisioningFailure } from ${JSON.stringify(pathToFileURL(helper).href)};
    console.log(isProvisioningFailure({ code: 'ENOENT' }));
    console.log(isProvisioningFailure({ stderr: 'npm error code EAI_AGAIN' }));
    console.log(isProvisioningFailure({ stderr: 'npx.cmd is not recognized as the name of a cmdlet' }));
    console.log(isProvisioningFailure({ stderr: 'Parse error on line 2' }));
  `;
  const result = await new Promise((resolveRun, reject) => {
    const child = spawn(process.execPath, ['--input-type=module', '--eval', program], { stdio: ['ignore', 'pipe', 'pipe'] });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.on('error', reject);
    child.on('close', (code) => resolveRun({ code, stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8') }));
  });

  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, 'true\ntrue\ntrue\nfalse\n');
});

test('uses an encoded PowerShell argument array for Windows command shims', async () => {
  const program = `
    import { rendererSpawn } from ${JSON.stringify(pathToFileURL(helper).href)};
    const result = rendererSpawn('npx.cmd', ['--output', 'C:\\\\temp\\\\%TEMP% & graph\\\\dag.png'], 'win32');
    console.log(JSON.stringify(result));
  `;
  const result = await new Promise((resolveRun, reject) => {
    const child = spawn(process.execPath, ['--input-type=module', '--eval', program], { stdio: ['ignore', 'pipe', 'pipe'] });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.on('error', reject);
    child.on('close', (code) => resolveRun({ code, stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8') }));
  });

  assert.equal(result.code, 0, result.stderr);
  const command = JSON.parse(result.stdout);
  assert.equal(command.command, 'powershell.exe');
  assert.deepEqual(command.args.slice(0, 5), ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand']);
  const script = Buffer.from(command.args[5], 'base64').toString('utf16le');
  assert.match(script, /& \$command @arguments/);
  assert.doesNotMatch(script, /%TEMP%|& graph/);
});
