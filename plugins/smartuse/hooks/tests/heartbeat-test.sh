#!/usr/bin/env bash
# Self-contained test for hooks/heartbeat.py: the state machine event by event, the line's priority order, stall detection,
# the until-done exception on Stop (stop_hook_active ignored, max_blocks honoured), session reset, the three renderers (--line /
# --statusline / --subagent-statusline), the state dir keyed by the full path (never the 0.3.0 folder-name dir), a failed os.replace,
# non-ASCII events under cp1252, garbage input -> silent exit 0. Every hook invocation must print nothing. Exit 1 on failure.
REAL_HOME="${HOME:-}"; set -e; D=$(mktemp -d); H="$(cd "$(dirname "$0")/.." && pwd)"; export HOME="$D/home"; mkdir -p "$HOME" "$D/proj"
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, not inside JSON strings (cygpath -m -> C:/Users/...); elsewhere unchanged
key() { py -c "import re,sys,pathlib; print(re.sub(r'[^A-Za-z0-9._-]','-',str(pathlib.Path(sys.argv[1]).resolve())).lstrip('-'))" "$1"; }   # the hooks' state-dir rule: the full resolved path, every character outside [A-Za-z0-9._-] -> "-", no leading "-" (~/.claude/smartuse/projects/<key>/)
PW=$(wp "$D/proj")   # the project path as it goes into the event JSON and CLAUDE_PROJECT_DIR
K=$(key "$PW"); P="$HOME/.claude/smartuse/projects/$K"; S="$P/status.json"; R="$P/routing.json"; fail=0
ev() { # $1 = event JSON -> the hook prints nothing and exits 0
  out=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py"; echo "rc=$?")
  [ "$out" = "rc=0" ] || { echo "FAIL hook printed or failed: $1 -> $out"; fail=1; }
}
line() { CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py" --line; }
expect() { l=$(line); case "$l" in *"$2"*) echo "PASS $1: $l";; *) echo "FAIL $1: expected '$2' in: $l"; fail=1;; esac; }
expect_not() { l=$(line); case "$l" in *"$2"*) echo "FAIL $1: unexpected '$2' in: $l"; fail=1;; *) echo "PASS $1: $l";; esac; }
# Ages: a stamp is cut for "N s before A", A = `date +%s` read in bash BEFORE the interpreter that cuts it starts (an interpreter reads its own
# clock only after its start-up, which takes seconds on Windows and happens twice per call through py.sh). Every render is bracketed by two
# more reads, b and e; the hook reads its clock between them, so the age it prints is within N+b-A .. N+e-A (+1 s: `date` and the interpreter
# are separate clocks). A slow start moves that window, it never fails a right age, and a wrong age is still outside it: no fixed allowance.
dur_s() { # the rendered duration back to seconds: "1m14s" -> 74 · "10m03s" -> 603 · "1h02m" -> 3720 · "8s" -> 8 · anything else -> -1 (bash 3.2: no regex, 10# keeps "03" decimal)
  local s=$1 h=0 m=0 x=0
  case "$s" in ""|*[!0-9hms]*) echo -1; return;; esac
  case "$s" in *h*) h=${s%%h*}; s=${s#*h};; esac
  case "$s" in *m*) m=${s%%m*}; s=${s#*m};; esac
  case "$s" in *s) x=${s%s};; esac
  case "$h$m$x" in *[!0-9]*) echo -1; return;; esac   # "1m2m3s": a bad number would be an arithmetic error, which set -e turns into a silent abort
  echo $(( 10#${h:-0} * 3600 + 10#${m:-0} * 60 + 10#${x:-0} ))
}
expect_ago() { # $1 label, $2 the age (s) of the stamp cut at A, $3 the line up to the duration, $4 what follows it, $5 (optional) a glob the duration must match ("[0-9]*h[0-9][0-9]m" = h:mm); renders with `line` (a VAR=x before the call reaches it); "1h02m" prints whole minutes: the age is up to 59 s more than it reads
  local b e l r d s lo hi g=0; b=$(date +%s); l=$(line); e=$(date +%s); lo=$(( $2 + b - A )); hi=$(( $2 + e - A + 1 ))
  case "$l" in "$3"*"$4"*) r=${l#"$3"}; d=${r%% *}; s=$(dur_s "$d"); case "$d" in *h*) g=59;; esac
      if [ -n "${5:-}" ] && ! case "$d" in $5) true;; *) false;; esac; then echo "FAIL $1: '$d' is not in the form $5: $l"; fail=1
      elif [ "$s" -le "$hi" ] && [ $(( s + g )) -ge "$lo" ]; then echo "PASS $1: $l"; else echo "FAIL $1: '$d' is not within $lo..$hi s: $l"; fail=1; fi;;
    *) echo "FAIL $1: expected '$3<duration>$4' in: $l"; fail=1;; esac
}
js() { CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py" --json | py -c "import json,sys; d=json.load(sys.stdin); assert $1, d"; }
ago() { py -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[2])-int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1" "$A"; }   # the stamp "$1 s before A" as the hooks write it: A comes from bash, not from a clock read inside the (slow to start) interpreter
C="\"cwd\":\"$PW\""
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
# Claude Code sets stop_hook_active=true on every Stop after a block; the gate ignores it (it holds until done or max_blocks), so does the mirror
ev "{\"hook_event_name\":\"Stop\",\"session_id\":\"s1\",\"stop_hook_active\":true,$C}"
expect "Stop with stop_hook_active and units left (the gate still holds)" "smartuse · working"
py - "$R" <<'PY'
import json,sys; p=sys.argv[1]; r=json.load(open(p)); r["blocks"]=6; json.dump(r,open(p,"w"))
PY
ev "{\"hook_event_name\":\"Stop\",\"session_id\":\"s1\",\"stop_hook_active\":true,$C}"
expect "Stop at blocks >= max_blocks (the gate lets it end)" "smartuse · waiting on you"
expect "loop suffix at the cap" "loop block 6/6"
rm "$R"
# --- stall: a working state with no event for 10 minutes
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s1\",$C}"
ev "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"t3\",$C}"; ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"t3\",$C}"
A=$(date +%s); py - "$S" "$(ago 72)" <<'PY'
import json,sys; p,t=sys.argv[1:]; s=json.load(open(p)); s["updated"]=t; s["last_tool"]["at"]=t; json.dump(s,open(p,"w"))
PY
expect_ago "duration format m:ss" 72 "smartuse · working · last Bash " " · 1 call this turn" "[0-9]*m[0-9][0-9]s"
A=$(date +%s); py - "$S" "$(ago 600)" <<'PY'
import json,sys; p,t=sys.argv[1:]; s=json.load(open(p)); s["updated"]=t; s["last_tool"]["at"]=t; json.dump(s,open(p,"w"))
PY
expect_ago "stalled" 600 "stalled? smartuse · no activity " " · last Bash · 1 call this turn"
js "d['state']=='stalled'" && echo "PASS --json state stalled" || { echo "FAIL state stalled"; fail=1; }
SMARTUSE_STALL_MIN=15 expect_ago "SMARTUSE_STALL_MIN=15 -> not stalled" 600 "smartuse · working · last Bash " " · 1 call this turn"   # the stamp of "stalled", so the same A: the js call in between only moves the window
A=$(date +%s); py - "$S" "$(ago 3723)" <<'PY'
import json,sys; p,t=sys.argv[1:]; s=json.load(open(p)); s["updated"]=t; s["last_tool"]["at"]=t; s["tool_running"]={"name":"Bash","tool_use_id":"t9","since":t}; json.dump(s,open(p,"w"))
PY
expect_ago "a long tool is not a stall (h:mm)" 3723 "smartuse · working · Bash running " "" "[0-9]*h[0-9][0-9]m"
# an agent whose SubagentStop was never seen is ignored after 3 h
A=$(date +%s); py - "$S" "$(ago 14400)" <<'PY'
import json,sys; p,t=sys.argv[1:]; s=json.load(open(p)); s["tool_running"]=None; s["agents"]={"zombie":{"type":"general-purpose","since":t}}; json.dump(s,open(p,"w"))
PY
expect_not "agent older than 3 h dropped" "waiting on agent"
# --- session handling: compact keeps the state, another session resets, a foreign SessionEnd is ignored
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s1\",\"source\":\"compact\",$C}"
js "d['turn']==3 and d['session_id']=='s1' and d['source']=='compact'" && echo "PASS SessionStart compact keeps the turn count" || { echo "FAIL compact reset the state"; fail=1; }
# --- the squeeze counter (recall, F2): a SessionStart compact of the same session counts; the line shows it while it is above 0
expect "a compact of the same session: the line counts one squeeze" "squeezed 1× (last "
js "d['compactions']==1 and d['compact_at']" && echo "PASS --json: compactions 1, compact_at set" || { echo "FAIL --json after the first compact"; fail=1; }
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s1\",\"source\":\"compact\",$C}"
expect "a second compact: squeezed 2×" "squeezed 2× (last "
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s1\",$C}"
expect "the counter survives the next prompt and the line still says working" "working · "
expect "the counter is in the line while the session works" "squeezed 2× (last "
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s9\",\"source\":\"startup\",$C}"
expect_not "a new session starts at 0: no squeezed suffix" "squeezed"
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s10\",\"source\":\"compact\",$C}"
expect_not "a compact of a session the state does not hold starts fresh at 0" "squeezed"
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
OUT=$(printf '%s' "{\"model\":{\"display_name\":\"Opus\"},\"cost\":{\"total_cost_usd\":1.234},\"context_window\":{\"used_percentage\":34},\"workspace\":{\"current_dir\":\"$PW\",\"project_dir\":\"$PW\"},$C}" | py "$H/heartbeat.py" --statusline)
case "$OUT" in "[Opus] ctx 34% · \$1.23 · working · thinking"*) echo "PASS --statusline: $OUT";; *) echo "FAIL --statusline: $OUT"; fail=1;; esac
OUT=$(printf '%s' "{$C}" | py "$H/heartbeat.py" --statusline)
case "$OUT" in "working · thinking"*) echo "PASS --statusline without model/cost fields: $OUT";; *) echo "FAIL --statusline minimal: $OUT"; fail=1;; esac
OUT=$(printf 'garbage' | CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py" --statusline)
[ -n "$OUT" ] && echo "PASS --statusline with garbage stdin still prints the heartbeat line: $OUT" || { echo "FAIL --statusline garbage"; fail=1; }
A=$(date +%s); MS=$(( A * 1000 - 75000 ))   # started 75 s before A; the elapsed time printed is within 75+b-A .. 75+e-A+1 s (b / e: the clock read just before / after the call, as in expect_ago); the result is checked as an argument, not via stdin (Windows would decode a pipe as cp1252)
b=$(date +%s); OUT=$(printf '%s' "{\"tasks\":[{\"id\":\"task-1\",\"name\":\"grep callers\",\"type\":\"local_agent\",\"agentType\":\"general-purpose\",\"status\":\"running\",\"startTime\":$MS,\"model\":\"haiku\",\"tokenCount\":12345,\"cwd\":\"$PW\"}]}" | py "$H/heartbeat.py" --subagent-statusline); e=$(date +%s); lo=$(( 75 + b - A )); hi=$(( 75 + e - A + 1 ))
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && py -c "import json,sys,re; d=json.loads(sys.argv[1]); p=d['content'].split(' '); m=re.fullmatch(r'(\d+)m(\d+)s', p[2]) if len(p) > 2 else None; s=int(m.group(1))*60+int(m.group(2)) if m else -1; assert d['id']=='task-1' and p[0]=='general-purpose' and $lo <= s <= $hi and p[-2:]==['12.3k','tok'], d" "$OUT" && echo "PASS --subagent-statusline (elapsed within $lo..$hi s): $OUT" || { echo "FAIL --subagent-statusline (expected elapsed within $lo..$hi s): $OUT"; fail=1; }
echo '{"active":true,"units":[{"id":2,"title":"build route","tier":"build","model":"opus","status":"running"}]}' > "$R"
A=$(date +%s); OUT=$(printf '%s' "{\"tasks\":[{\"id\":\"task-2\",\"agentType\":\"Explore\",\"startTime\":\"$(ago 5)\",\"tokenCount\":500,\"cwd\":\"$PW\"}]}" | py "$H/heartbeat.py" --subagent-statusline)
case "$OUT" in '{"id": "task-2", "content": "step 2 build·opus · Explore · '*'k tok"}') echo "PASS --subagent-statusline with a running step: $OUT";; *) echo "FAIL subagent step prefix: $OUT"; fail=1;; esac
rm "$R"
OUT=$(printf 'nope' | py "$H/heartbeat.py" --subagent-statusline; echo "rc=$?"); [ "$OUT" = "rc=0" ] && echo "PASS --subagent-statusline garbage -> nothing, exit 0" || { echo "FAIL subagent garbage: $OUT"; fail=1; }
# hooks installed mid-session: the first event is a PostToolUse (no SessionStart, no prompt seen) -> still "working"
rm "$S"; ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"s4\",\"tool_name\":\"Read\",\"tool_use_id\":\"t7\",$C}"
expect "first event mid-session is a PostToolUse" "smartuse · working · thinking"
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s3\",\"source\":\"startup\",$C}"; ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s3\",$C}"
# --- robustness: garbage / unknown events print nothing and never fail
OUT=$(printf 'not json' | CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py"; echo "rc=$?"); [ "$OUT" = "rc=0" ] && echo "PASS garbage stdin -> exit 0, no output" || { echo "FAIL garbage stdin: $OUT"; fail=1; }
OUT=$(printf '' | CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py"; echo "rc=$?"); [ "$OUT" = "rc=0" ] && echo "PASS empty stdin -> exit 0, no output" || { echo "FAIL empty stdin: $OUT"; fail=1; }
ev "{\"hook_event_name\":\"PreCompact\",\"session_id\":\"s3\",$C}"
js "d['turn']==1 and d['tool_calls']==0" && echo "PASS unknown event ignored" || { echo "FAIL unknown event changed the state"; fail=1; }
printf '{"active":true,"units":"broken"' > "$R"; expect "corrupt routing.json ignored" "smartuse · working"; rm "$R"
printf 'corrupt' > "$S"; ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s3\",$C}"
js "d['turn']==1 and d['session_id']=='s3'" && echo "PASS corrupt status.json -> rebuilt from the next event" || { echo "FAIL corrupt status.json"; fail=1; }
# --- the state dir is keyed by the full path: a same-named repo elsewhere has its own status file; a 0.3.0 dir (folder name only) is never used
evp() { out=$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" py "$H/heartbeat.py"; echo "rc=$?"); [ "$out" = "rc=0" ] || { echo "FAIL hook printed or failed: $2 -> $out"; fail=1; }; }   # $1 = the project dir, $2 = the event
mkdir -p "$D/other/proj"; PW2=$(wp "$D/other/proj"); K2=$(key "$PW2")
evp "$PW2" "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"o1\",\"source\":\"startup\",\"cwd\":\"$PW2\"}"
[ "$K2" != "$K" ] && [ -f "$HOME/.claude/smartuse/projects/$K2/status.json" ] && echo "PASS a same-named repo elsewhere gets its own state dir ($K2)" || { echo "FAIL state dir collision: $K vs $K2"; fail=1; }
l=$(CLAUDE_PROJECT_DIR="$PW2" py "$H/heartbeat.py" --line); case "$l" in *"waiting on you · no prompt yet"*) echo "PASS --line of the other repo: $l";; *) echo "FAIL other repo line: $l"; fail=1;; esac
expect "this repo's line untouched by the other" "smartuse · working"
CLAUDE_PROJECT_DIR="$PW2" py "$H/heartbeat.py" --json | py -c "import json,sys; d=json.load(sys.stdin); assert d['project']=='proj' and d['state_dir'].endswith('$K2') and d['project_path'].endswith('proj') and d['session_id']=='o1', d" && echo "PASS --json: project (folder name), project_path, state_dir" || { echo "FAIL --json project fields"; fail=1; }
# the 0.3.0 dir projects/old (shared by every repo named old) exists and holds an active until-done run with a running unit: the
# heartbeat neither writes there nor reads its routing.json (no step / loop suffix, and a Stop ends the turn: the gate reads the keyed dir only)
L="$HOME/.claude/smartuse/projects/old"; mkdir -p "$D/legacy/old" "$L"; PW3=$(wp "$D/legacy/old"); K3=$(key "$PW3")
echo '{"active":true,"until_done":true,"units":[{"id":1,"title":"old step","tier":"build","model":"opus","status":"running"}]}' > "$L/routing.json"; cp "$L/routing.json" "$D/old-before.json"
evp "$PW3" "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"l1\",\"cwd\":\"$PW3\"}"
[ -f "$HOME/.claude/smartuse/projects/$K3/status.json" ] && [ ! -e "$L/status.json" ] && echo "PASS status.json goes to the keyed dir even when the folder-name dir (projects/old) exists" || { echo "FAIL status.json not in the keyed dir: $(ls "$HOME/.claude/smartuse/projects") · projects/old: $(ls "$L")"; fail=1; }
l=$(CLAUDE_PROJECT_DIR="$PW3" py "$H/heartbeat.py" --line); case "$l" in *"step 1/1"*|*"loop block"*) echo "FAIL --line read the 0.3.0 routing.json: $l"; fail=1;; "smartuse · working"*) echo "PASS --line reads the keyed dir only (no step / loop suffix from projects/old): $l";; *) echo "FAIL --line of the keyed dir: $l"; fail=1;; esac
evp "$PW3" "{\"hook_event_name\":\"Stop\",\"session_id\":\"l1\",\"stop_hook_active\":false,\"cwd\":\"$PW3\"}"
l=$(CLAUDE_PROJECT_DIR="$PW3" py "$H/heartbeat.py" --line); case "$l" in "smartuse · waiting on you"*) [ "$(ls "$L")" = "routing.json" ] && [ "$(cat "$L/routing.json")" = "$(cat "$D/old-before.json")" ] && echo "PASS Stop ends the turn (the 0.3.0 run does not hold it), projects/old left as it was: $l" || { echo "FAIL projects/old written: $(ls "$L")"; fail=1; };; *) echo "FAIL Stop held by the 0.3.0 routing.json: $l"; fail=1;; esac
# --- write_json never raises: when the replace cannot land (here status.json is a directory; on Windows a reader holding the file) the hook retries, drops its tmp file and exits 0
mv "$S" "$S.keep"; mkdir "$S"; ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"s3\",\"tool_name\":\"Read\",\"tool_use_id\":\"t8\",$C}"
[ -d "$S" ] && [ -z "$(ls "$P" | grep '\.tmp$')" ] && echo "PASS replace failure -> retried, tmp file removed, exit 0, no output" || { echo "FAIL replace failure left: $(ls "$P")"; fail=1; }
rmdir "$S"; mv "$S.keep" "$S"
# --- non-ASCII in an event: Windows Python would decode a piped stdin as cp1252 (Á = C3 81, 0x81 undefined -> error, event lost); the hook reads bytes and decodes UTF-8
out=$(printf '%s' "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"s3\",\"agent_id\":\"u8\",\"agent_type\":\"Á中文-agent\",$C}" | PYTHONIOENCODING=cp1252 CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py"; echo "rc=$?")
[ "$out" = "rc=0" ] && echo "PASS event with Á / 中文 under PYTHONIOENCODING=cp1252 -> exit 0, no output" || { echo "FAIL cp1252 event: $out"; fail=1; }
expect "agent type with Á / 中文 recorded (stdin read as bytes, decoded as UTF-8)" "waiting on agent: Á中文-agent"
ev "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s3\",\"agent_id\":\"u8\",$C}"
[ -z "$(ls "$P" | grep '\.tmp$')" ] && echo "PASS no temp files left behind" || { echo "FAIL temp files left: $(ls "$P")"; fail=1; }
# --- M3: the wait gate's outcome (docs/notes/one-session-design.md). wait-gate.py writes wait.json at Stop when a hand-off is open. Rendered
# only when the turn is over, from this session, and not older than the last UserPromptSubmit (status.json prompt_at): "stopped" / "blocked"
# -> "STOPPED · handed off <HH:MM> (<what>) — nothing will wake this session", "watching" -> "waiting on <what> · watcher armed <HH:MM>"
# (HH:MM = the local clock); anything else -> "waiting on you". A project of its own, so the earlier cases stay as they were.
mkdir -p "$D/wproj"; PWW=$(wp "$D/wproj"); KW=$(key "$PWW"); WJ="$HOME/.claude/smartuse/projects/$KW/wait.json"; CW="\"cwd\":\"$PWW\""
evw() { out=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$PWW" py "$H/heartbeat.py"; echo "rc=$?"); [ "$out" = "rc=0" ] || { echo "FAIL hook printed or failed: $1 -> $out"; fail=1; }; }
hbl() { CLAUDE_PROJECT_DIR="$PWW" py "$H/heartbeat.py" --line; }
wline() { l=$(hbl); if [ "$l" = "$2" ]; then echo "PASS $1: $l"; else echo "FAIL $1: expected '$2', got: $l"; fail=1; fi; }   # the whole line
wexpect() { l=$(hbl); case "$l" in *"$2"*) echo "PASS $1: $l";; *) echo "FAIL $1: expected '$2' in: $l"; fail=1;; esac; }
jsw() { CLAUDE_PROJECT_DIR="$PWW" py "$H/heartbeat.py" --json | py -c "import json,sys; d=json.load(sys.stdin); assert $1, d"; }
hm() { py -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).astimezone().strftime('%H:%M'))" "$1"; }   # the local HH:MM of the epoch second $1, converted the way the hook converts a stamp
mkwait() { # $1 state, $2 what, $3 seconds ago = "since", $4 seconds ago = the watcher's "armed" (- = no watcher), $5 session_id (- = none; default w1), $6 seconds ago = "at" (default 0); A = the epoch second read in bash
  py - "$WJ" "$A" "$1" "$2" "$3" "$4" "${5-w1}" "${6-0}" <<'PY'
import datetime, json, sys
p, a, state, what, since, armed, sid, atage = sys.argv[1:9]
def iso(age): return datetime.datetime.fromtimestamp(int(a) - int(age), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
d = {"at": iso(atage), "state": state, "what": what, "since": iso(since), "watcher": None if armed == "-" else {"kind": "bash", "id": "b1", "armed": iso(armed), "state": "alive"}}
if sid != "-": d["session_id"] = sid
json.dump(d, open(p, "w"))
PY
}
evw "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"w1\",\"source\":\"startup\",$CW}"; evw "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"w1\",$CW}"
evw "{\"hook_event_name\":\"Stop\",\"session_id\":\"w1\",\"stop_hook_active\":false,$CW}"
wexpect "no wait.json: the turn is over and the line says waiting on you" "smartuse · waiting on you ·"
A=$(date +%s); hs=$(hm $((A - 300))); ha=$(hm $((A - 200)))
mkwait blocked builder 300 -; wline "wait.json blocked: STOPPED, the hand-off time (local HH:MM) and what" "smartuse · STOPPED · handed off $hs (builder) — nothing will wake this session"
mkwait stopped builder 300 -; wline "wait.json stopped: the same line" "smartuse · STOPPED · handed off $hs (builder) — nothing will wake this session"
mkwait stopped builder 300 200; wline "stopped with an ended watcher on record: still STOPPED" "smartuse · STOPPED · handed off $hs (builder) — nothing will wake this session"
mkwait watching builder 300 200; wline "wait.json watching: waiting on <what> · watcher armed <HH:MM> replaces waiting on you" "smartuse · waiting on builder · watcher armed $ha"
mkwait watching builder 300 -; wline "watching with no watcher time (taken from the Stop input): no time is invented" "smartuse · waiting on builder · watcher armed"
mkwait watching "" 300 200; wline "watching with no what" "smartuse · waiting on the hand-off · watcher armed $ha"
wshape() { # $1 = how wait.json spells the watcher: stamp (a bare ISO stamp) | hhmm (a plain "HH:MM") | at (an object with "at" instead of "armed")
  py - "$WJ" "$A" "$1" <<'PY'
import datetime, json, sys
p, a, how = sys.argv[1:4]
iso = lambda age: datetime.datetime.fromtimestamp(int(a) - age, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
w = {"stamp": iso(200), "hhmm": "09:07", "at": {"kind": "monitor", "at": iso(200)}}[how]
json.dump({"at": iso(0), "state": "watching", "what": "builder", "since": iso(300), "watcher": w}, open(p, "w"))
PY
}
wshape stamp; wline "the watcher as a bare ISO stamp" "smartuse · waiting on builder · watcher armed $ha"
wshape hhmm; wline "the watcher as a plain HH:MM string is shown as it is" "smartuse · waiting on builder · watcher armed 09:07"
wshape at; wline "the watcher as an object with at instead of armed" "smartuse · waiting on builder · watcher armed $ha"
mkwait blocked "" 300 -; wline "STOPPED with no what: no empty parentheses" "smartuse · STOPPED · handed off $hs — nothing will wake this session"
mkwait blocked '"Paste this into   the builder"  and a very long tail that goes on and on and on past sixty characters' 300 -; wexpect "what is one line (whitespace collapsed), cut at 60 characters" "(\"Paste this into the builder\" and a very long tail that goes) —"
py - "$WJ" "$A" <<'PY'
import datetime, json, sys
p, a = sys.argv[1:3]
d = {"at": datetime.datetime.fromtimestamp(int(a), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "state": "blocked", "what": "builder", "watcher": None}
json.dump(d, open(p, "w"))
PY
wexpect "no since in wait.json: the time of the Stop (at) is used" "STOPPED · handed off $(hm "$A") (builder)"
mkwait blocked builder 300 - - ; wexpect "wait.json without a session_id (an older writer) counts" "STOPPED · handed off $hs (builder)"
mkwait blocked builder 300 - other; wexpect "wait.json of ANOTHER session in this repo is not this session's: waiting on you" "smartuse · waiting on you ·"
mkwait blocked builder 300 - w1 3600; wexpect "wait.json older than the last UserPromptSubmit is last turn's: waiting on you" "smartuse · waiting on you ·"
printf 'not json' > "$WJ"; wexpect "corrupt wait.json is ignored" "smartuse · waiting on you ·"
printf '[1,2]' > "$WJ"; wexpect "wait.json that is not an object is ignored" "smartuse · waiting on you ·"
mkwait paused builder 300 -; wexpect "a state this file does not know is ignored" "smartuse · waiting on you ·"
py - "$WJ" <<'PY'
import json, sys
json.dump({"at": "yesterday", "state": "blocked", "what": "builder"}, open(sys.argv[1], "w"))
PY
wexpect "a wait.json whose at cannot be read is ignored" "smartuse · waiting on you ·"
mkwait blocked builder 300 -
jsw "d['state']=='stopped' and d['line'].startswith('smartuse · STOPPED · handed off ')" && echo "PASS --json: state stopped" || { echo "FAIL --json state stopped"; fail=1; }
mkwait watching builder 300 200
jsw "d['state']=='waiting_on_handoff' and d['line']=='smartuse · waiting on builder · watcher armed $ha'" && echo "PASS --json: state waiting_on_handoff" || { echo "FAIL --json state waiting_on_handoff"; fail=1; }
mkwait blocked builder 300 -
OUT=$(printf '%s' "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":12},\"workspace\":{\"current_dir\":\"$PWW\",\"project_dir\":\"$PWW\"}}" | py "$H/heartbeat.py" --statusline)
[ "$OUT" = "[Opus] ctx 12% · STOPPED · handed off $hs (builder) — nothing will wake this session" ] && echo "PASS --statusline: STOPPED without the smartuse prefix: $OUT" || { echo "FAIL --statusline STOPPED: $OUT"; fail=1; }
# the line follows the turn: only a turn that is over is STOPPED
evw "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"w1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"w-t1\",$CW}"
wexpect "a tool running: working, whatever wait.json says" "smartuse · working · Bash running"
evw "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"w1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"w-t1\",$CW}"
wexpect "between tools (the gate blocked, the model is acting on it): working" "smartuse · working · last Bash"
evw "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"w1\",\"agent_id\":\"wa1\",\"agent_type\":\"Explore\",$CW}"
evw "{\"hook_event_name\":\"Stop\",\"session_id\":\"w1\",\"stop_hook_active\":true,$CW}"
wexpect "an agent still running beats STOPPED" "working · waiting on agent: Explore"
evw "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"w1\",\"agent_id\":\"wa1\",$CW}"
wexpect "the agent done and the turn over (a second Stop, stop_hook_active true): STOPPED" "smartuse · STOPPED · handed off $hs (builder)"
evw "{\"hook_event_name\":\"Notification\",\"session_id\":\"w1\",\"notification_type\":\"permission_prompt\",$CW}"
wexpect "a permission prompt beats STOPPED" "waiting on you: permission prompt"
evw "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"w1\",\"tool_name\":\"Read\",\"tool_use_id\":\"w-t2\",$CW}"
evw "{\"hook_event_name\":\"Notification\",\"session_id\":\"w1\",\"notification_type\":\"idle_prompt\",$CW}"
wexpect "idle_prompt after the turn counts as the turn being over: STOPPED" "smartuse · STOPPED · handed off $hs (builder)"
echo '{"active":true,"needs_human":"which branch?","units":[]}' > "$HOME/.claude/smartuse/projects/$KW/routing.json"
wexpect "NEEDS YOU beats STOPPED" "smartuse · NEEDS YOU: which branch?"
rm "$HOME/.claude/smartuse/projects/$KW/routing.json"
A=$(date +%s); mkwait blocked builder 300 -; sleep 1.1   # a new prompt after wait.json (whole-second stamps): last turn's file is stale at once
evw "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"w1\",$CW}"
wexpect "a new UserPromptSubmit: working" "smartuse · working"
evw "{\"hook_event_name\":\"Stop\",\"session_id\":\"w1\",\"stop_hook_active\":false,$CW}"
wexpect "the next Stop with last turn's wait.json (older than the new prompt): waiting on you, not STOPPED" "smartuse · waiting on you ·"
jsw "d['prompt_at'] and d['turn']==2 and abs(__import__('time').time() - __import__('datetime').datetime.fromisoformat(d['prompt_at'].replace('Z','+00:00')).timestamp()) < 300" && echo "PASS UserPromptSubmit records prompt_at in status.json" || { echo "FAIL prompt_at: $(CLAUDE_PROJECT_DIR="$PWW" py "$H/heartbeat.py" --json | head -8)"; fail=1; }
evw "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"w2\",\"source\":\"startup\",$CW}"
jsw "d['prompt_at'] is None and d['session_id']=='w2'" && echo "PASS a new session starts with no prompt_at" || { echo "FAIL prompt_at after SessionStart"; fail=1; }
# --- the launcher (py.sh): on stock Windows `python3` is the Microsoft Store stub (prints a hint, exits 9009), so the launcher
# skips it and the next candidate, `python`, runs the hook. Here `python` wraps the interpreter the launcher itself found, so the
# case also passes on a Mac or a minimal Linux without a `python` of its own. No usable interpreter at all -> the launcher prints
# nothing and exits 0 (a hook must never block). HOME is a fresh dir here, so the hook must create projects/<key of $PW>/ under it.
REAL=$(bash "$H/py.sh" -c "import sys; sys.stdout.write(sys.executable)")
mkdir -p "$D/stub" "$D/real" "$D/home2"
printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut from Settings > Apps > Advanced app settings > App execution aliases."\nexit 9009\n' > "$D/stub/python3"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL" > "$D/real/python"; chmod +x "$D/stub/python3" "$D/real/python"
OUT=$(printf '%s' "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_use_id\":\"t\",\"session_id\":\"s\",$C}" | PATH="$D/stub:$D/real:$PATH" HOME="$D/home2" bash "$H/py.sh" "$H/heartbeat.py"; echo "rc=$?")
[ "$OUT" = "rc=0" ] && [ -f "$D/home2/.claude/smartuse/projects/$K/status.json" ] && echo "PASS launcher skips the Store stub: python3 = stub first on PATH, the hook still wrote status.json via python" || { echo "FAIL launcher skips the Store stub: $OUT"; fail=1; }
mkdir -p "$D/home4"   # a HOME with no remembered interpreter: the probe is the only way to find one
OUT=$(printf '{}' | PATH="$D/stub" HOME="$D/home4" "$BASH" "$H/py.sh" "$H/heartbeat.py" 2>&1; echo "rc=$?")
[ "$OUT" = "rc=0" ] && echo "PASS launcher with no usable interpreter: prints nothing, exit 0 (a hook never blocks)" || { echo "FAIL launcher without an interpreter: $OUT"; fail=1; }
# --- 0.6.1 F3: --say-missing, one optional FIRST word (an exact comparison, dropped before the hook path). With an interpreter nothing
# changes. Without one: a fixed sentence on stderr and exit 2 (the docs: a SessionStart hook that exits 2 "shows stderr to user only"
# and the session goes on); stdout stays empty. Without the word the launcher stays silent with exit 0 (the case above).
MISSING="smartuse: Python 3 was not found (tried python3, python, py -3). Its guards, gates and status line are OFF. Install Python 3.9 or newer and restart Claude Code."
RC=0; OUT=$(printf '{}' | PATH="$D/stub" HOME="$D/home4" "$BASH" "$H/py.sh" --say-missing "$H/heartbeat.py" 2>"$D/missing.err") || RC=$?
[ "$OUT" = "" ] && [ "$RC" = 2 ] && [ "$(cat "$D/missing.err")" = "$MISSING" ] && echo "PASS F3 --say-missing with no interpreter: the fixed sentence on stderr, exit 2, empty stdout" || { echo "FAIL F3 --say-missing without an interpreter: stdout '$OUT', rc $RC, stderr '$(cat "$D/missing.err")'"; fail=1; }
RC=0; OUT=$(printf '{}' | PATH="$D/stub" HOME="$D/home4" "$BASH" "$H/py.sh" "$H/heartbeat.py" 2>"$D/missing.err") || RC=$?
[ "$OUT" = "" ] && [ "$RC" = 0 ] && [ ! -s "$D/missing.err" ] && echo "PASS F3 no word and no interpreter: still silent, exit 0" || { echo "FAIL F3 silent launcher: stdout '$OUT', rc $RC, stderr '$(cat "$D/missing.err")'"; fail=1; }
mkdir -p "$D/home6"; RC=0
OUT=$(printf '%s' "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_use_id\":\"t\",\"session_id\":\"s\",$C}" | PATH="$D/stub:$D/real:$PATH" HOME="$D/home6" bash "$H/py.sh" --say-missing "$H/heartbeat.py" 2>"$D/missing.err") || RC=$?
[ "$OUT" = "" ] && [ "$RC" = 0 ] && [ ! -s "$D/missing.err" ] && [ -f "$D/home6/.claude/smartuse/projects/$K/status.json" ] && echo "PASS F3 --say-missing with an interpreter: the word is dropped, the hook runs, nothing printed, exit 0" || { echo "FAIL F3 --say-missing with an interpreter: stdout '$OUT', rc $RC, stderr '$(cat "$D/missing.err")'"; fail=1; }
OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home6" bash "$H/py.sh" --say-missing -c "print('ran')" 2>&1) || true
[ "$OUT" = ran ] && echo "PASS F3 --say-missing is dropped before the interpreter's own arguments" || { echo "FAIL F3 word not dropped: '$OUT'"; fail=1; }
OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home6" bash "$H/py.sh" -c "import sys; print(' '.join(sys.argv[1:]))" --say-missing x --say-missing 2>&1) || true
[ "$OUT" = "--say-missing x --say-missing" ] && echo "PASS F3 the word in any later position reaches Python untouched" || { echo "FAIL F3 later --say-missing: '$OUT'"; fail=1; }
mkdir -p "$D/home7/.claude/smartuse" "$D/stub3"; printf 'python\n' > "$D/home7/.claude/smartuse/interpreter"; printf '#!/bin/sh\n: > "%s/called"\nexit 9009\n' "$D/stub3" > "$D/stub3/python3"; chmod +x "$D/stub3/python3"
OUT=$(PATH="$D/stub3:$D/real" HOME="$D/home7" "$BASH" "$H/py.sh" --say-missing -c "print('ran')" 2>&1) || true
[ "$OUT" = ran ] && [ ! -e "$D/stub3/called" ] && echo "PASS F3 the remembered-name path takes the word too: the cached python runs, the stub ahead of it is never started" || { echo "FAIL F3 remembered name with the word: '$OUT', stub called: $([ -e "$D/stub3/called" ] && echo yes || echo no)"; fail=1; }
RC=0; OUT=$(PATH="$D/stub" HOME="$D/home7" "$BASH" "$H/py.sh" --say-missing -c "print('ran')" 2>"$D/missing.err") || RC=$?
[ "$OUT" = "" ] && [ "$RC" = 2 ] && [ "$(cat "$D/missing.err")" = "$MISSING" ] && echo "PASS F3 a remembered name that PATH no longer has, no other interpreter: the sentence, exit 2" || { echo "FAIL F3 stale remembered name: stdout '$OUT', rc $RC, stderr '$(cat "$D/missing.err")'"; fail=1; }
# hooks.json: only the SessionStart heartbeat command carries the word (the guards, the other heartbeat events and recall do not)
HW=$(py - "$H/hooks.json" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
want = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" --say-missing "${CLAUDE_PLUGIN_ROOT}/hooks/heartbeat.py"'
bad = []
for ev, ents in h.items():
    for ent in ents:
        for hd in ent.get("hooks", []):
            c = hd.get("command", "")
            if ev == "SessionStart" and c.endswith("/heartbeat.py\""):
                if c != want or hd.get("timeout") != 5 or hd.get("async"):
                    bad.append("SessionStart heartbeat: %r" % hd)
            elif "--say-missing" in c:
                bad.append("%s carries the word: %s" % (ev, c))
if not any(hd.get("command") == want for ent in h.get("SessionStart", []) for hd in ent.get("hooks", [])):
    bad.append("SessionStart heartbeat command lacks --say-missing")
print("BAD " + "; ".join(bad) if bad else "OK")
PY
)
[ "$HW" = OK ] && echo "PASS F3 hooks.json: only the SessionStart heartbeat command has --say-missing (blocking, timeout 5)" || { echo "FAIL F3 hooks.json: $HW"; fail=1; }
# --- the launcher remembers the NAME of the candidate it proved (python3, python or py -3, never a path) in
# ~/.claude/smartuse/interpreter: one start per event instead of a probe + a start (+ the stub's own start on stock Windows, 2 s per
# event on the author's laptop). The file is a hint about which probe step to skip, not a command: a writable state file must not
# choose what the hooks run, so a path, any other word, a name PATH no longer has and a Store alias (WindowsApps) are all ignored
# and probed again. Remembered only once ~/.claude/smartuse exists, and never written through a symlink.
CF="$D/home5/.claude/smartuse/interpreter"; mkdir -p "${CF%/*}"
OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" bash "$H/py.sh" -c "print('ran')" 2>&1)
P5=""; [ -f "$CF" ] && read -r P5 < "$CF"
[ "$OUT" = ran ] && case "$P5" in python3|python|"py -3") true;; *) false;; esac && echo "PASS launcher remembers the name the probe proved (a word, never a path): $P5" || { echo "FAIL launcher cache: out '$OUT', cached '$P5'"; fail=1; }
mkdir -p "$D/stub2"; printf '#!/bin/sh\n: > "%s/called"\nexit 9009\n' "$D/stub2" > "$D/stub2/python3"; chmod +x "$D/stub2/python3"
printf 'python\n' > "$CF"
OUT=$(PATH="$D/stub2:$D/real" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1)
[ "$OUT" = ran ] && [ ! -e "$D/stub2/called" ] && echo "PASS the remembered name runs straight away, and the stub ahead of it on PATH is never started" || { echo "FAIL remembered name: out '$OUT', stub called: $([ -e "$D/stub2/called" ] && echo yes || echo no)"; fail=1; }
printf 'python3\n' > "$CF"
OUT=$(PATH="$D/real" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1); P5=""; read -r P5 < "$CF"
[ "$OUT" = ran ] && [ "$P5" = python ] && echo "PASS a remembered name that PATH no longer has is probed again and replaced: $P5" || { echo "FAIL stale cache: out '$OUT', cached '$P5'"; fail=1; }
mkdir -p "$D/tmp"; printf '#!/bin/sh\necho EVIL\n' > "$D/tmp/python3"; chmod +x "$D/tmp/python3"; printf '%s\n' "$D/tmp/python3" > "$CF"
OUT=$(printf '{}' | PATH="$D/stub:$D/real" HOME="$D/home5" "$BASH" "$H/py.sh" "$H/heartbeat.py" 2>&1; echo "rc=$?")
[ "$OUT" = "rc=0" ] && echo "PASS a remembered path is never run, whatever its name: the probe runs the hook, nothing else" || { echo "FAIL launcher ran a remembered path: $OUT"; fail=1; }
printf '%s\n' "$REAL" > "$CF"   # a 0.5.0 cache: the absolute path of the real interpreter
OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1); P5=""; read -r P5 < "$CF"
[ "$OUT" = ran ] && case "$P5" in python3|python|"py -3") true;; *) false;; esac && echo "PASS a 0.5.0 cache (a path) is probed again and rewritten as a name: $P5" || { echo "FAIL upgrade from a path cache: out '$OUT', cached '$P5'"; fail=1; }
printf 'python3; echo pwned\n' > "$CF"
OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1)
[ "$OUT" = ran ] && echo "PASS the remembered word is one of three exact names, not a pattern: nothing after it runs" || { echo "FAIL a remembered word with a tail: $OUT"; fail=1; }
: > "$CF"; RC=0
OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1) || RC=$?
[ "$OUT" = ran ] && [ $RC = 0 ] && echo "PASS an empty remembered file is probed, rc 0" || { echo "FAIL empty cache: out '$OUT', rc $RC"; fail=1; }
mkdir -p "$D/WindowsApps"; cp "$D/stub/python3" "$D/WindowsApps/python3"; chmod +x "$D/WindowsApps/python3"; printf 'python3\n' > "$CF"
OUT=$(PATH="$D/WindowsApps:$D/real" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1); P5=""; read -r P5 < "$CF"
[ "$OUT" = ran ] && [ "$P5" = python ] && echo "PASS a Store alias (WindowsApps) is never exec'd from the cache: probed again, python remembered" || { echo "FAIL WindowsApps alias: out '$OUT', cached '$P5'"; fail=1; }
case "$OSTYPE" in
  msys*|cygwin*) echo "SKIP the launcher never writes through a symlinked cache file: Windows, no symlinks";;
  *) printf 'junk\n' > "$D/target"; rm -f "$CF"; ln -s "$D/target" "$CF"
     OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1); T5=""; read -r T5 < "$D/target"
     [ "$OUT" = ran ] && [ "$T5" = junk ] && echo "PASS the launcher never writes through a symlinked cache file" || { echo "FAIL symlinked cache: out '$OUT', target '$T5'"; fail=1; };;
