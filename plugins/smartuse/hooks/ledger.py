#!/usr/bin/env python3
"""ledger.py — smartuse receipts. Runs as a Stop hook (and SubagentStop). Deterministic, 0 model tokens.

Stop:        if ~/.claude/smartuse/projects/<project-dir-name>/pending.json exists (written by a skill at hand-off), sum the token usage
             in this session's transcript since pending.started_at, append one line to ~/.claude/smartuse/ledger.jsonl,
             delete pending.json. No pending file -> do nothing.
SubagentStop: if ~/.claude/smartuse/projects/<project-dir-name>/routing.json exists (written by run-plan), append one receipt line per
             finished agent to that folder's receipts.jsonl with its model and tokens.
Report:      python3 ledger.py --report [N]   -> a table of the last N ledger lines + totals (used by /smartuse:ledger).
Never blocks a turn. Any error -> exit 0 silently (a receipt must never stop the work).
"""
import json, os, sys, time, datetime, pathlib, statistics

HOME = pathlib.Path(os.path.expanduser("~"))
LEDGER = HOME / ".claude" / "smartuse" / "ledger.jsonl"


def iso_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_ts(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def sum_usage(transcript, since=None):
    """Per-model token totals from assistant records with message.usage, optionally only after `since`.
    Records that share one message id are partial views of the same API call (streamed content blocks / parallel
    tool calls); the LAST record carries the full counts, so per id we keep the MAX of each counter and count one call."""
    per_id, order = {}, []
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
                if since:
                    t = parse_ts(r.get("timestamp") or "")
                    if t and t < since:
                        continue
                mid = m.get("id") or f"_{len(order)}"
                cur = per_id.get(mid)
                vals = {"input": int(u.get("input_tokens") or 0), "output": int(u.get("output_tokens") or 0),
                        "cache_read": int(u.get("cache_read_input_tokens") or 0), "cache_create": int(u.get("cache_creation_input_tokens") or 0)}
                if cur is None:
                    per_id[mid] = {"model": m.get("model") or "unknown", **vals}; order.append(mid)
                else:
                    for k, v in vals.items():
                        cur[k] = max(cur[k], v)
    except Exception:
        pass
    totals, turns = {}, 0
    for mid in order:
        c = per_id[mid]
        d = totals.setdefault(c["model"], {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "calls": 0})
        for k in ("input", "output", "cache_read", "cache_create"):
            d[k] += c[k]
        d["calls"] += 1; turns += 1
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


def state_dir(project):
    """Per-project receipt state lives under the user's home, never inside the repo (team repos stay clean)."""
    d = HOME / ".claude" / "smartuse" / "projects" / project.name
    d.mkdir(parents=True, exist_ok=True)
    return d


def on_stop(data):
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd())
    pending = state_dir(project) / "pending.json"
    if not pending.exists():
        return
    # Two Stop hooks may run at once (a user-level copy and the plugin's): claim the file atomically so only one writes.
    claimed = pending.with_name(f"pending.{os.getpid()}.claimed")
    try:
        os.rename(pending, claimed)
    except OSError:
        return
    try:
        p = json.loads(claimed.read_text(encoding="utf-8"))
    except Exception:
        claimed.unlink(missing_ok=True)
        return
    pending = claimed
    since = parse_ts(p.get("started_at") or "")
    now0 = datetime.datetime.now(datetime.timezone.utc)
    if since and since > now0 + datetime.timedelta(seconds=60):
        # a forked skill wrote a local-time clock labelled Z (future) -> count the last 15 minutes instead of nothing
        since = now0 - datetime.timedelta(minutes=15)
        p["notes"] = (p.get("notes") or "") + " [started_at was in the future; window = last 15 min]"
    tp = data.get("transcript_path") or ""
    totals, turns = sum_usage(tp, since)
    # A forked skill (context: fork) or a subagent spends its tokens in <session>/subagents/agent-*.jsonl, not in the
    # main transcript: add every subagent file of this session that has usage after started_at.
    try:
        sub = pathlib.Path(tp).with_suffix("") / "subagents"
        for af in sorted(sub.glob("agent-*.jsonl")) if sub.is_dir() else []:
            t2, n2 = sum_usage(str(af), since)
            for model, d2 in t2.items():
                d = totals.setdefault(model, {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "calls": 0})
                for k in d2:
                    d[k] += d2[k]
            turns += n2
    except Exception:
        pass
    f = flat(totals)
    now = datetime.datetime.now(datetime.timezone.utc)
    rec = {
        "ts": iso_now(),
        "project": project.name,
        "session_id": data.get("session_id"),
        "skill": p.get("skill"),
        "task": p.get("task"),
        "mode": p.get("mode"),
        "duration_s": max(0, int((now - since).total_seconds())) if since else None,
        "assistant_calls": turns,
        "tokens": totals,
        "total_input": f["input"] + f["cache_read"] + f["cache_create"],
        "total_output": f["output"],
        "self_check": p.get("self_check"),
        "corrections": p.get("corrections"),
        "notes": p.get("notes"),
    }
    if LEDGER.exists():
        try:
            last = json.loads(LEDGER.read_text(encoding="utf-8").splitlines()[-1])
            if last.get("session_id") == rec["session_id"] and last.get("task") == rec["task"] and abs((parse_ts(last["ts"]) - now).total_seconds()) < 60:
                pending.unlink(missing_ok=True)
                return
        except Exception:
            pass
    append(LEDGER, rec)
    pending.unlink(missing_ok=True)


