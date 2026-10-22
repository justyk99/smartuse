#!/usr/bin/env python3
"""watch.py — smartuse watcher: a Claude Code session runs it as a BACKGROUND task right after it hands work to another
session (or starts a long job), so a durable signal — a git push, a file — wakes the session. A chat message can be lost;
a commit on the remote or a file on disk cannot. While it waits it costs 0 model tokens: one small `git ls-remote` per poll
(or one stat). Stdlib only, Python 3.9+, no POSIX-only calls: Linux, macOS and Windows Git Bash. Not a hook: nothing in
hooks.json starts it, the session does (design: docs/notes/one-session-design.md, M1).

  bash "<plugin>/hooks/py.sh" "<plugin>/hooks/watch.py" --git <remote> <branch> [--path <file>] [--since <sha>] [--every 60] [--max 4h]
  bash "<plugin>/hooks/py.sh" "<plugin>/hooks/watch.py" --file <path> [--every 5] [--max 4h]

--git <remote> <branch>   Run it inside a clone. The baseline is `git ls-remote <remote> refs/heads/<branch>` at the first poll
                          that works (a branch the remote does not have yet is a baseline too: its first push is the signal).
                          Every --every seconds the head is read again; when its sha differs the watcher runs
                          `git fetch <remote> refs/heads/<branch>` and, with --path, requires the file at that head
                          (`git cat-file -e <sha>:<path>`; a directory counts too; a file that is already in the baseline
                          head counts as well, so name one the hand-off creates). A head without the file is not a signal:
                          the watcher keeps waiting, from the new sha. It fires with ONE line on stdout, exit 0:
                              pushed <sha7> "<subject>" · <path, or the branch when there is no --path>
                          A push made before the first poll is part of the baseline: arm the watcher BEFORE the hand-off,
                          or give --since.
--since <sha>             With --git: the baseline is this commit instead of the first poll. Pass the commit the hand-off
                          left on the remote (`git rev-parse HEAD` right after your push), so a push made before the watcher
                          started still fires: a watcher armed late, or re-armed after a restart killed the first one. 7 to 64
                          hex digits (an abbreviation matches by prefix); it must be the remote's head at the hand-off, not a
                          local commit that was never pushed (any other head reads as a push).
--file <path>            Fires when the file exists: `file <path> (<n> bytes)`. A file that is already there fires at once
                          (remove a stale one first); the writer should create it atomically (temp name, then rename).
--every <seconds>         Whole seconds between polls, at least 5. Default 60 for --git, 5 for --file (a stat costs nothing).
                          SMARTUSE_WATCH_TEST=1 lowers the floor to 1: the regression suite sets it, nothing else changes.
--max <90s|30m|4h>        Stop waiting after this long (default 4h): `no signal after <max> (<what was watched>)`, exit 3. The
                          session is woken when nothing happened too and is never left waiting in silence. When the remote
                          never showed the branch, the parenthesis ends `· no such branch on the remote` (most likely a typo).
                          The time is measured on the wall clock and the monotonic clock, whichever has run further (a laptop
                          that slept past --max wakes the session on resume), the last poll is made at the deadline, and a git
                          call that hangs is killed at the deadline, a few seconds later at worst (a hung remote cannot hold
                          the wake-up back).
Exit codes                0 signal · 2 bad usage (ONE line on stderr; there is no --pid: run the command itself as the
                          background task) · 3 no signal at --max · 4 `cannot reach <remote>: <error line>` once 3 polls in a
                          row failed (the ls-remote, or the fetch after it; one --every apart, so a blip shorter than two
                          intervals is absorbed). A dead remote ends the watcher; it never spins on one. <error line> is the
                          last `fatal:` / `error:` line git printed, without its generic "Could not read from remote
                          repository." trailer, else its first line. Exit 0 always comes with exactly one line: an empty exit 0
                          means py.sh found no Python (it exits 0 silently then) and nothing was watched.
Output                    Only the lines above; the watcher is silent while it waits. The commit subject is text from the
                          remote: control characters become spaces and it is cut at 100 characters. A `user:password@` in a
                          URL remote is masked in every line that names it.
Side effects              None but what `git fetch` does in the clone: FETCH_HEAD and refs/remotes/<remote>/<branch>; never
                          the work tree, the index or HEAD. No state file, no lock. Git is called with an argument list (no
                          shell), with its stdin on the null device and GIT_TERMINAL_PROMPT=0 / GCM_INTERACTIVE=never, so a
                          missing credential fails the poll instead of waiting for a person; every call has a time limit
                          (60 s for ls-remote, 10 min for a fetch, 2 min for the checks on the fetched commit).
Windows                   Git Bash converts POSIX paths in arguments for a Windows program, never inside other text, so the
                          --file path (its "~" expanded) goes through native_path() ("/c/Users/x" -> "C:/Users/x") when
                          nothing exists at the spelling given. Git's output is decoded as UTF-8 (text=True would use the
                          ANSI code page), and stdout / stderr are written as UTF-8 with plain "\\n" line ends whatever the
                          console code page (reconfigured in main()).
Python 3.9 floor          No match statements, no `X | Y` types, no annotations: the CI matrix runs 3.9.
"""
import os, re, shutil, subprocess, sys, time, unicodedata

