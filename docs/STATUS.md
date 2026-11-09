STATUS: smartuse · updated 2026-11-09 12:10
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.0 recall released 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: 0.6.0 recall · phase 7 done, T2 green on 17e27fc (27 min), F4 docs committed ecfd874; phase 6 live pass blocked on the human-only scratch adapter; nothing pushed
Next: Claude, once the adapter exists: phase 6 (scripted pass, at most 6 headless `claude -p` runs on invented files), the 30-second demo (Thu 12 Nov), phase 8 security review of 1a1e62c..HEAD | maintainer: UAT and "push", post Fri 13 Nov on his word
NEEDS YOU (2): 1 (recommended) create the phase 6 scratch adapter by hand (guards keep smartuse.local.md human-only) 2 go to push a41adb2 (CI on main is red until then: the 3.9 job has no Python on ubuntu-latest); the pre-push scan needs .smartuse-terms.local on this machine first (see Unknowns)
## Last 3 cards
- 2026-11-09 94de8ae: status and roadmap updated after T2 and the F4 docs
- 2026-11-09 ecfd874 F4 docs: README, SECURITY, CHANGELOG, CONTRIBUTING, plugin README; README badge 1134 hook + 36 bench, checked against recall.py and bash-guard.py
- 2026-11-09 17e27fc: contract, roadmap and status after phase 7; full T2, one suite at a time, all green: run 152 · ledger 46 · until-done 40 · file-guard 26 · heartbeat 121 · ab 36 · watch 63 · wait 187 · fresh 309 · recall 190 · term-scan 6
## Unknowns
- later, asked of the maintainer: put .smartuse-terms.local on this machine (pre-push scan refuses without it; needed before the push above) · day-45 check Thu 26 Nov (1 star, 0 forks on 2026-11-06) · plugin icon before the 1.0 listing (square PNG 512-2048 px at .claude-plugin/icon.png) · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- does PreCompact output add to or replace the owner's /compact text → phase 6 headless runs
- docs/notes/input-2026-10-24-claude-system.md is on no machine searched → if it turns up, pick its 1.0 candidates and update the ROADMAP
- the CI 3.9 job pin (ubuntu-24.04) → not proven until a push
- paid-f3 has 3 failures (coproc in two suites, env --split-string) that predate the move → check before it merges
- the Done-when list above → assumed; the maintainer confirms
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/STATUS-history-2026-11.md (the old STATUS, unchanged)
- docs/ROADMAP.md
- docs/notes/recall-design.md
- docs/notes/paid-guard-plan.md
- docs/notes/py-cache-fix-plan.md
