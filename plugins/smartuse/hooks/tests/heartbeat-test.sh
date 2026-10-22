#!/usr/bin/env bash
# Self-contained test for hooks/heartbeat.py: the state machine event by event, the line's priority order, stall detection,
# the until-done exception on Stop, session reset, the three renderers (--line / --statusline / --subagent-statusline),
# garbage input -> silent exit 0. Every hook invocation must print nothing. Exit 1 on failure.
set -e; D=$(mktemp -d); H="$(cd "$(dirname "$0")/.." && pwd)"; export HOME="$D/home"; mkdir -p "$HOME" "$D/proj"
P="$HOME/.claude/smartuse/projects/proj"; S="$P/status.json"; R="$P/routing.json"; fail=0
ev() { # $1 = event JSON -> the hook prints nothing and exits 0
  out=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/heartbeat.py"; echo "rc=$?")
  [ "$out" = "rc=0" ] || { echo "FAIL hook printed or failed: $1 -> $out"; fail=1; }
}
line() { CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/heartbeat.py" --line; }
expect() { l=$(line); case "$l" in *"$2"*) echo "PASS $1: $l";; *) echo "FAIL $1: expected '$2' in: $l"; fail=1;; esac; }
expect_not() { l=$(line); case "$l" in *"$2"*) echo "FAIL $1: unexpected '$2' in: $l"; fail=1;; *) echo "PASS $1: $l";; esac; }
js() { CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/heartbeat.py" --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert $1, d"; }
ago() { python3 -c "import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"; }
C="\"cwd\":\"$D/proj\""
expect "no status file" "no activity recorded for proj"
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s1\",\"source\":\"startup\",$C}"
expect "SessionStart alone" "waiting on you · no prompt yet"
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s1\",$C}"
expect "UserPromptSubmit" "smartuse · working"
js "d['turn']==1 and d['state']=='working' and d['session_id']=='s1' and d['started'] and d['updated']" && echo "PASS --json: turn 1, state working" || { echo "FAIL --json after prompt"; fail=1; }
ev "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"tool_use_id\":\"t1\",$C}"
expect "PreToolUse" "working · Bash running"
ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"t1\",\"tool_response\":{\"stdout\":\"x\"},$C}"
expect "PostToolUse" "working · last Bash"
expect "PostToolUse call count" "1 call this turn"
js "d['tool_calls']==1 and d['tool_running'] is None and d['last_tool']['name']=='Bash'" && echo "PASS --json: tool_running cleared, last_tool Bash" || { echo "FAIL --json after PostToolUse"; fail=1; }
ev "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"s1\",\"agent_id\":\"a1\",\"agent_type\":\"general-purpose\",$C}"
expect "SubagentStart" "working · waiting on agent: general-purpose"
ev "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s1\",\"agent_id\":\"a1\",\"agent_type\":\"general-purpose\",$C}"
expect_not "SubagentStop" "waiting on agent"
js "d['agents']=={} and d['agents_done']==1" && echo "PASS --json: agents empty, agents_done 1" || { echo "FAIL --json after SubagentStop"; fail=1; }
ev "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"s1\",\"agent_id\":\"a2\",\"agent_type\":\"Explore\",$C}"
ev "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"s1\",\"agent_id\":\"a3\",\"agent_type\":\"Plan\",$C}"
expect "two agents" "waiting on agent: Explore"; expect "two agents count" ", 1 more"
ev "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s1\",\"agent_id\":\"a2\",$C}"; ev "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s1\",\"agent_id\":\"a3\",$C}"
js "d['agents']=={} and d['agents_done']==3" && echo "PASS --json: agents_done 3" || { echo "FAIL agents_done"; fail=1; }
ev "{\"hook_event_name\":\"Stop\",\"session_id\":\"s1\",\"stop_hook_active\":false,$C}"
expect "Stop" "smartuse · waiting on you ·"
js "d['turn_ended'] is True and d['state']=='waiting_on_you' and d['waiting_since']" && echo "PASS --json: turn_ended, waiting_since set" || { echo "FAIL --json after Stop"; fail=1; }
ev "{\"hook_event_name\":\"Notification\",\"session_id\":\"s1\",\"notification_type\":\"idle_prompt\",\"message\":\"Claude is waiting for your input\",$C}"
expect "idle_prompt" "waiting on you ·"
ev "{\"hook_event_name\":\"Notification\",\"session_id\":\"s1\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission\",$C}"
expect "permission_prompt" "waiting on you: permission prompt"
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s1\",$C}"
expect "UserPromptSubmit clears the notification" "smartuse · working"
js "d['notification'] is None and d['turn']==2 and d['tool_calls']==0 and d['turn_ended'] is False" && echo "PASS --json: notification cleared, turn 2, calls reset" || { echo "FAIL --json after second prompt"; fail=1; }
# permission prompt answered -> PostToolUse clears it (PreToolUse fires BEFORE the prompt, so Pre alone cannot)
ev "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Write\",\"tool_use_id\":\"t2\",$C}"
ev "{\"hook_event_name\":\"Notification\",\"session_id\":\"s1\",\"notification_type\":\"permission_prompt\",$C}"
expect "permission prompt beats a running tool" "permission prompt"
ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Write\",\"tool_use_id\":\"t2\",$C}"
expect "PostToolUse clears the permission prompt" "working · last Write"
# --- routing.json: NEEDS YOU first, then the running step and the until-done loop suffix
echo '{"active":true,"task":"csv","needs_human":"which rounding rule?   half-up or bankers?","units":[{"id":1,"status":"pass"}]}' > "$R"
expect "needs_human" "smartuse · NEEDS YOU: which rounding rule? half-up or bankers?"
echo '{"active":false,"needs_human":"old question","units":[]}' > "$R"
expect_not "inactive routing ignored" "NEEDS YOU"
echo '{"active":true,"task":"csv","until_done":true,"blocks":1,"units":[{"id":1,"title":"decide","tier":"judgment","model":"session","status":"pass"},{"id":2,"title":"build route","tier":"build","model":"opus","status":"running"},{"id":3,"title":"tests","tier":"build","model":"opus","status":"pending"}]}' > "$R"
expect "running unit" 'step 2/3 build·opus "build route"'; expect "until-done loop" "loop block 1/6"
# Stop inside an until-done run with units left: the gate will block, so the turn is NOT over
ev "{\"hook_event_name\":\"Stop\",\"session_id\":\"s1\",\"stop_hook_active\":false,$C}"
expect "Stop while the gate will block" "smartuse · working"
ev "{\"hook_event_name\":\"Stop\",\"session_id\":\"s1\",\"stop_hook_active\":true,$C}"
expect "Stop with stop_hook_active (gate lets it end)" "smartuse · waiting on you"
rm "$R"
# --- stall: a working state with no event for 10 minutes
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s1\",$C}"
ev "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"t3\",$C}"; ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"t3\",$C}"
python3 - "$S" "$(ago 72)" <<'PY'
import json,sys; p,t=sys.argv[1:]; s=json.load(open(p)); s["updated"]=t; s["last_tool"]["at"]=t; json.dump(s,open(p,"w"))
PY
expect "duration format m:ss" "last Bash 1m12s · 1 call this turn"
python3 - "$S" "$(ago 600)" <<'PY'
import json,sys; p,t=sys.argv[1:]; s=json.load(open(p)); s["updated"]=t; s["last_tool"]["at"]=t; json.dump(s,open(p,"w"))
PY
l=$(line); case "$l" in "stalled? smartuse · no activity 10m00s"*) echo "PASS stalled: $l";; *) echo "FAIL stalled: $l"; fail=1;; esac
js "d['state']=='stalled'" && echo "PASS --json state stalled" || { echo "FAIL state stalled"; fail=1; }
l=$(SMARTUSE_STALL_MIN=15 line); case "$l" in "smartuse · working · last Bash 10m00s"*) echo "PASS SMARTUSE_STALL_MIN=15 -> not stalled: $l";; *) echo "FAIL stall threshold env: $l"; fail=1;; esac
python3 - "$S" "$(ago 3723)" <<'PY'
import json,sys; p,t=sys.argv[1:]; s=json.load(open(p)); s["updated"]=t; s["last_tool"]["at"]=t; s["tool_running"]={"name":"Bash","tool_use_id":"t9","since":t}; json.dump(s,open(p,"w"))
PY
expect "a long tool is not a stall (h:mm)" "smartuse · working · Bash running 1h02m"
# an agent whose SubagentStop was never seen is ignored after 3 h
python3 - "$S" "$(ago 14400)" <<'PY'
import json,sys; p,t=sys.argv[1:]; s=json.load(open(p)); s["tool_running"]=None; s["agents"]={"zombie":{"type":"general-purpose","since":t}}; json.dump(s,open(p,"w"))
PY
expect_not "agent older than 3 h dropped" "waiting on agent"
# --- session handling: compact keeps the state, another session resets, a foreign SessionEnd is ignored
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s1\",\"source\":\"compact\",$C}"
js "d['turn']==3 and d['session_id']=='s1' and d['source']=='compact'" && echo "PASS SessionStart compact keeps the turn count" || { echo "FAIL compact reset the state"; fail=1; }
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s2\",$C}"
js "d['turn']==1 and d['session_id']=='s2' and d['agents_done']==0" && echo "PASS another session_id -> fresh file, turn 1" || { echo "FAIL session reset"; fail=1; }
ev "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"s1\",\"reason\":\"logout\",$C}"
js "d['session_id']=='s2' and d['ended'] is False" && echo "PASS SessionEnd of the old session does not overwrite the live one" || { echo "FAIL foreign SessionEnd"; fail=1; }
ev "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"s2\",\"reason\":\"logout\",$C}"
expect "SessionEnd" "smartuse · session ended"
js "d['state']=='ended' and d['end_reason']=='logout'" && echo "PASS --json state ended" || { echo "FAIL state ended"; fail=1; }
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s3\",\"source\":\"startup\",$C}"
js "d['session_id']=='s3' and d['turn']==0 and d['agents_done']==0 and d['ended'] is False" && echo "PASS SessionStart resets for the new session" || { echo "FAIL SessionStart reset"; fail=1; }
# --- the renderers for the status line and the subagent rows
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s3\",$C}"
OUT=$(printf '%s' "{\"model\":{\"display_name\":\"Opus\"},\"cost\":{\"total_cost_usd\":1.234},\"context_window\":{\"used_percentage\":34},\"workspace\":{\"current_dir\":\"$D/proj\",\"project_dir\":\"$D/proj\"},$C}" | python3 "$H/heartbeat.py" --statusline)
case "$OUT" in "[Opus] ctx 34% · \$1.23 · working · thinking"*) echo "PASS --statusline: $OUT";; *) echo "FAIL --statusline: $OUT"; fail=1;; esac
OUT=$(printf '%s' "{$C}" | python3 "$H/heartbeat.py" --statusline)
case "$OUT" in "working · thinking"*) echo "PASS --statusline without model/cost fields: $OUT";; *) echo "FAIL --statusline minimal: $OUT"; fail=1;; esac
OUT=$(printf 'garbage' | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/heartbeat.py" --statusline)
[ -n "$OUT" ] && echo "PASS --statusline with garbage stdin still prints the heartbeat line: $OUT" || { echo "FAIL --statusline garbage"; fail=1; }
MS=$(( $(date +%s) * 1000 - 75000 ))
OUT=$(printf '%s' "{\"tasks\":[{\"id\":\"task-1\",\"name\":\"grep callers\",\"type\":\"local_agent\",\"agentType\":\"general-purpose\",\"status\":\"running\",\"startTime\":$MS,\"model\":\"haiku\",\"tokenCount\":12345,\"cwd\":\"$D/proj\"}]}" | python3 "$H/heartbeat.py" --subagent-statusline)
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s' "$OUT" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['id']=='task-1' and d['content'].startswith('general-purpose · 1m1') and d['content'].endswith('12.3k tok'), d" && echo "PASS --subagent-statusline: $OUT" || { echo "FAIL --subagent-statusline: $OUT"; fail=1; }
echo '{"active":true,"units":[{"id":2,"title":"build route","tier":"build","model":"opus","status":"running"}]}' > "$R"
OUT=$(printf '%s' "{\"tasks\":[{\"id\":\"task-2\",\"agentType\":\"Explore\",\"startTime\":\"$(ago 5)\",\"tokenCount\":500,\"cwd\":\"$D/proj\"}]}" | python3 "$H/heartbeat.py" --subagent-statusline)
case "$OUT" in '{"id": "task-2", "content": "step 2 build·opus · Explore · '*'k tok"}') echo "PASS --subagent-statusline with a running step: $OUT";; *) echo "FAIL subagent step prefix: $OUT"; fail=1;; esac
rm "$R"
OUT=$(printf 'nope' | python3 "$H/heartbeat.py" --subagent-statusline; echo "rc=$?"); [ "$OUT" = "rc=0" ] && echo "PASS --subagent-statusline garbage -> nothing, exit 0" || { echo "FAIL subagent garbage: $OUT"; fail=1; }
# hooks installed mid-session: the first event is a PostToolUse (no SessionStart, no prompt seen) -> still "working"
rm "$S"; ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"s4\",\"tool_name\":\"Read\",\"tool_use_id\":\"t7\",$C}"
expect "first event mid-session is a PostToolUse" "smartuse · working · thinking"
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s3\",\"source\":\"startup\",$C}"; ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s3\",$C}"
# --- robustness: garbage / unknown events print nothing and never fail
OUT=$(printf 'not json' | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/heartbeat.py"; echo "rc=$?"); [ "$OUT" = "rc=0" ] && echo "PASS garbage stdin -> exit 0, no output" || { echo "FAIL garbage stdin: $OUT"; fail=1; }
OUT=$(printf '' | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/heartbeat.py"; echo "rc=$?"); [ "$OUT" = "rc=0" ] && echo "PASS empty stdin -> exit 0, no output" || { echo "FAIL empty stdin: $OUT"; fail=1; }
ev "{\"hook_event_name\":\"PreCompact\",\"session_id\":\"s3\",$C}"
js "d['turn']==1 and d['tool_calls']==0" && echo "PASS unknown event ignored" || { echo "FAIL unknown event changed the state"; fail=1; }
printf '{"active":true,"units":"broken"' > "$R"; expect "corrupt routing.json ignored" "smartuse · working"; rm "$R"
printf 'corrupt' > "$S"; ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s3\",$C}"
js "d['turn']==1 and d['session_id']=='s3'" && echo "PASS corrupt status.json -> rebuilt from the next event" || { echo "FAIL corrupt status.json"; fail=1; }
[ -z "$(ls "$P" | grep '\.tmp$')" ] && echo "PASS no temp files left behind" || { echo "FAIL temp files left: $(ls "$P")"; fail=1; }
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
