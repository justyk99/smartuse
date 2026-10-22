---
name: status
description: "Show whether Claude is working, waiting on an agent, waiting on you, stopped after a hand-off, or stalled — one deterministic line from the heartbeat hook (0 model tokens), plus how to put it in your status line. Use when the user asks 'are you still working', 'is it stuck', 'what is it doing', 'status', 'heartbeat'."
argument-hint: "[install]"
allowed-tools: Bash(bash *), Bash(echo *), Read, Edit
---

# status — the heartbeat (deterministic, 0 model tokens to compute)

!`bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/heartbeat.py" --line || true`

Plugin root (absolute): !`echo "${CLAUDE_PLUGIN_ROOT}"`

Print the heartbeat line above verbatim as your first line — that one line, unchanged; run nothing else to add to it (no `--json`, no second line). Then, in ≤ 3 lines, explain only the state words it contains, from this legend; never name an agent, a tool or a step the line does not show:
- `working · thinking 0s · 0 calls this turn` = a turn is running and no tool has run in it yet. Typed in this session, `/smartuse:status` always shows this: it runs inside your own new turn, and the prompt that started it is the latest activity (it ends the wait on you), so the line is this turn, not the work before it.
- `working · <tool> running 4s` / `working · last <tool> 4s · N calls this turn` = Claude is inside a turn, using tools; `working · waiting on agent: <type> 2m10s` = a subagent is running (`, N more` = several).
- `waiting on you · 4m12s` = the turn ended and nothing happens until you type (`no prompt yet` = a new session); `waiting on you: permission prompt` = an approval is pending; `NEEDS YOU: …` = run-plan wrote a question into routing.json — answer it.
- `STOPPED · handed off 20:41 (builder) — nothing will wake this session` = the wait gate saw work handed to another session while nothing is armed to wake this one: it is stopped, not waiting, so tell whoever should wake it or ask for a watcher (`hooks/watch.py`); `waiting on builder · watcher armed 20:41` = work was handed off and a watcher or a check-in will wake this session.
- `stalled? · no activity 6m10s` = a working state with no hook event for 5 minutes (`SMARTUSE_STALL_MIN` changes it): a long think and a hung tool look the same from outside — you decide whether to interrupt.
- `· step 2/5 build·opus "…"` = the run-plan step running now; `· loop block 1/6` = the until-done gate's block count; `session ended` = the session closed; `no activity recorded` = the hooks have not fired for this repo yet (restart Claude Code after installing the plugin).

Then say it plainly, in one or two lines: the live answer — while Claude works, or after it stopped — is the status line (`/smartuse:status install`), or this command run from a plain shell, not from Claude: `bash "<plugin root>/hooks/py.sh" "<plugin root>/hooks/heartbeat.py" --line` (write it out with the plugin root printed above). Never a second Claude session in the same repo: its own events overwrite this repo's status file.

Data: `~/.claude/smartuse/projects/<key>/status.json` (`<key>` is derived from the repo's full path), written by the heartbeat hook on every event (0 tokens, one Python start per event: ~55 ms on Linux, more on Windows, where a start can take seconds; `py.sh` probes for an interpreter once and remembers it). One status file per repo: the last session that writes it wins.

## install — only when `$ARGUMENTS` contains `install`

Print exactly this snippet with `<abs path>` replaced by the plugin root printed above (an absolute path — never the plugin-root variable, which is not set for a status-line command; on Windows write it with forward slashes, `C:/Users/...`, so the JSON needs no escaping). `py.sh` runs the hook with `python3`, else `python`, else `py -3` — on a stock Windows install `python3` is only the Microsoft Store stub:

```json
{"statusLine": {"type": "command", "command": "bash \"<abs path>/hooks/py.sh\" \"<abs path>/hooks/heartbeat.py\" --statusline", "padding": 2, "refreshInterval": 5}}
```

Say what it shows (`[Opus] ctx 34% · $1.23 · working · last Bash 4s · 3 calls this turn`; `refreshInterval` re-renders every 5 s, so the counters move without new events) and then OFFER: "Add it to ~/.claude/settings.json now? (yes/no)". Only after the user says yes: Read `~/.claude/settings.json`, merge the `statusLine` key into the existing object with the Edit tool (keep every other key; create the file with that single key if it does not exist; if a `statusLine` already exists, show the old value first and ask again), then tell the user to restart Claude Code. Never edit the file silently. The subagent rows in the UI (`subagentStatusLine`: `step 2 build·opus · general-purpose · 1m15s · 12.3k tok`) ship with the plugin's own settings.json and need no install.

Without `install` in `$ARGUMENTS`: add one line — "`/smartuse:status install` prints the status-line snippet."
