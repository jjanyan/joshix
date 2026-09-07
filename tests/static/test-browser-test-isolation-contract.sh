#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
node - "$ROOT/skills/using-joshix/SKILL.md" <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const text = fs.readFileSync(process.argv[2], 'utf8').replace(/\s+/g, ' ');
for (const rule of [
  'Use an isolated headless browser for automated testing by default.',
  "login for testing unless he explicitly requests that browser session.",
  'Do not copy his browser profile or login into a test session to bypass this rule.',
  'If a check requires a visible browser, use a separate test browser/profile.',
  'A hidden tab is not proof of isolation.',
  'headless tooling, or a failed isolated run never authorizes a live-browser fallback.',
  'report the concrete blocker and which checks remain unverified.',
  'This rule governs automated testing.',
  'Explicit live-session requests remain limited to the requested tabs and actions.',
]) assert(text.includes(rule), `Missing browser contract: ${rule}`);
console.log('PASS: bootstrap browser-isolation contract');
NODE
bash "$ROOT/tests/codex/test-browser-test-isolation-behavior.sh" --oracle-only
