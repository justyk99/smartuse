# recall: "the summary is not a source" (0.6.0 design and build contract, 2026-11-08)

Status: plan approved by YK on 2026-11-08. This note is the contract the builders work from (dev-flow phase 3); F4 turns it into the user docs. Every existing name below was grepped on the dev branch; new names are marked *new*.

## The problem (the class, not a case)
A long session gets compacted. Claude keeps a model-written summary and loses the exact words. Two failures follow:
- **Gone:** the owner's exact words and the job's details are not in context any more.
- **Present but not used:** the job's real files are on disk, but Claude works from the summary or from notes, and still says "checked".

Claude Code already reloads CLAUDE.md, auto memory and up to 5 recently modified files after a compaction. It does not know which files are this job's sources, and nothing refuses an action taken from the summary. Memory plugins put text back into context; none refuses a send. smartuse adds the refusal and the pointer, never a store.

## What ships in 0.6.0
| Feature | What the owner sees |
|---|---|
| F1 fresh-source gate | a `publish:` command or a `publish_tools:` tool call is denied until every `sources:` file has a Read in this session after the last compaction; the reason names the unopened files |
| F2 recall at the squeeze | PreCompact hands the summarizer the source list and the owner's last prompts verbatim; after the squeeze Claude is told "the summary is not a source" and which files to re-open; the status line counts squeezes |
| F3 recall at session start | `handoff:` names the handoff file; its first lines and its age are printed on startup, clear and resume |
| F4 docs, counts, a 30-second demo with invented files | README, SECURITY, CHANGELOG, this note |

## Adapter keys (in the human-only `.claude/smartuse.local.md`)
One line per key, `key: value, value`, first occurrence wins, frontmatter or body; values split on commas, trimmed, empty ones dropped. Read the way `until-done.py` `adapter_check()` reads `check:`. The project dir is `CLAUDE_PROJECT_DIR`, else the event's `cwd` (`native_path`), else the process cwd (the order of `until-done.py` main).
| Key *new* | Value | Example |
|---|---|---|
| `sources:` | paths or globs, relative to the project dir or absolute | `sources: jobs/demo/plan.pdf, jobs/demo/photos/*.jpg` |
| `publish:` | shell command patterns: a pattern matches a command segment whose words start with the pattern's words | `publish: python send.py, git push` |
| `publish_tools:` | tool names, `fnmatch` globs | `publish_tools: mcp__*__file_upload, mcp__*__upload_image` |
| `handoff:` | one path (F3) | `handoff: docs/STATUS.md` |
No `sources:` → no gate, no change for that repo. `sources:` without `publish:` and `publish_tools:` → no gate; F2/F3 say once that nothing is gated.

