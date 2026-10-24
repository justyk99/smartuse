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
- [x] 0.4.0 on `main` (5b3dbed, 2026-10-22); a fresh `claude plugin install smartuse@smartuse` gets 0.4.0 · [ ] release page + tag (YK: the harness blocks the Brain; notes in `docs/releases/0.4.0.md`)

## 0.5.0 — one session that delegates, the main pattern (YK 2026-10-22, case study 8; design and replay tests in `docs/notes/one-session-design.md`)
- [x] M1 `watch.py`: a push or a file wakes the session, 0 model tokens while waiting; `--since` survives a late arm or a restart (63 cases)
- [x] M2 wait gate (Stop): no idle stop after a hand-off without an armed watcher or an honest `STOPPED:` (187 cases, the incident replayed, 57 mutations caught) · M3 the status line shows `STOPPED · handed off 20:41 (builder) — nothing will wake this session` or `waiting on builder · watcher armed 20:41` (heartbeat 105)
- [x] M4 steering: make-prompt `Runs on:` + a hand-off that names one session (and no ping); run-plan pre-flight (`needs-machine`, "run this plan on <machine>"), a `command` tier (background task, no model), inputs by absolute path; eval cases `kickoff-two-sessions` and `run-plan-wrong-machine` (they fail on the pre-M4 skills, 3 of 3 with M4; the full suite is 10 of 10, run with `--scaffold`: `evals/results/2026-10-22-0.5.0-m4/`) · [ ] the README lead (YK words it)
- [x] until-done gate vs a running `command` unit: it counted the unit as unfinished and spent its 6 blocks (a long render would switch the gate off for the rest of the run); it now lets the turn end, without a block, while a `command` unit runs and the Stop input's `background_tasks` lists a live task (until-done 40)
- [x] wait gate: "don't paste the prompt into it" matched its hand-off phrase and blocked once; a phrase after don't / do not / never / no need to is no hand-off now (3 phrases added to its table; mutation-checked)
- [x] the 8 older eval cases declared `max_turns` / `timeout_seconds` / `allowed_tools` at the top level of `case.yaml`, where Claude Code 2.1.308 drops them (the m4 result shows kickoff-quick at 10 turns / 300 s, declared 25 / 600); moved under `execution:` (2026-10-24) · [ ] re-run the suite: six cases now get 4–8 turns instead of the default 10, unscored so far — `claude plugin eval` cannot run on the Windows laptop (no sandbox backend for Bash, scaffold needs `bash` on PATH); needs CI with a secret or a Linux/macOS session (YK)
- [x] heartbeat suite on a slow Windows laptop: 3 timing checks overshot (64 of 67 on 99eab34) — ages now checked against the clock read around each call (81e095b); the laptop confirms ALL PASS
- [x] `py.sh` started Python twice per hook event, plus the Store stub on Windows: about 2 s per event on the laptop (a start there: 0.4–3.6 s). The launcher now remembers the interpreter it proved: one start per event; laptop 0.5–1.8 s per call after (median ~1.4 s)
- [ ] Still ~3 s per Bash call on that laptop (two hook events, Python's own start): try `-S` (no site import; the hooks are stdlib only) and a lighter heartbeat (PostToolUse only) option; measure on the laptop before claiming

## 0.5.0 — also: measured
- [x] The routed-vs-not A/B over the 5 bench asks × 3 dials (run 3: −24 % median cost, n=4) · [ ] at least 5 real tasks on YK's repos (his laptop, `bench/ab.sh`); the table in README replaces "not yet measured"
- [ ] `claude plugin eval` for all 10 cases in CI — `.github/workflows/evals.yml` (2026-10-24: Linux, bubblewrap sandbox, `--scaffold`, one arm, `--max-cost-usd 3`; on dispatch and on pushes that touch skills, evals or hooks); waits on the repo secret `CLAUDE_CODE_OAUTH_TOKEN` (YK: `claude setup-token`), and the first run proves the token works for `plugin eval` (its docs name only API keys) — until then, run locally before each release (0.4.0: 8 of 8, +0.88 over no plugin, 2026-10-22; 0.5.0 working tree: 10 of 10, 2026-10-22)
- [ ] The subagentStatusLine verified live on the laptop (runtime loading of plugin settings)
- [ ] until-done on Windows: `--trust` pin path without /etc (pins under a root-equivalent the user owns: documented, not faked)
- [ ] bash-guard false positive: `curl … | python3 -c '…'` is denied as pipe-to-shell, though `-c` (or a script file) makes stdin data — apply the heredoc rule's "what reads stdin as code" test to pipes (found 2026-10-22)
- [ ] Sandbox mode: the skills' state writes are refused (sandboxed Bash cannot write `~/.claude`); move the skill → hook hand-off off the filesystem (the hooks read it from the transcript), so it works sandboxed and prompt-free

## 0.4.0 also carries the audit's list (`docs/notes/audit-2026-10-22.md`: 42 confirmed, 7 refuted) — in three batches
- [x] hooks core (worker): the until-done gate holds until done or max_blocks (it yielded after one push per prompt); check runner finds npm/pnpm/yarn on Windows and stops after one "not found" block; state dir keyed by full path (two same-named repos shared one routing.json); UTF-8 stdin; Windows-safe status.json replace; no receipts after a run closed
- [x] guards (worker): bash-guard rules widened (sudo in if/for/subshell, `bash -c "$(curl …)"`, `git -C … push --force`, `+refspec`, key names without a directory prefix, Windows path spellings, echo-mention false positive); file-guard case-insensitive and normalised; UTF-8 stdin; PYTHONUTF8 in the launcher
- [x] skills + docs (worker): `$ARGUMENTS` in the three `!` lines (the `${1:-}` form was refused in default permission mode); make-prompt hands off to run-plan; living-docs writes its receipt and declares its tools; run-plan allowed-tools + headless example + accepted `check:` shapes; status legend; self-check 14; three new eval cases; README/CHANGELOG/CONTRIBUTING counts and claims; `hooks/tests/all.sh`
- [x] repo: `.gitattributes` (LF everywhere), CI matrix ubuntu/macOS/Windows and on the dev branch — green on all three (bac4685)

## Proposed — relay guards (case study 7; design and failing tests in `docs/notes/relay-design.md`; not in the 1.0 bar until YK adds it)
One session that delegates (above) removes most of their reason — photos become paths, there is no relay — so rules 1, 2 and 5 are for second-machine setups only. Rule 4 still matters in one session (a cheap subagent can spend) and comes right after the 0.5.0 work.
- [ ] Rule 4: a `paid` rule family in bash-guard — the owner's go per script, a cap, one test output first
- [ ] Rule 1: `relay.py save` + `relay-guard` on the relay channels, then the receiver's open-before-done Stop gate
- [ ] Rule 2: `inventory.py` + the brief gate; the ask-again check
- [ ] Rules 3 and 5: the review-file contract with a round-3 owner verdict; the planner's `deny_write:` and the empty `## Visual parameters` section

## 1.0 — public
- [ ] "30 days of receipts": the measured post with the A/B table and the ledger medians
- [ ] Marketplace listing (community marketplace form), awesome-lists PRs (YK's clicks)
- [ ] README demo gif re-recorded on the laptop with the status line visible
- [ ] CHANGELOG squash into release notes; version 1.0.0; tag

## Not in 1.0 (said once so it is not relitigated)
- Another router or classifier; multi-vendor voting; anything needing a proxy or patched binary.
