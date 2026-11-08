#!/usr/bin/env python3
"""recall.py — PreCompact + SessionStart hook: "the summary is not a source" (design: docs/notes/recall-design.md, F2 and F3).

The problem is a class: a long session is compacted, the model keeps a summary it wrote itself and loses the exact words. The owner's
words and the job's details are gone; or the job's real files are on disk but the model works from the summary and says "checked".
Claude Code reloads CLAUDE.md and a few recent files after a squeeze; it does not know which files are THIS job's sources. This hook
adds the pointer (never a store): it hands the summarizer the source list and the owner's last prompts to keep verbatim, and after the
squeeze it tells the model the summary is not a source and which files to open again. It prints text only; it refuses nothing.
Keys, read from the human-only adapter `.claude/smartuse.local.md` the way until-done.py reads `check:` (one line per key,
`key: value, value`, the first occurrence wins, frontmatter or body, values split on commas, trimmed, empty ones dropped):
  sources:       paths or globs the job's answer must come from (listed as written)
  publish:       shell command patterns (the fresh-source gate reads them; here only "is anything gated?")
  publish_tools: tool-name globs (the same)
  handoff:       one path, a hand-over note for the next session (F3)
The project dir is CLAUDE_PROJECT_DIR, else the event's cwd (native_path), else the process cwd (until-done.py's order).
PreCompact (F2): prints instructions for the summary: custom instructions first when the event carries any, then "keep these source
paths verbatim", "keep these owner prompts verbatim" (the last 8, oldest first), "mark anything not re-verified as from summary".
SessionStart `compact` (F2): the squeeze time and "The summary is not a source."; with `sources:` also the list ("none counts as opened
now; open each before any output") and the owner prompts. Without `sources:` just those two lines. The state file counts the squeeze.
SessionStart `startup` / `clear` / `resume` (F3): with `handoff:` its first 15 lines, its modified time and age, and a stale line when
the repo's last commit (the last entry of .git/logs/HEAD, a file read) is newer than the note; on `resume` with a compaction in the
transcript "resumed; the compacted part is a summary, not a source"; with `sources:` the list. Neither key: nothing is printed.
`sources:` set but neither `publish:` nor `publish_tools:`: one line says nothing is gated. A `publish_tools:` entry the PreToolUse
matcher cannot reach (mcp__.*(upload|send|publish|post|share|submit).*) is named as "not gated": the matcher decides which tool calls
the gate ever sees, so a glob without one of those words after a literal `mcp__` prefix is never checked.
Owner prompts: `user` records that are a genuine human prompt, by wait-gate.py's rules (copied, no import between hooks): turnOrigin /
origin.kind human or sdk (a record with neither field counts, as in older versions), not isMeta, not a compact summary, not text that
starts with a harness marker (task notification, reminder, command echo, peer message, interrupt notice). Sidechain records are a
subagent's, not the owner's. One forward pass, a 3 s budget (a transcript that takes longer is read as far as it got).
Scrub (everything printed): known token prefixes with a word boundary -> [secret], e-mail addresses -> [email], digit runs of 8 or more
-> [number]. Output is cut at 9,000 characters, never spilled to a file.
State: ~/.claude/smartuse/projects/<key>/recall.json {compactions, last_at, last_unopened}, <key> as ledger.py computes it; counts and
paths only, never a command; written at SessionStart `compact` only. Nothing is written inside the repo or the project.
Windows: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, never inside the event JSON, so
cwd / transcript_path go through native_path(); stdin is read as bytes and decoded as UTF-8; stdout is written as UTF-8 bytes.
Python 3.9 stdlib only, no subprocess, no network. Any error: exit 0 and print nothing (a hook must never block a compaction).
"""
import collections, datetime, json, os, pathlib, re, sys, time

HOME = pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~"))   # HOME first: on Windows expanduser("~") reads USERPROFILE and ignores HOME (the tests and users who set HOME need it)
BUDGET_S = 3.0                 # one pass over the transcript; the hook's timeout is 10 s
CAP = 9000                     # characters printed, at most
LAST_N = 8                     # owner prompts quoted
PROMPT_CUT = 300               # characters of one quoted prompt
HANDOFF_LINES = 15
CUSTOM_CUT = 4000              # custom instructions are printed first; they must not push the prompts out
KEYS = ("sources", "publish", "publish_tools", "handoff")
HUMAN = {"human", "sdk"}       # the turnOrigin / origin.kind values of a prompt a person (or the SDK caller) sent; anything else was injected by the harness
INJECTED = ("<task-notification>", "<system-reminder>", "<local-command-", "<command-name>", "Stop hook feedback:",
            "Another Claude session sent a message:", "[Request interrupted",
            "Caveat: The messages below were generated by the user while running local commands")   # text that is never a human prompt, whatever the record's fields say (older versions)
