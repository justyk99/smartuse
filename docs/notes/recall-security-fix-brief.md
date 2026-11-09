# Brief: build the 0.6.0 security-review fix batch (2026-11-09, for the next session)

Read first: `docs/notes/recall-security-fix-plan.md` (approved 2026-11-09, option A in §7; §4 is the contract per feature, §6 the must-not-change list). Then run the phases below with the dev-flow skill. The 0.6.0 contract stays `docs/notes/recall-design.md`.

## Test tiers
- **T1, builder, after every change:** the feature's own suites from plan §4, one at a time.
- **T2, after every merge and before every commit:** every suite of `all.sh` plus `scripts/term-scan-test.sh`, run one at a time on the laptop (~30 min). Floor: `run 152 · ledger 46 · until-done 40 · file-guard 26 · heartbeat 121 · ab 36 · watch 63 · wait 187 · fresh 309 · recall 190 · term-scan 6`; counts only grow.
- **T3, before a push:** T2 plus `claude plugin validate --strict plugins/smartuse` (ICON_MISSING is the known warning) plus phase 6 (Parts A and B of the tester brief, and the plan's interactive scenarios as Part C).
- **T4, before ship:** the maintainer reads the scenario outputs and the release notes and says go.

## Phases
- **4 Build:** two `flow-builder`s, **one after the other** (both touch `bash-guard.py` and `fresh-gate-test.sh`, and parallel suites run the laptop out of memory). Each gets a worktree made by hand from the dev branch head (this session starts outside the repo, so `isolation: "worktree"` fails):
  - Builder A: F2 → F1 → F3. `git -C ~/smartuse worktree add -b fix/sec-a .claude/worktrees/sec-a claude/inspiring-galileo-8icw6s`
  - Builder B (starts from A's merged result): F5 → F4 → F6. `git -C ~/smartuse worktree add -b fix/sec-b .claude/worktrees/sec-b claude/inspiring-galileo-8icw6s`
  - Cases first and red on the unchanged code, then green. Files: only those plan §4 names for its features. F4 pins the failed-Read shape from a real transcript first: shapes and field names only, never content.
- **5 Integrate:** merge A, T2; then B, T2. Commit each feature group with its suites' last lines in the message.
- **6 Use it:** needs the hand-written scratch adapter (STATUS). The tester brief and the scratch repo are in the session scratchpad named in STATUS; add the plan's F1 scenario as Part C and record the Claude Code version (the Monitor note depends on it).
- **7 Review:** a fresh `flow-reviewer` on the batch diff against the plan, plus a security re-check of the batch. Majors go back to a builder, then 5 and 6 again.
- **F7 docs** after T2 is green (plan §4 F7 lists every line).
- **Fallback (plan §7):** F1 not green by Wed 11 Nov evening → the demo repo sets `CLAUDE_CODE_USE_POWERSHELL_TOOL=0` and the docs say so; F3–F6 drop to 0.6.1 one by one if T2 is not green.

## Restate in every agent brief (subagents don't carry these rules)
- Only the files named in the plan for that feature. Edit tool, no whole-file pastes. `RULES`, `HEREDOC`, `strip_heredocs`, `opener_line`, `STATE_CALL` stay byte-identical.
- Python only through `bash plugins/smartuse/hooks/py.sh`; one command per shell call; `git -C <dir> …`, no `cd`; suites one at a time.
- JSON holding Windows paths goes in a file written with the Write tool, never through printf/echo; prove an event parsed (a denied twin) before trusting an empty allow.
- Never write `.claude/*.local.md` or `.smartuse-terms.local`; never touch `.agents/` or `.codex/`; stage by file name.
- Public repo: comments and commit messages describe the class of problem, never the steps to exploit it. No personal paths or names in any file.
- Done means the suite's own last line, quoted. Builders never commit; the orchestrator commits with the session's Co-Authored-By and Claude-Session lines.

## Keep-running line (the maintainer pastes it after `/dev-flow continue`)
`/goal smartuse 0.6.0 security fixes per docs/notes/recall-security-fix-brief.md, phases 4 to 7: F1–F6 merged on the dev branch (F3–F6 may drop to 0.6.1 per plan §7), T2 green one suite at a time with every count at or above run 152 · ledger 46 · until-done 40 · file-guard 26 · heartbeat 121 · ab 36 · watch 63 · wait 187 · fresh 309 · recall 190 · term-scan 6, the fresh review and the security re-check leave no open major, F7 docs committed, nothing outside the plan's files changed, nothing pushed; or stop sooner at a decision with two reasonable answers, or after 25 turns`
