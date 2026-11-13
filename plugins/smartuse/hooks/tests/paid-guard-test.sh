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
export HOME="$D/home"; mkdir -p "$HOME/.claude/smartuse" "$D/proj"   # ~/.claude/smartuse exists, so py.sh remembers the interpreter: one start per call
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it (cygpath -m -> C:/Users/...); elsewhere unchanged
key() { py -c "import re,sys,pathlib; print(re.sub(r'[^A-Za-z0-9._-]','-',str(pathlib.Path(sys.argv[1]).resolve())).lstrip('-'))" "$1"; }   # the hooks' state-dir rule: the full resolved path, every character outside [A-Za-z0-9._-] -> "-", no leading "-"
jstr() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; printf '%s' "$s"; }   # a JSON string body
fail=0; n=0
ok() { n=$((n+1)); echo "PASS $1"; }
ko() { n=$((n+1)); echo "FAIL $1"; fail=1; }
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
    assert names <= top | {"hashlib", "pathlib"} and {"hashlib", "pathlib"} <= names, names
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
PY
CW=$(wp "$D/chk.py")

# --- the harness: one PreToolUse event in the shape Claude Code sends (session_id, transcript_path, cwd, permission_mode, tool_use_id)
guard() { # $1 = command, $2 = tool_use_id ("-" = none), $3 = cwd (default the project) -> $OUT (stdout) and $ERR (stderr)
  local tid=${2:-toolu_01} idf; idf=$(printf ',"tool_use_id":"%s"' "$tid"); [ "$tid" = "-" ] && idf=""
  IN=$(printf '{"session_id":"sid-test","transcript_path":"%s","cwd":"%s","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"Bash"%s,"tool_input":{"command":"%s"}}' "$(wp "$D/none.jsonl")" "${3:-$PW}" "$idf" "$(jstr "$1")")
  OUT=$(printf '%s' "$IN" | py "$G" 2>"$D/err"); ERR=$(cat "$D/err")
}
fresh() { rm -rf "$HOME/.claude/smartuse/projects" "$D/proj/.claude"; mkdir -p "$D/proj/.claude"; }   # a case starts with no state and no adapter
adapter() { printf '%b' "$1" > "$D/proj/.claude/smartuse.local.md"; }
deny() { # $1 = label, $2 = command, $3 = a text the reason must hold, $4 = tool_use_id
  guard "$2" "${4:-}"
  if [ -n "$OUT" ] && [ -z "$ERR" ]; then case "$OUT" in *"bash-guard: paid call ("*"$3"*) ok "$1";; *) ko "$1 -- the reason lacks '$3': $OUT";; esac; else ko "$1 -- wanted a deny, got stdout '$OUT' stderr '$ERR'"; fi
}
allow() { guard "$2" "${3:-}"; [ -z "$OUT" ] && [ -z "$ERR" ] && ok "$1" || ko "$1 -- wanted silence, got stdout '$OUT' stderr '$ERR'"; }
field() { py "$CW" entry "$(wp "$R")" "$1" </dev/null; }
IMP=$(printf 'import %s' openai)                                  # the SDK line, never spelled whole in this file
mkpaid() { printf '%s\nprint("would call")\n' "$IMP" > "$D/proj/render.py"; }   # render.py: names an SDK -> a paid script
mkplain() { printf 'print("%s")\n' "$1" > "$D/proj/$1.py"; }                    # <name>.py: names nothing paid
mkplain polish

# ===== 1. INCIDENT REPLAY 1: the batch command, the Gemini key in its source, no go anywhere -> denied at the first call
fresh; printf 'import os\nKEY = os.environ["%s_API_KEY"]\nprint("batch of 6")\n' GEMINI > "$D/proj/render.py"
deny "incident replay: python render.py --images 6, the key in the source, no go -> denied at the first call" 'python render.py --images 6' 'GEMINI_API_KEY in render.py'
case "$OUT" in *'bash-guard: paid call (GEMINI_API_KEY in render.py) '*) ok "the reason starts bash-guard: paid call (<signal>) and names the key and the script";; *) ko "reason start: $OUT";; esac
case "$OUT" in *'no go from the owner for render.py. The owner types in this session: \"paid go: render.py x <runs>, cap <amount>\" (or adds \"paid: render.py x <runs>, cap <amount>\" to .claude/smartuse.local.md). Nothing was spent.'*) ok "... and gives the exact lines to type, ending Nothing was spent.";; *) ko "reason body: $OUT";; esac
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
fresh; adapter 'paid: render.py x 10, cap RM5\n'; mkpaid; guard 'python render.py' toolu_1; mkdir -p "$P"; printf '{broken' > "$R"
deny "a corrupt paid-runs.json -> deny: could not verify the go" 'python render.py' 'could not verify the go (paid-runs.json is unreadable)' toolu_2
[ "$(cat "$R")" = '{broken' ] && ok "... and the file is left as it was: never a silent reset" || ko "the corrupt counter was changed: $(cat "$R")"
printf '[1,2]' > "$R"
deny "a counter file that is JSON but not an object -> deny" 'python render.py' 'could not verify the go (paid-runs.json is unreadable)' toolu_3
fresh; adapter 'paid: render.py x 10, cap RM5\n'; mkpaid; mkdir -p "$HOME/.claude/smartuse/projects"; : > "$P"
deny "the state dir cannot be created (a file sits where it goes) -> deny: could not verify the go" 'python render.py' 'could not verify the go (' toolu_4
fresh; mkpaid
guard 'python polish.py'; [ -z "$OUT" ] && [ -z "$ERR" ] && ok "a call that is not paid is let through whatever the state (detection errors fail open as before)" || ko "plain call: $OUT $ERR"
printf '{"tool_name":"Bash","tool_input":' | py "$G" > "$D/out" 2>&1; [ ! -s "$D/out" ] && ok "garbage on stdin -> silent, no deny (fail open, as before)" || ko "garbage stdin: $(cat "$D/out")"
rm -f "$D/proj/render.py"; adapter 'paid: render.py x 3, cap RM2\n'
allow "a script path that does not exist is no error: with the go it passes" 'python render.py --n 1'

