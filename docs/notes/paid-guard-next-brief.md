# 0.7.0 next brief — after F4b step 1 (2026-11-14)

The spec stays `paid-guard-plan.md` §8 (F5, §8.6, §8.7, §8.8). This file holds the state the next session starts from. Next session: the settings edit (F2 step 2) by hand, then the release on the owner's word. Update 2026-11-17: the bytecode cache (D-YK15) is merged (`13976b3`); method M passes (Bash 0.357 base · 0.360 light · 0.359 armed, plan §8.10). F5 merged (`cdf5cdb`) with its one review fix round (`fd99875`, plan §8.10); T2 after it 12 of 12.

## Start state
- Dev branch `paid-0.7.0`, local only, every feature merged with `--no-ff`: F0, F1, F2, F9, F3, F4b steps 1–3, F6, the fix round, F7, F8, the small fixes, F10, the review fixes. Last: step 1 merge on `97ca6ba`, docs `049ce4e`. T2 after it: 12 of 12 ALL PASS.
- Counts now (floors): run 1340 · file-guard 107 · ledger 46 · until-done 50 · watch 63 · heartbeat 203 · wait-gate 196 · recall 203 · fresh-gate 758 · paid 1356 · ab 36 · term-scan 6.
- T3 done so far: both `claude plugin validate --strict` pass; `term-scan.py --history` 0 private hits (rerun it before the push; the tree scan on 049ce4e has 192 generic hits, 0 private). Left: the settings edit (F2 step 2) by hand; the live pass and method M are done (2026-11-14 and 2026-11-17); `baseline.json` stays in the session scratchpad (`scratch/` is not gitignored here).
- Worktree `.claude/worktrees/pg7-a` (branch `pg7-a`) is at `fd99875`, merged into the dev branch. Method D tools: `.claude/worktrees/pg7-scratch/f3/replay.py` with the F2 `events.jsonl`; never pass `--monitor` now that F3 is the base.
- Names now: `RULE_NAMES` = the 16 of 0.6.1 + `settings-file`, `owner-file`, `ps-download-exec`, `ps-rm-root` (20). `GATE_NAMES` = `paid`. `FLOOR` = `human-only`, `trust-pin`, `config-switch`, `settings-file`, `owner-file`.

## What is left, in order
1. ~~F4b step 1, the folder lookup~~ done 2026-11-14 (D-YK13 yes): built, two Opus re-checks, every fail-open a red-first case; limits in SECURITY.md ("The folder lookup", "How a found file is matched").
2. ~~F5, the typed go~~ built and merged 2026-11-17 with one review fix round (plan §8.10). Live pass done 2026-11-17 (plan §8.10): the phone go ran 3 of 3, run 4 refused; a relayed go and a subagent refused.
3. ~~F10~~ done (version 0.7.0). 4. ~~Review (§8.8)~~ done, fixes merged.
5. **T3 (§8.7):** the live pass (every interactive scenario, method M after columns with 3+ runs each), then `term-scan.py --history` with 0 private hits. Then the checklist summary and the push only on the owner's word.

## For SECURITY.md (F10): limits by class, held to the no-spiral rule (§8.6)
- A command handed to another shell in a way the guard does not parse: quotes inside a word, `eval`/`source`, a download kept in a variable and run later with `iex`, `pwsh -Command "…"`, `& $var`.
- `python -m <module>` and helper modules are not followed; a script over 256 KB is read only in part.
- The count rule takes exact flags; a shortened flag that argparse accepts is refused only as "no count flag".
- The counter is matched by file name: a delete of the whole state folder, or a glob over it, resets the count. Same for an owner file named through a wildcard or an odd spelling (`./`, `..`).
- Folder changes the guard does not count: Start-Process `-WorkingDirectory`, `sudo -D`, tool folder flags (`pnpm -C`, `yarn --cwd`, `uv --directory`). The folder lookup follows only the 6 nearest named folders; a cut lookup is unreadable.
- file-guard does not match the counter's own temp file `paid-runs.json.<pid>.tmp`, nor transcripts under a relocated config folder (`CLAUDE_CONFIG_DIR`).
- ps-download-exec: a gap over 300 characters (150 for the saved-file form) hides a download-then-run; `DownloadFile(...)` and `wget` without `-O` are not followed.
- ps-rm-root: through the PowerShell tool, flags after the `${env:USERPROFILE}` brace form are not seen; computed paths (`$(...)`, `[Environment]::...`) are not resolved.
- The sudo waiver reads a comment as text, so a quote in a comment can still hide a `sudo` line from it.
- The typed lines (F5): only the last 4 MB of the transcript are read; a typed stop is stored only at the next paid call (lost after `/clear` or 4 MB); an adapter go stands on a cut transcript; `owner-file` matches a transcript by its path text; a record with no `timestamp` counts for no `test ok` or take-over.
- Over-denies the owner may meet: an `only` script whose argument holds a backslash or an inner quote is paid; a harmless PowerShell loop before a paid run makes the run a repeat; `sed`, `awk` or `python` on the adapter are refused (readers only); `Get-Content <adapter> | Select-String` is refused; a commit message holding "iwr | iex" is refused; F2's settings-path over-denies.

## Lessons for the builder briefs
- Every merge has drawn an automated security review with new findings. Classify each against the list above before building anything; build only findings in new code that move a run toward paid, and batch them.
- Keep each timing text under 32 KB. Fixtures that name a paid host, a settings path or a download-run go in a file.
- Suites one at a time; never two in one message. `ledger-test.sh:52` is a known flake.
