# Paid-call guard (relay-design rule 4) — brief, research and plan (dev-flow phases 0–2, 2026-10-24)

Status: **v2 of the build plan is §8 (2026-11-13), approved by YK 2026-11-13 ("2": the whole plan as one release).** §0–§2 (brief, research, decisions; YK's yes 2026-10-24) still hold except where §8.2 says otherwise; §3, §6 and §7 were written for the pre-0.6.0 code and are history. Planner of §0–§7: flow-planner on claude-fable-5-1. Every name below was grepped in the repo before it was written; new names are marked *new*.

## 0. Brief

**For whom.** The owner of a repo whose scripts call per-call billed APIs (image and LLM APIs), working with one Claude Code session on a laptop or from a phone (Remote Control). The incident: a batch script spent about RM7.5 on paid image runs with no go from the owner, and one whole batch was wrong (`docs/notes/relay-design.md` line 3, rule 4 at lines 33–36).

**Scope, locked by YK (2026-10-24, `docs/STATUS.md` step 4).** A call to a per-call paid API — `api.openai.com`, `api.stability.ai`, `api.replicate.com`, `fal.run`, `generativelanguage.googleapis.com`, `api.ideogram.ai`, and the like — is **denied until the owner gives a go for that script**, with a **cap on runs** and **one test output before a batch**. Claude Code runs on the Max plan (`claude -p`, `claude plugin eval`, subagents) are **not** paid calls: nothing asks for those.

**Out of scope (said once).** MCP `paid_tools:` from the design note (needs a second hook matcher and a second process); relay guards (rules 1, 2, 3, 5); measuring money (the hook counts runs, it cannot price a call); a new eval case (the suites prove the hook; an eval needs the CI secret).

**Done means.** The three incident replays pass as tests; `run.sh`'s 126 cases stay green; no new hook process per Bash call; Python 3.9 stdlib only; green on CI's three OSes; the docs name the new adapter keys and the state file.

## 1. Research

### 1a. YK's own work first (`.claude/skills/dev-flow/my-work.md` → yk-brain `lessons.md`, `decisions.md`, `learned/reuse-map.md`)
| Source | Verdict | Why |
|---|---|---|
| decisions 2026-10-15: a Stop gate may only run what a human wrote (adapter or root-owned file) | **reuse as-is** (the principle) | the go must come from a human-authored place: the adapter, or the owner's own typing in this session — never from routing.json, a tool result or a relayed message |
| decisions 2026-10-16: wider secret patterns; only the last 4 MB of a transcript are read | **adapt** | the owner-quote check reads only the tail (4 MB) of the transcript, under a time budget |
| lessons 2026-10-15: a user-level hook and its plugin copy both ran and wrote twice → claim shared state atomically | **reuse as-is** | the run counter claims each `tool_use_id` once with an `O_EXCL` marker, the way `ledger.py` claims `receipt.<agent>.done` (ledger.py:375–383) |
| the incident's script called a per-call image API | **reuse as-is** (as the test fixture) | the first two hosts the fixtures use are `generativelanguage.googleapis.com` and `api.openai.com`, two common per-call image APIs |
| reuse-map: smartuse hooks with tests; `tests/all.sh` one-line gate | **reuse as-is** | the new suite follows `wait-gate-test.sh` (temp HOME, synthetic transcripts from one `mk.py`, state dir asserted equal to ledger's key) |
| `wait-gate.py` `is_human()` (line 304) + `scan()` (line 314) + `INJECTED` (line 81) | **adapt** (copy the rules, own code) | this is the only "did the human type it" logic in the repo; **there is no owner-quote check yet** — the design note (relay-design line 13) describes one that was never built (grep `owner.quote` → design notes only) |
| `bash-guard.py` `strip_heredocs` / `words` / `opener_line` (lines 60–149) | **reuse as-is** | needed to see a heredoc body that an interpreter runs (`python3 - <<EOF`) as code for the paid scan |
| `ledger.py` `project_key` / `state_dir` / `write_json` / `native_path` (lines 89–102, 169–188, 214–228) | **adapt** (copy, assert equal in the test, as wait-gate did) | bash-guard imports nothing from the other hooks; `until-done.py` `guard_rules()` exec's bash-guard's source (until-done.py:109–117), so bash-guard must stay import-free |
| `file-guard.py` `HUMAN_ONLY` (line 10) and bash-guard's human-only rule (line 37) | **reuse as-is**, extend by one file name | the counter file gets the same protection as the adapter |

### 1b. Outside: reuse before build
| Candidate | Gives | Licence · maintenance | Fit | Verdict |
|---|---|---|---|---|
| Vendor hard limits: OpenAI project "Enforce a hard limit" (official spend-limits guide; requests fail with 429 once reached); Replicate monthly spend limit (deprecated for new customers since 2025-07-01, existing accounts keep it); fal: account locks when the credit balance drops below the lock threshold; Gemini: billing budgets alert, no hard cap | a money ceiling the hook cannot give | free, vendor-maintained | a backstop per vendor account, not per script, no "ask first", no test-first | **reuse as the backstop** — the docs tell the owner to set them; the hook is the per-script "ask first" |
| Claude Code permission deny rules in `settings.json`, e.g. `Bash(curl *api.openai.com*)` | a prefix/glob deny on the command text | built-in | cannot see inside a script; no go, no counter, no test-first; off in bypass mode | **avoid** for the guard; fine as an extra line in `docs/research/security-profiles.md` later |
| PreToolUse `permissionDecision: "ask"` (hooks reference: "prompts the user to confirm"; "forces a permission prompt in auto mode"; in `-p` the reason goes to Claude as a denial) | the owner's click on the phone | built-in | no cap, no run count, no test-first; a batch loop is ten clicks; bypass-mode behaviour not documented | **avoid** as the go; **deny with a reason** stays (the existing guards' shape, works in every mode) |
| Not giving the agent the key (keys outside the env; `.env` unreadable) | nothing can be spent | free | the incident's script reads its own `.env`; the owner wants "ask first", not "never" | **avoid** as the mechanism; mention in SECURITY.md as the stronger setting for repos that never need a paid run |
| Build: a `paid` family inside `bash-guard.py` (regexes + a counter + the owner-quote check), stdlib | the exact rule | MIT (this repo); ours to maintain | the design note's build order item 1 | **build** — about 200 lines plus tests |

Facts checked today (shapes only, no content read): on Claude Code 2.1.310 a message from another session arrives as a `queue-operation` record and as an `attachment` `queued_command` whose `prompt` starts with `<cross-session-message from-session=…>`, with `isMeta: true` and a `<system-reminder>` line "Another Claude session sent a message while you were working:". The 2.1.308 shape (`wait-gate.py` line 83) was a `user` record starting "Another Claude session sent a message:" with `turnOrigin` `peer`. Human prompts still carry `turnOrigin: "human"`. The owner-quote check must exclude **both** shapes. The hooks reference confirms every hook gets `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`; PreToolUse adds `tool_name`, `tool_input`, `tool_use_id` (and `agent_id` inside a subagent); a PreToolUse hook that times out **does not block** the call, so every scan here runs under its own budget and denies on overrun.

## 2. Decisions made (candidates → pick → why)

**D1. Where the go lives.** (a) a `paid:` line in the human-only adapter `.claude/smartuse.local.md` — the model cannot write it (file-guard line 10, bash-guard line 37); (b) a line the owner types in this session, `paid go: …`, verified against the transcript by the owner-quote check (new); (c) `permissionDecision: "ask"`. **Pick: (a) and (b), (a) first.** (a) ships value on its own and works for subagents and headless runs. (b) is the phone path (the owner cannot edit a file from Remote Control), it is what the incident replay "go inside a relayed message → denied" tests, and it is the primitive rules 3 and 5 reuse later. (c) carries no cap and no count. Precedence: `paid stop` typed in session always wins; else the adapter go for that script; else the newest in-session go for that script. Both forms share one grammar and one parser.

**D2. One test output first, without knowing each script's flags.** (a) the adapter names the count flag per script (the design's form); (b) count-agnostic: run 1 is the test whatever its flags; (c) generic count-flag detection, with the go able to name the flag or say `count none`. **Pick: (c).** (b) fails the incident (one invocation made the whole batch). (a) alone makes every script a config chore. (c): run 1 after a go must carry a count-ish flag with value 1 — one of `-n`, `-N`, `--n`, `--count`, `--num`, `--num-images`, `--num_images`, `--num-outputs`, `--num_outputs`, `--images`, `--samples`, `--batch`, `--batch-size`, `--runs`, `--iterations`, forms `--n 1`, `--n=1`, `-n1` — or the flag the go names (`count --images`); a go that says `count none` declares the script makes one output per run. No count flag seen and none declared → run 1 is denied with the fix in the reason.

**D3. What counts as a paid call (and its cost).** Two layers, no new process, no `.env` read. **Layer 1 (every Bash call, regex only, microseconds):** a *caller* word (`curl`, `wget`, `http`, `xh`, `python`, `python3`, `py`, `node`, `deno`, `bun`, `uv`, `npx`, `bash`, `sh`) followed in the same command segment by a paid host, or a `https?://…<host>` URL anywhere, or one of the **named** key variables, or an SDK import in inline code (`import openai`, `from openai`, `import replicate`, `import fal_client`, `from google import genai`, `import google.generativeai`, `import anthropic`, `from stability_sdk`, `require("openai")`, `@fal-ai/client`, `@google/genai`, `@google/generative-ai`, `@anthropic-ai/sdk`). Heredoc bodies stay data **except** when the opener runs an interpreter from stdin (`python3 - <<EOF`, `node - <<EOF`): that body is scanned (reuse `opener_line` / `words`). **Layer 2 (only when the command runs a script file by path — `python x.py`, `py -3 x.py`, `node x.js`, `npx tsx x.ts`, `bash x.sh`, `uv run x.py`, `./x.py`):** the file is resolved against the event's `cwd`, read once (first 256 KB, UTF-8 with replacement, files over 1 MB skipped) and searched with the same patterns plus `os.environ[...]` / `getenv(...)` / `process.env.<KEY>` of a named key. One `stat` and one read, 1–5 ms; nothing is read on a command without a script path. **The `.env` scan from the design note is dropped**: a script that uses the key names it in its own source, so the key *name* in the source is the signal; reading `.env` would put a secrets file through a hook and flag every script in a repo whose root holds a key. Known gap, stated in the docs: a helper module that holds the call (`from lib.render import polish`) is not followed; the adapter's `paid_scripts:` (*new*, a comma list of names always treated as paid) and any `paid:` line close it for a known script.

