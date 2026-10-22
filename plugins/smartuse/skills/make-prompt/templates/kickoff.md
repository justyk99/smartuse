# <Task title> — kickoff (<YYYY-MM-DD>, written by /make-prompt, mode: interview | quick)

## 1. Where things are (verified <date>)
- Work repo: <path> — open Claude THERE. Branch <branch>. Gates that apply: <the rules from CLAUDE.md that bite here>.
- Target code: <paths with line counts>. Reference code (the real thing, not guides): <paths>.
- Existing work on the same thing: <task folders / docs / commits / memory lines, or "none found">.
- Attachments read: <file → one line each>.

## 2. People, scope split, dates, appetite
- Asked by: <name>. Reviewer / lead: <name>. Working alongside: <name — what they own>.
- The user owns: <scope>. Not the user: <scope → who>.
- Dates: target <YYYY-MM-DD>, hard <YYYY-MM-DD>. Review with <name>: <date or unknown → who>.
- Appetite: <a day / a week / …> → scope sized to it (what is cut if it runs over: <item>).

## 3. Non-goals (do not build, do not touch)
- <item> · <item> · files of others: <path → owner (owner's sanction needed)>

## 4. Facts that constrain the design + rabbit holes
- <fact — verified: path/command> · <fact — unknown → who answers> · <fact — assumed: …>
- Rabbit holes (looks easy, is not): <item — evidence> · <item — evidence>
- Past incidents on similar work → gate: <incident (memory/rule) → the check>

## 5. Deliverables, in order — each line ends with its gate (the check that passes before the next one starts)
1. <audit / evidence table with file:line> — Gate: <…>
2. <benchmark or "done" checklist — dated sources> — Gate: <…>
3. <design proposal: options table + one recommendation per decision> — Gate: <…>
4. <interface / hand-off for the dependent person, if any> — Gate: <…>
5. <phased plan with dates + owners + test plan (happy / fail / edge / permission / cross-feature, test data with your prefix) + device or data matrix> — Gate: <…>
Acceptance (from "done"): <the check that proves it>.

## 6. Process
Plan mode. Strongest model = design deliverables; "Plan is firm — switch to the execution model" at the boundary. Counter-proposals before locking. Every mid-task decision → one dated line in `decisions.md` / task.md `## Decisions` immediately. Coverage claims need traces; every name verified by grep/MCP. Shared servers → warn + wait "g". Reply contract: What → How → Impact, ≤ 3-line blocks. Close (not a deliverable): task folder updated · knowledge file · after the commit, living-docs DEV.md + USER.md.

## 7. Open questions to settle FIRST (ask, don't guess)
1. <question> → <who answers>

## 8. End-to-end verification (the last step, always)
<the command / page / query that proves the whole thing works, with test data with your prefix; who confirms (tester / client); what artefact is kept (screenshot, log line, commit)>
