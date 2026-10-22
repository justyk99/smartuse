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
- [x] The routed-vs-not A/B over the 5 bench asks × 3 dials (run 3: −24 % median cost, n=4) · [ ] at least 5 real tasks on YK's repos (his laptop, `bench/ab.sh`); the table in README replaces "not yet measured"
- [ ] `claude plugin eval` for all 5 cases in CI (needs an API key secret: YK) — until then, run locally before each release
- [ ] The subagentStatusLine verified live on the laptop (runtime loading of plugin settings)
- [ ] until-done on Windows: `--trust` pin path without /etc (pins under a root-equivalent the user owns: documented, not faked)

## 0.4.0 also carries the audit's list (`docs/notes/audit-2026-10-22.md`: 42 confirmed, 7 refuted) — in three batches
- [ ] hooks core (worker): the until-done gate holds until done or max_blocks (it yielded after one push per prompt); check runner finds npm/pnpm/yarn on Windows and stops after one "not found" block; state dir keyed by full path (two same-named repos shared one routing.json); UTF-8 stdin; Windows-safe status.json replace; no receipts after a run closed
- [ ] guards (worker): bash-guard rules widened (sudo in if/for/subshell, `bash -c "$(curl …)"`, `git -C … push --force`, `+refspec`, key names without a directory prefix, Windows path spellings, echo-mention false positive); file-guard case-insensitive and normalised; UTF-8 stdin; PYTHONUTF8 in the launcher
- [ ] skills + docs (worker): `$ARGUMENTS` in the three `!` lines (the `${1:-}` form was refused in default permission mode); make-prompt hands off to run-plan; living-docs writes its receipt and declares its tools; run-plan allowed-tools + headless example + accepted `check:` shapes; status legend; self-check 14; three new eval cases; README/CHANGELOG/CONTRIBUTING counts and claims; `hooks/tests/all.sh`
- [x] repo: `.gitattributes` (LF everywhere), CI matrix ubuntu/macOS/Windows and on the dev branch — green on all three (bac4685)

## 1.0 — public
- [ ] "30 days of receipts": the measured post with the A/B table and the ledger medians
- [ ] Marketplace listing (community marketplace form), awesome-lists PRs (YK's clicks)
- [ ] README demo gif re-recorded on the laptop with the status line visible
- [ ] CHANGELOG squash into release notes; version 1.0.0; tag

## Not in 1.0 (said once so it is not relitigated)
- Another router or classifier; multi-vendor voting; anything needing a proxy or patched binary.
