#!/usr/bin/env bash
H="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
chk() { out=$(printf '%s' "$2" | python3 "$H/file-guard.py"); if [ "$1" = deny ]; then [ -n "$out" ] && echo "PASS deny $3" || { echo "FAIL expected deny $3"; fail=1; }; else [ -z "$out" ] && echo "PASS allow $3" || { echo "FAIL expected allow $3"; fail=1; }; fi; }
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude/smartuse.local.md","content":"x"}}' "Write adapter"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/trusted-checks.json"}}' "Edit pin file"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/docs/features/x/DEV.md","content":"x"}}' "Write a doc"
chk allow '{"tool_name":"Bash","tool_input":{"command":"cat .claude/smartuse.local.md"}}' "not a write tool"
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
