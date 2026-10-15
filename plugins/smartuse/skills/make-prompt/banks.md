# make-prompt — question banks (loaded by SKILL.md § 2)

Every question: ≤ 2 lines, plain words. Option 1 = Claude's best guess from the ground check + memory, labelled `(Recommended)` with its evidence in the description. Always offer `I don't know yet` (→ open question with an owner). "Turns into" = the kickoff section it fills.

## Common to every type (asked in call 1 / call 2)

| Key | Ask | Options (option 1 = the guess) | Turns into |
|---|---|---|---|
| goal | "In one line, like telling a friend — is this what should exist when it's done?" | the restated ask · "close, but…" (Other) | § 1 goal |
| appetite | "How much of your time is this worth?" | a day · a week · 2–3 weeks · a month+ | § 2 appetite → scope size |
| done | "How will you know it is finished?" | committed + tester passed · client signs off · report/email sent · demo to the team | § 5 last gate + acceptance |
| who | "Who asked, who reviews, who else touches the same files?" | names from the owners list (top 3) · just me | § 2 people + owner sanction list |
| when | "When? Rough is fine." | this week · 2 weeks · a month · no date (→ target = today + N, hard = +1 week, both absolute) | § 2 dates |
| not | "What must NOT be touched or built?" | from the ground check: other people's files · prod / customer data · sister module · native/offline/etc. · nothing comes to mind | § 3 non-goals |
| trouble | "If this fails in a month, what is the most likely reason?" (pre-mortem) | the top rabbit hole from the ground check · the last incident from memory · "nothing comes to mind" | § 4 constraints → a gate per risk |
| unknowns | "What do you not know yet, and who can answer it?" | the unknowns the ground check found (one per option, with a suggested owner) · nothing | § 7 open questions |

## feature (default)
Call 1: goal · appetite · done (+ type if unclear). Call 2: who · when · not · trouble. Call 3: unknowns · "these 3 rabbit holes — agree?" (multi-select).
Follow-ups (max 3): "done = no mistakes" → "what can we check to prove it?" · a reviewer without a name → "who signs off?" · a sister system named → "same change there too, or BO only?"

## bug (turns into a root-cause plan, not a feature plan)
| Key | Ask | Options | Turns into |
|---|---|---|---|
| symptom | "What exactly do you see? Paste the message or screenshot." | (Other = paste) · "it's in the attachment" | symptom, verbatim |
| where | "Where: which page / SP / customer / environment?" | from the ground check | trace entry point |
| since | "Since when, and what changed around then?" | after a deploy (last commit date) · after a data change · always · don't know | suspects (log window) |
| repro | "How do I make it happen again? Account, steps, data." | "same as the report" · can't reproduce · Other | repro script with `yk` data |
| expected | "What should happen instead?" | the obvious inverse (guess) · Other | expected = the test |
| reporter | "Who reported it, how urgent?" | customer live · tester · colleague · me | priority + who confirms the fix |
| not | "What must not change while fixing it?" | shared SP callers (from grep) · other projects · nothing | blast radius + owners' sanction |
Call 1: symptom · where · since · repro. Call 2: expected · reporter · not. Call 3: unknowns.

## design / research (turns into an options table + one recommendation; strongest model first)
| Key | Ask | Options | Turns into |
|---|---|---|---|
| decision | "What decision has to come out of this?" | the restated ask · Other | the question the doc answers |
| options | "Options already in your head?" | the 2–3 the ground check saw · none yet | option list seed |
| constraints | "Constraints: money, time, tech, people?" | multi-select from the ground check | § 4 |
| decider | "Who decides, and by when?" | names from owners · me · date options | decision owner + date |
| wrong | "What would make it the wrong decision?" | cost · breaks existing flow · nobody maintains it · Other | evaluation criteria |
| known | "What do you already know for sure?" | verified facts from the ground check (multi-select to confirm) | facts not to re-research |
| shape | "What should the output look like?" | options table · one-page doc · demo · team message | deliverable shape |
Call 1: decision · options · constraints · decider. Call 2: wrong · known · shape. Call 3: unknowns.