def on_subagent_stop(data):
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd())
    routing = state_dir(project) / "routing.json"
    if not routing.exists():
        return
    tp = data.get("agent_transcript_path") or data.get("transcript_path") or ""
    # Two SubagentStop hooks may run (a user-level copy and the plugin's): claim this agent once, atomically.
    aid = data.get("agent_id") or pathlib.Path(tp).stem
    marker = state_dir(project) / f"receipt.{aid}.done"
    try:
        fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
    except FileExistsError:
        return
    except Exception:
        pass
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
    append(state_dir(project) / "receipts.jsonl", rec)


def report(n=10):
    if not LEDGER.exists():
        print("ledger: empty (no task recorded yet)")
        return
    rows = [json.loads(l) for l in LEDGER.read_text(encoding="utf-8").splitlines() if l.strip()]
    if not rows:
        print("ledger: empty")
        return
    print(f"ledger: {len(rows)} tasks  ({LEDGER})")
    print("| when | project | skill | mode | task | min | fresh-in | cache-read | out | self-check |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for r in rows[-n:]:
        f = flat(r.get("tokens") or {})
        print(f"| {str(r.get('ts',''))[:16]} | {r.get('project')} | {r.get('skill')} | {r.get('mode')} | {str(r.get('task',''))[:40]} | "
              f"{(r.get('duration_s') or 0)/60:.1f} | {f['input'] + f['cache_create']:,} | {f['cache_read']:,} | {r.get('total_output',0):,} | {r.get('self_check') or ''} |")
    ins = [r.get("total_input", 0) for r in rows]; outs = [r.get("total_output", 0) for r in rows]
    print(f"median total-in {int(statistics.median(ins)):,} (mostly cache reads) · median out {int(statistics.median(outs)):,} · total out {sum(outs):,}")
    by = {}
    for r in rows:
        k = f"{r.get('skill')}/{r.get('mode')}"; by.setdefault(k, []).append(r.get("total_output", 0))
    print("by skill/mode (median out): " + " · ".join(f"{k} {int(statistics.median(v)):,} (n={len(v)})" for k, v in by.items()))


def recompute():
    """Re-sum every ledger line whose session transcript still exists (used after a counting-rule change)."""
    import glob
    if not LEDGER.exists():
        print("ledger: empty"); return
    rows = [json.loads(l) for l in LEDGER.read_text(encoding="utf-8").splitlines() if l.strip()]
    changed = 0
    for r in rows:
        sid = r.get("session_id"); end = parse_ts(r.get("ts") or "")
        if not sid or not end:
            continue
        hits = glob.glob(str(HOME / ".claude" / "projects" / "*" / f"{sid}.jsonl"))
        if not hits:
            continue
        since = end - datetime.timedelta(seconds=int(r.get("duration_s") or 0) + 5)
        totals, turns = sum_usage(hits[0], since); f = flat(totals)
        r.update({"tokens": totals, "assistant_calls": turns, "total_input": f["input"] + f["cache_read"] + f["cache_create"], "total_output": f["output"], "recomputed": iso_now()})
        changed += 1
    LEDGER.write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in rows), encoding="utf-8")
    print(f"ledger: recomputed {changed} of {len(rows)} lines")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--recompute":
        recompute(); return
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
