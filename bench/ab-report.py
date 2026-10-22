#!/usr/bin/env python3
"""ab-report.py — aggregate one bench/ab.sh output dir into the routed-vs-not comparison (stdout + <out>/report.md).
Pure stdlib. Reads, per ask n: <n>-meta.json (the ask, the task.md path or "no kickoff"), <n>-stage1.json (claude's JSON for
the kickoff) and, per dial: <n>-<dial>.json (claude's JSON for the run-plan session: total_cost_usd, num_turns, duration_ms,
result), <n>-<dial>-receipts.json (the routing.json the Stop hook archived under runs/: one unit per plan step with status,
model, agent_output, agent_models) and <n>-<dial>-npmtest.txt (`npm test` in the result dir). A missing or unreadable file
is an n/a cell, never a crash. Usage: python3 ab-report.py <out dir>
"""
import datetime
import json
import os
import re
import statistics
import sys

DIAL_ORDER = ["off", "safe", "aggressive"]


def load_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            return fh.read()
    except Exception:
        return None


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def short_model(name):
    """claude-fable-5-1 -> fable, claude-sonnet-5-5 -> sonnet; anything else (haiku, session-model) stays as written."""
    m = re.match(r"^claude-([a-z]+)-\d", str(name or ""))
    return m.group(1) if m else (str(name) if name else "unknown")


def fmt_k(n, approx=False):
    if n is None:
        return "n/a"
    n = float(n)
    s = f"{n / 1000:.1f}k" if n >= 1000 else str(int(round(n)))
    return ("~" if approx else "") + s


def fmt_usd(x):
    return "n/a" if x is None else f"${x:.2f}"


def fmt_min(ms):
    return "n/a" if ms is None else f"{ms / 60000:.1f}"


def fmt_int(x):
    return "n/a" if x is None else str(int(x))


def pct(a, b):
    if a is None or b is None or b == 0:
        return None
    return int(round((a - b) / b * 100))


def fmt_pct(p):
    if p is None:
        return "n/a"
    p = int(round(p))
    return "0%" if p == 0 else f"{p:+d}%"


def cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def split_by_model(units):
    """{short model: agent output}, {short model: approximate?}.
    One `agent_output` per plan step, a LIST of models per step (build + verify agents land on the same step):
    one model -> attributed to the step's `model`; several -> split evenly and marked approximate (see the report footnote)."""
    share, approx = {}, {}
    for u in units:
        out = num(u.get("agent_output")) or 0.0
        if out <= 0:
            continue
        models = [m for m in (u.get("agent_models") or []) if m]
        if len(models) <= 1:
            name = short_model(u.get("model") or (models[0] if models else "unknown"))
            share[name] = share.get(name, 0.0) + out
            approx.setdefault(name, False)
        else:
            for m in models:
                name = short_model(m)
                share[name] = share.get(name, 0.0) + out / len(models)
                approx[name] = True
    return share, approx


def fmt_by_model(share, approx):
    if not share:
        return "n/a"
    return " · ".join(f"{m} {fmt_k(v, approx.get(m, False))}" for m, v in sorted(share.items(), key=lambda kv: (-kv[1], kv[0])))


def npm_test(path):
    text = read_text(path)
    if text is None:
        return "n/a"
    m = re.search(r"Tests:\s*(.*?)(\d+)\s+total", text)
    if m:
        passed = re.search(r"(\d+)\s+passed", m.group(1))
        failed = re.search(r"(\d+)\s+failed", m.group(1))
        s = f"{int(passed.group(1)) if passed else 0}/{m.group(2)}"
        return s + (f" ({failed.group(1)} failed)" if failed else "")
    m = re.search(r"npm test exit code: (\d+)", text)
    if m:
        return "pass (no jest summary)" if m.group(1) == "0" else f"fail (exit {m.group(1)})"
    return "n/a"


