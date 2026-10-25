# STATUS — smartuse (2026-10-25, Smartuse-Worker · phase: 0.5.1 released; next 0.6.0, step 1 the paid-branch rebases · resume with `/dev-flow continue`)

Mandate (YK): drive smartuse to 1.0, ask only for real decisions; one session, Smartuse-Worker on YK's laptop. Plan `docs/ROADMAP.md`. Dev branch `claude/inspiring-galileo-8icw6s`. Flow: the repo's dev-flow skill (`.claude/skills/dev-flow/`); permissions in `.claude/settings.json`.
## Done
- 0.5.1 released 2026-10-25 (YK: "go, release 0.5.1"): main 5464ace, tag and page `v0.5.1`, laptop 0.5.0 → 0.5.1 (verified). Tests `run 138 · ledger 46 · until-done 40 · file-guard 26 · heartbeat 114 · ab 36 · watch 63 · wait 187`, CI run 40178450446 green. Review fixes and YK's answers: `docs/notes/py-cache-fix-plan.md` §8; the deferred items are on ROADMAP.
## Next, in order
1. **0.6.0, the paid-call guard** (plan `docs/notes/paid-guard-plan.md`, YK's yes 2026-10-24). Step 1: rebase `paid-guard`, then `paid-f3`, onto `main` per `docs/notes/paid-guard-rebase-brief.md`; then the plan's §7 resume state.
2. Parked: `docs/notes/input-2026-10-24-claude-system.md` is on no machine searched (YK 2026-10-24); if it turns up, pick its 1.0 candidates and update ROADMAP.
## Locked · must not change
- One Python start per hook event; a hook never blocks (no interpreter → exit 0); suite counts only grow.
- No paid-API call without the owner's go per script, a cap and one test output first; Claude runs on the Max plan are not paid calls.
- Before any fast-forward of main: a security review of the release diff, then YK's go.
- A path guard matches every reading of a path (as written, as Windows reads it, resolved) and fails closed when it cannot resolve one.
## Needs YK
- Plugin icon before the 1.0 listing (ICON_MISSING; square PNG 512–2048 px at `.claude-plugin/icon.png`) · release page + tag v0.4.0 · README's new lead line (YK words it) · Typefully for LinkedIn.
## Traps
- `send_later` check-ins are refused (ACCESS_DENIED): wake yourself with a background task (`hooks/watch.py`, a bash loop). `SendMessage` by name does not reach a cloud session.
- Linux-only checks run in CI: evals (no Windows sandbox for Bash, no `bash` for `--scaffold`; on Linux `TMPDIR` outside `/tmp`, `--scaffold`, `--allow-tools Bash Skill Read Grep Glob Agent Write`; secret `CLAUDE_CODE_OAUTH_TOKEN`, checked by "Token works?") and any Linux scenario (`Agent` with `isolation: "remote"` ran on this laptop).
- The laptop's Python starts in 0.4–3.6 s: run suites one at a time (10+ min in all); CI's Windows runner is the routine Windows check.
- This session starts in `C:\dev` (not git): `isolation: "worktree"` fails; make worktrees by hand (`git -C ~/smartuse worktree add -b <branch> .claude/worktrees/<name> <base>`).
- Test fixtures: no paid host, key or SDK by name (`hooks/tests/paid-cases.txt`, printf); JSON with Windows paths goes in a file (the Bash tool can collapse `\\`), and an empty guard answer counts only once the input is proven to parse.
- bash-guard's human-only rule stops at `;` (ROADMAP); skills write `~/.claude` state only through `ledger.py --put/--unit/--run`.
