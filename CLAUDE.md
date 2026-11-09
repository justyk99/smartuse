# smartuse
Stack: Claude Code plugin (plugins/smartuse/): Python 3.9+ stdlib hooks, bash tests, Markdown skills and output styles. This repo is PUBLIC.
T1: bash plugins/smartuse/hooks/tests/<suite>.sh (run.sh, file-guard-test.sh, ledger-test.sh, until-done-test.sh, heartbeat-test.sh, watch-test.sh, wait-gate-test.sh, fresh-gate-test.sh, recall-test.sh)
T2: bash plugins/smartuse/hooks/tests/all.sh
T3: bash plugins/smartuse/hooks/tests/all.sh, bash scripts/term-scan-test.sh, claude plugin validate --strict plugins/smartuse
Never touch: .claude/*.local.md and .smartuse-terms.local (gitignored, human-only), .agents/ and .codex/ (not ours); stage by file name, never git add .
Job data: none
Publish: git push to the public remote only on the maintainer's word, after python3 scripts/term-scan.py --history shows 0 hits; no force-push; no personal paths, names or company terms in any file.
