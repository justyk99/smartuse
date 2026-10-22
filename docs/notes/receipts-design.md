# A receipt per plan step — design notes (0.3.0, 2026-10-22). Not loaded by Claude; for the author.

## The problem it solves
`run-plan` splits a kickoff into steps and runs each through an agent with a model per tier. Before 0.3.0 the step's outcome came from the skill (the model's own report) and the agent's tokens came from a hook line that was not joined to any step. The 2026-10-15 bench run showed the gap: the receipts table quoted what each agent said about itself. A router that reports its own cost is the thing the landscape research (`docs/research/landscape-routing-and-orchestration-2026-10.md`, § 1, the feature-request commenter) said nobody ships: auditable routing receipts with decision, model, reason, escalation, verifier outcome, cost and user override, per unit.

## The join: one `running` unit
- The skill sets `"status": "running"` on exactly one unit before spawning its agent and sets `pass | fail | blocked` after it returns.
- The `SubagentStop` hook reads the agent transcript, sums its usage per model, and attaches the result to the unit that is `running` in `routing.json`: `agent_calls`, `agent_input`, `agent_output`, `agent_models`, `agent_by_model`, `agents`.
- **Zero or several running units → the receipt line is written but stays unattached** (`"unit": null`). The hook never guesses. A table with a hole is worth more than a table with a plausible number.
- Build and review agents on the same step accumulate: step 2 of the 2026-10-21 run = 3 build calls + 2 review calls. The per-model split (`agent_by_model`) keeps them apart.

Why the hook and not the model: the model cannot see its agents' usage; it can only repeat what an agent wrote in its report. The hook reads the transcript Claude Code wrote, so the number is the API's, not anyone's claim. Cost: 0 model tokens.

## What the user's hand looks like
`"override": {"from": "mechanical", "to": "build", "by": "user", "at": …}` on the unit, set by the skill when the user says "retier 3 build" at the dry run. The receipts table shows `mechanical→build`. The skill may not apply a retier silently; the field is the record.

## Verification and escalation on the receipt
`"verify": "no gaps" | "gaps fixed" | "gaps open"` from the fresh-agent review of a delegated build; `"escalated": true` when the unit was re-run one tier up. Judgment units have no `verify` (the user verifies them).

## Archive
When `run-plan` closes it writes `pending.json` for the ledger. The Stop hook writes the ledger line and copies `routing.json` to `runs/<started_at>_<task>.json` with `active: false` and `closed_at`, inside the repo's state dir `~/.claude/smartuse/projects/<key>/` (`<key>` is derived from the repo's full path, so two same-named repos never share receipts; `ledger.py --state-dir` prints it; a 0.3.0 dir keyed by the folder name alone is never written — only `/smartuse:receipts` shows its old runs, marked as shared by every repo of that name). `/smartuse:receipts <task>` reads the archive, so a task's receipts survive the next run in the same repo.

## The view
`ledger.py --receipts [task|all] [--json]`: one row per step (`# · step · tier · model · override · outcome · esc · verify · calls · in · out · check`), then one line: steps pass / blocked / open, agent tokens in / out, and the share of agent output per model (`haiku 45% · fable 40% · sonnet 13%`). `in` is mostly cache reads; `out` is the honest size of a step. Archives from before `agent_by_model` print the older "delegated out" form.

## What it guarantees / does not
Guarantees: every token in the table came from a transcript; a step with no attached agent shows no tokens; a run that closed has its archive; the user's retier is visible; the review verdict is the reviewer's, not the builder's.
Does not: attribute an agent the model spawned for another reason while a unit was `running` (an Explore agent for a side question lands on that step — the step's cost, honestly, but not the step's work); count the session model's own turns on judgment units (they are in the ledger line for the whole run, not per step); work with Claude Code versions whose `SubagentStop` payload lacks `agent_transcript_path` (the hook falls back to `transcript_path`, which is the main session — the receipt is then a whole-session sum and attached to the running unit; versions ≥ 2.1.300 send the agent path).

## Test log
- Hook tests (`hooks/tests/ledger-test.sh`, 17 cases): attach to the single running unit; accumulate a second agent; two running units → unattached; `--receipts` table with override, verify and tokens; archive on close; `--receipts <task>` reads the archive; `by_model` on the receipt line and `agent_by_model` on the unit; the share line ordered by output; `--json` shape; a 0.3.0-style archive still prints.
- Real run, 2026-10-21, headless, Claude Code 2.1.306 (`bench/results-example/2026-10-21-csv-export/`): 6 steps, 7 agent receipts, all attached to the right step; verify verdicts recorded; archive written; `/smartuse:receipts` printed the table the skill then pasted verbatim. Cost of the run $3.72, 6.4 min, 22 turns.
- Known weakness found by that run: the summary line said "delegated out 10.0k (100 %)" because every agent-run step is "delegated" — replaced by the per-model share in 0.4.0-dev.
