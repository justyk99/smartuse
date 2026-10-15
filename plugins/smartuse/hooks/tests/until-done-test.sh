#!/usr/bin/env bash
# Self-contained test for hooks/until-done.py (Stop gate of run-plan --until-done). Exit 1 on failure.
set -e; D=$(mktemp -d); H="$(cd "$(dirname "$0")/.." && pwd)"; export HOME="$D/home"; mkdir -p "$HOME/.claude/smartuse/projects/proj" "$D/proj"
R="$HOME/.claude/smartuse/projects/proj/routing.json"; IN="{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"cwd\":\"$D/proj\",\"stop_hook_active\":false}"
run() { echo "$IN" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/until-done.py"; }
fail=0; expect() { # $1 block|allow, $2 label
  out=$(run); if [ "$1" = block ]; then [ -n "$out" ] && echo "PASS block: $2" || { echo "FAIL expected block: $2"; fail=1; }; else [ -z "$out" ] && echo "PASS allow: $2" || { echo "FAIL expected allow: $2 -> $out"; fail=1; }; fi; }
expect allow "no routing.json"
echo '{"active":true,"until_done":false,"units":[{"id":1,"status":"pending"}]}' > "$R"; expect allow "until_done off"
echo '{"active":true,"until_done":true,"units":[{"id":1,"title":"grep","status":"pending"}]}' > "$R"; expect block "a pending unit"
echo '{"active":true,"until_done":true,"units":[{"id":1,"status":"pass"},{"id":2,"status":"fail"}]}' > "$R"; expect block "a failed unit"
echo '{"active":true,"until_done":true,"units":[{"id":1,"status":"pass"},{"id":2,"status":"blocked"}],"check":"true"}' > "$R"; expect allow "all pass/blocked + check true"
echo '{"active":true,"until_done":true,"units":[{"id":1,"status":"pass"}],"check":"false"}' > "$R"; expect block "check false"
echo '{"active":true,"until_done":true,"units":[{"id":1,"status":"pending"}],"needs_human":"which rounding rule?"}' > "$R"; expect allow "needs_human set"
echo '{"active":true,"until_done":true,"units":[{"id":1,"status":"pending"}],"blocks":6}' > "$R"; expect allow "max_blocks reached"
echo '{"active":true,"until_done":true,"units":[{"id":1,"status":"pending"}]}' > "$R"; expect block "pending again (counts a block)"
python3 -c "import json,sys; r=json.load(open(sys.argv[1])); assert r.get('blocks')==1, r" "$R" 2>/dev/null && echo "PASS block counter persisted" || { echo "FAIL block counter"; fail=1; }
out=$(echo "${IN/false/true}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/until-done.py"); [ -z "$out" ] && echo "PASS allow: stop_hook_active" || { echo "FAIL stop_hook_active"; fail=1; }
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
