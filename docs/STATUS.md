STATUS: smartuse · updated 2026-11-26
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released (done 2026-11-23) 3 0.7.1 hardening released (done 2026-11-24) 4 0.7.2 the scan reads every line released (done 2026-11-25) 5 0.7.3 the ledger line is kept 6 the 1.0 items on docs/ROADMAP.md closed
Now: 0.7.3 built on the local branch `fix-0.7.3`, in its review fix round; public main = 0.7.2 (`54f4b75`). Merged: F1 the ledger line is kept (1,000 rounds of two Stop hooks: one line each), F3 the scan frames history on newlines, E1/F2/F4 doctor names a counter left behind and the rule-name check fails, F5 docs and version. T2 12 of 12 (ledger 51 · heartbeat 219+3 · paid 1403+1, the rest as 0.7.2). Both validates pass. Fresh and security reviews: no major; round A fixes four minors. Plan docs/notes/0.7.3-plan.md (§10 results, §12 the fix round).
Next: finish round A, re-run its suites, the bare scan, then the release (brief docs/notes/0.7.3-brief.md). After that the next release picks from ROADMAP "Next release (after 0.7.3)": the paid check missing a counter past 259 characters first.
NEEDS YOU (2): 1 a tag only if you want one · 2 leftovers you delete (the permission system refused Claude): `.claude/worktrees/pg7-scratch/`, `.claude/worktrees/f3-073/` (empty), the old worktrees below
## Last 3 cards
- 2026-11-26 0.7.3 built: the ledger race fixed (1,000 rounds, one line each), E1 measured the too-long folder (a counter past 259 characters is missed after long paths go off: SECURITY.md, ROADMAP), E2 closed the 210 count, reviews no major
- 2026-11-25 0.7.2 released: CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
- 2026-11-25 0.7.2 reviews: the security review found that a folder copy could plant a counter (D9: two counters deny, checked again under the lock) and the scan could print a term in another encoding (D10, D13); fixed in four rounds, the re-check closed all
## Unknowns
- accepted (SECURITY.md): a delete of the state folder, a copy over the live counter, or a permission change on it resets the paid count: deliberate tampering with the owner's own state
- low, measured (0.7.3 E1): after `LongPathsEnabled` is switched off, a paid counter in a full-key folder of 245 characters or more is not seen and the count starts again (233 to 244: refused, and doctor names it) → ROADMAP, the paid-reasons batch
- low, pre-existing: `paid_why` says "path too long" even with long paths on (still a deny) → the paid-reasons batch (ROADMAP)
- method M's Stop wait is two-valued (about 0.33 or 0.57 s): not gated → look before 1.0
- open, documented: some ways of handing a command to another shell are not recognised; an adversarial PowerShell tokenisation hunt not done → on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- old worktrees: f1, f23, f3, lf-a…lf-e, sec-a…sec-j, sec-docs, pg7-a, pg7-b, pg7-ref (all merged) → remove with the maintainer's ok
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time, Claude Code stops background suites on low memory: restart only on the maintainer's word) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/0.7.3-brief.md (the release steps) · docs/notes/0.7.3-plan.md (the 0.7.3 plan, results, fix round)
- docs/notes/0.7.2-plan.md (0.7.2)
- docs/notes/next-release-plan.md (0.7.1) · docs/notes/paid-guard-next-brief.md (the SECURITY.md classes) · docs/notes/paid-guard-plan.md (§8: 0.7.0)
- docs/STATUS-history-2026-11.md (the old STATUS) · docs/ROADMAP.md
