---
name: status
description: "Show whether Claude is working, waiting on an agent, waiting on you, or stalled — one deterministic line from the heartbeat hook (0 model tokens), plus how to put it in your status line. Use when the user asks 'are you still working', 'is it stuck', 'what is it doing', 'status', 'heartbeat'."
argument-hint: "[install]"
allowed-tools: Bash(bash *), Read, Edit
---

# status — the heartbeat (deterministic, 0 model tokens to compute)

!`bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/heartbeat.py" --line || true`

Quote that line verbatim as your first line, then explain it in ≤ 4 lines:
- `working · <tool> running 4s` / `working · last <tool> 4s · N calls this turn` = Claude is inside a turn; `working · waiting on agent: <type> 2m10s` = a subagent is running (SubagentStart seen, no SubagentStop yet; `, N more` = several).
- `waiting on you · 4m12s` = the turn ended (or Claude has been idle, or no prompt yet) and nothing happens until you type; `waiting on you: permission prompt` = an approval is pending; `NEEDS YOU: …` = run-plan wrote a question into routing.json — answer it.
- `stalled? · no activity 6m10s` = a working state with no hook event for 5 minutes (`SMARTUSE_STALL_MIN` changes it): a long model think and a hung tool look the same from outside, hence the question mark — you decide whether to interrupt.
- `· step 2/5 build·opus "…"` / `· loop block 1/6` = the run-plan unit running now and the until-done gate's block count; `session ended` = SessionEnd fired; `no activity recorded` = the hooks have not fired for this repo yet (restart Claude Code after installing the plugin).

Data: `~/.claude/smartuse/projects/<repo>/status.json`, written by the heartbeat hook on every event (0 tokens, ~40 ms per event). Limit: **one status file per repo, the last session that wrote wins** — two sessions in the same repo overwrite each other's line (`--json` shows the `session_id`). Scripts: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/heartbeat.py" --json` (the file plus the derived `state` and `line`).

## install — only when `$ARGUMENTS` contains `install`

Plugin root (absolute): !`echo "${CLAUDE_PLUGIN_ROOT}"`

Print exactly this snippet with `<abs path>` replaced by the plugin root printed above (an absolute path — never `${CLAUDE_PLUGIN_ROOT}`, which is not set for a status-line command; on Windows write it with forward slashes, `C:/Users/...`, so the JSON needs no escaping). `py.sh` runs the hook with `python3`, else `python`, else `py -3` — on a stock Windows install `python3` is only the Microsoft Store stub:

```json
{"statusLine": {"type": "command", "command": "bash \"<abs path>/hooks/py.sh\" \"<abs path>/hooks/heartbeat.py\" --statusline", "padding": 2, "refreshInterval": 5}}
```

Say what it shows (`[Opus] ctx 34% · $1.23 · working · last Bash 4s · 3 calls this turn`; `refreshInterval` re-renders every 5 s, so the counters move without new events) and then OFFER: "Add it to ~/.claude/settings.json now? (yes/no)". Only after the user says yes: Read `~/.claude/settings.json`, merge the `statusLine` key into the existing object with the Edit tool (keep every other key; create the file with that single key if it does not exist; if a `statusLine` already exists, show the old value first and ask again), then tell the user to restart Claude Code. Never edit the file silently. The subagent rows in the UI (`subagentStatusLine`: `step 2 build·opus · general-purpose · 1m15s · 12.3k tok`) ship with the plugin's own settings.json and need no install.

Without `install` in `$ARGUMENTS`: add one line — "`/smartuse:status install` prints the status-line snippet."
