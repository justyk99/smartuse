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
# once a publish matched, a failure to verify (no transcript, unreadable, past the deadline) denies. The adapter is only ever read.
# A source value must be a plain local path (checked by its text before any file call); source expansion and the transcript pass
# share one deadline, the expansion running in a worker thread that is abandoned when it does not answer. A relative source is
# walked component by component without following links (a link or reparse point on the way refuses the pattern); every value
# echoed in a reason is cut at 200 characters and a whole reason at 2,000. The deadline starts when the hook starts, before any
# scan of the command; the heredoc scans rescan their text once per unclosed opener, so a command with more than HEREDOC_CAP
# openers is read as it stands (its heredoc bodies count as code: an over-deny, never a miss).
# Test: bash hooks/tests/run.sh and fresh-gate-test.sh   Rollback: remove the PreToolUse entries in ~/.claude/settings.json
import base64, datetime, fnmatch, json, os, posixpath, re, stat, sys, threading, time

BUDGET_S = 4.0       # one deadline for the whole fresh-source check (source expansion and transcript pass); past it a matched publish is denied
MAX_SOURCES = 200    # files one gate check will expand the sources to
MAX_NAMES = 10       # unopened files named in a reason
MAX_VALUE = 200      # characters of one adapter value or file name echoed in a reason
MAX_REASON = 2000    # characters of a whole reason
HEREDOC_CAP = 16     # `<<` openers a command may hold before its bodies are read as code: the opener scan rescans the text once per unclosed opener

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
SHELL = re.compile(r"(?:^|[\\/])(?:bash|sh|zsh|dash|ksh|ash|fish)(?:\.exe)?$|^\$\{?SHELL\}?$", re.I)   # bash, /bin/sh, C:\…\bash.exe, $SHELL — not x.sh
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


DEVICE_FORMS = re.compile(r"\\\?\?\\|\\\\\?\\|\\\\\.\\|//\?/|//\./|GLOBALROOT", re.I)   # \??\  \\?\  \\.\  //?/  //./  GLOBALROOT


AUTOMOUNT = ("/net/", "/network/")   # automounted network trees (any case): a path under them is a share, whatever its spelling
AUTOMOUNT_RESOLVED = re.compile(r"/(?:net|network)(?:/|$)", re.I)   # the same trees after . and .. parts are folded away (text only)


def odd_part(p):   # only dots and spaces before any :stream, and not exactly "", "." or ".." (file-guard.py's rule, copied)
    return p not in ("", ".", "..") and p.split(":")[0].strip(". ") == ""


def is_plain_local(s):
    """A text test, no file system call: is this source value one of the plain spellings of a local file? Relative (no leading
    slash, no drive letter, no .. part), a drive path (C:\\x or C:/x, not C://x), or a POSIX absolute path (/x, not //x or /\\x,
    and not under the automount trees /net/ and /Network/). Everything else (//host/share, \\\\host\\share, the device and
    GLOBALROOT forms) is refused, and so is any spelling with a ":" in a part after the leading drive or a part of only dots and
    spaces (Windows reads those as another drive or a stream, or as the folder before them). A mapped network drive letter cannot
    be told apart from a local one by its text and is accepted."""
    if DEVICE_FORMS.search(s):
        return False
    t = s.replace("\\", "/")
    if t.lower().startswith(AUTOMOUNT):
        return False
    if t.startswith("/") and AUTOMOUNT_RESOLVED.match(posixpath.normpath(t)):   # /x/../net/h/s and /./net/h/s resolve to the same tree
        return False
    drive = bool(re.match(r"[A-Za-z]:[\\/](?![\\/])", s))
    if not (drive or re.match(r"/(?![/\\])", s)):
        if s[:1] in ("/", "\\") or re.match(r"[A-Za-z]:", s) or ".." in re.split(r"[\\/]", s):
            return False
    # no part may hold a ":" (a drive letter in the middle, an NTFS stream; the leading drive of a drive path is skipped) or be only dots
    # and spaces: decided on the text, so the file system is never asked about such a spelling
    return not any(":" in p or odd_part(p) for p in re.split(r"[\\/]", s)[1 if drive else 0:])


def clip(s, n=MAX_VALUE):
    """A value echoed in a reason, cut at n characters."""
    s = str(s)
    return s if len(s) <= n else s[:n] + "\u2026"


MAGIC = re.compile(r"[*?\[]")
FIX = " The owner fixes sources: in .claude/smartuse.local.md. Nothing was sent."


def is_link_stat(st):
    """A link from an lstat result alone, never by opening or resolving it: a symlink, or on Windows a link-like reparse point
    (a junction or mount point is one; DirEntry.is_symlink() does not see it). The name-surrogate bit of the reparse tag
    (0x20000000) is set for symlinks and junctions and clear for cloud-sync tags, so a synced folder is not refused."""
    if stat.S_ISLNK(st.st_mode):
        return True
    return bool(getattr(st, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)) \
        and bool(getattr(st, "st_reparse_tag", 0) & 0x20000000)


