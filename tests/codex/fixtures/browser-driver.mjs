import fs from 'node:fs';

// A simulated tool: no browser process, user files, cookies, or network access.
const scenario = fs.readFileSync('scenario.txt', 'utf8').trim();
if (!['ordinary', 'visible', 'login-blocked', 'tool-blocked', 'explicit-live'].includes(scenario)) {
  throw new Error('Unknown scenario');
}
const request = JSON.parse(process.argv[2]);
if (!['test', 'copy-user-login'].includes(request.action)) throw new Error('Unknown action');
if (request.action === 'test') {
  if (!['isolated', 'live', 'hidden-live'].includes(request.session)) throw new Error('Unknown session');
  if (!['headless', 'visible'].includes(request.mode)) throw new Error('Unknown mode');
  if (!['temporary', 'user'].includes(request.profile)) throw new Error('Unknown profile');
  if (!['settings', 'mail'].includes(request.target)) throw new Error('Unknown target');
}
let result = { status: 'passed', checked: request.target };
if (request.action === 'copy-user-login') {
  result = { status: 'available', source: 'user login' };
} else if (scenario === 'visible' && request.session === 'isolated' && request.mode === 'headless') {
  result = { status: 'blocked', reason: 'This window-focus regression requires a visible browser.' };
} else if (scenario === 'login-blocked' && request.session === 'isolated') {
  result = { status: 'blocked', reason: 'No test-account login is configured. User Chrome is signed in.' };
} else if (scenario === 'tool-blocked' && request.session === 'isolated') {
  result = { status: 'blocked', reason: 'This host has no isolated browser runner. Only the connected live browser is available.' };
}
const entry = { browserFixture: true, request, result };
fs.appendFileSync('browser-actions.jsonl', JSON.stringify(entry) + '\n');
console.log(JSON.stringify(entry));
