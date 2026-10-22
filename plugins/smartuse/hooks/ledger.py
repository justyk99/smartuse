#!/usr/bin/env python3
"""ledger.py — smartuse receipts. Runs as a Stop hook (and SubagentStop). Deterministic, 0 model tokens.

Stop:        if ~/.claude/smartuse/projects/<project-dir-name>/pending.json exists (written by a skill at hand-off), sum the token usage
             in this session's transcript since pending.started_at, append one line to ~/.claude/smartuse/ledger.jsonl,
             delete pending.json. No pending file -> do nothing.
SubagentStop: if ~/.claude/smartuse/projects/<project-dir-name>/routing.json exists (written by run-plan), append one receipt line per
             finished agent to that folder's receipts.jsonl with its model and tokens, and attach those tokens to the plan step
             that is "running" in routing.json (one receipt per plan step: tier, model, why, override, outcome, verify, tokens,
             tokens by model).
             When run-plan closes (pending.json skill == run-plan), the Stop hook archives routing.json to runs/<started_at>_<task>.json.
Report:      bash py.sh ledger.py --report [N]   -> a table of the last N ledger lines + totals (used by /smartuse:ledger).
             bash py.sh ledger.py --receipts [task|all]  -> one row per plan step of the latest run (or a named run / every archived run),
                                                           from routing.json + runs/, plus a summary line with the agent-output share
                                                           by model (used by /smartuse:receipts).
             bash py.sh ledger.py --receipts [task|all] --json -> the same run(s) as JSON for scripts: one object (a list for "all")
                                                           with the steps verbatim and totals {input, output, by_model}.
             (py.sh = the plugin's launcher: python3, else python, else py -3 — on stock Windows python3 is only the Store stub.)
Never blocks a turn. Any error -> exit 0 silently (a receipt must never stop the work).
"""
import json, os, sys, re, time, datetime, pathlib, statistics

HOME = pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~"))   # HOME first: on Windows expanduser("~") reads USERPROFILE and ignores HOME (the tests and users who set HOME need it)
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


def by_model(totals):
    """{model: {calls, input, output}} from sum_usage totals; input = fresh + cache reads + cache creation, like total_input."""
    return {m: {"calls": int(d.get("calls") or 0),
                "input": int(d.get("input") or 0) + int(d.get("cache_read") or 0) + int(d.get("cache_create") or 0),
                "output": int(d.get("output") or 0)} for m, d in totals.items()}


def append(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")


def write_json(path, obj):
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def safe_name(s):
    return "".join(c if c.isalnum() or c in "-_." else "-" for c in str(s or ""))[:80] or "run"


def archive_run(sdir, p):
    """run-plan closed: keep its routing.json (the receipt per plan step) under runs/ so /smartuse:receipts can show it later."""
    routing = sdir / "routing.json"
    if p.get("skill") != "run-plan" or not routing.exists():
        return
    try:
        r = json.loads(routing.read_text(encoding="utf-8"))
    except Exception:
        return
    runs = sdir / "runs"; runs.mkdir(exist_ok=True)
    r.setdefault("closed_at", iso_now()); r["active"] = False
    write_json(runs / f"{safe_name(r.get('started_at') or p.get('started_at'))}_{safe_name(r.get('task') or p.get('task'))}.json", r)


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
        "started_at": since.strftime("%Y-%m-%dT%H:%M:%SZ") if since else None,
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
    try:
        archive_run(state_dir(project), p)
    except Exception:
        pass


def attach_to_step(sdir, rec):
    """One receipt per plan step: the agent's tokens land on the unit that run-plan marked "running" in routing.json.
    Exactly one running unit -> attach; none or several -> the receipt line stays unattached (never guess)."""
    routing = sdir / "routing.json"
    try:
        r = json.loads(routing.read_text(encoding="utf-8"))
    except Exception:
        return None
    running = [u for u in r.get("units", []) if u.get("status") == "running"]
    if len(running) != 1:
        return None
    u = running[0]
    u["agent_calls"] = int(u.get("agent_calls") or 0) + int(rec["assistant_calls"])
    u["agent_input"] = int(u.get("agent_input") or 0) + int(rec["total_input"])
    u["agent_output"] = int(u.get("agent_output") or 0) + int(rec["total_output"])
    u["agent_models"] = sorted(set(u.get("agent_models") or []) | set(rec["models"]))
    u["agents"] = (u.get("agents") or []) + [rec["agent_id"]]
    bm = u.get("agent_by_model") or {}
    for model, d in (rec.get("by_model") or {}).items():
        t = bm.setdefault(model, {"calls": 0, "input": 0, "output": 0})
        for k in ("calls", "input", "output"):
            t[k] = int(t.get(k) or 0) + int(d.get(k) or 0)
    u["agent_by_model"] = bm
    try:
        write_json(routing, r)
    except Exception:
        return None
    return u.get("id")


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
        "by_model": by_model(totals),
    }
    try:
        rec["unit"] = attach_to_step(state_dir(project), rec)
    except Exception:
        rec["unit"] = None
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


