#!/usr/bin/env bash
# Self-contained test for the paid-call guard in hooks/bash-guard.py (relay-design rule 4): a call to a per-call billed API is denied
# until the owner gave a go, and the adapter's `paid:` line is the go. This suite is the stateful half (the text-only cases are in
# run.sh, read from paid-cases.txt). Every fixture is SYNTHETIC: generic scripts (render.py, polish.py) in a temp project, made-up ids,
# no real key, path or name. The fixtures that must name a paid SDK or key are written through printf with the name as a separate
# argument, so no line of this file spells one: a script that names one is itself a paid call to the guard, and this file must stay
# runnable through it.
# Covered: the INCIDENT REPLAY (the batch command, the Gemini key in the script, no go anywhere -> DENIED at the first call, the reason
# starts "bash-guard: paid call", names the signal and the exact lines to type, nothing is written) · the deny JSON shape and the
# silent allow · the adapter go (the same call passes; paid-runs.json holds one entry: used 1, go_from adapter, runs, cap) · the state
# dir equal to ledger.py's · one claim marker per tool_use_id (the same id twice counts once, a new id counts again) · a call without
# an id · the go's grammar (x, ×, *, the list form, a path, any case; runs 0 and a bare script are no go) · a go for another script
# does not cover this one · a changed line is a new counter · paid_scripts (a helper script) · a script with a go is paid · paid_hosts ·
# a verification error after a positive detection DENIES (adapter unreadable, counter corrupt, state dir not creatable) while the
# counter file is never reset · the cwd in the Git Bash form · no .env is read · the RUN CAP (F2): run 1 must make ONE output (every
# count-flag form, the go's own `count <flag>`, `count none`), run 2 waits for `test ok` on the adapter line, `test ok` keeps the
# counter, the run after the cap is denied, a changed line resets, two scripts two counters, a corrupt counter is never reset, an
# unwritable one denies, the counter lock (held -> deny, stale -> taken over, three parallel calls on a cap of 2), INCIDENT REPLAY 2
# and the whole sequence with paid-runs.json read after each step · HARDENING: every paid script in one command needs its go (&&, ;, |,
# newline, bash -c "a; b"; none is counted when one is denied) · wrappers (timeout, nice, ionice, stdbuf, xargs, poetry / pipenv run, pnpm
# exec / dlx, yarn node, npm exec, caffeinate, env, nohup, time) do not hide the script · run 1's count rule needs plain literal arguments
# ($VAR, `cmd`, $(cmd), <(cmd), @file, globs are denied) · a loop / xargs / parallel / watch / the same script twice is denied whatever the
# counter says · bash-guard.py: stdlib only, no subprocess / network,
# Python 3.9 grammar, import-free of the other hooks, exec-able the way until-done.py does · hooks.json: still one Bash PreToolUse
# command. One temp dir under ${TMPDIR:-/tmp}/smartuse-paid-guard.XXXXXX, the only thing removed on exit; temp HOME. Every PASS / FAIL
# line is one check; exit 1 on failure.
set -u
export CLAUDE_PLUGIN_OPTION_STRICT=true   # strict is the bar of the cases below (paid is always on there); the arming and level block (section 19) sets the level itself
unset CLAUDE_PLUGIN_OPTION_RULES_OFF
H="$(cd "$(dirname "$0")/.." && pwd)"; G="$H/bash-guard.py"
D=$(mktemp -d "${TMPDIR:-/tmp}/smartuse-paid-guard.XXXXXX") && [ -d "$D" ] || { echo "FAIL could not create a temp dir under ${TMPDIR:-/tmp}"; exit 1; }
trap 'case "$D" in */smartuse-paid-guard.*) rm -rf "$D" 2>/dev/null;; esac' EXIT   # removes this run's own dir and nothing else
unset CLAUDE_PROJECT_DIR
REAL_HOME="${HOME:-}"; export HOME="$D/home"; mkdir -p "$HOME/.claude/smartuse" "$D/proj"   # ~/.claude/smartuse exists, so py.sh remembers the interpreter: one start per call
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it (cygpath -m -> C:/Users/...); elsewhere unchanged
key() { py -c "import re,sys,pathlib; print(re.sub(r'[^A-Za-z0-9._-]','-',str(pathlib.Path(sys.argv[1]).resolve())).lstrip('-'))" "$1"; }   # the hooks' state-dir rule: the full resolved path, every character outside [A-Za-z0-9._-] -> "-", no leading "-"
jstr() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; printf '%s' "$s"; }   # a JSON string body
fail=0; n=0
ok() { n=$((n+1)); echo "PASS $1"; }
ko() { n=$((n+1)); echo "FAIL $1"; fail=1; }
skip() { n=$((n+1)); echo "SKIP $1"; }   # a case that did not run on this machine: never a PASS, never sets fail
[ "$(py -c 'print("ok")' </dev/null 2>/dev/null)" = ok ] || { echo "FAIL no python 3 (python3, python or py -3) through $H/py.sh"; exit 1; }
PW=$(wp "$D/proj"); K=$(key "$PW"); P="$HOME/.claude/smartuse/projects/$K"; R="$P/paid-runs.json"   # the state dir of the project every case runs in
cat > "$D/chk.py" <<'PY'
import ast, json, sys
mode = sys.argv[1]
if mode == "entry":      # entry FILE FIELD: the field of the first entry, as JSON
    d = json.load(open(sys.argv[2], encoding="utf-8")); print(json.dumps(d[sorted(d)[0]].get(sys.argv[3])))
elif mode == "count":    # count FILE: how many go counters
    print(len(json.load(open(sys.argv[2], encoding="utf-8"))))
elif mode == "age":      # age FILE SECONDS: set the file's mtime that many seconds into the past
    import os, time
    t = time.time() - float(sys.argv[3]); os.utime(sys.argv[2], (t, t))
elif mode == "shape":    # shape OUT: the deny JSON is the shape the other guards print, on one ASCII line
    s = sys.argv[2]; d = json.loads(s); h = d["hookSpecificOutput"]
    assert sorted(d) == ["hookSpecificOutput"] and sorted(h) == ["hookEventName", "permissionDecision", "permissionDecisionReason"], d
    assert h["hookEventName"] == "PreToolUse" and h["permissionDecision"] == "deny" and h["permissionDecisionReason"].startswith("bash-guard: paid call ("), h
    assert "\n" not in s and all(ord(c) < 128 for c in s), s
    print("ok")
elif mode == "hooks":    # hooks hooks.json: exactly one shell-tool (Bash|PowerShell|Monitor) PreToolUse command, bash-guard, timeout 10
    d = json.load(open(sys.argv[2], encoding="utf-8"))
    hs = [h for e in d["hooks"]["PreToolUse"] if e.get("matcher") == "Bash|PowerShell|Monitor" for h in e["hooks"]]
    assert len(hs) == 1 and hs[0]["command"].endswith('bash-guard.py"') and hs[0]["timeout"] == 10, hs
    print("ok")
elif mode == "imports":  # imports bash-guard.py: stdlib only, no subprocess / network, no other hook, parses as Python 3.9
    t = ast.parse(open(sys.argv[2], encoding="utf-8").read(), feature_version=(3, 9))
    names = set()
    for x in ast.walk(t):
        if isinstance(x, ast.Import):
            names |= {a.name.split(".")[0] for a in x.names}
        elif isinstance(x, ast.ImportFrom):
            names.add((x.module or "").split(".")[0])
    top = set()   # the module-level imports are the 0.6.1 list, no new one; hashlib and pathlib are imported inside the paid path only (V9)
    for x in t.body:
        if isinstance(x, ast.Import):
            top |= {a.name.split(".")[0] for a in x.names}
        elif isinstance(x, ast.ImportFrom):
            top.add((x.module or "").split(".")[0])
    assert top == {"base64", "datetime", "fnmatch", "json", "os", "posixpath", "re", "stat", "sys", "threading", "time"}, top
    assert names <= top | {"hashlib", "pathlib", "winreg"} and {"hashlib", "pathlib"} <= names, names   # winreg: 0.7.1 D8, imported inside fit_key only
    print("ok")
elif mode == "rules":    # rules bash-guard.py: until-done.py's way of reusing RULES (exec the source without its main() call)
    import io, contextlib
    src = open(sys.argv[2], encoding="utf-8").read(); ns = {}; buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        exec(compile(src.replace("\nmain()\n", "\n"), "bash-guard", "exec"), ns)
    assert not buf.getvalue() and isinstance(ns.get("RULES"), list) and len(ns["RULES"]) == len(ns["RULE_NAMES"]) and "paid" in ns["GATE_NAMES"] and "paid" not in ns["RULE_NAMES"] and callable(ns.get("paid_verdict")), (buf.getvalue(), len(ns.get("RULES") or []))
    print("ok")
elif mode == "inproc":   # inproc GUARD PROJECT KIND: main() run in this process with one piece changed: deterr (the detection raises), deadline (the hook's deadline is already past), lock (a 0.3 s deadline)
    import contextlib, io, os, time, types
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "inproc"}
    exec(compile(src, "bash-guard", "exec"), ns)
    proj, kind = sys.argv[3], sys.argv[4]
    def boom(*a, **k):
        raise RuntimeError("forced detection error")
    def run(level, cmd="python render.py --n 1"):
        for k in ("CLAUDE_PLUGIN_OPTION_STRICT", "CLAUDE_PLUGIN_OPTION_RULES_OFF"):
            os.environ.pop(k, None)
        if level == "strict":
            os.environ["CLAUDE_PLUGIN_OPTION_STRICT"] = "true"
        ev = {"session_id": "s", "transcript_path": proj + "/none.jsonl", "cwd": proj, "tool_name": "Bash", "tool_use_id": "toolu_ip", "tool_input": {"command": cmd}}
        sys.stdin = types.SimpleNamespace(buffer=io.BytesIO(json.dumps(ev).encode()))
        out, t0, raised = io.StringIO(), time.monotonic(), ""
        try:
            with contextlib.redirect_stdout(out):
                ns["main"]()
        except Exception as e:
            raised = "raised " + type(e).__name__
        dt = time.monotonic() - t0
        r = json.loads(out.getvalue())["hookSpecificOutput"]["permissionDecisionReason"] if out.getvalue() else ""
        print("%s %.2f %s" % (level, dt, ("deny " + r) if r else (raised or "allow")))
    if kind == "deterr":
        ns["paid_hit"] = boom
        run("light"); run("strict")
    elif kind == "deadline":
        ns["BUDGET_S"] = -1.0
        run("strict")
    elif kind == "lock":
        ns["BUDGET_S"] = 0.3
        run("strict")
    elif kind == "race":     # 0.7.2 D14: a counter lands in the short-key folder AFTER the early two-counters check (the stub plants it and says "no"): the check under the lock must see it
        def late(project):
            base = str(ns["paid_home"]() / ".claude" / "smartuse" / "projects")
            full = __import__("re").sub(r"[^A-Za-z0-9._-]", "-", str(__import__("pathlib").Path(project).resolve())).lstrip("-")
            short = ns["fit_key"](full, "?" * len(base), os.name == "nt")
            os.makedirs(os.path.join(base, short), exist_ok=True)
            open(os.path.join(base, short, "paid-runs.json"), "w").write("{}")
            return False
        ns["paid_two_counters"] = late
        run("strict", "python render.py --images 1")
    elif kind == "unread":   # 0.7.0 review fix m7: the script exists but its read fails (the mock stands for a file that cannot be opened)
        ns["paid_read_file"] = lambda p: None
        run("strict", "python polish.py"); run("light", "python polish.py")
elif mode == "twolock":  # twolock GUARD HOME: 0.7.2 D14, paid_count called directly. The state folder used is the short-key one (a 240-character path), its full-key sibling "holds a counter" (os.path.isfile stands in: no 240-character name can be made on every OS)
    import os, pathlib, re
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "twolock"}
    exec(compile(src, "bash-guard", "exec"), ns)
    home = sys.argv[3]; os.environ["HOME"] = home
    proj = os.path.join(home, "a" * 80, "b" * 80, "c" * 80)
    full = re.sub(r"[^A-Za-z0-9._-]", "-", str(pathlib.Path(proj).resolve())).lstrip("-")
    sdir = ns["paid_state_dir"](proj)
    assert sdir.name != full, (sdir.name, full)
    go = {"script": "render.py", "runs": 3, "cap": "RM1", "count": "none", "test_ok": True, "go_from": "adapter"}
    items = [("go1", go, "render.py", 0)]
    target = os.path.normpath(os.path.join(str(sdir.parent), full, "paid-runs.json"))
    real = os.path.isfile
    os.path.isfile = lambda p: True if os.path.normpath(str(p)) == target else real(p)
    try:
        r1 = ns["paid_count"]({"tool_use_id": "toolu_x"}, sdir, items, "python render.py", None, proj)
    finally:
        os.path.isfile = real
    left = sorted(x.name for x in sdir.iterdir()) if sdir.is_dir() else None
    r2 = ns["paid_count"]({"tool_use_id": "toolu_y"}, sdir, items, "python render.py", None, proj)
    ok = r1 == (True, ns.get("PAID_LEFT"), 0) and left == [] and r2 is None and (sdir / "paid-runs.json").is_file()   # 0.7.4 F3 r5: the folder in use holds no counter, the other one does: one counter left behind
    seen = sorted(x.name for x in sdir.iterdir())
    os.path.isfile = lambda p: True if os.path.normpath(str(p)) == target else real(p)
    try:
        r3 = ns["paid_count"]({"tool_use_id": "toolu_z"}, sdir, items, "python render.py", None, proj)   # the folder in use holds a counter now (r2 made it): a counter in each folder
    finally:
        os.path.isfile = real
    ok = ok and r3 == (True, ns["PAID_TWO"], 0) and sorted(x.name for x in sdir.iterdir()) == seen
    print("ok" if ok else "r1=%r left=%r r2=%r r3=%r" % (r1, left, r2, r3))
elif mode == "paidwhy":  # paidwhy GUARD: 0.7.4 F3 r1, paid_why picks "too long" by the error the system gave (Windows, a path past 259, FileNotFoundError), not by the length alone; any OS, in process
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "paidwhy"}
    exec(compile(src, "bash-guard", "exec"), ns)
    pw, LONG, NW = ns["paid_why"], ns["PAID_LONG"], "the counter is not writable"
    BS = chr(92)
    p300 = "C:" + BS + ("d" * 99 + BS) * 2 + "f" * 97                      # 300 characters
    p200 = "C:" + BS + "d" * 99 + BS + "f" * 97                              # 200 characters
    p250 = "C:" + BS + "d" * 99 + BS + "e" * 99 + BS + "f" * 47              # 250 characters
    assert (len(p300), len(p200), len(p250)) == (300, 200, 250), (len(p300), len(p200), len(p250))
    PE, FE, EE = PermissionError(13, "x"), FileNotFoundError(2, "x"), OSError(22, "x")
    rows = [   # (what, call, wanted)
        ("300 chars, nt, PermissionError", lambda: pw(p300, 0, PE, True), NW),
        ("300 chars, nt, FileNotFoundError", lambda: pw(p300, 0, FE, True), LONG),
        ("300 chars, nt, another OSError", lambda: pw(p300, 0, EE, True), NW),
        ("200 chars, nt, FileNotFoundError: never too long", lambda: pw(p200, 0, FE, True), NW),
        ("200 chars, nt, PermissionError", lambda: pw(p200, 0, PE, True), NW),
        ("300 chars, not nt, FileNotFoundError: never", lambda: pw(p300, 0, FE, False), NW),
        ("300 chars, not nt, PermissionError", lambda: pw(p300, 0, PE, False), NW),
        ("250 chars + 20 (the temporary name), nt, FileNotFoundError", lambda: pw(p250, 20, FE, True), LONG),
        ("250 chars + 5, nt, FileNotFoundError", lambda: pw(p250, 5, FE, True), NW),
        ("250 chars + 20, nt, PermissionError", lambda: pw(p250, 20, PE, True), NW),
        ("no error object, 300 chars, nt: today's length rule", lambda: pw(p300, 0, None, True), LONG),
        ("no error object, 200 chars, nt", lambda: pw(p200, 0, None, True), NW),
        ("no error object, 300 chars, not nt", lambda: pw(p300, 0, None, False), NW),
        ("a path object, nt, FileNotFoundError", lambda: pw(__import__("pathlib").PurePath(p300), 0, FE, True), LONG),
    ]
    bad = []
    for what, call, want in rows:
        try:
            got = call()
        except Exception as e:
            got = "raised " + type(e).__name__ + ": " + str(e)
        if got != want:
            bad.append("%s: wanted %r got %r" % (what, want[:30], str(got)[:40]))
    # the write helper hands its last error back through an optional list and never raises
    import tempfile, pathlib, shutil
    wj = ns["paid_write_json"]; td = pathlib.Path(tempfile.mkdtemp()); errs = []
    try:
        if wj(td / "no-such-folder" / "paid-runs.json", {"yk": 1}, errs) is not False or len(errs) != 1 or not isinstance(errs[0], OSError):
            bad.append("paid_write_json into a missing folder: errs=%r" % (errs,))
        if wj(td / "paid-runs.json", {"yk": 1}) is not True or wj(td / "paid-runs.json", {"yk": 2}, []) is not True:
            bad.append("paid_write_json without the list, or with an empty one, did not write")
        if wj(td / "no-such-folder" / "x.json", {"yk": 1}) is not False or wj(td / "no-such-folder" / "x.json", {"yk": 1}, None) is not False:
            bad.append("paid_write_json without a list did not return False")
    except Exception as e:
        bad.append("paid_write_json raised %s: %s" % (type(e).__name__, e))
    finally:
        shutil.rmtree(td, ignore_errors=True)   # the suite removes only what it made: this folder is outside $D
    print("ok" if not bad else "; ".join(bad))
elif mode == "longform":   # longform GUARD: 0.7.4 F1 (39h), long_form is pure text and answers the same on every OS. The table is written with | for a backslash.
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "longform"}
    exec(compile(src, "bash-guard", "exec"), ns)
    lf = ns.get("long_form")
    if lf is None:
        print("long_form is not defined"); sys.exit(0)
    B = lambda s: s.replace("|", chr(92))
    deep = "C:|" + ("d" * 99 + "|") * 2 + "d" * 99          # a 302-character path, every name 99 characters
    assert len(deep) >= 300, len(deep)
    rows = [   # (path, nt, wanted)
        ("C:|a|b", True, "||?|C:|a|b"),                      # a drive path
        ("c:|a|b", True, "||?|c:|a|b"),                      # a lower-case drive
        ("C:/a/b", True, "||?|C:|a|b"),                      # forward slashes count as backslashes
        ("C:|a/b|c", True, "||?|C:|a|b|c"),                  # mixed
        ("||srv|sh|a", True, "||?|UNC|srv|sh|a"),            # a share path
        ("//srv/sh/a", True, "||?|UNC|srv|sh|a"),            # a share path, forward slashes
        ("||?|C:|a|b", True, "||?|C:|a|b"),                  # already long: as it is
        ("||?|UNC|srv|sh|a", True, "||?|UNC|srv|sh|a"),      # already long, a share: as it is
        (deep, True, "||?|" + deep),                         # 302 characters
        ("C:|a|b", False, ""),                               # not Windows: never
        ("||.|C:|a", True, ""),                              # a device path
        ("||srv|sh", True, ""),                              # a share with no name after it
        ("||srv", True, ""),                                 # a server only
        ("a|b|c", True, ""),                                 # relative
        ("C:a|b", True, ""),                                 # drive-relative
        ("C:|a|..|b", True, ""),                             # a .. part
        ("C:|a|.|b", True, ""),                              # a . part
        ("C:|a||b", True, ""),                               # an empty part
        ("C:|a|b|", True, ""),                               # a trailing separator
        ("||srv|sh||a", True, ""),                           # a share path with an empty part
        ("|a|b", True, ""),                                  # rooted, no drive
        ("\u00e9:|a", True, ""),                             # a drive letter must be ASCII
        ("C:", True, ""), ("C:|", True, ""), ("", True, ""),
    ]
    bad = []
    for p, nt, want in rows:
        try:
            got = lf(B(p), nt)
        except Exception as e:
            got = "raised " + type(e).__name__
        if got != B(want):
            bad.append("%r nt=%s wanted %r got %r" % (B(p)[:40], nt, B(want)[:40], got[:40]))
    for odd in (None, 5, b"C:|a"):                           # never raises, whatever it is given
        try:
            if lf(odd, True) != "":
                bad.append("%r did not give an empty text" % (odd,))
        except Exception as e:
            bad.append("%r raised %s" % (odd, type(e).__name__))
    print("ok" if not bad else "; ".join(bad))
elif mode == "counterin":  # counterin GUARD: 0.7.4 F1 (39h), counter_in with os.path.isfile stood in (no long path can be made on every OS): the plain look first, then the long form
    import os
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "counterin"}
    exec(compile(src, "bash-guard", "exec"), ns)
    ci = ns.get("counter_in")
    if ci is None:
        print("counter_in is not defined"); sys.exit(0)
    BS = chr(92); EXT = BS * 2 + "?" + BS
    base = "C:" + BS + "h" + BS + ".claude" + BS + "smartuse" + BS + "projects"   # a Windows spelling, on any OS
    plain = base + os.sep + "k1" + os.sep + "paid-runs.json"
    longp = EXT + "C:" + BS + "h" + BS + ".claude" + BS + "smartuse" + BS + "projects" + BS + "k1" + BS + "paid-runs.json"
    def look(true_for, nt, b=base):
        calls = []
        def stub(p):
            calls.append(p)
            return p in true_for
        real = os.path.isfile; os.path.isfile = stub
        try:
            r = ci(b, "k1", nt)
        finally:
            os.path.isfile = real
        return r, calls
    bad = []
    cases = [
        ("plain true (the long form is not tried)", look({plain}, True), (True, [plain])),
        ("plain true, nt false", look({plain}, False), (True, [plain])),
        ("plain false, long form true", look({longp}, True), (True, [plain, longp])),
        ("both false", look(set(), True), (False, [plain, longp])),
        ("nt false never tries the long form", look({longp}, False), (False, [plain])),
        ("a relative base gets the plain look only", look({longp}, True, "rel" + os.sep + "dir"), (False, ["rel" + os.sep + "dir" + os.sep + "k1" + os.sep + "paid-runs.json"])),
    ]
    for name, got, want in cases:
        if got != want or type(got[0]) is not bool:
            bad.append("%s: got %r wanted %r" % (name, got, want))
    print("ok" if not bad else "; ".join(bad))
elif mode == "nocall":   # nocall GUARD HOME: 0.7.4 F1 (39i), a project whose key fits never reaches counter_in (counted calls), in the early check and under the lock; a long one does (the control)
    import os
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "nocall"}
    exec(compile(src, "bash-guard", "exec"), ns)
    home = sys.argv[3]; os.environ["HOME"] = home
    calls = []
    def stub(*a):
        calls.append(a)
        return False
    ns["counter_in"] = stub
    go = {"script": "render.py", "runs": 3, "cap": "RM1", "count": "none", "test_ok": True, "go_from": "adapter"}
    items = [("go1", go, "render.py", 0)]
    short_p = os.path.join(home, "fits")
    s_early = ns["paid_two_counters"](short_p)
    s_lock = ns["paid_count"]({"tool_use_id": "toolu_n1"}, ns["paid_state_dir"](short_p), items, "python render.py", None, short_p)
    n_short = len(calls)
    long_p = os.path.join(home, "a" * 80, "b" * 80, "c" * 80)
    l_early = ns["paid_two_counters"](long_p)
    n_early = len(calls) - n_short
    l_lock = ns["paid_count"]({"tool_use_id": "toolu_n2"}, ns["paid_state_dir"](long_p), items, "python render.py", None, long_p)
    n_lock = len(calls) - n_short - n_early
    ok = s_early is False and s_lock is None and n_short == 0 and l_early is False and l_lock is None and n_early >= 1 and n_lock >= 1
    print("ok" if ok else "fits: early=%r lock=%r calls=%d; long: early=%r (%d calls) lock=%r (%d calls)" % (s_early, s_lock, n_short, l_early, n_early, l_lock, n_lock))
elif mode == "ptime":    # ptime GUARD PROJECT: the paid path inside the process, no process start in the times
    import os, time
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "ptime"}
    exec(compile(src, "bash-guard", "exec"), ns)
    proj, bad = sys.argv[3], []
    ev = {"cwd": proj, "tool_use_id": "toolu_t"}
    def verdict(c):
        return ns["paid_verdict"](ev, c, c, True, None)
    for c in ("ls -la", "git status --short", "echo hello world", "cat README.md"):
        t0 = time.monotonic()
        for _ in range(200):
            verdict(c)
        ms = (time.monotonic() - t0) / 200 * 1000
        if ms >= 5 or verdict(c) is not None:
            bad.append("ordinary %r: %.2f ms" % (c, ms))
    open(os.path.join(proj, "warm.py"), "w").write("print(1)\n")
    verdict("python warm.py")   # the patterns compile on first use: the times below are the steady state inside one process
    open(os.path.join(proj, "big.py"), "w").write("# lorem ipsum dolor sit amet\n" * 9600)   # 268,800 bytes, no signal
    t0 = time.monotonic(); r = verdict("python big.py"); ms = (time.monotonic() - t0) * 1000
    if r is not None or ms >= 50:
        bad.append("256 KB script, no signal: %r %.1f ms" % (r, ms))
    shapes = {   # one 30 KB text per pattern family; each is run alone through the whole paid path and through its own function
        "host names on a long dotted run": "curl " + "a." * 14000 + "b",
        "key names": "python x.py " + "OPENAI_API_KE " * 2100,
        "SDK imports": "python3 -c \"" + "from google import " * 1600 + "\"",
        "the segment splitter": "python x.py " + "a;|&" * 7000,
        "the count-flag reader": "python render.py " + "--n " * 7000,
    }
    for nm, c in shapes.items():
        assert len(c) < 32768, nm
        t0 = time.monotonic(); verdict(c); dt = time.monotonic() - t0
        if dt >= 1.0:
            bad.append("%s: %.2f s" % (nm, dt))
    t0 = time.monotonic(); ns["paid_code_signal"](shapes["host names on a long dotted run"], ns["PAID_HOST"], True); dt = time.monotonic() - t0
    if dt >= 1.0:
        bad.append("host regex alone: %.2f s" % dt)
    t0 = time.monotonic(); ns["paid_count_flags"](["--n", "1"] * 14000); dt = time.monotonic() - t0
    if dt >= 1.0:
        bad.append("count flags alone: %.2f s" % dt)
    print("ok" if not bad else "; ".join(bad))
elif mode == "hostre":   # hostre GUARD: the linear host finder gives the same matches (text and place) as the pattern it replaced, on short texts
    import re
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "hostre"}
    exec(compile(src, "bash-guard", "exec"), ns)
    hs = ns["PAID_HOSTS"] + ("extra.example-images.test",)
    old = re.compile(r"(?<![\w-])(?:[\w-]+\.)*(?:" + "|".join(re.escape(h) for h in hs) + r")(?![\w-]|\.\w)", re.I)
    new = ns["paid_host_re"](hs)
    a, b, x = hs[0], hs[3], hs[-1]
    samples = ["see " + a, "x." + a, "eu.x." + b + " and " + a, "not" + b, b + ".runtime.io", "https://" + a + "/v1", "-a." + hs[1], ".." + a, "." + a,
               "a..x." + a, a + ".", a + ":443", a + ".evil", a + "-x", "a." * 40 + b, "A." + a.upper(), "q-r_s." + x + "," + x, a + " " + b + " " + x,
               "café." + a, "x." + a + "." + b, b + b, "." * 5 + b, ""]
    bad = [s[:30] for s in samples if [(m.start(), m.group(0)) for m in old.finditer(s)] != [(m.start(), m.group(0)) for m in new.finditer(s)]]
    print("ok" if not bad and sum(len(list(old.finditer(s))) for s in samples) >= 15 else "differs on %s" % bad)
elif mode == "ftime":    # ftime GUARD PROJECT: the F4b readers inside the process, each text under 32 KB and decided in under 1 s with the verdict the cases show
    import os, time
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "ftime"}
    exec(compile(src, "bash-guard", "exec"), ns)
    proj, bad = sys.argv[3], []
    os.makedirs(os.path.join(proj, ".claude"), exist_ok=True); os.makedirs(os.path.join(proj, "tools"), exist_ok=True)
    open(os.path.join(proj, "tools", "entry.py"), "w").write("print(1)\n")
    open(os.path.join(proj, "render.py"), "w").write("import " + "open" + "ai\n")   # a paid script, the SDK name never spelled whole here
    ev = {"cwd": proj, "tool_use_id": "toolu_ft"}
    def verdict(c, adapter):
        open(os.path.join(proj, ".claude", "smartuse.local.md"), "w").write(adapter)
        return ns["paid_verdict"](ev, c, c, True, None)
    def check(name, c, adapter, want_none):
        assert len(c) < 32768, name
        t0 = time.monotonic(); r = verdict(c, adapter); dt = time.monotonic() - t0
        if dt >= 1.0:
            bad.append("%s: %.2f s" % (name, dt))
        if (r is None) != want_none:
            bad.append("%s: verdict %r" % (name, r and r[:60]))
    items = (["tools/entry.py only --pay"] + ["n%d.py only --a%d" % (i, i) for i in range(700)] + ["d%d/p%d.py only --b%d" % (i, i, i) for i in range(700)]
             + ["g%d/*_%d.py only --c%d" % (i, i, i) for i in range(600)])
    ad = "paid_scripts: " + ", ".join(items) + "\n"
    check("2,000 paid_scripts items, 30 KB of arguments, no pay flag", "python tools/entry.py " + "--zz " * 5000, ad, True)
    check("2,000 paid_scripts items, 30 KB of arguments, the pay flag last", "python tools/entry.py " + "--zz " * 5000 + "--pay", ad, False)
    fr = "paid_free: " + ", ".join("--ff%d" % i for i in range(1000)) + ", --dry-run\n"
    check("1,000 free flags, 30 KB of free words", "python render.py " + "--dry-run " * 3000, fr, True)
    check("1,000 free flags, 30 KB of words that are not", "python render.py " + "--ff " * 6000, fr, False)
    check("1,200 distinct script runs against the 2,000 items", ";".join("python tools/e%d.py" % i for i in range(1200)), ad, True)
    print("ok" if not bad else "; ".join(bad))
elif mode == "pstime":   # pstime GUARD PROJECT: F6, PowerShell texts through the paid path in this process (ps_text first, then paid_verdict with ps=True, as the hook does), each under 32 KB and decided in under 1 s
    import os, time
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "pstime"}
    exec(compile(src, "bash-guard", "exec"), ns)
    proj, bad = sys.argv[3], []
    open(os.path.join(proj, "render.py"), "w").write("import " + "open" + "ai\n")   # a paid script, the SDK name never spelled whole here
    open(os.path.join(proj, "warm.py"), "w").write("print(1)\n")
    ev = {"cwd": proj, "tool_use_id": "toolu_pt"}
    key = "OPEN" + "AI_API_KEY"
    def verdict(c):
        return ns["paid_verdict"](ev, c, ns["ps_text"](c), True, None, False, True)
    verdict("python warm.py")   # the patterns compile on first use: the times below are the steady state inside one process
    for c in ("Get-ChildItem", "Get-Content notes.txt", "Write-Host hello", "Set-Location .\\src"):
        t0 = time.monotonic()
        for _ in range(200):
            verdict(c)
        ms = (time.monotonic() - t0) / 200 * 1000
        if ms >= 5 or verdict(c) is not None:
            bad.append("ordinary %r: %.2f ms" % (c, ms))
    shapes = {   # (text, the verdict is None?)  one 30 KB text per PowerShell form
        "Start-Process words": ("Start-Process " * 2200, True),
        "Start-Process python, 30 KB of arguments": ('Start-Process python -ArgumentList "' + "a " * 14000 + '"', True),
        "Start-Process runs": ("Start-Process python -ArgumentList warm.py;" * 700, True),
        "key assignments": (("$env:%s = 'a'; " % key) * 1000, True),
        "mentions of a key": (("Write-Host %s; " % key) * 1000, True),
        "call operators": ("& python warm.py " * 1000, True),
        "a loop around a paid script": ("foreach ($i in 1..3) { " + "python render.py --n 1; " * 800 + "}", False),
        "a backslash path word": ("python " + "a\\" * 14000 + "x.py", True),
        "1,500 backslash script runs": (";".join(".\\tools\\e%d.py" % i for i in range(1500)), True),
        "download cmdlets": ("iwr -Uri a.example/x -OutFile y; " * 900, True),
        "bare-word assignments": ("$a = hello; " * 2500, True),
        "literal assignments": ("$a = 5; $b = $a; $c = $true; $d = 'x'; " * 750, True),
        "one number-like word": ("$a = " + "1" * 30000 + "x", True),
        "one long dotted word": ("$a = " + "1." * 15000 + "x", True),
    }
    for nm, (c, none) in shapes.items():
        assert len(c) < 32768, (nm, len(c))
        t0 = time.monotonic(); r = verdict(c); dt = time.monotonic() - t0
        if dt >= 1.0:
            bad.append("%s: %.2f s" % (nm, dt))
        if (r is None) != none:
            bad.append("%s: verdict %r" % (nm, r and r[:60]))
    print("ok" if not bad else "; ".join(bad))
