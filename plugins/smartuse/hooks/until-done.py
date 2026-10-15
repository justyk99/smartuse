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
hash from outside the repo (`--trust`), contains no shell metacharacters, and runs with shell=False. A file-guard hook denies
Claude's Write/Edit on the adapter and on the pin file. Its output is redacted (last 8 lines, secrets masked).
0 model tokens. Any error -> allow the stop (a gate must never trap the session).
"""
import json, os, sys, subprocess, pathlib, datetime, re, shlex

HOME = pathlib.Path(os.path.expanduser("~"))

# Exact command shapes that may run. Extra args are allowed only for the runners marked True, and only if they look like
# plain paths/names (no flags, no URLs, no package specs).
FIXED = {("npm", "test"): False, ("pnpm", "test"): False, ("yarn", "test"): False, ("bun", "test"): False,
         ("pytest",): True, ("make", "test"): False, ("make", "check"): False, ("cargo", "test"): False,
         ("go", "test", "./..."): False, ("dotnet", "test"): False, ("mvn", "test"): False, ("gradle", "test"): False,
         ("true",): False, ("false",): False}
ARG_OK = re.compile(r"^[A-Za-z0-9_./:-]+$")
TRUSTED = HOME / ".claude" / "smartuse" / "trusted-checks.json"   # human-pinned `bash <script>` checks: {project: {"check": str, "sha256": str}}
META = re.compile(r"[;&|`$<>\\]|\$\(|\n")
SECRET = re.compile(r"(?i)(token|password|passwd|secret|api[_-]?key|authorization)[^\n]{0,80}")


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


def trusted_match(check, project):
    """A `bash <relative script>` check runs only if the human pinned exactly this command + the script's hash."""
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
                  ", or a `bash <script-in-repo>` the human pinned with: python3 <hook dir>/until-done.py --trust \"bash path/to/check.sh\" (run from the repo)")


def trust(check):
    """Human command: pin `bash <script>` + its sha256 for the current repo. Needs a real terminal and a typed `y`:
    the model's Bash tool has no TTY, so it cannot pin anything (and bash-guard denies the command anyway)."""
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("refused: --trust must be typed by a human in an interactive terminal (no TTY here)"); return
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()).resolve()
    argv = shlex.split(check)
    if len(argv) != 2 or argv[0] not in ("bash", "sh") or argv[1].startswith(("-", "/", "~")) or ".." in argv[1] or not (project / argv[1]).is_file():
        print("refused: the form is `bash <relative script inside the repo>`"); return
    if input(f"Pin `{check}` for {project}? The script runs on every Stop while run-plan --until-done is active. [y/N] ").strip().lower() != "y":
        print("not pinned"); return
    TRUSTED.parent.mkdir(parents=True, exist_ok=True)
    try:
        data = json.loads(TRUSTED.read_text(encoding="utf-8"))
    except Exception:
        data = {}
    data[str(project)] = {"check": check, "sha256": sha256_of(project / argv[1]), "pinned": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    TRUSTED.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(f"pinned for {project}: {check} (sha256 {data[str(project)]['sha256'][:12]}…) — re-pin after you change the script")


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
        trust(sys.argv[2]); return
    try:
        data = json.load(sys.stdin)
    except Exception:
        allow()
    if data.get("stop_hook_active"):
        allow()
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd())
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