esac
# N6: the remembered name is on PATH but that file cannot be run (no exec bit): the old launcher exec'd it and bash exited 2 (126 on Linux), and an exit 2 blocks a PreToolUse hook. Now it is probed instead.
#     No executable python may follow on PATH (bash would pick that one and hide the bug): only a python3 does.
rm -f "$CF"; mkdir -p "$D/nx" "$D/real3"; printf 'fi\n' > "$D/nx/python"; chmod -x "$D/nx/python"; printf 'python\n' > "$CF"; RC=0
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL" > "$D/real3/python3"; chmod +x "$D/real3/python3"
OUT=$(PATH="$D/nx:$D/real3" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1) || RC=$?; P5=""; read -r P5 < "$CF"
[ "$OUT" = ran ] && [ $RC = 0 ] && [ "$P5" = python3 ] && echo "PASS a remembered name whose file on PATH is not executable is probed again, rc 0 (was exit 2 / 126), python3 remembered" || { echo "FAIL non-executable hit: out '$OUT', rc $RC, cached '$P5'"; fail=1; }
# N7: an environment variable named like the remembered word (python=...). On bash >= 4 this passes with or without the fix; on macOS /bin/bash 3.2 (CI) it is the regression check: there BASH_CMDS does not exist and $W was read as arithmetic.
printf 'python\n' > "$CF"; RC=0
OUT=$(python=/usr/bin/python3.11 PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1) || RC=$?
[ "$OUT" = ran ] && [ $RC = 0 ] && echo "PASS an env var named python does not abort the launcher (bash $BASH_VERSION; on bash >= 4 it passes either way, the bash 3.2 check runs on macOS /bin/bash in CI)" || { echo "FAIL env var named python: out '$OUT', rc $RC"; fail=1; }
# N8: the cache path is a FIFO: reading it is skipped ([ -f ] is false) and the write must not open it (a write to a FIFO with no reader blocks for ever). A watchdog turns a hang into a FAIL.
case "$OSTYPE" in
  msys*|cygwin*) echo "SKIP the launcher never opens a FIFO cache path: Windows, no FIFOs";;
  *) rm -f "$CF"; mkfifo "$CF"; n=0
     (PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" > "$D/fifo.out" 2>&1) & W8=$!
     while kill -0 "$W8" 2>/dev/null && [ $n -lt 100 ]; do sleep 0.2; n=$((n + 1)); done   # up to 20 s
     if kill -0 "$W8" 2>/dev/null; then pkill -P "$W8" 2>/dev/null || true; kill "$W8" 2>/dev/null || true; echo "FAIL FIFO cache file: the launcher is still running after 20 s (hung on the FIFO)"; fail=1
     else wait "$W8" 2>/dev/null || true; OUT=$(cat "$D/fifo.out"); [ "$OUT" = ran ] && echo "PASS the launcher never opens a FIFO cache file: it finished and ran" || { echo "FAIL FIFO cache file: out '$OUT'"; fail=1; }; fi
     rm -f "$CF";;
esac
# N9: a Store alias in another spelling of the folder name (WINDOWSAPPS): matched in any case, so it is never exec'd from the cache. (On a case-insensitive disk this is the same folder as WindowsApps; the PATH spelling is what is matched.)
mkdir -p "$D/WINDOWSAPPS"; cp "$D/stub/python3" "$D/WINDOWSAPPS/python3"; chmod +x "$D/WINDOWSAPPS/python3"; rm -f "$CF"; printf 'python3\n' > "$CF"
OUT=$(PATH="$D/WINDOWSAPPS:$D/real" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1); P5=""; read -r P5 < "$CF"
[ "$OUT" = ran ] && [ "$P5" = python ] && echo "PASS a Store alias under WINDOWSAPPS (upper case) is never exec'd from the cache: probed again, python remembered" || { echo "FAIL WINDOWSAPPS alias: out '$OUT', cached '$P5'"; fail=1; }
# --- 0.6.1 F1: the heartbeat's three tool-event handlers run in the background ("async": true), so a "before" can land after its
# "after", a failed call has its own event (PostToolUseFailure: tool_name, tool_use_id, error, is_interrupt; the field names are the
# docs' sample, no recorded event holds one), and two hooks can write at once. status.json keeps `done`, the last 32 tool_use_ids a
# PostToolUse / PostToolUseFailure saw: a PreToolUse whose id is in it counts the call but never sets tool_running.
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"f1\",\"source\":\"startup\",$C}"
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"f1\",$C}"
ev "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"f1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"f1a\",$C}"
expect "F1 a Bash call is running" "working · Bash running"
ev "{\"hook_event_name\":\"PostToolUseFailure\",\"session_id\":\"f1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"f1a\",\"error\":\"Exit code 1\",\"is_interrupt\":false,\"duration_ms\":12,$C}"
expect "F1 PostToolUseFailure clears 'running': the line moves on to last Bash" "working · last Bash"
js "d['tool_running'] is None and d['last_tool']['name']=='Bash' and d['tool_calls']==1" && echo "PASS F1 --json: a failed call leaves no tool_running, last_tool Bash, one call" || { echo "FAIL F1 --json after PostToolUseFailure"; fail=1; }
# PostToolUse, then a "before" of the same id that lands late: the line stays on last Bash, one call counted
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"f1\",$C}"
ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"f1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"f1b\",$C}"
ev "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"f1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"f1b\",$C}"
expect_not "F1 a late PreToolUse of a finished id does not set 'running'" "Bash running"
expect "F1 the line stays on last Bash" "working · last Bash"
expect "F1 the late PreToolUse still counts the call" "1 call this turn"
# a PreToolUse with a new id after that: running
ev "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"f1\",\"tool_name\":\"Read\",\"tool_use_id\":\"f1c\",$C}"
expect "F1 a PreToolUse with a new id is running" "working · Read running"
js "d['tool_calls']==2" && echo "PASS F1 --json: two calls counted" || { echo "FAIL F1 two calls counted"; fail=1; }
# a failure after a late-landing "before": same rule
ev "{\"hook_event_name\":\"PostToolUseFailure\",\"session_id\":\"f1\",\"tool_name\":\"Read\",\"tool_use_id\":\"f1c\",\"error\":\"nope\",$C}"
ev "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"f1\",\"tool_name\":\"Read\",\"tool_use_id\":\"f1c\",$C}"
expect "F1 a late PreToolUse after a failure does not set 'running' either" "working · last Read"
# done: the last 32 ids, newest last; a prompt empties it. Seeded with 31 ids, then three finished calls.
py - "$S" <<'PY'
import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["done"]=["seed%d" % i for i in range(31)]; json.dump(s,open(p,"w"))
PY
for i in 1 2 3; do ev "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"f1\",\"tool_name\":\"Bash\",\"tool_use_id\":\"fd$i\",$C}"; done
js "len(d['done'])==32 and d['done'][-3:]==['fd1','fd2','fd3'] and 'seed0' not in d['done'] and 'seed1' not in d['done'] and d['done'][0]=='seed2'" && echo "PASS F1 done holds 32 at most: the oldest ids drop, the newest stay last" || { echo "FAIL F1 done cap: $(py -c "import json,sys; print(json.load(open(sys.argv[1])).get('done'))" "$S")"; fail=1; }
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"f1\",$C}"
js "d['done']==[]" && echo "PASS F1 a prompt empties done" || { echo "FAIL F1 done after a prompt"; fail=1; }
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"f2\",\"source\":\"startup\",$C}"
js "d['done']==[]" && echo "PASS F1 a fresh session starts with done empty" || { echo "FAIL F1 done in a fresh state"; fail=1; }
# twenty events fired at once, different ids: status.json parses and counts 20 (POSIX flock; Windows msvcrt.locking)
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"f2\",$C}"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  ( printf '%s' "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"f2\",\"tool_name\":\"Bash\",\"tool_use_id\":\"par$i\",$C}" | CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py" >/dev/null 2>&1 ) &
done
wait
js "d['tool_calls']==20" && echo "PASS F1 twenty events at once: status.json parses and counts 20" || { echo "FAIL F1 twenty at once: $(py -c "import json,sys; print(json.load(open(sys.argv[1])).get('tool_calls'))" "$S" 2>&1)"; fail=1; }
# hooks.json: the three heartbeat tool handlers are async; no guard, ledger, until-done, wait-gate or recall handler is; the
# blocking smartuse handlers a tool call waits on (PreToolUse + PostToolUse entries whose matcher fits) are
# Bash 1, Read 0, Write 1 now and 3, 2, 3 when "async" is ignored (0.6.0: nothing was async).
HC=$(py - "$H/hooks.json" <<'PY'
import json, re, sys
h = json.load(open(sys.argv[1]))["hooks"]
bad = []
def handlers(ev):
    for ent in h.get(ev, []):
        for hd in ent.get("hooks", []):
            yield ent.get("matcher"), hd
def script(hd):
    m = re.search(r"hooks/([a-z-]+)\.py", hd.get("command", ""))
    return m.group(1) if m else None
for ev in h:
    for _, hd in handlers(ev):
        s = script(hd)
        if s is None or not hd.get("command", "").startswith('bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh"'):
            bad.append("not a smartuse launcher command: %s %s" % (ev, hd.get("command")))
        tool_hb = s == "heartbeat" and ev in ("PreToolUse", "PostToolUse", "PostToolUseFailure")
        if tool_hb:
            if hd.get("async") is not True or hd.get("timeout") != 5:
                bad.append("heartbeat tool handler under %s must be async with timeout 5: %s" % (ev, hd))
        elif hd.get("async"):
            bad.append("%s handler under %s must stay blocking" % (s, ev))
        elif hd.get("timeout") is None:
            bad.append("%s under %s lost its timeout" % (s, ev))
for ev in ("PreToolUse", "PostToolUse", "PostToolUseFailure"):
    if not any(m == "*" and script(hd) == "heartbeat" for m, hd in handlers(ev)):
        bad.append("no heartbeat handler on matcher * under " + ev)
def waited(tool, ignore_async):
    n = 0
    for ev in ("PreToolUse", "PostToolUse"):   # a call that succeeds; a failed one ends in PostToolUseFailure instead of PostToolUse, with the same async heartbeat
        for m, hd in handlers(ev):
            if (m is None or m == "*" or re.fullmatch(m, tool)) and (ignore_async or not hd.get("async")):
                n += 1
    return n
now = {t: waited(t, False) for t in ("Bash", "Read", "Write")}
was = {t: waited(t, True) for t in ("Bash", "Read", "Write")}
was_ok = was == {"Bash": 3, "Read": 2, "Write": 3}
if now != {"Bash": 1, "Read": 0, "Write": 1}:
    bad.append("blocking per call now: %s" % now)
if not was_ok:
    bad.append("per call with async ignored: %s" % was)
print("blocking per call: " + " ".join("%s %d" % kv for kv in now.items()) + " (async ignored: " + " ".join("%s %d" % kv for kv in was.items()) + ")")
print("BAD" if bad else "OK")
for b in bad:
    print(b)
PY
)
case "$HC" in *$'\n'OK*) echo "PASS F1 hooks.json: $(printf '%s\n' "$HC" | head -1)";; *) echo "FAIL F1 hooks.json: $HC"; fail=1;; esac
# --- 0.6.1 F5b: the switch is visible. SessionStart stores `config` (strict, rules_off, wait_gate: the CLAUDE_PLUGIN_OPTION_* texts as the
# hook sees them; None when unset) in status.json. While valid rule names are off and strict is not on, --line ends ` · N rule(s) off` and
# SessionStart prints ONE systemMessage naming them (E5 decides whether the user sees it; the fallback is stderr + exit 2). A name the
# hook does not know, and the three on the floor (human-only, trust-pin, config-switch), do not count. Strict on, or a strict value the
# hook cannot read as on or off (counts as strict), shows nothing. Every other run still prints nothing.
evo() { OUTO=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$PW" py "$H/heartbeat.py"; echo "rc=$?"); }   # the event in $1, the hook's output + rc in $OUTO; the caller sets the option variables
SS() { printf '%s' "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$1\",\"source\":\"${2:-startup}\",$C}"; }
CLAUDE_PLUGIN_OPTION_RULES_OFF="force-push" evo "$(SS g1)"
case "$OUTO" in '{"systemMessage": "smartuse: rules off: force-push"}'*"rc=0") echo "PASS F5b SessionStart with one rule off prints one systemMessage naming it, exit 0";; *) echo "FAIL F5b SessionStart message: $OUTO"; fail=1;; esac
js "d['config']=={'strict':None,'rules_off':'force-push','wait_gate':None}" && echo "PASS F5b --json: config stored as the hook saw it (unset options are None)" || { echo "FAIL F5b config: $(py -c "import json,sys; print(json.load(open(sys.argv[1])).get('config'))" "$S")"; fail=1; }
ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"g1\",$C}"
expect "F5b the line ends with the suffix for one rule" " · 1 rule off"
expect_not "F5b one rule is singular" "1 rules off"
CLAUDE_PLUGIN_OPTION_RULES_OFF="Force-Push, sudo  nonsense,human-only,trust-pin,config-switch" evo "$(SS g2)"
case "$OUTO" in '{"systemMessage": "smartuse: rules off: force-push, sudo"}'*"rc=0") echo "PASS F5b the message names the valid rules only (case, commas and blanks separate; unknown and floor names dropped)";; *) echo "FAIL F5b message names: $OUTO"; fail=1;; esac
expect "F5b two valid rules: plural" " · 2 rules off"
CLAUDE_PLUGIN_OPTION_STRICT="true" CLAUDE_PLUGIN_OPTION_RULES_OFF="force-push" evo "$(SS g3)"
[ "$OUTO" = "rc=0" ] && echo "PASS F5b strict on: Rules off is ignored, nothing printed" || { echo "FAIL F5b strict on printed: $OUTO"; fail=1; }
expect_not "F5b strict on: no suffix" "rule"
CLAUDE_PLUGIN_OPTION_STRICT="maybe" CLAUDE_PLUGIN_OPTION_RULES_OFF="force-push" evo "$(SS g4)"
[ "$OUTO" = "rc=0" ] && echo "PASS F5b a strict value that is neither on nor off counts as strict: nothing printed" || { echo "FAIL F5b unreadable strict printed: $OUTO"; fail=1; }
expect_not "F5b unreadable strict: no suffix" " off"
CLAUDE_PLUGIN_OPTION_STRICT="false" CLAUDE_PLUGIN_OPTION_WAIT_GATE="on" CLAUDE_PLUGIN_OPTION_RULES_OFF="nonsense,human-only" evo "$(SS g5)"
[ "$OUTO" = "rc=0" ] && echo "PASS F5b only unknown and floor names: nothing printed" || { echo "FAIL F5b unknown names printed: $OUTO"; fail=1; }
js "d['config']=={'strict':'false','rules_off':'nonsense,human-only','wait_gate':'on'}" && echo "PASS F5b --json: the three options stored as texts" || { echo "FAIL F5b config texts"; fail=1; }
expect_not "F5b unknown and floor names: no suffix" "rule"
evo "$(SS g6)"
[ "$OUTO" = "rc=0" ] && echo "PASS F5b SessionStart with no option set prints nothing" || { echo "FAIL F5b no options printed: $OUTO"; fail=1; }
js "d['config']=={'strict':None,'rules_off':None,'wait_gate':None}" && echo "PASS F5b --json: nothing set -> config of three None" || { echo "FAIL F5b empty config"; fail=1; }
CLAUDE_PLUGIN_OPTION_RULES_OFF="sudo" evo "$(SS g7)"; ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"g7\",$C}"
CLAUDE_PLUGIN_OPTION_RULES_OFF="sudo" evo "$(SS g7 compact)"
[ "$OUTO" = "rc=0" ] && echo "PASS F5b a compact of the same session does not repeat the message" || { echo "FAIL F5b compact message: $OUTO"; fail=1; }
expect "F5b ... and the suffix stays on the line" " · 1 rule off"
# the literal copy of bash-guard.py's RULE_NAMES in heartbeat.py (no import between hooks) must match it; 0.7.3 F4: a bash-guard.py without RULE_NAMES is BAD, never a skip (m1 below proves it)
rncmp() { py - "$1" "$2" <<'PY'
import ast, sys
def tup(path, name):
    for n in ast.walk(ast.parse(open(path, encoding="utf-8").read())):
        if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in n.targets):
            return list(ast.literal_eval(n.value))
    return None
