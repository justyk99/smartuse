#!/usr/bin/env python3
# bash-guard.py — PreToolUse guard for Bash (smartuse). Deterministic: runs even in bypassPermissions.
# Why: bypass mode skips every "ask"; only deny rules and hooks still fire. This file is the small, readable list of
# things Claude must never run on this machine, with the reason printed back to Claude so it picks a safe alternative.
# Heredoc bodies (cat > file <<EOF …, python3 - <<EOF …) are DATA and are ignored, and so is a heredoc fed to a shell SCRIPT
# (bash "/p/py.sh" "/p/ledger.py" --put routing.json <<'JSON' — the script's input). A heredoc a shell reads as COMMANDS is
# still checked: bash <<EOF, bash -s / -c, cat <<EOF | sh, bash /dev/stdin, source /dev/stdin, eval. The skills' state writes
# pass their JSON as one single-quoted argument instead (Claude Code refuses a JSON heredoc in default mode): in exactly the
# shape bash "<…>/py.sh" "<…>/ledger.py" --put|--unit|--run <quoted or plain words>, those quoted words are data too.
# stdin is read as bytes and decoded as UTF-8 here, not by Python's text layer: on Windows a piped stdin is decoded in the
# ANSI code page, where a non-ASCII byte makes json.load raise — and a guard that raises fails OPEN.
# Fresh-source gate (0.6.0, docs/notes/recall-design.md): after a long session is compacted, the model holds a summary, not the
# job's files. When the human-only adapter .claude/smartuse.local.md lists `sources:` and a command matches `publish:` (or a tool
# matches `publish_tools:`), the call is denied until each source has a Read in this session after the last compaction; the reason
# names the unopened files. Detection errors (bad input, no adapter, no sources, no publish match) allow, as every check here does;
# once a publish matched, a failure to verify (no transcript, unreadable, over budget) denies. The adapter is only ever read.
# Test: bash hooks/tests/run.sh and fresh-gate-test.sh   Rollback: remove the PreToolUse entries in ~/.claude/settings.json
import datetime, fnmatch, glob, json, os, re, sys, time

BUDGET_S = 3.0       # wall time the transcript pass may take before the gate gives up (and denies a matched publish)
MAX_SOURCES = 200    # files one gate check will expand the sources to
MAX_NAMES = 10       # unopened files named in a reason

RULES = [
    (r"(curl|wget)\b[^|]*\|\s*(sudo\s+)?(bash|sh|zsh|dash|python3?|node|perl)\b",
     "pipe-to-shell (download then execute) — save the file, read it, then run it on purpose"),
    (r"\b(bash|sh|zsh|dash|ksh|eval|source)\b[^;&|]*?(\$\(|<\()\s*(curl|wget)\b",
     "download-then-execute via $(curl …) or <(curl …) — save the file, read it, then run it on purpose"),
    (r"(?<![\w.-])sudo\s",
     "sudo — run it yourself with `! sudo …`"),
    (r"\brm\s+(-[A-Za-z]*r[A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*r|-r\s+-f|-f\s+-r)\s+(/|~|\$HOME|\*|\.)(\s|$|/\*)",
     "rm -rf of / ~ . or * — delete named paths only"),
    (r"\bchmod\s+(-R\s+)?(777|a\+rwx|o\+w)\b",
     "world-writable chmod"),
    # key and credential files by NAME (any directory, either slash): a reader/copier command word, then the file in the same segment
    (r"\b(cat|less|more|head|tail|sed|awk|grep|strings|base64|xxd|cp|scp|rsync|curl|python3?|node|tee|jq|find|type)\b[^;&|]*"
     r"(\.claude\.json|db-creds\.json|\.jira_env|\bid_(rsa|ed25519|ecdsa|dsa|\*)(?!\.pub)|\.ssh[\\/]id_[a-z0-9_]+(\s|[\"']|$)"
     r"|\.ssh[\\/]?(\*|\s|[\"']|$)|\.ssh[\\/]config|gh[\\/]hosts\.yml|\.git-credentials|\.netrc|recovery-codes|[\\/]secrets[\\/]"
     r"|\.claude[\\/]\.credentials\.json|\.aws[\\/]credentials|\.npmrc(?![\w.-])|\.pypirc(?![\w.-])|\.kube[\\/]config|\.docker[\\/]config\.json)",
     "credential file — its contents would land in the transcript on disk; use `claude mcp list` or env vars instead"),
    # anchored with ^: rules are searched with re.I | re.S, so `.` crosses newlines and one try at position 0 sees the whole text.
    # Unanchored, every position rescanned the rest: quadratic in the command's length.
    (r"^(?=.*\b(sqlcmd|osql|tsql|sqlq|spapply|mssql)\b)(?=.*\b(DROP\s+(TABLE|DATABASE|PROC|PROCEDURE|LOGIN|USER)|TRUNCATE\s+TABLE|DELETE\s+FROM)\b)",
     "destructive SQL through the shell — SQL in chat, a human runs it"),
    # git [options] push … --force / -f (also bundled: -fu) / --force-with-lease / --mirror / +ref
    (r"\bgit\b(\s+-\S+(\s+[^-\s]\S*)?)*\s+push\b[^;&|]*(\s--force\b|\s-[a-z]*f[a-z]*\b|--force-with-lease|--mirror|\s[\"']?\+\S)",
     "force push"),
    (r"(>|\btee\b|\bsed\s+-i|\bcp\b|\bmv\b|\bpython3?\b|\bpy\.sh\b)[^;&|]*(smartuse\.local\.md|trusted-checks\.json|\.claude[. ]*[/\\]smartuse[. ]*[/\\]interpreter(?![\w-]|\.\w))",   # Windows drops a trailing dot or space of every part and reads x::$DATA as x: all are the file, interpreter.md is not
     "human-only file (it decides what the until-done gate may run, or which Python runs the hooks) — ask the user to edit it"),
    (r"(^|[;&|]\s*)(unbuffer|expect|script)\s",
     "faking an interactive terminal (script / unbuffer / expect) is not allowed"),
    (r"until-done\.py\s+--trust",
     "pinning a check script is a human-only action — the user runs it in their own terminal"),
    (r"\bsvn\s+(revert|resolve\s+--accept\s+theirs-full)\b",
     "svn revert / theirs-full — colleagues' uncommitted work would be lost"),
]