def dial_record(out, n, dial):
    j = load_json(os.path.join(out, f"{n}-{dial}.json"))
    r = load_json(os.path.join(out, f"{n}-{dial}-receipts.json"))
    rec = {"dial": dial, "cost": None, "ms": None, "turns": None, "out": None, "steps": "n/a", "needs_human": "n/a",
           "by_model": "n/a", "npm": npm_test(os.path.join(out, f"{n}-{dial}-npmtest.txt")), "note": ""}
    if isinstance(j, dict):
        rec["cost"], rec["ms"], rec["turns"] = num(j.get("total_cost_usd")), num(j.get("duration_ms")), num(j.get("num_turns"))
        sub = j.get("subtype")
        if j.get("is_error") or (sub and sub != "success"):
            rec["note"] = str(sub or "error")
        result = j.get("result")
        if isinstance(result, str) and result.lstrip().startswith("NEEDS YOU"):
            rec["needs_human"] = "yes"
    else:
        rec["note"] = "no claude JSON"
    if isinstance(r, dict):
        units = [u for u in (r.get("units") or []) if isinstance(u, dict)]
        p = sum(1 for u in units if u.get("status") == "pass")
        b = sum(1 for u in units if u.get("status") == "blocked")
        rec["steps"] = f"{p}/{b}/{len(units) - p - b}"
        rec["needs_human"] = "yes" if r.get("needs_human") else ("yes" if rec["needs_human"] == "yes" else "no")
        rec["out"] = sum(num(u.get("agent_output")) or 0.0 for u in units)
        rec["share"], rec["approx"] = split_by_model(units)
        rec["by_model"] = fmt_by_model(rec["share"], rec["approx"])
        if r.get("active"):
            rec["note"] = (rec["note"] + " · " if rec["note"] else "") + "run not closed"
    else:
        rec["note"] = (rec["note"] + " · " if rec["note"] else "") + "no receipts"
    return rec