mine, theirs = tup(sys.argv[1], "KNOWN_RULES"), tup(sys.argv[2], "RULE_NAMES")
gates = tup(sys.argv[2], "GATE_NAMES")   # 0.7.0 F10: the named gates (paid) are known names too, so the copy is RULE_NAMES plus GATE_NAMES
if theirs is not None:
    theirs = theirs + (gates or [])
if mine is None:
    print("BAD heartbeat.py has no KNOWN_RULES")
elif theirs is None:
    print("BAD bash-guard.py has no RULE_NAMES")
elif sorted(mine) == sorted(theirs) and len(set(mine)) == len(mine):
    print("OK %d names" % len(mine))
else:
    print("BAD only in heartbeat.py: %s; only in bash-guard.py: %s" % (sorted(set(mine) - set(theirs)), sorted(set(theirs) - set(mine))))
PY
}
CMP=$(rncmp "$H/heartbeat.py" "$H/bash-guard.py")
case "$CMP" in OK*) echo "PASS F5b KNOWN_RULES in heartbeat.py equals bash-guard.py RULE_NAMES: $CMP";; *) echo "FAIL F5b KNOWN_RULES vs RULE_NAMES: $CMP"; fail=1;; esac
# m1 (0.7.3 F4), a mutation: a temp copy of bash-guard.py whose RULE_NAMES is renamed goes through the same comparison and must be BAD (it was a SKIP, which left heartbeat's copy unchecked and the suite green)
sed 's/RULE_NAMES/RULE_NAMEX/g' "$H/bash-guard.py" > "$D/bg-mut.py"
CMPM=$(rncmp "$H/heartbeat.py" "$D/bg-mut.py")
case "$CMPM" in "BAD bash-guard.py has no RULE_NAMES") echo "PASS F5b m1 a bash-guard.py without RULE_NAMES is BAD, not a skip: $CMPM";; *) echo "FAIL F5b m1 a bash-guard.py without RULE_NAMES: $CMPM"; fail=1;; esac
# --- 0.6.1 F6: --guard, the second optional first word of py.sh, on the three guard commands. No interpreter and Strict guards on (the option
# text is anything but empty / off / false / no / 0) -> a fixed sentence on stderr and exit 2: the call is blocked and Claude is told why.
# Light (the default, also when no option is set) -> silent exit 0 as before. With an interpreter nothing changes.
GUARDSAY="smartuse: Python 3 was not found (tried python3, python, py -3), so this call is blocked: Strict guards is on and its guard cannot run. Install Python 3.9 or newer and restart Claude Code, or switch Strict guards off in /plugin configure."
RC=0; OUT=$(printf '{}' | CLAUDE_PLUGIN_OPTION_STRICT=true PATH="$D/stub" HOME="$D/home4" "$BASH" "$H/py.sh" --guard "$H/file-guard.py" 2>"$D/missing.err") || RC=$?
[ "$OUT" = "" ] && [ "$RC" = 2 ] && [ "$(cat "$D/missing.err")" = "$GUARDSAY" ] && echo "PASS F6 --guard, no interpreter, strict: the fixed sentence on stderr, exit 2, empty stdout" || { echo "FAIL F6 --guard strict without an interpreter: stdout '$OUT', rc $RC, stderr '$(cat "$D/missing.err")'"; fail=1; }
RC=0; OUT=$(printf '{}' | CLAUDE_PLUGIN_OPTION_STRICT=maybe PATH="$D/stub" HOME="$D/home4" "$BASH" "$H/py.sh" --guard "$H/file-guard.py" 2>"$D/missing.err") || RC=$?
[ "$OUT" = "" ] && [ "$RC" = 2 ] && echo "PASS F6 --guard, no interpreter, a Strict text that is neither on nor off counts as strict: exit 2" || { echo "FAIL F6 --guard unreadable strict: stdout '$OUT', rc $RC"; fail=1; }
for SV in UNSET "" off False " no " 0; do
  if [ "$SV" = UNSET ]; then RC=0; OUT=$(printf '{}' | env -u CLAUDE_PLUGIN_OPTION_STRICT PATH="$D/stub" HOME="$D/home4" "$BASH" "$H/py.sh" --guard "$H/file-guard.py" 2>"$D/missing.err") || RC=$?
  else RC=0; OUT=$(printf '{}' | CLAUDE_PLUGIN_OPTION_STRICT="$SV" PATH="$D/stub" HOME="$D/home4" "$BASH" "$H/py.sh" --guard "$H/file-guard.py" 2>"$D/missing.err") || RC=$?; fi
  [ "$OUT" = "" ] && [ "$RC" = 0 ] && [ ! -s "$D/missing.err" ] && echo "PASS F6 --guard, no interpreter, light (Strict '$SV'): silent exit 0" || { echo "FAIL F6 --guard light ('$SV'): stdout '$OUT', rc $RC, stderr '$(cat "$D/missing.err")'"; fail=1; }