USAGE = ("--git <remote> <branch> [--path <file>] [--since <sha>] [--every 60] [--max 4h] | "
         "--file <path> [--every 5] [--max 4h]")
MISSES = 3              # failed polls in a row before "cannot reach"
LS_TIMEOUT = 60         # seconds one `git ls-remote` may take
FETCH_TIMEOUT = 600     # ... one `git fetch` (the builder may have pushed a lot: render output)
LOCAL_TIMEOUT = 120     # ... a check on the fetched commit (cat-file, log: ms, unless a partial clone has to fetch a blob first)
SUBJECT_MAX = 100       # characters of a commit subject in the fired line
ERROR_MAX = 200         # characters of git's error line in "cannot reach"
SHA = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?")   # a SHA-1 or SHA-256 object name
ERR_LINE = re.compile(r"(?:fatal|error):", re.I)
GENERIC = {"fatal: could not read from remote repository."}   # git's trailer on every transport failure: it says nothing


class Usage(Exception):
    """A bad command line: main() prints it as one line on stderr and exits 2."""


class Unreachable(Exception):
    """One poll could not reach the remote: git failed, timed out or could not start."""


def native_path(p):
    """A path string as this interpreter can open it. On Windows the watcher runs through Git Bash, which converts POSIX paths
    in arguments and environment variables for a Windows program but not inside other text: given "/c/Users/x/DONE", Windows
    Python looks under <current drive>:/c/Users/x/ and finds nothing. So when the string starts with "/" and nothing exists
    there, the MSYS drive form "/c/..." becomes "C:/..."; "/tmp/..." has no drive letter and stays as it is. Anything else, and
    everything on other platforms, comes back unchanged. Never raises."""
    try:
        s = str(p or "")
        if os.name == "nt" and s.startswith("/") and not os.path.exists(s):
            if len(s) >= 2 and "a" <= s[1].lower() <= "z" and (len(s) == 2 or s[2] == "/"):
                return s[1].upper() + ":" + (s[2:] or "/")
    except Exception:
        pass
    return p


def say(line, code, stream=None):
    """Print one line (to stdout, or `stream`) and return `code` for main() to exit with. Never raises: a console that cannot
    show the line in UTF-8 gets it with \\u escapes rather than nothing, and a closed pipe has nobody left to wake."""
    stream = stream or sys.stdout
    try:
        print(line, file=stream, flush=True)
    except UnicodeError:
        try:
            print(line.encode("ascii", "backslashreplace").decode("ascii"), file=stream, flush=True)
        except Exception:
            pass
    except (OSError, ValueError):
        pass
    return code


def clean(text, limit=SUBJECT_MAX):
    """One printable line out of text that came from outside (a commit subject, git's stderr): control and format characters
    (ESC, bidi overrides, zero-width marks) and line breaks become spaces, runs of spaces collapse, and anything past `limit`
    characters is cut with an ellipsis. The line is read by a model: the remote's text is data, kept short and plain."""
    s = "".join(" " if unicodedata.category(c) in ("Cc", "Cf", "Zl", "Zp") else c for c in str(text))
    s = " ".join(s.split())
    return s if len(s) <= limit else s[:limit - 1].rstrip() + "…"


def mask(text):
    """`user:password@` (or `token@`) after "://" removed: a URL remote may carry a credential, and every printed line ends up
    in the session's context."""
    return re.sub(r"(?<=://)[^/@\s]*@", "", str(text))


