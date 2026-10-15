# Living docs — DEV + USER doc per feature, kept current by the agent (plan, 2026-10-15)

Status: **PLAN — not installed anywhere.** the author's idea (15 Oct 2026): every feature gets a technical doc for developers and a user doc for operators, both LCD-written, both updated by Claude at low token cost when a task finishes and whenever a human verification / change / bug fix / concept change happens mid-task. Optional skill, not wired into either system yet.

## 0. Verdict in three lines

- **Important: yes.** Docs drift is the #1 complaint of every "vibe coding" write-up in 2026, and both GSG systems have the gap (Old: 5 module KBs for ~40 modules; New: `docs/` has guides and ADRs but no per-feature DEV/USER pair).
- **Novel: no.** At least 8 tools / templates do a version of it (§ 2). Most do dev docs only; almost none produce a user doc from the same flow.
- **Top-tier = the execution, not the idea:** deterministic trigger, delta-only input, isolated cheap context, marker-protected sections, and a human checkpoint before a doc records a bug as a feature. the author's flow already has the checkpoint (the commit closes the task, built 15 Oct). Add "the commit updates the docs" and a one-line mid-task decision log and the idea is complete.

## 1. Two corrections to the idea before building

| the author said | Keep | Change |
|---|---|---|
| "explanation in LCD… even a 10-year-old can understand" | True for the **USER doc** and for every explanation sentence. | The **DEV doc must keep exact names** (`usp_update_promotion`, `t_app_settings.GmtOffSetInMinutes`, `views/Bank/BankList.vue`). LCD = plain words *around* precise names, never instead of them. Two audiences → two files; one file for both goes wrong for both. |
| "Claude keeps updating the document every time it finishes a task" | Yes — but "finished" must mean **committed**, not "Claude thinks it is done". | The Living Docs template author's warning (§ 2): a silent after-every-task update records a bug as intended behaviour and the next session treats it as a rule. The commit gates (GATE 1/2 on New, svn checklist on Old) are the human checkpoint. Docs update **after** the commit lands, as step 9 of `commit-log` / step 6 of git EXECUTE. |
| "very less token spend" | Right goal. | Achieved by **inputs**, not by skipping: diff stat + task.md + the two docs (≈ 6–8 k tokens in, ≈ 1 k out) in a `context: fork` skill on `model: sonnet`. The main session pays one report line. Never "re-read the codebase to write docs". |

## 2. Who does this already (researched 2026-10-15)

