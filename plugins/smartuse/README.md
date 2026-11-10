# smartuse (plugin root)

The plugin that `justyk99/smartuse` publishes. Full README, benchmark and research live one level up: https://github.com/justyk99/smartuse

Install:
```text
/plugin install smartuse --marketplace justyk99/smartuse
```

Skills: `make-prompt` · `run-plan` · `living-docs` · `reply-style` · `ledger` · `receipts` · `status` · `doctor`. Hooks: `bash-guard` + `file-guard` (PreToolUse; bash-guard covers the Bash and PowerShell tools and also holds the fresh-source gate, which denies a send command or an upload tool until the job's `sources:` are reopened after the last compaction) · `recall` (PreCompact / SessionStart — the summary is not a source; the `handoff:` note at session start) · `ledger` (Stop / SubagentStop — one receipt per plan step) · `until-done` (Stop gate) · `wait-gate` (Stop — a hand-off with nothing armed to wake the session is blocked once; off unless Strict or the Wait gate option is on) · `heartbeat` (every event — working / waiting on agent / waiting on you / stopped / stalled; its tool-event handlers run in the background). `hooks/watch.py`: the watcher a session runs in the background after a hand-off. Output styles: lcd · bluf · engineer · teacher · minimal · plain · memo. Evals: `evals/` (10 cases; the first 8 all passed with the plugin in the 0.4.0 run, mean gain +0.88 over no plugin: `evals/results/2026-10-22-0.4.0/`; all 10 pass on 0.5.0 with each case's own limits: `evals/results/2026-10-25-0.5.0-ci/`; run them with `--scaffold`, two cases stage a repo or a task folder). Tests: `hooks/tests/` — `bash hooks/tests/all.sh` runs every suite (plus the bench A/B dry run) and prints one summary line.

Switches (0.6.1): `/plugin configure smartuse@smartuse` sets three options, Strict guards, Rules off and Wait gate. Light is the default. It frees only `force-with-lease` and `claude-json` and turns the wait gate off. Strict is every rule on, the wait gate on, and guards that fail closed (Rules off is ignored).
- Each deny ends `[rule <name>]`. Put that name into Rules off to switch the rule off. `human-only`, `trust-pin` and `config-switch` cannot be switched off.
- Claude cannot change the switches for itself: `file-guard` and the `config-switch` rule deny the edits and commands that would. The limit: they read text, so a write hidden in another program or built at run time is not seen, and a command that only quotes one is denied.
- `/smartuse:doctor` proves the hooks are live and prints the level. With no Python found, the session start says so once.
- Full text: the README and `SECURITY.md` one level up.
