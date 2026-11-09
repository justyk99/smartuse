#!/usr/bin/env bash
# Self-contained test for the fresh-source gate in hooks/bash-guard.py (docs/notes/recall-design.md, F1): a command that publishes
# (adapter key `publish:`) or a tool call that publishes (`publish_tools:`) is denied until every file of `sources:` has a Read in
# this session after the last compaction. Every transcript is SYNTHETIC: records in the shapes Claude Code writes (assistant tool_use
# blocks, the system compact_boundary record, the user isCompactSummary record, sidechain records) with invented names and text.
# Covered: reads after the boundary / only before it / 2 of 3 / none · no boundary at all · the summary record as the marker · the
# LAST of several boundaries · a glob with no match, a literal path that is missing, over 200 files, exactly 200 · a Read in a
# sidechain, a Bash cat, a same-named file in another folder · the same file spelt C:\ and C:/ · a publish in a segment (&&, ||, ;,
# |, newline), after VAR=value, inside a heredoc a shell runs, in a heredoc that is data, in echo "…", a longer word, a script path
# spelt two ways · a publish_tools tool, unopened and opened, a tool that is not listed · no sources / no publish keys / no adapter /
# bad stdin · a transcript missing, unnamed, a directory, a corrupt line, a budget overrun · a 2 MB transcript · the project dir
# order (env, then the event's cwd, MSYS form too) · first occurrence wins, CRLF adapter · the RULES still come first · the REPLAY
# (sources opened only after the publish call: denied at the first call, allowed at the second) · the deny JSON shape · nothing
# written · stdlib only · exec without main() prints nothing (until-done.py reuses this file's RULES) · the hooks.json entry.
# Review fixes (F1b): a script word matched by the end of its path (C:/proj/send.py, /home/u/send.py, ./send.py) and the command
# word by base name (/usr/bin/git, git.exe, the python family) · brackets in the project path, a literal file named with [1] · a
# link or junction on a relative source refused, never followed, and the automount trees /net/ and /Network/ · $(…) and backtick
# bodies, winpty, ksh, bash -c -- '…', xargs -i / -l · values echoed in a reason cut at 200 characters, a whole reason at 2,000.
# One temp dir under ${TMPDIR:-/tmp}/smartuse-fresh.XXXXXX, the only thing removed on exit; temp HOME. Every PASS / FAIL line is
# one check; exit 1 on failure. The event JSON is written to files by Python (Windows paths), never through a command line, and
# every allow case is built by the same code as its deny twin and re-read as JSON, so an empty answer is an allow of parsed input.
set -u
H="$(cd "$(dirname "$0")/.." && pwd)"; G="$H/bash-guard.py"
D=$(mktemp -d "${TMPDIR:-/tmp}/smartuse-fresh.XXXXXX") && [ -d "$D" ] || { echo "FAIL could not create a temp dir under ${TMPDIR:-/tmp}"; exit 1; }
trap 'case "$D" in */smartuse-fresh.*) rm -rf "$D" 2>/dev/null;; esac' EXIT   # removes this run's own dir and nothing else
export HOME="$D/home"; mkdir -p "$HOME/.claude/smartuse" "$D/c" "$D/r"   # ~/.claude/smartuse exists, so py.sh remembers the interpreter: one start per call
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it (C:/Users/... in Git Bash)
fail=0
ok() { echo "PASS $1"; }
ko() { echo "FAIL $1"; fail=1; }
[ "$(py -c 'print("ok")' </dev/null 2>/dev/null)" = ok ] || { echo "FAIL no python 3 (python3, python or py -3) through $H/py.sh"; exit 1; }
MSYS=0; command -v cygpath >/dev/null 2>&1 && MSYS=1
# FRESH_GUARD_REF=<git ref> runs the same cases against the guard as that commit had it (read into this run's temp dir): how a new
# case is shown failing on the code before the change. Unset, the working copy is tested.
if [ -n "${FRESH_GUARD_REF:-}" ]; then
  G="$D/guard-ref.py"
  MSYS_NO_PATHCONV=1 git -C "$(wp "$H")" show "$FRESH_GUARD_REF:plugins/smartuse/hooks/bash-guard.py" > "$G" 2> "$D/git.err"
  [ -s "$G" ] || { echo "FAIL could not read bash-guard.py at $FRESH_GUARD_REF: $(head -c 300 "$D/git.err")"; exit 1; }
  echo "NOTE testing the guard of $FRESH_GUARD_REF, not the working copy"
fi

# a copy of the guard whose transcript budget is 0 s: the pass overruns at once (the real budget is 3 s)
BG="$D/guard-budget0.py"; sed 's/^BUDGET_S = .*/BUDGET_S = 0.0/' "$G" > "$BG"
grep -q '^BUDGET_S = 0.0' "$BG" && ok "the guard keeps its transcript budget in one top-level number (BUDGET_S)" || ko "bash-guard.py has no top-level BUDGET_S = <seconds>"

cat > "$D/mk.py" <<'PY'
import datetime, json, os, sys

OUT, MSYS, BG = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
NOW = datetime.datetime.now(datetime.timezone.utc)
ORDER = []
FS = "bash-guard: fresh-source \u2014 "
PLAN, PA, PB = "jobs/demo/plan.pdf", "jobs/demo/photos/a.jpg", "jobs/demo/photos/b.jpg"
FILES = [PLAN, PA, PB]
DENY, ALLOW = "deny", "allow"


