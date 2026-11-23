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
# openers (or an opener with a delimiter over HEREDOC_DELIM_MAX characters, or delimiters times text length over
# HEREDOC_BUDGET) is read as it stands: its heredoc bodies count as code, and each $( ) and backtick body in it is also read with quote
# characters taken as plain text, so it can over-deny (one turn) where a quote would have hidden a substitution. A PowerShell text, and a
# text read as it stands, is read twice: whole, and one line at a time (a quote never reaches past its line there). Any other
# Bash text is read whole: a known limit, see ROADMAP.
# A command the source check cannot read cleanly counts as a send while the sources are unopened (complexity(), and a string run by
# another shell, see _scan): over 32 KB, heredoc openers past the scan cap, three or more command substitutions, typographic quotes or
# dashes and an escaped quote (PowerShell), a nested shell string. It is decided before RULES and before any scan of the command; with
# the sources opened it goes on to RULES as any command does. That is an over-deny at worst (open the sources, retry, or simplify).
# A command over RULES_FIRST_MAX characters has the whole fresh-source block run before RULES (the frozen RULES are slow on long dense text).
# Paid calls (0.7.0 F3, docs/notes/paid-guard-plan.md section 8): a call to a per-call billed API (image / LLM hosts, named key variables, SDK imports,
# in the command, in inline code or in the script file the command runs) is denied until the owner gave a go: a `paid:` line in the adapter. The check
# runs LAST (after RULES and the fresh-source gate, so a run is counted only when every other check allowed the call), inside the same deadline, on
# Bash, PowerShell and Monitor commands (a Monitor call carries its command in tool_input.command, as Bash does). Strict: always on. Light: only where
# the adapter has a paid line (paid:, paid_scripts:, paid_hosts:, paid_free:, paid_guard: on); `paid` can be named in Rules off (light only) and is not
# on the floor. Every reason ends [rule paid]. A detection error allows in light and denies in strict; once a call is seen as paid, an error while
# verifying the go denies at both levels. State: the counter paid-runs.json in ~/.claude/smartuse/projects/<key>/ (counts and names, never a command);
# the floor rule owner-file keeps the shell off it (readers only; F5: and off the session transcripts). The block sits before options(), under its own header.
# F5: the owner can also type the go in the session (`paid go: …`, `test ok`, `paid stop`): read from the last 4 MB of the transcript, only records whose origin
# says the owner typed them (paid_typed_text); a subagent's call takes the adapter go only.
# Test: bash hooks/tests/run.sh, fresh-gate-test.sh and paid-guard-test.sh   Rollback: remove the PreToolUse entries in ~/.claude/settings.json
import base64, datetime, fnmatch, json, os, posixpath, re, stat, sys, threading, time

BUDGET_S = 4.0       # one deadline for the whole fresh-source check (source expansion and transcript pass); past it a matched publish is denied
MAX_SOURCES = 200    # files one gate check will expand the sources to
MAX_NAMES = 10       # unopened files named in a reason
MAX_VALUE = 200      # characters of one adapter value or file name echoed in a reason
MAX_REASON = 2000    # characters of a whole reason
HEREDOC_CAP = 16     # `<<` openers a command may hold before its bodies are read as code: the opener scan rescans the text once per unclosed opener
HEREDOC_DELIM_MAX = 64   # longest heredoc delimiter the opener scan is run on: it backtracks once per delimiter character, so a longer one is read as code too

# the heads of the rules that were split out of a parent rule in 0.6.1 (the parent's own pattern is unchanged but for the moved alternative)
_READER = (r"\b(cat|less|more|head|tail|sed|awk|grep|strings|base64|xxd|cp|scp|rsync|curl|python3?|node|tee|jq|find|type)\b[^;&|]*")
_GIT_PUSH = r"\bgit\b(\s+-\S+(\s+[^-\s]\S*)?)*\s+push\b[^;&|]*"
# 0.7.0 F7: the download cmdlets, their aliases and the .NET download methods, as a word (ps-download-exec). Every gap after them is bounded, so a dense run of them costs linear time.
_PS_DL = r"(?<![\w-])(?:invoke-webrequest|invoke-restmethod|start-bitstransfer|iwr|irm|curl|wget|downloadstring|downloaddata)(?![\w-])"

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
     r"(db-creds\.json|\.jira_env|\bid_(rsa|ed25519|ecdsa|dsa|\*)(?!\.pub)|\.ssh[\\/]id_[a-z0-9_]+(\s|[\"']|$)"
     r"|\.ssh[\\/]?(\*|\s|[\"']|$)|\.ssh[\\/]config|gh[\\/]hosts\.yml|\.git-credentials|\.netrc|recovery-codes"
     r"|\.claude[\\/]\.credentials\.json|\.aws[\\/]credentials|\.npmrc(?![\w.-])|\.pypirc(?![\w.-])|\.kube[\\/]config|\.docker[\\/]config\.json)",
     "credential file — its contents would land in the transcript on disk; use `claude mcp list` or env vars instead"),
    # two alternatives of the rule above in rules of their own (0.6.1), so that light can switch them off by name; the strict result is the same
    (_READER + r"[\\/]secrets[\\/]",
     "credential file — its contents would land in the transcript on disk; use `claude mcp list` or env vars instead"),
    (_READER + r"\.claude\.json",
     "credential file — its contents would land in the transcript on disk; use `claude mcp list` or env vars instead"),
    # anchored with ^: rules are searched with re.I | re.S, so `.` crosses newlines and one try at position 0 sees the whole text.
    # Unanchored, every position rescanned the rest: quadratic in the command's length.
    (r"^(?=.*\b(sqlcmd|osql|tsql|sqlq|spapply|mssql)\b)(?=.*\b(DROP\s+(TABLE|DATABASE|PROC|PROCEDURE|LOGIN|USER)|TRUNCATE\s+TABLE|DELETE\s+FROM)\b)",
     "destructive SQL through the shell — SQL in chat, a human runs it"),
    # git [options] push … --force / -f (also bundled: -fu) / --force-with-lease / --mirror / +ref
    (r"\bgit\b(\s+-\S+(\s+[^-\s]\S*)?)*\s+push\b[^;&|]*(\s--force(?![\w-])|\s-[a-z]*f[a-z]*\b|--mirror|\s[\"']?\+\S)",
     "force push"),
    # --force-with-lease (and any other --force-<word> option) in a rule of its own (0.6.1): `--force` above no longer reads it as `--force`
    (_GIT_PUSH + r"(--force-with-lease|\s--force-)",
     "force push"),
    (r"(>|\btee\b|\bsed\s+-i|\bcp\b|\bmv\b|\bpython3?\b|\bpy\.sh\b)[^;&|]*(smartuse\.local\.md|trusted-checks\.json|\.claude[. ]*[/\\]smartuse[. ]*[/\\]interpreter(?![\w-]|\.\w))",   # Windows drops a trailing dot or space of every part and reads x::$DATA as x: all are the file, interpreter.md is not
     "human-only file (it decides what the until-done gate may run, or which Python runs the hooks) — ask the user to edit it"),
    (r"(^|[;&|]\s*)(unbuffer|expect|script)\s",
     "faking an interactive terminal (script / unbuffer / expect) is not allowed"),
    (r"until-done\.py\s+--trust",
     "pinning a check script is a human-only action — the user runs it in their own terminal"),
    (r"\bsvn\s+(revert|resolve\s+--accept\s+theirs-full)\b",
     "svn revert / theirs-full — colleagues' uncommitted work would be lost"),
    # config-switch (0.6.1): the shell routes that would change smartuse's switches, by text. (1) the plugin command's configure / enable /
    # disable / uninstall naming this plugin (any @marketplace), or `disable --all`, and an install of it that sets options; (2) a write to
    # a Claude Code settings file, in a command that also names one of the keys that hold the switches. It reads text only: a write hidden
    # inside another program or built at run time is not seen. Linear: every repetition is bounded or cannot start inside its own run.
    (r"(?<![\w.-])claude(?:\.exe)?(?:\s+-[^\s;&|]+)*\s+plugins?\s+(?:"
     r"(?:configure|config|enable|disable|uninstall|remove|rm)(?:\s+[^\s;&|]+){0,8}?\s+(?:[\"']?smartuse(?![\w-])|--all(?![\w-]))"
     r"|marketplaces?\s+(?:remove|rm|delete)(?:\s+[^\s;&|]+){0,8}?\s+[\"']?smartuse(?![\w-])"
     r"|install(?:\s+[^\s;&|]+){0,8}?\s+[\"']?smartuse(?![\w-])[^\s;&|]*(?:\s+[^\s;&|]+){0,16}?\s+(?:--[\w-]*(?:config|option|set)[\w-]*|(?:strict|rules_off|wait_gate)\b))"
     r"|^(?=.*(?:pluginConfigs|enabledPlugins|disableAllHooks|CLAUDE_PLUGIN_OPTION_))(?:"
     r"(?=.*(?:>\s*[^\s;&|>]*(?<![\w.-])settings(?:\.local)?\.json(?![\w-])"
     r"|\b(?:tee|cp|mv|sponge|install|sed\s+-i)\b(?:\s+[^\s;&|]+){0,8}?\s+[^\s;&|]*(?<![\w.-])settings(?:\.local)?\.json(?![\w-])))"
     r"|(?=.*(?<![\w.-])settings(?:\.local)?\.json(?![\w-]))(?=.*\b(?:python3?|py\.sh|node|perl|ruby|set-content|add-content|out-file|tee-object)\b)"
     r"(?=.*(?:write|dump|[\"'][wa][b+]?[\"']|content|out-file)))"
     # (3) whatever else the text names: a redirect, delete, move, truncate or replace whose target is a settings file (settings.json /
     # settings.local.json inside a .claude folder, either slash); copying FROM it is a read, so cp / copy-item count only with it last
     r"|>\|?\s*[^\s;&|>]*\.claude[\\/]+settings(?:\.local)?\.json(?![\w.-])"
     r"|(?<![\w.-])(?:rm|unlink|shred|mv|ln|truncate|tee|sponge|install|sed\s+-i|remove-item|move-item|set-content|add-content|out-file|clear-content)(?![\w-])"
     r"(?:\s+[^\s;&|]+){0,8}?\s+[^\s;&|]*\.claude[\\/]+settings(?:\.local)?\.json(?![\w.-])"
     r"|(?<![\w.-])(?:cp|copy|copy-item|xcopy|robocopy)(?![\w-])(?:\s+[^\s;&|]+){0,8}?\s+[^\s;&|]*\.claude[\\/]+settings(?:\.local)?\.json(?![\w.-])[\"']?(?=\s*(?:$|[;&|)\n]))",
     "switching smartuse's guards is the owner's action: /plugin configure or /config"),
    # settings-file (0.7.0): a Claude Code settings file is read-only from the shell. config-switch above lists the commands that write
    # one; other writers exist (download-to-file, copy and sync, block copy, in-place editors, link makers, interpreters) and a list of
    # them is never complete. So the pattern is the settings path alone, read as typed like config-switch, and the waiver (see
    # _settings_waived) frees only what it can read as a plain argument of a reader, text, or a text-only heredoc line. Linear.
    (r"\.claude[\\/]+settings(?:\.local)?\.json(?![\w.-])",
     "a Claude Code settings file is read-only from the shell: use the Edit tool, which is checked value by value. "
     "Switching smartuse's guards is the owner's action: /plugin configure or /config"),
    # owner-file (0.7.0 F3): the paid-run counter paid-runs.json, its lock and the claim markers paid.<id>.done in the state folder record the runs
    # the owner allowed. Same shape as settings-file: the names alone, read as typed, and the same reader waiver (_settings_waived) frees only
    # a plain argument of a reader, text, or a text-only heredoc line. A trailing dot or ::$DATA is the file on Windows. receipts.jsonl is not matched. Linear.
    # 0.7.0 F7 (D-YK8): the adapter, the trust file and the launcher file join it, by the three names human-only's pattern lists (human-only
    # itself is unchanged: it lists the Bash writers; this rule closes the PowerShell verbs and every other writer, readers excepted).
    (r"(?<![\w.-])paid-runs\.(?:json|lock)(?![\w-]|\.\w)|(?<![\w.-])paid\.[\w-][\w.-]*\.done(?![\w-]|\.\w)"
     r"|(?<![\w-])smartuse\.local\.md(?![\w-]|\.\w)|(?<![\w.-])trusted-checks\.json(?![\w-]|\.\w)"
     r"|\.claude[. ]*[/\\]smartuse[. ]*[/\\]interpreter(?![\w-]|\.\w)"
     # 0.7.0 F5: a session transcript, .claude/projects/<folder>/<id>.jsonl (a subagent's below it): the typed go is read from it. The run between is
     # bounded (400) and starts after ONE separator (its class takes more), so a text of repeated openers or of a long run of slashes costs linear time. smartuse's own state folder (.claude/smartuse/projects) and a memory .md are not matched.
     r"|\.claude[. ]*[/\\]+projects[. ]*[/\\][^\s;&|\"'<>)]{0,400}?\.jsonl(?![\w-]|\.\w)",
     "owner-only file (the paid-run counter, the adapter, the trust file or the launcher file): the shell may read it, nothing else. Ask the owner."),
    # ps-download-exec (0.7.0 F7): a download cmdlet or alias (_PS_DL) whose output runs as commands. (1) piped on to iex / Invoke-Expression or
    # powershell / pwsh / cmd (a pipe into bash, sh and the like stays pipe-to-shell's); (2) given to iex / Invoke-Expression, or to [scriptblock]::Create, in the same segment; (3) a script the same command saves with
    # -o / -OutFile / -Output / -Destination and runs: the file named there is the next command, or the first argument of an interpreter, in one of
    # the next three segments. Every gap is bounded and a segment ends at ; & | or a newline, so the cost stays linear; a gap past its bound is a
    # limit (SECURITY.md). Downloading to a file, or reading a download as data, is not matched.
    (_PS_DL + r"[^;&\n]{0,300}?\|\s*(?:&\s*)?[\"']?(?:iex|invoke-expression|powershell|pwsh|cmd)(?:\.exe)?(?![\w-])"
     r"|(?<![\w.-])(?:iex|invoke-expression)(?![\w-])[^;&|\n]{0,300}?" + _PS_DL +
     r"|\[scriptblock\]\s*::\s*create[^;&|\n]{0,300}?" + _PS_DL +
     r"|" + _PS_DL + r"[^;&|\n]{0,150}?\s-(?:[a-z]*o|-?out(?!v)[a-z]*|-?output|-?dest[a-z]*)\s+[\"']?([^\s;&|\"']+)[\"']?"
     r"[^;&|\n]{0,150}[;&|\n]+(?:[^;&|\n]{0,100}[;&|\n]+){0,2}\s*(?:&\s*|\.\s+)?"
     r"(?:(?:start-process|start|powershell|pwsh|cmd|bash|sh|zsh|python3?|py|node|perl|ruby|wscript|cscript)(?:\.exe)?(?![\w-])"
     r"(?:\s+(?:-\S+|/[a-z]\b|bypass|unrestricted|remotesigned|allsigned|hidden|minimized))*\s+)?[\"']?(?:\.[\\/])?\1(?![\w.-])",
     "download then execute in PowerShell (a download run as commands, or a script the same command downloads and runs) — save the file, read it, then run it on purpose"),
    # ps-rm-root (0.7.0 F7): Remove-Item or an alias (rm, ri, del, erase, rd, rmdir; not `git rm`) with a recurse flag (-r…, /s) and a force flag (-fo…,
    # -f, /q) in one segment, and as a word of it a root (/, \, C:, C:\, with a trailing *), the home folder (~, $HOME, $env:USERPROFILE, ${env:USERPROFILE} (ps_text reads its braces as ;), %USERPROFILE%,
    # C:\Users\<name>, /home/<name>), `.` or `*`. A path below them (.\build, $HOME\.cache, *.tmp) is not matched. The three scans are bounded.
    (r"(?<![\w.-])(?<!git )(?:remove-item|ri|rm|del|erase|rd|rmdir)(?![\w-])"
     r"(?=[^;&|\n]{0,300}?\s(?:--?r[a-z]*|/s)(?![\w/-]))(?=[^;&|\n]{0,300}?\s(?:--?f(?:o[a-z]*)?|/q)(?![\w/-]))"
     r"[^;&|\n]{0,300}?\s[\"']?(?:\*(?:\.\*)?|[\\/]+\*?|[a-z]:[\\/]*\*?|~[\\/]*\*?|\$\{?home\}?[\\/]*\*?"
     r"|\$(?:env:(?:userprofile|homepath|homedrive|systemdrive)|[{;]env:(?:userprofile|homepath|homedrive|systemdrive)[};])[\\/]*\*?|%userprofile%[\\/]*\*?|\.[\\/]*\*?"
     r"|[a-z]:[\\/]+users[\\/]+[^\\/\s\"';&|)]+[\\/]*\*?|/home/[^/\s\"';&|)]+/*\*?)[\"']?(?=[\s;&|)]|$)",
     "Remove-Item -Recurse -Force of a root, the home folder, . or * — delete named paths only"),
]
# One name per rule, same length and same order as RULES (a test pins it). A rule is changed by its name, never by its position.
RULE_NAMES = ("pipe-to-shell", "download-exec", "sudo", "rm-root", "chmod-open", "credential-file", "secrets-dir", "claude-json",
              "sql-destructive", "force-push", "force-with-lease", "human-only", "fake-tty", "trust-pin", "svn-revert", "config-switch",
              "settings-file", "owner-file", "ps-download-exec", "ps-rm-root")
# 0.7.0 F3: the checks that are not RULES entries, one name each (V4). `paid` runs last in _main(); light can name it in Rules off (it is
# not on the FLOOR); every reason of it ends [rule paid]. RULE_NAMES keeps the length of RULES.
GATE_NAMES = ("paid",)
# The guard level (0.6.1). Strict: every rule. Light (the default): the rules in LIGHT_OFF are off, and so is any rule named in the
# plugin option rules_off, except the FLOOR, which protects the switches themselves and is always on.
LIGHT_OFF = frozenset(("force-with-lease", "claude-json"))
FLOOR = frozenset(("human-only", "trust-pin", "config-switch", "settings-file", "owner-file"))
# 0.6.1 F7: the doctor's canary, a no-op if the guard is down. _main() answers it before the fresh-source gate and RULES; it is compared whole.
DOCTOR_CANARY = ": smartuse-doctor-canary"

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


# The same language as STATE_CALL, written so that no text can be split two ways: a plain word is matched one character at a time.
# STATE_CALL reads a plain word as a run inside a repeated group, so a text it does not accept after a long plain word (a second
# command after it) is tried in exponentially many splits. This pattern is the cheap look first; STATE_CALL only runs on text it accepts.
STATE_SHAPE = re.compile(r"[ \t]*bash[ \t]+" + _script(r"py\.sh") + r"[ \t]+" + _script(r"ledger\.py") + r"[ \t]+--(?:put|unit|run)"
                         r"(?:[ \t]+(?:'[^']*'|\"[^\"$`\\!]*\"|[\w./:=,@%+-])+)*[ \t]*")


def strip_state_args(cmd):
    """In a state-write command (STATE_CALL, the whole command) replace each quoted argument with a marker."""
    if not STATE_SHAPE.fullmatch(cmd):
        return cmd
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
RUNNERS = frozenset(("uv", "poetry", "pdm", "pipenv", "hatch", "rye", "pipx"))   # package runners: their own options are too many to list, so what follows `run` is read loosely (_hit)
IEX = frozenset(("iex", "invoke-expression"))   # run the text they are given (or that is piped into them) as commands
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
    return line_segments(text, seps)


