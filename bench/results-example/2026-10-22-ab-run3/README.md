# A/B run 3 (2026-10-22, headless, 5 bench asks × 3 dials, model pinned to Opus) — the first multi-ask comparison

`bench/ab.sh --asks 5 --model opus` with the 0.4.0-dev plugin. One kickoff per ask (`make-prompt quick`), then `run-plan --until-done` under each routing dial on a fresh copy of the bench repo. Every number comes from the hooks (per-step agent tokens, `agent_by_model`), claude's JSON (`total_cost_usd`, turns, minutes) or `npm test` run by the runner on the result.

| # | ask | off | safe | aggressive |
|---|---|---|---|---|
| 1 | add a CSV export of orders | $1.60 · 13/13 tests | **$1.44 (−10 %)** · 18/18 | **$1.12 (−30 %)** · 19/19 |
| 2 | totals are off by one cent (planted rounding bug) | $0.98 · 5/5 · stopped: NEEDS YOU | **$0.58 (−41 %)** · 2/2 · NEEDS YOU | **$0.75 (−23 %)** · **2/5, 3 failing** · NEEDS YOU |
| 3 | move the in-memory store to SQLite or Postgres? (design) | $1.09 · NEEDS YOU | **$0.93 (−15 %)** · NEEDS YOU | $1.66 (**+52 %**) · NEEDS YOU |
| 4 | add request logging to every route | — no kickoff: make-prompt said it is a one-sentence change and offered to just do it (its size check, by design) | | |
| 5 | make orders faster | $1.87 · 20/20 · NEEDS YOU | **$1.27 (−32 %)** · 10/10 · NEEDS YOU | **$1.41 (−25 %)** · 7/7 · NEEDS YOU |

**Medians over the 4 comparable asks:** cost `off` $1.35 · `safe` $1.10 · `aggressive` $1.26; median per-ask change vs `off`: **cost −24 % on both routed dials**. Agent output did **not** drop (median +58 % `safe`, +2 % `aggressive`): the cheaper models wrote more tokens for the same steps, and still cost less.

**What it says, and no more**
- Routing lowered the cost of the run-plan session on 7 of 8 routed runs; one aggressive run (the design question) cost 52 % more.
- Tests: 11 of 12 result directories are green. The aggressive run on the rounding bug left **3 failing tests** when it stopped for the human's rounding decision — a quality cost the price column does not show.
- 3 of 4 asks ended on a real human question, on every dial: the rounding rule (money), the database choice (design), the performance trade-off. That is the until-done gate's intended exit, not a failure.
- n = 4 asks on one small fixture repo, one run each. It is a direction, not a published saving; the real-repo runs decide the claim.

Files: `report.md` (`ab-report.py`'s full output, re-rendered from the saved run data after the runner crashed on its final report step — the runner script had been edited on disk while it ran, which bash does not survive; every session had completed), `<ask>-<dial>-receipts.json` (the hook archives), `<ask>-meta.json`, `run.json`.
