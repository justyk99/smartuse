#!/usr/bin/env python3
"""ab-report.py — aggregate one bench/ab.sh output dir into the routed-vs-not comparison (stdout + <out>/report.md).
Pure stdlib. Reads run.json (parameters; `model` = the --model pin, null when claude's default ran) and, per ask n:
<n>-meta.json (the ask, the task.md path or "no kickoff"), <n>-stage1.json (claude's JSON for the kickoff: cost, turns,
duration, `modelUsage`) and, per dial: <n>-<dial>.json (claude's JSON for the run-plan session: total_cost_usd, num_turns,
duration_ms, result, `modelUsage` keyed by the models that ran in that session), <n>-<dial>-receipts.json (the routing.json
the Stop hook archived under runs/: one unit per plan step with status, model, agent_output, agent_models and, since 0.4.0,
agent_by_model = {model: {calls, input, output}}) and <n>-<dial>-npmtest.txt (`npm test` in the result dir). A missing or
unreadable file is an n/a cell, never a crash. A run that did no work (no step passed) keeps its row but feeds no percent
line and no median. Usage: python3 ab-report.py <out dir>
"""
import datetime
import json
import os
import re
import statistics
import sys

DIAL_ORDER = ["off", "safe", "aggressive"]
NO_DATA = "—"   # the agent out of a run that did no work: no agent ran, there is nothing to compare (not a measured 0)
NEEDS_YOU = re.compile(r"^[\s*_#>`]*NEEDS YOU")   # the final message, with or without markdown emphasis around it


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
    """ONE shortening for every model cell: claude-opus-5-5 -> opus-5-5, claude-sonnet-4-5-20250929 -> sonnet-4-5 (the
    `claude-` prefix and a date suffix go; the version stays, it is what differs between sessions). Anything else (the shim's
    `session-model`, an alias such as `opus`) stays as written."""
    s = str(name) if name else ""
    if not s:
        return "unknown"
    s = re.sub(r"^claude-", "", s)
    return re.sub(r"-\d{8}$", "", s)


def session_models(j):
    """The models claude's JSON says ran in a session: the keys of `modelUsage`, shortened, in claude's order (the session
    model first, then the models its agents ran on). [] when the JSON or the object is missing."""
    mu = j.get("modelUsage") if isinstance(j, dict) else None
    return [short_model(k) for k in mu] if isinstance(mu, dict) else []