done
OUT=$(CLAUDE_PLUGIN_OPTION_STRICT=true PATH="$D/stub:$D/real:$PATH" HOME="$D/home6" bash "$H/py.sh" --guard -c "print('ran')" 2>&1) || true
[ "$OUT" = ran ] && echo "PASS F6 --guard with an interpreter: the word is dropped, the interpreter runs" || { echo "FAIL F6 --guard with an interpreter: '$OUT'"; fail=1; }
OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home6" bash "$H/py.sh" -c "import sys; print(' '.join(sys.argv[1:]))" --guard x 2>&1) || true
[ "$OUT" = "--guard x" ] && echo "PASS F6 --guard in a later position reaches Python untouched" || { echo "FAIL F6 later --guard: '$OUT'"; fail=1; }
HG=$(py - "$H/hooks.json" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
bad, pre = [], h["PreToolUse"]
want = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" --guard "${CLAUDE_PLUGIN_ROOT}/hooks/%s.py"'
n = 0
for ev, ents in h.items():
    for ent in ents:
        for hd in ent.get("hooks", []):
            c = hd.get("command", "")
            if "--guard" in c:
                n += 1
                if ev != "PreToolUse" or c not in (want % "bash-guard", want % "file-guard") or hd.get("async") or hd.get("timeout") != 10:
                    bad.append("unexpected --guard: %s %r" % (ev, hd))
            elif ("bash-guard.py" in c or "file-guard.py" in c):
                bad.append("a guard command without --guard: %s" % c)
bash = [e for e in pre if e.get("matcher") == "Bash|PowerShell|Monitor"]   # 0.7.0 F3 (D-YK12): a Monitor command is a shell command to the guard
mcp = [e for e in pre if str(e.get("matcher", "")).startswith("mcp__")]
if len(bash) != 1 or len(mcp) != 1 or bash[0]["hooks"] != mcp[0]["hooks"]:
    bad.append("the Bash|PowerShell|Monitor entry and the mcp tool entry must keep identical commands")
if n != 3:
    bad.append("%d --guard commands, expected 3" % n)
print("BAD " + "; ".join(bad) if bad else "OK")
PY
)
[ "$HG" = OK ] && echo "PASS F6 hooks.json: exactly the three guard commands carry --guard (blocking, timeout 10); the Bash and mcp entries are identical" || { echo "FAIL F6 hooks.json: $HG"; fail=1; }
# --- 0.6.1 F7: --doctor, the read-only renderer behind /smartuse:doctor. At most eight lines: the Python, the plugin version, the events hooks.json
# registers, the age of the last heartbeat event, the level + rules off + any unknown name (from the stored `config`), whether the state folder
# can be written. A failing line carries its fix. It never creates the state folder.
doc() { CLAUDE_PROJECT_DIR="$1" py "$H/heartbeat.py" --doctor; }   # $1 = the project dir
ev "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"d1\",\"source\":\"startup\",$C}"; ev "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"d1\",$C}"
OUT=$(doc "$PW"); N=$(printf '%s\n' "$OUT" | wc -l)
case "$OUT" in *"python: "*"plugin: smartuse "*"hooks registered: "*"SessionStart"*"heartbeat: live · last event "*"s ago"*"level: light · rules off: none"*"state folder: writable"*) [ "$N" -le 8 ] && echo "PASS F7 --doctor, a fresh event: python, plugin, hooks, heartbeat live, level light, state folder writable ($N lines)" || { echo "FAIL F7 --doctor has $N lines (limit 8): $OUT"; fail=1; };; *) echo "FAIL F7 --doctor, a fresh event: $OUT"; fail=1;; esac
py -c "import json,sys,datetime; p=sys.argv[1]; s=json.load(open(p)); s['updated']=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'); json.dump(s,open(p,'w'))" "$S"
OUT=$(doc "$PW")
case "$OUT" in *"heartbeat: live"*) echo "FAIL F7 --doctor, an event an hour old must not read live: $OUT"; fail=1;; *"heartbeat: FAIL · last event 1h0"*"ago"*"restart Claude Code"*) echo "PASS F7 --doctor, a stale event (1h): FAIL with its age and the fix";; *) echo "FAIL F7 --doctor, a stale event: $OUT"; fail=1;; esac
NP="$D/proj-none"; NK=$(key "$(wp "$NP")")
OUT=$(doc "$(wp "$NP")")
case "$OUT" in *"heartbeat: FAIL · no event: the hooks are not firing, restart Claude Code"*"level: unknown"*"state folder: writable"*) [ ! -e "$HOME/.claude/smartuse/projects/$NK" ] && echo "PASS F7 --doctor with no state: no event, the fix, level unknown, and the state folder is not created (read-only)" || { echo "FAIL F7 --doctor created the state folder"; fail=1; };; *) echo "FAIL F7 --doctor with no state: $OUT"; fail=1;; esac
CLAUDE_PLUGIN_OPTION_RULES_OFF="Force-Push nonsense,human-only" evo "$(SS d4)"
OUT=$(doc "$PW")
case "$OUT" in *"level: light · rules off: force-push · unknown name: nonsense"*) case "$OUT" in *human-only*) echo "FAIL F7 --doctor names a floor rule: $OUT"; fail=1;; *) echo "PASS F7 --doctor, an unknown rule name: listed once; a valid name is off; a floor name is not an unknown";; esac;; *) echo "FAIL F7 --doctor, an unknown rule name: $OUT"; fail=1;; esac
# 0.7.0 F10: `paid` is a gate name (bash-guard.py GATE_NAMES), not a rule, and light can name it in Rules off: the doctor knows it
CLAUDE_PLUGIN_OPTION_RULES_OFF="paid" evo "$(SS d5)"
OUT=$(doc "$PW")
case "$OUT" in *"unknown name"*) echo "FAIL F10 --doctor, rules_off=paid must not print an unknown name: $OUT"; fail=1;; *"level: light · rules off: paid"*) echo "PASS F10 --doctor, rules_off=paid: listed as off, no unknown-name warning";; *) echo "FAIL F10 --doctor, rules_off=paid: $OUT"; fail=1;; esac
UH="$D/homeU"; mkdir -p "$UH/.claude"; : > "$UH/.claude/smartuse"   # a regular file where the state folder's parent should be: nothing can be created under it
OUT=$(HOME="$UH" doc "$PW")
case "$OUT" in *"state folder: FAIL · cannot be written"*"check"*) echo "PASS F7 --doctor, an unwritable state folder: FAIL with the fix";; *) echo "FAIL F7 --doctor, an unwritable state folder: $OUT"; fail=1;; esac
VER=$(py -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$H/../.claude-plugin/plugin.json"); VER=${VER%$'\r'}
OUT=$(doc "$PW")
case "$OUT" in *"plugin: smartuse $VER"*) [ -n "$VER" ] && echo "PASS F7 --doctor reads the plugin version from plugin.json ($VER)" || { echo "FAIL F7 empty version"; fail=1; };; *) echo "FAIL F7 --doctor version line (plugin.json says '$VER'): $OUT"; fail=1;; esac
# --- 0.7.0 D-YK15: the bytecode cache. py.sh runs a hook script (a first word that is an existing *.py file) through a short loader
# passed with -c, so Python keeps the compiled script in hooks/__pycache__/ and reuses it while the source is unchanged (a main script
# is compiled on every start and never cached; bash-guard.py's compile alone is ~60 ms). Cases run on a COPY of the hooks, so no
# pyc lands in the real folder. R1 behaves as the plain script run (compared with `python script` itself), R2 the cwd is never on
# sys.path (`-c` puts '' first: a json.py in the user's project must not be imported), R3 the cache is written once and used, R4 it
# is only a speed-up: no pyc, an unwritable pyc folder or a stale pyc all still run the current source. Not scripts -> as before
# (the `-c "..."` and `-` cases above).
K="$D/d15"; mkdir -p "$K/hooks" "$K/proj"; cp "$H/py.sh" "$H/bash-guard.py" "$H/file-guard.py" "$H/heartbeat.py" "$K/hooks/"
cat > "$K/hooks/probe.py" <<'PROBE'
import os, sys
data = sys.stdin.read()
sys.stdout.write("out:" + data + "|" + __name__ + "|" + os.path.basename(__file__) + "|" + str(os.path.isabs(__file__)) + "|" + os.path.basename(sys.argv[0]) + "|" + repr(sys.argv[1:]) + "|" + str(os.path.normcase(sys.path[0]) == os.path.normcase(os.path.dirname(os.path.realpath(__file__)))) + "|" + str(sys.modules["__main__"].__file__ == __file__) + "\n")
sys.stderr.write("err:ok\n")
if __name__ == "__main__":
    sys.exit(int(os.environ.get("PROBE_RC", "0")))
