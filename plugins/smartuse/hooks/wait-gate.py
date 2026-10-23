#!/usr/bin/env python3
"""wait-gate.py — Stop hook: "if nothing will wake you, you are not waiting, you are stopped" (design: docs/notes/one-session-design.md, M2).

The incident: a manager session handed a step to a builder session, had stopped its own watcher earlier "to save tokens", and went
idle; the builder's "step done" message never arrived and the owner found out first. A session that hands work off and ends its turn
with nothing armed to wake it is stopped, and must say so. At Stop this hook reads the session transcript ONCE (no subprocess, no
network, 0 model tokens) and asks two questions.
1. Is a hand-off OPEN? In scope — the records after the last genuine human prompt — and not answered since:
     · a `mcp__claude-code-remote__send_message` call that did not fail (is_error: nothing was sent);
     · a `SendMessage` whose recipient_kind is not "agent" and whose recipient is not a background agent of this session (an agent
       hands its result back by itself; the control types such as shutdown_request are no hand-off either);
     · the final reply says it hands work over or promises a later report. A PATTERN MATCH on the prose (PHRASES; code is ignored;
       case-insensitive): "paste this / it / that / the following / the line / the prompt / the brief ... into / in ..." (not into a
       file, a console, a terminal or a shell, a chat or a reply, Slack, an issue or a PR: those tell the human what to do),
       "I'll / I will ping / notify / message / update you", "tell you" (not "tell you what / why / how"), "let you know",
       "check / come / report back". It catches the plain wordings, not every wording; the list is kept tight, a false block costs
       a turn.
   Answered = after it came a task notification with status "completed" (a watcher fired; not the echo of a task the session stopped
   itself, not a failed one such as watch.py's "no signal") or a message from another session or agent. Without this the designed
   flow would block itself: arm the watcher, hand off, wake on its notification, review.
2. Is a watcher ALIVE? Searched in the whole transcript: a Bash call that went to the background (run_in_background, or moved there at
   its timeout), a `Monitor`, a background `Agent` or `Workflow` — unless a later `TaskStop` names its task id or a task notification
   for its task id / tool-use id has a final status (a `<status>` that is not running; a Monitor "event" has none); a `send_later`
   whose fire_at is ahead; a `ScheduleWakeup` whose delay has not passed (`stop: true` ends them); a `CronCreate`, `create_trigger`, `subscribe_pr_activity` or `watch_url` unless a
   later `CronDelete`, `delete_trigger`, `unsubscribe_pr_activity` or `unwatch_url` removed it (a one-shot cron or trigger counts until
   its time). A `SendMessage` to a background agent that finished makes it alive again. ANY live task counts as the watcher: the gate
   cannot tell a watch.py from a test run. The Stop input's `background_tasks` / `session_crons` count too when they hold a live entry.
PASS (exit 0, nothing printed) when: no hand-off is open (wait.json is removed) · a watcher is alive (wait.json "watching") · the
final reply has a line starting `STOPPED:` (`**` or `>` before it is fine; "STOPPED: nothing will wake me; <who> must.") ("stopped") ·
the adapter frontmatter says `wait_gate: off` (nothing is read or written; the adapter is human-only: file-guard, bash-guard) · the gate
already blocked once for this scope. Otherwise it BLOCKS ONCE with the Stop-hook JSON until-done.py prints, a reason of at most 6
lines: what was handed off and when; the watcher that was stopped or finished, if any; then the fix — run in the background
`bash "<plugin>/hooks/py.sh" "<plugin>/hooks/watch.py" --git origin <branch> --path <result file> --since <the commit you handed off
at>` (<plugin> absolute, from this file's location; <branch> from .git/HEAD when it is a plain branch name, else a placeholder), or
schedule a check-in, or end the reply with STOPPED. "Once" = per scope: wait-block.json (the last 20) names session id + the uuid of
the last human prompt + the last answer; the second Stop in it passes (never a trap), a hand-off after a later answer is gated again.
stop_hook_active plays no part, as in until-done.py: it is true on every Stop after a block, whoever blocked.
State dir: ~/.claude/smartuse/projects/<key>/ (shared with heartbeat.py, ledger.py, until-done.py), <key> the repo's full resolved path
with every character outside [A-Za-z0-9._-] replaced by "-" and a leading "-" dropped (ledger.py's project_key, copied, tested equal).
wait.json = {"at", "state": "watching" | "stopped" | "blocked", "what", "since", "watcher": {kind, id, armed, state} | null,
"session_id", "scope"}, the outcome of the last Stop with an open hand-off; heartbeat.py --line shows it ("STOPPED · handed off 20:41
(builder) — nothing will wake this session") while it is newer than the last UserPromptSubmit. The hand-off a Stop found stands until
something answers it: a later Stop in the same scope whose reply does not repeat it (it says STOPPED:, it armed a watcher, it just
ends) carries it over, so "STOPPED:" after a block still reads STOPPED on the status line, not "waiting on you".
Facts, checked on real Claude Code 2.1.308 transcripts (shapes only were read; every test fixture is synthetic):
  · assistant records hold one block each: {type: "text", text} or {type: "tool_use", id, name, input, caller}; a user record holds
    `tool_result` blocks {tool_use_id, content, is_error?} and a top-level toolUseResult (backgroundTaskId, agentId, taskId). Result
    texts: "Command running in background with ID: <id>." / "... was moved to the background (ID: <id>)", "Async agent launched
    successfully. ... agentId: <id>", "Monitor started (task <id>, expires in 30m ...)", "Workflow launched in background. Task ID:
    <id>", send_message {"status":"delivered"}, send_later {"fire_at":"<ISO>","now":..,"trigger_id":..}. TaskStop {task_id};
    SendMessage {to, recipient_kind, type, summary, message}. ScheduleWakeup {delaySeconds 60..3600, stop} -> {scheduledFor: epoch ms}
    and CronCreate -> {id, recurring, nextFireAt} / CronDelete {id}: from the binary's schemas, no real call was available.
  · a task notification is `<task-notification>` with <task-id>, <tool-use-id>, <status> (completed | failed), as a `queue-operation`
    enqueue record (every one), a `user` record (turnOrigin "task_notification", origin.kind "task-notification") when it started a
    turn, an `attachment` queued_command when it was absorbed mid-turn. The one real TaskStop in the data left no notification for its
    task: the stop is the end signal (an echo of it, should a version send one, is no answer).
  · a genuine human prompt is a `user` record with plain text and no isMeta, turnOrigin "human" (origin.kind "human") or "sdk" (-p).
    Not human: tool results, isMeta records (skill text, "Stop hook feedback: ...", reminders), isCompactSummary, turnOrigin "peer" /
    "task_notification" / "system" or whatever a cron or a wake-up injects (origin.kind "peer": another session, a subagent's
    hand-back), <command-name> / <local-command-*> echoes, "[Request interrupted". A message the owner typed mid-turn is an
    attachment queued_command (origin.kind "human"); a slash command (<command-message>) is a prompt. A turnOrigin / origin.kind
    other than human and sdk is not: a scheduled check-in that finds nothing must not close the hand-off it was set for.
  · the Stop input: session_id, transcript_path, cwd, prompt_id, hook_event_name, stop_hook_active, last_assistant_message,
    background_tasks [{id, type, status, description, command}], session_crons. The final assistant message was already in the
    transcript when Stop fired (two headless probes, re-read 0.5 s and 1.5 s later: unchanged); the gate prefers last_assistant_message
    when the input has it and reads the transcript's last assistant text when it does not.
Windows: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, never inside the event JSON, so
transcript_path / cwd go through native_path() ("/c/Users/x" -> "C:/Users/x"); stdin is read as bytes and decoded as UTF-8 (Windows
Python would decode a pipe in the ANSI code page and raise on the first non-ASCII byte, failing the gate open); the transcript is read
as bytes and decoded per line; the block is JSON with ASCII escapes (json.dumps), so stdout needs no re-encoding. Python 3.9 floor.
Any error — no stdin, no transcript, a record it cannot read, the 6 s pass budget — exits 0 with no output: a gate must never trap the session.
"""
import json, os, re, sys, time, pathlib, datetime