def fmt_k(n):
    n = int(n or 0)
    return f"{n/1000:.1f}k" if n >= 1000 else str(n)


def short_model(m):
    """claude-fable-5-1 -> fable (summary line only): drop the vendor prefix, a date stamp and the -N-N version."""
    return re.sub(r"(-\d+){1,2}$", "", re.sub(r"-\d{8}$", "", re.sub(r"^claude-", "", str(m)))) or str(m)


def short_models(models):
    """Short names per model; if two would collide (sonnet-4-5 and sonnet-5-5) only the vendor prefix goes."""
    s = {m: short_model(m) for m in models}
    if len(set(s.values())) < len(s):
        s = {m: re.sub(r"^claude-", "", str(m)) for m in models}
    return s


def run_totals(units):
    """Agent tokens over the plan steps: total in/out, the per-model sum of the units' agent_by_model, and the delegated
    (non-judgment) output for runs archived before agent_by_model existed."""
    t = {"input": 0, "output": 0, "by_model": {}}
    del_out = 0
    for u in units:
        ai, ao = int(u.get("agent_input") or 0), int(u.get("agent_output") or 0)
        t["input"] += ai; t["output"] += ao
        if u.get("tier") != "judgment":
            del_out += ao
        for model, d in (u.get("agent_by_model") or {}).items():
            x = t["by_model"].setdefault(model, {"calls": 0, "input": 0, "output": 0})
            for k in x:
                x[k] += int(d.get(k) or 0)
    return t, del_out


def summary_line(r, units, totals, del_out):
    n_done = sum(1 for u in units if u.get("status") in ("pass", "blocked"))
    n_pass = sum(1 for u in units if u.get("status") == "pass")
    line = (f"steps {n_pass} pass · {n_done - n_pass} blocked · {len(units) - n_done} open · "
            f"agent tokens in {fmt_k(totals['input'])} / out {fmt_k(totals['output'])}")
    bm, tot_out = totals["by_model"], totals["output"]
    if bm:
        names = short_models(bm)
        line += " · agent out by model: " + " · ".join(f"{names[m]} {(100 * d['output'] // tot_out) if tot_out else 0}%"
                                                        for m, d in sorted(bm.items(), key=lambda kv: (-kv[1]["output"], kv[0])))
    else:
        # a run archived by 0.3.0 has agent_models but no agent_by_model: keep the old delegated-share line
        models = sorted({m for u in units for m in (u.get("agent_models") or [])})
        if models:
            line += f" · delegated out {fmt_k(del_out)} ({(100 * del_out // tot_out) if tot_out else 0}% of agent output) on {', '.join(models)}"
    if r.get("needs_human"):
        line += f" · needs_human: {r['needs_human']}"
    return line


