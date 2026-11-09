STATUS: smartuse · updated 2026-11-10
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.0 recall released 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: 0.6.0 security fix batch built, reviewed seven times, docs committed (2bd00aa) · code = round G (51ecc57: a command the source check cannot read counts as a send while sources are unopened, plan §7e); round H reverted (93cf9b8, plan §7f) · T2 green at the head: run 269 · ledger 46 · until-done 40 · file-guard 26 · heartbeat 121 · ab 36 · watch 63 · wait 187 · fresh 659 · recall 210 · term-scan 6 · `claude plugin validate --strict` passes (ICON_MISSING only) · phase 6 passed at d47d901 (before round G) · nothing pushed (39 commits ahead)
Next: maintainer decides (NEEDS YOU 1) → Claude: either a short phase 6 rerun on the head plus UAT pack, or a careful round I for the open forms (each with a linear check and a timing case, then review) | maintainer: UAT and "push"; demo Thu 12 Nov; post Fri 13 Nov on his word
NEEDS YOU (3): 1 ship 0.6.0 at the head with the open "another shell" forms documented as limits for 0.6.1 (recommended), or harden first 2 keep or veto plan §7e (one extra denied turn for an unusual command after a squeeze; revert is one line) 3 at ship: .smartuse-terms.local on this machine, then "push" (CI on main red until then)
## Last 3 cards
- 2026-11-10 round H reverted after review 7 found three regressions it introduced (a quadratic regex past the hook timeout, an option walk and a quote reading that turned denies into allows); code back to round G
- 2026-11-10 direction change §7e after five review rounds kept finding crafted-input classes (planner on claude-fable-5-1 agreed; owner may veto)
- 2026-11-10 phase 6 at d47d901: all scripted scenarios PASS, live PowerShell and Monitor denies confirmed on Claude Code 2.1.321
## Unknowns
- open, pre-existing, documented: some ways of handing a command to another shell are not yet recognised (review rounds 6–7) → 0.6.1 or round I
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- new, low: on Windows a very long project path pushes the smartuse state dir past 248 characters and heartbeat/recall silently write no state → ROADMAP 0.6.1
- not checked: an adversarial PowerShell tokenisation hunt (a review run was cut short) → ROADMAP 0.6.1
- phase 6 ran before round G; the §7e rule's honest-use over-denies after a /compact were checked by review 6, not live
- CLAUDE.md names all.sh (parallel) as T2; this laptop runs the suites one at a time → the maintainer confirms which
- old worktrees: .claude/worktrees/f1, f23 (merged) and this batch's sec-a…sec-h, sec-docs → remove with the maintainer's ok
- leftover scratch outside the repo (agents' deletes were denied): listed in the session report, not here (public repo)
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/recall-security-fix-plan.md (§7b–§7f: review rounds, the direction change, the revert) · docs/notes/recall-security-fix-brief.md
- docs/STATUS-history-2026-11.md (the old STATUS, unchanged) · docs/ROADMAP.md
- docs/notes/recall-design.md · docs/notes/paid-guard-plan.md · docs/notes/py-cache-fix-plan.md