def line_segments(text, seps=None, exact=False):
    """The commands of a shell text split one line at a time (a line that does not split cleanly is split crudely on separators).
    A quoted word never reaches over a line break here, so a quote character in a comment, a data line or a here-string cannot
    hide the lines after it. With a `seps` list, the separator that ended each segment is appended: a crude split counts as a
    pipe (only errs towards the check); with `exact` a cleanly split line gives its real separators and a line break."""
    segs = []
    for line in text.split("\n"):
        mine = [] if exact else None
        s = flex_split(line, mine)
        if s is None:
            s = [[w.strip("'\"") for w in piece.split()] for piece in re.split(r"[;&|()]+", line)]
            ends = ["|"] * len(s)
        else:
            ends = (mine[:-1] + ["\n"]) if exact else ["|"] * len(s)
        segs.extend(s)
        if seps is not None:
            seps.extend(ends)
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


LONG_DELIM = re.compile(r"<<-?\s*[\\'\"]?\w{%d,}" % (HEREDOC_DELIM_MAX + 1))   # an opener the way HEREDOC reads it, with a delimiter over the bound
OPENER_WORD = re.compile(r"<<-?\s*[\\'\"]?(\w+)")   # the same opener, the delimiter captured
# The two frozen heredoc scans cost about (the openers' delimiter lengths added up) x (the text length) x 3e-8 s on the slowest laptop
# measured, so a budget of 8 million keeps one scan pair near 0.3 s at any size (16 openers x 64 characters stop at 8 KB, 16 x EOF
# at 160 KB). The budget is spent once per command: the decision is made on the whole command (nested openers included) and every
# nested body inherits it, so a command made of many bodies that are each just under the budget is not scanned body by body.
HEREDOC_BUDGET = 8000000


def many_heredocs(text):
    """More `<<` than HEREDOC_CAP, an opener whose delimiter is longer than HEREDOC_DELIM_MAX, or openers whose delimiter lengths
    times the text length pass HEREDOC_BUDGET: the heredoc scans (each rescans the text once per unclosed opener, and tries the
    delimiter at every length) are skipped and every line of the text is read as code. A command like that is an over-deny at worst:
    one turn."""
    if text.count("<<") > HEREDOC_CAP or LONG_DELIM.search(text):
        return True
    return sum(len(w) for w in OPENER_WORD.findall(text)) * len(text) > HEREDOC_BUDGET


# A command the source check cannot read cleanly is treated like a send while the sources are unopened: reading shell and PowerShell
# quoting ever deeper is a race the guard cannot win, and the cost of being wrong is one turn (open the sources, retry).
COMPLEX_MAX = 32768                                 # characters of a command the source check reads at all
COMPLEX_SUBST = 3                                   # command substitutions that make a command too tangled to read
RULES_FIRST_MAX = 4096                              # a command longer than this has the fresh-source block run before RULES (see main)
PS_TYPOGRAPHIC = re.compile("[\u2013-\u2015\u2018-\u201e]")   # the dashes and quotes PowerShell reads as plain ones
PS_ESCAPED_QUOTE = re.compile("`[`\"']")            # a backtick before a quote or another backtick
# a START_PROCESS word as a whole word (no letter, digit, _ or - beside it), any case; plain alternation, linear. Its arguments can be
# grouped in many ways (parentheses, arrays, a here-string, one quoted string), so the word alone makes the command unreadable
PS_START_WORD = re.compile(r"(?<![A-Za-z0-9_-])(?:" + "|".join(re.escape(w) for w in sorted(START_PROCESS)) + r")(?![A-Za-z0-9_-])", re.I)


def complexity(pre, ps):
    """A short tag naming why the source check cannot read this command (`pre`: the command before any heredoc stripping), or ""
    when it can. In order: over COMPLEX_MAX characters; heredoc openers past the scan cap (many_heredocs); COMPLEX_SUBST or more
    command substitutions (a backtick pair counts as one in Bash; in PowerShell the backtick is the escape character, so only $( counts;
    the text of a data heredoc is not counted);
    PowerShell only: typographic quotes or dashes, an escaped quote, a block comment (`<#` anywhere), Start-Process (a Start-Process word,
    start or saps, as a whole word anywhere: its arguments are not read). One pass of linear scans: no scan depends on the shape of the
    text."""
    if len(pre) > COMPLEX_MAX:
        return "over 32 KB"
    if many_heredocs(pre):
        return "heredocs past the scan cap"
    n = pre.count("$(") + (0 if ps else pre.count("`") // 2)
    if n >= COMPLEX_SUBST and not ps:
        # a data heredoc body (a quoted delimiter: a commit message with markdown backticks) is text, not substitutions; the
        # substitutions bash runs in an unquoted body still count. Counted again on the stripped text only when the raw count says so.
        t = data_text(pre)
        n = t.count("$(") + t.count("`") // 2 + len(heredoc_substs(pre))
    if n >= COMPLEX_SUBST:
        return "3 or more command substitutions"
    if ps:
        if PS_TYPOGRAPHIC.search(pre):
            return "typographic quotes or dashes"
        if PS_ESCAPED_QUOTE.search(pre):
            return "an escaped quote"
        if "<#" in pre:
            return "a block comment"
        if PS_START_WORD.search(pre):
            return "Start-Process (its arguments are not read)"
    return ""


def cap_strip(text, many=False):
    """gate_strip, except that a text with many heredoc openers is returned as it stands. With many True (the command this text
    was cut from is already over the cap) it is returned as it stands without looking."""
    return text if many or many_heredocs(text) else gate_strip(text)


def _heredoc_end(t, i):
    """t[i:] starts with <<: the index just after the terminator line of a heredoc opened there, or i + 2 when there is none."""
    m = HEREDOC_OPEN.match(t, i)
    nl = t.find("\n", m.end()) if m else -1
    e = re.compile(r"\n[ \t]*" + re.escape(m.group(2)) + r"[ \t]*(?=\n|$)").search(t, nl) if nl >= 0 else None
    return e.end() if e else i + 2


COMMENT_STOP = re.compile(r"[#'\"\\`$()}<\n]")           # the characters strip_comments has to look at; the rest of the text is jumped over
COMMENT_CASE = re.compile(r"\bcase\b[^\n]{0,200}?\bin\b")   # a case statement: its `a)` is no end of a substitution, so strip_comments leaves the text alone


def strip_comments(s):
    """0.7.0 F8. A Bash command with its # comments blanked, each to the end of its line (the line break stays), for the two readers that
    cut a command into words and would pair a quote in a comment with one in a later comment, hiding the lines between: the fresh-source
    gate and the paid scan. A # starts a comment only where a word can start (the start of the text, or after a blank, a line break or
    one of ; & | ( that is not escaped) and only at the top level: outside every quote and every $( ), ${ } and backtick pair. A # that is
    text (in single, double or $'…' quotes, $#, ${#x}, a#b, a URL fragment) is never read as a comment. A heredoc body is skipped
    untouched. One left-to-right pass, linear in the text; a text without # costs one `in` test. A text this pass cannot read to its end
    (a quote or $( that never closes, a case statement, =~) comes back as it was, so the readers then see what they saw before."""
    if "#" not in s or "=~" in s or COMMENT_CASE.search(s):
        return s
    out, last, i, n = [], 0, 0, len(s)
    st = [["c", 0, False]]   # a stack of [kind, open parentheses, arithmetic]; kind: c the top level or a $( ), b backticks, d double quotes, p ${ }
    esc = pend = pdepth = -1   # esc: the index after the last backslash pair; pend: the end of a heredoc opened on this line (its body is skipped at the next line break of that depth)
    find = COMMENT_STOP.search
    while True:
        m = find(s, i)
        if not m:
            break
        i = m.start()
        ch = s[i]
        top = st[-1]
        k = top[0]
        if ch == "\\":
            i += 2
            esc = i
        elif ch == "$" and k != "d" and s[i + 1:i + 2] == "'":   # $'…': a backslash escapes inside it
            j = i + 2
            while j < n and s[j] != "'":
                j += 2 if s[j] == "\\" else 1
            if j >= n:
                return s
            i = j + 1
        elif ch == "$":
            nx = s[i + 1:i + 2]
            if nx == "(":
                st.append(["c", 0, s.startswith("$((", i)])
                i += 2
            elif nx == "{":
                st.append(["p", 0, False])
                i += 2
            elif nx == '"' and k != "d":
                st.append(["d", 0, False])
                i += 2
            else:
                i += 1
        elif ch == "`":
            if k == "b":
                st.pop()
            else:
                st.append(["b", 0, False])
            i += 1
        elif k == "d":
            if ch == '"':
                st.pop()
            i += 1
        elif ch == '"':
            st.append(["d", 0, False])
            i += 1
        elif ch == "'":
            if k == "p" and len(st) > 1 and st[-2][0] == "d":
                i += 1   # a single quote inside "${ … }" is a plain character
            else:
                j = s.find("'", i + 1)
                if j < 0:
                    return s
                i = j + 1
        elif k == "p":
            if ch == "}":
                st.pop()
            i += 1
        elif ch == "(":
            top[1] += 1
            i += 1
        elif ch == ")":
            if top[1]:
                top[1] -= 1
            elif k == "c" and len(st) > 1:
                st.pop()
            i += 1
        elif ch == "#":
            if len(st) == 1 and i != esc and (i == 0 or s[i - 1] in " \t\n;&|("):
                out.append(s[last:i])
                j = s.find("\n", i)
                last = i = n if j < 0 else j
            else:
                i += 1
        elif ch == "<":
            if s.startswith("<<<", i):
                i += 3
            elif s.startswith("<<", i) and not top[2]:
                e = _heredoc_end(s, i)
                if e > i + 2:
                    pend, pdepth = e, len(st)
                i += 2
            else:
                i += 1
        elif ch == "\n" and pend > i and pdepth == len(st):
            i, pend = pend, -1
        else:
            i += 1
    if len(st) != 1 or not out:
        return s
    out.append(s[last:])
    return "".join(out)


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


def subst_bodies(text, quoted=True, many=False):
    """The text inside each $( … ) and `…` of a shell text, also inside double quotes (not inside single quotes; an open single
    quote is read as a plain character, so more is checked, not less). Nested ones are found when a body is checked in turn.
    With quoted False the text is the body of an unquoted heredoc, where quote characters are plain text and only a backslash
    keeps a $ or backtick from substituting. With many True the text belongs to a command that is already over the heredoc cap."""
    out, n, i, dq = [], len(text), 0, False
    many = many or many_heredocs(text)
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


def command_start(seg, points=None):
    """Index of the command word of a segment: past VAR=value words, the if / then / do of a compound command, and the
    programs that only run what follows them (env, nohup, nice, timeout, stdbuf, xargs, time, sudo, doas, command, exec …)
    with their options. With a `points` list, the index of each such program that was skipped is appended to it, in order: a
    publish pattern whose first word is one of them (`uv publish`, `wsl ./deploy.sh`) starts there."""
    i = 0
    while i < len(seg):
        w = seg[i]
        name = base_name(w).lower()
        if w == "coproc" and i + 2 < len(seg) and seg[i + 2] == "{":   # coproc NAME { … }: the word before the brace is a name
            i += 2
        elif VAR_ASSIGN.match(w) or w in LEAD_WORDS:
            i += 1
        elif name in WRAPPERS:
            if points is not None:
                points.append(i)
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


UNREADABLE = []   # set when an encoded PowerShell command could not be decoded: the gate then denies with its own reason (emptied at the start of each check)
COMPLEX = []      # the tag of a command the scan gave up on (a nested shell string): the gate then counts the command as a send (emptied at the start of each check)


PS_PAIR = re.compile(r"``|`[\"']")
PS_HERE_OPEN = re.compile(r"[ \t]*\r?\n")
PS_CURLY_SINGLE = re.compile("[‘’‚‛]")   # PowerShell's tokenizer reads these as single quotes ...
PS_CURLY_DOUBLE = re.compile("[“”„]")   # ... and these as double quotes, mixed freely with the ASCII ones


def ps_unescape(s):
    """s without its escaped quotes and backticks (a backtick and the quote or backtick after it), so that those can never open or
    close a quoted word. One left-to-right pass that follows PowerShell's own quoting: a single-quoted string is read strictly
    (a backtick in it is an ordinary character and a doubled '' is one escaped quote; nothing else is special, so a backtick before
    the closing quote leaves that quote in place) and is kept as it stands; in a double-quoted string, and outside any string, a
    backtick and the quote or backtick after it are dropped. A single quote that is never closed has nothing to pair with, so it is
    dropped and the rest read as it stands. Here-strings and comments are read as data, their pairs dropped. Only the ASCII ' and "
    are quotes here: the typographic ones PowerShell also reads as quotes are folded to them by ps_text before this runs."""
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == "`":
            if s[i + 1:i + 2] in ("`", '"', "'"):
                i += 2
            else:
                out.append(c)
                i += 1
        elif c == "'":
            k = i + 1
            while True:
                j = s.find("'", k)
                if j < 0:   # never closed: PowerShell cannot parse this, so nothing runs; its quote is dropped (so it cannot pair with another) and the rest is read as it stands
                    out.append(s[i + 1:])
                    i = n
                    break
                if s[j + 1:j + 2] == "'":   # a doubled quote is one escaped quote; a backtick before it is a plain character
                    k = j + 2
                    continue
                out.append(s[i:j + 1])
                i = j + 1
                break
        elif c == '"':
            out.append(c)
            i += 1
            while i < n:
                d = s[i]
                if d == "`" and s[i + 1:i + 2] in ("`", '"', "'"):
                    i += 2
                elif d == '"':
                    if s[i + 1:i + 2] == '"':
                        out.append('""')
                        i += 2
                    else:
                        out.append(d)
                        i += 1
                        break
                else:
                    out.append(d)
                    i += 1
        elif c == "@" and s[i + 1:i + 2] in ('"', "'") and PS_HERE_OPEN.match(s, i + 2):
            nl = PS_HERE_OPEN.match(s, i + 2).end() - 1   # a here-string: data up to its closing fence at a line start
            t = s.find("\n" + s[i + 1] + "@", nl)
            end = n if t < 0 else t
            out.append(s[i:nl] + PS_PAIR.sub("", s[nl:end]) + s[end:end + 3])
            i = min(n, end + 3)
        elif (c == "#" and (i == 0 or s[i - 1] in " \t\r\n;")) or (c == "<" and s[i + 1:i + 2] == "#"):
            e = s.find("\n" if c == "#" else "#>", i + 2 if c == "<" else i)
            e = n if e < 0 else (e if c == "#" else e + 2)
            out.append(PS_PAIR.sub("", s[i:e]))   # a comment: data, no quote in it counts
            i = e
        else:
            out.append(c)
            i += 1
    return "".join(out)


def ps_text(s):
    """A PowerShell command as shell-like text the segment splitter reads: a backtick-newline joins lines, an escaped quote or
    backtick is dropped whole outside single-quoted strings (see ps_unescape) so that it can never open or close a quoted word, any
    other backtick (PowerShell's escape character) is dropped, here-string fences (@" "@ @' '@) become line breaks, { and } (script
    blocks) become ;, and commas (array literals) become blanks. The typographic quotes PowerShell's tokenizer reads as quotes
    (U+2018 to U+201B as ', U+201C to U+201E as ") are folded to the ASCII ones first. Nothing else."""
    s = re.sub(r"`\r?\n", "", s)
    s = PS_CURLY_SINGLE.sub("'", s)
    s = PS_CURLY_DOUBLE.sub('"', s)
    s = ps_unescape(s)
    s = re.sub(r"@[\"']|[\"']@", "\n", s)
    return s.replace("`", "").replace("{", ";").replace("}", ";").replace(",", " ")


# an UNQUOTED heredoc: no quote or backslash in or after the delimiter (bash substitutes $( … ) and backticks in its body lines)
HEREDOC_OPEN_PLAIN = re.compile(r"(?<!<)<<-?[ \t]*(\w+)(?![\w'\"\\])[^\n]*\n(.*?)\n[ \t]*\1[ \t]*(?=\n|$)", re.S)


BACKSLASH_DELIM = re.compile(r"(?<!<)<<(-?[ \t]*)\\(\w+)")


def gate_strip(text):
    """strip_heredocs for the gate's text: a backslashed delimiter (<<\\EOF) quotes it like '…' does, so its body is data too
    (strip_heredocs itself does not read that spelling; the RULES path is left as it is)."""
    return strip_heredocs(BACKSLASH_DELIM.sub(lambda m: "<<" + m.group(1) + "'" + m.group(2) + "'", text))


def data_text(text):
    """text with the body of every heredoc cut out (HEREDOC, after the backslashed delimiter is read as a quoted one), whoever reads
    it: for counting what is on the command line itself. strip_heredocs would leave a body in place when its opener line does not
    split (the `"$(cat <<'EOF'` of a commit message has an open quote there). A heredoc a shell runs is scanned for a publish as usual."""
    return HEREDOC.sub(lambda m: m.group(0)[:m.start(3) - m.start()] + m.group(0)[m.end(3) - m.start():],
                       BACKSLASH_DELIM.sub(lambda m: "<<" + m.group(1) + "'" + m.group(2) + "'", text))


def heredoc_substs(text, many=False):
    """The $( … ) and backtick bodies inside the bodies of the unquoted heredocs of a shell text. strip_heredocs removes a data
    heredoc body whatever its quoting, but bash still runs the substitutions in an unquoted one; the plain lines stay data and a
    quoted or backslashed delimiter's body is not looked at."""
    if "<<" not in text or many or many_heredocs(text):
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
    file matches by the end of its path, see word_eq). The body of each $( … ) and backtick pair is checked the same way, to depth 2.
    A command that runs a string through another shell (sh|bash|zsh|dash|ksh -c, eval, iex, cmd /c, pwsh -Command / -EncodedCommand)
    is not read into: it counts as a hit and COMPLEX names why (the gate reports it as too complex to read). `echo "python send.py"`
    is not a match: its command word is echo. A word that only happens to appear later (git log --grep push) is an over-deny, which costs one turn. With ps
    True (a PowerShell command, see ps_text) a pattern's first word may be any word of a statement and the later ones follow it
    in order (PowerShell puts the program after a parameter); for Start-Process they may come in any order. A pattern whose first
    word is a program that only runs what follows it (uv publish, wsl ./deploy.sh, start deploy.bat) also matches from that word,
    and the package runners (uv, poetry, pdm, pipenv, hatch, rye, pipx) are read loosely: after their `run` word the pattern's
    first word may be any word, whatever options the runner has."""
    del UNREADABLE[:]
    del COMPLEX[:]
    pats = []
    for p in patterns:
        segs = flex_split(p)
        if segs and segs[0]:
            pats.append(segs[0])
    if not pats:
        return False
    many = many_heredocs(text if raw is None else raw)   # one heredoc budget per command: decided here on the whole command, inherited by every nested text
    if _hit(text, pats, depth, ps, many):
        return True
    # `raw` is the command before strip_heredocs: the substitutions inside its unquoted heredocs run, whatever strip_heredocs did
    return raw is not None and depth < 2 and any(_hit(cap_strip(b, many), pats, depth + 1, False, many) for b in heredoc_substs(raw, many))


def _subseq(pw, words, begin):
    """Do the pattern's words after its first appear, in order, among words[begin:]? One pass, and no copy of the words."""
    need, k = len(pw) - 1, 0
    if not need:
        return True
    for j in range(begin, len(words)):
        if word_eq(pw[k + 1], words[j]):
            k += 1
            if k == need:
                return True
    return False