HOME = pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~"))   # HOME first: on Windows expanduser("~") reads USERPROFILE and ignores HOME (the tests and users who set HOME need it)
RC = "mcp__claude-code-remote__"
BUDGET_S = 6.0                 # the hook's timeout is 10 s: one pass over a very large transcript gives up after this and lets the stop through
KEEP_SCOPES = 20               # block markers kept in wait-block.json
LIVE = {"running", "pending", "started", "starting", "in_progress", "in-progress", "active", "queued"}   # a task <status> / a background_tasks status that is not final
HUMAN = {"human", "sdk"}   # the turnOrigin / origin.kind values of a prompt a person (or the SDK caller) sent; anything else was injected by the harness: a task notification, a peer, a wake-up, a cron
INJECTED = ("<task-notification>", "<system-reminder>", "<local-command-", "<command-name>", "Stop hook feedback:",
            "Another Claude session sent a message:", "[Request interrupted",
            "Caveat: The messages below were generated by the user while running local commands")   # text that is never a human prompt, whatever the record's fields say (older versions)
TOOLS = {"Bash", "Monitor", "Agent", "Workflow", "ScheduleWakeup", "CronCreate", "CronDelete", "TaskStop", "SendMessage"}
RC_TOOLS = {RC + n for n in ("send_message", "send_later", "create_trigger", "delete_trigger", "subscribe_pr_activity",
                             "unsubscribe_pr_activity", "watch_url", "unwatch_url")}
