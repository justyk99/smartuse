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
thread for at most 3 s: a network share that does not answer must not hold the hook. A path that cannot be resolved (it took
longer, or resolving failed) cannot be checked, so it is denied with its own reason (fail closed).
F5b: an edit of a Claude Code settings file that would change this plugin's options, its on/off entry or disableAllHooks is denied
(switch_change below); the guards' level and rule switches are the owner's, set in /plugin configure or /config.
F7: a write to `~/.claude/smartuse/doctor-canary` (the path ends in `/.claude/smartuse/doctor-canary`, nothing else) is denied first, with a
reason that says the guard is live and the level: /smartuse:doctor has Claude try it to prove this hook answers.
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

# --- 0.6.1 F5b: the guards' switch is the owner's. A Claude Code settings file (settings.json / settings.local.json in a .claude folder, or in
# the folder CLAUDE_CONFIG_DIR names) may not be edited so that one of three values changes: this plugin's pluginConfigs entry (its
# options), its enabledPlugins entry, or disableAllHooks (key names: code.claude.com/docs/en/settings-reference). The plugin is the plugin
# id's name part, `smartuse@<marketplace>`, whatever the marketplace is called. Also compared: every `env` entry whose name starts with
# CLAUDE_PLUGIN_OPTION_ (any case). Other edits of the file pass.
SETTINGS_FILE = re.compile(r"(^|/)\.claude/settings(\.local)?\.json$", re.I)
SETTINGS_NAME = re.compile(r"^settings(\.local)?\.json$", re.I)
SWITCH_NAMES = re.compile(r"pluginConfigs|enabledPlugins|disableAllHooks|CLAUDE_PLUGIN_OPTION_|\\u", re.I)   # \u: a JSON escape can spell a key without the word
OPTION_ENV = "CLAUDE_PLUGIN_OPTION_"   # the `env` block of a settings file sets the variables the guards read as the plugin's options: every such entry is compared too
MAX_SETTINGS = 1 << 20
SWITCH_WHY = "file-guard: this edit would change smartuse's switches. That is the owner's action: /plugin configure or /config."

def norm(f):
    return os.path.normcase(os.path.normpath(f)).replace("\\", "/")

def is_settings_file(f):   # one reading of the path
    n = norm(f)
    if SETTINGS_FILE.search(n):
        return True
    d = os.environ.get("CLAUDE_CONFIG_DIR")
    if d:
        head, _, name = norm(os.path.abspath(f)).rpartition("/")
        if SETTINGS_NAME.match(name):
            try:
                fold = (lambda s: s.lower()) if os.name == "nt" or sys.platform == "darwin" else (lambda s: s)   # Windows and macOS: another case is the same folder
                if fold(head) in (fold(norm(os.path.abspath(d)).rstrip("/")), fold(norm(os.path.realpath(d)).rstrip("/"))):
                    return True
                return same_dir(os.path.dirname(os.path.abspath(f)), d)   # the same folder under another name (a link, a short name)
            except Exception:
                return True   # the folder cannot be compared: a file of that name is treated as the settings file (fail closed)
    return False

def same_dir(a, b, wait=1.0):   # os.path.samefile in a worker thread: False when either folder is missing, the call fails or takes longer than `wait` s
    out = []
    def work():
        try:
            out.append(os.path.isdir(a) and os.path.isdir(b) and os.path.samefile(a, b))
        except Exception:
            out.append(False)
    t = threading.Thread(target=work, daemon=True)
    t.start(); t.join(wait)
    return bool(out and out[0])

def switch_values(text):   # the three values as one comparable string; None when the text does not parse (or is over 1 MB)
    if len(text) > MAX_SETTINGS:
        return None
    try:
        o = json.loads(text.lstrip("﻿") if text.strip() else "{}")
    except Exception:
        return None
    if not isinstance(o, dict):
        return None
    def pick(v):
        if isinstance(v, dict):
            return {k: x for k, x in v.items() if str(k).split("@")[0].strip().lower() == "smartuse"} or None
        return v
    env = o.get("env")
    opts = {k: x for k, x in env.items() if str(k).upper().startswith(OPTION_ENV)} if isinstance(env, dict) else None
    return json.dumps([pick(o.get("pluginConfigs")), pick(o.get("enabledPlugins")), o.get("disableAllHooks") or None, opts or None], sort_keys=True, default=str)

EMPTY = switch_values("{}")

def read_settings(paths):   # the file as it is now: "" when it does not exist, None when it cannot be read or is over 1 MB
    for p in paths:
        try:
            with open(p, "rb") as fh:
                b = fh.read(MAX_SETTINGS + 1)
        except FileNotFoundError:
            continue
        except Exception:
            return None
        return b.decode("utf-8", "replace") if len(b) <= MAX_SETTINGS else None
    return ""