elif mode == "fxtime":   # fxtime GUARD PROJECT: the F4b fix readers inside the process (Bash texts, then PowerShell texts), each under 32 KB and decided in under 1 s with the verdict the cases show
    import os, time
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "fxtime"}
    exec(compile(src, "bash-guard", "exec"), ns)
    proj, bad = sys.argv[3], []
    for d in (".claude", "tools", "tests"):
        os.makedirs(os.path.join(proj, d), exist_ok=True)
    open(os.path.join(proj, "tools", "entry.py"), "w").write("print(1)\n")
    open(os.path.join(proj, "render.py"), "w").write("import " + "open" + "ai\n")   # a paid script, the SDK name never spelled whole here
    open(os.path.join(proj, "warm.py"), "w").write("print(1)\n")
    ev = {"cwd": proj, "tool_use_id": "toolu_fx"}
    def check(name, c, adapter, want_none, ps=False):
        assert len(c) < 32768, (name, len(c))
        open(os.path.join(proj, ".claude", "smartuse.local.md"), "w").write(adapter)
        t0 = time.monotonic(); r = ns["paid_verdict"](ev, c, ns["ps_text"](c) if ps else c, True, None, False, ps); dt = time.monotonic() - t0
        if dt >= 1.0:
            bad.append("%s: %.2f s" % (name, dt))
        if (r is None) != want_none:
            bad.append("%s: verdict %r" % (name, r and r[:60]))
    only = "paid_scripts: tools/entry.py only --pay\n"
    free = "paid_free: --dry-run, tests/*.py\n"
    check("cd words, then a paid run, a free path and a free flag listed", "cd a; " * 5000 + "python render.py --n 1", free, False)
    check("30 KB of glued quoted words against an only item", "python tools/entry.py " + "'a'b " * 5000, only, False)
    check("30 KB of glued free flags", "python render.py " + "'--dry-run'x " * 2400, free, False)
    check("30 KB of words with a backslash", "python render.py " + "--dry\\-run " * 2700, free, False)
    check("30 KB of false free-flag values", "python render.py " + "--dry-run=no " * 2300, free, False)
    check("xargs with 30 KB of arguments", "printf x | xargs python tools/entry.py " + "--zz " * 5000, only, False)
    check("one mention with 2,000 substitutions", "echo notes.py " + '"$(echo x)" ' * 2000, "", True)
    check("1,500 mentions with a substitution, then a paid run", 'echo "$(echo x)"; ' * 1500 + "python render.py --n 1", "", False)
    check("2,000 nested substitutions around a paid run", 'echo "$(' * 2000 + "python render.py" + ')"' * 2000, "", False)
    check("2,000 nested substitutions, no paid run", 'echo "$(' * 2000 + "notes.py" + ')"' * 2000, "", True)
    check("a back-tick word in 30 KB of mentions", 'echo "`echo x`" ' * 1900 + "notes.py", "", True)
    check("PowerShell: 5,000 chained assignments, then a paid run", "$a = " * 5000 + "python render.py", "", False, True)
    check("PowerShell: 5,000 Start-Process parameters the guard does not know", "Start-Process " + "-Foo " * 5000 + "python warm.py", "", False, True)
    check("PowerShell: 5,000 Start-Process prefixes it does know", "Start-Process python -ArgumentList warm.py " + "-Wai " * 5000, "", True, True)
    check("PowerShell: 1,200 script blocks after pipes, no paid run", "1..3 | Foo-Bar { $_ }; " * 1200 + "python warm.py", "", True, True)
    check("PowerShell: 1,500 nested blocks after pipes around a paid run", "1..3 | Foo { " * 1500 + "python render.py --n 1" + " }" * 1500, "", False, True)
    check("PowerShell: 1,800 Set-Location words, then a paid run", "Set-Location a; " * 1800 + "python render.py", free, False, True)
    check("PowerShell: 1,000 mentions with a substitution, no paid run", 'Write-Output "$(Get-Date)"; ' * 1000 + "python warm.py", "", True, True)
    # 0.7.0 review fix round: the runner wrappers (M1) and the inline key before a script (m5)
    check("24 KB of runner words (pdm run, conda run -n e, op run --) around a paid run", "pdm run " * 1500 + "conda run -n e " * 500 + "op run -- " * 500 + "python render.py --n 1", "", False)
    check("PowerShell: 24 KB of runner words around a paid run", "pdm run " * 1500 + "conda run -n e " * 500 + "op run -- " * 500 + "python render.py --n 1", "", False, True)
    check("28 KB of runner options before run (hatch -e t run, dotenv -f .e run, doppler --token x run), then a paid run", "hatch -e t run " * 700 + "dotenv -f .e run " * 400 + "doppler --token x run -- " * 300 + "pdm " + "-v " * 1500 + "run python render.py --n 1", "", False)
    check("PowerShell: 28 KB of runner options before run, then a paid run", "hatch -e t run " * 700 + "dotenv -f .e run " * 400 + "doppler --token x run -- " * 300 + "pdm " + "-v " * 1500 + "run python render.py --n 1", "", False, True)
    check("1,700 inline key assignments, then a paid run",(("OPENAI" + "_API_KEY") + "=x ") * 1700 + "python render.py", "", False)
    check("1,700 env words with an inline key, then a paid run", "env " + (("OPENAI" + "_API_KEY") + "=x ") * 1700 + "python render.py", "", False)
    print("ok" if not bad else "; ".join(bad))
elif mode == "ltime":    # ltime GUARD PROJECT: F4b step 1, the folder lookup inside the process: each text under 32 KB and decided in under 1 s with the verdict the cases show (this mode writes its own folders)
    import os, time
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "ltime"}
    exec(compile(src, "bash-guard", "exec"), ns)
    proj, bad = sys.argv[3], []
    sdk = "import " + "open" + "ai\n"                                     # a paid script, the SDK name never spelled whole here
    for i in range(70):
        os.makedirs(os.path.join(proj, "d%d" % i), exist_ok=True)
    for i in range(300):
        os.makedirs(os.path.join(proj, "e%d" % i), exist_ok=True)
    for d, n in (("pol", "g.py"), ("d9", "g9.py"), ("d4", "g4.py"), ("d0", "g0.py")):
        os.makedirs(os.path.join(proj, d), exist_ok=True); open(os.path.join(proj, d, n), "w").write(sdk)
    os.makedirs(os.path.join(proj, ".claude"), exist_ok=True)
    open(os.path.join(proj, "warm.py"), "w").write("print(1)\n")
    ev = {"cwd": proj, "tool_use_id": "toolu_lt"}
    def check(name, c, adapter, want_none, ps=False, strict=True, deadline=None, has=""):
        assert len(c) < 32768, (name, len(c))
        open(os.path.join(proj, ".claude", "smartuse.local.md"), "w").write(adapter)
        t0 = time.monotonic(); r = ns["paid_verdict"](ev, c, ns["ps_text"](c) if ps else c, strict, deadline, False, ps); dt = time.monotonic() - t0
        if dt >= 1.0:
            bad.append("%s: %.2f s" % (name, dt))
        if (r is None) != want_none or (has and not (r and has in r)):
            bad.append("%s: verdict %r" % (name, r and r[:90]))
    check("warm up", "python warm.py", "", True)       # the patterns compile on first use
    cds = "; ".join("cd d%d" % i for i in range(64))
    ten = "; ".join("cd d%d" % i for i in range(10))
    check("64 folder words, the script in the nearest folder", cds + "; cd pol; python g.py", "", False)
    check("PowerShell: 64 folder words, the script in the nearest folder", cds.replace("cd ", "Set-Location ") + "; Set-Location pol; python g.py", "", False, True)
    check("a script only in the folder 10 folders back is beyond the 6 nearest (a stated limit)", ten + "; python g0.py", "", True)
    check("... in the 6th nearest folder it is read", ten + "; python g4.py", "", False)
    check("... in the nearest folder it is read", ten + "; python g9.py", "", False)
    check("3,000 plain words, then a relative script word in the folder named last", "echo " + "w " * 3000 + "pol; python g.py", "", False)
    check("3,000 plain words, then a relative script word that is nowhere", "echo " + "w " * 3000 + "; python nowhere.py", "", True)
    check("30 KB of cd words to one folder, then the run", "cd pol; " * 3500 + "python g.py", "", False)
    check("30 KB of distinct words, then the run", ";".join("echo x%d y%d" % (i, i) for i in range(1700)) + "; python warm.py", "", True)
    check("as many runs as fit in 30 KB, each after 64 new words of its own: the probe cap is spent, a run that still needs a lookup is unreadable (strict denies)", ";".join("echo " + " ".join("f%d_%d" % (i, j) for j in range(64)) + "; python warm.py" for i in range(1000))[:32000], "", False, has="could not verify")
    check("1,500 relative runs of files that are not there", ";".join("python u%d.py" % i for i in range(1500)), "", True)
    check("a missing folder", "cd nowhere; python g.py", "", True)
    check("PowerShell: a missing folder", "Set-Location nowhere; python g.py", "", True, True)
    ad = "paid_scripts: nothing.py\n"                                    # arms light
    cap0 = ns["PAID_LOOK_STATS"]; ns["PAID_LOOK_STATS"] = 2
    check("fix 3: the probe cap spent, strict: could not verify (a lookup that was cut is no 'no signal')", "cd d0; cd d1; cd pol; python g.py", "", False, has="could not verify whether g.py pays")
    check("fix 3: ... light allows, as a script that cannot be read does", "cd d0; cd d1; cd pol; python g.py", ad, True, strict=False)
    ns["PAID_LOOK_STATS"] = cap0
    check("fix 3: the same text with the cap whole is denied as a paid run", "cd d0; cd d1; cd pol; python g.py", "", False, has="no go from the owner for g.py")
    filler = ";".join("echo " + " ".join("f%d_%d" % (i, j) for j in range(40)) + "; python warm.py" for i in range(56))
    check("fix 3: a crafted text that spends the cap, then a cd run of a paid script: not allowed in strict", filler + "; cd pol; python g.py", "", False)
    check("fix 3: ... and in light it is allowed as a script that cannot be read (m7)", filler + "; cd pol; python g.py", ad, True, strict=False)
    open(os.path.join(proj, "pol", "h.py"), "w").write("print(1)\n")
    open(os.path.join(proj, "rg.py"), "w").write(sdk)
    adf = "paid_scripts: rg.py only --pay\n"
    check("fix 2: a file name item frees a run with no flag (the cap whole)", "cd d0; cd d1; python rg.py", adf, True)
    cap0 = ns["PAID_LOOK_STATS"]; ns["PAID_LOOK_STATS"] = 1
    check("fix 2: the lookup cut short: no only freedom, the run is paid (strict)", "cd d0; cd d1; python rg.py", adf, False, has="no go from the owner for rg.py")
    check("fix 2: ... and in light", "cd d0; cd d1; python rg.py", adf, False, strict=False, has="no go from the owner for rg.py")
    ns["PAID_LOOK_STATS"] = cap0
    check("fix 2: a free path frees the run when the lookup is whole", "echo d0; echo d1; python rg.py", "paid_free: rg.py\n", True)
    ns["PAID_LOOK_STATS"] = 1
    check("fix 2: ... and does not when the lookup was cut short (the file list is incomplete)", "echo d0; echo d1; python rg.py", "paid_free: rg.py\n", False, has="no go from the owner for rg.py")
    ns["PAID_LOOK_STATS"] = cap0
    check("fix 4: the hook's deadline already past, a run that needs a lookup is unreadable: strict denies", "cd pol; python h.py", "", False, deadline=time.monotonic() - 1, has="could not verify")
    check("fix 4: ... the same run with time left is allowed (no signal in pol/h.py)", "cd pol; python h.py", "", True, deadline=time.monotonic() + 100)
    check("fix 4: ... a plain run that needs none is not changed by it", "python warm.py", "", True, deadline=time.monotonic() + 100)
    check("fix 4: 32 KB of the same cd and run pair (the files are read once)", "cd pol; python g.py; " * 1500, "", False, has="no go from the owner for g.py")
    check("fix 4: 32 KB of cd and run pairs over 300 folders", "".join("cd e%d; python w.py; " % (i % 300) for i in range(1500)), "", True)
    check("fix 4: PowerShell, 32 KB of Set-Location and run pairs over 300 folders", "".join("Set-Location e%d; python w.py; " % (i % 300) for i in range(950)), "", True, True)
    check("fix 5: PowerShell, Set-Location -Path:pol reads the value as the folder", "Set-Location -Path:pol; python g.py", "", False, True, has="no go from the owner for g.py")
    check("fix 5: ... -LiteralPath:pol, a quoted value, a shortened parameter", "Set-Location -LiteralPath:pol; sl -Pa:'pol'; python g.py", "", False, True)
    check("a folder at the outside of two nested bash -c strings", "cd pol; bash -c \"bash -c 'python g.py'\"", "", False)
    h = os.path.join(proj, "home"); os.makedirs(os.path.join(h, "hf"), exist_ok=True); open(os.path.join(h, "hf", "gh.py"), "w").write(sdk)
    old = {k: os.environ.get(k) for k in ("HOME", "USERPROFILE")}
    os.environ["HOME"] = os.environ["USERPROFILE"] = h
    try:
        check("a ~ folder is expanded", "cd ~/hf; python gh.py", "", False)
        check("a ~ word that names no folder", "cd ~/nothere; python gh.py", "", True)
    finally:
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    print("ok" if not bad else "; ".join(bad))
elif mode == "ekey":     # ekey FILE KEY FIELD: the field of the entry KEY of paid-runs.json, as JSON ("missing" when there is no such entry)
    d = json.load(open(sys.argv[2], encoding="utf-8")); e = d.get(sys.argv[3])
    print(json.dumps(e.get(sys.argv[4])) if isinstance(e, dict) else "missing")
elif mode == "scandl":   # scandl GUARD PROJECT TRANSCRIPT: 0.7.0 F5, the transcript scan itself runs past the hook's one deadline (its record reader is made slow): a past deadline given to the scan raises, and the whole hook denies
    import contextlib, io, os, time, types
    src = open(sys.argv[2], encoding="utf-8").read().replace("\nmain()\n", "\n"); ns = {"__name__": "scandl"}
    exec(compile(src, "bash-guard", "exec"), ns)
    proj, tp = sys.argv[3], sys.argv[4]
    try:
        ns["paid_scan_typed"](tp, time.monotonic() - 1)
        print("scan: no raise")
    except ns["PaidUnverified"] as e:
        print("scan: raised " + str(e))
    def slow(r):
        time.sleep(0.02)
        return None
    ns["paid_typed_text"] = slow
    ns["BUDGET_S"] = 0.6
    os.environ["CLAUDE_PLUGIN_OPTION_STRICT"] = "true"
    os.environ.pop("CLAUDE_PLUGIN_OPTION_RULES_OFF", None)
    ev = {"session_id": "s", "transcript_path": tp, "cwd": proj, "tool_name": "Bash", "tool_use_id": "toolu_sd", "tool_input": {"command": "python render.py --n 1"}}
    sys.stdin = types.SimpleNamespace(buffer=io.BytesIO(json.dumps(ev).encode()))
    out, t0 = io.StringIO(), time.monotonic()
    with contextlib.redirect_stdout(out):
        ns["main"]()
    dt = time.monotonic() - t0
    r = json.loads(out.getvalue())["hookSpecificOutput"]["permissionDecisionReason"] if out.getvalue() else ""
    print("hook %.2f %s" % (dt, ("deny " + r) if r else "allow"))
PY
CW=$(wp "$D/chk.py")

# --- the harness: one PreToolUse event in the shape Claude Code sends (session_id, transcript_path, cwd, permission_mode, tool_use_id)
PGTOOL=Bash   # the tool_name guard() sends: Bash, or PowerShell where a section sets it (F6, section 27)
: > "$D/none.jsonl"   # 0.7.0 F5: an empty transcript, the owner typed nothing (a MISSING one is a verification error, tested on its own in section 37)
NONE=$(wp "$D/none.jsonl"); TPATH=; XEV=   # TPATH, when a case sets it, is the transcript_path the next guard calls send instead of NONE; XEV is extra event fields (a subagent's agent_id)
guard() { # $1 = command, $2 = tool_use_id ("-" = none), $3 = cwd (default the project) -> $OUT (stdout) and $ERR (stderr)
  local tid=${2:-toolu_01} idf; idf=$(printf ',"tool_use_id":"%s"' "$tid"); [ "$tid" = "-" ] && idf=""
  IN=$(printf '{"session_id":"sid-test","transcript_path":"%s","cwd":"%s","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"%s"%s%s,"tool_input":{"command":"%s"}}' "${TPATH:-$NONE}" "${3:-$PW}" "$PGTOOL" "$idf" "$XEV" "$(jstr "$1")")
  OUT=$(printf '%s' "$IN" | py "$G" 2>"$D/err"); ERR=$(cat "$D/err")
}
fresh() { rm -rf "$HOME/.claude/smartuse/projects" "$D/proj/.claude"; mkdir -p "$D/proj/.claude"; }   # a case starts with no state and no adapter
adapter() { printf '%b' "$1" > "$D/proj/.claude/smartuse.local.md"; }
deny() { # $1 = label, $2 = command, $3 = a text the reason must hold, $4 = tool_use_id
  guard "$2" "${4:-}"
  if [ -n "$OUT" ] && [ -z "$ERR" ]; then case "$OUT" in *"bash-guard: paid call ("*"$3"*) ok "$1";; *) ko "$1 -- the reason lacks '$3': $OUT";; esac; else ko "$1 -- wanted a deny, got stdout '$OUT' stderr '$ERR'"; fi
}
allow() { guard "$2" "${3:-}"; [ -z "$OUT" ] && [ -z "$ERR" ] && ok "$1" || ko "$1 -- wanted silence, got stdout '$OUT' stderr '$ERR'"; }
endrule() { # $1 = label, $2 = "noadapter" (a counter-side reason): the deny in $OUT passes the shape check, ends "Nothing was spent." then " [rule paid]", and names no way to reset a count; "noadapter" also names no adapter (0.7.4 F3)
  case "$OUT" in *'Nothing was spent. [rule paid]"}}') ;; *) ko "$1 -- the reason does not end Nothing was spent. [rule paid]: $OUT"; return;; esac
  case "$OUT" in *reset*|*Reset*) ko "$1 -- the reason says how to reset a count: $OUT"; return;; esac
  if [ "${2:-}" = noadapter ]; then case "$OUT" in *smartuse.local.md*|*adapter*|*'put it in'*) ko "$1 -- a counter-side reason must not send the owner to the adapter: $OUT"; return;; esac; fi
  [ "$(py "$CW" shape "$OUT" </dev/null 2>&1)" = ok ] && ok "$1" || ko "$1 -- the deny JSON shape: $OUT"
}
T_RO="could not verify the go (the counter is not writable); run this call again. If it repeats, run /smartuse:doctor, then check that paid-runs.json in the state folder is not read-only. Nothing was spent."   # 0.7.4 F3 (D-YK31): the three counter-side tails
T_BUSY="could not verify the go (the counter is busy); the counter lock could not be taken (another paid call may hold it); run this call again. If it repeats, run /smartuse:doctor. Nothing was spent."
T_UNR="could not verify the go (paid-runs.json is unreadable); ask the owner to repair paid-runs.json in this project's state folder. Nothing was spent."
field() { py "$CW" entry "$(wp "$R")" "$1" </dev/null; }
IMP=$(printf 'import %s' openai)                                  # the SDK line, never spelled whole in this file
mkpaid() { printf '%s\nprint("would call")\n' "$IMP" > "$D/proj/render.py"; }   # render.py: names an SDK -> a paid script
mkplain() { printf 'print("%s")\n' "$1" > "$D/proj/$1.py"; }                    # <name>.py: names nothing paid
mkplain polish

# ===== 1. INCIDENT REPLAY 1: the batch command, the Gemini key in its source, no go anywhere -> denied at the first call
fresh; printf 'import os\nKEY = os.environ["%s_API_KEY"]\nprint("batch of 6")\n' GEMINI > "$D/proj/render.py"
deny "incident replay: python render.py --images 6, the key in the source, no go -> denied at the first call" 'python render.py --images 6' 'GEMINI_API_KEY in render.py'
case "$OUT" in *'bash-guard: paid call (GEMINI_API_KEY in render.py) '*) ok "the reason starts bash-guard: paid call (<signal>) and names the key and the script";; *) ko "reason start: $OUT";; esac
case "$OUT" in *'no go from the owner for render.py. Ask the owner to add \"paid: render.py x <runs>, cap <amount>\" to .claude/smartuse.local.md. Nothing was spent.'*) ok "... and gives the exact adapter line to add, ending Nothing was spent.";; *) ko "reason body: $OUT";; esac
case "$OUT" in *'The owner can also type \"paid go: render.py x <runs>, cap <amount>\" in this session (a go relayed from another session or a tool does not count).'*) ok "... and (F5) names the typed go, and that a relayed one does not count";; *) ko "reason lacks the typed go (F5): $OUT";; esac
[ ! -e "$P" ] && ok "a deny writes nothing: no state dir" || ko "a deny created $P"
[ "$(py "$CW" shape "$OUT" </dev/null)" = ok ] && ok "the deny JSON is the other guards' shape: one ASCII line, hookEventName PreToolUse, permissionDecision deny, reason prefixed bash-guard:" || ko "deny shape: $OUT"
fresh; mkpaid
deny "an SDK import in the script is named in the reason ($IMP in render.py)" 'python render.py --images 1' "$IMP in render.py"
deny "a host on the command line is named (host api.openai.com on the command line)" 'curl https://api.openai.com/v1/images/generations -d @req.json' 'host api.openai.com on the command line'

# ===== 2. the adapter go: the same call passes (silently); one entry in paid-runs.json; the state dir is ledger.py's
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'   # test ok: the cap rules of section 9 are not in play here
allow "paid: render.py x 10, cap RM5, test ok in the adapter -> python render.py --images 1 passes, nothing printed" 'python render.py --images 1' toolu_a
[ "$(py "$CW" count "$(wp "$R")" </dev/null)" = 1 ] && ok "paid-runs.json holds one entry" || ko "paid-runs.json: $(cat "$R" 2>&1)"
[ "$(field used)" = 1 ] && ok "... used: 1" || ko "used: $(field used)"
[ "$(field go_from)" = '"adapter"' ] && ok "... go_from: adapter" || ko "go_from: $(field go_from)"
[ "$(field script)" = '"render.py"' ] && [ "$(field runs)" = 10 ] && [ "$(field cap)" = '"RM5"' ] && ok "... script render.py, runs 10, cap RM5 (echoed, never measured)" || ko "entry: $(cat "$R")"
[ "$(field test_ok)" = true ] && [ "$(field stopped)" = false ] && ok "... test_ok true (from the line), stopped false (F3 owns that)" || ko "flags: $(cat "$R")"
[ -f "$P/paid.toolu_a.done" ] && ok "one claim marker per counted call: paid.toolu_a.done" || ko "no claim marker in $P: $(ls "$P" 2>&1)"
lk=$(CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --state-dir </dev/null); lk=${lk##*[/\\]}; lk=${lk%$'\r'}
got=$(ls "$HOME/.claude/smartuse/projects" 2>/dev/null); [ -n "$lk" ] && [ "$got" = "$lk" ] && [ "$K" = "$lk" ] && ok "the state dir equals ledger.py's --state-dir and the key the test computes ($lk)" || ko "state dir: the guard wrote '$got', ledger.py says '$lk', the test computes '$K'"
allow "the same tool_use_id again (a second copy of the hook) passes" 'python render.py --images 1' toolu_a
[ "$(field used)" = 1 ] && ok "... and counts once: used still 1" || ko "used after a repeated id: $(field used)"
allow "a new tool_use_id passes" 'python render.py --images 1' toolu_b
[ "$(field used)" = 2 ] && ok "... and counts: used 2" || ko "used after a new id: $(field used)"
allow "a call with no tool_use_id passes" 'python render.py --images 1' -
[ "$(field used)" = 3 ] && ok "... and counts (nothing to claim): used 3" || ko "used after an id-less call: $(field used)"
ls "$P"/*.tmp >/dev/null 2>&1 && ko "a tmp file was left in $P" || ok "the atomic write leaves no tmp file"
allow "a call that is not paid is not counted, and not touched" 'python polish.py' toolu_c
[ "$(field used)" = 3 ] && ok "... used still 3" || ko "used after a plain call: $(field used)"
allow "a cd before the command does not hide it: with the go it passes" 'cd . && python render.py --images 1' toolu_d
[ "$(field used)" = 4 ] && ok "... counted in the segment after cd: used 4" || ko "used after cd &&: $(field used)"

# ===== 3. a go covers its own script only; a changed line is a new counter
fresh; mkpaid; adapter 'paid: polish.py x 2, cap RM1\n'
deny "a go for polish.py does not cover render.py" 'python render.py' 'no go from the owner for render.py'
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'; guard 'python render.py --n 1' toolu_e
adapter 'paid: render.py x 10, cap RM6\n'; guard 'python render.py --n 1' toolu_f
[ "$(py "$CW" count "$(wp "$R")" </dev/null)" = 2 ] && ok "a changed go line (cap RM5 -> RM6) is a new counter: two entries" || ko "entries after a changed line: $(cat "$R")"
adapter 'paid: render.py x 10,   cap  RM6\n'; guard 'python render.py --n 1' toolu_g
[ "$(py "$CW" count "$(wp "$R")" </dev/null)" = 2 ] && ok "... but extra spaces in the line are not a change" || ko "entries after a respaced line: $(cat "$R")"

# ===== 4. the go's grammar
gram() { # $1 = label, $2 = adapter text, $3 = allow|deny
  fresh; mkpaid; adapter "$2"
  if [ "$3" = allow ]; then allow "$1" 'python render.py --n 1' toolu_x; else deny "$1" 'python render.py' 'no go from the owner for render.py'; fi
}
gram "x between script and runs" 'paid: render.py x 3, cap RM2\n' allow
gram "× (multiplication sign)" 'paid: render.py × 3, cap RM2\n' allow
gram "* (asterisk)" 'paid: render.py * 3, cap RM2\n' allow
gram "the list form under paid:" 'paid:\n  - render.py x 3, cap RM2\n' allow
gram "the list form, the go in the second item" 'paid:\n  - polish.py x 3, cap RM2\n  - render.py x 3, cap RM2\n' allow
gram "a go in the frontmatter of a larger adapter" '---\ncheck: true\npaid: render.py x 3, cap RM2\n---\nnotes\n' allow
gram "a quoted line" 'paid: "render.py x 3, cap RM2"\n' allow
gram "CRLF line ends" 'paid: render.py x 3, cap RM2\r\n' allow
gram "the script by its path and in another case (Src/Render.PY)" 'paid: Src/Render.PY x 3, cap RM2\n' allow
gram "no cap is still a go (cap is free text)" 'paid: render.py x 3\n' allow
gram "count and test ok parse: render.py x 3, cap RM2, count --pics, test ok" 'paid: render.py x 3, cap RM2, count --pics, test ok\n' allow
gram "runs 0 is no go" 'paid: render.py x 0, cap RM2\n' deny
gram "a bare script name is no go (no runs)" 'paid: render.py\n' deny
gram "an empty paid: line is no go" 'paid:\n' deny
gram "paid_scripts alone is not a go" 'paid_scripts: render.py\n' deny
gram "a go in a line that is not at the start (prose) is no go" 'note: paid: render.py x 3\n' deny
fresh; mkpaid; adapter 'paid: render.py x 3, cap RM2, count --pics, test ok\n'; guard 'python render.py' toolu_y
[ "$(field count)" = '"--pics"' ] && [ "$(field test_ok)" = true ] && ok "count --pics and test ok are kept in the entry" || ko "entry: $(cat "$R")"

# ===== 5. paid_scripts, a script with a go, paid_hosts
fresh; adapter 'paid_scripts: polish.py\n'
deny "paid_scripts: a helper script that names nothing paid is paid by name" 'python polish.py' 'polish.py is in paid_scripts'
fresh; adapter 'paid_scripts: other.py, Polish.PY\n'
deny "paid_scripts: a comma list, any case" 'python3 polish.py --x' 'polish.py is in paid_scripts'
fresh; adapter 'paid_scripts: polish.py\npaid: polish.py x 2, cap RM1\n'
allow "paid_scripts + a go for the script -> passes" 'python polish.py --n 1' toolu_p
[ "$(field script)" = '"polish.py"' ] && [ "$(field used)" = 1 ] && ok "... and is counted" || ko "entry: $(cat "$R" 2>&1)"
fresh; adapter 'paid: polish.py x 2, cap RM1\n'
allow "a script named in a paid: line is paid even though its source names nothing: with the go it passes" 'python polish.py --n 1' toolu_q
[ "$(field used)" = 1 ] && ok "... and is counted (a helper-module call is closed by the go line)" || ko "entry: $(cat "$R" 2>&1)"
fresh
allow "no adapter: curl to a host the list does not know passes" 'curl -s https://api.example-images.test/v1/x'
adapter 'paid_hosts: api.example-images.test, other.test\n'
deny "paid_hosts: an extra host is paid" 'curl -s https://api.example-images.test/v1/x' 'host api.example-images.test on the command line'
deny "... with a subdomain in front" 'curl -s https://eu.api.example-images.test/v1/x' 'host eu.api.example-images.test on the command line'
allow "... a look-alike host is not" 'curl -s https://api.example-images.test.invalid/v1/x'
allow "... and the built-in list still stands for what it does not name (api.github.com)" 'curl -s https://api.github.com/repos/x/y'

# ===== 6. a verification error after a positive detection DENIES; the counter is never reset; a detection error does not
fresh; mkpaid; mkdir "$D/proj/.claude/smartuse.local.md"
deny "the adapter exists but cannot be read -> deny: could not verify the go" 'python render.py' 'could not verify the go (the adapter is unreadable); put it in .claude/smartuse.local.md. Nothing was spent.'
endrule "... 0.7.4 F3 r7 (pin): the adapter-unreadable reason keeps its adapter tail and still ends Nothing was spent. [rule paid]"
fresh; adapter 'paid: render.py x 10, cap RM5\n'; mkpaid; guard 'python render.py' toolu_1; mkdir -p "$P"; printf '{broken' > "$R"
deny "a corrupt paid-runs.json -> deny: could not verify the go" 'python render.py' 'could not verify the go (paid-runs.json is unreadable)' toolu_2
deny "... 0.7.4 F3 r4: the tail says to ask the owner to repair the file, in this project's state folder" 'python render.py' "$T_UNR" toolu_2
endrule "... r4/r7: the unreadable-counter reason is one ASCII line, ends Nothing was spent. [rule paid], names no adapter" noadapter
[ "$(cat "$R")" = '{broken' ] && ok "... and the file is left as it was: never a silent reset" || ko "the corrupt counter was changed: $(cat "$R")"
printf '[1,2]' > "$R"
deny "a counter file that is JSON but not an object -> deny" 'python render.py' "$T_UNR" toolu_3
fresh; adapter 'paid: render.py x 10, cap RM5\n'; mkpaid; mkdir -p "$HOME/.claude/smartuse/projects"; : > "$P"
deny "the state dir cannot be created (a file sits where it goes) -> deny: could not verify the go" 'python render.py' 'could not verify the go (' toolu_4
case "$OUT" in *'could not verify the go (the state folder cannot be written); run /smartuse:doctor. Nothing was spent.'*) ok "... 0.7.1 F2: the reason names the state folder and /smartuse:doctor";; *) ko "state folder reason: $OUT";; esac
case "$OUT" in *'smartuse.local.md'*) ko "0.7.1 F2: a state folder that cannot be written must not point at the adapter: $OUT";; *) ok "... and does not send the owner to smartuse.local.md (the adapter is not the fix)";; esac
fresh; mkpaid
guard 'python polish.py'; [ -z "$OUT" ] && [ -z "$ERR" ] && ok "a call that is not paid is let through whatever the state (detection errors fail open as before)" || ko "plain call: $OUT $ERR"
printf '{"tool_name":"Bash","tool_input":' | py "$G" > "$D/out" 2>&1; [ ! -s "$D/out" ] && ok "garbage on stdin -> silent, no deny (fail open, as before)" || ko "garbage stdin: $(cat "$D/out")"
rm -f "$D/proj/render.py"; adapter 'paid: render.py x 3, cap RM2\n'
allow "a script path that does not exist is no error: with the go it passes" 'python render.py --n 1'

# ===== 7. the cwd in the Git Bash form; a script in another directory by absolute path; no .env is read
case "$PW" in [A-Za-z]:/*)   # Windows: the cwd as Git Bash writes it, /c/Users/... (a JSON string the hook must convert; "/tmp/..." has no drive and stays)
  fresh; mkpaid; U="/$(printf '%s' "${PW:0:1}" | tr 'A-Z' 'a-z')${PW:2}"
  guard 'python render.py' toolu_u "$U"; case "$OUT" in *"$IMP in render.py"*) ok "cwd $U (the Git Bash form) still finds the script: converted by native_path";; *) ko "cwd in the MSYS form $U: '$OUT' '$ERR'";; esac;;
*) skip "cwd in the Git Bash form: skipped (not a Windows drive path on this OS)";; esac
fresh; mkpaid; mkdir -p "$D/elsewhere"
guard "python $PW/render.py" toolu_v "$(wp "$D/elsewhere")"; case "$OUT" in *"$IMP in render.py"*) ok "an absolute script path is read from any cwd";; *) ko "absolute path: '$OUT' '$ERR'";; esac
fresh; mkplain plain; printf 'OPENAI_%s=sk-synthetic\n' API_KEY > "$D/proj/.env"
allow "a .env that holds a key does not make a plain script paid (it is never opened)" 'python plain.py'
allow "... nor does reading around it" 'ls -la'

# ===== 8. the count rule: the first run after a go must make ONE output (a count flag at 1, the flag the go names, or `count none`)
used() { sed -n 's/.*"used": *\([0-9][0-9]*\).*/\1/p' "$R" 2>/dev/null | head -1; }   # the one entry's used, without a Python start
nent() { grep -c '"script":' "$R" 2>/dev/null; }                                       # how many go counters
cf() { # $1 = label, $2 = command, $3 = allow|deny, $4 = adapter text (default: x 10, no test ok), $5 = text the deny reason must hold
  fresh; mkpaid; adapter "${4:-paid: render.py x 10, cap RM5\n}"
  if [ "$3" = allow ]; then allow "$1" "$2" toolu_cf; else deny "$1" "$2" "${5:-first run after the go must make ONE output}" toolu_cf; fi
}
cf "--n 1" 'python render.py --n 1' allow
cf "--n=1" 'python render.py --n=1' allow
cf "-n1 (glued)" 'python render.py -n1' allow
cf "-n 1" 'python render.py -n 1' allow
cf "-N 1" 'python render.py -N 1' allow
cf "--count=1" 'python render.py --count=1' allow
cf "--num-images 1" 'python render.py --num-images 1' allow
cf "--images 1" 'python render.py --images 1' allow
cf "a count flag among other flags" 'python render.py --prompt cat --images 1 --out x.png' allow
cf "python3 and a path: the flag after the script is found" "python3 $PW/render.py --samples 1" allow
cf "--images 6 is a batch: denied, the reason names what it saw" 'python render.py --images 6' deny '' 'first run after the go must make ONE output: set the count flag to 1 (seen --images 6; the owner can add \"count <flag>\" or \"count none\" to the go).'
cf "--n 2" 'python render.py --n 2' deny '' 'seen --n 2;'
cf "-n6 (glued)" 'python render.py -n6' deny '' 'seen -n 6;'
cf "--images 1 with a --batch 6 beside it: every count flag must be 1" 'python render.py --images 1 --batch 6' deny '' 'seen --batch 6;'
cf "no count flag at all" 'python render.py' deny '' 'first run after the go must make ONE output: set the count flag to 1 (seen no count flag; the owner can add \"count <flag>\" or \"count none\" to the go).'
cf "a count flag without a value" 'python render.py --images' deny '' 'seen --images;'
cf "a look-alike flag (--num-images-x 1) is not a count flag" 'python render.py --num-images-x 1' deny '' 'seen no count flag'
cf "the 1 must belong to the script that is run (--n 1 on another command)" 'python polish.py --n 1 && python render.py' deny '' 'seen no count flag'
cf "... and the flag on the right segment passes" 'python polish.py && python render.py --n 1' allow
cf "bash -c \"python render.py --images 1\" passes" 'bash -c "python render.py --images 1"' allow
cf "bash -c \"python render.py --images 6\" is denied" 'bash -c "python render.py --images 6"' deny '' 'seen --images 6;'
cf "count --pics: the go's own flag at 1 passes" 'python render.py --pics 1' allow 'paid: render.py x 10, cap RM5, count --pics\n'
cf "count --pics: --pics 3 is denied" 'python render.py --pics 3' deny 'paid: render.py x 10, cap RM5, count --pics\n' 'seen --pics 3;'
cf "count --pics: the usual flags still count (--n 1)" 'python render.py --n 1' allow 'paid: render.py x 10, cap RM5, count --pics\n'
cf "count none: a script that makes one output per run passes with no flag" 'python render.py' allow 'paid: render.py x 10, cap RM5, count none\n'
cf "count none: ... whatever its flags" 'python render.py --images 6' allow 'paid: render.py x 10, cap RM5, count none\n'
cf "test ok on the line: the first run needs no count flag either" 'python render.py --images 6' allow 'paid: render.py x 3, cap RM2, test ok\n'
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'; guard 'python render.py --images 6' toolu_nc
[ ! -e "$R" ] && [ ! -e "$P/paid.toolu_nc.done" ] && ok "a denied first run is not counted: no counter, no claim marker" || ko "a deny left state: $(ls "$P" 2>&1)"

# ===== 9. the cap: run 2 waits for test ok, test ok on the line lets the batch run (same counter), the run after the cap is denied
fresh; mkpaid; adapter 'paid: render.py x 3, cap RM2\n'
allow "x 3: run 1 (--n 1) passes" 'python render.py --n 1' toolu_r1
[ "$(used)" = 1 ] && ok "... used 1" || ko "used: $(used)"
deny "run 2 is denied: the batch waits for the owner's test ok" 'python render.py --n 1' "run 1 of 3 is done; the batch waits for the owner's " toolu_r2
case "$OUT" in *'waits for the owner'\''s \"test ok\": ask the owner to add \", test ok\" to that paid: line. Show the owner the one output first.'*) ok "... the reason says to add test ok to the paid: line and to show the owner the one output first";; *) ko "waits reason: $OUT";; esac
case "$OUT" in *'The owner can also type \"test ok\" in this session.'*) ok "... and (F5) says the owner can type test ok in this session";; *) ko "waits reason lacks the typed test ok (F5): $OUT";; esac
[ "$(used)" = 1 ] && [ ! -e "$P/paid.toolu_r2.done" ] && ok "... a denied run is not counted: used still 1, no claim marker" || ko "used after the deny: $(used)"
adapter 'paid: render.py x 3, cap RM2, test ok\n'
allow "the owner adds test ok to the line: run 2 passes (any flags)" 'python render.py --images 6' toolu_r3
[ "$(used)" = 2 ] && [ "$(nent)" = 1 ] && ok "... it is the same counter (test ok is not part of the go's id): one entry, used 2" || ko "after test ok: used $(used), $(nent) entries: $(cat "$R")"
[ "$(field test_ok)" = true ] && ok "... and the entry now says test_ok true" || ko "test_ok: $(field test_ok)"
allow "run 3 passes" 'python render.py --images 6' toolu_r4
deny "run 4 is denied: the go is used up (3 of 3)" 'python render.py --images 6' 'the go for render.py is used up (3 of 3). Ask the owner for a new go.' toolu_r5
[ "$(used)" = 3 ] && ok "... a denied run is not counted: used still 3" || ko "used after the cap: $(used)"
allow "the same tool_use_id as run 3 again passes even after the cap (counted once)" 'python render.py --images 6' toolu_r4
[ "$(used)" = 3 ] && ok "... used still 3" || ko "used after a repeated id: $(used)"
adapter 'paid: render.py x 3, cap RM3, test ok\n'
allow "a changed go line (cap RM2 -> RM3) is a fresh counter: the cap does not apply to it yet" 'python render.py --images 6' toolu_r6
[ "$(nent)" = 2 ] && ok "... two entries" || ko "entries: $(cat "$R")"
fresh; mkpaid; adapter 'paid: render.py x 1, cap RM1\n'
allow "x 1: the one run passes" 'python render.py --n 1' toolu_o1
deny "... and the next is used up (1 of 1), not 'waits for test ok'" 'python render.py --n 1' 'the go for render.py is used up (1 of 1)' toolu_o2
fresh; mkpaid; adapter 'paid:\n  - render.py x 1, cap RM1\n  - polish.py x 1, cap RM1\n'
allow "two scripts, two counters: render.py run 1" 'python render.py --n 1' toolu_s1
allow "... polish.py has its own: run 1 passes" 'python polish.py --n 1' toolu_s2
deny "... render.py is used up" 'python render.py --n 1' 'the go for render.py is used up (1 of 1)' toolu_s3
deny "... and polish.py is used up on its own" 'python polish.py --n 1' 'the go for polish.py is used up (1 of 1)' toolu_s4
[ "$(nent)" = 2 ] && [ "$(grep -c '"used": 1' "$R")" = 2 ] && ok "... two entries, each used 1" || ko "two counters: $(cat "$R")"

