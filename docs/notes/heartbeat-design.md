# Heartbeat — "is it working, waiting on an agent, waiting on me, or stalled?" (0.4.0-dev, 2026-10-22). For the author.

## The problem
The author's own words, watching the brain session from the app: *"how do I check that you are working with an agent or other session, or just AFK waiting for me? this is the big weakness."* The landscape research (§ 2, "Visibility / stuck") already said nobody addresses it; the official surfaces are `/tasks`, the agent view, `subagentStatusLine` and stall timeouts — all per-agent, none answering the one question above in one line.

## The answer: a status file written by hooks, rendered in one line
- `hooks/heartbeat.py` runs on `SessionStart`, `UserPromptSubmit`, `PreToolUse` (every tool), `PostToolUse` (every tool), `SubagentStart`, `SubagentStop`, `Notification` (`idle_prompt`, `permission_prompt`), `Stop`, `SessionEnd`. Each event updates `~/.claude/smartuse/projects/<repo>/status.json` (atomic write): turn, tool calls this turn, the tool running now, the last tool, the agents running (id, type, since), agents done, the last notification, turn ended, session ended, updated-at.
- `heartbeat.py --line` renders one line by fixed priority: **NEEDS YOU** (routing.json has `needs_human`) → session ended → waiting on you: permission prompt → working · waiting on agent `<type> <elapsed>` → working · `<tool>` running `<elapsed>` → waiting on you `<since>` → working · last `<tool>` `<ago>` · N calls, with `stalled?` prefixed when nothing was recorded for 5 minutes (`SMARTUSE_STALL_MIN`) while in a working state. When run-plan has a unit running: `· step 3/6 build·opus "tests"`; in the until-done loop: `· loop block 2/6`.
- `/smartuse:status` prints that line (0 model tokens) and, with `install`, the settings snippet that puts it in the terminal status line permanently (`--statusline` merges the model, context % and cost that Claude Code hands to status-line commands). The plugin also ships a `subagentStatusLine` so each agent row in the UI names its plan step.

## Why this shape
- Deterministic and cheap: a Python process per tool call (tens of ms), no model tokens, no network. Same rule as the ledger: a receipt must never stop the work, so every error exits 0 silently.
- "Stalled?" is the only inferred word in the line. A long `Bash` is not a stall because `PreToolUse` recorded it as running; an agent is not a stall because `SubagentStart` recorded it. A stall is: working state, nothing recorded for N minutes. Users set N.
- One file per repo, last session wins. Two sessions in one repo overwrite each other's line; the `session_id` field says whose it is. Good enough for a solo developer; a per-session file is a follow-up if anyone asks.
- Not a timer. Claude Code has no periodic hook; the line is as fresh as the last event. The status line's `refreshInterval` re-renders the same file, so "ago" counts up without new events.

## What it does not do
- It cannot see inside a worker (an agent's own tool calls fire hooks in the agent's context with the same project dir — they do update the file, so the line shows the agent's last tool too; the agent row in the UI is the per-agent view).
- It does not know *why* nothing happens (a model thinking for 4 minutes and a hung tool look the same until the tool returns). It says "stalled?", with the question mark, and leaves the kill to the human.
- For the brain running in the cloud app, the file lives in the container; the app's Background-tasks panel, the branch's last push and `docs/STATUS.md` remain the signals.

## Test log
- `hooks/tests/heartbeat-test.sh`: the state machine event by event, the priority order, stall detection, session reset, the three renderers, garbage input → silent exit 0.
- First real use: this branch's own worker runs (the plugin is installed at user scope in the brain's container, so the hooks fired on the brain's own tool calls while the feature was being built).