def edited(tool, ti, before):   # the text the tool call would leave in the file; None when that cannot be known
    if tool == "Write":
        c = ti.get("content")
        return c if isinstance(c, str) else None
    edits = [ti] if tool == "Edit" else ti.get("edits") if tool == "MultiEdit" else None
    if before is None or not isinstance(edits, list):
        return None
    text = before
    for e in edits:
        o, n = (e.get("old_string"), e.get("new_string")) if isinstance(e, dict) else (None, None)
        if not isinstance(o, str) or not isinstance(n, str):
            return None
        if o == "":
            if text.strip():
                return None
            text = n
        elif o not in text:
            return None   # not found verbatim: Claude Code's Edit may still match it (it handles typographic quotes its own way), so no result is predicted
        else:
            text = text.replace(o, n) if e.get("replace_all") else text.replace(o, n, 1)
    return text

def switch_change(tool, ti, paths):   # True: the call would change one of the three values (or cannot be shown not to)
    before = read_settings(paths)
    after = edited(tool, ti, before)
    bv = switch_values(before) if before is not None else None
    if after is None:   # the result is unknown
        if bv is not None and bv != EMPTY:   # the file holds a switch value and the call cannot be shown to keep it
            return True
        parts = [ti.get("content")] if tool == "Write" else [x for e in (ti.get("edits") or [ti]) if isinstance(e, dict) for x in (e.get("old_string"), e.get("new_string"))]
        return bool(SWITCH_NAMES.search("\n".join(p for p in parts if isinstance(p, str))))   # a file that holds none: decided by what the call names
    av = switch_values(after)
    if av is not None:
        return av != (EMPTY if bv is None else bv)   # the file as it was is unknown (unreadable or over 1 MB): anything the result holds is a change
    if bv is not None and bv != EMPTY:   # an unparsable result over a file that holds the switches: they would be lost
        return True
    return bool(SWITCH_NAMES.search(after))   # unparsable (or over 1 MB): denied when it names a switch

CANARY_TAIL = "/.claude/smartuse/doctor-canary"   # F7: the doctor's canary file (~/.claude/smartuse/doctor-canary): a write to it is denied with a reason that says the guard is live

def strict_level():   # Strict guards (plugin option): anything but empty / off / false / no / 0 counts as on, so a text that cannot be read is strict
    return str(os.environ.get("CLAUDE_PLUGIN_OPTION_STRICT") or "").strip().lower() not in ("", "off", "false", "no", "0")

def main():   # 0.6.1 F6: under strict an unexpected error denies; in light it is raised as before (a traceback on stderr, nothing on stdout)
    try:
        run()
    except Exception:
        if not strict_level():
            raise
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
              "permissionDecisionReason": "file-guard: internal error; strict guards fail closed. Retry, or ask the user."}}))

def run():
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except Exception:
        return
    if data.get("tool_name") not in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        return
    ti = data.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    path = path.replace("\\", "/")
    if norm(path).endswith(CANARY_TAIL):   # F7: /smartuse:doctor writes here to see that this guard answers; one fixed name, so nothing else is caught
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
              "permissionDecisionReason": "file-guard: doctor canary — the guard is live · level: " + ("strict" if strict_level() else "light")}}))
        return
    deny = human_only(path) or human_only("/".join(win_part(p) for p in path.split("/"))) \
        or (re.search("smartuse", path, re.I) and any(odd_part(p) for p in path.split("/")))   # as written, as Windows reads it, odd parts
    why = "file-guard: this file is human-only (it decides what the until-done gate may execute, or which Python runs the hooks). Ask the user to edit it."
    stuck = False
    r = None
    if not deny and path:   # then as the OS resolves it (links, junctions, 8.3 names of what exists), for at most 3 s
        r = resolved(path)
        stuck = r is None
        if r:
            deny = human_only(r)
        else:   # timed out or failed: the target cannot be checked, so it is not written (fail closed)
            deny, why = True, "file-guard: this path could not be resolved within 3 s, so it cannot be checked against the human-only files. Retry, or ask the user."
    if not deny and path and data.get("tool_name") in ("Write", "Edit", "MultiEdit"):   # F5b: a settings file may not change the guards' switches
        win = "/".join(win_part(p) for p in path.split("/"))
        try:
            hit = any(is_settings_file(c) for c in (path, win, r) if c)
        except Exception:
            hit = "settings" in path.lower()   # fail closed: an error while reading the path is not a pass
        if hit:
            try:
                changed = switch_change(data["tool_name"], ti, [c for c in (path, win, r) if c])
            except Exception:
                changed = True
            if changed:
                deny, why = True, SWITCH_WHY
    if deny:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
              "permissionDecisionReason": why}}))
    if stuck:   # the worker may still be waiting on the network: leave without it
        sys.stdout.flush(); os._exit(0)

main()
