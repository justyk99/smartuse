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
0 model tokens. Any error -> allow the stop (a gate must never trap the session).
"""
import json, os, sys, subprocess, pathlib, datetime

HOME = pathlib.Path(os.path.expanduser("~"))


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
    check = (r.get("check") or "").strip()
    if check and not left:
        try:
            cp = subprocess.run(check, shell=True, cwd=str(project), capture_output=True, text=True, timeout=int(r.get("check_timeout_s") or 300))
            if cp.returncode != 0:
                tail = (cp.stdout + "\n" + cp.stderr).strip().splitlines()[-12:]
                reasons.append(f"check failed (exit {cp.returncode}): `{check}`\n" + "\n".join(tail))
        except subprocess.TimeoutExpired:
            reasons.append(f"check timed out: `{check}`")
        except Exception as e:
            reasons.append(f"check could not run: {e}")
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
