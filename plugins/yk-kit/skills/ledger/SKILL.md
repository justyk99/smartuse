---
name: ledger
description: Show the receipts ledger — every make-prompt / living-docs run with its minutes, tokens and self-check score, plus medians by skill and mode. Use when the user asks "how much did that cost", "show the ledger", "receipts", "token usage of the kit", or wants numbers for a write-up.
argument-hint: "[N last rows]"
allowed-tools: Bash(python3 *)
---

# ledger — the receipts (deterministic, 0 model tokens to compute)

!`python3 "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --report ${1:-10} || true`

Explain the table in ≤ 5 lines: what one row is (one skill run, tokens summed from the session transcript since the skill was invoked, input = fresh + cache read + cache written), what the medians say, and which row is the outlier if any. Numbers come from `~/.claude/yk-kit/ledger.jsonl`; a row is written by the Stop hook when a skill left `~/.claude/yk-kit/projects/<repo>/pending.json`. No row for a run means the skill ended without its hand-off step.