# <<EOF … EOF  /  <<'EOF' … EOF  /  <<-EOF … EOF   (body = group 3)
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.S)
# The heredoc's opener line split into shell words: quotes ('…', "…", $'…', \x) kept inside a word; redirections (<<'EOF', 2>&1,
# >file) dropped with their target; | || & && ; ( ) kept as separators. A line that does not split cleanly (an open quote, a
# trailing backslash) is never trusted: its heredoc stays checked.
_WORD = r"""(?:'[^']*'|\$'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|\\.|[^\s|;&()<>'"\\])+"""
LEX = re.compile(r"\s+|(?P<redir>\d*(?:<<<|<<-?|<>|>>|>&|<&|&>>?|>\||[<>]))\s*(?:" + _WORD + r")?"
                 r"|(?P<sep>\|\||&&|;;|\|&|[|;&()])|(?P<word>" + _WORD + ")", re.S)
UNQUOTE = re.compile(r"""\$'((?:\\.|[^'\\])*)'|'([^']*)'|"((?:\\.|[^"\\])*)"|\\(.)""", re.S)
SHELL = re.compile(r"(?:^|[\\/])(?:bash|sh|zsh|dash|ksh)(?:\.exe)?$", re.I)   # bash, /bin/sh, C:\…\bash.exe — not x.sh
STDIN_FILE = re.compile(r"^(?:-|/dev/stdin|/dev/fd/0|/proc/[^/]+/fd/0)$")     # a "script" that is the heredoc itself


def words(line):
    """[("word", text unquoted) | ("sep", op)] for one shell line, or None when it does not split cleanly."""
    out, pos = [], 0
    while pos < len(line):
        m = LEX.match(line, pos)
        if not m:
            return None
        pos = m.end()
        if m.group("word"):
            out.append(("word", UNQUOTE.sub(lambda q: next(g for g in q.groups() if g is not None), m.group("word"))))
        elif m.group("sep"):
            out.append(("sep", m.group("sep")))
    return out


