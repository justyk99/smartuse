# STATUS — smartuse (2026-10-25, Smartuse-Worker · phase: 0.5.1 release commit on the dev branch, waiting for YK's go to main · resume with `/dev-flow continue`)

Mandate (YK): drive smartuse to 1.0, ask only for real decisions; one session, Smartuse-Worker on YK's laptop. Plan `docs/ROADMAP.md`. Dev branch `claude/inspiring-galileo-8icw6s`. Flow: the repo's dev-flow skill (`.claude/skills/dev-flow/`); permissions in `.claude/settings.json`.

## Done
- 0.5.0 released 2026-10-25 (YK: "go, release 0.5.0"): main 8574524, tag and page `v0.5.0`, laptop updated 0.4.0 → 0.5.0. Evals 10 of 10 in CI (run 40154595342, `evals/results/2026-10-25-0.5.0-ci/`). Tests `run 126 · ledger 46 · until-done 40 · file-guard 10 · heartbeat 105 · ab 36 · watch 63 · wait 187`.
- CI evals run on the secret `CLAUDE_CODE_OAUTH_TOKEN` (re-issued by YK 2026-10-25; the "Token works?" step checks it before the suite).

## Next, in order
1. **0.5.1, the launcher fix** — built, both scenarios run (outputs with YK), fresh review + security review done, their fixes and YK's three answers in plan §8 (`docs/notes/py-cache-fix-plan.md`). Gate: CI green on the release commit, then **YK's go**, then plan §7: ff `main`, tag `v0.5.1` + release page, `claude plugin marketplace update smartuse`, `claude plugin update smartuse@smartuse`, verify the version. The Linux scenario ran as CI's launcher cases + a laptop simulation (no Linux box here).
2. Paid-call guard as 0.6.0 (plan `docs/notes/paid-guard-plan.md`, YK's yes 2026-10-24; local branches `paid-guard`, `paid-f3`; resume state in that plan's §7). Rebase both onto 0.5.1 first.
3. Parked: `docs/notes/input-2026-10-24-claude-system.md` is on no machine searched (YK 2026-10-24); if it turns up, pick its 1.0 candidates and update ROADMAP.

## Locked · must not change
- One Python start per hook event; a hook never blocks (no interpreter → exit 0); suite counts only grow.
- No paid-API call without the owner's go per script, a cap and one test output first; Claude runs on the Max plan are not paid calls.
- Before any fast-forward of main: a security review of the release diff, then YK's go.

## Needs YK
- Plugin icon before the 1.0 listing (ICON_MISSING; square PNG 512–2048 px at `.claude-plugin/icon.png`) · release page + tag v0.4.0 · README's new lead line (he words it) · Typefully for LinkedIn.

## Traps
- `send_later` check-ins are refused (ACCESS_DENIED): wake yourself with a background task (`hooks/watch.py`, a bash loop). `SendMessage` by name does not reach a cloud session.
- Evals run only in CI (the laptop has no Windows sandbox for Bash and no `bash` for `--scaffold`); on Linux: `TMPDIR` outside `/tmp`, `--scaffold`, `--allow-tools Bash Skill Read Grep Glob Agent Write`.
- The laptop's Python starts in 0.4–3.6 s: run suites one at a time (10+ min in all); CI's Windows runner is the routine Windows check.
- This session starts in `C:\dev` (not git): `isolation: "worktree"` fails; make worktrees by hand (`git -C ~/smartuse worktree add -b <branch> .claude/worktrees/<name> <base>`).
- Test scripts that name a paid host, key or SDK trip the paid guard: keep them in `hooks/tests/paid-cases.txt`, build fixtures with printf.
- bash-guard's human-only rule stops at `;` (ROADMAP); skills write `~/.claude` state only through `ledger.py --put/--unit/--run`.
