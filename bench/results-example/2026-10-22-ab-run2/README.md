# A/B run 2 (2026-10-22, headless, 1 ask × 3 dials, model pinned to Opus) — the first clean routed-vs-not row

`bench/ab.sh --asks 1 --model opus` on the bench repo with the 0.4.0-dev plugin (after the run-plan blocker fix from run 1). Ask: "add a CSV export of orders". One kickoff ($0.38, 1.1 min), then `run-plan --until-done` per dial on a fresh copy, same kickoff for all three.

| dial | steps | npm test | agent out by model | agent out | cost | min | vs off |
|---|---|---|---|---|---|---|---|
| off | 4/0/0 | 26/26 | opus 16.5k | 16.5k | $2.08 | 6.2 | — |
| safe | 5/0/0 | 12/12 | opus 8.3k · haiku 5.5k · sonnet 3.1k | 16.9k | $1.72 | 6.1 | cost −17 %, agent out +3 % |
| aggressive | 5/1/0 | 10/10 | sonnet 10.9k · haiku 6.4k | 17.3k | $1.44 | 6.2 | cost −31 %, agent out +5 % |

Every number is the hook's (`agent_by_model` per step, exact) or claude's own JSON (`total_cost_usd`, turns, duration); `npm test` was run on each result directory by the runner.

What it says, and no more: on this one ask, routing changed the cost (−17 % / −31 %) and not the amount of work (agent output within 5 %), and all three dials finished with tests green. What it does not say: anything about variance (n = 1), about harder tasks, or about quality beyond "tests the run wrote pass" (the three runs wrote different numbers of tests: 26, 12, 10). The 5-ask run and the real-repo runs are what the README's measured table waits for.