def reads_stdin_as_code(prog, args):
    """Does this shell / source / . / eval run its stdin — the heredoc — as commands? args = its words up to the next
    separator. A shell given a script file runs the script and the heredoc is the script's input (data). Code: eval; -c (the
    string may read stdin) or -s; no script at all; a script that is stdin (-, /dev/stdin, /dev/fd/0, /proc/<pid>/fd/0) or
    whose file name the guard cannot see ("$f", `…`)."""
    if prog == "eval":
        return True
    i = 0
    while prog not in ("source", ".") and i < len(args):
        a = args[i]
        if a == "--":
            i += 1
            break
        if len(a) < 2 or a[0] not in "-+":
            break                                         # the script (or "-")
        if a.startswith("--"):
            i += 2 if a in ("--rcfile", "--init-file") else 1
            continue
        if "c" in a or "s" in a:
            return True
        i += 2 if ("o" in a or "O" in a) else 1           # -o / -O / +o take an option name, not a script
    if i >= len(args):
        return True
    script = args[i]
    name = re.split(r"[\\/]", script)[-1]
    return bool(STDIN_FILE.match(script)) or name in ("", "stdin", "0") or bool(re.search(r"[$`]", name))


def heredoc_is_code(line, depth=0):
    """True when any shell, source, . or eval on the heredoc's opener line would read its stdin as commands — the rule is
    per line, not per command, so `x.sh <<EOF | bash` stays code. A quoted command line inside a word (ssh h "bash -s",
    eval "…") is split and judged too."""
    toks = words(line)
    if toks is None:
        return True
    for i, (kind, w) in enumerate(toks):
        if kind != "word":
            continue
        prog = w if w in ("source", ".", "eval") else ("sh" if SHELL.search(w) else None)
        if prog:
            args = []
            for k, a in toks[i + 1:]:
                if k == "sep":
                    break
                args.append(a)
            if reads_stdin_as_code(prog, args):
                return True
        if depth < 2 and re.search(r"[\s|;&]", w) and heredoc_is_code(w, depth + 1):
            return True
    return False


def opener_line(cmd, m):
    """The logical line that opens heredoc match m: back over backslash-newline continuations to where the command starts,
    and, when the line ends in a pipe or && / ||, plus the line after the body (`cat <<EOF |` … EOF / `bash`)."""
    start = cmd.rfind("\n", 0, m.start()) + 1
    while start >= 2 and cmd[start - 2] == "\\":
        start = cmd.rfind("\n", 0, start - 1) + 1
    end = cmd.find("\n", m.start())
    line = cmd[start:end if end >= 0 else len(cmd)].replace("\\\n", " ")
    if re.search(r"(\|\|?|&&|\|&)\s*$", line):
        line += " " + cmd[m.end():].lstrip("\n").split("\n", 1)[0]
    return line


def strip_heredocs(cmd):
    """Replace heredoc bodies with a marker unless something on the opener line runs the body as commands (bash <<EOF,
    cat <<EOF | bash, sh -s, bash /dev/stdin stay code; bash check.sh <<EOF and python3 - <<EOF are data)."""
    def repl(m):
        if heredoc_is_code(opener_line(cmd, m)):
            return m.group(0)
        before = m.group(0)[:m.start(3) - m.start()]
        after = m.group(0)[m.end(3) - m.start():]
        return before + "<heredoc body stripped>" + after
    return HEREDOC.sub(repl, cmd)


def _script(name):
    """A path to the plugin script `name` as written on the command line: double-quoted (nothing expands in it but
    ${CLAUDE_PLUGIN_ROOT}; a backslash only as a Windows separator), single-quoted, or plain."""
    return (r'''(?:"(?:[^"$`\\]|\\(?=[^"$`\\\n])|\$\{CLAUDE_PLUGIN_ROOT\})*[\\/]''' + name + r'"'
            r"|'[^']*[\\/]" + name + r"'|(?:[\w.:~+@/\\-]*[\\/])?" + name + ")")


# The skills' state writes: ONE command, the plugin's launcher running ledger.py's --put / --unit / --run, then nothing but
# single-quoted strings, inert double-quoted strings and plain words — no ; & | < > ( ) $ ` \ { } * ? ! # or newline outside
# single quotes. Single quotes expand nothing and no other command runs, so the quoted words are ledger.py's data.
STATE_CALL = re.compile(r"[ \t]*bash[ \t]+" + _script(r"py\.sh") + r"[ \t]+" + _script(r"ledger\.py") + r"[ \t]+--(?:put|unit|run)"
                        r"(?P<args>(?:[ \t]+(?:'[^']*'|\"[^\"$`\\!]*\"|[\w./:=,@%+-]+)+)*)[ \t]*")