# ===== 10. the counter file: corrupt -> deny, restored -> carries on (never a reset); unwritable -> deny
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'
guard 'python render.py --n 1' toolu_k1; cp "$R" "$D/saved.json"; printf '{broken' > "$R"
deny "a corrupt counter -> deny: could not verify the go" 'python render.py --n 1' "$T_UNR" toolu_k2
cp "$D/saved.json" "$R"
allow "the file restored: the same go carries on" 'python render.py --n 1' toolu_k3
[ "$(used)" = 2 ] && ok "... used 2: counted on from the restored file, never reset to 0" || ko "used after the restore: $(used)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'
guard 'python render.py --n 1' toolu_w1
chmod a-w "$R" "$P" 2>/dev/null   # POSIX: the read-only dir blocks the lock / marker; Windows: the read-only counter file blocks os.replace
guard 'python render.py --n 1' toolu_w2
if [ -n "$OUT" ]; then case "$OUT" in *"$T_RO"*) ok "an unwritable counter -> deny: could not verify the go (the counter is not writable), 0.7.4 F3 r2: run the call again, then doctor and the read-only check";; *) ko "unwritable reason: $OUT";; esac
  endrule "... r2/r7: the unwritable-counter reason is one ASCII line, ends Nothing was spent. [rule paid], and does not send the owner to smartuse.local.md" noadapter
elif [ "$(id -u 2>/dev/null)" = 0 ]; then skip "an unwritable counter: skipped (root ignores read-only)"; else ko "an unwritable counter let the call through: '$OUT' '$ERR'"; fi
chmod u+w "$P" "$R" 2>/dev/null
[ "$(used)" = 1 ] && [ ! -e "$P/paid.toolu_w2.done" ] && ok "... nothing counted (used 1) and the claim marker released" || ko "after the unwritable deny: used $(used), $(ls "$P")"
allow "writable again: the same call passes" 'python render.py --n 1' toolu_w2
[ "$(used)" = 2 ] && ok "... used 2" || ko "used after the retry: $(used)"