LABEL = {"bash": "background Bash", "monitor": "Monitor", "agent": "background agent", "workflow": "background workflow",
         "send_later": "send_later", "wakeup": "ScheduleWakeup", "cron": "cron job", "trigger": "scheduled task",
         "pr": "PR subscription", "url": "webhook", "task": "background task"}
VERB = {"stopped": "was stopped", "finished": "has finished", "fired": "has already fired"}

# The hand-off / promise phrases, matched against the final reply's prose (code stripped). A PATTERN MATCH, not understanding.
_DET = r"(?:the|your|a|an|my|another|that|this)"
# What "paste this into ..." can name when it only tells the human what to do and no session is involved: a tool or a place of the human's
# own (a terminal, a browser console, Slack, a PR description, settings.json, ~/.zshrc, src/app.py). The word must come right after "into / in"
# and an optional the / your / a / an / my, so "another terminal" and "the builder terminal" stay sessions; a word and the full stop that ends
# the sentence ("... into the builder.") is no file name.
_NOT_A_SESSION = (r"(?:(?:browser|console|devtools|shell|terminal|cmd|powershell|command\s+(?:line|prompt)|editor|ide|files?|config|settings|env|chat|conversation|reply|message|response|answer"
                  r"|slack|jira|notion|e-?mail|excel|spreadsheet|sheets?|docs?|document|readme|pr|issue|ticket|comment|description|github)\b"
                  r"|~[\w./~-]*|[\w.-]*/[\w./-]*|[\w-]*\.\w[\w./-]*)")
_I = r"\bI(?:['’]ll|\s+will)\s+"
PHRASES = [
    re.compile(r"\bpaste\s+(?:this|it|that|the\s+following|the\s+line|the\s+prompt|the\s+brief)\b(?:\s+[\w'-]+){0,6}?\s+(?:into|in)\b"
               r"(?!\s+(?:(?:the|your|a|an|my)\s+)?" + _NOT_A_SESSION + r")"
               r"(?:\s+" + _DET + r")?(?:\s+[\w-]+){0,2}", re.I),
    re.compile(_I + r"(?:(?:ping|notify|message|update)\s+you\b|tell\s+you\b(?!\s+(?:what|why|how|about|that)\b))", re.I),   # "I'll tell you what I found" is an idiom, not a promise
    re.compile(_I + r"let\s+you\s+know\b", re.I),
    re.compile(_I + r"(?:check|come|report)\s+back\b", re.I),
]
NEGATED = re.compile(r"\b(?:don['’]?t|do\s+not|never|no\s+need\s+to)\s+$", re.I)   # "don't paste the prompt into the builder" hands nothing over
STOPPED = re.compile(r"^[ \t\r\u00a0>*_`]*STOPPED(?:\*\*|__)?[ \t]*:", re.M)   # a line that starts "STOPPED:" (markdown bold / quote marks before it are fine); no class crosses a line end, so the search is linear


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
    ledger.py and until-done.py). Made (mkdir -p) only when the gate writes there; there is no fallback to the 0.3.0 folder-name dir."""
    return HOME / ".claude" / "smartuse" / "projects" / project_key(project)


def stdin_json():
    """The event JSON from stdin, read as bytes and decoded as UTF-8: Windows Python decodes a piped stdin in the ANSI code
    page, where one non-ASCII byte raises and the gate would fail open; a bad byte becomes U+FFFD instead."""
    raw = sys.stdin.buffer.read() if hasattr(sys.stdin, "buffer") else sys.stdin.read().encode("utf-8", "replace")
    return json.loads(raw.decode("utf-8", "replace"))


def write_json(path, obj):
    """Atomic: tmp file + os.replace. On Windows the replace raises PermissionError while another hook or the status line has
    the file open: retry 5 times, 20 ms apart; still failing -> drop the tmp file and give up (last writer wins). Never raises."""
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
    """An ISO-8601 stamp ("2026-10-22T20:41:03.123Z", with or without a zone) -> an aware UTC datetime, else None. Python 3.9's
    fromisoformat takes neither "Z" nor a fraction that is not 3 or 6 digits: the first is replaced, the second falls back to the date part."""
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


def epoch(v):
    """A stamp -> epoch seconds: an ISO string, or a number (milliseconds when it is that large); None when it is neither."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return v / 1000.0 if v > 1e11 else float(v)
    t = parse_ts(v) if isinstance(v, str) else None
    return t.timestamp() if t else None


