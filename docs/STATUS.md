STATUS: smartuse · updated 2026-11-10
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.0 recall released 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: maintainer said "go ship" · rounds J (f55adc8, §7g) and K (1b6ebab, §7h) closed review 8's and 9's PowerShell majors as §7e tags · review 10 (of 1b6ebab): no new major; one 0.6.1-class limit documented · owner decisions built: §7i (`~/.claude.json` out of the credential rule) and the version bump to 0.6.0 · T2 green on that tree, each suite alone: run 272 · ledger 46 · until-done 40 · file-guard 26 · heartbeat 121 · ab 36 · watch 63 · wait 187 · fresh 722 · recall 210 · term-scan 6 · a whole-plugin review ran (speed, friction, docs, setup, platform, rivals) → plan for 0.6.1 "lighter, faster, switchable" written (docs/notes/light-fast-plan.md, brief beside it), not yet approved · the dev branch is pushed at a5726af (2026-11-10; term-scan --history with the private list: 0 private hits, the generic hits are test fixtures); main is not merged
Next: maintainer picks the 0.6.1 build: cut 1 only (plan §10, recommended) or the whole plan → Claude: dev-flow phase 3 onward | merge to main on the maintainer's word, after a short live pass on the head (the last one ran before round G) | demo Thu 12 Nov
NEEDS YOU (2): 1 0.6.1: cut 1 only (recommended), the whole plan, or change it (plan §10–§12) 2 say when 0.6.0 goes to main (CI on main is red until then)
## Last 3 cards
- 2026-11-10 0.6.1 plan written after a seven-part review: the slowness is hook starts, not guard logic; the planner confirmed six Claude Code features in the official docs
- 2026-11-10 review 10 of round K: no new major; ship-ready pending the maintainer's push
- 2026-11-10 round H reverted after review 7 found three regressions it introduced (a quadratic regex past the hook timeout, an option walk and a quote reading that turned denies into allows); code back to round G
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
