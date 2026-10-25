#!/usr/bin/env python3
"""file-guard.py — PreToolUse guard for Write / Edit / MultiEdit / NotebookEdit: three files are human-only.
`.claude/smartuse.local.md` (the adapter: it names the check command the until-done gate will run) and
`/etc/smartuse/trusted-checks.json` (the human's hash pins, root-owned: until-done.py TRUSTED), plus `~/.claude/smartuse/interpreter`
(the launcher's remembered Python name). The model may read them, never write them.
The path is normalised before the match (backslashes, `x/..`, case): APFS and NTFS are case-insensitive, so
`.claude/SmartUse.Local.MD` is the adapter too. stdin is read as bytes and decoded as UTF-8 here: on Windows a piped stdin
is decoded in the ANSI code page, where a non-ASCII path makes json.load raise — and a guard that raises fails OPEN.
Windows drops a trailing dot or space and `x::$DATA` is the file itself, so `interpreter.`, `interpreter ` and `interpreter::$DATA` match too.
"""
import json, os, re, sys
HUMAN_ONLY = re.compile(r"(smartuse\.local\.md|smartuse/trusted-checks\.json|/etc/smartuse(/|$)|\.claude/smartuse/interpreter[. ]*(:.*)?$)", re.I)

def main():
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except Exception:
        return
    if data.get("tool_name") not in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        return
    ti = data.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    path = os.path.normcase(os.path.normpath(path.replace("\\", "/"))).replace("\\", "/")   # normpath/normcase give backslashes on Windows
    if HUMAN_ONLY.search(path):
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
              "permissionDecisionReason": "file-guard: this file is human-only (it decides what the until-done gate may execute, or which Python runs the hooks). Ask the user to edit it."}}))

main()
