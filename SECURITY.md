# Security

smartuse ships five hooks: `bash-guard` and `file-guard` (PreToolUse), `ledger` (Stop / SubagentStop), `until-done` (Stop) and `heartbeat` (every event; it records tool names, agent types and timestamps — never tool arguments, file contents or prompts). All are small Python files you can read in a few minutes. None makes network calls. `ledger` reads your session and agent transcripts to sum token usage and writes to `~/.claude/smartuse/`; it never reads file contents other than the transcripts. `until-done` runs the repo's `check:` command only from the human-written adapter, only in fixed shapes or as a script pinned by hash in a root-owned file, with `shell=False`, and prints a redacted tail of its output.

Report a vulnerability by opening a GitHub issue titled `security:` with no exploit details, or email the maintainer address on the GitHub profile. You will get an answer within 7 days.

Known limits: skills and output styles are instructions, not enforcement; the hook rules are regexes and can be bypassed by an actor who edits the hook file. Pair the kit with a deny list in `~/.claude/settings.json` and read-only database logins (see `docs/research/security-profiles.md`).