def stamp(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (dt.microsecond // 1000)


class T(object):
    """One synthetic transcript, 11 s between records."""

    def __init__(self):
        self.recs, self.n, self.t = [], 0, NOW - datetime.timedelta(minutes=30)

    def rec(self, **r):
        self.n += 1
        self.t += datetime.timedelta(seconds=11)
        r.setdefault("uuid", "00000000-0000-4000-8000-%012d" % self.n)
        r.setdefault("timestamp", stamp(self.t))
        r.setdefault("sessionId", "sid-test")
        r.setdefault("isSidechain", False)
        self.recs.append(r)
        return self

    def raw(self, line):
        self.recs.append(line)
        return self

    def human(self, text):
        return self.rec(type="user", userType="external", turnOrigin="human", origin={"kind": "human"}, message={"role": "user", "content": text})

    def say(self, text):
        return self.rec(type="assistant", message={"role": "assistant", "model": "test-model", "content": [{"type": "text", "text": text}]})

    def use(self, name, inp, side=False, err=None, result=True):
        """A tool call and its result record. err: the text of an error result (the record shape of a failed call, pinned from a real
        transcript: a user record whose message content holds one tool_result block with content, is_error true and tool_use_id).
        result=False: the call has no result record."""
        self.rec(type="assistant", isSidechain=side, message={"role": "assistant", "model": "test-model", "stop_reason": "tool_use",
                 "content": [{"type": "tool_use", "id": "toolu_T%04d" % self.n, "name": name, "input": inp}]})
        self.last_id = "toolu_T%04d" % (self.n - 1)
        if not result:
            return self
        if err is None:
            return self.rec(type="user", isSidechain=side, message={"role": "user", "content": [{"type": "tool_result", "tool_use_id": self.last_id, "content": "ok"}]})
        return self.error_result(self.last_id, err, side)

    def error_result(self, tool_use_id, text, side=False):
        return self.rec(type="user", isSidechain=side, toolUseResult="Error: " + text, message={"role": "user", "content": [
            {"type": "tool_result", "content": text, "is_error": True, "tool_use_id": tool_use_id}]})

    def read(self, path, side=False, err=None, result=True, **extra):
        inp = {"file_path": path}
        inp.update(extra)
        return self.use("Read", inp, side, err, result)

    def bash(self, cmd):
        return self.use("Bash", {"command": cmd, "description": "test"})

    def boundary(self):
        return self.rec(type="system", subtype="compact_boundary", content="Conversation compacted", isMeta=False, compactMetadata={"trigger": "auto", "preTokens": 170000})

    def summary(self):
        return self.rec(type="user", isCompactSummary=True, isVisibleInTranscriptOnly=True,
                        message={"role": "user", "content": "This session is being continued from a previous conversation. Summary: invented."})

    def junk(self, n, size=1000, mention=False):
        for i in range(n):
            txt = ("line %d " % i) * (size // 8)
            if mention and i == 3:   # a tool result that merely quotes the marker words is no marker
                txt += ' "subtype":"compact_boundary" isCompactSummary "tool_use"'
            self.rec(type="user", message={"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_J%d" % i, "content": txt}]})
        return self

    def write(self, path, cut=None):
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            for r in (self.recs if cut is None else self.recs[:cut]):
                fh.write((r if isinstance(r, str) else json.dumps(r, ensure_ascii=False)) + "\n")


def adapter(sources="jobs/demo/plan.pdf, jobs/demo/photos/*.jpg", publish="python send.py, git push", tools="mcp__*__file_upload, mcp__*__upload_image", front=True, eol="\n"):
    lines = []
    if sources is not None:
        lines.append("sources: " + sources)
    if publish is not None:
        lines.append("publish: " + publish)
    if tools is not None:
        lines.append("publish_tools: " + tools)
    body = eol.join(lines)
    return ("---" + eol + body + eol + "---" + eol + "# demo notes" + eol) if front else ("# demo notes" + eol + eol + body + eol)


def ex(mode, prefix=FS, has=(), no=(), rx=(), max=0, maxlen=0):
    return {"mode": mode, "prefix": prefix, "has": list(has), "no": list(no), "rx": list(rx), "max": max, "maxlen": maxlen}


def reads_all(t, P, side=False):
    for f in FILES:
        t.read(P + "/" + f, side=side)
    return t


def reads_many(t, P, folder, count):
    for i in range(count):
        t.read(P + "/%s/f%03d.txt" % (folder, i))
    return t


def base(P, boundary=True):
    t = T().human("Send the demo job to the client.")
    if boundary:
        t.say("Working.").boundary().say("Continuing from the summary.")
    return t


SKIPS, CAN = [], {}


def is_reparse(p):
    st = os.lstat(p)
    return os.path.islink(p) or bool(getattr(st, "st_file_attributes", 0) & 0x400)


def mklink(link, target, kind):
    """One link of kind file | dir (symlinks) | junction (Windows, no admin needed); False when this machine cannot make it."""
    try:
        os.makedirs(os.path.dirname(link), exist_ok=True)
        if kind == "junction":
            if os.name != "nt":
                return False
            import subprocess
            subprocess.run(["cmd", "/c", "mklink", "/J", link.replace("/", "\\"), target.replace("/", "\\")], capture_output=True, timeout=20)
        else:
            os.symlink(target, link, target_is_directory=(kind == "dir"))
        return os.path.lexists(link) and is_reparse(link)
    except Exception:
        return False


def can_link(kind):
    """Tried once per kind in a probe folder that is removed again; the cases of a kind that cannot be made are skipped, said once."""
    if kind not in CAN:
        probe = OUT + "/_probe_" + kind
        os.makedirs(probe + "/t", exist_ok=True)
        open(probe + "/t/f", "w").write("x")
        CAN[kind] = mklink(probe + "/l", probe + "/t" + ("/f" if kind == "file" else ""), kind)
        for p in (probe + "/l",):
            for rm in (os.unlink, os.rmdir):
                try:
                    rm(p)
                    break
                except OSError:
                    pass
        import shutil
        shutil.rmtree(probe, ignore_errors=True)
        if not CAN[kind]:
            SKIPS.append("%s links cannot be made on this machine (no privilege, or not Windows for junctions)" % kind)
    return CAN[kind]


def make(name, expect, cmd=None, tool="Bash", tinput=None, tr=None, adp=None, noadp=False, files=FILES, cut=None, tpath="auto", cwd="proj",
         raw=None, env=False, guard=None, pyenc=None, nfiles=None, proj="proj", links=()):
    d = OUT + "/" + name
    P = d + "/" + proj
    if not all(can_link(k) for _, _, k in links):
        return
    os.makedirs(P, exist_ok=True)
    for f in files:
        os.makedirs(os.path.dirname(P + "/" + f), exist_ok=True)
        open(P + "/" + f, "w").write("x")
    for rel, target, kind in links:   # link kinds were proven makeable above; the target is a project-relative path
        assert mklink(P + "/" + rel, P + "/" + target, kind), "could not make " + rel
    if nfiles:
        folder, count = nfiles
        os.makedirs(P + "/" + folder, exist_ok=True)
        for i in range(count):
            open(P + "/%s/f%03d.txt" % (folder, i), "w").write("x")
    text_adp = adapter() if adp is None else (adp(P) if callable(adp) else adp)
    if not noadp:
        os.makedirs(P + "/.claude", exist_ok=True)
        with open(P + "/.claude/smartuse.local.md", "w", encoding="utf-8", newline="") as fh:
            fh.write(text_adp)
    os.makedirs(d + "/elsewhere", exist_ok=True)
    tt = tr(P) if tr else None
    tp = None
    if tt is not None:
        tp = d + "/t.jsonl"
        tt.write(tp, cut)
    if tpath == "missing":
        tp = d + "/nope.jsonl"
    elif tpath == "dir":
        tp = d
    elif tpath == "none":
        tp = None
    cwdv = {"proj": P, "other": d + "/elsewhere"}.get(cwd, cwd)
    if cwd == "msys":
        cwdv = "/" + P[0].lower() + P[2:]
        if tp:
            tp = "/" + tp[0].lower() + tp[2:]
    if tinput is None:
        tinput = {"command": cmd, "description": "test"} if tool == "Bash" else {"path": "jobs/demo/plan.pdf"}
    ev = {"hook_event_name": "PreToolUse", "session_id": "sid-test", "cwd": cwdv, "tool_name": tool, "tool_input": tinput}
    if tp:
        ev["transcript_path"] = tp
    with open(d + "/event.json", "w", encoding="utf-8", newline="") as fh:
        fh.write(raw if raw is not None else json.dumps(ev, ensure_ascii=False))
    if raw is None:   # the input is proven to parse: an empty answer on an allow case is then a real allow
        assert json.load(open(d + "/event.json", encoding="utf-8")) == ev
    meta = dict(expect)
    meta["name"] = name
    json.dump(meta, open(d + "/meta.json", "w"))
    if env:
        open(d + "/env", "w").write(P)
    if guard:
        open(d + "/guard", "w").write(guard)
    if pyenc:
        open(d + "/pyenc", "w").write(pyenc)
    ORDER.append(name)


# ================= deny
make("d_reads_only_before_boundary", ex(DENY, has=["3 of 3 sources not opened since the last compaction (", "Nothing was sent."], rx=[r"\(\d\d:\d\d\)"]),
     cmd="python send.py --to client", tr=lambda P: reads_all(T().human("go"), P).boundary().say("Continuing."))
make("d_no_reads_after_boundary", ex(DENY, has=["3 of 3 sources not opened since the last compaction", "Open each with Read, then retry."], rx=[r"since the last compaction \(\d\d:\d\d\): "]),
     cmd="python send.py", tr=lambda P: base(P))
make("d_no_boundary_no_reads", ex(DENY, has=["3 of 3 sources not opened in this session"], no=["since the last compaction"]),
     cmd="python send.py", tr=lambda P: base(P, boundary=False))
make("d_two_of_three", ex(DENY, has=["2 of 3 sources not opened since the last compaction", "jobs/demo/photos/a.jpg, jobs/demo/photos/b.jpg"], no=["jobs/demo/plan.pdf"]),
     cmd="python send.py", tr=lambda P: base(P).read(P + "/" + PLAN))
# a Read whose result record says is_error (a missing file, a Read the permission rules denied) is not an opened source; a later Read that
# works counts again; a Read with no result record counts (the documented limit); an error result in a subagent's sidechain is ignored
NOFILE = "File does not exist."
make("d_failed_read_not_opened", ex(DENY, has=["1 of 3 sources not opened since the last compaction", "jobs/demo/photos/b.jpg"], no=["jobs/demo/plan.pdf", "jobs/demo/photos/a.jpg"]),
     cmd="python send.py", tr=lambda P: base(P).read(P + "/" + PLAN).read(P + "/" + PA).read(P + "/" + PB, err=NOFILE))
make("a_failed_then_successful_read", ex(ALLOW), cmd="python send.py",
     tr=lambda P: base(P).read(P + "/" + PLAN).read(P + "/" + PA).read(P + "/" + PB, err=NOFILE).read(P + "/" + PB))
make("d_denied_read_not_opened", ex(DENY, has=["1 of 3 sources not opened since the last compaction", "jobs/demo/plan.pdf"], no=["jobs/demo/photos/"]),
     cmd="python send.py", tr=lambda P: base(P).read(P + "/" + PLAN, err="denied").read(P + "/" + PA).read(P + "/" + PB))
make("a_read_without_result_counts", ex(ALLOW), cmd="python send.py",
     tr=lambda P: base(P).read(P + "/" + PLAN).read(P + "/" + PA).read(P + "/" + PB, result=False))


def sidechain_error(P):
    t = reads_all(base(P), P)
    return t.error_result(t.last_id, NOFILE, side=True)   # the result of the last main-thread Read, but written in a subagent's records


make("a_error_result_in_sidechain_ignored", ex(ALLOW), cmd="python send.py", tr=sidechain_error)
make("a_failed_read_of_another_file", ex(ALLOW), cmd="python send.py", tr=lambda P: reads_all(base(P), P).read(P + "/jobs/demo/other.txt", err=NOFILE))
make("d_glob_no_match", ex(DENY, has=["source pattern matches no file: jobs/demo/nothing/*.png", "The owner fixes sources: in .claude/smartuse.local.md. Nothing was sent."]),
     cmd="python send.py", adp=adapter(sources="jobs/demo/nothing/*.png"), tr=lambda P: reads_all(base(P), P))
make("d_literal_path_missing", ex(DENY, has=["source pattern matches no file: jobs/demo/gone.pdf"]),
     cmd="python send.py", adp=adapter(sources="jobs/demo/plan.pdf, jobs/demo/gone.pdf"), tr=lambda P: reads_all(base(P), P))
# a source that is a network path (//host/share, \\host\share, the \\?\ and //?/ forms) is never expanded, stat'ed or compared: the
# adapter can ship in a cloned repo, and a hook must not touch the network (192.0.2.7 is a documentation address that answers nothing,
# so a gate that tried would stall: each case must be decided in under 5 s, interpreter start included)
NET = " is not a plain local path; sources must be local files. The owner fixes sources: in .claude/smartuse.local.md. Nothing was sent."
UNC = "\\\\192.0.2.7\\share\\plan.pdf"
make("d_network_path_slashes", ex(DENY, has=["//192.0.2.7/share/plan.pdf" + NET], max=5), cmd="python send.py",
     adp=adapter(sources="//192.0.2.7/share/plan.pdf"), tr=lambda P: base(P))
make("d_network_path_backslashes", ex(DENY, has=[UNC + NET], max=5), cmd="python send.py", adp=adapter(sources=UNC), tr=lambda P: base(P))
make("d_network_path_extended_backslash", ex(DENY, has=["\\\\?\\UNC\\192.0.2.7\\share\\plan.pdf" + NET], max=5), cmd="python send.py",
     adp=adapter(sources="\\\\?\\UNC\\192.0.2.7\\share\\plan.pdf"), tr=lambda P: base(P))
make("d_network_path_extended_slashes", ex(DENY, has=["//?/UNC/192.0.2.7/share/plan.pdf" + NET], max=5), cmd="python send.py",
     adp=adapter(sources="//?/UNC/192.0.2.7/share/plan.pdf"), tr=lambda P: base(P))
make("d_network_path_after_a_local_one", ex(DENY, has=["//192.0.2.7/share/b.pdf" + NET], max=5), cmd="python send.py",
     adp=adapter(sources="jobs/demo/plan.pdf, //192.0.2.7/share/b.pdf"), tr=lambda P: reads_all(base(P), P))
make("d_network_path_tool", ex(DENY, has=["//192.0.2.7/share/plan.pdf" + NET], max=5), tool="mcp__demo__file_upload",
     adp=adapter(sources="//192.0.2.7/share/plan.pdf"), tr=lambda P: base(P))
make("d_network_path_in_a_read", ex(DENY, has=["3 of 3 sources not opened"], max=5), cmd="python send.py",
     tr=lambda P: base(P).read("//192.0.2.7/share/plan.pdf").read("\\\\192.0.2.7\\share\\a.jpg"))   # a Read of a network path is compared as text, never stat'ed
# the allowlist: relative (no .. part), C:\x or C:/x (not C://x), /x (not //x); the device, \??\ and GLOBALROOT forms never
for nm, val in (("nt_object_path", "\\??\\UNC\\192.0.2.7\\s\\a.pdf"), ("device_pipe", "\\\\.\\pipe\\x"), ("drive_double_slash", "C://x"),
                ("drive_relative", "C:x"), ("dotdot_part", "jobs/../x"), ("dotdot_backslash", "jobs\\..\\x"), ("leading_backslash", "\\jobs\\demo\\plan.pdf"),
                ("slash_backslash", "/\\192.0.2.7/share/a.pdf"), ("globalroot_any_case", "/dev/globalroot/x"), ("posix_double_slash", "//x/y"),
                ("drive_in_the_middle", "sub/D:/x.pdf"), ("stream_part", "jobs/demo/plan.pdf:zone"), ("odd_part", "jobs/.../plan.pdf")):   # a ":" in a part (a drive letter mid-path, an NTFS stream) and a part of only dots and spaces are refused by text
    make("d_not_plain_" + nm, ex(DENY, has=[val + NET], max=5), cmd="python send.py", adp=adapter(sources=val), tr=lambda P: base(P))
make("a_not_plain_but_no_publish", ex(ALLOW, max=5), cmd="python other.py", adp=adapter(sources="jobs/../x"), tr=lambda P: base(P))
# one deadline (BUDGET_S, 4 s) for the glob expansion and the transcript pass: the expansion runs in a worker thread joined with the time
# left; past the deadline a matched publish is denied, never let through. The patched copy has a deadline of 0.
make("d_deadline_overrun_in_the_expansion", ex(DENY, has=["could not verify which sources were opened (source expansion over 0 s)", "Nothing was sent."]),
     cmd="python send.py", tr=lambda P: reads_all(base(P), P), guard=BG)
make("d_deadline_overrun_literal_sources", ex(DENY, has=["could not verify which sources were opened (source expansion over 0 s)"]),
     cmd="python send.py", adp=adapter(sources="jobs/demo/plan.pdf"), tr=lambda P: base(P).read(P + "/" + PLAN), guard=BG)
make("d_deadline_overrun_tool", ex(DENY, has=["could not verify which sources were opened ("]), tool="mcp__demo__file_upload",
     tr=lambda P: reads_all(base(P), P), guard=BG)
# the heredoc scan is bounded: a command with more than 16 `<<` openers is read as it stands (bodies count as code), and the deadline
# starts when the hook starts. 8,000 unclosed openers (48 KB) before a publish word are decided well inside the 10 s hook timeout
# (interpreter start included); 16 data heredocs behave as before; 17 are read as code (the documented over-deny at the cap).
HD = lambda n, body: "".join("cat > f%d.txt <<'EOF'\n%s\nEOF\n" % (i, body if i == 5 else "data %d" % i) for i in range(n))
make("d_many_heredocs_publish", ex(DENY, has=["3 of 3 sources not opened"], max=9), cmd="x <<a\n" * 8000 + "git push", tr=lambda P: base(P))
make("d_cap_overdeny_pinned", ex(DENY, has=["3 of 3 sources not opened"]), cmd=HD(17, "python send.py"), tr=lambda P: base(P))
make("a_sixteen_heredocs_data", ex(ALLOW), cmd=HD(16, "python send.py"), tr=lambda P: base(P))
# the PowerShell tool (hooks.json matcher Bash|PowerShell) is gated as well. Its text is normalised and the pattern's first word may be
# any word of a statement, without regard to case (coarse and fail-closed); the text-side cases are in run.sh.
PS = lambda cm: dict(tool="PowerShell", tinput={"command": cm})
PSENC = "the PowerShell command carries an encoded command the gate cannot read. Run it in plain text. Nothing was sent."
make("d_ps_git_push_unopened", ex(DENY, has=["3 of 3 sources not opened since the last compaction (", "Open each with Read, then retry. Nothing was sent."], rx=[r"\(\d\d:\d\d\)"]),
     tr=lambda P: base(P), **PS("git push origin main"))
make("d_ps_start_process_unopened", ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P), **PS("Start-Process git -ArgumentList push"))
make("d_ps_python_script_unopened", ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P), **PS("py -3 .\\jobs\\send.py"))
make("d_ps_encoded_command_unreadable", ex(DENY, has=[PSENC]), tr=lambda P: reads_all(base(P), P), **PS("pwsh -enc not-base64!!"))
make("d_ps_replay_first_call", ex(DENY, has=["3 of 3 sources not opened since the last compaction"]),
     tr=lambda P: base(P).use("PowerShell", {"command": "git push"}), cut=-1, **PS("git push"))