GATE_WORDS = re.compile(r"upload|send|publish|post|share|submit")   # the words of the gate's PreToolUse matcher mcp__.*(upload|send|publish|post|share|submit).*
SCRUB_TOKEN = re.compile(r"\b(?:sk-|ghp_|gho_|github_pat_|xox[abpr]-|AKIA|AIza)[A-Za-z0-9_-]{8,}")
SCRUB_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
SCRUB_NUMBER = re.compile(r"\d{8,}")
CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2066-\u2069]")


def native_path(p):
    """A path string from the event JSON as this interpreter can open it. On Windows the hook runs through Git Bash, which
    converts POSIX paths in arguments and environment variables for a Windows program but not inside JSON strings: given
    "/c/Users/x/t.jsonl", Windows Python looks under <current drive>:/c/Users/x/ and finds nothing. So when the string starts
    with "/" and nothing exists there, the MSYS drive form "/c/..." becomes "C:/..."; "/tmp/..." has no drive letter and stays
    as it is. Anything else, and everything on other platforms, comes back unchanged. Never raises."""
    try:
        s = str(p or "")
        if os.name == "nt" and s.startswith("/") and not os.path.exists(s):
            if len(s) >= 2 and "a" <= s[1].lower() <= "z" and (len(s) == 2 or s[2] == "/"):
                return s[1].upper() + ":" + (s[2:] or "/")
    except Exception:
        pass
    return p


def project_key(project):
    """The state-dir name of a project: its full resolved path with every character outside [A-Za-z0-9._-] replaced by "-"
    and a leading "-" dropped (/home/u/proj -> home-u-proj, C:/Users/u/proj -> C--Users-u-proj), the way Claude Code keys
    ~/.claude/projects/. Two repos that share a folder name get two state dirs."""
    return re.sub(r"[^A-Za-z0-9._-]", "-", str(pathlib.Path(project).resolve())).lstrip("-") or "root"


def state_dir(project):
    """~/.claude/smartuse/projects/<project_key()>/ — under the user's home, never inside the repo (same rule as heartbeat.py,
    ledger.py and until-done.py). Made (mkdir -p) only when this hook writes there."""
    return HOME / ".claude" / "smartuse" / "projects" / project_key(project)


def stdin_json():
    """The event JSON from stdin, read as bytes and decoded as UTF-8: Windows Python decodes a piped stdin in the ANSI code
    page, where one non-ASCII byte raises and the event would be lost; a bad byte becomes U+FFFD instead."""
    raw = sys.stdin.buffer.read() if hasattr(sys.stdin, "buffer") else sys.stdin.read().encode("utf-8", "replace")
    return json.loads(raw.decode("utf-8", "replace"))


def write_json(path, obj):
    """Atomic: tmp file + os.replace; on Windows the replace raises PermissionError while another hook has the file open: retry
    5 times, 20 ms apart; still failing -> drop the tmp file and give up (last writer wins). Never raises."""
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
        for attempt in range(5):
            try:
                os.replace(tmp, path)
                return True
            except OSError:
                if attempt < 4:
                    time.sleep(0.02)
    except Exception:
        pass
    try:
        tmp.unlink()
    except Exception:
        pass
    return False


