STATUS: smartuse · updated 2026-11-27
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released (done 2026-11-23) 3 0.7.1 hardening released (done 2026-11-24) 4 0.7.2 the scan reads every line released (done 2026-11-25) 5 0.7.3 the ledger line is kept released (done 2026-11-26) 6 0.7.4 the paid count is found at any path length released (done 2026-11-27) 7 0.7.5 Python starts isolated released (done 2026-11-27) 8 the 1.0 items on docs/ROADMAP.md closed
Now: 0.7.5 released 2026-11-27: CI's five jobs green on `claude/fix-0.7.5`, then main fast-forwarded and pushed. E1 the isolated start measured (same answers, the plants run today, no measurable cost), F1 every hook starts with `-I -S -X utf8`, F2 the remembered name carries its mark and a Python that refuses `-I` still runs the hooks, F3 the code-page cases bite again, F4 doctor says `isolated`, R1 (one lockout found and fixed), T3 (docs fixes), F5 docs and version. T2 12 of 12 after the R1 fix (heartbeat 299+3; fresh-gate's timing cases failed once under load and passed alone). Bare publish scan 0 private hits. Plan docs/notes/0.7.5-plan.md (§10 results, §12 R1).
Next: 0.7.6, the skills' `Bash(bash *)` grants narrowed, with the ledger and receipts in one view ("To 1.0" item 2 in docs/ROADMAP.md): a plan first; the view's look needs one mock the maintainer taps.
NEEDS YOU (2): 1 a tag only if you want one · 2 leftovers you delete (the permission system refused Claude): `.claude/worktrees/pg7-scratch/`, `f3-073/`, `fa-073/`, `f2-074/scratch/` (merged; removal refused), four `tmp.*` folders in the system temp folder from a 0.7.5 builder's suite runs, the old worktrees below
## Last 3 cards
- 2026-11-27 0.7.5 released: CI green on the work branch, CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
- 2026-11-27 0.7.4 released: CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
- 2026-11-26 0.7.3 released: CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
## Unknowns
- accepted (SECURITY.md): a delete of the state folder, a copy over the live counter, or a permission change on it resets the paid count: deliberate tampering with the owner's own state
- closed in 0.7.4 (F1, F2): a paid counter left in a full-key folder of any length after `LongPathsEnabled` is switched off is refused and named by doctor; a machine where it was already missed is refused until one folder is deleted (SECURITY.md)
- closed in 0.7.4 (F3): "path too long" is picked by the error the system gave; the counter-side tails no longer name the adapter
- low, flaky under load: watch-test's "push without the file" case now gives the watcher 30 s (0.7.4 F4, 63 PASS three times at low priority); run.sh's F7 timing case (1 s limit) took 2.16 s once beside a game, 0.13 to 0.16 s in 5 runs alone → widen only if it repeats in a quiet run
- assumed, not measured (0.7.5 E1): a real Store Python behaves as Python's documentation says with `-I -S -X utf8` (only the Store alias stub is on the laptop; the stub takes the flags, ignores them and exits 9009 as before) → a report
- assumed, not measured (0.7.5 E1): the Python install manager's aliases (a `WindowsApps` hit is still never trusted, so such a machine keeps two starts per event, both isolated) → a report
- assumed, not measured (0.7.5 E1): Linux, macOS and bash 3.2 start every hook isolated and the launcher runs on bash 3.2 (no machine here) → CI's five jobs on the pushed work branch before main moves
- assumed, not measured (0.7.5 E1): any Python other than 3.13 and any older than 3.9, another Windows build or Git Bash version, `py` with its own settings file, the cost of the first event (the cold probe), and a quiet laptop (E1e ran with the laptop in use) → a report, or the next quiet run
- method M's Stop wait is two-valued (about 0.33 or 0.57 s): not gated → look before 1.0
- open, documented: some ways of handing a command to another shell are not recognised; an adversarial PowerShell tokenisation hunt not done → on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- old worktrees: f1, f23, f3, lf-a…lf-e, sec-a…sec-j, sec-docs, pg7-a, pg7-b, pg7-ref (all merged) → remove with the maintainer's ok
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time, Claude Code stops background suites on low memory: restart only on the maintainer's word) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/0.7.5-plan.md · docs/notes/0.7.5-brief.md (0.7.5: plan, results, R1)
- docs/notes/0.7.4-plan.md · docs/notes/0.7.4-brief.md (0.7.4: plan, results, fix rounds)
- docs/notes/0.7.3-brief.md (the release steps) · docs/notes/0.7.3-plan.md (the 0.7.3 plan, results, fix round)
- docs/notes/0.7.2-plan.md (0.7.2)
- docs/notes/next-release-plan.md (0.7.1) · docs/notes/paid-guard-next-brief.md (the SECURITY.md classes) · docs/notes/paid-guard-plan.md (§8: 0.7.0)
- docs/STATUS-history-2026-11.md (the old STATUS) · docs/ROADMAP.md