def _strict(pw, words, starts):
    """Does pattern pw run from one of the word positions in `starts` (a program's position: the command word, or a program that
    only runs what follows it)? Each start holds the words of the one after it, so the first whose word is the pattern's program
    decides: a later one has fewer words left and cannot match what the first did not."""
    for p in starts:
        if p < len(words) and head_eq(pw[0], words[p]):
            return _subseq(pw, words, p + 1)
    return False


def _loose(pw, words, begin):
    """Does pattern pw run from any word of words[begin:] (its first word is any word, the later ones follow in order)? The first
    word that is the pattern's program decides, for the same reason."""
    for h in range(begin, len(words)):
        if head_eq(pw[0], words[h]):
            return _subseq(pw, words, h + 1)
    return False


def _start_at(seg):
    """PowerShell: the index of the first Start-Process / saps / start word of a statement (also after an assignment glued to it,
    $p=Start-Process), or -1. Later ones have fewer words after them, so the first decides."""
    for j, w in enumerate(seg):
        if w[:1] == "$" and "=" in w:
            w = w.split("=", 1)[1]
        if base_name(w).lower() in START_PROCESS:
            return j
    return -1


def _ps_match(pw, seg, cmd, sp):
    """PowerShell: does the statement run pattern pw? Any word of cmd (the statement's words from its first wrapper on) may be the
    program; the later pattern words follow it in order. For Start-Process (and its aliases; sp is where the first one is in seg)
    the words after the verb may come in any order. Linear: the first word that is the program decides, the others cannot do
    better."""
    for h, w in enumerate(cmd):
        if head_eq(pw[0], w):
            if _subseq(pw, cmd, h + 1):
                return True
            break
    if sp >= 0:
        lone = set()   # the only place a later pattern word stands: the program cannot be that word as well
        for p in pw[1:]:
            at = []
            for i in range(sp + 1, len(seg)):
                if word_eq(p, seg[i]):
                    at.append(i)
                    if len(at) == 2:   # two places: whichever word is the program, the other one stands for it
                        break
            if not at:
                return False
            if len(at) == 1:
                lone.add(at[0])
        return any(i not in lone and head_eq(pw[0], seg[i]) for i in range(sp + 1, len(seg)))
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


def _scan(segs, seps, pats, depth, ps, seen, many=False):
    """_hit for one split of the text into commands. `seen`: the inner strings already checked (the same text found twice is
    checked once). `many`: the command is over the heredoc cap (see many_heredocs), passed on to the inner texts."""
    for n, seg in enumerate(segs):
        herestr = [w[1:] for w in seg if w[:1] == HERESTRING]
        if herestr:
            seg = [w for w in seg if w[:1] != HERESTRING]
        pts = []
        start = command_start(seg, pts)
        cmd = seg[start:]
        if not cmd and not pts:
            continue
        extra = alias_words(cmd)
        full = seg + extra if extra else seg
        if extra:
            cmd = cmd + extra
        if ps:
            wide = full[pts[0] if pts else start:]   # from the first wrapper on: `uv publish`, `Start-Process ./go.ps1`
            sp = _start_at(seg)
        else:
            starts, loose = pts + [start], -1
            for p in pts:   # a package runner: whatever options it has, the pattern's program may be any word after its `run`
                if base_name(seg[p]).lower() in RUNNERS:
                    loose = next((j + 1 for j in range(p + 1, len(seg)) if seg[j].lower() == "run"), p + 1)
                    break
        for pw in pats:
            if ps:
                if _ps_match(pw, seg, wide, sp):
                    return True
            elif _strict(pw, full, starts) or (loose >= 0 and _loose(pw, full, loose)):
                return True
        if not cmd:
            continue
        try:
            inner = shell_string(cmd)
        except ValueError:   # an encoded command that does not decode: nothing to look at, so the gate cannot clear it
            UNREADABLE.append(1)
            return True
        if inner is not None:   # a string run by another shell (-c, eval, iex, cmd /c, -Command): the gate counts the command as a send, whatever the string says
            COMPLEX.append("a nested shell string")
            return True
        if depth < 2 and n and seps[n - 1] in ("|", "|&") and base_name(cmd[0]).lower() in IEX:
            # a string piped into iex is run as commands: the previous segment's words
            fed = piped_text(segs[n - 1])
            if fed is None:
                fed = " ".join(w for w in segs[n - 1] if w[:1] != HERESTRING)
            if fed and fed not in seen:
                seen.add(fed)
                if _hit(fed, pats, depth + 1, ps, many):
                    return True
        if depth < 2 and base_name(cmd[0]).lower() in SHELLS and reads_stdin_as_code("sh", cmd[1:]):
            # a shell that runs its stdin as commands: a here-string word, and the text an echo / printf pipes into it
            if any(_hit(h, pats, depth + 1, ps, many) for h in herestr):
                return True
            fed = piped_text(segs[n - 1]) if n and seps[n - 1] in ("|", "|&") else None
            if fed and _hit(fed, pats, depth + 1, ps, many):
                return True
    return False


def _hit(text, pats, depth, ps=False, many=False):
    many = many or many_heredocs(text)   # a text cut from a command that is over the cap is read as it stands too: one budget per command
    seen = set()
    seps = []
    if _scan(command_segments(text, seps), seps, pats, depth, ps, seen, many):
        return True
    if "\n" in text and (ps or many):
        # A quoted word that spans lines can hide the lines inside it in the whole-text split (a PowerShell here-string, a data
        # heredoc body read as code past the cap). So a PowerShell text, and a text read as it stands (many_heredocs), is also read one
        # line at a time, where a quote never reaches past its line (over-checking only: a line break inside a quoted word is read as
        # a line break). Not done for the other Bash texts, where it would deny quoted commit messages and PR bodies: known limit, see ROADMAP.
        seps = []
        if _scan(line_segments(text.replace("\\\n", ""), seps, True), seps, pats, depth, ps, seen, many):
            return True
    if depth < 2:
        done = set()
        for body in subst_bodies(text, True, many):
            done.add(body)
            if _hit(cap_strip(body, many), pats, depth + 1, ps, many):   # a quoted-delimiter heredoc in a body is text (git commit -m "$(cat <<'EOF' …)")
                return True
            if any(_hit(cap_strip(b, many), pats, depth + 1, ps, many) for b in heredoc_substs(body, many)):   # but an unquoted one still substitutes
                return True
        if many:
            # A text read as it stands is not heredoc-stripped, so the substitutions in an unquoted heredoc body are seen only through the
            # quote-aware split above, where an apostrophe in a heredoc line (a plain character to bash) pairs as a quote and hides them. So
            # its substitutions are collected once more with quote characters taken as plain text (over-checking only), at every level.
            for body in subst_bodies(text, False, many):
                if body not in done and _hit(cap_strip(body, many), pats, depth + 1, ps, many):
                    return True
    return False


SENT = " Nothing was sent."


def fresh_gate(data, text, raw=None, deadline=None, ps=False, tag=""):
    """None to allow the call, else the reason to deny it. `text` is the Bash command with data heredocs stripped (or a
    PowerShell command, normalised, with ps True), or None for a tool call (then the tool's name is matched against
    `publish_tools:`); `raw` is the same command before the stripping. `deadline` is the time.monotonic() value the whole check
    must end by: main() starts it when the hook starts. `tag` (see complexity): the command is too complex to read, so with
    `sources:` and `publish:` listed it counts as a publish without being scanned. A command that publish_hit gave up on
    (COMPLEX) is reported the same way: the reason adds that the command is too complex to read."""
    if deadline is None:
        deadline = time.monotonic() + BUDGET_S
    del UNREADABLE[:]   # the flag belongs to this check: an earlier call in the same process must not leave it set
    del COMPLEX[:]
    try:
        project = project_dir(data)
        adapter = adapter_text(project)
        sources = adapter_list(adapter, "sources")
        if not sources:
            return None
        if tag:
            hit = bool(adapter_list(adapter, "publish"))   # a command that cannot be read is a send only where the owner lists what a send is
            if hit:
                COMPLEX.append(tag)
        elif text is not None:
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
        why = fresh_verdict(data, project, sources, deadline)
    except Exception as e:
        return "fresh-source \u2014 could not verify which sources were opened (" + type(e).__name__ + "). Retry, or ask the owner. Nothing was sent."
    if why and COMPLEX and "sources not opened" in why and why.endswith(SENT):
        why = why[:-len(SENT)] + (" The command is also too complex for the source check to read (%s), so it counts as a send: "
                                  "open each with Read, then retry, or simplify it." % COMPLEX[0]) + SENT
    return why


# ---- waivers (0.6.1): honest commands that two RULES entries match by mistake ----------------------------------------------------
# A match of a rule named in WAIVABLE can be waived, and only when EVERY match of that rule in the text is such a case. Anything the
# waiver cannot read cleanly stays denied: a text complexity() tags, a text words() or flex_split cannot split, a line continuation.
#   pipe-to-shell: a download piped into Python run as `-m <module>` for a module on the allow list PY_DATA_MODULES (json.tool: it
#                  reads JSON as data and prints it), with only plain flags before -m and only json.tool's own flags, a number after
#                  --indent and a lone `-` after it (a file word is a file it reads or writes). Everything else stays denied: a shell, a bare
#                  interpreter, a program text, a script file, Node, Perl, any other module, an interpreter behind sudo or other
#                  wrapper. An allow list, because a deny list of risky programs is never complete.
#   sudo:          the word carried as text, in an argument of a command that only carries text (the message of git commit / tag /
#                  notes, echo, printf, grep, rg, the title and body of gh pr / issue / release). Not waived when the text holds a
#                  command substitution or process substitution anywhere, when any segment has sudo or doas before its command, or
#                  when a pipe feeds anything but a plain filter.
#   settings-file: (0.7.0) a command that names a Claude Code settings file is denied unless EVERY place the path is named is (1) a plain
#                  argument of a reader (READERS; GIT_READERS for git; a copy command with the path as a source; `python -m json.tool`
#                  given that one file and flags only), (2) text carried by a text-only command (_text_words), or (3) a line of a data
#                  heredoc whose opener only carries text (cat, or a text-only command), with nothing else on the opener line. Never
#                  waived: an option value or a redirect target, a reader behind sudo, a command or process substitution anywhere in
#                  the text, a text complexity() tags or that does not split cleanly, and a command that names the path whose output is
#                  piped into anything but a plain filter (the path would reach it as an argument).
WAIVABLE = frozenset(("pipe-to-shell", "sudo", "settings-file", "owner-file"))   # owner-file (0.7.0 F3) has the settings-file waiver: readers only
PIPE_OK = frozenset(("head", "tail", "wc", "sort", "uniq", "cat", "cut", "tr", "less", "more", "grep", "rg", "nl", "column", "jq"))   # read what is piped in, run nothing
PY_DATA_MODULES = frozenset(("json.tool",))   # modules `python -m` may run on a download: they read it as data
PY_FLAGS = frozenset(("-u", "-B", "-I", "-S", "-E", "-s", "-O", "-OO", "-q", "-v", "-b", "-bb", "-d", "-R", "-P"))   # plain flags: none takes a value or runs code
JSON_TOOL_FLAGS = frozenset(("-h", "--help", "--sort-keys", "--no-ensure-ascii", "--json-lines", "--tab", "--no-indent", "--compact"))   # json.tool's own options that take no value (--indent takes a number, handled beside it); its file words are never waived
# 0.7.0 settings-file: the commands whose plain arguments are only READ (an allow list: a list of writers is never complete). Bash and PowerShell names, lower case.
READERS = frozenset(("cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg", "wc", "ls", "stat", "file", "jq", "diff", "cmp", "test", "[",
                     "md5sum", "sha1sum", "sha224sum", "sha256sum", "sha384sum", "sha512sum", "b2sum", "cksum", "sum", "shasum", "md5", "sha256",
                     "get-content", "gc", "type", "select-string", "sls", "test-path", "get-item", "get-childitem", "dir", "get-filehash"))
GIT_READERS = frozenset(("add", "diff", "status", "log", "show", "blame", "ls-files", "check-ignore", "commit"))   # git subcommands that only read a path argument
GIT_GLOBAL_OK = frozenset(("--no-pager", "-P", "--no-optional-locks", "--literal-pathspecs", "--glob-pathspecs", "--noglob-pathspecs", "--icase-pathspecs"))   # git options before the subcommand (-C and its value too); any other (-c, --git-dir, --exec-path) is not a reader
COPIERS = frozenset(("cp", "copy", "copy-item", "cpi"))   # the path may be a source (never the last word) with only plain flags
COPY_FLAGS = re.compile(r"-[rRapfivnuPLHdx]+|-(?:force|recurse|verbose|confirm|whatif|passthru)", re.I)   # no -l / -s (links) and no -t / -T / -Destination / -b
SETTINGS_PIPE_OK = PIPE_OK | frozenset(("convertfrom-json", "select-object", "measure-object", "sort-object", "out-string", "out-host", "format-list", "format-table"))
FLAG_LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
# a reader's options that take a value: (short letters, long names). A hit that is such a value is never waived (less -o and --log-file WRITE the file named).
READER_VALUE_OPTS = {
    "grep": ("efmABCdD", ("--regexp", "--file", "--max-count", "--after-context", "--before-context", "--context", "--directories", "--devices",
                          "--include", "--exclude", "--exclude-from", "--exclude-dir", "--label", "--binary-files")),
    "head": ("nc", ("--lines", "--bytes")), "tail": ("ncs", ("--lines", "--bytes", "--pid", "--sleep-interval", "--max-unchanged-stats")),
    "less": ("oOpPtTxyzbhjkDU", ("--log-file", "--LOG-FILE", "--pattern", "--prompt", "--tag", "--tag-file", "--tabs", "--shift", "--jump-target",
                                 "--lesskey-file", "--lesskey-src", "--lesskey-content", "--max-back-scroll", "--max-forw-scroll", "--window", "--buffers")),
    "ls": ("IwT", ("--ignore", "--width", "--tabsize", "--format", "--sort", "--time", "--time-style", "--block-size", "--hide", "--color", "--indicator-style", "--quoting-style")),
    "stat": ("c", ("--format", "--printf")), "file": ("fmeFP", ("--files-from", "--magic-file", "--exclude", "--separator", "--parameter")),
    "jq": ("fL", ("--from-file", "--arg", "--argjson", "--slurpfile", "--rawfile", "--argfile", "--indent")),
    "diff": ("IULCDxXFW", ("--ignore-matching-lines", "--label", "--unified", "--context", "--ifdef", "--exclude", "--exclude-from",
                           "--show-function-line", "--width", "--starting-file", "--from-file", "--to-file")),
    "cmp": ("in", ("--ignore-initial", "--bytes", "--skip-initial")), "shasum": ("a", ("--algorithm",)),
}
READER_VALUE_OPTS["egrep"] = READER_VALUE_OPTS["fgrep"] = READER_VALUE_OPTS["grep"]


def _shell_tokens(t):
    """[(kind, value, start, end)] for a shell text read as flex_split reads it (redirections and their targets leave no word), or
    None when it does not split cleanly."""
    out, pos = [], 0
    while pos < len(t):
        m = FLEX.match(t, pos)
        if not m:
            return None
        s, pos = pos, m.end()
        if m.group("word"):
            out.append(("word", UNQUOTE.sub(lambda q: next(g for g in q.groups() if g is not None), m.group("word")), s, pos))
        elif m.group("sep"):
            out.append(("sep", m.group("sep"), s, pos))
    return out


def _option_values(v, start, letters, flags, longs):
    """Indices of the words of v (from `start`) that are the VALUE of an option: -m VALUE, -mVALUE, -am VALUE (a bundle of `flags`
    letters ending in an option letter of `letters`), --message VALUE, --message=VALUE. Nothing after a bare --."""
    out, take = set(), False
    for j in range(start, len(v)):
        a = v[j]
        if take:
            out.add(j)
            take = False
        elif a == "--":
            break
        elif a in longs:
            take = True
        elif a.startswith("--"):
            k = a.find("=")
            if k > 0 and a[:k] in longs:
                out.add(j)
        elif a.startswith("-") and len(a) > 1:
            n = 1
            while n < len(a) and a[n] in flags:
                n += 1
            if n < len(a) and a[n] in letters:
                if n + 1 < len(a):
                    out.add(j)
                else:
                    take = True
    return out


def _text_words(v, i):
    """The words of the command v[i:] that are text and nothing else (True: every argument), or None when the command is not one
    that only carries text: git commit / tag / notes (the message options), echo, printf, grep, rg (not its --pre program), gh pr /
    issue / release (the title, body and notes options)."""
    cmd = base_name(v[i]).lower()
    if cmd in ("echo", "printf", "grep"):
        return True
    if cmd == "rg":
        return None if any(a == "--pre" or a.startswith("--pre=") for a in v[i + 1:]) else True
    if cmd == "git":
        k = i + 1
        while k < len(v) and v[k].startswith("-"):
            k += 2 if v[k] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace") else 1
        if k < len(v) and v[k] in ("commit", "tag", "notes"):
            return _option_values(v, k + 1, "m", "aensvq", ("--message",))
        return None
    if cmd == "gh" and i + 1 < len(v) and v[i + 1] in ("pr", "issue", "release"):
        return _option_values(v, i + 2, "tbn", "", ("--title", "--body", "--notes"))
    return None


def _python_data_module(a):
    """Is this Python, given the words `a` after its name, run as `-m <module>` for a module of PY_DATA_MODULES, with only plain
    flags (PY_FLAGS) before the -m, and after the module only its own flags (JSON_TOOL_FLAGS), a number after --indent and a lone
    `-` (stdin)? Any other word after the module is a file it reads or writes, and a pipeline that carries one is not waived."""
    i = 0
    while i < len(a) and a[i] in PY_FLAGS:
        i += 1
    if not (i + 1 < len(a) and a[i] == "-m" and a[i + 1] in PY_DATA_MODULES):
        return False
    j = i + 2
    while j < len(a):
        w = a[j]
        if w == "--indent":
            j += 1
            if j >= len(a) or not (a[j].isascii() and a[j].isdigit()):
                return False
        elif w not in JSON_TOOL_FLAGS and w != "-":
            return False
        j += 1
    return True


def _json_tool_file(a):
    """The index in `a` (the words after a Python's name) of the ONE file word of `-m json.tool` given plain flags (PY_FLAGS) before
    the -m, and after the module only JSON_TOOL_FLAGS, a number after --indent and exactly one other word; None for anything else (no
    file word, two or more, a lone `-` counts as one: the module's second positional is the file it writes)."""
    i = 0
    while i < len(a) and a[i] in PY_FLAGS:
        i += 1
    if not (i + 1 < len(a) and a[i] == "-m" and a[i + 1] in PY_DATA_MODULES):
        return None
    files, j = [], i + 2
    while j < len(a):
        if a[j] == "--indent":
            j += 1
            if j >= len(a) or not (a[j].isascii() and a[j].isdigit()):
                return None
        elif a[j] not in JSON_TOOL_FLAGS:
            files.append(j)
        j += 1
    return files[0] if len(files) == 1 else None