make("a_ps_all_opened", ex(ALLOW), tr=lambda P: reads_all(base(P), P), **PS("git push origin main"))
make("a_ps_replay_second_call", ex(ALLOW), tr=lambda P: reads_all(base(P).use("PowerShell", {"command": "git push"}), P).say("Read them; pushing again."), **PS("git push"))
make("a_ps_quoted_words_are_data", ex(ALLOW), tr=lambda P: base(P), **PS('Write-Host "git push"'))
make("a_ps_other_script", ex(ALLOW), tr=lambda P: base(P), **PS("python .\\other.py"))
# the accepted over-deny: a publish word inside a here-string that is only data (a PowerShell here-string fence is a statement break)
make("d_ps_data_herestring_overdeny_pinned", ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P), **PS('@"\nnote: git push\n"@ | Out-File x.txt'))
# commands that run a publish through a wrapper, or have it in the middle: the pattern's first word is the command word (after the
# wrappers) and its later words appear in order among the command's later words
for nm, cm in (("timeout", "timeout 60 python send.py"), ("timeout_options", "timeout -s KILL 60 python send.py"), ("env_nohup", "env A=1 nohup python send.py"),
               ("env_options", "env -i -u HOME B=2 python send.py"), ("nice", "nice -n 5 python send.py"), ("stdbuf", "stdbuf -oL python send.py"),
               ("xargs", "echo x | xargs -n 1 python send.py"), ("time", "time -p python send.py"), ("command", "command python send.py"),
               ("exec", "exec python send.py"), ("bash_c", 'bash -c "cd x && python send.py"'), ("sh_c_single", "sh -c 'python send.py'"),
               ("bash_lc", 'bash -lc "python send.py"'), ("eval", 'eval "python send.py"'), ("eval_words", "eval python send.py"),
               ("nested_depth_2", "bash -c \"sh -c 'python send.py'\""), ("git_option", "git -C dir push"), ("git_options", "git -c a.b=c -C dir push origin main"),
               ("python_option", "python -u send.py"), ("script_path_in_the_middle", "python -X utf8 ./send.py --to client"),
               ("wrapped_git", "timeout 30 git -C dir push origin main")):
    make("d_wrapped_" + nm, ex(DENY, has=["sources not opened"]), cmd=cm, tr=lambda P: base(P))
make("a_echo_unquoted", ex(ALLOW), cmd="echo python send.py", tr=lambda P: base(P))
make("a_git_log", ex(ALLOW), cmd="git log", tr=lambda P: base(P))
make("a_git_status_dash_c", ex(ALLOW), cmd="git -C dir status", tr=lambda P: base(P))
make("a_wrapped_other_command", ex(ALLOW), cmd="timeout 60 python other.py", tr=lambda P: base(P))
make("a_wrapped_publish_all_opened", ex(ALLOW), cmd="env A=1 nohup python -u send.py", tr=lambda P: reads_all(base(P), P))
# spellings a shell runs that an exact-case, exact-name match missed: letter case, a trailing dot / space / stream on the script name, the
# Windows interpreter names, package-runner wrappers, setsid / coproc, more shells, a here-string, text echoed into a shell, a git alias,
# and a backslash-newline inside a word (bash joins without a space). Not seen, by design: brace and glob expansion, ${IFS}, $'…' quoting,
# a command held in a variable, 8.3 names, bash <(…) and text produced by a program other than echo / printf.
for nm, cm in (("case_python", "Python send.py"), ("case_git", "GIT push"), ("trailing_dot", "python send.py."), ("trailing_space", "python 'send.py '"),
               ("ntfs_stream", "python 'send.py::$DATA'"), ("uv_run", "uv run python send.py"), ("uv_run_with", "uv run --with x python send.py"),
               ("poetry_run", "poetry run python send.py"), ("pdm_run", "pdm run python send.py"), ("pipenv_run", "pipenv run python send.py"),
               ("hatch_run", "hatch run python send.py"), ("rye_run", "rye run python send.py"), ("pipx_run", "pipx run python send.py"),
               ("pythonw", "pythonw send.py"), ("pyw", "pyw send.py"), ("setsid", "setsid git push"), ("coproc", "coproc git push"),
               ("coproc_named", "coproc JOB { git push; }"), ("ash_c", "ash -c 'git push'"), ("fish_c", "fish -c 'git push'"),
               ("busybox_sh_c", "busybox sh -c 'git push'"), ("dollar_shell_c", "$SHELL -c 'git push'"), ("herestring", "bash <<< 'git push'"),
               ("herestring_double_quoted", "bash <<< \"python send.py\""), ("echo_into_bash", "echo git push | bash"), ("echo_quoted_into_sh", 'echo "python send.py" | sh -s'),
               ("printf_into_bash", "printf 'git push\\n' | bash"), ("git_alias", "git -c alias.p=push p"), ("git_alias_shell", "git -c alias.p='!git push' p"),
               ("dollar_shell_heredoc", "$SHELL <<EOF\ncd out\ngit push\nEOF"), ("braced_shell_heredoc", "${SHELL} <<EOF\ngit push\nEOF"),
               ("fish_heredoc", "fish <<EOF\npython send.py\nEOF"), ("ash_heredoc", "ash <<'EOF'\ngit push\nEOF"),
               ("backslash_newline_in_a_word", "gi\\\nt push"), ("continued_pattern_word", "python send.\\\npy")):
    make("d_spelling_" + nm, ex(DENY, has=["sources not opened"]), cmd=cm, tr=lambda P: base(P))
for nm, cm in (("pyc", "python send.pyc"), ("uv_other", "uv run python other.py"), ("echo_no_shell", "echo git push"), ("echo_into_cat", "echo git push | cat"),
               ("git_alias_status", "git -c alias.s=status s"), ("herestring_other_program", "cat <<< 'git push'"), ("shell_script_with_herestring", "bash check.sh <<< 'git push'"),
               ("python_other_w", "pythonw other.py"), ("cat_heredoc_data", "cat <<EOF > notes.txt\ngit push\nEOF")):
    make("a_spelling_" + nm, ex(ALLOW), cmd=cm, tr=lambda P: base(P))
make("a_network_path_no_publish", ex(ALLOW, max=5), cmd="python other.py", adp=adapter(sources="//192.0.2.7/share/plan.pdf"), tr=lambda P: base(P))
# an absolute source is taken literally: no glob expansion; it must exist as a file
make("d_absolute_pattern_is_literal", ex(DENY, has=["source pattern matches no file: "]), cmd="python send.py",
     adp=lambda P: adapter(sources=P + "/jobs/demo/photos/*.jpg"), tr=lambda P: reads_all(base(P), P))
make("d_absolute_literal_missing", ex(DENY, has=["source pattern matches no file: "]), cmd="python send.py",
     adp=lambda P: adapter(sources=P + "/jobs/demo/gone.pdf"), tr=lambda P: reads_all(base(P), P))
make("d_absolute_literal_unread", ex(DENY, has=["1 of 1 sources not opened"]), cmd="python send.py",
     adp=lambda P: adapter(sources=P + "/" + PLAN), tr=lambda P: base(P))
make("d_over_200_files", ex(DENY, has=["narrow the pattern: big/*.txt matches over 200 files. Nothing was sent."]),
     cmd="python send.py", adp=adapter(sources="big/*.txt"), files=[], nfiles=("big", 201), tr=lambda P: base(P))
make("d_names_capped_at_10", ex(DENY, has=["12 of 12 sources not opened", "many/f009.txt, and 2 more."], no=["many/f010.txt"]),
     cmd="python send.py", adp=adapter(sources="many/*.txt"), files=[], nfiles=("many", 12), tr=lambda P: base(P))
make("d_read_only_in_sidechain", ex(DENY, has=["3 of 3 sources not opened"]),
     cmd="python send.py", tr=lambda P: reads_all(base(P), P, side=True))
# the files Claude Code re-attaches right after a compaction are attachment records (type file), not the model's Read: they do not
# count as opened (the shape seen in a real compacted transcript, 2026-11-08; the text quotes "tool_use" and "Read" so the line is parsed)
def attached_all(P):
    t = T().human("Send the demo job to the client.").say("Working.").boundary().summary()
    for f in FILES:
        t.rec(type="attachment", attachment={"type": "file", "filename": P + "/" + f, "displayPath": f, "content": {"type": "text",
              "file": {"filePath": P + "/" + f, "content": 'invented {"type":"tool_use","name":"Read"}', "numLines": 1, "startLine": 1, "totalLines": 1}}})
    return t.say("Continuing from the summary.")
make("d_reattached_after_compaction_is_not_opened", ex(DENY, has=["3 of 3 sources not opened since the last compaction"]),
     cmd="python send.py", tr=attached_all)
make("d_heredoc_a_shell_runs", ex(DENY, has=["3 of 3 sources not opened"]),
     cmd="bash <<'EOF'\npython send.py\nEOF", tr=lambda P: base(P))
make("d_transcript_missing", ex(DENY, has=["could not verify which sources were opened (", "Retry, or ask the owner. Nothing was sent."]),
     cmd="python send.py", tr=lambda P: base(P), tpath="missing")
make("d_transcript_path_absent", ex(DENY, has=["could not verify which sources were opened ("]), cmd="python send.py", tr=lambda P: base(P), tpath="none")
make("d_transcript_is_a_dir", ex(DENY, has=["could not verify which sources were opened ("]), cmd="python send.py", tr=lambda P: base(P), tpath="dir")
make("d_budget_overrun", ex(DENY, has=["could not verify which sources were opened (", "Nothing was sent."]),
     cmd="python send.py", tr=lambda P: reads_all(base(P), P), guard=BG)
make("d_tool_unopened", ex(DENY, has=["3 of 3 sources not opened"]), tool="mcp__demo__file_upload", tr=lambda P: base(P))
make("d_tool_second_glob", ex(DENY, has=["sources not opened"]), tool="mcp__demo__upload_image", tr=lambda P: base(P))
make("d_tool_two_of_three", ex(DENY, has=["2 of 3 sources not opened"]), tool="mcp__demo__file_upload", tr=lambda P: base(P).read(P + "/" + PB))
make("d_replay_first_call", ex(DENY, has=["3 of 3 sources not opened since the last compaction"]), cmd="python send.py",
     tr=lambda P: base(P).bash("python send.py"), cut=-1)   # the transcript as it stands when the first publish call is made: the reads come later
make("d_git_push_segment", ex(DENY, has=["sources not opened"]), cmd="cd out && git push origin main", tr=lambda P: base(P))
make("d_var_prefix", ex(DENY, has=["sources not opened"]), cmd="MODE=1 KEY=abc python send.py now", tr=lambda P: base(P))
make("d_pipe_segment", ex(DENY, has=["sources not opened"]), cmd="python send.py | tee send.log", tr=lambda P: base(P))
make("d_or_segment", ex(DENY, has=["sources not opened"]), cmd="false || python send.py", tr=lambda P: base(P))
make("d_semicolon_segment", ex(DENY, has=["sources not opened"]), cmd="echo start; python send.py; echo end", tr=lambda P: base(P))
make("d_compound_command", ex(DENY, has=["sources not opened"]), cmd="if true; then python send.py; fi", tr=lambda P: base(P))
make("d_subshell", ex(DENY, has=["sources not opened"]), cmd="echo $(python send.py)", tr=lambda P: base(P))
make("d_newline_segment", ex(DENY, has=["sources not opened"]), cmd="echo start\npython send.py\n", tr=lambda P: base(P))
make("d_script_path_spelt_two_ways", ex(DENY, has=["sources not opened"]), cmd='python "tools\\send.py"', adp=adapter(publish="python ./tools/send.py"), tr=lambda P: base(P))
make("d_bash_cat_is_not_a_read", ex(DENY, has=["3 of 3 sources not opened"]), cmd="python send.py",
     tr=lambda P: base(P).bash("cat " + P + "/" + PLAN).bash("head -c 100 " + P + "/" + PA))
make("d_same_names_other_folder", ex(DENY, has=["3 of 3 sources not opened"]), cmd="python send.py",
     tr=lambda P: base(P).read(P + "/other/plan.pdf").read(P + "/other/a.jpg").read(P + "/other/b.jpg"))
make("d_summary_marker_reads_before", ex(DENY, has=["3 of 3 sources not opened since the last compaction"]), cmd="python send.py",
     tr=lambda P: reads_all(base(P, boundary=False), P).summary().say("Continuing."))
make("d_last_boundary_wins", ex(DENY, has=["3 of 3 sources not opened since the last compaction"]), cmd="python send.py",
     tr=lambda P: reads_all(base(P), P).say("Again.").boundary().say("Continuing."))
make("d_cp1252_stdin", ex(DENY, has=["sources not opened"]), cmd="echo \u00c1 \u4e2d\u6587 && python send.py", tr=lambda P: base(P), pyenc="cp1252")
make("d_project_dir_from_env", ex(DENY, has=["3 of 3 sources not opened"]), cmd="python send.py", tr=lambda P: base(P), cwd="other", env=True)
make("d_rules_come_first", ex(DENY, prefix="bash-guard: sudo", has=["run it yourself"]), cmd="sudo python send.py", tr=lambda P: reads_all(base(P), P))
make("d_big_2mb_one_unopened", ex(DENY, has=["2 of 3 sources not opened"]), cmd="python send.py",
     tr=lambda P: base(P).junk(1000, 1000, mention=True).read(P + "/" + PLAN).junk(1000, 1000))
if MSYS:
    make("d_cwd_in_msys_form", ex(DENY, has=["3 of 3 sources not opened"]), cmd="python send.py", tr=lambda P: base(P), cwd="msys")

# ================= allow
make("a_all_opened_after_boundary", ex(ALLOW), cmd="python send.py --to client", tr=lambda P: reads_all(base(P), P))
make("a_no_boundary_all_opened", ex(ALLOW), cmd="python send.py", tr=lambda P: reads_all(base(P, boundary=False), P))
make("a_summary_marker_reads_after", ex(ALLOW), cmd="python send.py", tr=lambda P: reads_all(base(P, boundary=False).summary().say("Continuing."), P))
make("a_last_boundary_reads_after", ex(ALLOW), cmd="python send.py", tr=lambda P: reads_all(base(P).boundary().say("Again."), P))
make("a_backslash_paths_in_reads", ex(ALLOW), cmd="python send.py",
     tr=lambda P: base(P).read((P + "/" + PLAN).replace("/", "\\")).read((P + "/" + PA).replace("/", "\\")).read((P + "/" + PB).replace("/", "\\")))
