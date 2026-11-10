STATUS: smartuse · updated 2026-11-10
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.0 recall released 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: maintainer said "go ship" · review 8 (of b248f59) found 2 new PowerShell majors → round J merged (f55adc8, plan §7g: block-comment and Start-Process tags; builder's T1 fresh 711 · run 269; full T2 NOT run on J) · review 9 (of f55adc8) → plan §7h: widen the Start-Process tag (round K) · owner decision plan §7i (996b19c): drop `~/.claude.json` from the credential rule · round K + §7i code: STOPPED half-done by the maintainer, UNCOMMITTED in the worktree .claude/worktrees/sec-j (branch sec-j at 3075083; 9 files modified, docs half done) · nothing pushed
Next: Claude: finish round K + §7i in sec-j (plan §7h, §7i), cherry-pick onto the dev branch, T2 one suite at a time, review 10; then push on the maintainer's word | maintainer: .smartuse-terms.local, then "push"; demo Thu 12 Nov
NEEDS YOU (1): at ship: write .smartuse-terms.local on this machine (one private term per line), then say "push" (CI on main red until then)
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
