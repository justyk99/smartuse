#!/usr/bin/env bash
# Self-contained test for hooks/recall.py — the PreCompact + SessionStart hook behind "the summary is not a source"
# (docs/notes/recall-design.md, F2 and F3). Every transcript is SYNTHETIC: records in the shapes Claude Code writes (human prompts with
# turnOrigin / origin.kind, peer and task-notification records, meta records, compact_boundary and compact-summary markers, tool results,
# sidechain records, a mid-turn queued_command), with invented text, paths (jobs/demo/plan.pdf, photos/a.jpg) and fake secrets (sk- plus
# a run of x's). No real path, name or message.
# Covered: PreCompact (source paths and owner prompts to keep verbatim, custom instructions first, the "from summary" rule) · the owner-prompt
# filter (peer, task notification, meta, summary, tool result, sidechain, command echo, reminder never quoted; sdk, older records and a
# mid-turn message quoted; last 8, oldest first, whitespace collapsed, cut at 300) · the scrub (tokens, 10-digit run, e-mail masked;
# task-folder kept) · the 9,000 cap on a 2 MB transcript · SessionStart compact (squeeze time, the sentence, sources, prompts, the
# two-line form without sources, state counting) · startup / clear / resume (handoff lines, age, stale line, missing file, resumed line,
# sources) · "nothing is gated" once · publish_tools entries the matcher cannot reach · adapter parsing (first line wins, quotes, empty
# values, CRLF) · project dir order · bad stdin, garbage transcripts, cp1252 bytes · the state dir equal to ledger.py's · nothing written
# in the project · stdlib-only imports · the hooks.json entries.
# One temp dir under ${TMPDIR:-/tmp}/smartuse-recall.XXXXXX, the only thing removed on exit; temp HOME. Every PASS / FAIL line is one
# check; exit 1 on failure.
set -u
H="$(cd "$(dirname "$0")/.." && pwd)"; HOOK="$H/recall.py"
D=$(mktemp -d "${TMPDIR:-/tmp}/smartuse-recall.XXXXXX") && [ -d "$D" ] || { echo "FAIL could not create a temp dir under ${TMPDIR:-/tmp}"; exit 1; }
trap 'case "$D" in */smartuse-recall.*) rm -rf "$D" 2>/dev/null;; esac' EXIT   # removes this run's own dir and nothing else
export HOME="$D/home"; export USERPROFILE="$HOME"; mkdir -p "$HOME/.claude/smartuse" "$D/proj/.claude" "$D/proj/docs" "$D/t" "$D/other"   # ~/.claude/smartuse exists, so py.sh remembers the interpreter: one start per call
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, not inside JSON strings (cygpath -m -> C:/Users/...); elsewhere unchanged
key() { py -c "import re,sys,pathlib; print(re.sub(r'[^A-Za-z0-9._-]','-',str(pathlib.Path(sys.argv[1]).resolve())).lstrip('-'))" "$1"; }   # the hooks' state-dir rule: the full resolved path, every character outside [A-Za-z0-9._-] -> "-", no leading "-"
fail=0
ok() { echo "PASS $1"; }
ko() { echo "FAIL $1"; fail=1; }
[ "$(py -c 'print("ok")' </dev/null 2>/dev/null)" = ok ] || { echo "FAIL no python 3 (python3, python or py -3) through $H/py.sh"; exit 1; }
# RECALL_REF=<git ref> runs the same cases against recall.py as that commit had it (read into this run's temp dir): how a new case is
# shown failing on the code before the change. Unset, the working copy is tested.
if [ -n "${RECALL_REF:-}" ]; then
  HOOK="$D/recall-ref.py"
  MSYS_NO_PATHCONV=1 git -C "$(wp "$H")" show "$RECALL_REF:plugins/smartuse/hooks/recall.py" > "$HOOK" 2> "$D/git.err"
  [ -s "$HOOK" ] || { echo "FAIL could not read recall.py at $RECALL_REF: $(head -c 300 "$D/git.err")"; exit 1; }
  echo "NOTE testing recall.py of $RECALL_REF, not the working copy"
fi
PW=$(wp "$D/proj"); K=$(key "$PW"); P="$HOME/.claude/smartuse/projects/$K"; ST="$P/recall.json"   # the state dir of the project every case runs in
PO=$(wp "$D/other")

# --- the synthetic transcripts and the static checks: mk.py writes every case to $D/t/<case>.jsonl in one start
cat > "$D/mk.py" <<'PY'
import datetime, json, os, sys

OUT = sys.argv[1]
NOW = datetime.datetime.now(datetime.timezone.utc)