make("a_read_with_offset_and_limit", ex(ALLOW), cmd="python send.py", tr=lambda P: base(P).read(P + "/" + PLAN, offset=1, limit=20).read(P + "/" + PA).read(P + "/" + PB))
make("a_absolute_literal_sources", ex(ALLOW), cmd="python send.py",
     adp=lambda P: adapter(sources=", ".join(P + "/" + f for f in FILES)), tr=lambda P: reads_all(base(P), P))   # absolute and existing, each Read
make("a_heredoc_data_body", ex(ALLOW), cmd="cat > notes.txt <<'EOF'\npython send.py\nEOF\n", tr=lambda P: base(P))
make("a_echo_of_the_command", ex(ALLOW), cmd='echo "python send.py"', tr=lambda P: base(P))
make("a_longer_word", ex(ALLOW), cmd="python send.pyc", tr=lambda P: base(P))
make("a_other_script", ex(ALLOW), cmd="python other.py && git status", tr=lambda P: base(P))
make("a_unrelated_command", ex(ALLOW), cmd="ls -la", tr=lambda P: base(P))
make("a_no_publish_keys", ex(ALLOW), cmd="python send.py", adp=adapter(publish=None, tools=None), tr=lambda P: base(P))
make("a_no_sources", ex(ALLOW), cmd="python send.py", adp=adapter(sources=None), tr=lambda P: base(P))
make("a_empty_sources_value", ex(ALLOW), cmd="python send.py", adp=adapter(sources=" , "), tr=lambda P: base(P))
make("a_no_adapter", ex(ALLOW), cmd="python send.py", noadp=True, tr=lambda P: base(P))
make("a_tool_not_listed", ex(ALLOW), tool="mcp__demo__list_files", tr=lambda P: base(P))
make("a_tool_in_matcher_not_listed", ex(ALLOW), tool="mcp__demo__send_note", tr=lambda P: base(P))
make("a_tool_all_opened", ex(ALLOW), tool="mcp__demo__file_upload", tr=lambda P: reads_all(base(P), P))
make("a_other_tool", ex(ALLOW), tool="Read", tr=lambda P: base(P))
make("a_bad_stdin", ex(ALLOW), raw="{not json")
make("a_empty_stdin", ex(ALLOW), raw="")
make("a_json_not_an_object", ex(ALLOW), raw="[1, 2]")
make("a_corrupt_transcript_line", ex(ALLOW), cmd="python send.py",
     tr=lambda P: reads_all(base(P), P).raw('{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read" BROKEN').say("Fine."))
make("a_first_sources_line_wins", ex(ALLOW), cmd="python send.py",
     adp="---\nsources: jobs/demo/plan.pdf\npublish: python send.py\n---\nsources: jobs/demo/photos/*.jpg\n", tr=lambda P: base(P).read(P + "/" + PLAN))
make("a_keys_in_the_body", ex(ALLOW), cmd="python send.py", adp=adapter(front=False), tr=lambda P: reads_all(base(P), P))
make("a_crlf_adapter", ex(ALLOW), cmd="python send.py", adp=adapter(eol="\r\n"), tr=lambda P: reads_all(base(P), P))
make("a_exactly_200_files", ex(ALLOW), cmd="python send.py", adp=adapter(sources="big/*.txt"), files=[], nfiles=("big", 200),
     tr=lambda P: reads_many(base(P), P, "big", 200))
make("a_big_2mb", ex(ALLOW), cmd="python send.py", tr=lambda P: reads_all(base(P).junk(1000, 1000, mention=True), P).junk(1000, 1000))
make("a_replay_second_call", ex(ALLOW), cmd="python send.py", tr=lambda P: reads_all(base(P).bash("python send.py"), P).say("Read them; sending again."))
make("a_env_dir_beats_cwd", ex(ALLOW), cmd="python send.py", tr=lambda P: reads_all(base(P), P), cwd="other", env=True)
if MSYS:
    make("a_cwd_in_msys_form", ex(ALLOW), cmd="python send.py", tr=lambda P: reads_all(base(P), P), cwd="msys")

# ================= F1b review fixes
SRC = "sources not opened"
# 1 + 2: a script word is matched by the end of its path; the command word by its base name; the python family is one name
for nm, cm in (("abs_drive_path", "python C:/work/send.py"), ("abs_backslash_path", 'python "C:\\work\\send.py"'), ("abs_posix_path", "python /home/u/proj/send.py"),
               ("dotdot_path", "python ../send.py"), ("dot_path", "python ./send.py"), ("relative_dir_path", "python tools/send.py"),
               ("path_case_insensitive", "python C:/Work/SEND.PY"), ("python3", "python3 send.py"), ("python3_minor", "python3.12 send.py"),
               ("py_launcher", "py -3 send.py"), ("python_exe_path", "C:/Python313/python.exe send.py"),
               ("python_exe_quoted", '"C:\\Python313\\python.exe" send.py'), ("python_option_then_abs_path", "python -u C:/work/send.py --to client"),
               ("git_abs_path", "/usr/bin/git push"), ("git_exe", "git.exe push"), ("git_exe_windows_path", '"C:\\Program Files\\Git\\cmd\\git.exe" -C dir push'),
               ("wrapped_abs_path", "timeout 60 /usr/bin/python3 /home/u/proj/send.py")):
    make("d_match_" + nm, ex(DENY, has=[SRC]), cmd=cm, tr=lambda P: base(P))
make("d_match_pattern_dir_path", ex(DENY, has=[SRC]), cmd='python "C:\\p\\tools\\send.py"', adp=adapter(publish="python tools/send.py"), tr=lambda P: base(P))
make("d_match_pattern_dir_path_posix", ex(DENY, has=[SRC]), cmd="python /home/u/tools/send.py", adp=adapter(publish="python tools/send.py"), tr=lambda P: base(P))
make("d_match_pattern_python3_head", ex(DENY, has=[SRC]), cmd="python send.py", adp=adapter(publish="python3 send.py"), tr=lambda P: base(P))
make("d_match_pattern_py_head", ex(DENY, has=[SRC]), cmd="python3.11 C:/work/send.py", adp=adapter(publish="py send.py"), tr=lambda P: base(P))
make("d_match_pattern_git_exe_head", ex(DENY, has=[SRC]), cmd="git push", adp=adapter(publish="git.exe push"), tr=lambda P: base(P))
# one letter as the first part of a path is a drive: /c/proj/send.py and C:/proj/send.py are the same file, whichever side holds which spelling
make("d_match_msys_drive_command_drive_pattern", ex(DENY, has=[SRC]), cmd="python /c/proj/send.py", adp=adapter(publish="python C:/proj/send.py"), tr=lambda P: base(P))
make("d_match_msys_drive_command_backslash_pattern", ex(DENY, has=[SRC]), cmd='python "\\c\\proj\\send.py"', adp=adapter(publish="python C:/proj/send.py"), tr=lambda P: base(P))
make("d_match_drive_command_msys_pattern", ex(DENY, has=[SRC]), cmd="python C:/proj/send.py", adp=adapter(publish="python /c/proj/send.py"), tr=lambda P: base(P))
make("d_match_backslash_drive_command_msys_pattern", ex(DENY, has=[SRC]), cmd='python "C:\\proj\\send.py"', adp=adapter(publish="python /c/proj/send.py"), tr=lambda P: base(P))
make("d_match_msys_drive_upper_letter", ex(DENY, has=[SRC]), cmd="python /C/proj/send.py", adp=adapter(publish="python c:/proj/send.py"), tr=lambda P: base(P))
make("d_match_posix_dir_pattern_for_a_posix_dir", ex(DENY, has=[SRC]), cmd="python /a/proj/send.py", adp=adapter(publish="python a/proj/send.py"), tr=lambda P: base(P))
make("a_match_two_letter_dir_is_not_a_drive", ex(ALLOW), cmd="python /cc/proj/send.py", adp=adapter(publish="python C:/proj/send.py"), tr=lambda P: base(P))
make("a_match_two_letter_dir_is_not_a_drive_reverse", ex(ALLOW), cmd="python C:/proj/send.py", adp=adapter(publish="python /cc/proj/send.py"), tr=lambda P: base(P))
make("a_match_other_drive", ex(ALLOW), cmd="python /d/proj/send.py", adp=adapter(publish="python C:/proj/send.py"), tr=lambda P: base(P))
make("d_match_all_opened_still_allows", ex(ALLOW), cmd="python C:/work/send.py", tr=lambda P: reads_all(base(P), P))
# allow: other scripts, other names, other families
for nm, cm in (("other_script", "python other.py"), ("other_script_deeper", "python tools/other/send2.py"), ("other_script_abs", "python C:/work/other.py"),
               ("longer_name_abs", "python /home/u/proj/mysend.py"), ("git_pull", "git pull"), ("git_abs_pull", "/usr/bin/git pull"), ("git_exe_pull", "git.exe pull"),
               ("python3_other", "python3 other.py"), ("py_other", "py -3 other.py"), ("gitx", "gitx push"), ("node_is_not_python", "node send.py"),
               ("python_head_only_as_a_word", "echo python send.py"), ("send_as_a_directory", "python send.py/other.py")):
    make("a_match_" + nm, ex(ALLOW), cmd=cm, tr=lambda P: base(P))
make("a_match_pattern_dir_path_other_dir", ex(ALLOW), cmd="python C:/p/send.py", adp=adapter(publish="python tools/send.py"), tr=lambda P: base(P))
make("a_match_pattern_dir_path_longer_dir", ex(ALLOW), cmd="python xtools/send.py", adp=adapter(publish="python tools/send.py"), tr=lambda P: base(P))
make("a_match_pattern_dir_path_bare_name", ex(ALLOW), cmd="python send.py", adp=adapter(publish="python tools/send.py"), tr=lambda P: base(P))
make("a_match_pattern_python3_head_other", ex(ALLOW), cmd="python other.py", adp=adapter(publish="python3 send.py"), tr=lambda P: base(P))
# 5: matcher gaps
for nm, cm in (("dquote_subst", 'echo "$(python send.py)"'), ("dquote_subst_text_around", 'echo "done: $(python send.py) ok"'),
               ("backtick", "echo `python send.py`"), ("dquote_backtick", 'echo "went `python send.py` ok"'),
               ("subst_nested", 'echo "$(echo "$(python send.py)")"'), ("subst_in_bash_c", "bash -c 'echo \"$(python send.py)\"'"),
               ("subst_assignment", 'X="$(git push)"'), ("subst_with_inner_quote", 'echo "$(echo \')\'; python send.py)"'),
               ("subst_after_apostrophe_in_dquotes", 'echo "it\'s $(python send.py)"'),
               ("winpty", "winpty python send.py"), ("winpty_option", "winpty -Xallow-non-tty python send.py"),
               ("ksh_c", "ksh -c 'python send.py'"), ("bash_c_dashdash", "bash -c -- 'python send.py'"), ("bash_lc_dashdash", 'bash -lc -- "python send.py"'),
               ("xargs_i", "echo x | xargs -i python send.py"), ("xargs_l", "echo x | xargs -l python send.py"), ("xargs_i_attached", "echo x | xargs -i{} python send.py"),
               ("xargs_I_valued", "echo x | xargs -I % python send.py")):
    make("d_gap_" + nm, ex(DENY, has=[SRC]), cmd=cm, tr=lambda P: base(P))
for nm, cm in (("dquote_subst_other", 'echo "$(python other.py)"'), ("backtick_other", "echo `ls`"), ("dquote_subst_pull", 'echo "$(git pull)"'),
               ("subst_text_only", 'echo "python send.py is $(date)"'), ("winpty_other", "winpty python other.py"), ("ksh_c_other", "ksh -c 'python other.py'"),
               ("bash_c_dashdash_other", "bash -c -- 'python other.py'"), ("xargs_i_other", "echo x | xargs -i python other.py"),
               ("xargs_l_other", "echo x | xargs -l python other.py")):
    make("a_gap_" + nm, ex(ALLOW), cmd=cm, tr=lambda P: base(P))
make("a_gap_subst_all_opened", ex(ALLOW), cmd='echo "$(python send.py)"', tr=lambda P: reads_all(base(P), P))
# a quoted-delimiter heredoc inside $( … ) is text, not commands (Claude Code's own commit and PR form); one a shell runs still is code
EOFQ = "<<'EOF'"
COMMIT = 'git commit -m "$(cat ' + EOFQ + '\n%s\n\nCo-Authored-By: Test <t@example.com>\nEOF\n)"'
PRBODY = 'gh pr create --title "demo" --body "$(cat ' + EOFQ + '\n## Summary\n%s\n\n## Test plan\n- ran it\nEOF\n)"'
for nm, cm in (("commit_line_is_the_publish_command", COMMIT % "fix the parser\ngit push\nand more"),
               ("commit_backtick_span_names_the_script", COMMIT % "run `python send.py` after the build"),
               ("commit_apostrophes_and_parentheses", COMMIT % "don't (really) break it, 1) then\ngit push\nit's `python send.py` fine"),
               ("pr_body_line_is_the_publish_command", PRBODY % "- git push\ngit push origin main"),
               ("pr_body_backtick_span", PRBODY % "- `python send.py` stays manual")):
    make("a_heredoc_text_" + nm, ex(ALLOW), cmd=cm, tr=lambda P: base(P))
