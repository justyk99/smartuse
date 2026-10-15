#!/usr/bin/env python3
"""ledger.py — yk-kit receipts. Runs as a Stop hook (and SubagentStop). Deterministic, 0 model tokens.

Stop:        if <project>/.claude/yk-kit/pending.json exists (written by a skill at hand-off), sum the token usage
             in this session's transcript since pending.started_at, append one line to ~/.claude/yk-kit/ledger.jsonl,
             delete pending.json. No pending file -> do nothing.
SubagentStop: if <project>/.claude/yk-kit/routing.json exists (written by run-plan), append one receipt line per
             finished agent to <project>/.claude/yk-kit/receipts.jsonl with its model and tokens.
Report:      python3 ledger.py --report [N]   -> a table of the last N ledger lines + totals (used by /yk-kit:ledger).
Never blocks a turn. Any error -> exit 0 silently (a receipt must never stop the work).
"""
import json, os, sys, time, datetime, pathlib, statistics

HOME = pathlib.Path(os.path.expanduser("~"))
LEDGER = HOME / ".claude" / "yk-kit" / "ledger.jsonl"


def iso_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_ts(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def sum_usage(transcript, since=None):
    """Per-model token totals from assistant records with message.usage, optionally only after `since`."""
    totals, turns, seen = {}, 0, set()
    try:
        with open(transcript, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("type") != "assistant":
                    continue
                m = r.get("message") or {}
                u = m.get("usage") or {}
                if not u:
                    continue
                mid = m.get("id")  # parallel tool calls share one message id -> count usage once (official cost-tracking rule)
                if mid:
                    if mid in seen:
                        continue
                    seen.add(mid)
                if since:
                    t = parse_ts(r.get("timestamp") or "")
                    if t and t < since:
                        continue
                model = m.get("model") or "unknown"
                d = totals.setdefault(model, {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "calls": 0})
                d["input"] += int(u.get("input_tokens") or 0)
                d["output"] += int(u.get("output_tokens") or 0)
                d["cache_read"] += int(u.get("cache_read_input_tokens") or 0)
                d["cache_create"] += int(u.get("cache_creation_input_tokens") or 0)
                d["calls"] += 1
                turns += 1
    except Exception:
        pass
    return totals, turns


def flat(totals):
    out = {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0}
    for d in totals.values():
        for k in out:
            out[k] += d[k]
    return out


def append(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")


def on_stop(data):
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd())
    pending = project / ".claude" / "yk-kit" / "pending.json"
    if not pending.exists():
        return
    try:
        p = json.loads(pending.read_text(encoding="utf-8"))
    except Exception:
        pending.unlink(missing_ok=True)
        return
    since = parse_ts(p.get("started_at") or "")
    totals, turns = sum_usage(data.get("transcript_path") or "", since)
    f = flat(totals)
    now = datetime.datetime.now(datetime.timezone.utc)
    rec = {
        "ts": iso_now(),
        "project": project.name,
        "session_id": data.get("session_id"),
        "skill": p.get("skill"),
        "task": p.get("task"),
        "mode": p.get("mode"),
        "duration_s": int((now - since).total_seconds()) if since else None,
        "assistant_calls": turns,
        "tokens": totals,
        "total_input": f["input"] + f["cache_read"] + f["cache_create"],
        "total_output": f["output"],
        "self_check": p.get("self_check"),
        "corrections": p.get("corrections"),
        "notes": p.get("notes"),
    }
    append(LEDGER, rec)
    pending.unlink(missing_ok=True)


def on_subagent_stop(data):
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd())
    routing = project / ".claude" / "yk-kit" / "routing.json"
    if not routing.exists():
        return
    tp = data.get("agent_transcript_path") or data.get("transcript_path") or ""
    totals, turns = sum_usage(tp)
    f = flat(totals)
    rec = {
        "ts": iso_now(),
        "project": project.name,
        "session_id": data.get("session_id"),
        "agent_id": data.get("agent_id"),
        "agent_name": data.get("agent_name") or data.get("agent_type"),
        "models": list(totals.keys()),
        "assistant_calls": turns,
        "total_input": f["input"] + f["cache_read"] + f["cache_create"],
        "total_output": f["output"],
    }
    append(project / ".claude" / "yk-kit" / "receipts.jsonl", rec)


def report(n=10):
    if not LEDGER.exists():
        print("ledger: empty (no task recorded yet)")
        return
    rows = [json.loads(l) for l in LEDGER.read_text(encoding="utf-8").splitlines() if l.strip()]
    if not rows:
        print("ledger: empty")
        return
    print(f"ledger: {len(rows)} tasks  ({LEDGER})")
    print("| when | project | skill | mode | task | min | in-tokens | out-tokens | self-check |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in rows[-n:]:
        print(f"| {str(r.get('ts',''))[:16]} | {r.get('project')} | {r.get('skill')} | {r.get('mode')} | {str(r.get('task',''))[:40]} | "
              f"{(r.get('duration_s') or 0)//60} | {r.get('total_input',0):,} | {r.get('total_output',0):,} | {r.get('self_check') or ''} |")
    ins = [r.get("total_input", 0) for r in rows]; outs = [r.get("total_output", 0) for r in rows]
    print(f"median in {int(statistics.median(ins)):,} · median out {int(statistics.median(outs)):,} · total out {sum(outs):,}")
    by = {}
    for r in rows:
        k = f"{r.get('skill')}/{r.get('mode')}"; by.setdefault(k, []).append(r.get("total_output", 0))
    print("by skill/mode (median out): " + " · ".join(f"{k} {int(statistics.median(v)):,} (n={len(v)})" for k, v in by.items()))


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--report":
        report(int(sys.argv[2]) if len(sys.argv) > 2 else 10)
        return
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    ev = data.get("hook_event_name") or ""
    try:
        if ev == "SubagentStop":
            on_subagent_stop(data)
        else:
            on_stop(data)
    except Exception:
        pass


main()
