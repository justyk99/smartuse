#!/usr/bin/env bash
# Self-contained test for hooks/heartbeat.py: the state machine event by event, the line's priority order, stall detection,
# the until-done exception on Stop (stop_hook_active ignored, max_blocks honoured), session reset, the three renderers (--line /
# --statusline / --subagent-statusline), the state dir keyed by the full path (never the 0.3.0 folder-name dir), a failed os.replace,
# non-ASCII events under cp1252, garbage input -> silent exit 0. Every hook invocation must print nothing. Exit 1 on failure.
set -e; D=$(mktemp -d); H="$(cd "$(dirname "$0")/.." && pwd)"; export HOME="$D/home"; mkdir -p "$HOME" "$D/proj"
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
  msys*|cygwin*) echo "PASS (skipped on Windows: no symlinks)";;
  *) printf 'junk\n' > "$D/target"; rm -f "$CF"; ln -s "$D/target" "$CF"
     OUT=$(PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1); T5=""; read -r T5 < "$D/target"
     [ "$OUT" = ran ] && [ "$T5" = junk ] && echo "PASS the launcher never writes through a symlinked cache file" || { echo "FAIL symlinked cache: out '$OUT', target '$T5'"; fail=1; };;
esac
# N6: the remembered name is on PATH but that file cannot be run (no exec bit): the old launcher exec'd it and bash exited 2 (126 on Linux), and an exit 2 blocks a PreToolUse hook. Now it is probed instead.
rm -f "$CF"; mkdir -p "$D/nx"; printf 'fi\n' > "$D/nx/python"; chmod -x "$D/nx/python"; printf 'python\n' > "$CF"; RC=0
OUT=$(PATH="$D/nx:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1) || RC=$?
[ "$OUT" = ran ] && [ $RC = 0 ] && echo "PASS a remembered name whose file on PATH is not executable is probed again, rc 0 (was exit 2 / 126)" || { echo "FAIL non-executable hit: out '$OUT', rc $RC"; fail=1; }
# N7: an environment variable named like the remembered word (python=...). On bash >= 4 this passes with or without the fix; on macOS /bin/bash 3.2 (CI) it is the regression check: there BASH_CMDS does not exist and $W was read as arithmetic.
printf 'python\n' > "$CF"; RC=0
OUT=$(python=/usr/bin/python3.11 PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1) || RC=$?
[ "$OUT" = ran ] && [ $RC = 0 ] && echo "PASS an env var named python does not abort the launcher (bash >= 4: passes either way; the bash 3.2 check runs on macOS /bin/bash in CI)" || { echo "FAIL env var named python: out '$OUT', rc $RC"; fail=1; }
# N8: the cache path is a FIFO: reading it is skipped ([ -f ] is false) and the write must not open it (a write to a FIFO with no reader blocks for ever). A watchdog turns a hang into a FAIL.
case "$OSTYPE" in
  msys*|cygwin*) echo "PASS (skipped on Windows: no FIFOs)";;
  *) rm -f "$CF"; mkfifo "$CF"; n=0
     (PATH="$D/stub:$D/real:$PATH" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" > "$D/fifo.out" 2>&1) & W8=$!
     while kill -0 "$W8" 2>/dev/null && [ $n -lt 100 ]; do sleep 0.2; n=$((n + 1)); done   # up to 20 s
     if kill -0 "$W8" 2>/dev/null; then kill "$W8" 2>/dev/null || true; pkill -P "$W8" 2>/dev/null || true; echo "FAIL FIFO cache file: the launcher is still running after 20 s (hung on the FIFO)"; fail=1
     else wait "$W8" 2>/dev/null || true; OUT=$(cat "$D/fifo.out"); [ "$OUT" = ran ] && echo "PASS the launcher never opens a FIFO cache file: it finished and ran" || { echo "FAIL FIFO cache file: out '$OUT'"; fail=1; }; fi
     rm -f "$CF";;
esac
# N9: a Store alias in another spelling of the folder name (WINDOWSAPPS): matched in any case, so it is never exec'd from the cache. (On a case-insensitive disk this is the same folder as WindowsApps; the PATH spelling is what is matched.)
mkdir -p "$D/WINDOWSAPPS"; cp "$D/stub/python3" "$D/WINDOWSAPPS/python3"; chmod +x "$D/WINDOWSAPPS/python3"; rm -f "$CF"; printf 'python3\n' > "$CF"
OUT=$(PATH="$D/WINDOWSAPPS:$D/real" HOME="$D/home5" "$BASH" "$H/py.sh" -c "print('ran')" 2>&1); P5=""; read -r P5 < "$CF"
[ "$OUT" = ran ] && [ "$P5" = python ] && echo "PASS a Store alias under WINDOWSAPPS (upper case) is never exec'd from the cache: probed again, python remembered" || { echo "FAIL WINDOWSAPPS alias: out '$OUT', cached '$P5'"; fail=1; }
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