def stamp(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (dt.microsecond // 1000)


class T(object):
    """One synthetic transcript: 11 s between records, the first 30 minutes ago."""

    def __init__(self):
        self.recs, self.n, self.t = [], 0, NOW - datetime.timedelta(minutes=30)

    def uid(self):
        self.n += 1
        return "00000000-0000-4000-8000-%012d" % self.n

    def rec(self, **r):
        self.t += datetime.timedelta(seconds=11)
        r.setdefault("uuid", self.uid())
        r.setdefault("timestamp", stamp(self.t))
        r.setdefault("sessionId", "sid-test")
        r.setdefault("isSidechain", False)
        self.recs.append(r)
        return r

    def human(self, text, **kw):
        return self.rec(type="user", userType="external", entrypoint="cli", turnOrigin="human", promptSource="sdk",
                        origin={"kind": "human"}, promptId=self.uid(), message={"role": "user", "content": text}, **kw)

    def user(self, content, **kw):
        return self.rec(type="user", userType="external", entrypoint="cli", message={"role": "user", "content": content}, **kw)

    def say(self, text):
        self.n += 1
        return self.rec(type="assistant", requestId="req_TEST%04d" % self.n, message={"id": "msg_TEST%04d" % self.n, "type": "message", "role": "assistant",
                        "model": "test-model", "content": [{"type": "text", "text": text}], "stop_reason": "end_turn"})

    def tool(self, name, inp, result):
        self.n += 1
        tid = "toolu_TEST%04d" % self.n
        self.rec(type="assistant", message={"id": "msg_TEST%04d" % self.n, "type": "message", "role": "assistant", "model": "test-model",
                 "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}], "stop_reason": "tool_use"})
        self.user([{"type": "tool_result", "tool_use_id": tid, "content": result}], toolUseResult={"stdout": result})

    def boundary(self, ago_s):
        return self.rec(type="system", subtype="compact_boundary", content="Conversation compacted",
                        timestamp=stamp(NOW - datetime.timedelta(seconds=ago_s)))

    def summary(self, text="SUMMARYTEXT the model wrote this itself"):
        return self.rec(type="user", isCompactSummary=True, isVisibleInTranscriptOnly=True, message={"role": "user", "content": text})

    def save(self, name):
        with open(os.path.join(OUT, name + ".jsonl"), "w", encoding="utf-8", newline="\n") as f:
            for r in self.recs:
                f.write(json.dumps(r) + "\n")


# main: ten genuine prompts, every kind of record that is not one, and a squeeze 60 s ago
t = T()
t.human("PROMPT-01 first request")
t.human("PROMPT-02 second request")
t.say("working on it")
t.tool("Read", {"file_path": "jobs/demo/plan.pdf"}, "TOOLRESULT-TEXT the file body")
t.human("PROMPT-03 third request")
t.user("Another Claude session sent a message: <agent-message from=\"builder\">PEER-TEXT</agent-message>", isMeta=True, turnOrigin="peer",
       promptSource="system", origin={"kind": "peer", "from": "builder"})
t.human("PROMPT-04 line one\n\n   line   two")
t.user("<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n<summary>TASKNOTE-TEXT</summary>\n</task-notification>",
       turnOrigin="task_notification", promptSource="system", origin={"kind": "task-notification"})
t.human("PROMPT-05 fifth request")
t.user("META-TEXT skill body", isMeta=True)
t.rec(type="user", userType="external", entrypoint="sdk-cli", turnOrigin="sdk", origin={"kind": "sdk"}, promptId=t.uid(),
      message={"role": "user", "content": [{"type": "text", "text": "PROMPT-06 sent through the SDK"}]})
t.rec(type="user", isSidechain=True, turnOrigin="human", origin={"kind": "human"}, message={"role": "user", "content": "SIDECHAIN-TEXT a subagent's prompt"})
t.user("PROMPT-07 an older record with no origin fields")
t.user("<command-name>/clear</command-name> CMDECHO-TEXT")
t.user("<system-reminder>REMINDER-TEXT</system-reminder>")
t.rec(type="attachment", attachment={"type": "queued_command", "prompt": "PROMPT-08 typed while Claude was working", "commandMode": "prompt",
                                     "origin": {"kind": "human"}})
t.rec(type="attachment", attachment={"type": "queued_command", "prompt": "QUEUED-PEER-TEXT", "origin": {"kind": "peer"}})
t.rec(type="queue-operation", operation="enqueue", content="QUEUE-OP-TEXT user")
t.human("PROMPT-09 " + "a" * 500)
t.boundary(60)
t.summary()
t.human("PROMPT-10 after the squeeze")
t.save("main")
open(os.path.join(OUT, "hhmm-boundary"), "w").write((NOW - datetime.timedelta(seconds=60)).astimezone().strftime("%H:%M"))

# old: the only marker is three hours old (an earlier squeeze: the new one is not written yet)
t = T()
t.human("PROMPT-OLD request")
t.boundary(3 * 3600)
t.summary()
t.save("old")

# sumonly: a compact summary record and no boundary (the fallback marker)
t = T()
t.human("PROMPT-S1 request")
t.summary()
t.save("sumonly")

# plain: no squeeze at all
t = T()
t.human("PROMPT-P1 request")
t.say("done")
t.save("plain")

# secret: a prompt full of things that must be masked
t = T()
t.human("use sk-xxxxxxxxxxxxxxxxxxxx and ghp_xxxxxxxxxxxxxxxxxxxxxxxx and AKIAxxxxxxxxxxxxxxxx, mail yk@example.test, call 0123456789 not 1234567, keep task-folder jobs/demo")
t.save("secret")

# digits: free-standing digit runs are masked, runs inside a name or a path are kept
t = T()
t.human("call 0234567891 now, acct 1234567892. also +60198765432 and ref-12345678 and photos/20261108.jpg and photos/IMG_20261108_140233.jpg")
t.save("digits")

# big: about 2 MB of records, the last prompt at the end
t = T()
for i in range(1, 2201):
    t.human("PROMPT-BIG-%04d %s" % (i, "word " * 150))
    t.say("ok " + "y" * 200)
t.human("PROMPT-BIG-LAST the end")
t.save("big")

# garbage: lines that are not records, then one genuine prompt
with open(os.path.join(OUT, "garbage.jsonl"), "wb") as f:
    f.write(b'not json at all "user"\n{"type":"user"\n[]\n"user"\n\xff\xfe\x00 "user"\n')
    f.write((json.dumps({"type": "user", "turnOrigin": "human", "message": {"role": "user", "content": "PROMPT-OK after the garbage"}}) + "\n").encode("utf-8"))

# an event file with Windows-style backslash paths (written here: a command line can collapse \\)
pw, tp = sys.argv[2].replace("/", "\\"), os.path.join(OUT, "main.jsonl").replace("/", "\\")
with open(os.path.join(OUT, "ev-backslash.json"), "w", encoding="utf-8") as f:
    json.dump({"hook_event_name": "PreCompact", "session_id": "sid-test", "cwd": pw, "transcript_path": tp, "trigger": "manual"}, f)
PY
py "$D/mk.py" "$(wp "$D/t")" "$PW" || { echo "FAIL could not build the synthetic transcripts"; exit 1; }

cat > "$D/chk.py" <<'PY'
import ast, json, re, sys
mode = sys.argv[1]
if mode == "imports":      # imports <recall.py>: stdlib only, no subprocess, no network, the 3.9 grammar
    src = open(sys.argv[2], encoding="utf-8").read()
    tree = ast.parse(src, feature_version=(3, 9))
    mods = sorted({a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names} |
                  {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module})
    calls = sorted({n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id == "os"
                    and (n.attr in ("system", "popen", "fork", "startfile") or n.attr.startswith(("exec", "spawn")))})
    allowed = {"collections", "datetime", "json", "os", "pathlib", "posixpath", "re", "stat", "sys", "time"}
    print("ok" if set(mods) <= allowed and not calls else "imports %s, process calls %s" % (mods, calls))
elif mode == "plain":      # plain <recall.py>: plain_local_target() on gitdir: values (the file runs main() on import; stdin is empty here, so it prints nothing)
    import runpy
    g = runpy.run_path(sys.argv[2], run_name="recall_under_test")
    f = g["plain_local_target"]
    want = {"/net/192.0.2.7/x": False, "/Network/x": False, "/NET/x": False, "/network": False, "/netx/a": True, "/home/yk/x": True,
            "/x/../net/192.0.2.7/s": False, "/./Network/x": False, "/x/./../NET/h": False, "\\x\\..\\net\\h": False, "/x/../home/y": True, "/net/../home/y": False,
            "C:/demo/x": True, "../gd": True, "gd/x": True, "//192.0.2.7/x": False}
    bad = ["%s -> %s" % (k, f(k)) for k, v in want.items() if f(k) != v]
    print("ok" if not bad else "; ".join(bad))
elif mode == "linkstat":   # linkstat <recall.py>: the link predicate on fake lstat results (a cloud-sync reparse point is not a link; a symlink or a mount point is)
    import collections, os, runpy, stat
    g = runpy.run_path(sys.argv[2], run_name="recall_under_test")
    real_lstat = os.lstat
    def f(st):   # path_kind() itself, over a fake os.lstat result (the predicate is not called by name: the older file has none)
        os.lstat = lambda p: st
        try:
            return g["path_kind"]("fake") == "link"
        finally:
            os.lstat = real_lstat
    S = collections.namedtuple("S", "st_mode st_file_attributes st_reparse_tag")
    RP, REG, DIR, LNK = 0x400, stat.S_IFREG | 0o644, stat.S_IFDIR | 0o755, stat.S_IFLNK | 0o777
    want = [("cloud placeholder file (tag 0x9000001A)", S(REG, RP | 0x20, 0x9000001A), False),
            ("cloud placeholder folder (tag 0x9000001A)", S(DIR, RP | 0x10, 0x9000001A), False),
            ("symlink by mode", S(LNK, 0, 0), True),
            ("symlink tag 0xA000000C", S(REG, RP, 0xA000000C), True),
            ("mount point / junction tag 0xA0000003", S(DIR, RP | 0x10, 0xA0000003), True),
            ("plain file, no reparse attribute", S(REG, 0x20, 0), False),
            ("plain folder, no reparse attribute", S(DIR, 0x10, 0), False),
            ("reparse attribute and a tag of 0", S(DIR, RP, 0), False)]
    bad = ["%s -> %s" % (n, f(s)) for n, s, w in want if f(s) != w]
    print("ok" if not bad else "; ".join(bad))
elif mode == "timed":      # timed <recall.py> <event file>: runs the hook in this interpreter and prints its output, then ELAPSED_MS=<the hook's own time, without the interpreter start>
    import io, runpy, time
    sys.stdin = io.TextIOWrapper(io.BytesIO(open(sys.argv[3], "rb").read()), encoding="utf-8")
    real, sys.stdout = sys.stdout, io.TextIOWrapper(io.BytesIO(), encoding="utf-8")
    t0 = time.perf_counter()
    runpy.run_path(sys.argv[2], run_name="__main__")
    ms = int((time.perf_counter() - t0) * 1000)
    sys.stdout.flush()
    got = sys.stdout.buffer.getvalue().decode("utf-8", "replace")
    sys.stdout = real
    sys.stdout.write(got + "\nELAPSED_MS=%d\n" % ms)
elif mode == "hooks":      # hooks <hooks.json>: the PreCompact entry and the second SessionStart command
    d = json.load(open(sys.argv[2], encoding="utf-8"))
    want = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/recall.py"'
    pc = d["hooks"].get("PreCompact") or []
    if not (len(pc) == 1 and pc[0].get("matcher") == "manual|auto" and len(pc[0]["hooks"]) == 1):
        print("PreCompact: %r" % pc); sys.exit()
    h = pc[0]["hooks"][0]
    if not (h.get("type") == "command" and h.get("command") == want and h.get("timeout") == 10):
        print("PreCompact hook: %r" % h); sys.exit()
    ss = d["hooks"].get("SessionStart") or []
    cmds = [(re.search(r"hooks/([a-z-]+)\.py", x["command"]).group(1), x.get("timeout")) for x in ss[0]["hooks"]] if len(ss) == 1 else None
    if cmds != [("heartbeat", 5), ("recall", 10)] or "matcher" in ss[0] or ss[0]["hooks"][1]["command"] != want:
        print("SessionStart: %r" % (cmds,)); sys.exit()
    print("ok" if "recall" in d.get("description", "") else "description does not mention recall")
PY

# --- drivers
CPDIR="$PW"   # CLAUDE_PROJECT_DIR for run (empty: the hook falls back to the event's cwd, then the process cwd)
run() { # $1 = the event JSON on stdin -> OUT RC ERR (the hook's stdout, exit code, stderr)
  OUT=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$CPDIR" py "$HOOK" 2>"$D/err"; echo "rc=$?"); RC=${OUT##*rc=}; OUT=${OUT%rc=*}; OUT=${OUT%$'\n'}; ERR=$(cat "$D/err")
}
runf() { # $1 = a file holding the event JSON
  OUT=$(CLAUDE_PROJECT_DIR="$CPDIR" py "$HOOK" < "$1" 2>"$D/err"; echo "rc=$?"); RC=${OUT##*rc=}; OUT=${OUT%rc=*}; OUT=${OUT%$'\n'}; ERR=$(cat "$D/err")
}
NETMAX=3000   # ms: the hook's own time (the interpreter start is not in it, and it takes seconds on a loaded laptop); touching a dead share took 27-34 s (SMB timeout)
runt() { # $1 = the event JSON -> OUT RC ERR as run, and MS = the hook's own time in ms (see chk.py timed)
  printf '%s' "$1" > "$D/ev-timed.json"
  OUT=$(CLAUDE_PROJECT_DIR="$CPDIR" py "$D/chk.py" timed "$HOOK" "$D/ev-timed.json" 2>"$D/err"; echo "rc=$?"); RC=${OUT##*rc=}; OUT=${OUT%rc=*}; ERR=$(cat "$D/err")
  MS=${OUT##*ELAPSED_MS=}; MS=${MS%%[!0-9]*}; MS=${MS:-999999}; OUT=${OUT%ELAPSED_MS=*}; OUT=${OUT%$'\n'}; OUT=${OUT%$'\n'}
}
ev() { # $1 event, $2 source or -, $3 transcript case or -, $4 more JSON fields (start with a comma)
  local s="" t=""
  [ "$2" != "-" ] && s=",\"source\":\"$2\""
  [ "$3" != "-" ] && t=",\"transcript_path\":\"$(wp "$D/t/$3.jsonl")\""
  printf '{"hook_event_name":"%s","session_id":"sid-test","cwd":"%s"%s%s%s}' "$1" "$PW" "$s" "$t" "${4:-}"
}
adapter() { printf '%s\n' "$1" > "$D/proj/.claude/smartuse.local.md"; }
okrun() { [ "$RC" = 0 ] && [ -z "$ERR" ]; }   # exit 0 and nothing on stderr
has() { # $1 label, $2 text the output must hold
  if okrun && case "$OUT" in *"$2"*) true;; *) false;; esac; then ok "$1"; else ko "$1: expected '$2' -> rc=$RC out='${OUT:0:300}' err='${ERR:0:200}'"; fi
}
lacks() { # $1 label, $2 text the output must not hold (the output must exist: a hook that printed nothing proves nothing)
  if okrun && [ -n "$OUT" ] && ! case "$OUT" in *"$2"*) true;; *) false;; esac; then ok "$1"; else ko "$1: '$2' must be absent from a non-empty output -> rc=$RC out='${OUT:0:300}' err='${ERR:0:200}'"; fi
}
quiet() { # $1 label: exit 0, nothing on stdout, nothing on stderr
  if okrun && [ -z "$OUT" ]; then ok "$1"; else ko "$1: expected nothing -> rc=$RC out='${OUT:0:300}' err='${ERR:0:200}'"; fi
}
before() { # $1 label, $2 a, $3 b: both in the output, a first
  local x=${OUT%%"$2"*} y=${OUT%%"$3"*}
  if okrun && [ "$x" != "$OUT" ] && [ "$y" != "$OUT" ] && [ ${#x} -lt ${#y} ]; then ok "$1"; else ko "$1: '$2' must come before '$3' -> out='${OUT:0:300}'"; fi
}
count_of() { printf '%s\n' "$OUT" | grep -c "$1"; }   # lines holding the text
fresh() { rm -rf "$HOME/.claude/smartuse/projects"; }
A_FULL=$'sources: jobs/demo/plan.pdf, photos/*.jpg\npublish: python send.py\npublish_tools: mcp__*__file_upload\nhandoff: docs/STATUS.md'

# ===== 1. PreCompact (F2): what the summarizer is told to keep
adapter "$A_FULL"; fresh
run "$(ev PreCompact - main ',"trigger":"manual"')"
has "PreCompact: the source path is printed verbatim" "jobs/demo/plan.pdf"
has "PreCompact: a glob source is printed as written" "photos/*.jpg"
has "PreCompact: the owner's last prompt is quoted" "PROMPT-10 after the squeeze"
has "PreCompact: the 8th prompt back is quoted" "PROMPT-03 third request"
lacks "PreCompact: only the last 8 (the 9th back is not quoted)" "PROMPT-02"
before "PreCompact: oldest first" "PROMPT-03" "PROMPT-10"
lacks "PreCompact: a peer message is never quoted" "PEER-TEXT"
lacks "PreCompact: a task notification is never quoted" "TASKNOTE-TEXT"
lacks "PreCompact: a meta record is never quoted" "META-TEXT"
lacks "PreCompact: the compact summary is never quoted" "SUMMARYTEXT"
lacks "PreCompact: a tool result is never quoted" "TOOLRESULT-TEXT"
lacks "PreCompact: a subagent's (sidechain) prompt is never quoted" "SIDECHAIN-TEXT"
lacks "PreCompact: a command echo is never quoted" "CMDECHO-TEXT"
lacks "PreCompact: a reminder is never quoted" "REMINDER-TEXT"
lacks "PreCompact: a queued peer message is never quoted" "QUEUED-PEER-TEXT"
has "PreCompact: an SDK prompt is quoted" "PROMPT-06 sent through the SDK"
has "PreCompact: an older record with no origin fields is quoted" "PROMPT-07 an older record"
has "PreCompact: a message typed mid-turn is quoted" "PROMPT-08 typed while Claude was working"
has "PreCompact: whitespace is collapsed to single spaces" "PROMPT-04 line one line two"
A250=$(printf '%250s' '' | tr ' ' a); A300=$(printf '%300s' '' | tr ' ' a)
has "PreCompact: a long prompt keeps its first characters" "$A250"
lacks "PreCompact: a prompt is cut at 300 characters" "$A300"
has "PreCompact: the summary is told to mark what it did not re-verify" "from summary"
okrun && [ ! -e "$ST" ] && ok "PreCompact: writes no state (the squeeze is counted when it is over)" || ko "PreCompact wrote $ST or failed: rc=$RC"
adapter "sources: jobs/demo/plan.pdf"; run "$(ev PreCompact - main)"
lacks "PreCompact: the gating note belongs to the session start, not the summarizer" "nothing is gated"
adapter "$A_FULL"

run "$(ev PreCompact - main ',"custom_instructions":"CUSTOM-FIRST keep the budget table sk-xxxxxxxxxxxxxxxxxxxx"')"
case "$OUT" in "CUSTOM-FIRST"*) ok "PreCompact: custom instructions are printed first";; *) ko "custom instructions not first: ${OUT:0:200}";; esac
lacks "PreCompact: custom instructions are scrubbed too" "sk-xxxxxxxx"

adapter ""; run "$(ev PreCompact - main)"
has "PreCompact without sources: the prompts are still quoted" "PROMPT-10 after the squeeze"
lacks "PreCompact without sources: no source list" "source paths"
adapter "$A_FULL"; run "$(ev PreCompact - -)"
has "PreCompact without a transcript path: the sources are still listed" "jobs/demo/plan.pdf"
run "$(ev PreCompact - nope)"
has "PreCompact with a transcript that is not there: exit 0, sources listed" "jobs/demo/plan.pdf"
run "$(ev PreCompact - garbage)"
has "PreCompact over a garbage transcript: the one genuine prompt is quoted" "PROMPT-OK after the garbage"

# ===== 2. the scrub
run "$(ev PreCompact - secret)"
has "scrub: a token is masked" "[secret]"
lacks "scrub: sk- token gone" "sk-xxxxxxxx"
lacks "scrub: ghp_ token gone" "ghp_xxxxxxxx"
lacks "scrub: AKIA key gone" "AKIAxxxxxxxx"
has "scrub: an e-mail is masked" "[email]"
lacks "scrub: the e-mail address is gone" "yk@example"
has "scrub: a digit run of 10 is masked" "[number]"
lacks "scrub: the 10-digit run is gone" "0123456789"
has "scrub: a 7-digit run stays" "1234567"
has "scrub: task-folder stays as it is" "task-folder jobs/demo"
run "$(ev PreCompact - digits)"
has "scrub: a run between spaces is masked" "call [number] now"
has "scrub: a run at a sentence end is masked" "acct [number]."
has "scrub: a run after a plus sign is masked" "+[number]"
lacks "scrub: the three runs are gone" "0234567891"
lacks "scrub: the sentence-end run is gone" "1234567892"
lacks "scrub: the phone-style run is gone" "60198765432"
has "scrub: a run after a letter and a hyphen is part of a name and stays" "ref-12345678"
has "scrub: a dated file name in a folder stays" "photos/20261108.jpg"
has "scrub: a camera-style file name stays" "photos/IMG_20261108_140233.jpg"
adapter "sources: photos/IMG_20261108_140233.jpg, exports/2026110812.csv"; fresh
run "$(ev PreCompact - main)"
has "scrub: PreCompact prints a source path with digits in its name intact" "photos/IMG_20261108_140233.jpg"
has "scrub: PreCompact keeps a dated export name intact" "exports/2026110812.csv"
run "$(ev SessionStart compact main)"
has "scrub: SessionStart compact prints a source path with digits in its name intact" "photos/IMG_20261108_140233.jpg"
adapter "$A_FULL"

# ===== 3. the 9,000 cap
S=""; for i in $(seq 1 400); do S="$S${S:+, }jobs/demo/folder-$i/photo.jpg"; done
adapter "sources: $S"
run "$(ev PreCompact - big)"
if okrun && [ ${#OUT} -le 9000 ] && [ ${#OUT} -ge 8500 ]; then ok "cap: 400 long sources over a 2 MB transcript print at most 9,000 characters, cut not dropped (${#OUT})"; else ko "cap: rc=$RC length ${#OUT} err='${ERR:0:200}'"; fi
adapter "$A_FULL"; run "$(ev PreCompact - big)"
has "2 MB transcript: the last prompt is still found" "PROMPT-BIG-LAST the end"

# ===== 4. SessionStart compact (F2)
adapter $'sources: jobs/demo/plan.pdf, photos/*.jpg\npublish: python send.py'; fresh
py "$D/mk.py" "$(wp "$D/t")" "$PW" || { echo "FAIL could not rebuild the synthetic transcripts"; exit 1; }   # fresh markers: the squeeze-time check needs a boundary under 10 minutes old, and a slow run can be past that by here
BT=$(cat "$D/t/hhmm-boundary")
run "$(ev SessionStart compact main)"
has "compact: says the summary is not a source" "The summary is not a source."
has "compact: the squeeze time is the transcript's boundary" "squeezed at $BT"
has "compact: lists the sources" "jobs/demo/plan.pdf"
has "compact: a glob is listed as written" "photos/*.jpg"
has "compact: none counts as opened now" "none counts as opened now; open each before any output"
has "compact: quotes the owner's last prompt" "PROMPT-10 after the squeeze"
lacks "compact: no peer text" "PEER-TEXT"
lacks "compact: publish: is not echoed (the gate reads it, the model need not)" "send.py"
if [ -f "$ST" ] && grep -q '"compactions": 1' "$ST" && grep -q '"last_at"' "$ST" && grep -q 'jobs/demo/plan.pdf' "$ST"; then ok "state: recall.json counts the squeeze and keeps the source paths"; else ko "recall.json: $(cat "$ST" 2>/dev/null)"; fi
if [ ! -f "$ST" ] || grep -q 'send.py' "$ST"; then ko "state missing or holds a command: $(cat "$ST" 2>/dev/null)"; else ok "state: counts and paths only, never a command"; fi
run "$(ev SessionStart compact main)"
if grep -q '"compactions": 2' "$ST"; then ok "state: a second squeeze counts 2"; else ko "second squeeze: $(cat "$ST")"; fi
LK=$(CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --state-dir </dev/null); LK=${LK##*[/\\]}; LK=${LK%$'\r'}
GOT=$(ls "$HOME/.claude/smartuse/projects" 2>/dev/null)
[ -n "$LK" ] && [ "$GOT" = "$LK" ] && [ -f "$HOME/.claude/smartuse/projects/$LK/recall.json" ] && ok "state dir equals ledger.py's --state-dir ($LK)" || ko "state dir: recall.py wrote '$GOT', ledger.py says '$LK'"

N1=$(date +%H:%M); run "$(ev SessionStart compact old)"; N2=$(date +%H:%M)
if okrun && { case "$OUT" in *"squeezed at $N1."*|*"squeezed at $N2."*) true;; *) false;; esac; }; then ok "compact: a boundary hours old is an earlier squeeze, the time shown is now"; else ko "old boundary: want $N1 or $N2 -> ${OUT:0:200}"; fi
N1=$(date +%H:%M); run "$(ev SessionStart compact -)"; N2=$(date +%H:%M)
if okrun && { case "$OUT" in *"squeezed at $N1."*|*"squeezed at $N2."*) true;; *) false;; esac; }; then ok "compact: no transcript, the time shown is now"; else ko "no transcript: want $N1 or $N2 -> ${OUT:0:200}"; fi

adapter "publish: python send.py"; run "$(ev SessionStart compact main)"
if okrun && [ "$(printf '%s\n' "$OUT" | wc -l)" -eq 2 ]; then ok "compact without sources: two lines (time, the sentence)"; else ko "two lines expected: ${OUT:0:300}"; fi
lacks "compact without sources: no owner prompts" "PROMPT-10"
rm -f "$D/proj/.claude/smartuse.local.md"; run "$(ev SessionStart compact main)"
has "compact with no adapter at all: the sentence is still printed" "The summary is not a source."

# ===== 5. nothing is gated / not gated
adapter "sources: jobs/demo/plan.pdf"; run "$(ev SessionStart compact main)"
[ "$(count_of "nothing is gated")" = 1 ] && ok "sources without publish: or publish_tools: says once that nothing is gated" || ko "nothing-is-gated lines: $(count_of "nothing is gated") in ${OUT:0:300}"
adapter $'sources: jobs/demo/plan.pdf\npublish: python send.py'; run "$(ev SessionStart compact main)"
lacks "sources with publish: does not say nothing is gated" "nothing is gated"
adapter $'sources: jobs/demo/plan.pdf\npublish_tools: mcp__*__file_upload, mcp__drive__create_post'; run "$(ev SessionStart compact main)"
lacks "publish_tools: with a gated word: not warned" "not gated"
lacks "publish_tools: alone is a gate: nothing is gated is not said" "nothing is gated"
adapter $'sources: jobs/demo/plan.pdf\npublish_tools: Bash, mcp__drive__*, *upload*, mcp__crm__attach, mcp__crm__send_mail'; run "$(ev SessionStart compact main)"
has "publish_tools: a non-mcp name is named as not gated" "not gated"
has "publish_tools: Bash is named" "Bash"
has "publish_tools: a glob with no gate word is named" "mcp__drive__*"
has "publish_tools: a glob that starts with a wildcard is named" "*upload*"
has "publish_tools: an mcp tool the matcher cannot see is named" "mcp__crm__attach"
if okrun && [ -n "$OUT" ] && ! case "$OUT" in *"mcp__crm__send_mail"*) true;; *) false;; esac; then ok "publish_tools: a reachable name is not named"; else ko "mcp__crm__send_mail is reachable and must not be named: rc=$RC ${OUT:0:400}"; fi

