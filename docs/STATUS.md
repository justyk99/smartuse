STATUS: smartuse · updated 2026-11-09
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.0 recall released 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: 0.6.0 recall · phase 8 security review found 2 majors (the PowerShell tool skips bash-guard; a crafted heredoc command runs past the 10 s hook timeout) and 4 minors · fix plan approved, option A · build not started; nothing pushed
Next: Claude: build per docs/notes/recall-security-fix-brief.md (builder A F2→F1→F3, then builder B F5→F4→F6, one at a time), T2, fresh review + security re-check, F7 docs, then phase 6 once the adapter exists (Wed 11 Nov), demo Thu 12 Nov | maintainer: UAT and "push", post Fri 13 Nov on his word
NEEDS YOU (2): 1 (recommended) create the phase 6 scratch adapter by hand: copy p6/adapter.txt to p6/yk-demo/.claude/smartuse.local.md in the session scratchpad that holds p6-brief.md (guards keep smartuse.local.md human-only) 2 go to push a41adb2 (CI on main is red until then); the pre-push scan needs .smartuse-terms.local on this machine first
## Last 3 cards
- 2026-11-09 plan docs/notes/recall-security-fix-plan.md approved; the maintainer left A/B to Claude, Claude chose A (B's extra PowerShell rules guard against deliberate tampering that stays open through Bash, so they cost the demo without making that promise true); brief docs/notes/recall-security-fix-brief.md
- 2026-11-09 security review of 1a1e62c..HEAD: majors re-verified (hooks.json:6 matches Bash only; 48 KB heredoc probe 4.84 s + 5.39 s); `claude plugin validate --strict` passes (ICON_MISSING only)
- 2026-11-09 acb65d0: project CLAUDE.md; STATUS in the card format, the old one kept unchanged in docs/STATUS-history-2026-11.md
## Unknowns
- later, asked of the maintainer: put .smartuse-terms.local on this machine (pre-push scan refuses without it) · day-45 check Thu 26 Nov (1 star, 0 forks on 2026-11-06) · plugin icon before the 1.0 listing (square PNG 512-2048 px at .claude-plugin/icon.png) · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- does PreCompact output add to or replace the owner's /compact text → phase 6 headless runs
- does Monitor reach a Bash matcher on the laptop's Claude Code version → phase 6 Part C records the version
- CLAUDE.md names all.sh (parallel) as T2; this laptop runs the suites one at a time → the maintainer confirms which
- the old recall worktrees .claude/worktrees/f1 and f23 (merged branches) → remove with the maintainer's ok
- docs/notes/input-2026-10-24-claude-system.md is on no machine searched → if it turns up, pick its 1.0 candidates and update the ROADMAP
- the CI 3.9 job pin (ubuntu-24.04) → not proven until a push · paid-f3's 3 failures predate the move → check before it merges
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/recall-security-fix-brief.md (next) · docs/notes/recall-security-fix-plan.md
- docs/STATUS-history-2026-11.md (the old STATUS, unchanged) · docs/ROADMAP.md
- docs/notes/recall-design.md · docs/notes/paid-guard-plan.md · docs/notes/py-cache-fix-plan.md
