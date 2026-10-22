# smartuse benchmark

Runs `/smartuse:make-prompt quick dry <ask>` on 5 typical asks against a tiny sample repo and prints one comparison table.

## Run

```bash
cd smartuse/bench
./run.sh                          # loads ../plugins/smartuse via --plugin-dir
./run.sh --plugin-dir /path/to/smartuse
```

Needs `claude` and python 3, found the way the hooks find it (`plugins/smartuse/hooks/py.sh` tries `python3`, `python`, `py -3`, so Git Bash on Windows works); no `jq`. Each ask runs on a fresh temp copy of `sample-repo/` (git-initialised), so the fixture stays clean. Raw JSON goes to `results/<n>.json`. Runs spend plan usage (cap: 60 turns, $4 each).

## Table columns

- Cost: `total_cost_usd` for the run.
- Turns: `num_turns`, model round trips.
- Minutes: `duration_ms` / 60000.
- Prompt saved: result text contains "Prompt saved".
- Self-check: result text contains a "✓" line.

`sample-repo/` has one planted rabbit hole: `computeTotal()` in `orders.js` rounds silently (see its TODO). Good runs notice it without wandering off.

Numbers depend on your plan's models and on Claude Code's version; publish the version with the table.

## A/B: routed vs not

`ab.sh` measures what the `run-plan` dial buys (the 0.4 roadmap item). Per ask in `asks.txt` it runs ONE kickoff (`/smartuse:make-prompt quick <ask>`) on a fresh, git-initialised copy of `sample-repo/` with `npm install` done, snapshots that kickoff, then runs `/smartuse:run-plan <task.md> --until-done --routing <dial>` once per dial (`off`, `safe`, `aggressive`) on an identical restore of the snapshot — the dials start from the same task.md and differ only in the routing. **Pin the session model with `--model <id or alias>`** for every real run: it is passed as `--model` to every session (stage 1 and 2) and recorded in `run.json`. Without it claude's default decides per session, and A/B run 1 ran its kickoff on one model and its three run-plan sessions on another, which makes the dials incomparable (the report flags such a run as **models differ**). Each run dir gets a unique basename (`ab-<n>-<dial>-<timestamp>`), which is the key of its receipt state under `~/.claude/smartuse/projects/`; when run-plan closes, the Stop hook archives `routing.json` there under `runs/`, and `ab.sh` copies that file (the per-step receipts) next to claude's JSON. Nothing is written inside the fixture or the repo except the out dir and the dependency cache.

```bash
cd smartuse/bench
./ab.sh                                   # all asks, dials off,safe,aggressive, out: results/ab/<UTC timestamp>/
./ab.sh --asks 2 --dials off,aggressive   # the first 2 asks, two dials
./ab.sh --model claude-opus-5-5 --asks 2  # pin the session model (do this for every real run; alias or full id)
./ab.sh --dry-run                         # the whole pipeline through fake-claude.sh: no model, nothing spent
python3 ab-report.py results/ab/<ts>/     # re-print the table from the raw files (Windows: bash ../plugins/smartuse/hooks/py.sh ab-report.py ...)
```