# ===== 6. adapter parsing
adapter $'---\nsources: jobs/demo/plan.pdf\n---\nnotes\nsources: photos/IGNORED.jpg'; run "$(ev PreCompact - plain)"
has "adapter: a key in the frontmatter is read" "jobs/demo/plan.pdf"
lacks "adapter: the first line wins" "IGNORED"
adapter $'notes first\nsources: "jobs/demo/plan.pdf",  , '"'photos/a.jpg'"; run "$(ev PreCompact - plain)"
has "adapter: a key in the body is read, quotes dropped" "  photos/a.jpg"
lacks "adapter: no quote marks are kept" "\"jobs"
adapter $'sources:\nsources: photos/LATER.jpg\npublish: x'; run "$(ev PreCompact - plain)"
lacks "adapter: an empty first line wins (no sources)" "LATER"
printf 'sources: jobs/demo/plan.pdf, photos/a.jpg\r\npublish: python send.py\r\n' > "$D/proj/.claude/smartuse.local.md"; fresh; run "$(ev SessionStart compact plain)"
if [ ! -f "$ST" ] || grep -q '\\r' "$ST"; then ko "CRLF adapter: no state, or a carriage return reached it: $(cat "$ST" 2>/dev/null)"; else ok "adapter: CRLF line ends are not part of a value"; fi
has "adapter: CRLF, the last source is read whole" "photos/a.jpg"

