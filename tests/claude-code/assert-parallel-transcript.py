#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path


def run_self_test():
    analyzer = str(Path(__file__).resolve())

    def use(identifier, description, prompt="", name="Task"):
        return {
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": name,
                        "id": identifier,
                        "input": {
                            "description": description,
                            "prompt": prompt,
                        },
                    }
                ]
            },
        }

    def result(identifier, text="", is_error=False, status=None):
        event = {
            "type": "user",
            "message": {
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": identifier,
                        "content": text,
                        "is_error": is_error,
                    }
                ]
            },
        }
        if status is not None:
            event["toolUseResult"] = {"status": status}
        return event

    def notification_body(identifier, text, status):
        return (
            "<task-notification>\n"
            f"<task-id>a{identifier}</task-id>\n"
            f"<tool-use-id>{identifier}</tool-use-id>\n"
            f"<status>{status}</status>\n"
            f"<result>{text}</result>\n"
            "</task-notification>"
        )

    def notification(identifier, text="", status="completed"):
        return {
            "type": "user",
            "message": {"content": notification_body(identifier, text, status)},
        }

    def queued_notification(
        identifier, text="", status="completed", operation="enqueue"
    ):
        return {
            "type": "queue-operation",
            "operation": operation,
            "content": notification_body(identifier, text, status),
        }

    def task_three_and_closeout_events():
        return [
            use("i3", "Implement Task 3: Public module integration"),
            result("i3", "DONE"),
            use("s3", "Spec review Task 3: Public module integration"),
            result("s3", "SPEC OUTCOME: PASS"),
            use("q3", "Quality review Task 3: Public module integration"),
            result("q3", "QUALITY OUTCOME: APPROVED"),
            use("w1", "Whole-change review: math library"),
            result("w1", "QUALITY OUTCOME: APPROVED"),
        ]

    def synchronous_events():
        return [
            use("i1", "Implement Task 1: Add operation"),
            use("i2", "Implement Task 2: Multiply operation", name="Agent"),
            result("i1", "DONE"),
            result("i2", "DONE"),
            use("s1", "Spec review Task 1: Add operation"),
            result("s1", "SPEC OUTCOME: PASS"),
            use("q1", "Quality review Task 1: Add operation"),
            result("q1", "QUALITY OUTCOME: APPROVED"),
            use("s2", "Spec review Task 2: Multiply operation"),
            result("s2", "SPEC OUTCOME: PASS"),
            use("q2", "Quality review Task 2: Multiply operation"),
            result("q2", "QUALITY OUTCOME: APPROVED"),
            *task_three_and_closeout_events(),
        ]

    cases = []
    cases.append(
        (
            "synchronous completion",
            synchronous_events(),
            "independent",
            0,
            "Both quality reviews approved",
        )
    )

    events = synchronous_events()
    events[2:3] = [
        result("i1", "launched", status="async_launched"),
        result("i1", "DONE", status="completed"),
    ]
    cases.append(
        (
            "async launch then completion",
            events,
            "independent",
            0,
            "Both quality reviews approved",
        )
    )

    events = [
        use("i1", "Implement Task 1: Add operation"),
        use("i2", "Implement Task 2: Multiply operation"),
        result("i1", "launched", status="async_launched"),
        result("i2", "launched", status="async_launched"),
        notification("i1", "Status: DONE"),
        notification("i2", "Status: DONE"),
        use("s1", "Spec review Task 1: Add operation"),
        result("s1", "launched", status="async_launched"),
        notification("s1", "Reviewed.\nSPEC OUTCOME: PASS"),
        use("q1", "Quality review Task 1: Add operation"),
        result("q1", "launched", status="async_launched"),
        notification("q1", "Reviewed.\nQUALITY OUTCOME: APPROVED"),
        use("s2", "Spec review Task 2: Multiply operation"),
        result("s2", "launched", status="async_launched"),
        notification("s2", "Reviewed.\nSPEC OUTCOME: PASS"),
        use("q2", "Quality review Task 2: Multiply operation"),
        result("q2", "launched", status="async_launched"),
        notification("q2", "Reviewed.\nQUALITY OUTCOME: APPROVED"),
        *task_three_and_closeout_events(),
    ]
    cases.append(
        (
            "async agents completed via task-notification events",
            events,
            "independent",
            0,
            "Both quality reviews approved",
        )
    )

    events = [
        use("i1", "Implement Task 1: Add operation"),
        use("i2", "Implement Task 2: Multiply operation"),
        result("i1", "launched", status="async_launched"),
        result("i2", "launched", status="async_launched"),
        queued_notification("i1", "Status: DONE"),
        queued_notification("i2", "Status: DONE"),
        use("s1", "Spec review Task 1: Add operation"),
        result("s1", "launched", status="async_launched"),
        queued_notification("s1", "Reviewed.\nSPEC OUTCOME: PASS"),
        use("q1", "Quality review Task 1: Add operation"),
        result("q1", "launched", status="async_launched"),
        queued_notification("q1", "Reviewed.\nQUALITY OUTCOME: APPROVED"),
        use("s2", "Spec review Task 2: Multiply operation"),
        result("s2", "launched", status="async_launched"),
        queued_notification("s2", "Reviewed.\nSPEC OUTCOME: PASS"),
        use("q2", "Quality review Task 2: Multiply operation"),
        result("q2", "launched", status="async_launched"),
        queued_notification("q2", "Reviewed.\nQUALITY OUTCOME: APPROVED"),
        *task_three_and_closeout_events(),
    ]
    cases.append(
        (
            "undelivered queued notifications still prove completion",
            events,
            "independent",
            0,
            "Both quality reviews approved",
        )
    )

    events = [
        use("i1", "Implement Task 1: Add operation"),
        use("i2", "Implement Task 2: Multiply operation"),
        result("i1", "launched", status="async_launched"),
        result("i2", "launched", status="async_launched"),
        notification("i1", "Status: DONE"),
        notification("i2", "Status: DONE", status="failed"),
        use("s1", "Spec review Task 1: Add operation"),
        result("s1", "SPEC OUTCOME: PASS"),
    ]
    cases.append(
        (
            "non-completed task-notification status is not a completion",
            events,
            "independent",
            1,
            "no successful completed implementer",
        )
    )

    events = synchronous_events()
    events[2:4] = [
        result("i1", "launched", status="async_launched"),
        result("i2", "launched", status="async_launched"),
        queued_notification(
            "i1", "Status: DONE", operation="remove"
        ),
        queued_notification(
            "i2", "Status: DONE", operation="remove"
        ),
    ]
    cases.append(
        (
            "removed queued notifications are not completions",
            events,
            "independent",
            1,
            "no successful completed implementer",
        )
    )

    events = synchronous_events()
    events.insert(5, result("i1", "DONE again", status="completed"))
    cases.append(
        (
            "later duplicate completion preserves first completed event",
            events,
            "independent",
            0,
            "Both quality reviews approved",
        )
    )

    events = synchronous_events()
    events[2] = result("i1", "launched", status="async_launched")
    cases.append(
        (
            "async launch without completion",
            events,
            "independent",
            1,
            "no successful completed implementer",
        )
    )

    events = synchronous_events()
    events[2] = result("i1", "still running", status="running")
    cases.append(
        (
            "unknown non-completed status",
            events,
            "independent",
            1,
            "no successful completed implementer",
        )
    )

    events = [
        use("i1", "Implement Task 1: Add operation"),
        use("i2", "Implement Task 2: Multiply operation"),
        result("i1", "launched", status="async_launched"),
        result("i2", "DONE", status="completed"),
        use("s1", "Spec review Task 1: Add operation"),
        result("i1", "DONE", status="completed"),
        result("s1", "SPEC OUTCOME: PASS"),
        use("q1", "Quality review Task 1: Add operation"),
        result("q1", "QUALITY OUTCOME: APPROVED"),
        use("s2", "Spec review Task 2: Multiply operation"),
        result("s2", "SPEC OUTCOME: PASS"),
        use("q2", "Quality review Task 2: Multiply operation"),
        result("q2", "QUALITY OUTCOME: APPROVED"),
        use("i3", "Implement Task 3: Public module integration"),
    ]
    cases.append(
        (
            "spec starts before implementer completion",
            events,
            "independent",
            1,
            "spec review started before implementer completed",
        )
    )

    events = synchronous_events()
    events[5] = result("s1", "No outcome marker")
    cases.append(
        (
            "missing spec outcome",
            events,
            "independent",
            1,
            "no successful PASS spec-review",
        )
    )

    events = synchronous_events()
    events[5] = result(
        "s1",
        "SPEC OUTCOME: PASS\nSPEC OUTCOME: PASS",
    )
    cases.append(
        (
            "duplicate spec outcome",
            events,
            "independent",
            1,
            "no successful PASS spec-review",
        )
    )

    events = synchronous_events()
    events[7] = result(
        "q1",
        "QUALITY OUTCOME: APPROVED\n"
        "QUALITY OUTCOME: CHANGES REQUIRED",
    )
    cases.append(
        (
            "contradictory quality outcome",
            events,
            "independent",
            1,
            "no successful APPROVED quality-review",
        )
    )

    events = synchronous_events()[:-2]
    cases.append(
        (
            "missing whole-change review",
            events,
            "independent",
            1,
            "no whole-change review tool use found",
        )
    )

    events = synchronous_events()
    whole_change_use = events.pop(18)
    events.insert(17, whole_change_use)
    cases.append(
        (
            "whole-change review starts before Task 3 quality approval",
            events,
            "independent",
            1,
            "whole-change review started before Task 3 quality review approved",
        )
    )

    cases.append(
        (
            "coupled zero dispatch",
            [],
            "coupled",
            0,
            "No Agent/Task calls were dispatched.",
        )
    )
    cases.append(
        (
            "coupled generic dispatch",
            [use("generic", "Background work")],
            "coupled",
            1,
            "coupled execution dispatched Agent/Task call",
        )
    )

    failures = 0
    for name, events, mode, expected_code, expected_text in cases:
        payload = "\n".join(json.dumps(event) for event in events) + "\n"
        completed = subprocess.run(
            [sys.executable, analyzer, "/dev/stdin", mode],
            input=payload,
            text=True,
            capture_output=True,
            check=False,
        )
        output = completed.stdout + completed.stderr
        if (
            completed.returncode == expected_code
            and expected_text in output
        ):
            print(f"PASS: {name}")
        else:
            print(
                f"FAIL: {name} (exit {completed.returncode})\n{output}",
                file=sys.stderr,
            )
            failures += 1

    if failures:
        print(f"STATUS: FAILED ({failures} oracle fixtures)", file=sys.stderr)
        return 1
    print("STATUS: PASSED")
    return 0


