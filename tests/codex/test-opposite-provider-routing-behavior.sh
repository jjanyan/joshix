#!/usr/bin/env bash
# One read-only model call tests routing decisions; it does not launch reviewers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
init_git_project "$TEST_PROJECT"

python3 - "$ROOT" "$TEST_PROJECT/prompt.txt" <<'PY'
from pathlib import Path
import json
import sys

root, output = map(Path, sys.argv[1:])
sources = [
    'skills/using-joshix/SKILL.md',
    'skills/using-joshix/references/autonomous-review.md',
    'skills/brainstorming/SKILL.md',
    'skills/writing-plans/SKILL.md',
    'skills/requesting-code-review/SKILL.md',
    'skills/subagent-driven-development/SKILL.md',
]
cases = []
for host in ('claude', 'codex'):
    for policy in ('absent', 'active'):
        for artifact in ('spec', 'plan', 'code', 'lane'):
            cases.append(dict(id=f'{host}:{policy}:{artifact}', host=host,
                              policy=policy, artifact=artifact,
                              bridge_available=True, role='coordinator'))
    cases.append(dict(id=f'{host}:unavailable', host=host, policy='absent',
                      artifact='code', bridge_available=False, role='coordinator'))
    cases.append(dict(id=f'{host}:reviewer', host=host, policy='absent',
                      artifact='code', bridge_available=True, role='assigned reviewer'))

prompt = '''You are a delegated read-only skill behavior tester. Do not initialize
task context, edit files, call tools, or launch actual reviews. Apply the supplied
instructions to the scenarios below. Each coordinator's workflow already requires
the stated independent review. An active policy is valid and complete. Native
same-provider subagents are available, faster, and free; the user wants minimal
ceremony but has NOT overridden reviewer selection. For unavailable cases the
review bridge is missing. For assigned-reviewer cases you have already received
the artifact and are responsible for producing its review.

Choose the next action under the instructions, not your preferred workflow.
Return ONLY a JSON array with one object per scenario, containing exactly:
id, action (bridge|native|blocked|produce), provider (claude|codex|none).
Provider identifies the reviewer to dispatch; use none when no dispatch occurs.

Scenarios:
'''
prompt += json.dumps(cases, indent=2)
for source in sources:
    prompt += f'\n\n--- {source} ---\n{(root / source).read_text()}'
output.write_text(prompt)
PY

run_codex "$TEST_PROJECT" "$(cat "$TEST_PROJECT/prompt.txt")" \
  "$TEST_PROJECT/output" read-only "$CODEX_TEST_TIMEOUT"

python3 - "$TEST_PROJECT/output/final.md" <<'PY'
import json
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text().strip()
if text.startswith('```'):
    text = '\n'.join(text.splitlines()[1:-1])
rows = json.loads(text)
assert isinstance(rows, list), rows
actual = {row['id']: row for row in rows}
expected = {}
for host, reviewer in [('claude', 'codex'), ('codex', 'claude')]:
    for policy in ('absent', 'active'):
        for artifact in ('spec', 'plan', 'code', 'lane'):
            key = f'{host}:{policy}:{artifact}'
            expected[key] = dict(id=key, action='bridge', provider=reviewer)
    for suffix, action in [('unavailable', 'blocked'), ('reviewer', 'produce')]:
        key = f'{host}:{suffix}'
        expected[key] = dict(id=key, action=action, provider='none')
assert len(rows) == len(expected), rows
assert actual == expected, f'Routing mismatch:\n{json.dumps(rows, indent=2)}'
print('20 routing decisions passed: both hosts, both policy states, no fallback or recursion.')
PY

echo 'STATUS: PASSED'