# ===== 7. SessionStart startup / clear / resume (F3)
fresh; adapter "handoff: docs/STATUS.md"
i=1; : > "$D/proj/docs/STATUS.md"; while [ $i -le 20 ]; do printf 'HANDOFF-LINE-%02d status text\n' $i >> "$D/proj/docs/STATUS.md"; i=$((i + 1)); done
run "$(ev SessionStart startup -)"
has "handoff: the first line is printed" "HANDOFF-LINE-01 status text"
has "handoff: the 15th line is printed" "HANDOFF-LINE-15"
lacks "handoff: the 16th line is not" "HANDOFF-LINE-16"
has "handoff: the modified time is printed" "modified 20"
has "handoff: the age is printed" " ago)"
lacks "handoff: no .git, no stale line" "stale:"
lacks "handoff without sources: no source list" "Sources"
okrun && [ -n "$OUT" ] && [ ! -e "$ST" ] && ok "startup writes no state" || ko "startup wrote $ST or printed nothing: rc=$RC"
run "$(ev SessionStart clear -)"
has "handoff: printed on clear" "HANDOFF-LINE-01"
run "$(ev SessionStart resume plain)"
has "handoff: printed on resume" "HANDOFF-LINE-01"
lacks "resume without a compaction: no resumed line" "resumed;"
run "$(ev SessionStart resume main)"
has "resume with a compaction in the transcript: the compacted part is a summary" "resumed; the compacted part is a summary, not a source"
run "$(ev SessionStart resume sumonly)"
has "resume: the compact summary record alone is a compaction too" "resumed; the compacted part is a summary, not a source"
run "$(ev SessionStart startup main)"
lacks "startup never prints the resumed line" "resumed;"
run "$(ev SessionStart - -)"
has "a SessionStart with no source is a startup" "HANDOFF-LINE-01"
run "$(ev SessionStart bogus -)"
quiet "an unknown source prints nothing"

