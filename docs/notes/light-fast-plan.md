# 0.6.1 — lighter, faster, switchable: plan (dev-flow phase 2, 2026-11-10)

Status: **approved by the owner 2026-11-10: the whole plan, both cuts ("big"); see §13.** Build started 2026-11-10. Planner: flow-planner on claude-fable-5-2. Brief, research and the build-or-reuse note: `docs/notes/light-fast-brief.md`. Every existing name and line below was grepped on the dev branch at 0.6.0 (`bash-guard.py` 1,372 lines, `heartbeat.py` 551, `hooks.json` 174); new names are marked *new*. This note is the contract the builders work from, one builder brief per feature.

## 0. What this release is, and the number it is judged by
Three changes for the person at the keyboard: the heartbeat stops making Claude wait, the guards stop denying honest commands, and the owner gets a switch that only the owner can flip.

| What | 0.6.0 | Target | Checked by |
|---|---|---|---|
| smartuse hooks waited on per Bash or PowerShell call | 3 (guard and heartbeat before, heartbeat after) | **1** (the guard) | a count read from `hooks.json` (F1 test) |
| per Read, Grep, Glob or other unguarded call | 2 | **0** | same |
| per Write or Edit call | 3 | **1** | same |
| Seconds waited per Bash call, median, the author's laptop | F0 measures it; estimate 0.5–0.7 | **≤ 0.35** (one start) | method M (F0) |
| Seconds waited per Read call | F0 measures it; estimate 0.4–0.7 | **0** | method M |
| End of a turn | 4 starts side by side; the wait gate reads the whole transcript | 4 starts; **no transcript read** in light | method M, on a long session |
| Honest command classes denied (brief §1) | 4 | **0** in light | `run.sh`, light block |

The seconds are estimates until F0 has run: hooks of one event start side by side, so the wait is not the sum of the starts.

## 1. Facts the plan rests on
- Claude Code: the six claims in brief §5, all confirmed in the docs. Every field used needs Claude Code 2.1.296 or older; the README's floor is 2.1.300.
- `hooks.json`: heartbeat on PreToolUse `*` (`:35–44`) and PostToolUse `*` (`:88–99`); Stop runs ledger, until-done, wait-gate, heartbeat (`:46–71`).
- `bash-guard.py`: `RULES` (`:43–75`) is a list of `(pattern, why)`; `main()` searches each with `re.search` (`:1354–1357`); `until-done.py:109–117` runs this file without `main()` and takes `RULES` as pairs.
- `heartbeat.py`: PreToolUse sets `tool_running` (`:293–296`); only PostToolUse clears it (`:297–301`); the lock is `fcntl` only, so Windows has none (`:203–212`).
- `wait-gate.py`: `gate_off()` (`:229`) is checked at `:592`, before the transcript is read at `:597`.
- `py.sh:40`: no interpreter → `exit 0`, nothing printed. `heartbeat-test.sh:308` pins that.
- Suites assert parts of `hooks.json`: `fresh-gate-test.sh:1296–1307` (PreToolUse matchers and timeouts), `wait-gate-test.sh:983–986` (Stop order and timeouts). Neither looks at `async`.

## 2. Decisions made here (defaults; the owner may veto any)
1. The release is **0.6.1**. Today's 0.6.1 list moves (see §7). The paid-call guard stays 0.7.0.
2. The switch lives in Claude Code's plugin options (`userConfig`). No smartuse file, flag, skill or typed word switches a guard.
3. Three options: `strict` (on/off), `rules_off` (text), `wait_gate` (on/off). No picker field, so older Claude Code still loads the plugin.
4. **Light is the default**, also when Claude Code passes no option at all. An option value the hook cannot read as on or off counts as strict.
5. Light switches off two rule classes (`force-with-lease`, `secrets-dir`) and the wait gate. Strict is 0.6.0's behaviour. The two bug-class fixes of F2 apply to both.
6. `~/.ssh`: no change. `ls ~/.ssh` is already allowed (`run.sh:120`); the folder pattern also stops a wildcard read of every key.
7. The owner may switch off any rule except the three that protect the switches: `human-only`, `trust-pin`, `config-switch` (*new*).
8. Strict ignores `rules_off`: strict means everything on.
9. The fresh-source gate has no level and no switch. Its rule "a command the gate cannot read counts as a send" (security plan §7e) is untouched.
10. Only the heartbeat's three tool-event handlers go to the background. Guards and Stop gates never do.
11. No `if` filter on a guard: it is a best-effort text filter, and file-guard must match every reading of a path.
12. The bash launcher stays (brief §5, claim 5).
13. `PostToolBatch` is not used: its minimum version is not stated.
14. `onFailure: "block"` is not on by default (F9, §11 question 3).
15. A rule is narrowed by a waiver after its match, or by moving one alternative into its own named rule. Never by deleting an alternative.
16. No new suite and no new hook file. New cases go into the existing suites; `all.sh` NAMES and `ci.yml` steps stay.
17. `ConfigChange` hooks are not used: a blocked change shows no message to anyone, and the owner's own change would be blocked too.

## 3. Scope
| | Feature | Why here |
|---|---|---|
| **must land** | F1 heartbeat off the waiting path · F2 two false denies · F3 missing Python, the `check:` bug | the speed and the honest-command complaints; no new concept for the user |
| **must land for "switchable"** | F4 level and per-rule switch · F5 the switch is human-only · F6 strict means on | F4 without F5 would let the model switch a guard off for itself, so they ship together or not at all |
| rides along | F0 measure · F7 doctor · F8 docs | F0 and F8 make the numbers honest; F7 proves the hooks are live |
| optional, the owner's yes | F9 a hung guard blocks | static for every user; see §11 |
| not in this release | brief §4 | |

