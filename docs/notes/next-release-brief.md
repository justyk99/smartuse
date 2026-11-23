# 0.7.1 next brief (2026-11-23)

The spec is `docs/notes/next-release-plan.md` (approved 2026-11-23, D-YK16 yes, D-YK17 agreed). This file holds the state the next session starts from.

## Start state
- 0.7.0 released 2026-11-23: public main = `8a38454` (release at `3c7c92d`; `8a38454` fixed three release lines that still said not released).
- Work branch `fix-0.7.1` from `8a38454`, local only. Every feature merges into it with `--no-ff`.
- Counts (floors, from 0.7.0's T2): run 1340 · file-guard 107 · ledger 46 · until-done 50 · watch 63 · heartbeat 203 · wait-gate 196 · recall 203 · fresh-gate 758 · paid 1356 · ab 36 · term-scan 6.
- Nothing built yet. Phase next: 3 (contract), then 4 (build).

## Order (plan §5)
1. Lane A: E1 (measure the failing path length), then F1 (long path keeps state), then F2 (paid refusal wording).
2. Lane B, beside lane A: F3 (term-scan encoding), then E2 (200-loop race experiment), then F4 only if E2 reproduces it, rebased on F1's merge.
3. Lane C last: F5 (README uninstall and reads/writes sections, the test badge).
4. T2 after each merge (12 suites, one at a time). T3 once before the push. The push waits for the maintainer's word.

## Carry-over rules
- At most 2 heavy jobs at once on the laptop. Suites never run side by side, across all lanes.
- Builder briefs: every "as today" claim gets a file:line; a bug gets its red case first.
- Before the release push: `git grep -n -i -E 'not yet released|not released|unreleased|the build, not|then the release'` over README, CHANGELOG and ROADMAP, then fix every hit for 0.7.1.
- Leftovers the maintainer deletes (the permission system refused Claude): `.claude/worktrees/pg7-scratch/` and the old worktrees listed in STATUS.
