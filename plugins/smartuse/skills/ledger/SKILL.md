---
name: ledger
description: Show the ledger — per-run totals (make-prompt · run-plan · living-docs): every run with its minutes, tokens and self-check score, plus medians by skill and mode. Use when the user asks "how much did that cost", "show the ledger", "token usage of the kit", or wants numbers for a write-up. The per-step table of one run-plan run is /smartuse:receipts, not this.
argument-hint: "[N last rows]"
allowed-tools: Bash(bash *)
---

# ledger — per-run totals (make-prompt · run-plan · living-docs) (deterministic, 0 model tokens to compute)

!`bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --report $ARGUMENTS || true`

Explain the table in ≤ 5 lines: what one row is (one skill run, tokens summed from the session transcript since the skill was invoked, input = fresh + cache read + cache written), what the medians say, and which row is the outlier if any. Numbers come from `~/.claude/smartuse/ledger.jsonl`; a row is written by the Stop hook when a skill left `~/.claude/smartuse/projects/<key>/pending.json` (`<key>` is derived from the repo's full path). No row for a run means the skill ended without its hand-off step.

When the tool prints `ledger: empty` (no ledger file yet, or no line in it): quote that line, then say in one line that a row is written by the Stop hook from `pending.json` when a make-prompt, run-plan or living-docs run finishes its hand-off — the first such run creates the first row. No table, no numbers, nothing estimated.