# ===== 11. the lock around the read-modify-write: held -> deny (fail closed); stale -> taken over; parallel calls cannot both pass the cap
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'; mkdir -p "$P"; : > "$P/paid-runs.lock"
deny "a lock held by another call -> deny after a short wait: the counter is busy, 0.7.4 F3 r3: run this call again" 'python render.py --n 1' "$T_BUSY" toolu_l1
endrule "... r3/r7: the busy reason is one ASCII line, ends Nothing was spent. [rule paid], and does not send the owner to smartuse.local.md" noadapter
[ -e "$P/paid-runs.lock" ] && [ ! -e "$R" ] && ok "... the other holder's lock is left alone and nothing was counted" || ko "after a busy deny: $(ls "$P")"
py "$CW" age "$(wp "$P/paid-runs.lock")" 120 </dev/null
allow "a stale lock (120 s old) is taken over: the call passes" 'python render.py --n 1' toolu_l2
[ "$(used)" = 1 ] && [ ! -e "$P/paid-runs.lock" ] && ok "... counted (used 1) and the lock is released" || ko "after a stale lock: used $(used), $(ls "$P")"
ls "$P"/*.lock >/dev/null 2>&1 && ko "a lock was left after a normal call" || ok "a normal call leaves no lock behind"
fresh; mkpaid; adapter 'paid: render.py x 2, cap RM1, test ok\n'
ev() { printf '{"session_id":"sid-test","transcript_path":"%s","cwd":"%s","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":"%s"}}' "$NONE" "$PW" "$1" "$(jstr "$2")"; }
for t in a b c; do ev "toolu_p$t" 'python render.py --n 1' | py "$G" > "$D/par.$t" 2>/dev/null & done; wait
np=0; for t in a b c; do [ -s "$D/par.$t" ] && np=$((np+1)); done
[ "$np" = 1 ] && [ "$(used)" = 2 ] && ok "three parallel calls on a cap of 2: exactly two pass and one is denied (used 2)" || ko "parallel: $np denied, used $(used): $(cat "$D"/par.? 2>&1)"
cat "$D"/par.? | grep -q 'used up (2 of 2)' && ok "... the denied one says used up (2 of 2)" || ko "parallel reason: $(cat "$D"/par.? 2>&1)"

# ===== 12. INCIDENT REPLAY 2: go x 10, no test ok -> run 1 with the count at 1 passes, the second call is denied
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
allow "incident replay 2: go x 10, run 1 with --images 1 passes" 'python render.py --images 1' toolu_i1
deny "... the second call is denied: the wrong batch is one picture, not ten" 'python render.py --images 1' "the batch waits for the owner's " toolu_i2
deny "... and so is the third, whatever its flags" 'python render.py --images 6' "the batch waits for the owner's " toolu_i3
[ "$(used)" = 1 ] && ok "... used 1: one picture was made" || ko "used after the replay: $(used)"

# ===== 13. the whole sequence in one run: deny, pass, deny, test ok, pass x9, deny; paid-runs.json read after each step
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
deny "step 1: --images 6 is denied (first run must make ONE output)" 'python render.py --images 6' 'first run after the go must make ONE output' toolu_n0
[ ! -e "$R" ] && ok "... paid-runs.json does not exist yet" || ko "a counter after step 1: $(cat "$R")"
allow "step 2: --images 1 passes" 'python render.py --images 1' toolu_n1
[ "$(used)" = 1 ] && [ "$(field test_ok)" = false ] && ok "... used 1, test_ok false" || ko "after step 2: $(cat "$R")"
deny "step 3: the next call is denied (waits for test ok)" 'python render.py --images 6' "the batch waits for the owner's " toolu_n1b
[ "$(used)" = 1 ] && ok "... used still 1" || ko "after step 3: $(cat "$R")"
adapter 'paid: render.py x 10, cap RM5, test ok\n'
[ "$(used)" = 1 ] && ok "step 4: the owner adds test ok to the line (the file is not touched until the next run: used 1)" || ko "after step 4: $(cat "$R")"
for i in 2 3 4 5 6 7 8 9 10; do
  guard 'python render.py --images 6' "toolu_n$i"
  if [ -z "$OUT" ] && [ -z "$ERR" ] && [ "$(used)" = "$i" ]; then ok "step 5: run $i passes silently, used $i"; else ko "run $i: used $(used), stdout '$OUT' stderr '$ERR'"; fi
done
[ "$(nent)" = 1 ] && [ "$(field test_ok)" = true ] && ok "... still one counter, test_ok true" || ko "after the batch: $(cat "$R")"
deny "step 6: run 11 is denied: used up (10 of 10)" 'python render.py --images 6' 'the go for render.py is used up (10 of 10). Ask the owner for a new go.' toolu_n11
[ "$(used)" = 10 ] && ok "... used stays 10" || ko "after step 6: $(cat "$R")"

# ===== 14. EVERY paid script in a command needs its go (no first-match short-circuit); all are checked before any is counted
mkbatch() { printf '%s\nprint("batch")\n' "$IMP" > "$D/proj/batch.py"; }   # batch.py: names an SDK -> a second paid script
two() { # $1 = label, $2 = command: render.py has a go, batch.py has none -> denied naming batch.py, and render.py is not spent
  fresh; mkpaid; mkbatch; adapter 'paid: render.py x 10, cap RM5\n'
  deny "$1" "$2" 'no go from the owner for batch.py' toolu_two
  [ ! -e "$R" ] && ok "... nothing counted: the covered script is not spent on a denied call" || ko "a deny left a counter: $(cat "$R")"
}
two "&&: a go for render.py only -> batch.py is named and the call is denied" 'python render.py --n 1 && python batch.py'
two ";: the same" 'python render.py --n 1; python batch.py'
two "|: the same" 'python render.py --n 1 | python batch.py'
two "newline: the same" $'python render.py --n 1\npython batch.py'
two "bash -c \"a; b\": the same" 'bash -c "python render.py --n 1; python batch.py"'
two "the uncovered script first: still named" 'python batch.py && python render.py --n 1'
two "a wrapper in front of the second: still seen" 'python render.py --n 1 && timeout 60 python batch.py'
fresh; mkpaid; mkbatch; adapter 'paid:\n  - render.py x 10, cap RM5\n  - batch.py x 10, cap RM5\n'
allow "both scripts have a go: render.py --n 1 && batch.py --n 1 passes" 'python render.py --n 1 && python batch.py --n 1' toolu_bo
[ "$(nent)" = 2 ] && [ "$(grep -c '"used": 1' "$R")" = 2 ] && ok "... both counters moved: two entries, each used 1" || ko "two counters: $(cat "$R" 2>&1)"
[ -f "$P/paid.toolu_bo.done" ] && [ "$(ls "$P"/paid.toolu_bo*.done | wc -l | tr -d ' ')" = 2 ] && ok "... one claim marker per (tool_use_id, go): two" || ko "markers: $(ls "$P")"
allow "the same tool_use_id again passes and counts nothing twice" 'python render.py --n 1 && python batch.py --n 1' toolu_bo
[ "$(grep -c '"used": 1' "$R")" = 2 ] && ok "... both still used 1" || ko "after a repeated id: $(cat "$R")"
deny "a new id: run 2 of render.py waits for test ok (named)" 'python render.py --n 1 && python batch.py --n 1' "the batch waits for the owner's " toolu_bo2
[ "$(grep -c '"used": 1' "$R")" = 2 ] && ok "... and neither counter moved" || ko "after the deny: $(cat "$R")"
adapter 'paid:\n  - render.py x 10, cap RM5, test ok\n  - batch.py x 10, cap RM5, test ok\n'
allow "test ok on both lines: a new id passes" 'python render.py --n 1 ; python batch.py --n 1' toolu_bo3
[ "$(grep -c '"used": 2' "$R")" = 2 ] && ok "... both used 2 (test ok is not part of the go's id)" || ko "after test ok: $(cat "$R")"
fresh; mkpaid; mkbatch; adapter 'paid:\n  - render.py x 10, cap RM5\n  - batch.py x 10, cap RM5\n'
allow "both with a go through |" 'python render.py --n 1 | python batch.py --n 1' toolu_bp
[ "$(nent)" = 2 ] && ok "... two counters" || ko "|: $(cat "$R" 2>&1)"
fresh; mkpaid; mkbatch; adapter 'paid:\n  - render.py x 10, cap RM5\n  - batch.py x 10, cap RM5\n'
allow "both with a go through bash -c \"a; b\"" 'bash -c "python render.py --n 1; python batch.py --n 1"' toolu_bq
[ "$(nent)" = 2 ] && [ "$(grep -c '"used": 1' "$R")" = 2 ] && ok "... two counters, each used 1" || ko "bash -c: $(cat "$R" 2>&1)"
fresh; mkpaid; mkbatch; adapter 'paid:\n  - render.py x 10, cap RM5\n  - batch.py x 10, cap RM5\n'
deny "both have a go, the count flag is missing on the second: denied naming batch.py's rule" 'python render.py --n 1 && python batch.py' 'first run after the go must make ONE output' toolu_br
[ ! -e "$R" ] && ok "... and render.py is not spent" || ko "a deny left a counter: $(cat "$R")"
fresh; mkpaid; mkbatch; adapter 'paid:\n  - render.py x 10, cap RM5\n  - batch.py x 1, cap RM5, test ok\n'
allow "batch.py x 1 test ok: its one run passes" 'python batch.py --n 1' toolu_bs1
deny "render.py (fresh) with batch.py (used up) -> denied: batch.py is used up" 'python render.py --n 1 && python batch.py --n 1' 'the go for batch.py is used up (1 of 1)' toolu_bs2
[ "$(nent)" = 1 ] && ok "... and render.py was not counted (one entry: batch.py)" || ko "after a partial deny: $(cat "$R")"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'
deny "a command naming a paid host and no go, after a covered script: the host (curl) is named" "python render.py --n 1 && curl -s https://$(printf 'api.%s.com' openai)/v1/x" 'no go from the owner for curl' toolu_bt

# ===== 15. wrapper commands do not hide the script: timeout, nice, ionice, stdbuf, poetry run, pnpm exec, yarn node, caffeinate, env, ...
printf 'import OpenAI from "%s";\n' openai > "$D/proj/render.ts"; printf 'const O = require("%s");\n' openai > "$D/proj/render.js"
wrap() { # $1 = command, $2 = the script file: no go -> denied naming it; with a go -> passes and is counted
  fresh; mkpaid; deny "wrapper: $1 -> the script is seen (denied without a go)" "$1" "no go from the owner for $2" toolu_wr
  adapter "paid: $2 x 10, cap RM5, test ok\n"
  allow "... and with a go it passes" "$1" toolu_wr2
  [ "$(used)" = 1 ] && ok "... and is counted: used 1" || ko "used after a wrapped run: $(used) $(cat "$R" 2>&1)"
}
wrap 'timeout 60 python render.py --n 1' render.py
wrap 'timeout -s KILL 60 python render.py --n 1' render.py
wrap 'nice -n 10 python render.py --n 1' render.py
wrap 'nice python render.py --n 1' render.py
wrap 'ionice -c3 python render.py --n 1' render.py
wrap 'ionice -c 2 -n 7 python render.py --n 1' render.py
wrap 'stdbuf -oL python render.py --n 1' render.py
wrap 'stdbuf -o L -e0 python render.py --n 1' render.py
wrap 'poetry run python render.py --n 1' render.py
wrap 'pipenv run python render.py --n 1' render.py
wrap 'pnpm exec tsx render.ts' render.ts
wrap 'pnpm dlx tsx render.ts' render.ts
wrap 'yarn node render.js' render.js
wrap 'npm exec -- tsx render.ts' render.ts
wrap 'caffeinate python render.py --n 1' render.py
wrap 'caffeinate -t 60 -i python render.py --n 1' render.py
wrap 'env -i python render.py --n 1' render.py
wrap 'env -i FOO=1 python render.py --n 1' render.py
wrap 'env -u FOO python render.py --n 1' render.py
wrap 'nohup timeout 5 python render.py --n 1' render.py
wrap 'timeout 5 nohup python render.py --n 1' render.py
wrap 'time python render.py --n 1' render.py
fresh; mkpaid
allow "a wrapper with no script: timeout 5 sleep 1 passes" 'timeout 5 sleep 1'
allow "a wrapper around a plain script: nice -n 5 python polish.py passes" 'nice -n 5 python polish.py'
allow "a wrapper alone: env -i passes" 'env -i'
allow "a wrapper with only its own arguments: timeout 60 passes" 'timeout 60'
deny "a host behind a wrapper: timeout 5 curl <paid host>" "timeout 5 curl -s https://$(printf 'api.%s.com' openai)/v1/x" 'host api.openai.com on the command line'
allow "a mention behind a wrapper stays a mention: timeout 5 grep <paid host> src/" "timeout 5 grep -rn $(printf 'api.%s.com' openai) src/"

# ===== 16. the count rule needs plain literal arguments: $VAR, `cmd`, $(cmd), <(cmd), @file, globs are denied (fail closed)
lit() { cf "$1" "$2" deny '' "its arguments must be plain literals (seen $3"; }   # $3 empty: any token (a quoted one is JSON-escaped in the reason)
lit '$VAR after the count flag' 'python render.py --n 1 $EXTRA' '$EXTRA)'
lit '${VAR}' 'python render.py --n 1 ${EXTRA}' '${EXTRA})'
lit '$VAR glued to the value' 'python render.py --n $N' '$N)'
lit '"$VAR" in double quotes' 'python render.py --n 1 "$EXTRA"' ''
lit 'a backtick substitution' 'python render.py --n 1 `echo --n 9`' '`)'
lit '$(cmd)' 'python render.py --n 1 $(echo --n 9)' '$()'
lit '<(cmd)' 'python render.py --n 1 <(echo x)' '<()'
lit '@file (argparse fromfile)' 'python render.py --n 1 @more.txt' '@more.txt)'
lit '"@file" in quotes is still @file' 'python render.py --n 1 "@more.txt"' ''
lit 'a glob *' 'python render.py --n 1 *.png' '*.png)'
lit 'a glob ?' 'python render.py --n 1 img?.png' 'img?.png)'
lit 'a glob [' 'python render.py --n 1 img[12].png' 'img[12].png)'
lit 'inside bash -c' 'bash -c "python render.py --n 1 $EXTRA"' '$EXTRA)'
lit 'the first plain word is fine, the second is not' 'python render.py --n 1 --out a.png --extra $X' '$X)'
cf "a single-quoted \$ is literal" "python render.py --n 1 --prompt 'costs \$5'" allow
cf "a ? or * inside quotes is text, not a glob" 'python render.py --n 1 --prompt "a cat? yes*"' allow
cf "a path, a number, a hyphen word are plain" 'python render.py --n 1 --out out/a-b_c.png --seed 42' allow
cf "count none: no count rule, so no literal rule (the owner said one run is one output)" 'python render.py $EXTRA' allow 'paid: render.py x 10, cap RM5, count none\n'
cf "test ok: the same" 'python render.py --n 1 $EXTRA' allow 'paid: render.py x 3, cap RM2, test ok\n'
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'; guard 'python render.py --n 1 $EXTRA' toolu_lt
[ ! -e "$R" ] && ok "a denied literal check counts nothing" || ko "a deny left state: $(cat "$R")"

# ===== 17. a loop or repeat of a paid script is denied whatever the counter says; a loop with no paid script stays allowed
rp() { # $1 = label, $2 = command: a go that would cover it, still denied as a repeat, nothing counted
  fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
  deny "$1" "$2" 'a loop or repeat runs render.py more than once in one call; run it once per call so each run is counted.' toolu_rp
  [ ! -e "$R" ] && ok "... nothing counted" || ko "a repeat left state: $(cat "$R")"
}
rp "for loop" 'for i in 1 2 3; do python render.py --n 1; done'
rp "for loop over a glob, one line per word" $'for f in a b\ndo\n  python render.py --n 1\ndone'
rp "while loop" 'while true; do python render.py --n 1; done'
rp "while with the paid script as the condition" 'while python render.py --n 1; do sleep 1; done'
rp "until loop" 'until python render.py --n 1; do sleep 1; done'
rp "select loop" 'select x in a b; do python render.py --n 1; done'
rp "a loop after another command" 'cd . && for i in 1 2; do python render.py --n 1; done'
rp "a loop inside bash -c" 'bash -c "for i in 1 2; do python render.py --n 1; done"'
rp "a loop with a wrapper inside" 'for i in 1 2; do timeout 60 python render.py --n 1; done'
rp "xargs" 'echo 1 2 3 | xargs python render.py --n 1'
rp "xargs -n 1" 'echo 1 2 3 | xargs -n 1 python render.py --n'
rp "parallel" 'parallel python render.py --n 1 ::: a b'
rp "watch" 'watch -n 5 python render.py --n 1'
rp "named twice: ;" 'python render.py --n 1; python render.py --n 1'
rp "named twice: &&" 'python render.py --n 1 && python render.py --n 1'
rp "named twice: | " 'python render.py --n 1 | python render.py --n 1'
rp "named twice: bash -c" 'bash -c "python render.py --n 1; python render.py --n 1"'
rp "named twice, one behind a wrapper" 'python render.py --n 1 && nice python render.py --n 1'
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "a loop with no paid script stays allowed" 'for i in 1 2 3; do python polish.py --n 1; done' toolu_rq
allow "... and a loop of echo" 'for i in 1 2 3; do echo $i; done'
allow "the paid script AFTER a finished loop is one run: passes" 'for i in 1 2; do echo $i; done; python render.py --n 1' toolu_rr
[ "$(used)" = 1 ] && ok "... and counted once" || ko "after a loop then one run: $(cat "$R" 2>&1)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "the paid script BEFORE a loop is one run: passes" 'python render.py --n 1; for i in 1 2; do echo $i; done' toolu_rs
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "a plain word 'for' or 'done' in an argument is no loop" 'echo for done; python render.py --n 1' toolu_rt
fresh; mkpaid; mkbatch
adapter 'paid: render.py x 10, cap RM5, count none\n'
deny "a loop over a script with no go is a no-go first (named), not a repeat" 'for i in 1 2; do python batch.py --n 1; done' 'no go from the owner for batch.py' toolu_ru

# ===== 18. the file itself: stdlib, Python 3.9 grammar, no subprocess / network, import-free of the other hooks, exec-able, hooks.json untouched
[ "$(py "$CW" imports "$(wp "$G")" </dev/null)" = ok ] && ok "bash-guard.py: the module-level imports are 0.6.1's list, hashlib and pathlib come in only inside the paid path (no subprocess, socket, urllib, no other hook), Python 3.9 grammar" || ko "bash-guard.py imports: $(py "$CW" imports "$(wp "$G")" </dev/null 2>&1 | tail -1)"
[ "$(py "$CW" rules "$(wp "$G")" </dev/null)" = ok ] && ok "until-done.py's reuse still works: the source without main() execs silently, RULES has one name per entry, paid is a gate (GATE_NAMES), not a rule, paid_verdict exists" || ko "exec as until-done does: $(py "$CW" rules "$(wp "$G")" </dev/null 2>&1 | tail -1)"
[ "$(py "$CW" hooks "$(wp "$H/hooks.json")" </dev/null)" = ok ] && ok "hooks.json: exactly one Bash|PowerShell|Monitor PreToolUse command (bash-guard, timeout 10): no second process per shell call" || ko "hooks.json: $(py "$CW" hooks "$(wp "$H/hooks.json")" </dev/null 2>&1 | tail -1)"
CI="$H/../../../.github/workflows/ci.yml"
if [ -f "$CI" ]; then
  grep -q 'plugins/smartuse/hooks/bash-guard.py' "$CI" && grep -q 'bash plugins/smartuse/hooks/tests/paid-guard-test.sh' "$CI" && ok "ci.yml: bash-guard.py is in the py_compile step and this suite has a step of its own" || ko "ci.yml lacks bash-guard.py or the suite's step"
fi

# ===== 19. 0.7.0 F3: every reason family ends [rule paid]. paid is a named gate (GATE_NAMES), not a RULES entry and not on the floor: no ", always on"
sfx() { # $1 = label: the reason in $OUT ends with " [rule paid]" and does not say "always on"
  case "$OUT" in *' [rule paid]"}}') case "$OUT" in *"always on"*) ko "$1 -- the paid gate is not on the floor: $OUT";; *) ok "$1";; esac;; *) ko "$1 -- no [rule paid] suffix: $OUT";; esac
}
fresh; mkpaid
guard 'python render.py'; sfx "[rule paid] ends the no-go reason"
fresh; mkpaid; mkdir "$D/proj/.claude/smartuse.local.md"
guard 'python render.py'; sfx "... the could-not-verify reason"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
guard 'python render.py --images 6' toolu_s1; sfx "... the ONE output reason"
guard 'python render.py --n 1' toolu_s2
guard 'python render.py --n 1' toolu_s3; sfx "... the waits-for-test-ok reason"
fresh; mkpaid; adapter 'paid: render.py x 1, cap RM1\n'
guard 'python render.py --n 1' toolu_s4; guard 'python render.py --n 1' toolu_s5; sfx "... the used-up reason"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
guard 'for i in 1 2; do python render.py --n 1; done' toolu_s6; sfx "... the loop-or-repeat reason"

# ===== 20. level and arming (V5): strict is always on; light is armed by a paid line of the adapter (paid:, paid_scripts:, paid_hosts:, paid_free:, paid_guard: on)
inlight() { local off=${LOFF:-}; unset CLAUDE_PLUGIN_OPTION_STRICT; [ -n "$off" ] && export CLAUDE_PLUGIN_OPTION_RULES_OFF=$off; "$@"; export CLAUDE_PLUGIN_OPTION_STRICT=true; unset CLAUDE_PLUGIN_OPTION_RULES_OFF; }   # runs one helper call in light
fresh; mkpaid
inlight allow "light, no adapter: a paid script runs and nothing is printed" 'python render.py'
adapter 'check: npm test\n'
inlight allow "light, an adapter with no paid line: the same" 'python render.py'
adapter 'paid_guard: off\n'
inlight allow "light, paid_guard: off is no arming" 'python render.py'
adapter 'paid_guard: on\n'
inlight deny "light, paid_guard: on arms it: denied without a go" 'python render.py' 'no go from the owner for render.py'
adapter 'paid: polish.py x 2, cap RM1\n'
inlight deny "light, a paid: line arms it (for any script)" 'python render.py' 'no go from the owner for render.py'
adapter 'paid_scripts: polish.py\n'
inlight deny "light, a paid_scripts: line arms it" 'python render.py' 'no go from the owner for render.py'
adapter 'paid_hosts: api.example-images.test\n'
inlight deny "light, a paid_hosts: line arms it" 'python render.py' 'no go from the owner for render.py'
adapter 'paid_free: --dry-run\n'
inlight deny "light, a paid_free: line arms it" 'python render.py' 'no go from the owner for render.py'
fresh; mkpaid
deny "strict, no adapter: denied" 'python render.py' 'no go from the owner for render.py'
adapter 'paid_guard: on\n'
LOFF=paid inlight allow "light with paid named in Rules off: allowed, even armed" 'python render.py'
export CLAUDE_PLUGIN_OPTION_RULES_OFF=paid
deny "strict ignores Rules off: paid stays on" 'python render.py' 'no go from the owner for render.py'
unset CLAUDE_PLUGIN_OPTION_RULES_OFF
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
inlight allow "light, armed, with the go: the call passes silently" 'python render.py --n 1' toolu_lv1
[ "$(used)" = 1 ] && ok "... and is counted: used 1" || ko "used after a light run: $(used)"
fresh; mkpaid; adapter 'paid_guard: on\n'
r=$(py "$CW" inproc "$(wp "$G")" "$PW" deterr </dev/null 2>&1)
case "$r" in *'light '*' allow'*) ok "a forced detection error in light: the call is allowed (as every check does)";; *) ko "detection error, light: $r";; esac
case "$r" in *'strict '*' deny '*'[rule paid]'*) ok "... and in strict it denies, [rule paid]";; *) ko "detection error, strict: $r";; esac
fresh; adapter 'paid: render.py x 10, cap RM5\n'; mkpaid; mkdir -p "$HOME/.claude/smartuse/projects"; : > "$P"
inlight deny "0.7.1 F2: light, a file where the state folder goes: still a deny, naming the state folder and doctor" 'python render.py' 'could not verify the go (the state folder cannot be written); run /smartuse:doctor. Nothing was spent.' toolu_4l

# ===== 21. order (V7, V8): the paid check runs last; the counter is touched only by a call every other check allowed; one deadline
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
guard 'sudo python render.py --n 1' toolu_od1
case "$OUT" in *'bash-guard: sudo'*) ok "a command a rule denies keeps the rule's reason (sudo), not the paid reason";; *) ko "rule first: $OUT";; esac
[ ! -e "$R" ] && [ ! -e "$P/paid.toolu_od1.done" ] && ok "... and the counter is untouched" || ko "a rule deny touched the counter: $(ls "$P" 2>&1)"
fresh; mkpaid; printf 'x' > "$D/proj/notes.md"; adapter 'sources: notes.md\npublish: python render.py\npaid: render.py x 10, cap RM5, count none\n'
guard 'python render.py --n 1' toolu_od2
case "$OUT" in *'bash-guard: fresh-source'*) ok "a paid call the fresh-source gate denies gets the gate's reason";; *) ko "fresh-source first: $OUT";; esac
[ ! -e "$R" ] && [ ! -e "$P/paid.toolu_od2.done" ] && ok "... and is not counted" || ko "a fresh-source deny was counted: $(ls "$P" 2>&1)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'; mkdir -p "$P"; : > "$P/paid-runs.lock"
r=$(py "$CW" inproc "$(wp "$G")" "$PW" lock </dev/null 2>&1)
case "$r" in *'could not verify the go (the counter is busy)'*'[rule paid]'*) ok "a counter lock held past the deadline denies: could not verify the go (the counter is busy)";; *) ko "lock past the deadline: $r";; esac
case "$r" in *"$T_BUSY [rule paid]"*) ok "... 0.7.4 F3: with the busy tail (run this call again), no adapter";; *) ko "lock past the deadline, the tail: $r";; esac
dt=$(printf '%s' "$r" | awk '{print $2}'); awk -v x="$dt" 'BEGIN{exit !(x+0 < 0.8)}' && ok "... and the wait ends at the deadline (0.3 s here), not after the lock's own second: $dt s" || ko "the lock wait ran to $dt s"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
r=$(py "$CW" inproc "$(wp "$G")" "$PW" deadline </dev/null 2>&1)
case "$r" in *'could not verify the go (the hook ran past its deadline)'*'[rule paid]'*) ok "a call already seen as paid, past the hook's deadline: denied (could not verify)";; *) ko "past the deadline: $r";; esac
case "$r" in *'could not verify the go (the hook ran past its deadline); put it in .claude/smartuse.local.md. Nothing was spent. [rule paid]'*) ok "... 0.7.4 F3 r7 (pin): the deadline reason keeps its adapter tail";; *) ko "the deadline reason's tail: $r";; esac
[ ! -e "$R" ] && ok "... and nothing is counted" || ko "a deadline deny was counted: $(cat "$R")"

# ===== 22. V10: a command the guard cannot read cleanly (over the heredoc cap, or tagged by complexity()) is denied only when it also holds a paid word
PH=$(printf 'api.%s.com' openai)
mk17() { local i s=''; for i in $(seq 1 17); do s+="cat > f$i.txt <<'E$i'"$'\n'"x"$'\n'"E$i"$'\n'; done; printf '%s' "$s"; }   # 17 heredoc openers: past the scan cap (16)
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
deny "over the heredoc cap, an interpreter-read body names a paid SDK: denied (a go cannot cover a command that is not read)" "$(mk17)"$'\npython3 - <<\'EOPY\'\n'"$IMP"$'\nEOPY' 'too tangled to read'
allow "over the heredoc cap, nothing paid in it: allowed" "$(mk17)"$'\npython3 - <<\'EOPY\'\nprint(1)\nEOPY'
deny "tagged (three command substitutions) and it holds a paid host: denied" "echo \$(date) \$(pwd) \$(id) $PH" 'too tangled to read'
allow "tagged (three command substitutions) with no paid word: allowed" 'echo $(date) $(pwd) $(id)'
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "an untagged mention is still only a mention: echo <paid host>" "echo $PH" toolu_v10

# ===== 23. routes: PowerShell, a background run, a Monitor-shaped event (the field the event carries is tool_input.command)
guardx() { # $1 = tool_name, $2 = the tool_input as JSON, $3 = tool_use_id -> $OUT $ERR
  IN=$(printf '{"session_id":"sid-test","transcript_path":"%s","cwd":"%s","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"%s","tool_use_id":"%s","tool_input":%s}' "$NONE" "$PW" "$1" "${3:-toolu_x1}" "$2")
  OUT=$(printf '%s' "$IN" | py "$G" 2>"$D/err"); ERR=$(cat "$D/err")
}
tin() { printf '{"command":"%s"%s}' "$(jstr "$1")" "${2:-}"; }
dx() { # $1 = label, $2 = tool, $3 = tool_input JSON, $4 = text the reason must hold, $5 = tool_use_id
  guardx "$2" "$3" "${5:-}"
  if [ -n "$OUT" ] && [ -z "$ERR" ]; then case "$OUT" in *"bash-guard: paid call ("*"$4"*' [rule paid]"}}') ok "$1";; *) ko "$1 -- the reason lacks '$4' or its suffix: $OUT";; esac; else ko "$1 -- wanted a deny, got stdout '$OUT' stderr '$ERR'"; fi
}
ax() { # $1 = label, $2 = tool, $3 = tool_input JSON, $4 = tool_use_id
  guardx "$2" "$3" "${4:-}"; [ -z "$OUT" ] && [ -z "$ERR" ] && ok "$1" || ko "$1 -- wanted silence, got stdout '$OUT' stderr '$ERR'"
}
fresh; mkpaid
dx "PowerShell: python render.py with no go is denied" PowerShell "$(tin 'python render.py --images 6')" 'no go from the owner for render.py'
dx "PowerShell: a paid host in a URL is named" PowerShell "$(tin "Invoke-RestMethod https://$PH/v1/images")" 'host api.openai.com on the command line'
ax "PowerShell: a bare paid host as a search pattern is only a mention" PowerShell "$(tin "Select-String -Pattern $PH notes.txt")"
dx "a background run (run_in_background) is checked like any other" Bash "$(tin 'python render.py --images 6' ',"run_in_background":true')" 'no go from the owner for render.py'
dx "a Monitor event: its tool_input.command is read as a Bash command (denied without a go)" Monitor "$(tin 'python render.py --images 6' ',"description":"watch","timeout_ms":60000')" 'no go from the owner for render.py'
adapter 'paid: render.py x 10, cap RM5\n'
ax "PowerShell: with the go, run 1 (--n 1) passes" PowerShell "$(tin 'python render.py --n 1')" toolu_pw1
[ "$(used)" = 1 ] && ok "... and is counted" || ko "used after a PowerShell run: $(used)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
ax "a background run with the go passes and is counted" Bash "$(tin 'python render.py --n 1' ',"run_in_background":true')" toolu_bg1
[ "$(used)" = 1 ] && ok "... used 1" || ko "used after a background run: $(used)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
ax "a Monitor event with the go passes" Monitor "$(tin 'python render.py --n 1' ',"description":"watch","timeout_ms":60000')" toolu_mo1
[ "$(used)" = 1 ] && ok "... and is counted: used 1" || ko "used after a Monitor run: $(used)"

# ===== 24. timing, inside the process (no process start in the times): ordinary commands leave the paid path at once; a big script without a signal and one 30 KB text per pattern family stay fast
mkdir -p "$D/pt"
r=$(py "$CW" ptime "$(wp "$G")" "$(wp "$D/pt")" </dev/null 2>&1)
[ "$r" = ok ] && ok "four ordinary commands under 5 ms each, a 256 KB script with no signal under 50 ms, five 30 KB texts (dotted host run, key names, SDK imports, the segment splitter, the count-flag reader) under 1 s each" || ko "paid-path timing: $r"
[ "$(py "$CW" hostre "$(wp "$G")" </dev/null 2>&1)" = ok ] && ok "the linear host finder (a pattern that took 30 s on 28 KB of a.a.a.) gives the same matches, text and place, as the pattern it replaced: 23 short texts, subdomains, glued and look-alike hosts" || ko "host finder: $(py "$CW" hostre "$(wp "$G")" </dev/null 2>&1 | tail -1)"
# ===== 25. 0.7.0 F4b: free runs (paid_free: flags and paths), pay flags (`only` on a paid_scripts: item), entry scripts (paths and patterns). Step 1 (the folder lookup, D-YK13) is section 34; the cases here keep a script that is the file under the event's cwd
mkat() { # $1 = a path under the project (always with a folder), $2 = key | sdk | none: a script that names a paid key, a paid SDK, or nothing paid
  mkdir -p "$(dirname "$D/proj/$1")"
  case "$2" in
    key) printf 'import os\nK = os.environ["%s_API_KEY"]\nprint("check")\n' OPENAI > "$D/proj/$1";;
    sdk) printf '%s\nprint("x")\n' "$IMP" > "$D/proj/$1";;
    *) printf 'print("x")\n' > "$D/proj/$1";;
  esac
}
nostate() { [ ! -e "$P" ] && ok "$1" || ko "$1 -- state was written: $(ls "$P" 2>&1)"; }   # a free run touches nothing: no state dir at all
mkf4() { mkpaid; mkat tools/entry.py none; mkat other/entry.py none; mkat tools/x_job.py none; mkat tools/x_run.py none; mkat other/x_job.py none
  mkat tests/check_a.py key; mkat tools/check_a.py key; mkat tests/sub/check_b.py key; mkat tests/check_p.py none; mkat pay.py sdk; mkat sub/client.py sdk; }

# --- 25a. paid_free: flags. A run of a paid script whose plain literal arguments hold a free flag is free: allowed, not counted, no go needed
fresh; mkf4; adapter 'paid_free: --dry-run, --mock\n'
allow "free flag: python render.py --dry-run runs with no go, nothing printed" 'python render.py --dry-run' toolu_f1
nostate "... and writes no state (no state dir, no claim marker)"
allow "... the second listed flag (--mock) too" 'python render.py --mock --prompt cat' toolu_f2
deny "... a run with no free flag is still refused" 'python render.py --n 1' 'no go from the owner for render.py'
fresh; mkf4; adapter 'paid: render.py x 3, cap RM1, count none\npaid_free: --dry-run\n'
allow "free flag with a go: the paying run passes and counts" 'python render.py --n 1' toolu_f3
allow "... a dry run after it passes" 'python render.py --dry-run' toolu_f4
[ "$(used)" = 1 ] && ok "... and is not counted: used stays 1" || ko "used after a free run: $(used) $(cat "$R" 2>&1)"
[ ! -e "$P/paid.toolu_f4.done" ] && ok "... no claim marker for the free run" || ko "a free run left a marker: $(ls "$P")"
fresh; mkf4; adapter 'paid_free: --dry-run\n'
allow "free flag --flag=value" 'python render.py --dry-run=1' toolu_f5
allow "... a free flag in quotes (a plain literal)" 'python render.py "--dry-run"' toolu_f5b
deny "a \$VAR beside the free flag: not free" 'python render.py --dry-run $EXTRA' 'no go from the owner for render.py'
deny "a glob beside the free flag: not free" 'python render.py --dry-run *.png' 'no go from the owner for render.py'
deny "a command substitution beside the free flag: not free" 'python render.py --dry-run `echo x`' 'no go from the owner for render.py'
deny "the free flag after a bare --: not free" 'python render.py -- --dry-run' 'no go from the owner for render.py'
deny "a shortened spelling (--dry) is not the flag" 'python render.py --dry' 'no go from the owner for render.py'
deny "a look-alike (--dry-runs) is not the flag" 'python render.py --dry-runs' 'no go from the owner for render.py'
deny "a look-alike (--dry-run-x) is not the flag" 'python render.py --dry-run-x' 'no go from the owner for render.py'
deny "a free flag glued to something (--no-dry-run) is not the flag" 'python render.py --no-dry-run' 'no go from the owner for render.py'
fresh; mkf4; adapter 'paid_free: -d\n'
deny "a single-dash item is ignored: -d frees nothing" 'python render.py -d' 'no go from the owner for render.py'
fresh; mkf4; adapter 'paid_free: --dry-run\n'
allow "inside bash -c \"...\" the free flag frees" 'bash -c "python render.py --dry-run"' toolu_f6
allow "a literal loop of free runs is allowed (no hit, so no repeat)" 'for i in 1 2; do python render.py --dry-run; done' toolu_f7
allow "two free runs in one command are two free runs (no same-script-twice rule)" 'python render.py --dry-run && python render.py --dry-run' toolu_f8
nostate "... nothing written"
allow "a free run behind a wrapper (timeout 60 ...)" 'timeout 60 python render.py --dry-run' toolu_f9
deny "a tagged command (V10, three substitutions) frees nothing" 'echo $(date) $(pwd) $(id); python render.py --dry-run' 'no go from the owner for render.py'
guardx PowerShell "$(tin 'python render.py --dry-run')" toolu_f10; [ -z "$OUT" ] && [ -z "$ERR" ] && ok "the PowerShell tool: a free flag frees the same way" || ko "PowerShell free run: '$OUT' '$ERR'"
fresh; mkf4; adapter 'paid_free: --dry-run\n'
inlight allow "light, armed by paid_free: a free run passes silently" 'python render.py --dry-run' toolu_f11
inlight deny "light, armed by paid_free: a run with no free flag is refused" 'python render.py --n 1' 'no go from the owner for render.py'

# --- 25b. paid_free: paths. A script at a project-relative path that matches is free; a script that is also listed or has a go is never free by path
fresh; mkf4; adapter 'paid_free: tests/check_*.py\n'
allow "free path: tests/check_*.py frees a check that names a key" 'python tests/check_a.py' toolu_p1
nostate "... and writes no state"
deny "... the same name under tools/ is not freed" 'python tools/check_a.py' 'no go from the owner for check_a.py'
deny "... * does not cross a folder (tests/sub/check_b.py)" 'python tests/sub/check_b.py' 'no go from the owner for check_b.py'
fresh; mkf4; adapter 'paid_scripts: check_missing.py\npaid_free: tests/check_*.py\n'
deny "a script that is listed but not found is never free by path" 'python tests/check_missing.py' 'check_missing.py is in paid_scripts'
case "$PW" in [A-Za-z]:/*)   # a \ in a path needs the Windows file system rules (the same word on POSIX is an escape)
  fresh; mkf4; adapter 'paid_free: tests\\check_*.py\n'
  allow "a \\ in the item and in the script word (Windows spelling)" 'python tests\check_a.py' toolu_p2;;
*) skip "a \\ in the item and the script word: skipped (not Windows)";; esac
fresh; mkf4; adapter "paid_free: $PW/tests/check_*.py, ../tests/check_*.py, ~/tests/check_*.py\n"
deny "an absolute, a climbing and a ~ item are ignored: nothing is freed" 'python tests/check_a.py' 'no go from the owner for check_a.py'
fresh; mkf4; adapter 'paid_free: tests/check_*.py\n'
allow "the script by an absolute path inside the project is freed" "python $PW/tests/check_a.py" toolu_p3
mkdir -p "$D/elsewhere/tests"; cp "$D/proj/tests/check_a.py" "$D/elsewhere/tests/check_a.py"
deny "... one outside the project is not" "python $(wp "$D/elsewhere")/tests/check_a.py" 'no go from the owner for check_a.py'
fresh; mkf4; adapter 'paid_free: tests/*.py\n'
rm -f "$D/proj/tests/link.py"; ln -s "$D/proj/tools/check_a.py" "$D/proj/tests/link.py" 2>/dev/null
if [ -L "$D/proj/tests/link.py" ]; then
  deny "a link under tests/ to a paying script elsewhere is not freed (resolved, it is outside the pattern)" 'python tests/link.py' 'no go from the owner for link.py'
else skip "a link to a paying script: skipped (no link can be made here)"; fi
rm -f "$D/proj/tests/link.py"
fresh; mkf4; adapter 'paid_scripts: check_p.py\npaid_free: tests/check_*.py\n'
deny "a script that is also listed in paid_scripts: stays paid" 'python tests/check_p.py' 'check_p.py is in paid_scripts'
fresh; mkf4; adapter 'paid_scripts: check_p.py\npaid_free: --dry-run, tests/check_*.py\n'
allow "... a free flag still frees it" 'python tests/check_p.py --dry-run' toolu_p4
nostate "... with no state written"
fresh; mkf4; adapter 'paid: check_p.py x 3, cap RM1, count none\npaid_free: tests/check_*.py\n'
allow "a script named by a go line is not free by path: it runs on its go ..." 'python tests/check_p.py' toolu_p5
[ "$(used)" = 1 ] && ok "... and is counted: used 1" || ko "go + free path: $(cat "$R" 2>&1)"

# --- 25c. paid_scripts: items, `only`
fresh; mkf4; adapter 'paid_scripts: tools/entry.py\n'
guard 'python tools/entry.py' toolu_i0; case "$OUT" in *'entry.py is in paid_scripts'*) ok "a path item denies its script (entry.py is in paid_scripts)";; *) ko "path item: '$OUT' '$ERR'";; esac
allow "... and allows the same name in another folder" 'python other/entry.py' toolu_i1
fresh; mkf4; adapter 'paid_scripts: tools/*_job.py\n'
guard 'python tools/x_job.py' toolu_i2; case "$OUT" in *'x_job.py is in paid_scripts'*) ok "a pattern item denies a script it matches";; *) ko "pattern item: '$OUT' '$ERR'";; esac
allow "... not a script it does not match" 'python tools/x_run.py' toolu_i3
allow "... nor the same name in another folder" 'python other/x_job.py' toolu_i4
fresh; mkf4; adapter 'paid_scripts: entry.py\n'
guard 'python tools/entry.py' toolu_i5; case "$OUT" in *'entry.py is in paid_scripts'*) ok "a file-name item matches in any folder, as F3 built it (tools/)";; *) ko "name item: '$OUT' '$ERR'";; esac
guard 'python other/entry.py' toolu_i6; case "$OUT" in *'entry.py is in paid_scripts'*) ok "... and in the other folder";; *) ko "name item, other folder: '$OUT' '$ERR'";; esac
fresh; mkf4; adapter 'paid_scripts: tools\\entry.py\n'
guard 'python tools/entry.py' toolu_i7; case "$OUT" in *'entry.py is in paid_scripts'*) ok "a path item with a \\ matches the same path";; *) ko "backslash item: '$OUT' '$ERR'";; esac
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "only --pay: no flag, the run is free: allowed with no go" 'python tools/entry.py --out a.png' toolu_o1
nostate "... and writes no state"
deny "only --pay: with the flag the run is refused without a go" 'python tools/entry.py --pay' 'no go from the owner for entry.py'
deny "only: the flag with a value (--pay=yes) is the flag" 'python tools/entry.py --pay=yes' 'no go from the owner for entry.py'
deny "only: a shortened start of the flag (--pa) is the flag, a parser accepts it" 'python tools/entry.py --pa' 'no go from the owner for entry.py'
deny "only: a \$VAR with the flag absent may hold it" 'python tools/entry.py $X' 'no go from the owner for entry.py'
deny "only: a glob with the flag absent may hold it" 'python tools/entry.py *.json' 'no go from the owner for entry.py'
allow "only: a different flag is not the flag (--payload is no start of --pay)" 'python tools/entry.py --payload x' toolu_o2
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\npaid: entry.py x 3, cap RM1, count none\n'
allow "only with a go: the run without the flag is free" 'python tools/entry.py' toolu_o3
nostate "... nothing counted"
allow "only with a go: the run with the flag passes on the go" 'python tools/entry.py --pay' toolu_o4
[ "$(used)" = 1 ] && ok "... and counts: used 1" || ko "only + go: $(cat "$R" 2>&1)"
fresh; mkf4; adapter 'paid_scripts: pay.py only --pay\n'
allow "only on a script whose source holds a signal: no flag, free" 'python pay.py --n 1' toolu_o5
deny "... with the flag, the signal in the source is named" 'python pay.py --pay' 'in pay.py'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay --polish\n'
allow "several flags: none present is free" 'python tools/entry.py' toolu_o6
deny "... the second one denies" 'python tools/entry.py --polish' 'no go from the owner for entry.py'
deny "... the first one denies" 'python tools/entry.py --pay' 'no go from the owner for entry.py'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay, entry.py\n'
deny "a second item for the script without only makes it paid on every run" 'python tools/entry.py' 'no go from the owner for entry.py'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\npaid_free: --dry-run\n'
allow "a pay flag beside a free flag is free" 'python tools/entry.py --pay --dry-run' toolu_o7
nostate "... and writes no state"
for bad in 'tools/entry.py only' 'tools/entry.py only -p' 'tools/entry.py only --pay more' 'tools/entry.py only pay'; do
  fresh; mkf4; adapter "paid_scripts: $bad\n"
  deny "an item that does not parse ($bad) is paid on every run (the first word is the script)" 'python tools/entry.py' 'no go from the owner for entry.py'
done
fresh; mkf4; adapter 'paid: render.py x 3, cap RM1, only --pay\n'
allow "only on a go line is not read: the go stands and the script is paid on every run (the run counts)" 'python render.py --n 1' toolu_o8
[ "$(used)" = 1 ] && ok "... used 1" || ko "only on a go line: $(cat "$R" 2>&1)"
fresh; mkf4; adapter 'paid_scripts: tools/entry.py\n'
deny "a path item and a script word from a variable match by file name" 'python $S/entry.py' 'entry.py is in paid_scripts'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "... with only, the variable word and no flag: free" 'python $S/entry.py' toolu_o9
deny "... with the flag: refused" 'python $S/entry.py --pay' 'no go from the owner for entry.py'
fresh; mkf4; adapter 'paid_scripts: tools/missing.py only --pay\n'
deny "a script that is not found is matched by file name alone (with the flag)" 'python tools/missing.py --pay' 'no go from the owner for missing.py'

# --- 25d. one command, a free run and a paid run of one script: the count rule reads the paid run's arguments
fresh; mkf4; adapter 'paid: render.py x 3, cap RM1\npaid_free: --dry-run\n'
allow "a free run then the first paid run with --n 1: passes" 'python render.py --dry-run && python render.py --n 1' toolu_c1
[ "$(used)" = 1 ] && ok "... one run counted: used 1" || ko "free then paid: $(cat "$R" 2>&1)"
fresh; mkf4; adapter 'paid: render.py x 3, cap RM1\npaid_free: --dry-run\n'
deny "a free run then a paid run with --n 6: the count rule reads the paid run (seen --n 6)" 'python render.py --dry-run && python render.py --n 6' 'seen --n 6;' toolu_c2
[ ! -e "$R" ] && [ ! -e "$P/paid.toolu_c2.done" ] && ok "... and nothing is counted" || ko "a count-rule deny left state: $(ls "$P" 2>&1)"
fresh; mkf4; adapter 'paid: render.py x 3, cap RM1\npaid_free: --dry-run\n'
allow "a paid run first, then a free run: passes" 'python render.py --n 1 && python render.py --dry-run' toolu_c3
fresh; mkf4; adapter 'paid_free: --dry-run\n'
deny "a free run and a paid run, no go: the paid run is named" 'python render.py --dry-run; python render.py --n 1' 'no go from the owner for render.py'
fresh; mkf4; adapter 'paid: render.py x 3, cap RM1\npaid_free: --dry-run\n'
deny "two paid runs and a free one are still a repeat" 'python render.py --n 1 && python render.py --dry-run && python render.py --n 1' 'a loop or repeat runs render.py more than once'

# --- 25e. pins: what F3 did stays (no new key, or a new key with no free run)
fresh; mkf4; adapter 'paid: render.py x 3, cap RM1\n'
deny "pin: with no paid_free:, --dry-run is a paid run like any other (the count rule: no count flag)" 'python render.py --dry-run' 'first run after the go must make ONE output'
deny "pin: a mention of the script before the run is still the segment the count rule reads (F3)" 'echo render.py; python render.py --n 1' 'seen no count flag'
cf "pin: a shortened count flag on its own is refused (no count flag): --num-im 1" 'python render.py --num-im 1' deny '' 'seen no count flag'
fresh; mkf4; adapter 'paid_free: --dry-run\n'
inlight deny "pin: a paid_free: line with no free run in the command still arms light" 'python render.py --n 1' 'no go from the owner for render.py'

# ===== 26. timing for the F4b readers, inside the process: 2,000 paid_scripts: items against a 30 KB argument list, 1,000 free flags against 30 KB of free words, 1,500 distinct script runs against the items
mkdir -p "$D/ft"
r=$(py "$CW" ftime "$(wp "$G")" "$(wp "$D/ft")" </dev/null 2>&1)
[ "$r" = ok ] && ok "F4b timing: each 30 KB text is decided in under 1 s, with the verdicts the cases above show" || ko "F4b timing: $r"

# ===== 27. 0.7.0 F6: the paid check on the PowerShell tool. PGTOOL is the tool_name guard() sends (Bash unless set here); it is put back at the end. Same tables, same go, count rule, cap and F4b words as Bash
PWB=${PW//\//\\}                                    # the project path with backslashes, as Windows spells it
KN=$(printf '%s_API_KEY' OPENAI)                    # a paid key name, never spelled whole in this file
mkdir -p "$D/proj/tools"; mkat tools/entry.py none
PGTOOL=PowerShell
# --- 27a. deny: the forms of a run (no go anywhere)
fresh; mkpaid
deny "PS: run render.py for 6 images is refused exactly as through Bash" 'python render.py --images 6' 'no go from the owner for render.py'
case "$IN" in *'"tool_name":"PowerShell"'*) ok "... and the event the case sent really names the PowerShell tool";; *) ko "the PGTOOL case sent: $IN";; esac
case "$OUT" in *'[rule paid]"}}') ok "... and the reason ends [rule paid]";; *) ko "PS reason suffix: $OUT";; esac
deny "PS: a backslash path (.\\render.py as the script word of an interpreter)" 'python .\render.py --images 6' 'no go from the owner for render.py'
deny "PS: an absolute path with backslashes" "python $PWB\\render.py --images 6" 'no go from the owner for render.py'
deny "PS: a backslash path after a ; that a \\ sits against (cd <dir>\\; python render.py)" "Set-Location $PWB\\; python render.py --images 6" 'no go from the owner for render.py'
deny "PS: py -3 render.py" 'py -3 render.py --images 6' 'no go from the owner for render.py'
deny "PS: python.exe with a quoted path" "& \"$PWB\\python.exe\" render.py --images 6" 'no go from the owner for render.py'
deny "PS: the call operator before an interpreter" '& python render.py --images 6' 'no go from the owner for render.py'
deny "PS: the call operator before a script (& .\\render.py)" '& .\render.py --images 6' 'no go from the owner for render.py'
deny "PS: the call operator, quoted words" "& 'python' 'render.py' --images 6" 'no go from the owner for render.py'
deny "PS: a script block run with the call operator (& { ... })" '& { python render.py --images 6 }' 'no go from the owner for render.py'
for c in Invoke-WebRequest Invoke-RestMethod iwr irm Start-BitsTransfer curl wget INVOKE-WEBREQUEST; do
  deny "PS: $c with a paid host and no scheme is a call to it" "$c -Uri $PH/v1/images -OutFile out.json" "host $PH on the command line"
done
for c in Invoke-WebRequest Invoke-RestMethod iwr irm Start-BitsTransfer; do
  deny "PS: $c with a paid URL" "$c https://$PH/v1/images" "host $PH on the command line"
done
deny "PS: Start-Process with an interpreter and the script in -ArgumentList" 'Start-Process python -ArgumentList "render.py --images 6"' 'no go from the owner for render.py'
deny "PS: Start-Process -FilePath ... -ArgumentList array form with -Wait" 'Start-Process -FilePath python -ArgumentList render.py,--images,6 -Wait' 'no go from the owner for render.py'
deny "PS: saps (the alias) with positional words" 'saps python render.py' 'no go from the owner for render.py'
deny "PS: Start-Process on a script file" 'Start-Process -FilePath .\render.py -NoNewWindow' 'no go from the owner for render.py'
deny "PS: Start-Process with an interpreter and -c code that names an SDK" "Start-Process python -ArgumentList \"-c \`\"$IMP\`\"\"" "$IMP"
deny "PS: a host in a Start-Process argument list is a call (Start-Process is tagged: the whole text is searched)" "Start-Process curl -ArgumentList \"https://$PH/v1/images\"" "host $PH in a command that is not read cleanly"

# --- 27b. allow: mentions, a key assignment alone, a script with no signal
allow "PS: Select-String for a key name is only a mention" "Select-String -Pattern $KN notes.txt"
allow "PS: ... piped from Get-Content" "Get-Content notes.txt | Select-String -Pattern $KN"
allow "PS: Write-Host of a key name" "Write-Host \"set $KN first\""
allow "PS: Write-Output of a paid URL" "Write-Output \"see https://$PH/docs\""
allow "PS: Get-Content of a script that names an SDK (reading it is not running it)" 'Get-Content .\render.py'
allow "PS: the aliases gc, sls and write are mentions too" "gc notes.txt | sls $KN | write"
allow "PS: a key assignment alone (\$env:KEY = value) is preparation" "\$env:$KN = 'sk-x'"
allow "PS: ... without spaces, then a script that is not paid" "\$env:$KN=\"sk-x\"; python polish.py"
allow "PS: ... a value with a / in it (a base64 key)" "\$env:$KN=\"sk-a/b+c=\""
allow "PS: a script with no signal" 'python polish.py'
allow "PS: ... by a backslash path" '.\polish.py'
allow "PS: ... through the call operator" '& .\polish.py'
allow "PS: ... through Start-Process" 'Start-Process python -ArgumentList polish.py'
allow "PS: a download of a host that is not paid" 'Invoke-WebRequest -Uri example.org/x -OutFile y'
allow "PS: an ordinary command" 'Get-ChildItem -Recurse | Measure-Object'

# --- 27c. a loop is a repeat: with a go, still denied
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
rp "PS: foreach loop" 'foreach ($i in 1..3) { python render.py --n 1 }'
rp "PS: ForEach-Object after a pipe" '1..3 | ForEach-Object { python render.py --n 1 }'
rp "PS: % (the ForEach-Object alias)" '1..3 | % { python render.py --n 1 }'
rp "PS: a while loop" 'while ($true) { python render.py --n 1 }'
rp "PS: a for loop" 'for ($i = 0; $i -lt 3; $i++) { python render.py --n 1 }'
rp "PS: do ... while" 'do { python render.py --n 1 } while ($false)'
rp "PS: the .ForEach() method" '(1..3).ForEach({ python render.py --n 1 })'
rp "PS: a loop around the call operator" 'foreach ($i in 1..3) { & .\render.py --n 1 }'
rp "PS: a loop of Start-Process runs" 'foreach ($i in 1..3) { Start-Process python -ArgumentList "render.py --n 1" }'
allow "PS: a loop with no paid script is allowed" 'foreach ($i in 1..3) { Write-Host $i }' toolu_lp1
allow "PS: a loop of a script with no signal is allowed" 'foreach ($i in 1..3) { python polish.py }' toolu_lp2
allow "PS: the same script once, before a loop, is not a repeat" 'python render.py --n 1; foreach ($i in 1..3) { Write-Host $i }' toolu_lp3
[ "$(used)" = 1 ] && ok "... and it is counted once" || ko "used after the run before a loop: $(used) $(cat "$R" 2>&1)"

# --- 27d. a go, the count rule and the cap behave as through Bash: a variable or a subexpression is not a literal
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
cf "PS: --images 1 passes" 'python render.py --images 1' allow
cf "PS: --images 6 is a batch: denied" 'python render.py --images 6' deny '' 'seen --images 6;'
cf "PS: a backslash script word with --n 1 passes" 'python .\render.py --n 1' allow
cf "PS: the call operator with --n 1 passes" '& python render.py --n 1' allow
cf "PS: no count flag: denied" 'python render.py' deny '' 'seen no count flag'
lit "PS: a \$variable as the count is not a literal" 'python render.py --n $n' '$n'
lit "PS: a \$env: variable as the count is not a literal" 'python render.py --n $env:N' '$env:N'
lit "PS: a braced \${n} is not a literal" 'python render.py --n ${n}' '$'
lit "PS: a subexpression \$(1) is not a literal" 'python render.py --n $(1)' '$('
lit "PS: a splat (@args) is not a literal" 'python render.py @args' '@args'
lit "PS: a double-quoted word with a variable is not a literal" 'python render.py --prompt "a $x" --n 1' ''
cf "PS: a single-quoted word is a literal" "python render.py --prompt 'a \$x' --n 1" allow
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
allow "PS: Start-Process: run 1 with --images 1 passes" 'Start-Process python -ArgumentList "render.py --images 1"' toolu_sp1
[ "$(used)" = 1 ] && ok "... and is counted (the run is read through Start-Process)" || ko "used after Start-Process: $(used) $(cat "$R" 2>&1)"
deny "PS: Start-Process: the next run waits for test ok" 'Start-Process python -ArgumentList "render.py --images 1"' "the batch waits for the owner's " toolu_sp2
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
deny "PS: Start-Process: --images 6 is a batch, the count rule reads the argument list" 'Start-Process python -ArgumentList "render.py --images 6"' 'seen --images 6;' toolu_sp3
deny "PS: Start-Process: a variable in the argument list is not a literal" 'Start-Process python -ArgumentList "render.py --images $n"' 'must be plain literals' toolu_sp4
[ ! -e "$R" ] && ok "... and nothing was counted" || ko "a denied Start-Process run left state: $(cat "$R")"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "PS: count none: a call-operator run passes" '& .\render.py' toolu_co1
[ "$(used)" = 1 ] && ok "... counted: used 1" || ko "used after the call operator: $(used)"

# --- 27e. F4b words through PowerShell: a free flag, `only`
fresh; mkf4; adapter 'paid_free: --dry-run\n'
allow "PS: a free flag frees an interpreter run" 'python render.py --dry-run' toolu_pf1
allow "PS: ... a call-operator run" '& python render.py --dry-run' toolu_pf2
allow "PS: ... a script word with a backslash" 'python .\render.py --dry-run' toolu_pf3
nostate "... and writes no state"
deny "PS: a \$variable beside the free flag: not free" 'python render.py --dry-run $x' 'no go from the owner for render.py'
deny "PS: no free flag: refused" 'python render.py --n 1' 'no go from the owner for render.py'
deny "PS: Start-Process is tagged (V10): it frees nothing" 'Start-Process python -ArgumentList "render.py --dry-run"' 'no go from the owner for render.py'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "PS: only --pay: no flag, free (backslash path)" 'python tools\entry.py --out a.png' toolu_po1
deny "PS: only --pay: with the flag, refused" 'python tools\entry.py --pay' 'no go from the owner for entry.py'
deny "PS: only --pay: a \$variable may hold it" 'python tools\entry.py $x' 'no go from the owner for entry.py'
fresh; mkf4; adapter 'paid_free: --dry-run\n'
inlight allow "PS, light, armed by paid_free: a free run passes" 'python render.py --dry-run' toolu_pl1
inlight deny "PS, light, armed by paid_free: a call-operator run is refused" '& python render.py --n 1' 'no go from the owner for render.py'
fresh; mkpaid
inlight allow "PS, light, no paid line in the adapter: the paid path stays off" 'python render.py --n 1' toolu_pl2

# --- 27f. Bash results do not move: the same words through the Bash tool
PGTOOL=Bash
fresh; mkpaid
allow "Bash pin: a download cmdlet with a bare paid host is not a caller there" "iwr $PH/v1/images" toolu_bp1
deny "Bash pin: Select-String for a key name is still a key on the line" "Select-String -Pattern $KN notes.txt" "$KN on the command line"
deny "Bash pin: \$env:KEY = value is still a key on the line" "\$env:$KN = 'sk-x'" "$KN on the command line"
allow "Bash pin: Start-Process is not read" 'Start-Process python -ArgumentList "render.py --n 1"' toolu_bp2

# --- 27g. the F3 sequence once more with tool_name PowerShell: deny, pass, deny, test ok, pass x9, deny; paid-runs.json read after each step
PGTOOL=PowerShell
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
deny "PS step 1: --images 6 is denied (first run must make ONE output)" 'python render.py --images 6' 'first run after the go must make ONE output' toolu_q0
[ ! -e "$R" ] && ok "... paid-runs.json does not exist yet" || ko "a counter after PS step 1: $(cat "$R")"
allow "PS step 2: --images 1 passes" 'python render.py --images 1' toolu_q1
[ "$(used)" = 1 ] && [ "$(field test_ok)" = false ] && ok "... used 1, test_ok false" || ko "after PS step 2: $(cat "$R")"
deny "PS step 3: the next call is denied (waits for test ok)" 'python render.py --images 6' "the batch waits for the owner's " toolu_q1b
[ "$(used)" = 1 ] && ok "... used still 1" || ko "after PS step 3: $(cat "$R")"
adapter 'paid: render.py x 10, cap RM5, test ok\n'
[ "$(used)" = 1 ] && ok "PS step 4: the owner adds test ok to the line (used 1 until the next run)" || ko "after PS step 4: $(cat "$R")"
for i in 2 3 4 5 6 7 8 9 10; do
  guard 'python render.py --images 6' "toolu_q$i"
  if [ -z "$OUT" ] && [ -z "$ERR" ] && [ "$(used)" = "$i" ]; then ok "PS step 5: run $i passes silently, used $i"; else ko "PS run $i: used $(used), stdout '$OUT' stderr '$ERR'"; fi
done
[ "$(nent)" = 1 ] && [ "$(field test_ok)" = true ] && ok "... still one counter, test_ok true" || ko "after the PS batch: $(cat "$R")"
deny "PS step 6: run 11 is denied: used up (10 of 10)" 'python render.py --images 6' 'the go for render.py is used up (10 of 10). Ask the owner for a new go.' toolu_q11
[ "$(used)" = 10 ] && ok "... used stays 10" || ko "after PS step 6: $(cat "$R")"
PGTOOL=Bash

# ===== 28. timing for the PowerShell forms, inside the process: each 30 KB text decided in under 1 s
mkdir -p "$D/pst"
r=$(py "$CW" pstime "$(wp "$G")" "$(wp "$D/pst")" </dev/null 2>&1)
[ "$r" = ok ] && ok "F6 timing: four ordinary PowerShell commands under 5 ms each, fourteen 30 KB PowerShell texts decided in under 1 s with the verdicts the cases above show" || ko "F6 timing: $r"

# ===== 29. 0.7.0 F4b fix round (automated security review): every case here moves a run toward paid or scanned, never toward free
# --- 29a. a word that is not plain is never a free flag, and never missing from an `only` check (a backslash, a quote that is not the one outer pair, quoted text glued to other text)
fresh; mkf4; adapter 'paid_free: --dry-run\n'
allow "29a pin: the plain free flag still frees" 'python render.py --dry-run' toolu_n1
allow "29a pin: ... one outer pair of double quotes" 'python render.py "--dry-run"' toolu_n2
allow "29a pin: ... one outer pair of single quotes" "python render.py '--dry-run'" toolu_n3
deny "29a: \"--dry\"-run (quoted text glued to text) is not free" 'python render.py "--dry"-run' 'no go from the owner for render.py'
deny "29a: --dry-run\\ (a trailing backslash) is not free" 'python render.py --dry-run\' 'no go from the owner for render.py'
deny "29a: --dry\\-run (a backslash inside) is not free" 'python render.py --dry\-run' 'no go from the owner for render.py'
deny "29a: '--dry-run'x (glued after the quotes) is not free" "python render.py '--dry-run'x" 'no go from the owner for render.py'
deny "29a: \"--dry-run\"x is not free" 'python render.py "--dry-run"x' 'no go from the owner for render.py'
deny "29a: x\"--dry-run\" (glued before the quotes) is not free" 'python render.py x"--dry-run"' 'no go from the owner for render.py'
deny "29a: --dry-run\"\" (empty quotes glued on) is not free" 'python render.py --dry-run""' 'no go from the owner for render.py'
deny "29a: --dry-run'' is not free" "python render.py --dry-run''" 'no go from the owner for render.py'
deny "29a: a quote inside the outer pair is not free" "python render.py \"--dry-run'\"" 'no go from the owner for render.py'
deny "29a: a word that reads as a bare -- ends the look (\\-\\- then the flag)" 'python render.py \-\- --dry-run' 'no go from the owner for render.py'
PGTOOL=PowerShell
fresh; mkf4; adapter 'paid_free: --dry-run\n'
allow "29a PS pin: the plain free flag still frees" 'python render.py --dry-run' toolu_n4
deny "29a PS: --dry-run\\ is read with / for \\ (--dry-run/): not the flag, not free" 'python render.py --dry-run\' 'no go from the owner for render.py'
deny "29a PS: \"--dry\"-run is not free" 'python render.py "--dry"-run' 'no go from the owner for render.py'
deny "29a PS: '--dry-run'x is not free" "python render.py '--dry-run'x" 'no go from the owner for render.py'
deny "29a PS: --dry-run\"\" is not free" 'python render.py --dry-run""' 'no go from the owner for render.py'
PGTOOL=Bash
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "29a only pin: no pay flag, free" 'python tools/entry.py --out a.png' toolu_n5
allow "29a only pin: a quoted value with a blank is plain" 'python tools/entry.py --prompt "a cat" --out a.png' toolu_n6
deny "29a only: --pa\\y (the shell reads --pay) is paid" 'python tools/entry.py --pa\y' 'no go from the owner for entry.py'
deny "29a only: --pay\\ is paid" 'python tools/entry.py --pay\' 'no go from the owner for entry.py'
deny "29a only: --pay\"\" is paid" 'python tools/entry.py --pay""' 'no go from the owner for entry.py'
deny "29a only: --pa\"\"y is paid" 'python tools/entry.py --pa""y' 'no go from the owner for entry.py'
deny "29a only: --pa'y' is paid" "python tools/entry.py --pa'y'" 'no go from the owner for entry.py'
deny "29a only: '--pay'x is paid" "python tools/entry.py '--pay'x" 'no go from the owner for entry.py'
deny "29a only: \"--p\"ay is paid" 'python tools/entry.py "--p"ay' 'no go from the owner for entry.py'
deny "29a only: a Windows-looking word with a backslash may hold it" 'python tools/entry.py --out C:\x\a.png' 'no go from the owner for entry.py'
PGTOOL=PowerShell
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "29a PS only pin: no flag, free" 'python tools\entry.py --out a.png' toolu_n7
deny "29a PS only: --pa\"\"y is paid" 'python tools\entry.py --pa""y' 'no go from the owner for entry.py'
deny "29a PS only: the backtick is PowerShell's escape (--pa\`y is --pay)" 'python tools\entry.py --pa`y' 'no go from the owner for entry.py'
allow "29a PS only (pinned): a trailing \\ is read as / and is part of the word, not the flag: free" 'python tools\entry.py --pay\' toolu_n8
PGTOOL=Bash

# --- 29b. arguments from outside: under xargs / parallel / watch an `only` script is paid whatever flags it shows; a free flag still frees it
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "29b pin: the run alone, no pay flag: free" 'python tools/entry.py --out a.png' toolu_x1
deny "29b: printf -- --pay | xargs python tools/entry.py is paid" 'printf -- --pay | xargs python tools/entry.py' 'no go from the owner for entry.py'
deny "29b: echo --pay | xargs python tools/entry.py is paid" 'echo --pay | xargs python tools/entry.py' 'no go from the owner for entry.py'
deny "29b: ... with a flag that is not the pay flag" 'echo --pay | xargs python tools/entry.py --out a.png' 'no go from the owner for entry.py'
deny "29b: xargs -n 1 (options of xargs)" 'printf -- --pay | xargs -n 1 python tools/entry.py' 'no go from the owner for entry.py'
deny "29b: parallel" 'printf -- --pay | parallel python tools/entry.py' 'no go from the owner for entry.py'
deny "29b: watch" 'watch python tools/entry.py' 'no go from the owner for entry.py'
deny "29b: xargs sh -c \"...\" hands the arguments down" 'printf -- --pay | xargs sh -c "python tools/entry.py"' 'no go from the owner for entry.py'
deny "29b: timeout around xargs" 'printf -- --pay | timeout 60 xargs python tools/entry.py' 'no go from the owner for entry.py'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\npaid_free: --dry-run\n'
allow "29b: the free flag visible on the line still frees it under xargs" 'printf -- --pay | xargs python tools/entry.py --dry-run' toolu_x2
nostate "... and writes no state"
deny "29b: the free flag with a false value does not" 'printf -- --pay | xargs python tools/entry.py --dry-run=no' 'no go from the owner for entry.py'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\npaid: entry.py x 3, cap RM1, count none\n'
deny "29b: with a go, xargs is still a repeat (denied whatever the counter says)" 'printf -- --pay | xargs python tools/entry.py' 'a loop or repeat runs entry.py more than once'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "29b pin: a literal loop of runs with no pay flag is not an outside source" 'for i in 1 2; do python tools/entry.py --out a.png; done' toolu_x3

# --- 29c. after a folder change (cd, pushd, Set-Location, env -C) no paid_free: path frees a run, and a paid_scripts: path item matches by file name alone; a free flag still frees
fresh; mkf4; adapter 'paid_free: tests/check_*.py\n'
allow "29c pin: the plain run of the free path is free" 'python tests/check_a.py' toolu_m0
nostate "... and writes no state"
for c in 'cd sub && python tests/check_a.py' 'cd sub; python tests/check_a.py' 'pushd sub; python tests/check_a.py' 'cd sub || exit 1; python tests/check_a.py' 'builtin cd sub && python tests/check_a.py' 'cd sub; echo ok; python tests/check_a.py' \
         'env -C sub python tests/check_a.py' 'env --chdir=sub python tests/check_a.py' 'env --chdir sub python tests/check_a.py' 'env -Csub python tests/check_a.py' 'bash -c "cd sub && python tests/check_a.py"' \
         '(cd sub && python tests/check_a.py)' 'for d in a b; do python tests/check_a.py; cd $d; done'; do
  deny "29c: $c is not free by path" "$c" 'no go from the owner for check_a.py'
done
allow "29c pin: a cd after the run does not matter" 'python tests/check_a.py && cd sub' toolu_m1
allow "29c pin: another command that is not a folder change" 'ls sub && python tests/check_a.py' toolu_m2
fresh; mkf4; adapter 'paid_free: --dry-run, tests/check_*.py\n'
allow "29c: a free flag still frees after a cd" 'cd sub && python tests/check_a.py --dry-run' toolu_m3
nostate "... and writes no state"
fresh; mkf4; adapter 'paid_scripts: tools/entry.py\n'
allow "29c pin: a path item does not match another folder's file" 'python other/entry.py' toolu_m4
deny "29c: after a cd the path item matches by file name alone" 'cd sub && python other/entry.py' 'entry.py is in paid_scripts'
fresh; mkf4; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "29c: with only, the cd run with no flag is free" 'cd sub && python other/entry.py --out a.png' toolu_m5
deny "29c: with only, the cd run with the flag is paid (matched by name)" 'cd sub && python other/entry.py --pay' 'no go from the owner for entry.py'
PGTOOL=PowerShell
fresh; mkf4; adapter 'paid_free: tests/check_*.py\n'
allow "29c PS pin: the plain run of the free path is free" 'python tests/check_a.py' toolu_m6
for c in 'Set-Location sub; python tests/check_a.py' 'sl sub; python tests/check_a.py' 'chdir sub; python tests/check_a.py' 'cd sub; python tests/check_a.py' 'Push-Location sub; python tests/check_a.py' 'Set-Location sub && python tests/check_a.py' 'Set-Location -Path sub; python tests\check_a.py'; do
  deny "29c PS: $c is not free by path" "$c" 'no go from the owner for check_a.py'
done
PGTOOL=Bash

# --- 29d. a free flag with a value: free only as the bare word, or =1 / =true / =yes (any case)
fresh; mkf4; adapter 'paid_free: --dry-run\n'
for v in 1 true yes TRUE Yes tRuE; do
  allow "29d: --dry-run=$v is free" "python render.py --dry-run=$v" toolu_v1
done
nostate "... and writes no state"
for v in false 0 no False NO FALSE '' 2 off 11 'yes!'; do
  deny "29d: --dry-run=$v is not free" "python render.py --dry-run=$v" 'no go from the owner for render.py'
done
deny "29d: a quoted false value is not free" 'python render.py "--dry-run=false"' 'no go from the owner for render.py'
deny "29d: a false value beside another flag is not free" 'python render.py --dry-run=false --n 1' 'no go from the owner for render.py'
allow "29d: a false value and then the bare flag: the bare flag frees" 'python render.py --dry-run=false --dry-run' toolu_v2

# --- 29e. a mention, a double-quoted word or an assignment does not hide a command substitution (bash and PowerShell)
fresh; mkf4; mkplain polish
for c in 'echo "$(python render.py)"' 'git log "$(python render.py)"' 'echo $(python render.py)' '(python render.py)' 'X=$(python render.py)' 'export X="$(python render.py)"' \
         'echo `python render.py`' 'echo "`python render.py`"' 'cat "$(python render.py --n 1)" | head' 'echo "a $(echo "$(python render.py)")"' 'echo ok && (python render.py)' 'printf "%s" "$(cd sub && python render.py)"'; do
  deny "29e Bash: $c" "$c" 'no go from the owner for render.py'
done
allow "29e Bash pin: a mention with no substitution" 'echo "run python render.py later"' toolu_s1
allow "29e Bash pin: single quotes keep the substitution text" "echo 'x \$(python render.py)'" toolu_s2
allow "29e Bash pin: a commit message with backticks in single quotes" "git commit -m 'run \`python render.py\` first'" toolu_s3
allow "29e Bash pin: a substitution of a script with no signal" 'echo "$(python polish.py)"' toolu_s4
PGTOOL=PowerShell
for c in 'Write-Output "$(python render.py)"' 'Write-Host (python render.py)' 'Write-Host $(python render.py)' 'Write-Output @(python render.py)' 'gc x | % { python render.py }' \
         'Write-Host "a $(python render.py) b"' 'echo hi | Write-Output "$(& python render.py)"' 'Write-Output "$(Write-Output "$(python render.py)")"' 'Get-Content x | Write-Host (python render.py)' 'gc x | ForEach-Object { python render.py }'; do
  deny "29e PS: $c" "$c" 'no go from the owner for render.py'
done
allow "29e PS pin: a mention with no substitution" 'Write-Output "run python render.py later"' toolu_s5
allow "29e PS pin: single quotes keep the substitution text" "Write-Host 'a \$(python render.py) b'" toolu_s6
allow "29e PS pin: a substitution of a script with no signal" 'Write-Output "$(python polish.py)"' toolu_s7
PGTOOL=Bash

# --- 29f. PowerShell: only `$env:NAME = <one literal word>` is preparation; what else follows the = is scanned as a segment of its own
PGTOOL=PowerShell
fresh; mkf4
for c in '$env:X = $(python render.py)' '$env:X = (python render.py)' '$env:X = python render.py' '$env:X = "$(python render.py)"' '$x = python render.py' '[string]$x = python render.py' '$x += python render.py' \
         '$env:X = Start-Process python render.py' '$a = $b = python render.py' '$env:X = 1; $y = python render.py'; do
  deny "29f PS: $c" "$c" 'render.py'
done
allow "29f PS pin: a literal in single quotes" "\$env:X = 'abc'" toolu_e1
allow "29f PS pin: a literal in double quotes" '$env:X = "abc"' toolu_e2
allow "29f PS pin: a plain word" '$env:X = abc' toolu_e3
allow "29f PS pin: a key name is the variable, the value is a literal" "\$env:$KN = 'sk-x'" toolu_e4
allow "29f PS pin: a key name read into another variable" "\$env:X = \$env:$KN" toolu_e5
allow "29f PS pin: a read of the script is a mention" '$x = Get-Content render.py' toolu_e6
allow "29f PS pin: the variable, then a script with no signal" '$env:X = abc; python polish.py' toolu_e7
# 0.7.0 fix round 2: on the right of an = only a quoted word, a number, a $variable read and $true / $false / $null are literals; a bare word is a
# command in PowerShell ($x = .\render.py runs the script), so it is scanned as a segment (a word that names no script and no interpreter finds nothing)
for c in '$x = .\render.py' '$x = python render.py' '$x = render.py' '$env:X = .\render.py' '$env:X = render.py' '[string]$x = .\render.py' '$x += render.py' '$x = ./render.py' '$a = $b = render.py'; do
  deny "29f PS bare word: $c" "$c" 'render.py'
done
allow "29f PS bare word pin: \$env:K = 'abc'" "\$env:K = 'abc'" toolu_e8
allow "29f PS bare word pin: a number" '$n = 5' toolu_e9
allow "29f PS bare word pin: a negative decimal" '$n = -1.5' toolu_e10
allow "29f PS bare word pin: a variable read" '$y = $x' toolu_e11
allow "29f PS bare word pin: a variable read with a scope" '$y = $env:PATH' toolu_e12
allow "29f PS bare word pin: \$true" '$y = $true' toolu_e13
allow "29f PS bare word pin: \$false" '$y = $false' toolu_e14
allow "29f PS bare word pin: \$null" '$y = $null' toolu_e15
allow "29f PS bare word pin: a double-quoted word" '$y = "abc"' toolu_e16
allow "29f PS bare word pin: a word that names no script and no interpreter" '$x = hello' toolu_e17
allow "29f PS bare word pin: ... then a script with no signal" '$x = hello; python polish.py' toolu_e18
PGTOOL=Bash

# --- 29g. PowerShell Start-Process: a word starting with - is never the program; parameters resolve by unique prefix; what cannot be read fails closed
PGTOOL=PowerShell
fresh; mkf4; mkplain polish
for c in 'Start-Process -Wa python render.py' 'Start-Process -FilePath:python render.py' 'Start-Process -ErrorAction Stop python render.py' 'Start-Process -Verb RunAs python render.py' \
         'Start-Process -Wai -NoNew python render.py' 'Start-Process -File python -Arg render.py' 'Start-Process -Wait -PassThru -FilePath python -ArgumentList render.py' '$p = Start-Process python render.py -PassThru'; do
  deny "29g PS: $c" "$c" 'render.py'
done
for c in 'Start-Process -Foo bar python render.py' 'Start-Process -Foo python render.py' 'Start-Process python polish.py -Foo' 'Start-Process -W python polish.py' 'Start-Process -FilePath -Foo python polish.py' 'Start-Process -Verbose:python python polish.py -Bar' \
         'Start-Process -- python polish.py' 'Start-Process -X python polish.py' 'saps -Foo python polish.py' 'start -Foo python polish.py'; do
  deny "29g PS: $c (not read cleanly)" "$c" 'too tangled to read'
done
allow "29g PS pin: a unique prefix (-Wai is -Wait)" 'Start-Process -Wai python polish.py' toolu_t1
allow "29g PS pin: -NoNew and -Arg prefixes" 'Start-Process -NoNew python -Arg polish.py' toolu_t2
allow "29g PS pin: common parameters (-ErrorAction Stop)" 'Start-Process -ErrorAction Stop python polish.py' toolu_t3
allow "29g PS pin: -ea alias, -WhatIf switch" 'Start-Process -ea Stop -WhatIf python polish.py' toolu_t4
allow "29g PS pin: -WorkingDirectory and -Verb" 'Start-Process python -ArgumentList polish.py -WorkingDirectory sub -Verb Open' toolu_t5
allow "29g PS pin: an unknown parameter with a program that is no interpreter" 'Start-Process -Foo notepad; python polish.py' toolu_t6
PGTOOL=Bash

# --- 29h. repeat detection in PowerShell: a script block after a pipe or a switch, Where-Object, ?, .Where(), the cmdlets that run a block (a go still denies it)
PGTOOL=PowerShell
rp "29h PS: Where-Object" '1..3 | Where-Object { python render.py --n 1 }'
rp "29h PS: ? (the Where-Object alias)" '1..3 | ? { python render.py --n 1 }'
rp "29h PS: where (the alias)" 'Get-ChildItem | Where { python render.py --n 1 }'
rp "29h PS: the .Where() method" '(1..3).Where({ python render.py --n 1 })'
rp "29h PS: the .where() method, lower case" '(1..3).where({ python render.py --n 1 })'
rp "29h PS: switch" 'switch (1) { 1 { python render.py --n 1 } }'
rp "29h PS: switch with options" 'switch -Regex ($x) { "a" { python render.py --n 1 } }'
rp "29h PS: a variable set from a switch" '$r = switch (1) { 1 { python render.py --n 1 } }'
rp "29h PS: Sort-Object with a script block" '1..3 | Sort-Object { python render.py --n 1 }'
rp "29h PS: Group-Object with a script block" '1..3 | Group-Object { python render.py --n 1 }'
rp "29h PS: Select-Object with a calculated property" "1..3 | Select-Object @{n='a'; e={ python render.py --n 1 }}"
rp "29h PS: Format-Table with a calculated property" '1..3 | Format-Table { python render.py --n 1 }'
rp "29h PS: a cmdlet the guard has never heard of, a block after a pipe" '1..3 | Foo-Bar { python render.py --n 1 }'
rp "29h PS: ... inside an if block" 'if ($true) { 1..3 | Foo-Bar { python render.py --n 1 } }'
rp "29h PS: ... after several pipes" 'Get-Date | Get-Member | Foo-Bar -x { python render.py --n 1 }'
rp "29h PS: ForEach-Object -Parallel" '1..3 | ForEach-Object -Parallel { python render.py --n 1 }'
rp "29h PS: Invoke-Command" 'Invoke-Command -ScriptBlock { python render.py --n 1 }'
rp "29h PS: icm" 'icm { python render.py --n 1 }'
rp "29h PS: Start-Job" 'Start-Job { python render.py --n 1 }'
rp "29h PS: Start-ThreadJob" 'Start-ThreadJob -ScriptBlock { python render.py --n 1 }'
rp "29h PS: Register-ObjectEvent -Action" 'Register-ObjectEvent $w Changed -Action { python render.py --n 1 }'
rp "29h PS: the earlier forms stay: ForEach-Object" '1..3 | ForEach-Object { python render.py --n 1 }'
rp "29h PS: the earlier forms stay: foreach" 'foreach ($i in 1..3) { python render.py --n 1 }'
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "29h PS pin: a pipe with no block, then one run" 'Get-ChildItem | Sort-Object Name; python render.py --n 1' toolu_h1
[ "$(used)" = 1 ] && ok "... counted once" || ko "29h pin: $(cat "$R" 2>&1)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "29h PS pin: a block that is not after a pipe, one run" 'if ($true) { python render.py --n 1 }' toolu_h2
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "29h PS pin: the run comes before the block after a pipe" 'python render.py --n 1; 1..3 | Where-Object { $_ -gt 1 }' toolu_h3
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
allow "29h PS pin: a mention of Where-Object is not a loop" 'Get-Help Where-Object; python render.py --n 1' toolu_h4
PGTOOL=Bash

# ===== 30. timing for the F4b fix readers (folder changes, glued words, substitutions in mentions, assignments, Start-Process parameters, script blocks), inside the process: each 30 KB text decided in under 1 s
mkdir -p "$D/fx"
r=$(py "$CW" fxtime "$(wp "$G")" "$(wp "$D/fx")" </dev/null 2>&1)
[ "$r" = ok ] && ok "F4b fix timing: each 30 KB text (cd lists, glued quoted words, substitutions in mentions, nested substitutions, assignment chains, Start-Process parameters, script blocks after pipes; 0.7.0 review fix: 24 KB of runner words in Bash and PowerShell, 1,700 inline keys, with and without env) is decided in under 1 s with the verdict the cases above show" || ko "F4b fix timing: $r"

# ===== 31. 0.7.0 F8: a quote in a # comment no longer hides the lines after it (strip_comments reads the text the paid scan reads)
# a paid run between two comments that hold an apostrophe each: the two quotes used to pair up and the run between them was read as text
fresh; mkpaid
deny "31 a paid run between two comments with an apostrophe each, no go -> denied" $'# it\'s ready\npython render.py --n 1\n# check the PR\'s status' 'no go from the owner for render.py' toolu_f8a
[ ! -e "$P" ] && ok "... and a deny writes nothing" || ko "31: state was written: $(ls "$P" 2>&1)"
deny "31 the comment starts after a semicolon" $'echo a; # it\'s ready\npython render.py --n 1\n# check the PR\'s status' 'no go from the owner for render.py' toolu_f8b
deny "31 the comment starts after &&" $'echo a && # it\'s ready\npython render.py --n 1\n# check the PR\'s status' 'no go from the owner for render.py' toolu_f8c
deny "31 the comment starts after a pipe" $'echo a | # it\'s ready\npython render.py --n 1\n# check the PR\'s status' 'no go from the owner for render.py' toolu_f8d
deny "31 the comment starts after a parenthesis" $'( # it\'s ready\npython render.py --n 1\n# check the PR\'s status\n)' 'no go from the owner for render.py' toolu_f8e
deny "31 the comment follows a command on its line" $'echo a # it\'s ready\npython render.py --n 1\n# check the PR\'s status' 'no go from the owner for render.py' toolu_f8f
deny "31 a # that is text (single quotes) hides nothing" "echo 'a # b'; python render.py --n 1" 'no go from the owner for render.py' toolu_f8g
deny "31 a # that is text (double quotes) hides nothing" 'echo "a # b"; python render.py --n 1' 'no go from the owner for render.py' toolu_f8h
deny "31 a # that is text (\$#, a#b, a URL fragment) hides nothing" 'echo $# a#b https://h/p#frag; python render.py --n 1' 'no go from the owner for render.py' toolu_f8i
deny "31 a # inside a substitution in double quotes hides nothing" 'echo "$(echo "a #b")"; python render.py --n 1' 'no go from the owner for render.py' toolu_f8j
adapter 'paid: render.py x 10, cap RM5, test ok\n'
allow "31 the same run between comments, with a go, passes" $'# it\'s ready\npython render.py --n 1\n# check the PR\'s status' toolu_f8k
[ "$(used)" = 1 ] && ok "... and is counted: used 1" || ko "31 used after a run between comments: $(used) $(cat "$R" 2>&1)"
# a comment that names the script is text, and a script with no paid signal is free between comments
fresh; mkpaid; mkplain polish
allow "31 a comment that names the paid script is no run" $'# it\'s ready: python render.py --n 1 later\npython polish.py\n# check the PR\'s status' toolu_f8l
allow "31 a free script between comments is free" $'# it\'s ready\npython polish.py\n# check the PR\'s status' toolu_f8m
nostate "31 ... and touches no state"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'
allow "31 pin: a multi-line commit message with a # line and an apostrophe still runs" $'git commit -m "fix the parser\n# it\'s a heading\nmore text"' toolu_f8n
allow "31 pin: a paid word inside such a message is text, not a run" $'git commit -m "a\n# it\'s\npython render.py --n 1\n# don\'t\nb"' toolu_f8o
nostate "31 ... and touches no state"

# ===== 32. 0.7.0 review fix round (dev-flow phase 7). M1: pdm / hatch / rye / pixi / conda / op / dotenv / doppler `run` unwrap to the command they run (as poetry run does), Bash and PowerShell
for c in 'pdm run python render.py --n 1' 'hatch run python render.py --n 1' 'hatch run test:python render.py --n 1' 'rye run python render.py --n 1' 'pixi run python render.py --n 1' 'pixi run -e dev python render.py --n 1' \
         'conda run python render.py --n 1' 'conda run -n myenv python render.py --n 1' 'conda run -p /opt/envs/x python render.py --n 1' 'conda run --no-capture-output -n myenv python render.py --n 1' \
         'op run -- python render.py --n 1' 'op run --env-file=.env -- python render.py --n 1' 'op run --env-file .env -- python render.py --n 1' 'dotenv run -- python render.py --n 1' 'dotenv run python render.py --n 1' \
         'doppler run -- python render.py --n 1' 'doppler run -p proj -c dev -- python render.py --n 1' 'timeout 60 pdm run python render.py --n 1' 'pdm run timeout 60 python render.py --n 1'; do
  wrap "$c" render.py
done
fresh; mkpaid; mkplain polish
for c in 'pdm run python polish.py' 'pdm run pytest' 'hatch run python polish.py' 'hatch run test:pytest' 'rye run python polish.py' 'pixi run python polish.py' 'conda run -n myenv python polish.py' 'op run -- python polish.py' \
         'dotenv run -- python polish.py' 'doppler run -- python polish.py' 'doppler run -p proj -c dev -- python polish.py' 'pdm run' 'op run --' 'conda run -n myenv' 'pdm install' 'conda install x'; do
  allow "32 M1: a runner around a script with no paid signal passes: $c" "$c"
done
nostate "32 M1: ... and those touch no state"
fresh; mkpaid; adapter 'paid: polish.py x 3, cap RM2\n'
deny "32 M1: a go for another script does not cover the one behind the runner" 'pdm run python render.py --n 1' 'no go from the owner for render.py'
PGTOOL=PowerShell
for c in 'pdm run python render.py --n 1' 'hatch run python render.py --n 1' 'rye run python render.py --n 1' 'pixi run python render.py --n 1' 'conda run -n myenv python render.py --n 1' 'op run -- python render.py --n 1' 'dotenv run -- python render.py --n 1' \
         'doppler run -- python render.py --n 1'; do
  wrap "$c" render.py
done
fresh; mkpaid; mkplain polish
for c in 'pdm run python polish.py' 'conda run -n myenv python polish.py' 'op run -- python polish.py' 'doppler run -- python polish.py' 'dotenv run -- python polish.py'; do
  allow "32 M1 PS: a runner around a script with no paid signal passes: $c" "$c"
done
PGTOOL=Bash
# m5: a key spelled in front of the command (NAME=value, or after env) is preparation: the script is read as usual and the go is matched by its name; the key still makes the run paid
KEYN=$(printf '%s_API_KEY' OPENAI)
fresh; printf 'print("x")\n' > "$D/proj/render.py"; mkplain polish
deny "32 m5: KEY=x python render.py, no go -> denied, naming render.py (not python)" "$KEYN=x python render.py --n 1" 'no go from the owner for render.py'
deny "32 m5: ... the signal named is the key" "$KEYN=x python render.py --n 1" "$KEYN on the command line) "
deny "32 m5: env KEY=x python render.py, no go -> denied, naming render.py" "env $KEYN=x python render.py --n 1" 'no go from the owner for render.py'
deny "32 m5: KEY=x timeout 5 python render.py, no go -> denied, naming render.py" "$KEYN=x timeout 5 python render.py --n 1" 'no go from the owner for render.py'
deny "32 m5: KEY=x python polish.py (a script with no signal of its own) -> denied, naming polish.py" "$KEYN=x python polish.py" 'no go from the owner for polish.py'
deny "32 m5: KEY=x python -c (no script file) still names the command word" "$KEYN=x python -c 'print(1)'" 'no go from the owner for python'
nostate "32 m5: ... and no deny wrote state"
adapter 'paid: polish.py x 3, cap RM2\n'
deny "32 m5: a go for another script does not cover render.py" "$KEYN=x python render.py --n 1" 'no go from the owner for render.py'
adapter 'paid: render.py x 10, cap RM5, test ok\n'
allow "32 m5: with a go for render.py, KEY=x python render.py passes" "$KEYN=x python render.py --n 1" toolu_m5a
[ "$(used)" = 1 ] && ok "... and is counted once: used 1" || ko "32 m5 used: $(used) $(cat "$R" 2>&1)"
allow "32 m5: env KEY=x python render.py passes with the same go" "env $KEYN=x python render.py --n 1" toolu_m5b
[ "$(used)" = 2 ] && ok "... and is counted: used 2" || ko "32 m5 used after env: $(used) $(cat "$R" 2>&1)"
allow "32 m5: KEY=x pdm run python render.py passes with the same go" "$KEYN=x pdm run python render.py --n 1" toolu_m5c
fresh; printf 'print("x")\n' > "$D/proj/render.py"; adapter 'paid: render.py x 3, cap RM2\n'
deny "32 m5: the count rule still reads the run: the first run with no count flag is denied" "$KEYN=x python render.py --images 6" 'must make ONE output' toolu_m5e
allow "32 m5: ... and the first run with one output passes: KEY=x python render.py --n 1" "$KEYN=x python render.py --n 1" toolu_m5d
# m7: a script that exists but cannot be opened is read as no signal; in strict that is "could not verify", in light it stays allowed
fresh; mkplain polish; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
r=$(py "$CW" inproc "$(wp "$G")" "$PW" unread </dev/null 2>&1)
case "$r" in *'strict '*' deny bash-guard: could not verify whether polish.py pays'*'it could not be read'*'Make it readable, or run it in light mode.'*'Nothing was spent.'*'[rule paid]'*) ok "32 m7: strict, a script whose read fails -> denied: could not verify whether polish.py pays (make it readable, or light mode)";; *) ko "32 m7 strict: $r";; esac
case "$r" in *'paid call'*|*'smartuse.local.md'*) ko "32 m7: the reason must not say 'paid call' nor point to the adapter (no go clears it): $r";; *) ok "32 m7: ... and it names no go (no 'paid call', no adapter file)";; esac
case "$r" in *'light '*' allow'*) ok "32 m7: light, the same script -> allowed (as before)";; *) ko "32 m7 light: $r";; esac
[ ! -e "$R" ] && ok "32 m7: ... and nothing is counted" || ko "32 m7: state was written: $(cat "$R")"

# ===== 33. 0.7.0 review fix round 2. A runner's own options before `run` (hatch -e test run, dotenv -f .env run, op --account me run --, doppler --token x run --) are skipped, with an option's value
R1OPT=('hatch -e test run python render.py --n 1' 'dotenv -f .env.local run python render.py --n 1' 'op --account me run -- python render.py --n 1' 'doppler --token x run -- python render.py --n 1' 'pdm -v run python render.py --n 1' 'poetry -q run python render.py --n 1')
for c in "${R1OPT[@]}"; do wrap "$c" render.py; done
PGTOOL=PowerShell
for c in "${R1OPT[@]}"; do wrap "$c" render.py; done
fresh; mkpaid; mkplain polish
for c in 'hatch -e test run pytest' 'hatch -e test run python polish.py' 'dotenv -f .env.local run python polish.py' 'op --account me run -- python polish.py' 'doppler --token x run -- python polish.py'; do
  allow "33 PS: a runner with options before run, around a script with no paid signal, passes: $c" "$c"
done
PGTOOL=Bash
for c in 'hatch -e test run pytest' 'hatch -e test run python polish.py' 'dotenv -f .env.local run python polish.py' 'op --account me run -- python polish.py' 'doppler --token x run -- python polish.py'; do
  allow "33: a runner with options before run, around a script with no paid signal, passes: $c" "$c"
done
nostate "33: ... and those touch no state"
# a folder flag before run is a recorded limit (SECURITY.md): the run is in another folder, the guard does not unwrap it
allow "33 limit: pdm -p sub run python render.py is not unwrapped (a folder flag)" 'pdm -p sub run python render.py --n 1'

# ===== 34. 0.7.0 F4b step 1, the folder lookup (V17, D-YK13): a relative script word is looked for under the event's cwd and under each folder that a plain word before it names (chained in command order, handed down into bash -c); every file found is read. Not followed: a folder from a variable, a substitution or a glob; a folder the command creates; cd -
mkl() { mkf4; mkat polish/gemini_client.py key; mkat chain/inner/x.py sdk; mkat tests/check_a.py none; mkat polish/dup.py key; mkat dup.py none; mkat dup2.py sdk; mkat polish/dup2.py none; mkat other/notpaid.py none; mkat hold/z.py sdk; }
# --- 34a. no go: a run after a folder change is read in the folder it names, Bash tool
fresh; mkl
for c in 'cd polish && python gemini_client.py' 'cd polish; python gemini_client.py' 'cd ./polish && python gemini_client.py' 'cd polish || exit 1; python gemini_client.py' 'pushd polish; python gemini_client.py' 'pushd polish && python gemini_client.py && popd' \
         'Set-Location polish; python gemini_client.py' 'cd polish && python ./gemini_client.py' '(cd polish && python gemini_client.py)' 'env -C polish python gemini_client.py' 'env --chdir=polish python gemini_client.py' \
         'cd polish && python gemini_client.py --n 1' 'cd polish && cd . && python gemini_client.py' 'cd chain && cd inner && python x.py' 'cd chain; cd inner; python x.py' \
         'bash -c "cd polish && python gemini_client.py"' 'cd polish && bash -c "python gemini_client.py"' 'bash -c "cd chain && cd inner && python x.py"' 'cd chain && bash -c "cd inner && python x.py"' \
         'tool --dir=polish; python gemini_client.py' 'ls polish && python gemini_client.py' 'cd sub && python ../render.py' 'cd polish && python dup.py' 'cd polish && python dup2.py' 'cd hold && python z.py'; do
  deny "34a: $c" "$c" 'no go from the owner for'
done
deny "34a: the reason names the file, not the folder" 'cd polish && python gemini_client.py' 'no go from the owner for gemini_client.py'
deny "34a: ... and the signal is the one in that file" 'cd polish && python gemini_client.py' "OPENAI_API_KEY in gemini_client.py"
deny "34a: a newline between the cd and the run" $'cd polish\npython gemini_client.py' 'no go from the owner for gemini_client.py'
deny "34a: popd after the run does not hide it" 'pushd polish && python gemini_client.py; popd' 'no go from the owner for gemini_client.py'
nostate "34a: ... and no deny wrote state"
# --- 34b. pins: what the lookup does not change
allow "34b pin: the script is not in the cwd and no word names a folder" 'python gemini_client.py' toolu_l0
allow "34b pin: a cd after the run is not before it" 'python gemini_client.py && cd polish' toolu_l1
deny "34b pin: a path from the cwd is read as before" 'python polish/gemini_client.py' 'no go from the owner for gemini_client.py'
deny "34b pin: a script in the cwd is read as before, with a cd to a folder that has none of that name" 'cd other && python render.py --n 1' 'no go from the owner for render.py'
allow "34b pin: a folder with no paid script of that name" 'cd other && python notpaid.py' toolu_l2
allow "34b pin: a missing script, and the folder only after it" 'python render_missing.py polish/gemini_client.py' toolu_l3
nostate "34b: ... pins write no state"
# --- 34c. allowed: no signal in the file, a missing folder, and the stated limits (a variable, a glob, cd -, a folder the command creates, a folder beyond 6 / 64 words)
fresh; mkl
allow "34c: cd tests && python check_a.py (no signal in tests/check_a.py)" 'cd tests && python check_a.py' toolu_l4
allow "34c: a missing folder" 'cd nowhere && python gemini_client.py' toolu_l5
allow "34c limit: a folder from a variable is not followed" 'D=polish; cd $D && python gemini_client.py' toolu_l6
allow "34c limit: ... in double quotes" 'D=polish; cd "$D" && python gemini_client.py' toolu_l7
allow "34c limit: ... in braces" 'cd ${D:-x} && python gemini_client.py' toolu_l8
allow "34c limit: a glob is not followed" 'cd pol* && python gemini_client.py' toolu_l9
allow "34c limit: a ? glob" 'cd polis? && python gemini_client.py' toolu_l10
allow "34c limit: cd - is not followed" 'cd - && python gemini_client.py' toolu_l11
allow "34c limit: a folder the command makes is not followed" 'mkdir newdir && cd newdir && python gemini_client.py' toolu_l12
nostate "34c: ... and none of them wrote state"
adapter 'paid_scripts: gemini_client.py\n'
deny "34c: a script listed by file name is still caught after a folder from a variable" 'D=polish; cd $D && python gemini_client.py' 'gemini_client.py is in paid_scripts'
fresh; mkl; adapter 'paid_scripts: tests/check_a.py\n'
allow "34c: a path item of another folder does not match" 'cd other && python notpaid.py' toolu_l13
# --- 34d. with a go for gemini_client.py: allowed after the folder change and counted once; a free flag frees the dry run
fresh; mkl; adapter 'paid: gemini_client.py x 3, cap RM1, count none, test ok\n'
allow "34d: with a go, cd polish && python gemini_client.py passes" 'cd polish && python gemini_client.py --n 1' toolu_g1
[ "$(used)" = 1 ] && ok "... and is counted once: used 1" || ko "34d used: $(used) $(cat "$R" 2>&1)"
allow "34d: pushd form, a second run" 'pushd polish; python gemini_client.py --n 1' toolu_g2
[ "$(used)" = 2 ] && ok "... counted: used 2" || ko "34d used 2: $(used) $(cat "$R" 2>&1)"
allow "34d: inside bash -c" 'bash -c "cd polish && python gemini_client.py --n 1"' toolu_g3
[ "$(used)" = 3 ] && ok "... counted: used 3" || ko "34d used 3: $(used) $(cat "$R" 2>&1)"
deny "34d: the run after the cap is denied" 'cd polish && python gemini_client.py --n 1' 'gemini_client.py'
fresh; mkl; adapter 'paid_free: --dry-run\n'
allow "34d: the dry run after cd is free, no go" 'cd polish && python gemini_client.py --dry-run' toolu_g4
allow "34d: ... pushd" 'pushd polish; python gemini_client.py --dry-run=1' toolu_g5
allow "34d: ... inside bash -c" 'bash -c "cd polish && python gemini_client.py --dry-run"' toolu_g6
nostate "34d: ... and writes no state"
deny "34d: the paying run after it is not free" 'cd polish && python gemini_client.py --dry-run && cd polish && python gemini_client.py' 'no go from the owner for gemini_client.py'
fresh; mkl; adapter 'paid: gemini_client.py x 3, cap RM1, count none\npaid_free: --dry-run\n'
allow "34d: with a go, the dry run is free" 'cd polish && python gemini_client.py --dry-run' toolu_g7
[ ! -e "$R" ] && ok "... and the counter is untouched" || ko "34d dry run wrote $(cat "$R")"
allow "34d: then the paying run counts" 'cd polish && python gemini_client.py --n 1' toolu_g8
allow "34d: a dry run after it is not counted" 'cd polish && python gemini_client.py --dry-run' toolu_g9
[ "$(used)" = 1 ] && ok "... used stays 1" || ko "34d used after dry: $(used) $(cat "$R" 2>&1)"
# --- 34e. a free path and an `only` item after a folder change (a free path holds when every found file lies in the project and matches it, as written and resolved; the file the guard finds under the cwd after a folder change is not evidence, see 35b)
fresh; mkl; mkat tests/check_a.py key; adapter 'paid_free: tests/check_*.py\n'
allow "34e pin: the plain run of the free path is free" 'python tests/check_a.py' toolu_p0
allow "34e: cd tests && python check_a.py, the one file found in tests/ matches the free path: free after cd" 'cd tests && python check_a.py' toolu_p1a
allow "34e: a plain word that names the folder (no cd): the file found there matches the free path: free" 'ls tests && python check_a.py' toolu_p1b
nostate "34e: ... and writes no state"
fresh; mkl; adapter 'paid_scripts: tools/entry.py only --pay\n'
allow "34e: only, the run after cd with no flag is free" 'cd tools && python entry.py --out a.png' toolu_p1
deny "34e: only, the run after cd with the flag is paid" 'cd tools && python entry.py --pay' 'no go from the owner for entry.py'
deny "34e: only, a folder word without cd and the flag: found in another folder, matched by file name" 'ls tools && python entry.py --pay' 'no go from the owner for entry.py'
# --- 34f. PowerShell tool: a \ in a folder or script word reads as /
PGTOOL=PowerShell
fresh; mkl
for c in 'Set-Location polish; python gemini_client.py' 'Set-Location -Path .\polish; python gemini_client.py' 'Push-Location polish; python gemini_client.py' 'pushd polish; python gemini_client.py' 'cd polish; python gemini_client.py' 'cd .\polish; python .\gemini_client.py' \
         'sl polish; python gemini_client.py' 'Set-Location polish && python gemini_client.py' 'cd chain; cd inner; python x.py' 'cd .\chain; cd .\inner; python x.py' 'cd chain\inner; python x.py' 'Set-Location -LiteralPath .\chain\inner; python x.py' \
         'bash -c "cd polish && python gemini_client.py"' 'cd polish; bash -c "python gemini_client.py"' 'cd polish; python polish\gemini_client.py' 'cd chain; python inner\x.py' 'cd sub; python ..\render.py'; do
  deny "34f PS: $c" "$c" 'no go from the owner for'
done
allow "34f PS pin: no folder is named" 'python gemini_client.py' toolu_q0
allow "34f PS: cd tests; python check_a.py (no signal)" 'cd tests; python check_a.py' toolu_q1
allow "34f PS: a missing folder" 'Set-Location nowhere; python gemini_client.py' toolu_q2
allow "34f PS limit: a variable folder" 'Set-Location $d; python gemini_client.py' toolu_q3
allow "34f PS limit: a wildcard folder" 'Set-Location pol*; python gemini_client.py' toolu_q4
nostate "34f PS: ... no state"
fresh; mkl; adapter 'paid: gemini_client.py x 3, cap RM1, count none\npaid_free: --dry-run\n'
allow "34f PS: with a go, Set-Location polish; python gemini_client.py passes" 'Set-Location polish; python gemini_client.py --n 1' toolu_q5
[ "$(used)" = 1 ] && ok "... and is counted once: used 1" || ko "34f used: $(used) $(cat "$R" 2>&1)"
allow "34f PS: the dry run after Set-Location is free and not counted" 'Set-Location polish; python gemini_client.py --dry-run' toolu_q6
[ "$(used)" = 1 ] && ok "... used stays 1" || ko "34f used after dry: $(used) $(cat "$R" 2>&1)"
PGTOOL=Bash
# --- 34g. timing, inside the process: 64 folder words before a script, a 30 KB text, many words and runs; the ~ folder
mkdir -p "$D/lt"
r=$(py "$CW" ltime "$(wp "$G")" "$(wp "$D/lt")" </dev/null 2>&1)
[ "$r" = ok ] && ok "34g folder lookup timing: 64 folder words before a script, the 6-folder cap, 3,000 words, 30 KB of cd words, runs with 64 words each, a missing folder, PowerShell, nested bash -c and ~ are each decided in under 1 s with the verdict the cases above show" || ko "34g folder lookup timing: $r"

# ===== 35. step 1 fix round (re-check). 35a: a paid_scripts: path item is matched against the files the lookup found (the file name alone only when none was found); a found file the item does not cover gets no `only` freedom. 35b: a paid_free: path frees a run when every found file lies in the project and matches it. 35c: PowerShell -Path:value
mk35() { mkl; mkat polish/client.py key; mkat tools/client.py none; mkat tests/check_a.py key; }
# --- 35a. the item names tools/client.py; the key is in polish/client.py
fresh; mk35; adapter 'paid_scripts: tools/client.py only --pay\n'
for c in 'cd polish && python client.py' 'cd polish; python client.py --out a.png' 'pushd polish; python client.py' 'cd polish && python client.py --pay' '(cd polish && python client.py)' 'bash -c "cd polish && python client.py"' 'ls polish && python client.py' 'env -C polish python client.py'; do
  deny "35a: $c (the item does not cover polish/client.py: paid, no only freedom)" "$c" 'no go from the owner for client.py'
  guard "$c" toolu_a0; case "$OUT" in *"OPENAI_API_KEY in client.py"*) ok "... the signal is the one in polish/client.py";; *) ko "35a signal: $c -> $OUT";; esac
done
inlight deny "35a light: cd polish && python client.py" 'cd polish && python client.py' 'no go from the owner for client.py'
inlight deny "35a light: pushd" 'pushd polish; python client.py' 'no go from the owner for client.py'
allow "35a: cd tools && python client.py (matches the item path, no signal, no flag): free" 'cd tools && python client.py' toolu_a1
deny "35a: ... with the flag: paid" 'cd tools && python client.py --pay' 'no go from the owner for client.py'
allow "35a pin: the plain run of the item's own file, no flag" 'python tools/client.py' toolu_a2
nostate "35a: ... and none of the allows wrote state"
fresh; mk35; adapter 'paid_scripts: polish/client.py only --pay\n'
allow "35a: the item names polish/client.py: cd polish && python client.py with no flag is free (the owner's item)" 'cd polish && python client.py' toolu_a3
deny "35a: ... with the flag it is paid" 'cd polish && python client.py --pay' 'no go from the owner for client.py'
fresh; mk35; adapter 'paid_scripts: tools/client.py\n'
deny "35a: an item with no only: the script found elsewhere with a signal is paid" 'cd polish && python client.py' 'no go from the owner for client.py'
fresh; mk35; adapter 'paid_scripts: tools/client.py only --pay\npaid_free: --dry-run\n'
allow "35a: a free flag still frees it" 'cd polish && python client.py --dry-run' toolu_a4
fresh; mk35; adapter 'paid_scripts: tools/client.py only --pay\npaid_free: polish/*.py\n'
deny "35a: a script that an item lists is never free by path" 'cd tools && python client.py --pay' 'no go from the owner for client.py'
fresh; mk35; adapter 'paid_scripts: tools/client.py only --pay\npaid: client.py x 3, cap RM1, count none\n'
allow "35a: with a go for client.py the cd run passes" 'cd polish && python client.py --n 1' toolu_a5
[ "$(used)" = 1 ] && ok "... and is counted once" || ko "35a used: $(used) $(cat "$R" 2>&1)"
PGTOOL=PowerShell
fresh; mk35; adapter 'paid_scripts: tools/client.py only --pay\n'
for c in 'Set-Location polish; python client.py' 'Push-Location polish; python client.py' 'cd polish; python client.py --pay' 'Set-Location -Path polish; python client.py'; do
  deny "35a PS: $c" "$c" 'no go from the owner for client.py'
done
allow "35a PS: Set-Location tools; python client.py is free" 'Set-Location tools; python client.py' toolu_a6
PGTOOL=Bash
# --- 35b. a free path after a folder change
fresh; mk35; adapter 'paid_free: tests/check_*.py\n'
for c in 'cd tests && python check_a.py' 'cd tests; python check_a.py' 'pushd tests; python check_a.py' 'pushd tests && python check_a.py && popd' 'ls tests && python check_a.py' 'env -C tests python check_a.py' 'bash -c "cd tests && python check_a.py"' '(cd tests && python check_a.py)' 'cd tools && python ../tests/check_a.py'; do
  allow "35b: $c is free (the one file found lies in the project and matches tests/check_*.py)" "$c" toolu_b1
done
nostate "35b: ... and writes no state"
inlight allow "35b light: cd tests && python check_a.py" 'cd tests && python check_a.py' toolu_b2
for c in 'cd tools && python check_a.py' 'ls tests tools && python check_a.py' 'cd tests && cd ../tools && python check_a.py' 'cd sub && python tests/check_a.py' 'pushd sub; python tests/check_a.py' 'cd tests && python tools/check_a.py'; do
  deny "35b: $c is not free (a found file is outside the pattern, or the file found under the cwd is not the one that runs)" "$c" 'no go from the owner for check_a.py'
done
fresh; mk35; adapter 'paid_free: tests/check_*.py\npaid: check_a.py x 3, cap RM1, count none\n'
deny "35b: a script a go names is never free by path" 'cd tests && python check_a.py --n 1 && python check_a.py --n 1' 'a loop or repeat runs check_a.py more than once'
fresh; mk35; adapter 'paid_free: tests/check_*.py, --dry-run\n'
allow "35b: a free flag frees a run whose files are outside the pattern" 'cd tools && python check_a.py --dry-run' toolu_b3
PGTOOL=PowerShell
fresh; mk35; adapter 'paid_free: tests/check_*.py\n'
for c in 'Set-Location tests; python check_a.py' 'Push-Location tests; python check_a.py' 'cd .\tests; python .\check_a.py' 'Set-Location -Path:tests; python check_a.py'; do
  allow "35b PS: $c is free" "$c" toolu_b4
done
deny "35b PS: Set-Location tools; python check_a.py is not free" 'Set-Location tools; python check_a.py' 'no go from the owner for check_a.py'
deny "35b PS: Set-Location sub; python tests\check_a.py is not free" 'Set-Location sub; python tests\check_a.py' 'no go from the owner for check_a.py'
PGTOOL=Bash
# --- 35c. PowerShell -Param:value reads the value as the folder, as --opt=value is read
PGTOOL=PowerShell
fresh; mk35
for c in 'Set-Location -Path:polish; python gemini_client.py' 'Set-Location -LiteralPath:polish; python gemini_client.py' "Set-Location -Path:'polish'; python gemini_client.py" 'Set-Location -Path:.\polish; python gemini_client.py' 'sl -Pa:polish; python gemini_client.py' 'Push-Location -Path:polish; python gemini_client.py'; do
  deny "35c PS: $c" "$c" 'no go from the owner for gemini_client.py'
done
allow "35c PS: a missing folder in -Path:" 'Set-Location -Path:nowhere; python gemini_client.py' toolu_c1
PGTOOL=Bash
fresh; mk35
deny "35c: a quoted --opt=value" 'tool --dir="polish"; python gemini_client.py' 'no go from the owner for gemini_client.py'

# ===== 36. step 1 fix round 2. 36a: `only` freedom needs every found file that holds a signal to be covered by an `only` item (a path item matches only its own file). 36b: the attached value of env -C, the PowerShell -LP and -PSPath parameters
mk36() { mkl; mkat client.py sdk; mkat tools/client.py none; mkat polish/client.py key; }
# --- 36a. the item names tools/client.py; the root client.py and polish/client.py pay
fresh; mk36; adapter 'paid_scripts: tools/client.py only --pay\n'
for c in 'ls tools && python client.py' 'git status tools; python client.py' 'cd tools && cd .. && python client.py' 'ls tools && cd polish && python client.py' 'cd polish && ls ../tools && python client.py' 'echo tools; python client.py --out a.png' 'ls tools && python ./client.py'; do
  deny "36a: $c (the signal is in a file the item does not cover: paid, no only freedom)" "$c" 'no go from the owner for client.py'
done
inlight deny "36a light: ls tools && python client.py" 'ls tools && python client.py' 'no go from the owner for client.py'
inlight deny "36a light: cd tools && cd .. && python client.py" 'cd tools && cd .. && python client.py' 'no go from the owner for client.py'
nostate "36a: ... and no deny wrote state"
PGTOOL=PowerShell
for c in 'Get-ChildItem tools; python client.py' 'gci tools; python client.py' 'Set-Location tools; Set-Location ..; python client.py'; do
  deny "36a PS: $c" "$c" 'no go from the owner for client.py'
done
PGTOOL=Bash
fresh; mk36; adapter 'paid_scripts: client.py only --pay\n'
allow "36a: a file name item covers every folder: ls tools && python client.py with no flag is free (the owner's item)" 'ls tools && python client.py' toolu_s1
deny "36a: ... with the flag it is paid" 'ls tools && python client.py --pay' 'no go from the owner for client.py'
fresh; mk36; adapter 'paid_scripts: polish/client.py only --pay\n'
deny "36a: two files pay, the item covers only polish/client.py: paid" 'ls polish && python client.py' 'no go from the owner for client.py'
deny "36a: ... after cd" 'cd polish && python client.py' 'no go from the owner for client.py'
fresh; mk36; adapter 'paid_scripts: tools/client.py only --pay\npaid_free: --dry-run\n'
allow "36a: a free flag still frees it" 'ls tools && python client.py --dry-run' toolu_s2
fresh; mk36; adapter 'paid_scripts: tools/client.py only --pay\npaid: client.py x 3, cap RM1, count none\n'
allow "36a: with a go the run passes and is counted once" 'ls tools && python client.py --n 1' toolu_s3
[ "$(used)" = 1 ] && ok "... used 1" || ko "36a used: $(used) $(cat "$R" 2>&1)"
# --- 36b. env -Cdir, PowerShell -LP and -PSPath
fresh; mkl
deny "36b: env -Cpolish python gemini_client.py" 'env -Cpolish python gemini_client.py' 'no go from the owner for gemini_client.py'
deny "36b: env -C polish still read" 'env -C polish python gemini_client.py' 'no go from the owner for gemini_client.py'
PGTOOL=PowerShell
for c in 'Set-Location -LP:polish; python gemini_client.py' 'Set-Location -PSPath:polish; python gemini_client.py' 'Set-Location -PSP:polish; python gemini_client.py' 'Set-Location -lp:polish; python gemini_client.py' 'Push-Location -PSPath:.\polish; python gemini_client.py'; do
  deny "36b PS: $c" "$c" 'no go from the owner for gemini_client.py'
done
allow "36b PS: a missing folder" 'Set-Location -LP:nowhere; python gemini_client.py' toolu_s4
PGTOOL=Bash

# ===== 37. 0.7.0 F5, the owner-quote check: the typed go, `test ok`, `paid stop`. Only a record whose origin says the owner typed it is a go (origin.kind human AND promptSource typed or queued, E1-E3); a relayed, tool, scheduled, summary or model text never is.
# The transcripts are SYNTHETIC: one mk.py writes every case to $D/t/<name>.jsonl in one start (the shapes of E1-E4, field names only, no real content).
MK=$(wp "$D/mk.py")
cat > "$D/mk.py" <<'PY'
import datetime, json, os, sys
GO = "paid go: render.py x 3, cap RM1"
HUMAN = {"kind": "human"}
MARKERS = ("system-reminder", "cross-session-message", "task-notification", "local-command-stdout", "local-command-stderr", "bash-stdout", "bash-stderr")
PAST = "2026-11-10T00:00:00.000Z"      # every record has a time (the record's own `timestamp`); the default is long before any run of a test
STOPPED = "2026-11-02T00:00:00.000Z"   # ... the stop and the go of the take-over cases
FUTURE = "2099-01-01T00:00:00.000Z"    # ... a test ok in a fixed transcript that is later than run 1, whenever the suite runs
def now():
    n = datetime.datetime.now(datetime.timezone.utc)
    return n.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (n.microsecond // 1000)
def user(text, uid, src="typed", origin=HUMAN, turn="human", ts=PAST, **kw):   # E1: a prompt typed while Claude is idle (origin human, turnOrigin human, promptSource typed)
    r = {"type": "user", "uuid": uid, "parentUuid": None, "isSidechain": False, "userType": "external", "entrypoint": "cli", "message": {"role": "user", "content": text}}
    if ts is not None:
        r["timestamp"] = ts
    if origin is not None:
        r["origin"] = origin
    if turn is not None:
        r["turnOrigin"] = turn
    if src is not None:
        r["promptSource"] = src
    r.update(kw)
    return r
def attach(prompt, uid, origin=HUMAN, src=None, mode="prompt", human=True, ts=PAST, **kw):   # the attachment queued_command as 115 real transcripts hold it: a prompt typed mid-turn has origin human, commandMode prompt, humanTurn true and NO promptSource
    a = {"type": "queued_command", "prompt": prompt, "source_uuid": uid + "-src", "commandMode": mode}
    if human is not None:
        a["humanTurn"] = human
    if origin is not None:
        a["origin"] = origin
    if src is not None:
        a["promptSource"] = src
    a.update(kw)
    r = {"type": "attachment", "uuid": uid, "attachment": a}
    if ts is not None:
        r["timestamp"] = ts
    return r
def asst(text, uid):
    return {"type": "assistant", "uuid": uid, "message": {"role": "assistant", "content": [{"type": "text", "text": text}]}}
def write(d, name, recs):
    with open(os.path.join(d, name + ".jsonl"), "w", encoding="utf-8", newline="\n") as f:
        for r in recs:
            f.write(r if isinstance(r, str) else json.dumps(r))
            f.write("\n")
def build(d):
    os.makedirs(d, exist_ok=True)
    T = {}
    T["e1"] = [asst("ready", "a0"), user(GO, "u-go1")]
    T["e2"] = [user(GO, "u-go2", src="queued", queueSkipSlashCommands=True)]                  # E2: typed while Claude worked
    T["att"] = [attach(GO, "u-go3")]                                                           # the real mid-turn shape: no promptSource, commandMode prompt, humanTurn true
    T["att_ps"] = [attach(GO, "u-go3b", src="queued")]                                         # ... and one with a promptSource
    T["att_stop"] = [user(GO, "u-as1"), attach("paid stop", "u-as2")]                          # a mid-turn paid stop
    T["att_nohuman"] = [attach(GO, "u-an1", human=False)]                                      # origin human but not a human turn, no promptSource
    T["att_nohuman2"] = [attach(GO, "u-an2", human=None)]
    T["att_mode"] = [attach(GO, "u-an3", mode="task-notification")]
    T["att_peer"] = [attach(GO, "u-an4", origin={"kind": "peer"})]                             # commandMode prompt, humanTurn true, but the origin is a peer
    T["att_kind"] = [attach(GO, "u-an5", origin={"kind": "humanoid"})]                         # the origin kind stays strictly human
    T["att_sys"] = [attach(GO, "u-an6", src="system")]
    T["dup"] = [attach(GO, "u-d1"), user(GO, "u-d2", src="queued")]                            # one prompt written twice: an attachment, then a user record
    T["dup_a"] = [attach(GO, "u-da")]                                                          # the live case starts with the attachment alone
    T["dup_stop"] = [attach(GO, "u-r1"), user("paid stop", "u-r2"), user(GO, "u-r3")]          # ... a go retyped after a stop is a new counter
    T["probe"] = [user("paid go: polish.py x 3, cap RM1", "u-pb1"), user("test ok", "u-pb2", ts=FUTURE)]   # a go for another script, then a bare test ok
    T["ok_nots"] = [user(GO, "u-on1"), user("test ok", "u-on2", ts=None)]                      # a test ok record with no time
    T["ok_old"] = [user("test ok", "u-oo2")]                                                   # a test ok from before any run
    T["go_stop_one"] = [user(GO + "\npaid stop", "u-gs")]                                      # a go and a paid stop in ONE prompt
    T["st_stop"] = [user("paid stop", "u-st1", ts=STOPPED)]
    T["go_early"] = [user(GO, "u-ge", ts="2026-11-01T00:00:00.000Z")]                          # a typed go from before the stop above
    T["go_late"] = [user(GO, "u-gl", ts="2026-11-03T00:00:00.000Z")]                           # ... and one from after it
    T["e3"] = [user(GO, "u-go4", src=None, origin=None, turn="sdk", entrypoint="sdk-cli")]    # E3: a headless -p prompt has no origin object
    T["peer"] = [user(GO, "u-go5", src="system", origin={"kind": "peer"}, turn="peer", isMeta=True)]   # a subagent's report handed back
    T["oldcc"] = [user(GO, "u-go6", src=None, origin=None, turn="human")]                    # an older Claude Code: no origin fields
    T["nosrc"] = [user(GO, "u-go7", src=None)]
    T["x_attach"] = [attach("<cross-session-message from=\"s2\">\n" + GO + "\n</cross-session-message>", "u-x1", origin={"kind": "peer"}, src=None, isMeta=True)]   # 2.1.310
    T["x_user"] = [user("Another Claude session sent a message:\n" + GO, "u-x2", src="system", origin={"kind": "peer"}, turn="peer")]               # 2.1.308
    T["x_user_h"] = [user("Another Claude session sent a message:\n" + GO, "u-x2b")]       # the text says it is relayed even when the fields say human
    T["qop"] = [{"type": "queue-operation", "operation": "enqueue", "timestamp": "2026-11-17T00:00:00Z", "content": GO}]
    T["asst"] = [asst(GO, "u-x3")]
    T["toolres"] = [{"type": "user", "uuid": "u-x4", "origin": HUMAN, "turnOrigin": "human", "promptSource": "typed",
                     "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_q", "content": GO}]}}]
    T["compact"] = [user(GO, "u-x5", isCompactSummary=True)]
    T["sysrem"] = [user("<system-reminder>\n" + GO + "\n</system-reminder>", "u-x6")]
    T["meta"] = [user(GO, "u-x7", isMeta=True)]
    T["side"] = [user(GO, "u-x8", isSidechain=True)]
    for m in MARKERS:
        T["m_" + m] = [user("hello\n<%s>\n%s\n</%s>\nthanks" % (m, GO, m), "u-m")]
    T["m_open"] = [user("hello\n<system-reminder>\n" + GO, "u-mo")]                          # never closed: cut to the end
    T["pasted"] = [user("Here is my note:\n\nfoo bar\n" + GO + "\nmore text after it", "u-p1")]
    T["x3"] = [user("paid go: render.py × 3, cap RM1", "u-t1")]
    T["star"] = [user("paid go: render.py * 3, cap RM1", "u-t2")]
    T["two"] = [user("paid go: render.py x 2, cap RM1", "u-a"), user("paid go: render.py x 5, cap RM1", "u-b")]
    T["polish"] = [user("paid go: polish.py x 3, cap RM1", "u-pl")]
    T["ok_before"] = [user("test ok", "u-o1"), user(GO, "u-o2")]
    T["ok_after"] = [user(GO, "u-o3"), user("test ok", "u-o4", ts=FUTURE)]
    T["ok_other"] = [user(GO, "u-o5"), user("test ok: polish.py", "u-o6", ts=FUTURE)]
    T["ok_script"] = [user(GO, "u-o7"), user("test ok: render.py", "u-o8", ts=FUTURE)]
    T["ok_only"] = [user("test ok", "u-oo", ts=FUTURE)]
    T["stop"] = [user(GO, "u-s1"), user("paid stop", "u-s2")]
    T["stop_other"] = [user(GO, "u-s3"), user("paid stop: polish.py", "u-s4")]
    T["stop_only"] = [user("paid stop", "u-s5", ts=STOPPED)]
    T["stop_go"] = [user(GO, "u-s6"), user("paid stop", "u-s7"), user("paid go: render.py x 3, cap RM2", "u-s8")]
    T["stop_then"] = [user("paid stop", "u-s9", ts="2026-11-09T00:00:00.000Z"), user("paid go: render.py x 3, cap RM1", "u-sa")]
    T["garbage"] = ["this is not json, paid go: render.py x 9", "{\"type\":", "\x01\x02 binary paid go: render.py x 9", user(GO, "u-g1")]
    T["relay"] = T["x_attach"] + T["x_user"] + T["x_user_h"] + T["qop"] + T["asst"] + T["toolres"]
    T["slow"] = [user("paid go: polish.py x 1", "u-sl%d" % i) for i in range(200)]
    fill = lambda i: json.dumps(asst("x" * 900, "f%d" % i))
    T["big_tail"] = [fill(i) for i in range(6000)] + [user(GO, "u-bt")]                      # 6 MB, the go in the last 4 MB
    T["big_head"] = [fill(i) for i in range(1000)] + [user(GO, "u-bh")] + [fill(i) for i in range(5200)]   # 6 MB, the go about 1 MB in
    for k, v in T.items():
        write(d, k, v)
if sys.argv[1] == "build":
    build(sys.argv[2])
elif sys.argv[1] == "add":   # add FILE UUID TEXT [SRC]: the owner types one more line at the end of the transcript, stamped with the time now (E1 shape, or promptSource SRC)
    with open(sys.argv[2], "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(user(sys.argv[4], sys.argv[3], src=(sys.argv[5] if len(sys.argv) > 5 else "typed"), ts=now())) + "\n")
elif sys.argv[1] == "addatt":   # addatt FILE UUID TEXT: the same, as the mid-turn attachment shape
    with open(sys.argv[2], "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(attach(sys.argv[4], sys.argv[3], ts=now())) + "\n")
PY
mkdir -p "$D/t"
py "$MK" build "$(wp "$D/t")" </dev/null || { echo "FAIL could not build the synthetic transcripts"; exit 1; }
[ -s "$D/t/e1.jsonl" ] && [ -s "$D/t/big_tail.jsonl" ] || { echo "FAIL the synthetic transcripts are missing"; exit 1; }
tp() { TPATH=$(wp "$D/t/$1.jsonl"); }                                                         # the next guard calls send this transcript
tdeny() { tp "$2"; deny "$1" "$3" "$4" "${5:-}"; TPATH=; }                                     # $1 label, $2 transcript, $3 command, $4 text the reason must hold, $5 tool_use_id
tallow() { tp "$2"; allow "$1" "$3" "${4:-}"; TPATH=; }                                        # $1 label, $2 transcript, $3 command, $4 tool_use_id
ekey() { py "$CW" ekey "$(wp "$R")" "$1" "$2" </dev/null; }                                   # a field of one entry of paid-runs.json, by the go's id
ign() { fresh; mkpaid; tdeny "$1" "$2" 'python render.py --n 1' 'no go from the owner for render.py' toolu_ig; [ -e "$P" ] && ko "$1 -- state was written: $(ls "$P" 2>&1)"; }   # the go in transcript $2 is not the owner's typing: no go, nothing written

# --- 37a. the shapes that count (E1 typed, E2 queued, the attachment) and the typed go's entry
fresh; mkpaid
tallow "E1: the owner types the go (a user record, origin human, promptSource typed): run 1 (--n 1) passes silently" e1 'python render.py --n 1' toolu_f1
[ "$(used)" = 1 ] && [ "$(field go_from)" = '"session:u-go1"' ] && [ "$(field script)" = '"render.py"' ] && [ "$(field runs)" = 3 ] && [ "$(field cap)" = '"RM1"' ] && ok "... paid-runs.json: used 1, go_from session:u-go1 (the record's uuid), render.py, runs 3, cap RM1" || ko "typed go entry: $(cat "$R" 2>&1)"
tdeny "... run 2 waits for the owner's test ok, as for an adapter go" e1 'python render.py --n 1' "the batch waits for the owner's " toolu_f2
case "$OUT" in *'the owner types \"test ok\" in this session. Show the owner the one output first.'*) ok "... 0.7.1 F2: the reason leads with the typed instruction (the owner types test ok in this session)";; *) ko "wait reason: $OUT";; esac
case "$OUT" in *'to that paid: line'*) ko "0.7.1 F2: a typed go has no paid: line, the reason must not send the owner to it: $OUT";; *) ok "... and does not mention a paid: line";; esac
fresh; mkpaid
tallow "E2: typed while Claude worked (promptSource queued, queueSkipSlashCommands true) counts" e2 'python render.py --n 1' toolu_f3
[ "$(field go_from)" = '"session:u-go2"' ] && ok "... go_from session:u-go2" || ko "E2 entry: $(cat "$R" 2>&1)"
fresh; mkpaid
tallow "an attachment queued_command with origin human (typed mid-turn) counts" att 'python render.py --n 1' toolu_f4
[ "$(field go_from)" = '"session:u-go3"' ] && ok "... go_from session:u-go3" || ko "attachment entry: $(cat "$R" 2>&1)"
fresh; mkpaid
tallow "a prompt the owner pasted that holds the line among other lines counts" pasted 'python render.py --n 1' toolu_f5
fresh; mkpaid
tallow "the x spelled as a multiplication sign counts" x3 'python render.py --n 1' toolu_f6
fresh; mkpaid
tallow "the x spelled as * counts" star 'python render.py --n 1' toolu_f7
fresh; mkpaid
tallow "a garbage line and a binary line in the transcript are skipped: the typed go after them counts" garbage 'python render.py --n 1' toolu_f8

# --- 37b. what never counts: the go in these transcripts is refused, nothing is written
ign "E3: a headless run's prompt (no origin object, turnOrigin sdk) is not a go" e3
ign "a subagent's report handed back (origin peer, promptSource system, isMeta) is not a go" peer
ign "an older Claude Code with no origin fields (turnOrigin human only) fails closed" oldcc
case "$OUT" in *'to .claude/smartuse.local.md'*) ok "... and its reason points at the adapter go" || true;; *) ko "old Claude Code reason: $OUT";; esac
ign "origin human but no promptSource is not a go" nosrc
ign "a go inside a cross-session-message attachment (isMeta, the 2.1.310 shape) is not a go" x_attach
ign "a go in a user record that starts 'Another Claude session sent a message' (2.1.308, peer) is not a go" x_user
ign "... even when the record's fields say human: the start of the text says it is relayed" x_user_h
ign "a go inside a queue-operation is not a go" qop
ign "a go in the model's own text is not a go" asst
ign "a go quoted in a tool result is not a go, whatever the record's origin says" toolres
ign "a compact summary (isCompactSummary) is not a go" compact
ign "a record that is a <system-reminder> is not a go" sysrem
ign "any isMeta record is not a go" meta
ign "a subagent's own record (isSidechain) is not a go" side
for m in system-reminder cross-session-message task-notification local-command-stdout local-command-stderr bash-stdout bash-stderr; do
  ign "a go line inside <$m> ... </$m> in a human prompt is cut before its lines are read" "m_$m"
done
ign "an unterminated <system-reminder> in a human prompt cuts to the end of it" m_open

# --- 37c. the grammar of the typed lines: the newest go, the script it names, test ok and paid stop
fresh; mkpaid
tallow "the newest of two typed goes counts (x 2 then x 5)" two 'python render.py --n 1' toolu_g1
[ "$(ekey session:u-b runs)" = 5 ] && [ "$(ekey session:u-a runs)" = missing ] && ok "... the entry is the newest go's: runs 5, none for the older one" || ko "two goes: $(cat "$R" 2>&1)"
ign "a typed go for polish.py does not cover render.py" polish
fresh; mkpaid
tallow "test ok typed BEFORE the go: run 1 passes" ok_before 'python render.py --n 1' toolu_g2
tdeny "... run 2 waits: that test ok is ignored" ok_before 'python render.py --n 1' "the batch waits for the owner's " toolu_g3
fresh; mkpaid
tallow "test ok typed AFTER the go: run 1 passes" ok_after 'python render.py --n 1' toolu_g4
tallow "... run 2 passes (any flags)" ok_after 'python render.py --images 6' toolu_g5
[ "$(used)" = 2 ] && [ "$(field test_ok)" = true ] && ok "... used 2, test_ok true kept in paid-runs.json" || ko "test ok entry: $(cat "$R" 2>&1)"
fresh; mkpaid
tallow "test ok: polish.py after the go: run 1 passes" ok_other 'python render.py --n 1' toolu_g6
tdeny "... run 2 waits: a test ok for another script does not count" ok_other 'python render.py --n 1' "the batch waits for the owner's " toolu_g7
fresh; mkpaid
tallow "test ok: render.py after the go: run 1 passes" ok_script 'python render.py --n 1' toolu_g8
tallow "... and run 2 passes" ok_script 'python render.py --images 6' toolu_g9
fresh; mkpaid
tdeny "paid stop typed after the go: the very first call is refused" stop 'python render.py --n 1' 'the owner said \"paid stop\"' toolu_h1
[ "$(ekey session:u-s1 stopped)" = true ] && [ "$(ekey session:u-s1 used)" = 0 ] && [ ! -e "$P/paid.toolu_h1.done" ] && ok "... and the stop is written into paid-runs.json the first time it is seen (stopped true, used 0, nothing claimed)" || ko "stop entry: $(cat "$R" 2>&1)"
fresh; mkpaid
tallow "paid stop: polish.py does not stop render.py" stop_other 'python render.py --n 1' toolu_h2
fresh; mkpaid
tallow "a paid stop typed BEFORE the go is over: the go counts" stop_then 'python render.py --n 1' toolu_h3
fresh; mkpaid
tallow "go, paid stop, then a new go: the newest go counts" stop_go 'python render.py --n 1' toolu_h4
[ "$(ekey session:u-s8 used)" = 1 ] && [ "$(ekey session:u-s6 used)" = missing ] && ok "... a go typed after the stop is a new counter (session:u-s8 used 1)" || ko "stop then go: $(cat "$R" 2>&1)"

# --- 37d. the adapter go and the typed lines: a stop wins, the stop is kept, a go typed later is new; test ok counts for an adapter go; no transcript is needed
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'
tdeny "paid stop typed in the session wins over an adapter go" stop_only 'python render.py --n 1' 'the owner said \"paid stop\"' toolu_i1
[ "$(field stopped)" = true ] && [ "$(used)" = 0 ] && ok "... the stop is written into the adapter go's entry (stopped true, used 0)" || ko "adapter stop entry: $(cat "$R" 2>&1)"
deny "... and it holds when the stop has scrolled out of the transcript (an empty one): still refused" 'python render.py --n 1' 'the owner said \"paid stop\"' toolu_i2
tallow "... a go typed after the stop is a new counter: it covers although the adapter go is stopped" e1 'python render.py --n 1' toolu_i3
[ "$(ekey session:u-go1 used)" = 1 ] && [ "$(nent)" = 2 ] && ok "... two entries: the stopped adapter go, and session:u-go1 with used 1" || ko "stop kept: $(cat "$R" 2>&1)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'
tallow "a stop, then a typed go, with an adapter go: the typed go covers (a go typed after the stop)" stop_then 'python render.py --n 1' toolu_i4
[ "$(ekey session:u-sa used)" = 1 ] && ok "... session:u-sa used 1" || ko "stop then go, adapter: $(cat "$R" 2>&1)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
tallow "an adapter go: run 1 passes" ok_only 'python render.py --n 1' toolu_i5
tallow "... and run 2 passes: a test ok typed in the session counts for an adapter go" ok_only 'python render.py --images 6' toolu_i6
[ "$(used)" = 2 ] && ok "... used 2" || ko "adapter go and typed test ok: $(cat "$R" 2>&1)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none, test ok\n'
tallow "an adapter go works with a transcript that does not exist" nowhere 'python render.py --n 1' toolu_i7
[ "$(used)" = 1 ] && ok "... and is counted" || ko "adapter go, missing transcript: $(cat "$R" 2>&1)"
tallow "an adapter go works beside a 6 MB transcript with no go in it" big_head 'python render.py --n 1' toolu_i8

# --- 37e. cannot verify: a typed go needs a transcript the guard can read (the adapter go does not)
fresh; mkpaid
tdeny "a missing transcript, no adapter go: could not verify the go (the transcript is missing)" nowhere 'python render.py --n 1' 'could not verify the go (the transcript is missing); put it in .claude/smartuse.local.md. Nothing was spent.' toolu_j1
endrule "... 0.7.4 F3 r7 (pin): the transcript reason keeps its adapter tail and ends Nothing was spent. [rule paid]"
mkdir -p "$D/t/adir.jsonl"
tdeny "a transcript path that is a folder: could not verify the go (the transcript is unreadable)" adir 'python render.py --n 1' 'could not verify the go (the transcript is unreadable); put it in .claude/smartuse.local.md. Nothing was spent.' toolu_j2
endrule "... 0.7.4 F3 r7 (pin): the unreadable-transcript reason keeps its adapter tail and ends Nothing was spent. [rule paid]"
[ ! -e "$P" ] && ok "... nothing written" || ko "a could-not-verify deny wrote state: $(ls "$P")"
fresh; mkpaid
tallow "a 6 MB transcript, the go in its last 4 MB: found" big_tail 'python render.py --n 1' toolu_j3
fresh; mkpaid
tdeny "a 6 MB transcript, the go only in the first 2 MB, no adapter go: could not verify the go" big_head 'python render.py --n 1' 'could not verify the go (the transcript is longer than the last 4 MB read and holds no go in them)' toolu_j4
fresh; mkpaid
tp e1
case "$(wp "$D/t/e1.jsonl")" in [A-Za-z]:/*) q=$(wp "$D/t/e1.jsonl"); l=$(printf '%s' "${q:0:1}" | tr 'A-Z' 'a-z'); TPATH="/$l${q:2}"; allow "a /c/Users/... transcript_path (the Git Bash spelling of a Windows path) is read" 'python render.py --n 1' toolu_j5;; *) skip "a /c/... transcript_path: skipped (not a Windows path here)";; esac
TPATH=
fresh; mkpaid
r=$(py "$CW" scandl "$(wp "$G")" "$PW" "$(wp "$D/t/slow.jsonl")" </dev/null 2>&1)
case "$r" in *'scan: raised the transcript scan ran over the hook'*) ok "a deadline that has passed, given to the scan, raises (the scan is bounded by the hook's one deadline)";; *) ko "scan with a past deadline: $r";; esac
case "$r" in *'hook '*' deny '*'could not verify the go (the transcript scan ran over the hook'*'[rule paid]'*) ok "the scan itself overrunning the shared deadline (a slow reader, 200 records): the call is denied, could not verify the go";; *) ko "scan overrun: $r";; esac
[ ! -e "$R" ] && ok "... and nothing is counted" || ko "a scan overrun was counted: $(cat "$R")"
fresh; mkpaid; adapter 'paid: polish.py x 2, cap RM1\n'; mkdir -p "$D/t/adir2.jsonl"
tp adir2
inlight deny "light, armed, a folder as the transcript: the scan runs and cannot read it (control)" 'python render.py --n 1' 'could not verify the go (the transcript is unreadable)'
LOFF=paid inlight allow "light with paid named in Rules off: the check is skipped and the transcript is not read" 'python render.py --n 1'
TPATH=

# --- 37f. E4: a subagent's call carries agent_id (and the main session's transcript): the typed go is refused, the adapter go covers it
fresh; mkpaid
XEV=',"agent_id":"agent-x","agent_type":"general-purpose"'
tdeny "E4: a subagent's call (agent_id) does not use a typed go: refused" e1 'python render.py --n 1' 'no go from the owner for render.py' toolu_k1
case "$OUT" in *'A subagent cannot use a typed go'*'.claude/smartuse.local.md'*) ok "... and the reason says subagents need the adapter go (the paid: line in .claude/smartuse.local.md)";; *) ko "subagent reason: $OUT";; esac
adapter 'paid: render.py x 10, cap RM5, count none\n'
tallow "... with an adapter go the subagent's call passes" e1 'python render.py --n 1' toolu_k2
tdeny "... a typed paid stop still stops the subagent's call" stop_only 'python render.py --n 1' 'the owner said \"paid stop\"' toolu_k3
XEV=

# --- 37g. INCIDENT REPLAY 3: the manager's go relayed into the builder session in every shape: denied, and the reason asks for the owner's own typing
fresh; mkpaid
tdeny "INCIDENT REPLAY 3: the go relayed from another session (cross-session message, 'Another Claude session sent a message', queue-operation, model text, tool result) -> denied" relay 'python render.py --images 1' 'no go from the owner for render.py' toolu_ir3
case "$OUT" in *'The owner can also type \"paid go: render.py x <runs>, cap <amount>\" in this session (a go relayed from another session or a tool does not count).'*) ok "... the reason asks for the owner's own typing";; *) ko "relayed go reason: $OUT";; esac
[ ! -e "$P" ] && ok "... nothing was written" || ko "a relayed go wrote state: $(ls "$P")"

# --- 37h. INTEGRATION: the six steps of the acceptance in one run, one real-shaped event per call through py.sh, the transcript growing as the owner types, paid-runs.json read after each step
fresh; mkpaid; rm -f "$D/t/live.jsonl"
addl() { py "$MK" add "$(wp "$D/t/live.jsonl")" "$1" "$2" </dev/null; }                     # the owner types one more line
addl u-l1 'paid go: render.py x 3, cap RM1'; tp live
allow "six steps, 1: the owner types the go; run 1 (--images 1) passes" 'python render.py --images 1' toolu_L1
[ "$(ekey session:u-l1 used)" = 1 ] && ok "... paid-runs.json: session:u-l1 used 1" || ko "after step 1: $(cat "$R" 2>&1)"
deny "2: the next call waits for the owner's test ok" 'python render.py --images 6' "the batch waits for the owner's " toolu_L2
[ "$(ekey session:u-l1 used)" = 1 ] && ok "... used still 1" || ko "after step 2: $(cat "$R" 2>&1)"
addl u-l2 'test ok'
allow "3: the owner types test ok: run 2 passes" 'python render.py --images 6' toolu_L3
allow "... run 3 passes" 'python render.py --images 6' toolu_L4
[ "$(ekey session:u-l1 used)" = 3 ] && ok "... used 3" || ko "after step 3: $(cat "$R" 2>&1)"
deny "4: run 4 is refused: used up (3 of 3)" 'python render.py --images 6' 'the go for render.py is used up (3 of 3)' toolu_L5
[ "$(ekey session:u-l1 used)" = 3 ] && ok "... used stays 3" || ko "after step 4: $(cat "$R" 2>&1)"
addl u-l3 'paid go: render.py x 10, cap RM2'
allow "5: a new typed go is a new counter: its run 1 passes (the old test ok does not carry over)" 'python render.py --images 1' toolu_L6
[ "$(ekey session:u-l3 used)" = 1 ] && [ "$(ekey session:u-l1 used)" = 3 ] && ok "... session:u-l3 used 1, session:u-l1 still 3" || ko "after step 5: $(cat "$R" 2>&1)"
addl u-l4 'test ok'
allow "... test ok, then run 2 of the new go passes" 'python render.py --images 6' toolu_L7
[ "$(ekey session:u-l3 used)" = 2 ] && ok "... used 2 of 10" || ko "after run 2 of the new go: $(cat "$R" 2>&1)"
addl u-l5 'paid stop'
deny "6: paid stop refuses the next run although 8 are left" 'python render.py --images 6' 'the owner said \"paid stop\"' toolu_L8
[ "$(ekey session:u-l3 used)" = 2 ] && [ "$(ekey session:u-l3 stopped)" = true ] && ok "... used stays 2, stopped true in paid-runs.json" || ko "after step 6: $(cat "$R" 2>&1)"
TPATH=

# ===== 38. 0.7.0 F5 fix round (one round). 38a the real mid-turn shape (an attachment with no promptSource), and the same prompt written twice. 38b a typed test ok counts for a go only when its record is later than that go's run 1. 38c a go and a stop in one prompt. 38d a typed go takes over a stopped adapter go only when its record is later than the stop. 38e the stop reason.
# --- 38a. a queued_command attachment: origin human AND (promptSource typed or queued, OR commandMode prompt with humanTurn true); the origin kind stays strictly human
fresh; mkpaid
tallow "38a: a mid-turn prompt as the real transcripts hold it (attachment, origin human, commandMode prompt, humanTurn true, NO promptSource) counts" att 'python render.py --n 1' toolu_n1
[ "$(field go_from)" = '"session:u-go3"' ] && ok "... go_from session:u-go3" || ko "mid-turn entry: $(cat "$R" 2>&1)"
fresh; mkpaid
tallow "38a: the same attachment with a promptSource (queued) still counts" att_ps 'python render.py --n 1' toolu_n2
fresh; mkpaid
tdeny "38a: a paid stop typed mid-turn (that shape) after a typed go stops the call" att_stop 'python render.py --n 1' 'the owner said \"paid stop\"' toolu_n3
ign "38a: origin human but humanTurn false and no promptSource is not a go" att_nohuman
ign "38a: origin human with no humanTurn and no promptSource is not a go" att_nohuman2
ign "38a: origin human, humanTurn true, but commandMode task-notification is not a go" att_mode
ign "38a: commandMode prompt and humanTurn true with origin peer is not a go (the kind stays strictly human)" att_peer
ign "38a: origin kind humanoid is not a go" att_kind
ign "38a: a promptSource system with the mid-turn fields is not a go" att_sys
fresh; mkpaid
tallow "38a dedupe: an attachment and a user record of the same prompt are one go (the attachment's)" dup 'python render.py --n 1' toolu_n4
[ "$(ekey session:u-d1 used)" = 1 ] && [ "$(ekey session:u-d2 used)" = missing ] && [ "$(nent)" = 1 ] && ok "... one entry, session:u-d1 used 1; none for the user record" || ko "dedupe: $(cat "$R" 2>&1)"
fresh; mkpaid; cp "$D/t/dup_a.jsonl" "$D/t/dup_live.jsonl"
tallow "38a dedupe, live: run 1 passes on the attachment alone" dup_live 'python render.py --n 1' toolu_n5
py "$MK" add "$(wp "$D/t/dup_live.jsonl")" u-dl2 'paid go: render.py x 3, cap RM1' queued </dev/null
tdeny "... the same prompt then shows up as a user record: still the one counter (run 2 waits for test ok)" dup_live 'python render.py --n 1' "the batch waits for the owner's " toolu_n6
[ "$(nent)" = 1 ] && [ "$(ekey session:u-da used)" = 1 ] && ok "... still one entry, used 1" || ko "dedupe, live: $(cat "$R" 2>&1)"
fresh; mkpaid
tallow "38a: a go retyped after a stop (attachment, paid stop, the same go again) is a new counter" dup_stop 'python render.py --n 1' toolu_n7
[ "$(ekey session:u-r3 used)" = 1 ] && [ "$(ekey session:u-r1 used)" = missing ] && ok "... session:u-r3 used 1, no entry for the first go" || ko "retyped go: $(cat "$R" 2>&1)"
# --- 38b. a typed test ok counts only when its record is later than the go's run 1 (stored in the entry when run 1 is counted)
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
tdeny "38b: the reviewer's probe: a typed go for polish.py, then a bare test ok, does not lift render.py's one-output rule" probe 'python render.py --images 6' 'first run after the go must make ONE output' toolu_o1
fresh; mkpaid
tdeny "38b: a typed go, and a test ok in the transcript before its run 1: the first run still makes ONE output" ok_after 'python render.py --images 6' 'first run after the go must make ONE output' toolu_o2
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
tallow "38b: an adapter go, a test ok from before any run: run 1 passes" ok_old 'python render.py --n 1' toolu_o3
tdeny "... run 2 waits: that test ok is older than run 1" ok_old 'python render.py --n 1' "the batch waits for the owner's " toolu_o4
fresh; mkpaid
tallow "38b: a typed go and a test ok record with no time: run 1 passes" ok_nots 'python render.py --n 1' toolu_o5
tdeny "... run 2 waits: a record with no time does not count (fail closed)" ok_nots 'python render.py --n 1' "the batch waits for the owner's " toolu_o6
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5\n'
tallow "38b: an adapter go, a test ok typed after run 1: run 1 passes" ok_only 'python render.py --n 1' toolu_o7
tallow "... run 2 passes" ok_only 'python render.py --images 6' toolu_o8
adapter 'paid: render.py x 10, cap RM6\n'
tdeny "... a changed adapter line is a new counter: it does not inherit the old test ok" ok_only 'python render.py --images 6' 'first run after the go must make ONE output' toolu_o9
fresh; mkpaid
tallow "38b: a typed go, a test ok typed after run 1: run 1 passes" ok_after 'python render.py --n 1' toolu_o10
tallow "... run 2 passes" ok_after 'python render.py --images 6' toolu_o11
[ "$(used)" = 2 ] && [ "$(field test_ok)" = true ] && [ -n "$(field run1_at)" ] && [ "$(field run1_at)" != null ] && ok "... used 2, test_ok true, run1_at stored in the entry" || ko "38b entry: $(cat "$R" 2>&1)"
# --- 38c. a go and a paid stop in one prompt: the stop is later (record, then line within the record)
fresh; mkpaid
tdeny "38c: paid go and paid stop typed in ONE prompt: the call is refused" go_stop_one 'python render.py --n 1' 'the owner said \"paid stop\"' toolu_p1
# --- 38e. the stop reason says only what is true
case "$OUT" in *'paid: line'*|*'changes the'*) ko "38e: the stop reason still names changing the paid: line: $OUT";; *'The owner types a new \"paid go:'*) ok "38e: the stop reason says a new typed go starts again, and names no paid: line change";; *) ko "38e: stop reason: $OUT";; esac
# --- 38d. the stop is stored with its time; a typed go takes over only when its record is later
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'
tdeny "38d: a stop typed in the session stops an adapter go (stored with its time)" st_stop 'python render.py --n 1' 'the owner said \"paid stop\"' toolu_q1
[ "$(field stopped)" = true ] && [ "$(field stopped_at)" != null ] && [ -n "$(field stopped_at)" ] && ok "... the entry holds stopped true and stopped_at" || ko "38d entry: $(cat "$R" 2>&1)"
tdeny "... a typed go from BEFORE the stop cannot take over: still stopped" go_early 'python render.py --n 1' 'the owner said \"paid stop\"' toolu_q2
tallow "... a typed go from AFTER the stop takes over" go_late 'python render.py --n 1' toolu_q3
[ "$(ekey session:u-gl used)" = 1 ] && ok "... session:u-gl used 1" || ko "38d take-over: $(cat "$R" 2>&1)"

# ===== 39. 0.7.1 F1, a long Windows path keeps its paid counter. A real project folder whose state folder passes the limit (240 characters on Windows, E1: the
# folder is made, then no file reaches it; a 300-character key elsewhere) plus an adapter go: run 1 is allowed (it was denied "the counter is not writable"),
# the counter and its claim marker sit in the short-key folder, it is the folder ledger.py names, and the two owner-file guards still refuse a write to it.
TPATH=; XEV=; PGTOOL=Bash
NT=$(py -c 'import os, sys; sys.stdout.write("1" if os.name == "nt" else "0")' </dev/null)
BL=$(py -c 'import os, sys, pathlib; sys.stdout.write(str(len(str(pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~")) / ".claude" / "smartuse" / "projects"))))' </dev/null)
mklong() { # $1 = a key length -> makes a project folder (two parts, so none passes 255 characters) whose key is that long and prints its path
  local pre k0 rest a b; pre="$D/lp"; k0=$(key "$(wp "$pre")"); rest=$(( $1 - ${#k0} - 2 )); a=$(( rest / 2 )); b=$(( rest - a ))
  a=$(printf '%*s' "$a" ''); b=$(printf '%*s' "$b" ''); mkdir -p "$pre/${a// /a}/${b// /b}" && printf '%s' "$pre/${a// /a}/${b// /b}"
}
if [ "$NT" = 1 ]; then LK=$(( 239 - BL )); else LK=300; fi
if [ "$LK" -lt 60 ]; then skip "39 skipped: HOME is $BL characters, too long to build a state folder of 240"; else
  rm -rf "$D/lp"; LP=$(mklong "$LK"); LPW=$(wp "$LP"); LKEY=$(key "$LPW")
  fresh; mkdir -p "$LP/.claude"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"
  [ "${#LKEY}" = "$LK" ] && ok "39 the project folder's key is $LK characters (state folder $(( BL + 1 + LK )) on this HOME)" || ko "39 the key is ${#LKEY} characters, wanted $LK"
  guard 'python render.py --images 1' toolu_L1 "$LPW"
  [ -z "$OUT" ] && [ -z "$ERR" ] && ok "39 run 1 in the long folder with an adapter go: allowed, nothing printed" || ko "39 run 1 in the long folder: stdout '${OUT:0:300}' stderr '$ERR'"
  LS=$(CLAUDE_PROJECT_DIR="$LPW" py "$H/ledger.py" --state-dir </dev/null); LS=${LS%$'\r'}; LN=${LS##*[/\\]}; LR="$HOME/.claude/smartuse/projects/$LN/paid-runs.json"
  [ -n "$LN" ] && [ "$LN" != "$LKEY" ] && [ "${#LN}" -le 53 ] && ok "39 ledger.py --state-dir names the short key ($LN), not the $LK-character full key" || ko "39 ledger.py names '$LN' (${#LN} characters)"
  [ "$(ls "$HOME/.claude/smartuse/projects" 2>/dev/null | tr '\n' ' ')" = "$LN " ] && [ -f "$LR" ] && [ -f "$HOME/.claude/smartuse/projects/$LN/paid.toolu_L1.done" ] && ok "39 the counter and the claim marker sit in the short-key folder, and no other folder was made" || ko "39 state: $(ls "$HOME/.claude/smartuse/projects" 2>&1 | tr '\n' ' ') (wanted '$LN' holding paid-runs.json and paid.toolu_L1.done)"
  [ "$(py "$CW" entry "$(wp "$LR")" used </dev/null 2>/dev/null)" = 1 ] && [ "$(py "$CW" entry "$(wp "$LR")" go_from </dev/null 2>/dev/null)" = '"adapter"' ] && ok "39 ... used 1, go_from adapter" || ko "39 counter: $(cat "$LR" 2>&1)"
  guard 'python render.py --images 1' toolu_L2 "$LPW"
  [ -z "$OUT" ] && [ -z "$ERR" ] && [ "$(py "$CW" entry "$(wp "$LR")" used </dev/null 2>/dev/null)" = 2 ] && ok "39 run 2 is allowed (test ok) and the same counter holds used 2" || ko "39 run 2: stdout '${OUT:0:300}' stderr '$ERR' counter: $(cat "$LR" 2>&1)"
  FGOUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"{}"}}' "$(wp "$LR")" | py "$H/file-guard.py" 2>/dev/null); FGRC=$?
  case "$FGOUT" in *'"permissionDecision": "deny"'*"this file is human-only"*"how many paid runs"*) [ "$FGRC" = 0 ] && ok "39 file-guard still refuses a Write to the short-key folder's paid-runs.json (exit 0, the human-only deny JSON on stdout)" || ko "39 file-guard exit code $FGRC";; *) ko "39 file-guard did not deny a Write to $LR: stdout '${FGOUT:0:300}'";; esac
  guard "echo '{}' > $(wp "$LR")" toolu_L3 "$LPW"
  case "$OUT" in *"owner-only file"*) ok "39 bash-guard's owner-file rule still refuses a shell write to it";; *) ko "39 owner-file: stdout '${OUT:0:300}' stderr '$ERR'";; esac
  [ "$(ls "$REAL_HOME/.claude/smartuse/projects" 2>/dev/null | grep -c 'aaaaaaaa')" = 0 ] && ok "39 the real ~/.claude/smartuse gained no folder from these cases" || ko "39 a test folder reached the real ~/.claude/smartuse/projects"
  rm -rf "$D/lp"
fi
# ===== 39b. 0.7.2 F2 (D-YK19), making a state folder keeps the paid count. A project whose state folder is 205 characters (the real reset window: 195 to 209 with
# long paths off, where a 30-character tool_use_id's marker fits) is on the short key (no full-key folder yet: a 64-character name would not fit). Run 1 is counted
# in the short folder. A shell then makes the full-key folder (a file fits in it, so 0.7.1's rule moved to it and the count restarted at used 1). Now the folder that
# already holds the counter wins: run 2 shows used 2 in the short folder, and the made folder stays empty. Card A: with a go WITHOUT test ok, run 2 is refused with
# "waits for the owner's test ok" (the count survived; before, it ran as a new run 1). Windows only: elsewhere a short key arises past 255 characters, where its
# full-key folder cannot be made.
if [ "$NT" != 1 ]; then skip "39b skipped here (not Windows: no short key can meet a full-key folder that can be made)"; else
  LK=$(( 204 - BL )); ID1=toolu_01ABCDEFGHIJKLMNOPQRSTUV; ID2=toolu_02ABCDEFGHIJKLMNOPQRSTUV   # two 30-character ids, as Claude Code makes them (marker paid.<id>.done is 40)
  if [ "$LK" -lt 60 ]; then skip "39b skipped: HOME is $BL characters, too long to build a state folder of 205"; else
    rm -rf "$D/lp"; LP=$(mklong "$LK"); LPW=$(wp "$LP"); LKEY=$(key "$LPW")
    fresh; mkdir -p "$LP/.claude"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"
    [ "${#LKEY}" = "$LK" ] && ok "39b the project folder's key is $LK characters (state folder $(( BL + 1 + LK )) on this HOME)" || ko "39b the key is ${#LKEY} characters, wanted $LK"
    [ "${#ID1}" = 30 ] && ok "39b the tool_use_id is 30 characters (marker 40), the state folder $(( BL + 1 + LK ))" || ko "39b id ${#ID1}"
    guard 'python render.py --images 1' "$ID1" "$LPW"
    LS=$(CLAUDE_PROJECT_DIR="$LPW" py "$H/ledger.py" --state-dir </dev/null); LS=${LS%$'\r'}; LN=${LS##*[/\\]}; LR="$HOME/.claude/smartuse/projects/$LN/paid-runs.json"
    [ -z "$OUT" ] && [ -z "$ERR" ] && [ -n "$LN" ] && [ "$LN" != "$LKEY" ] && [ -f "$LR" ] && [ "$(py "$CW" entry "$(wp "$LR")" used </dev/null 2>/dev/null)" = 1 ] && ok "39b run 1 is counted in the short-key folder ($LN): used 1" || ko "39b run 1: stdout '${OUT:0:300}' stderr '$ERR' short folder '$LN', counter: $(cat "$LR" 2>&1)"
    mkdir -p "$HOME/.claude/smartuse/projects/$LKEY"
    guard 'python render.py --images 1' "$ID2" "$LPW"
    LS2=$(CLAUDE_PROJECT_DIR="$LPW" py "$H/ledger.py" --state-dir </dev/null); LS2=${LS2%$'\r'}; LN2=${LS2##*[/\\]}
    [ "$LN2" = "$LN" ] && ok "39b after the shell made the full-key folder, ledger.py --state-dir still names the short folder" || ko "39b ledger.py now names '$LN2' (was '$LN')"
    [ -z "$OUT" ] && [ -z "$ERR" ] && [ "$(py "$CW" entry "$(wp "$LR")" used </dev/null 2>/dev/null)" = 2 ] && ok "39b run 2 shows used 2 in the short-key folder: the count survived" || ko "39b run 2: stdout '${OUT:0:300}' stderr '$ERR' short counter: $(cat "$LR" 2>&1) full-key folder: $(ls -A "$HOME/.claude/smartuse/projects/$LKEY" 2>&1 | tr '\n' ' ')"
    [ -z "$(ls -A "$HOME/.claude/smartuse/projects/$LKEY" 2>/dev/null)" ] && ok "39b the full-key folder the shell made stays empty (no counter, no marker moved into it)" || ko "39b the full-key folder holds: $(ls -A "$HOME/.claude/smartuse/projects/$LKEY" 2>&1 | tr '\n' ' ')"
    # Card A: a go WITHOUT test ok. Run 1 is counted in the short folder, the shell makes the full-key folder, run 2 is refused (the count survived; before, run 2 was a new run 1)
    fresh; mkdir -p "$LP/.claude"; printf 'paid: render.py x 10, cap RM5\n' > "$LP/.claude/smartuse.local.md"
    guard 'python render.py --images 1' "$ID1" "$LPW"
    [ -z "$OUT" ] && [ -z "$ERR" ] && [ -f "$LR" ] && ok "39b Card A: run 1 (a go without test ok) is allowed and counted in the short-key folder" || ko "39b Card A run 1: stdout '${OUT:0:300}' stderr '$ERR'"
    mkdir -p "$HOME/.claude/smartuse/projects/$LKEY"
    guard 'python render.py --images 1' "$ID2" "$LPW"
    case "$OUT" in *"run 1 of 10 is done; the batch waits for the owner's "*"test ok"*) ok "39b Card A: after the shell made the full-key folder, run 2 is refused: the batch waits for the owner's test ok";; *) ko "39b Card A run 2: stdout '${OUT:0:400}' stderr '$ERR' counter: $(cat "$LR" 2>&1)";; esac
    [ "$(py "$CW" entry "$(wp "$LR")" used </dev/null 2>/dev/null)" = 1 ] && [ -z "$(ls -A "$HOME/.claude/smartuse/projects/$LKEY" 2>/dev/null)" ] && ok "39b Card A: the count stays used 1 in the short folder and the made folder stays empty" || ko "39b Card A state: short counter $(cat "$LR" 2>&1) full-key folder: $(ls -A "$HOME/.claude/smartuse/projects/$LKEY" 2>&1 | tr '\n' ' ')"
    [ "$(ls "$REAL_HOME/.claude/smartuse/projects" 2>/dev/null | grep -c 'aaaaaaaa')" = 0 ] && ok "39b the real ~/.claude/smartuse gained no folder from these cases" || ko "39b a test folder reached the real ~/.claude/smartuse/projects"
    rm -rf "${D:?}/lp"
  fi
fi
# ===== 39d. 0.7.2 D9 (the review's proven exploit), a folder copy plants a counter. owner-file matches only names in the command text and file-guard only paths under projects/<key>/,
# so `cp -r <tmp>/snap <state>/projects/<short>` puts a paid-runs.json holding {} in the short-key folder without either guard seeing it. A kept full-key project (a counter
# there, used 1) then moved to the short folder, where the count was {}. Now a counter in BOTH folders makes the paid check deny ("two state folders hold a counter", naming
# /smartuse:doctor): no single planted counter wins, in either direction. The copy is a real cp -r here. Windows only (a made full-key folder next to a short key).
if [ "$NT" != 1 ]; then skip "39d skipped here (not Windows: no short key can meet a full-key folder that can be made)"; else
  LK=$(( 204 - BL )); ID1=toolu_01ABCDEFGHIJKLMNOPQRSTUV; ID2=toolu_02ABCDEFGHIJKLMNOPQRSTUV
  if [ "$LK" -lt 60 ]; then skip "39d skipped: HOME is $BL characters, too long to build a state folder of 205"; else
    rm -rf "${D:?}/lp" "${D:?}/snap"; LP=$(mklong "$LK"); LPW=$(wp "$LP"); LKEY=$(key "$LPW"); PR="$HOME/.claude/smartuse/projects"
    FP="$PR/$LKEY"; FR="$FP/paid-runs.json"
    LNAME=$(py -c "import hashlib, sys; k = sys.argv[1]; sys.stdout.write((k[-40:] + '-' + hashlib.sha1(k.encode()).hexdigest()[:12]).lstrip('-'))" "$LKEY" </dev/null)   # the short-key folder's name, worked out the suite's own way
    SP="$PR/$LNAME"; SR="$SP/paid-runs.json"
    # (a) the kept full-key project: its folder exists, its counter says used 1; (b) the planted copy; (c) run 2 must be denied
    fresh; mkdir -p "$LP/.claude" "$FP" "$D/snap"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"
    guard 'python render.py --images 1' "$ID1" "$LPW"
    [ -z "$OUT" ] && [ -z "$ERR" ] && [ -f "$FR" ] && [ "$(py "$CW" entry "$(wp "$FR")" used </dev/null 2>/dev/null)" = 1 ] && ok "39d the kept full-key project holds its counter: used 1" || ko "39d run 1: stdout '${OUT:0:300}' stderr '$ERR' full-key folder: $(ls -A "$FP" 2>&1 | tr '\n' ' ')"
    printf '{}' > "$D/snap/paid-runs.json"; cp -r "$D/snap" "$SP"
    [ -f "$SR" ] && ok "39d the folder copy planted a counter ({}) in the short-key folder ($LNAME)" || ko "39d the copy did not land: $(ls -A "$PR" 2>&1 | tr '\n' ' ')"
    guard 'python render.py --images 1' "$ID2" "$LPW"
    case "$OUT" in *'could not verify the go (two state folders hold a counter); run /smartuse:doctor. Nothing was spent.'*) ok "39d run 2 is denied: two state folders hold a counter, the reason names /smartuse:doctor";; *) ko "39d run 2: stdout '${OUT:0:400}' stderr '$ERR' full counter: $(cat "$FR" 2>&1) short counter: $(cat "$SR" 2>&1)";; esac
    case "$OUT" in *'smartuse.local.md'*) ko "39d the reason must not send the owner to the adapter: $OUT";; *) ok "39d ... and does not send the owner to smartuse.local.md";; esac
    [ "$(py "$CW" entry "$(wp "$FR")" used </dev/null 2>/dev/null)" = 1 ] && [ "$(cat "$SR" 2>/dev/null)" = '{}' ] && [ ! -e "$FP/paid.$ID2.done" ] && [ ! -e "$SP/paid.$ID2.done" ] && ok "39d nothing was counted: the full-key counter still says used 1, the planted one is untouched, no marker for run 2" || ko "39d state: full $(cat "$FR" 2>&1) short $(cat "$SR" 2>&1) markers: $(ls -A "$FP" "$SP" 2>&1 | tr '\n' ' ')"
    # the other direction: a live short-key counter, a copy plants one in the full-key folder
    rm -rf "${D:?}/lp" "${D:?}/snap"; LP=$(mklong "$LK"); fresh; mkdir -p "$LP/.claude" "$D/snap"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"
    guard 'python render.py --images 1' "$ID1" "$LPW"
    [ -z "$OUT" ] && [ -z "$ERR" ] && [ -f "$SR" ] && [ "$(py "$CW" entry "$(wp "$SR")" used </dev/null 2>/dev/null)" = 1 ] && ok "39d the short-key project holds its counter: used 1" || ko "39d short run 1: stdout '${OUT:0:300}' stderr '$ERR' folders: $(ls -A "$PR" 2>&1 | tr '\n' ' ')"
    printf '{}' > "$D/snap/paid-runs.json"; cp -r "$D/snap" "$FP"
    guard 'python render.py --images 1' "$ID2" "$LPW"
    case "$OUT" in *'could not verify the go (two state folders hold a counter); run /smartuse:doctor. Nothing was spent.'*) ok "39d the other direction (a counter copied into the full-key folder): run 2 is denied too";; *) ko "39d other direction run 2: stdout '${OUT:0:400}' stderr '$ERR' short counter: $(cat "$SR" 2>&1)";; esac
    [ "$(py "$CW" entry "$(wp "$SR")" used </dev/null 2>/dev/null)" = 1 ] && ok "39d ... and the short-key counter still says used 1" || ko "39d short counter: $(cat "$SR" 2>&1)"
    # a delete still resets the count (documented in SECURITY.md): remove the planted folder, the live counter runs again
    rm -rf "${FP:?}"; guard 'python render.py --images 1' "$ID2" "$LPW"
    [ -z "$OUT" ] && [ -z "$ERR" ] && [ "$(py "$CW" entry "$(wp "$SR")" used </dev/null 2>/dev/null)" = 2 ] && ok "39d with the planted folder removed, run 2 is counted: used 2" || ko "39d after the delete: stdout '${OUT:0:300}' stderr '$ERR' counter: $(cat "$SR" 2>&1)"
    [ "$(ls "$REAL_HOME/.claude/smartuse/projects" 2>/dev/null | grep -c 'aaaaaaaa')" = 0 ] && ok "39d the real ~/.claude/smartuse gained no folder from these cases" || ko "39d a test folder reached the real ~/.claude/smartuse/projects"
    # D14: a counter lands in the short-key folder after the early check (stubbed): the check under the counter lock denies, and nothing is counted
    rm -rf "${D:?}/lp" "${D:?}/snap"; LP=$(mklong "$LK"); fresh; mkdir -p "$LP/.claude" "$FP"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"
    guard 'python render.py --images 1' "$ID1" "$LPW"
    r=$(CLAUDE_PROJECT_DIR="$LPW" py "$CW" inproc "$(wp "$G")" "$LPW" race </dev/null 2>&1)
    case "$r" in *"deny "*"two state folders hold a counter"*) ok "39d D14: a counter that lands after the early check is caught under the counter lock: denied";; *) ko "39d D14 race: $r";; esac
    [ "$(py "$CW" entry "$(wp "$FR")" used </dev/null 2>/dev/null)" = 1 ] && ok "39d D14: nothing was counted (the full-key counter still says used 1)" || ko "39d D14 state: $(cat "$FR" 2>&1)"
    rm -rf "${D:?}/lp" "${D:?}/snap"
  fi
fi
# ===== 39e. 0.7.2 D14, any OS. paid_count is called with the folder it will use (the short-key one) and a full-key sibling that holds a counter: it denies under the lock and
# leaves the folder empty (0.7.4 F3 r5: PAID_LEFT, the folder in use holds no counter; a counter in the folder in use too is PAID_TWO); with no counter beside it, the same call counts. The sibling's counter is faked through os.path.isfile (a 240-character name cannot be made everywhere).
mkdir -p "$D/tl"; r=$(py "$CW" twolock "$(wp "$G")" "$(wp "$D/tl")" </dev/null 2>&1); [ "$r" = ok ] && ok "39e paid_count under the lock: a counter in the other state folder and none in the folder in use is denied as PAID_LEFT, nothing is written; without one the run is counted; then a counter in each folder is denied as PAID_TWO (0.7.4 F3 r5)" || ko "39e twolock: $r"
rm -rf "${D:?}/tl"
# ===== 39c. 0.7.2 F3 (D-YK20, the honest half), a kept state folder too long for paid runs is said aloud. A full-key folder that already exists is kept while a file
# of 26 characters fits in it (up to 232), but a real 30-character tool_use_id makes the claim marker paid.<id>.done 40 characters: in a folder of 219 to 232 characters,
# with Windows long paths off, that marker cannot be made, so no paid run was ever counted there, and the reason sent the owner to the adapter, which is not the fix. Now
# the reason says the folder's path is too long and names /smartuse:doctor; nothing is counted, no marker is left. Windows only, and only with LongPathsEnabled = 0.
if [ "$NT" != 1 ]; then skip "39c skipped here (not Windows: the 259-character path limit is Windows-only)"; else
  LPON=$(py -c 'import sys
try:
    import winreg
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\FileSystem") as k:
        sys.stdout.write("1" if winreg.QueryValueEx(k, "LongPathsEnabled")[0] == 1 else "0")
except Exception:
    sys.stdout.write("0")' </dev/null)   # the same read as wait-gate-test.sh section e: this machine's long-path switch (read only)
  LK=$(( 224 - BL )); LID=toolu_01ABCDEFGHIJKLMNOPQRSTUV
  if [ "$LPON" = 1 ]; then skip "39c skipped: Windows long paths are on here (LongPathsEnabled = 1), so a marker in a 225-character folder is made; the deny text is the only proof"
  elif [ "$LK" -lt 60 ]; then skip "39c skipped: HOME is $BL characters, too long to build a state folder of 225"; else
    rm -rf "$D/lp"; LP=$(mklong "$LK"); LPW=$(wp "$LP"); LKEY=$(key "$LPW"); LF="$HOME/.claude/smartuse/projects/$LKEY"
    fresh; mkdir -p "$LP/.claude" "$LF"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"
    [ "${#LID}" = 30 ] && [ "${#LKEY}" = "$LK" ] && ok "39c the kept state folder is $(( BL + 1 + LK )) characters, the tool_use_id 30 (marker 40)" || ko "39c key ${#LKEY} (wanted $LK), id ${#LID} (wanted 30)"
    guard 'python render.py --images 1' "$LID" "$LPW"
    case "$OUT" in *'could not verify the go (the state folder'*'path is too long for the counter'*'run /smartuse:doctor. Nothing was spent.'*) ok "39c a paid run in the kept 225-character folder: the reason says the path is too long and names /smartuse:doctor";; *) ko "39c reason: stdout '${OUT:0:400}' stderr '$ERR'";; esac
    case "$OUT" in *'smartuse.local.md'*) ko "39c the reason must not send the owner to the adapter: $OUT";; "") ko "39c no deny at all";; *) ok "39c ... and does not send the owner to smartuse.local.md (the adapter is not the fix)";; esac
    [ -z "$(ls -A "$LF" 2>/dev/null)" ] && ok "39c nothing counted and no claim marker or lock left in the folder" || ko "39c the folder holds: $(ls -A "$LF" 2>&1 | tr '\n' ' ')"
    rm -rf "$D/lp"; LK=$(( 209 - BL ))   # pin: a kept folder of 210 characters still counts (the marker path is 251)
    if [ "$LK" -lt 60 ]; then skip "39c pin skipped: HOME is $BL characters, too long to build a state folder of 210"; else
      LP=$(mklong "$LK"); LPW=$(wp "$LP"); LKEY=$(key "$LPW"); LF="$HOME/.claude/smartuse/projects/$LKEY"
      fresh; mkdir -p "$LP/.claude" "$LF"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"
      guard 'python render.py --images 1' "$LID" "$LPW"
      [ -z "$OUT" ] && [ -z "$ERR" ] && [ -f "$LF/paid-runs.json" ] && [ -f "$LF/paid.$LID.done" ] && ok "39c pin: in a kept folder of $(( BL + 1 + LK )) characters the same run is counted (no PAID_LONG there)" || ko "39c pin: stdout '${OUT:0:300}' stderr '$ERR' folder: $(ls -A "$LF" 2>&1 | tr '\n' ' ')"
    fi
    [ "$(ls "$REAL_HOME/.claude/smartuse/projects" 2>/dev/null | grep -c 'aaaaaaaa')" = 0 ] && ok "39c the real ~/.claude/smartuse gained no folder from these cases" || ko "39c a test folder reached the real ~/.claude/smartuse/projects"
    rm -rf "$D/lp"
  fi
fi
# ===== 39f. 0.7.3 F2 (D-YK25, E1), a real counter left in a folder fit_key no longer uses. A project whose full-key state folder is 240 characters (E1: 233 to 244 characters is where plain file
# calls still reach a counter, its own path is at most 259; from 245 the paid check cannot see it) holds paid-runs.json. With Windows long paths off fit_key sends the project to the short key. This
# is a pin, green on 54f4b75 by trace: the paid call is refused (0.7.4 F3 r6: now with the left-behind words, "the paid counter is in a state folder that is no longer used"; 54f4b75 said "two state folders hold a counter"), nothing is counted, the counter's bytes stay (39e fakes the file check, so
# no test had run it on a real folder). Then heartbeat.py --doctor for the same project names the same two folders (it said "writable" only). Windows only, and only with LongPathsEnabled = 0.
if [ "$NT" != 1 ]; then skip "39f skipped here (not Windows: the 259-character path limit is Windows-only)"; else
  LPON=$(py -c 'import sys
try:
    import winreg
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\FileSystem") as k:
        sys.stdout.write("1" if winreg.QueryValueEx(k, "LongPathsEnabled")[0] == 1 else "0")
except Exception:
    sys.stdout.write("0")' </dev/null)   # the same read as 39c: this machine's long-path switch (read only)
  LK=$(( 239 - BL )); ID1=toolu_01ABCDEFGHIJKLMNOPQRSTUV
  if [ "$LPON" = 1 ]; then skip "39f skipped: Windows long paths are on here (LongPathsEnabled = 1), a 240-character full-key folder is kept and the layout cannot arise"
  elif [ "$LK" -lt 60 ]; then skip "39f skipped: HOME is $BL characters, too long to build a state folder of 240"; else
    rm -rf "${D:?}/lp"; LP=$(mklong "$LK"); LPW=$(wp "$LP"); LKEY=$(key "$LPW"); PR="$HOME/.claude/smartuse/projects"; FP="$PR/$LKEY"; FR="$FP/paid-runs.json"
    LNAME=$(py -c "import hashlib, sys; k = sys.argv[1]; sys.stdout.write((k[-40:] + '-' + hashlib.sha1(k.encode()).hexdigest()[:12]).lstrip('-'))" "$LKEY" </dev/null)   # the short-key folder's name, worked out the suite's own way
    fresh; mkdir -p "$LP/.claude" "$FP"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"; printf '{}' > "$FR"
    [ "${#LKEY}" = "$LK" ] && [ -f "$FR" ] && ok "39f the full-key folder is $(( BL + 1 + LK )) characters and holds paid-runs.json" || ko "39f key ${#LKEY} (wanted $LK), counter: $(ls -A "$FP" 2>&1 | tr '\n' ' ')"
    guard 'python render.py --images 1' "$ID1" "$LPW"
    case "$OUT" in *'could not verify the go (the paid counter is in a state folder that is no longer used); run /smartuse:doctor. Nothing was spent.'*) ok "39f the paid call is refused: the paid counter is in a state folder that is no longer used (0.7.4 F3 r6), the reason names /smartuse:doctor";; *) ko "39f paid call: stdout '${OUT:0:400}' stderr '$ERR'";; esac
    endrule "39f the left-behind reason is one ASCII line and ends Nothing was spent. [rule paid]" noadapter
    [ "$(cat "$FR" 2>/dev/null)" = '{}' ] && [ "$(ls -A "$FP" | tr '\n' ' ')" = "paid-runs.json " ] && [ -z "$(ls -A "$PR/$LNAME" 2>/dev/null)" ] && ok "39f nothing was counted: the counter's bytes are unchanged, no marker, the short-key folder holds nothing" || ko "39f state: full $(ls -A "$FP" 2>&1 | tr '\n' ' ') counter '$(cat "$FR" 2>&1)' short '$(ls -A "$PR/$LNAME" 2>&1 | tr '\n' ' ')'"
    DOUT=$(CLAUDE_PROJECT_DIR="$LPW" py "$H/heartbeat.py" --doctor </dev/null); DN=$(printf '%s\n' "$DOUT" | wc -l)
    case "$DOUT" in *"state folder: FAIL"*"$LKEY"*"(240 characters)"*"$LNAME"*) [ "$DN" -le 8 ] && ok "39f doctor for the same project names the same two folders and 240 characters ($DN lines)" || ko "39f doctor has $DN lines (limit 8)";; *) ko "39f doctor: $(printf '%s' "$DOUT" | grep 'state folder')";; esac
    [ "$(cat "$FR" 2>/dev/null)" = '{}' ] && [ "$(ls -A "$FP" | tr '\n' ' ')" = "paid-runs.json " ] && [ -z "$(ls -A "$PR/$LNAME" 2>/dev/null)" ] && ok "39f doctor left both folders as they were" || ko "39f doctor touched the folders: full $(ls -A "$FP" 2>&1 | tr '\n' ' ') short '$(ls -A "$PR/$LNAME" 2>&1 | tr '\n' ' ')'"
    [ "$(ls "$REAL_HOME/.claude/smartuse/projects" 2>/dev/null | grep -c 'aaaaaaaa')" = 0 ] && ok "39f the real ~/.claude/smartuse gained no folder from these cases" || ko "39f a test folder reached the real ~/.claude/smartuse/projects"
    rm -rf "${D:?}/lp"
  fi
fi
# ===== 39g. 0.7.4 F1 (E1), a counter in the other state folder is seen at ANY length. 39f is the 240-character window, where plain file calls still reach the counter. From 245 characters
# the counter's own path passes 259, os.path.isfile says "no" with Windows long paths off, and the paid call was allowed and counted again in the short folder (used 1). Now the check also
# looks through the extended-length form. Real folders, made the way E1e proved (Git Bash mkdir -p and a redirect; rm -rf takes them away): g1 250 characters with a counter and an adapter
# go -> refused with the left-behind words (0.7.4 F3 r6), the counter's bytes unchanged, nothing in the short folder; g2 the same at 245 and 270; g3 a counter in BOTH folders at 250 -> the 39d words
# (two state folders hold a counter); g4 pin: 240 keeps 39f's outcome. Windows only, and only with LongPathsEnabled = 0 (read only).
if [ "$NT" != 1 ]; then skip "39g skipped here (not Windows: the 259-character path limit is Windows-only)"; else
  LPON=$(py -c 'import sys
try:
    import winreg
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\FileSystem") as k:
        sys.stdout.write("1" if winreg.QueryValueEx(k, "LongPathsEnabled")[0] == 1 else "0")
except Exception:
    sys.stdout.write("0")' </dev/null)   # the same read as 39c and 39f: this machine's long-path switch (read only)
  ID1=toolu_01ABCDEFGHIJKLMNOPQRSTUV; GOUT='could not verify the go (two state folders hold a counter); run /smartuse:doctor. Nothing was spent.'; GLEFT='could not verify the go (the paid counter is in a state folder that is no longer used); run /smartuse:doctor. Nothing was spent.'
  if [ "$LPON" = 1 ]; then skip "39g skipped: Windows long paths are on here (LongPathsEnabled = 1), a long full-key folder is kept and plain calls see it, so the layout cannot arise"
  elif [ $(( 239 - BL )) -lt 60 ]; then skip "39g skipped: HOME is $BL characters, too long to build a state folder of 240"; else
    for GL in 250 245 270 240; do   # the state folder's length: g1, g2, g2, g4 (the pin)
      case "$GL" in 250) T=g1;; 240) T=g4;; *) T=g2;; esac
      LK=$(( GL - 1 - BL )); rm -rf "${D:?}/lp"; LP=$(mklong "$LK"); LPW=$(wp "$LP"); LKEY=$(key "$LPW"); PR="$HOME/.claude/smartuse/projects"; FP="$PR/$LKEY"; FR="$FP/paid-runs.json"
      LNAME=$(py -c "import hashlib, sys; k = sys.argv[1]; sys.stdout.write((k[-40:] + '-' + hashlib.sha1(k.encode()).hexdigest()[:12]).lstrip('-'))" "$LKEY" </dev/null)   # the short-key folder's name, worked out the suite's own way
      fresh; mkdir -p "$LP/.claude" "$FP"; printf '%s\nprint("would call")\n' "$IMP" > "$LP/render.py"; printf 'paid: render.py x 10, cap RM5, test ok\n' > "$LP/.claude/smartuse.local.md"; printf '{"yk":1}' > "$FR"
      [ "${#LKEY}" = "$LK" ] && [ -f "$FR" ] && ok "39g $T the full-key folder is $GL characters (the counter's path $(( GL + 15 ))) and holds paid-runs.json" || ko "39g $T key ${#LKEY} (wanted $LK), counter: $(ls -A "$FP" 2>&1 | tr '\n' ' ')"
      guard 'python render.py --images 1' "$ID1" "$LPW"
      case "$OUT" in *"$GLEFT"*) ok "39g $T the paid call is refused at $GL characters: the paid counter is in a state folder that is no longer used (0.7.4 F3 r6), the reason names /smartuse:doctor";; *) ko "39g $T paid call at $GL: stdout '${OUT:0:400}' stderr '$ERR'";; esac
      [ "$(cat "$FR" 2>/dev/null)" = '{"yk":1}' ] && [ "$(ls -A "$FP" | tr '\n' ' ')" = "paid-runs.json " ] && [ -z "$(ls -A "$PR/$LNAME" 2>/dev/null)" ] && ok "39g $T nothing was counted: the counter's bytes are unchanged, no marker, the short-key folder holds no counter and no marker" || ko "39g $T state: full $(ls -A "$FP" 2>&1 | tr '\n' ' ') counter '$(cat "$FR" 2>&1)' short '$(ls -A "$PR/$LNAME" 2>&1 | tr '\n' ' ')'"
      if [ "$GL" = 250 ]; then   # 0.7.4 F2, the doctor half of g1: heartbeat.py --doctor for the same project names the same two folders the refusal is about, 250 characters, and the way out E1e proved (it said "writable" only)
        DOUT=$(CLAUDE_PROJECT_DIR="$LPW" py "$H/heartbeat.py" --doctor </dev/null); DN=$(printf '%s
' "$DOUT" | wc -l)
        case "$DOUT" in *"state folder: FAIL"*"$LKEY (250 characters)"*"$LNAME"*"delete ~/.claude/smartuse/projects/$LKEY with rm -rf in Git Bash"*) [ "$DN" -le 8 ] && ok "39g g1 doctor for the same project names the same two folders, 250 characters and rm -rf in Git Bash ($DN lines)" || ko "39g g1 doctor has $DN lines (limit 8)";; *) ko "39g g1 doctor: $(printf '%s' "$DOUT" | grep 'state folder')";; esac
        [ "$(cat "$FR" 2>/dev/null)" = '{"yk":1}' ] && [ "$(ls -A "$FP" | tr '
' ' ')" = "paid-runs.json " ] && [ -z "$(ls -A "$PR/$LNAME" 2>/dev/null)" ] && ok "39g g1 doctor left both folders as they were" || ko "39g g1 doctor touched the folders: full $(ls -A "$FP" 2>&1 | tr '
' ' ') short '$(ls -A "$PR/$LNAME" 2>&1 | tr '
' ' ')'"
      fi
      if [ "$GL" = 250 ]; then   # g3: the miss already happened, a counter in both folders
        mkdir -p "$PR/$LNAME"; printf '{"yk":2}' > "$PR/$LNAME/paid-runs.json"
        guard 'python render.py --images 1' "$ID1" "$LPW"
        case "$OUT" in *"$GOUT"*) ok "39g g3 a counter in both folders at 250 characters: the paid call is refused with the two-counters words";; *) ko "39g g3 paid call: stdout '${OUT:0:400}' stderr '$ERR'";; esac
        endrule "39g g3 the two-counters reason is one ASCII line and ends Nothing was spent. [rule paid]" noadapter
        [ "$(cat "$FR" 2>/dev/null)" = '{"yk":1}' ] && [ "$(cat "$PR/$LNAME/paid-runs.json" 2>/dev/null)" = '{"yk":2}' ] && [ "$(ls -A "$FP" | tr '\n' ' ')" = "paid-runs.json " ] && [ "$(ls -A "$PR/$LNAME" | tr '\n' ' ')" = "paid-runs.json " ] && ok "39g g3 both counters' bytes are unchanged and no marker was made" || ko "39g g3 state: full '$(cat "$FR" 2>&1)' short '$(cat "$PR/$LNAME/paid-runs.json" 2>&1)' folders: $(ls -A "$FP" "$PR/$LNAME" 2>&1 | tr '\n' ' ')"
      fi
    done
    [ "$(ls "$REAL_HOME/.claude/smartuse/projects" 2>/dev/null | grep -c 'aaaaaaaa')" = 0 ] && ok "39g the real ~/.claude/smartuse gained no folder from these cases" || ko "39g a test folder reached the real ~/.claude/smartuse/projects"
    rm -rf "${D:?}/lp" "$HOME/.claude/smartuse/projects"
    [ ! -e "$D/lp" ] && [ -z "$(ls -A "$HOME/.claude/smartuse/projects" 2>/dev/null)" ] && ok "39g the long folders were removed the way they were made (rm -rf)" || ko "39g left behind: $(ls -A "$D/lp" "$HOME/.claude/smartuse/projects" 2>&1 | head -c 300 | tr '\n' ' ')"
  fi
fi
# ===== 39h. 0.7.4 F1, any OS, in process. long_form is pure text (a table of 25 rows: a drive path, forward slashes, a share, already long, a 302-character path, not Windows, a device path,
# relative, drive-relative, .. . and empty parts, a non-ASCII drive letter, odd inputs). counter_in with os.path.isfile stood in, the 39e way: the plain look first and alone when it says yes,
# then the long form; both false; not Windows never tries the long form; a base the long form cannot spell gets the plain look only.
r=$(py "$CW" longform "$(wp "$G")" </dev/null 2>&1); [ "$r" = ok ] && ok "39h long_form: the 25-row table (drive, slashes, share, already long, 302 characters, nt false, device, relative, C:x, .. . and empty parts) answers as wanted and never raises" || ko "39h long_form: $r"
r=$(py "$CW" counterin "$(wp "$G")" </dev/null 2>&1); [ "$r" = ok ] && ok "39h counter_in: plain true; plain false and long form true; both false; nt false never tries the long form; an unspellable base gets the plain look only" || ko "39h counter_in: $r"
# ===== 39i. 0.7.4 F1, any OS (pin). A project whose key fits makes no call to counter_in, in the early check and under the counter lock (counted calls: 0), so a short path costs nothing more;
# a project whose key does not fit does call it (the control, so the count cannot be zero by accident).
mkdir -p "$D/tl"; r=$(py "$CW" nocall "$(wp "$G")" "$(wp "$D/tl")" </dev/null 2>&1); [ "$r" = ok ] && ok "39i a project whose key fits makes no call to counter_in (early check and under the lock); one that does not fit does" || ko "39i nocall: $r"
rm -rf "${D:?}/tl"
# ===== 39j. 0.7.4 F3 r1, any OS, in process. paid_why picks the too-long words by the error the system gave (E1d: a name that does not fit is a FileNotFoundError on Windows past 259; a read-only counter is a PermissionError), not by the length.
r=$(py "$CW" paidwhy "$(wp "$G")" </dev/null 2>&1); [ "$r" = ok ] && ok "39j F3 r1 paid_why: too long only on Windows, past 259, with a FileNotFoundError (a PermissionError or another error says not writable; 200 characters and not Windows never too long; no error object keeps the length rule); paid_write_json hands its error back through a list" || ko "39j paid_why: $r"
TPATH=
PGTOOL=Bash
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