# an UNQUOTED heredoc still substitutes $( … ) and backticks in its body lines (strip_heredocs removes the body either way); plain lines stay data
EOFU, EOFQ2, EOFB = "<<EOF", '<<"EOF"', "<<\\EOF"
COMMITU = 'git commit -m "$(cat <<EOF\n%s\nEOF\n)"'
for nm, cm in (("commit_dollar_paren", COMMITU % "$(python send.py)"), ("commit_backticks", COMMITU % "`python send.py`"),
               ("commit_text_around", COMMITU % "notes\nrun $(git push) now\nmore"), ("commit_single_quotes_do_not_protect", COMMITU % "'$(python send.py)'"),
               ("top_level_dollar_paren", "cat " + EOFU + "\n$(python send.py)\nEOF"), ("top_level_backticks", "cat " + EOFU + "\n`python send.py`\nEOF\n"),
               ("top_level_dash_tab_terminator", "cat <<-EOF\n\t$(git push)\n\tEOF\n"), ("top_level_other_publish_command", "cat " + EOFU + "\nx $(git push origin main) y\nEOF"),
               ("pr_body", 'gh pr create --body "$(cat ' + EOFU + '\n- `python send.py`\nEOF\n)"'),
               ("nested_in_a_bash_c", "bash -c 'echo \"$(cat " + EOFU + "\n$(python send.py)\nEOF\n)\"'"),
               ("after_other_text", "echo start; cat " + EOFU + " > out.txt\nline\n$(python send.py)\nEOF\necho end")):
    make("d_unquoted_heredoc_" + nm, ex(DENY, has=[SRC]), cmd=cm, tr=lambda P: base(P))
for nm, cm in (("quoted_single", "cat <<'EOF'\n$(python send.py)\nEOF"), ("quoted_double", "cat " + EOFQ2 + "\n$(python send.py)\nEOF"),
               ("backslashed", "cat " + EOFB + "\n$(python send.py)\nEOF"), ("quoted_single_backticks", "cat <<'EOF'\n`python send.py`\nEOF\n"),
               ("commit_quoted_single", COMMIT % "$(python send.py)"), ("commit_quoted_double", 'git commit -m "$(cat ' + EOFQ2 + '\n$(python send.py)\nEOF\n)"'),
               ("commit_backslashed", 'git commit -m "$(cat ' + EOFB + '\n$(python send.py)\nEOF\n)"'),
               ("plain_line", "cat " + EOFU + "\npython send.py\nEOF"), ("plain_lines_in_a_commit", COMMITU % "run python send.py\ngit push"),
               ("dash_plain_line", "cat <<-EOF\n\tpython send.py\n\tEOF\n"),
               ("escaped_dollar_paren", "cat " + EOFU + "\n\\$(python send.py)\nEOF"), ("escaped_backtick", "cat " + EOFU + "\n\\`python send.py\\`\nEOF"),
               ("other_substitution", "cat " + EOFU + "\nnow $(date) and `hostname`\nEOF")):
    make("a_unquoted_heredoc_" + nm, ex(ALLOW), cmd=cm, tr=lambda P: base(P))
for nm, cm in (("plain_subst_still_denies", 'echo "$(python send.py)"'),
               ("shell_heredoc_in_subst", 'echo "$(bash ' + EOFQ + '\npython send.py\nEOF\n)"'),
               ("command_after_the_heredoc_in_subst", 'echo "$(cat ' + EOFQ + '\ntext\nEOF\npython send.py)"'),
               ("commit_then_a_real_publish", COMMIT % "fix the parser" + " && git push"),
               ("commit_with_subst_publish_in_the_message_command", 'git commit -m "$(python send.py)"'),
               ("pr_then_a_real_publish", PRBODY % "- text" + "; python send.py")):
    make("d_heredoc_text_" + nm, ex(DENY, has=[SRC]), cmd=cm, tr=lambda P: base(P))

# 3: brackets in the project path are only a name; a relative source with wildcard characters that is a literal file is that file
BR = "3 of 3 sources not opened since the last compaction"
for pj in ("p[a]x", "[1]p", "p[!x]"):
    make("a_bracket_project_" + pj.replace("[", "L").replace("]", "R").replace("!", "N"), ex(ALLOW), cmd="python send.py", proj=pj, tr=lambda P: reads_all(base(P), P))
    make("d_bracket_project_" + pj.replace("[", "L").replace("]", "R").replace("!", "N"),
         ex(DENY, has=[BR, "jobs/demo/plan.pdf, jobs/demo/photos/a.jpg, jobs/demo/photos/b.jpg."], no=["matches no file"]), cmd="python send.py", proj=pj, tr=lambda P: base(P))
make("d_bracket_project_two_of_three", ex(DENY, has=["2 of 3 sources not opened", "jobs/demo/photos/a.jpg, jobs/demo/photos/b.jpg."], no=["matches no file", "jobs/demo/plan.pdf"]),
     cmd="python send.py", proj="p[a]x", tr=lambda P: base(P).read(P + "/" + PLAN))
make("d_bracket_project_env_dir", ex(DENY, has=[BR], no=["matches no file"]), cmd="python send.py", proj="p[a]x", tr=lambda P: base(P), cwd="other", env=True)
make("d_bracket_project_missing_glob_still_says_so", ex(DENY, has=["source pattern matches no file: jobs/demo/nothing/*.png"]), cmd="python send.py",
     proj="p[a]x", adp=adapter(sources="jobs/demo/nothing/*.png"), tr=lambda P: base(P))
LIT = ["jobs/demo/plan.pdf", "jobs/demo/photo[1].jpg"]
make("a_literal_bracket_file", ex(ALLOW), cmd="python send.py", adp=adapter(sources=", ".join(LIT)), files=LIT,
     tr=lambda P: base(P).read(P + "/" + LIT[0]).read(P + "/" + LIT[1]))
make("d_literal_bracket_file_unread", ex(DENY, has=["1 of 2 sources not opened", "jobs/demo/photo[1].jpg."], no=["matches no file"]), cmd="python send.py",
     adp=adapter(sources=", ".join(LIT)), files=LIT, tr=lambda P: base(P).read(P + "/" + LIT[0]))
make("d_literal_bracket_file_missing", ex(DENY, has=["source pattern matches no file: jobs/demo/photo[2].jpg."]), cmd="python send.py",
     adp=adapter(sources="jobs/demo/photo[2].jpg"), files=LIT, tr=lambda P: base(P))
# a file named like the pattern is a source beside whatever the wildcards match (lit[1].pdf is not hidden by lit1.pdf)
BOTH = ["lit[1].pdf", "lit1.pdf"]
make("d_literal_and_wildcard_match_both_required", ex(DENY, has=["2 of 2 sources not opened", "lit1.pdf", "lit[1].pdf"]), cmd="python send.py",
     adp=adapter(sources="lit[1].pdf"), files=BOTH, tr=lambda P: base(P))
make("d_literal_opened_wildcard_match_not", ex(DENY, has=["1 of 2 sources not opened", "lit1.pdf."], no=["lit[1].pdf"]), cmd="python send.py",
     adp=adapter(sources="lit[1].pdf"), files=BOTH, tr=lambda P: base(P).read(P + "/lit[1].pdf"))
make("d_wildcard_match_opened_literal_not", ex(DENY, has=["1 of 2 sources not opened", "lit[1].pdf."], no=["lit1.pdf"]), cmd="python send.py",
     adp=adapter(sources="lit[1].pdf"), files=BOTH, tr=lambda P: base(P).read(P + "/lit1.pdf"))
make("a_literal_and_wildcard_match_both_opened", ex(ALLOW), cmd="python send.py", adp=adapter(sources="lit[1].pdf"), files=BOTH,
     tr=lambda P: base(P).read(P + "/lit[1].pdf").read(P + "/lit1.pdf"))
make("d_only_the_wildcard_match_exists", ex(DENY, has=["1 of 1 sources not opened", "lit1.pdf."]), cmd="python send.py",
     adp=adapter(sources="lit[1].pdf"), files=["lit1.pdf"], tr=lambda P: base(P))
make("d_only_the_literal_exists", ex(DENY, has=["1 of 1 sources not opened", "lit[1].pdf."], no=["matches no file"]), cmd="python send.py",
     adp=adapter(sources="lit[1].pdf"), files=["lit[1].pdf"], tr=lambda P: base(P))
make("a_glob_class_still_a_glob", ex(ALLOW), cmd="python send.py", adp=adapter(sources="jobs/demo/photos/[ab].jpg"), tr=lambda P: reads_all(base(P), P))
make("a_glob_skips_hidden_names", ex(ALLOW), cmd="python send.py", files=FILES + ["jobs/demo/photos/.h.jpg"], tr=lambda P: reads_all(base(P), P))
make("d_glob_dot_pattern_reaches_hidden_names", ex(DENY, has=["1 of 1 sources not opened", "jobs/demo/photos/.h.jpg."]), cmd="python send.py",
     adp=adapter(sources="jobs/demo/photos/.*.jpg"), files=FILES + ["jobs/demo/photos/.h.jpg"], tr=lambda P: base(P))
make("a_glob_double_star_finds_the_nested_file", ex(ALLOW), cmd="python send.py", adp=adapter(sources="jobs/**/b.jpg"), tr=lambda P: reads_all(base(P), P))
make("d_glob_double_star_finds_the_nested_file", ex(DENY, has=["1 of 1 sources not opened", "jobs/demo/photos/b.jpg."], no=["matches no file"]), cmd="python send.py",
     adp=adapter(sources="jobs/**/b.jpg"), tr=lambda P: base(P).read(P + "/" + PA))
DEEP = FILES + ["jobs/x.jpg", "jobs/demo/y.jpg"]
make("d_glob_double_star_several_depths", ex(DENY, has=["4 of 4 sources not opened", "jobs/demo/photos/a.jpg, jobs/demo/photos/b.jpg, jobs/demo/y.jpg, jobs/x.jpg."]),
     cmd="python send.py", adp=adapter(sources="jobs/**/*.jpg"), files=DEEP, tr=lambda P: base(P))
make("a_glob_double_star_several_depths_opened", ex(ALLOW), cmd="python send.py", adp=adapter(sources="jobs/**/*.jpg"), files=DEEP,
     tr=lambda P: base(P).read(P + "/jobs/x.jpg").read(P + "/jobs/demo/y.jpg").read(P + "/" + PA).read(P + "/" + PB))
make("d_glob_double_star_zero_levels_counts", ex(DENY, has=["1 of 2 sources not opened", "jobs/x.jpg."]), cmd="python send.py",
     adp=adapter(sources="jobs/**/x.jpg, jobs/**/a.jpg"), files=DEEP, tr=lambda P: base(P).read(P + "/" + PA))
make("a_glob_double_star_skips_hidden_folders", ex(ALLOW), cmd="python send.py", adp=adapter(sources="jobs/**/*.jpg"), files=FILES + ["jobs/.hid/z.jpg"],
     tr=lambda P: base(P).read(P + "/" + PA).read(P + "/" + PB))
make("d_glob_double_star_last_names_every_file", ex(DENY, has=["4 of 4 sources not opened", "jobs/demo/photos/a.jpg, jobs/demo/photos/b.jpg, jobs/demo/plan.pdf, jobs/x.jpg."]),
     cmd="python send.py", adp=adapter(sources="jobs/**"), files=FILES + ["jobs/x.jpg"], tr=lambda P: base(P))
make("d_glob_double_star_one_level_matches", ex(DENY, has=["1 of 1 sources not opened", "jobs/demo/plan.pdf."]), cmd="python send.py",
     adp=adapter(sources="jobs/**/plan.pdf"), tr=lambda P: base(P))
make("d_glob_dir_is_not_a_file", ex(DENY, has=["source pattern matches no file: jobs/demo/photos."]), cmd="python send.py",
     adp=adapter(sources="jobs/demo/photos"), tr=lambda P: reads_all(base(P), P))

# 4: a link on a relative source is refused, never followed; a link elsewhere in the project is not on the path and is no business of the gate
def linkmsg(pat, link):
    return pat + " passes through a link (" + link + "); sources must be plain local files. The owner fixes sources: in .claude/smartuse.local.md. Nothing was sent."


def reads_and(P, *extra):
    t = reads_all(base(P), P)
    for e in extra:
        t.read(P + "/" + e)
    return t