**Cut line.** F0, F1, F2, F3, F7, F8 are a complete release on their own (about 3.25 days). F4, F5, F6 can follow as a second cut (§10).

## 4. Features (build order in §5)

### F0 — measure first (0.25 day, no code)
**What.** Record "before" on 0.6.0 as pushed. **Method M**, used again for "after":
1. On the laptop, load the dev branch as the plugin and start Claude Code with a debug file (`claude --debug-file <file in the gitignored scratch folder>`), in a scratch repo with no adapter.
2. Send one fixed prompt: ten separate Bash calls (`echo 1` … `echo 10`), ten Reads of one file, five one-line Edits, then stop.
3. In the debug file take every `Hooks:` line for a smartuse command (Claude Code 2.1.296+ writes one per command hook, with its time). Waited per call = the longest blocking smartuse hook before the call plus the longest after it. A line that says `moved to the background` counts as zero.
4. Report the median per tool and for Stop. Run it twice; quote the slower run.
5. Also time ten bare interpreter starts with and without Python's `-S` option (no site import; ROADMAP's open "try `-S`" line).
**Acceptance.** The owner reads a six-row table with real seconds. If the debug file has no `Hooks:` line, say so and time the hook command on a recorded event instead.
**Tests.** None: no file changes. **Must not change.** Every file.

### F1 — the heartbeat leaves the waiting path (0.75 day)
**What changes.**
- `hooks.json`: `"async": true` on the heartbeat handler under PreToolUse (`:35–44`) and PostToolUse (`:88–99`). A *new* `PostToolUseFailure` block: matcher `*`, the same command, `"async": true`, timeout 5. Nothing else in the file.
- `heartbeat.py` `EVENTS` (`:61`) gains `PostToolUseFailure`; `apply()` (`:272`) treats it as PostToolUse: it clears `tool_running` and sets `last_tool`. The builder pins the event's field names from one real debug-log entry first (names only, never content).
- `done` *new* in `status.json`: the last 32 `tool_use_id`s that PostToolUse or PostToolUseFailure saw. A PreToolUse whose id is already in `done` counts the call but does not set `tool_running`: a "before" that lands late must not undo its "after". `fresh()` (`:225`) starts it empty; UserPromptSubmit empties it.
- `lock()` (`:203`): where `fcntl` is missing (Windows), lock one byte of `status.lock` with `msvcrt.locking` (stdlib), wait at most 1 s, then go on unlocked as today.
**Acceptance (what a person does and sees).** (1) Claude runs a three-minute command: within about a second the status line says `working · Bash running …` and keeps counting. (2) Claude reads ten files: no pause from smartuse between calls; the line ends at `last Read … · 10 calls this turn`. (3) A command fails: the line moves on to `last Bash`; it does not stay on `running`. (4) A permission prompt is open: the line says `waiting on you: permission prompt` (experiment E4). (5) The count in §0 holds: Bash 1, Read 0, Write 1.
**Unit tests (`heartbeat-test.sh`; each new case red on the old code first).** PostToolUseFailure after PreToolUse clears `tool_running` (old: the event is ignored). PostToolUse then a late PreToolUse of the same id: the line stays `last Bash`, one call counted (old: `running`). A PreToolUse with a new id after that: `running`. `done` holds 32 at most and empties on a prompt. Twenty events fired at once with different ids: `status.json` parses and counts 20, on POSIX and on Windows. A *new* `hooks` check reads `hooks.json`: the three heartbeat tool handlers are async; no handler that runs bash-guard, file-guard, ledger, until-done, wait-gate or recall is; blocking smartuse handlers per call are Bash 1, Read 0, Write 1 before and 0 after. Every hook run still prints nothing.
**Integration test.** `ci.yml` as it is (three OSes); `claude plugin validate --strict plugins/smartuse` accepts the fields (E1).
**Interactive scenario.** One session on the laptop with the status line installed: the five acceptance steps, then method M for the "after" numbers.
**Files.** `hooks.json`, `heartbeat.py`, `heartbeat-test.sh`.
**Must not change.** The wording of every status line; the existing keys of `status.json`; SessionStart, UserPromptSubmit, Notification, Subagent, Stop and SessionEnd handlers stay blocking with their timeouts; "prints nothing"; the two `hooks.json` checks in other suites pass unedited.
**T1.** `bash plugins/smartuse/hooks/tests/heartbeat-test.sh`.

### F2 — two false denies fixed; the rule for changing RULES (0.75 day)
**What changes (`bash-guard.py`).**
- `RULE_NAMES` *new*: a tuple beside `RULES`, same length, same order: `pipe-to-shell`, `download-exec`, `sudo`, `rm-root`, `chmod-open`, `credential-file`, `sql-destructive`, `force-push`, `human-only`, `fake-tty`, `trust-pin`, `svn-revert`. `RULES` keeps its shape and, in F2, every string.
- `waived(name, text, ps)` *new*, called in the `RULES` loop (`:1354`) after a match. It can say yes for two classes only, and never for a text `complexity()` (`:753`) tags or a segment `words()` (`:90`) cannot split cleanly:
  - **A download piped into an interpreter that was given its own program.** The interpreter is Python, Node or Perl, not a shell and not behind `sudo`, and its words name a module, a program text or a script file that is not standard input. Built from `words()` and the test in `reads_stdin_as_code()` (`:105`).
  - **The word `sudo` carried as text.** Every match sits in an argument of a command that only carries text: the message options of `git commit`, `git tag` and `git notes`, `echo`, `printf`, `grep`, `rg`, the title and body options of `gh`. The word holds no command substitution, and no segment has `sudo` or `doas` as its command word (`command_segments()` `:617`, `command_start()` `:863`).