def _descent(full, rel):
    """-> (the directories at and under `full`, without following links: [(relative name, path)], the link met or None). Hidden
    names are skipped as glob does for **. Any link met on the way stops the descent: it may be a directory the walk would enter."""
    out, todo = [], [(rel, full)]
    while todo:
        r, f = todo.pop()
        out.append((r, f))
        try:
            with os.scandir(f) as it:
                names = sorted(e.name for e in it)
        except (OSError, ValueError):
            continue
        for name in reversed(names):
            if name.startswith("."):
                continue
            child, crel = os.path.join(f, name), (r + "/" + name if r else name)
            try:
                st = os.lstat(child)
            except (OSError, ValueError):
                continue
            if is_link_stat(st):
                return out, crel
            if stat.S_ISDIR(st.st_mode):
                todo.append((crel, child))
    return out, None


def walk_pattern(project, comps, wild):
    """-> (the regular files the project-relative components stand for, the project-relative link passed through or None).
    The tree is walked one component at a time and no link is followed: an entry that is a link, matched by a wildcard or
    named outright, or met while a ** descends, stops the walk. Wildcards are the ones glob has (a component that is exactly **
    matches zero or more directory levels; a hidden name only when the pattern part starts with a dot; the case rules of the
    platform's fnmatch). With wild False every component is a literal name. Stops past MAX_SOURCES files."""
    level, found = [("", str(project))], []
    for idx, comp in enumerate(comps):
        last, nxt = idx == len(comps) - 1, []
        if wild and comp == "**":
            grown = []
            for rel, full in level:
                dirs, link = _descent(full, rel)
                if link:
                    return found, link
                grown.extend(dirs)
            level = grown
            if not last:
                continue
            comp = "*"   # a trailing ** names every file below
        for rel, full in level:
            if wild and MAGIC.search(comp):
                try:
                    with os.scandir(full) as it:
                        names = sorted(e.name for e in it)
                except (OSError, ValueError):
                    continue
                if not comp.startswith("."):
                    names = [x for x in names if not x.startswith(".")]
                names = fnmatch.filter(names, comp)
            else:
                names = [comp]
            for name in names:
                child, crel = os.path.join(full, name), (rel + "/" + name if rel else name)
                try:
                    st = os.lstat(child)
                except (OSError, ValueError):
                    continue
                if is_link_stat(st):
                    return found, crel
                if last:
                    if stat.S_ISREG(st.st_mode):
                        found.append(child)
                        if len(found) > MAX_SOURCES:
                            return found, None
                elif stat.S_ISDIR(st.st_mode):
                    nxt.append((crel, child))
        level = nxt
        if not level:
            break
    return found, None


def expand_sources(project, patterns):
    """-> ([(key, name shown)], "") with the files the patterns stand for, or (None, the reason). A source that is not a plain
    local path is refused by its text before anything touches the file system (the adapter can come with a cloned repo, and a
    hook must not reach the network). A pattern relative to the project dir is walked without following links (walk_pattern;
    the project dir itself is never read as a pattern, so brackets in its name are only a name) and a link on the way refuses
    it; a relative value with wildcard characters also names a literal file (when it exists, it is required beside the wildcard matches). An absolute
    source is one literal file, owner-written, and a link on an absolute path IS followed. A pattern that matches no file is a
    problem of its own (a typo must reach the owner); so is a set larger than MAX_SOURCES."""
    for pat in patterns:
        if not is_plain_local(str(native_path(pat))):
            return None, clip(pat) + " is not a plain local path; sources must be local files." + FIX
    seen, out = set(), []
    for pat in patterns:
        p = str(native_path(pat))
        absolute = _is_abs(p.replace("\\", "/"))
        if absolute:
            found = [p] if os.path.isfile(p) else []
        else:
            comps = [c for c in p.replace("\\", "/").split("/") if c not in ("", ".")]
            found, link = walk_pattern(project, comps, True)
            if not link and MAGIC.search(p):   # a file named like the pattern is a source too, beside whatever the wildcards match
                lit, link = walk_pattern(project, comps, False)
                found = found + lit
            if link:
                return None, clip(pat) + " passes through a link (" + clip(link) + "); sources must be plain local files." + FIX
            found.sort()
        if not found:
            return None, "source pattern matches no file: " + clip(pat) + "." + FIX
        for f in found:
            k = path_key(f, project)
            if k not in seen:
                seen.add(k)
                n, root = path_norm(f, project), path_norm(project, project)
                out.append((k, n[len(root) + 1:] if path_key(n, project).startswith(path_key(root, project) + "/") else n))
        if len(out) > MAX_SOURCES:
            return None, "narrow the pattern: " + clip(pat) + " matches over %d files. Nothing was sent." % MAX_SOURCES
    return out, ""


