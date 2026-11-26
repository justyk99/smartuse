STATUS: smartuse · updated 2026-11-26
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released (done 2026-11-23) 3 0.7.1 hardening released (done 2026-11-24) 4 0.7.2 the scan reads every line released (done 2026-11-25) 5 0.7.3 the ledger line is kept released (done 2026-11-26) 6 the 1.0 items on docs/ROADMAP.md closed
Now: 0.7.3 released 2026-11-26: main fast-forwarded to `fix-0.7.3` and pushed. F1 the ledger line is kept (1,000 rounds of two Stop hooks: one line each), F2 doctor names a counter left behind, F3 the scan frames history on newlines, F4 the rule-name check fails, E1 the too-long folder measured, E2 the 210 count, F5 docs and version, review round A. T2 12 of 12 (ledger 53 · heartbeat 219+3 · paid 1403+1; watch-test flaked once under load, alone 63 PASS). Bare publish scan 0 private hits. Plan docs/notes/0.7.3-plan.md (§10 results, §12 the fix round).
Next: 0.7.4, the paid count is found at any path length (draft plan docs/notes/0.7.4-plan.md, brief docs/notes/0.7.4-brief.md): waits for the maintainer's yes on Card A (plan §11) and D-YK30 (a long-form look that errors: no counter, as today, or deny). Then E1 → F1 → F2 → F3 → R1 → F4 → T2 → F5 → T3.
NEEDS YOU (3): 1 the yes on the 0.7.4 plan (Card A, D-YK30) · 2 a tag only if you want one · 3 leftovers you delete (the permission system refused Claude): `.claude/worktrees/pg7-scratch/`, `.claude/worktrees/f3-073/` and `.claude/worktrees/fa-073/` (merged, removal refused), the old worktrees below
## Last 3 cards
- 2026-11-26 0.7.3 released: CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
- 2026-11-26 0.7.3 built: the ledger race fixed (1,000 rounds, one line each), E1 measured the too-long folder (a counter past 259 characters is missed after long paths go off: SECURITY.md, ROADMAP), E2 closed the 210 count, reviews no major
- 2026-11-25 0.7.2 released: CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
## Unknowns
- accepted (SECURITY.md): a delete of the state folder, a copy over the live counter, or a permission change on it resets the paid count: deliberate tampering with the owner's own state
- low, measured (0.7.3 E1): after `LongPathsEnabled` is switched off, a paid counter in a full-key folder of 245 characters or more is not seen and the count starts again (233 to 244: refused, and doctor names it) → ROADMAP, the paid-reasons batch
- low, pre-existing: `paid_why` says "path too long" even with long paths on (still a deny) → the paid-reasons batch (ROADMAP)
- low, flaky under load: watch-test's "push without the file" case gives the watcher 10 s; at lowest priority beside a game it failed once (0.7.3 T2 re-run), alone it passed → widen its --max if it repeats
- method M's Stop wait is two-valued (about 0.33 or 0.57 s): not gated → look before 1.0
- open, documented: some ways of handing a command to another shell are not recognised; an adversarial PowerShell tokenisation hunt not done → on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- old worktrees: f1, f23, f3, lf-a…lf-e, sec-a…sec-j, sec-docs, pg7-a, pg7-b, pg7-ref (all merged) → remove with the maintainer's ok
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time, Claude Code stops background suites on low memory: restart only on the maintainer's word) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/0.7.4-plan.md · docs/notes/0.7.4-brief.md (0.7.4, draft until the yes)
- docs/notes/0.7.3-brief.md (the release steps) · docs/notes/0.7.3-plan.md (the 0.7.3 plan, results, fix round)
- docs/notes/0.7.2-plan.md (0.7.2)
- docs/notes/next-release-plan.md (0.7.1) · docs/notes/paid-guard-next-brief.md (the SECURITY.md classes) · docs/notes/paid-guard-plan.md (§8: 0.7.0)
- docs/STATUS-history-2026-11.md (the old STATUS) · docs/ROADMAP.md