def _copy_lands(dest, src, pat):
    """0.7.0 review fix M3: does a copy of `src` into `dest` write a path that `pat` (the rule's own pattern) names? Only when dest is a
    folder: a word ending in a slash or backslash, or one with no file extension (`.`, `..`, `.claude`, a project's state folder), or
    a project's state folder whatever its name. The copy then makes <dest>/<file name of src>, so a settings file copied into `.claude/`
    is a write. A destination with a file extension (settings.bak, backup.json) is a file and is not joined. The joined path counts when
    the pattern's match starts inside the destination (`.claude/` + settings.json) or, for a pattern that names a file alone (paid-runs.json,
    smartuse.local.md), when the destination is one of the owner's folders (.claude, ~/.claude/smartuse, a project's state folder): a copy of the
    counter into backup/ is a plain read, as before."""
    d = dest.replace("\\", "/")
    base = d.rstrip("/").rsplit("/", 1)[-1]
    if not (d.endswith("/") or not os.path.splitext(base)[1] or re.search(r"(?:^|/)\.claude/smartuse/projects/[^/]+/?$", d)):
        return False
    d = d.rstrip("/")
    m = pat.search(d + "/" + src.replace("\\", "/").rsplit("/", 1)[-1])
    return bool(m) and (m.start() < len(d) or bool(re.search(r"(?:^|/)\.claude(?:/smartuse(?:/projects/[^/]+)?)?$|(?:^|/)etc/smartuse$", d, re.I)))


def _settings_reader_arg(v, i, wi, pat=None):
    """Is word v[wi] (it names a settings file) a plain argument that only READS it, of the command whose name is v[i]? A reader of
    READERS (not as the value of one of its options, READER_VALUE_OPTS), a git subcommand of GIT_READERS (no --output, no external
    diff), a copy command with the path as a source (not the last word, plain flags only), `python -m json.tool` given that one file."""
    w = v[wi]
    if w.startswith("-"):
        return False   # an option, or an option's value spelled --opt=path
    cmd = base_name(v[i]).lower()
    if cmd == "git":
        k = i + 1
        while k < len(v) and v[k].startswith("-"):
            if v[k] == "-C":
                k += 2
            elif v[k] in GIT_GLOBAL_OK:
                k += 1
            else:
                return False
        # git takes an unambiguous abbreviation of a long option: --ou… is --output (writes the file it is given)
        return k < wi and k < len(v) and v[k] in GIT_READERS and not any(a.startswith(("--ou", "--ext")) for a in v[k + 1:])
    if cmd in COPIERS:
        pos, ended = [], False
        for j in range(i + 1, len(v)):
            a = v[j]
            if not ended and a == "--":
                ended = True
            elif not ended and a.startswith("-") and len(a) > 1:
                if not COPY_FLAGS.fullmatch(a):
                    return False
            else:
                pos.append(j)
        return len(pos) >= 2 and wi in pos and wi != pos[-1] and not (pat is not None and _copy_lands(v[pos[-1]], w, pat))
    if PYFAM.fullmatch(cmd):
        return _json_tool_file(v[i + 1:]) == wi - (i + 1)
    if cmd in READERS:
        if cmd == "rg" and any(a == "--pre" or a.startswith("--pre=") for a in v[i + 1:]):
            return False   # rg runs the program --pre names on each file
        letters, longs = READER_VALUE_OPTS.get(cmd, ("", ()))
        return wi not in _option_values(v, i + 1, letters, "".join(c for c in FLAG_LETTERS if c not in letters), longs)
    return False


def _text_opener(line):
    """Does the opener line of a data heredoc only carry text: one command, `cat` or a text-only command (_text_words), not behind sudo?"""
    toks = _shell_tokens(line)
    if not toks or any(k == "sep" for k, *_ in toks):
        return False
    v = [x[1] for x in toks]
    i = command_start(v)
    if i >= len(v) or any(base_name(w).lower() in ("sudo", "doas") for w in v[:i]):
        return False
    return base_name(v[i]).lower() == "cat" or _text_words(v, i) is not None


def _settings_waived(text, ps, pre, name="settings-file"):
    """The settings-file waiver: True when EVERY place a settings path is named is a case of the list above. `text` is what main() runs
    the other rules on (for Bash the data heredoc bodies are stripped from it), `pre` the command as typed (the rule matched on it).
    `name` is the rule whose pattern says what a "path" is: settings-file, or owner-file (0.7.0 F3, the same waiver for the paid counter).
    Linear: the hits and the words are walked once, side by side."""
    subject = text if ps or pre is None else pre
    if complexity(subject, ps):
        return False
    t = text.replace("\\", "/") if ps else text
    if "\\\n" in t or words(t) is None or "$(" in t or "`" in t or "<(" in t or ">(" in t:
        return False
    pat = re.compile(RULES[RULE_NAMES.index(name)][0], re.I | re.S)
    seen = 0
    if not ps and pre is not None:
        if heredoc_substs(pre):   # bash runs the substitutions in an unquoted heredoc body
            return False
        for m in HEREDOC.finditer(pre):   # the bodies strip_heredocs cut out of `text`: text, when the opener only carries text
            line = opener_line(pre, m)
            if not heredoc_is_code(line) and pat.search(m.group(3)):
                if not _text_opener(line):
                    return False
                seen += 1
    toks = _shell_tokens(t)
    if toks is None:
        return False
    segs, ends = [[]], []
    for kind, val, s, e in toks:
        if kind == "word":
            segs[-1].append((val, s, e))
        else:
            ends.append(val)
            segs.append([])
    ends.append("")
    vals = [[w[0] for w in seg] for seg in segs]
    first = [command_start(v) for v in vals]
    flat = [(w[1], w[2], si, wi) for si, seg in enumerate(segs) for wi, w in enumerate(seg)]
    ptr = [0]
    def token_at(pos):   # (segment, word) of the word that holds position pos, or None; positions come in ascending order
        p = ptr[0]
        while p < len(flat) and flat[p][1] <= pos:
            p += 1
        ptr[0] = p
        return (flat[p][2], flat[p][3]) if p < len(flat) and flat[p][0] <= pos else None
    memo, fed = {}, set()
    for m in pat.finditer(t):
        seen += 1
        tk = token_at(m.start())   # None: the path is in a redirect (its target leaves no word) or a place the words do not hold
        if tk is None:
            return False
        si, wi = tk
        v, i = vals[si], first[si]
        if wi <= i or i >= len(v) or any(base_name(w).lower() in ("sudo", "doas") for w in v[:i]):
            return False
        if si not in memo:
            memo[si] = _text_words(v, i)
        tw = memo[si]
        if not (tw is True or (tw is not None and wi in tw)) and not _settings_reader_arg(v, i, wi, pat):
            return False
        if si not in fed:   # what the command prints (the path may be in it) must not be piped on into anything but a plain filter
            fed.add(si)
            k = si
            while ends[k] in ("|", "|&"):
                k += 1
                if first[k] >= len(vals[k]) or base_name(vals[k][first[k]]).lower() not in SETTINGS_PIPE_OK:
                    return False
    return seen > 0


WAIVER_ERRORS = []   # what a waiver raised, if anything (a test reads it); a waiver that raises waives nothing


def waived(name, text, ps, pre=None):
    """True when `name` is a waivable rule and every match of it in `text` (the text main() runs RULES on; `ps` for the PowerShell
    tool; `pre` the command as typed, which settings-file reads) is an honest command of its class (see above). An error is a no."""
    try:
        return _waived(name, text, ps, pre)
    except Exception as e:
        WAIVER_ERRORS.append(repr(e))
        return False


def _waived(name, text, ps, pre=None):
    """The work of waived. Linear in the text: the matches and the words are walked once, side by side."""
    if name in ("settings-file", "owner-file"):
        return _settings_waived(text, ps, pre, name)
    if name not in WAIVABLE or complexity(text, ps):
        return False
    t = text.replace("\\", "/") if ps else text   # PowerShell has no backslash escape: read as a bash text it would hide a command inside a quote
    if "\\\n" in t or words(t) is None:
        return False
    toks = _shell_tokens(t)
    if toks is None:
        return False
    segs, ends = [[]], []
    for kind, val, s, e in toks:
        if kind == "word":
            segs[-1].append((val, s, e))
        else:
            ends.append(val)
            segs.append([])
    ends.append("")
    vals = [[w[0] for w in seg] for seg in segs]
    first = [command_start(v) for v in vals]
    hits = list(re.finditer(RULES[RULE_NAMES.index(name)][0], t, re.I | re.S))
    if not hits:
        return False
    flat = [(w[1], w[2], si, wi) for si, seg in enumerate(segs) for wi, w in enumerate(seg)]
    ptr = [0]
    def token_at(pos):   # (segment, word) of the word that holds position pos, or None; positions come in ascending order
        p = ptr[0]
        while p < len(flat) and flat[p][1] <= pos:
            p += 1
        ptr[0] = p
        return (flat[p][2], flat[p][3]) if p < len(flat) and flat[p][0] <= pos else None
    if name == "sudo":
        if "$(" in t or "`" in t or "<(" in t or ">(" in t:
            return False
        for si, v in enumerate(vals):
            if any(base_name(w).lower() in ("sudo", "doas") for w in v[:first[si]]):
                return False
            if si and ends[si - 1] in ("|", "|&") and (first[si] >= len(v) or base_name(v[first[si]]).lower() not in PIPE_OK):
                return False
    memo = {}
    for m in hits:
        if name == "sudo":
            tk = token_at(m.start())
            if tk is None:
                return False
            si, wi = tk
            i = first[si]
            if wi <= i or i >= len(vals[si]):
                return False
            if si not in memo:
                memo[si] = _text_words(vals[si], i)
            if memo[si] is None or (memo[si] is not True and wi not in memo[si]):
                return False
        else:
            if m.group(2):   # (sudo\s+)? of the pattern
                return False
            tk = token_at(m.end() - 1)
            if tk is None or tk[1] != 0 or tk[0] == 0 or ends[tk[0] - 1] != "|":
                return False
            si, pj = tk[0], tk[0] - 1
            v = vals[si]
            if not PYFAM.fullmatch(base_name(v[0]).lower()) or not _python_data_module(v[1:]):
                return False
            pv = vals[pj]
            if first[pj] >= len(pv) or base_name(pv[first[pj]]).lower() not in ("curl", "wget") \
                    or not (segs[pj][0][1] <= m.start() < segs[pj][-1][2]):
                return False
            k = si   # what the interpreter prints must not be piped on into a shell: the download would reach it
            while ends[k] in ("|", "|&"):
                k += 1
                if first[k] >= len(vals[k]) or base_name(vals[k][first[k]]).lower() not in PIPE_OK:
                    return False
    return True


# ---- paid calls: per-call billed APIs need the owner's go ------------------------------------------------------------------------
PAID_HOSTS = ("api.openai.com", "api.stability.ai", "api.replicate.com", "fal.run", "generativelanguage.googleapis.com",
              "api.ideogram.ai", "api.anthropic.com")   # whole host names; claude -p / plugin eval / subagents never name them
PAID_KEYS = ("OPENAI_API_KEY", "STABILITY_API_KEY", "STABILITY_KEY", "REPLICATE_API_TOKEN", "FAL_KEY", "FAL_API_KEY", "GEMINI_API_KEY",
             "GOOGLE_API_KEY", "GOOGLE_GENAI_API_KEY", "IDEOGRAM_API_KEY", "ANTHROPIC_API_KEY")   # named, never *_TOKEN / *_API_KEY as a family
PAID_KEY = re.compile(r"(?<!\w)(?:" + "|".join(PAID_KEYS) + r")(?!\w)")
_PAID_PKG = "openai|replicate|fal_client|anthropic"   # the SDKs' import names
PAID_SDK = re.compile(r"\bimport\s+(?:" + _PAID_PKG + r"|google\.generativeai|google\.genai|stability_sdk)\b"
                 r"|\bfrom\s+(?:" + _PAID_PKG + r"|stability_sdk|google\.genai|google\.generativeai)\b|\bfrom\s+google\s+import\s+genai\b"
                 r"|(?:require\(|\bfrom\s+|\bimport\(?)\s*[\"'](?:openai|replicate|@fal-ai/client|@google/genai|@google/generative-ai|@anthropic-ai/sdk)[\"']\)?")
PAID_SDK_WORDS = ("openai", "replicate", "fal_client", "anthropic", "stability_sdk", "genai", "generative", "@fal-ai", "@google/")   # a word every PAID_SDK match holds (lower case): the substring look before the pattern
PAID_MENTION = frozenset("grep egrep fgrep rg ag cat echo printf head tail less more git wc diff ls type".split())   # a host after these is text, not a call
PAID_PREP = frozenset("export unset declare typeset readonly set".split())        # a key NAME after these is preparation; the run that follows is scanned
PAID_INTERP = re.compile(r"python[\d.]*|pythonw|py|node|deno|bun|uv|uvx|npx|tsx|ts-node|bash|sh|zsh|dash|ksh")
PAID_CALLER = re.compile(r"(?:" + PAID_INTERP.pattern + r")|curl|wget|http|xh")
PAID_STDIN_INTERP = re.compile(r"python[\d.]*|pythonw|py|node|deno|bun")
PAID_SCRIPT_EXT = re.compile(r"\.(?:py|pyw|js|mjs|cjs|ts|mts|cts|tsx|jsx|sh|bash)$", re.I)
# One command segment: split on ; & | ( ) newline ` outside quotes (0.7.0 F4b fix: `)` too, so `(python render.py)` and `$(python render.py)`
# name the script, not `render.py)`). LEAD = what may stand before the command word (then / do / exec / VAR=x …; wrappers are WRAP).
PAID_SEG = re.compile(r"""'[^']*'|"(?:\\.|[^"\\])*"|\\.|(?P<sep>[;&|()\n`])|[^'"\\;&|()\n`]+|.""", re.S)
# A command substitution outside single quotes: $( @( <( >( or a backtick. A segment that holds one has its text after the first scanned as segments too.
PAID_SUBST = re.compile(r"[$@<>]\(|`")
# A command that changes the folder (the words only; env -C / --chdir are read in paid_unwrap): the run after it is not the file the guard found.
PAID_CD = re.compile(r"(?:cd|chdir|pushd|popd|sl|set-location|push-location|pop-location)(?:\.\.|[/\\]|$)", re.I)
PAID_CD_WORD = re.compile(r"(?<![\w.-])(?:cd|chdir|pushd|popd|sl|set-location|push-location|pop-location)(?![\w-])", re.I)   # the same words anywhere in the text (a loop may run the cd first)
PAID_ENV_CD = re.compile(r"-[A-Za-z]*C.*|--c(?:h(?:d(?:i(?:r)?)?)?)?(?:=.*)?")                  # env -C dir, -Cdir, --chdir[=dir] and its shortened spellings
PAID_LEAD = re.compile(r"""(?:(?:then|do|else|elif|if|while|until|exec|command|!|\{)\s+|[A-Za-z_]\w*=(?:'[^']*'|"[^"]*"|\S*)\s*)*""")
# Wrappers that run the next command: name -> (options that take a value as the NEXT word, positional words of their own, the
# subcommands that precede the command). `timeout 60 python x.py`, `nice -n 10 …`, `poetry run python x.py`, `pnpm exec tsx x.ts`, `yarn node x.js`.
PAID_WRAP = {"timeout": ("-s -k --signal --kill-after", 1, ""), "nice": ("-n --adjustment", 0, ""), "ionice": ("-c -n -p -P -u --class --classdata", 0, ""),
        "stdbuf": ("-i -o -e --input --output --error", 0, ""), "xargs": ("-n -I -L -P -d -E -s -a --max-args --replace -i", 0, ""),
        "env": ("-u -C -S --unset --chdir --split-string", 0, ""), "caffeinate": ("-t -w", 0, ""), "poetry": ("", 0, "run"), "pipenv": ("", 0, "run"),
        "pnpm": ("-p --package", 0, "exec dlx"), "yarn": ("-p --package", 0, "exec dlx"), "npm": ("-p --package", 0, "exec"), "nohup": ("", 0, ""),
        "sudo": ("-u -g -h -p -C -D -R -T -U -r -t", 0, ""), "time": ("-f -o --format --output", 0, ""),
        "parallel": ("-j -n -N -a -S -L -P --jobs", 0, ""), "watch": ("-n --interval", 0, ""),
        # 0.7.0 review fix M1: the other runners and secret injectors. `pdm run python x.py`, `conda run -n env python x.py`, `op run -- python x.py`
        "pdm": ("", 0, "run"), "hatch": ("-e --env", 0, "run"), "rye": ("", 0, "run"), "pixi": ("-e --environment --manifest-path", 0, "run"),
        "conda": ("-n -p --name --prefix", 0, "run"), "op": ("--env-file --account --session", 0, "run"), "dotenv": ("-f --file", 0, "run"),
        "doppler": ("-p -c --project --config --token -t --config-dir", 0, "run")}
# 0.7.0 review fix round 2: the runner's OWN options before the subcommand (`hatch -e test run python x.py`, `op --account me run -- python x.py`),
# name -> the ones that take a value as the NEXT word; any other -word before the subcommand is one word. A folder flag (pdm -p, poetry -C,
# hatch -p, conda run --cwd) is left out on purpose: that run is in another folder (a stated limit, SECURITY.md).
PAID_PRE = {"hatch": "-e --env --data-dir --cache-dir --config", "dotenv": "-f --file -q --quote -e --export", "op": "--account --config --encoding --format --session",
        "doppler": "-p -c -t --project --config --token --config-dir --api-host --scope --timeout --attempts", "pdm": "-c --config", "poetry": ""}
PAID_REPEAT = frozenset("xargs parallel watch".split())   # these run the command once per input / tick: more than one run in one call
PAID_LOOP_OPEN = re.compile(r"(?:(?:then|do|else|elif|if|!|\{)\s+)*(?:for|while|until|select)\b")   # a segment that opens a loop …
PAID_LOOP_END = re.compile(r"done\b")                                                               # … and the one that closes it
PAID_ARGS = re.compile(r""""([^"]*)"|'([^']*)'|(\S+)""")   # words with the quotes off and no escape handling: a Windows path keeps its backslashes
PAID_GO = re.compile(r"(?P<script>[^\s,]+)\s*(?:x|×|\*)\s*(?P<runs>\d+)\b(?P<rest>.*)", re.I | re.S)   # render.py x 10, cap RM5[, count --n | count none][, test ok]
# 0.7.0 F6, the PowerShell tool. These tables are read only when the event's tool is PowerShell (ps True); a Bash call never sees them. The
# call operator & is a segment separator already (PAID_SEG), so `& python render.py` is the segment `python render.py`.
PAID_PS_CALLER = frozenset("invoke-webrequest invoke-restmethod iwr irm start-bitstransfer".split())   # download cmdlets and their aliases (curl, wget are callers already); a bare paid host beside them is a call
PAID_PS_MENTION = frozenset("get-content gc select-string sls write-host write-output write".split())   # a paid word after these is text, not a call
# a segment that opens a loop: there is no `done` in PowerShell, so a hit after it repeats. F4b fix: the cmdlets that run a script block once per
# item or per event (where-object, switch, jobs, remoting, event actions) join the loops; a script block after a pipe is marked in paid_ps_blocks
PAID_PS_LOOP = re.compile(r"(?:foreach|for|while|until|do|foreach-object|%|where-object|where|\?|switch|invoke-command|icm|start-job|sajb|start-threadjob"
                          r"|register-objectevent|register-engineevent|register-wmievent|register-cimindicationevent)(?![\w.-])", re.I)
PAID_PS_METHOD = re.compile(r"\.(?:foreach|where)\b", re.I)                                               # (1..3).ForEach({ ... }), (1..3).Where({ ... })
PAID_PS_BRACE = re.compile(r"[|;\n{}]")                                                                    # what ends a statement, or opens or closes a script block
PAID_PS_SWITCH = re.compile(r"\s*(?:\$[\w:]+\s*=\s*)?switch(?![\w-])", re.I)                               # a statement that is a switch
PAID_PS_SP_VAL = ("filepath", "argumentlist", "workingdirectory", "redirectstandardinput", "redirectstandardoutput", "redirectstandarderror",
                  "verb", "windowstyle", "credential", "environment")   # the parameters of Start-Process that take a value ...