def strip_state_args(cmd):
    """In a state-write command (STATE_CALL, the whole command) replace each quoted argument with a marker."""
    m = STATE_CALL.fullmatch(cmd)
    if not m:
        return cmd
    args = re.sub(r"'[^']*'|\"[^\"]*\"", "'<data>'", m.group("args"))
    return cmd[:m.start("args")] + args + cmd[m.end("args"):]


# ---- fresh-source gate -------------------------------------------------------------------------------------------------------

def native_path(p):
    """A path string from the event JSON as this interpreter can open it. On Windows the hook runs through Git Bash, which
    converts POSIX paths in arguments and environment variables but not inside JSON strings: "/c/Users/x" becomes "C:/Users/x"
    when nothing exists at the POSIX spelling. Anything else comes back unchanged. Never raises."""
    try:
        s = str(p or "")
        if os.name == "nt" and s.startswith("/") and len(s) >= 2 and "a" <= s[1].lower() <= "z" and (len(s) == 2 or s[2] == "/"):
            if not os.path.exists(s):   # only a "/c/…" spelling is looked up; "//host/…" never reaches the file system
                return s[1].upper() + ":" + (s[2:] or "/")
    except Exception:
        pass
    return p


def adapter_text(project):
    """The human-only adapter, read and never written; "" when it is missing or unreadable."""
    try:
        with open(os.path.join(project, ".claude", "smartuse.local.md"), "rb") as fh:
            return fh.read(1 << 20).decode("utf-8-sig", "replace").replace("\r\n", "\n").replace("\r", "\n")
    except Exception:
        return ""


def adapter_list(text, key):
    """`key: a, b, c` -> ["a", "b", "c"]: the first line that starts with the key wins (frontmatter or body), values split on
    commas, trimmed, quotes dropped, empty ones dropped."""
    m = re.search(r"^" + re.escape(key) + r":[ \t]*(.*)$", text, re.M)
    if not m:
        return []
    return [v for v in (x.strip().strip("'\"").strip() for x in m.group(1).split(",")) if v]


def project_dir(data):
    """CLAUDE_PROJECT_DIR, else the event's cwd, else the process cwd (the order until-done.py uses)."""
    return os.environ.get("CLAUDE_PROJECT_DIR") or native_path(data.get("cwd")) or os.getcwd()


def _is_abs(s):
    return s.startswith("/") or bool(re.match(r"[A-Za-z]:", s))


def path_norm(p, project):
    """One spelling of a path: absolute (a relative one against the project dir), normalised, forward slashes."""
    s = str(native_path(p)).replace("\\", "/")
    if not _is_abs(s):
        s = str(project).replace("\\", "/").rstrip("/") + "/" + s
    return os.path.normpath(s).replace("\\", "/")


def path_key(p, project):
    """path_norm, case-folded the way this platform's file system is."""
    return os.path.normcase(path_norm(p, project)).replace("\\", "/")


def is_network_path(s):
    """A text test, no file system call: //host/share, \\\\host\\share and the \\\\?\\ and //?/ forms all start with two slashes."""
    return s[:2] in ("//", "\\\\", "/\\", "\\/")


def expand_sources(project, patterns):
    """-> ([(key, name shown)], "") with the files the patterns stand for, or (None, the reason). A network path is refused
    by its text before anything touches the file system (the adapter can come with a cloned repo, and a hook must not reach
    the network). Only a pattern relative to the project dir is expanded as a glob; an absolute source is one literal file.
    A pattern that matches no file is a problem of its own (a typo must reach the owner); so is a set larger than MAX_SOURCES."""
    for pat in patterns:
        if is_network_path(str(native_path(pat))):
            return None, pat + " is a network path; sources must be local files. The owner fixes sources: in .claude/smartuse.local.md. Nothing was sent."
    seen, out = set(), []
    for pat in patterns:
        p = str(native_path(pat))
        absolute = _is_abs(p.replace("\\", "/"))
        full = p if absolute else os.path.join(str(project), p)
        if not absolute and re.search(r"[*?\[]", p):
            found = []
            for f in glob.iglob(full, recursive=True):
                if os.path.isfile(f):
                    found.append(f)
                    if len(found) > MAX_SOURCES:
                        break
            found.sort()
        else:
            found = [full] if os.path.isfile(full) else []
        if not found:
            return None, ("source pattern matches no file: " + pat + ". The owner fixes sources: in .claude/smartuse.local.md. Nothing was sent.")
        for f in found:
            k = path_key(f, project)
            if k not in seen:
                seen.add(k)
                n, root = path_norm(f, project), path_norm(project, project)
                out.append((k, n[len(root) + 1:] if path_key(n, project).startswith(path_key(root, project) + "/") else n))
        if len(out) > MAX_SOURCES:
            return None, "narrow the pattern: " + pat + " matches over %d files. Nothing was sent." % MAX_SOURCES
    return out, ""