def iso(sec=None):
    return datetime.datetime.fromtimestamp(time.time() if sec is None else sec, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def hhmm(v):
    """The local wall-clock time HH:MM of a stamp (the owner's clock, not UTC); "" when it cannot be read."""
    t = parse_ts(v) if isinstance(v, str) else None
    if t is None:
        return ""
    try:
        return t.astimezone().strftime("%H:%M")
    except Exception:
        return t.strftime("%H:%M")


def clean(text, n=60):
    """One printable line out of text that came from the transcript (a recipient name, a message): control and bidi characters
    become spaces, runs of spaces collapse, cut at n characters. The line is read by a model: kept short and plain."""
    s = re.sub(r"[\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2066-\u2069]", " ", str(text))
    s = " ".join(s.split())
    return s if len(s) <= n else s[:n - 1].rstrip() + "…"


def gate_off(project):
    """`wait_gate: off` in the YAML frontmatter of the human-authored adapter .claude/smartuse.local.md (off / false / no / 0 / disabled)."""
    try:
        text = (project / ".claude" / "smartuse.local.md").read_text(encoding="utf-8-sig")
        fm = re.match(r"\s*---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|$)", text, re.S)
        v = re.search(r"^wait_gate:[ \t]*(.*?)[ \t]*$", fm.group(1), re.M) if fm else None
        return bool(v) and re.sub(r"\s+#.*$", "", v.group(1)).strip().strip("'\"").lower() in ("off", "false", "no", "0", "disabled")
    except Exception:
        return False


def git_branch(project):
    """The checked-out branch, read straight from .git/HEAD (no subprocess; a worktree's .git is a file naming its git dir): only
    a plain branch name comes back — anything with a character a shell would act on, a detached HEAD or an unreadable repo gives "".
    The name is pasted into a command the model runs, so it is never taken as it is."""
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
            m = re.match(r"ref:\s*refs/heads/(\S+)\s*$", (g / "HEAD").read_text(encoding="utf-8").strip()) if g else None
            b = m.group(1) if m else ""
            return b if re.fullmatch(r"[A-Za-z0-9._/-]+", b) and not b.startswith(("-", "/")) and ".." not in b else ""
    except Exception:
        pass
    return ""


# ---------------------------------------------------------------- the transcript: one pass

def blocks(r):
    m = r.get("message")
    c = m.get("content") if isinstance(m, dict) else None
    return [b for b in c if isinstance(b, dict)] if isinstance(c, list) else []


def text_of(content):
    """A tool_result's content (a string, or a list of text blocks) as one string."""
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


def slim(d, n=200):
    """The small scalar fields of a dict (a tool input, a toolUseResult): the rest can be megabytes of output."""
    return {k: (v[:n] if isinstance(v, str) else v) for k, v in d.items()
            if isinstance(v, (bool, int, float)) or isinstance(v, str)} if isinstance(d, dict) else {}


def note(i, ts, text):
    """A `<task-notification>` -> {i, ts, task, call, status, final}. final = it carries a status that is not running."""
    def tag(name):
        m = re.search(r"<" + name + r">\s*([^<\s]+)\s*</" + name + r">", text)
        return m.group(1) if m else None
    st = (tag("status") or "").lower() or None
    return {"i": i, "ts": ts, "task": tag("task-id"), "call": tag("tool-use-id"), "status": st, "final": bool(st) and st not in LIVE}


def is_human(r, text, kind, turn):
    """A genuine human prompt: a user record with real text that was not injected — see the docstring for the fields."""
    if r.get("isMeta") or r.get("isCompactSummary") or r.get("isVisibleInTranscriptOnly") or r.get("promptSource") == "system":
        return False
    if (kind is not None and kind not in HUMAN) or (turn is not None and turn not in HUMAN):
        return False
    t = text.lstrip()
    return bool(t) and not t.startswith(INJECTED)


def scan(path):
    """One pass over the transcript -> {"start": index of the last genuine human prompt (-1: none), "scope": its uuid, "calls": the
    tool calls this gate cares about (index, id, name, timestamp, slim input), "res": their results {id: {err, text, tur}},
    "notes": task notifications, "peers": indexes of messages from another session or agent, "texts": the assistant's text blocks
    after the last user record (the final reply), "reply_ts"}. Records of a subagent (isSidechain) are not this session's.
    Raises on an unreadable file or when the pass takes longer than BUDGET_S."""
    f = {"start": -1, "scope": None, "calls": [], "res": {}, "notes": [], "peers": [], "texts": [], "reply_ts": None}
    want, texts = set(), []
    deadline = time.monotonic() + BUDGET_S
    with open(path, "rb") as fh:
        for i, raw in enumerate(fh):
            if not (i & 255) and time.monotonic() > deadline:
                raise TimeoutError("transcript pass over budget")
            try:
                r = json.loads(raw.decode("utf-8", "replace"))
            except Exception:
                continue
            if not isinstance(r, dict) or r.get("isSidechain"):
                continue
            t, ts = r.get("type"), r.get("timestamp")
            if t == "assistant":
                for b in blocks(r):
                    if b.get("type") == "text" and isinstance(b.get("text"), str):
                        texts.append(b["text"])
                        f["reply_ts"] = ts
                    elif b.get("type") == "tool_use" and (b.get("name") in TOOLS or b.get("name") in RC_TOOLS):
                        f["calls"].append({"i": i, "id": b.get("id"), "name": b["name"], "ts": ts, "input": slim(b.get("input"))})
                        want.add(b.get("id"))
            elif t == "user":
                texts = []                                    # a user record ends the assistant's message
                results = [b for b in blocks(r) if b.get("type") == "tool_result"]
                for b in results:
                    if b.get("tool_use_id") in want:
                        f["res"][b["tool_use_id"]] = {"err": bool(b.get("is_error")), "text": text_of(b.get("content"))[:1500],
                                                      "tur": slim(r.get("toolUseResult"))}
                if results:
                    continue
                m = r.get("message")
                text = user_text(m.get("content") if isinstance(m, dict) else None)
                o = r.get("origin")
                kind, turn = (o.get("kind") if isinstance(o, dict) else None), r.get("turnOrigin")
                if "<task-notification>" in text[:300] and (text.lstrip().startswith("<task-notification>") or turn == "task_notification" or kind == "task-notification"):
                    f["notes"].append(note(i, ts, text))
                elif turn == "peer" or kind == "peer" or text.lstrip().startswith("Another Claude session sent a message:"):
                    f["peers"].append(i)
                elif is_human(r, text, kind, turn):
                    f["start"], f["scope"] = i, r.get("uuid") or f"line{i}"
            elif t == "queue-operation":
                c = r.get("content")
                if r.get("operation") == "enqueue" and isinstance(c, str) and "<task-notification>" in c[:300]:
                    f["notes"].append(note(i, ts, c))
            elif t == "attachment":
                a = r.get("attachment")
                if isinstance(a, dict) and a.get("type") == "queued_command":   # a message absorbed into a running turn: no user record of its own
                    p = a.get("prompt")
                    p = p if isinstance(p, str) else text_of(p)
                    o = a.get("origin")
                    kind = o.get("kind") if isinstance(o, dict) else None
                    if a.get("commandMode") == "task-notification" or p.lstrip().startswith("<task-notification>"):
                        f["notes"].append(note(i, ts, p))
                    elif kind == "peer":
                        f["peers"].append(i)
                        texts = []
                    elif kind == "human" and p.strip():
                        f["start"], f["scope"] = i, r.get("uuid") or f"line{i}"
                        texts = []
    f["texts"] = texts
    return f


# ---------------------------------------------------------------- watchers and hand-offs

def first(pattern, text):
    m = re.search(pattern, text or "")
    return m.group(1) if m else None


def jload(text):
    try:
        d = json.loads(text)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def replay(f, now):
    """Replay the calls and task notifications in transcript order -> (watchers, answered_at, agents). A watcher is {kind, id, call, i,
    at, due (epoch the timer fires, or None), end (None = alive | stopped | finished | fired), end_at}. answered_at is the
    index of the last record that answers an earlier hand-off: a task notification with status "completed" that the session did not
    cause with TaskStop, or a message from another session or agent (-1: none). agents = the ids and names of the background agents
    this session started (a message to one of them is no hand-off: its result comes back by itself)."""
    ev = sorted([(c["i"], 0, c) for c in f["calls"]] + [(n["i"], 1, n) for n in f["notes"]], key=lambda e: (e[0], e[1]))
    ws, ids, calls = [], {}, {}
    answered = max(f["peers"]) if f["peers"] else -1

    def add(kind, c, ident=None, key=None, due=None):
        w = {"kind": kind, "id": ident, "call": c["id"], "i": c["i"], "at": c["ts"], "due": due, "end": None, "end_at": None}
        ws.append(w)
        calls[c["id"]] = w
        if key or ident:
            ids[key or ident] = w
        return w

    def end(w, how, at):
        if w and w["end"] is None:
            w["end"], w["end_at"] = how, at

    for i, k, e in ev:
        if k == 1:                                            # a task notification
            w = calls.get(e["call"]) or ids.get(e["task"])
            if e["final"] and (w is None or w["end"] is None):
                if e["status"] == "completed":
                    answered = max(answered, i)               # a watcher that ended on its own and well; the echo of a task the session stopped is not an answer
                end(w, "finished", e["ts"])
            continue
        name, inp = e["name"], e["input"]
        res = f["res"].get(e["id"]) or {}
        if res.get("err"):
            continue                                          # a call that failed started nothing and stopped nothing
        text, tur, armed = res.get("text") or "", res.get("tur") or {}, epoch(e["ts"])
        if name == "Bash":
            tid = tur.get("backgroundTaskId") or first(r"(?:background with ID:|moved to the background \(ID:)\s*([A-Za-z0-9_-]+)", text)
            if tid or inp.get("run_in_background"):
                add("bash", e, tid)
        elif name == "Monitor":                               # armed until its end notice: the harness sends one at expiry ("you get one notice at expiry")
            add("monitor", e, first(r"Monitor started \(task\s+([A-Za-z0-9_-]+)", text) or tur.get("taskId"))
        elif name == "Agent":
            if inp.get("run_in_background") or tur.get("isAsync") or text.startswith("Async agent launched"):
                w = add("agent", e, tur.get("agentId") or first(r"\bagentId:\s*([A-Za-z0-9_-]+)", text))
                if isinstance(inp.get("name"), str) and inp["name"]:
                    ids[inp["name"]] = w                      # addressed by name later (agent teams): the same agent
        elif name == "Workflow":
            tid = tur.get("taskId") or first(r"Task ID:\s*([A-Za-z0-9_-]+)", text)
            if tid or text.startswith("Workflow launched in background"):
                add("workflow", e, tid)
        elif name == "TaskStop":
            end(ids.get(inp.get("task_id") or inp.get("shell_id")), "stopped", e["ts"])
        elif name == "SendMessage":                           # more work for a background agent that finished: it runs again and will notify again
            w = ids.get(inp.get("to") or inp.get("recipient"))
            if w and w["kind"] == "agent" and w["end"] == "finished":
                w["end"], w["end_at"], w["at"], w["i"] = None, None, e["ts"], e["i"]
        elif name == RC + "send_later":
            d = jload(text)
            delay = inp.get("delay_minutes")
            due = epoch(d.get("fire_at")) or epoch(inp.get("at")) or (armed + delay * 60 if armed is not None and isinstance(delay, (int, float)) else None)
            add("send_later", e, due=due)
        elif name == "ScheduleWakeup":
            if inp.get("stop"):
                for w in ws:
                    if w["kind"] == "wakeup":
                        end(w, "stopped", e["ts"])
            else:
                s = inp.get("delaySeconds")
                due = epoch(jload(text).get("scheduledFor")) or (armed + min(3600, max(60, s)) if armed is not None and isinstance(s, (int, float)) else None)
                add("wakeup", e, due=due)
        elif name == "CronCreate":
            d = jload(text)
            cid = d.get("id") or tur.get("id") or first(r'"id"\s*:\s*"([^"]+)"', text)
            rec = d["recurring"] if "recurring" in d else inp.get("recurring", True)
            add("cron", e, cid, ("cron", cid) if cid else None, due=epoch(d.get("nextFireAt")) if rec is False else None)
        elif name == "CronDelete":
            cid = inp.get("id")
            end(ids.get(("cron", cid)) or next((w for w in reversed(ws) if w["kind"] == "cron" and w["id"] is None and w["end"] is None), None), "stopped", e["ts"])
        elif name == RC + "create_trigger":
            tid = first(r"\b(trig_[A-Za-z0-9]+)", text) or tur.get("id")
            add("trigger", e, tid, ("trigger", tid) if tid else None, due=epoch(inp.get("run_once_at")))
        elif name == RC + "delete_trigger":
            end(ids.get(("trigger", inp.get("trigger_id"))) or next((w for w in reversed(ws) if w["kind"] == "trigger" and w["id"] is None and w["end"] is None), None), "stopped", e["ts"])
        elif name == RC + "subscribe_pr_activity":
            key = ("pr", str(inp.get("owner")).lower(), str(inp.get("repo")).lower(), str(inp.get("pullNumber")))
            end(ids.get(key), "stopped", e["ts"])             # subscribing again replaces the earlier subscription
            if "will not receive events" not in text:         # another session already holds the PR: the call worked, nothing will reach this one
                add("pr", e, None, key)
        elif name == RC + "unsubscribe_pr_activity":
            end(ids.get(("pr", str(inp.get("owner")).lower(), str(inp.get("repo")).lower(), str(inp.get("pullNumber")))), "stopped", e["ts"])
        elif name == RC + "watch_url":
            tid = first(r'trigger_id"?\s*[:=]\s*"?([A-Za-z0-9_-]+)', text) or tur.get("trigger_id")
            add("url", e, tid, ("url", tid) if tid else None)
        elif name == RC + "unwatch_url":
            w = ids.get(("url", inp.get("trigger_id")))
            for x in ([w] if w else [x for x in ws if x["kind"] == "url"]):
                end(x, "stopped", e["ts"])
    for w in ws:
        if w["end"] is None and w["due"] is not None and w["due"] <= now:
            w["end"], w["end_at"] = "fired", iso(w["due"])
    return ws, answered, {k for k, w in ids.items() if w["kind"] == "agent"}


def live_in_input(data):
    """A live task or cron the Stop input itself lists (2.1.308: background_tasks [{id, type, status, ...}], session_crons), as a watcher
    record; None when both lists are missing, empty, or hold only finished entries. An empty list is not evidence that nothing is armed."""
    for key, kind in (("background_tasks", "task"), ("session_crons", "cron")):
        v = data.get(key)
        for x in v if isinstance(v, list) else []:
            if not isinstance(x, dict) or str(x.get("status") or "running").lower() in LIVE:
                return {"kind": kind, "id": x.get("id") if isinstance(x, dict) else None, "at": None, "end": None}
    return None


def handoffs(f, answered, agents, reply):
    """The open hand-offs, oldest first: [{i, ts, what (short: the recipient or the quoted phrase), how (a sentence part)}]. The
    reply's own phrase comes last (index = infinity: nothing can have answered it)."""
    out = []
    for c in f["calls"]:
        if c["i"] <= f["start"] or c["i"] < answered:
            continue
        inp, res = c["input"], f["res"].get(c["id"]) or {}
        if res.get("err"):
            continue                                          # nothing was sent
        if c["name"] == RC + "send_message":
            who = clean(inp.get("session_id") or "another session", 21)
            out.append({"i": c["i"], "ts": c["ts"] or iso(), "what": who, "how": "send_message to " + who})
        elif (c["name"] == "SendMessage" and inp.get("recipient_kind") and inp.get("recipient_kind") != "agent" and inp.get("type") in (None, "message")
              and (inp.get("to") or inp.get("recipient")) not in agents):
            who = clean(inp.get("to") or inp.get("recipient") or "another session", 40)
            out.append({"i": c["i"], "ts": c["ts"] or iso(), "what": who, "how": "SendMessage to " + who})
    prose = re.sub(r"`[^`\n]*`", " ", re.sub(r"```.*?```", " ", reply[-200000:], flags=re.S))   # a promise in prose counts, one inside code does not
    m = next((m for p in PHRASES for m in p.finditer(prose) if not NEGATED.search(prose[max(0, m.start() - 30):m.start()])), None)
    if m:
        q = clean(m.group(0), 60)
        out.append({"i": float("inf"), "ts": f["reply_ts"] or iso(), "what": '"' + q + '"', "how": 'your reply says "' + q + '"'})
    return out


# ---------------------------------------------------------------- verdict

def watcher_of(w):
    """The wait.json form of a watcher: {kind, id, armed, state}."""
    return None if w is None else {"kind": w["kind"], "id": w.get("id"), "armed": w.get("at"), "state": w["end"] or "alive"}


def put_wait(sdir, state, hand, w, sid, scope):
    write_json(sdir / "wait.json", {"at": iso(), "state": state, "what": hand["what"], "since": hand["ts"] or iso(), "watcher": watcher_of(w),
                                    "session_id": sid, "scope": scope})


def drop_wait(sdir):
    try:
        (sdir / "wait.json").unlink()
    except Exception:
        pass


def reason_text(hand, dead, project):
    """The block reason: 6 lines at most. <plugin> is this file's own plugin dir (absolute, forward slashes, escaped for double quotes)."""
    plug = re.sub(r'(["$`\\])', r"\\\1", pathlib.Path(__file__).resolve().parent.parent.as_posix())
    cmd = (f'bash "{plug}/hooks/py.sh" "{plug}/hooks/watch.py" --git origin {git_branch(project) or "<branch>"} '
           "--path <result file> --since <the commit you handed off at>")
    more = f" (+{hand['more']} earlier)" if hand.get("more") else ""
    lines = [f"wait gate: you handed off at {hhmm(hand['ts']) or 'an earlier time'} ({hand['how']}){more} and nothing will wake you."]
    if dead:
        lines.append(f"No watcher is armed: the watcher started at {hhmm(dead['at']) or 'an earlier time'} {VERB.get(dead['end'], 'has ended')} ({LABEL.get(dead['kind'], 'watcher')}).")
    else:
        lines.append("No watcher is armed: none was ever started in this session.")
    lines += ["Before you end the turn, do ONE of these:",
              " 1. arm a watcher, run in the background: " + cmd,
              " 2. or schedule a check-in (send_later, ScheduleWakeup or CronCreate)",
              " 3. or end your reply with: STOPPED: nothing will wake me; <who> must."]
    return "\n".join(lines)


def allow():
    sys.exit(0)


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason[:1800]}))
    sys.exit(0)


