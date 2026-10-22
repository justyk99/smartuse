# A/B: routed vs not — ab-run3

5 ask(s) · dials: off, safe, aggressive · claude: 2.1.308 (Claude Code) · model: opus (pinned with --model) · caps: kickoff 60 turns / $4, run-plan 40 turns / $5 per dial · generated 2026-10-22 11:08 UTC

| # | ask | dial | session model | steps pass/blocked/open | needs_human | npm test | agent out by model | agent out | cost | min | turns | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | add a CSV export of orders | off | opus-5-5 | 4/0/0 | no | 13/13 | opus-5-5 11.0k | 11.0k | $1.60 | 4.5 | 19 |  |
| 1 | add a CSV export of orders | safe | opus-5-5 (+sonnet-5-5, haiku-5-5) | 4/0/0 | no | 18/18 | opus-5-5 6.4k · haiku-5-5 2.8k · sonnet-5-5 1.7k | 10.9k | $1.44 | 4.6 | 22 |  |
| 1 | add a CSV export of orders | aggressive | opus-5-5 (+sonnet-5-5, haiku-5-5) | 5/0/0 | no | 19/19 | haiku-5-5 8.7k · sonnet-5-5 5.3k | 14.0k | $1.12 | 4.8 | 21 |  |
| 2 | totals are off by one cent on some orders | off | opus-5-5 | 1/3/0 | yes | 5/5 | opus-5-5 5.3k | 5.3k | $0.98 | 3.0 | 13 |  |
| 2 | totals are off by one cent on some orders | safe | opus-5-5 (+haiku-5-5) | 1/3/0 | yes | 2/2 | haiku-5-5 11.8k | 11.8k | $0.58 | 2.7 | 13 |  |
| 2 | totals are off by one cent on some orders | aggressive | opus-5-5 (+sonnet-5-5) | 1/3/0 | yes | 2/5 (3 failed) | sonnet-5-5 2.2k | 2.2k | $0.75 | 0.9 | 6 |  |
| 3 | should we move the in-memory store to SQLite or Postgres | off | opus-5-5 (+haiku-5-5) | 5/1/0 | yes | 2/2 | opus-5-5 6.0k | 6.0k | $1.09 | 3.6 | 17 |  |
| 3 | should we move the in-memory store to SQLite or Postgres | safe | opus-5-5 (+haiku-5-5) | 6/0/0 | yes | 2/2 | haiku-5-5 12.1k | 12.1k | $0.93 | 4.2 | 20 |  |
| 3 | should we move the in-memory store to SQLite or Postgres | aggressive | opus-5-5 (+haiku-5-5, sonnet-5-5) | 6/0/0 | yes | 2/2 | sonnet-5-5 13.0k · haiku-5-5 11.0k | 24.0k | $1.66 | 8.1 | 26 |  |
| 4 | add request logging to every route | — | n/a | no kickoff | n/a | n/a | n/a | n/a | n/a | n/a | n/a | no kickoff |
| 5 | make orders faster | off | opus-5-5 | 2/3/0 | yes | 20/20 | opus-5-5 10.7k | 10.7k | $1.87 | 0.5 | 2 |  |
| 5 | make orders faster | safe | opus-5-5 (+sonnet-5-5) | 2/3/0 | yes | 10/10 | opus-5-5 8.4k · sonnet-5-5 3.6k | 12.0k | $1.27 | 4.9 | 17 |  |
| 5 | make orders faster | aggressive | opus-5-5 (+sonnet-5-5) | 3/2/0 | yes | 7/7 | sonnet-5-5 8.2k | 8.2k | $1.41 | 4.2 | 14 |  |

## Per ask, vs `off` (negative = cheaper than everything on the session model)

- **1 · add a CSV export of orders** — kickoff $0.55 · 1.4 min · 5 turns · on opus-5-5 · `.task/ACTIVE/orders-csv-export/task.md`
  - safe vs off: agent out -1% · cost -10%  (10.9k vs 11.0k · $1.44 vs $1.60)
  - aggressive vs off: agent out +27% · cost -30%  (14.0k vs 11.0k · $1.12 vs $1.60)
