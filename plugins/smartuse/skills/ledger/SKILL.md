---
name: ledger
description: Show the ledger — the runs (make-prompt · run-plan · living-docs) with their minutes, tokens and self-check score, medians by skill and mode, and under them the steps of each run-plan run (step · model · outcome · tokens). Use when the user asks "how much did that cost", "show the ledger", "token usage of the kit", "what did that run do", or wants numbers for a write-up. /smartuse:receipts shows the steps of one run alone.
argument-hint: "[N | task word | all]"
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --view *)'
---

# ledger — the runs, and the steps of each run-plan run (make-prompt · run-plan · living-docs) (deterministic, 0 model tokens to compute)

!`bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --view $ARGUMENTS || true`

Print the tool's output as it is. The words after the command are `N` (the last N runs; no word means 10), a task word (only the runs of tasks holding it) or `all` (every run). Under the table, each run-plan run shown has its own steps block, the same one `/smartuse:receipts <task>` prints. `steps: not kept (<file name>)` means that run's steps file is not on disk (an older run, or one cleaned away): quote the line, never fill the steps in from another run. `running now` is a run still in progress. `N lines unreadable` means that many ledger lines could not be read and were left out.

Then explain the table in ≤ 5 lines: what one row is (one skill run, tokens summed from the session transcript since the skill was invoked, input = fresh + cache read + cache written), what the medians say, and which row is the outlier if any. Numbers come from `~/.claude/smartuse/ledger.jsonl`; a row is written by the Stop hook when a skill left `~/.claude/smartuse/projects/<key>/pending.json` (`<key>` is derived from the repo's full path). No row for a run means the skill ended without its hand-off step.

When the tool prints `ledger: empty` (no ledger file yet, or no line in it): quote that line, then say in one line that a row is written by the Stop hook from `pending.json` when a make-prompt, run-plan or living-docs run finishes its hand-off — the first such run creates the first row. No table, no numbers, nothing estimated.