- For these two rules the loop looks at every match (`re.finditer`), because a waiver must cover all of them. The other rules keep `re.search`.
**Acceptance.** (1) These run: `curl -s <url> | python -m json.tool`, the same into `python3 -c "<program>"`, `git commit -m "fix sudo handling in the docs"`, `grep -rn "sudo " docs/`. (2) These are still denied: a download piped into a shell, into a bare interpreter, or behind `sudo`; `sudo` as a command word wherever a command can start (after a separator, inside a compound, in a string handed to a shell, in a command substitution inside a message, behind a runner). (3) The commit-message case also runs through the PowerShell tool.
**Unit tests (`run.sh`; red first by running the suite before the edit).** About 10 allow cases for (1), quoted and unquoted. About 14 deny cases that pin each edge named in (2), one per class. One long dense text ending in a real `sudo`: denied in under 1 s, timed inside the process. `RULE_NAMES` and `RULES` have the same length. `fresh-gate-test.sh:1351` (the run without `main()`) still passes. **The differential** (§6 rule 3): old guard against new over every command string in `run.sh` and `fresh-gate-test.sh`, both tools; the only flips are the new allow cases.
**Integration test.** `ci.yml` as it is.
**Interactive scenario.** Ask Claude to pretty-print a JSON URL with curl and `python -m json.tool`, then to commit with a message that mentions sudo: both run. Ask it to run a command with sudo: denied with the sudo reason.
**Files.** `bash-guard.py`, `run.sh`.
**Must not change.** `RULES` strings and order; `HEREDOC`, `strip_heredocs`, `opener_line`, `STATE_CALL`; every existing case's result; the reasons' first words.
**T1.** `run.sh`, then `fresh-gate-test.sh`, one at a time.

### F3 — say so when Python is missing; the empty `check:` bug (0.5 day)
**What changes.**
- `py.sh`: one optional first word, `--say-missing`, compared as an exact word and dropped before the hook path. With an interpreter: no change at all. Without one: a fixed sentence on stderr and `exit 2`. Without the word: silent `exit 0`, as today (`:40`).
- `hooks.json` `:139`: the SessionStart heartbeat command gets `--say-missing`. The docs say a SessionStart hook that exits 2 "Shows stderr to user only" and the session goes on.
- `until-done.py:105`: the `check:` value ends at its own line end. Copy the pattern and comment of `recall.py:166`.
- Optional, decided by F0: start hooks with `-S` if it saves 30 ms or more per start and every suite stays green.
**Acceptance.** (1) On a machine with no Python, at session start the user reads: `smartuse: Python 3 was not found (tried python3, python, py -3). Its guards, gates and status line are OFF. Install Python 3.9 or newer and restart Claude Code.` Tool calls keep working. (2) With Python, nothing new is printed. (3) An adapter with an empty `check:` line and another line under it: the gate has no check; it no longer takes the next line.
**Unit tests.** `heartbeat-test.sh`, launcher block (`:297–335`): `--say-missing` with no interpreter → the sentence on stderr, exit 2, empty stdout; with an interpreter → the hook runs as before; no word and no interpreter → silent exit 0 (`:308` unchanged); the word in any later position reaches Python untouched; the remembered-name path with the word. `until-done-test.sh` +4: an empty `check:` above a line that is itself an allowed shape (red on the old code, which runs it); `check:` with only blanks; CRLF; a normal check unchanged.
**Integration test.** `ci.yml` as it is (`bash -n py.sh`, both suites on three OSes).
**Interactive scenario.** Start Claude Code from a shell whose PATH has no Python: the sentence shows once. A remembered name that PATH no longer has is probed again (`py.sh:13`), so no file needs touching.
**Files.** `py.sh`, `hooks.json`, `heartbeat-test.sh`, `until-done.py`, `until-done-test.sh`.
**Must not change.** The launcher's cache rules (a name, never a path, never through a link) and its lines `:19–39`; `PYTHONUTF8`; one start per event; until-done's fixed shapes, trust rules and block JSON.
**T1.** `heartbeat-test.sh`, then `until-done-test.sh`.

### F4 — a guard level and a switch per rule (1 day, after F2)
**What changes.**
- `plugin.json`: `userConfig` *new*, three options, each with `type`, `title`, `description`, `default`:
  - `strict` — boolean, "Strict guards", default off. "Off: the light set. On: every rule, the wait gate, and guards that fail closed."
  - `rules_off` — string, "Rules off", default empty. "Rule names to switch off, separated by commas. Each deny message prints its rule name. Ignored when Strict is on."
  - `wait_gate` — boolean, "Wait gate", default off. "Block a hand-off once when nothing is armed to wake the session. Always on in Strict."