# ===== 7. the cwd in the Git Bash form; a script in another directory by absolute path; no .env is read
case "$PW" in [A-Za-z]:/*)   # Windows: the cwd as Git Bash writes it, /c/Users/... (a JSON string the hook must convert; "/tmp/..." has no drive and stays)
  fresh; mkpaid; U="/$(printf '%s' "${PW:0:1}" | tr 'A-Z' 'a-z')${PW:2}"
  guard 'python render.py' toolu_u "$U"; case "$OUT" in *"$IMP in render.py"*) ok "cwd $U (the Git Bash form) still finds the script: converted by native_path";; *) ko "cwd in the MSYS form $U: '$OUT' '$ERR'";; esac;;
*) ok "cwd in the Git Bash form: skipped (not a Windows drive path on this OS)";; esac
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
case "$OUT" in *'waits for the owner'\''s \"test ok\" (typed in this session). Show the owner the one output first.'*) ok "... the reason says test ok is typed in this session and to show the owner the one output first";; *) ko "waits reason: $OUT";; esac
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
deny "a corrupt counter -> deny: could not verify the go" 'python render.py --n 1' 'could not verify the go (paid-runs.json is unreadable)' toolu_k2
cp "$D/saved.json" "$R"
allow "the file restored: the same go carries on" 'python render.py --n 1' toolu_k3
[ "$(used)" = 2 ] && ok "... used 2: counted on from the restored file, never reset to 0" || ko "used after the restore: $(used)"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'
guard 'python render.py --n 1' toolu_w1
chmod a-w "$R" "$P" 2>/dev/null   # POSIX: the read-only dir blocks the lock / marker; Windows: the read-only counter file blocks os.replace
guard 'python render.py --n 1' toolu_w2
if [ -n "$OUT" ]; then case "$OUT" in *'could not verify the go (the counter is not writable); put it in .claude/smartuse.local.md. Nothing was spent.'*) ok "an unwritable counter -> deny: could not verify the go (the counter is not writable)";; *) ko "unwritable reason: $OUT";; esac
elif [ "$(id -u 2>/dev/null)" = 0 ]; then ok "an unwritable counter: skipped (root ignores read-only)"; else ko "an unwritable counter let the call through: '$OUT' '$ERR'"; fi
chmod u+w "$P" "$R" 2>/dev/null
[ "$(used)" = 1 ] && [ ! -e "$P/paid.toolu_w2.done" ] && ok "... nothing counted (used 1) and the claim marker released" || ko "after the unwritable deny: used $(used), $(ls "$P")"
allow "writable again: the same call passes" 'python render.py --n 1' toolu_w2
[ "$(used)" = 2 ] && ok "... used 2" || ko "used after the retry: $(used)"

# ===== 11. the lock around the read-modify-write: held -> deny (fail closed); stale -> taken over; parallel calls cannot both pass the cap
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, test ok\n'; mkdir -p "$P"; : > "$P/paid-runs.lock"
deny "a lock held by another call -> deny after a short wait: the counter is busy" 'python render.py --n 1' 'could not verify the go (the counter is busy); put it in .claude/smartuse.local.md. Nothing was spent.' toolu_l1
[ -e "$P/paid-runs.lock" ] && [ ! -e "$R" ] && ok "... the other holder's lock is left alone and nothing was counted" || ko "after a busy deny: $(ls "$P")"
py "$CW" age "$(wp "$P/paid-runs.lock")" 120 </dev/null
allow "a stale lock (120 s old) is taken over: the call passes" 'python render.py --n 1' toolu_l2
[ "$(used)" = 1 ] && [ ! -e "$P/paid-runs.lock" ] && ok "... counted (used 1) and the lock is released" || ko "after a stale lock: used $(used), $(ls "$P")"
ls "$P"/*.lock >/dev/null 2>&1 && ko "a lock was left after a normal call" || ok "a normal call leaves no lock behind"
fresh; mkpaid; adapter 'paid: render.py x 2, cap RM1, test ok\n'
ev() { printf '{"session_id":"sid-test","transcript_path":"%s","cwd":"%s","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":"%s"}}' "$(wp "$D/none.jsonl")" "$PW" "$1" "$(jstr "$2")"; }
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
dt=$(printf '%s' "$r" | awk '{print $2}'); awk -v x="$dt" 'BEGIN{exit !(x+0 < 0.8)}' && ok "... and the wait ends at the deadline (0.3 s here), not after the lock's own second: $dt s" || ko "the lock wait ran to $dt s"
fresh; mkpaid; adapter 'paid: render.py x 10, cap RM5, count none\n'
r=$(py "$CW" inproc "$(wp "$G")" "$PW" deadline </dev/null 2>&1)
case "$r" in *'could not verify the go (the hook ran past its deadline)'*'[rule paid]'*) ok "a call already seen as paid, past the hook's deadline: denied (could not verify)";; *) ko "past the deadline: $r";; esac
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
  IN=$(printf '{"session_id":"sid-test","transcript_path":"%s","cwd":"%s","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"%s","tool_use_id":"%s","tool_input":%s}' "$(wp "$D/none.jsonl")" "$PW" "$1" "${3:-toolu_x1}" "$2")
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
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
