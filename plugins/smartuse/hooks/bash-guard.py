#!/usr/bin/env python3
# bash-guard.py — PreToolUse guard for Bash (smartuse). Deterministic: runs even in bypassPermissions.
# Why: bypass mode skips every "ask"; only deny rules and hooks still fire. This file is the small, readable list of
# things Claude must never run on this machine, with the reason printed back to Claude so it picks a safe alternative.
# Heredoc bodies (cat > file <<EOF …, python3 - <<EOF …) are DATA and are ignored; a heredoc fed to bash/sh is still checked.
# Test: bash ~/.claude/hooks/tests/run.sh   Rollback: remove the PreToolUse entry in ~/.claude/settings.json
import json, re, sys

RULES = [
    (r"(curl|wget)\b[^|]*\|\s*(sudo\s+)?(bash|sh|zsh|dash|python3?|node|perl)\b",
     "pipe-to-shell (download then execute) — save the file, read it, then run it on purpose"),
    (r"(^|[;&|\n]\s*|\$\(\s*)sudo\s",
     "sudo — run it yourself with `! sudo …`"),
    (r"\brm\s+(-[A-Za-z]*r[A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*r|-r\s+-f|-f\s+-r)\s+(/|~|\$HOME|\*|\.)(\s|$|/\*)",
     "rm -rf of / ~ . or * — delete named paths only"),
    (r"\bchmod\s+(-R\s+)?(777|a\+rwx|o\+w)\b",
     "world-writable chmod"),
    (r"\b(cat|less|more|head|tail|sed|awk|grep|strings|base64|xxd|cp|scp|rsync|curl|python3?|node|tee|jq)\b[^;&|]*"
     r"(\.claude\.json|db-creds\.json|\.jira_env|/\.ssh/id_[a-z0-9]+(\s|$)|\.ssh/config|gh/hosts\.yml|\.git-credentials|\.netrc)",
     "credential file — its contents would land in the transcript on disk; use `claude mcp list` or env vars instead"),
    (r"(?=.*\b(sqlcmd|osql|tsql|sqlq|spapply|mssql)\b)(?=.*\b(DROP\s+(TABLE|DATABASE|PROC|PROCEDURE|LOGIN|USER)|TRUNCATE\s+TABLE|DELETE\s+FROM)\b)",
     "destructive SQL through the shell — SQL in chat, a human runs it"),
    (r"\bgit\s+push\b[^;&|]*(\s--force\b|\s-f\b|--force-with-lease)",
     "force push"),
    (r"\bsvn\s+(revert|resolve\s+--accept\s+theirs-full)\b",
     "svn revert / theirs-full — colleagues' uncommitted work would be lost"),
]

# <<EOF … EOF  /  <<'EOF' … EOF  /  <<-EOF … EOF   (body = group 3)
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.S)
SHELL_RECEIVER = re.compile(r"(?:^|[|;&(]\s*|\bsudo\s+)(bash|sh|zsh|dash|ksh)\b(?![\w./-])")  # shell as a COMMAND word, not x.sh


def strip_heredocs(cmd):
    """Replace heredoc bodies with a marker unless a shell consumes the body (bash <<EOF … is still code)."""
    def repl(m):
        line_start = cmd.rfind("\n", 0, m.start()) + 1
        head = cmd[line_start:m.start()]
        if SHELL_RECEIVER.search(head):
            return m.group(0)
        before = m.group(0)[:m.start(3) - m.start()]
        after = m.group(0)[m.end(3) - m.start():]
        return before + "<heredoc body stripped>" + after
    return HEREDOC.sub(repl, cmd)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if data.get("tool_name") != "Bash":
        return
    cmd = (data.get("tool_input") or {}).get("command") or ""
    text = strip_heredocs(cmd)
    for pat, why in RULES:
        if re.search(pat, text, re.I | re.S):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"bash-guard: {why}"}}))
            return


main()
