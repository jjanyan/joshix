import { access, link, lstat, open, rm, stat } from 'node:fs/promises';
import { constants, realpathSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { basename, dirname, extname, join, resolve } from 'node:path';

const pluginRoot = fileURLToPath(new URL('../../../', import.meta.url));
const references = join(pluginRoot, 'skills/using-joshix/references');
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function usage(message) {
  throw new Error(`${message}\nUsage: node render-mermaid.mjs --output /path/to/dag.png < diagram.mmd`);
}

function parseOutput(args) {
  if (args.length !== 2 || args[0] !== '--output') usage('Expected exactly --output <path.png>.');

  const output = resolve(args[1]);
  if (extname(output).toLowerCase() !== '.png') usage('Output path must end in .png.');
  return output;
}

function normalizeSource(input) {
  const trimmed = input.trim();
  const fenced = /^```mermaid\s*\r?\n([\s\S]*?)\r?\n?```\s*$/.exec(trimmed);
  if (fenced) return fenced[1].trim();
  if (!trimmed || trimmed.includes('```')) usage('Input must be raw Mermaid or exactly one complete ```mermaid fence.');
  return trimmed;
}

async function pathExists(path) {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

async function entryExists(path) {
  try {
    await lstat(path);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

async function assertPng(path) {
  const file = await open(path, 'r');
  try {
    const signature = Buffer.alloc(pngSignature.length);
    const { bytesRead } = await file.read(signature, 0, signature.length, 0);
    if (bytesRead !== pngSignature.length || !signature.equals(pngSignature)) {
      throw new Error('Mermaid renderer did not produce a valid PNG.');
    }
  } finally {
    await file.close();
  }
}

async function rendererCommand() {
  const local = join(pluginRoot, 'node_modules/.bin', process.platform === 'win32' ? 'mmdc.cmd' : 'mmdc');
  if (await pathExists(local)) return { command: local, args: [], fallback: false };
  return {
    command: process.platform === 'win32' ? 'npx.cmd' : 'npx',
    args: ['--yes', '--package', '@mermaid-js/mermaid-cli@11.16.0', 'mmdc'],
    fallback: true,
  };
}

export function rendererArguments(output) {
  return [
    '--input', '-',
    '--output', output,
    '--scale', '2',
    '--configFile', join(references, 'mermaid-dark-config.json'),
    '--cssFile', join(references, 'mermaid-dark.css'),
    '--backgroundColor', '#171717',
  ];
}

function readStdin() {
  return new Promise((resolveInput, reject) => {
    let input = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => { input += chunk; });
    process.stdin.on('end', () => resolveInput(input));
    process.stdin.on('error', reject);
  });
}

export function rendererSpawn(command, args, platform = process.platform) {
  if (platform !== 'win32') return { command, args };
  const encodedCommand = Buffer.from(command, 'utf8').toString('base64');
  const encodedArguments = Buffer.from(JSON.stringify(args), 'utf8').toString('base64');
  const script = [
    "$ErrorActionPreference = 'Stop'",
    `$command = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encodedCommand}'))`,
    `$arguments = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encodedArguments}')) | ConvertFrom-Json`,
    'try { & $command @arguments; if ($null -eq $LASTEXITCODE) { exit 1 }; exit $LASTEXITCODE } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }',
  ].join('; ');
  return {
    command: 'powershell.exe',
    args: ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')],
  };
}

async function runRenderer(command, args, source) {
  await new Promise((resolveRun, reject) => {
    const renderer = rendererSpawn(command, args);
    const child = spawn(renderer.command, renderer.args, { stdio: ['pipe', 'pipe', 'pipe'] });
    const stderr = [];
    child.on('error', reject);
    child.stdout.on('data', (chunk) => process.stderr.write(chunk));
    child.stderr.on('data', (chunk) => {
      stderr.push(chunk);
      process.stderr.write(chunk);
    });
    child.on('close', (code) => {
      if (code === 0) resolveRun();
      else reject(Object.assign(new Error(`Mermaid renderer exited with status ${code}.`), {
        exitCode: code,
        stderr: Buffer.concat(stderr).toString('utf8'),
      }));
    });
    child.stdin.end(source);
  });
}

export function isProvisioningFailure(error) {
  const diagnostic = [error?.code, error?.stderr, error?.message].filter(Boolean).join('\n');
  return error?.code === 'ENOENT' || /npm (?:ERR!|error) code|EAI_AGAIN|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|ECONNRESET|could not determine executable to run|is not recognized as the name of a cmdlet/i.test(diagnostic);
}

async function main() {
  const output = parseOutput(process.argv.slice(2));
  const source = normalizeSource(await readStdin());
  const parent = dirname(output);
  const targetName = basename(output, '.png');
  const temporary = join(parent, `.${targetName}.${randomUUID()}.tmp.png`);

  try {
    if (!(await stat(parent)).isDirectory()) usage('Output parent directory must exist and be writable.');
    await access(parent, constants.W_OK);
  } catch (error) {
    if (error.message?.includes('Output parent directory')) throw error;
    usage('Output parent directory must exist and be writable.');
  }
  if (await entryExists(output)) usage('Output path already exists.');

  try {
    const renderer = await rendererCommand();
    try {
      await runRenderer(renderer.command, [...renderer.args, ...rendererArguments(temporary)], source);
    } catch (error) {
      if (renderer.fallback && isProvisioningFailure(error)) {
        throw new Error(`${error.message}\nRenderer could not be provisioned. Restore network access or run npm install in the joshix plugin root.`);
      }
      throw error;
    }

    await assertPng(temporary);
    try {
      await link(temporary, output);
    } catch (error) {
      if (error.code === 'EEXIST') usage('Output path already exists.');
      throw error;
    }
    process.stdout.write(`${output}\n`);
  } finally {
    await rm(temporary, { force: true });
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