def read_dict(path):
    try:
        d = json.loads(path.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else None
    except Exception:
        return None


def parse_ts(s):
    """An ISO-8601 stamp ("2026-10-22T20:41:03.123Z", with or without a zone) -> an aware UTC datetime, else None."""
    try:
        t = datetime.datetime.fromisoformat(str(s).replace("Z", "+00:00"))
        return t if t.tzinfo else t.replace(tzinfo=datetime.timezone.utc)
    except Exception:
        pass
    try:
        m = re.match(r"(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)", str(s))
        return datetime.datetime(*[int(x) for x in m.groups()], tzinfo=datetime.timezone.utc) if m else None
    except Exception:
        return None


def hhmm(t):
    """The local wall-clock time HH:MM of an aware datetime (the owner's clock, not UTC)."""
    try:
        return t.astimezone().strftime("%H:%M")
    except Exception:
        return t.strftime("%H:%M")


# ---------------------------------------------------------------- adapter keys

def adapter_keys(project):
    """{key: [value, ...]} for sources / publish / publish_tools / handoff from the human-authored adapter, read the way
    until-done.py adapter_check() reads `check:` (the first line `key: ...` wins, wherever it is; a value is a comma-separated
    list). A missing or unreadable adapter gives four empty lists."""
    out = {k: [] for k in KEYS}
    try:
        text = (project / ".claude" / "smartuse.local.md").read_text(encoding="utf-8-sig")
    except Exception:
        return out
    for k in KEYS:
        m = re.search(r"^" + k + r":[ \t]*(.*?)[ \t\r]*$", text, re.M)   # [ \t] not \s: an empty value must not swallow the next line
        if m:
            out[k] = [v for v in (x.strip().strip("'\"").strip() for x in m.group(1).split(",")) if v]
    return out


def gated_by_matcher(entry):
    """True when the PreToolUse matcher mcp__.*(upload|send|publish|post|share|submit).* reaches every tool a `publish_tools:`
    glob can match: the entry starts with a literal `mcp__` and one of the matcher's words stands in a literal part of the glob
    (a word that only a wildcard might supply would reach some tools, not all). Anything else is "not gated"."""
    if not entry.startswith("mcp__"):
        return False
    return any(GATE_WORDS.search(part) for part in re.split(r"[*?\[\]]", entry[len("mcp__"):]))


def notes(keys):
    """The warnings a session start repeats: nothing gated; publish_tools entries the matcher cannot reach."""
    out = []
    if keys["sources"] and not keys["publish"] and not keys["publish_tools"]:
        out.append("note: nothing is gated: sources: is set, but neither publish: nor publish_tools: is.")
    miss = [e for e in keys["publish_tools"] if not gated_by_matcher(e)]
    if keys["sources"] and miss:
        out.append("note: not gated (the tool matcher reaches only mcp__ tools whose name holds upload, send, publish, post, share or submit): "
                   + ", ".join(miss))
    return out


# ---------------------------------------------------------------- the owner's prompts

def blocks(r):
    m = r.get("message")
    c = m.get("content") if isinstance(m, dict) else None
    return [b for b in c if isinstance(b, dict)] if isinstance(c, list) else []


def text_of(content):
    """A content value (a string, or a list of text blocks) as one string."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b["text"] for b in content if isinstance(b, dict) and isinstance(b.get("text"), str))
    return ""


def user_text(content):
    """The text of a user record: the string, or its text blocks (an image counts as "[image]": a picture alone is a prompt too)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b["text"] if b.get("type") == "text" and isinstance(b.get("text"), str) else "[image]"
                         for b in content if isinstance(b, dict) and b.get("type") in ("text", "image"))
    return ""


def is_human(r, text, kind, turn):
    """A genuine human prompt: a user record with real text that was not injected (wait-gate.py's rule, copied)."""
    if r.get("isMeta") or r.get("isCompactSummary") or r.get("isVisibleInTranscriptOnly") or r.get("promptSource") == "system":
        return False
    if (kind is not None and kind not in HUMAN) or (turn is not None and turn not in HUMAN):
        return False
    t = text.lstrip()
    return bool(t) and not t.startswith(INJECTED)


def scrub(text):
    """Token prefixes -> [secret], e-mail addresses -> [email], digit runs of 8 or more -> [number]."""
    return SCRUB_NUMBER.sub("[number]", SCRUB_EMAIL.sub("[email]", SCRUB_TOKEN.sub("[secret]", text)))


def one_line(text, n):
    """Scrubbed, control characters out, whitespace collapsed to single spaces, cut at n characters (the cut comes last, so a
    token is masked whole before it can be cut in half)."""
    s = " ".join(CTRL.sub(" ", scrub(str(text))).split())
    return s if len(s) <= n else s[:n - 1].rstrip() + "…"