# the stale line: the last commit (the last entry of .git/logs/HEAD) is newer than the note
mkdir -p "$D/proj/.git/logs"; NOWS=$(date +%s)
printf '0000000000000000000000000000000000000000 1111111111111111111111111111111111111111 Demo <demo@example.test> 1577836800 +0000\tcommit: first\n0000000000000000000000000000000000000000 2222222222222222222222222222222222222222 Demo <demo@example.test> %s +0000\tcommit: second\n' "$NOWS" > "$D/proj/.git/logs/HEAD"
touch -t 202001010000 "$D/proj/docs/STATUS.md"
run "$(ev SessionStart startup -)"
case "$OUT" in *"stale: the handoff is "*" days older than the last commit"*) ok "stale: a note older than the last commit says by how many days";; *) ko "stale line: ${OUT:0:400}";; esac
touch "$D/proj/docs/STATUS.md"; printf '0000000000000000000000000000000000000000 1111111111111111111111111111111111111111 Demo <demo@example.test> 1577836800 +0000\tcommit: old\n' > "$D/proj/.git/logs/HEAD"
run "$(ev SessionStart startup -)"
lacks "stale: a note newer than the last commit is not stale" "stale:"
mkdir -p "$D/proj2/.claude" "$D/proj2/docs" "$D/gd/logs"; cp "$D/proj/docs/STATUS.md" "$D/proj2/docs/STATUS.md"; touch -t 202001010000 "$D/proj2/docs/STATUS.md"
printf 'gitdir: %s\n' "$(wp "$D/gd")" > "$D/proj2/.git"; printf 'handoff: docs/STATUS.md\n' > "$D/proj2/.claude/smartuse.local.md"
printf '0000000000000000000000000000000000000000 2222222222222222222222222222222222222222 Demo <demo@example.test> %s +0000\tcommit: wt\n' "$NOWS" > "$D/gd/logs/HEAD"
CPDIR=$(wp "$D/proj2"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
has "stale: a worktree's .git file leads to its git dir" "stale: the handoff is"

adapter "handoff: docs/NOPE.md"; run "$(ev SessionStart startup -)"
has "a missing handoff file is said, not hidden" "docs/NOPE.md was not found"
printf 'token sk-xxxxxxxxxxxxxxxxxxxx for yk@example.test\n' > "$D/proj/docs/SECRET.md"
adapter "handoff: docs/SECRET.md"; run "$(ev SessionStart startup -)"
lacks "handoff: its lines are scrubbed" "sk-xxxxxxxx"
has "handoff: the e-mail in it is masked" "[email]"

# --- the handoff must be a file inside the project: a cloned repo can ship its own adapter, so a value that points at another file
# (absolute, up and out, a network share, a directory, a link out) is named and never read; a network path is never even stat'ed
NR="is not read: it must be a file inside the project"
printf 'OUTSIDE-LINE not part of the project\n' > "$D/outside.md"
adapter "handoff: $(wp "$D/proj/docs/STATUS.md")"; run "$(ev SessionStart startup -)"
has "handoff: an absolute path is not read" "$NR"
lacks "handoff: an absolute path prints none of the file" "HANDOFF-LINE-01"
adapter "handoff: ../outside.md"; run "$(ev SessionStart startup -)"
has "handoff: a path that leaves the project is not read" "$NR"
lacks "handoff: ../outside.md prints none of the file" "OUTSIDE-LINE"
adapter "handoff: docs/../docs/STATUS.md"; run "$(ev SessionStart startup -)"
has "handoff: a .. part is refused even when the path ends up inside" "$NR"
adapter "handoff: //192.0.2.7/share/STATUS.md"; runt "$(ev SessionStart startup -)"
has "handoff: a //host/share path is not read" "$NR"
[ "$MS" -le $NETMAX ] && ok "handoff: a //host/share path is decided at once ($MS ms, nothing touched the network)" || ko "handoff: //host/share took $MS ms"
cat > "$D/proj/.claude/smartuse.local.md" <<'EOF'
handoff: \\192.0.2.7\share\STATUS.md
EOF
runt "$(ev SessionStart startup -)"
has "handoff: a \\\\host\\share path is not read" "$NR"
[ "$MS" -le $NETMAX ] && ok "handoff: a \\\\host\\share path is decided at once ($MS ms)" || ko "handoff: \\\\host\\share took $MS ms"
cat > "$D/proj/.claude/smartuse.local.md" <<'EOF'
handoff: \\?\C:\demo\STATUS.md
EOF
run "$(ev SessionStart startup -)"
has "handoff: a \\\\?\\ device path is not read" "$NR"
adapter "handoff: docs"; run "$(ev SessionStart startup -)"
has "handoff: a directory is not read" "$NR"
case "$OSTYPE" in
  msys*|cygwin*) ok "(skipped on Windows: no symlinks)";;
  *) ln -s "$D/outside.md" "$D/proj/docs/LINK.md"; adapter "handoff: docs/LINK.md"; run "$(ev SessionStart startup -)"
     has "handoff: a link inside the project that points outside is not read" "$NR"
     lacks "handoff: the link's target is not printed" "OUTSIDE-LINE";;