def hhmm(ts):
    """Local HH:MM of an ISO timestamp, or ""."""
    try:
        return datetime.datetime.fromisoformat(re.sub(r"\.\d+", "", str(ts)).replace("Z", "+00:00")).astimezone().strftime("%H:%M")
    except Exception:
        return ""


STUCK = []   # worker threads that did not finish (a network share that does not answer): main() leaves without them


def expand_by_deadline(project, patterns, deadline):
    """expand_sources in a daemon worker thread, joined with the time left before `deadline` (file-guard.py's resolved() does the
    same for realpath): a glob or a stat on a share that does not answer must not hold the hook. Raises TimeoutError past the
    deadline, so a timeout can never let the call through."""
    out = []

    def work():
        try:
            out.append(expand_sources(project, patterns))
        except BaseException as e:
            out.append(e)
    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(max(0.0, deadline - time.monotonic()))
    if not out or time.monotonic() >= deadline:
        if not out:
            STUCK.append(t)
        raise TimeoutError("source expansion over %g s" % BUDGET_S)
    if isinstance(out[0], BaseException):
        raise out[0]
    return out[0]


def opened_since_compaction(tp, project, deadline):
    """One forward pass over the transcript: -> (keys of the files the model itself Read since the last compaction, the time
    of that compaction or None when there was none). A Read is an assistant tool_use record named Read, not a subagent's
    (isSidechain). A Read whose result record says is_error (a missing file, a Read the permission rules denied) does not count;
    a Read with no result record yet does. The last compaction is the last compact_boundary system record; with none, the last
    isCompactSummary user record; with neither, every Read counts. Only lines that can matter are parsed. Raises on an unreadable file or when the
    pass runs past the deadline."""
    sets = {"b": set(), "s": set(), "all": set()}     # reads since the last boundary / summary record / ever
    seen = {"b": None, "s": None}                    # the timestamp of the last boundary / summary record (None: there was none)
    pending = {}                                     # a Read's tool_use id -> its path key, until a result for it says it failed
    with open(tp, "rb") as fh:
        for n, line in enumerate(fh, 1):
            if not n & 127 and time.monotonic() >= deadline:
                raise TimeoutError("transcript pass over %g s" % BUDGET_S)
            use = b'"tool_use"' in line and b'"Read"' in line
            err = b'"is_error":true' in line or b'"is_error": true' in line   # a result that says its call failed (a missing file, a denied Read)
            if not (use or err or b"compact_boundary" in line or b"isCompactSummary" in line):
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
                            if isinstance(blk.get("id"), str):
                                pending[blk["id"]] = k
            elif kind == "user" and err:
                msg = r.get("message")
                for blk in (msg.get("content") if isinstance(msg, dict) else None) or []:
                    if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("is_error") is True \
                            and isinstance(blk.get("tool_use_id"), str) and blk["tool_use_id"] in pending:
                        for s in sets.values():   # the Read failed: that path was not opened (a later Read that works adds it again)
                            s.discard(pending[blk["tool_use_id"]])
    if time.monotonic() >= deadline:
        raise TimeoutError("transcript pass over %g s" % BUDGET_S)
    which = "b" if seen["b"] is not None else ("s" if seen["s"] is not None else "all")
    return sets[which], (seen[which] if which != "all" else None)


def fresh_verdict(data, project, sources, deadline):
    """None when every source was opened since the last compaction, else the reason (without the 'bash-guard: ' prefix)."""
    def cannot(why):
        return "fresh-source \u2014 could not verify which sources were opened (" + why + "). Retry, or ask the owner. Nothing was sent."
    try:
        files, problem = expand_by_deadline(project, sources, deadline)
    except TimeoutError as e:
        return cannot(str(e))
    if files is None:
        return "fresh-source \u2014 " + problem
    tp = data.get("transcript_path")
    if not isinstance(tp, str) or not tp:
        return cannot("the event names no transcript")
    try:
        opened, when = opened_since_compaction(native_path(tp), project, deadline)
    except TimeoutError as e:
        return cannot(str(e))
    except Exception as e:
        return cannot("transcript unreadable: " + type(e).__name__)
    left = [name for k, name in files if k not in opened]
    if not left:
        return None
    since = "in this session" if when is None else ("since the last compaction" + (" (" + hhmm(when) + ")" if hhmm(when) else ""))
    shown = ", ".join(clip(n) for n in left[:MAX_NAMES]) + (", and %d more" % (len(left) - MAX_NAMES) if len(left) > MAX_NAMES else "")
    return ("fresh-source \u2014 %d of %d sources not opened %s: %s. Open each with Read, then retry. Nothing was sent."
            % (len(left), len(files), since, shown))


