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
adapter `.claude/smartuse.local.md` (`check:`), is screened by the bash-guard rules, must start with a known test runner,
contains no shell metacharacters, and runs with shell=False. Its output is redacted (last 8 lines, secrets masked).
0 model tokens. Any error -> allow the stop (a gate must never trap the session).
"""
import json, os, sys, subprocess, pathlib, datetime, re, shlex

HOME = pathlib.Path(os.path.expanduser("~"))

RUNNERS = {"npm", "pnpm", "yarn", "bun", "npx", "pytest", "python", "python3", "make", "dotnet", "go", "cargo", "mvn", "gradle", "bash", "sh", "true", "false"}
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


def safe_argv(check, project):
    """Return argv for a check that is allowed to run, else None with a reason."""
    if META.search(check):
        return None, "shell metacharacters are not allowed in `check:`"
    for pat, why in guard_rules():
        if re.search(pat, check, re.I | re.S):
            return None, f"refused by bash-guard: {why}"
    try:
        argv = shlex.split(check)
    except ValueError as e:
        return None, f"cannot parse: {e}"
    if not argv or argv[0] not in RUNNERS:
        return None, f"`{argv[0] if argv else ''}` is not an allowed test runner ({', '.join(sorted(RUNNERS))})"
    if argv[0] in ("bash", "sh"):
        if len(argv) < 2 or argv[1].startswith(("-", "/", "~")) or ".." in argv[1] or not (project / argv[1]).is_file():
            return None, "bash/sh checks must name a script inside the repo (relative path, no flags)"
    return argv, ""


def redact(text):
    lines = [SECRET.sub(lambda m: m.group(1) + " [redacted]", l) for l in text.strip().splitlines()[-8:]]
    return "\n".join(l[:200] for l in lines)


def allow():
    sys.exit(0)


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason[:1800]}))
    sys.exit(0)


def main():
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