**D4. False positives, by construction.** Named keys only: `OPENAI_API_KEY`, `STABILITY_API_KEY`, `STABILITY_KEY`, `REPLICATE_API_TOKEN`, `FAL_KEY`, `FAL_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_GENAI_API_KEY`, `IDEOGRAM_API_KEY`, `ANTHROPIC_API_KEY` (the last one: D-YK1). Never `*_TOKEN` or `*_API_KEY` as a family (`GH_TOKEN`, `NPM_TOKEN`, `SENDGRID_API_KEY` are not per-call image/LLM bills). Hosts as whole host names with boundaries (`fal.run` must not match `fal.runtime.io`; `queue.fal.run` counts). A host after `grep`, `cat`, `echo`, `rg`, `git commit -m` is a mention, not a call. `export OPENAI_API_KEY=…` alone is preparation, allowed; the run that follows is caught by layer 2. `claude -p …`, `claude plugin eval …`, `bench/ab.sh`, `npm test` are allowed (checked: no file under `plugins/`, `bench/` or `scripts/` names a paid key or host; only `.github/workflows/evals.yml` and the design note do).

**D5. Fail-open or fail-closed.** The existing guards fail open on their own errors (bash-guard.py:177–179; until-done "any error → allow"). Here: **detection** errors (unreadable script, bad stdin) → not seen → allow, as today. **After a positive detection**, a verification error (transcript missing or over the 3 s budget, adapter unreadable, counter not writable) → **deny** with the reason "could not verify the go: put it in .claude/smartuse.local.md". One deliberate asymmetry, written in the file header and in SECURITY.md: a missed tool call costs a turn; a missed deny costs money. The harness timeout (10 s, hooks.json line 11) never decides: the scan's own budget does.

**D6. No second process; where the code lives.** The family is a section of `bash-guard.py` (hooks.json unchanged; the test asserts it). Not a new `RULES` entry: `until-done.py` runs `RULES` over the `check:` command (until-done.py:158–160) and a stateful rule there would be wrong. `main()` calls `paid_verdict(data, cmd, text)` after the `RULES` loop. The regexes compile at import. Transcript scan: only on a paid hit with no adapter go; the last 4 MB of the file; 3 s budget; a subagent's `transcript_path` (`…/<sid>/subagents/agent-*.jsonl`, the shape ledger.py:285 uses) also looks in the parent `…/<sid>.jsonl` — to be confirmed live in F3 (the reference does not say which path a subagent's hook gets).

**D7. State and tamper.** `~/.claude/smartuse/projects/<key>/paid-runs.json` (*new*): `{"<go-id>": {script, runs, cap, count, used, test_ok, stopped, go_from: "adapter" | "session:<uuid>", first_at, last_at}}`, atomic write (copy of `write_json`), one claim marker `paid.<tool_use_id>.done` per counted call (removed when the go closes). `<go-id>` = `adapter:` + sha1 of the normalised go line, or `session:` + the go record's uuid; a changed line or a new typed go is a new counter (that is how the owner re-goes). The run is counted when it is **allowed** (PreToolUse sees no result): a crashed run burns one of N; stated in the docs. The file is human-only like the adapter: bash-guard's rule at line 37 gains `\brm\b` in its verb list and `paid-runs\.json` in its file list; `file-guard.py` `HUMAN_ONLY` gains `smartuse/projects/[^/]+/paid-runs\.json` (Write/Edit under `~/.claude` already prompt in default mode, ledger.py:36–37; the rule covers bypass mode).