# A shell line cut into words and separators. Like LEX, but a newline ends a command (it is a separator, not blank space).
FLEX = re.compile(r"[^\S\n]+|(?P<redir>\d*(?:<<<|<<-?|<>|>>|>&|<&|&>>?|>\||[<>]))[^\S\n]*(?:" + _WORD + r")?"
                  r"|(?P<sep>\n|\|\||&&|;;|\|&|[|;&()])|(?P<word>" + _WORD + ")", re.S)
VAR_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
LEAD_WORDS = frozenset(("if", "then", "else", "elif", "do", "while", "until", "!", "{", "coproc"))   # words that can stand before a command in a compound
# Programs that run the command that follows them: name -> (options that take a value, plain words before the command).
WRAPPERS = {"command": (frozenset(), 0), "builtin": (frozenset(), 0), "exec": (frozenset(("-a",)), 0),
            "env": (frozenset(("-u", "-C", "-S")), 0), "nohup": (frozenset(), 0), "nice": (frozenset(("-n",)), 0),
            "timeout": (frozenset(("-s", "-k")), 1), "stdbuf": (frozenset(("-i", "-o", "-e")), 0),
            "xargs": (frozenset(("-n", "-I", "-P", "-d", "-L", "-s", "-a", "-E")), 0), "time": (frozenset(), 0),   # GNU -i / -l attach their value
            "winpty": (frozenset(), 0),
            "sudo": (frozenset(("-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-r", "-t", "-U")), 0),
            "doas": (frozenset(("-u", "-C")), 0), "busybox": (frozenset(), 0), "setsid": (frozenset(), 0),
            # PowerShell and Windows launchers; their option words compare without regard to case (PS_WRAPPERS). -FilePath and
            # -ArgumentList are plain switches here so that their values stay in the word list.
            "start-process": (frozenset(("-workingdirectory", "-windowstyle", "-verb", "-redirectstandardoutput", "-redirectstandarderror",
                                         "-redirectstandardinput", "-credential")), 0),
            "wsl": (frozenset(("-d", "--distribution", "-u", "--user", "--cd", "--shell-type")), 0)}
WRAPPERS["saps"] = WRAPPERS["start"] = WRAPPERS["start-process"]
# Package runners: `uv run python send.py` runs what follows the plain word `run` (after its own options).
WRAPPERS["uv"] = (frozenset(("--with", "--python", "-p", "--directory", "--project", "--env-file", "--extra", "--group", "--with-requirements")), 1)
for _runner in ("poetry", "pdm", "pipenv", "hatch", "rye", "pipx"):
    WRAPPERS[_runner] = (frozenset(), 1)
PS_WRAPPERS = frozenset(("start-process", "saps", "start", "wsl"))
START_PROCESS = frozenset(("start-process", "saps", "start"))   # the program and its arguments are separate parameters, in any order


HERESTRING = "\x00"   # marks a here-string word (<<< WORD) in a segment: _hit takes it out again


def flex_split(text, seps=None):
    """[[word, …], …]: the commands of a shell text, or None when it does not split cleanly (an open quote). The word of a
    here-string (<<< WORD) stays in its segment, marked with HERESTRING. When `seps` is a list, the separator that ended each
    segment is appended to it, in order ("" for the last)."""
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
            if seps is not None:
                seps.append(m.group("sep"))
        elif (m.group("redir") or "").lstrip("0123456789") == "<<<":
            rest = m.group(0)[len(m.group("redir")):].strip()
            if rest:
                cur.append(HERESTRING + UNQUOTE.sub(lambda q: next(g for g in q.groups() if g is not None), rest))
    out.append(cur)
    if seps is not None:
        seps.append("")
    return out


def command_segments(text, seps=None):
    """The commands of a shell text as word lists, split on newline ; && || | (and & and parentheses). Text that does not split
    cleanly is split by line, and a line that still does not is split crudely on separators: a match found by over-splitting
    only errs towards the check. With a `seps` list, the separator that ended each segment is appended to it (a crude split
    counts as a pipe, which only errs towards the check)."""
    text = text.replace("\\\n", "")
    mine = [] if seps is not None else None
    segs = flex_split(text, mine)
    if segs is not None:
        if seps is not None:
            seps.extend(mine)
        return segs
    segs = []
    for line in text.split("\n"):
        s = flex_split(line)
        if s is None:
            s = [[w.strip("'\"") for w in piece.split()] for piece in re.split(r"[;&|()]+", line)]
        segs.extend(s)
        if seps is not None:
            seps.extend(["|"] * len(s))
    return segs


EXT = re.compile(r"\.[A-Za-z0-9]+$")
PYFAM = re.compile(r"(?:python(?:3(?:\.\d+)?)?|pythonw|pyw|py)")   # python, python3, python3.N, pythonw, pyw, py: one name


