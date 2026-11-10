# Security profiles — pick one, paste it (2026-10-15)

These profiles are permission presets for your `settings.json`. They are not the plugin's guard level (light or Strict): that is set in `/plugin configure smartuse@smartuse` (see "Switches" in the README). Deny rules and hooks fire in every mode, `ask` rules only in `default` / `auto`.

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

The plugin registers it itself (`plugins/smartuse/hooks/hooks.json`), so there is nothing to paste:
```json
"hooks": { "PreToolUse": [ { "matcher": "Bash|PowerShell", "hooks": [
  { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/py.sh\" --guard \"${CLAUDE_PLUGIN_ROOT}/hooks/bash-guard.py\"", "timeout": 10 } ] } ] }
```
`py.sh` is the launcher: it runs the hook with `python3`, else `python`, else `py -3` (a stock Windows install has only the Store stub as `python3`).

Script: `plugins/smartuse/hooks/bash-guard.py` (pipe-to-shell · sudo · rm -rf of / ~ . * · chmod 777 · credential-file reads · destructive SQL via shell · force push · svn revert · the human-only files · the switches; heredoc bodies are data).

Test: `bash plugins/smartuse/hooks/tests/run.sh` → `ALL PASS` (539 cases).

In the light level the guard does not deny a shell read of `~/.claude.json` (the `claude-json` rule is off). The `Read(~/.claude.json)` deny above covers the Read tool, and Strict guards denies the shell read.

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

`/permissions` lists the denies · `bash plugins/smartuse/hooks/tests/run.sh` → ALL PASS · `/smartuse:doctor` → five PASS lines · `SELECT 1; SELECT 2` through each MCP → refused · `/context` shows only what you expect.
