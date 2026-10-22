#!/usr/bin/env python3
# bash-guard.py — PreToolUse guard for Bash (smartuse). Deterministic: runs even in bypassPermissions.
# Why: bypass mode skips every "ask"; only deny rules and hooks still fire. This file is the small, readable list of
# things Claude must never run on this machine, with the reason printed back to Claude so it picks a safe alternative.
# Heredoc bodies (cat > file <<EOF …, python3 - <<EOF …) are DATA and are ignored; a heredoc fed to bash/sh is still checked.
# stdin is read as bytes and decoded as UTF-8 here, not by Python's text layer: on Windows a piped stdin is decoded in the
# ANSI code page, where a non-ASCII byte makes json.load raise — and a guard that raises fails OPEN.
# Test: bash hooks/tests/run.sh   Rollback: remove the PreToolUse entry in ~/.claude/settings.json
import json, re, sys

RULES = [
    (r"(curl|wget)\b[^|]*\|\s*(sudo\s+)?(bash|sh|zsh|dash|python3?|node|perl)\b",
     "pipe-to-shell (download then execute) — save the file, read it, then run it on purpose"),
    (r"\b(bash|sh|zsh|dash|ksh|eval|source)\b[^;&|]*?(\$\(|<\()\s*(curl|wget)\b",
     "download-then-execute via $(curl …) or <(curl …) — save the file, read it, then run it on purpose"),
    (r"(?<![\w.-])sudo\s",
     "sudo — run it yourself with `! sudo …`"),
    (r"\brm\s+(-[A-Za-z]*r[A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*r|-r\s+-f|-f\s+-r)\s+(/|~|\$HOME|\*|\.)(\s|$|/\*)",
     "rm -rf of / ~ . or * — delete named paths only"),
    (r"\bchmod\s+(-R\s+)?(777|a\+rwx|o\+w)\b",
     "world-writable chmod"),
    # key and credential files by NAME (any directory, either slash): a reader/copier command word, then the file in the same segment
    (r"\b(cat|less|more|head|tail|sed|awk|grep|strings|base64|xxd|cp|scp|rsync|curl|python3?|node|tee|jq|find|type)\b[^;&|]*"
     r"(\.claude\.json|db-creds\.json|\.jira_env|\bid_(rsa|ed25519|ecdsa|dsa|\*)(?!\.pub)|\.ssh[\\/]id_[a-z0-9_]+(\s|[\"']|$)"
     r"|\.ssh[\\/]?(\*|\s|[\"']|$)|\.ssh[\\/]config|gh[\\/]hosts\.yml|\.git-credentials|\.netrc|recovery-codes|[\\/]secrets[\\/]"
     r"|\.claude[\\/]\.credentials\.json|\.aws[\\/]credentials|\.npmrc(?![\w.-])|\.pypirc(?![\w.-])|\.kube[\\/]config|\.docker[\\/]config\.json)",
     "credential file — its contents would land in the transcript on disk; use `claude mcp list` or env vars instead"),
    (r"(?=.*\b(sqlcmd|osql|tsql|sqlq|spapply|mssql)\b)(?=.*\b(DROP\s+(TABLE|DATABASE|PROC|PROCEDURE|LOGIN|USER)|TRUNCATE\s+TABLE|DELETE\s+FROM)\b)",
     "destructive SQL through the shell — SQL in chat, a human runs it"),
    # git [options] push … --force / -f (also bundled: -fu) / --force-with-lease / --mirror / +ref
    (r"\bgit\b(\s+-\S+(\s+[^-\s]\S*)?)*\s+push\b[^;&|]*(\s--force\b|\s-[a-z]*f[a-z]*\b|--force-with-lease|--mirror|\s[\"']?\+\S)",
     "force push"),
    (r"(>|\btee\b|\bsed\s+-i|\bcp\b|\bmv\b|\bpython3?\b|\bpy\.sh\b)[^;&|]*(smartuse\.local\.md|trusted-checks\.json)",
     "human-only file (it decides what the until-done gate may run) — ask the user to edit it"),
    (r"(^|[;&|]\s*)(unbuffer|expect|script)\s",
     "faking an interactive terminal (script / unbuffer / expect) is not allowed"),
    (r"until-done\.py\s+--trust",
     "pinning a check script is a human-only action — the user runs it in their own terminal"),
    (r"\bsvn\s+(revert|resolve\s+--accept\s+theirs-full)\b",
     "svn revert / theirs-full — colleagues' uncommitted work would be lost"),
]

# <<EOF … EOF  /  <<'EOF' … EOF  /  <<-EOF … EOF   (body = group 3)
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.S)
SHELL_RECEIVER = re.compile(r"(?:^|[|;&(]\s*|\bsudo\s+)(bash|sh|zsh|dash|ksh)\b(?![\w./-])")  # shell as a COMMAND word, not x.sh


def strip_heredocs(cmd):
    """Replace heredoc bodies with a marker unless a shell consumes the body (bash <<EOF … and cat <<EOF | bash are still code)."""
    def repl(m):
        line_start = cmd.rfind("\n", 0, m.start()) + 1
        line_end = cmd.find("\n", m.start())            # the whole opener line, so `cat <<EOF | bash` counts as a shell receiver
        head = cmd[line_start:line_end if line_end >= 0 else len(cmd)]
        if SHELL_RECEIVER.search(head):
            return m.group(0)
        before = m.group(0)[:m.start(3) - m.start()]
        after = m.group(0)[m.end(3) - m.start():]
        return before + "<heredoc body stripped>" + after
    return HEREDOC.sub(repl, cmd)


def main():
    try:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
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