- `bash-guard.py` `options()` *new*: reads `CLAUDE_PLUGIN_OPTION_STRICT` and `CLAUDE_PLUGIN_OPTION_RULES_OFF` from the hook's own environment. Missing → light, nothing off. Unreadable → strict.
- `RULES`: two alternatives move into their own entries, each placed right after its parent with the same reason: `--force-with-lease` out of the force-push pattern (`:65`) → `force-with-lease`; the `secrets` folder alternative out of the credential pattern (`:57`) → `secrets-dir`. `RULE_NAMES` gains both. Under strict the result is 0.6.0's.
- `LIGHT_OFF` *new* = those two names. `FLOOR` *new* = `human-only`, `trust-pin` (and `config-switch`, F5).
- The loop skips a rule when the level is light and its name is in `LIGHT_OFF` or in `rules_off`, unless it is in `FLOOR`.
- `deny()` (`:1306`) appends ` [rule <name>]`, or ` [rule <name>, always on]` for a floor rule. The first words of every reason stay.
- Strict only: an unexpected error in `main()` denies with "internal error; strict guards fail closed". Light: as today.
- `run.sh` and `fresh-gate-test.sh` export `CLAUDE_PLUGIN_OPTION_STRICT=true` at the top: the 0.6.0 cases are the strict bar. A new light block sets it off.
- `until-done.py` is not touched. Its check screen still gets every rule.
**Acceptance.** (1) After the update, nothing configured: `git push --force-with-lease origin x` runs and `cat config/secrets/readme.md` runs; `git push --force` is denied and the reason ends `[rule force-push]`; a read of a private key is denied, `[rule credential-file]`. (2) The owner opens `/plugin configure smartuse@smartuse`, types `force-push` into Rules off: `git push --force` runs. He types `human-only`: still denied, `[rule human-only, always on]`. (3) He turns Strict on: the two light classes are denied again and Rules off is ignored. (4) A misspelt name changes nothing; doctor names it (F7).
**Unit tests (`run.sh`).** Strict block: all 272 existing cases unchanged. Light block, about 25: the two light classes allowed; each of the ten switchable names, switched off, allows its own deny case and no other rule's; a floor name is ignored; an unknown name is ignored; commas and blanks both separate; an unreadable strict value is strict; strict ignores `rules_off`; the reason's suffix; four PowerShell twins; a forced internal error denies under strict and allows under light.
**Integration test.** `claude plugin validate --strict plugins/smartuse` accepts the three options (E1); `ci.yml` as it is.
**Interactive scenario.** The four acceptance steps on the laptop, plugin installed from the repo as a local marketplace. Record the exact text Claude Code passes for an on/off option (E2) and whether a change works in the running session or after a restart (E3).
**Files.** `plugin.json`, `bash-guard.py`, `run.sh`, `fresh-gate-test.sh` (the one export line).
**Must not change.** Every 0.6.0 result under strict; the fresh-source gate, `complexity()` and their order; what until-done sees in `RULES`; the frozen names of §6.
**T1.** `run.sh`, then `fresh-gate-test.sh`.

### F5 — the switch is human-only (0.75 day: F5a 0.25 after F4, F5b 0.5)
**The rule.** The model must not switch a guard off for itself. How that is prevented, exactly:
1. **No smartuse switch exists outside Claude Code's options.** No file, flag, environment variable of a tool call, skill or typed word changes the level. Skills never write options.
2. **Hooks read the level from their own environment.** Claude Code sets it when it starts the hook. A command the model runs cannot change another process's environment.
3. **file-guard denies an edit that would change the switch.** Write, Edit and MultiEdit on a Claude Code settings file are compared before and after on three values: this plugin's options, its on/off entry, and the switch that turns all hooks off. Any difference is denied. Other edits to the file pass.
4. **bash-guard denies the shell routes, by text.** The plugin command's configure, enable, disable and uninstall verbs for this plugin, an install that sets options, and a write to a settings file that names one of the three values. This rule is on the floor.
5. **A change is visible.** At the next session start one line names the rules that are off; the status line carries `· N rules off`; doctor prints the level.
6. **Claude Code's own layer stays in front** where it exists: a file-tool write into the `.claude` folder is prompted in default mode and goes to the classifier in auto mode (brief §5, "Protected paths"). In bypass mode it is allowed, so the two hooks above are the only layer there.
**Honest limit, said once.** Point 4 reads text. A write hidden inside another program, or a command built at run time, is not seen: the same class as the adapter's known limit on the ROADMAP. Points 5 and 6 still hold then. This limit gets no deeper parsing.
**What changes.**
- F5a, `bash-guard.py`: one *new* `RULES` entry at the end, name `config-switch`, reason "switching smartuse's guards is the owner's action: /plugin configure or /config".
- F5b, `file-guard.py`: `switch_change(path, tool_input)` *new*. The target is a settings file when it is `settings.json` or `settings.local.json` in a `.claude` folder or in the folder `CLAUDE_CONFIG_DIR` names; matched as written, as Windows reads it, and resolved, as the human-only files are (`:50–60`). It builds the text the edit would leave and compares the three values. A result it cannot parse, or a file over 1 MB, is denied when the edit names one of the three values (fail closed) and allowed when it names none.
- F5b, `heartbeat.py`: SessionStart stores `config` *new* (`strict`, `rules_off`, `wait_gate`, as the hook sees them) in `status.json`; `--line` adds ` · N rules off` while valid names are off and strict is not on; SessionStart prints one message for the user naming those rules (E5 picks the form). Otherwise the hook still prints nothing.
**Acceptance.** (1) The owner says "switch off the force-push rule for me". Claude's edit of the settings file is denied: `file-guard: this edit would change smartuse's switches. That is the owner's action: /plugin configure or /config.` A try through the plugin command is denied, `[rule config-switch, always on]`. (2) Claude adds a status line to the same settings file: allowed. (3) The owner switches a rule off himself: the next session start shows `smartuse: rules off: force-push` and the status line shows `· 1 rule off`.
**Unit tests.** `file-guard-test.sh` about +20: for each of Write, Edit and MultiEdit, a change to each of the three values is denied; an unrelated key, a rewrite that changes nothing and a first write without the plugin are allowed; an unparsable result that names a value is denied, one that names none is allowed; Windows spellings and a link to the file; a project settings file that turns the plugin off is denied. `run.sh` about +10: each class of point 4 denied; allowed: reading a settings file, listing and validating plugins, installing another plugin, a settings write that names none of the values. `heartbeat-test.sh` +6: `config` stored; the suffix; the message only when a rule is off.
**Integration test.** `ci.yml` as it is.
**Interactive scenario.** The three acceptance steps live, once in auto mode and once in bypass mode.
**Files.** F5a: `bash-guard.py`, `run.sh`. F5b: `file-guard.py`, `file-guard-test.sh`, `heartbeat.py`, `heartbeat-test.sh`.
**Must not change.** file-guard's three readings and its fail-closed resolve; reading a settings file; edits to any other file.
**T1.** F5a `run.sh`; F5b `file-guard-test.sh`, then `heartbeat-test.sh`.

