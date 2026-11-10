STATUS: smartuse · updated 2026-11-10
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.1 released 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: 0.6.0 released on main 2026-11-10 (e5713d3) · 0.6.1 "lighter, faster, switchable" built (F0–F8, plan docs/notes/light-fast-plan.md), reviewed (review 11 + one fix round), docs written · waiting for the live pass (experiments E1–E5, method M "after" numbers) and the push · the README's "after" cells say [[F8-AFTER]] until then
Next: live pass on the laptop → fill the [[F8-AFTER]] cells → push the dev branch → merge to main on the maintainer's word | demo Thu 12 Nov
NEEDS YOU: none until push
## Last 3 cards
- 2026-11-10 0.6.1 docs written (F8): README "Switches" and counts, SECURITY, CHANGELOG, ROADMAP (0.6.2 parked), version 0.6.1; waiting for the live pass
- 2026-11-10 review 11 of 556b332: F1–F6 pass; two majors (a whole settings file deleted or replaced; the `env` option variables) fixed in one round, merged at 769f1c7
- 2026-11-10 0.6.1 plan approved whole (both cuts) and built on two tracks; 0.6.0 released on main (e5713d3)
## Unknowns
- open, pre-existing, documented: some ways of handing a command to another shell are not yet recognised (review rounds 6–7) → ROADMAP 0.6.2, built on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- new, low: on Windows a very long project path pushes the smartuse state dir past 248 characters and heartbeat/recall silently write no state → ROADMAP 0.6.2
- not checked: an adversarial PowerShell tokenisation hunt (a review run was cut short) → ROADMAP 0.6.2, on a reported miss
- phase 6 ran before round G; the §7e rule's honest-use over-denies after a /compact were checked by review 6, not live
- CLAUDE.md names all.sh (parallel) as T2; this laptop runs the suites one at a time → the maintainer confirms which
- old worktrees: .claude/worktrees/f1, f23 (merged) and this batch's sec-a…sec-h, sec-docs → remove with the maintainer's ok
- leftover scratch outside the repo (agents' deletes were denied): listed in the session report, not here (public repo)
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/recall-security-fix-plan.md (§7b–§7f: review rounds, the direction change, the revert) · docs/notes/recall-security-fix-brief.md
- docs/STATUS-history-2026-11.md (the old STATUS, unchanged) · docs/ROADMAP.md
- docs/notes/recall-design.md · docs/notes/paid-guard-plan.md · docs/notes/py-cache-fix-plan.md
