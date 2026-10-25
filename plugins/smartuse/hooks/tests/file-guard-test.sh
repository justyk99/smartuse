#!/usr/bin/env bash
H="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
chk() { # $1 = deny|allow, $2 = event JSON, $3 = label, $4 = code page the guard's stdin is decoded in (optional; cp1252 = Windows ANSI)
  out=$(printf '%s' "$2" | env ${4:+PYTHONIOENCODING=$4} bash "$H/py.sh" "$H/file-guard.py"); if [ "$1" = deny ]; then [ -n "$out" ] && echo "PASS deny $3" || { echo "FAIL expected deny $3"; fail=1; }; else [ -z "$out" ] && echo "PASS allow $3" || { echo "FAIL expected allow $3"; fail=1; }; fi; }
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude/smartuse.local.md","content":"x"}}' "Write adapter"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/trusted-checks.json"}}' "Edit pin file"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude/SmartUse.Local.MD","content":"x"}}' "Write adapter in mixed case (APFS and NTFS are case-insensitive)"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/x/../trusted-checks.json"}}' "Edit pin file through x/.."
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"C:\\Users\\u\\.claude\\smartuse\\trusted-checks.json"}}' "Edit pin file with backslashes"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:/Users/李雷/proj/.claude/smartuse.local.md","content":"x"}}' "Write adapter under a non-ASCII path, stdin in cp1252 (Windows ANSI; 0x9D of 李 is undefined there)" cp1252
chk deny  '{"tool_name":"MultiEdit","tool_input":{"file_path":"/etc/smartuse/trusted-checks.json"}}' "MultiEdit the root-owned pin file"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/docs/features/x/DEV.md","content":"x"}}' "Write a doc"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/Docs/SmartUse/Notes.md","content":"x"}}' "Write a doc under a SmartUse/ folder"
chk allow '{"tool_name":"Bash","tool_input":{"command":"cat .claude/smartuse.local.md"}}' "not a write tool"
# --- the launcher's remembered interpreter name (~/.claude/smartuse/interpreter): human-only too, anchored to .claude/smartuse/ and the end
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/interpreter","content":"python"}}' "Write the launcher's interpreter file"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"C:\\Users\\u\\.claude\\smartuse\\Interpreter"}}' "Edit the interpreter file with backslashes and mixed case"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/x/../interpreter"}}' "Edit the interpreter file through x/.."
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/docs/smartuse/interpreter.md","content":"x"}}' "Write a doc named interpreter.md under a smartuse/ folder"
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
