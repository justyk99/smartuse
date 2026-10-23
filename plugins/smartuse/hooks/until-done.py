#!/usr/bin/env python3
"""until-done.py — Stop hook: the deterministic half of `run-plan --until-done`.

When the project's routing.json is active with "until_done": true, the turn may NOT end while units are still pending /
running / failed, or while the repo's check command fails. The hook blocks the stop with a reason the model reads ("units
left: 3, 4 · check failed: …"), so the session keeps working. It lets the turn end when:
  - routing.needs_human is set (the model wrote the question it needs answered),
  - every unit is pass / blocked and the check passes (or no check is configured),
  - the hook has blocked `max_blocks` times for this run (default 6; the counter `blocks` lives in routing.json),
  - routing.active is false,
  - a `command` unit (run-plan's no-model tier: one shell command run as a background task) is running and the Stop input's
    own `background_tasks` (Claude Code 2.1.308: [{id, type, status, …}]) lists a live task: ending the turn is waiting, not
    quitting — the command's end notification wakes the session to record it — and no block is spent (a long render would
    otherwise use up max_blocks and switch the gate off for the rest of the run).
Claude Code sets stop_hook_active=true on EVERY Stop that follows a block, so the gate ignores that flag on purpose:
allowing on it would push exactly once per user prompt. The loop is bounded by `max_blocks` instead.
State dir: ~/.claude/smartuse/projects/<key>/ (shared with heartbeat.py and ledger.py). <key> is the repo's full resolved
path with every character outside [A-Za-z0-9._-] replaced by "-" and a leading "-" dropped (/home/u/proj -> home-u-proj,
C:/Users/u/proj -> C--Users-u-proj), the way Claude Code keys ~/.claude/projects/, so two repos that share a folder name no
longer share routing.json. The gate reads and writes routing.json in that keyed dir only. 0.3.0 keyed the dir by the folder
name alone: projects/<folder name>/ is shared by every repo of that name, so it is never read here and never written — a
0.3.0 run that was in progress at the upgrade is not gated (the gate fails open, its rule for anything it cannot trust).
The check command is NEVER taken from routing.json (the model writes that file). It comes only from the human-authored
adapter `.claude/smartuse.local.md` (`check:`), is screened by the bash-guard rules, must be one of a few exact shapes
(`npm test`, `pytest`, `make test`, `cargo test`, `go test ./...`, `dotnet test`, …) or a `bash <script>` the human pinned by
hash in a ROOT-OWNED file (/etc/smartuse/trusted-checks.json, installed with sudo — `--trust` only prints the commands;
Linux/macOS only: Windows has no root-owned /etc/smartuse, so only the fixed shapes run there), contains no shell
metacharacters, and runs with shell=False. The runner is resolved with shutil.which first (on Windows npm / pnpm / yarn /
mvn / gradle are .cmd shims that CreateProcess alone does not find; which honours PATHEXT) and its output is decoded as
UTF-8 with replacement, never strictly in the console code page. A runner that is not installed blocks ONCE ("check
command not found: …") and is recorded in routing.json as `check_error` {check, exe, reason, at}: the next Stop allows
instead of blocking six times; the check runs again once `check:` changes or the runner appears on PATH. A file-guard hook
denies Claude's Write/Edit on the adapter and on the pin file. Check output is redacted (last 8 lines, secrets masked).
Windows: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, never inside the event
JSON, so a "cwd" taken from it goes through native_path() ("/c/Users/x" -> "C:/Users/x"). stdin is read as bytes and decoded
as UTF-8 (Windows Python would decode a pipe in the ANSI code page and raise on the first non-ASCII byte, failing the gate
open). The block decision is JSON with ASCII escapes (json.dumps), so stdout needs no re-encoding.
0 model tokens. Any error -> allow the stop (a gate must never trap the session).
"""
import json, os, sys, subprocess, pathlib, datetime, re, shlex, shutil

HOME = pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~"))   # HOME first: on Windows expanduser("~") reads USERPROFILE and ignores HOME (the tests and users who set HOME need it)

# Exact command shapes that may run. Extra args are allowed only for the runners marked True, and only if they look like
# plain paths/names (no flags, no URLs, no package specs).
FIXED = {("npm", "test"): False, ("pnpm", "test"): False, ("yarn", "test"): False, ("bun", "test"): False,
         ("pytest",): True, ("make", "test"): False, ("make", "check"): False, ("cargo", "test"): False,
         ("go", "test", "./..."): False, ("dotnet", "test"): False, ("mvn", "test"): False, ("gradle", "test"): False,
         ("true",): False, ("false",): False}