make("d_link_source_file", ex(DENY, has=[linkmsg("jobs/demo/link.pdf", "jobs/demo/link.pdf")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/demo/link.pdf"), links=[("jobs/demo/link.pdf", "jobs/demo/plan.pdf", "file")], tr=lambda P: reads_and(P, "jobs/demo/link.pdf"))
make("d_link_source_folder", ex(DENY, has=[linkmsg("jobs/linked/plan.pdf", "jobs/linked")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/linked/plan.pdf"), links=[("jobs/linked", "jobs/demo", "dir")], tr=lambda P: reads_and(P, "jobs/linked/plan.pdf"))
make("d_link_folder_matched_by_a_wildcard", ex(DENY, has=[linkmsg("jobs/*/plan.pdf", "jobs/linked")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/*/plan.pdf"), links=[("jobs/linked", "jobs/demo", "dir")], tr=lambda P: reads_all(base(P), P))
make("d_link_file_matched_by_a_wildcard", ex(DENY, has=[linkmsg("jobs/demo/photos/*.jpg", "jobs/demo/photos/c.jpg")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/demo/photos/*.jpg"), links=[("jobs/demo/photos/c.jpg", "jobs/demo/photos/a.jpg", "file")], tr=lambda P: reads_all(base(P), P))
make("d_link_source_file_tool", ex(DENY, has=[linkmsg("jobs/demo/link.pdf", "jobs/demo/link.pdf")]), tool="mcp__demo__file_upload",
     adp=adapter(sources="jobs/demo/link.pdf"), links=[("jobs/demo/link.pdf", "jobs/demo/plan.pdf", "file")], tr=lambda P: reads_all(base(P), P))
make("d_link_after_a_local_source", ex(DENY, has=[linkmsg("jobs/linked/a.jpg", "jobs/linked")]), cmd="python send.py",
     adp=adapter(sources="jobs/demo/plan.pdf, jobs/linked/a.jpg"), links=[("jobs/linked", "jobs/demo/photos", "dir")], tr=lambda P: reads_all(base(P), P))
make("d_junction_source_folder", ex(DENY, has=[linkmsg("jobs/jn/photos/*.jpg", "jobs/jn")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/jn/photos/*.jpg"), links=[("jobs/jn", "jobs/demo", "junction")], tr=lambda P: reads_all(base(P), P))
make("d_junction_matched_by_a_wildcard", ex(DENY, has=[linkmsg("jobs/*/photos/*.jpg", "jobs/jn")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/*/photos/*.jpg"), links=[("jobs/jn", "jobs/demo", "junction")], tr=lambda P: reads_all(base(P), P))
make("d_link_folder_under_double_star", ex(DENY, has=[linkmsg("jobs/**/b.jpg", "jobs/demo/linked")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/**/b.jpg"), links=[("jobs/demo/linked", "jobs/demo/photos", "dir")], tr=lambda P: reads_all(base(P), P))
make("d_link_file_under_double_star", ex(DENY, has=[linkmsg("jobs/**/*.jpg", "jobs/demo/photos/c.jpg")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/**/*.jpg"), links=[("jobs/demo/photos/c.jpg", "jobs/demo/photos/a.jpg", "file")], tr=lambda P: reads_all(base(P), P))
make("d_junction_under_double_star", ex(DENY, has=[linkmsg("jobs/**/b.jpg", "jobs/demo/jn")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/**/b.jpg"), links=[("jobs/demo/jn", "jobs/demo/photos", "junction")], tr=lambda P: reads_all(base(P), P))
make("d_link_folder_under_trailing_double_star", ex(DENY, has=[linkmsg("jobs/**", "jobs/linked")], no=["not opened"]), cmd="python send.py",
     adp=adapter(sources="jobs/**"), links=[("jobs/linked", "jobs/demo", "dir")], tr=lambda P: reads_all(base(P), P))
make("a_link_outside_the_double_star_tree", ex(ALLOW), cmd="python send.py", adp=adapter(sources="jobs/**/b.jpg"), links=[("other/l", "jobs/demo", "dir")],
     tr=lambda P: reads_all(base(P), P))
make("a_link_elsewhere_in_the_project", ex(ALLOW), cmd="python send.py", links=[("other/l", "jobs/demo", "dir"), ("other/f", "jobs/demo/plan.pdf", "file")],
     tr=lambda P: reads_all(base(P), P))
make("a_junction_elsewhere_in_the_project", ex(ALLOW), cmd="python send.py", links=[("other/j", "jobs/demo", "junction")], tr=lambda P: reads_all(base(P), P))
make("a_link_no_publish_is_no_business", ex(ALLOW), cmd="python other.py", adp=adapter(sources="jobs/demo/link.pdf"),
     links=[("jobs/demo/link.pdf", "jobs/demo/plan.pdf", "file")], tr=lambda P: base(P))
# an absolute source is owner-written and taken literally: a link on its path IS followed (documented in the guard)
make("a_absolute_source_through_a_link_is_followed", ex(ALLOW), cmd="python send.py", adp=lambda P: adapter(sources=P + "/jobs/linked/plan.pdf"),
     links=[("jobs/linked", "jobs/demo", "dir")], tr=lambda P: base(P).read(P + "/jobs/linked/plan.pdf"))
# the automount trees are network paths whatever their spelling
for nm, val in (("net_tree", "/net/192.0.2.7/x"), ("network_tree", "/Network/x"), ("net_upper", "/NET/192.0.2.7/x"), ("network_lower", "/network/x/y.pdf"),
                ("net_backslashes_after_slash", "/net\\192.0.2.7\\x"), ("net_through_dotdot", "/xx/../net/192.0.2.7/s/a.pdf"),
                ("network_through_dot", "/./Network/x/a.pdf"), ("net_through_dotdot_backslash", "/x\\..\\NET\\192.0.2.7\\s\\a.pdf"),
                ("net_bare_folder_through_dotdot", "/xx/../net")):
    make("d_not_plain_" + nm, ex(DENY, has=[val + NET], max=5), cmd="python send.py", adp=adapter(sources=val), tr=lambda P: base(P))
make("d_net_lookalike_is_a_plain_path", ex(DENY, has=["source pattern matches no file: /netflix/x.pdf."], max=5), cmd="python send.py",
     adp=adapter(sources="/netflix/x.pdf"), tr=lambda P: base(P))
make("d_netx_is_a_plain_path", ex(DENY, has=["source pattern matches no file: /netx/a.pdf."], max=5), cmd="python send.py",
     adp=adapter(sources="/netx/a.pdf"), tr=lambda P: base(P))
make("d_netx_through_dotdot_is_a_plain_path", ex(DENY, has=["source pattern matches no file: /xx/../netx/a.pdf."], max=5), cmd="python send.py",
     adp=adapter(sources="/xx/../netx/a.pdf"), tr=lambda P: base(P))
make("a_netx_no_publish", ex(ALLOW, max=5), cmd="python other.py", adp=adapter(sources="/netx/a.pdf"), tr=lambda P: base(P))
make("d_net_folder_inside_a_drive_is_a_plain_path", ex(DENY, has=["source pattern matches no file: C:/net/x.pdf."], max=5), cmd="python send.py",
     adp=adapter(sources="C:/net/x.pdf"), tr=lambda P: base(P))
make("a_net_path_no_publish", ex(ALLOW, max=5), cmd="python other.py", adp=adapter(sources="/net/192.0.2.7/x"), tr=lambda P: base(P))

# 6: a value echoed in a reason is cut at 200 characters, a whole reason at 2,000 (a 1 MB sources value; the unit checks are below)
X200 = "x" * 200
make("d_size_1mb_pattern", ex(DENY, has=["source pattern matches no file: " + X200 + "\u2026."], no=["x" * 201], maxlen=2000), cmd="python send.py",
     adp=adapter(sources="x" * 1000000), tr=lambda P: base(P))
make("d_size_long_glob_pattern", ex(DENY, has=["source pattern matches no file: " + "jobs/" + "y" * 195 + "\u2026."], no=["y" * 196], maxlen=2000), cmd="python send.py",
     adp=adapter(sources="jobs/" + "y" * 100000 + "*"), tr=lambda P: base(P))
make("d_size_1mb_not_plain", ex(DENY, has=["../" + "z" * 197 + "\u2026" + NET], no=["z" * 198], maxlen=2000, max=5), cmd="python send.py",
     adp=adapter(sources="../" + "z" * 1000000), tr=lambda P: base(P))
make("d_size_1mb_link", ex(DENY, has=[linkmsg("jobs/linked/" + "w" * 188 + "\u2026", "jobs/linked")], maxlen=2000), cmd="python send.py",
     adp=adapter(sources="jobs/linked/" + "w" * 1000000), links=[("jobs/linked", "jobs/demo", "dir")], tr=lambda P: base(P))
make("d_size_many_unopened_still_capped", ex(DENY, has=["12 of 12 sources not opened"], maxlen=2000), cmd="python send.py",
     adp=adapter(sources="many/*.txt"), files=[], nfiles=("many", 12), tr=lambda P: base(P))

# --- review fixes (round 7). M1: a pattern whose FIRST word is a wrapper the guard skips (uv, poetry, hatch, pdm, rye, pipx, wsl,
# start, setsid, busybox, Start-Process, saps) still matches: the pattern is tried from every wrapper position of a statement, not only
# from the command word after the wrappers. Other uses of the same runner stay allowed.
WPUB = "uv publish, poetry publish, hatch publish, pdm publish, rye publish, pipx run twine upload, wsl ./deploy.sh, start deploy.bat, setsid ./ship.sh, busybox sh ship.sh, Start-Process ./go.ps1, saps ./go2.ps1"
for nm, cm in (("uv", "uv publish dist/*"), ("poetry", "poetry publish --build"), ("hatch", "hatch publish"), ("pdm", "pdm publish"), ("rye", "rye publish"),
               ("pipx", "pipx run twine upload dist/*"), ("wsl", "wsl ./deploy.sh"), ("start", "start deploy.bat"), ("setsid", "setsid ./ship.sh"),
               ("busybox", "busybox sh ship.sh"), ("env_uv", "env A=1 uv publish"), ("timeout_uv", "timeout 60 uv publish dist/*"), ("var_uv", "A=1 uv publish"),
               ("compound_uv", "if true; then uv publish; fi"), ("startprocess", "Start-Process ./go.ps1"), ("saps", "saps ./go2.ps1"),
               ("nohup_poetry", "nohup poetry publish")):
    make("d_m1_" + nm, ex(DENY, has=["sources not opened"]), cmd=cm, adp=adapter(publish=WPUB), tr=lambda P: base(P))
    make("d_m1_ps_" + nm, ex(DENY, has=["sources not opened"]), adp=adapter(publish=WPUB), tr=lambda P: base(P), **PS(cm))
for nm, cm in (("uv_run_other", "uv run python other.py"), ("uv_pip", "uv pip list"), ("poetry_run", "poetry run pytest"), ("pipx_run_other", "pipx run black ."),
               ("wsl_other", "wsl ls"), ("start_other", "start other.bat"), ("hatch_build", "hatch build"), ("env_other", "env A=1 python other.py")):
    make("a_m1_" + nm, ex(ALLOW), cmd=cm, adp=adapter(publish=WPUB), tr=lambda P: base(P))
    make("a_m1_ps_" + nm, ex(ALLOW), adp=adapter(publish=WPUB), tr=lambda P: base(P), **PS(cm))
# M3: one PowerShell statement of 6,000 words that all match the pattern's first word, then a real publish: decided inside the hook's
# 10 s timeout (the time went quadratic: the words after every head match were scanned again)
make("d_m3_ps_many_heads", ex(DENY, has=["3 of 3 sources not opened"], max=9), tr=lambda P: base(P), **PS("Write-Output " + "git " * 6000 + "; git push"))
make("a_m3_ps_many_heads_no_publish", ex(ALLOW, max=9), tr=lambda P: base(P), **PS("Write-Output " + "git " * 6000))
make("d_m3_ps_start_process_many_heads", ex(DENY, has=["3 of 3 sources not opened"], max=9), tr=lambda P: base(P),
     **PS("Start-Process git -ArgumentList " + "git " * 6000 + " push"))
# M2: a quoted word that spans lines must not hide the lines inside it. (a) the cap: 17 heredocs read as code, an apostrophe in one body
# and another in a later one used to pair up and hide the publish line between them; (b) PowerShell: an apostrophe in a here-string
# and one in a comment, two here-strings that each hold one quote, an escaped quote; (c) Bash comments with an apostrophe (a known limit)
CAP17 = "cat > a.md <<EOF\nit's data\nEOF\ngit push\ncat > b.md <<EOF\ndon't\nEOF\n" + "".join("cat > f%d.md <<EOF\nnote %d\nEOF\n" % (i, i) for i in range(15))
make("d_m2a_cap_apostrophes", ex(DENY, has=["3 of 3 sources not opened"]), cmd=CAP17, tr=lambda P: base(P))
make("a_m2a_cap_apostrophes_no_publish", ex(ALLOW), cmd=CAP17.replace("git push", "git status"), tr=lambda P: base(P))
make("d_m2b_herestring_apostrophes", ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P),
     **PS('git commit -m @"\nFix the user\'s login\n"@\ngit push  # it\'s ready'))
make("a_m2b_herestring_apostrophes_no_publish", ex(ALLOW), tr=lambda P: base(P),
     **PS('git commit -m @"\nFix the user\'s login\n"@\ngit status  # it\'s ready'))
make("d_m2b_two_herestrings_one_quote_each", ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P),
     **PS('$a = @"\nsize 5"\n"@\ngit push\n$n = @"\n"quoted\n"@'))
make("d_m2b_escaped_quotes", ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P), **PS('Write-Host "a`""; git push; Write-Host "`"b"'))
make("d_m2b_escaped_single_quotes", ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P), **PS("Write-Host 'a`''; git push; Write-Host '`'b'"))
make("a_m2b_escaped_quotes_no_publish", ex(ALLOW), tr=lambda P: base(P), **PS('Write-Host "a`""; git status; Write-Host "`"b"'))
# (c) KNOWN LIMIT, pinned: on Bash a quoted word that spans lines is read whole (reading every Bash text line by line as well turned seven
# existing allows, quoted commit messages and PR bodies with a line that is a publish command, into denies), so an apostrophe in one comment
# pairs with one in a later comment and hides the line between them. Allowed today; the day this is fixed the case flips (ROADMAP).
make("a_m2c_known_limit_bash_comment_apostrophes_pinned", ex(ALLOW), cmd="# it's ready\ngit push origin main\n# check the PR's status", tr=lambda P: base(P))
make("a_m2c_bash_comment_apostrophes_no_publish", ex(ALLOW), cmd="# it's ready\ngit status\n# check the PR's status", tr=lambda P: base(P))
# M4 (a): one heredoc opener with a 12,000-character delimiter and 6,000 body lines before a publish (the opener scan backtracked once per
# delimiter character); (b) a state write whose plain argument cannot be split in a hurry
make("d_m4a_long_delimiter", ex(DENY, has=["3 of 3 sources not opened"], max=9), cmd="cat <<" + "a" * 12000 + "\n" + "x\n" * 6000 + "git push", tr=lambda P: base(P))
make("a_m4a_short_delimiter_data", ex(ALLOW), cmd="cat <<" + "a" * 64 + "\ngit push\n" + "a" * 64 + "\n", tr=lambda P: base(P))
STATE = 'bash "/p/hooks/py.sh" "/p/hooks/ledger.py" --unit 3 status=done note='
make("d_m4b_state_arg_then_publish", ex(DENY, has=["3 of 3 sources not opened"], max=9), cmd=STATE + "a" * 12 + " && git push", tr=lambda P: base(P))
make("d_m4b_state_arg_then_publish_ps", ex(DENY, has=["3 of 3 sources not opened"], max=9), tr=lambda P: base(P), **PS(STATE + "a" * 12 + " && git push"))
make("a_m4b_state_write_stays_data", ex(ALLOW, max=9), cmd=STATE + "a" * 12 + " 'git push was refused'", tr=lambda P: base(P))
# minors. m1: a string piped into iex / Invoke-Expression is code; m2: a decoded -EncodedCommand is normalised like the rest;
# m3: runner options the guard does not know (uv run --package app python send.py); n3: Start-Process after an assignment
ENC_BT = __import__("base64").b64encode("gi`t push".encode("utf-16-le")).decode()
for nm, cm in (("iex_single", "'git push' | iex"), ("iex_double", '"git push" | iex'), ("invoke_expression", "'python send.py' | Invoke-Expression"),
               ("iex_write_output", "Write-Output 'git push' | iex"), ("iex_alias_case", "'git push' | IEX")):
    make("d_m1b_" + nm, ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P), **PS(cm))
make("a_m1b_iex_other_text", ex(ALLOW), tr=lambda P: base(P), **PS("'Get-Date' | iex"))
make("a_m1b_piped_text_not_into_iex", ex(ALLOW), tr=lambda P: base(P), **PS("'git push' | Out-File notes.txt"))
make("d_m2m_encoded_backtick", ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P), **PS("pwsh -enc " + ENC_BT))
for nm, cm in (("uv_package", "uv run --package app python send.py"), ("uv_index", "uv run --index-url https://x.test python send.py"),
               ("poetry_C", "poetry -C sub run python send.py"), ("pdm_p", "pdm -p sub run python send.py"), ("hatch_env", "hatch -e prod run python send.py"),
               ("pipx_spec", "pipx run --spec foo python send.py"), ("uv_isolated", "uv --quiet run --no-project --isolated python send.py")):
    make("d_m3m_" + nm, ex(DENY, has=["3 of 3 sources not opened"]), cmd=cm, tr=lambda P: base(P))
for nm, cm in (("uv_run_other", "uv run python other.py"), ("poetry_run_pytest", "poetry run pytest"), ("uv_package_other", "uv run --package app python other.py"),
               ("poetry_C_other", "poetry -C sub run pytest")):
    make("a_m3m_" + nm, ex(ALLOW), cmd=cm, tr=lambda P: base(P))
for nm, cm in (("assign", "$p = Start-Process -ArgumentList push -FilePath git -PassThru"), ("assign_glued", "$p=Start-Process -ArgumentList push -FilePath git"),
               ("assign_saps", "$p = saps -ArgumentList push -FilePath git"), ("in_pipeline", "Get-Date | Start-Process -ArgumentList push -FilePath git"),
               ("after_semicolon", "Write-Host x; Start-Process -ArgumentList push -FilePath git")):
    make("d_n3_" + nm, ex(DENY, has=["3 of 3 sources not opened"]), tr=lambda P: base(P), **PS(cm))
make("a_n3_start_process_other", ex(ALLOW), tr=lambda P: base(P), **PS("$p = Start-Process -ArgumentList status -FilePath git -PassThru"))

open(OUT + "/order.txt", "w", newline="\n").write("\n".join(ORDER) + "\n")
open(OUT + "/skipped.txt", "w", newline="\n").write("".join(s + "\n" for s in SKIPS))
PY

cat > "$D/chk.py" <<'PY'
import ast, json, os, re, sys

mode = sys.argv[1]


def rd(p):
    try:
        with open(p, encoding="utf-8") as fh:
            return fh.read()
    except Exception:
        return ""


if mode == "results":    # results <cases dir> <results dir>: one PASS / FAIL line per case
    cdir, rdir = sys.argv[2], sys.argv[3]
    for name in rd(cdir + "/order.txt").split():
        meta = json.loads(rd(cdir + "/" + name + "/meta.json"))
        out, err, rc, secs = rd(rdir + "/" + name + ".out"), rd(rdir + "/" + name + ".err"), rd(rdir + "/" + name + ".rc").strip(), rd(rdir + "/" + name + ".secs").strip()
        if err.strip() or rc != "0":
            print("FAIL %s: rc=%s err=%r" % (name, rc, err[:200]))
            continue
        if meta.get("max") and secs.isdigit() and int(secs) >= meta["max"]:
            print("FAIL %s: decided in %s s (needs under %s: a gate that touches the network stalls)" % (name, secs, meta["max"]))
            continue
        if meta["mode"] == "allow":
            print(("PASS allow %s (%s s)" % (name, secs)) if out == "" else "FAIL allow %s: printed %r" % (name, out[:200]))
            continue
        try:
            o = json.loads(out)
            h = o["hookSpecificOutput"]
            assert sorted(o) == ["hookSpecificOutput"] and sorted(h) == ["hookEventName", "permissionDecision", "permissionDecisionReason"]
            assert h["hookEventName"] == "PreToolUse" and h["permissionDecision"] == "deny"
            r = h["permissionDecisionReason"]
        except Exception as e:
            print("FAIL deny %s: no deny JSON in %r (%s)" % (name, out[:200], type(e).__name__))
            continue
        bad = []
        if meta.get("maxlen") and len(r) > meta["maxlen"]:
            bad.append("reason is %d characters (limit %d)" % (len(r), meta["maxlen"]))
        if not r.startswith(meta["prefix"]):
            bad.append("prefix %r" % r[:60])
        bad += ["missing %r" % s for s in meta["has"] if s not in r]
        bad += ["unexpected %r" % s for s in meta["no"] if s in r]
        bad += ["no match for /%s/" % s for s in meta["rx"] if not re.search(s, r)]
        print(("PASS deny %s (%s s)" % (name, secs)) if not bad else "FAIL deny %s: %s in %r" % (name, "; ".join(bad), r[:400]))
elif mode == "snap":     # snap <dir>: every file's relative path and size, sorted
    root = sys.argv[2]
    rows = []
    for dp, dn, fn in os.walk(root):
        for f in fn:
            p = os.path.join(dp, f)
            rows.append("%s %d" % (os.path.relpath(p, root).replace("\\", "/"), os.path.getsize(p)))
    print("\n".join(sorted(rows)))
elif mode == "imports":  # imports <bash-guard.py>: stdlib only, no process or network, the 3.9 grammar
    src = rd(sys.argv[2])
    tree = ast.parse(src, feature_version=(3, 9))
    mods = sorted({a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names} |
                  {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module})
    calls = sorted({n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id == "os"
                    and (n.attr in ("system", "popen", "fork", "startfile") or n.attr.startswith(("exec", "spawn")))})
    ok = set(mods) <= {"json", "os", "re", "sys", "time", "stat", "posixpath", "glob", "fnmatch", "datetime", "itertools", "threading", "base64"} and not calls
    print("ok" if ok else "imports %s, process calls %s" % (mods, calls))
elif mode == "execsilent":   # execsilent <bash-guard.py>: until-done.py's way of reusing RULES prints nothing, and the file has one main() line to cut
    src = rd(sys.argv[2])
    if src.count("\nmain()\n") != 1:
        print("the file has %d lines that are exactly main() (until-done.py cuts them all)" % src.count("\nmain()\n"))
    else:
        ns = {}
        exec(compile(src.replace("\nmain()\n", "\n"), "bash-guard", "exec"), ns)
        print("ok" if ns.get("RULES") else "no RULES")
elif mode == "units":    # units <bash-guard.py> <empty dir>: the size caps on the functions themselves (file names too long for a temp path are not needed)
    import contextlib, io
    ns = {}
    exec(compile(rd(sys.argv[2]).replace("\nmain()\n", "\n"), "bash-guard", "exec"), ns)

    def denied(why):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            ns["deny"](why)
        return json.loads(buf.getvalue())["hookSpecificOutput"]["permissionDecisionReason"]
    bad = []
    r = denied("z" * 5000)
    if len(r) != 2000 or not r.startswith("bash-guard: zzz") or not r.endswith("…"):
        bad.append("a 5000-character reason came out as %d characters" % len(r))
    if denied("short") != "bash-guard: short":
        bad.append("a short reason was changed")
    out, why = ns["expand_sources"](sys.argv[3], ["a" * 300])
    if out is not None or ("a" * 200 + "….") not in why or "a" * 201 in why:
        bad.append("a 300-character pattern is echoed as %r" % why[:80])
    ns["expand_by_deadline"] = lambda project, sources, deadline: ([("k" + str(i), "n" * 300 + str(i)) for i in range(12)], "")
    ns["opened_since_compaction"] = lambda tp, project, deadline: (set(), None)
    why = ns["fresh_verdict"]({"transcript_path": "t.jsonl"}, sys.argv[3], ["x"], 10 ** 12)
    if "n" * 201 in why or ("n" * 200 + "…") not in why or "and 2 more" not in why:
        bad.append("unopened file names are not cut at 200 characters")
    # the link predicate on fake lstat results: only link-like reparse points count (the name-surrogate bit of the tag), not cloud-sync ones
    import collections
    St = collections.namedtuple("St", "st_mode st_file_attributes st_reparse_tag")
    Posix = collections.namedtuple("Posix", "st_mode")
    REG, LNK, RP = 0o100644, 0o120777, 0x400
    try:
        for label, st, want in (("cloud-sync tag 0x9000001A", St(REG, RP | 0x20, 0x9000001A), False), ("cloud-sync tag 0x8000001E", St(REG, RP, 0x8000001E), False),
                                ("symlink tag 0xA000000C", St(REG, RP, 0xA000000C), True), ("mount point / junction tag 0xA0000003", St(REG, RP | 0x10, 0xA0000003), True),
                                ("no reparse attribute", St(REG, 0x20, 0), False), ("a tag without the reparse attribute", St(REG, 0x20, 0xA000000C), False),
                                ("S_ISLNK mode", St(LNK, 0, 0), True), ("plain POSIX stat", Posix(REG), False), ("POSIX symlink", Posix(LNK), True)):
            if bool(ns["is_link_stat"](st)) != want:
                bad.append("is_link_stat(%s) is not %s" % (label, want))
    except Exception as e:
        bad.append("is_link_stat: " + type(e).__name__)
    print("ok" if not bad else "; ".join(bad))
elif mode == "bounded":  # bounded <bash-guard.py> <empty dir>: the heredoc scan is capped, the deadline is a parameter
    import time
    ns = {}
    exec(compile(rd(sys.argv[2]).replace("\nmain()\n", "\n"), "bash-guard", "exec"), ns)
    bad = []
    # three shapes of 8,000 unclosed openers (the publish word last) are found in under 1 s each, measured around the stripping and
    # the match (no interpreter start in the number); the stripping is cap_strip, else gate_strip (the guard before the cap)
    strip = ns.get("cap_strip") or ns["gate_strip"]
    opens = "x <<a\n" * 8000
    for label, cmd in (("plain openers", opens + "git push"), ("openers inside $( )", 'echo "$(' + opens + 'git push)"'),
                       ("openers inside backticks", 'echo "`' + opens + 'git push`"')):
        t0 = time.perf_counter()
        hit = ns["publish_hit"](strip(cmd), ["git push"], 0, cmd)
        took = time.perf_counter() - t0
        if hit is not True or took >= 1.0:
            bad.append("8000 %s: publish_hit=%r in %.1f s (needs True in under 1 s)" % (label, hit, took))
    # a deadline already past: the gate denies (never lets a matched publish through) with the budget in the reason
    proj = sys.argv[3] + "/f2proj"
    os.makedirs(proj + "/.claude", exist_ok=True)
    with open(proj + "/.claude/smartuse.local.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write("sources: a.pdf\npublish: git push\n")
    os.environ["CLAUDE_PROJECT_DIR"] = proj
    try:
        why = ns["fresh_gate"]({"cwd": proj, "transcript_path": proj + "/t.jsonl"}, "git push", None, time.monotonic() - 1)
        if not why or "could not verify" not in why or "(source expansion over 4 s)" not in why:
            bad.append("fresh_gate with a deadline in the past returned %r" % (why,))
    except Exception as e:
        bad.append("fresh_gate(data, text, raw, deadline): " + type(e).__name__)
    # the unreadable-encoded-command flag belongs to one call: a second call in the same namespace must not inherit it
    try:
        data = {"cwd": proj, "transcript_path": proj + "/t.jsonl"}
        first = ns["fresh_gate"](data, "pwsh -enc not-base64!!", None, None, True)
        second = ns["fresh_gate"](data, "git push", None, time.monotonic() - 1, True)
        if not first or "encoded command" not in first:
            bad.append("an undecodable encoded command gave %r" % (first,))
        if not second or "encoded command" in second or "could not verify" not in second:
            bad.append("a second fresh_gate call inherited the first call's unreadable flag: %r" % (second,))
    except Exception as e:
        bad.append("per-call flag: " + type(e).__name__)
    print("ok" if not bad else "; ".join(bad))
elif mode == "linear":   # linear <bash-guard.py>: the pattern match, the state-write strip and the heredoc pre-check take time linear in the text
    import time
    ns = {}
    exec(compile(rd(sys.argv[2]).replace("\nmain()\n", "\n"), "bash-guard", "exec"), ns)
    bad = []

    def timed(label, f, want):
        """True when f() gives `want` in under 1 s (function time: no interpreter start in the number); else a note is added."""
        t0 = time.perf_counter()
        got = f()
        took = time.perf_counter() - t0
        if got != want or took >= 1.0:
            bad.append("%s: %r in %.1f s (needs %r in under 1 s)" % (label, got, took, want))
            return False
        return True

    def ps(t, pats):
        return ns["publish_hit"](ns["ps_text"](t).replace("\\", "/"), pats, 0, None, True)

    def sh(t, pats):
        return ns["publish_hit"](t, pats, 0)
    # (label, function, wanted): each family is run at 24 KB and at 96 KB; a family that is already slow at 24 KB is not run at 96 KB
    for label, mk in (
            ("PowerShell: heads then a publish", lambda n: (lambda: ps("Write-Output " + "git " * n + "; git push", ["git push"]), True)),
            ("PowerShell: heads, no publish", lambda n: (lambda: ps("Write-Output " + "git " * n, ["git push"]), False)),
            ("PowerShell: Start-Process heads, no publish", lambda n: (lambda: ps("Start-Process " + "git " * n, ["git push"]), False)),
            ("PowerShell: Start-Process heads then the argument", lambda n: (lambda: ps("Start-Process git -ArgumentList " + "git " * n + " push", ["git push"]), True)),
            ("PowerShell: a string piped into iex", lambda n: (lambda: ps("'" + "git " * n + "push' | iex", ["git push"]), True)),
            ("Bash: runner words then a publish", lambda n: (lambda: sh("uv run " + "x " * n + "python send.py", ["python send.py"]), True)),
            ("Bash: runner words, no publish", lambda n: (lambda: sh("uv run " + "python " * n, ["python send.py"]), False)),
            ("Bash: a chain of wrappers", lambda n: (lambda: sh("env " * n + "uv publish", ["uv publish"]), True)),
            ("Bash: a chain of runners", lambda n: (lambda: sh("uv " * n + "x", ["uv publish"]), False)),
            ("PowerShell: many lines, an apostrophe in each", lambda n: (lambda: ps("# it's\n" * (n // 2) + "git push\n# it's", ["git push"]), True)),
            ("Bash: 17 heredocs read as code, many lines", lambda n: (lambda: sh("x <<a\n" * 17 + "# it's\n" * (n // 2) + "git push\n# it's", ["git push"]), True))):
        for size, n in (("24 KB", 6000), ("96 KB", 24000)):
            f, want = mk(n)
            if not timed("%s, %s" % (label, size), f, want):
                break
    # the heredoc opener with a very long delimiter: read as code, not scanned; found at 96 KB too
    for body in (6000, 24000):
        cmd = "cat <<" + "a" * 12000 + "\n" + "x\n" * body + "git push"
        timed("one heredoc opener with a 12,000-character delimiter, %d lines" % body, lambda: ns["publish_hit"](ns["cap_strip"](cmd), ["git push"], 0, cmd), True)
    # the state-write strip: a plain argument that cannot be split in a hurry, at a length that took over 10 s before; the shape stays data
    st = 'bash "/p/hooks/py.sh" "/p/hooks/ledger.py" --unit 3 status=done note='
    for plain in (12, 4000, 100000):
        c = st + "a" * plain + " && git push"
        if not timed("state write, %d plain characters then && git push" % plain, lambda: ns["strip_state_args"](c) == c, True):
            break
    ok_c = st + "a" * 100000 + " 'git push was refused'"
    timed("state write, a 100,000-character plain argument and a quoted note", lambda: "git push" not in ns["strip_state_args"](ok_c), True)
    print("ok" if not bad else "; ".join(bad))
elif mode == "hooks":    # hooks <hooks.json>
    d = json.loads(rd(sys.argv[2]))
    pre = d["hooks"]["PreToolUse"]
    bg = [e for e in pre if any("bash-guard.py" in h["command"] for h in e["hooks"])]
    bash = [e for e in pre if e.get("matcher") == "Bash|PowerShell"]
    pub = [e for e in bg if e.get("matcher") == "mcp__.*(upload|send|publish|post|share|submit).*"]
    others = [(e.get("matcher"), re.search(r"hooks/([a-z-]+)\.py", e["hooks"][0]["command"]).group(1), e["hooks"][0].get("timeout")) for e in pre if e not in bg]
    good = (len(bash) == 1 and len(bash[0]["hooks"]) == 1 and len(pub) == 1 and len(bg) == 2 and len(pub[0]["hooks"]) == 1
            and pub[0]["hooks"][0]["command"] == bash[0]["hooks"][0]["command"] and pub[0]["hooks"][0].get("timeout") == 10
            and pub[0]["hooks"][0].get("type") == "command"
            and sorted(others, key=str) == sorted([("Write|Edit|MultiEdit|NotebookEdit", "file-guard", 10), ("*", "heartbeat", 5)], key=str))
    print("ok" if good else "PreToolUse: bash-guard %r, others %r" % ([(e.get("matcher"), e["hooks"][0].get("timeout")) for e in bg], others))
PY

py "$D/mk.py" "$(wp "$D/c")" "$MSYS" "$(wp "$BG")" </dev/null || { echo "FAIL could not build the synthetic cases"; exit 1; }
[ -s "$D/c/order.txt" ] || { echo "FAIL the synthetic cases are missing"; exit 1; }

# --- drive the guard once per case; the answers go to $D/r (outside the cases, so the "nothing written" snapshot is of the inputs only)
py "$D/chk.py" snap "$D/c" > "$D/snap.before" </dev/null
for n in $(cat "$D/c/order.txt"); do
  c="$D/c/$n"; gd="$G"; [ -f "$c/guard" ] && gd=$(cat "$c/guard")
  E=(env -u CLAUDE_PROJECT_DIR)
  [ -f "$c/env" ] && E=(env "CLAUDE_PROJECT_DIR=$(cat "$c/env")")
  [ -f "$c/pyenc" ] && E+=("PYTHONIOENCODING=$(cat "$c/pyenc")")
  for try in 1 2; do   # a case with a time limit gets a second go: the laptop's interpreter start alone can take seconds under load, a gate stalled on the network takes tens of seconds every time
    t0=$(date +%s)
    "${E[@]}" bash "$H/py.sh" "$gd" < "$c/event.json" > "$D/r/$n.out" 2> "$D/r/$n.err"; echo $? > "$D/r/$n.rc"
    echo $(( $(date +%s) - t0 )) > "$D/r/$n.secs"
    [ "$(grep -o '"max": [0-9]*' "$c/meta.json" | grep -o '[0-9]*$')" -gt "$(cat "$D/r/$n.secs")" ] 2>/dev/null && break
    grep -q '"max": [1-9]' "$c/meta.json" || break
  done
done
py "$D/chk.py" results "$D/c" "$D/r" </dev/null > "$D/results.txt"
cat "$D/results.txt"
grep -q '^FAIL' "$D/results.txt" && fail=1
while IFS= read -r l; do [ -n "$l" ] && ok "(skipped the link cases: $l)"; done < "$D/c/skipped.txt"
[ "$(grep -c '^PASS\|^FAIL' "$D/results.txt")" = "$(grep -c . "$D/c/order.txt")" ] && ok "every case printed exactly one result ($(grep -c . "$D/c/order.txt") cases)" || ko "some case printed no result line"

# --- the 2 MB transcript: the pass has a 3 s budget of its own and a pass over it ends in an allow, not a "could not verify" deny
#     (above). The wall time here is mostly the laptop's Python start (0.4 to 3.6 s, sometimes more under load), so it only has to stay sane.
for n in a_big_2mb d_big_2mb_one_unopened; do
  sz=$(wc -c < "$D/c/$n/t.jsonl" | tr -d ' '); s=$(cat "$D/r/$n.secs")
  if [ "$sz" -gt 2000000 ] && [ "$s" -lt 30 ]; then ok "$n: transcript of $sz bytes decided in $s s (interpreter start included; hook timeout 10 s)"; else ko "$n: transcript of $sz bytes, $s s (needs > 2 MB and < 30 s)"; fi
done

# --- nothing is written: not in the project, not in the state dir
py "$D/chk.py" snap "$D/c" > "$D/snap.after" </dev/null
cmp -s "$D/snap.before" "$D/snap.after" && ok "no file was created, changed or removed in any project dir (adapter, sources, transcript)" || ko "the gate wrote into a project dir: $(diff "$D/snap.before" "$D/snap.after" | head -3 | tr '\n' ' ')"
[ -z "$(ls -A "$HOME/.claude/smartuse" | grep -v '^interpreter$')" ] && ok "no state file in ~/.claude/smartuse (the launcher's interpreter hint aside)" || ko "state written: $(ls -A "$HOME/.claude/smartuse")"

# --- structure
r=$(py "$D/chk.py" imports "$G" </dev/null); [ "$r" = ok ] && ok "stdlib only (json os re sys time stat fnmatch datetime threading), no process call, Python 3.9 grammar" || ko "imports: $r"
mkdir -p "$D/empty"; r=$(py "$D/chk.py" units "$G" "$(wp "$D/empty")" </dev/null 2>&1 | tail -1); [ "$r" = ok ] && ok "unit checks on the functions: a value echoed in a reason is cut at 200 characters, a whole reason at 2,000; only link-like reparse points are links" || ko "size caps: $r"
r=$(py "$D/chk.py" bounded "$G" "$(wp "$D/empty")" </dev/null 2>&1 | tail -1); [ "$r" = ok ] && ok "bounded scan: three 8,000-opener shapes found in under 1 s each; a deadline in the past denies ('source expansion over 4 s')" || ko "bounded scan: $r"
r=$(py "$D/chk.py" linear "$G" </dev/null 2>&1 | tail -1); [ "$r" = ok ] && ok "linear time: ten shapes of 6,000 and 24,000 words (PowerShell heads, Start-Process, iex, runner and wrapper chains, apostrophe lines), a 12,000-character heredoc delimiter and a state-write argument of 100,000 characters each decided in under 1 s" || ko "linear time: $r"
r=$(py "$D/chk.py" execsilent "$G" </dev/null); [ "$r" = ok ] && ok "until-done.py's exec of this file without main() prints nothing and yields RULES" || ko "exec without main(): $r"
r=$(py "$D/chk.py" hooks "$H/hooks.json" </dev/null); [ "$r" = ok ] && ok "hooks.json: one Bash|PowerShell entry, one mcp__ entry (same command, timeout 10), file-guard and heartbeat entries unchanged" || ko "hooks.json: $r"

[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
