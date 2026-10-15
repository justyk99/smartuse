# Security profiles — pick one, paste it (2026-10-15)

Full reasoning: `guides/security-and-permissions-2026.md`. Deny rules and hooks fire in every mode, `ask` rules only in `default` / `auto`.

## Deny block (every profile)

```json
"deny": [
  "Bash(rm -rf *)", "Bash(rm -rf /*)", "Bash(sudo *)",
  "Bash(git push --force*)", "Bash(git push -f*)", "Bash(git reset --hard*)", "Bash(git checkout -- .)",
  "Bash(git clean -f*)", "Bash(git branch -D*)",
  "Bash(svn revert*)", "Bash(svn resolve --accept theirs-full*)",
  "Read(~/.claude.json)", "Read(~/.ssh/**)", "Read(~/.claude/tools/db-creds.json)", "Read(~/.claude/tools/.jira_env)",
  "mcp__claude_ai_Gmail__send_message", "mcp__claude_ai_Gmail__forward", "mcp__claude_ai_Gmail__reply",
  "mcp__claude_ai_Gmail__trash_thread", "mcp__claude_ai_Gmail__trash_message",
  "mcp__claude_ai_Google_Calendar__delete_event", "mcp__claude_ai_Canva__publish-brand-template"
]
```

## Guard hook (every profile)

```json
"hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
  { "type": "command", "command": "python3 \"$HOME/.claude/hooks/bash-guard.py\"", "timeout": 10 } ] } ] }
```
Script: `library/hooks/global/bash-guard.py` (pipe-to-shell · sudo · rm -rf of / ~ . * · chmod 777 · credential-file reads · destructive SQL via shell · force push · svn revert; heredoc bodies are data). Test: `bash ~/.claude/hooks/tests/run.sh` → `ALL PASS` (32 cases).

## Profiles

| | Locked | Balanced | Fast (the author) |
|---|---|---|---|
| `defaultMode` | `default` | `auto` | `bypassPermissions` |
| `allow` | project build/test commands only, e.g. `Bash(pnpm test*)` | + `Bash(git status*)`, `Bash(git diff*)`, `Bash(git log*)`, project MCP read tools, `WebFetch(domain:docs.*)` | `Bash(*)`, `Read`, `Edit`, `Write`, project MCP read tools |
| `skipDangerousModePermissionPrompt` | — | — | `true` |
| DB logins | read-only only | read-only; apply tool separate | read-only recommended; UAT writer only via `sp-apply` after a per-change yes |
| Connectors | none | only what the repo uses | pruned per repo (`/mcp`) |
| Extra | — | — | all six layers present and tested before switching |

## File permissions (every profile)

```bash
chmod 600 ~/.claude.json; chmod 700 ~/.claude ~/.claude/projects
```
Store DB passwords as env vars and write `"SQLSERVER_PASSWORD": "${<db>_PW}"` in the MCP config.

## Read-only SQL login (DBA runs it)

```sql
CREATE LOGIN claude_ro WITH PASSWORD = '<strong>';
USE <db>; CREATE USER claude_ro FOR LOGIN claude_ro;
ALTER ROLE db_datareader ADD MEMBER claude_ro; GRANT VIEW DEFINITION TO claude_ro;
```

## Check it worked

`/permissions` lists the denies · `bash ~/.claude/hooks/tests/run.sh` → ALL PASS · `SELECT 1; SELECT 2` through each MCP → refused · `/context` shows only what you expect.
