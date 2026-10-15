# Security

smartuse ships a PreToolUse hook (`bash-guard`) and a Stop hook (`ledger`). Both are small Python files you can read in two minutes. Neither makes network calls. `ledger` reads your session transcript to sum token usage and writes to `~/.claude/smartuse/`; it never reads file contents other than the transcript.

Report a vulnerability by opening a GitHub issue titled `security:` with no exploit details, or email the maintainer address on the GitHub profile. You will get an answer within 7 days.

Known limits: skills and output styles are instructions, not enforcement; the hook rules are regexes and can be bypassed by an actor who edits the hook file. Pair the kit with a deny list in `~/.claude/settings.json` and read-only database logins (see `docs/research/security-profiles.md`).
