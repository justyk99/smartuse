---
name: living-docs
description: Update a feature's DEV.md (developers) + USER.md (operators) after a commit landed — called after a commit lands (wire it into your commit procedure), or by the user as `/living-docs <task-folder>`, `/living-docs fix "<correction>"`, `/living-docs publish <feature>`. Reads task.md + the commit diff only, rewrites AUTO-MANAGED sections only, never records behaviour that is not in the committed diff. Opt-in per repo (needs a docs root). Invoke it (Skill tool, args `<task-folder> <commit id>`) right after a commit lands and the task folder is closed — it forks to a cheap model, so do not wait on it.
context: fork
model: sonnet
---

# living-docs — keep the DEV + USER doc of a feature current (v1.0, 2026-10-15)

You run in a fresh context. The project rules are NOT loaded here — the ones that matter are restated in § Guardrails. Follow them.


## Project adapter (optional, read first)
If `.claude/smartuse.local.md` exists in the repo, its YAML frontmatter overrides detection:
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

## Live context
- Invoked at: !`date -u +%FT%TZ || true` (use this exact value as `started_at` in the receipt — never your own clock)

## Inputs (arguments)

`$ARGUMENTS` = one of:
- `<task-folder>` — path to the task folder (`_SESSIONS/<task>_<date>/` or `.task/COMPLETED/<task>/`), optionally followed by the commit id (`r3534` or a git hash). Without an id, read it from the `DONE — committed …` stamp in task.md.
- `fix "<correction>"` — the user read a doc and found an error; apply the correction to the right section, add nothing else.
- `publish <feature>` — push USER.md to Confluence (Atlassian MCP `createConfluencePage` / `updateConfluencePage`; ask for the space key if unknown) or, if no Atlassian MCP, publish it as an Artifact. The repo markdown stays the source of truth.

## Where docs live (docs root) — skip if absent
Docs root and diff command come from the adapter (`docs_root`, `vcs`, `svn_flags`) or detection: git → `git show --stat <hash>` then `git show <hash> -- <file>`; svn → `svn diff -c rNNNN --summarize` then `svn diff -c rNNNN <file>` with `svn_flags`. No docs root → print `living-docs: no docs root, skipping` and stop. Never create a docs root on your own.

## Step 0 — say what is missing before doing anything
Check, in this order, and print the matching line as the FIRST line of the reply, then stop:
- no docs root (adapter `docs_root` unset and no detectable one) → `living-docs: no docs root, skipping`
- the task folder / task.md named in the arguments does not exist → `living-docs: task folder not found: <path>`
- the commit id cannot be found in the task.md stamp or the arguments → `living-docs: no commit id, give me rNNNN / <hash>`
Never draft DEV.md or USER.md content for a feature you could not find; a missing input is reported, not invented.

## Procedure (T3 — after a commit)

1. **Read** task.md fully (status line, requirements, plan checklist, `## Decisions` if present, `decisions.md` if present). Note the commit id and version.
2. **Diff, summarized first.** Run the summarize/stat command. List the changed files. Then read the diff only for files that change behaviour (code, SP text, config, resx). Skip screenshots, test artifacts, lock files.
3. **Read the two docs** if they exist. If not, copy `templates/DEV.md` and `templates/USER.md` from this skill folder (`${CLAUDE_SKILL_DIR}/templates/`) and replace `<Feature>` with the feature name.
4. **Rewrite only the AUTO-MANAGED sections the diff touches.** Mapping:
   - new/changed page, handler, BL/DAL, SP, API endpoint, Vue view/store → DEV `flow` + `objects`
   - new table/column/app setting/permission/resx key → DEV `objects`; permission or menu change → USER `what`
   - `## Decisions` lines in task.md newer than the doc's last History line → DEV `decisions` (copy verbatim, newest first)
   - anything that bit you in task.md (`Side finding`, `got bitten`, `gotcha`, `careful`) → DEV `gotchas`
   - test commands / verification steps in task.md → DEV `verify`
   - user-visible behaviour (new button, new column, new filter, new report, changed rule) → USER `steps` / `see` / `faq`
   - always: append one line to DEV `history` and USER `changes` (version + id + date + what)
5. **Index.** Add or update the feature's line in `<docs-root>/../INDEX.md` (`| feature | DEV | USER | last version | date |`), create INDEX.md from the one-line header if missing.
6. **Report, one line per file, then stop:** `docs updated: DEV.md (flow, objects, +1 decision) · USER.md (+1 step, +1 change) · INDEX.md`. If a section needed a fact you could not find in the diff or the repo, say `unknown: <what>` instead of guessing.

7. **Receipt.** Write `~/.claude/smartuse/projects/<repo folder name>/pending.json` with `{"skill":"living-docs","task":"<feature>","mode":"update|fix|publish","started_at":"<Invoked at, from the live context>","self_check":"<sections updated>/<sections>","notes":"<one line>"}`; the Stop hook appends the ledger line.

## Guardrails (restated — you do not inherit the project rules)

1. **Source of truth = the committed diff + task.md.** A task.md decision without a matching diff goes in `decisions`, never in `flow` or `steps`. Never describe behaviour you did not see in the diff.
2. **Markers.** Rewrite only between `<!-- AUTO-MANAGED: x -->` and `<!-- /AUTO-MANAGED -->`. `<!-- MANUAL -->` blocks are untouchable. Never delete a `history` / `changes` line. Keep the marker lines exactly.
3. **Names are verified, never assumed.** Every page, SP, table, column, method, route or key in DEV.md must appear in the diff or be found by grep in the repo. USER.md menu paths, permission names and button labels come from `module.json` / `aff_module.json` / the router / `.resx` or `locales` — grep them. Not found → write `unknown: <what>` and say so in the report.
4. **LCD language.** Every block ≤ 3 short lines, one idea per line. USER.md: no code names, no SP names, no file paths; a technical term gets a 3-word gloss the first time ("settled bets (bets already paid out)"). DEV.md: plain sentences around exact names.
5. **≤ 1 page per doc.** If a doc would exceed ~60 lines, split by sub-feature (`<feature>/<sub>/`), never compress the language.
6. **Edit tool only; smallest edit.** Never rewrite the whole file. Never touch any file outside the docs root, task.md and INDEX.md. No commits, no `svn add`, no `git add` — the user decides what gets versioned.
7. **Nothing else.** No "docs are up to date" without the per-section list. No extra sections, no emojis, no marketing tone.

## `fix "<correction>"`

Locate the section the correction belongs to (by the words the user used), apply the smallest edit inside its markers, add nothing else, report `fixed: <file> § <section>`.

## `publish <feature>`

Read USER.md, strip the marker comments, push the body as the page content. Report the page URL. Never publish DEV.md unless asked by name.
