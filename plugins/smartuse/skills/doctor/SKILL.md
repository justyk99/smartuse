---
name: doctor
description: "Prove that smartuse's hooks are live: one deterministic report (0 model tokens to compute) of the Python it runs on, the hooks registered, the heartbeat, and a live try of the bash-guard and file-guard, each PASS or FAIL with the fix, plus the guard level and the rules switched off. Use when the user asks 'is smartuse working', 'are the hooks on', 'doctor', 'check my setup', 'is the guard live', 'why is nothing happening'."
allowed-tools: Bash(bash *), Bash(echo *), Bash(: smartuse-doctor-canary), Write(~/.claude/smartuse/doctor-canary)
---

# doctor — are the hooks live? (the renderer is deterministic; two tries prove the guards)

Renderer output (empty = the launcher found no Python 3):

!`bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/heartbeat.py" --doctor || true`

Now try both canaries, one tool call each, in this order. Each is harmless: a canary does nothing when the guard is down, and a guard that is live denies it with a reason that starts `doctor canary`.
1. Bash, exactly this command and nothing else: `: smartuse-doctor-canary`
2. Write, file `~/.claude/smartuse/doctor-canary` (give the absolute path of your home folder), content `canary`.

A denial is the PASS you want: do not retry, work around it or ask the user to approve it. If a call runs instead of being denied, that guard is not live (a Write that ran left a tiny file, `~/.claude/smartuse/doctor-canary`; say so and that it can be deleted).

Then print these lines, nothing before them (five checks, then the level):
- `Python`: PASS if the renderer printed a `python:` line without FAIL; else FAIL. Empty output: FAIL, fix "install Python 3.9 or newer (python3, python or py -3 on PATH) and restart Claude Code".
- `Hooks registered`: PASS if the `hooks registered:` line lists events; else FAIL with its fix.
- `Heartbeat live`: PASS if the `heartbeat:` line says `live`; else FAIL with the fix on that line (no event: restart Claude Code).
- `Bash-guard live`: PASS if try 1 was denied with `doctor canary`; else FAIL, fix "restart Claude Code; if it persists, check that the smartuse plugin is enabled in /plugin and that Python runs".
- `File-guard live`: PASS if try 2 was denied with `doctor canary`; else FAIL, same fix.
- `Level`: copy the renderer's `level:` line (level, rules off, any unknown name). If a canary's reason named a level, it must equal this one; if it differs, say so.

Format: `PASS Python — 3.12.1` / `FAIL Heartbeat live — no event: the hooks are not firing, restart Claude Code`. One line each, the detail copied from the renderer or the denial, never invented. End with `All five PASS` or `N of 5 FAIL`, and add the `state folder:` line only if it says FAIL (the heartbeat cannot save its state until it is fixed). Never name a file, tool or setting these lines do not show; never edit settings. A level or a rule is switched by the owner in `/plugin configure`, not here.