### F6 — strict means on: the wait gate and the launcher follow the level (0.5 day)
**What changes.**
- `wait-gate.py` `gate_on()` *new*: true when strict or `wait_gate` is on. `main()` (`:584`) leaves at once when it is false, before any file is read. The adapter's `wait_gate: off` (`:229`) still wins per project.
- `py.sh`: a second optional first word, `--guard`. No interpreter and strict → the sentence on stderr and `exit 2`, which blocks the call and shows Claude why. Light → `exit 0` as today.
- `hooks.json`: the three guard commands (`:10`, `:20`, `:30`) get `--guard`. The Bash entry and the tool entry keep identical commands.
- `file-guard.py`: under strict an unexpected error denies.
- `wait-gate-test.sh` exports strict at the top; its 187 cases are the strict bar.
**Acceptance.** Light: Claude ends a reply with "I'll check back when the build finishes": no block, and the end of a turn on a long session is quicker (method M). Strict: the hand-off replay blocks once, as today. Strict on a machine without Python: a Bash call is refused with the sentence.
**Unit tests.** `wait-gate-test.sh` +6: under light the incident transcript passes with no output and no `wait.json`; `wait_gate` alone turns the gate on; the adapter's off beats strict. `heartbeat-test.sh` +3 for `--guard`. `file-guard-test.sh` +2 for the strict error path. The `hooks.json` checks at `fresh-gate-test.sh:1296` and `wait-gate-test.sh:983` pass unedited.
**Integration test.** `ci.yml` as it is. **Interactive scenario.** The light and strict steps above in one session each.
**Files.** `wait-gate.py`, `wait-gate-test.sh`, `py.sh`, `hooks.json`, `heartbeat-test.sh`, `file-guard.py`, `file-guard-test.sh`.
**Must not change.** The gate's phrases, its block text, `wait.json`'s shape, "blocks once per scope"; the Stop order and timeouts.
**T1.** `wait-gate-test.sh`, `heartbeat-test.sh`, `file-guard-test.sh`.

### F7 — doctor: proof that the hooks are live (0.5 day, after both tracks merge)
**What changes.**
- `skills/doctor/SKILL.md` *new* (`/smartuse:doctor`), shaped like the status skill.
- `heartbeat.py --doctor` *new* renderer, read-only, at most eight lines: the Python it runs on; the plugin version; the events `hooks.json` registers; the age of the last heartbeat event in this session ("no event: the hooks are not firing, restart Claude Code"); the level, the rules off and any unknown name (from `config`); whether the state folder can be written.
- Two canaries. `bash-guard.py` denies the exact command `: smartuse-doctor-canary` (a no-op if the guard is down) with "doctor canary — the guard is live" and the level. `file-guard.py` denies a write to one fixed canary file in the state folder the same way. Both compare one exact string, so they deny nothing else.
- The skill prints the renderer's lines, has Claude try both canaries, and reports five lines: Python, hooks registered, heartbeat live, bash-guard live, file-guard live. Each is PASS or FAIL with the fix the tool printed.
**Acceptance.** The owner types `/smartuse:doctor` and reads five PASS lines and the level. With the plugin disabled or Python missing he reads which line fails and what to do.
**Unit tests.** `heartbeat-test.sh` +6 (`--doctor` with a fresh event, a stale one, no state, an unknown rule name, an unwritable state folder); `run.sh` +2 and `file-guard-test.sh` +2 (the canaries deny; a near-miss string does not).
**Integration test.** `claude plugin validate --strict plugins/smartuse` lists the new skill. **Interactive scenario.** Run it live in a healthy session, then once with the plugin disabled.
**Files.** `skills/doctor/SKILL.md`, `heartbeat.py`, `heartbeat-test.sh`, `bash-guard.py`, `run.sh`, `file-guard.py`, `file-guard-test.sh`.
**Must not change.** The status skill; nothing is written outside the state folder; no model call, no subprocess.

