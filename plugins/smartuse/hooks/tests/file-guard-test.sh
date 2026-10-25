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
# Windows maps these spellings to the same file: a trailing dot or space is dropped, and ::$DATA is the file's own data stream
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude\\smartuse\\interpreter::$DATA","content":"python"}}' "Write the interpreter file as interpreter::\$DATA"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/interpreter.","content":"python"}}' "Write the interpreter file with a trailing dot"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/interpreter ","content":"python"}}' "Write the interpreter file with a trailing space"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude.\\smartuse \\interpreter","content":"python"}}' "Write the interpreter file through folder names with a trailing dot or space"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/x/.. /interpreter"}}' "Edit the interpreter file through a '.. ' part (a part of only dots and spaces: fail closed)"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/.. /../interpreter","content":"python"}}' "Write the interpreter file through a POSIX folder named '.. ' (a name there, so the path as written is the file)"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude\\smartuse\\q\\... \\interpreter","content":"python"}}' "Write under smartuse through a part of only dots and spaces ('... ' may be read as a name, . or ..: fail closed)"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/docs/.../notes.md","content":"x"}}' "Write a path with a '...' part that names no smartuse file"
case "$OSTYPE" in   # the path the OS resolves is matched too (links here; Windows short 8.3 names the same way)
  msys*|cygwin*) echo "PASS (skipped on Windows: no symlinks)"; echo "PASS (skipped on Windows: no symlinks; a leading //)";;
  *) T=$(mktemp -d); mkdir -p "$T/h/.claude/smartuse"; : > "$T/h/.claude/smartuse/interpreter"; ln -s "$T/h/.claude/smartuse" "$T/lnk"
     chk deny "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$T/lnk/interpreter\",\"content\":\"python\"}}" "Write the interpreter file through a symlinked folder (the resolved path is matched)"
     chk deny "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/$T/lnk/interpreter\",\"content\":\"python\"}}" "the same with a leading // (a local path on POSIX: resolved too)"; rm -rf "$T";;
esac
# a share that does not answer (192.0.2.7 is a documentation address) must not hold the guard past the hook's 10 s timeout: the text
# forms decide first, and resolving the path gives up after 3 s (then the path cannot be checked: denied with its own reason)
t0=$(date +%s); out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"//192.0.2.7/share/proj/.claude/smartuse.local.md","content":"x"}}' | bash "$H/py.sh" "$H/file-guard.py"); t1=$(date +%s)
[ -n "$out" ] && [ $((t1 - t0)) -lt 10 ] && echo "PASS deny Write the adapter on a network share that does not answer, in $((t1 - t0)) s (the text match decides; no network call)" || { echo "FAIL network share: $((t1 - t0)) s, output '${out:0:40}'"; fail=1; }
t0=$(date +%s); out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"//192.0.2.7/share/proj/notes.md","content":"x"}}' | bash "$H/py.sh" "$H/file-guard.py"); t1=$(date +%s)
case "$out" in ""|*"could not be resolved"*) ok=1;; *) ok=0;; esac   # allowed (resolved, or refused at once) or not checkable; never human-only
[ $ok = 1 ] && [ $((t1 - t0)) -lt 10 ] && echo "PASS an ordinary file on a network share that does not answer is decided in $((t1 - t0)) s: $([ -z "$out" ] && echo allowed || echo 'denied as not checkable')" || { echo "FAIL network share, ordinary file: $((t1 - t0)) s, output '${out:0:60}'"; fail=1; }
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