def scan(path):
    """One forward pass over the transcript -> {"prompts": the last LAST_N owner prompts (oldest first), "compacted": a squeeze is
    in it, "squeezed_at": the aware datetime of the last compaction marker or None}. The marker is a `system` record with subtype
    compact_boundary; a `user` record with isCompactSummary is the fallback. A line is parsed only when it holds one of the
    words that can matter. Records of a subagent (isSidechain) are not the owner's. Stops reading at BUDGET_S; what it has so far
    counts. Raises on an unreadable file."""
    prompts = collections.deque(maxlen=LAST_N)
    f = {"prompts": prompts, "compacted": False, "squeezed_at": None}
    boundary = summary = None
    deadline = time.monotonic() + BUDGET_S
    with open(path, "rb") as fh:
        for i, raw in enumerate(fh):
            if not (i & 255) and time.monotonic() > deadline:
                break
            has_mark = b"compact_boundary" in raw or b"isCompactSummary" in raw
            if not (has_mark or b'"user"' in raw or b"queued_command" in raw):
                continue
            if not has_mark and b'"tool_result"' in raw:
                continue
            try:
                r = json.loads(raw.decode("utf-8", "replace"))
            except Exception:
                continue
            if not isinstance(r, dict) or r.get("isSidechain"):
                continue
            t = r.get("type")
            if t == "system" and r.get("subtype") == "compact_boundary":
                f["compacted"], boundary = True, parse_ts(r.get("timestamp")) or boundary
            elif t == "user":
                if r.get("isCompactSummary"):
                    f["compacted"], summary = True, parse_ts(r.get("timestamp")) or summary
                    continue
                if any(b.get("type") == "tool_result" for b in blocks(r)):
                    continue
                m = r.get("message")
                text = user_text(m.get("content") if isinstance(m, dict) else None)
                o = r.get("origin")
                kind, turn = (o.get("kind") if isinstance(o, dict) else None), r.get("turnOrigin")
                if is_human(r, text, kind, turn):
                    prompts.append(one_line(text, PROMPT_CUT))
            elif t == "attachment":
                a = r.get("attachment")
                if isinstance(a, dict) and a.get("type") == "queued_command":   # a message the owner typed mid-turn: no user record of its own
                    p = a.get("prompt")
                    p = p if isinstance(p, str) else text_of(p)
                    o = a.get("origin")
                    if (o.get("kind") if isinstance(o, dict) else None) == "human" and p.strip() and not p.lstrip().startswith(INJECTED):
                        prompts.append(one_line(p, PROMPT_CUT))
    f["prompts"] = list(prompts)
    f["squeezed_at"] = boundary or summary
    return f


def scan_safe(data):
    """scan() of the event's transcript, or an empty result when there is none or it cannot be read."""
    empty = {"prompts": [], "compacted": False, "squeezed_at": None}
    try:
        tp = native_path(data.get("transcript_path") or "")
        return scan(tp) if tp and os.path.isfile(tp) else empty
    except Exception:
        return empty


# ---------------------------------------------------------------- the handoff note (F3)

def last_commit_epoch(project):
    """The time of the last entry of .git/logs/HEAD (a file read, no subprocess; a worktree's .git is a file naming its git dir),
    or None. The entry is `<old> <new> <name> <mail> <epoch> <zone><TAB><message>`; only the last 4 KB are read."""
    try:
        d = pathlib.Path(project).resolve()
        for base in [d] + list(d.parents)[:6]:
            g = base / ".git"
            if g.is_file():
                m = re.match(r"gitdir:\s*(.+)", g.read_text(encoding="utf-8").strip())
                gd = pathlib.Path(m.group(1).strip()) if m else None
                g = (gd if gd.is_absolute() else base / gd) if gd else None
            elif not g.is_dir():
                continue
            log = g / "logs" / "HEAD" if g else None
            if log is None or not log.is_file():
                return None
            with open(log, "rb") as fh:
                fh.seek(0, os.SEEK_END)
                size = fh.tell()
                fh.seek(max(0, size - 4096))
                tail = fh.read().decode("utf-8", "replace")
            for line in reversed(tail.splitlines()):
                m = re.search(r">\s+(\d{9,11})\s+[+-]\d{4}", line)
                if m:
                    return int(m.group(1))
            return None
    except Exception:
        pass
    return None


def age(seconds):
    s = max(0, int(seconds))
    return "under a minute" if s < 60 else f"{s // 60}m" if s < 3600 else f"{s // 3600}h" if s < 86400 else f"{s // 86400}d"


