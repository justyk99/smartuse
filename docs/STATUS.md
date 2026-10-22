# STATUS — smartuse (owner: Smartuse-Brain · updated 2026-10-22 12:00 UTC)

Mandate (YK, 2026-10-22): the Brain drives to 1.0 and asks only for real decisions; the laptop session Smartuse-Worker does laptop-only steps. Plan: `docs/ROADMAP.md`. Dev branch: `claude/inspiring-galileo-8icw6s`.

## Done
- 0.3.0 on `main`, CI green; the marketplace serves it. The release page is still not published (see Blocked).
- 0.4.0-dev on the branch: heartbeat, receipts by model, A/B runner, Windows (all five hook suites green on the laptop and on the Windows CI runner), and **audit batch one** (until-done gate now holds until done; hooks read stdin as UTF-8; widened bash-guard rules; state dir keyed by full path; skills on the hooks' state-dir API; 3 eval cases; `hooks/tests/all.sh`): `run 94 · ledger 28 · until-done 32 · file-guard 10 · heartbeat 66 · ab 36`.
- **A/B run 3** (5 bench asks × 3 dials, Opus pinned): median cost −24 % on both routed dials over 4 asks; agent output not lower; 11 of 12 runs green; one aggressive run left 3 failing tests. In README with the caveats. Post #3 material.
- Audit fix-check (all 5 lenses): 29 of 42 verified fixed; the legacy state dir is now display-only and CI has a Python 3.9 leg. **CI green on all five jobs** (Linux, macOS, Windows, Python 3.9, strict validate) at 23cc9df. Laptop: all suites + bench green on real Windows (bac4685).

## In progress
- Worker 1: every state write goes through the hook CLI (`ledger.py --put/--unit/--run`), because in default permission mode Claude Code prompts on any Write under `~/.claude/` — every receipt would have cost the user a click. Plus: bash-guard treats a heredoc fed to `bash <script>` as data; status and receipts skills aligned with their eval graders.
- Worker 2: the remaining doc accuracy findings (counts, eval totals, manifests, `check:` shapes, footprint).
- Next: score all 8 eval cases here (sandbox tools installed), one laptop re-test, then 0.4.0 to `main`.

## Blocked on YK
- The release page for v0.3.0 (and later 0.4.0): the harness will not let the Brain publish, and the laptop needs YK to allow `gh`. One paste in the laptop terminal ends this (my message of 2026-10-22 08:00 UTC).
- LinkedIn post #2: his one line + "post", Friday 23 Oct 13:00 MYT (wake-up armed).

## Next (mine)
- Merge the state-dir fix, full suite, CI green on all legs → 0.4.0 release notes final → merge to `main`.
