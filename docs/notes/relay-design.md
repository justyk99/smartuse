# Relay — pass the evidence, not a description (proposal, 2026-10-22). For the author.

Source: the incident "The relay that turned photos into words" (anonymised; the course's case study 7). Two Claude Code sessions on one project: a cloud **manager** that plans and reviews, a laptop **builder** that writes code and renders 3D room pictures; they talk through git and short messages; the **owner** talks to the manager from a phone. The manager forwarded the owner's photos as one line of text, read one day of a three-day export, ran eight review rounds on numbers while the owner's test was "does it look real on my phone", and spent about RM7.5 on paid image runs that were all thrown away (one batch orange from the manager's own light setting).

Status: **proposal, nothing built.** Each rule below gets the cheapest mechanism that *enforces* it (a hook or a gate, not a reminder), the test that would have failed on this incident, and its limits. Build order at the end.

## Three primitives cover the five rules
All three are deterministic, stdlib-only, 0 model tokens, and reuse what smartuse already has (the transcript parsing in `ledger.py`, the human-only adapter guarded by `file-guard` and `bash-guard`, the Stop-gate pattern of `until-done.py`).

| Primitive | What it does | Rules |
|---|---|---|
| **Evidence extraction** — `relay.py save` | Copies every attachment the owner sent (image and document blocks in the session transcript, and files the app saved for the session's uploads) into `docs/inbox/<date>/` as files, with `MANIFEST.json`: name · type · bytes · sha256 · received at · which turn. Videos also get keyframes (first / middle / last) so a receiver can open them; audio is listed as "needs a transcript". | 1, 2 |
| **Owner-quote check** | Verifies that a quoted line exists verbatim in a message the human typed in *this* session — not tool output, and not a message relayed from another session (`<cross-session-message …>` turns are excluded, so a planner cannot authorise anything on the owner's behalf). | 3, 4, 5 |
| **Open-before-done gate** | A Stop gate (the `until-done` pattern) that refuses to end the turn while a file the session was handed has not been opened with the Read tool; a PostToolUse hook on Read records what was opened. | 1, 2 |

## Rule 1 — attachments travel as files, never as descriptions; the receiver confirms it opened each one
- **Mechanism (cheapest that enforces): `relay-guard`, a PreToolUse hook** on the relay channels: `SendMessage`, `mcp__claude-code-remote__send_message`, and `git commit` of a brief (`docs/code-brief-*`, `docs/*-ANSWERS.md`). It reads the session transcript, collects every owner attachment since the last relay, and denies when one is in no `MANIFEST.json` that the outgoing message or brief names: `relay-guard: 3 attachments from the owner are not forwarded: room.jpg, desk.jpg, laminate.jpg. Run relay.py save and list docs/inbox/<date>/MANIFEST.json in the brief, or SKIP <name>: <reason>.` `relay.py save` is what makes this cheap: the model never has to re-create a picture it only saw; the script moves the bytes.
- **Second layer, on the receiver:** the open-before-done gate over every manifest named in the brief it is building from. Its result file starts with `## Opened` (each file and one line on what it shows), which the owner can read.
- **Test that fails on this incident:** fixture transcript where the owner's turn holds three image blocks; the outgoing message is `hand-crank desk 1200x600, walnut top, black legs`. Expected: **deny**, naming the three files. Receiver fixture: a brief naming a 3-file manifest and a builder transcript with no Read of them. Expected: the **Stop is blocked** with `unopened: room.jpg, desk.jpg, laminate.jpg`.
- **Limits:** opening a file is not understanding it — the owner still judges the result (rule 3). Attachments the owner sends *after* the relay are caught at the next relay, not before.

## Rule 2 — inventory before scope; never ask again for something already received
- **Mechanism: `inventory.py <dir|zip>` plus a gate.** The script lists every file with type (image · pdf · audio · video · text · other), date (from WhatsApp-style names such as `IMG-YYYYMMDD-WA…` / `PTT-…` / `DOC-…`, the timestamp of the chat line that attached it, the zip entry date, else mtime) and size, and writes `docs/inbox/INVENTORY.md` with an empty `decision` column. A PreToolUse gate denies writing a brief or sending a relay while any file under `docs/inbox/` has no row with `read` or `skip: <reason>`. The brief's first line is the count the owner can judge at a glance: `read 4 of 31 files (day 3 only); skipped 27 — see INVENTORY.md`.
- **"Never ask again":** a check on `AskUserQuestion` (PreToolUse) and on the final reply (Stop) that blocks a request for a kind of file the inventory already lists — pattern `(send|share|upload|attach|forward) … (photo|picture|render|pdf|drawing|plan|video|voice)` against the inventory's types and names: `already received: 6 designer renders dated 2 days earlier (docs/inbox/…); open them instead of asking`. This part is a pattern match: it catches the plain request, not every phrasing.
- **Test that fails on this incident:** fixture export with designer renders dated D−2, photos and PDFs on D−1, the chat of day D; an inventory that covers only day D. Expected: the brief write is **denied**, naming the D−2 renders. Ask fixture: the reply `Could you send me the designer renders?` with those renders in the inventory. Expected: the **Stop is blocked** with `already received`.
- **Limits:** a `skip` reason is not judged — but the count in the brief's first line puts it in front of the owner.

## Rule 3 — review against the owner's goal first, judged by the owner's eyes; numbers only support it
- **Mechanism: a review-file contract, checked by a PreToolUse hook, with a round cap.** Each review round is a file (`docs/M<n>-REVIEW-<k>.md`). Its first line must be `Owner's test: "<the acceptance line from the brief, verbatim>" — owner verdict: pass | fail | pending`. From round 3 on, an earlier round must carry an owner verdict that passes the owner-quote check (the owner's own words about a phone-size picture they were sent), else the write is denied: `round 3 without the owner's verdict: send the owner the picture at phone size and ask the brief's test; numbers do not decide this`.
- **Test that fails on this incident:** rounds 1–8 as files that open with hue / colour-difference / wall-share numbers, no `Owner's test:` line, no owner verdict. Expected: round 1 is **denied** for the missing first line; with that line added, round 3 is **denied** for the missing verdict. The incident ran 8 rounds; the cap stops it at 3.
- **Limits:** the hook proves the owner was asked and answered; it cannot make the picture look real.

## Rule 4 — no paid call without the owner's go for that exact run, a cap, and one test output first
- **Mechanism: a `paid` rule family in `bash-guard`.** A command is a paid call when it names a paid-API host or key variable (image and LLM APIs: `api.openai.com`, `api.stability.ai`, `api.replicate.com`, `fal.run`, `generativelanguage.googleapis.com`, `api.ideogram.ai`, … and `*_API_KEY` / `*_TOKEN` names), or runs a script whose source, or the `.env` beside it, names one. MCP tools the project marks in the adapter (`paid_tools:`) count too (PreToolUse on those tool names). A paid call is denied unless a go exists for that script: either a `paid:` entry in the human-only adapter (`script`, `runs`, `cap`), or — for an owner who is only on a phone — a line the owner typed in this session that passes the owner-quote check, `paid go: <script> × <runs>, cap <amount>`. The hook counts runs in the state dir. The first run after a new go must ask for one output (the project names its count flag in the adapter); further runs need `test ok` from the owner, also by quote.
- **Test that fails on this incident:** the batch command that spent the RM7.5, with no go anywhere. Expected: **denied at the first call** (RM0 spent). With a go of `× 10` but no `test ok`: the second call is **denied**, so the orange batch is one picture, not a batch. With the go inside a message relayed from the manager session: **denied** (the go must be the owner's own typing).
- **Limits:** a call hidden behind configuration the scan cannot see (a host read from a remote config) slips through; the adapter's `paid_scripts:` list closes that for a known project.

## Rule 5 — visual iteration runs between the owner and the builder; the planner joins only when asked
- **Mechanism (two lines of defence, both cheap):**
  1. **`deny_write:` in each checkout's human-only adapter**, enforced by `file-guard` (Write / Edit / MultiEdit / NotebookEdit) and `bash-guard` (shell writes): the manager's checkout lists `render/**`, `scenes/**`, `materials/**`, `lighting/**`. The manager cannot change a light by editing a file.
  2. **A `## Visual parameters` section in the brief** that the manager's brief writes must leave empty unless an owner quote (owner-quote check) asks for the change. The manager cannot change a light by writing it into the brief either.
- **Test that fails on this incident:** the manager's checkout with `deny_write: [lighting/**]` editing `lighting/key.json` → **denied**. A manager brief that sets a colour temperature in `## Visual parameters` with no owner quote → **denied**.
- **Limits:** this keeps the planner's hands off the pictures; it does not stop the owner from asking the planner for an opinion, which is the point.

## Protocol lines to propose for the two-Claude protocol (not applied)
- Replace "Pictures and screenshots are the only hand-carried things" with: "The person sends pictures to whichever session needs them. A session that receives files saves them to `docs/inbox/` with `relay.py save` before it writes anything about them, and every brief lists the manifest."
- Add: "Visual rounds run between the person and the builder (Remote Control on the phone); the manager reviews only when asked."
- Add: "Paid calls: the person's typed go, one test output, then the batch."

## Build order (cheapest first, most money or harm first)
1. Rule 4 — the `paid` rule in `bash-guard` (a regex family, a counter, one owner-quote check). Stops money leaking today.
2. Rule 1 — `relay.py save` + `relay-guard`, then the receiver's open-before-done gate. The lesson of the incident.
3. Rule 2 — `inventory.py` + the brief gate; the ask-again check.
4. Rules 3 and 5 — the review-file contract and the planner's `deny_write:` / visual-parameters section (both reuse the owner-quote check).
