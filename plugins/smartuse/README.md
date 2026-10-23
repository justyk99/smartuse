# smartuse (plugin root)

The plugin that `justyk99/smartuse` publishes. Full README, benchmark and research live one level up: https://github.com/justyk99/smartuse

Install:
```text
/plugin install smartuse --marketplace justyk99/smartuse
```

Skills: `make-prompt` · `run-plan` · `living-docs` · `reply-style` · `ledger` · `receipts` · `status`. Hooks: `bash-guard` + `file-guard` (PreToolUse) · `ledger` (Stop / SubagentStop — one receipt per plan step) · `until-done` (Stop gate) · `wait-gate` (Stop — a hand-off with nothing armed to wake the session is blocked once) · `heartbeat` (every event — working / waiting on agent / waiting on you / stopped / stalled). `hooks/watch.py`: the watcher a session runs in the background after a hand-off. Output styles: lcd · bluf · engineer · teacher · minimal · plain · memo. Evals: `evals/` (10 cases; the first 8 all passed with the plugin in the 0.4.0 run, mean gain +0.88 over no plugin: `evals/results/2026-10-22-0.4.0/`; all 10 pass on the 0.5.0 working tree: `evals/results/2026-10-22-0.5.0-m4/`; run them with `--scaffold`, two cases stage a repo or a task folder). Tests: `hooks/tests/` — `bash hooks/tests/all.sh` runs every suite (plus the bench A/B dry run) and prints one summary line.