### F8 — docs, counts, ROADMAP, version (0.5 day, after T2)
**What changes.** `README.md` (the measured before-and-after row, a short "Switches" section, the Windows paragraph, the counts badge); `SECURITY.md` (what light turns off, the human-only switch, its limit by class); `CHANGELOG.md` (a 0.6.1 section that opens with "Changed defaults"); `plugins/smartuse/README.md`; the version in `plugin.json` **and** `.claude-plugin/marketplace.json`; `docs/ROADMAP.md` (§7 below); `docs/notes/recall-design.md` (its `RULES` line points at §6 here); `docs/STATUS.md`; `skills/status/SKILL.md:25`; one line in `plugins/smartuse/docs/security-profiles.md` saying its "profiles" are permission presets, not the guard level.
**Acceptance.** `python3 scripts/term-scan.py --history` shows 0 hits; `claude plugin validate --strict` passes for the plugin and the marketplace; every number is a suite's last line or a method M measurement; no limit is described by its method.
**Tests.** `bash scripts/term-scan-test.sh`; the CI `validate` job. **Interactive.** The owner reads the CHANGELOG entry on the phone and finds each claim backed by a case or a number.

### F9 — optional, needs the owner's yes: a hung guard blocks the call (0.25 day)
`"onFailure": "block"` on the three guard handlers. Confirmed in the docs (brief §5, claim 1). Not planned by default, for three reasons: it is one static field for light and strict alike; on a machine where the hook cannot start at all, every Bash and Write call would be blocked; and the 1.0 bar says the hooks never block a turn by mistake. F6 already makes strict fail closed where the hook itself decides. If the owner says yes: add the field, a doctor line, and reword the 1.0 bar.

## 5. Build order, worktrees, tiers
**Two tracks, different files, so two worktrees can run side by side.**
| Track | Order | Files it owns |
|---|---|---|
| A — rules | F2 → F4 → F5a | `bash-guard.py`, `run.sh`, `fresh-gate-test.sh`, `plugin.json` |
| B — the rest | F1 → F3 → F5b → F6 | `hooks.json`, `heartbeat.py`, `heartbeat-test.sh`, `py.sh`, `until-done.py`, `until-done-test.sh`, `file-guard.py`, `file-guard-test.sh`, `wait-gate.py`, `wait-gate-test.sh` |
Then, one builder after the merge: F7. Then F8. F0 runs before anything, by the orchestrator.
- Worktrees are made by hand from the dev branch head; a builder's first command is `git log -1`.
- Each builder runs one suite at a time. Track B never runs `run.sh` or `fresh-gate-test.sh`. If the laptop slows, run the tracks one after the other (about 1.5 days more).
- **Approvals.** The auto-mode safety check refused a rule edit once (security plan §7i). Expect up to three prompts on track A (F2, F4, F5a) and up to two on track B (`file-guard.py`, `hooks.json`). The orchestrator asks for track A's in one sitting.
- **Days.** Build: 2 days side by side. Merge, T2 and the fresh review: 1 day. F7, the interactive pass and F8: 1 day. Started Mon 16 Nov, it is ready to push Thu 19 Nov, a week before the reach check.

**Tiers.**
- **T1, the builder, after every change:** the suites named in the feature, one at a time.
- **T2, after each merge and before each commit, every suite, one at a time, in this order:** `file-guard-test.sh`, `ledger-test.sh`, `until-done-test.sh`, `watch-test.sh`, `heartbeat-test.sh`, `wait-gate-test.sh`, `recall-test.sh`, `run.sh`, `fresh-gate-test.sh` (each as `bash plugins/smartuse/hooks/tests/<name>`), then `bash bench/tests/ab-test.sh`, then `bash scripts/term-scan-test.sh`. The parallel `all.sh` runs this laptop out of memory; it stays the one-command gate for bigger machines and CI runs the suites as separate steps. Floor, counts only grow: `run 272 · ledger 46 · until-done 40 · file-guard 26 · heartbeat 121 · ab 36 · watch 63 · wait 187 · fresh 722 · recall 210 · term-scan 6`.
- **T3, before the push:** T2, then `claude plugin validate --strict plugins/smartuse` and `claude plugin validate --strict .`, then the interactive pass (every feature's scenario, experiments E1–E5, method M "after"), then `python3 scripts/term-scan.py --history` with 0 hits.

**Restate in every builder brief.** Only the files the feature names. Edit tool, no whole-file pastes. Cases first, red on the unchanged code. Python only through `py.sh`; one command per shell call; `git -C <dir>`. Never write `.claude/*.local.md` or `.smartuse-terms.local`. Public repo: describe a problem by its class, never by the steps to use it; no personal paths or names. Builders never commit.

## 6. Must not change (every feature), and the new rule for RULES
- At most one Python start per hook event; no subprocess, no second interpreter, no model call, no network, no store; Python 3.9 stdlib; no import between hooks.
- In light a hook never blocks by mistake: no interpreter means `exit 0`. Strict fails closed only where F4 and F6 say.
- Under strict every existing case in every suite keeps its result. Suite counts only grow.
- `RULES` stays a list of `(pattern, why)` in today's order; `until-done.py`'s run of bash-guard without `main()` still prints nothing and yields `RULES`.
- `HEREDOC`, `strip_heredocs`, `opener_line`, `STATE_CALL`, `STATE_SHAPE` stay byte-identical. The fresh-source gate, `complexity()`, `BUDGET_S` and the order in `main()` are not touched by any level or switch.
- The deny JSON shape; the first words of every reason; nothing printed on allow.
- The human-only files stay human-only; the adapter is read, never written; state holds counts, names and paths, never a command; nothing is written inside the repo.
- `hooks.json`: one shell PreToolUse entry, matcher `Bash|PowerShell`; one tool entry with the same command; the Stop order and timeouts; no guard or Stop gate in the background.
- The status line's existing wording; Windows Git Bash behaviour (`native_path`, the cp1252 stdin case, `PYTHONUTF8`); `all.sh` NAMES and `ci.yml` steps.

**The rule for changing `RULES`** (this replaces "RULES strings and order frozen" of the security plan §6):
1. A change names the class of honest command it frees or the class of harm it stops.
2. Cases first. Every changed or new rule ships with cases that fail on the old code: allow cases for a narrowing, deny cases for a widening. The red run is quoted in the commit message.
3. A differential over every command string in `run.sh` and `fresh-gate-test.sh`, both tools, old guard against new. Every deny-to-allow flip is on the change's own list; an unlisted flip stops the merge.
4. Each changed pattern or waiver has one timing case: a long dense text decided in under 1 s inside the process.
5. Narrow by a waiver after the match or by moving an alternative into its own named rule (§2, 15). Strict keeps every 0.6.0 deny except the two classes F2 lists.
6. One fresh review of the rule diff before the merge, and the owner approves the edit at the prompt.

## 7. If days run out, and what changes in ROADMAP
**Drop order, last first to go:** F9 (not planned) → F5b's status-line suffix → the `-S` option → F7's file-guard canary → F6's `wait_gate` option (the gate is then simply off unless strict) → the second cut as a whole (F4, F5, F6) to a later release. F1, F2 and F3 are not dropped.

**ROADMAP.**
- `0.6.1` becomes "lighter, faster, switchable" (this plan).
- Today's 0.6.1 list moves to "0.6.2 — parked follow-ups": removing the dead code paths of rounds C–F and the Windows long path stay as planned work; "recognise more ways of handing a command to another shell" and the PowerShell tokenisation pass are built only when a real miss is reported.
- `0.7.0` stays the paid-call guard. Its `onFailure` line gets the confirmed facts (v2.1.295; what counts as failure; no effect on Stop and background hooks) and points at F9.
- Closed by this release: 0.5.0's "still ~3 s per Bash call … lighter heartbeat" line (with F0's numbers) and "bash-guard false positive: `curl … | python3 -c`".
- The 1.0 bar "the hooks never block a turn by mistake" gains "in the light level".