## F1: what "opened" means
- A **Read** is an assistant record whose `message.content` holds `{"type":"tool_use","name":"Read","input":{"file_path":…}}`. Records with `isSidechain: true` are skipped (a subagent's read is not the model's). Bash `cat` or `head` does not count (documented).
- The **last compaction** is the last record `{"type":"system","subtype":"compact_boundary"}`; a `user` record with `isCompactSummary: true` is the fallback marker. No marker → every Read in the session counts.
- **Path equality:** both sides through `native_path`, made absolute (a relative source against the project dir), `os.path.normpath`, `os.path.normcase`, backslashes to `/`. `C:\x\plan.pdf` and `C:/x/plan.pdf` are the same file.
- **Globs** are expanded on disk at check time (`glob.glob`, sorted), and only for patterns relative to the project dir; an absolute source is taken literally. A pattern that matches no file → deny with its own reason (a typo must reach the owner). More than 200 files after expansion → deny "narrow the pattern".
- **Plain local paths only:** the adapter can arrive with a cloned repo, so a source value (after `native_path`) is accepted only in a plain local spelling: relative with no leading separator, no drive and no `..` part; `X:\…` or `X:/…` (not `X://`); or `/…` (not `//` or `/\`). Any value holding `\??\`, `\\?\`, `\\.\`, `//?/`, `//./` or `GLOBALROOT` (any case) is refused. Anything else is never expanded, stat'ed or compared; a matching publish is denied with its own reason. The text check runs before any filesystem call. Hooks never touch the network. A mapped network drive letter cannot be told from a local one by its text and is accepted (documented).
- **One deadline:** `BUDGET_S = 4.0` from the start of the fresh-source check, shared by the source expansion and the transcript pass. The expansion runs in a daemon worker thread joined with the time left (as `file-guard.py` `resolved()` does for realpath); a worker that does not answer is left behind and the process ends with `os._exit(0)` after its output is flushed. Past the deadline at either step a matched publish is denied, never let through: a hook that times out lets the call through, so the deadline sits inside the hook.
- **Transcript pass:** one forward pass; `json.loads` only on lines that contain `"tool_use"`, `compact_boundary` or `isCompactSummary`; the deadline is checked every 128 lines and at the end. The `transcript_path` comes from the event. Measure the pass on the laptop (a session-sized log and the largest `.jsonl` under `~/.claude/projects`, sizes only) before any number is quoted.

## F1: what a publish is
- **Bash:** after the existing `RULES` loop allows the command. `strip_heredocs(cmd)` first (a data body is not a command; a body that a shell or interpreter runs from stdin stays, as today). Split on newlines, `;`, `&&`, `||`, `|`. Per segment find the command word: skip leading `VAR=value` words, the `if` / `then` / `do` of a compound, and the programs that only run what follows them, with their options (`command`, `builtin`, `exec`, `env`, `nohup`, `nice`, `timeout` and its duration, `stdbuf`, `xargs`, `time`, `sudo`, `doas`). A segment matches a pattern when the pattern's first word is the command word and each later pattern word appears, in order, among the command's later words, compared case-sensitively, with a script path compared by its normalised form: `git push` matches `git -C dir push origin`, `python send.py` matches `python -u send.py`. The string given to `sh|bash|zsh|dash -c` and to `eval` is checked the same way, to depth 2. `echo "python send.py"` is not a match (its command word is `echo`). A pattern word that only happens to appear later (`git log --grep push`) is an over-deny, which costs one turn.
- **Tools:** `hooks.json` gains one PreToolUse entry, matcher `mcp__.*(upload|send|publish|post|share|submit).*`, command bash-guard.py, timeout 10. In bash-guard `main()`, a non-Bash event runs only the fresh-source check, and only when the tool name matches a `publish_tools:` glob; anything else is allowed. A `publish_tools:` entry the matcher cannot reach is named by F2/F3 as "not gated". A click on a page's own Send button is not gated (documented).

## F1: fail open, fail closed
Detection errors (bad stdin, unreadable adapter, no `sources:`) → allow, as today. **After a publish match**, any failure to verify (transcript missing or unreadable, past the deadline) → deny. A missed deny ships a wrong deliverable; a wrong deny costs one turn.

## F1: the reasons the model reads (prefixes asserted by tests)
- `bash-guard: fresh-source — 2 of 3 sources not opened since the last compaction (14:02): photos/a.jpg, photos/b.jpg. Open each with Read, then retry. Nothing was sent.` (no compaction: `not opened in this session`; at most 10 names, then `and N more`; names relative to the project dir when inside it)
- `bash-guard: fresh-source — source pattern matches no file: <pattern>. The owner fixes sources: in .claude/smartuse.local.md. Nothing was sent.`
- `bash-guard: fresh-source — narrow the pattern: <pattern> matches over 200 files. Nothing was sent.`
- `bash-guard: fresh-source — could not verify which sources were opened (<why>). Retry, or ask the owner. Nothing was sent.`
- `bash-guard: fresh-source — <value> is not a plain local path; sources must be local files. The owner fixes sources: in .claude/smartuse.local.md. Nothing was sent.`
An allowed call prints nothing. The deny JSON shape is bash-guard's existing one.

## F2 and F3: `hooks/recall.py` *new*
Registered on `PreCompact` (matcher `manual|auto`) and `SessionStart` (no matcher), timeout 10. Python 3.9 stdlib, no subprocess, no network, exit 0 always, prints nothing on bad stdin. Everything printed is scrubbed first and capped at 9,000 characters (cut, never spilled to a file).
- **Owner prompts:** `user` records whose `turnOrigin` or `origin.kind` is in `{"human","sdk"}`, not `isMeta`, not `isCompactSummary`, not starting with a harness marker: copy `wait-gate.py`'s `HUMAN`, `INJECTED`, `is_human()` and `text_of()` rules (no import between hooks). The last 8, oldest first, whitespace collapsed, each cut at 300 characters.
- **Scrub:** token prefixes with a word boundary (`\b(sk-|ghp_|gho_|github_pat_|xox[abpr]-|AKIA|AIza)[A-Za-z0-9_-]{8,}` → `[secret]`), digit runs of 8 or more → `[number]`, e-mail addresses → `[email]`. `task-folder` stays as it is.
- **PreCompact** (F2) prints instructions for the summary: keep these source paths verbatim; keep these owner prompts verbatim; mark anything not re-verified as "from summary". When the input carries `custom_instructions`, they are printed first.
- **SessionStart `compact`** (F2) prints: the squeeze time, `The summary is not a source.`, the `sources:` list with "none counts as opened now; open each before any output", and the owner prompts. Without `sources:`: two lines (time, the sentence).
- **The handoff file is contained:** read only when it is a relative path with no `..` part, not a network path, resolved inside the project dir, and a regular file (64 KB read cap); otherwise one line says it is not read. A `.git` file's `gitdir:` that is a network path skips the stale check. The text checks run before any filesystem call.
- **SessionStart `startup` / `clear` / `resume`** (F3): with `handoff:`, its first 15 lines, its modified time, and `stale: the handoff is N days older than the last commit` when `.git/logs/HEAD`'s last entry is newer (a file read). On `resume` with a compaction in the transcript: `resumed; the compacted part is a summary, not a source`. With `sources:`: the list and "open each before any output". Neither key → nothing.
- **State** *new*: `~/.claude/smartuse/projects/<key>/recall.json` `{compactions, last_at, last_unopened: [...]}`, key and dir as `ledger.py` computes them (asserted equal in the test). Counts and paths only, never a command.
- **Counter** (F2): `heartbeat.py` `apply()` on SessionStart `compact` of the same session: `compactions += 1`, `compact_at`; `--line` adds ` · squeezed N× (last HH:MM)` while it is above 0.

## Must not change (every feature)
`run.sh` 138 and every other suite green (`all.sh | tail -1`); `RULES` strings and order; heredoc and `STATE_CALL` behaviour; Python 3.9 stdlib only, no subprocess, no network, no import between hooks; nothing printed on allow, the same deny JSON shape; the state-dir key equal to `ledger.py`'s; Windows Git Bash (`native_path`, the cp1252 stdin case); the adapter stays human-only; nothing is written inside the repo; exactly one Bash PreToolUse command in `hooks.json`.

## Tests (each new case shown failing on the code before it)
- **F1:** about 12 text cases in `run.sh`; `fresh-gate-test.sh` *new*, about 45 cases on synthetic transcripts made by one helper (the way `wait-gate-test.sh` builds them), event JSON written to files (Windows paths). Deny: no Reads after the boundary; Reads only before it; 2 of 3 opened; a glob with no match; over 200 files; a Read only in a sidechain; a publish run from a heredoc a shell reads as code; a missing transcript; a budget overrun; a `publish_tools:` tool call with an unopened source. Allow: all opened after the boundary; no boundary and all opened once; `C:\` against `C:/`; a publish word inside a heredoc data body; `echo "python send.py"`; no publish pattern; no `sources:`; no adapter; a tool not in `publish_tools:`. **Replay:** sources opened only after the publish call → denied at the first call.
- **F2/F3:** `recall-test.sh` *new*, about 65 cases; `heartbeat-test.sh` about +6. The prompt filter (peer, task notification, meta and summary records never quoted), the scrub (a fake `sk-` token and a 10-digit run masked, `task-folder` kept), the 9,000 cap on a 2 MB transcript, each SessionStart source, the stale line, a missing handoff file, bad stdin.
- `all.sh` NAMES gain `fresh` and `recall`; CI gets one step per new suite.

## Honest limits (for the README)
A Read is counted, not understood. The summary's quality is the model's. A click on a page's Send button is not gated; uploads and named commands are. Only tools whose names the `mcp__…(upload|send|publish|post|share|submit)…` matcher reaches are gated; a `publish_tools:` entry outside it is named "not gated" at session start. A publish hidden inside another program (`python -c`, a script that calls the send, `xargs` given the script name on stdin, `env -S`) is not seen; the wrappers listed above are. A mapped network drive letter is accepted as local. A subagent's hook may get its own transcript; v1 checks the transcript it is given. A hook that does not finish inside Claude Code's timeout (a very slow interpreter start) lets the call through. Transcript records are internal to Claude Code and change between versions; the fixtures carry each shape seen.
