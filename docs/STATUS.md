STATUS: smartuse · updated 2026-11-25
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released (done 2026-11-23) 3 0.7.1 hardening released (done 2026-11-24) 4 0.7.2 the scan reads every line released (done 2026-11-25) 5 the 1.0 items on docs/ROADMAP.md closed
Now: 0.7.2 released 2026-11-25: main fast-forwarded to `fix-0.7.2` and pushed. F1 the scan reads every line, F2 a made folder keeps the paid count, F3 a too-long kept folder is named, F4 SKIP, F5 docs and version, E1 the ledger drop traced, review fix rounds A–D. Final T2: 12 of 12. Bare publish scan 0 private hits. Plan docs/notes/0.7.2-plan.md (§10 results, §12 the fix rounds D9–D15).
Next: the next release picks from ROADMAP "Next release (after 0.7.2)": the ledger fix first (its red case is E1b, the fix shape is in ROADMAP).
NEEDS YOU (2): 1 a tag for 0.7.2 only if you want one · 2 leftovers you delete (the permission system refused Claude): `.claude/worktrees/pg7-scratch/`, the old worktrees below
## Last 3 cards
- 2026-11-25 0.7.2 released: CHANGELOG dated, stale-wording grep clean, bare scan 0 private hits, main fast-forwarded and pushed
- 2026-11-25 0.7.2 reviews: the security review found that a folder copy could plant a counter (D9: two counters deny, checked again under the lock) and the scan could print a term in another encoding (D10, D13); fixed in four rounds, the re-check closed all
- 2026-11-25 0.7.2 E1: the ledger drop is a sharing violation on the claimed file (3 in 1,000; a held delete handle reproduces it); fix shape in ROADMAP
## Unknowns
- low, traced (0.7.2 E1): the ledger race drops a line about 3 in 1000 on Windows → the fix in the next release (ROADMAP)
- accepted (SECURITY.md): a delete of the state folder, a copy over the live counter, or a permission change on it resets the paid count: deliberate tampering with the owner's own state
- low: doctor does not name the layout a `LongPathsEnabled` switch-off leaves (a counter in a full-key folder over 232 characters); the paid check refuses it → ROADMAP
- low, pre-existing: the scan splits lines on a bare `\r`; `paid_why` says "path too long" even with long paths on (still a deny); heartbeat-test's RULE_NAMES skip branch is stale → next release
- method M's Stop wait is two-valued (about 0.33 or 0.57 s): not gated → look before 1.0
- the 0.6.1 docs quoted recall-test 210; the suite prints 203 → find where 210 came from before a release text quotes it
- open, documented: some ways of handing a command to another shell are not recognised; an adversarial PowerShell tokenisation hunt not done → on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- old worktrees: f1, f23, f3, lf-a…lf-e, sec-a…sec-j, sec-docs, pg7-a, pg7-b, pg7-ref (all merged) → remove with the maintainer's ok
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time, Claude Code stops background suites on low memory: restart only on the maintainer's word) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/0.7.2-brief.md (the release steps) · docs/notes/0.7.2-plan.md (the 0.7.2 plan, results, fix rounds)
- docs/notes/next-release-plan.md (0.7.1) · docs/notes/paid-guard-next-brief.md (the SECURITY.md classes) · docs/notes/paid-guard-plan.md (§8: 0.7.0)
- docs/STATUS-history-2026-11.md (the old STATUS) · docs/ROADMAP.md
