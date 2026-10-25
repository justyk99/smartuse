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
named `.. ` is a name, not `..`. A path that names smartuse and has a part of only dots and spaces (other than `.` and `..`)
is denied outright: an OS may read such a part as a name, `.` or `..` (fail closed). The path the OS resolves (`os.path.realpath`:
links, junctions, Windows short 8.3 names like `CLAUDE~1` of what exists) is matched last, when the text forms miss, in a worker
thread for at most 3 s: a network share that does not answer must not hold the hook. When it gives up, a path that may be one of
the files (`smartuse`, `~` or `interp` in it) is denied (fail closed).
"""
import json, os, re, sys, threading
HUMAN_ONLY = re.compile(r"(smartuse\.local\.md|smartuse/trusted-checks\.json|/etc/smartuse(/|$)|\.claude/smartuse/interpreter[. ]*(:.*)?$)", re.I)

def win_part(p):   # one path part as Windows reads it
    return p.split(":")[0].rstrip(". ") or p

def odd_part(p):   # only dots and spaces before any :stream, and not exactly "", "." or ".."
    return p not in ("", ".", "..") and p.split(":")[0].strip(". ") == ""

def human_only(f):   # normpath/normcase give backslashes on Windows
    return HUMAN_ONLY.search(os.path.normcase(os.path.normpath(f)).replace("\\", "/"))

def resolved(path, wait=3.0):   # os.path.realpath in a worker thread: "" when it fails, None when it took longer than `wait` s
    out = []
    def work():
        try:
            out.append(os.path.realpath(path))
        except Exception:
            out.append("")
    t = threading.Thread(target=work, daemon=True)
    t.start(); t.join(wait)
    return out[0] if out else None

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
    deny = human_only(path) or human_only("/".join(win_part(p) for p in path.split("/"))) \
        or (re.search("smartuse", path, re.I) and any(odd_part(p) for p in path.split("/")))   # as written, as Windows reads it, odd parts
    stuck = False
    if not deny and path:   # then as the OS resolves it (links, junctions, 8.3 names of what exists), for at most 3 s
        r = resolved(path)
        stuck = r is None
        deny = human_only(r) if r else (stuck and re.search(r"smartuse|~|interp", path, re.I))   # gave up: fail closed
    if deny:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
              "permissionDecisionReason": "file-guard: this file is human-only (it decides what the until-done gate may execute, or which Python runs the hooks). Ask the user to edit it."}}))
    if stuck:   # the worker may still be waiting on the network: leave without it
        sys.stdout.flush(); os._exit(0)

main()
