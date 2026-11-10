# Road to smartuse 1.0 (owner: Smartuse-Brain · started 2026-10-22; the 1.0 audit's confirmed findings get folded in as they land)

**1.0 means:** a user on Windows, macOS or Linux installs it in 30 seconds, every claim in the README has a test or a receipt behind it, the hooks never block a turn by mistake (in the light level), and the one number the project exists for — routed vs not, per step, on real tasks — is published with the method.

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
- [x] the 8 older eval cases declared `max_turns` / `timeout_seconds` / `allowed_tools` at the top level of `case.yaml`, where Claude Code 2.1.308 drops them (the m4 result shows kickoff-quick at 10 turns / 300 s, declared 25 / 600); moved under `execution:` (2026-10-24) · [x] re-run the suite in CI: 10 of 10 at 1.00 with each case's own limits (2026-10-25, `evals/results/2026-10-25-0.5.0-ci/`)
- [x] heartbeat suite on a slow Windows laptop: 3 timing checks overshot (64 of 67 on 99eab34) — ages now checked against the clock read around each call (81e095b); the laptop confirms ALL PASS
- [x] `py.sh` started Python twice per hook event, plus the Store stub on Windows: about 2 s per event on the laptop (a start there: 0.4–3.6 s). The launcher now remembers the interpreter it proved: one start per event; laptop 0.5–1.8 s per call after (median ~1.4 s)
- [x] 0.5.1: the launcher remembers a NAME (`python3`, `python` or `py -3`), never a path, and `~/.claude/smartuse/interpreter` is human-only in file-guard and bash-guard, Windows spellings of the file included; bash-guard's SQL rule no longer quadratic, so a long command is decided within the hook's timeout (push security review 2026-10-25, then a fresh review and a security review; plan `docs/notes/py-cache-fix-plan.md` §8; run 138 · file-guard 26 · heartbeat 114)
- [x] Still ~3 s per Bash call on that laptop (two hook events, Python's own start): closed by 0.6.1: the heartbeat's tool events run in the background, so Claude waits on one hook per Bash call instead of three. Before (method M, Claude Code 2.1.322): Bash 0.83 s, Read 0.76 s, Edit 0.98 s, Stop 0.54 s; "after" comes from the live pass. `-S` not built

## 0.5.0 — also: measured
- [x] The routed-vs-not A/B over the 5 bench asks × 3 dials (run 3: −24 % median cost, n=4) · [ ] at least 5 real tasks on YK's repos (his laptop, `bench/ab.sh`); the table in README replaces "not yet measured"
- [x] `claude plugin eval` for all 10 cases in CI — `.github/workflows/evals.yml` (Linux, bubblewrap sandbox, `--scaffold`, one arm, `--max-cost-usd 3`; on dispatch and on pushes that touch skills, evals or hooks); the repo secret `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token` works for `plugin eval` (2026-10-25, run 40154595342: 10 of 10); a "Token works?" step makes one plain call first, so a bad token fails there
- [ ] The subagentStatusLine verified live on the laptop (runtime loading of plugin settings)
- [ ] until-done on Windows: `--trust` pin path without /etc (pins under a root-equivalent the user owns: documented, not faked)
- [x] bash-guard false positive: `curl … | python3 -c '…'` is denied as pipe-to-shell, though `-c` (or a script file) makes stdin data (found 2026-10-22). Closed by 0.6.1 in a narrower form: only a download piped into `python -m json.tool` is allowed; program texts, script files, Node and Perl stay denied, because a deny list of module names and code words can never be complete
- [ ] bash-guard human-only rule stops at `;`: `python3 -c "import os; os.remove('.claude/smartuse.local.md')"` is not denied (file-guard covers Write/Edit only) — found by the paid-guard F2 builder 2026-10-24; the 0.5.1 reviews add directory targets and other spellings of the launcher file to the same rule's gaps (0.6.0, with paid-guard item D); the PowerShell write verbs (`Set-Content`, `Out-File`, `Add-Content`, `Copy-Item`, `Move-Item`, `New-Item`, `Remove-Item`, `[IO.File]::…`) on the human-only files are the same gap on the PowerShell side
- [x] file-guard matches the resolved path too (links, junctions, short 8.3 names of what exists) and fails closed on dot-and-space parts (0.5.1) · [ ] a `~/.claude` that is itself a link: compare with the protected files' resolved paths · [ ] bash-guard: paths inside commands are still matched as text (0.5.1 reviews)
- [ ] The launcher never trusts a `WindowsApps` alias, so users of the Python install manager (3.14+, python.org's default) keep 0.4.0 speed like Store users: find a safe way to tell a real alias from the Store stub; and a cached name whose PATH target broke is run without proof, never re-probed (0.5.1 reviews)
- [ ] Hooks start Python without isolation and run from an install the model can write: harden before 1.0 (0.5.1 security review)
- [ ] Sandbox mode: the skills' state writes are refused (sandboxed Bash cannot write `~/.claude`); move the skill → hook hand-off off the filesystem (the hooks read it from the transcript), so it works sandboxed and prompt-free

## 0.6.0 — recall: "the summary is not a source" (design and contract `docs/notes/recall-design.md`; plan approved 2026-11-08)
A long session gets compacted and keeps a summary; Claude then works from the summary while the job's real files sit unopened, and says "checked". Deterministic pieces, 0 model tokens, no network:
- [x] F1 fresh-source gate: with `sources:` in the adapter, a `publish:` command or a `publish_tools:` tool call (browser uploads included) is denied until every source file has a Read in this session after the last compaction; the reason names the unopened files (built 2026-11-08, with a fresh review and an automated review folded in)
- [x] F2 recall at the squeeze: a PreCompact hook hands the summarizer the source list and the owner's last prompts verbatim; a SessionStart (`compact`) hook says which sources must be re-opened and that the summary is not a source; the status line counts squeezes (`hooks/recall.py`, heartbeat)
- [x] F3 recall at session start: `handoff:` names the handoff file; its first lines and its age are printed on startup, clear and resume; "stale" when older than the last commit
- [ ] F4 docs and counts (committed 2026-11-09, `ecfd874`) · the live `/compact` pass (needs the owner's scratch adapter) · a 30-second demo with invented files (Thu 12 Nov)
- [x] Security-review fix batch (review 2026-11-09 of `1a1e62c..HEAD`: the PowerShell tool skipped bash-guard; a crafted heredoc command ran past the hook timeout; 4 minor): plan `docs/notes/recall-security-fix-plan.md`, option A decided 2026-11-09, built and reviewed in ten rounds (2026-11-10; one fix round was reverted after its review found regressions); it ended with the rule "a command the gate cannot read counts as a send while the sources are unopened"; Monitor confirmed live on Claude Code 2.1.321; full PowerShell parity (write verbs on the human-only files, `iwr | iex`) goes to 0.7.0 with the Bash-side gap below
- [ ] Honest limits of the gate, listed in `docs/notes/recall-design.md` (said once here): a command built at run time (variables, brace and glob expansion, `$'…'` quoting) is not seen; on Bash at or under the heredoc cap a quoted word that spans lines is read whole (pinned known limit, see 0.7.0); a Python start slower than about 6 s is outside every deadline; the frozen RULES are slow on a very long, dense command, so when the sources are opened or there is no adapter such a command can outlast the hook timeout (see "every rule linear" above); PowerShell: write verbs on the human-only files, download-then-run and `-File` bodies (0.7.0). Accepted over-denies, one turn each: right after a compaction and before the sources are re-read, an unusual but harmless command in a tagged class (very long, heredocs past the cap, several substitutions, a `-c` / `eval` / `iex` / `cmd /c` / `-Command` string handed to another shell, PowerShell typographic quotes, escaped quotes, a block comment `<#`, or a `Start-Process` / `saps` / `start` word anywhere, `npm start` included) is denied once; a backtick escape inside that word is not caught yet (0.6.2, on a report); some other ways of handing a command to another shell or interpreter are not yet recognised as such (other spellings of the same launchers, text fed on standard input, process substitution, shell functions and traps; 0.6.2, on a report); an unquoted `Write-Host git push`, a publish word in a data here-string, an array, or on its own line inside a multi-line quoted PowerShell argument
- [ ] bash-guard RULES: `strip_heredocs` drops the body of an unquoted-delimiter heredoc (`<<EOF`) as data, but bash still runs `$( )` and backticks in it, so a rule's command placed there is not seen (found 2026-11-08 by an automated review and the phase 7 re-check; the fresh-source gate checks those bodies since 0.6.0; RULES and `strip_heredocs` were on the must-not-change list for 0.6.0)
- [ ] Open from the build: whether Claude Code adds a PreCompact hook's output to the owner's `/compact` text or replaces it (undocumented; the live pass settles it) · a `**`/`*` pattern that meets a link is refused (a `venv/`, a `jobs/latest` link): watch whether owners hit it
- Not in 0.6.0 (said once): a memory store or vector search (Claude Code's compaction and auto memory stay the substrate); a click on a page's own Send button (uploads and named commands are gated); a typed `sources:` line from a phone (needs the owner-quote check from the paid guard)

## 0.6.1 — lighter, faster, switchable (plan `docs/notes/light-fast-plan.md`; approved 2026-11-10; built and reviewed, waiting for the live pass and the push)
Claude waits on fewer hooks, honest commands stop being denied, and the owner gets a switch that only the owner can flip.
- [x] F0 measure: method M, "before" on Claude Code 2.1.322 (Bash 0.83 s, Read 0.76 s, Edit 0.98 s, Stop 0.54 s waited per call) · [ ] "after" numbers in the live pass (README has `[[F8-AFTER]]` placeholders until then)
- [x] F1 the heartbeat leaves the waiting path (Bash 3 → 1 hooks waited on, Read 2 → 0, Edit 3 → 1; `PostToolUseFailure`; finished-call ids; a state-file lock on Windows)
- [x] F2 two false denies fixed (a download into `python -m json.tool`; `sudo` carried as text) and the rule for changing `RULES` (plan §6)
- [x] F3 a missing Python is said aloud at session start; the empty `check:` line bug
- [x] F4 a guard level and a switch per rule (Strict guards, Rules off, Wait gate; every deny ends `[rule <name>]`) · F5 the switch is human-only · F6 strict means on
- [x] F7 `/smartuse:doctor` · [x] F8 docs, counts, version
- [x] Review 11 (Opus, xhigh): F1–F6 pass; two majors (a whole settings file deleted or replaced; the `env` block setting the option variables) fixed in one round; the minors are recorded as limits in SECURITY.md
- [ ] The live pass: experiments E1–E5 (plan §8), the five acceptance steps of F1, method M "after" · [ ] push the dev branch, then merge to main on the owner's word
- Not built: F9 (`onFailure: "block"` on the guards; nobody asked for it, see 0.7.0) and the optional `-S` start option

## 0.6.2 — parked follow-ups (were on 0.6.1)
Rule: more shell parsing waits for a real reported miss. The two items marked "on a report" are built only then.
- [ ] bash-guard: every rule linear in the command's length (0.5.1 reviews; moved up the list by review 11)
  - The heredoc scan is capped since 0.6.0 (a bound on heredoc openers and delimiter length; past it the bodies are read as code). A linear scanner is still open.
  - The frozen RULES patterns, and the three rules split out in 0.6.1 that reuse their heads, are quadratic on a very long, dense run of command words (seconds at 30 KB).
  - A command over 4,096 characters has the source check first, but with the sources opened or no adapter it still reaches RULES.
- [ ] Remove the deep-parsing code paths from fix rounds C–F (heredoc-body re-reads, nested-string recursion, PowerShell quote unescaping): the older round C–F helpers are kept for the suites, which call them directly, and `main()` still runs `ps_text` → `ps_unescape` on every PowerShell command; removing them is 0.6.2 work, and their unit checks should be re-pointed at `complexity()`
- [ ] Bash `command_segments`: the line-join for a trailing backslash does not check what precedes that backslash, so the line after an escaped backslash, or after a comment that ends in a backslash, can be misread (present before the security batch)
- [ ] On a report: recognise the remaining ways of handing a command to another shell (review rounds 6–7), each with a linear check and a timing case
- [ ] On a report: an adversarial pass over PowerShell tokenisation (the round-3 attempt was cut short, so it was never done)
- [ ] Windows long path: a very long project path pushes the state directory past the 248-character limit and state is silently not written; shorten the key or use the extended-length form, and say so when a write fails

## 0.7.0 — the paid-call guard (was 0.6.0; plan `docs/notes/paid-guard-plan.md`, YK's yes 2026-10-24; branches `paid-guard`, `paid-f3` rebased onto main 2026-11-06)
- [x] F1 detect and deny without a go · F2 run cap, one test output first, the counter's protection · hardening (on `paid-guard`, not merged)
- [ ] F3 the owner-quote check (WIP on `paid-f3`) · F4 docs
- [ ] PowerShell parity for the older rules (the 0.6.0 gate covers PowerShell, the rules mostly do not): download-then-run (`iwr` / `irm` … `| iex`, `-File`), `Remove-Item -Recurse -Force` of a root, the human-only write verbs (`Set-Content`, `Out-File`, `Add-Content`, `Copy-Item`, `Move-Item`, `New-Item`, `Remove-Item`, `[IO.File]::…`); `onFailure: "block"` scoped to the guards, decided with the paid-call guard (0.6.1's F9, not built): confirmed in the docs, needs Claude Code v2.1.295 or later; a failure is a command that cannot start, exits with a code other than 0 or 2, times out or prints invalid output; the field has no effect on Stop, SubagentStop and background hooks; one static setting for every user, and a machine that cannot start the hook would have every call blocked
- [ ] bash-guard: a quoted word that spans lines is read whole on Bash, at or under the heredoc cap (pinned known limit). Fixing it needs quote-aware per-line handling: reading every Bash text line by line turned seven quoted commit-message and PR-body allows into denies

## 0.4.0 also carries the audit's list (`docs/notes/audit-2026-10-22.md`: 42 confirmed, 7 refuted) — in three batches
- [x] hooks core (worker): the until-done gate holds until done or max_blocks (it yielded after one push per prompt); check runner finds npm/pnpm/yarn on Windows and stops after one "not found" block; state dir keyed by full path (two same-named repos shared one routing.json); UTF-8 stdin; Windows-safe status.json replace; no receipts after a run closed
- [x] guards (worker): bash-guard rules widened (sudo in if/for/subshell, `bash -c "$(curl …)"`, `git -C … push --force`, `+refspec`, key names without a directory prefix, Windows path spellings, echo-mention false positive); file-guard case-insensitive and normalised; UTF-8 stdin; PYTHONUTF8 in the launcher
- [x] skills + docs (worker): `$ARGUMENTS` in the three `!` lines (the `${1:-}` form was refused in default permission mode); make-prompt hands off to run-plan; living-docs writes its receipt and declares its tools; run-plan allowed-tools + headless example + accepted `check:` shapes; status legend; self-check 14; three new eval cases; README/CHANGELOG/CONTRIBUTING counts and claims; `hooks/tests/all.sh`
- [x] repo: `.gitattributes` (LF everywhere), CI matrix ubuntu/macOS/Windows and on the dev branch — green on all three (bac4685)

## Proposed — relay guards (case study 7; design and failing tests in `docs/notes/relay-design.md`; not in the 1.0 bar until YK adds it)
One session that delegates (above) removes most of their reason — photos become paths, there is no relay — so rules 1, 2 and 5 are for second-machine setups only. Rule 4 still matters in one session (a cheap subagent can spend): it is 0.7.0.
Rule 1's open-before-done gate ships in 0.6.0 as the fresh-source gate (opened = a Read after the last compaction); the rest of rule 1 (relay.py save, relay-guard) stays second-machine-only.
- [ ] Rule 4: a `paid` rule family in bash-guard — the owner's go per script, a cap, one test output first
- [ ] Rule 1: `relay.py save` + `relay-guard` on the relay channels, then the receiver's open-before-done Stop gate
- [ ] Rule 2: `inventory.py` + the brief gate; the ask-again check
- [ ] Rules 3 and 5: the review-file contract with a round-3 owner verdict; the planner's `deny_write:` and the empty `## Visual parameters` section

## 1.0 — public
- [ ] "30 days of receipts": the measured post with the A/B table and the ledger medians
- [ ] README rewrite for a first-time reader
- [ ] The owner's personal rules out of the make-prompt template
- [ ] Uninstall and privacy sections in the README: what the hooks read, what they write, how to remove the state under `~/.claude/smartuse/`
- [ ] Merge the ledger and the receipts into one view
- [ ] The skills' broad `Bash(bash *)` grants narrowed to the commands each skill runs
- [ ] The evals CI fix: slash-command cases score 0 in CI on Claude Code 2.1.322, so the evals workflow (`.github/workflows/evals.yml`) is run by hand until this is fixed
- [ ] Marketplace listing (community marketplace form), awesome-lists PRs (YK's clicks)
- [ ] README demo gif re-recorded on the laptop with the status line visible
- [ ] CHANGELOG squash into release notes; version 1.0.0; tag

## Not in 1.0 (said once so it is not relitigated)
- Another router or classifier; multi-vendor voting; anything needing a proxy or patched binary.
- A memory database, embeddings or a model call inside a hook: smartuse adds the gate and the pointer, never a store.
