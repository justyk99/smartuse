# Contributing

Thanks for looking. smartuse stays small on purpose: native Claude Code mechanisms only, under ten files per piece, and every claim backed by a test or a ledger line.

## Before you open a PR
1. `claude plugin validate --strict plugins/smartuse` prints `✔ Validation passed`.
2. `bash plugins/smartuse/hooks/tests/all.sh` runs every suite — bash-guard (`run.sh`), file-guard, ledger + receipts, until-done, heartbeat and the bench A/B dry run (`bench/tests/ab-test.sh`) — each prints `ALL PASS` and the script ends with `run N · ledger N · until-done N · file-guard N · heartbeat N · ab N`; quote that line when you change a count.
3. A hook change comes with a new test case. A skill change comes with an eval case or an updated one (`plugins/smartuse/evals/`).
4. No vendor names in skill names, no colleague names, emails or internal hosts anywhere.

## What we take
- Bug fixes with a reproduction.
- New question banks for `make-prompt` (a profile other than feature / bug / design) with three realistic asks.
- New reply styles with the who-is-it-for line and honest pros and cons.
- Adapters for other VCS / task-folder conventions in `smartuse.local.md`.

## What we decline
- Another model router. The routing layer stays a dial with receipts, not a classifier.
- Anything that needs a proxy, a patched binary or undocumented internals.
- Numbers without a ledger line behind them.

## Style
Plain English, short sentences, one idea per line. Dates absolute. Commit messages: what changed and why, one line each.