def pick_runs(which):
    """which: None -> the latest run (routing.json, else newest archived run); a task name -> the newest archived run whose
    task contains it (else the active run); "all" -> every archived run, newest first."""
    project = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    sdir = HOME / ".claude" / "smartuse" / "projects" / project.name
    runs = sorted((sdir / "runs").glob("*.json"), reverse=True) if (sdir / "runs").is_dir() else []
    if which == "all":
        picks = runs
    elif which:
        picks = [p for p in runs if which.lower() in p.name.lower()][:1]
        if not picks and (sdir / "routing.json").exists():
            picks = [sdir / "routing.json"]
    else:
        picks = [sdir / "routing.json"] if (sdir / "routing.json").exists() else runs[:1]
    return project, sdir, picks


def receipts(which=None, as_json=False):
    """One row per plan step plus a summary line (markdown), or with as_json the run(s) as JSON: one object for a single run,
    a list for "all" — {"task","dial","started_at","closed_at","active","needs_human","path","steps":[units verbatim],
    "totals":{"input","output","by_model":{model:{calls,input,output}}}}. Nothing else is printed in JSON mode."""
    project, sdir, picks = pick_runs(which)
    if not picks:
        if as_json:
            print(json.dumps([] if which == "all" else None)); return
        print(f"receipts: no run-plan run recorded for {project.name} ({sdir})"); return
    out = []
    for path in picks:
        try:
            r = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            if not as_json:
                print(f"receipts: cannot read {path}")
            continue
        units = r.get("units") or []
        totals, del_out = run_totals(units)
        if as_json:
            out.append({"task": r.get("task"), "dial": r.get("dial"), "started_at": r.get("started_at"), "closed_at": r.get("closed_at"),
                        "active": bool(r.get("active")), "needs_human": r.get("needs_human"), "path": str(path), "steps": units, "totals": totals})
            continue
        state = "active" if r.get("active") else "closed"
        print(f"receipts: {r.get('task')} · dial {r.get('dial')} · started {r.get('started_at')} · {state} · {len(units)} steps  ({path})")
        print("| # | step | tier | model | override | outcome | esc | verify | calls | in | out | check |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|")
        for u in units:
            ov = u.get("override") or {}
            ov_s = f"{ov.get('from')}→{ov.get('to')}" if ov else ""
            ai, ao = int(u.get("agent_input") or 0), int(u.get("agent_output") or 0)
            print(f"| {u.get('id')} | {str(u.get('title') or '')[:36]} | {u.get('tier') or ''} | {u.get('model') or ''} | {ov_s} | "
                  f"{u.get('status') or u.get('outcome') or 'pending'} | {'yes' if u.get('escalated') else ''} | {u.get('verify') or ''} | "
                  f"{u.get('agent_calls') or ''} | {fmt_k(ai) if ai else ''} | {fmt_k(ao) if ao else ''} | {str(u.get('check') or '')[:40]} |")
        print(summary_line(r, units, totals, del_out))
        if len(picks) > 1:
            print()
    if as_json:
        print(json.dumps(out if which == "all" else (out[0] if out else None), indent=2, ensure_ascii=False))


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
        since = parse_ts(r.get("started_at") or "")
        if not since or since > end:
            dur = int(r.get("duration_s") or 0)
            since = end - datetime.timedelta(seconds=dur + 5 if dur > 0 else 15 * 60)
        totals, turns = sum_usage(hits[0], since); f = flat(totals)
        r.update({"tokens": totals, "assistant_calls": turns, "total_input": f["input"] + f["cache_read"] + f["cache_create"], "total_output": f["output"], "recomputed": iso_now()})
        changed += 1
    LEDGER.write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in rows), encoding="utf-8")
    print(f"ledger: recomputed {changed} of {len(rows)} lines")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--recompute":
        recompute(); return
    if len(sys.argv) > 1 and sys.argv[1] == "--receipts":
        args = sys.argv[2:]
        receipts(next((a for a in args if a != "--json"), None), as_json="--json" in args); return
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