def handoff_lines(project, rel):
    """The printed lines for `handoff:`: the path, modified time and age, the first HANDOFF_LINES lines, a stale line when the
    repo's last commit is newer than the note. A missing file is said, not hidden."""
    p = pathlib.Path(str(native_path(rel)))
    if not p.is_absolute():
        p = project / p
    try:
        mtime = p.stat().st_mtime
        with open(p, "rb") as fh:
            body = fh.read(65536).decode("utf-8", "replace")
    except Exception:
        return [f"Handoff: {rel} was not found or cannot be read."]
    when = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
    out = [f"Handoff: {rel} · modified {when} ({age(time.time() - mtime)} ago). First lines:"]
    out += ["  " + one_line(l, PROMPT_CUT) if l.strip() else "" for l in body.splitlines()[:HANDOFF_LINES]]
    commit = last_commit_epoch(project)
    if commit is not None and commit > mtime:
        days = int((commit - mtime) // 86400)
        out.append(f"stale: the handoff is {days} days older than the last commit" if days >= 1 else "stale: the handoff is older than the last commit")
    return out


# ---------------------------------------------------------------- output

def emit(lines):
    text = scrub("\n".join(lines))[:CAP]
    try:
        sys.stdout.buffer.write((text + "\n").encode("utf-8", "replace"))
        sys.stdout.buffer.flush()
    except Exception:
        pass


def quote_prompts(prompts, head):
    return [head] + [f"  {i}. {p}" for i, p in enumerate(prompts, 1)] if prompts else []


def pre_compact(data, project, keys):
    lines = []
    custom = data.get("custom_instructions")
    if isinstance(custom, str) and custom.strip():
        lines.append(scrub(custom.strip())[:CUSTOM_CUT])
    lines.append("smartuse recall: write the summary so the next turn can check it against the real files.")
    if keys["sources"]:
        lines.append("Keep these source paths verbatim:")
        lines += ["  " + one_line(s, 300) for s in keys["sources"]]
    lines += quote_prompts(scan_safe(data)["prompts"], "Keep these owner prompts verbatim (oldest first):")
    lines.append('Mark anything you did not re-verify against a source as "from summary".')
    emit(lines)


def squeeze_time(squeezed_at):
    """The local HH:MM of the squeeze: the transcript's marker when it is from the last 10 minutes (an older one belongs to an earlier
    squeeze, the new marker is not written yet), else now."""
    now = datetime.datetime.now(datetime.timezone.utc)
    if squeezed_at is not None and abs((now - squeezed_at).total_seconds()) <= 600:
        return hhmm(squeezed_at)
    return hhmm(now)


def count_squeeze(sdir, keys):
    """recall.json: compactions + 1, last_at, last_unopened (the sources as written: none counts as opened after a squeeze)."""
    st = read_dict(sdir / "recall.json") or {}
    n = st.get("compactions")
    write_json(sdir / "recall.json", {"compactions": (n if isinstance(n, int) and not isinstance(n, bool) else 0) + 1,
                                      "last_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                                      "last_unopened": list(keys["sources"])})


def session_start(data, project, keys):
    src = data.get("source") if data.get("source") is not None else "startup"
    if src == "compact":
        s = scan_safe(data)
        lines = [f"smartuse recall: squeezed at {squeeze_time(s['squeezed_at'])}.", "The summary is not a source."]
        if keys["sources"]:
            lines.append("Sources (none counts as opened now; open each before any output):")
            lines += ["  " + one_line(x, 300) for x in keys["sources"]]
            lines += quote_prompts(s["prompts"], "Owner prompts, verbatim (oldest first):")
            lines += notes(keys)
        count_squeeze(state_dir(project), keys)
        emit(lines)
    elif src in ("startup", "clear", "resume"):
        if not (keys["sources"] or keys["handoff"]):
            return
        lines = [f"smartuse recall ({src}):"]
        if keys["handoff"]:
            lines += handoff_lines(project, keys["handoff"][0])
        if src == "resume" and scan_safe(data)["compacted"]:
            lines.append("resumed; the compacted part is a summary, not a source")
        if keys["sources"]:
            lines.append("Sources (open each before any output):")
            lines += ["  " + one_line(x, 300) for x in keys["sources"]]
            lines += notes(keys)
        emit(lines)


def main():
    try:
        data = stdin_json()
    except Exception:
        return
    if not isinstance(data, dict):
        return
    ev = data.get("hook_event_name")
    if ev not in ("PreCompact", "SessionStart"):
        return
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or native_path(data.get("cwd")) or os.getcwd())
    keys = adapter_keys(project)
    if ev == "PreCompact":
        pre_compact(data, project, keys)
    else:
        session_start(data, project, keys)


try:
    main()
except SystemExit:
    raise
except Exception:
    pass
