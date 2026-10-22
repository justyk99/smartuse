#!/usr/bin/env python3
"""until-done.py — Stop hook: the deterministic half of `run-plan --until-done`.

When ~/.claude/smartuse/projects/<repo>/routing.json is active with "until_done": true, the turn may NOT end while
units are still pending / running / failed, or while the repo's check command fails. The hook blocks the stop with a
reason the model reads ("units left: 3, 4 · check failed: …"), so the session keeps working. It lets the turn end when:
  - routing.needs_human is set (the model wrote the question it needs answered),
  - every unit is pass / blocked and the check passes (or no check is configured),
  - stop_hook_active is true (Claude Code already blocked once this turn — never loop),
  - the hook has blocked `max_blocks` times for this run (default 6; stored in routing.json),
  - routing.active is false.
The check command is NEVER taken from routing.json (the model writes that file). It comes only from the human-authored
adapter `.claude/smartuse.local.md` (`check:`), is screened by the bash-guard rules, must be one of a few exact shapes
(`npm test`, `pytest`, `make test`, `cargo test`, `go test ./...`, `dotnet test`, …) or a `bash <script>` the human pinned by
hash in a ROOT-OWNED file (/etc/smartuse/trusted-checks.json, installed with sudo — `--trust` only prints the commands),
contains no shell metacharacters, and runs with shell=False. A file-guard hook denies
Claude's Write/Edit on the adapter and on the pin file. Its output is redacted (last 8 lines, secrets masked).
Windows: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, never inside the event
JSON, so a "cwd" taken from it goes through native_path() ("/c/Users/x" -> "C:/Users/x"). The block decision is JSON with
ASCII escapes (json.dumps), so stdout needs no re-encoding.
0 model tokens. Any error -> allow the stop (a gate must never trap the session).
"""
import json, os, sys, subprocess, pathlib, datetime, re, shlex

HOME = pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~"))   # HOME first: on Windows expanduser("~") reads USERPROFILE and ignores HOME (the tests and users who set HOME need it)

# Exact command shapes that may run. Extra args are allowed only for the runners marked True, and only if they look like
# plain paths/names (no flags, no URLs, no package specs).
FIXED = {("npm", "test"): False, ("pnpm", "test"): False, ("yarn", "test"): False, ("bun", "test"): False,
         ("pytest",): True, ("make", "test"): False, ("make", "check"): False, ("cargo", "test"): False,
         ("go", "test", "./..."): False, ("dotnet", "test"): False, ("mvn", "test"): False, ("gradle", "test"): False,
         ("true",): False, ("false",): False}
ARG_OK = re.compile(r"^[A-Za-z0-9_./:-]+$")
TRUSTED = pathlib.Path("/etc/smartuse/trusted-checks.json")   # human-pinned `bash <script>` checks, ROOT-OWNED: the agent runs as the user and cannot write it
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
                  ", or a `bash <script-in-repo>` the human pinned with: bash <hook dir>/py.sh <hook dir>/until-done.py --trust \"bash path/to/check.sh\" (run from the repo)")


def trust(check):
    """Human helper: prints the pin entry and the sudo command that installs it. Writes nothing itself."""
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
    print("\nRe-run this after you change the script (the hash is pinned).")


def redact(text):
    lines = [SECRET.sub(lambda m: m.group(1) + " [redacted]", l) for l in text.strip().splitlines()[-8:]]
    return "\n".join(l[:200] for l in lines)


def allow():
    sys.exit(0)


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason[:1800]}))
    sys.exit(0)


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--trust":
        trust(sys.argv[2]); return   # prints instructions only
    try:
        data = json.load(sys.stdin)
    except Exception:
        allow()
    if data.get("stop_hook_active"):
        allow()
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or native_path(data.get("cwd")) or os.getcwd())
    rpath = HOME / ".claude" / "smartuse" / "projects" / project.name / "routing.json"
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
    reasons = []
    if left:
        reasons.append("units not finished: " + ", ".join(f"#{u.get('id')} {u.get('title', '')[:40]} [{u.get('status') or 'pending'}]" for u in left[:6]))
    check = adapter_check(project)  # never from routing.json
    if check and not left:
        argv, why = safe_argv(check, project)
        if argv is None:
            reasons.append(f"check command refused ({why}); fix `check:` in .claude/smartuse.local.md")
        else:
            try:
                cp = subprocess.run(argv, shell=False, cwd=str(project), capture_output=True, text=True, timeout=300)
                if cp.returncode != 0:
                    reasons.append(f"check failed (exit {cp.returncode}): `{check}`\n" + redact(cp.stdout + "\n" + cp.stderr))
            except subprocess.TimeoutExpired:
                reasons.append(f"check timed out: `{check}`")
            except Exception as e:
                reasons.append(f"check could not run: {type(e).__name__}")
    if not reasons:
        allow()
    r["blocks"] = blocks + 1
    r["last_block"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
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