def fmt_models(models):
    if not models:
        return "n/a"
    return models[0] + (f" (+{', '.join(models[1:])})" if len(models) > 1 else "")


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
    A step the hook recorded with `agent_by_model` ({model: {calls, input, output}}, since 0.4.0) is exact: each model gets
    its own output. An older archive has ONE `agent_output` per step and the LIST of models that ran on it (build + verify
    agents land on the same step): one model -> attributed to the step's `model`; several -> split evenly and marked
    approximate (see the report footnote)."""
    share, approx = {}, {}

    def add(name, out, is_approx):
        share[name] = share.get(name, 0.0) + out
        approx[name] = approx.get(name, False) or is_approx

    for u in units:
        bm = u.get("agent_by_model")
        if isinstance(bm, dict) and bm:
            for m, d in bm.items():
                out = num(d.get("output") if isinstance(d, dict) else None) or 0.0
                if out > 0:
                    add(short_model(m), out, False)
            continue
        out = num(u.get("agent_output")) or 0.0
        if out <= 0:
            continue
        models = [m for m in (u.get("agent_models") or []) if m]
        if len(models) <= 1:
            add(short_model(u.get("model") or (models[0] if models else "unknown")), out, False)
        else:
            for m in models:
                add(short_model(m), out / len(models), True)
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
    rec = {"dial": dial, "cost": None, "ms": None, "turns": None, "out": None, "steps": "n/a", "passed": None,
           "needs_human": "n/a", "models": [], "share": {}, "approx": {}, "no_work": False,
           "npm": npm_test(os.path.join(out, f"{n}-{dial}-npmtest.txt")), "notes": []}
    if isinstance(j, dict):
        rec["cost"], rec["ms"], rec["turns"] = num(j.get("total_cost_usd")), num(j.get("duration_ms")), num(j.get("num_turns"))
        rec["models"] = session_models(j)
        sub = j.get("subtype")
        if j.get("is_error") or (sub and sub != "success"):
            rec["notes"].append(str(sub or "error"))
        result = j.get("result")
        if isinstance(result, str) and NEEDS_YOU.match(result):
            rec["needs_human"] = "yes"
    else:
        rec["notes"].append("no claude JSON")
    if isinstance(r, dict):
        units = [u for u in (r.get("units") or []) if isinstance(u, dict)]
        p = sum(1 for u in units if u.get("status") == "pass")
        b = sum(1 for u in units if u.get("status") == "blocked")
        rec["passed"] = p
        rec["steps"] = f"{p}/{b}/{len(units) - p - b}"
        rec["needs_human"] = "yes" if r.get("needs_human") else ("yes" if rec["needs_human"] == "yes" else "no")
        rec["out"] = sum(num(u.get("agent_output")) or 0.0 for u in units)
        rec["share"], rec["approx"] = split_by_model(units)
        if r.get("active"):
            rec["notes"].append("run not closed")
        if p == 0:   # no step passed: nothing to compare, whatever was spent
            rec["no_work"] = True
            rec["notes"].append("no work done — stopped on NEEDS YOU before any step" if rec["needs_human"] == "yes"
                                else "no work done — no step passed")
    else:
        rec["notes"].append("no receipts")
    rec["note"] = " · ".join(rec["notes"])
    return rec


def out_cell(rec):
    if rec["out"] is None:
        return "n/a"
    if rec["no_work"] and rec["out"] <= 0:
        return NO_DATA
    return fmt_k(rec["out"])


def by_model_cell(rec):
    if rec["out"] is None:
        return "n/a"
    if rec["share"]:
        return fmt_by_model(rec["share"], rec["approx"])
    return NO_DATA if rec["no_work"] else "0"


def median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def main():
    for stream in (sys.stdout, sys.stderr):   # the report has "·" and "→": on Windows a pipe defaults to cp1252
        try:
            stream.reconfigure(encoding="utf-8")
        except Exception:
            pass
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
    if run.get("model"):
        hdr.append(f"model: {run['model']} (pinned with --model)")
    else:
        hdr.append("model: not pinned (claude's default per session; pass --model to pin)")
    caps = run.get("caps") or {}
    if caps.get("stage1") and caps.get("stage2"):
        hdr.append(f"caps: kickoff {caps['stage1'].get('max_turns')} turns / ${caps['stage1'].get('max_budget_usd')}, "
                   f"run-plan {caps['stage2'].get('max_turns')} turns / ${caps['stage2'].get('max_budget_usd')} per dial")
    hdr.append("generated " + datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"))
    L.append(" · ".join(hdr))
    L.append("")
    L.append("| # | ask | dial | session model | steps pass/blocked/open | needs_human | npm test | agent out by model | agent out | cost | min | turns | note |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    per_ask = []  # (meta, {dial: rec})
    for meta in metas:
        n, ask = meta.get("n"), cell(str(meta.get("ask") or "").rstrip("\r"))
        if not meta.get("kickoff"):
            L.append(f"| {n} | {ask} | — | n/a | no kickoff | n/a | n/a | n/a | n/a | n/a | n/a | n/a | {cell(meta.get('note') or 'no task.md after stage 1')} |")
            per_ask.append((meta, {}))
            continue
        recs = {}
        for dial in dials:
            rec = dial_record(out, n, dial)
            recs[dial] = rec
            L.append(f"| {n} | {ask} | {dial} | {fmt_models(rec['models'])} | {rec['steps']} | {rec['needs_human']} | {rec['npm']} | "
                     f"{by_model_cell(rec)} | {out_cell(rec)} | {fmt_usd(rec['cost'])} | {fmt_min(rec['ms'])} | {fmt_int(rec['turns'])} | "
                     f"{cell(rec['note'])} |")
        per_ask.append((meta, recs))

    L.append("")
    L.append("## Per ask, vs `off` (negative = cheaper than everything on the session model)")
    L.append("")
    deltas = {d: {"out": [], "cost": []} for d in dials}
    for meta, recs in per_ask:
        n, ask = meta.get("n"), cell(str(meta.get("ask") or "").rstrip("\r"))
        s1 = load_json(os.path.join(out, f"{n}-stage1.json"))
        s1m = session_models(s1)
        if isinstance(s1, dict):
            kick = (f"kickoff {fmt_usd(num(s1.get('total_cost_usd')))} · {fmt_min(num(s1.get('duration_ms')))} min · "
                    f"{fmt_int(num(s1.get('num_turns')))} turns · on {fmt_models(s1m)}")
        else:
            kick = "kickoff: no claude JSON" if meta.get("kickoff") else "no kickoff"
        if meta.get("kickoff"):
            kick += f" · `{cell(meta['kickoff'])}`"
        L.append(f"- **{n} · {ask}** — {kick}")
        if not recs:
            continue
        firsts = [("kickoff", s1m[0])] if s1m else []
        firsts += [(dial, recs[dial]["models"][0]) for dial in dials if recs[dial]["models"]]
        if len({m for _, m in firsts}) > 1:
            L.append("  - **models differ** (" + ", ".join(f"{k} on {m}" for k, m in firsts) +
                     "): claude's default decided per session, so the dials did not run on one model; pin it with `ab.sh --model`")
        base = recs.get("off")
        if base is None:
            L.append("  - no `off` run in this set: nothing to compare against")
            continue
        for dial in dials:
            if dial == "off":
                continue
            rec = recs[dial]
            idle = [d for d, x in (("off", base), (dial, rec)) if x["no_work"]]
            if idle:
                L.append(f"  - {dial} vs off: {' and '.join(idle)} did no work → no comparison")
                continue
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
    L.append(f"## Medians per dial ({n_ok} ask(s) with a kickoff; rows that did no work are excluded and counted)")
    L.append("")
    for dial in dials:
        rs_all = [recs[dial] for _, recs in per_ask if recs and dial in recs]
        if not rs_all:
            continue
        rs = [r for r in rs_all if not r["no_work"]]
        excluded = len(rs_all) - len(rs)
        count = f"n={len(rs)}"
        if any(r["out"] is None for r in rs):
            count += f", receipts for {sum(1 for r in rs if r['out'] is not None)}"
        if excluded:
            count += f"; {excluded} excluded: no work done"
        if not rs:
            L.append(f"- **{dial}**: no row with work done ({count})")
            continue
        line = (f"- **{dial}**: agent out {fmt_k(median([r['out'] for r in rs]))} · cost {fmt_usd(median([r['cost'] for r in rs]))} · "
                f"{fmt_min(median([r['ms'] for r in rs]))} min · {fmt_int(median([r['turns'] for r in rs]))} turns ({count})")
        if dial != "off" and (deltas[dial]["out"] or deltas[dial]["cost"]):
            line += (f" · vs off (median of the per-ask deltas, {len(deltas[dial]['cost'])} compared): "
                     f"agent out {fmt_pct(median(deltas[dial]['out']))} · cost {fmt_pct(median(deltas[dial]['cost']))}")
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
    L.append("- **session model** = the keys of claude's `modelUsage` for the run-plan session, shortened (`claude-opus-5-5` → `opus-5-5`): "
             "the session model first, then in brackets the models its agents ran on. The kickoff's model is on the per-ask line. "
             "Without `ab.sh --model`, claude's default decides per session and can differ between the kickoff and the run-plan "
             "sessions, or between dials; the per-ask line flags that as **models differ**, and then the dials are not comparable.")
    L.append(f"- **no work done** = no step passed: the run stopped on NEEDS YOU before any step, or nothing passed. The row stays in "
             f"the table (see its note) but feeds no percent line and no median; the per-ask lines say `did no work → no comparison` "
             f"and the median lines say how many rows were excluded. Its agent out is `{NO_DATA}`, not 0: no agent ran, so there is "
             f"nothing to compare. A measured 0 (steps passed, no agent used) stays 0.")
    L.append("- **Per-model split.** A step the hook recorded with `agent_by_model` ({model: {calls, input, output}}, hooks 0.4.0 and "
             "later) is exact: each model's share is the hook's own sum for that model, so the by-model column carries no `~`. An "
             "archive from before that records ONE `agent_output` per step and the LIST of models that ran on it (a build agent and "
             "its verify agent land on the same step): a step with a single model is attributed to the step's `model`, a step with "
             "several models is split EVENLY between them and each share is marked `~`, because the true per-model share of that "
             "step was not recorded. Totals, cost and the percent lines are exact either way.")
    L.append("- **steps** = pass/blocked/open (open = pending, running or failed). **needs_human** = the run stopped on a question for the "
             "human (`needs_human` in the receipts, or a final message starting with `NEEDS YOU`). **npm test** = jest's passed/total from "
             "`npm test` in the result dir (n/a in a dry run). **note** = claude's non-success subtype (a cap hit), missing files, a run "
             "that never closed, or `no work done`.")
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