def error_line(text):
    """The one line of git's stderr that says what went wrong: the LAST `fatal:` / `error:` line that is not git's generic
    trailer ("fatal: Could not read from remote repository."), else the first non-empty line, else "". Git prints the cause
    first and advice after it ("Please make sure you have the correct access rights..."), so the last line of the text would
    be the least useful one. Masked and cut at ERROR_MAX characters."""
    lines = [l.strip() for l in str(text).splitlines() if l.strip()]
    errs = [l for l in lines if ERR_LINE.match(l) and l.lower() not in GENERIC]
    return clean(mask(errs[-1] if errs else lines[0] if lines else ""), ERROR_MAX)


def parse_duration(text):
    """'90s' / '30m' / '4h' (any case) -> (seconds, the normalised text). At least one second; anything else, a bare number
    included, raises ValueError."""
    m = re.fullmatch(r"([0-9]{1,6})([smh])", str(text).strip().lower())
    if not m or int(m.group(1)) < 1:
        raise ValueError(f"not a duration: {text!r}")
    n = int(m.group(1))
    return n * {"s": 1, "m": 60, "h": 3600}[m.group(2)], f"{n}{m.group(2)}"


def norm_path(p):
    """A --path as git spells it inside a tree: forward slashes, relative to the repository root ('.\\docs\\x.md' and
    '/docs/x.md' -> 'docs/x.md')."""
    p = str(p).replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p.lstrip("/")


def parse_args(argv):
    """argv -> {"mode": "git" | "file", "remote", "branch", "path", "since", "file", "every", "max" (seconds), "max_text"}.
    Raises Usage with the reason. Strict on purpose: a typo is told at once (the task ends, the session is woken) instead of
    waiting four hours for a signal that cannot come."""
    got, i = {}, 0
    while i < len(argv):
        opt = argv[i]
        if opt == "--git":
            vals = argv[i + 1:i + 3]
            if len(vals) < 2 or any(v.startswith("--") for v in vals):
                raise Usage("--git needs <remote> <branch>")
            if opt in got:
                raise Usage("--git given twice")
            got[opt] = tuple(vals)
            i += 3
        elif opt in ("--path", "--since", "--file", "--every", "--max"):
            if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
                raise Usage(f"{opt} needs a value")
            if opt in got:
                raise Usage(f"{opt} given twice")
            got[opt] = argv[i + 1]
            i += 2
        elif opt.startswith("-"):
            raise Usage(f"unknown option {opt}")
        else:
            raise Usage(f"unexpected argument '{opt}'")
    if "--git" in got and "--file" in got:
        raise Usage("--git and --file are two modes: give one")
    if "--git" not in got and "--file" not in got:
        raise Usage("give --git <remote> <branch> or --file <path>")
    if "--file" in got and "--path" in got:
        raise Usage("--path goes with --git")
    if "--file" in got and "--since" in got:
        raise Usage("--since goes with --git")
    a = {"mode": "git" if "--git" in got else "file", "remote": None, "branch": None, "path": None, "since": None, "file": None}
    if a["mode"] == "git":
        remote, branch = got["--git"]
        if not remote or not branch or remote.startswith("-") or branch.startswith("-"):
            raise Usage("<remote> and <branch> must be given and must not start with '-'")
        a["remote"], a["branch"] = remote, branch
        if "--path" in got:
            a["path"] = norm_path(got["--path"])
            if not a["path"]:
                raise Usage("--path is empty")
        if "--since" in got:
            if not re.fullmatch(r"[0-9a-fA-F]{7,64}", got["--since"]):
                raise Usage(f"--since must be a commit sha, 7 to 64 hex digits (got '{got['--since']}')")
            a["since"] = got["--since"].lower()
    else:
        if not got["--file"]:
            raise Usage("--file needs a path")
        a["file"] = got["--file"]
    floor = 1 if os.environ.get("SMARTUSE_WATCH_TEST") == "1" else 5
    v = got.get("--every")
    if v is None:
        a["every"] = 60 if a["mode"] == "git" else 5
    elif re.fullmatch(r"[0-9]{1,6}", v) and int(v) >= floor:
        a["every"] = int(v)
    else:
        raise Usage(f"--every must be whole seconds, {floor} or more (got '{v}')")
    v = got.get("--max", "4h")
    try:
        a["max"], a["max_text"] = parse_duration(v)
    except ValueError:
        raise Usage(f"--max must look like 90s, 30m or 4h (got '{v}')")
    return a


