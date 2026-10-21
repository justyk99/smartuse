# Example run on 0.3.0 — one line → kickoff → until-done loop → a receipt per plan step (2026-10-21, Claude Code 2.1.306, headless)

Repo: `bench/sample-repo` (Express orders API, planted rounding bug, `check: npm test`), fresh copy, `npm install` done. Ask typed: *"add a CSV export of orders (a GET endpoint that returns the orders as CSV, with a test). Deadline next week, I sign off."* Session model: fable. Both stages ran with `claude -p … --plugin-dir plugins/smartuse --permission-mode bypassPermissions`.

| Stage | What happened | Cost (list price) | Time |
|---|---|---|---|
| 1 `make-prompt quick` | kickoff saved (1,018 words, 14/14 self-check), `research.md` + `decisions.md`, living-docs stubs; chose a new router file so the other developer's `orders.js` is never edited | $1.57 | 2.4 min, 6 turns |
| 2 `run-plan --until-done --routing safe` | 6 steps; export router + mount + 4 new tests built (6/6 pass, lint clean); live curl verified; three fresh-agent reviews on sonnet, all "no gaps"; docs step on haiku; step 6 **blocked by rule** (run-plan never commits) — the commit is the human's | $3.72 | 6.4 min, 22 turns |

Files here: `kickoff-task.md` · `decisions.md` · `stage1-make-prompt.md` and `stage2-run-plan-until-done.md` (the final messages, verbatim) · **`receipts-table.md`** (`/smartuse:receipts` output, verbatim) · `routing-archived.json` (the per-step receipts as the Stop hook archived them under `runs/`) · `receipts.jsonl` (hook lines with `unit` attached + the skill's per-unit outcome lines).

What changed since the 2026-10-15 run: the tokens in the table are the SubagentStop hook's, attached to the step that was `running` — the 0.2.0 run had to quote what each agent reported about itself. Build and verify agents on the same step add up (step 2 = 3 build calls + 2 review calls). Input is mostly cache reads; the `out` column is the honest size of each step.

Agent output by model: fable 40% (three build steps, safe dial = session model) · haiku 45% (docs) · sonnet 13% (three reviews). With `--routing off` all of it runs on the session model; `--routing aggressive` sends the build steps one tier down. That A/B is the 0.4 roadmap item.