esac
# a worktree's .git file may name a git dir outside its folder (a local absolute path stays allowed, the stale test above), never a network one
mkdir -p "$D/proj3/.claude" "$D/proj3/docs"; cp "$D/proj/docs/STATUS.md" "$D/proj3/docs/STATUS.md"; touch -t 202001010000 "$D/proj3/docs/STATUS.md"
printf 'gitdir: //192.0.2.7/x\n' > "$D/proj3/.git"; printf 'handoff: docs/STATUS.md\n' > "$D/proj3/.claude/smartuse.local.md"
CPDIR=$(wp "$D/proj3"); runt "$(ev SessionStart startup -)"; CPDIR="$PW"
has "gitdir: //host/x: the handoff is still printed" "HANDOFF-LINE-01"
lacks "gitdir: //host/x gives no stale line" "stale:"
[ "$MS" -le $NETMAX ] && ok "gitdir: //host/x is skipped at once ($MS ms, nothing touched the network)" || ko "gitdir //host/x took $MS ms"
# the gitdir: value goes through the same plain-local allowlist as bash-guard's sources (a lock, not a fix: Python's pathlib joins this
# \??\ form under the project, so the code before reached no share either); a relative gitdir with a .. part stays allowed
cat > "$D/proj3/.git" <<'EOF'
gitdir: \??\UNC\192.0.2.7\x
EOF
CPDIR=$(wp "$D/proj3"); runt "$(ev SessionStart startup -)"; CPDIR="$PW"
has "gitdir: \\??\\UNC form: the handoff is still printed" "HANDOFF-LINE-01"
lacks "gitdir: \\??\\UNC form gives no stale line" "stale:"
[ "$MS" -le $NETMAX ] && ok "gitdir: \\??\\UNC form is skipped at once ($MS ms)" || ko "gitdir \\??\\UNC took $MS ms"
mkdir -p "$D/proj4/.claude" "$D/proj4/docs"; cp "$D/proj/docs/STATUS.md" "$D/proj4/docs/STATUS.md"; touch -t 202001010000 "$D/proj4/docs/STATUS.md"
printf 'gitdir: ../gd\n' > "$D/proj4/.git"; printf 'handoff: docs/STATUS.md\n' > "$D/proj4/.claude/smartuse.local.md"
CPDIR=$(wp "$D/proj4"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
has "stale: a relative gitdir with a .. part still leads to its git dir" "stale: the handoff is"

# --- links are refused, never followed (a link can come with a cloned repo or an archive and point at a share or at a file nobody named):
# the handoff's folders and file, the .git entry, the git dir's logs folder. Links need rights on Windows: tried once with a native
# symlink, then (folders) a junction; where neither can be made the cases are skipped with a PASS line, never silently
mkln() { # $1 target (a file or a folder that exists), $2 the link to make -> 0 when a link now stands there
  case "$OSTYPE" in
    msys*|cygwin*)
      MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null
      [ -e "$2" ] || { [ -d "$1" ] && MSYS_NO_PATHCONV=1 cmd //c mklink //J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null 2>&1; };;
    *) ln -s "$1" "$2" 2>/dev/null;;
  esac
  [ -e "$2" ] && { [ -L "$2" ] || [ -d "$2" ]; }
}
oldproj() { # $1 name: a project with a handoff note from 2020 (the stale line shows when the repo has a newer commit)
  mkdir -p "$D/$1/.claude" "$D/$1/docs"; cp "$D/proj/docs/STATUS.md" "$D/$1/docs/STATUS.md"; touch -t 202001010000 "$D/$1/docs/STATUS.md"
  printf 'handoff: docs/STATUS.md\n' > "$D/$1/.claude/smartuse.local.md"
}
newlog() { printf '0000000000000000000000000000000000000000 2222222222222222222222222222222222222222 Demo <demo@example.test> %s +0000\tcommit: now\n' "$NOWS" > "$1"; }
if mkln "$D/proj/docs" "$D/proj/dlink"; then
  adapter "handoff: dlink/STATUS.md"; run "$(ev SessionStart startup -)"
  has "handoff: a file reached through a linked folder (pointing inside the project) is not read" "$NR"
  lacks "handoff: the linked folder prints none of the file" "HANDOFF-LINE-01"
  adapter "handoff: ./docs//STATUS.md"; run "$(ev SessionStart startup -)"
  has "handoff: a ./ part and a doubled separator are fine (control: no link on the way)" "HANDOFF-LINE-01"