PROBE
mt() { bash "$H/py.sh" -c "import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)" "$1"; }   # a file's mtime in ns (a non-script run: the loader is not involved)
pyc() { ls "$K/hooks/__pycache__/$1".*.pyc 2>/dev/null | head -1 || true; }
BGEV='{"tool_name":"Bash","tool_input":{"command":"sudo ls"}}'; BGOK='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
FGEV='{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude/smartuse.local.md","content":"x"}}'
for RCV in 0 2 7; do
  REF=$(printf 'in put' | PROBE_RC=$RCV PYTHONUTF8=1 "$REAL" "$K/hooks/probe.py" a "b c" --guard 2>"$D/d15.rerr"; echo "rc=$?")
  GOT=$(printf 'in put' | PROBE_RC=$RCV bash "$K/hooks/py.sh" "$K/hooks/probe.py" a "b c" --guard 2>"$D/d15.gerr"; echo "rc=$?")
  if [ "$REF" = "$GOT" ] && cmp -s "$D/d15.rerr" "$D/d15.gerr"; then
    case "$GOT" in *"out:in put|__main__|probe.py|True|probe.py|['a', 'b c', '--guard']|True|True"*"rc=$RCV") echo "PASS D15 R1 the loader runs a script as python does (stdin, args after it, stderr, exit code $RCV, __name__, absolute __file__, sys.path[0] = its folder)";; *) echo "FAIL D15 R1 exit $RCV: $GOT"; fail=1;; esac
  else echo "FAIL D15 R1 exit $RCV differs from a plain run: ref '$REF' got '$GOT'"; fail=1; fi
