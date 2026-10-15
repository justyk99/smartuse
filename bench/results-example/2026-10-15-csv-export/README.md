# Example run — one line → kickoff → until-done loop → docs (2026-10-15, Claude Code 2.1.300, Max plan)

Repo: `bench/sample-repo` (Express orders API, planted rounding bug, `check: npm test`). Ask typed: *"add a CSV export of orders (a GET endpoint that returns the orders as CSV, with a test). Deadline next week, I sign off."*

| Stage | What happened | Cost (list price) | Time |
|---|---|---|---|
| 1 `make-prompt quick` | kickoff saved (8 sections, 14/14 self-check), task folder + doc stubs created; flagged that `orders.js` belongs to another developer | $0.45 | 1.4 min |
| 2 `run-plan --until-done --routing safe` | 6 units tiered; route + CSV escaper built; 4 new tests (11/11 pass); end-to-end curl verified; a fresh-agent review found no gaps; stopped with **NEEDS YOU** on a pre-existing lint gap (no ESLint config in the fixture) and left the commit to the human | $1.30 | 5.6 min, 19 turns |
| 3 commit + `living-docs` | human answered the question in `decisions.md`, committed; docs updated from the diff by a plain sentence, no slash | see stage3 file | |

Files here: the kickoff (`kickoff-task.md`), the decisions log, the loop's final message with its receipts table, and `receipts.jsonl` (hook lines = real per-agent tokens; skill lines = per-unit outcome).

What the receipts show on `--routing safe`: the two build units ran on the session model (opus), the review on sonnet (about a third of agent tokens); nothing went to haiku except the blocked close-out. `--routing aggressive` would send the build units one tier down; the A/B is the 0.3 roadmap item.