else ok "(skipped: no folder link can be made here without admin rights)"; fi
if mkln "$D/proj/docs/STATUS.md" "$D/proj/docs/FLINK.md"; then
  adapter "handoff: docs/FLINK.md"; run "$(ev SessionStart startup -)"
  has "handoff: a linked file (pointing inside the project) is not read" "$NR"
  lacks "handoff: the linked file prints none of the target" "HANDOFF-LINE-01"
else ok "(skipped: no file link can be made here without admin rights)"; fi
adapter "handoff: docs/NOPE.md"; run "$(ev SessionStart startup -)"
has "handoff: a missing file is still said to be missing (control)" "docs/NOPE.md was not found"
# .git as a link: no stale line (control first: the same git dir reached by a gitdir: file does give one)
oldproj proj5; mkdir -p "$D/gdreal/logs"; newlog "$D/gdreal/logs/HEAD"
printf 'gitdir: %s\n' "$(wp "$D/gdreal")" > "$D/proj5/.git"
CPDIR=$(wp "$D/proj5"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
has "links (control): a .git file leading to that git dir gives the stale line" "stale: the handoff is"
rm -f "$D/proj5/.git"
if mkln "$D/gdreal" "$D/proj5/.git"; then
  CPDIR=$(wp "$D/proj5"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
  has "links: .git as a link: the handoff is still printed" "HANDOFF-LINE-01"
  lacks "links: .git as a link gives no stale line" "stale:"
else ok "(skipped: no .git link can be made here without admin rights)"; fi
# the git dir's logs folder as a link
oldproj proj6; mkdir -p "$D/proj6/.git/logs" "$D/logsreal"; newlog "$D/proj6/.git/logs/HEAD"; newlog "$D/logsreal/HEAD"
CPDIR=$(wp "$D/proj6"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
has "links (control): a plain .git/logs gives the stale line" "stale: the handoff is"
rm -rf "$D/proj6/.git/logs"
if mkln "$D/logsreal" "$D/proj6/.git/logs"; then
  CPDIR=$(wp "$D/proj6"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
  has "links: .git/logs as a link: the handoff is still printed" "HANDOFF-LINE-01"
  lacks "links: .git/logs as a link gives no stale line" "stale:"
else ok "(skipped: no logs link can be made here without admin rights)"; fi
r=$(py "$D/chk.py" linkstat "$HOOK" </dev/null); [ "$r" = ok ] && ok "links: a cloud-sync reparse point is not a link; a symlink and a mount point are; no reparse attribute follows st_mode" || ko "link predicate: $r"
# the automount prefixes: decided on the text (a unit check of the allowlist, then the run: nothing is touched)
r=$(py "$D/chk.py" plain "$HOOK" </dev/null); [ "$r" = ok ] && ok "gitdir: /net/host/x and /Network/x (any case) are not plain local; /netx/a and other local spellings still are" || ko "plain_local_target: $r"
oldproj proj7; newlog "$D/gdreal/logs/HEAD"
for gd in "/net/192.0.2.7/x" "/Network/x" "/x/../net/192.0.2.7/s" "/./Network/x"; do
  printf 'gitdir: %s\n' "$gd" > "$D/proj7/.git"
  CPDIR=$(wp "$D/proj7"); runt "$(ev SessionStart startup -)"; CPDIR="$PW"
  has "gitdir: $gd: the handoff is still printed" "HANDOFF-LINE-01"
  lacks "gitdir: $gd gives no stale line" "stale:"
  [ "$MS" -le $NETMAX ] && ok "gitdir: $gd is skipped at once ($MS ms)" || ko "gitdir $gd took $MS ms"
done
# a relative gitdir: every component from its base is looked at, not only the last (control first: through a real folder it gives the stale line)
oldproj proj8; mkdir -p "$D/proj8/real/gd/logs" "$D/gdparent/gd/logs"; newlog "$D/proj8/real/gd/logs/HEAD"; newlog "$D/gdparent/gd/logs/HEAD"
printf 'gitdir: real/gd\n' > "$D/proj8/.git"
CPDIR=$(wp "$D/proj8"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
has "links (control): a relative gitdir through a real folder gives the stale line" "stale: the handoff is"
if mkln "$D/gdparent" "$D/proj8/lnk"; then
  printf 'gitdir: lnk/gd\n' > "$D/proj8/.git"
  CPDIR=$(wp "$D/proj8"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
  has "links: a relative gitdir through a linked folder: the handoff is still printed" "HANDOFF-LINE-01"
  lacks "links: a relative gitdir through a linked folder gives no stale line" "stale:"
  printf 'gitdir: real/../lnk/gd\n' > "$D/proj8/.git"
  CPDIR=$(wp "$D/proj8"); run "$(ev SessionStart startup -)"; CPDIR="$PW"
  lacks "links: a link behind a .. part is looked at too" "stale:"
else ok "(skipped: no folder link can be made here without admin rights)"; fi

adapter $'sources: jobs/demo/plan.pdf, photos/a.jpg\nhandoff: docs/STATUS.md'; run "$(ev SessionStart startup -)"
has "startup: sources are listed" "jobs/demo/plan.pdf"
has "startup: open each before any output" "open each before any output"
[ "$(count_of "nothing is gated")" = 1 ] && ok "startup: sources without publish say once that nothing is gated" || ko "startup nothing-is-gated lines: $(count_of "nothing is gated")"
has "startup: the handoff comes with the sources" "HANDOFF-LINE-01"
adapter "publish: python send.py"; run "$(ev SessionStart startup -)"
quiet "startup with neither sources: nor handoff: prints nothing"
rm -f "$D/proj/.claude/smartuse.local.md"; run "$(ev SessionStart resume main)"
quiet "resume with no adapter prints nothing"

# ===== 8. bad input
adapter "$A_FULL"
run ""; quiet "empty stdin: nothing, exit 0"
run "this is not json {"; quiet "garbage stdin: nothing, exit 0"
run "[]"; quiet "a JSON list: nothing, exit 0"
run "$(ev Stop - main)"; quiet "another event: nothing"
printf '{"hook_event_name":"PreCompact","session_id":"s","cwd":"%s","custom_instructions":"CAF\xe9 NOTE"}' "$PW" > "$D/ev-cp1252.json"; runf "$D/ev-cp1252.json"
has "a non-UTF-8 byte in the event is replaced, not fatal" "NOTE"
printf '{"hook_event_name":"PreCompact","session_id":"s","cwd":"%s","custom_instructions":"CAF\xc3\xa9 NOTE-UTF8"}' "$PW" > "$D/ev-utf8.json"; runf "$D/ev-utf8.json"
has "a UTF-8 character in the event is kept" "NOTE-UTF8"
case "$OSTYPE" in
  msys*|cygwin*) runf "$D/t/ev-backslash.json"; has "an event with backslash paths (cwd, transcript) works" "PROMPT-10 after the squeeze";;
  *) ok "(skipped off Windows: a backslash path is not a path here)";;
esac

# ===== 9. which project dir
adapter "$A_FULL"
CPDIR="$PW"; run "$(printf '{"hook_event_name":"PreCompact","cwd":"%s"}' "$PO")"; CPDIR="$PW"
has "CLAUDE_PROJECT_DIR beats the event's cwd" "jobs/demo/plan.pdf"
CPDIR=""; run "$(ev PreCompact - -)"; CPDIR="$PW"
has "no CLAUDE_PROJECT_DIR: the event's cwd" "jobs/demo/plan.pdf"
OUT=$(cd "$D/proj" && printf '%s' '{"hook_event_name":"PreCompact"}' | CLAUDE_PROJECT_DIR="" py "$HOOK" 2>"$D/err"; echo "rc=$?"); RC=${OUT##*rc=}; OUT=${OUT%rc=*}; ERR=$(cat "$D/err")
has "neither: the process cwd" "jobs/demo/plan.pdf"

# ===== 10. nothing written in the project, stdlib only, hooks.json
snap() { (cd "$D/proj" && find . | sort | tr '\n' ' '); }
B=$(snap); fresh
run "$(ev SessionStart compact main)"; run "$(ev PreCompact - main)"; run "$(ev SessionStart startup -)"
okrun && [ -n "$OUT" ] && [ "$(snap)" = "$B" ] && ok "nothing is written inside the project (state goes to the home dir only)" || ko "the project changed: before '$B' after '$(snap)'"
r=$(py "$D/chk.py" imports "$HOOK" </dev/null); [ "$r" = ok ] && ok "recall.py: stdlib only, no subprocess, no import between hooks, the 3.9 grammar" || ko "recall.py imports: $r"
r=$(py "$D/chk.py" hooks "$H/hooks.json" </dev/null); [ "$r" = ok ] && ok "hooks.json: PreCompact (manual|auto) and SessionStart run recall.py, timeout 10" || ko "hooks.json: $r"

[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
