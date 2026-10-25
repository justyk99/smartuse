#!/usr/bin/env python3
"""file-guard.py — PreToolUse guard for Write / Edit / MultiEdit / NotebookEdit: three files are human-only.
`.claude/smartuse.local.md` (the adapter: it names the check command the until-done gate will run) and
`/etc/smartuse/trusted-checks.json` (the human's hash pins, root-owned: until-done.py TRUSTED), plus `~/.claude/smartuse/interpreter`
(the launcher's remembered Python name). The model may read them, never write them.
The path is normalised before the match (backslashes, `x/..`, case): APFS and NTFS are case-insensitive, so
`.claude/SmartUse.Local.MD` is the adapter too. stdin is read as bytes and decoded as UTF-8 here: on Windows a piped stdin
is decoded in the ANSI code page, where a non-ASCII path makes json.load raise — and a guard that raises fails OPEN.
Windows drops trailing dots and spaces and reads `x::$DATA` as `x`, so the path is matched twice: as written, and with every part
cut back that way (`.claude./smartuse /interpreter::$DATA` is the launcher file). Either form matching denies: on POSIX a folder
named `.. ` is a name, not `..`. A part of only dots and spaces (other than `.` and `..`) is dropped from the second form: fail closed.
"""
import json, os, re, sys
HUMAN_ONLY = re.compile(r"(smartuse\.local\.md|smartuse/trusted-checks\.json|/etc/smartuse(/|$)|\.claude/smartuse/interpreter[. ]*(:.*)?$)", re.I)

def win_part(p):   # one path part as Windows reads it
    q = p.split(":")[0].rstrip(". ")
    return q or (p.strip(" ") if p.strip(" ") in (".", "..") else "")

def main():
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except Exception:
        return
    if data.get("tool_name") not in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        return
    ti = data.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    path = path.replace("\\", "/")
    forms = (path, "/".join(win_part(p) for p in path.split("/")))   # as written, and as Windows reads it
    if any(HUMAN_ONLY.search(os.path.normcase(os.path.normpath(f)).replace("\\", "/")) for f in forms):   # normpath/normcase give backslashes on Windows
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
              "permissionDecisionReason": "file-guard: this file is human-only (it decides what the until-done gate may execute, or which Python runs the hooks). Ask the user to edit it."}}))

main()
