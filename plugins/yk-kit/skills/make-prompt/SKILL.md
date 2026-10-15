---
name: make-prompt
description: Turn a rough one-line ask into a top-tier kickoff prompt with the LEAST effort from the user — Claude greps the ground first (repo, memory, past tasks, owners, constraints), asks a few BASIC questions with clickable options (option 1 = Claude's best guess, "I don't know" always allowed), writes the prompt + task folder + a 5-line human summary, then WAITS for "go". Modes — `/make-prompt <ask>` (interview, ~3 min of the user's time) · `/make-prompt quick <ask>` (no questions, every slot assumed and marked) · add `dry` (scratch folder only). Not for one-file fixes, questions, or chat.
when_to_use: the user types /make-prompt, says "make me a prompt", "write the prompt", "kickoff", "brief me", pastes a thin one-line ask for work that takes more than a day, or starts a feature / bug hunt / design question from one line — OFFER it in one line ("want /make-prompt?"), never force it.
argument-hint: "[quick] [dry] <one-line ask>"
allowed-tools: Bash(date *), Bash(pwd), Bash(git *), Bash(svn info *), Bash(svn status *), Bash(ls *), Bash(command -v *), Bash(node -v*), Bash(grep *), Bash(cut *), Bash(tr *), Bash(wc *), Bash(head *), Read, Grep, Glob, Agent, AskUserQuestion, Write
---


# make-prompt — one line in, a planner-grade kickoff out (v2.0, 2026-10-15)

Part of yk-kit. Sources and reasoning: `DESIGN.md` beside this file (official "let Claude interview you" pattern, clarification research, context engineering, Shape Up).

**Guarantees:** no empty slot (filled, assumed, or `unknown → who answers`), no invented fact (every path / name / date from the repo, memory, or YK), saved where `/clear` cannot kill it, a self-check table before "go". **Not guaranteed:** the research after "go" (plan mode + the project rules do that) and a wrong answer from the user (it propagates; the summary shows it so it can be caught).


## Project adapter (optional, read first)
If `.claude/yk-kit.local.md` exists in the repo, its YAML frontmatter overrides detection:
```yaml
---
vcs: git            # git | svn
task_root: .task/ACTIVE          # where task folders live
archive_root: .task/COMPLETED    # closed tasks
docs_root: docs/features         # living-docs root (omit = living-docs skipped)
task_template:                   # optional template file for task.md
svn_flags: "--non-interactive --trust-server-cert-failures=unknown-ca,cn-mismatch"
author: your-vcs-username        # to recognise your own commits
jira_cli:                        # optional command that prints a ticket, e.g. "jira"
---
```
Without the file: git → `.task/ACTIVE` / `.task/COMPLETED` / `docs/features` (only if `docs/` exists); svn → `_SESSIONS/` / `_SESSIONS/archive/` / `_KNOWLEDGE_BASE/features/` (only if `_KNOWLEDGE_BASE/` exists). Keep the file out of git (`.gitignore`).

## Live context (injected when the skill is invoked — do not re-run these)
- Today: !`date +%F || true` · Invoked at: !`date -u +%FT%TZ || true` · cwd: !`pwd || true`
- VCS: !`git branch --show-current 2>/dev/null || svn info --show-item revision 2>/dev/null || echo none` · dirty files: !`{ git status --short 2>/dev/null || svn status 2>/dev/null || true; } | wc -l`
- Open task folders: !`{ ls -d _SESSIONS/*/ .task/ACTIVE/*/ .task/PARKED/*/ 2>/dev/null || true; } | grep -v -i "archive\|template" | head -12 | tr '\n' ' ' || true`
- Docs root: !`{ ls -d _KNOWLEDGE_BASE/features docs/features 2>/dev/null || echo none; } | tr '\n' ' ' || true`
- Recent commits: !`{ git log --oneline -6 2>/dev/null || echo "(svn: run svn log -q -l 6 with the trust flags if needed)"; } | cut -c1-70 | tr '\n' ';' || true`
- On this PC: cloudflared=!`command -v cloudflared >/dev/null 2>&1 && echo yes || echo no` pnpm=!`command -v pnpm >/dev/null 2>&1 && echo yes || echo no` node=!`node -v 2>/dev/null || echo no`
- Arguments: `$ARGUMENTS` — leading words `quick` and/or `dry` are modes; the rest is the ask.

## 0. Size check (one line, no tools)
The diff fits in one sentence, or it is a question → reply "no kickoff prompt needed — just do it?" and stop. Otherwise pick the **task type** from the ask: `feature` · `bug` · `design` (research / decision). Unclear → it becomes question 1 of the interview.

## 1. Ground check FIRST — silent, before any question (≤ 2 min)
Spawn ONE Explore subagent (read-only) with the ask's nouns and the live context. Its brief, verbatim:
1. **Attachments** the user pasted or named (screenshots, docs, Jira keys via a Jira CLI when `jira_cli` is set in the adapter) — read them; list what each one says in one line.
2. **Right repo?** Where does the code for this ask live? If elsewhere (a sister repo), say so with the path.
3. **Existing work:** grep the task folders and the docs root (see the adapter), the project memory dir (`~/.claude/projects/<project>/memory/*.md`) and `.claude/rules/*.md` incident lines for the same nouns. Report: shipped already? parked? a past incident?
4. **Reference code:** the real files behind the ask (not guides), with line counts; the entry points (page / handler / SP / route / store).
5. **Owners of the files the task must touch:** `git log --format=%an -- <path> | sort | uniq -c | sort -rn | head -3` (or `svn log -q -l 20 <path>` with `svn_flags` from the adapter). The user's VCS name = `author` in the adapter.
6. **Constraints:** package manager + lockfile agreement, build/deploy shape, shared servers, the database apply gate, missing tools on this PC, HTTPS / env unknowns.
7. **Rabbit holes:** 3 things that look easy but are not (shared SP with several callers, cross-project resx, lockfile mismatch, prod-only config…), each with evidence.
8. **A guess for every interview slot** (goal in one line, people, dates, done, non-goals, trouble, unknowns) tagged `verified` / `guess`.
It returns ≤ 40 lines, every fact tagged `verified:<path or command>` or `unknown`. Never ask the user anything this check or memory can answer.

## 2. Interview — defaults first, few clicks (skip entirely in `quick` mode)
Open `banks.md` (same folder) and use the bank for the task type. Rules that make it cheap for the user:
- **`AskUserQuestion` only.** ≤ 4 questions per call, ≤ 3 calls. Call 1 = goal + appetite + done (+ type if unclear). Call 2 = who + when + non-goals + trouble. Call 3 = unknowns + the rabbit holes to confirm. Each question ≤ 2 lines, plain words, no jargon.
- **Option 1 is always Claude's best guess from § 1 + memory, labelled `(Recommended)`**, with the evidence in its description. Names come from the owners list, dates from today + N, non-goals from the ground check. The user presses Enter most of the time.
- **"I don't know yet" is always an option.** It becomes an open question with an owner, never a guess.
- **Vague answer → restate it in one precise line** and confirm only when the precision changes the plan.
- **Follow-ups: max 3**, only when a gate is still undefined ("done = no mistakes" → "what can we check to prove it?").
- Stop when every template slot is filled or marked.

`quick` mode (also the only mode that works headless — `claude -p` cannot answer questions): no questions. Every slot gets the § 1 guess, each marked `assumed:` in the prompt and listed in the summary so the user corrects by exception.

## 3. Write the kickoff prompt
Fill `templates/kickoff.md` (sections: where things are · people / scope / dates / appetite · non-goals · constraints + rabbit holes · deliverables with gates · process · open questions first · end-to-end verification). **≤ 1,200 words.** Overflow (long evidence lines, the audit of old code, attachment digests) goes to `research.md` beside it, and the prompt says `see research.md § n` — the executing session reads it when needed. Reference files by path, never paste contents. Plain sentences around exact names. Every fact traceable to § 1, § 2, or marked `unknown → who` / `assumed:`.

## 4. Save where it survives /clear
- Task folder per the adapter: `task_root/<task>/task.md` (+ `decisions.md`); if `task_template` is set, start from it and put the prompt under `## Task`, leaving `## Decisions` empty.
- Docs root present → living-docs stubs `DEV.md` + `USER.md` from the `living-docs` skill templates (same plugin) with only the summary line filled.
- Wrong repo per § 1 → save to `~/.claude/tmp/make-prompt/<task>/` and say "open Claude in <repo>, then `/make-prompt` again or paste <path>".
- `dry` mode → `~/.claude/tmp/make-prompt/<task>/` only, nothing in the repo.

## 5. Self-check — the quality gate, shown with the hand-off
Score the saved prompt, ✓ / ✗ per line; fix every ✗ with one more question (interview) or an explicit `unknown → who` (quick) before handing off:
`≤ 1,200 words (overflow in research.md) · right repo · paths verified · owner named per file to touch · dates absolute · appetite stated · non-goals listed · deliverables ordered with a gate each · acceptance check for "done" · end-to-end verification step · open questions each with an owner · past incidents turned into gates · attachments read · nothing pasted that a path could reference`.

## 6. Hand-off (then WAIT — never start the work)
Print, in this order:
1. `Prompt saved: <path>` and the self-check line (✓ count, the ✗ items).
2. **Human summary, 5 lines** (what · who · when · done · not) — ready to paste to the team or Jira.
3. The `assumed:` list (quick mode) or the open questions (interview).
4. Next step, one line: small task → `say "go" — I start deliverable 1 in plan mode here`; big task → `/clear, then "continue <task folder>" (fresh context beats this one)`; when "done" is a checkable condition → `set it as /goal <condition> so the session cannot stop early`; design-heavy → "This needs a design pass — switch to your strongest model".

7. **Receipt.** Write `~/.claude/yk-kit/projects/<repo folder name>/pending.json` (create the folder; never inside the repo) with: `{"skill":"make-prompt","task":"<feature name>","mode":"interview|quick","started_at":"<Invoked at, from the live context>","self_check":"<n>/13","corrections":<how many answers the user changed>,"notes":"<one line>"}`. The Stop hook turns it into one ledger line (tokens, minutes) when this turn ends — say `receipt: pending → ledger` in the report. `dry` mode: still write it (the ledger is how the skill proves its cost).

## Rules
- Ground check before questions. Memory and grep answer before YK does.
- Defaults first; typing is the exception. One block at a time, ≤ 3 calls.
- Dates absolute, people named, paths verified, non-goals explicit, deliverables gated, verification last.
- No praise, no roast, no essay. The prompt and the 5-line summary are the output.
