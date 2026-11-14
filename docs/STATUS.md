STATUS: smartuse · updated 2026-11-14
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: 0.7.0 on the local dev branch `paid-0.7.0` (not pushed). Merged: F0, F1, F2, F9, F3, F4b steps 2–3, F6, the fix round (8 review findings), F7, F8, two small fixes. T2 after each merge: 12 of 12 ALL PASS. F10 merged (`4918217`, merge `e3442ec`; version 0.7.0); T2 after it 12 of 12 (heartbeat 179). Counts: run.sh 1178, fresh-gate-test 758, paid-guard-test 852, file-guard-test 107. Term scan with the private list: 0 private hits (187 generic, the usual fixtures). Review fixes merged (`a4edf03`, `9dca43b`, merge `2e4c385`); T2 after them 12 of 12 (run.sh 1278, paid-guard-test 1025). T3 so far: both `claude plugin validate --strict` pass; `term-scan.py --history` 0 private hits (400 generic).
Next: F4b step 1 (only with D-YK13) | F5 after E1/E2 | F10 | review (§8.8) | T3 — the brief: docs/notes/paid-guard-next-brief.md
NEEDS YOU (2): decided 2026-11-14: D-YK13 yes (folder lookup, F4b step 1 building), D-YK14 yes (pay flags of the batch entry script, plan §8.9) · E1/E2 phone prompts (one word from the phone while idle, one while Claude works; needed by F5) · the F0 and F3 scratch leftovers: the delete was refused by the permission system, the maintainer runs it
## Last 3 cards
- 2026-11-14 F7, F8 and two small fixes merged: PowerShell download-run and home-delete refused, owner-file covers the adapter, trust and launcher files, a quote in a comment no longer hides a publish; T2 green each time
- 2026-11-14 F4b steps 2–3, F6 and the fix round merged: free runs and `only` flags, the paid check on PowerShell, 8 review findings fixed toward paid; method D 0 flips each time; T2 green
- 2026-11-13 F3 merged: paid gate, owner-file, Monitor; 328 reference cases all present; T2 green
## Unknowns
- fresh review (§8.8, Opus xhigh, 2026-11-14) over origin/main..F10: frozen names, old RULES, hooks.json, exec-without-main clean; judge: adapter go sequence PASS, owner repo and method M not measurable; 3 majors (unknown runners pdm/hatch/conda/rye/pixi/op/dotenv/doppler hide a paid script; deny reasons point at the unbuilt typed go; a copy into a folder writes a protected file) and minors 5–8 → fix round committed on pg7-a (`a4edf03`, paid 976, run 1250, method D 0 flips); Opus re-check of that diff: all five closed for the shapes named, no regression; follow-ups building (runner options before `run`, the unreadable-script reason, a CHANGELOG count); a settings file staged elsewhere and copied into `.claude/` → SECURITY.md limit (0.6.1 the same; 0.6.2); minor 4 (a mention before the run shifts the count rule's segment) → SECURITY.md
- every merge drew an automated security review; findings are classed in docs/notes/paid-guard-next-brief.md ("For SECURITY.md"): new code toward paid → fixed; a recorded class → SECURITY.md (no-spiral rule, plan §8.6)
- E1/E2 open (phone prompt records) → F5 waits for them. Seen 2026-11-14: an owner prompt typed while idle records `origin.kind=human`, `turnOrigin=human`, `promptSource=typed`, `entrypoint=cli` (phone or laptop not yet confirmed)
- F5 blocker if F5 does not ship: the paid deny reason (bash-guard.py, the paid block) tells the owner to type `paid go: …` in the session, which only F5 builds → then the reason must point to the adapter line
- new, low: the 0.6.1 docs quoted recall-test 210; the suite prints 203 with recall-test.sh unchanged since origin/main → find where 210 came from before the release text quotes it
- new, low: `ledger-test.sh:52` failed once (F1) and passed on a rerun; likely class: two same-instant renames on Windows both fail and the receipt is dropped (`ledger.py:264–267`) → ROADMAP 0.6.2 candidate, with the maintainer's ok
- new, low: method M's two base runs differ by 0.036 s on Bash, more than the 0.03 s pass margin → the "after" columns take 3+ runs
- open, pre-existing, documented: some ways of handing a command to another shell are not yet recognised → ROADMAP 0.6.2, built on a reported miss
- new, low: on Windows a very long project path pushes the smartuse state dir past 248 characters and heartbeat/recall silently write no state → ROADMAP 0.6.2
- not checked: an adversarial PowerShell tokenisation hunt → ROADMAP 0.6.2, on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- old worktrees: f1, f23, f3 (paid-f3, still F5's reference), lf-a…lf-e, sec-a…sec-j, sec-docs (merged) → remove with the maintainer's ok; pg7-a, pg7-b, pg7-ref are this batch's
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/paid-guard-next-brief.md (the next brief, and the SECURITY.md limits) · docs/notes/paid-guard-plan.md (§8: the 0.7.0 plan; §8.4 F4b; §8.10 results)
- docs/STATUS-history-2026-11.md (the old STATUS, unchanged) · docs/ROADMAP.md
- docs/notes/recall-design.md · docs/notes/recall-security-fix-plan.md · docs/notes/py-cache-fix-plan.md