ARG_OK = re.compile(r"^[A-Za-z0-9_./:-]+$")
TRUSTED = pathlib.Path("/etc/smartuse/trusted-checks.json")   # human-pinned `bash <script>` checks, ROOT-OWNED: the agent runs as the user and cannot write it
POSIX_ONLY = "(Linux/macOS only: needs a root-owned /etc/smartuse; on Windows use one of the fixed shapes)"
META = re.compile(r"[;&|`$<>\\]|\$\(|\n")
SECRET = re.compile(r"(?i)(token|password|passwd|secret|api[_-]?key|authorization)[^\n]{0,80}")


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
    """~/.claude/smartuse/projects/<project_key()>/ — under the user's home, never inside the repo (same rule as heartbeat.py
    and ledger.py). The only dir the gate reads routing.json from, whether or not it exists: there is no fallback to the 0.3.0
    folder-name dir (shared by every repo of that name). The gate never creates it."""
    return HOME / ".claude" / "smartuse" / "projects" / project_key(project)


def stdin_json():
    """The event JSON from stdin, read as bytes and decoded as UTF-8: Windows Python decodes a piped stdin in the ANSI code
    page, where one non-ASCII byte raises and the gate would fail open; a bad byte becomes U+FFFD instead."""
    raw = sys.stdin.buffer.read() if hasattr(sys.stdin, "buffer") else sys.stdin.read().encode("utf-8", "replace")
    return json.loads(raw.decode("utf-8", "replace"))


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def adapter_check(project):
    """`check:` from the human-authored adapter only."""
    f = project / ".claude" / "smartuse.local.md"
    try:
        text = f.read_text(encoding="utf-8")
    except Exception:
        return ""
    m = re.search(r"^check:\s*(.+?)\s*$", text, re.M)
    return (m.group(1).strip().strip("'\"") if m else "")


def guard_rules():
    """Reuse bash-guard's RULES if the file sits beside this one."""
    try:
        src = (pathlib.Path(__file__).parent / "bash-guard.py").read_text(encoding="utf-8")
        ns = {}
        exec(compile(src.replace("\nmain()\n", "\n"), "bash-guard", "exec"), ns)
        return ns.get("RULES") or []
    except Exception:
        return []


def sha256_of(path):
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pins_are_trustworthy():
    """The pin file counts only if root owns it and its directory, and neither is writable by anyone else.
    The agent runs as the user: it cannot create, replace or edit such a file (sudo is denied to it), so a pin there is a human act."""
    if os.name == "nt":
        return False   # Windows reports st_uid 0 for every file, so ownership proves nothing: no `bash <script>` pins there, only the fixed shapes
    try:
        f = TRUSTED.stat(); d = TRUSTED.parent.stat()
    except Exception:
        return False
    return f.st_uid == 0 and d.st_uid == 0 and not (f.st_mode & 0o022) and not (d.st_mode & 0o022)


def trusted_match(check, project):
    """A `bash <relative script>` check runs only if a root-owned pin names exactly this command + the script's hash."""
    if not pins_are_trustworthy():
        return False
    try:
        t = json.loads(TRUSTED.read_text(encoding="utf-8")).get(str(project.resolve())) or {}
    except Exception:
        return False
    if t.get("check") != check:
        return False
    argv = shlex.split(check)
    if len(argv) != 2 or argv[0] not in ("bash", "sh") or argv[1].startswith(("-", "/", "~")) or ".." in argv[1]:
        return False
    script = project / argv[1]
    return script.is_file() and sha256_of(script) == t.get("sha256")


def safe_argv(check, project):
    """Return argv for a check that is allowed to run, else (None, reason)."""
    if META.search(check):
        return None, "shell metacharacters are not allowed in `check:`"
    for pat, why in guard_rules():
        if re.search(pat, check, re.I | re.S):
            return None, f"refused by bash-guard: {why}"
    try:
        argv = shlex.split(check)
    except ValueError as e:
        return None, f"cannot parse: {e}"
    if not argv:
        return None, "empty"
    if trusted_match(check, project):
        return argv, ""
    for shape, extras_ok in FIXED.items():
        if tuple(argv[:len(shape)]) == shape:
            rest = argv[len(shape):]
            if not rest:
                return argv, ""
            if extras_ok and all(ARG_OK.match(a) and not a.startswith("-") and "://" not in a and "@" not in a for a in rest):
                return argv, ""
            return None, f"extra arguments not allowed after `{' '.join(shape)}`"
    return None, ("not an allowed check. Allowed: " + ", ".join(" ".join(k) for k in FIXED if k[0] not in ("true", "false")) +
                  ", or a `bash <script-in-repo>` the human pinned with: bash <hook dir>/py.sh <hook dir>/until-done.py --trust \"bash path/to/check.sh\" (run from the repo) " + POSIX_ONLY)