done
for EV in "bash-guard|$BGEV" "bash-guard|$BGOK" "file-guard|$FGEV"; do
  N=${EV%%|*}; E=${EV#*|}
  REF=$(printf '%s' "$E" | CLAUDE_PLUGIN_OPTION_STRICT=true PYTHONUTF8=1 "$REAL" "$K/hooks/$N.py" 2>&1; echo "rc=$?")
  GOT=$(printf '%s' "$E" | CLAUDE_PLUGIN_OPTION_STRICT=true bash "$K/hooks/py.sh" --guard "$K/hooks/$N.py" 2>&1; echo "rc=$?")
  case "$GOT" in *rc=0) [ "$REF" = "$GOT" ] && echo "PASS D15 R1 $N through --guard prints what the plain run prints: ${GOT:0:60}" || { echo "FAIL D15 R1 $N: ref '$REF' got '$GOT'"; fail=1; };; *) echo "FAIL D15 R1 $N: $GOT"; fail=1;; esac
done
case "$GOT" in *deny*) ;; *) echo "FAIL D15 R1 the guard events must include a deny: $GOT"; fail=1;; esac
OUT=$(bash "$K/hooks/py.sh" -c "import sys; print(repr(sys.path[0]))" 2>&1) || true; [ "$OUT" = "''" ] && echo "PASS D15 -c is untouched: no loader, sys.path[0] stays ''" || { echo "FAIL D15 -c: $OUT"; fail=1; }
OUT=$(printf 'print(40+2)\n' | bash "$K/hooks/py.sh" - 2>&1) || true; [ "$OUT" = 42 ] && echo "PASS D15 '-' (a script on stdin) is untouched" || { echo "FAIL D15 stdin script: $OUT"; fail=1; }
RC=0; OUT=$(bash "$K/hooks/py.sh" "$K/hooks/nope.py" 2>&1) || RC=$?; RC0=0; "$REAL" "$K/hooks/nope.py" >/dev/null 2>&1 || RC0=$?
if [ "$RC" = "$RC0" ] && [ "$RC" != 0 ]; then
  case "$OUT" in *"can't open file"*) echo "PASS D15 R1 a script that does not exist fails as python does (exit $RC, can't open file)";; *) echo "FAIL D15 R1 missing script message: $OUT"; fail=1;; esac
else echo "FAIL D15 R1 missing script: rc $RC vs $RC0: $OUT"; fail=1; fi
if command -v cygpath >/dev/null 2>&1; then
  OUT=$(printf 'z' | bash "$K/hooks/py.sh" "$(cygpath -w "$K/hooks/probe.py")" a 2>&1) || true; case "$OUT" in *"out:z|__main__|probe.py|True|probe.py|['a']|True|True"*) echo "PASS D15 R1 a Windows-style script path (C:\\...) runs through the loader";; *) echo "FAIL D15 Windows-style path: $OUT"; fail=1;; esac
fi
# R2: a project that holds json.py / re.py / importlib/util.py (the cwd of every hook) must never be imported by the loader or the hook
mkdir -p "$K/proj/importlib"
for M in json re; do printf 'print("PLANTED-%s")\n' "$M" > "$K/proj/$M.py"; done
printf 'print("PLANTED-importlib-util")\n' > "$K/proj/importlib/util.py"; : > "$K/proj/importlib/__init__.py"
for EV in "bash-guard|$BGEV" "bash-guard|$BGOK" "file-guard|$FGEV" "heartbeat|{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_use_id\":\"t15\",\"session_id\":\"s15\",\"cwd\":\"$PW\"}"; do
  N=${EV%%|*}; E=${EV#*|}
  OUT=$(cd "$K/proj" && printf '%s' "$E" | CLAUDE_PLUGIN_OPTION_STRICT=true CLAUDE_PROJECT_DIR="$PW" bash "$K/hooks/py.sh" "$K/hooks/$N.py" 2>&1; echo "rc=$?")
  case "$OUT" in *PLANTED*|*Traceback*|*Error*) echo "FAIL D15 R2 $N imported something from the project folder: $OUT"; fail=1;; *rc=0) echo "PASS D15 R2 $N with json.py, re.py and importlib/util.py planted in the cwd: none imported";; *) echo "FAIL D15 R2 $N: $OUT"; fail=1;; esac
done
OUT=$(cd "$K/proj" && printf 'q' | bash "$K/hooks/py.sh" "$K/hooks/probe.py" 2>&1) || true; case "$OUT" in *"|True|True"*) echo "PASS D15 R2 sys.path[0] is the script's folder, not '' (checked in the script itself)";; *) echo "FAIL D15 R2 sys.path[0]: $OUT"; fail=1;; esac
# R3: the cache is written on the first run, left alone on the second, and really used
rm -rf "$K/hooks/__pycache__"
printf '%s' "$BGOK" | bash "$K/hooks/py.sh" --guard "$K/hooks/bash-guard.py" >/dev/null 2>&1 || true; PY1=$(pyc bash-guard)
[ -n "$PY1" ] && echo "PASS D15 R3 the first run wrote hooks/__pycache__/$(basename "$PY1")" || { echo "FAIL D15 R3 no bash-guard pyc after a run"; fail=1; }
if [ -n "$PY1" ]; then
  M1=$(mt "$PY1"); sleep 1
  printf '%s' "$BGOK" | bash "$K/hooks/py.sh" --guard "$K/hooks/bash-guard.py" >/dev/null 2>&1 || true; M2=$(mt "$PY1")
  [ -n "$M1" ] && [ "$M1" = "$M2" ] && echo "PASS D15 R3 the second run does not rewrite the pyc (mtime $M1 unchanged)" || { echo "FAIL D15 R3 pyc rewritten: $M1 -> $M2"; fail=1; }
fi
# the cache is USED: a source edited to a same-size text with the same mtime still runs the cached code (Python trusts mtime + size)
printf 'import os, sys\nsys.stdout.write("AAAA\\n")\n' > "$K/hooks/cached.py"
bash "$H/py.sh" -c "import os,sys; os.utime(sys.argv[1], (1700000000, 1700000000))" "$K/hooks/cached.py"
O1=$(bash "$K/hooks/py.sh" "$K/hooks/cached.py" 2>&1) || true
printf 'import os, sys\nsys.stdout.write("BBBB\\n")\n' > "$K/hooks/cached.py"
bash "$H/py.sh" -c "import os,sys; os.utime(sys.argv[1], (1700000000, 1700000000))" "$K/hooks/cached.py"
O2=$(bash "$K/hooks/py.sh" "$K/hooks/cached.py" 2>&1) || true
[ "$O1" = AAAA ] && [ "$O2" = AAAA ] && echo "PASS D15 R3 the pyc is used: a same-size, same-mtime edit still runs the cached code" || { echo "FAIL D15 R3 the cache is not used: '$O1' then '$O2' (want AAAA twice)"; fail=1; }
# R4: a changed source (other size) is recompiled and the pyc is replaced
printf 'import os, sys\nsys.stdout.write("CCCCCCCC\\n")\n' > "$K/hooks/cached.py"
O3=$(bash "$K/hooks/py.sh" "$K/hooks/cached.py" 2>&1) || true; O4=$(bash "$K/hooks/py.sh" "$K/hooks/cached.py" 2>&1) || true
[ "$O3" = CCCCCCCC ] && [ "$O4" = CCCCCCCC ] && [ -n "$(pyc cached)" ] && echo "PASS D15 R4 a stale pyc (the source changed) is recompiled: the new text runs, and the pyc stays" || { echo "FAIL D15 R4 stale pyc: '$O3' '$O4' pyc '$(pyc cached)'"; fail=1; }
# R4: PYTHONDONTWRITEBYTECODE=1 -> works, writes no pyc
rm -rf "$K/hooks/__pycache__"
OUT=$(printf '%s' "$BGEV" | PYTHONDONTWRITEBYTECODE=1 CLAUDE_PLUGIN_OPTION_STRICT=true bash "$K/hooks/py.sh" --guard "$K/hooks/bash-guard.py" 2>&1) || true
case "$OUT" in *deny*) if [ -z "$(pyc bash-guard)" ] && [ ! -e "$K/hooks/__pycache__" ]; then echo "PASS D15 R4 PYTHONDONTWRITEBYTECODE=1: the guard denies as before and no pyc is written"; else echo "FAIL D15 R4 a pyc was written under PYTHONDONTWRITEBYTECODE"; fail=1; fi;; *) echo "FAIL D15 R4 PYTHONDONTWRITEBYTECODE: $OUT"; fail=1;; esac
# R4: a pyc path that cannot be written (__pycache__ is a plain file, so the folder cannot be made) -> works as today
rm -rf "$K/hooks/__pycache__"; : > "$K/hooks/__pycache__"
OUT=$(printf '%s' "$BGEV" | CLAUDE_PLUGIN_OPTION_STRICT=true bash "$K/hooks/py.sh" --guard "$K/hooks/bash-guard.py" 2>&1; echo "rc=$?")
case "$OUT" in *deny*"rc=0") echo "PASS D15 R4 a pyc path that cannot be written (a file named __pycache__): the guard still denies, exit 0, no noise";; *) echo "FAIL D15 R4 unwritable pyc path: $OUT"; fail=1;; esac
rm -f "$K/hooks/__pycache__"
# R4: a read-only hooks folder (only where chmod really blocks a write: not as root, not on a disk that ignores modes)
mkdir -p "$K/ro"; cp "$K/hooks/py.sh" "$K/hooks/bash-guard.py" "$K/ro/"; chmod a-w "$K/ro"
if ! ( : > "$K/ro/.w" ) 2>/dev/null; then
  OUT=$(printf '%s' "$BGEV" | CLAUDE_PLUGIN_OPTION_STRICT=true bash "$K/ro/py.sh" --guard "$K/ro/bash-guard.py" 2>&1; echo "rc=$?")
  case "$OUT" in *deny*"rc=0") echo "PASS D15 R4 a read-only hooks folder: the guard still denies, exit 0, no noise";; *) echo "FAIL D15 R4 read-only folder: $OUT"; fail=1;; esac
