# A/B: routed vs not — ab-run2

1 ask(s) · dials: off, safe, aggressive · claude: 2.1.308 (Claude Code) · model: opus (pinned with --model) · caps: kickoff 60 turns / $4, run-plan 40 turns / $5 per dial · generated 2026-10-22 07:33 UTC

| # | ask | dial | session model | steps pass/blocked/open | needs_human | npm test | agent out by model | agent out | cost | min | turns | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | add a CSV export of orders | off | opus-5-5 | 4/0/0 | no | 26/26 | opus-5-5 16.5k | 16.5k | $2.08 | 6.2 | 22 |  |
| 1 | add a CSV export of orders | safe | opus-5-5 (+sonnet-5-5, haiku-5-5) | 5/0/0 | no | 12/12 | opus-5-5 8.3k · haiku-5-5 5.5k · sonnet-5-5 3.1k | 16.9k | $1.72 | 6.1 | 22 |  |
| 1 | add a CSV export of orders | aggressive | opus-5-5 (+sonnet-5-5, haiku-5-5) | 5/1/0 | no | 10/10 | sonnet-5-5 10.9k · haiku-5-5 6.4k | 17.3k | $1.44 | 6.2 | 24 |  |

## Per ask, vs `off` (negative = cheaper than everything on the session model)

- **1 · add a CSV export of orders** — kickoff $0.38 · 1.1 min · 5 turns · on opus-5-5 · `.task/ACTIVE/orders-csv-export/task.md`
  - safe vs off: agent out +3% · cost -17%  (16.9k vs 16.5k · $1.72 vs $2.08)
  - aggressive vs off: agent out +5% · cost -31%  (17.3k vs 16.5k · $1.44 vs $2.08)

## Medians per dial (1 ask(s) with a kickoff; rows that did no work are excluded and counted)

- **off**: agent out 16.5k · cost $2.08 · 6.2 min · 22 turns (n=1) · agent out by model, summed: opus-5-5 16.5k
- **safe**: agent out 16.9k · cost $1.72 · 6.1 min · 22 turns (n=1) · vs off (median of the per-ask deltas, 1 compared): agent out +3% · cost -17% · agent out by model, summed: opus-5-5 8.3k · haiku-5-5 5.5k · sonnet-5-5 3.1k
- **aggressive**: agent out 17.3k · cost $1.44 · 6.2 min · 24 turns (n=1) · vs off (median of the per-ask deltas, 1 compared): agent out +5% · cost -31% · agent out by model, summed: sonnet-5-5 10.9k · haiku-5-5 6.4k

## Notes

- **agent out** = sum of `agent_output` over the plan steps of the archived run: the tokens the SubagentStop hook attached to the step that was running, never an estimate. Judgment steps run in the session itself and carry no agent tokens. **cost** = `total_cost_usd` of the run-plan session (stage 2 only; the kickoff is shared by the dials and listed per ask). **min** = `duration_ms` / 60000, **turns** = `num_turns`, both from claude's JSON.
- **session model** = the keys of claude's `modelUsage` for the run-plan session, shortened (`claude-opus-5-5` → `opus-5-5`): the session model first, then in brackets the models its agents ran on. The kickoff's model is on the per-ask line. Without `ab.sh --model`, claude's default decides per session and can differ between the kickoff and the run-plan sessions, or between dials; the per-ask line flags that as **models differ**, and then the dials are not comparable.
- **no work done** = no step passed: the run stopped on NEEDS YOU before any step, or nothing passed. The row stays in the table (see its note) but feeds no percent line and no median; the per-ask lines say `did no work → no comparison` and the median lines say how many rows were excluded. Its agent out is `—`, not 0: no agent ran, so there is nothing to compare. A measured 0 (steps passed, no agent used) stays 0.
- **Per-model split.** A step the hook recorded with `agent_by_model` ({model: {calls, input, output}}, hooks 0.4.0 and later) is exact: each model's share is the hook's own sum for that model, so the by-model column carries no `~`. An archive from before that records ONE `agent_output` per step and the LIST of models that ran on it (a build agent and its verify agent land on the same step): a step with a single model is attributed to the step's `model`, a step with several models is split EVENLY between them and each share is marked `~`, because the true per-model share of that step was not recorded. Totals, cost and the percent lines are exact either way.
- **steps** = pass/blocked/open (open = pending, running or failed). **needs_human** = the run stopped on a question for the human (`needs_human` in the receipts, or a final message starting with `NEEDS YOU`). **npm test** = jest's passed/total from `npm test` in the result dir (n/a in a dry run). **note** = claude's non-success subtype (a cap hit), missing files, a run that never closed, or `no work done`.