**D8. Grammar (one parser, both places).** Adapter (frontmatter or body, regex-read like `check:` at until-done.py:105): one line `paid: render.py x 10, cap RM5` or a list under `paid:` with `  - render.py x 10, cap RM5, count --images`; `paid_scripts: render.py, polish.py`; `paid_hosts: api.example-images.com` (*new*, extra hosts). In session, typed by the owner, at the start of a line: `paid go: render.py x 10, cap RM5[, count <flag> | count none][, test ok]`, `test ok[: render.py]`, `paid stop[: render.py]`. `x`, `×` and `*` all mean times; `runs` is a whole number ≥ 1 and is the enforced cap; `cap <amount>` is free text (the owner's money ceiling, echoed in every reason, never measured). The script is matched by file name (basename, case-insensitive, either slash); a bare `curl …` call matches a go for `curl`.

**D9. The reasons the model reads** (exact prefixes asserted by the tests): `bash-guard: paid call (<signal>) — no go from the owner for <script>. The owner types in this session: "paid go: <script> x <runs>, cap <amount>" (or adds "paid: <script> x <runs>, cap <amount>" to .claude/smartuse.local.md). Nothing was spent.` · `… — first run after the go must make ONE output: set the count flag to 1 (seen --images 6 | no count flag; the owner can add "count <flag>" or "count none" to the go).` · `… — run 1 of <runs> is done; the batch waits for the owner's "test ok" (typed in this session). Show the owner the one output first.` · `… — the go for <script> is used up (<runs> of <runs>). Ask the owner for a new go.` · `… — the owner said "paid stop".` · `… — could not verify the go (<why>); put it in .claude/smartuse.local.md. Nothing was spent.` `<signal>` is one of `host api.openai.com on the command line`, `OPENAI_API_KEY in render.py`, `import openai in render.py`, `render.py is in paid_scripts`. An allowed run prints nothing (the suites' convention: output = deny).

**D10. Version.** 0.6.0, after 0.5.0 ships (STATUS order: step 3 before step 4). CHANGELOG gets `## 0.6.0 — in progress`.

## 3. Plan — features in build order (each ≤ 1 day) — history: replaced by §8 for the build on 0.6.1

Common to every feature — **must not change:** `run.sh` 126 cases green; `hooks.json` byte-identical (one Bash PreToolUse command, timeout 10); `RULES` strings and order untouched except the one human-only rule; heredoc and `STATE_CALL` behaviour; Python 3.9 stdlib only, no `subprocess`, no network, no import between hooks; prints nothing on allow and the same deny JSON shape (bash-guard.py:186–189); state dir key equal to ledger.py's; Windows Git Bash (`native_path` for `cwd` and `transcript_path`, cp1252 stdin case); no `.env` is ever opened. **Test command:** `bash plugins/smartuse/hooks/tests/run.sh` and `bash plugins/smartuse/hooks/tests/paid-guard-test.sh`; the gate line from `bash plugins/smartuse/hooks/tests/all.sh | tail -1`.

### F1 — detect a paid call and deny it without a go; the adapter go (piece A, files: `hooks/bash-guard.py`, `hooks/tests/run.sh`, `hooks/tests/paid-guard-test.sh` new, `hooks/tests/all.sh`, `.github/workflows/ci.yml`)
Depends on: nothing.
- **Acceptance (what a user does):** the owner asks Claude to "run render.py for 6 images" in a repo where `render.py` imports `openai`; the call is denied before it runs, the reason names `import openai in render.py` and the exact `paid go:` line to type; nothing is spent. The owner adds `paid: render.py x 10, cap RM5` to `.claude/smartuse.local.md`; the same ask now passes F1 (F2 adds the count rule). `grep api.openai.com src/`, `cat docs/notes.md`, `claude -p "hi"`, `npm test`, `git commit -m "call api.openai.com later"` are not touched.
- **Unit tests (run.sh, text only, no state; about 36):** deny: `curl https://api.openai.com/v1/images/generations -d …`; `python render.py` where the fixture file names each host / each named key / each SDK import (one case per host and per key name, Python and JS forms); `py -3 render.py`, `node render.js`, `npx tsx render.ts`, `bash render.sh` (curl to a host inside), `uv run render.py`, `./render.py`; `OPENAI_API_KEY=sk-x python x.py`; `python3 -c "import openai; …"`; `python3 - <<'EOF'\nimport openai\nEOF`; a Windows path `python C:\p\render.py`; a script listed in `paid_scripts:`; stdin in cp1252 with a non-ASCII path. Allow: `grep -rn api.openai.com src/`; `cat docs/openai-notes.md`; `echo "see api.openai.com"`; `git commit -m "uses api.openai.com"`; `export OPENAI_API_KEY=x`; `echo $GH_TOKEN`; `curl -s https://api.github.com/repos/x/y`; `claude -p "hi"`; `claude plugin eval plugins/smartuse`; `bash bench/ab.sh`; `npm test`; `python x.py` whose source has no paid name; a script over 1 MB; a missing script path; `curl https://fal.runtime.example/`; `cat > render.py <<'EOF'\nimport openai\nEOF` (a write, not a run). **Incident replay 1:** the batch command (`python render.py --images 6` with the fixture's Gemini key in its source), no go anywhere → **denied at the first call**, reason starts `bash-guard: paid call`.
- **Integration test (paid-guard-test.sh):** temp HOME + project dir + `.claude/smartuse.local.md` with one `paid:` line → the first `python render.py --images 1` passes and `paid-runs.json` holds one entry with `used: 1`, `go_from: adapter`; the state dir equals the key the test computes with ledger's rule; `hooks.json` still has exactly one Bash PreToolUse command.
- **Interactive scenario:** on the laptop (Git Bash), a scratch repo with a stub `render.py` that imports `openai` and only prints "would call"; ask Claude to run it with 6 images → the deny reason appears in the reply and Claude asks the owner for the go; add the adapter line → it runs. Screenshot of both replies to `scratch/`.
- **Docs touched by this feature:** none yet (F4).

### F2 — the run cap, one test output first, the counter's protection (piece A, files: `hooks/bash-guard.py`, `hooks/file-guard.py`, `hooks/tests/run.sh`, `hooks/tests/file-guard-test.sh`, `hooks/tests/paid-guard-test.sh`)
Depends on: F1.
- **Acceptance:** with `paid: render.py x 10, cap RM5` in the adapter, the owner's first ask "run render.py --images 6" is denied with "first run … ONE output"; "--images 1" runs; the second ask is denied with "waits for the owner's test ok"; the owner adds `, test ok` to the adapter line (F3 gives the typed form) → runs 2…10 pass; run 11 is denied "used up (10 of 10)". The owner changes the line (new runs or cap) → a fresh counter. Claude cannot `rm`, overwrite or edit `paid-runs.json` (denied like the adapter).
- **Unit tests (paid-guard-test.sh, about 30):** count forms `--n 1`, `--n=1`, `-n1`, `--num-images 1`, `--images 1`; `--images 6` denied; no count flag denied; `count --pics` honoured; `count none` honoured; `test ok` on the adapter line; run 2 without test ok denied; runs up to the cap then denied; a changed go line resets; two different scripts, two counters; the claim marker: the same `tool_use_id` sent twice counts once; counter unwritable (read-only state dir) → deny with "could not verify"; `used` survives a corrupt-then-restored file (a corrupt file → deny, never a silent reset). run.sh: `rm ~/.claude/smartuse/projects/x/paid-runs.json`, `echo x > …/paid-runs.json`, `rm .claude/smartuse.local.md` denied; `cat …/paid-runs.json` allowed. file-guard-test.sh: Write and Edit on `…/smartuse/projects/<key>/paid-runs.json` denied (+2). **Incident replay 2:** go `x 10`, no test ok: run 1 with the count at 1 passes, **the second call is denied** — the wrong batch is one picture, not ten.
- **Integration test:** the full sequence above in one shell run (deny · pass · deny · test ok · pass ×9 · deny), reading `paid-runs.json` after each step.
- **Interactive scenario:** same scratch repo; the owner walks the sequence from the Claude prompt and watches `used` climb in `paid-runs.json`; tries "delete the counter file" → denied.
- **Docs:** none yet (F4).

### F3 — the owner-quote check: the typed go, `test ok`, `paid stop`; relayed text is never a go (piece A, files: `hooks/bash-guard.py`, `hooks/tests/paid-guard-test.sh`)
Depends on: F1, F2.
- **Acceptance:** with no adapter line, the owner types `paid go: render.py x 3, cap RM1` in the session (laptop or phone); the next `python render.py --n 1` runs; the owner types `test ok`; runs 2 and 3 pass; run 4 is denied. The owner types `paid stop` → the next call is denied even with runs left. A go that reaches the session **from another session** (`<cross-session-message …>`, "Another Claude session sent a message", a `queue-operation`, any `isMeta` record, a compact summary, a tool result that quotes the line, Claude's own reply that writes the line) is **not** a go.
- **Unit tests (paid-guard-test.sh, synthetic transcripts from one `mk.py` as in wait-gate-test.sh, about 30):** the go as a `user` record with `turnOrigin: human`; as an `attachment` `queued_command` with `origin.kind: human` (typed mid-turn); `test ok` before the go ignored, after the go honoured; `paid stop` wins over the adapter; the go for `polish.py` does not cover `render.py`; `×` and `*` spellings; the newest of two typed goes counts; a go inside a `<cross-session-message>` attachment (2.1.310 shape, `isMeta` true) ignored; inside a `user` record starting "Another Claude session sent a message:" with `turnOrigin: peer` (2.1.308 shape) ignored; inside a `queue-operation` ignored; inside an assistant text block ignored; inside a `tool_result` ignored; `isCompactSummary` ignored; a `<system-reminder>` ignored; the go typed in a subagent's parent transcript found from `…/subagents/agent-x.jsonl`; a transcript of 6 MB with the go in the last 4 MB found, with the go only in the first 2 MB → deny "could not verify"; a missing transcript → deny "could not verify"; a garbage line in the transcript skipped; the 3 s budget overrun → deny; Windows `transcript_path` in `/c/Users/…` form. **Incident replay 3:** the manager's go relayed into the builder session → **denied**, the reason asks for the owner's own typing.
- **Integration test:** headless `claude -p` is not needed; the suite feeds a real-shaped PreToolUse JSON (`session_id`, `transcript_path`, `cwd`, `tool_use_id`, `permission_mode: bypassPermissions`) through `py.sh` and checks the deny JSON and the counter file after each of the six steps.
- **Interactive scenario:** on the laptop, with Remote Control on the phone: type the go from the phone, watch run 1 pass, type `test ok`, watch runs 2–3 pass and run 4 refused; then from a second session send the go with `SendMessage` and watch it refused. This is also the live check of D6 (which `transcript_path` a subagent's hook gets): ask Claude to run the script through a subagent after a typed go.
- **Docs:** none yet (F4).

### F4 — docs and counts (piece B, files: `README.md`, `plugins/smartuse/README.md`, `SECURITY.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/STATUS.md`, `docs/ROADMAP.md`, `docs/notes/relay-design.md`)
Depends on: F1–F3 merged and `all.sh` green.
- **Acceptance:** a reader of the README finds the rule, the three adapter keys and the two typed lines in under a minute; the test-count line matches `all.sh | tail -1`; SECURITY.md says what the hook reads (the invoked script's first 256 KB; the last 4 MB of the transcript on a paid hit; never `.env`, never the network) and the fail-closed asymmetry; the vendor hard limits are named as the backstop.
- **Edits, by line:** README.md:36 (bash-guard row: add "paid-API calls without the owner's go, a run cap and one test output first"; replace the stale "94 regression cases" with the new count), :62 (counts line, add `paid N`), :78 (adapter keys `paid`, `paid_scripts`, `paid_hosts`), :82 (state files `paid-runs.json`, `paid.<id>.done`), Honest limits (one bullet: a helper module hides the call; runs are counted, money is not). plugins/smartuse/README.md:10 (hooks sentence). SECURITY.md paragraph 1 and Known limits. CHANGELOG.md: `## 0.6.0 — in progress` entry with the gate line. CONTRIBUTING.md:7 (suite list + `paid N` in the summary line). STATUS.md step 4 → done with the commit id; ROADMAP.md:42 ticked; relay-design.md line 5 and the rule 4 heading marked BUILT with the date, the `.env` and `paid_tools:` deviations noted.
- **Unit / integration / interactive:** `all.sh -q` prints the new summary line; CI green on ubuntu (3.9 and 3.12), macOS, Windows; `claude plugin validate --strict plugins/smartuse` passes; a person reads the README section aloud to the LCD test.

## 4. Decisions that need YK (recommendation first)
**Answered 2026-10-24: YK said yes to the plan and to all five recommendations** (Anthropic API key calls count as paid; they are not part of the Max plan).
- **D-YK1 `api.anthropic.com` and `ANTHROPIC_API_KEY` in the paid list.** Recommend **yes**: a script that calls the API with a key bills per call even on a Max plan; `claude -p`, `claude plugin eval` and subagents never name them, so they stay free. Alternative: leave them out and add later on first sight.
- **D-YK2 Keep the typed (in-session) go in 1.0.** Recommend **yes** (F3, about one day): it is the phone path and the incident's third replay. Alternative: adapter-only for 0.6.0, F3 in 0.7.0.
- **D-YK3 Money is echoed, not measured.** Recommend **accept**, and set the vendor's hard limit as the backstop (OpenAI project hard limit; fal's lock threshold; Replicate's existing-account limit). Alternative: require `cap` to be a number and multiply by a per-script price in the adapter — more config, still an estimate.
- **D-YK4 Ship as 0.6.0 after 0.5.0.** Recommend **yes** (STATUS order). Alternative: fold into 0.5.0 if its eval re-run slips past the build.
- **D-YK5 Counter file protected in file-guard too (+1 regex, +2 cases).** Recommend **yes**: it is the only line that covers bypass mode.

## 5. Risks
- A subagent's PreToolUse may get the agent's own `transcript_path`; the typed go is then found only through the parent lookup (D6), confirmed live in F3. If the parent is not derivable, the adapter form still covers subagents.
- The laptop's Python start (0.4–3.6 s) plus a 3 s scan budget stays under the 10 s hook timeout, but a very slow start on a paid hit with a 4 MB tail could approach it; measured on the laptop in F3 before claiming.
- Real transcript shapes changed between 2.1.308 and 2.1.310 (peer messages); the check keys on fields (`isMeta`, `turnOrigin`, `origin.kind`, record type) and on both text markers, and the test fixtures carry both shapes.
- A `cap` typed as "RM5" is not enforced by anything in the hook; the docs say so in the first sentence of the section.

## 6. Files and counts
Piece A (code, 7 files): `plugins/smartuse/hooks/bash-guard.py`, `plugins/smartuse/hooks/file-guard.py`, `plugins/smartuse/hooks/tests/run.sh`, `plugins/smartuse/hooks/tests/file-guard-test.sh`, `plugins/smartuse/hooks/tests/paid-guard-test.sh` (new), `plugins/smartuse/hooks/tests/all.sh` (`paid` added to `NAMES`), `.github/workflows/ci.yml` (one step). Piece B (docs, 8 files): listed under F4. Test estimate: run.sh 126 → about 162; paid-guard-test.sh about 60; file-guard 10 → 12; roughly 98 new cases, three of them the incident replays.

## 7. Resume state (moved from STATUS step 4, 2026-10-25) — history: the branch ids and the resume steps are replaced by §8.1 and §8.5
Ships as 0.6.0, after 0.5.1. **Local branches on the laptop only (not pushed).** First rebase both onto the 0.5.1 dev branch (conflicts and the resolution rule: `py-cache-fix-plan.md` §7).
- `paid-guard` @ d88444c — F1 (detect + deny without a go, adapter `paid:`), F2 (run cap, one test output first, `test ok`, counter lock + protection) and a hardening pass from the commit security reviews (every paid hit checked, wrappers unwrapped, first 256 KB of any script scanned, literal args on run 1, loops denied). Gate on the laptop: `run 278 · paid-guard 328 · file-guard 13 · until-done 40`, all ALL PASS.
- `paid-f3` @ 83fcf6e (worktree `.claude/worktrees/f3`) — F3 WIP, **stopped mid-build, untested**: the owner-quote check (typed `paid go:` / `test ok` / `paid stop` from the transcript, relayed or meta records never a go) + fail-closed review fixes A (non-literal count args deny), B (scan `env -S` / `watch` / `su -c` strings), C (any loop word in a paid command denies), D (transcripts `.claude/projects/**/*.jsonl` human-only in bash-guard and file-guard — a forged "typed" line was the review's finding). A review of 83fcf6e adds two items for D: file-guard should also match `os.path.realpath(path)` (a symlink to a transcript), and bash-guard's transcript rule should also catch `ln`, `dd`, `perl`, `node`, `ruby`, `awk`, `install` writes. A second review of 83fcf6e: (E) persist `stopped` in paid-runs.json the first time a `paid stop` is seen, so a stop that scrolls out of the 4 MB tail cannot age out; (F) strip `<bash-stdout>` / `<bash-stderr>` / `<local-command-*>` blocks (any tool-output markers) before matching a typed line; (G) design option for the planner: record typed go / test ok / stop lines from the UserPromptSubmit hook (only real prompts fire it — verify whether peer messages do) instead of reading the writable transcript back. Resume: finish F3 in that worktree, run run.sh, paid-guard-test.sh, file-guard-test.sh, until-done-test.sh one at a time (paid-guard ~10 min), commit, ff `paid-guard`, then F4 docs.
- F4 docs must state the limits: a go matches by file name; deleting the state dir resets the counter; only a script's first 256 KB is read; helper modules are not followed; the guard stops honest mistakes, not a model that forges approval — vendor hard spend limits are the backstop. Also: plan D3 still says "files over 1 MB skipped" (now: first 256 KB always read).

## 8. v2 — the 0.7.0 build plan on the 0.6.1 code (dev-flow phases 0–2, 2026-11-13)

Status: **approved 2026-11-13: YK picked "2", the whole plan F0–F10 as one 0.7.0 (decisions in §8.9).** Planner: flow-planner on claude-fable-5-2. Scope: the four lines of ROADMAP "0.7.0" plus two findings from the automated review of the 0.6.1 push. Not in it: the 0.6.2 list, a dispatcher, MCP `paid_tools:`, relay rules 1, 2, 3 and 5. Feature numbers here are new: old F1 + F2 + hardening → F3, old F3 → F5, old F4 → F10. Existing names and lines were grepped on the 0.6.1 code today; new names are marked *new*. A weakness is described by its class, never by the steps to use it.

### 8.0 What this release is, and how each line is checked
| What | 0.6.1 | 0.7.0 | Checked by |
|---|---|---|---|
| A script that calls a per-call paid API | runs | denied until the owner's go, where the guard is armed (V5) | incident replays 1–3, `paid-guard-test.sh` |
| A go from the phone | none | a `paid go:` line the owner types | F5, the live pass |
| The guard on the owner's real repo | not tried | a replay table of its real commands, nothing run | F4 |
| A shell command that names a Claude Code settings file | denied for a list of writers | allowed for a list of readers, denied otherwise | `run.sh`, method D |
| A download piped into `python -m json.tool` | any words after the module accepted | flags only | `run.sh` |
| PowerShell tool: download-then-run, delete of a root, writes to the owner's files | not covered | covered | `run.sh` |
| Seconds Claude waits per Bash call | 0.41 | no measurable change (at most +0.03 s) | method M |

### 8.1 Facts verified today (2026-11-13)
- **Base.** The build starts from `origin/main` after a fetch: the 0.6.1 release commit `f1f4ea5` plus docs-only commits. The local branch `main` is older and nothing branches from it. A builder's first command is `git log -1`.
- **The paid branches** are local and unpushed: `paid-guard` `19c7e45` (old F1, F2, hardening) and `paid-f3` `040316c` (old F3, work in progress). They fork from `1a1e62c`, before 0.6.0.
- `bash-guard.py` is 1,624 lines on main and 930 on `paid-f3` (a 0.5.1 file of about 190 lines plus the paid block).
- Both sides put their large section right after `strip_state_args`, and both rewrote `deny()` and `main()`.
- The paid block defines `native_path` and `adapter_list` a second time. 0.6.1 has its own, hardened ones (`bash-guard.py:257`, `:280`). In a text merge the later definition wins for the whole file, the fresh-source gate included.
- The paid branch edited the `human-only` entry of `RULES` without the steps `light-fast-plan.md` §6 now asks for.
- Three structure checks in the branch's `paid-guard-test.sh` are false on 0.6.1: a matcher equal to `Bash` (now `Bash|PowerShell`, `hooks.json:6`), an import allow list, and `len(RULES) == 12` (now 16).
- `paid-f3`'s suite has 18 sections and none for the typed go: old F3 has code and no cases.
- The paid block serves the `Bash` tool only. 0.6.1's `_main()` serves `Bash` and `PowerShell` (`bash-guard.py:1569`), and a Monitor command reaches the hook as a Bash call (`recall-security-fix-plan.md`; a version fact).
- `until-done.py:109–115` runs this file without `main()` and takes `RULES` as pairs. Waivers and the paid check are not part of what it sees.
- Hooks reference (code.claude.com/docs/en/hooks, read today):
  - `UserPromptSubmit` also fires for a scheduled task, a background subagent reporting back, and a message another session sends. Its input has no origin field.
  - `onFailure: "block"` needs v2.1.295. A failure is a hook that cannot start, exits with a code other than 0 or 2, times out or prints invalid output. It has no effect on Stop hooks and background hooks.
  - A PreToolUse hook that times out does not block the call.
- `skills/reply-style/SKILL.md:30` sets `outputStyle` in a settings file with a small Python program run through Bash. `skills/status/SKILL.md:35` makes its settings edit with the Edit tool.
- `run.sh` has 11 allow cases that name a Claude Code settings path (`:447–453`, `:502–506`, `:514–515`). Each is a reader or a copy from the file.
- The pinned limit on ROADMAP 0.7.0's last line is two cases, `run.sh:632` and `fresh-gate-test.sh:853`: a quote character in a `#` comment pairs with one in a later comment and hides the lines between.
- **The owner's real image-pipeline repo** (files read today, nothing run): 13 Python files name a paid host, key or SDK: 7 client and UI files and 6 test checks. The entry scripts that start a batch or a paid read name none, because the call sits in a helper module they load by name. Four client scripts pay unless they get a dry-run flag; three scripts pay only with a pay flag; a mock flag exists too. The guard as built on the branch would deny the test checks and every dry run, and would not see the entry scripts.

### 8.2 Decisions made in v2 (defaults; the owner may veto any)
- **V1. Re-port, do not rebase or cherry-pick.** The new branch starts from main. The paid block and its two test files come over by content; the four old commits are not replayed. Why:
  - every old commit conflicts in the same places (the section after `strip_state_args`, `deny()`, `main()`, the end of `run.sh`, `all.sh`, `file-guard.py`);
  - a text merge would keep the block's second `native_path` and `adapter_list`, which silently replace 0.6.1's for the fresh-source gate;
  - the branch's `RULES` edit has to be redone under §6 anyway (cases first, differential, timing);
  - with main's file as the base, the frozen names stay byte-identical by construction;
  - the branches were never pushed, so their history carries nothing but their content. What carries over as the contract is the suite: every case of `paid-guard-test.sh` and `paid-cases.txt` green on the new base.
- **V2. Two sources.** The port (F3) takes `paid-guard` `19c7e45`: its suite was green before the branch was moved on 2026-11-06 (§7), and F0 runs it once more on that commit to fix the count the port must reach. The typed go (F5) uses the difference `19c7e45..040316c` as a reference, after its cases are written.
- **V3. The block moves byte for byte, then is adapted in small edits.** A splice script in the gitignored scratch folder copies the block; the proof is that the block's hash equals the branch's. The same script gives every top-level name in the block the prefix `paid_` / `PAID_` (the block has its own small tokenizer; it must not be mixed up with `FLEX` and `WRAPPERS`). Every later change is an Edit-tool edit, one concern each.
- **V4. `paid` is a named gate, not a `RULES` entry** (D6 stands). `GATE_NAMES = ("paid",)` *new* sits beside `RULE_NAMES`, which keeps the length of `RULES`. Every paid reason ends `[rule paid]`.
- **V5. Where `paid` sits (needs the owner, D-YK6; this is the plan's default).**
  - Strict: always on.
  - Light, the default level: on in a project whose human-only adapter has a paid line (`paid:`, `paid_scripts:`, `paid_hosts:`, `paid_free:`, or the plain `paid_guard: on` *new*). The fresh-source gate is armed the same way, by `sources:`.
  - `paid` can be named in Rules off (light only). It is not on the floor.
  - Why not "on for everyone": the scope of 2026-10-24 predates the levels. Every script that imports an LLM SDK is a hit, so a developer of an LLM app would be denied on each run of each script. The 1.0 bar says light never blocks a turn by mistake.
- **V6. The files the go depends on are on the floor, behind a reader allow list.** The counter and the session transcripts get one new always-on rule, `owner-file` *new*, built with F2's mechanism. The branch's widening of `human-only`'s list of writers is not replayed: a list of writers is never complete.
- **V7. The paid check runs last in `_main()`:** after `RULES` and after the fresh-source gate. A run is counted only when every other check has allowed the call.
- **V8. One deadline.** The paid check works inside the deadline `_main()` already starts (`BUDGET_S`, from the hook's start). Past it, a call already seen as paid is denied. A second budget on top would pass the 10 s hook timeout on a slow start.
- **V9. No cost on an ordinary command.** No new top-level import (`hashlib` and `pathlib` are imported inside the paid path). A linear first look ends the paid path for a command with no interpreter word, no script file and no paid word. In light with no paid line, the paid path is one look at the adapter text.
- **V10. Heredocs and unreadable commands.** The paid scan runs the `HEREDOC` pattern only under the scan cap (`many_heredocs`); over it the text is read as it stands. A command `complexity()` tags is denied only when it also holds a paid word.
- **V11. The typed go is read from the transcript, as built on `paid-f3`.** Option G of §7 (record typed lines from `UserPromptSubmit`) is closed: that event also fires for turns the owner did not type and has no origin field (§8.1). The transcript record has one.
- **V12. Settings files: a new rule beside `config-switch`, not a change to it.** `settings-file` *new* (floor) matches a command that names a settings path; its waiver allows readers. `config-switch` stays byte-identical, so no existing case changes its reason.
- **V13. PowerShell parity is plain `RULES` entries with their own names** (`ps-download-exec`, `ps-rm-root` *new*). They run on both tools: a PowerShell command started from Bash is the same harm.
- **V14. The comment fix gets one try.** If method D shows a flip that is not on its list, the feature is reverted and the limit stays pinned.
- **V15. No new hook, no new process.** `hooks.json` stays byte-identical. The version is 0.7.0.

### 8.3 Research
**Own work first** (lessons, decisions and the reuse map of the owner's notes; the code in this repo).
| Source | Verdict | Use here |
|---|---|---|
| lesson 2026-10-15: anchor a guard pattern to the segment that writes | adapt | the reader allow list decides per command segment that names the path |
| lesson 2026-10-15: a heredoc body is data unless a shell consumes it; test both shapes | reuse | F2's heredoc cases; V10 |
| lesson 2026-10-16: a token pattern needs a word boundary | reuse | host and key patterns keep their boundaries; one hyphenated-word case each |
| lesson 2026-10-25: a path guard matches every reading and fails closed; each case red on the code before | reuse | F9 uses file-guard's three readings; cases first everywhere |
| lesson 2026-10-25: release text claims what was measured, never an open gap's method | reuse | F10; this section |
| lesson 2026-10-25: profile before naming a speed fix | reuse | V9 is checked by measurement (method M and the in-process cases) before any further tuning |
| lesson 2026-10-26: at most 2–3 heavy jobs; a builder's first command is `git log -1`; review before push | reuse | §8.5 |
| lesson 2026-10-28: synthetic scenarios are regression guards; the done signal is the real job | reuse | F4 |
| lesson 2026-11-11: estimate only the new part | reuse | §8.12 |
| decision 2026-10-15: a gate trusts only what a human wrote | reuse | a go, and a "free run" line, come only from the adapter or the owner's typing |
| decision 2026-10-25: writable state never supplies a command | reuse | the counter holds counts and names |
| 0.6.1 waiver code (`_shell_tokens`, `_text_words`, `command_start`, `waived`) | reuse as-is | the reader allow list is one more waiver |
| `recall.py` `is_human` (`:220`) | avoid as it is | it counts an SDK-sent prompt as human; a go must not |
| `opened_since_compaction` (`bash-guard.py:518`) | adapt | one pass under a deadline with a byte pre-filter: the shape `scan_typed` already has |
| the paid branches | adapt | V1–V3 |
| `paid-guard-rebase-brief.md` | avoid | written for 0.5.1; replaced by V1 |

**Outside: reuse before build.**
| Candidate | Gives | Licence · upkeep | Verdict |
|---|---|---|---|
| Vendor hard spend limits (§1b) | a money ceiling per account | vendor | reuse as the backstop; the docs say so first |
| Claude Code permission rules for the settings files | a deny on a command prefix | built-in | avoid as the mechanism: a prefix rule cannot say "readers only, on this path, in any command"; fine as an extra layer |
| Claude Code's own prompt for file-tool writes into `.claude` | a prompt in default mode | built-in | already in front; it is off in bypass mode and does not cover the shell |
| `onFailure: "block"` | a hook failure blocks the call | built-in, v2.1.295 | avoid in 0.7.0 (D-YK9) |
| `UserPromptSubmit` `prompt` for the typed go | the text of a prompt | built-in | avoid: fires for turns the owner did not type, no origin field |
| `shlex` for comment-aware reading (F8) | a tokenizer that knows `#` | stdlib | avoid: it raises on an open quote and does not keep positions; a short state machine is needed |
| A shell parser from a package index | a full parse | third party | avoid: the hooks are stdlib only |
| A metering proxy in front of the APIs | real money caps per key | third party, needs a running service | avoid: ROADMAP "Not in 1.0" rules out a proxy |
| Build: transplant the paid block; one waiver for readers | the rule as approved | MIT, ours | **build**; about 700 lines already exist with 328 cases |

### 8.4 Features (build order in §8.5)

#### F0 — base, baseline, experiments (0.25 day; the orchestrator and one tester; no repo file changes)
- **What.** Fetch; dev branch `paid-0.7.0` *new* from `origin/main`; worktrees `.claude/worktrees/pg7-a` and `pg7-b`. T2 on the base: each suite's last line is the floor. In a throwaway worktree of `19c7e45`: `paid-guard-test.sh` and `run.sh` once, their last lines kept as the port's reference (a case red there is not a fault of the port). In the `paid-f3` worktree: `git status --short`, so that uncommitted work is seen before F5 reads the difference. Method M "before" on today's Claude Code version. Experiments E1–E5 (§8.10), recording field names only, never content.
- **Acceptance.** The owner reads the baseline numbers, the branch's reference counts and a five-row table of what each experiment showed.
- **Tests.** None. **Must not change.** Every file.

#### F1 — `python -m json.tool`: flags only (0.25 day)
- **Class.** The waiver accepted any words after the module name, and the module's own arguments include file names.
- **What changes.** `_python_data_module` (`bash-guard.py:1430`) accepts after the module name only the module's known flags (`JSON_TOOL_FLAGS` *new*), a number after `--indent`, and a lone `-`.
- **Acceptance.** `curl -s <url> | python -m json.tool` runs, also with `--sort-keys`, `--indent 2` or `--compact`. The same pipeline with any other word after the module name is denied, `[rule pipe-to-shell]`.
- **Unit tests (`run.sh`, red first).** About 6 allow (each flag form, `-`) and 6 deny (one positional word, two, a non-number after `--indent`, an unknown option, a word behind `--`, a PowerShell twin). Cases `:200–217` keep their results. The waiver timing case (`:289`) still passes.
- **Integration test.** Method D: the only flips are the new deny cases.
- **Interactive scenario.** Ask Claude to pretty-print a JSON URL: it runs.
- **Files.** `bash-guard.py`, `run.sh`. **Must not change.** `PY_DATA_MODULES`, `PY_FLAGS`, the `sudo` waiver, every `RULES` string.
- **T1.** `run.sh`.

#### F2 — a settings file is read-only from the shell (0.75 day)
- **Class.** `config-switch` lists the commands that write a settings file. Other kinds of writer exist (download-to-file, copy and sync, block copy, in-place editors, link makers, interpreters), and a list of them is never complete.
- **What changes.**
  - One `RULES` entry after `config-switch`: `settings-file` *new*, on the floor. Its pattern is the settings-path expression `config-switch` already uses (`bash-guard.py:102`) and nothing else. It reads the command as typed, like `config-switch`.
  - `WAIVABLE` gains it. The waiver says yes only when every place the path is named is one of:
    - a plain argument of a reader. `READERS` *new*: `cat head tail less more grep egrep fgrep rg wc ls stat file jq diff cmp test [` and checksum tools; PowerShell `Get-Content gc type Select-String sls Test-Path Get-Item Get-ChildItem dir Get-FileHash`; `git` with a reading subcommand (`GIT_READERS` *new*: `add diff status log show blame ls-files check-ignore commit`); `python -m json.tool` given that one file to read and flags only (never a second file word; F1's flag list); a copy command with the path as a source;
    - text carried by a text-only command (`_text_words`, `bash-guard.py:1409`): a commit message, `echo`, a `gh` body;
    - a line of a data heredoc whose opener only carries text (`cat`, a message).
  - Never waived: an option value or a redirect target (some readers can write to a file an option names); a reader behind `sudo`; any command or process substitution in the text; a text `complexity()` tags or that does not split cleanly.
  - Reason: "a Claude Code settings file is read-only from the shell: use the Edit tool, which is checked value by value. Switching smartuse's guards is the owner's action: /plugin configure or /config".
  - `skills/reply-style/SKILL.md` step 4 sets `outputStyle` with Read and Edit (Write when the file does not exist), as the status skill does.
- **Acceptance.** (1) `cat`, `jq`, `grep`, `git diff` and `git add` on a settings file run; so does a copy of it to a backup. (2) The owner says "set my reply style to bluf": Claude changes the file with the Edit tool and the style is on. (3) Any other command that names the path is denied, `[rule settings-file, always on]`, whatever keys its text names. (4) A commit message that mentions the path runs.
- **Unit tests (`run.sh`, red first).** About 14 deny: one per class above, Bash and PowerShell where both exist, plus the never-waived list. About 14 allow: each kind of reader, the git readers, copy-from, the validate call, text mentions, a data heredoc into a notes file, the reply-style skill's own `grep` line. The 11 existing allows keep their result. Floor: `rules_off=settings-file` changes nothing. The names pin (`run.sh:192–195`) is updated. Timing: 1,000 reader commands that name the path and then one that is not a reader, decided in under 1 s inside the process; the same text without it, allowed in under 1 s.
- **Integration test.** Method D over `run.sh` and `fresh-gate-test.sh`, both tools. Expected flips among existing strings: none. Any flip stops the merge. `until-done-test.sh` stays green (its screen runs the pattern without the waiver, so a `check:` that names a settings file is refused; the docs say so).
- **Interactive scenario.** The four acceptance steps, once in light and once in strict.
- **Files.** `bash-guard.py`, `run.sh`, `skills/reply-style/SKILL.md`. **Must not change.** `config-switch`'s pattern and reason; `file-guard.py`'s `switch_change`; every existing case.
- **T1.** `run.sh`, then `until-done-test.sh`.

#### F3 — the port: detect, deny without a go, the adapter go, the run cap, one test output, the counter (1 day)
- **What changes.**
  - The block of `19c7e45` (V2, V3) goes in before `options()` (`bash-guard.py:1527`), under its own header.
  - Dropped from it: its `native_path` and `adapter_list` (0.6.1's are used). Its adapter read keeps the "unreadable" answer in `paid_adapter` *new*, because an unreadable adapter denies once a call is paid; `adapter_text` is not changed.
  - `_main()`: after the last fresh-source check, when the tool is `Bash` or `PowerShell` and the gate is on (V5), `paid_verdict` runs and `deny(why, "paid")` prints its reason. PowerShell text is read as `_main()` already normalises it; F6 adds the PowerShell cases.
  - V4, V7, V8, V9, V10 as written. In light a detection error allows, as every check does; in strict it denies. After a call is seen as paid, a verification error denies at both levels (D5).
  - `owner-file` *new* (V6): one `RULES` entry, on the floor, for `paid-runs.json`, its lock and claim markers. Same waiver as F2: readers only. Reason: "owner-only file (it records the paid runs the owner allowed): the shell may read it, nothing else. Ask the owner."
  - Tests: the two files from `19c7e45`. In `paid-guard-test.sh` the three structure checks are re-pointed (matcher `Bash|PowerShell`; the 0.6.1 import list plus the two in-function imports; `len(RULES) == len(RULE_NAMES)` and `paid` in `GATE_NAMES`), and the suite exports the strict option at its top, as `run.sh` does. `run.sh` gets the block that reads `paid-cases.txt`.
  - `all.sh`: `paid` in `NAMES`, `script_of` and the header. `ci.yml`: one step.
- **Acceptance (strict, or light with a paid line).** (1) The owner asks "run render.py for 6 images"; the script imports a paid SDK. The call is denied before it runs. The reason names the signal and the exact line to type, and ends `[rule paid]`. Nothing is spent. (2) He adds `paid: render.py x 10, cap RM5`. Six images: denied, "ONE output". One image: runs. The next: "waits for the owner's test ok". He adds `, test ok`: runs 2–10 pass, run 11 is "used up". (3) Claude cannot change the counter from the shell: `[rule owner-file, always on]`. (4) Light with no paid line: the same command runs and nothing is printed. (5) `grep`, `cat`, `echo` and a commit message that mention a paid host are not touched.
- **Unit tests.**
  - Carried over: every section of the branch's `paid-guard-test.sh` (§7 records 328 PASS; F0's run on `19c7e45` is the reference) and `paid-cases.txt` through `run.sh`. A count below the reference is explained case by case in the commit message.
  - New, red first: the `[rule paid]` suffix on each reason family (6). Level and arming (8): light with no adapter allows; `paid_guard: on` denies; a `paid:` line arms; strict with no adapter denies; `rules_off=paid` allows in light and is ignored in strict; a forced detection error allows in light and denies in strict.
  - Order (3): a command both a rule and the paid check would deny gets the rule's reason and the counter is untouched; a paid call the fresh-source gate denies is not counted; a counter lock held past the deadline denies "could not verify".
  - V10 (3): a command over the heredoc cap with an interpreter-read body that names a paid SDK is denied; a tagged command with a paid word is denied; a tagged command without one is allowed.
  - Routes (6): four PowerShell smoke cases, a background run, a Monitor-shaped event (as E5 records it).
  - `owner-file` (12): the branch's counter cases (delete, overwrite, copy over, move, in-place edit, a program that writes it, a Windows spelling), readers allowed, a text mention allowed, the floor suffix. A state file that is not the counter (`receipts.jsonl`) is not matched.
  - Timing, inside the process: four ordinary commands leave the paid path in under 5 ms each; a 256 KB script with no signal in under 50 ms; one 30 KB text per pattern family (host names on a long dotted run, key names, SDK imports, the segment splitter, the count-flag reader) in under 1 s. A pattern that fails is rewritten, with cases that show the same matches.
- **Integration test.** The branch's whole sequence in one run (deny · pass · deny · test ok · pass ×9 · deny), reading `paid-runs.json` after each step. `hooks.json` is byte-identical to main. `fresh-gate-test.sh`'s run-without-`main()` check passes. Method D in an empty temp project: no flip among the strings of `run.sh` and `fresh-gate-test.sh`.
- **Interactive scenario.** A scratch repo with a stub `render.py` that imports a paid SDK and only prints "would call". Steps 1–3 in strict; then light with `paid_guard: on` in a scratch adapter the owner writes.
- **Files.** `bash-guard.py`, `run.sh`, `paid-cases.txt` *new here*, `paid-guard-test.sh` *new here*, `all.sh`, `.github/workflows/ci.yml`. **Must not change.** The frozen names (§8.6); every `RULES` entry but the appended one; every fresh-source result; `hooks.json`.
- **T1.** `run.sh`, `paid-guard-test.sh`, `fresh-gate-test.sh`, `until-done-test.sh`, one at a time.

#### F4 — proven on the owner's real repo; free runs (0.75 day; needs D-YK7)
- **Part 1, the replay (a tester; no repo file changes).** The commands that repo documents for itself are sent to the ported guard as event JSON, with that repo as `cwd` and a temp HOME. Nothing is run and nothing is spent. One row per class: a paying client call; the same call as a dry run; a client that pays only with its pay flag, with and without it; an offline check that names a key; an entry script whose call sits in a helper; the test gate script. The table goes into §8.10.
- **Part 2, only what the table shows is missing (a builder).**
  - `paid_free:` *new*, adapter only. Its items are flags and project-relative path patterns. A run of a paid script is free (allowed, not counted, no go needed) when its plain literal arguments hold a listed flag, or the script's path matches a listed pattern.
  - `only <flag>` *new* on a go line: the script is paid only when that flag is present.
  - `paid_scripts:` also takes project-relative paths and patterns, for entry scripts whose call sits in a helper.
  - A non-literal argument beside a free flag is not free. A `paid_free` value that is absolute or climbs out of the project is ignored. A typed go cannot carry `only`.
- **Acceptance.** In his real repo, with the adapter lines this feature's report hands him: a paying run is refused without a go; a dry run and an offline check run and are not counted; the entry scripts he listed are refused without a go.
- **Unit tests (`paid-guard-test.sh`, about 16, red first).** A free flag allows and leaves the counter untouched; a non-literal argument beside it does not; `only`: free without the flag, counted with it; a `paid_free` path pattern, and one that must not match another folder; `paid_scripts` with a path and with a pattern; Windows separators; the ignored values; an adapter without the new keys behaves as in F3.
- **Integration test.** The replay table run again: every row has the verdict the owner expects.
- **Interactive scenario.** In the real repo the owner asks Claude for a dry run (it runs), then for a paying run (refused, nothing spent).
- **Files.** `bash-guard.py`, `paid-guard-test.sh`, `paid-cases.txt`. **Must not change.** F3's results for an adapter without the new keys.
- **T1.** `paid-guard-test.sh`, `run.sh`.

#### F5 — the owner-quote check: the typed go, `test ok`, `paid stop` (1 day; old F3)
- **What changes.** The typed-go code of `040316c` goes in after its cases exist. Added to it:
  - `paid stop` is written into `paid-runs.json` the first time it is seen, so it cannot scroll out of the part of the transcript that is read; a go typed later is a new counter.
  - Text between tool-output markers is cut from a prompt before its lines are read.
  - The record shapes of E1–E3 decide what counts as typed: only a record whose origin says the owner typed it. A prompt from another session, a tool, a scheduled or nested run, a summary or the model is never a go.
  - `owner-file` also covers session transcripts (`.claude/projects/**.jsonl`): readers only.
  - The scan uses the one deadline (V8) and the last 4 MB.
- **Acceptance.** As old F3 (§3): with no adapter go the owner types `paid go: render.py x 3, cap RM1` on the phone; run 1 passes; `test ok`; runs 2 and 3 pass; run 4 is refused. `paid stop` refuses the next run even with runs left. A go that arrives from another session is refused, and the reason asks for the owner's own typing.
- **Unit tests (`paid-guard-test.sh`, about 38, red first; transcripts from one `mk.py` as in `wait-gate-test.sh`).** The old F3 list (§3). Plus: the stop that persists; a go typed after a stop; a line inside tool-output markers ignored; the E1, E2 and E3 shapes; a prompt the owner pasted that holds the line counts; the shared deadline overrun denies; `rules_off=paid` skips the scan. `run.sh`: about 10 `owner-file` cases for transcripts (append, overwrite, copy over, move, delete, a program that writes one, both Windows spellings; readers and a text mention allowed). **Incident replay 3:** the go relayed from another session is denied.
- **Integration test.** A real-shaped PreToolUse event through `py.sh` for the six steps of the acceptance, with the counter file read after each.
- **Interactive scenario.** On the laptop with the phone: type the go from the phone, watch run 1 pass, type `test ok`, watch run 4 refused. Then send the go from a second session and watch it refused. Then ask for the script through a subagent after a typed go (E4).
- **Files.** `bash-guard.py`, `paid-guard-test.sh`, `run.sh`. **Must not change.** Every F3 and F4 result; an adapter go works with no transcript at all.
- **T1.** `paid-guard-test.sh`, `run.sh`, `fresh-gate-test.sh`.

#### F6 — the paid check on the PowerShell tool (0.5 day)
- **What changes.** PowerShell forms in the block's tables: download cmdlets and their aliases as callers; `$env:<KEY> = …` as preparation; `Get-Content`, `Select-String`, `Write-Host` and `Write-Output` as mentions; the call operator and `Start-Process` as wrappers; PowerShell loop words as repeats.
- **Acceptance.** Through the PowerShell tool, "run render.py for 6 images" is refused exactly as through Bash, and a go, the count rule and the cap behave the same.
- **Unit tests (`paid-guard-test.sh` with a tool parameter, about 20, red first).** Deny: an interpreter with a script, a backslash path, `py -3`, the call operator, a paid URL given to each download cmdlet, `Start-Process` with an interpreter, a loop. Allow: the mentions, a key assignment alone, a script with no signal. The count rule: a variable or a subexpression as an argument is not literal. Timing: one 30 KB PowerShell text in under 1 s.
- **Integration test.** The F3 sequence once more with `tool_name` `PowerShell`.
- **Interactive scenario.** The F3 scenario, asked for through the PowerShell tool.
- **Files.** `bash-guard.py`, `paid-guard-test.sh`. **Must not change.** Every Bash result of F3–F5.
- **T1.** `paid-guard-test.sh`, `run.sh`.

#### F7 — PowerShell parity for the older rules (0.75 day; ROADMAP 0.7.0 line 3)
- **What changes.**
  - `ps-download-exec` *new*: a download cmdlet or alias whose output is run as commands (piped or passed to `iex` / `Invoke-Expression`), or a script that the same command downloads and then runs. The reason is the pipe-to-shell one.
  - `ps-rm-root` *new*: `Remove-Item` or an alias, recursive and forced, on a root, the home folder, `.` or `*`.
  - Writes to the owner's files with PowerShell verbs: covered by the reader allow list when D-YK8 is yes (the adapter, the trust file and the launcher file join `owner-file`). When it is no, the verbs are added to `human-only`'s list.
  - Both new rules are on in light and strict, and can be named in Rules off.
- **Acceptance.** Through the PowerShell tool: an installer one-liner that downloads and runs is refused, `[rule ps-download-exec]`, and Claude is told to save the file and read it first; a recursive forced delete of the home folder is refused, `[rule ps-rm-root]`; a write to the adapter is refused. `Remove-Item -Recurse -Force .\build` and a download saved to a file run.
- **Unit tests (`run.sh`, red first).** About 12 deny and 10 allow per rule, `check` and `pcheck` twins; the switch cases for both names; a timing case each. The comment at `run.sh:546` ("not covered, by design") is replaced by the cases.
- **Integration test.** Method D, both tools: the flips are the new deny cases; none among existing strings.
- **Interactive scenario.** The three refusals and the two allowed commands, live in a PowerShell-tool session.
- **Files.** `bash-guard.py`, `run.sh`. **Must not change.** Every existing rule string.
- **T1.** `run.sh`, `fresh-gate-test.sh`.

#### F8 — a quote in a comment no longer hides the next lines (0.5 day; ROADMAP 0.7.0 line 4; V14)
- **What changes.** `strip_comments` *new*: one linear, quote-aware pass that blanks a `#` comment (a `#` where a word can start, outside quotes) to the end of its line. Bash only. It is applied to the text the fresh-source gate and the paid scan read, at or under the heredoc cap. `RULES` keep reading what they read today. The builder first traces how `publish_hit` uses its `raw` argument (`bash-guard.py:1086`) and says so in the commit message.
- **Acceptance.** A command with a comment line that holds an apostrophe, then a publish (or a paid run), then another such comment is refused where today it runs. A multi-line commit message with a `#` line and an apostrophe still runs.
- **Unit tests (red first).** The two pinned cases flip to deny (`run.sh:632`, `fresh-gate-test.sh:853`); the neighbour at `run.sh:633` stays allowed. New: `#` inside single, double and `$'…'` quotes is text; `$#`, `${#x}`, `a#b` and a URL fragment are text; a `#` after `;`, `&&`, `|` and `(` starts a comment; heredoc bodies are untouched; a paid run between two such comments is denied. Timing: 30 KB of comment lines in under 1 s.
- **Integration test.** Method D plus the unchanged suites: the listed flips and no other. The quoted commit-message and PR-body allows that broke the last attempt all stay allowed.
- **Interactive scenario.** Ask Claude to run a three-line command whose first and last lines are comments with apostrophes and whose middle line is a publish, with the sources unopened: refused.
- **Files.** `bash-guard.py`, `run.sh`, `fresh-gate-test.sh`, `paid-guard-test.sh`. **Must not change.** `gate_strip`, `LEX`, `FLEX` and the other frozen names; every PowerShell result.
- **T1.** `run.sh`, `fresh-gate-test.sh`, `paid-guard-test.sh`.

#### F9 — the file tools: counter and transcripts are owner-only (0.5 day; track B)
- **What changes.** `file-guard.py` `HUMAN_ONLY` (`:22`) gains the counter, its lock and claim markers, and session transcripts. The reason and the docstring name them. The three readings and the resolved path apply as they do today.
- **Acceptance.** Claude's Write or Edit on `paid-runs.json` or on a session transcript is refused with the human-only reason. A write to a project memory file under the same folder is not touched.
- **Unit tests (`file-guard-test.sh`, about 10, red first).** Write and Edit on the counter; Write, Edit and MultiEdit on a transcript; a Windows spelling; a link that resolves to a transcript; a subagent transcript; allowed: a memory `.md` beside the transcripts, `receipts.jsonl` in the state folder.
- **Integration test.** `ci.yml` as it is.
- **Interactive scenario.** Ask Claude to "fix the counter file": refused.
- **Files.** `file-guard.py`, `file-guard-test.sh`. **Must not change.** `switch_change`, the canary, the strict error path.
- **T1.** `file-guard-test.sh`.

#### F10 — names, docs, counts, version (0.5 day, after the merge and T2)
- **What changes.**
  - `heartbeat.py` `KNOWN_RULES` (`:77`) and `FLOOR_RULES` (`:79`) follow the final lists (§8.6); the compare in `heartbeat-test.sh:539` reads `RULE_NAMES` plus `GATE_NAMES`.
  - `README.md` (the bash-guard row, the names in "Switches", the adapter keys, the state files, honest limits), `plugins/smartuse/README.md`, `SECURITY.md`, `CHANGELOG.md` (0.7.0 opens with "Changed defaults": the settings reader list, the PowerShell rules), `CONTRIBUTING.md`, `docs/STATUS.md`, `docs/ROADMAP.md`, `docs/notes/relay-design.md` (rule 4 built; the `.env` and `paid_tools:` differences), `docs/notes/recall-design.md` (the pinned limit, if F8 landed), the version in `plugin.json` and `.claude-plugin/marketplace.json`.
  - SECURITY.md says, by class: what the paid check reads (the script a command runs, first 256 KB; the last 4 MB of the transcript on a paid call; never `.env`, never the network); that a missed deny costs money, so a failed check denies; that it stops honest mistakes and not a forged approval; that the adapter go is the stronger form; that vendor hard limits are the backstop; that a go matches by file name, a helper module and a module run by name are not followed, runs are counted and money is not.
- **Acceptance.** A reader finds the rule, the adapter keys and the typed lines in under a minute. Every number is a suite's last line or a method M measurement.
- **Tests.** `heartbeat-test.sh`; `bash scripts/term-scan-test.sh`; the CI `validate` job.
- **Interactive scenario.** The owner reads the CHANGELOG entry on the phone and finds each claim backed by a case or a number.
- **Files.** As listed. The repo's `CLAUDE.md` test lines are the owner's edit (D-YK11).

### 8.5 Build order, worktrees, what can run side by side
| Track | Order | Files it owns |
|---|---|---|
| A — the guard | F1 → F2 → F3 → F4 → F5 → F6 → F7 → F8 | `bash-guard.py`, `run.sh`, `fresh-gate-test.sh`, `paid-guard-test.sh`, `paid-cases.txt`, `all.sh`, `ci.yml`, `skills/reply-style/SKILL.md` |
| B — the file tools | F9 | `file-guard.py`, `file-guard-test.sh` |
- F0 runs first, by the orchestrator. Track B can run beside any track A feature: it shares no file.
- Track A is one worktree and one builder at a time: every feature edits `bash-guard.py` and `run.sh`. F7 may run in a second worktree beside F4–F5 only if the laptop keeps up; its merge then has three known spots (the names tuple, its pin in `run.sh`, `FLOOR`), resolved by keeping both sides.
- At most two heavy jobs at once on the laptop (a builder's suite run counts as one). A builder runs one suite at a time.
- After track A and B merge: T2, then F10, then the review (§8.8), then T3.
- **Cut line (D-YK10).** F0–F4 with F9 and F10 are a complete release: both findings fixed, the adapter go, proven on the real repo. F5–F8 can follow as 0.7.1 (the transcript part of F9 then goes with F5).
- **Approvals.** The auto-mode safety check refused a rule edit once. Expect a prompt for each feature that edits `RULES` (F2, F3, F5, F7). The orchestrator asks for them in as few sittings as it can and says how many are coming.

### 8.6 Must not change, the constraints for every builder, and the two methods
- Python 3.9 stdlib. One Python start per hook event. No subprocess, no second interpreter, no network, no model call. No import between hooks. Hooks run through `py.sh`.
- Byte-identical: `HEREDOC`, `strip_heredocs`, `opener_line`, `STATE_CALL`, `STATE_SHAPE`, `HEREDOC_OPEN_PLAIN`, `gate_strip`, `heredoc_is_code`, `LEX`, `FLEX`, `BUDGET_S`. Also `complexity()` and `hooks.json`.
- `RULES` stays a list of `(pattern, why)`; existing entries keep their strings and order; new entries are appended. `until-done.py`'s run of this file without `main()` prints nothing and yields `RULES`.
- Under strict every existing case in every suite keeps its result, except the cases a feature lists. Suite counts only grow.
- The deny JSON shape; the first words of every existing reason; nothing printed on allow; a whole reason is at most `MAX_REASON` characters.
- The adapter is read, never written. State holds counts, names and paths, never a command. No `.env` is opened. Nothing is written inside the repo by a hook.
- **Final names.** `RULE_NAMES` = today's 16, then `settings-file`, `owner-file`, `ps-download-exec`, `ps-rm-root`. `GATE_NAMES` = `paid`. `FLOOR` = `human-only`, `trust-pin`, `config-switch`, `settings-file`, `owner-file`. `LIGHT_OFF` is unchanged.
- **The rule for changing `RULES`** (`light-fast-plan.md` §6) applies to F1, F2, F3, F5, F7 and F8: name the class; cases first and red on the code before; method D; one timing case per changed pattern or waiver; widen with a new named entry and narrow with a waiver; one review.
- **The no-spiral rule** (`light-fast-plan.md` §9, §14). A review finding inside a class this plan already records as a limit goes to SECURITY.md's limits, not into a fix round. More shell parsing waits for a reported miss.
- **In every builder brief.** Only the files the feature names. Edit tool, no pasted whole files (the two test files that come from the branch excepted). One command per shell call; `git -C <dir> …`; `MSYS_NO_PATHCONV=1` before `git show <rev>:<path>` in Git Bash. Suites one at a time; never `all.sh` on the laptop. Never touch `.claude/*.local.md`, `.smartuse-terms.local`, `.agents/`, `.codex/`; never read or print `~/.claude.json`. Stage by file name. Builders never commit and never push. Public repo: no personal paths or names in any file; a problem is described by its class. A fixture that names a paid host, key or SDK lives in `paid-cases.txt` or is written through `printf`, so the suites stay runnable through the guard. Scratch files go in the gitignored scratch folder and are deleted at the end.

**Method D, the differential (§6 rule 3).** A scratch script, not committed.
1. Record: `run.sh`, `fresh-gate-test.sh` and the paid cases run once in a scratch copy of the hooks folder whose guard is replaced by a recorder. The recorder appends each event JSON it is given to a file and prints nothing.
2. Replay: one Python process runs every recorded event through the old guard (main's file) and the new one, inside the process, as the suites' timing cases do (`run.sh:292–306`). Each event runs as sent and with the other tool name, under strict and under light, in an empty temp project with a temp HOME.
3. Output: one line per flip (tool, level, old → new, the first 70 characters). The commit message quotes the list. A flip that is not on the feature's list stops the merge.
Verdicts that depend on state (the fresh-source gate with a transcript, the paid counter) are not what D compares; for those the unchanged suites run green on the new guard.

**Method M, the wait (as 0.6.1's F0).** `claude --debug-file <a scratch file>` in a scratch repo; one fixed prompt (ten `echo` Bash calls, ten Reads, five Edits); the `Hooks:` lines of smartuse commands; the median per tool; two runs, the slower quoted. Three columns on the same day and Claude Code version: the base; 0.7.0 in light with no paid line; 0.7.0 armed. Pass: each 0.7.0 Bash median is at most the base plus 0.03 s. A second prompt of ten runs of a one-line script is reported for the armed column (the script read), not gated.

### 8.7 Tiers
- **T1, the builder, after every change:** the suites its feature names, one at a time, each as `bash plugins/smartuse/hooks/tests/<suite>`.
- **T2, after each merge and before each commit, one at a time, in this order:** `file-guard-test.sh`, `ledger-test.sh`, `until-done-test.sh`, `watch-test.sh`, `heartbeat-test.sh`, `wait-gate-test.sh`, `recall-test.sh`, `run.sh`, `fresh-gate-test.sh`, `paid-guard-test.sh` (each as `bash plugins/smartuse/hooks/tests/<name>`), then `bash bench/tests/ab-test.sh`, then `bash scripts/term-scan-test.sh`. Twelve suites; the floor is F0's list; counts only grow. `all.sh` stays the one-command gate for bigger machines and CI.
- **T3, before the push:** T2; `claude plugin validate --strict plugins/smartuse` and `claude plugin validate --strict .`; the live pass (every feature's interactive scenario, experiments E1–E5, method M); `bash plugins/smartuse/hooks/py.sh scripts/term-scan.py --history` with 0 hits and the private list present.

### 8.8 Review
One fresh review of the merged code before any push, on Opus at xhigh, over the diff from `origin/main` to the dev branch. Its brief: check each feature against §8.4; diff the frozen names; confirm `hooks.json` is identical; read each method D list and each red-first run quoted in the commit messages; class every finding as blocker, major or minor. One fix round for blockers and majors, then a re-check of that fix diff only. Minors, and anything inside a recorded limit, go to SECURITY.md. The automated security review of the push follows the same rule.

### 8.9 Decisions that need the owner (recommendation first)
**Decided 2026-11-13.** YK picked "2" on Card A: the whole plan, F0–F10, ships as one 0.7.0 (D-YK10: one release, no cut after F4). D-YK6 (V5 arming), D-YK7 (free runs: yes), D-YK8 (reader allow list for the adapter, trust and launcher files: yes) and D-YK9 (`onFailure`: no) take the recommendation below; the owner may still veto any of them. D-YK11 stays open: the repo `CLAUDE.md` is the owner's edit.
- **D-YK6. Where `paid` sits.** Recommend V5: always on in strict; in light, on in a project whose adapter has a paid line. The other choice is on for everyone, as the 2026-10-24 wording says: then every user who runs their own LLM-app scripts is denied on each new script until they write a go.
- **D-YK7. Free runs** (`paid_free:`, `only <flag>`). Recommend yes, sized by F4's table. Without them the guard denies every dry run and offline check in the real repo, and it would be switched off within a day.
- **D-YK8. The reader allow list for the adapter, the trust file and the launcher file too** (ROADMAP 0.5.0 "also", the `human-only` gaps). Recommend yes, in F3, about 0.25 day more: the `paid:` go lives in the adapter. The cost is that any command other than a reader that names those files is denied; method D lists the flips first.
- **D-YK9. `onFailure: "block"` on the guards.** Recommend no. It is one static setting for every user; in light an internal error would then block the call, against the 1.0 bar; and a machine that cannot start the hook command would have every Bash and PowerShell call blocked. The paid check denies on its own errors once a call is paid (D5, V8).
- **D-YK10. One release or two.** Recommend: build in this order and decide after F4. 0.7.0 can ship there; the typed go, PowerShell parity and the comment fix follow as 0.7.1.
- **D-YK11. The repo's `CLAUDE.md` test lines** (add `paid-guard-test.sh` to T1; T2 one suite at a time on a small machine). The owner's edit or his yes.

### 8.10 Unknowns, each an experiment (results are written here)
| # | Unknown | Experiment (field names only, never content) | If it goes the other way |
|---|---|---|---|
| E1 | The transcript record of a prompt typed on the phone: its type and origin fields | the owner types one word from the phone; the tester reads the record's keys | the phone shape is added to what counts as typed, with a case |
| E2 | The record of a prompt typed while Claude is working | the same, mid-turn | as E1 |
| E3 | The origin fields of the prompt of a headless run that a command starts | one headless run in a scratch repo | if it reads as the owner's typing, the typed go cannot tell the two apart: the limit is written down and the owner decides whether F5 ships (the adapter go is not affected) |
| E4 | Which `transcript_path` and ids a subagent's PreToolUse gets | one Bash call inside a subagent, event keys recorded by a scratch hook | the typed go covers the main session only; subagents need the adapter go |
| E5 | The `tool_name` of a command started through Monitor | one Monitor call, event keys recorded | Monitor's name joins the shell tools in `_main()`, with a case |
| R | The verdict for each class of real command in the owner's repo | F4 part 1 | F4 part 2 is sized by the table |
Assumed, not tested: a prompt the owner pastes is his typing; an older Claude Code that lacks the origin fields makes the typed go fail closed (the reason says to use the adapter).

### 8.11 Risks
- **Another hardening spiral.** Two new floor rules will be probed. The answer is §8.6's no-spiral rule: one review, one fix round, the rest recorded.
- **The reader list denies an honest command.** Method D measures it before the merge; the reason names the Edit tool or a reader; removing one `RULES` entry rolls it back.
- **Transcript shapes are internal to Claude Code** and changed twice in three weeks. The typed go fails closed and points at the adapter.
- **The typed go rests on a file the model's process can write.** The protection reads command text; a write hidden inside another program or built at run time is not seen. Stated in SECURITY.md; the adapter go and vendor limits stand behind it.
- **The real repo shows more than two missing pieces.** Anything past `paid_free`, `only` and path patterns goes back to the owner before it is built.
- **Track A is one long line.** Eight features share two files. The cut line after F4 keeps a release shippable.
- **The laptop.** Suites run one at a time; a full T2 is about an hour. A very long project path can push the state folder past the Windows limit: the counter then cannot be written and a paid call is denied with "could not verify", not allowed silently (the fix is on 0.6.2).
- **Time when armed.** Each command that runs a script file costs one read of up to 256 KB. Method M's second prompt reports it.

### 8.12 Estimate (only the new part: about 700 lines of the block and 328 cases exist)
| Step | Agent runs | Tokens, rough | Wall time on the laptop |
|---|---|---|---|
| F0 | 1 tester | 0.3 M | 1.5 h, 10 minutes of the owner (the phone prompt) |
| F1, F2 | 2 builders | 1.3 M | 4 h |
| F3 | 1 builder | 1.2 M | 4 h |
| F4 | 1 tester, 1 builder | 0.9 M | 3 h, the owner writes his adapter lines |
| F5 | 1 builder | 1.2 M | 4 h |
| F6, F7, F8 | 3 builders | 2.2 M | 7 h |
| F9 | 1 builder | 0.4 M | 1 h, beside track A |
| Merge, T2 ×3, F10 | 1 tester, 1 builder | 1.0 M | 4 h |
| Review, one fix round, re-check | 1 reviewer, 1 builder | 1.3 M | 3 h |
| Live pass (T3) | 1 tester | 0.5 M | 2 h, 30 minutes of the owner |
| **Total** | **about 17** | **about 10 M** (most of it cached reads of two large files) | **about 33 h of agent time, three to four working days; the cut after F4 is about half** |
These are estimates, not measurements. The suite times behind them: `run.sh` and `paid-guard-test.sh` about 10 minutes each and `fresh-gate-test.sh` about 15 on this laptop.

### 8.13 Card A
```
FINISH LINE: smartuse 0.7.0 "the paid-call guard"
So you want: no script spends on a paid API without your go, and the two review findings closed, with no extra wait
Sample: docs/notes/paid-guard-plan.md §8 | bash-guard: paid call (<KEY> in <script>) — no go from the owner for <script>. … Nothing was spent. [rule paid]
Done when: 1 in your image repo you ask for the batch run and it is refused before it runs, with the line to type 2 you type "paid go: <script> x 3, cap RM1" on the phone: one run, "test ok", two more, the fourth refused, a dry run not counted 3 you ask Claude to change the counter or a settings file from the shell and it is refused, and the Bash wait table reads the same as 0.6.1
Proven on: the owner's image-pipeline repo, its own documented commands (F4's replay; path in the session report) | synthetic: the suites' event JSON
Unknown: E1 the phone prompt's record → experiment · E3 a headless run's prompt → experiment | assumed: a Monitor command arrives as a Bash call
Not in this: MCP paid tools · measuring money · following helper modules · relay rules 1, 2, 3, 5 · the 0.6.2 list · a dispatcher
Alt: ship in two cuts: 0.7.0 after F4 (adapter go, both findings, proven on the real repo), the typed go and PowerShell parity as 0.7.1
Tap: 1 yes · 2 send a reference · 3 no
```