Flags: `--asks N` (first N lines of asks.txt) · `--dials a,b,c` · `--model ID` (pin the session model of every session; default: claude's default, not pinned) · `--plugin-dir P` (default `../plugins/smartuse`) · `--out DIR` · `--dry-run`. `CLAUDE_BIN=/path/to/claude` overrides the binary (the dry run points it at `fake-claude.sh` unless you set it). Needs `claude`, `git`, `tar`, `npm` and python 3; no `jq`. Python is found the way the hooks find it, through `plugins/smartuse/hooks/py.sh` (`python3`, `python` or `py -3`), so the bench runs in Git Bash on Windows, where `python3` is the Store stub and there is no `jq`.

**Cost and caps.** Every session is a real Claude session and spends your plan usage: on the bench repo ≈ $5–6 per ask per dial (the kickoff ≈ $1.5 / 2.5 min, once per ask; each `run-plan --until-done` ≈ $2–4 / 6 min), i.e. ≈ $50 and 1.5 h for 5 asks × 3 dials. The caps are passed to `claude -p` and are hard: stage 1 `--max-turns 60 --max-budget-usd 4`, stage 2 `--max-turns 40 --max-budget-usd 5`, so N asks × M dials can never exceed N × ($4 + M × $5). The script prints this NOTE with the computed cap before it starts; Ctrl-C stops between sessions and keeps what was collected; a run that hit a cap shows its subtype in the report's `note` column. Dependencies are installed once and cached in `bench/.cache/node_modules` (reused with `cp -a`).

**Files per (ask n, dial)** in the out dir: `<n>-stage1.json` (claude's JSON for the kickoff), `<n>-meta.json` (the ask and the task.md path, or `no kickoff`), `<n>-<dial>.json` (claude's JSON for the run-plan session: `total_cost_usd`, `num_turns`, `duration_ms`, `result`, `modelUsage` keyed by the models that ran in the session), `<n>-<dial>-receipts.json` (the archived `routing.json`: one unit per plan step with tier, model, status, verify, `agent_output`, `agent_models` and, since hooks 0.4.0, `agent_by_model` = `{model: {calls, input, output}}`), `<n>-<dial>-npmtest.txt` (`npm test` in the result dir plus its exit code), `<n>-*.err` (stderr), `run.json` (parameters, caps, claude version, the pinned `model` or `null`) and `report.md`. An ask whose kickoff left no `.task/ACTIVE/*/task.md` gets one `no kickoff` row and no dial runs. The per-run state dirs under `~/.claude/smartuse/projects/ab-*` are removed once their receipts are copied; the ledger lines the hooks write to `~/.claude/smartuse/ledger.jsonl` stay (one per session, like any other run).

**The report** (`ab-report.py`, stdlib only; printed and written to `<out>/report.md`): one row per (ask, dial) — session model · steps pass/blocked/open · needs_human · npm test passed/total · agent out by model · agent out total · cost · min · turns · note — then per ask `safe vs off` / `aggressive vs off` as percent of agent output and of cost (negative = cheaper), then the medians per dial (and the median of the per-ask deltas vs `off`). "Agent out" is the sum of the hook-attached `agent_output` over the run's plan steps, never an estimate; cost is the `total_cost_usd` of the run-plan session (the shared kickoff is listed per ask, with the model it ran on). **Session model** is read from claude's `modelUsage` for that session (`claude-opus-5-5` → `opus-5-5`; the session model first, then in brackets the models its agents ran on). When the kickoff and the dials did not all run on one model, the per-ask line says **models differ** and names them: those dials are not comparable, pin the model and rerun.

**The no-work rule.** A run that did no work — no step passed, typically because it stopped on NEEDS YOU before any step, as `off` and `safe` did in A/B run 1 — keeps its row, with the note `no work done — stopped on NEEDS YOU before any step`, but feeds no comparison: the per-ask line says `off did no work → no comparison` (or `safe` / `aggressive`) instead of a percent, the medians leave such rows out and say how many were excluded, and the row's agent out is `—`, not 0, because no agent ran and there is nothing to compare. A measured 0 (steps passed, no agent used) stays 0. Without this rule run 1 printed "aggressive vs off: cost +235%" against a run that had built nothing.

**Honesty footnote (the per-model split).** Since hooks 0.4.0 the SubagentStop hook records `agent_by_model` per plan step — `{model: {calls, input, output}}` — so the by-model column is exact: each model's share is the hook's own sum, no `~`. An archive from before that has only ONE `agent_output` per step and the LIST of models that ran on it (a build agent and its verify agent land on the same step); there a step with one model is attributed to the step's `model`, a step with several models is split EVENLY between them and each share is marked `~`, because the true per-model share of that step was not recorded. Totals, cost and the percent lines are exact either way. The report repeats this in its footer, so the table never travels without it.

**Dry run and CI.** `./ab.sh --dry-run` runs the whole pipeline with `fake-claude.sh` standing in for `claude`: it writes a 10-line task.md for make-prompt and a deterministic archived run per dial (4 steps, one blocked; off = 9k agent out / $3.70, safe = 8k / $3.40, aggressive = 6k / $2.10; every agent step carries `agent_by_model`), prints claude's JSON with a `modelUsage` object, and skips `npm install` / `npm test`. Ask 2 on dial `off` does no work (NEEDS YOU before any step, 0 steps passed) so the no-work rule is exercised. `--model X` is echoed back as the model of every session; without it the shim drifts the way run 1 did (kickoff on `claude-fable-5-1`, run-plan sessions on `claude-opus-5-5`) so the **models differ** flag is exercised. The fake's numbers are fixtures, not measurements — they exist so the pipeline and the report can be tested for free. `tests/ab-test.sh` (temp `HOME`, python through the launcher, no `jq`) runs that dry run three ways: with `--model` (6 rows for 2 asks × 3 dials, the session-model column, the vs-off lines with percents, aggressive cheaper than off, the exact split without `~`, the no-work row excluded from the deltas and the medians with the explicit lines, no leftovers), without `--model` (the drift is flagged, `run.json` has `model: null`), and over a copy of the files with `agent_by_model` stripped (the even split marked `~` still works); CI runs it on every push.