def main():
    try:
        data = stdin_json()
    except Exception:
        allow()
    if not isinstance(data, dict) or data.get("hook_event_name") not in (None, "Stop"):
        allow()
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or native_path(data.get("cwd")) or os.getcwd())
    if gate_off(project):
        allow()
    tp = native_path(data.get("transcript_path") or "")
    if not tp or not os.path.isfile(tp):
        allow()
    f = scan(tp)
    ws, answered, agents = replay(f, time.time())
    given = data.get("last_assistant_message")
    reply = given if isinstance(given, str) and given.strip() else "\n".join(f["texts"])
    hands = handoffs(f, answered, agents, reply)
    sdir, sid = state_dir(project), str(data.get("session_id") or "")
    scope = f"{sid}:{f['scope'] or 'start'}@{answered}"          # one block per human prompt and per wake-up that answered a hand-off: the second Stop of either passes
    alive = [w for w in ws if w["end"] is None]
    live = max(alive, key=lambda w: w["i"]) if alive else live_in_input(data)
    dead = max((w for w in ws if w["end"]), key=lambda w: w["i"], default=None)
    if not hands:
        prev = read_dict(sdir / "wait.json") or {}
        if prev.get("scope") != scope or prev.get("state") not in ("watching", "stopped", "blocked") or not prev.get("what"):
            drop_wait(sdir)
            allow()
        # the last Stop in this scope found a hand-off, nobody has answered it, and this reply only does not repeat it (it says STOPPED:, or
        # it armed a watcher, or it just ends): the hand-off stands, and the status line must go on saying so
        put_wait(sdir, "watching" if live else "stopped", {"what": prev["what"], "ts": prev.get("since")}, live or dead, sid, scope)
        allow()
    hand = dict(hands[-1], more=len(hands) - 1)
    if live:
        put_wait(sdir, "watching", hand, live, sid, scope)
        allow()
    if STOPPED.search(reply):
        put_wait(sdir, "stopped", hand, dead, sid, scope)
        allow()
    marks = read_dict(sdir / "wait-block.json") or {}
    scopes = marks.get("scopes") if isinstance(marks.get("scopes"), dict) else {}
    if scope in scopes:
        put_wait(sdir, "stopped", hand, dead, sid, scope)    # blocked once already: the session chose to stop, and now it says so on the status line
        allow()
    scopes[scope] = iso()
    write_json(sdir / "wait-block.json", {"scopes": dict(sorted(scopes.items(), key=lambda kv: str(kv[1]))[-KEEP_SCOPES:])})
    put_wait(sdir, "blocked", hand, dead, sid, scope)
    block(reason_text(hand, dead, project))


try:
    main()
except SystemExit:
    raise
except Exception:
    allow()