def hhmm(ts):
    """Local HH:MM of an ISO timestamp, or ""."""
    try:
        return datetime.datetime.fromisoformat(re.sub(r"\.\d+", "", str(ts)).replace("Z", "+00:00")).astimezone().strftime("%H:%M")
    except Exception:
        return ""


def opened_since_compaction(tp, project):
    """One forward pass over the transcript: -> (keys of the files the model itself Read since the last compaction, the time
    of that compaction or None when there was none). A Read is an assistant tool_use record named Read, not a subagent's
    (isSidechain). The last compaction is the last compact_boundary system record; with none, the last isCompactSummary user
    record; with neither, every Read counts. Only lines that can matter are parsed. Raises on an unreadable file or when the
    pass takes longer than BUDGET_S."""
    start = time.monotonic()
    sets = {"b": set(), "s": set(), "all": set()}     # reads since the last boundary / summary record / ever
    seen = {"b": None, "s": None}                    # the timestamp of the last boundary / summary record (None: there was none)
    with open(tp, "rb") as fh:
        for n, line in enumerate(fh, 1):
            if not n & 127 and time.monotonic() - start > BUDGET_S:
                raise TimeoutError("transcript pass over %g s" % BUDGET_S)
            use = b'"tool_use"' in line and b'"Read"' in line
            if not (use or b"compact_boundary" in line or b"isCompactSummary" in line):
                continue
            try:
                r = json.loads(line.decode("utf-8", "replace"))
            except Exception:
                continue
            if not isinstance(r, dict) or r.get("isSidechain"):
                continue
            kind = r.get("type")
            if kind == "system" and r.get("subtype") == "compact_boundary":
                sets["b"], seen["b"] = set(), r.get("timestamp") or ""
            elif kind == "user" and r.get("isCompactSummary") is True:
                sets["s"], seen["s"] = set(), r.get("timestamp") or ""
            elif kind == "assistant" and use:
                msg = r.get("message")
                for blk in (msg.get("content") if isinstance(msg, dict) else None) or []:
                    if isinstance(blk, dict) and blk.get("type") == "tool_use" and blk.get("name") == "Read":
                        fp = (blk.get("input") or {}).get("file_path") if isinstance(blk.get("input"), dict) else None
                        if isinstance(fp, str) and fp:
                            k = path_key(fp, project)
                            for s in sets.values():
                                s.add(k)
    if time.monotonic() - start > BUDGET_S:
        raise TimeoutError("transcript pass over %g s" % BUDGET_S)
    which = "b" if seen["b"] is not None else ("s" if seen["s"] is not None else "all")
    return sets[which], (seen[which] if which != "all" else None)


def fresh_verdict(data, project, sources):
    """None when every source was opened since the last compaction, else the reason (without the 'bash-guard: ' prefix)."""
    files, problem = expand_sources(project, sources)
    if files is None:
        return "fresh-source \u2014 " + problem

    def cannot(why):
        return "fresh-source \u2014 could not verify which sources were opened (" + why + "). Retry, or ask the owner. Nothing was sent."
    tp = data.get("transcript_path")
    if not isinstance(tp, str) or not tp:
        return cannot("the event names no transcript")
    try:
        opened, when = opened_since_compaction(native_path(tp), project)
    except TimeoutError as e:
        return cannot(str(e))
    except Exception as e:
        return cannot("transcript unreadable: " + type(e).__name__)
    left = [name for k, name in files if k not in opened]
    if not left:
        return None
    since = "in this session" if when is None else ("since the last compaction" + (" (" + hhmm(when) + ")" if hhmm(when) else ""))
    shown = ", ".join(left[:MAX_NAMES]) + (", and %d more" % (len(left) - MAX_NAMES) if len(left) > MAX_NAMES else "")
    return ("fresh-source \u2014 %d of %d sources not opened %s: %s. Open each with Read, then retry. Nothing was sent."
            % (len(left), len(files), since, shown))


