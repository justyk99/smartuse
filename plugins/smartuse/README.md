# smartuse (plugin root)

The plugin that `justyk99/smartuse` publishes. Full README, benchmark and research live one level up: https://github.com/justyk99/smartuse

Install:
```text
/plugin install smartuse --marketplace justyk99/smartuse
```

Skills: `make-prompt` · `run-plan` · `living-docs` · `reply-style` · `ledger` · `receipts` · `status`. Hooks: `bash-guard` + `file-guard` (PreToolUse) · `ledger` (Stop / SubagentStop — one receipt per plan step) · `until-done` (Stop gate) · `heartbeat` (every event — working / waiting on agent / waiting on you / stalled). Output styles: lcd · bluf · engineer · teacher · minimal · plain · memo. Evals: `evals/` (8 cases; the 4/4 score is the 0.2.0 run of the first four, the other four are not scored yet). Tests: `hooks/tests/` — `bash hooks/tests/all.sh` runs every suite (plus the bench A/B dry run) and prints one summary line.
