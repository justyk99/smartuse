# Brief: build and ship 0.5.1, the launcher remembers a name (2026-10-25, for the next session)

Read first: `docs/notes/py-cache-fix-plan.md` (approved; §3 is the contract, §5 the tests, §7 the release). Then run the phases below with the repo's dev-flow skill.

## Test tiers (dev-flow v1.1)
- **T1, builder, after every change:** the touched suite only (`bash plugins/smartuse/hooks/tests/run.sh`, `file-guard-test.sh`, or `heartbeat-test.sh`).
- **T2, before every commit:** those three suites one at a time on the laptop, each printing ALL PASS. `all.sh` takes 10+ minutes there.
- **T3, before the push of each batch:** CI `ci.yml` green (the full `all.sh` on 4 systems) plus phase 6's two interactive scenarios.
- **T4, before ship:** YK reads the scenario outputs and the release notes and says go.

## Phases
- **3 Contract:** the plan's §3 is the contract (py.sh rules, the two regex additions, the reason texts). A name the builder cannot find → stop and ask; never invent one.
- **4 Build:** one `flow-builder`, in a worktree made by hand: `git -C C:/Users/zero_/smartuse worktree add -b fix/py-cache .claude/worktrees/py-cache claude/inspiring-galileo-8icw6s`. Six files only: `plugins/smartuse/hooks/py.sh`, `hooks/file-guard.py`, `hooks/bash-guard.py`, `hooks/tests/heartbeat-test.sh`, `hooks/tests/file-guard-test.sh`, `hooks/tests/run.sh`. It runs `run.sh`, `file-guard-test.sh` and `heartbeat-test.sh` one at a time and quotes each last line. One commit, no push.
- **5 Integrate:** fast-forward the local dev branch to the builder's commit, on top of the local docs commit (plan, brief, STATUS). Push all of it together. Gate: `ci.yml`, the four test jobs and validate green; the Linux job's `all.sh` line is `run 134 · ledger 46 · until-done 40 · file-guard 14 · heartbeat 110 · ab 36 · watch 63 · wait 187`.
- **6 Use it:** `flow-tester` runs the plan's two interactive scenarios. For step 5 of the Windows one, load the dev checkout with `claude --plugin-dir`, not the installed 0.5.0. It saves the outputs.
- **7 Review:** a fresh `flow-reviewer` (Opus, xhigh) on the fix diff against the plan, plus a security review of the whole 0.5.1 diff (lesson 2026-10-25). Majors go back to a builder, then phases 5 and 6 again.
- **8 Ship:** the release commit (plan §7: manifests 0.5.1, `docs/releases/0.5.1.md`, CHANGELOG, STATUS, README lines 36/63/76, ROADMAP). CI green, then **YK's go**, then fast-forward main, tag `v0.5.1` with its release page, `claude plugin marketplace update smartuse`, `claude plugin update smartuse@smartuse`, and verify the version.
- **9 Handoff:** rebase `paid-guard`, then `paid-f3` (plan §7, one suite at a time after each), rewrite STATUS, then the `/clear` line.

## Restate in every agent brief (subagents don't carry these rules)
- Only the files named. Edit tool for changes, no whole-file pastes. The paid branches stay untouched until phase 9.
- One command per shell call; `git -C <dir> …`; no `cd`.
- Laptop suites run one at a time (each Python start takes 0.4–3.6 s, and low memory kills parallel runs).
- Public repo: comments, commit messages and release notes describe the class of problem, never the steps to exploit it.
- Done means the suite's own last line, quoted. Commits end with the session's Co-Authored-By and Claude-Session lines.

## Keep-running line (YK pastes it after `/dev-flow continue`; it ends at his go)
`/goal smartuse 0.5.1 per docs/notes/py-cache-fix-brief.md, phases 3 to 8 up to but not including main: ci.yml green on the pushed dev branch with the Linux all.sh line run 134 · ledger 46 · until-done 40 · file-guard 14 · heartbeat 110 · ab 36 · watch 63 · wait 187, both interactive scenarios pass with outputs saved, the fresh review and the security review leave no open major, the 0.5.1 release commit is on the dev branch with CI green, nothing outside the six files and the plan §7 release files changed, and the last reply asks YK for the go to main; or stop sooner at a decision with two reasonable answers, or after 25 turns`
