---
name: reply-style
description: Pick how Claude writes its replies from a catalogue of 7 researched styles — lcd (common base, relay-to-a-senior) · bluf (decision first) · engineer (diff first) · teacher (why shown) · minimal (one line + code) · plain (non-technical) · memo (narrative decisions) — each shown with pros and cons, then installed as a Claude Code output style and switched on (applies from the next message). Use when a user asks which reply styles exist or who each is for (this skill holds the catalogue — invoke it rather than searching for files), asks how Claude should write, wants replies shorter / longer / simpler / more technical, says "reply style", "output style", "too long", "too technical", "explain simpler", or during a new setup. Changeable any time.
when_to_use: /reply-style (catalogue + pick) · /reply-style <name> (switch) · /reply-style show · /reply-style off (back to Default) · /reply-style try <name> (this conversation only, no files) · add --project (this repo only) · add --claude-md (write the block into CLAUDE.md instead, for setups where output styles are disabled)
argument-hint: "[show|off|try] [<style>] [--project] [--claude-md]"
allowed-tools: Read, Write, Edit, AskUserQuestion, Bash(ls *), Bash(mkdir *), Bash(cp *), Bash(cat *), Bash(grep *), Bash(python3 *)
---

# reply-style — a switchable response system (v1.0, 2026-10-15)

Built on Claude Code **output styles** (official: `~/.claude/output-styles/<name>.md`, switched with `/output-style <name>` or `outputStyle` in settings; applies from the next message; a newly created style file needs one session restart). Style files + catalogue live beside this file — read them by these absolute paths, no search needed: `${CLAUDE_PLUGIN_ROOT}/skills/reply-style/catalogue.md` and `${CLAUDE_PLUGIN_ROOT}/skills/reply-style/styles/<name>.md` (below, `catalogue.md` and `styles/<name>.md` mean these). Research: `${CLAUDE_PLUGIN_ROOT}/docs/reply-styles-research.md`.

## Live context
- Active style: !`grep -ho '"outputStyle": *"[^"]*"' .claude/settings.local.json .claude/settings.json ~/.claude/settings.json 2>/dev/null | head -1 || echo '"outputStyle": "Default"'`
- Installed custom styles (user): !`ls ~/.claude/output-styles 2>/dev/null | tr '\n' ' ' || echo none` · (project): !`ls .claude/output-styles 2>/dev/null | tr '\n' ' ' || echo none`
- CLAUDE.md already has a hand-written reply section: !`grep -l -i "REPLY CONTRACT\|REPLY-STYLE\|reply style" ~/.claude/CLAUDE.md CLAUDE.md 2>/dev/null | tr '\n' ' ' || echo no`
- Arguments: `$ARGUMENTS`

## Procedure
1. **`show`** → print the active style, the installed ones, and the one-line description of each of the 7 (from `catalogue.md`). Stop.
2. **No style named** → print `catalogue.md` in full (the identity table, then the style table with pros and cons — nothing else), then ask with `AskUserQuestion` (one call, up to 3 questions):
   - "Which is closest to you?" → `developer / technical person` · `entrepreneur / founder / idea person` · `manager / decision-maker` · `non-technical (ops, support, marketing, owner)`
   - "Do you forward Claude's replies to other people, or read them on a phone?" → `often` · `sometimes` · `no` · `I don't know yet`
   - "When learning or deciding, do you want the reasoning written out?" → `no, keep it short` · `yes, I am learning` · `yes, for decisions` · `I don't know yet`
   Mapping: developer + forwards often/sometimes → **lcd**; developer + no → **engineer** (offer `minimal` as runner-up); founder → **lcd**; manager → **bluf**; non-technical → **plain**; "learning" → **teacher** as the second style to try; "decisions" → mention `try memo`.
   Then one confirming question: the recommended style (Recommended, with its one-line pros/cons) + the runner-up + "pick another" · scope `user-level (every project)` vs `this project only`.
3. **`try <name>`** → read `styles/<name>.md` and follow it for the rest of this conversation. No files written. Say so in one line.
4. **Install + switch** (default, or `<name>` given):
   - copy `styles/<name>.md` → `~/.claude/output-styles/<name>.md` (`--project` → `.claude/output-styles/<name>.md`, create the folder). Never edit the user's other style files.
   - set `"outputStyle": "<name>"` in `~/.claude/settings.json` (`--project` → `.claude/settings.local.json`), touching only that key — a 5-line Python read-modify-write, JSON validated after.
   - if the live context shows a hand-written reply section in CLAUDE.md: say "your CLAUDE.md has its own reply rules; when they conflict, those win — keep them or remove that section", and continue.
5. **`--claude-md`** (output styles disabled by an org, or the user prefers one file) → wrap the style's instructions in `<!-- REPLY-STYLE: <name> -->` … `<!-- /REPLY-STYLE -->` and insert it at the top of `~/.claude/CLAUDE.md` (`--project` → `./CLAUDE.md`), replacing an existing marked block. Takes effect after `/clear` or a restart.
6. **`off`** → set `outputStyle` to `Default` (or remove the marked block). Style files stay installed.
7. **Report (≤ 6 lines):** what is active now, from when (next message / after restart for a new file / after `/clear` for CLAUDE.md), where it was written, how to change it again (`/reply-style <name>` or `/output-style <name>`), and the one-line pros/cons of the chosen style so the user knows the trade-off they accepted.

## Rules
- Never change the user's rules, gates or CLAUDE.md content beyond the marked block. Never touch `permissions` or `hooks` in settings.
- Always confirm before writing (the AskUserQuestion step), except for an explicit `/reply-style <name>` which is the confirmation.
- Styles are instructions, not enforcement: say so when asked "is it guaranteed?". Errors, warnings and destructive-action confirmations keep full content in every style.