def median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    if not os.path.isdir(out):
        print(f"ab-report: not a directory: {out}", file=sys.stderr)
        return 2
    run = load_json(os.path.join(out, "run.json")) or {}
    metas = []
    for f in os.listdir(out):
        m = re.match(r"^(\d+)-meta\.json$", f)
        if m:
            d = load_json(os.path.join(out, f))
            if isinstance(d, dict):
                d.setdefault("n", int(m.group(1)))
                metas.append(d)
    metas.sort(key=lambda d: int(d.get("n") or 0))
    if not metas:
        print(f"ab-report: no <n>-meta.json in {out} (nothing ran?)", file=sys.stderr)
        return 2
    dials = run.get("dials") or sorted({d for m in metas for d in (m.get("dials") or [])},
                                       key=lambda d: DIAL_ORDER.index(d) if d in DIAL_ORDER else 99)

    L = []
    L.append(f"# A/B: routed vs not — {os.path.basename(os.path.abspath(out))}")
    L.append("")
    hdr = [f"{len(metas)} ask(s)", "dials: " + ", ".join(dials)]
    if run.get("dry_run"):
        hdr.append("DRY RUN (bench/fake-claude.sh stood in for claude: fixture numbers, nothing spent)")
    if run.get("claude_version"):
        hdr.append(f"claude: {run['claude_version']}")
    caps = run.get("caps") or {}
    if caps.get("stage1") and caps.get("stage2"):
        hdr.append(f"caps: kickoff {caps['stage1'].get('max_turns')} turns / ${caps['stage1'].get('max_budget_usd')}, "
                   f"run-plan {caps['stage2'].get('max_turns')} turns / ${caps['stage2'].get('max_budget_usd')} per dial")
    hdr.append("generated " + datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"))
    L.append(" · ".join(hdr))
    L.append("")
    L.append("| # | ask | dial | steps pass/blocked/open | needs_human | npm test | agent out by model | agent out | cost | min | turns | note |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    per_ask = []  # (meta, {dial: rec})
    for meta in metas:
        n, ask = meta.get("n"), cell(meta.get("ask") or "")
        if not meta.get("kickoff"):
            L.append(f"| {n} | {ask} | — | no kickoff | n/a | n/a | n/a | n/a | n/a | n/a | n/a | {cell(meta.get('note') or 'no task.md after stage 1')} |")
            per_ask.append((meta, {}))
            continue
        recs = {}
        for dial in dials:
            rec = dial_record(out, n, dial)
            recs[dial] = rec
            L.append(f"| {n} | {ask} | {dial} | {rec['steps']} | {rec['needs_human']} | {rec['npm']} | {rec['by_model']} | "
                     f"{fmt_k(rec['out'])} | {fmt_usd(rec['cost'])} | {fmt_min(rec['ms'])} | {fmt_int(rec['turns'])} | {rec['note']} |")
        per_ask.append((meta, recs))

    L.append("")
    L.append("## Per ask, vs `off` (negative = cheaper than everything on the session model)")
    L.append("")
    deltas = {d: {"out": [], "cost": []} for d in dials}
    for meta, recs in per_ask:
        n, ask = meta.get("n"), cell(meta.get("ask") or "")
        s1 = load_json(os.path.join(out, f"{n}-stage1.json"))
        kick = "no kickoff"
        if isinstance(s1, dict):
            kick = f"kickoff {fmt_usd(num(s1.get('total_cost_usd')))} · {fmt_min(num(s1.get('duration_ms')))} min · {fmt_int(num(s1.get('num_turns')))} turns"
            if meta.get("kickoff"):
                kick += f" · `{cell(meta['kickoff'])}`"
        L.append(f"- **{n} · {ask}** — {kick}")
        if not recs:
            continue
        base = recs.get("off")
        if base is None:
            L.append("  - no `off` run in this set: nothing to compare against")
            continue
        for dial in dials:
            if dial == "off":
                continue
            rec = recs[dial]
            if rec["out"] is None or base["out"] is None:
                L.append(f"  - {dial} vs off: n/a (receipts missing for {'both' if rec['out'] is None and base['out'] is None else dial if rec['out'] is None else 'off'})")
                continue
            p_out, p_cost = pct(rec["out"], base["out"]), pct(rec["cost"], base["cost"])
            deltas[dial]["out"].append(p_out)
            deltas[dial]["cost"].append(p_cost)
            L.append(f"  - {dial} vs off: agent out {fmt_pct(p_out)} · cost {fmt_pct(p_cost)}"
                     f"  ({fmt_k(rec['out'])} vs {fmt_k(base['out'])} · {fmt_usd(rec['cost'])} vs {fmt_usd(base['cost'])})")

    L.append("")
    n_ok = sum(1 for _, recs in per_ask if recs)
    L.append(f"## Medians per dial ({n_ok} ask(s) with a kickoff)")
    L.append("")
    for dial in dials:
        rs = [recs[dial] for _, recs in per_ask if recs and dial in recs]
        if not rs:
            continue
        line = (f"- **{dial}**: agent out {fmt_k(median([r['out'] for r in rs]))} · cost {fmt_usd(median([r['cost'] for r in rs]))} · "
                f"{fmt_min(median([r['ms'] for r in rs]))} min · {fmt_int(median([r['turns'] for r in rs]))} turns"
                f" (n={len(rs)}" + (f", receipts for {sum(1 for r in rs if r['out'] is not None)}" if any(r['out'] is None for r in rs) else "") + ")")
        if dial != "off" and (deltas[dial]["out"] or deltas[dial]["cost"]):
            line += f" · vs off (median of the per-ask deltas): agent out {fmt_pct(median(deltas[dial]['out']))} · cost {fmt_pct(median(deltas[dial]['cost']))}"
        share, approx = {}, {}
        for r in rs:
            for m, v in (r.get("share") or {}).items():
                share[m] = share.get(m, 0.0) + v
                approx[m] = approx.get(m, False) or r["approx"].get(m, False)
        if share:
            line += f" · agent out by model, summed: {fmt_by_model(share, approx)}"
        L.append(line)

    L.append("")
    L.append("## Notes")
    L.append("")
    L.append("- **agent out** = sum of `agent_output` over the plan steps of the archived run: the tokens the SubagentStop hook attached to "
             "the step that was running, never an estimate. Judgment steps run in the session itself and carry no agent tokens. "
             "**cost** = `total_cost_usd` of the run-plan session (stage 2 only; the kickoff is shared by the dials and listed per ask). "
             "**min** = `duration_ms` / 60000, **turns** = `num_turns`, both from claude's JSON.")
    L.append("- **Per-model split is approximate where marked `~`.** The hook records ONE `agent_output` per plan step and the LIST of "
             "models that ran on it (a build agent and its verify agent land on the same step). A step with a single model is attributed "
             "to the step's `model`. A step with several models is split EVENLY between them and each share is marked `~`: the true "
             "per-model share of that step is not recorded. Totals, cost and the percent lines are exact; only the by-model column is approximate.")
    L.append("- **steps** = pass/blocked/open (open = pending, running or failed). **needs_human** = the run stopped on a question for the "
             "human (`needs_human` in the receipts, or a final message starting with `NEEDS YOU`). **npm test** = jest's passed/total from "
             "`npm test` in the result dir (n/a in a dry run). **note** = claude's non-success subtype (a cap hit), missing files, or a run "
             "that never closed.")
    text = "\n".join(L) + "\n"
    try:
        with open(os.path.join(out, "report.md"), "w", encoding="utf-8") as fh:
            fh.write(text)
    except Exception as e:
        print(f"ab-report: could not write report.md: {e}", file=sys.stderr)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