## 8. Unknowns, each an experiment in the interactive pass
| # | Unknown | Experiment | If it goes the other way |
|---|---|---|---|
| E1 | Does `claude plugin validate --strict` accept `async`, the PostToolUseFailure block and the three options? | run it on the laptop and in CI | drop the field it rejects and say so |
| E2 | The text Claude Code passes for an on/off option, and whether a default is passed when the user never opened the dialog | a scratch hook prints its environment to a scratch file | `options()` already reads on, true, yes, 1 and their opposites; a missing value is light |
| E3 | Does a changed option work in the running session, or after a restart? Does enabling the plugin open a dialog when every option has a default? | change one in `/plugin configure` mid-session and run a denied command | the docs and the deny text say "restart Claude Code" |
| E4 | With the before-heartbeat in the background, does the line still say `waiting on you: permission prompt` while a prompt is open? | a Bash call that needs approval, watched for 30 s | the Notification handler goes to the background too, so the order holds |
| E5 | Does the user see a SessionStart hook's `systemMessage`? | the F5 message with one rule off | print it on stderr with exit 2, which the docs say the user sees |
Assumed, not tested: an older Claude Code ignores a hook field or event it does not know. The README's floor (2.1.300) is above every field used.

## 9. Risks
- **Another hardening spiral.** F5 adds a guard surface. It reads three values and a few verbs, by text, with its limit written once. A review finding beyond that class goes to the limits list, not into a fix round.
- **A waiver frees a real harm.** F2's waivers are an allow list of text-only commands; the differential and the strict bar catch a stray flip.
- **Changed defaults surprise a user.** The CHANGELOG opens with them; Strict is one switch.
- **Background writes out of order.** The lock and the `done` ids cover it; E4 checks the one case they cannot.
- **Headless runs.** In `-p` mode a background hook still running at the end is cancelled. Stop and SessionEnd stay blocking, so the last state is written. The CI eval run after the push checks it.
- **The safety check refuses a rule edit again.** Then that feature waits for the owner; track B does not depend on it.
- **One word, two meanings.** "Light" also names a mode in the owner's private setup. Deny and status texts here say "guards: light".
- **Time.** Another project has first call on the owner's hours. The cut line in §3 and the drop order in §7 keep a release shippable after about three days.

## 10. The one counter-proposal
Ship this in two cuts, and decide one thing in between. Cut 1 is F0, F1, F2, F3, F7 and F8: faster, two false denies gone, honest about Python, doctor. It is about 3.25 builder-days, adds no new concept and no new guard surface, and can be pushed by Tue 17 Nov with days left for the post and the README before the reach check. The switch (F4, F5, F6) is about 40 % of the work, changes the defaults for every user, needs the owner at the prompt for each rule edit, and adds the one thing last week showed to be expensive: a new guard that reviewers will try to break. Its need is also unproven until cut 1 is in use: if no honest command is denied any more, a per-rule switch may never be flipped. And before the switch's protection is built, one question deserves a yes or no: should the regex safety floor exist in 1.0 at all, or should it move to Claude Code's own deny rules, which are per-rule, edited by the user, cost no process start and, in the docs' words, are the place "to enforce a hard allow or deny"? If the floor moves, the switch and its protection are not needed.

