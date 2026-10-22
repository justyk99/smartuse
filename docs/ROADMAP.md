# Road to smartuse 1.0 (owner: Smartuse-Brain · started 2026-10-22; the 1.0 audit's confirmed findings get folded in as they land)

**1.0 means:** a user on Windows, macOS or Linux installs it in 30 seconds, every claim in the README has a test or a receipt behind it, the hooks never block a turn by mistake, and the one number the project exists for — routed vs not, per step, on real tasks — is published with the method.

## 0.4.0 — "is it working, or waiting on me?" (this week)
- [x] Heartbeat hook + `/smartuse:status` + status line + agent rows
- [x] Receipts by model, `--json`
- [x] A/B runner with dry run in CI; first real run archived (found the run-plan blocker defect)
- [x] Windows: interpreter launcher, HOME honoured (laptop-verified: run, until-done, file-guard pass)
- [x] Windows round 2: all five hook suites pass on the laptop (Git Bash, Python 3.13), confirmed 2026-10-22
- [x] A/B runner: pinned `--model`, "no work done" rows out of the deltas, exact per-model split, no jq
- [x] A/B re-run (1 ask × 3 dials, Opus pinned): clean; row in README with the n=1 caveat
- [ ] Release 0.4.0 (laptop publishes; notes in `docs/releases/0.4.0.md`)

## 0.5.0 — measured
- [ ] The routed-vs-not A/B over the 5 bench asks × 3 dials, and over at least 5 real tasks on YK's repos (his laptop, `bench/ab.sh`); the table in README replaces "not yet measured"
- [ ] `claude plugin eval` for all 5 cases in CI (needs an API key secret: YK) — until then, run locally before each release
- [ ] The subagentStatusLine verified live on the laptop (runtime loading of plugin settings)
- [ ] until-done on Windows: `--trust` pin path without /etc (pins under a root-equivalent the user owns: documented, not faked)

## 0.6.0 — the audit's list (filled from `smartuse-1.0-audit`)
- [ ] hook correctness/security findings
- [ ] portability findings beyond Windows
- [ ] docs-vs-code mismatches
- [ ] skill prompt fixes + eval cases for status, run-plan, ledger
- [ ] first-run gaps (adapter, state dir, `check:` requirement, what the hooks write)

## 1.0 — public
- [ ] "30 days of receipts": the measured post with the A/B table and the ledger medians
- [ ] Marketplace listing (community marketplace form), awesome-lists PRs (YK's clicks)
- [ ] README demo gif re-recorded on the laptop with the status line visible
- [ ] CHANGELOG squash into release notes; version 1.0.0; tag

## Not in 1.0 (said once so it is not relitigated)
- Another router or classifier; multi-vendor voting; anything needing a proxy or patched binary.