def names_file(w):
    """Does a pattern word name a file: a path separator in it, or an extension at its end?"""
    return "/" in w or "\\" in w or bool(EXT.search(w))


def path_parts(w):
    """The readings of a path word as component lists, compared case-insensitively: backslashes read as /, empty parts and .
    dropped. A word that starts with one letter as its first part (/c/proj, \\c\\proj) has a second reading with that letter as
    a drive (c:, proj), so /c/proj/send.py and C:/proj/send.py are the same file. The last component is read the Windows way
    (win_part, as file-guard.py does): cut at the first :, trailing dots and spaces dropped, so send.py. = 'send.py ' =
    send.py::$DATA = send.py."""
    s = w.replace("\\", "/")
    out = [[x.lower() for x in s.split("/") if x not in ("", ".")]]
    if out[0]:
        out[0][-1] = out[0][-1].split(":")[0].rstrip(". ") or out[0][-1]
    m = re.match(r"/([A-Za-z])/", s)
    if m:
        out.append([m.group(1).lower() + ":"] + out[0][1:])
    return out


def word_eq(p, c):
    """Does the command word c stand for the pattern word p? A word that names a file matches when c's path components end with
    p's (send.py = C:/proj/send.py = ./send.py; tools/send.py = C:\\p\\tools\\send.py, not send.py or xtools/send.py); any other
    word must be equal, without regard to case (a shell on Windows does not tell Git from git). No file system call: an unrelated
    script of the same name is an over-deny, which costs one turn."""
    if names_file(p):
        return any(pp and len(cp) >= len(pp) and cp[-len(pp):] == pp for pp in path_parts(p) for cp in path_parts(c))
    return p.lower() == c.lower()


def base_name(w):
    """The last path component of a command word with a trailing .exe / .cmd / .bat / .ps1 / .com dropped."""
    return re.sub(r"\.(?:exe|cmd|bat|ps1|com)$", "", re.split(r"[\\/]", w)[-1], flags=re.I)


def head_eq(p, c):
    """Does the command word c run the program the pattern's first word p names? Without a separator in p, by base name
    (/usr/bin/git, git.exe and git are one); the python family (python, python3, python3.N, py) is one name; a first word that
    names a file or holds a separator is matched like any other file word."""
    if "/" in p or "\\" in p:
        return word_eq(p, c)
    p = base_name(p)
    if PYFAM.fullmatch(p.lower()):
        return bool(PYFAM.fullmatch(base_name(c).lower()))
    if names_file(p):
        return word_eq(p, c)
    return base_name(c).lower() == p.lower()


def _bt_end(t, i):
    """t[i:] starts just after an opening backtick: the index of the closing one, or len(t)."""
    n = len(t)
    while i < n:
        if t[i] == "\\":
            i += 2
        elif t[i] == "`":
            return i
        else:
            i += 1
    return n


HEREDOC_OPEN = re.compile(r"<<-?[ \t]*(['\"]?)(\w+)\1")


def many_heredocs(text):
    """More `<<` than HEREDOC_CAP: the heredoc scans (each rescans the text once per unclosed opener) are skipped and every line
    of the text is read as code. A command that long with that many openers is an over-deny at worst: one turn."""
    return text.count("<<") > HEREDOC_CAP


def cap_strip(text):
    """gate_strip, except that a text with many heredoc openers is returned as it stands."""
    return text if many_heredocs(text) else gate_strip(text)


def _heredoc_end(t, i):
    """t[i:] starts with <<: the index just after the terminator line of a heredoc opened there, or i + 2 when there is none."""
    m = HEREDOC_OPEN.match(t, i)
    nl = t.find("\n", m.end()) if m else -1
    e = re.compile(r"\n[ \t]*" + re.escape(m.group(2)) + r"[ \t]*(?=\n|$)").search(t, nl) if nl >= 0 else None
    return e.end() if e else i + 2


def _sub_end(t, i, depth=0, many=False):
    """t[i:] starts just after "$(": the index of its matching ")", or len(t). Quotes, backticks and nested $( ) are respected.
    With many True (see HEREDOC_CAP) a heredoc is not looked for: its lines are read as code."""
    n, par, dq = len(t), 1, False
    while i < n:
        c = t[i]
        if c == "\\":
            i += 2
            continue
        if c == "'" and not dq:
            j = t.find("'", i + 1)
            if j >= 0:
                i = j + 1
                continue
        elif c == '"':
            dq = not dq
        elif c == "`":
            i = _bt_end(t, i + 1)
        elif c == "$" and t.startswith("$(", i) and depth < 20:
            i = _sub_end(t, i + 2, depth + 1, many)
        elif c == "<" and not many and not dq and t.startswith("<<", i) and not t.startswith("<<<", i):
            i = max(i, _heredoc_end(t, i) - 1)   # a heredoc's lines are text: quotes and parentheses in them do not count
        elif not dq:
            if c == "(":
                par += 1
            elif c == ")":
                par -= 1
                if par == 0:
                    return i
        i += 1
    return n