## 11. Questions only the owner can answer
1. **Is the light set right?** Light switches off `force-with-lease` and `secrets-dir`, and the wait gate. Named key and credential files, `sudo`, forced pushes, root deletes and download-then-run stay on. **Recommended: yes as listed.** If a folder named `secrets` in your repos really holds secrets, keep `secrets-dir` on in light.
2. **Where do you flip the switch?** This plan gives a screen in Claude Code at the laptop (`/plugin configure`, `/config`). Flipping it from the phone by typing a word needs the owner-quote check of 0.7.0. **Recommended: laptop only for now.**
3. **A guard that hangs: block the call, or let it through?** Blocking (F9) is safer but is one setting for everyone, and a machine that cannot start the hook would have every call blocked. **Recommended: let it through in 0.6.1, as today; decide with the paid-call guard in 0.7.0.**

## 12. Card A
```
FINISH LINE: smartuse 0.6.1 "lighter, faster, switchable"
So you want: guards that stop slowing you and stop blocking honest commands, with a switch only you can flip
Sample: docs/notes/light-fast-plan.md §0 | Bash call: 3 hooks waited → 1 · Read: 2 → 0 · a deny ends "[rule force-push]"
Done when: 1 ten Reads and ten Bash calls show 0 and 1 smartuse hooks waited on 2 you turn Strict on, or name a rule in /plugin configure, and the next deny follows it 3 you ask Claude to switch a rule off and it is refused
Proven on: the author's laptop, this repo's dev branch loaded as the plugin, one real session (method M) | synthetic: the suites' event JSON
Unknown: E1–E5 → experiments in the interactive pass (§8) | assumed: an older Claude Code ignores a field it does not know
Not in this: paid-call guard · more shell parsing · removing the launcher · README rewrite · a switch from the phone
Alt: ship speed and the false-deny fixes first (about 3 days), build the switch after the reach check (§10)
Tap: 1 yes · 2 send a reference · 3 no
```

## 13. Approval and decisions (2026-11-10)
- The owner approved the whole plan, F0 to F8, both cuts, the same day it was written. F9 stays out: nobody asked for it.
- §11's three questions were not answered one by one, so the recommended answers stand as defaults and the owner may veto any: the light set as listed; the switch at the laptop only; a hung guard lets the call through in 0.6.1.
- Decided by the orchestrator (owner may veto): in F4 the `~/.claude.json` alternative that the security plan §7i removed comes back as its own named rule, `claude-json`, placed after `credential-file` with the same reason, and it is in `LIGHT_OFF`. Light, the default, behaves as 0.6.0 does today (the read runs); strict denies it, as 0.5.1 did. This follows §2 decision 15 (narrow by a named rule, never by deleting an alternative) and answers the automated security review of the 0.6.0 push, which asked for an opt-in instead of a removal. `run.sh`'s `cat ~/.claude.json` case is a deny under strict and an allow in the light block.
- The build runs the two tracks side by side only while the laptop keeps up; F0's "before" numbers are taken first, with no suite running.
- Decided by the orchestrator after an automated security review of F2 (owner may veto): the download-into-interpreter waiver is narrowed to an allow list. Only a download piped into Python run as `-m json.tool` (plus plain text filters) is freed. Program texts, script files, Node and Perl are denied again, as in 0.6.0. A deny list of risky module names and code words can never be complete, which is the race §7e of the security plan gave up.
- Decided by the orchestrator after an automated security review of F4 (owner may veto; §11 question 1 allowed it): `secrets-dir` stays on in light. Light switches off only `force-with-lease` and `claude-json`; `secrets-dir` can be switched off by name through Rules off. A public plugin cannot know that a folder named `secrets` holds no secrets.

## 14. Review 11 (2026-11-10, of 556b332): decisions
Review 11 (Opus, xhigh): F1–F6 and the three §13 decisions PASS; frozen names, complexity() and the gate order untouched; honest settings edits (a status line, a permission, another plugin's options) allowed. Two majors outside F5's named limit, decided by the orchestrator (owner may veto), one fix round, no more:
- **M1.** config-switch caught a settings write only when the command named one of the keys, so a command that deletes, moves or replaces a whole Claude Code settings file passed, and the plugin command's marketplace-level remove verb was not listed. Fix: config-switch also denies a delete, move, copy-over, truncate or redirect whose target is a Claude Code settings file (settings.json or settings.local.json in a `.claude` folder), whatever the text names, and the marketplace remove verb for smartuse's marketplace. Reading such a file stays allowed.
- **M2.** A settings file's `env` block can set the `CLAUDE_PLUGIN_OPTION_*` variables the hooks read. Fix: file-guard's compared values include every `env` entry whose name starts with `CLAUDE_PLUGIN_OPTION_`, and config-switch treats that prefix as a key name. Experiment E2 also records which value wins when both an option and an `env` entry are set.
Minors, recorded and not fixed in 0.6.1:
- The three split-out rules reuse their parents' heads, which are slow on a long dense text (seconds at 30 KB; the parent credential rule was already past the hook timeout there). Same class as the ROADMAP item "every rule linear"; it moves up the list. §6 rule 4's timing case is met for the new patterns (config-switch, the waivers), not for heads copied unchanged.
- Background heartbeat events can land out of order across a turn boundary (a late "after" can reset a finished turn on the status line); status.json stays valid. The `done` list covers only a "before" landing after its own "after".
- config-switch reads text (the named limit): other spellings of the program name, writers outside its list, escaped key names and other path spellings are not seen.
- A hard link to a settings file has its own path (same gap as the human-only files since 0.5).
- A multi-line Edit of a settings file with CRLF line endings is denied, because its result cannot be computed and the file holds smartuse's entry: the accepted cost of failing closed.
- A switch from strict to light is not shown at session start or on the status line; doctor prints the level.
- The plugin's own installed files (hooks.json, the guards) are not guarded; editing them turns the guards off (since before 0.6.0).
