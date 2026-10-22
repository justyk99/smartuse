# smartuse benchmark

Runs `/smartuse:make-prompt quick dry <ask>` on 5 typical asks against a tiny sample repo and prints one comparison table.

## Run

```bash
cd smartuse/bench
./run.sh                          # loads ../plugins/smartuse via --plugin-dir
./run.sh --plugin-dir /path/to/smartuse
```

Needs `claude` and `jq`. Each ask runs on a fresh temp copy of `sample-repo/` (git-initialised), so the fixture stays clean. Raw JSON goes to `results/<n>.json`. Runs spend plan usage (cap: 60 turns, $4 each).

## Table columns

- Cost: `total_cost_usd` for the run.
- Turns: `num_turns`, model round trips.
- Minutes: `duration_ms` / 60000.
- Prompt saved: result text contains "Prompt saved".
- Self-check: result text contains a "✓" line.

`sample-repo/` has one planted rabbit hole: `computeTotal()` in `orders.js` rounds silently (see its TODO). Good runs notice it without wandering off.

Numbers depend on your plan's models and on Claude Code's version; publish the version with the table.

## A/B: routed vs not

`ab.sh` measures what the `run-plan` dial buys (the 0.4 roadmap item). Per ask in `asks.txt` it runs ONE kickoff (`/smartuse:make-prompt quick <ask>`) on a fresh, git-initialised copy of `sample-repo/` with `npm install` done, snapshots that kickoff, then runs `/smartuse:run-plan <task.md> --until-done --routing <dial>` once per dial (`off`, `safe`, `aggressive`) on an identical restore of the snapshot — the dials start from the same task.md and differ only in the routing. Each run dir gets a unique basename (`ab-<n>-<dial>-<timestamp>`), which is the key of its receipt state under `~/.claude/smartuse/projects/`; when run-plan closes, the Stop hook archives `routing.json` there under `runs/`, and `ab.sh` copies that file (the per-step receipts) next to claude's JSON. Nothing is written inside the fixture or the repo except the out dir and the dependency cache.

```bash
cd smartuse/bench
./ab.sh                                   # all asks, dials off,safe,aggressive, out: results/ab/<UTC timestamp>/
./ab.sh --asks 2 --dials off,aggressive   # the first 2 asks, two dials
./ab.sh --dry-run                         # the whole pipeline through fake-claude.sh: no model, nothing spent
python3 ab-report.py results/ab/<ts>/     # re-print the table from the raw files
```

Flags: `--asks N` (first N lines of asks.txt) · `--dials a,b,c` · `--plugin-dir P` (default `../plugins/smartuse`) · `--out DIR` · `--dry-run`. `CLAUDE_BIN=/path/to/claude` overrides the binary (the dry run points it at `fake-claude.sh` unless you set it). Needs `claude`, `jq`, `git`, `tar`, `python3` and `npm`.

**Cost and caps.** Every session is a real Claude session and spends your plan usage: on the bench repo ≈ $5–6 per ask per dial (the kickoff ≈ $1.5 / 2.5 min, once per ask; each `run-plan --until-done` ≈ $2–4 / 6 min), i.e. ≈ $50 and 1.5 h for 5 asks × 3 dials. The caps are passed to `claude -p` and are hard: stage 1 `--max-turns 60 --max-budget-usd 4`, stage 2 `--max-turns 40 --max-budget-usd 5`, so N asks × M dials can never exceed N × ($4 + M × $5). The script prints this NOTE with the computed cap before it starts; Ctrl-C stops between sessions and keeps what was collected; a run that hit a cap shows its subtype in the report's `note` column. Dependencies are installed once and cached in `bench/.cache/node_modules` (reused with `cp -a`).

**Files per (ask n, dial)** in the out dir: `<n>-stage1.json` (claude's JSON for the kickoff), `<n>-meta.json` (the ask and the task.md path, or `no kickoff`), `<n>-<dial>.json` (claude's JSON for the run-plan session: `total_cost_usd`, `num_turns`, `duration_ms`, `result`), `<n>-<dial>-receipts.json` (the archived `routing.json`: one unit per plan step with tier, model, status, verify, `agent_output`, `agent_models`), `<n>-<dial>-npmtest.txt` (`npm test` in the result dir plus its exit code), `<n>-*.err` (stderr), `run.json` (parameters, caps, claude version) and `report.md`. An ask whose kickoff left no `.task/ACTIVE/*/task.md` gets one `no kickoff` row and no dial runs. The per-run state dirs under `~/.claude/smartuse/projects/ab-*` are removed once their receipts are copied; the ledger lines the hooks write to `~/.claude/smartuse/ledger.jsonl` stay (one per session, like any other run).

**The report** (`ab-report.py`, stdlib only; printed and written to `<out>/report.md`): one row per (ask, dial) — steps pass/blocked/open · needs_human · npm test passed/total · agent out by model · agent out total · cost · min · turns · note — then per ask `safe vs off` / `aggressive vs off` as percent of agent output and of cost (negative = cheaper), then the medians per dial (and the median of the per-ask deltas vs `off`). "Agent out" is the sum of the hook-attached `agent_output` over the run's plan steps, never an estimate; cost is the `total_cost_usd` of the run-plan session (the shared kickoff is listed per ask).

**Honesty footnote (the per-model split).** The hook records ONE `agent_output` per plan step and the LIST of models that ran on it — a build agent and its verify agent land on the same step. A step with one model is attributed to the step's `model`; a step with several models is split EVENLY between them and each share is marked `~`, because the true per-model share of that step is not recorded. Totals, cost and the percent lines are exact; only the by-model column is approximate where marked. The report repeats this in its footer, so the table never travels without it.

**Dry run and CI.** `./ab.sh --dry-run` runs the whole pipeline with `fake-claude.sh` standing in for `claude`: it writes a 10-line task.md for make-prompt and a deterministic archived run per dial (4 steps, one blocked; off ≈ 9k agent out / $3.70, safe ≈ 8k / $3.40, aggressive ≈ 6k / $2.10) and skips `npm install` / `npm test`. The fake's numbers are fixtures, not measurements — they exist so the pipeline and the report can be tested for free. `tests/ab-test.sh` runs that dry run with a temp `HOME` and asserts the report (6 rows for 2 asks × 3 dials, the vs-off lines with percents, aggressive cheaper than off, the `~` mark, no leftovers); CI runs it on every push.