PAID_PS_SP_SW = ("wait", "nonewwindow", "passthru", "usenewenvironment", "loaduserprofile")   # ... and the switches
PAID_PS_COMMON_VAL = ("erroraction", "warningaction", "informationaction", "progressaction", "errorvariable", "warningvariable", "informationvariable",
                      "outvariable", "outbuffer", "pipelinevariable")   # the common parameters that take a value ...
PAID_PS_COMMON_SW = ("verbose", "debug", "whatif", "confirm")           # ... and the common switches
PAID_PS_ALIAS = {"args": "argumentlist", "path": "filepath", "pspath": "filepath", "ea": "erroraction", "wa": "warningaction", "infa": "informationaction",
                 "proga": "progressaction", "ev": "errorvariable", "wv": "warningvariable", "iv": "informationvariable", "ov": "outvariable",
                 "ob": "outbuffer", "pv": "pipelinevariable", "vb": "verbose", "db": "debug", "wi": "whatif", "cf": "confirm"}
PAID_PS_ALL = PAID_PS_SP_VAL + PAID_PS_SP_SW + PAID_PS_COMMON_VAL + PAID_PS_COMMON_SW
PAID_PS_LIT = re.compile(r"""(?:'[^']*'|"[^"$`()@]*"|[-+]?(?:0x[\da-f]+|\d+(?:\.\d+)?(?:e[-+]?\d+)?|\.\d+)(?:[kmgtp]b|[ld])?|\$(?:[\w:.?]+|\{[^}$`]*\}))""", re.I)   # one literal word on the right of an =: a quoted word (no expansion in "..."), a number, a $variable read ($true, $false, $null too); a bare word is a command in PowerShell and is scanned
PAID_PS_ASSIGN = re.compile(r"(?:\[[^\]]*\]\s*)*\$[\w:.?{}-]+\s*[-+*/%]?=\s*")   # `$x = `, `[int]$x = `, `$env:X = `, `$x += ` at the start of a statement


PAID_COUNT_FLAGS = ("-n", "-N", "--n", "--count", "--num", "--num-images", "--num_images", "--num-outputs", "--num_outputs", "--images",
               "--samples", "--batch", "--batch-size", "--runs", "--iterations")   # "how many outputs this run makes"; `--n 1`, `--n=1`, `-n1`


class PaidHostHit:
    """One host match: what re's match object gives paid_code_signal (start and group)."""
    def __init__(self, s, text):
        self.s, self.text = s, text

    def start(self):
        return self.s

    def group(self, i=0):
        return self.text


class PaidHosts:
    """A whole host name, any subdomain in front (queue.fal.run), nothing glued on either side (fal.runtime.io, notfal.run).
    The same matches as (?<![\\w-])(?:[\\w-]+\\.)*(?:hosts)(?![\\w-]|\\.\\w), found in linear time (V9): that pattern restarts at every label of
    a long dotted run (30 s on 28 KB of `a.a.a.`). Here the host itself is searched, then the subdomain labels are taken from the left."""
    def __init__(self, hosts):
        self.names = tuple(h.lower() for h in hosts)
        self.core = re.compile(r"(?<![\w-])(?:" + "|".join(re.escape(h) for h in hosts) + r")(?![\w-]|\.\w)", re.I)

    def finditer(self, src):
        for m in self.core.finditer(src):
            s = m.start()
            while s > 1 and src[s - 1] == ".":
                k = s - 1
                while k > 0 and (src[k - 1].isalnum() or src[k - 1] in "_-"):
                    k -= 1
                if k == s - 1:
                    break
                s = k
            yield PaidHostHit(s, src[s:m.end()])


def paid_host_re(hosts):
    return PaidHosts(hosts)


PAID_HOST = paid_host_re(PAID_HOSTS)


# (the block's own native_path and adapter_list are not carried over: the fresh-source gate's (above) are used)
def fit_key(full, base, nt):
    """The state-dir name to use for the project key `full` (the whole resolved path, as project_key() has always built it), under `base`
    (<HOME>/.claude/smartuse/projects); nt = os.name == "nt". `full` itself while the folder and its longest file name fit (a whole path may hold
    259 characters on Windows, E1; one name 255 elsewhere), else the last 40 characters of it, "-", and 12 hex of the sha1 of the whole key. A folder
    that already exists under the full key is kept while a file fits in it (D7a). Reads folder names only. Never raises: any error returns `full`.
    The same text is copied into heartbeat.py, ledger.py, recall.py, until-done.py, wait-gate.py and bash-guard.py (the tests assert it equal)."""
    try:
        import hashlib   # inside the function: no new top-level import
        WIN_PATH_MAX = 259   # the longest whole file path on Windows without long-path support (MAX_PATH 260 with its NUL, measured by E1)
        NAME_ROOM = 64       # the longest fixed file name in the folder (paid.<tool_use_id>.<8>.done, 49) plus room
        KEPT_ROOM = 26       # status.json.<pid>.tmp with a 10-digit pid: the longest name a hook writes in a folder that already exists
        KEY_MAX = 255        # one name on Linux and macOS (the key is ASCII, so characters = bytes)
        TAIL = 40            # characters of the full key kept in the short key
        HASH = 12            # hex digits of the sha1 of the whole key
        short = full[-TAIL:].lstrip("-") + "-" + hashlib.sha1(full.encode()).hexdigest()[:HASH]
        dirlen = len(base) + 1 + len(full)
        have = os.path.isdir(base + os.sep + full)
        if nt and have and dirlen + 1 + KEPT_ROOM <= WIN_PATH_MAX:
            return full
        if not nt and have:
            return full
        if len(full) > KEY_MAX:
            return short
        if nt and dirlen + 1 + NAME_ROOM > WIN_PATH_MAX:
            return short
        return full
    except Exception:
        return full


def paid_project_key(project):
    """The state-dir name of a project (copy of ledger.py's rule, asserted equal by paid-guard-test.sh): the full resolved path,
    every character outside [A-Za-z0-9._-] -> "-", a leading "-" dropped, then shortened by fit_key() when the folder would not hold its files (0.7.1).
    This file imports no other hook."""
    import pathlib   # inside the paid path only (V9): no new top-level import
    full = re.sub(r"[^A-Za-z0-9._-]", "-", str(pathlib.Path(project).resolve())).lstrip("-") or "root"
    return fit_key(full, str(paid_home() / ".claude" / "smartuse" / "projects"), os.name == "nt")


def paid_write_json(path, obj):
    """Atomic (copy of ledger.py's): tmp file + os.replace, 5 tries 20 ms apart on Windows; True when written. Never raises."""
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    try:
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


def paid_segments(text, keep=False):
    """The command's segments (quote-aware), each stripped; empty ones dropped. keep: a segment that ends at a backtick or ( keeps it
    (the arguments of `x --n 1 $(…)` / `<(…)` / `…` are not what they look like)."""
    out, cur = [], []
    for m in PAID_SEG.finditer(text):
        if m.group("sep"):
            out.append("".join(cur) + (m.group("sep") if keep and m.group("sep") in "`(" else "")); cur = []
        else:
            cur.append(m.group(0))
    out.append("".join(cur))
    return [s.strip() for s in out if s.strip()]


def paid_basename(p):
    return re.split(r"[\\/]", p)[-1]


def paid_code_signal(src, hosts, caller, keys=True):
    """The first paid signal in a piece of text as "host api.openai.com" / "OPENAI_API_KEY" / "import openai", else None. A bare
    host counts only where something that calls (curl, an interpreter, the script itself) holds it, or when it is a URL."""
    low = src.lower()   # V9: plain substring looks first; a text with no paid word at all (a big script) never reaches the patterns below
    if not (any(h in low for h in hosts.names) or any(k in src for k in PAID_KEYS) or any(w in low for w in PAID_SDK_WORDS)):
        return None
    for m in hosts.finditer(src):
        if caller or re.search(r"(?:https?|wss?)://$", src[max(0, m.start() - 8):m.start()]):
            return "host " + m.group(0).lower()
    m = PAID_KEY.search(src) if keys else None
    if m:
        return m.group(0)
    m = PAID_SDK.search(src) if caller else None
    return re.sub(r"\s+", " ", m.group(0)) if m else None


def paid_script_arg(cmd, toks):
    """The script file this line runs: the first word with a script extension after an interpreter (none when -c / -m / -e comes
    first — inline code or a module, nothing to open), or the command word itself (./render.py)."""
    if not PAID_INTERP.fullmatch(cmd):
        return toks[0] if PAID_SCRIPT_EXT.search(toks[0].rstrip("`")) else None   # a closing backtick of `python x.py` stays on the segment's last word (paid_segments keep)
    for t in toks[1:]:
        if t in ("-c", "-m", "-e", "-p", "--eval", "--print"):
            return None
        if not t.startswith("-") and PAID_SCRIPT_EXT.search(t.rstrip("`")):
            return t
    return None


PAID_LOOK_WORDS, PAID_LOOK_DIRS, PAID_LOOK_STATS = 64, 6, 2000   # F4b step 1 (V9): the words looked at before a script word, the folders kept, the file system probes (isdir, isfile, open) one command may make beyond the cwd's own file


def paid_script_files(tok, cwd, dirs=(), cfg=None):
    """The files a script word may be, as paths: [] when the guard cannot see one (a $f, `…` or glob in the word, a missing file).
    A relative word is joined to the event's cwd (that file comes first, as before step 1) and to each folder in dirs (paid_folders,
    F4b step 1, D-YK13); an absolute one stays itself. The callers read every file of the list and take a signal in any of them. With
    a cfg a path is asked of the file system once per command, and a probe in a folder of dirs counts against the cap and the
    deadline (cfg.probe): when it is refused the lookup stops and cfg.cut says so."""
    if re.search(r"[$`*?]", tok):
        return []
    w = native_path(os.path.expanduser(tok))
    out, seen = [], set()
    for i, base in enumerate((cwd,) + tuple(dirs)):
        p = os.path.join(base, w)                                   # an absolute path stays itself
        k = os.path.normcase(os.path.abspath(p))
        if k in seen:
            continue
        seen.add(k)
        r = cfg.filecache.get(k) if cfg else None
        if r is None:
            if i and cfg and not cfg.probe():
                break
            try:
                r = os.path.isfile(p)
            except OSError:
                r = False
            if cfg:
                cfg.filecache[k] = r
        if r:
            out.append(p)
        if os.path.isabs(w):
            break
    return out


def paid_word_path(w):
    """The path a plain word may name, as the file system reads it, or "" when the word names none the guard follows: a word with a
    $, `, glob character, = or { }, a script file, `-` or `.`. `--opt=value` gives its value, and so does the PowerShell
    `-Path:value` / `-LiteralPath:value` / `-PSPath:value` (any shortened parameter name, and `-LP`), and `env -Cvalue`; a quoted value has its quotes taken off; `~` is expanded."""
    v = w
    if w[:2] == "--":
        v = w.partition("=")[2]
    elif w[:2] == "-C" and len(w) > 2:                              # env -Cdir: the value is attached
        v = w[2:]
    elif w[:1] == "-":
        n, c, x = w[1:].partition(":")
        n = n.lower()
        v = x if c and n and ("path".startswith(n) or "literalpath".startswith(n) or n == "lp" or (n[:2] == "ps" and "pspath".startswith(n))) else ""
    v = v.strip("'\"")
    if not v or v[0] == "-" or v == "." or len(v) > 255 or re.search(r"[$`*?=\[\]{}<>]", v) or PAID_SCRIPT_EXT.search(v):
        return ""
    return native_path(os.path.expanduser(v))


def paid_folders(cfg, words, cwd):
    """The folders a run's earlier words name (F4b step 1, V17): [paths], the nearest last, at most PAID_LOOK_DIRS. Only the last
    PAID_LOOK_WORDS words are looked at, and only the named paths are looked at (never a folder listed); each probe counts against
    the cap and the deadline (cfg.probe), and when one is refused the look stops and cfg.cut says so. A plain word is one that
    paid_word_path accepts. Folders chain in command order: a word is looked for under the folder the one before it named, then under
    the cwd. A folder from a variable, a substitution or a glob, a folder the command makes, and `cd -` are not followed (stated limits)."""
    if cfg.deadline is not None and time.monotonic() >= cfg.deadline:   # V8: past the hook's deadline no run looks any further (a run that needs a lookup is unreadable)
        cfg.cut = True
        return []
    out, last = [], cwd
    for w in words[-PAID_LOOK_WORDS:]:
        c = cfg.wordcache.get(w)                                    # a word is judged once, however many runs look back at it
        if c is None:
            c = cfg.wordcache[w] = paid_word_path(w)
        if not c:
            continue
        for base in ((last, cwd) if last != cwd else (cwd,)):
            p = os.path.join(base, c)
            d = cfg.dircache.get(p)
            if d is None:
                if not cfg.probe():
                    return out[-PAID_LOOK_DIRS:]
                try:
                    d = os.path.isdir(p)
                except (OSError, ValueError):
                    d = False
                cfg.dircache[p] = d
            if d:
                out = [x for x in out if x != p] + [p]
                last = p
                break
    return out[-PAID_LOOK_DIRS:]


def paid_read_file(p):
    """The first 256 KB of a file (UTF-8, bad bytes replaced), whatever its size, or None when it cannot be read. What lies beyond
    256 KB is never read (a stated limit)."""
    try:
        with open(p, "rb") as fh:
            return fh.read(262144).decode("utf-8", "replace")
    except OSError:
        return None


PAID_UNREAD = "a script that could not be read"   # the signal of a hit for a script file that exists and could not be opened (strict only; paid_verdict turns it into "could not verify")
PAID_FLAG = re.compile(r"--[A-Za-z0-9_-]+")   # a flag of paid_free: and of `only`: two dashes, then letters, digits, - or _


def paid_glob(pat, s):
    """`*` and `?` against one path part, nothing else is special. No regex is built per item (V9: 2,000 items must stay cheap), and
    a part longer than any file name never matches (the work is its length times the pattern's)."""
    if len(s) > 255:
        return False
    i = j = mark = 0
    star = -1
    while i < len(s):
        if j < len(pat) and pat[j] == "*":
            star, mark, j = j, i, j + 1
        elif j < len(pat) and (pat[j] == "?" or pat[j] == s[i]):
            i += 1
            j += 1
        elif star >= 0:
            mark += 1
            i, j = mark, star + 1
        else:
            return False
    while j < len(pat) and pat[j] == "*":
        j += 1
    return j == len(pat)


def paid_parts(spec):
    """(parts, climbs, absolute) of one path spec of the adapter: a \\ is read as /, empty and `.` parts are dropped."""
    s = spec.replace("\\", "/")
    parts = [p for p in s.split("/") if p not in ("", ".")]
    return parts, ".." in parts, s.startswith(("/", "~")) or bool(re.match(r"[A-Za-z]:", s))


def paid_rel(p, base):
    """p relative to base with / between parts, or None when p lies outside base (or on another drive)."""
    try:
        r = os.path.relpath(p, base).replace("\\", "/")
    except ValueError:
        return None
    return None if r in (".", "..") or r.startswith("../") or r.startswith("/") or re.match(r"[A-Za-z]:", r) else r


def paid_gentry(parts, flags):
    """A pattern item with its cheap look-ahead: the literal text before its first * / ? and after its last, of the whole path and of
    its last part (a start / end test in C rules most items out before the part-by-part match)."""
    j = "/".join(parts)
    k = [m.start() for m in re.finditer(r"[*?]", j)]
    last = parts[-1]
    lk = [m.start() for m in re.finditer(r"[*?]", last)]
    return (parts, flags, j[:k[0]], j[k[-1] + 1:], last[:lk[0]] if lk else last, last[lk[-1] + 1:] if lk else last)


class PaidCfg:
    """What the adapter says about scripts, read once per command (F4b): the `paid_scripts:` items (a file name, or a project-relative
    path or pattern, each with the flags of its `only`), the `paid_free:` items (flags and path patterns) and the names the go lines
    cover. blind (V10): the command is not read cleanly, so no run is free."""
    def __init__(self, adapter, project, blind=False):
        self.project, self.blind, self.base = project, blind, None
        self.strict = False                                     # paid_hit sets it: strict reads a script that cannot be opened as "could not verify" (m7)
        self.moved, self.cd_any = False, False                  # a folder change was seen before this run (paid_seg_hits sets it); a cd word is anywhere in the command (paid_hit sets it)
        self.words, self.dircache, self.wordcache, self.filecache, self.srccache = [], {}, {}, {}, {}   # F4b step 1: the last words of the segments scanned so far (handed down into a bash -c string), and what the file system said about a word, a folder, a file and a script's source (asked once per command)
        self.probes, self.cut, self.deadline = 0, False, None    # the probes made beyond the cwd's own file; a lookup of this run was refused by the cap or the deadline; the hook's deadline (paid_hit sets it)
        self.ci = os.name == "nt" or sys.platform == "darwin"   # the file system's case rule, for the paid_free: paths
        self.names, self.paths, self.pnames = {}, {}, {}        # literal items: file name / project-relative path / file name of a path item -> [flags or None]
        self.gnames, self.gpaths = [], []                       # items with * or ?: paid_gentry
        self.go = {paid_basename(g["script"]).lower() for g in map(paid_parse_go, paid_lines(adapter)) if g}   # a script with a go is a paid script
        for item in adapter_list(adapter, "paid_scripts"):
            self.add_item(item)
        self.free_flags, self.free_paths = set(), []
        for item in adapter_list(adapter, "paid_free"):
            if item.startswith("-"):
                if PAID_FLAG.fullmatch(item):                   # a single-dash item is ignored
                    self.free_flags.add(item)
                continue
            parts, climbs, absolute = paid_parts(item)
            if parts and not climbs and not absolute:           # an absolute or climbing item is ignored
                self.free_paths.append([p.lower() if self.ci else p for p in parts])

    def probe(self):
        """One more file system probe for the folder lookup (F4b step 1), or False when the cap (PAID_LOOK_STATS) is spent or the hook's
        deadline has passed: then cut is set and the run that asked is unreadable (strict denies it, light allows, as m7)."""
        if self.probes >= PAID_LOOK_STATS or (self.deadline is not None and time.monotonic() >= self.deadline):
            self.cut = True
            return False
        self.probes += 1
        return True

    def read(self, f, counted):
        """The first 256 KB of a script (paid_read_file), once per command; a read of a file found in another folder (counted) counts
        against the probe cap and the deadline, and is None (could not be read) when refused."""
        if f in self.srccache:
            return self.srccache[f]
        if counted and not self.probe():
            return None
        self.srccache[f] = src = paid_read_file(f)
        return src

    def add_item(self, item):
        """One `paid_scripts:` item: `<script>` or `<script> only <flag> [<flag> ...]`. An item that does not parse makes its first
        word a script that is paid on every run."""
        w = item.split()
        flags = tuple(w[2:]) if len(w) >= 3 and w[1].lower() == "only" and all(PAID_FLAG.fullmatch(f) for f in w[2:]) else None
        parts, climbs, absolute = paid_parts(w[0])
        if not parts:
            return
        low = [p.lower() for p in parts]
        wild = any(c in w[0] for c in "*?")
        if "/" in w[0].replace("\\", "/") and not climbs and not absolute:   # a project-relative path or pattern
            if wild:
                self.gpaths.append(paid_gentry(low, flags))
            else:
                self.paths.setdefault("/".join(low), []).append(flags)
                self.pnames.setdefault(low[-1], []).append(flags)
        elif wild:                                                          # a file name with a pattern; an absolute or climbing item is read by its file name alone
            self.gnames.append(paid_gentry(low[-1:], flags))
        else:
            self.names.setdefault(low[-1], []).append(flags)

    def rels(self, p):
        """(as written, resolved) project-relative paths of a file found, each None when it lies outside the project."""
        if self.base is None:
            b = os.path.abspath(native_path(self.project))
            self.base = (b, os.path.realpath(b))
        return paid_rel(os.path.abspath(p), self.base[0]), paid_rel(os.path.realpath(p), self.base[1])

    @staticmethod
    def gmatch(e, parts, joined):
        return joined.startswith(e[2]) and joined.endswith(e[3]) and len(e[0]) == len(parts) and all(paid_glob(a, b) for a, b in zip(e[0], parts))

    def script_items(self, name, files):
        """The flags (a tuple, None for an item with no `only`) of every paid_scripts: item that matches this run of a script, [] when
        none does. name: the file name of the script word; files: the files found for it. A file-name item matches in any folder and
        any case. A path item is compared with the project-relative path of each file found, as written and resolved, in any case;
        a script not found, or outside the project, is matched by its file name alone."""
        low = name.lower()
        out = list(self.names.get(low, ()))
        out += [e[1] for e in self.gnames if self.gmatch(e, [low], low)]
        if self.paths or self.gpaths:
            rels = {r.lower() for p in files for r in self.rels(p) if r}
            if rels:
                for r in rels:
                    out += self.paths.get(r, ())
                    parts = r.split("/")
                    out += [e[1] for e in self.gpaths if self.gmatch(e, parts, r)]
            else:
                out += self.pnames.get(low, ())
                out += [e[1] for e in self.gpaths if low.startswith(e[4]) and low.endswith(e[5]) and paid_glob(e[0][-1], low)]
        return out

    def free_file(self, p):
        """True when this found file, as written and resolved (links followed), lies inside the project and matches a paid_free: path."""
        w, r = self.rels(p)
        if not w or not r:
            return False
        for rel in (w, r):
            parts = (rel.lower() if self.ci else rel).split("/")
            if not any(len(pat) == len(parts) and all(paid_glob(a, b) for a, b in zip(pat, parts)) for pat in self.free_paths):
                return False
        return True