| Tool / pattern | What it does | Trigger | Closest to the author's idea? |
|---|---|---|---|
| **Mintlify agent** (Pro/Enterprise) | reads the code change, opens a PR on the docs repo (or commits directly) | merge to `main` | dev/API docs only, hosted product |
| **Augment "docs agents"** guide | merge-triggered agent compares code vs prose, proposes doc PRs; advice: start with ONE surface, keep reviewer capacity | merge | pattern, not a tool |
| **Kiro (AWS)** | `.kiro/specs/<feature>/requirements.md · design.md · tasks.md`; **Agent Hooks** update related artifacts when code changes | file events | spec + auto-update, dev-side only, Bedrock-only |
| **GitHub Spec Kit** (MIT) | per-feature dir with `constitution / specify / plan / tasks / implement` slash commands; portable across agents | manual commands | spec before code; no update-after |
| **Living Docs template** (Diew, GitHub) | `agent.md` (short session rules) + `docs/` (one concern per file, `ARCH_ GUIDE_ REF_ LOGIC_ INCIDENT_` prefixes) + a **governance registry** ("one file owns each rule") | human says "doc sweep" | closest **shape**; author deliberately refuses auto-update |
| **claude-code-auto-memory** (plugin) | PostToolUse records dirty files → Stop spawns an isolated `memory-updater` agent → rewrites only `AUTO-MANAGED` marker sections of CLAUDE.md; `gitmode` = only on commit | Stop / commit | closest **mechanism** (markers + fork + commit mode); targets CLAUDE.md, not feature docs |
| **hook-auto-docs** (plugin) | SessionStart/PostToolUse/Stop hooks write a project-structure `.md` with zero model tokens | Stop | deterministic only — no prose, no user doc |
| **DeepWiki / Devin Wiki, Google Code Wiki** | whole-repo wiki, regenerated (Code Wiki: after each commit, not public yet) | commit / refresh | heavy, whole-repo, dev only |
| **ADRs as agent memory** (Davidson; codemyspec; Mistral `write-vibe-adr`) | `docs/decisions/*.md`; **accepted = binding, proposed = context, superseded = history**; one rule lives in one ADR; no deliberation logs | when a durable decision is made | the "decision log" half of the author's idea; the git repo already has `docs/adr/` |
| Research note (ceaksan, 108 k-line C# project) | auto-generate the "what" (signatures, schema, module map), humans write the "why"; models did better with structured persistent docs than with repo scanning | CI / git hook staleness check | supports the approach for the svn repo-sized C# code |

**What nobody in the list ships:** a USER doc produced from the same commit, in LCD language, next to the DEV doc. That plus the mid-task decision log is the author's addition.

## 3. The design (optional skill, user-level, opt-in per repo)

### 3.1 Files

```
<repo>/<docs-root>/<feature>/
  DEV.md     technical, for developers      (AUTO-MANAGED sections + MANUAL blocks)
  USER.md    for operators / customers      (AUTO-MANAGED sections + MANUAL blocks)
<repo>/<docs-root>/INDEX.md   one line per feature: name · DEV · USER · last version · owner
```

| Repo | docs-root | Why |
|---|---|---|
| the svn repo | `_KNOWLEDGE_BASE/features/<feature>/` | KB is already the dev-doc convention; svn-ignored, so it is local until the author decides to version it (`svn add` is the only change) |
| the git repo | `docs/features/<feature>/` | `docs/` is tracked (41 files, has `adr/`, `v2-handbook/`); the team sees it in GitLab |
| the git repo | same as the git repo | |

Feature name = the task folder name without the date (`a shipped feature`, `a shipped feature`).

### 3.2 DEV.md template (≤ 1 page, every block ≤ 3 lines)

```markdown
# <Feature> — DEV
<!-- AUTO-MANAGED: summary -->
**What it does:** one sentence.  **Who uses it:** role.  **Since:** 2.8.YYMMDD.XX (rNNNN) / <hash>.
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: flow -->
## Flow (exact names)
page `bo_web/.../x.aspx` → `services/X.ashx` case `do_thing` → `BL.X_YK.DoThing()` → `DAL.X_YK` → `usp_do_thing`
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: objects -->
## DB / config objects
| Object | Kind | Note |
|---|---|---|
| `usp_do_thing` | SP | @error_code / @error_msg OUT |
| `t_app_settings.ThingEnabled` | app setting | default 0; description on advanced_settings.aspx |
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: decisions -->
## Decisions (dated, newest first — copied from task.md `## Decisions`)
- 15/10/2026 — targeted users win over whitelist when both set — manager confirmed (chat)
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: gotchas -->
## Gotchas
- dates in `t_x.created_at` are UTC; display via GMTOffset
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: verify -->
## How to verify
`bash .claude/build-check.sh` → BUILD CLEAN · open page → filter `yk_test` → expect 1 row
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: history -->
## History
- 2.8.261015.01 (r3534) 15/10/2026 — v1 shipped
<!-- /AUTO-MANAGED -->
<!-- MANUAL -->
(hand-written notes survive every update)
<!-- /MANUAL -->
```

### 3.3 USER.md template (LCD, zero code names unless the user types them)

```markdown
# <Feature name as the menu shows it>
<!-- AUTO-MANAGED: what -->
**What it is for:** one sentence a new operator understands.
**Where:** Menu → Reports → Win/Lose (needs the "Win/Lose report" permission).
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: steps -->
## How to use it
1. Pick the date range (today is pre-filled).
2. Click **Search**.
3. Click **Export** to get the Excel file.
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: see -->
## What you will see
A table with one row per agent; the bottom row is the total.
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: faq -->
## Common questions
- **Why is today's number lower than the game provider's?** The report shows settled bets only; open bets are not counted.
<!-- /AUTO-MANAGED -->
<!-- AUTO-MANAGED: changes -->
## Changes
- 15/10/2026 (v2.8.261015.01) — new: Export button
<!-- /AUTO-MANAGED -->
```

Menu path, permission name and button labels are **read from the code** (`module.json` / router / resx), never guessed (R8). The `## Changes` list is the raw material for the Release Notes Automation project (`a release-notes automation`).

### 3.4 Triggers — four, each with a cost

| # | When | Who runs | Cost | What happens |
|---|---|---|---|---|
| T1 | Plan approved ("plan is firm") | main session, 1 edit | ~0.3 k | Create `DEV.md` + `USER.md` stubs from the templates with only `summary` / `what` filled; add `## Decisions` to task.md |
| T2 | **Mid-task change**: human verification result, "actually do it this way", bug found, concept change | main session, 1 line | ~0.1 k | Append `- DD/MM/YYYY — <what changed> — <why / who said>` to task.md `## Decisions`. This is the memory fix: it is written the moment it happens, not at the end. A rule line, no skill. |
| T3 | **Commit landed** (`commit-log` step 9 / git EXECUTE step 6) | `living-docs` skill, **`context: fork`, `model: sonnet`** | ~6–8 k in / 1 k out, outside the main window | Inputs: task.md (incl. Decisions) + `svn diff -r PREV:HEAD --summarize` or `git show --stat <hash>` + the two docs. Rewrites only the AUTO-MANAGED sections that the diff touches; appends History / Changes; updates INDEX.md. Returns one line: `docs updated: DEV.md (flow, objects, +1 decision) · USER.md (+1 step, +1 change)`. |
| T4 | Optional later: **staleness gate** | hook, deterministic | 0 | SessionStart: list features whose source files (from DEV.md `flow` paths) changed after the doc's last History line → `docs stale: a shipped feature`. Or a Stop block like the build gate. Build only after T1–T3 have run for a month. |

Explicit calls: `/living-docs <task-folder>` (re-run T3 by hand) · `/living-docs fix "<correction>"` (the author read a doc and found it wrong) · `/living-docs publish <feature>` (USER.md → Confluence page via the Atlassian MCP `createConfluencePage` / `updateConfluencePage`, or an Artifact link for a quick share). The repo markdown stays the source of truth; Confluence / Artifact are views of it.

### 3.5 Skill frontmatter (draft, `~/.claude/skills/living-docs/SKILL.md`)

```yaml
---
name: living-docs
description: Update the per-feature DEV.md + USER.md after a commit landed (called by commit-log step 9 / git EXECUTE step 6, or /living-docs <task-folder>). Also /living-docs fix "<correction>" and /living-docs publish <feature>. Reads task.md + the commit diff only; rewrites AUTO-MANAGED sections only; never records behaviour that is not in the committed diff.
context: fork
model: sonnet
disable-model-invocation: true
---
```

`disable-model-invocation: true` so it never fires on its own — only the commit steps and the author call it. The templates live in the skill folder (`templates/DEV.md`, `templates/USER.md`) so both repos share one copy.

### 3.6 Guardrails (restate in the skill body — forked skills do not inherit the rules)

1. Source of truth = the committed diff + task.md. A decision line without a matching diff goes in `Decisions`, never in `Flow`.
2. Rewrite only `AUTO-MANAGED` sections the diff touches; `MANUAL` blocks are untouchable; never delete a History / Changes line.
3. Every name in DEV.md must appear in the diff or the repo (grep before writing — R8). USER.md menu paths come from `module.json` / router / resx.
4. LCD: ≤ 3 lines per block, one idea per line, a technical term gets a 3-word gloss on first use in USER.md; no code names in USER.md.
5. ≤ 1 page per doc. When a doc outgrows it, split by sub-feature, do not compress the language.
6. Report what changed per file and stop. No "docs are up to date" without the per-section list.

## 4. Rollout order (when the user says "g")

1. **Templates + skill** in `~/.claude/skills/living-docs/` (S). Copy to Guru `library/skills/living-docs/`.
2. **Wire T3**: one line in the svn repo `commit-log/SKILL.md` (step 9) and the git repo `git-workflow.md` (EXECUTE step 6): "then `/living-docs <task-folder>`; report its line". Opt-in per repo: a repo without a docs-root skips with "living-docs: no docs root, skipping" (S).
3. **Wire T1 + T2**: add `## Decisions` to `_SESSIONS/_TEMPLATE_task.md` and the gsg `.task` template; one rule line in both `task-management.md`: "any mid-task verification / change / bug / concept change → one dated line under `## Decisions` immediately" (S).
4. **Back-fill 2 features** as the proof: `a shipped feature` (Old, active) and `a shipped feature` (New, shipped) — generated from their task.md + commit diff, then the author reads both USER.md files as the 10-year-old test (M).
5. Run for a month → decide T4 (staleness hook) and the Confluence publish.

## 5. What it is worth in the ladder

`cheat-sheets/mastery-ladder.md` dimension **Verification + Memory**: this moves "docs" from Default (none) to Enforced (commit-triggered, marker-protected) and, with T4, to Measured (stale-doc count per session). It is also a sellable teaching asset: the template pair + the skill is the kind of thing a colleague can adopt in ten minutes.

## 6. Sources (fetched 2026-10-15)

- Living Docs template — https://github.com/Diew/living-docs (three layers, governance registry, "updates only when you ask — a bug would be recorded as intended behaviour")
- claude-code-auto-memory — https://github.com/severity1/claude-code-auto-memory (PostToolUse dirty files → Stop → isolated agent; AUTO-MANAGED markers; `gitmode`)
- hook-auto-docs plugin — https://www.claudepluginhub.com/plugins/dev-gom-hook-auto-docs-plugins-hook-auto-docs (0-token structure doc; only tracks `Write`; confidence 38/100)
- Mintlify agent — https://www.mintlify.com/docs/guides/automate-agent and https://www.mintlify.com/blog/docs-on-autopilot
- Augment self-updating docs guide — https://www.augmentcode.com/guides/self-updating-documentation-docs-agents-sync
- Living architecture documentation research — https://ceaksan.com/en/ai-agent-living-architecture-documentation
- ADRs for agents — https://duncandavidson.com/agents-love-decisions and https://codemyspec.com/blog/architectural-decision-records
- Spec Kit vs Kiro — https://docs.plannotator.ai/compare/github-spec-kit-vs-kiro-specs.md and https://codemyspec.com/blog/spec-kit-vs-kiro
- DeepWiki — https://docs.devin.ai/work-with-devin/deepwiki
- Dosu "doc-it" skill — https://dosu.dev/blog/claude-code-skill-doc-it
