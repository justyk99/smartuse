# smartuse (plugin root)

The plugin that `justyk99/smartuse` publishes. Full README, benchmark and research live one level up: https://github.com/justyk99/smartuse

Install:
```text
/plugin install smartuse --marketplace justyk99/smartuse
```

Skills: `make-prompt` · `run-plan` · `living-docs` · `reply-style` · `ledger` · `receipts` · `status`. Hooks: `bash-guard` + `file-guard` (PreToolUse) · `ledger` (Stop / SubagentStop — one receipt per plan step) · `until-done` (Stop gate) · `heartbeat` (every event — working / waiting on agent / waiting on you / stalled). Output styles: lcd · bluf · engineer · teacher · minimal · plain · memo. Evals: `evals/` (8 cases, all 8 pass with the plugin in the 0.4.0 run, mean gain +0.88 over no plugin: `evals/results/2026-10-22-0.4.0/`). Tests: `hooks/tests/` — `bash hooks/tests/all.sh` runs every suite (plus the bench A/B dry run) and prints one summary line.