def paid_flag_present(args, flags, odd=()):
    """True when the pay flag of an `only` item may be on the command line: a plain argument equal to a flag, the flag with =value, or
    a shortened start of it that a parser accepts (--pa for --pay); or any argument that is not a plain literal (F4b fix: a backslash,
    a quote that is not the one outer pair, or quoted text glued to other text is not plain either; `odd` marks the glued ones)."""
    starts = {f[:k] for f in flags for k in range(3, len(f) + 1)}
    for i, t in enumerate(args):
        if paid_not_plain(t) or paid_quirky(t) or (i < len(odd) and odd[i]):
            return True
        u = paid_unq(t)
        if u.startswith("--") and len(u) > 2 and u.split("=", 1)[0] in starts:
            return True
    return False


PAID_FREE_VALUES = ("1", "true", "yes")   # the only values that keep a free flag free: --dry-run=1, =true, =yes (any case)


def paid_run_free(cfg, args, items, files, golisted, odd=(), ext=False, moved=False):
    """True when this one run of a paid script is free (the order of paid-guard-plan 8.4 F4b): a free flag among plain literal
    arguments, before any bare --, as the bare word or with =1 / =true / =yes; else `only` (every matching item has it: free when no
    flag is there, and the arguments come from this command line: under xargs / parallel / watch, `ext`, the run is paid); else a free
    path (at least one file found, every file found inside the project and matching as written and resolved; never for a script that a
    paid_scripts: item lists or a go names, and not when `moved`: the caller sets it after a folder change when the file under the cwd
    was found, which may not be the file that runs). args: the raw words after the script word; odd: which of them are glued to other text."""
    if cfg.free_flags and not any(paid_not_plain(t) for t in args):
        for i, t in enumerate(args):
            u = paid_unq(t)
            if u == "--":
                break
            if paid_quirky(t) or (i < len(odd) and odd[i]):   # not a plain word: never a flag; one that reads as a bare -- ends the look
                if re.sub(r"[\\'\"]", "", t) == "--":
                    break
                continue
            name, eq, val = u.partition("=")
            if name in cfg.free_flags and (not eq or val.lower() in PAID_FREE_VALUES):
                return True
    if items:
        return not ext and all(fl is not None for fl in items) and not paid_flag_present(args, {f for fl in items for f in fl}, odd)
    return bool(files) and not golisted and not moved and bool(cfg.free_paths) and all(cfg.free_file(p) for p in files)


def paid_stdin_bodies(cmd):
    """[(interpreter, body)] for each heredoc an interpreter reads as code (python3 - <<EOF, node - <<EOF, cat <<EOF | python3 -):
    bodies the data-heredoc strip hides. A shell reading the body is code already and stays in the stripped text."""
    out = []
    for m in HEREDOC.finditer(cmd):
        line = opener_line(cmd, m)
        toks = words(line)
        if toks is None or heredoc_is_code(line):
            continue
        for i, (kind, w) in enumerate(toks):
            name = re.sub(r"\.exe$", "", paid_basename(w).lower())
            if kind != "word" or not PAID_STDIN_INTERP.fullmatch(name):
                continue
            args = []
            for k, a in toks[i + 1:]:
                if k == "sep":
                    break
                args.append(a)
            if next((a for a in args if a == "-" or not a.startswith("-")), None) in (None, "-"):   # no script: stdin is the code
                out.append((name, m.group(3)))
                break
    return out


def paid_unwrap(toks):
    """(toks with the wrapper commands and their own options / arguments skipped, True when a repeater (xargs, parallel, watch) was
    among them, True when env changed the folder (-C / --chdir)): `timeout 60 python x.py` -> python x.py. WRAP says what each wrapper
    takes; an unknown wrapper stays the command."""
    rep, cd = False, False
    while toks:
        name = re.sub(r"\.exe$", "", paid_basename(toks[0]).lower())
        if name not in PAID_WRAP:
            break
        vopts, npos, subs = PAID_WRAP[name][0].split(), PAID_WRAP[name][1], PAID_WRAP[name][2].split()
        rep = rep or name in PAID_REPEAT
        i = 1
        if subs:
            j = 1
            if name in PAID_PRE:                                      # the runner's own options (and their values) before the subcommand
                pv = PAID_PRE[name].split()
                while j < len(toks) and len(toks[j]) > 1 and toks[j][0] == "-" and toks[j] != "--":
                    j += 2 if toks[j] in pv else 1
            if j < len(toks) and toks[j] in subs:
                i = j + 1
            elif j == 1 and len(toks) > 1 and PAID_INTERP.fullmatch(toks[1]):   # yarn node x.js: the interpreter stays
                toks = toks[1:]
                continue
            else:
                break
        while i < len(toks):
            t = toks[i]
            if t == "--":
                i += 1
                break
            if len(t) > 1 and t[0] == "-":
                cd = cd or (name == "env" and bool(PAID_ENV_CD.fullmatch(t)))
                i += 2 if t in vopts else 1                       # an attached value (-oL, -n10, --signal=KILL) is one word
            elif name == "env" and re.match(r"[A-Za-z_]\w*=", t):
                i += 1
            elif npos:
                npos -= 1
                i += 1
            else:
                break
        toks = toks[i:]
        if name == "hatch" and toks and re.match(r"[\w.-]+:[\w./-]", toks[0]):   # hatch run test:python x.py: the environment name is not the command
            toks = [toks[0].split(":", 1)[1]] + toks[1:]
    return toks, rep, cd


def paid_ps_opt(w):
    """(parameter, takes a value) when the bare word w names a Start-Process parameter or a common parameter (any case, -name:value, an
    alias, or a start of the name of any length that only one parameter has: PowerShell binds the same way), (None, False) for a word
    that starts like a parameter and names none (unknown or ambiguous: the caller fails closed), None for a word that is not one (a
    quoted word, a -- word, a number such as -1)."""
    if w[:1] != "-" or w[:2] == "--" or w[1:2].isdigit():
        return None
    name = w[1:].partition(":")[0].lower()
    full = PAID_PS_ALIAS.get(name)
    if full is None and name:
        hit = [f for f in PAID_PS_ALL if f.startswith(name)] if name not in PAID_PS_ALL else [name]
        full = hit[0] if len(hit) == 1 else None
    return (full, full in PAID_PS_SP_VAL + PAID_PS_COMMON_VAL) if full else (None, False)


def paid_ps_start(seg):
    """A Start-Process statement as the command it runs: `Start-Process python -ArgumentList "render.py --n 1"` -> `python render.py --n 1`
    (a statement whose first word is Start-Process, saps or start; any other segment comes back as it was). The program is -FilePath or the
    first plain word; the arguments are -ArgumentList's words (to the next parameter) and any later plain word; the other parameters and
    their values are dropped. An ArgumentList string with blanks in it is split into words again, so the count rule and the free flags
    read what the program is given. With no program, a parameter the guard does not know, or a program that starts with - the segment is
    returned unchanged (paid_seg_hits then fails closed on it when it holds an interpreter or a script word)."""
    ws = [m.group(0) for m in PAID_ARGS.finditer(seg)]
    if not ws or ws[0].lower() not in START_PROCESS:
        return seg
    fp, al, cur = None, [], None
    for w in ws[1:]:
        o = paid_ps_opt(w)
        if o and o[0] is None:
            return seg
        ctx, val = cur, w
        if o:
            ctx, val = o[0], w[1:].partition(":")[2]
            cur = o[0] if o[1] and not val else None
            if not val:
                continue
        if ctx == "filepath":
            fp, cur = val, None
        elif ctx == "argumentlist":
            al.append(val)                        # stays open: the commas of an array are blanks by now
        elif ctx is None:
            if fp is None:
                fp = val
            else:
                al.append(val)
        else:
            cur = None                            # the value of another parameter
    if fp is None or fp[:1] == "-":
        return seg
    words = [fp]
    for a in al:
        u = paid_unq(a)
        words += [m.group(0) for m in PAID_ARGS.finditer(u)] if re.search(r"\s", u) else [a]
    return " ".join(words)


def paid_ps_text(text):
    """The text of a PowerShell call as the paid scan reads it (F6). A backslash is a path separator there, not an escape: left in, the
    segment splitter would take \\; and \\& as escaped and join two commands, and a script word would not name its file off Windows. A
    Start-Process statement is then rewritten as the command it runs (paid_ps_start), so the run, its count rule and its loop are read as
    for Bash. Linear; a text with no Start-Process word is only the one replace (V9)."""
    text = text.replace("\\", "/")
    if not PS_START_WORD.search(text):
        return text
    return ";".join(paid_ps_start(s) for s in paid_segments(text, True))


def paid_ps_blocks(raw):
    """The raw PowerShell command with a `foreach` statement put after each `{` that follows a pipe, or a switch, in its statement
    (`1..3 | Sort-Object { python render.py }`, `switch (1) { 1 { ... } }`): a script block there runs once per item or per match,
    whatever the cmdlet is, and ps_text turns the marker into the loop word the scan already knows. Linear; the caller looks only at
    a command that holds a {."""
    out, last, start, piped = [], 0, 0, False
    for m in PAID_PS_BRACE.finditer(raw):
        c, i = m.group(0), m.start()
        if c == "|":
            piped = True
            continue
        if c == "{" and (piped or PAID_PS_SWITCH.match(raw, start, i)):
            out.append(raw[last:i + 1])
            out.append(" foreach ; ")
            last = i + 1
        start, piped = i + 1, False
    out.append(raw[last:])
    return "".join(out)


def paid_subst_body(seg):
    """The text after the first command substitution of a segment that is not inside 'single quotes' ($( @( <( >( or a backtick, in
    a bare or "double-quoted" word), else None: bash and PowerShell run what is in it, and the segment splitter keeps a double-quoted
    word whole, so the body is scanned as segments of its own."""
    for m in PAID_SEG.finditer(seg):
        t = m.group(0)
        if t[0] != "'":
            k = PAID_SUBST.search(t)
            if k:
                return seg[m.start() + k.end():]
    return None


def paid_inner(text, hosts, cwd, cfg, depth, loop, ps, ext):
    """The hits of a text that sits inside a segment (a substitution body, what an assignment gives a variable): scanned as segments of
    their own, three levels deep. Deeper, a text that holds a paid word is a hit no go can cover (script None)."""
    if depth < 3:
        return paid_scan(paid_segments(text, True), hosts, cwd, cfg, depth + 1, loop, ps, ext)
    return [("a paid word nested too deep in a command that is not read cleanly", None, False)] if PAID_FIRST.search(text) else []


def paid_seg_hits(seg, hosts, cwd, cfg, depth=0, loop=False, ps=False, ext=False):
    """[(signal, script, repeats)] for one command segment: the segment itself (paid_seg_run), then the text inside its command
    substitutions (a mention or a double-quoted word does not hide them), then, in PowerShell, what a `$x = …` gives the variable
    unless it is one literal word (`$env:KEY = 'x'` is the one preparation)."""
    out = paid_seg_run(seg, hosts, cwd, cfg, depth, loop, ps, ext)
    if PAID_SUBST.search(seg):
        sub = paid_subst_body(seg)
        if sub:
            out = out + paid_inner(sub, hosts, cwd, cfg, depth, loop, ps, ext)
    if ps and "=" in seg:
        body = seg[PAID_LEAD.match(seg).end():]
        m = PAID_PS_ASSIGN.match(body)
        rest = body[m.end():].strip() if m else ""
        if rest and not PAID_PS_LIT.fullmatch(rest):
            out = out + paid_inner(paid_ps_start(rest), hosts, cwd, cfg, depth, loop, ps, ext)
    return out


def paid_seg_run(seg, hosts, cwd, cfg, depth, loop, ps, ext):
    """The hits of one command segment alone: layer 1 (the segment's own text), layer 2 (the script file it runs) unless
    layer 1 hit, and every hit inside a bash -c string. repeats = it sits in a loop or runs under xargs / parallel / watch. A run of a
    paid script that is free (cfg, F4b) is no hit: it comes back as (None, script, False, its raw arguments) for paid_finish. ps: the
    PowerShell tool (F6): the cmdlets that call (PAID_PS_CALLER), the mentions (PAID_PS_MENTION) and `$env:KEY = …` as preparation.
    ext: the arguments come from outside the command line (a repeater, xargs / parallel / watch, is above this run)."""
    ms = list(PAID_ARGS.finditer(seg[PAID_LEAD.match(seg).end():]))
    vals = [next(g for g in a.groups() if g is not None) for a in ms]
    prev, cfg.words = cfg.words, (cfg.words + vals)[-PAID_LOOK_WORDS:]   # F4b step 1: the words before this segment, and the words a later segment (or a bash -c string of this one) looks back at
    toks, rep, cdw = paid_unwrap(vals)
    if not toks:
        return []
    raws = [a.group(0) for a in ms][len(ms) - len(toks):]   # the same words with their quotes, aligned with toks
    cmd = re.sub(r"\.exe$", "", paid_basename(toks[0]).lower())
    c0 = toks[1] if toks[0].lower() == "builtin" and len(toks) > 1 else toks[0]
    if cdw or PAID_CD.match(c0):                            # F4b fix: after a folder change the file the guard finds is not the one that runs
        cfg.moved = True
    if cmd in PAID_MENTION or (ps and cmd in PAID_PS_MENTION):
        return []
    if ps and cmd in START_PROCESS and PAID_FIRST.search(seg):   # a Start-Process the parser could not read (paid_ps_start left it as it was)
        return [("a Start-Process that is not read in a command that is not read cleanly", None, False)]
    moved = cfg.moved or (loop and cfg.cd_any)
    ext, rep, out = ext or rep, rep or loop, []
    sig = paid_code_signal(seg, hosts, bool(PAID_CALLER.fullmatch(cmd)) or (ps and cmd in PAID_PS_CALLER),
                           cmd not in PAID_PREP and not (ps and toks[0][:5].lower() == "$env:"))   # not cmd: its base name stops at a / in the value
    path = None if sig else paid_script_arg(cmd, toks)
    if sig in PAID_KEYS and not paid_code_signal(" ".join(raws), hosts, bool(PAID_CALLER.fullmatch(cmd)) or (ps and cmd in PAID_PS_CALLER), True):
        # 0.7.0 review fix m5: the key stands only in front of the command (KEY=x python render.py, env KEY=x ...): preparation. It still makes the run
        # paid, but the hit is the script the command runs, so a go for that script covers it (was: the interpreter's name, which no go can name)
        sp = paid_script_arg(cmd, toks)
        out.append((sig + " on the command line", paid_basename(sp.rstrip("`")) if sp else cmd, rep))
    elif sig:
        out.append((sig + " on the command line", cmd, rep))
    if path:
        name = paid_basename(path.rstrip("`"))
        ci, pi = len(ms) - len(toks), toks.index(path)                  # the place of the command word among the words, and of the script word among toks
        dirs, cfg.cut = (), False
        if not os.path.isabs(native_path(os.path.expanduser(path.rstrip("`")))):   # F4b step 1 (V17): nothing is looked up until a relative script word is seen; then the folders the words before it name (the command word is not one)
            dirs = paid_folders(cfg, prev + vals[:ci] + vals[ci + 1:ci + pi], cwd)
        files = paid_script_files(path.rstrip("`"), cwd, dirs, cfg)
        own = paid_script_files(path.rstrip("`"), cwd, (), cfg) if dirs and files else files   # the file under the cwd alone (the one a script word meant before step 1)
        sig, unread, sigfiles = None, False, []
        for f in files:                                                 # a signal in any file found makes the run paid; every file is read, so every file that holds one is known
            src = cfg.read(f, f not in own)
            fs = paid_code_signal(src, hosts, True) if src else None
            if fs:
                sig = sig or fs
                sigfiles.append(f)
            else:
                unread = unread or src is None                          # the file exists and could not be opened (an empty file reads as "")
        unread = unread or cfg.cut                                      # F4b step 1: a lookup that the probe cap or the deadline cut short is no "no signal": the run is unreadable (strict denies, light allows, as m7)
        items = cfg.script_items(name, files)                           # a path item against every file found (a file name item in any folder); by file name alone only when no file in the project was found
        items_paid = cfg.script_items(name, []) if moved else items     # after a folder change the file under the cwd may not be the one that runs: the item is also read by file name, for paid
        if cfg.cut:                                                     # the file list is incomplete: no `only` freedom (and no free path, below)
            items_free = []
        elif sigfiles:                                                  # `only` freedom needs every file that holds a signal to be covered by an item (a path item covers its own file only)
            per = [cfg.script_items(name, [f]) for f in sigfiles]
            items_free = [] if any(not x for x in per) else [fl for x in per for fl in x]
        else:
            items_free = items if not moved else items_paid
        golisted = name.lower() in cfg.go
        if unread and not sig and cfg.strict:                            # 0.7.0 review fix m7: a script that cannot be read is not "no signal" in strict (light allows, as before)
            out.append((PAID_UNREAD, name, rep))
        elif sig or items_paid or golisted:
            k = toks.index(path) + 1
            args = raws[k:]
            base = len(ms) - len(toks) + k                               # the index of the first argument among the words with their places
            odd = [bool((base + j > 0 and ms[base + j - 1].end() == ms[base + j].start()) or (base + j + 1 < len(ms) and ms[base + j].end() == ms[base + j + 1].start()))
                   for j in range(len(args))]                            # quoted text glued to other text is one word to the shell, two to the splitter
            if not cfg.blind and paid_run_free(cfg, args, items_free, files, golisted or bool(items_paid) or cfg.cut, odd, ext, moved and bool(own)):
                out.append((None, name, False, tuple(args)))
            else:
                out.append((f"{sig} in {name}" if sig else f"{name} is in paid_scripts", name, rep))
    if depth < 2 and cmd in ("bash", "sh", "zsh", "dash", "ksh") and "-c" in toks[1:-1]:   # bash -c "python render.py": judge the string too
        out += paid_scan(paid_segments(toks[toks.index("-c") + 1], True), hosts, cwd, cfg, depth + 1, rep, ps, ext)
    return out


