STATUS: smartuse · updated 2026-11-27
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released (done 2026-11-23) 3 0.7.1 hardening released (done 2026-11-24) 4 0.7.2 the scan reads every line released (done 2026-11-25) 5 0.7.3 the ledger line is kept released (done 2026-11-26) 6 0.7.4 the paid count is found at any path length released (done 2026-11-27) 7 the 1.0 items on docs/ROADMAP.md closed
Now: 0.7.4 released 2026-11-27: main fast-forwarded to `fix-0.7.4` and pushed. E1 the long form measured, F1 the paid check finds a counter left behind at any length, F2 doctor sees it and names `rm -rf` past 244 characters, F3 each paid refusal names a fix that works, F4 the watch case gets room and the `;` example is pinned, R1 and T3 reviews (no major; one fix round each), F5 docs and version. T2 12 of 12 (heartbeat 228+3 · run 1341 · paid 1436+1; the three suites the T3 fix touches run again). Bare publish scan 0 private hits. Plan docs/notes/0.7.4-plan.md (§10 results, §12 fix rounds).
Next: 0.7.5, Python starts isolated (plan docs/notes/0.7.5-plan.md, brief docs/notes/0.7.5-brief.md): E1 → F1 → F2 → F3 → F4 → R1 → T2 → F5 → T3, under the standing go to 1.0.
NEEDS YOU (2): 1 a tag only if you want one · 2 leftovers you delete (the permission system refused Claude): `.claude/worktrees/pg7-scratch/`, `f3-073/`, `fa-073/`, `f2-074/scratch/` (merged; removal refused), the old worktrees below
## Last 3 cards
- 2026-11-27 0.7.4 released: CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
- 2026-11-26 0.7.3 released: CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
- 2026-11-26 0.7.3 built: the ledger race fixed (1,000 rounds, one line each), E1 measured the too-long folder (a counter past 259 characters is missed after long paths go off: SECURITY.md, ROADMAP), E2 closed the 210 count, reviews no major
## Unknowns
- accepted (SECURITY.md): a delete of the state folder, a copy over the live counter, or a permission change on it resets the paid count: deliberate tampering with the owner's own state
- closed in 0.7.4 (F1, F2): a paid counter left in a full-key folder of any length after `LongPathsEnabled` is switched off is refused and named by doctor; a machine where it was already missed is refused until one folder is deleted (SECURITY.md)
- closed in 0.7.4 (F3): "path too long" is picked by the error the system gave; the counter-side tails no longer name the adapter
- low, flaky under load: watch-test's "push without the file" case now gives the watcher 30 s (0.7.4 F4, 63 PASS three times at low priority); run.sh's F7 timing case (1 s limit) took 2.16 s once beside a game, 0.13 to 0.16 s in 5 runs alone → widen only if it repeats in a quiet run
- method M's Stop wait is two-valued (about 0.33 or 0.57 s): not gated → look before 1.0
- open, documented: some ways of handing a command to another shell are not recognised; an adversarial PowerShell tokenisation hunt not done → on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- old worktrees: f1, f23, f3, lf-a…lf-e, sec-a…sec-j, sec-docs, pg7-a, pg7-b, pg7-ref (all merged) → remove with the maintainer's ok
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time, Claude Code stops background suites on low memory: restart only on the maintainer's word) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/0.7.5-plan.md · docs/notes/0.7.5-brief.md (0.7.5)
- docs/notes/0.7.4-plan.md · docs/notes/0.7.4-brief.md (0.7.4: plan, results, fix rounds)
- docs/notes/0.7.3-brief.md (the release steps) · docs/notes/0.7.3-plan.md (the 0.7.3 plan, results, fix round)
- docs/notes/0.7.2-plan.md (0.7.2)
- docs/notes/next-release-plan.md (0.7.1) · docs/notes/paid-guard-next-brief.md (the SECURITY.md classes) · docs/notes/paid-guard-plan.md (§8: 0.7.0)
- docs/STATUS-history-2026-11.md (the old STATUS) · docs/ROADMAP.md
