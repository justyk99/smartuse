#!/usr/bin/env python3
"""file-guard.py — PreToolUse guard for Write / Edit / MultiEdit: two files are human-only.
`.claude/smartuse.local.md` (the adapter: it names the check command the until-done gate will run) and
`~/.claude/smartuse/trusted-checks.json` (the human's hash pins). The model may read them, never write them.
"""
import json, re, sys
HUMAN_ONLY = re.compile(r"(smartuse\.local\.md|smartuse/trusted-checks\.json)$")

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if data.get("tool_name") not in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        return
    ti = data.get("tool_input") or {}
    path = (ti.get("file_path") or ti.get("notebook_path") or "").replace("\\", "/")
    if HUMAN_ONLY.search(path):
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
              "permissionDecisionReason": "file-guard: this file is human-only (it decides what the until-done gate may execute). Ask the user to edit it."}}))

main()