def clock():
    return time.time(), time.monotonic()


def elapsed(t0):
    """Seconds since t0 = clock(), by whichever of the two clocks has run further. The monotonic clock stops while a laptop
    sleeps and the wall clock can be stepped back: taking the larger keeps --max true to its word both ways."""
    w, m = clock()
    return max(w - t0[0], m - t0[1])


def budget(cap, left):
    """Seconds one git call may take: its own cap, but not past the deadline (a call that hangs must not hold the wake-up
    back), and never under 5 so the poll made right at the deadline can still finish."""
    return max(5, min(cap, left))


def run(cmd, timeout):
    """cmd (a list, never a shell) -> (returncode, stdout, stderr) as text decoded UTF-8 with replacement (text=True would use
    the ANSI code page on Windows and could raise). returncode None = the call did not complete: it could not start, or it
    was still running after `timeout` seconds and was killed. The pipes get 2 more seconds after the kill and are then
    dropped, so nothing here waits for a grandchild (ssh, a remote helper) that kept them open."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never")
    try:
        p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    except OSError as e:
        return None, "", f"cannot run {cmd[0]}: {e}"
    try:
        out, err = p.communicate(timeout=max(1, timeout))
    except subprocess.TimeoutExpired:
        p.kill()
        try:
            p.communicate(timeout=2)
        except Exception:
            pass
        return None, "", f"timed out after {int(timeout)}s"
    return p.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


def git(args, timeout=LOCAL_TIMEOUT):
    return run(["git"] + list(args), timeout)   # a list, never a shell: a remote, branch or path is one argument whatever it holds


def why(what, rc, err):
    """The reason a git call failed, for "cannot reach": its error line, else a plain statement of the exit status."""
    return error_line(err) or f"git {what} exited {rc}"


def ls_remote(remote, branch, timeout=LS_TIMEOUT):
    """The head sha of refs/heads/<branch> on the remote; None when the remote has no such branch (an empty answer is not
    an error). Only the exact ref counts: `ls-remote <remote> <name>` would also list a tag of that name. Raises Unreachable."""
    rc, out, err = git(["ls-remote", remote, "refs/heads/" + branch], timeout)
    if rc != 0:
        raise Unreachable(why("ls-remote", rc, err))
    for line in out.splitlines():
        sha, _, ref = line.strip().partition("\t")
        if ref == "refs/heads/" + branch and SHA.fullmatch(sha):
            return sha
    return None


def fetch(remote, branch, timeout=FETCH_TIMEOUT):
    """`git fetch <remote> refs/heads/<branch>`, the full ref so a tag of the same name cannot be fetched instead; no tags and
    no submodules (the watcher wants the commit, not the side effects). Raises Unreachable."""
    rc, out, err = git(["fetch", "--quiet", "--no-tags", "--recurse-submodules=no", remote, "refs/heads/" + branch], timeout)
    if rc != 0:
        raise Unreachable(why("fetch", rc, err))


def have_commit(sha, timeout=LOCAL_TIMEOUT):
    return git(["cat-file", "-e", sha + "^{commit}"], timeout)[0] == 0


def has_path(sha, path, timeout=LOCAL_TIMEOUT):
    """True when `path` (a file or a directory) exists in the tree of commit `sha`. In a partial clone git fetches the missing
    blob to answer, which is why the limit is generous."""
    return git(["cat-file", "-e", f"{sha}:{path}"], timeout)[0] == 0


def subject_of(sha, timeout=LOCAL_TIMEOUT):
    """The commit's subject line, cleaned; "" when git cannot say."""
    rc, out, err = git(["log", "-1", "--no-show-signature", "--format=%s", sha, "--"], timeout)
    return clean(out) if rc == 0 else ""


def preflight(a):
    """--git needs git on PATH, a clone to run in, and a branch name git accepts. Anything else is a usage error (exit 2)."""
    if not shutil.which("git"):
        raise Usage("git is not on PATH")
    rc, out, err = git(["rev-parse", "--git-dir"])
    if rc != 0:
        raise Usage(f"not inside a git clone — run it in one; git says: {error_line(err) or 'rev-parse failed'}")
    if git(["check-ref-format", "refs/heads/" + a["branch"]])[0] != 0:
        raise Usage(f"'{a['branch']}' is not a valid branch name")


def same(head, base):
    """Is `head` (a full sha, or None: no such branch) the commit `base` names? `base` may be a --since abbreviation."""
    return head is None if base is None else head is not None and head.startswith(base)