# A shell line cut into words and separators. Like LEX, but a newline ends a command (it is a separator, not blank space).
FLEX = re.compile(r"[^\S\n]+|(?P<redir>\d*(?:<<<|<<-?|<>|>>|>&|<&|&>>?|>\||[<>]))[^\S\n]*(?:" + _WORD + r")?"
                  r"|(?P<sep>\n|\|\||&&|;;|\|&|[|;&()])|(?P<word>" + _WORD + ")", re.S)
VAR_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
LEAD_WORDS = frozenset(("if", "then", "else", "elif", "do", "while", "until", "!", "{", "time"))   # words that can stand before a command in a compound


def flex_split(text):
    """[[word, …], …]: the commands of a shell text, or None when it does not split cleanly (an open quote)."""
    out, cur, pos = [], [], 0
    while pos < len(text):
        m = FLEX.match(text, pos)
        if not m:
            return None
        pos = m.end()
        if m.group("word"):
            cur.append(UNQUOTE.sub(lambda q: next(g for g in q.groups() if g is not None), m.group("word")))
        elif m.group("sep"):
            out.append(cur)
            cur = []
    out.append(cur)
    return out


def command_segments(text):
    """The commands of a shell text as word lists, split on newline ; && || | (and & and parentheses). Text that does not split
    cleanly is split by line, and a line that still does not is split crudely on separators: a match found by over-splitting
    only errs towards the check."""
    text = text.replace("\\\n", " ")
    segs = flex_split(text)
    if segs is not None:
        return segs
    segs = []
    for line in text.split("\n"):
        s = flex_split(line)
        if s is None:
            s = [[w.strip("'\"") for w in piece.split()] for piece in re.split(r"[;&|()]+", line)]
        segs.extend(s)
    return segs


def word_norm(w):
    """A word with a path in it (a script) compared by its normalised form: ./tools/send.py = tools/send.py = tools\\send.py."""
    if "/" in w or "\\" in w:
        return os.path.normcase(os.path.normpath(str(native_path(w)).replace("\\", "/"))).replace("\\", "/")
    return w


def publish_hit(text, patterns):
    """Does any command of `text` start with the words of any publish pattern? Leading VAR=value words (and the if / then / do
    of a compound command) are dropped; the words
    are compared case-sensitively, so `echo "python send.py"` (first word echo) is not a match."""
    pats = []
    for p in patterns:
        segs = flex_split(p)
        pw = [word_norm(w) for w in (segs[0] if segs else [])]
        if pw:
            pats.append(pw)
    if not pats:
        return False
    longest = max(len(p) for p in pats)
    for seg in command_segments(text):
        i = 0
        while i < len(seg) and (VAR_ASSIGN.match(seg[i]) or seg[i] in LEAD_WORDS):
            i += 1
        head = [word_norm(w) for w in seg[i:i + longest]]
        if any(head[:len(p)] == p for p in pats):
            return True
    return False


def fresh_gate(data, text):
    """None to allow the call, else the reason to deny it. `text` is the Bash command with data heredocs stripped, or None for
    a tool call (then the tool's name is matched against `publish_tools:`)."""
    try:
        project = project_dir(data)
        adapter = adapter_text(project)
        sources = adapter_list(adapter, "sources")
        if not sources:
            return None
        if text is not None:
            hit = publish_hit(text, adapter_list(adapter, "publish"))
        else:
            name = data.get("tool_name")
            hit = isinstance(name, str) and any(fnmatch.fnmatchcase(name, g) for g in adapter_list(adapter, "publish_tools"))
        if not hit:
            return None
    except Exception:
        return None
    try:
        return fresh_verdict(data, project, sources)
    except Exception as e:
        return "fresh-source \u2014 could not verify which sources were opened (" + type(e).__name__ + "). Retry, or ask the owner. Nothing was sent."


def deny(why):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": f"bash-guard: {why}"}}))


def main():
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except Exception:
        return
    if not isinstance(data, dict):
        return
    if data.get("tool_name") != "Bash":
        why = fresh_gate(data, None)
        if why:
            deny(why)
        return
    cmd = (data.get("tool_input") or {}).get("command") or ""
    text = strip_heredocs(strip_state_args(cmd))
    for pat, why in RULES:
        if re.search(pat, text, re.I | re.S):
            deny(why)
            return
    why = fresh_gate(data, text)
    if why:
        deny(why)


main()