def paid_scan(segs, hosts, cwd, cfg, depth=0, loop=False, ps=False, ext=False):
    """Every hit of these segments in order, flagged `repeats` when it stands between a for / while / until / select and its `done`. ps
    (F6): PowerShell has no `done` (its braces are `;` by now), so a hit after a loop word (foreach, for, while, do, ForEach-Object, %,
    .ForEach) repeats, to the end of the command."""
    out, d = [], 0
    for seg in segs:
        if ps:
            d = d or bool(PAID_PS_LOOP.match(seg) or PAID_PS_METHOD.search(seg))
        else:
            d += bool(PAID_LOOP_OPEN.match(seg))
        out += paid_seg_hits(seg, hosts, cwd, cfg, depth, loop or d > 0, ps, ext)
        if not ps and PAID_LOOP_END.match(seg):
            d = max(0, d - 1)
    return out


def paid_lines(adapter):
    """The go lines of the adapter: `paid: <go>` or a list under `paid:` (`  - <go>`)."""
    out, in_list = [], False
    for ln in adapter.splitlines():
        m = re.match(r"paid:[ \t]*(.*?)[ \t]*$", ln)
        if m:
            in_list = not m.group(1)
            if m.group(1):
                out.append(m.group(1).strip("'\""))
            continue
        m = re.match(r"[ \t]+-[ \t]+(.+?)[ \t]*$", ln) if in_list else None
        if m:
            out.append(m.group(1).strip("'\""))
        elif ln.strip():
            in_list = False
    return out


def paid_parse_go(line):
    """One go line -> {script, runs, cap, count, test_ok}, or None when it does not parse: `render.py x 10, cap RM5[, count <flag>
    | count none][, test ok]` (x, × and * all mean times; runs >= 1). cap is free text, echoed and never measured. The one grammar
    the adapter shares with the owner's typed go (F3)."""
    m = PAID_GO.fullmatch(line.strip())
    if not m or int(m.group("runs")) < 1:
        return None
    g = {"script": m.group("script"), "runs": int(m.group("runs")), "cap": "", "count": "", "test_ok": False}
    for part in m.group("rest").split(","):
        part = part.strip()
        c = re.fullmatch(r"cap\s+(.+)", part, re.I)
        n = re.fullmatch(r"count\s+(\S+)", part, re.I)
        if c:
            g["cap"] = c.group(1).strip()
        elif n:
            g["count"] = n.group(1) if n.group(1).lower() != "none" else "none"
        elif re.fullmatch(r"test\s+ok", part, re.I):
            g["test_ok"] = True
    return g


def paid_finish(raw):
    """The hits as paid_verdict reads them: (signal, script, repeats, skip). The free runs the scan saw (signal None) are not hits. skip
    = the raw arguments of the free runs of the hit's own script, so the count rule (paid_seg_args) reads the paid run's segment and
    not the free run's. With no free run skip is empty and nothing differs from F3."""
    free = [h for h in raw if h[0] is None]
    return [(h[0], h[1], h[2], tuple(f[3] for f in free if h[1] and f[1].lower() == h[1].lower())) for h in raw if h[0] is not None]


def paid_hit(cmd, text, cwd, adapter, blind=False, project=None, ps=False, strict=False, deadline=None):
    """[(signal, script, repeats, skip)] — EVERY paid signal in the command (stdin-heredoc bodies first, then each segment), [] when none.
    text = the command with data heredocs stripped. blind (V10): the command is one the source check cannot read cleanly (complexity(),
    or over the heredoc scan cap): the HEREDOC pattern is not run (it rescans the text once per opener), and the whole text is searched
    for a paid word instead; a hit there has script None (no go can cover a command that was not read)."""
    extra = [h for h in adapter_list(adapter, "paid_hosts") if re.fullmatch(r"[\w.-]+", h)]
    hosts = paid_host_re(PAID_HOSTS + tuple(extra)) if extra else PAID_HOST
    cfg = PaidCfg(adapter, project or cwd, blind)
    cfg.strict = strict
    cfg.deadline = deadline                        # F4b step 1: the folder lookup stops at the hook's deadline (V8)
    cfg.cd_any = bool(PAID_CD_WORD.search(text))   # a loop may run its cd before the run that stands above it in the text
    segs = paid_segments(text, True)   # keep: a segment that ends at a backtick or ( keeps it, so a free flag beside `…` / $(…) is seen as not plain (as paid_seg_args reads it)
    looped = any(PAID_LOOP_OPEN.match(s) for s in segs)   # a body is not tied to a segment: any loop in the command makes it a repeat
    if blind:
        sig = paid_code_signal(cmd, hosts, True)
        return paid_finish(([(sig + " in a command that is not read cleanly", None, False)] if sig else []) + paid_scan(segs, hosts, cwd, cfg, 0, False, ps))
    out = [(sig + " on the command line", interp, looped) for interp, body in paid_stdin_bodies(cmd) for sig in [paid_code_signal(body, hosts, True)] if sig]
    return paid_finish(out + paid_scan(segs, hosts, cwd, cfg, 0, False, ps))


# 0.7.0 F5, the owner-quote check: what the OWNER typed in this session (`paid go: …`, `test ok[: script]`, `paid stop[: script]`), read from
# the transcript (docs/notes/paid-guard-plan.md, F5; shapes E1-E4). A record counts only when its origin says the owner typed it: origin.kind
# "human" AND promptSource "typed" or "queued". Never: a record with no origin object (a headless -p run, E3), origin peer (a subagent's report),
# isMeta, a compact summary, a subagent's own record, the model's text, a tool result, a queue-operation, a text that starts as another session's
# message. userType is never the test (it is "external" everywhere). Old Claude Code without the origin fields: nothing counts (fail closed).
class PaidUnverified(Exception):
    """The owner-quote check could not be done (transcript missing, unreadable, longer than the part read, over the hook's deadline): once a call is paid, deny."""


# Tool-output and relayed blocks inside a human prompt are cut before its lines are read; an unterminated one is cut to the end of the text.
PAID_BLOCK = re.compile(r"<(system-reminder|cross-session-message|task-notification|local-command-stdout|local-command-stderr|bash-stdout|bash-stderr)\b.*?(?:</\1>|\Z)", re.I | re.S)
PAID_RELAY = ("another claude session sent a message", "[request interrupted", "stop hook feedback:",
              "caveat: the messages below were generated by the user while running local commands")   # a text that STARTS like this is not the owner's line
PAID_T_GO = re.compile(r"paid[ \t]+go[ \t]*:[ \t]*(\S.*)", re.I)
PAID_T_OK = re.compile(r"test[ \t]+ok(?:[ \t]*:[ \t]*([^\s,]+))?", re.I)
PAID_T_STOP = re.compile(r"paid[ \t]+stop(?:[ \t]*:[ \t]*([^\s,]+))?", re.I)
PAID_TYPED_PRE = re.compile(rb"paid(?:\s|\\t)+(?:go|stop)|test(?:\s|\\t)+ok", re.I)   # a transcript line without one of these cannot hold a typed line: skipped unparsed
PAID_TAIL = 4 * 1024 * 1024                                                       # only the last 4 MB of a transcript are read (decision 2026-10-16)
PAID_SCANS = {}                                                                   # transcript path -> events (or the PaidUnverified it raised): one scan per call, whatever the number of scripts


def paid_typed_text(r):
    """The text of a transcript record only the OWNER can have typed, else None (see the header above), with the injected blocks cut out."""
    if r.get("isMeta") or r.get("isCompactSummary") or r.get("isSidechain") or r.get("isVisibleInTranscriptOnly"):
        return None
    t, a, src, midturn = r.get("type"), r.get("attachment"), r.get("promptSource"), False
    if t == "user":
        o, turn, m = r.get("origin"), r.get("turnOrigin"), r.get("message")
        c = m.get("content") if isinstance(m, dict) else None
        if isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return None
    elif t == "attachment" and isinstance(a, dict) and a.get("type") == "queued_command" and not a.get("isMeta"):
        o, turn, c = a.get("origin"), a.get("turnOrigin", r.get("turnOrigin")), a.get("prompt")
        src = a.get("promptSource", src)
        midturn = a.get("commandMode") == "prompt" and a.get("humanTurn") is True   # a prompt typed while Claude works, as the transcripts of Claude Code 2.1.305 to 2.1.326 hold it: no promptSource
    else:
        return None
    if not isinstance(o, dict) or o.get("kind") != "human" or turn not in (None, "human") or not (src in ("typed", "queued") or (src is None and midturn)):
        return None
    text = c if isinstance(c, str) else "\n".join(b["text"] for b in c if isinstance(b, dict) and b.get("type") == "text" and isinstance(b.get("text"), str)) if isinstance(c, list) else ""
    return None if text.lstrip().lower().startswith(PAID_RELAY) else PAID_BLOCK.sub("", text)


def paid_typed_lines(text, uuid):
    """[("go", go_id, go) | ("ok", script | None) | ("stop", script | None)] for the lines the owner typed at the start of a line (D8). go_id =
    "session:" + the record's uuid (a second go line in one record gets ".1" …); no uuid -> a hash of the line. The go is parsed by the
    adapter's own grammar (paid_parse_go)."""
    import hashlib   # inside the paid path only (V9): no new top-level import
    out, n = [], 0
    for ln in text.split("\n"):
        ln = ln.strip(" \t\r").rstrip(".! \t")
        if len(ln) < 7 or ln[0] not in "pPtT":
            continue
        m = PAID_T_GO.fullmatch(ln)
        if m:
            g = paid_parse_go(m.group(1))
            if g:
                gid = "session:" + (uuid or hashlib.sha1(m.group(1).encode("utf-8")).hexdigest()[:12]) + (f".{n}" if n else "")
                out.append(("go", gid, dict(g, go_from=gid)))
                n += 1
            continue
        m = PAID_T_OK.fullmatch(ln)
        if m:
            out.append(("ok", m.group(1)))
            continue
        m = PAID_T_STOP.fullmatch(ln)
        if m:
            out.append(("stop", m.group(1)))
    return out


def paid_scan_typed(path, deadline=None):
    """[(seq, kind, …)] in transcript order for what the owner typed: only the last 4 MB are read (the first, cut, line is dropped and a
    ("cut") event tells paid_find_go the head was not read), lines that cannot hold a typed line are skipped without parsing, a garbage
    line is skipped, and the pass stops at `deadline` (the hook's one deadline, V8; BUDGET_S from now when none is given). Raises
    PaidUnverified when the file is missing or unreadable or the deadline passes."""
    if deadline is None:
        deadline = time.monotonic() + BUDGET_S
    try:
        with open(path, "rb") as fh:
            size = fh.seek(0, 2)
            fh.seek(max(0, size - PAID_TAIL))
            buf = fh.read(PAID_TAIL)
    except FileNotFoundError:
        raise PaidUnverified("the transcript is missing")
    except OSError:
        raise PaidUnverified("the transcript is unreadable")
    ev, prev = [((0, 0), "cut")] if size > PAID_TAIL else [], None
    for i, raw in enumerate(buf.split(b"\n")[1 if size > PAID_TAIL else 0:]):
        if not (i & 63) and time.monotonic() >= deadline:
            raise PaidUnverified("the transcript scan ran over the hook's deadline")
        if not PAID_TYPED_PRE.search(raw):
            continue
        try:
            r = json.loads(raw.decode("utf-8", "replace"))
        except Exception:
            continue
        text = paid_typed_text(r) if isinstance(r, dict) else None
        if text:
            uuid = r.get("uuid") if isinstance(r.get("uuid"), str) else ""
            new = paid_typed_lines(text, uuid)
            if not new:
                continue
            att, norm = r.get("type") == "attachment", " ".join(text.split())
            if prev and prev[0] and not att and prev[1] == norm and prev[2] == len(ev):
                prev = None                                   # the same prompt written twice (an attachment, then a user record, with no typed line between): one go, the first
                continue
            ts = paid_ts(r.get("timestamp"))
            ev += [((i + 1, k),) + e + (ts,) for k, e in enumerate(new)]   # seq = (record, line within it); the last field is the record's own time (None when it has none)
            prev = (att, norm, len(ev))
    return ev


def paid_ts(v):
    """A record's `timestamp` (ISO 8601, Z or an offset) as seconds since the epoch, else None: a record with no usable time counts for nothing that needs one."""
    try:
        s = re.sub(r"\.(\d+)", lambda m: "." + (m.group(1) + "000000")[:6], v.replace("Z", "+00:00"), count=1)
        return datetime.datetime.fromisoformat(s).timestamp()
    except Exception:
        return None


def paid_typed_events(data, deadline=None):
    """What the owner typed in this session: paid_scan_typed over the event's transcript_path (a Windows path in the /c/Users/… form is
    converted, as the fresh-source gate does). No transcript_path in the event -> nothing typed. Raises PaidUnverified."""
    tp = data.get("transcript_path")
    if not isinstance(tp, str) or not tp:
        return []
    if tp not in PAID_SCANS:
        try:
            PAID_SCANS[tp] = paid_scan_typed(str(native_path(tp)), deadline)
        except PaidUnverified as e:
            PAID_SCANS[tp] = e
    if isinstance(PAID_SCANS[tp], PaidUnverified):
        raise PAID_SCANS[tp]
    return PAID_SCANS[tp]


def paid_state_dir(project):
    """The folder of this project's counter: ~/.claude/smartuse/projects/<key>/ (the same one ledger.py uses)."""
    return paid_home() / ".claude" / "smartuse" / "projects" / paid_project_key(project)


