STATUS: smartuse · updated 2026-11-10
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.0 recall released 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: 0.6.0 security fix batch · F1–F6 + review rounds C–F merged on the dev branch (d47d901), T2 green at every merge (last: run 231 · ledger 46 · until-done 40 · file-guard 26 · heartbeat 121 · ab 36 · watch 63 · wait 187 · fresh 522 · recall 210 · term-scan 6) · phase 6 passed at d47d901, no hook failure (Claude Code 2.1.321; PowerShell and Monitor denied live) · round G (plan §7e: a command the gate cannot read counts as a send while sources are unopened) being built in .claude/worktrees/sec-g · F7 docs drafted in .claude/worktrees/sec-docs, not committed (number markers to fill) · nothing pushed
Next: Claude: merge G, T2, review 6, fill the F7 markers (counts from the last T2; 48 KB = 0.38 s median wall; Monitor confirmed on 2.1.321), commit docs | maintainer: veto §7e or not; UAT and "push"; post Fri 13 Nov on his word
NEEDS YOU (2): 1 keep or veto plan §7e (one extra denied turn for an unusual command after a squeeze; revert is one line) 2 at ship: .smartuse-terms.local on this machine, then "push" (CI on main red until then)
## Last 3 cards
- 2026-11-10 direction change §7e after five review rounds kept finding crafted-input classes (planner on claude-fable-5-1 agreed; owner may veto)
- 2026-11-10 phase 6 at d47d901: all scripted scenarios PASS, live B/C PASS except the send step (fixture photos are not valid images); report in the session scratchpad p6-report-d47d901.md
- 2026-11-10 review rounds 1–5 on the batch: majors fixed in rounds C–F (87b3cc2..d47d901); decisions in plan §7b–§7d
## Unknowns
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- new, low: on Windows a very long project path pushes ~/.claude/smartuse/projects/<key> past 248 chars and heartbeat/recall silently write no state → ROADMAP
- not checked: an adversarial PowerShell tokenisation hunt (a review run was cut short) → 0.6.1
- CLAUDE.md names all.sh (parallel) as T2; this laptop runs the suites one at a time → the maintainer confirms which
- old worktrees: .claude/worktrees/f1, f23 (merged) and this batch's sec-a…sec-g, sec-docs → remove with the maintainer's ok
- leftover scratch outside the repo (agents' deletes were denied): listed in the session report, not here (public repo)
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/recall-security-fix-plan.md (§7b–§7e: review rounds and the direction change) · docs/notes/recall-security-fix-brief.md
- docs/STATUS-history-2026-11.md (the old STATUS, unchanged) · docs/ROADMAP.md
- docs/notes/recall-design.md · docs/notes/paid-guard-plan.md · docs/notes/py-cache-fix-plan.md
