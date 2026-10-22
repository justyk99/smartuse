# make-prompt — design notes (v2.0, 2026-10-15). Not loaded by Claude; for the author and course readers.

## The problem it solves
A planner needs paths, owners, absolute dates, non-goals, gates and open questions with owners (the 2026-10-15 PWA roast listed exactly these). Nobody types that by hand every time. Split: the repo half is found by grep; the head half is asked with defaults; the rest is marked unknown with an owner.

## Effort model (what the author actually does)
one line (the ask) → ~8–10 clicks on options (most are "Recommended" = Claude's guess) → 1–3 typed answers (names, a symptom) → read a 5-line summary → "go". About 3 minutes. `quick` mode: one line, then correct by exception.

## Where each design choice comes from
| Choice | Source |
|---|---|
| Interview with AskUserQuestion, then a self-contained spec, then a fresh session | Claude Code best practices → "Let Claude interview you" (code.claude.com/docs/en/best-practices): spec names files + out-of-scope + ends with end-to-end verification; execute in a fresh session |
| Ask only when something is missing; otherwise do not | "Ask or Assume?" (arXiv 2603.26233): on underspecified SWE-bench, asking lifted resolve rate on the asked tasks from 44% to 66%; on tasks where the agent did not ask, 77% either way. Separate "intent" detection from execution → our ground-check subagent flags gaps, the main session asks |
| Smallest high-signal prompt, clear sections, paths not contents, few canonical examples | Anthropic "Effective context engineering for AI agents" |
| Appetite · rabbit holes · no-gos | Shape Up pitch (Basecamp): the pitch is not a spec — define WHAT, bound the time, name what is left out |
| One question block at a time, lettered options, user can answer with a letter | superpowers `brainstorming` (hard gate before code; one question at a time was the part users liked) |
| 3–5 questions then a file; label unspecified things TBD, never invent | OpenHands PRD skill · julianromli prd skill |
| Context → scope → approach → … → timeline phases; PRD with decision log | propstreet `deep-interview` |
| Decisions written the moment they happen | Living Docs template + ADR-as-memory posts (Davidson) |
| Pre-mortem question ("if this fails in a month, why?") | classic pre-mortem (Klein); cheapest single question for risks |
| Defaults first: option 1 = Claude's guess with evidence | effort reduction; AskUserQuestion "(Recommended)" convention |
| `!` shell preprocessing for date / branch / task folders | Claude Code commands + skills dynamic context (official plugin-dev docs) |

## What it guarantees / does not
Guarantees: every slot filled, assumed or `unknown → who`; no invented fact; saved in the task folder; self-check table. Does not: the research after "go"; a wrong answer from the author; a vague ask in `quick` mode produces a prompt full of `assumed:` lines (that is the point — he corrects by exception).

## Test log
(appended after each run — see § below)

### Test A — 2026-10-15, the git repo, `quick dry`, ask = "PWA for the the customer web app. a colleague will build push on top after. Deadline 3-4 weeks. Reference: old system PWA + a colleague's docs in ~/Downloads/PWA"
- Headless `claude -p`, bypass mode, 8 turns, 7 min 11 s, $2.53 (Explore subagent did the ground check).
- Output: `task.md` 53 lines / 1,754 words + empty `decisions.md`; self-check 13/13; 5-line summary; 9 `assumed:` items; found that `~/Downloads/PWA` does not exist in WSL (real path `/mnt/c/Users/user/Downloads/PWA`) and read all 7 docs there.
- Versus the 2026-10-15 roast prompt: covered every item it listed (file:line reference code, both lockfiles, HTTPS unknown → the deploy owner, a colleague's boot-gate bug as a gate, cloudflared check, owners per file) plus items it lacked (appetite with the cut list, 5 rabbit holes with evidence, 8 open questions each with an owner, an end-to-end verification step, the iOS separate-storage re-login risk).
- Weakness: 1,754 words against a 1-page target → rule changed to ≤ 1,200 words with overflow in `research.md`.

### Test B — 2026-10-15, the svn repo, `quick dry`, ask = "Balance transfer credits the account many times the amount when the rate is entered as a percentage like 80 instead of 0.8. A customer reported it on the account details page."
- Headless, 6 turns, 7 min 51 s, $2.97. Output 82 lines / 1,282 words in the the svn repo task template (Status · Task · Research · Plan · Notes · Decisions); self-check 12/13 (two Jira screenshots not downloaded → marked unknown).
- The ground check found the bug was ALREADY FIXED: Jira a Jira ticket (read via the jira tool), the back-office fix, an earlier revision by the file owner 2026-09-25, deployed 2026-09-29 — and that the fix left two gaps (the sister system's `transfer` module has the same multiply with no cap; stored rows with rate > 1 never reset). The bug bank's "since when / where" slots were answered from svn + Jira, not from the author.
- It mapped every caller of the sister system's transfer path (web, app, api), named the file owner (the file owner, 11 of the last 20 commits), turned the 2026-05-05 shared-SP incident into a gate, and wrote 4 rabbit holes (including that the sister system may under-credit rather than over-credit — "trace before assuming same bug").
- Weakness: none blocking. Cost per quick run ≈ $2.5–3 (the Explore subagent reads a lot); fine for multi-day work, wrong for a one-file fix — which the size check refuses anyway.

### Verdict after two runs
Quick mode alone already produces a kickoff that exceeds the 2026-10-15 roast prompt. The interview mode adds the author's head-half (names, dates, appetite, done) on top with ~8–10 clicks. Next test: a real interactive run on the PWA task from the git repo.

