# A/B: routed vs not — ab-run1

1 ask(s) · dials: off, safe, aggressive · claude: 2.1.308 (Claude Code) · caps: kickoff 60 turns / $4, run-plan 40 turns / $5 per dial · generated 2026-10-22 06:51 UTC

| # | ask | dial | steps pass/blocked/open | needs_human | npm test | agent out by model | agent out | cost | min | turns | note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | add a CSV export of orders | off | 0/5/0 | yes | 2/2 | n/a | 0 | $0.34 | 0.8 | 6 |  |
| 1 | add a CSV export of orders | safe | 0/5/0 | yes | 2/2 | n/a | 0 | $0.32 | 0.8 | 5 |  |
| 1 | add a CSV export of orders | aggressive | 4/1/0 | yes | 6/6 | haiku 6.8k · sonnet 3.7k | 10.5k | $1.12 | 4.6 | 19 |  |

## Per ask, vs `off` (negative = cheaper than everything on the session model)

- **1 · add a CSV export of orders** — kickoff $1.55 · 2.4 min · 5 turns · `.task/ACTIVE/orders-csv-export/task.md`
  - safe vs off: agent out n/a · cost -3%  (0 vs 0 · $0.32 vs $0.34)
  - aggressive vs off: agent out n/a · cost +235%  (10.5k vs 0 · $1.12 vs $0.34)

## Medians per dial (1 ask(s) with a kickoff)

- **off**: agent out 0 · cost $0.34 · 0.8 min · 6 turns (n=1)
- **safe**: agent out 0 · cost $0.32 · 0.8 min · 5 turns (n=1) · vs off (median of the per-ask deltas): agent out n/a · cost -3%
- **aggressive**: agent out 10.5k · cost $1.12 · 4.6 min · 19 turns (n=1) · vs off (median of the per-ask deltas): agent out n/a · cost +235% · agent out by model, summed: haiku 6.8k · sonnet 3.7k

## Notes

- **agent out** = sum of `agent_output` over the plan steps of the archived run: the tokens the SubagentStop hook attached to the step that was running, never an estimate. Judgment steps run in the session itself and carry no agent tokens. **cost** = `total_cost_usd` of the run-plan session (stage 2 only; the kickoff is shared by the dials and listed per ask). **min** = `duration_ms` / 60000, **turns** = `num_turns`, both from claude's JSON.
- **Per-model split is approximate where marked `~`.** The hook records ONE `agent_output` per plan step and the LIST of models that ran on it (a build agent and its verify agent land on the same step). A step with a single model is attributed to the step's `model`. A step with several models is split EVENLY between them and each share is marked `~`: the true per-model share of that step is not recorded. Totals, cost and the percent lines are exact; only the by-model column is approximate.
- **steps** = pass/blocked/open (open = pending, running or failed). **needs_human** = the run stopped on a question for the human (`needs_human` in the receipts, or a final message starting with `NEEDS YOU`). **npm test** = jest's passed/total from `npm test` in the result dir (n/a in a dry run). **note** = claude's non-success subtype (a cap hit), missing files, or a run that never closed.