def paid_stored(project):
    """paid-runs.json read as it stands ({} when it cannot be read: paid_count, under its lock, is where a corrupt file denies)."""
    try:
        d = json.loads((paid_state_dir(project) / "paid-runs.json").read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def paid_find_go(data, project, script, adapter, deadline=None):
    """(go_id, go) of the go that covers this script, else None (matched by file name, case-insensitive). go_id = "adapter:" + sha1 of the
    whitespace-normalised line, so a changed line is a new counter, except that `, test ok` is not part of the id (adding it must not
    reset the count); "session:" + the typed go record's uuid. Precedence (D1): the adapter go, else the newest go the owner typed in
    this session. go["stopped"]: the owner typed `paid stop` (after the typed go; for an adapter go, ever in the visible transcript) or an
    earlier call stored it in paid-runs.json (paid_count writes it the first time it is seen, so it cannot scroll out of the last 4 MB). A
    stopped adapter go is replaced by a typed go that comes after the stop: that go is a new counter. go["test_ok"]: the line says it, or
    the owner typed `test ok` (after the typed go). A subagent's call (agent_id, E4) takes no typed go: only the adapter go covers it, and
    only a typed stop or test ok is read for it. The transcript is read once per call; when it cannot be (PaidUnverified), an adapter go
    still stands (headless runs and subagents have no owner prompts to find), a typed go cannot."""
    import hashlib   # inside the paid path only (V9): no new top-level import
    me, found = script.lower(), None
    for line in paid_lines(adapter):
        g = paid_parse_go(line)
        if g and paid_basename(g["script"]).lower() == me:
            g["go_from"] = "adapter"
            norm = re.sub(r"\s*,\s*test\s+ok\b", "", " ".join(line.split()), flags=re.I)
            found = "adapter:" + hashlib.sha1(norm.encode("utf-8")).hexdigest()[:12], g
            break
    sub = bool(data.get("agent_id"))
    if sub and not found:
        return None
    try:
        ev = paid_typed_events(data, deadline)
    except PaidUnverified:
        if not found:
            raise
        ev = []
    # an event is (seq, kind, …, time): seq = (record, line within the record), so a go and a stop typed in one prompt keep their order; time = the record's own `timestamp` (None: it has none)
    mine = lambda e: e[2] is None or paid_basename(e[2]).lower() == me
    gos = [] if sub else [e for e in ev if e[1] == "go" and paid_basename(e[3]["script"]).lower() == me]
    stops = [e for e in ev if e[1] == "stop" and mine(e)]
    newest = gos[-1] if gos else None
    t = newest[0] if newest else (-1, 0)
    stored = paid_stored(project) if (found or newest) else {}
    entry = lambda gid: stored[gid] if isinstance(stored.get(gid), dict) else {}
    held = lambda gid: bool(entry(gid).get("stopped"))
    if found and newest and (stops or held(found[0])) and t > max([e[0] for e in stops], default=(-1, 0)):
        # the adapter go was stopped and the owner typed a go after the stop: that go is a new counter, but only when its record is also LATER IN TIME than the stop
        # (the stop, seen or stored with its time; a time that is missing on either side means no take-over)
        times = [e[-1] for e in stops] + ([entry(found[0]).get("stopped_at")] if held(found[0]) else [])
        if newest[-1] is not None and times and all(isinstance(x, (int, float)) for x in times) and newest[-1] > max(times):
            found = None
    typed = False
    if not found and newest:
        found, typed = (newest[2], dict(newest[3])), True
    if not found and any(e[1] == "cut" for e in ev):
        raise PaidUnverified("the transcript is longer than the last 4 MB read and holds no go in them")
    if found:
        g, at = found[1], (t if typed else (-1, 0))
        run1 = entry(found[0]).get("run1_at")                 # a typed test ok counts only when its record is later than this go's run 1 (stored when run 1 was counted): no run yet, no typed ok
        g["test_ok"] = g["test_ok"] or (isinstance(run1, (int, float)) and any(e[1] == "ok" and mine(e) and e[-1] is not None and e[-1] > run1 for e in ev))
        seen = [e for e in stops if e[0] > at]
        g["stopped"] = held(found[0]) or bool(seen)
        g["stopped_at"] = None if any(e[-1] is None for e in seen) or not seen else max(e[-1] for e in seen)   # kept in the entry with `stopped`
    return found


def paid_seg_args(text, script, depth=0, skip=()):
    """The words after `script` in the command segment that runs it, RAW (quotes kept: unq() takes them off), up to the next && / || /
    ; / |; a bash -c "…" string is searched the same way. None when no segment holds the script. skip: the raw arguments of the free
    runs of the script (paid_finish): a segment whose words are one of them is a free run and is passed over."""
    for seg in paid_segments(text, True):
        toks = [a.group(0) for a in PAID_ARGS.finditer(seg[PAID_LEAD.match(seg).end():])]
        for i, t in enumerate(toks):
            if re.sub(r"\.exe$", "", paid_basename(paid_unq(t)).lower()) == script.lower():
                out = []
                for a in toks[i + 1:]:
                    if a in ("&&", "||", ";", "|"):
                        break
                    out.append(a)
                if tuple(out) in skip:
                    break
                return out
        if depth < 2 and "-c" in toks[:-1]:
            r = paid_seg_args(paid_unq(toks[toks.index("-c") + 1]), script, depth + 1, skip)
            if r is not None:
                return r
    return None


def paid_unq(t):
    """A raw word with one pair of outer quotes taken off."""
    return t[1:-1] if len(t) > 1 and t[0] in "'\"" and t[-1] == t[0] else t


def paid_quirky(t):
    """True when a raw word is not one clean literal for the free flags and the `only` flags (F4b fix): a backslash in it (an escape in
    bash), or a quote anywhere except as the one outer pair (`'--dry-run'x`, `--dry-run""`, `"--dry"-run`). The shell may turn such a
    word into a flag, or out of one. paid_not_plain, the count rule's test, is not changed."""
    u = paid_unq(t)
    return "\\" in t or "'" in u or '"' in u


def paid_not_plain(t):
    """True when the shell (or argparse) may turn this raw word into something else: $ ` <( >( in a bare or "double-quoted" word, a
    glob in a bare word, an @file anywhere. A 'single-quoted' word is literal."""
    u = paid_unq(t)
    if u.startswith("@"):
        return True
    return False if t[0] == "'" and t[-1] == "'" and len(t) > 1 else bool(re.search(r"[$`]|[<>]\(" + ("" if t[0] == '"' else r"|[*?\[]"), u))


def paid_count_flags(args, extra=""):
    """[(flag, value)] for every count flag in args (`--n 1`, `--n=1`, `-n1`); extra = the flag the go names (`count --pics`)."""
    flags = PAID_COUNT_FLAGS + ((extra,) if extra and extra != "none" else ())
    out = []
    for i, t in enumerate(args):
        for f in flags:
            if t == f:
                out.append((f, args[i + 1] if i + 1 < len(args) else ""))
            elif t.startswith(f + "="):
                out.append((f, t[len(f) + 1:]))
            elif len(f) == 2 and f[1] != "-" and t.startswith(f) and t[2:].isdigit():
                out.append((f, t[2:]))
    return out


def paid_counter_lock(sdir, deadline=None):
    """Hold paid-runs.lock (an O_EXCL file) for the read-modify-write of the counter: wait up to ~1 s for another holder (never past
    `deadline`, a time.monotonic() value: V8, one deadline for the whole hook), take over a lock older than 10 s (its holder died).
    -> the lock path, or None when busy; OSError when the dir is not writable."""
    lock = sdir / "paid-runs.lock"
    for _ in range(50):
        if deadline is not None and time.monotonic() >= deadline:
            return None
        try:
            os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
            return lock
        except FileExistsError:
            try:
                if time.time() - lock.stat().st_mtime > 10:
                    lock.unlink()
                    continue
            except OSError:
                pass
        except PermissionError:
            if os.name != "nt":                               # POSIX: the dir is not writable; Windows: the file is mid-delete, wait
                raise
        time.sleep(0.02)
    return None


def paid_count(data, sdir, items, text, deadline=None):
    """The cap rules, then count each allowed run, all under the counter lock (two parallel calls cannot both pass the cap). items =
    [(go_id, go, script)], one per script the command runs; ALL are checked before ANY is counted. A script already counted (a marker
    for this tool_use_id and go) is allowed again, not counted twice. Rules: runs used up; run 2+ needs `test ok`; run 1 must make ONE
    output (plain literal arguments and a count flag at 1 in the segment that runs the script, or the go says `count none`; `test ok`
    skips it). Counting: claim the tool_use_id (an O_EXCL marker, as ledger.py claims receipt.<agent>.done), used += 1, one atomic write.
    -> None when allowed, else (True, why the run cannot be counted, item index: the caller says "could not verify the go") or
    (False, the reason's tail, item index: a rule denies it). A corrupt counter file is never reset silently. F5: a go the owner stopped
    (go["stopped"], or the entry's stopped) is denied first, and the stop is written into the entry the first time it is seen."""
    sdir.mkdir(parents=True, exist_ok=True)
    try:
        lock = paid_counter_lock(sdir, deadline)
    except OSError:
        return True, "the counter is not writable", 0
    if not lock:
        return True, "the counter is busy", 0
    claimed = []
    try:
        f = sdir / "paid-runs.json"
        try:
            state = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}
        except Exception:
            state = None
        if not isinstance(state, dict):
            return True, "paid-runs.json is unreadable", 0
        tid = re.sub(r"[^A-Za-z0-9._-]", "-", str(data.get("tool_use_id") or ""))
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        todo = []                                             # (index, go_id, entry, ok, marker) of the runs to count
        for k, (go_id, go, script, skip) in enumerate(items):
            marker = sdir / (f"paid.{tid}.done" if k == 0 else f"paid.{tid}.{go_id[-8:]}.done") if tid else None
            if marker and marker.exists():
                continue                                      # this call was counted already (the other copy of the hook)
            e = state.get(go_id)
            if not isinstance(e, dict):
                e = {"script": go["script"], "runs": go["runs"], "cap": go["cap"], "count": go["count"], "used": 0, "test_ok": go["test_ok"],
                     "stopped": False, "go_from": go["go_from"], "first_at": now}
            used, runs, ok = int(e.get("used") or 0), int(e.get("runs") or go["runs"]), bool(e.get("test_ok") or go["test_ok"])
            if go.get("stopped") or e.get("stopped"):
                if not e.get("stopped"):                      # F5: the first sight of the stop is written down, so it cannot scroll out of the last 4 MB of the transcript
                    e["stopped"], e["stopped_at"] = True, go.get("stopped_at")   # with the stop record's own time: a typed go takes over only when it is later
                    state[go_id] = e
                    if not paid_write_json(f, state):
                        return True, "the counter is not writable", k
                return False, 'the owner said "paid stop": no more runs of this go. The owner types a new "paid go: …" to start again.', k
            if used >= runs:
                return False, f"the go for {clip(script)} is used up ({runs} of {runs}). Ask the owner for a new go.", k
            if used and not ok:
                return False, f"run {used} of {runs} is done; the batch waits for the owner's \"test ok\": ask the owner to add \", test ok\" to that paid: line. Show the owner the one output first. The owner can also type \"test ok\" in this session.", k
            if not ok and go["count"] != "none":
                raw = paid_seg_args(text, script, 0, skip) or []
                bad = next((t for t in raw if paid_not_plain(t)), None)
                if bad:                                       # $X, `…`, a glob, @file: the real arguments are not the ones the guard sees
                    return False, f"first run after the go must make ONE output: its arguments must be plain literals (seen {clip(bad)}).", k
                c = paid_count_flags([paid_unq(t) for t in raw], go["count"])
                if not c or any(v != "1" for _, v in c):
                    seen = next((f"{n} {v}".strip() for n, v in c if v != "1"), "no count flag")
                    return False, (f"first run after the go must make ONE output: set the count flag to 1 (seen {clip(seen)}; "
                                   "the owner can add \"count <flag>\" or \"count none\" to the go)."), k
            todo.append((k, go_id, e, ok, marker))
        for k, go_id, e, ok, marker in todo:
            if marker:
                try:
                    os.close(os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
                except FileExistsError:
                    continue
                except Exception:
                    return True, "the counter is not writable", k
                claimed.append(marker)
            if not int(e.get("used") or 0):
                e["run1_at"] = time.time()                    # F5: a typed test ok counts for this go only when its record is later than this (the first run)
            e["used"], e["test_ok"], e["last_at"] = int(e.get("used") or 0) + 1, ok, now
            state[go_id] = e
        if not todo or (not claimed and any(m for *_, m in todo)):
            return None                                       # nothing to count, or the other copy of the hook claimed every run
        if paid_write_json(f, state):
            claimed = []
            return None
        return True, "the counter is not writable", 0
    finally:
        for m in claimed:
            try:
                m.unlink()                                    # not counted: the retry may claim it again
            except Exception:
                pass
        try:
            lock.unlink()
        except Exception:
            pass


# 0.7.0 F3, V9: a linear first look. A command with no interpreter or caller word, no script file word, no URL and no paid word ends the
# paid path before anything is read (plain alternation of literals: no backtracking). The hosts, key names and SDK names are the
# lists above; adapter-listed hosts count only beside a caller or in a URL, and both are in this look.
PAID_FIRST = re.compile(r"\.(?:py|pyw|js|mjs|cjs|ts|mts|cts|tsx|jsx|sh|bash)\b"
                        r"|\b(?:python[\d.]*|pythonw|py|node|deno|bun|uv|uvx|npx|tsx|ts-node|bash|sh|zsh|dash|ksh|curl|wget|http|xh)\b"
                        r"|(?:https?|wss?)://|" + "|".join(re.escape(w) for w in PAID_HOSTS + PAID_KEYS) +
                        r"|openai|replicate|fal_client|anthropic|stability_sdk|genai|generativeai|@fal-ai|@google/", re.I)
# V5: light is armed by a paid line of the adapter (the fresh-source gate is armed the same way, by `sources:`); strict is always on.
PAID_ARM = re.compile(r"^(?:paid|paid_scripts|paid_hosts|paid_free):|^paid_guard:[ \t]*(?i:on)[ \t]*$", re.M)


def paid_home():
    """The home folder as the hook sees it: HOME first (on Windows expanduser("~") reads USERPROFILE and ignores HOME, which the
    tests and users who set HOME need)."""
    import pathlib   # inside the paid path only (V9): no new top-level import
    return pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~"))


def paid_adapter(project):
    """(adapter text, why): the human-only adapter, read and never written. A missing file is ("", ""); one that exists and cannot be
    read is ("", "the adapter is unreadable"): once a call is paid that denies (adapter_text, the fresh-source gate's read, answers ""
    for both and is not changed)."""
    try:
        with open(os.path.join(project, ".claude", "smartuse.local.md"), "rb") as fh:
            return fh.read(1 << 20).decode("utf-8-sig", "replace").replace("\r\n", "\n").replace("\r", "\n"), ""
    except FileNotFoundError:
        return "", ""
    except Exception:
        return "", "the adapter is unreadable"


def paid_verdict(data, cmd, text, strict=True, deadline=None, blind=False, ps=False):
    """None (not a paid call, or every go stands) or the deny reason. A detection error RAISES (the caller, paid_gate, allows it in
    light and denies it in strict); once the call is paid, any error while verifying the go -> deny. EVERY script the command runs
    needs its go; the first one without it is named. A loop or repeat of a paid script is denied whatever the counter says. strict:
    always on; light: only where the adapter has a paid line. deadline: the hook's time.monotonic() deadline (V8): past it a call
    already seen as paid is denied. blind (V10): a command that is not read cleanly is denied when it holds a paid word. ps (F6): the
    PowerShell tool; `text` is then ps_text of the command, and the scan reads it through paid_ps_text (the count rule reads the same text)."""
    if not PAID_FIRST.search(cmd):
        return None
    PAID_SCANS.clear()                                        # F5: one transcript scan per call
    cwd = native_path(data.get("cwd")) or os.getcwd()
    project = os.environ.get("CLAUDE_PROJECT_DIR") or cwd   # pathlib is imported only where a paid call needs the state folder (paid_home, paid_project_key)
    adapter, why = paid_adapter(project)
    if not strict and not PAID_ARM.search(adapter):
        return None
    if ps:
        text = paid_ps_text(ps_text(paid_ps_blocks(cmd)) if "{" in cmd else text)   # a script block after a pipe or a switch is marked as a loop first
    elif not blind:
        text = strip_comments(text)   # 0.7.0 F8: Bash only, at or under the heredoc cap (blind is the command that was not read cleanly): a quote in a # comment must not hide a paid run
    hits = paid_hit(cmd, text, cwd, adapter, blind, project, ps, strict, deadline)
    if not hits:
        return None
    head = lambda h: f"paid call ({clip(h[0])}) — "
    tangled = next((h for h in hits if h[1] is None), None)
    if tangled:
        return (head(tangled) + "this command is too tangled to read (nested shell strings, many substitutions or heredocs, or over 32 KB), "
                "so no go can cover it: run the paid script alone, in a command of its own. Nothing was spent.")
    if not why and deadline is not None and time.monotonic() >= deadline:
        why = "the hook ran past its deadline"
    first, rule, miss = hits[0], "", None                    # first = the hit the reason names
    unread = next((h for h in hits if h[0] == PAID_UNREAD), None)   # strict only (paid_hit): a script that exists and could not be opened
    if unread and not why:
        # No go clears this and the script has no known paid signal: say what is true (the guard cannot tell whether it pays) and the two ways out.
        return (f"could not verify whether {clip(unread[1])} pays: it could not be read, so the guard cannot see a paid signal in it. "
                "Make it readable, or run it in light mode. Nothing was spent.")
    try:
        if not why:
            covered = []                                      # [(hit, go_id, go)] once per script
            for h in hits:
                found = paid_find_go(data, project, h[1], adapter, deadline)
                if not found:
                    miss = miss or h
                elif found[0] not in [c[1] for c in covered]:
                    covered.append((h, found[0], found[1]))
            if not miss:
                low = [h[1].lower() for h in hits]
                again = next((h for h in hits if h[2] or low.count(h[1].lower()) > 1), None)
                if again:
                    return (head(again) + f"a loop or repeat runs {clip(again[1])} more than once in one call; run it once per call so each run is counted.")
                r = paid_count(data, paid_state_dir(project), [(c[1], c[2], c[0][1], c[0][3]) for c in covered], text, deadline)
                if r:
                    first = covered[r[2]][0]
                    why, rule = (r[1], "") if r[0] else ("", r[1])
    except PaidUnverified as e:                               # F5: the transcript could not be read in time (or at all, or is longer than the part read)
        why = str(e)
    except Exception:
        why = "the check failed"
    if why:
        return head(first) + f"could not verify the go ({why}); put it in .claude/smartuse.local.md. Nothing was spent."
    if rule:
        return head(first) + rule
    if not miss:
        return None
    typed = (" A subagent cannot use a typed go: only the adapter go (a paid: line in .claude/smartuse.local.md) covers it." if data.get("agent_id") else
             f" The owner can also type \"paid go: {clip(miss[1])} x <runs>, cap <amount>\" in this session (a go relayed from another session or a tool does not count).")
    return (head(miss) + f"no go from the owner for {clip(miss[1])}. Ask the owner to add \"paid: {clip(miss[1])} x <runs>, cap <amount>\" "
            "to .claude/smartuse.local.md. Nothing was spent." + typed)


def paid_gate(data, pre, text, tag, ps, strict, off, deadline):
    """The paid check as _main() runs it, last (V7): the deny reason, or None. `pre` the command as typed, `text` what the rules ran
    on, `tag` the complexity() tag, `ps` the PowerShell tool. Light with `paid` named in Rules off: not run (strict ignores the name).
    A detection error allows in light, as every check does, and denies in strict (fails closed)."""
    if not strict and "paid" in off:
        return None
    try:
        blind = bool(tag) or (not ps and "<<" in pre and many_heredocs(pre))
        return paid_verdict(data, pre, text, strict, deadline, blind, ps)
    except Exception:
        return "the paid check could not run (internal error); strict guards fail closed. Nothing was spent." if strict else None


def options():
    """(strict, off) from the plugin options Claude Code exports to the hook (CLAUDE_PLUGIN_OPTION_<KEY>, key upper-cased); the hook
    reads its own environment and nothing else, so nothing a command does can change it. STRICT not set, empty, or off / false / no / 0
    (any case) is light; any other value is strict, so a value the hook cannot read fails closed. `off` is the set of rule names in
    RULES_OFF (commas or blanks between, any case); strict ignores it."""
    strict = os.environ.get("CLAUDE_PLUGIN_OPTION_STRICT", "").strip().lower() not in ("", "off", "false", "no", "0")
    if strict:
        return True, frozenset()
    return False, frozenset(w for w in re.split(r"[\s,]+", os.environ.get("CLAUDE_PLUGIN_OPTION_RULES_OFF", "").lower()) if w)


def deny(why, name=None):
    msg = f"bash-guard: {why}"
    if name:
        msg += " [rule %s%s]" % (name, ", always on" if name in FLOOR else "")
    if len(msg) > MAX_REASON:
        msg = msg[:MAX_REASON - 1] + "…"   # a whole reason, ellipsis included, is at most MAX_REASON characters
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": msg}}))


def main():
    strict = options()[0]
    try:
        _main()
    except Exception:
        if not strict:
            raise   # light: as before, the hook fails and the call goes through
        deny("internal error; strict guards fail closed")


def _main():
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except Exception:
        return
    if not isinstance(data, dict):
        return
    deadline = time.monotonic() + BUDGET_S   # the fresh-source check's deadline starts with the hook, before any scan of the command
    tool = data.get("tool_name")
    if tool not in ("Bash", "PowerShell", "Monitor"):   # 0.7.0 D-YK12: a Monitor call carries its command in tool_input.command, like Bash; one without (a websocket) has an empty one
        why = fresh_gate(data, None, None, deadline)
        if why:
            deny(why)
        leave()
        return
    cmd = (data.get("tool_input") or {}).get("command") or ""
    if isinstance(cmd, str) and cmd.strip() == DOCTOR_CANARY:   # 0.6.1 F7: /smartuse:doctor tries this one command; the whole trimmed text, so no other command is touched
        deny("doctor canary — the guard is live · level: " + ("strict" if options()[0] else "light"))
        return
    pre = strip_state_args(cmd)
    ps = tool == "PowerShell"
    def gate():   # the fresh-source block on this command's text: PowerShell is read normalised (with / for \, which is no escape there)
        if ps:
            return fresh_gate(data, ps_text(pre).replace("\\", "/"), None, deadline, True)
        many = many_heredocs(pre)
        return fresh_gate(data, pre if many else strip_comments(gate_strip(pre)), None if many else pre, deadline)   # 0.7.0 F8: publish_hit uses `raw` (here `pre`) only for the heredoc budget and the substitutions in unquoted heredocs, never as text to read, so only `text` loses its comments
    # Order. A command the source check cannot read cleanly (see complexity) counts as a send while the sources are unopened, decided
    # before any scan of it, RULES included; with the sources opened (or none listed) it goes on to RULES as any command does, but its
    # text is not scanned for a publish. A long command (over RULES_FIRST_MAX characters) has the fresh-source block run before RULES
    # too: the frozen RULES patterns cost time quadratic in the text on a dense run of command words, past the hook's timeout (a
    # timed-out hook lets the call through), so a long text must not reach them while it is still unchecked. At or under the limit
    # RULES come first, as always: a RULES match keeps its own reason.
    tag = complexity(pre, ps)
    early = bool(tag) or len(pre) > RULES_FIRST_MAX
    if early:
        why = fresh_gate(data, None, None, deadline, ps, tag) if tag else gate()
        if why:
            deny(why)
            leave()
            return
    text = ps_text(pre) if ps else (pre if many_heredocs(pre) else strip_heredocs(pre))   # no heredocs in PowerShell
    strict, off = options()
    for (pat, why), name in zip(RULES, RULE_NAMES):
        if not strict and name not in FLOOR and (name in LIGHT_OFF or name in off):
            continue
        # config-switch reads the command as typed: a heredoc written to a settings file carries the key in its body (stripped from `text`);
        # settings-file and owner-file read it as typed too, and their waiver is given `pre` to tell a data heredoc line from a command
        if re.search(pat, pre if name in ("config-switch", "settings-file", "owner-file") and not ps else text, re.I | re.S) \
                and not (name in WAIVABLE and not tag and waived(name, text, ps, pre)):
            deny(why, name)
            return
    why = None if early else gate()
    if why:
        deny(why)
    else:   # 0.7.0 F3, V7: the paid check runs last, so a run is counted only when every other check allowed the call
        why = paid_gate(data, pre, text, tag, ps, strict, off, deadline)
        if why:
            deny(why, "paid")
    leave()


def leave():
    """A worker still waiting on the file system (it timed out above) must not hold the process: leave without it, as
    file-guard.py does. Only when one is stuck; otherwise a normal return."""
    if STUCK:
        sys.stdout.flush()
        os._exit(0)


main()
