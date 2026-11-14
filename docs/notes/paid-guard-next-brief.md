# 0.7.0 next brief — after F8 and the small fixes (2026-11-14)

The spec stays `paid-guard-plan.md` §8 (F4b, F5, F10, §8.6, §8.8). This file holds the state the next session starts from, and the review findings F10 writes into SECURITY.md.

## Start state
- Dev branch `paid-0.7.0`, local only, every feature merged with `--no-ff`: F0, F1, F2, F9, F3, F4b steps 2–3, F6, the fix round (8 findings), F7, F8, the two small fixes. T2 after each merge: 12 of 12 ALL PASS.
- Counts now: `run.sh` 1178, `fresh-gate-test.sh` 758, `paid-guard-test.sh` 852, `file-guard-test.sh` 107; the other suites unchanged (ledger 46, until-done 50, watch 63, heartbeat 178, wait-gate 196, recall 203, ab 36, term-scan 6).
- Worktree `.claude/worktrees/pg7-a` (branch `pg7-a`) is level with the dev branch. Method D tools: `.claude/worktrees/pg7-scratch/f3/replay.py` with the F2 `events.jsonl`; never pass `--monitor` now that F3 is the base.
- Names now: `RULE_NAMES` = the 16 of 0.6.1 + `settings-file`, `owner-file`, `ps-download-exec`, `ps-rm-root` (20). `GATE_NAMES` = `paid`. `FLOOR` = `human-only`, `trust-pin`, `config-switch`, `settings-file`, `owner-file`.

## What is left, in order
1. **F4b step 1, the folder lookup (only with D-YK13).** Plan §8.4 F4b step 1. `paid_script_files` returns the found files (one today); step 1 adds the folders a plain word before the script names. About 15 cases.
2. **F5, the typed go (needs E1/E2 from the owner's phone).** Plan §8.4 F5. Shapes known so far are in §8.10 (CLI `origin.kind=human`; headless no `origin`; a subagent carries `agent_id`; a peer report is `origin.kind=peer`).
3. **F10, names, docs, counts, version.** Plan §8.4 F10, plus:
   - `heartbeat.py` doctor: `rules_off=paid` prints "unknown name: paid"; the compare reads `RULE_NAMES` plus `GATE_NAMES`.
   - The `owner-file` reason still names only the paid runs; since F7 it also covers the adapter, the trust file and the launcher file.
   - `plugin.json` and `.claude-plugin/marketplace.json` still say 0.6.1.
   - SECURITY.md limits: the list below.
4. **Review (§8.8):** one fresh review on Opus at xhigh over `origin/main..paid-0.7.0`. One fix round for blockers and majors.
5. **T3 (§8.7):** T2, both `claude plugin validate --strict`, the live pass (every interactive scenario, method M after columns with 3+ runs each), `term-scan.py --history` with 0 hits.

## For SECURITY.md (F10): limits by class, held to the no-spiral rule (§8.6)
- A command handed to another shell in a way the guard does not parse: quotes inside a word, `eval`/`source`, a download kept in a variable and run later with `iex`, `pwsh -Command "…"`, `& $var`.
- `python -m <module>` and helper modules are not followed; a script over 256 KB is read only in part.
- The count rule takes exact flags; a shortened flag that argparse accepts is refused only as "no count flag".
- The counter is matched by file name: a delete of the whole state folder, or a glob over it, resets the count. Same for an owner file named through a wildcard or an odd spelling (`./`, `..`).
- Folder changes the guard does not count: Start-Process `-WorkingDirectory`, `sudo -D`, tool folder flags (`pnpm -C`, `yarn --cwd`, `uv --directory`). Without step 1, `cd sub && python client.py` is also not followed.
- file-guard does not match the counter's own temp file `paid-runs.json.<pid>.tmp`, nor transcripts under a relocated config folder (`CLAUDE_CONFIG_DIR`).
- ps-download-exec: a gap over 300 characters (150 for the saved-file form) hides a download-then-run; `DownloadFile(...)` and `wget` without `-O` are not followed.
- ps-rm-root: through the PowerShell tool, flags after the `${env:USERPROFILE}` brace form are not seen; computed paths (`$(...)`, `[Environment]::...`) are not resolved.
- The sudo waiver reads a comment as text, so a quote in a comment can still hide a `sudo` line from it.
- Over-denies the owner may meet: an `only` script whose argument holds a backslash or an inner quote is paid; a harmless PowerShell loop before a paid run makes the run a repeat; `sed`, `awk` or `python` on the adapter are refused (readers only); `Get-Content <adapter> | Select-String` is refused; a commit message holding "iwr | iex" is refused; F2's settings-path over-denies.

## Lessons for the builder briefs
- Every merge has drawn an automated security review with new findings. Classify each against the list above before building anything; build only findings in new code that move a run toward paid, and batch them.
- Keep each timing text under 32 KB. Fixtures that name a paid host, a settings path or a download-run go in a file.
- Suites one at a time; never two in one message. `ledger-test.sh:52` is a known flake.
