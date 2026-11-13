STATUS: smartuse · updated 2026-11-13
FINISH LINE: smartuse 1.0, driven by the plan in docs/ROADMAP.md (the old STATUS: "drive smartuse to 1.0")
Done when (assumed from the old Next list): 1 0.6.1 released (done 2026-11-11) 2 0.7.0 paid-call guard released 3 the 1.0 items on docs/ROADMAP.md closed
Now: 0.7.0 build on the local dev branch `paid-0.7.0` (not pushed): F0 done (baseline, reference counts, method M before, E3–E5), F1 merged (json.tool flags only), F2 merged (settings file read-only from the shell, rule `settings-file`); T2 after F2: 11 of 11 ALL PASS (run.sh 633 PASS); F9 merged 2026-11-13 (`788e24b`, file-guard-test 107 PASS); T2 after F9 (`a29af09`): 11 of 11 ALL PASS, counts at or above the floor
Next: F3, the port of the paid block, building in worktree pg7-a (docs/notes/paid-guard-f3-brief.md, plan §8.4 F3) | then F4–F8, T2, F10, review, T3
NEEDS YOU (2): E1/E2 phone prompts (one word from the phone idle, one while Claude works; needed by F5) · the delete of the F0 scratch leftovers was approved but the permission system refused it: the maintainer runs it (session report) · decided 2026-11-13: D-YK12 yes (Monitor in F3), D-YK11 yes (CLAUDE.md test lines)
## Last 3 cards
- 2026-11-13 F2 merged: settings file read-only from the shell; method D 120 flips, all new deny cases; T2 green
- 2026-11-13 F1 merged: json.tool flags only; method D 32 flips, all new deny cases; T2 green (one ledger flake, see Unknowns)
- 2026-11-13 0.7.0 plan v2 approved whole ("2"): F0–F10, one release
## Unknowns
- E5 showed a Monitor command is not seen by bash-guard (its matcher is Bash|PowerShell) → D-YK12 yes: fixed in F3
- new, low: `ledger-test.sh:52` failed once and passed on a rerun; likely class: two same-instant renames on Windows both fail and the receipt is dropped (`ledger.py:264–267`); not touched by 0.7.0 → ROADMAP 0.6.2 candidate, with the maintainer's ok
- new, low: method M's two base runs differ by 0.036 s on Bash, more than the 0.03 s pass margin → the "after" columns take 3+ runs
- known gaps from F9 (for SECURITY.md in F10): file-guard does not match the counter's own temp file `paid-runs.json.<pid>.tmp`, nor transcripts under a relocated config folder (CLAUDE_CONFIG_DIR)
- known over-denies from F2 (for SECURITY.md in F10): a `$(cat <<'EOF' …)` commit message that names a settings path; an input redirect from it; Copy-Item with named -Path/-Destination
- open, pre-existing, documented: some ways of handing a command to another shell are not yet recognised (review rounds 6–7) → ROADMAP 0.6.2, built on a reported miss
- later, asked of the maintainer: .smartuse-terms.local on this machine · day-45 check Thu 26 Nov · plugin icon before the 1.0 listing · release page + tag v0.4.0 · README's new lead line · Typefully for LinkedIn
- new, low: on Windows a very long project path pushes the smartuse state dir past 248 characters and heartbeat/recall silently write no state → ROADMAP 0.6.2
- not checked: an adversarial PowerShell tokenisation hunt → ROADMAP 0.6.2, on a reported miss
- old worktrees: f1, f23, lf-a…lf-e, sec-a…sec-j, sec-docs (merged) → remove with the maintainer's ok; pg7-a, pg7-b, pg7-ref are this batch's
- locked rules and traps (one Python start per hook, history rewrite 2026-11-06, run suites one at a time) → see the history file
## Job sheets (repo-relative: this repo is public)
- docs/notes/paid-guard-plan.md (§8: the 0.7.0 plan; §8.10: F0 and T2 results) · docs/notes/paid-guard-f3-brief.md (the next brief)
- docs/STATUS-history-2026-11.md (the old STATUS, unchanged) · docs/ROADMAP.md
- docs/notes/recall-design.md · docs/notes/recall-security-fix-plan.md · docs/notes/py-cache-fix-plan.md