else echo "SKIP D15 R4 (chmod does not block writes here, so a read-only folder cannot be made; the unwritable-path case above stands in)"; fi
chmod u+w "$K/ro" 2>/dev/null || true
# the repo ignores the cache folder, and py.sh stays bash 3.2 safe (nothing from bash 4+ was added)
if [ -f "$H/../../../.gitignore" ]; then grep -qx '__pycache__/' "$H/../../../.gitignore" && echo "PASS D15 .gitignore ignores __pycache__/" || { echo "FAIL D15 .gitignore lacks __pycache__/"; fail=1; }; fi
if grep -nE 'declare -[Aan]|mapfile|readarray|\|&|&>>|coproc|;;&' "$H/py.sh" >/dev/null; then echo "FAIL D15 py.sh uses a bash 4 feature: $(grep -nE 'declare -[Aan]|mapfile|readarray|\|&|&>>|coproc' "$H/py.sh" | head -2)"; fail=1; else echo "PASS D15 py.sh has no bash 4 feature (declare -A/-n, mapfile, readarray, |&, &>>, coproc, ;;&)"; fi
# ===== 0.7.1 F1 (a): a long Windows path keeps its state. A project whose state folder passes the limit (240 characters on Windows, E1: the folder is made, then
# no file reaches it; 300 characters of key elsewhere too: one name past 255) must still get a status.json and a live line, not "no activity recorded". The project path
# is keyed, never made. Own temp HOME, so the cases above are not touched; the real ~/.claude/smartuse is checked after.
NT=$(py -c 'import os, sys; sys.stdout.write("1" if os.name == "nt" else "0")' </dev/null)
H2="$D/h2"; mkdir -p "$H2/.claude/smartuse"
BL2=$(HOME="$H2" py -c 'import os, sys, pathlib; sys.stdout.write(str(len(str(pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~")) / ".claude" / "smartuse" / "projects"))))' </dev/null)
lpath() { # $1 = a key length -> a project path (forward slashes, never made) whose key is that long: C:/p/xxx -> C--p-xxx (Windows), /p/xxx -> p-xxx
  local n s; if [ "$NT" = 1 ]; then n=$(( $1 - 5 )); else n=$(( $1 - 2 )); fi
  s=$(printf '%*s' "$n" ''); s=${s// /x}; if [ "$NT" = 1 ]; then printf 'C:/p/%s' "$s"; else printf '/p/%s' "$s"; fi
}
longcase() { # $1 = label, $2 = key length
  local pw ln sd nf; pw=$(lpath "$2"); rm -rf "$H2/.claude/smartuse/projects"
  printf '%s' "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s1\",\"source\":\"startup\",\"cwd\":\"$pw\"}" | HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" >/dev/null 2>&1 || true
  ln=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" --line </dev/null 2>&1) || true
  sd=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/ledger.py" --state-dir </dev/null 2>&1) || true; sd=${sd%$'\r'}
  nf=$(ls "$H2/.claude/smartuse/projects"/*/status.json 2>/dev/null | wc -l | tr -d ' ')
  case "$ln" in *"waiting on you · no prompt yet"*) if [ "$nf" = 1 ] && [ -f "$sd/status.json" ]; then echo "PASS F1a $1: SessionStart writes status.json in the folder ledger.py names, the line is live: $ln"; else echo "FAIL F1a $1: the line is live but status.json is not in '$sd'"; fail=1; fi;;
    *) echo "FAIL F1a $1: SessionStart in a project whose key is $2 characters left no state (line: $ln; status.json files: $nf)"; fail=1;; esac
}
if [ "$NT" = 1 ]; then
  if [ $(( 239 - BL2 )) -ge 20 ]; then longcase "a state folder of 240 characters (key $(( 239 - BL2 )), Windows)" $(( 239 - BL2 )); else echo "SKIP F1a HOME is $BL2 characters, too long to build a folder of 240"; fi
else echo "SKIP F1a the 240-character state folder is Windows-only (one name may be 255 characters)"; fi
longcase "a key of 300 characters" 300
rm -rf "$H2/.claude/smartuse/projects"
[ "$(ls "$REAL_HOME/.claude/smartuse/projects" 2>/dev/null | grep -c 'xxxxxxxx')" = 0 ] && echo "PASS F1a the real ~/.claude/smartuse gained no folder from these cases" || { echo "FAIL F1a a test folder reached the real ~/.claude/smartuse/projects"; fail=1; }

# ===== 0.7.2 F3 (D-YK20): doctor tells a kept state folder that is too long for paid runs. A full-key folder that already exists is kept while a 26-character file fits in
# it (up to 232 characters), but the claim marker of a paid run is 40 characters (paid.<30-character tool_use_id>.done): in a kept folder of 219 to 232 characters, with
# Windows long paths off, it cannot be made, so doctor's short throwaway file saying "writable" was not the truth. A second throwaway of 49 characters (the longest claim
# marker, the second script's paid.<id>.<8>.done) now decides, and the FAIL line is printed only when the path really is over 209 characters (259 - 1 - 49). Windows
# only, and only with LongPathsEnabled = 0. In a kept folder of 200 characters doctor still says writable, and doctor never fills the folder. D9: a counter in both the
# full-key and the short-key folder is one FAIL line naming both folders.
if [ "$NT" = 1 ]; then
  LPON=$(py -c 'import sys
try:
    import winreg
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\FileSystem") as k:
        sys.stdout.write("1" if winreg.QueryValueEx(k, "LongPathsEnabled")[0] == 1 else "0")
except Exception:
    sys.stdout.write("0")' </dev/null)   # the same read as wait-gate-test.sh section e: this machine's long-path switch (read only)
  if [ "$LPON" = 1 ]; then echo "SKIP F3 doctor, a kept state folder too long for paid runs: Windows long paths are on here (LongPathsEnabled = 1), the 40-character file is made"
  elif [ $(( 224 - BL2 )) -lt 20 ]; then echo "SKIP F3 doctor, a kept state folder of 225 characters: HOME is $BL2 characters, too long to build it"
  else
    rm -rf "$H2/.claude/smartuse/projects"
    for L in 225 215 200; do   # 215: a single-script run still fits (40-character marker), only a two-script command fails: the line says "some paid runs"
      pw=$(lpath $(( L - 1 - BL2 ))); fk=$(key "$pw"); sf="$H2/.claude/smartuse/projects/$fk"; mkdir -p "$sf"
      OUT=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" --doctor </dev/null); N=$(printf '%s\n' "$OUT" | wc -l)
      if [ "$L" = 215 ]; then
        case "$OUT" in *"state folder: FAIL · some paid runs (two scripts in one command) cannot be counted here: its path is 215 characters"*"Windows long paths"*"delete"*"paid-runs.json"*) [ "$N" -le 8 ] && echo "PASS F3 doctor, a kept state folder of 215 characters (long paths off): FAIL says some paid runs (two scripts in one command), with its length and both ways out ($N lines)" || { echo "FAIL F3 doctor has $N lines (limit 8): $OUT"; fail=1; };; *) echo "FAIL F3 doctor, a kept state folder of 215 characters: $(printf '%s' "$OUT" | grep 'state folder')"; fail=1;; esac
      elif [ "$L" != 200 ]; then
        case "$OUT" in *"state folder: FAIL · paid runs cannot be counted here: its path is $L characters"*"Windows long paths"*"delete"*"paid-runs.json"*) [ "$N" -le 8 ] && echo "PASS F3 doctor, a kept state folder of $L characters (long paths off): FAIL with its length and both ways out ($N lines)" || { echo "FAIL F3 doctor has $N lines (limit 8): $OUT"; fail=1; };; *) echo "FAIL F3 doctor, a kept state folder of $L characters: $(printf '%s' "$OUT" | grep 'state folder')"; fail=1;; esac
      else
        case "$OUT" in *"state folder: writable"*) echo "PASS F3 doctor, a kept state folder of 200 characters: still writable";; *) echo "FAIL F3 doctor, a kept state folder of 200 characters: $(printf '%s' "$OUT" | grep 'state folder')"; fail=1;; esac
      fi
      [ -z "$(ls -A "$sf" 2>/dev/null)" ] && echo "PASS F3 doctor ($L): its throwaway files are gone, the folder is left empty" || { echo "FAIL F3 doctor ($L) left files: $(ls -A "$sf" | tr '\n' ' ')"; fail=1; }
    done
    rm -rf "$H2/.claude/smartuse/projects"
  fi
else echo "SKIP F3 doctor, a kept state folder too long for paid runs: Windows only"; fi
# the probe is 49 characters and the FAIL line checks the length (any OS: can_write is stood in for): a state folder of 209 characters or less that fails the long probe
# is "cannot be written" (not a length claim); one over 209 says the path is too long
cat > "$D/dl.py" <<'PY'
import os, pathlib, sys
src = open(os.path.join(sys.argv[1], "heartbeat.py"), encoding="utf-8").read()
cut = src.index("\ntry:\n    main()")
ns = {"__name__": "doctor_probe", "__file__": os.path.join(sys.argv[1], "heartbeat.py")}
exec(compile(src[:cut], "heartbeat", "exec"), ns)
ns["can_write"] = lambda d: (False, ns["LONG_FOLDER"])
bad = []
for n, want in ((209, "cannot be written"), (210, "some paid runs (two scripts in one command) cannot be counted here: its path is 210 characters"),
                (218, "some paid runs (two scripts in one command) cannot be counted here: its path is 218 characters"), (219, "paid runs cannot be counted here: its path is 219 characters")):
    sd = pathlib.Path("C:/" + "x" * (n - 3) if os.name == "nt" else "/" + "x" * (n - 1))
    line = [l for l in ns["doctor_lines"](sd) if l.startswith("state folder:")][0]
    if want not in line or (n == 209 and "too long" in line) or (n == 219 and "some paid runs" in line):
        bad.append("%d: %s" % (n, line[:120]))
print("ok" if not bad else "; ".join(bad))
PY
r=$(py "$D/dl.py" "$H" </dev/null 2>&1 | tail -3); [ "$r" = ok ] && echo "PASS F3 doctor: a failed 49-character probe in a folder of 209 characters says cannot be written (no length claim); at 210 to 218 it says some paid runs (two scripts in one command) cannot be counted, and from 219 that paid runs cannot" || { echo "FAIL F3 doctor probe length check: $r"; fail=1; }
# ===== 0.7.3 F2 (D-YK25): a paid counter left in the folder that is no longer used. With Windows long paths off fit_key sends a project whose full-key folder is too long to the short key, whatever the
# short folder holds, so a counter that sits in the full-key folder stays behind: the paid check refuses ("two state folders hold a counter") while doctor said "writable". Doctor now prints its own
# FAIL line: both folders, the length of the one holding the counter, and both ways out (long paths on: the count carries on; delete that folder: it starts again). It says what is in the folders,
# never how it got there, and it never creates or fills a folder. h1 to h3, any OS: fit_key is stood in (it answers a short name) over real folders under a temp base; h4, below, is the real Windows layout.
cat > "$D/cl.py" <<'PY'
import os, pathlib, sys, tempfile
src = open(os.path.join(sys.argv[1], "heartbeat.py"), encoding="utf-8").read()
cut = src.index("\ntry:\n    main()")
ns = {"__name__": "counter_probe", "__file__": os.path.join(sys.argv[1], "heartbeat.py")}
tmp = tempfile.mkdtemp(dir=sys.argv[2])
proj = os.path.join(tmp, "proj"); os.makedirs(proj)
os.environ["CLAUDE_PROJECT_DIR"] = proj
exec(compile(src[:cut], "heartbeat", "exec"), ns)
full = ns["full_key"](proj)
SHORT = "short-kkkkkkkkkk"
ns["fit_key"] = lambda f, b, nt: SHORT   # the project's key is too long for its folder: the short key is the one that is used
TWO = "state folder: FAIL · two state folders hold a paid counter: %s and %s: the paid check refuses every paid run until you delete the one that is wrong (its count and receipts go with it)" % (full, SHORT)
N = [0]

def tree(base):
    return sorted(os.path.join(r, n)[len(base):] for r, ds, fs in os.walk(base) for n in ds + fs)

def case(have_full, have_short, in_use):   # have_*: None (no folder) | "empty" | "counter"; in_use: the folder doctor is given
    N[0] += 1
    base = os.path.join(tmp, "projects%d" % N[0]); os.makedirs(base)
    for name, have in ((full, have_full), (SHORT, have_short)):
        if have:
            os.makedirs(os.path.join(base, name))
            if have == "counter":
                open(os.path.join(base, name, "paid-runs.json"), "w").write("{}")
    before = tree(base)
    lines = ns["doctor_lines"](pathlib.Path(base) / in_use)
    return base, lines, tree(base) == before

def fails(lines):
    return [l for l in lines if l.startswith("state folder: FAIL")]

res = {"h1": [], "h2": [], "h3": []}
for label, hs in (("short folder not made yet", None), ("short folder made, empty", "empty")):   # h1: the counter only in the full-key folder
    base, lines, same = case("counter", hs, SHORT)
    st = fails(lines)
    want = "(%d characters)" % len(str(pathlib.Path(base) / full))
    if len(st) != 1 or not all(x in st[0] for x in (full, SHORT, want, "refuses every paid run", "long paths", "delete")) or "two state folders" in st[0]:
        res["h1"].append("%s: %s" % (label, st or lines))
    if len(lines) > 8 or not same or not any(l == "state folder: writable" for l in lines):
        res["h1"].append("%s: %d lines, folders untouched %s, lines %s" % (label, len(lines), same, lines))
base, lines, same = case("counter", "counter", SHORT)   # h2: a counter in both folders: today's line, byte for byte, and not the new one
if fails(lines) != [TWO] or any("the paid counter is in" in l for l in lines) or len(lines) > 8 or not same:
    res["h2"].append("%s" % (lines,))
for label, args in (("a counter only in the folder used", (None, "counter", SHORT)), ("no counter at all", (None, None, SHORT)),
                    ("a kept full-key folder, its counter in it, in use", ("counter", None, full)), ("the short folder holds a counter, the full-key one is empty", ("empty", "counter", SHORT))):
    base, lines, same = case(*args)   # h3: no FAIL line
    if fails(lines) or not same or not any(l == "state folder: writable" for l in lines):
        res["h3"].append("%s: %s" % (label, lines))
for k in ("h1", "h2", "h3"):
    print(k, "ok" if not res[k] else "; ".join(res[k])[:600])
PY
r=$(py "$D/cl.py" "$H" "$D" </dev/null 2>&1) || true
l=$(printf '%s\n' "$r" | grep '^h1 ' | head -1); case "$l" in "h1 ok") echo "PASS F2 h1 doctor, a counter only in the full-key folder: its own FAIL line names both folders, the length of the one holding the counter and both ways out; folders untouched, at most 8 lines";; *) echo "FAIL F2 h1 doctor, a counter left behind: ${l:-$r}"; fail=1;; esac
l=$(printf '%s\n' "$r" | grep '^h2 ' | head -1); case "$l" in "h2 ok") echo "PASS F2 h2 doctor, a counter in both folders: today's two-counters line byte for byte, not the new one";; *) echo "FAIL F2 h2 doctor, two counters: ${l:-$r}"; fail=1;; esac
l=$(printf '%s\n' "$r" | grep '^h3 ' | head -1); case "$l" in "h3 ok") echo "PASS F2 h3 doctor, a counter only in the folder used, none at all, a kept full-key folder: no FAIL line";; *) echo "FAIL F2 h3 doctor, a false FAIL: ${l:-$r}"; fail=1;; esac
# D9: a counter in both the full-key and the short-key folder is one FAIL line naming both (Windows: a short key beside a full-key folder that can be made)
if [ "$NT" = 1 ]; then
  if [ $(( 204 - BL2 )) -lt 20 ]; then echo "SKIP D9 doctor, two counters: HOME is $BL2 characters, too long to build a state folder of 205"
  else
    rm -rf "$H2/.claude/smartuse/projects"
    pw=$(lpath $(( 205 - 1 - BL2 ))); fk=$(key "$pw"); pr="$H2/.claude/smartuse/projects"
    sk=$(py -c "import hashlib, sys; k = sys.argv[1]; sys.stdout.write((k[-40:] + '-' + hashlib.sha1(k.encode()).hexdigest()[:12]).lstrip('-'))" "$fk" </dev/null)
    mkdir -p "$pr/$fk" "$pr/$sk"; printf '{}' > "$pr/$fk/paid-runs.json"
    OUT=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" --doctor </dev/null); N=$(printf '%s\n' "$OUT" | wc -l)
    case "$OUT" in *"state folder: FAIL"*"two state folders hold"*"$fk"*"$sk"*) echo "FAIL D9 doctor named two folders with only one counter: $OUT"; fail=1;; *) echo "PASS D9 doctor, a counter in the full-key folder only: no two-counters line";; esac
    printf '{}' > "$pr/$sk/paid-runs.json"
    OUT=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" --doctor </dev/null); N=$(printf '%s\n' "$OUT" | wc -l)
    case "$OUT" in *"state folder: FAIL · two state folders hold a paid counter: $fk and $sk"*"delete"*) [ "$N" -le 8 ] && echo "PASS D9 doctor, a counter in both folders: one FAIL line names both folders and the way out ($N lines)" || { echo "FAIL D9 doctor has $N lines (limit 8): $OUT"; fail=1; };; *) echo "FAIL D9 doctor, a counter in both folders: $(printf '%s' "$OUT" | grep 'state folder')"; fail=1;; esac
    [ "$(ls -A "$pr/$fk" | tr '\n' ' ')" = "paid-runs.json " ] && [ "$(ls -A "$pr/$sk" | tr '\n' ' ')" = "paid-runs.json " ] && echo "PASS D9 doctor left both folders as they were (read-only)" || { echo "FAIL D9 doctor touched the folders: $(ls -A "$pr/$fk" "$pr/$sk" | tr '\n' ' ')"; fail=1; }
    rm -rf "$H2/.claude/smartuse/projects"
  fi
else echo "SKIP D9 doctor, a counter in two state folders: Windows only"; fi
# 0.7.3 F2 h4, the real layout (E1: a full-key folder of 233 to 244 characters is where the counter is still seen, its own path is at most 259; the paid check refuses there, 245 and up it cannot see
# the counter): a full-key folder of 240 characters holding paid-runs.json, long paths off, so fit_key uses the short key. Windows only, LongPathsEnabled = 0 (read at the F3 block above).
if [ "$NT" = 1 ]; then
  if [ "$LPON" = 1 ]; then echo "SKIP F2 h4 doctor, a counter left in a 240-character folder: Windows long paths are on here (LongPathsEnabled = 1), that folder is kept"
  elif [ $(( 239 - BL2 )) -lt 20 ]; then echo "SKIP F2 h4 doctor, a counter left in a 240-character folder: HOME is $BL2 characters, too long to build it"
  else
    rm -rf "$H2/.claude/smartuse/projects"
    pw=$(lpath $(( 239 - BL2 ))); fk=$(key "$pw"); pr="$H2/.claude/smartuse/projects"
    mkdir -p "$pr/$fk"; printf '{}' > "$pr/$fk/paid-runs.json"
    OUT=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" --doctor </dev/null); N=$(printf '%s\n' "$OUT" | wc -l)
    case "$OUT" in *"state folder: FAIL"*"$fk"*"(240 characters)"*"long paths"*"delete"*) [ "$N" -le 8 ] && echo "PASS F2 h4 doctor, a real 240-character full-key folder holding a counter (long paths off): its own FAIL line names the folders, 240 characters and both ways out ($N lines)" || { echo "FAIL F2 h4 doctor has $N lines (limit 8): $OUT"; fail=1; };; *) echo "FAIL F2 h4 doctor, a counter left in a 240-character folder: $(printf '%s' "$OUT" | grep 'state folder')"; fail=1;; esac
    [ "$(ls -A "$pr" | tr '\n' ' ')" = "$fk " ] && [ "$(ls -A "$pr/$fk" | tr '\n' ' ')" = "paid-runs.json " ] && [ "$(cat "$pr/$fk/paid-runs.json")" = "{}" ] && echo "PASS F2 h4 doctor left the folders as they were (no short-key folder made, the counter untouched)" || { echo "FAIL F2 h4 doctor touched the folders: $(ls -A "$pr" "$pr/$fk" | tr '\n' ' ')"; fail=1; }
    rm -rf "$H2/.claude/smartuse/projects"
  fi
else echo "SKIP F2 h4 doctor, a counter left in a 240-character folder: Windows only"; fi

# ===== 0.7.4 F2: doctor sees the same counter the paid check sees. From 245 characters the counter's own path passes 259 and a plain os.path.isfile says "no" with Windows long paths off; doctor said "writable"
# (also after the miss, with a counter in both folders) while the paid check, since F1, refuses. heartbeat.py now has the same two functions as bash-guard.py (long_form, counter_in), looked at as text.
# h5 to h7 are the real Windows layouts (Git Bash mkdir -p and a redirect make the folders, rm -rf takes them away: E1e; `rd` and PowerShell leave a folder that long), Windows with LongPathsEnabled = 0 only
# (LPON, read above): h5 a 250-character full-key folder holding a counter -> the left-behind line, "(250 characters)", the rm -rf words (E1e), at most 8 lines, both folders as they were; h6 a counter in both
# folders at 250 -> the two-counters line; h7 the longest folder that can exist (a 255-character key) holding a counter -> the left-behind line. h8, any OS: the two functions are equal text in heartbeat.py and
# bash-guard.py (so doctor and the refusal cannot drift); m2, a mutation: one character of counter_in changed in a temp copy must make the same comparison BAD.
if [ "$NT" = 1 ]; then
  if [ "$LPON" = 1 ]; then echo "SKIP F2 h5 h6 h7 doctor, a counter in a folder past 244 characters: Windows long paths are on here (LongPathsEnabled = 1), such a folder is kept and plain calls see it"
  elif [ $(( 249 - BL2 )) -lt 20 ]; then echo "SKIP F2 h5 h6 h7 doctor, a counter in a 250-character folder: HOME is $BL2 characters, too long to build it"
  else
    pr="$H2/.claude/smartuse/projects"
    rm -rf "$pr"
    pw=$(lpath $(( 249 - BL2 ))); fk=$(key "$pw")   # h5: the full-key folder is 250 characters, its counter's path 265
    mkdir -p "$pr/$fk"; printf '{}' > "$pr/$fk/paid-runs.json"
    OUT=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" --doctor </dev/null); N=$(printf '%s\n' "$OUT" | wc -l)
    case "$OUT" in *"state folder: FAIL · the paid counter is in $fk (250 characters)"*"turn Windows long paths back on"*"delete ~/.claude/smartuse/projects/$fk with rm -rf in Git Bash (Windows PowerShell 5.1 and rd left a folder that long in place)"*)
        [ "$N" -le 8 ] && echo "PASS F2 h5 doctor, a real 250-character full-key folder holding a counter (long paths off): the left-behind line names (250 characters), both ways out and rm -rf in Git Bash ($N lines)" || { echo "FAIL F2 h5 doctor has $N lines (limit 8): $OUT"; fail=1; };;
      *) echo "FAIL F2 h5 doctor, a counter left in a 250-character folder: $(printf '%s' "$OUT" | grep 'state folder')"; fail=1;; esac
    [ "$(ls -A "$pr" | tr '\n' ' ')" = "$fk " ] && [ "$(ls -A "$pr/$fk" | tr '\n' ' ')" = "paid-runs.json " ] && [ "$(cat "$pr/$fk/paid-runs.json")" = "{}" ] && echo "PASS F2 h5 doctor left the folders as they were (no short-key folder made, the counter untouched)" || { echo "FAIL F2 h5 doctor touched the folders: $(ls -A "$pr" "$pr/$fk" | tr '\n' ' ')"; fail=1; }
    sk=$(py -c "import hashlib, sys; k = sys.argv[1]; sys.stdout.write((k[-40:] + '-' + hashlib.sha1(k.encode()).hexdigest()[:12]).lstrip('-'))" "$fk" </dev/null)   # h6: the same project with a counter in the short-key folder too
    mkdir -p "$pr/$sk"; printf '{}' > "$pr/$sk/paid-runs.json"
    OUT=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" --doctor </dev/null); N=$(printf '%s\n' "$OUT" | wc -l)
    case "$OUT" in *"state folder: FAIL · two state folders hold a paid counter: $fk and $sk: the paid check refuses every paid run until you delete the one that is wrong (its count and receipts go with it)"*)
        case "$OUT" in *"the paid counter is in"*) echo "FAIL F2 h6 doctor printed the left-behind line beside the two-counters line: $OUT"; fail=1;;
          *) [ "$N" -le 8 ] && echo "PASS F2 h6 doctor, a counter in both folders at 250 characters (long paths off): the two-counters line names both folders, not the left-behind one ($N lines)" || { echo "FAIL F2 h6 doctor has $N lines (limit 8): $OUT"; fail=1; };; esac;;
      *) echo "FAIL F2 h6 doctor, a counter in both folders at 250 characters: $(printf '%s' "$OUT" | grep 'state folder')"; fail=1;; esac
    [ "$(ls -A "$pr/$fk" | tr '\n' ' ')" = "paid-runs.json " ] && [ "$(ls -A "$pr/$sk" | tr '\n' ' ')" = "paid-runs.json " ] && echo "PASS F2 h6 doctor left both folders as they were" || { echo "FAIL F2 h6 doctor touched the folders: $(ls -A "$pr/$fk" "$pr/$sk" | tr '\n' ' ')"; fail=1; }
    rm -rf "$pr"
    pw=$(lpath 255); fk=$(key "$pw"); FL=$(( BL2 + 1 + 255 ))   # h7: a 255-character key, the longest name a folder can have
    mkdir -p "$pr/$fk"; printf '{}' > "$pr/$fk/paid-runs.json"
    OUT=$(HOME="$H2" CLAUDE_PROJECT_DIR="$pw" py "$H/heartbeat.py" --doctor </dev/null); N=$(printf '%s\n' "$OUT" | wc -l)
    case "$OUT" in *"state folder: FAIL · the paid counter is in $fk ($FL characters)"*"delete ~/.claude/smartuse/projects/$fk with rm -rf in Git Bash"*)
        [ "${#fk}" = 255 ] && [ "$N" -le 8 ] && echo "PASS F2 h7 doctor, the longest folder that can exist (a 255-character key, $FL characters) holding a counter: the left-behind line ($N lines)" || { echo "FAIL F2 h7 key ${#fk} (wanted 255), $N lines (limit 8): $OUT"; fail=1; };;
      *) echo "FAIL F2 h7 doctor, a counter left in a 255-character-key folder: $(printf '%s' "$OUT" | grep 'state folder')"; fail=1;; esac
    [ "$(ls -A "$pr" | tr '\n' ' ')" = "$fk " ] && [ "$(ls -A "$pr/$fk" | tr '\n' ' ')" = "paid-runs.json " ] && echo "PASS F2 h7 doctor left the folder as it was" || { echo "FAIL F2 h7 doctor touched the folders: $(ls -A "$pr" "$pr/$fk" | tr '\n' ' ')"; fail=1; }
    rm -rf "$pr"
    [ -z "$(ls -A "$pr" 2>/dev/null)" ] && echo "PASS F2 h5 h6 h7 the long folders were removed the way they were made (rm -rf)" || { echo "FAIL F2 h5 h6 h7 left behind: $(ls -A "$pr" 2>&1 | head -c 300 | tr '\n' ' ')"; fail=1; }
  fi
else echo "SKIP F2 h5 h6 h7 doctor, a counter in a folder past 244 characters: Windows only"; fi
# h8, any OS: long_form and counter_in are the same text in the two files (ast: each FunctionDef's source segment, docstring included). A missing function or a difference is BAD and names the file(s).
fncmp() { py - "$1" "$2" <<'PY'
import ast, sys
def segs(path):
    src = open(path, encoding="utf-8").read()
    return {n.name: ast.get_source_segment(src, n) for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name in ("long_form", "counter_in")}
a, b = sys.argv[1], sys.argv[2]
sa, sb = segs(a), segs(b)
na, nb = a.replace("\\", "/").rsplit("/", 1)[-1], b.replace("\\", "/").rsplit("/", 1)[-1]
for f in ("long_form", "counter_in"):
    if f not in sa:
        print("BAD %s has no %s" % (na, f)); sys.exit()
    if f not in sb:
        print("BAD %s has no %s" % (nb, f)); sys.exit()
    if sa[f] != sb[f]:
        d = [(x, y) for x, y in zip(sa[f].splitlines(), sb[f].splitlines()) if x != y]
        x, y = d[0] if d else ("(the line count differs)", "")
        print("BAD %s differs between %s and %s: %s has [%s], %s has [%s]" % (f, na, nb, na, x.strip()[:80], nb, y.strip()[:80])); sys.exit()
print("OK long_form and counter_in are equal text in %s and %s" % (na, nb))
PY
}
CMP=$(fncmp "$H/heartbeat.py" "$H/bash-guard.py")
case "$CMP" in OK*) echo "PASS F2 h8 long_form and counter_in in heartbeat.py are the same text as in bash-guard.py: $CMP";; *) echo "FAIL F2 h8 long_form / counter_in drifted: $CMP"; fail=1;; esac
# m2 (mutation): one character of counter_in changed in a temp copy of heartbeat.py (the file name's last letter) goes through the same comparison and must be BAD, naming counter_in and both files
sed 's/^    p = base + os.sep + name + os.sep + "paid-runs.json"$/    p = base + os.sep + name + os.sep + "paid-runs.jsoN"/' "$H/heartbeat.py" > "$D/hb-mut.py"
if cmp -s "$H/heartbeat.py" "$D/hb-mut.py"; then echo "FAIL F2 m2 the mutation changed nothing (the line it edits moved)"; fail=1
else
  CMPM=$(fncmp "$D/hb-mut.py" "$H/bash-guard.py")
  case "$CMPM" in "BAD counter_in differs between hb-mut.py and bash-guard.py"*) echo "PASS F2 m2 one character of counter_in changed in a copy is BAD: $CMPM";; *) echo "FAIL F2 m2 a one-character change to counter_in: $CMPM"; fail=1;; esac
fi

[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