def watch_git(remote, branch, path, every, max_s, max_text, since=None):
    """The --git loop -> the exit code (0 pushed · 3 no signal at max_s · 4 cannot reach). One iteration is one poll: read the
    head; on a change fetch it and look for the path; then either fire, give up at the deadline, or sleep. The deadline check
    comes AFTER the poll, so the last look at the remote is made at --max and a poll that wakes a laptop from sleep is not
    skipped. Any exception inside a poll (git failing, a bug) is a failed poll, so the watcher can only end by firing, by the
    deadline, or by MISSES failures in a row — never by dying in silence at hour three."""
    shown = mask(remote)
    what = f"git {shown}/{branch}" + (f" · {path}" if path else "")
    t0 = clock()
    armed, seen, base, misses, last = bool(since), False, since, 0, ""   # armed: the baseline is taken (--since takes it now) · seen: the remote has shown the branch at least once

    def lim(cap):                                 # the time one git call may take, counted from NOW against the deadline
        return budget(cap, max_s - elapsed(t0))

    while True:
        try:
            head = ls_remote(remote, branch, lim(LS_TIMEOUT))
            seen = seen or head is not None
            if not armed:
                base, armed = head, True          # the first look that works is the baseline
            elif not same(head, base):
                if head is None:
                    base = None                   # the branch was deleted: nothing to report, wait for it to come back
                else:
                    fetch(remote, branch, lim(FETCH_TIMEOUT))
                    if have_commit(head, lim(LOCAL_TIMEOUT)):   # not there after the fetch = a force-push in between: look again next poll
                        if not path or has_path(head, path, lim(LOCAL_TIMEOUT)):
                            return say(f'pushed {head[:7]} "{subject_of(head, lim(LOCAL_TIMEOUT))}" · {path or branch}', 0)
                        base = head               # the file is not in this head: keep waiting, from here
            misses = 0
        except Exception as e:
            misses, last = misses + 1, (str(e) if isinstance(e, Unreachable) else f"{type(e).__name__}: {e}")
            if misses >= MISSES:
                return say(f"cannot reach {shown}: {last}", 4)
        left = max_s - elapsed(t0)
        if left <= 0:
            if armed and not seen:                # four silent hours on a typo would be the worst answer: say the branch never showed
                what += " · no such branch on the remote"
            return say(f"no signal after {max_text} ({what})", 3)
        time.sleep(min(every, left))


def real_path(path):
    """A --file argument as this interpreter can open it: "~" expanded (a quoted "~/x" reaches us unexpanded), then native_path()."""
    return native_path(os.path.expanduser(path))


def watch_file(path, every, max_s, max_text):
    """The --file loop -> the exit code (0 the file exists · 3 no signal at max_s). A directory is not a file."""
    real = real_path(path)
    t0 = clock()
    while True:
        try:
            if os.path.isfile(real):
                return say(f"file {path} ({os.path.getsize(real)} bytes)", 0)
        except OSError:
            pass                                  # gone again between the two calls: look again at the next poll
        left = max_s - elapsed(t0)
        if left <= 0:
            return say(f"no signal after {max_text} (file {path})", 3)
        time.sleep(min(every, left))


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):       # UTF-8 and "\n" whatever the console code page (Windows pipes default to cp1252 and "\r\n")
        try:
            stream.reconfigure(encoding="utf-8", errors="replace", newline="\n")
        except Exception:
            pass
    argv = sys.argv[1:] if argv is None else list(argv)
    try:
        if any(a in ("-h", "--help") for a in argv):
            return say("usage: watch.py " + USAGE, 0)
        try:
            a = parse_args(argv)
            if a["mode"] == "git":
                preflight(a)
            elif os.path.isdir(real_path(a["file"])):
                raise Usage(f"--file needs a file, '{a['file']}' is a directory")
        except Usage as e:
            return say(f"watch: {e} (usage: {USAGE})", 2, sys.stderr)
        if a["mode"] == "git":
            return watch_git(a["remote"], a["branch"], a["path"], a["every"], a["max"], a["max_text"], a["since"])
        return watch_file(a["file"], a["every"], a["max"], a["max_text"])
    except KeyboardInterrupt:
        return 130                                # Ctrl-C in a terminal: no traceback


if __name__ == "__main__":
    sys.exit(main())