def trust(check):
    """Human helper: prints the pin entry and the sudo command that installs it. Writes nothing itself.
    On Windows there is no root-owned /etc/smartuse, so it prints the one-line refusal and nothing else."""
    if os.name == "nt":
        print("`bash <script>` pins are not available here " + POSIX_ONLY); return
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()).resolve()
    argv = shlex.split(check)
    if len(argv) != 2 or argv[0] not in ("bash", "sh") or argv[1].startswith(("-", "/", "~")) or ".." in argv[1] or not (project / argv[1]).is_file():
        print("refused: the form is `bash <relative script inside the repo>`"); return
    entry = {str(project): {"check": check, "sha256": sha256_of(project / argv[1])}}
    try:
        existing = json.loads(TRUSTED.read_text(encoding="utf-8")) if TRUSTED.exists() else {}
    except Exception:
        existing = {}
    existing.update(entry)
    body = json.dumps(existing, indent=2)
    print("Run these yourself in your terminal (root-owned file = the human boundary; the agent cannot write it):\n")
    print("sudo mkdir -p /etc/smartuse && sudo chmod 755 /etc/smartuse && sudo tee /etc/smartuse/trusted-checks.json >/dev/null <<'JSON'\n" + body + "\nJSON\nsudo chmod 644 /etc/smartuse/trusted-checks.json")
    print("\nRe-run this after you change the script (the hash is pinned). " + POSIX_ONLY)


def redact(text):
    lines = [SECRET.sub(lambda m: m.group(1) + " [redacted]", l) for l in text.strip().splitlines()[-8:]]
    return "\n".join(l[:200] for l in lines)


def run_check(check, argv, project, prior):
    """Run an allowed check in the repo -> (reason to block or "", check_error to record or None).
    argv[0] goes through shutil.which (PATHEXT: npm -> npm.cmd on Windows, which CreateProcess alone does not find).
    A runner that is not installed is reported ONCE: `prior` is routing.json's check_error, and while it names this same
    check with the same (missing) resolution the check is skipped, so the next Stop allows instead of blocking six times."""
    exe = shutil.which(argv[0])
    if isinstance(prior, dict) and prior.get("check") == check and prior.get("exe") == exe:
        return "", None
    argv0, argv = argv[0], [exe or argv[0]] + argv[1:]
    try:
        cp = subprocess.run(argv, shell=False, cwd=str(project), capture_output=True, encoding="utf-8", errors="replace", timeout=300)
    except subprocess.TimeoutExpired:
        return f"check timed out: `{check}`", None
    except FileNotFoundError:
        reason = f"check command not found: {argv0} — install it or fix `check:` in .claude/smartuse.local.md"
        return reason, {"check": check, "exe": exe, "reason": reason, "at": utc_now()}
    except Exception as e:
        return f"check could not run: {type(e).__name__}", None
    if cp.returncode != 0:
        return f"check failed (exit {cp.returncode}): `{check}`\n" + redact(cp.stdout + "\n" + cp.stderr), None
    return "", None


LIVE = {"running", "pending", "started", "starting", "in_progress", "in-progress", "active", "queued"}   # a background task status that is not final


def live_background(data):
    """True when the Stop input lists a background task that is still running (an entry without a status counts as running:
    letting the turn end is this gate's fail-open side)."""
    v = data.get("background_tasks")
    return isinstance(v, list) and any(isinstance(x, dict) and str(x.get("status") or "running").lower() in LIVE for x in v)


def allow():
    sys.exit(0)


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason[:1800]}))
    sys.exit(0)


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--trust":
        trust(sys.argv[2]); return   # prints instructions only
    try:
        data = stdin_json()
    except Exception:
        allow()
    if not isinstance(data, dict):
        allow()
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or native_path(data.get("cwd")) or os.getcwd())
    rpath = state_dir(project) / "routing.json"
    if not rpath.exists():
        allow()
    try:
        r = json.loads(rpath.read_text(encoding="utf-8"))
    except Exception:
        allow()
    if not r.get("active") or not r.get("until_done"):
        allow()
    if r.get("needs_human"):
        allow()
    blocks = int(r.get("blocks") or 0)
    if blocks >= int(r.get("max_blocks") or 6):
        allow()
    left = [u for u in r.get("units", []) if (u.get("status") or "pending") in ("pending", "running", "fail")]
    if any(u.get("tier") == "command" and u.get("status") == "running" for u in left) and live_background(data):
        allow()                                   # a command is running in the background: its end notification wakes the session
    reasons = []
    if left:
        reasons.append("units not finished: " + ", ".join(f"#{u.get('id')} {u.get('title', '')[:40]} [{u.get('status') or 'pending'}]" for u in left[:6]))
    check = adapter_check(project)  # never from routing.json
    check_error = None
    if check and not left:
        argv, why = safe_argv(check, project)
        if argv is None:
            reasons.append(f"check command refused ({why}); fix `check:` in .claude/smartuse.local.md")
        else:
            why, check_error = run_check(check, argv, project, r.get("check_error"))
            if why:
                reasons.append(why)
    if not reasons:
        allow()
    r["blocks"] = blocks + 1
    r["last_block"] = utc_now()
    if check_error:
        r["check_error"] = check_error
    try:
        rpath.write_text(json.dumps(r, indent=2), encoding="utf-8")
    except Exception:
        pass
    block("run-plan --until-done: keep going. " + " · ".join(reasons) +
          "\nFinish the units in order (one escalation each), then make the check pass. If a unit truly needs the human, "
          "write the exact question into routing.json as \"needs_human\" and end with it as your first line.")


try:
    main()
except SystemExit:
    raise
except Exception:
    allow()
