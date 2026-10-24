# STATUS — smartuse (updated 2026-10-24 by Smartuse-Brain, handing off to ONE new session)

Mandate (YK): drive smartuse to 1.0, ask only for real decisions. One session from now on: the cloud brain + laptop worker pair is closed (case study 8: two peer sessions drop files and signals). Plan: `docs/ROADMAP.md`. Dev branch: `claude/inspiring-galileo-8icw6s` (main merged in at b0bd7d5). Run work with the repo's dev-flow skill (`.claude/skills/dev-flow/`); repo permissions in `.claude/settings.json`.

## State
- `main` = 0.4.0, released 2026-10-22; `claude plugin install smartuse@smartuse` serves it. Evals 8 of 8 (+0.88 over no plugin).
- Dev branch = 0.5 work, unreleased (manifests still say 0.4.0): `hooks/watch.py`; the wait gate + `STOPPED` status line; the launcher remembers its Python (one start per event); one-session steering (make-prompt `Runs on:`, run-plan pre-flight `needs-machine` + no-model `command` tier); evals 10 of 10. Tests: `run 126 · ledger 46 · until-done 40 · file-guard 10 · heartbeat 105 · ab 36 · watch 63 · wait 187`.

## Next, in order
0. Check CI on the branch head (the merge of main was pushed with this file).
1. YK's `docs/notes/input-2026-10-24-claude-system.md` is not pushed yet. When it lands: pick its 1.0 candidates, answer its 6 open questions with a reason each, update ROADMAP.
2. Move the 8 older eval cases' `max_turns` / `timeout_seconds` / `allowed_tools` under `execution:` (Claude Code 2.1.308 ignores them at the top level), re-run the suite.
3. Release 0.5.0: version bump, `docs/releases/0.5.0.md`, merge to main, check the marketplace serves it.
4. Paid-call guard (relay-design rule 4): low priority — YK: test runs on his Max plan need no asking; keep a cost cap on each run.

## Needs YK
- Release pages + tags for v0.3.0 / v0.4.0 (the `gh release create` paste from 2026-10-22).
- README's new lead line (one session that delegates): he words it.
- LinkedIn automation: connect Typefully (typefully.com + its claude.ai connector); then posts are scheduled with the first comment, no manual step.

## Traps learned the hard way
- Scheduled check-ins (`send_later`) into a session were refused at delivery (ACCESS_DENIED, 2 of 2): wake yourself with an in-session background task (`hooks/watch.py`, a bash loop) instead.
- `SendMessage` to a session by name does not reach a cloud session; read the other session's transcript with `list_events`.
- Evals on Linux: `TMPDIR` outside `/tmp`, `--scaffold`, `--allow-tools Bash Skill Read Grep Glob Agent Write`.
- The laptop's Python starts slowly (0.4–3.6 s); a full suite there takes 10+ minutes and low memory can kill it. CI's Windows runner is the routine Windows check; ask YK for a laptop session only for Windows-only checks or his logins (gh, LinkedIn).
- Skills write `~/.claude` state only through `ledger.py --put/--unit/--run` (Write/Edit there prompts every time).