if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
    sys.exit(run_self_test())

if len(sys.argv) != 3 or sys.argv[2] not in {"independent", "coupled"}:
    print(
        "Usage: assert-parallel-transcript.py SESSION.jsonl "
        "independent|coupled",
        file=sys.stderr,
    )
    sys.exit(2)

session_path = Path(sys.argv[1])
mode = sys.argv[2]
uses = []
results = {}


def classify_role(description):
    lowered = description.lower()
    if re.search(r"\bwhole[- ]change review\b", lowered):
        return "whole-change-reviewer"
    if re.match(r"spec review task\s+[123]:", lowered):
        return "spec-reviewer"
    if re.match(r"quality review task\s+[123]:", lowered):
        return "quality-reviewer"
    if re.match(r"implement task\s+[123]:", lowered):
        return "implementer"
    return "other"


def classify_lane(text):
    lowered = text.lower()
    task_match = re.search(r"\btask\s*([123])\b", lowered)
    if task_match:
        return task_match.group(1)
    if "add.js" in lowered or "add operation" in lowered:
        return "1"
    if "multiply.js" in lowered or "multiply operation" in lowered:
        return "2"
    if "index.js" in lowered or "public module" in lowered:
        return "3"
    return None


def extract_text(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(extract_text(item) for item in value)
    if isinstance(value, dict):
        if "text" in value:
            return extract_text(value["text"])
        if "content" in value:
            return extract_text(value["content"])
    return ""


def has_exact_outcome(review_result, label, expected_value):
    marker_values = [
        re.sub(r"\s+", " ", match.group(1)).strip().upper()
        for match in re.finditer(
            rf"^\s*{re.escape(label)}\s*:\s*(.*?)\s*$",
            review_result["text"],
            flags=re.IGNORECASE | re.MULTILINE,
        )
    ]
    return (
        len(marker_values) == 1
        and marker_values[0] == expected_value.upper()
    )


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


NOTIFICATION_PATTERN = re.compile(
    r"<task-notification>(.*?)</task-notification>", re.DOTALL
)


def iter_task_notifications(text):
    """Yield (tool_use_id, status, result_text) for each async agent
    completion notification embedded in a user message. Claude Code >= 2.1
    reports Agent completion this way instead of a second tool_result."""
    for match in NOTIFICATION_PATTERN.finditer(text):
        body = match.group(1)
        tool_use_id = re.search(r"<tool-use-id>(.*?)</tool-use-id>", body)
        status = re.search(r"<status>(.*?)</status>", body)
        result_text = re.search(r"<result>(.*?)</result>", body, re.DOTALL)
        if tool_use_id is None:
            continue
        yield (
            tool_use_id.group(1).strip(),
            status.group(1).strip().lower() if status else None,
            result_text.group(1) if result_text else "",
        )


for event_index, line in enumerate(session_path.read_text().splitlines()):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue

    message = event.get("message", {})
    content = message.get("content", [])
    if not isinstance(content, list):
        content = []

    if event.get("type") == "assistant":
        for block in content:
            if (
                isinstance(block, dict)
                and block.get("type") == "tool_use"
                and block.get("name") in {"Agent", "Task"}
            ):
                tool_input = block.get("input", {})
                description = str(tool_input.get("description", ""))
                text = " ".join(
                    str(tool_input.get(key, ""))
                    for key in ("description", "prompt", "task")
                )
                uses.append(
                    {
                        "id": block.get("id"),
                        "event": event_index,
                        "role": classify_role(description),
                        "lane": classify_lane(description),
                        "description": description,
                        "text": text,
                    }
                )

    if event.get("type") == "user":
        tool_use_result = event.get("toolUseResult", {})
        if not isinstance(tool_use_result, dict):
            tool_use_result = {}
        raw_status = tool_use_result.get("status")
        normalized_status = (
            str(raw_status).strip().lower()
            if raw_status is not None
            else None
        )
        completed = normalized_status in {None, "completed"}

        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                is_error = bool(block.get("is_error", False))
                tool_use_id = block.get("tool_use_id")
                result = {
                    "event": event_index,
                    "status": normalized_status,
                    "completed": completed,
                    "is_error": is_error,
                    "success": completed and not is_error,
                    "text": extract_text(block.get("content", "")),
                }
                existing = results.get(tool_use_id)
                if existing is None or not existing["completed"]:
                    results[tool_use_id] = result

        message_text = extract_text(message.get("content", ""))
        for tool_use_id, status, result_text in iter_task_notifications(
            message_text
        ):
            note_completed = status == "completed"
            result = {
                "event": event_index,
                "status": status,
                "completed": note_completed,
                "is_error": False,
                "success": note_completed,
                "text": result_text,
            }
            existing = results.get(tool_use_id)
            if existing is None or not existing["completed"]:
                results[tool_use_id] = result

    # An async agent's completion is recorded when its task-notification is
    # enqueued, even if the coordinator consumes the result another way (for
    # example by reading the task output file) and the queued notification is
    # removed before delivery as a user message.
    if (
        event.get("type") == "queue-operation"
        and event.get("operation") == "enqueue"
    ):
        for tool_use_id, status, result_text in iter_task_notifications(
            str(event.get("content", ""))
        ):
            note_completed = status == "completed"
            result = {
                "event": event_index,
                "status": status,
                "completed": note_completed,
                "is_error": False,
                "success": note_completed,
                "text": result_text,
            }
            existing = results.get(tool_use_id)
            if existing is None or not existing["completed"]:
                results[tool_use_id] = result


if mode == "coupled":
    if uses:
        fail(
            "coupled execution dispatched Agent/Task call(s): "
            + ", ".join(use["text"][:80] for use in uses)
        )
    print("No Agent/Task calls were dispatched.")
    sys.exit(0)

implementers = [use for use in uses if use["role"] == "implementer"]

by_lane = {}
for lane in ("1", "2"):
    lane_implementers = [
        use
        for use in implementers
        if (
            use["lane"] == lane
            and use["id"] in results
            and results[use["id"]]["success"]
        )
    ]
    if not lane_implementers:
        fail(
            f"no successful completed implementer tool use found for Task {lane}"
        )
    by_lane[lane] = min(lane_implementers, key=lambda use: use["event"])

latest_start = max(use["event"] for use in by_lane.values())
earliest_result = min(results[use["id"]]["event"] for use in by_lane.values())
if latest_start >= earliest_result:
    fail("both implementers did not start before the first implementer result")

quality_result_events = {}


def validate_lane_reviews(lane, implementer_result_event):
    spec_uses = [
        use
        for use in uses
        if use["role"] == "spec-reviewer" and use["lane"] == lane
    ]
    if not spec_uses:
        fail(f"no spec-review tool use found for Task {lane}")

    first_spec_start = min(use["event"] for use in spec_uses)
    if first_spec_start <= implementer_result_event:
        fail(
            f"Task {lane} spec review started before implementer completed"
        )

    passing_spec_uses = [
        use
        for use in spec_uses
        if (
            use["id"] in results
            and results[use["id"]]["success"]
            and has_exact_outcome(
                results[use["id"]], "SPEC OUTCOME", "PASS"
            )
        )
    ]
    quality_uses = [
        use
        for use in uses
        if use["role"] == "quality-reviewer" and use["lane"] == lane
    ]
    if not passing_spec_uses:
        fail(f"no successful PASS spec-review result found for Task {lane}")
    if not quality_uses:
        fail(f"no quality-review tool use found for Task {lane}")
    first_spec_result = min(
        results[use["id"]]["event"] for use in passing_spec_uses
    )
    first_quality_start = min(use["event"] for use in quality_uses)
    if first_spec_result >= first_quality_start:
        fail(f"Task {lane} quality review started before spec review passed")

    approved_quality_uses = [
        use
        for use in quality_uses
        if (
            use["id"] in results
            and results[use["id"]]["success"]
            and has_exact_outcome(
                results[use["id"]], "QUALITY OUTCOME", "APPROVED"
            )
        )
    ]
    if not approved_quality_uses:
        fail(f"no successful APPROVED quality-review result found for Task {lane}")
    return min(
        results[use["id"]]["event"] for use in approved_quality_uses
    )


for lane in ("1", "2"):
    quality_result_events[lane] = validate_lane_reviews(
        lane, results[by_lane[lane]["id"]]["event"]
    )

task_three_implementers = [
    use for use in implementers if use["lane"] == "3"
]
if not task_three_implementers:
    fail("no Task 3 implementer tool use found")

first_task_three_start = min(use["event"] for use in task_three_implementers)
latest_quality_result = max(quality_result_events.values())
if first_task_three_start <= latest_quality_result:
    fail("Task 3 implementation started before both quality reviews approved")

completed_task_three = [
    use
    for use in task_three_implementers
    if (
        use["id"] in results
        and results[use["id"]]["success"]
    )
]
if not completed_task_three:
    fail("no successful completed implementer tool use found for Task 3")

task_three = min(completed_task_three, key=lambda use: use["event"])
quality_result_events["3"] = validate_lane_reviews(
    "3", results[task_three["id"]]["event"]
)

whole_change_uses = [
    use for use in uses if use["role"] == "whole-change-reviewer"
]
if not whole_change_uses:
    fail("no whole-change review tool use found")

first_whole_change_start = min(use["event"] for use in whole_change_uses)
if first_whole_change_start <= quality_result_events["3"]:
    fail(
        "whole-change review started before Task 3 quality review approved"
    )

approved_whole_change_uses = [
    use
    for use in whole_change_uses
    if (
        use["id"] in results
        and results[use["id"]]["success"]
        and has_exact_outcome(
            results[use["id"]], "QUALITY OUTCOME", "APPROVED"
        )
    )
]
if not approved_whole_change_uses:
    fail("no successful APPROVED whole-change review result found")

print("Both implementers started before either returned.")
print("Tasks 1, 2, and 3 each passed spec review before quality review started.")
print("Both quality reviews approved before Task 3 implementation started.")
print("Final whole-change review started after Task 3 quality approval and passed.")
