STATUS: smartuse · updated 2026-11-24
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released (done 2026-11-23) 3 0.7.1 hardening released 4 the 1.0 items on docs/ROADMAP.md closed
Now: 0.7.1 built and tested on the local branch `fix-0.7.1` (`07a363e` plus this handoff), not pushed. Merged: F1 long path keeps state (`433f026`), F2 paid refusal wording (`55ba537`), F3 term scan runs bare on Windows (`445314e`), F5 README uninstall + what it reads and writes (`410e420`), the review fix round D8 (`daf96ef`), the re-check follow-up (`07a363e`). F4 (ledger race) not built: E2 reproduced 4 drops in 1000 rounds, cause untraced (plan §10). T2 after the last change: 12 of 12 (run 1340 · file-guard 107 · ledger 46 · until-done 50 · watch 63 · heartbeat 206 · wait-gate 209 · recall 203 · fresh-gate 758 · paid 1369 · ab 36 · term-scan 7). T3: both validates pass, the bare publish scan 0 private hits (and a per-line re-check 0), interactive F1 and F5 PASS, fresh review + security review: nothing open but the minors below. Plan docs/notes/next-release-plan.md (§10 results, §12 contract, last section D8).
Next: the release (brief docs/notes/next-release-brief.md): CHANGELOG date, fast-forward main to `fix-0.7.1`, push on the maintainer's word.
NEEDS YOU (2): 1 the release word for 0.7.1 · 2 optional, 1 minute: the live F2 adapter check (write the test's adapter file; the guard refuses it to Claude) · leftovers you delete (the permission system refused Claude): `.claude/worktrees/pg7-scratch/`, the old worktrees below
## Last 3 cards
- 2026-11-24 0.7.1 T3: validates pass, bare scan 0 private hits, F1/F5 interactive PASS, F2 live check waits on the owner's file; security review nothing major
- 2026-11-24 review fix round (D8): an existing state folder is kept at any length when Windows long paths are on (M1, the E1 measurement assumed long paths off); re-check closed all six; fresh-gate's allowlist fixed
- 2026-11-23 0.7.1 plan approved: 5 features, 3 lanes; no change to command parsing
## Unknowns
- new, minor (security review 2026-11-24, pre-existing): `term-scan.py` keeps only the first pattern per line, so a private term on a line with a generic hit is not counted and shows unmasked in the context; the 0.7.1 push was checked by a per-line re-check instead (0). Fix: scan every pattern per line, private first → next release
- new, minor (F3): history decoded as UTF-8 with replace, so a private term committed in another encoding is missed silently (before: a crash) → with the item above
- new, low: the ledger race (two Stop hooks at once) drops a line about 4 in 1000 on Windows; no failed claim saw pending.json still there, so the planned retry would not help; needs a file-handle trace → ROADMAP next release
- new, low: a kept state folder of 219–232 characters denies every paid run (claim marker past 259) and doctor still says writable → ROADMAP
- new, low: skipped test cases print as PASS and count toward the floors; wait-gate-test's fit_key check would pass a top-level `import hashlib`/`winreg` → ROADMAP
- method M's Stop wait is two-valued (about 0.33 or 0.57 s): not gated → look before 1.0
- the 0.6.1 docs quoted recall-test 210; the suite prints 203 → find where 210 came from before a release text quotes it
- open, documented: some ways of handing a command to another shell are not recognised; an adversarial PowerShell tokenisation hunt not done → on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- old worktrees: f1, f23, f3, lf-a…lf-e, sec-a…sec-j, sec-docs, pg7-a, pg7-b, pg7-ref (all merged) → remove with the maintainer's ok
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time, Claude Code stops background suites on low memory: restart only on the maintainer's word) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/next-release-brief.md (the release steps) · docs/notes/next-release-plan.md (the 0.7.1 plan, results, contract)
- docs/notes/paid-guard-next-brief.md (the SECURITY.md classes) · docs/notes/paid-guard-plan.md (§8: 0.7.0)
- docs/STATUS-history-2026-11.md (the old STATUS) · docs/ROADMAP.md