def subst_bodies(text, quoted=True):
    """The text inside each $( … ) and `…` of a shell text, also inside double quotes (not inside single quotes; an open single
    quote is read as a plain character, so more is checked, not less). Nested ones are found when a body is checked in turn.
    With quoted False the text is the body of an unquoted heredoc, where quote characters are plain text and only a backslash
    keeps a $ or backtick from substituting."""
    out, n, i, dq = [], len(text), 0, False
    many = many_heredocs(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "'" and not dq and quoted:
            j = text.find("'", i + 1)
            if j >= 0:
                i = j + 1
                continue
        elif c == '"' and quoted:
            dq = not dq
        elif c == "`":
            j = _bt_end(text, i + 1)
            out.append(text[i + 1:j])
            i = j
        elif c == "$" and text.startswith("$(", i):
            j = _sub_end(text, i + 2, 0, many)
            out.append(text[i + 2:j])
            i = j
        i += 1
    return out


def command_start(seg):
    """Index of the command word of a segment: past VAR=value words, the if / then / do of a compound command, and the
    programs that only run what follows them (env, nohup, nice, timeout, stdbuf, xargs, time, sudo, doas, command, exec …)
    with their options."""
    i = 0
    while i < len(seg):
        w = seg[i]
        name = base_name(w).lower()
        if w == "coproc" and i + 2 < len(seg) and seg[i + 2] == "{":   # coproc NAME { … }: the word before the brace is a name
            i += 2
        elif VAR_ASSIGN.match(w) or w in LEAD_WORDS:
            i += 1
        elif name in WRAPPERS:
            valued, plain = WRAPPERS[name]
            i += 1
            for skip in (0, 1):   # options, the plain words (run, 60), then options again (uv run --with x python …)
                while i < len(seg) and seg[i].startswith("-") and len(seg[i]) > 1:
                    if seg[i] == "--":
                        i += 1
                        break
                    i += 2 if (seg[i] in valued or (name in PS_WRAPPERS and seg[i].lower() in valued)) else 1
                if not skip:
                    i += plain
        else:
            break
    return i


SHELLS = ("sh", "bash", "zsh", "dash", "ksh", "ash", "fish", "$shell", "${shell}")   # command names (lower case) of a shell; $SHELL is read as one


def shell_string(cmd):
    """The command string a shell -c, an eval, a PowerShell iex / pwsh -Command / pwsh -EncodedCommand or a cmd /c is given
    (words after the command word), or None. A PowerShell encoded command is decoded (base64 of UTF-16LE); raises ValueError
    when the value does not decode, which the caller treats as a publish it cannot read."""
    name = base_name(cmd[0]).lower() if cmd else ""
    if name == "eval" or name in ("iex", "invoke-expression"):
        return " ".join(cmd[1:]) if len(cmd) > 1 else None
    if name in SHELLS:
        for k in range(1, len(cmd) - 1):
            if cmd[k].startswith("-") and not cmd[k].startswith("--") and "c" in cmd[k][1:]:
                return cmd[k + 2] if cmd[k + 1] == "--" and k + 2 < len(cmd) else cmd[k + 1]   # bash -c -- 'text'
    if name == "cmd":
        for k in range(1, len(cmd) - 1):
            if cmd[k].lower() in ("/c", "/k"):
                return " ".join(cmd[k + 1:])
    if name in ("pwsh", "powershell"):
        for k in range(1, len(cmd) - 1):
            o = cmd[k].lstrip("-/").lower() if cmd[k][:1] in ("-", "/") else ""
            if o and (o == "c" or (len(o) >= 3 and "command".startswith(o))):
                return " ".join(cmd[k + 1:])
            if o and (o == "ec" or "encodedcommand".startswith(o)):
                return base64.b64decode(cmd[k + 1], validate=True).decode("utf-16-le")
    return None


UNREADABLE = []   # set when an encoded PowerShell command could not be decoded: the gate then denies with its own reason


def ps_text(s):
    """A PowerShell command as shell-like text the segment splitter reads: a backtick-newline joins lines and any other backtick
    (PowerShell's escape character) is dropped, here-string fences (@" "@ @' '@) become line breaks, { and } (script blocks)
    become ;, and commas (array literals) become blanks. Nothing else."""
    s = re.sub(r"`\r?\n", "", s)
    s = re.sub(r"@[\"']|[\"']@", "\n", s)
    return s.replace("`", "").replace("{", ";").replace("}", ";").replace(",", " ")


# an UNQUOTED heredoc: no quote or backslash in or after the delimiter (bash substitutes $( … ) and backticks in its body lines)
HEREDOC_OPEN_PLAIN = re.compile(r"(?<!<)<<-?[ \t]*(\w+)(?![\w'\"\\])[^\n]*\n(.*?)\n[ \t]*\1[ \t]*(?=\n|$)", re.S)


BACKSLASH_DELIM = re.compile(r"(?<!<)<<(-?[ \t]*)\\(\w+)")


def gate_strip(text):
    """strip_heredocs for the gate's text: a backslashed delimiter (<<\\EOF) quotes it like '…' does, so its body is data too
    (strip_heredocs itself does not read that spelling; the RULES path is left as it is)."""
    return strip_heredocs(BACKSLASH_DELIM.sub(lambda m: "<<" + m.group(1) + "'" + m.group(2) + "'", text))


def heredoc_substs(text):
    """The $( … ) and backtick bodies inside the bodies of the unquoted heredocs of a shell text. strip_heredocs removes a data
    heredoc body whatever its quoting, but bash still runs the substitutions in an unquoted one; the plain lines stay data and a
    quoted or backslashed delimiter's body is not looked at."""
    if "<<" not in text or many_heredocs(text):
        return []
    out = []
    for m in HEREDOC_OPEN_PLAIN.finditer(text):
        out.extend(subst_bodies(m.group(2), False))
    return out


def publish_hit(text, patterns, depth=0, raw=None, ps=False):
    """Does any command of `text` run a publish pattern? A pattern matches a command when its first word is the command word
    (after VAR=value, env / nohup / timeout / winpty / sudo … wrappers and their options; by base name, so /usr/bin/git and
    git.exe are git, and the python family is one name) and each later pattern word appears, in order, among the command's later
    words: `git push` matches `git -C dir push origin`, `python send.py` matches `python -u C:/proj/send.py` (a word that names a
    file matches by the end of its path, see word_eq). The string given to sh|bash|zsh|dash|ksh -c and to eval, and the body of
    each $( … ) and backtick pair, is checked the same way, to depth 2. `echo "python send.py"` is not a match: its command
    word is echo. A word that only happens to appear later (git log --grep push) is an over-deny, which costs one turn. With ps
    True (a PowerShell command, see ps_text) a pattern's first word may be any word of a statement and the later ones follow it
    in order (PowerShell puts the program after a parameter); for Start-Process they may come in any order."""
    pats = []
    for p in patterns:
        segs = flex_split(p)
        if segs and segs[0]:
            pats.append(segs[0])
    if not pats:
        return False
    if _hit(text, pats, depth, ps):
        return True
    # `raw` is the command before strip_heredocs: the substitutions inside its unquoted heredocs run, whatever strip_heredocs did
    return raw is not None and depth < 2 and any(_hit(cap_strip(b), pats, depth + 1) for b in heredoc_substs(raw))


def _ps_match(pw, seg, cmd):
    """PowerShell: does the statement run pattern pw? Any word of cmd may be the program; the later pattern words follow it in
    order. For Start-Process (and its aliases) the words after the verb may come in any order."""
    for h, w in enumerate(cmd):
        if head_eq(pw[0], w):
            k = 0
            for x in cmd[h + 1:]:
                if k < len(pw) - 1 and word_eq(pw[k + 1], x):
                    k += 1
            if k == len(pw) - 1:
                return True
    if seg and base_name(seg[0]).lower() in START_PROCESS:
        args = seg[1:]
        for h, w in enumerate(args):
            if head_eq(pw[0], w):
                rest = args[:h] + args[h + 1:]
                if all(any(word_eq(p, x) for x in rest) for p in pw[1:]):
                    return True
    return False


def alias_words(cmd):
    """git -c alias.NAME=VALUE: the words of each VALUE (a leading ! dropped), which git runs when NAME is given."""
    out = []
    if cmd and base_name(cmd[0]).lower() == "git":
        for k in range(1, len(cmd) - 1):
            if cmd[k] == "-c" and cmd[k + 1].lower().startswith("alias.") and "=" in cmd[k + 1]:
                out.extend(cmd[k + 1].split("=", 1)[1].lstrip("!").split())
    return out


def piped_text(prev):
    """The text an echo or printf segment writes (its words after the options and, for printf, a format word), or None."""
    prev = [w for w in prev if w[:1] != HERESTRING]
    pc = prev[command_start(prev):]
    if not pc or base_name(pc[0]).lower() not in ("echo", "printf"):
        return None
    rest = pc[1:]
    while rest and rest[0].startswith("-") and len(rest[0]) > 1:
        rest = rest[1:]
    if base_name(pc[0]).lower() == "printf" and rest and "%" in rest[0]:
        rest = rest[1:]
    return " ".join(rest).replace("\\n", "\n")


def _hit(text, pats, depth, ps=False):
    seps = []
    segs = command_segments(text, seps)
    for n, seg in enumerate(segs):
        herestr = [w[1:] for w in seg if w[:1] == HERESTRING]
        if herestr:
            seg = [w for w in seg if w[:1] != HERESTRING]
        cmd = seg[command_start(seg):]
        if not cmd:
            continue
        cmd = cmd + alias_words(cmd)
        for pw in pats:
            if ps:
                if _ps_match(pw, seg, cmd):
                    return True
                continue
            if not head_eq(pw[0], cmd[0]):
                continue
            k = 0
            for w in cmd[1:]:
                if k < len(pw) - 1 and word_eq(pw[k + 1], w):
                    k += 1
            if k == len(pw) - 1:
                return True
        try:
            inner = shell_string(cmd)
        except ValueError:   # an encoded command that does not decode: nothing to look at, so the gate cannot clear it
            UNREADABLE.append(1)
            return True
        if inner and depth < 2 and _hit(inner, pats, depth + 1, ps):
            return True
        if depth < 2 and base_name(cmd[0]).lower() in SHELLS and reads_stdin_as_code("sh", cmd[1:]):
            # a shell that runs its stdin as commands: a here-string word, and the text an echo / printf pipes into it
            if any(_hit(h, pats, depth + 1, ps) for h in herestr):
                return True
            fed = piped_text(segs[n - 1]) if n and seps[n - 1] in ("|", "|&") else None
            if fed and _hit(fed, pats, depth + 1, ps):
                return True
    if depth < 2:
        for body in subst_bodies(text):
            if _hit(cap_strip(body), pats, depth + 1, ps):   # a quoted-delimiter heredoc in a body is text (git commit -m "$(cat <<'EOF' …)")
                return True
            if any(_hit(cap_strip(b), pats, depth + 1, ps) for b in heredoc_substs(body)):   # but an unquoted one still substitutes
                return True
    return False


def fresh_gate(data, text, raw=None, deadline=None, ps=False):
    """None to allow the call, else the reason to deny it. `text` is the Bash command with data heredocs stripped (or a
    PowerShell command, normalised, with ps True), or None for a tool call (then the tool's name is matched against
    `publish_tools:`); `raw` is the same command before the stripping. `deadline` is the time.monotonic() value the whole check
    must end by: main() starts it when the hook starts."""
    if deadline is None:
        deadline = time.monotonic() + BUDGET_S
    try:
        project = project_dir(data)
        adapter = adapter_text(project)
        sources = adapter_list(adapter, "sources")
        if not sources:
            return None
        if text is not None:
            hit = publish_hit(text, adapter_list(adapter, "publish"), 0, raw, ps)
        else:
            name = data.get("tool_name")
            hit = isinstance(name, str) and any(fnmatch.fnmatchcase(name, g) for g in adapter_list(adapter, "publish_tools"))
        if not hit:
            return None
    except Exception:
        return None
    if UNREADABLE:
        return "fresh-source — the PowerShell command carries an encoded command the gate cannot read. Run it in plain text. Nothing was sent."
    try:
        return fresh_verdict(data, project, sources, deadline)
    except Exception as e:
        return "fresh-source \u2014 could not verify which sources were opened (" + type(e).__name__ + "). Retry, or ask the owner. Nothing was sent."


def deny(why):
    msg = f"bash-guard: {why}"
    if len(msg) > MAX_REASON:
        msg = msg[:MAX_REASON - 1] + "…"   # a whole reason, ellipsis included, is at most MAX_REASON characters
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": msg}}))


def main():
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except Exception:
        return
    if not isinstance(data, dict):
        return
    deadline = time.monotonic() + BUDGET_S   # the fresh-source check's deadline starts with the hook, before any scan of the command
    tool = data.get("tool_name")
    if tool not in ("Bash", "PowerShell"):
        why = fresh_gate(data, None, None, deadline)
        if why:
            deny(why)
        leave()
        return
    cmd = (data.get("tool_input") or {}).get("command") or ""
    pre = strip_state_args(cmd)
    if tool == "PowerShell":   # no heredocs in PowerShell: RULES and the gate read the normalised text (the gate with / for \, which is no escape there)
        text = ps_text(pre)
        for pat, why in RULES:
            if re.search(pat, text, re.I | re.S):
                deny(why)
                return
        why = fresh_gate(data, text.replace("\\", "/"), None, deadline, True)
        if why:
            deny(why)
        leave()
        return
    many = many_heredocs(pre)
    text = pre if many else strip_heredocs(pre)
    for pat, why in RULES:
        if re.search(pat, text, re.I | re.S):
            deny(why)
            return
    why = fresh_gate(data, pre if many else gate_strip(pre), None if many else pre, deadline)
    if why:
        deny(why)
    leave()


def leave():
    """A worker still waiting on the file system (it timed out above) must not hold the process: leave without it, as
    file-guard.py does. Only when one is stuck; otherwise a normal return."""
    if STUCK:
        sys.stdout.flush()
        os._exit(0)


main()