- **2 · totals are off by one cent on some orders** — kickoff $0.38 · 1.1 min · 7 turns · on opus-5-5 · `.task/ACTIVE/order-total-rounding/task.md`
  - safe vs off: agent out +125% · cost -41%  (11.8k vs 5.3k · $0.58 vs $0.98)
  - aggressive vs off: agent out -59% · cost -23%  (2.2k vs 5.3k · $0.75 vs $0.98)
- **3 · should we move the in-memory store to SQLite or Postgres** — kickoff $0.60 · 1.6 min · 6 turns · on opus-5-5 · `.task/ACTIVE/persistent-store-decision/task.md`
  - safe vs off: agent out +103% · cost -15%  (12.1k vs 6.0k · $0.93 vs $1.09)
  - aggressive vs off: agent out +302% · cost +52%  (24.0k vs 6.0k · $1.66 vs $1.09)
- **4 · add request logging to every route** — kickoff $0.22 · 0.4 min · 3 turns · on opus-5-5
- **5 · make orders faster** — kickoff $0.56 · 1.5 min · 6 turns · on opus-5-5 · `.task/ACTIVE/orders-faster/task.md`
  - safe vs off: agent out +13% · cost -32%  (12.0k vs 10.7k · $1.27 vs $1.87)
  - aggressive vs off: agent out -23% · cost -25%  (8.2k vs 10.7k · $1.41 vs $1.87)

## Medians per dial (4 ask(s) with a kickoff; rows that did no work are excluded and counted)

- **off**: agent out 8.3k · cost $1.35 · 3.3 min · 15 turns (n=4) · agent out by model, summed: opus-5-5 32.9k
- **safe**: agent out 11.9k · cost $1.10 · 4.4 min · 18 turns (n=4) · vs off (median of the per-ask deltas, 4 compared): agent out +58% · cost -24% · agent out by model, summed: haiku-5-5 26.7k · opus-5-5 14.8k · sonnet-5-5 5.3k
- **aggressive**: agent out 11.1k · cost $1.26 · 4.5 min · 17 turns (n=4) · vs off (median of the per-ask deltas, 4 compared): agent out +2% · cost -24% · agent out by model, summed: sonnet-5-5 28.8k · haiku-5-5 19.7k

## Notes

- **agent out** = sum of `agent_output` over the plan steps of the archived run: the tokens the SubagentStop hook attached to the step that was running, never an estimate. Judgment steps run in the session itself and carry no agent tokens. **cost** = `total_cost_usd` of the run-plan session (stage 2 only; the kickoff is shared by the dials and listed per ask). **min** = `duration_ms` / 60000, **turns** = `num_turns`, both from claude's JSON.
- **session model** = the keys of claude's `modelUsage` for the run-plan session, shortened (`claude-opus-5-5` → `opus-5-5`): the session model first, then in brackets the models its agents ran on. The kickoff's model is on the per-ask line. Without `ab.sh --model`, claude's default decides per session and can differ between the kickoff and the run-plan sessions, or between dials; the per-ask line flags that as **models differ**, and then the dials are not comparable.
- **no work done** = no step passed: the run stopped on NEEDS YOU before any step, or nothing passed. The row stays in the table (see its note) but feeds no percent line and no median; the per-ask lines say `did no work → no comparison` and the median lines say how many rows were excluded. Its agent out is `—`, not 0: no agent ran, so there is nothing to compare. A measured 0 (steps passed, no agent used) stays 0.
- **Per-model split.** A step the hook recorded with `agent_by_model` ({model: {calls, input, output}}, hooks 0.4.0 and later) is exact: each model's share is the hook's own sum for that model, so the by-model column carries no `~`. An archive from before that records ONE `agent_output` per step and the LIST of models that ran on it (a build agent and its verify agent land on the same step): a step with a single model is attributed to the step's `model`, a step with several models is split EVENLY between them and each share is marked `~`, because the true per-model share of that step was not recorded. Totals, cost and the percent lines are exact either way.
- **steps** = pass/blocked/open (open = pending, running or failed). **needs_human** = the run stopped on a question for the human (`needs_human` in the receipts, or a final message starting with `NEEDS YOU`). **npm test** = jest's passed/total from `npm test` in the result dir (n/a in a dry run). **note** = claude's non-success subtype (a cap hit), missing files, a run that never closed, or `no work done`.
