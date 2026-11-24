# 0.7.1 release brief (2026-11-24)

The spec and results are `docs/notes/next-release-plan.md` (§10 results, §12 contract, last section D8). This file holds the state the next session starts from.

## Start state
- Branch `fix-0.7.1` (local only) holds 0.7.1, built and tested: T2 12 of 12 after the last change, T3 passed except the optional live F2 adapter check (plan §10).
- Public main = `8a38454` (0.7.0). Nothing of 0.7.1 is pushed.
- `CHANGELOG.md` head reads `## 0.7.1 — unreleased, "hardening"`.

## Release steps (only after the maintainer's word)
1. Optional, if the maintainer wrote the F2 test adapter: run the prepared headless adapter check; run 1 allowed, run 2 refused with the adapter wording.
2. CHANGELOG head: `unreleased` → the release date. Then `git grep -n -i -E 'not yet released|not released|unreleased|the build, not|then the release' -- README.md CHANGELOG.md docs/ROADMAP.md`: the only hit allowed is the old `0.1.0 — unreleased (packaged …)` line. ROADMAP: tick T3 and the release box.
3. The publish scan typed bare: `python scripts/term-scan.py --history --max-hits 1000000` → 0 private hits; plus the per-line re-check (every private pattern on every line, counts only), because the scan keeps one pattern per line (STATUS Unknowns).
4. Fast-forward main to `fix-0.7.1` (no force-push), push main to the public remote. Tag only if the maintainer asks.
5. STATUS: 0.7.1 released; the next release picks from ROADMAP "Next release (after 0.7.1)".

## Carry-over rules
- At most 2 heavy jobs at once on the laptop; suites never side by side. Claude Code stops a background suite when memory runs low: report it, restart only on the maintainer's word.
- Builder briefs: every "as today" claim gets a file:line; a bug gets its red case first; name every import allowlist (four suites have one: wait-gate, recall, paid-guard, fresh-gate).
- A limit measured on one machine holds only for its switches (D8): name the switch in the rule.
- Leftovers the maintainer deletes (the permission system refused Claude): `.claude/worktrees/pg7-scratch/` and the old worktrees in STATUS (this batch's five were removed with `git worktree remove`).
