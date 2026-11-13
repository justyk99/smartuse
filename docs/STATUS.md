STATUS: smartuse · updated 2026-11-13
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: 0.6.1 "lighter, faster, switchable" released on main 2026-11-11 (f1f4ea5; CI green on ubuntu 3.12, ubuntu-24.04 3.9, macOS, Windows, validate) · waited per call 0.6.0 → 0.6.1: Bash 0.83 → 0.41 s, Read 0.76 → 0.00 s, Edit 0.98 → 0.35 s, Stop 0.54 → 0.56 s · 0.7.0 paid-call guard: plan v2 approved whole 2026-11-13 (docs/notes/paid-guard-plan.md §8, F0–F10, one release; estimate about 17 agent runs, about 10 M tokens, 3–4 working days)
Next: dev-flow phase 3/4 for 0.7.0: start at F0 (§8.4: dev branch `paid-0.7.0` from origin/main, worktrees pg7-a/pg7-b, T2 floor, branch reference counts on 19c7e45, method M "before", experiments E1–E5) | open: 0.6.1's E3/E4 not exercised live
NEEDS YOU (1): D-YK11 (the repo CLAUDE.md test lines: add paid-guard-test.sh to T1; T2 one suite at a time) is the maintainer's edit; F0's phone prompt (E1) needs 10 minutes of him
## Last 3 cards
- 2026-11-13 0.7.0 plan v2 approved whole ("2"): re-port the paid block onto 0.6.1, both security findings (json.tool flags only; settings files read-only from the shell), typed go, PowerShell parity, comment fix
- 2026-11-11 0.6.1 released on main (f1f4ea5), CI green on five jobs
- 2026-11-10 0.6.1 docs written (F8): README "Switches" and counts, SECURITY, CHANGELOG, ROADMAP (0.6.2 parked), version 0.6.1
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
