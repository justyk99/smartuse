# 0.6.1 — lighter, faster, switchable: brief (dev-flow phases 0–1, 2026-11-10)

Status: **brief written 2026-11-10. Nothing built.** The plan is `docs/notes/light-fast-plan.md`. Planner: flow-planner on claude-fable-5-2. Every file name and line below was grepped on the dev branch at 0.6.0. Every Claude Code fact was read in the official docs on 2026-11-10 (§5). Source of the ask: the seven-part review of 2026-11-10, section C, which the owner approved ahead of the paid-call guard.

## 1. The problem, in the owner's words
"The guards are too hard." Two things are meant.
- **They slow every tool call.** The plugin starts a process before and after each call, and Claude waits for it.
- **They deny honest commands,** and no rule can be switched off without editing the plugin's code.

Measured on the author's laptop (Windows 11, Git Bash, 2026-11-10):
| Fact | Where |
|---|---|
| One hook start costs 0.2–0.35 s: about 0.1 s for bash, 0.16 s for Python | measured |
| The heartbeat runs before and after every tool call | `hooks.json:36` and `:90` |
| A Bash call starts 3 smartuse hooks; a Read starts 2; the end of a turn starts 4 | `hooks.json` |
| Hooks of one event run side by side, so the wait is less than the sum | hooks reference; the plan's F0 measures it |
| A download piped into `python -m json.tool` is denied as "download then run" | `bash-guard.py:44` |
| The word `sudo` inside a commit message is denied | `bash-guard.py:48` |
| `git push --force-with-lease`, the safe force push, is denied | `bash-guard.py:65`, `run.sh:52` |
| Any path under a folder named `secrets` is denied for reader commands | `bash-guard.py:57`, `run.sh:92` |
| With no Python on the machine every guard is off and nothing says so | `py.sh:40` (silent `exit 0`) |
| An empty `check:` line makes the next line the check command | `until-done.py:105` |
| The wait gate reads the whole transcript at every stop and blocks plain phrases | `wait-gate.py:597`, `:102–109` |

One correction to the review: it said listing `~/.ssh` is denied. `ls ~/.ssh` is allowed (`run.sh:120`). What is denied is naming the folder in a reader command such as `find`, `grep` or `cp`. That alternative also stops a wildcard read of every key in the folder, so the plan leaves it alone.

## 2. Who it is for
1. **The owner.** A solo developer on a Windows laptop who drives sessions from a phone and wants plain words.
2. **A stranger** who installs the plugin in 30 seconds. The plugin must not be felt until it stops a real mistake.
3. **A careful user** who wants every guard on. One switch gives that.

## 3. Done: what a person does and sees
1. Claude reads ten files in a row. No smartuse hook is waited on. A Bash call waits on one. The status line still says what is running.
2. In the default (light) level these run with no deny: a download piped into `python -m json.tool`, a commit whose message contains the word sudo, `git push --force-with-lease`, a read under a `secrets` folder.
3. The owner opens `/plugin configure smartuse@smartuse` (or `/config`) and turns "Strict guards" on, or types a rule name into "Rules off". No file is edited. Every deny message ends with its rule name.
4. The owner asks Claude to switch a rule off. Claude is refused and told it is the owner's action.
5. On a machine without Python, one line at session start says the guards are off.
6. `/smartuse:doctor` prints five PASS or FAIL lines that prove the hooks are live in this session.
7. The CHANGELOG shows seconds waited per call, before and after, measured the same way.

## 4. Out of scope
- The paid-call guard (0.7.0).
- More reading of shell text. The old 0.6.1 list is parked (plan §7).
- The fresh-source gate. No change and no switch: it is on only where the owner's adapter lists `sources:` and `publish:`.
- Removing the bash launcher, one process for several events, hooks served by a long-lived server. These are 1.0 questions.
- The README rewrite for a stranger, uninstall and privacy sections (review section D).
- Tuning the wait gate's phrase list.
- Switching a rule from the phone by a typed word. That needs the owner-quote check planned for 0.7.0.
- Per-project rule switches in the adapter.
- A memory store, a model call in a hook, a subprocess, any dependency. Hooks stay Python 3.9 stdlib.

## 5. Research: six claims, checked in the official docs on 2026-11-10
Quotes were copied on that day. A builder re-reads the section before using a field. Pages: [hooks] `https://code.claude.com/docs/en/hooks` · [guide] `https://code.claude.com/docs/en/hooks-guide` · [manifest] `https://code.claude.com/docs/en/plugins-reference` · [cli] `https://code.claude.com/docs/en/plugins/cli-reference` · [settings] `https://code.claude.com/docs/en/settings-reference`.

| # | Claim | Verdict | The docs say | What the plan does |
|---|---|---|---|---|
| 1 | `onFailure: "block"` makes a failed or timed-out command hook block the call; the default lets it through | **Confirmed** | [hooks], "Block the action when a hook fails": "On most events, when a hook fails or times out, Claude Code still carries out the action." · "To block the action instead, set `"onFailure": "block"` on a `command` or `http` hook. Requires Claude Code v2.1.295 or later." Failure means: cannot start, exit code other than 0 or 2, timeout, invalid output. "The field has no effect" on Stop, SubagentStop and background hooks | Not on by default. It is one static field for every user, and a machine that cannot start the hook at all would have every call blocked. Offered as optional F9, the owner's call. Strict fails closed without it where the hook itself decides (exit code 2) |
| 2 | `"async": true` on a command hook | **Confirmed** | [hooks], "Run hooks in the background": "Async hooks can't block or control Claude's behavior: response fields like `decision`, `permissionDecision`, and `continue` have no effect" · "This field is only available on `type: "command"` hooks." · "Claude Code doesn't enforce `timeout` on it." · "Each execution creates a separate background process." Its `additionalContext` and `systemMessage` reach Claude on the next turn and are not shown to the user | F1: the heartbeat's tool-event handlers go async. Guards and Stop gates never do |
| 3 | Plugin `userConfig`; a hook reads `CLAUDE_PLUGIN_OPTION_<KEY>`; the user changes a value after install | **Confirmed** | [manifest]: "`userConfig` declares values Claude Code prompts the user for when the plugin is enabled, so users don't edit `settings.json` themselves." Types: "`string`, `number`, `boolean`, `directory`, or `file`". "`CLAUDE_PLUGIN_OPTION_<KEY>`: exported to hook processes for every option, with `<KEY>` uppercased." "Non-sensitive values are saved under `pluginConfigs` in the user's `settings.json`." [settings] lists `pluginConfigs` as "User or managed". Change later: [cli] "`/plugin configure <plugin>` … Opens the plugin's `userConfig` dialog"; [manifest] "Each option of each enabled plugin also appears as a row in the `/config` panel" (v2.1.269+); [cli] `claude plugin configure <name@marketplace> --values-stdin` prints "Configuration saved. Restart Claude Code to apply it." (v2.1.285+) | F4: three options. A picker (`options`) is not used: the docs say users before v2.1.271 "can't load the plugin" then. Not in the docs: the text a boolean arrives as, and whether a change applies in the running session. Both are experiments (plan §8) |
| 4 | The `if` filter on tool-event hooks | **Confirmed, with limits** | [hooks], "Common fields": "The `if` field holds exactly one permission rule. There is no `&&`, `||`, or list syntax" · "Only evaluated on tool events" · "Because the `if` filter is best-effort, use the permission system rather than a hook to enforce a hard allow or deny." | Not used. A guard cannot be pre-filtered by one text rule, and file-guard must match every reading of a path |
| 5 | A hook without the bash launcher on Windows; several events served by one process | **Confirmed that the fields exist; they do not remove the launcher** | [hooks], "Exec form and shell form": "Claude Code resolves `command` as an executable on `PATH` and spawns it directly with `args` as the argument vector. There is no shell" · "On Windows, exec form requires `command` to resolve to a real executable such as a `.exe`." `shell` "Accepts `"bash"` or `"powershell"`." A `type: "mcp_tool"` hook calls a tool on a running server; "If the server isn't connected at that point, the hook produces a non-blocking error and execution continues", and at launch SessionStart skips such hooks | The launcher stays. No single interpreter name works on every OS (`python3` is a store stub on stock Windows; `py` exists only there), and a hook cannot be chosen per OS. A served hook cannot fail closed and is a new architecture: a 1.0 question |
| 6 | `PostToolUseFailure`, `PostToolBatch` | **Confirmed** | [hooks]: PostToolUse "Runs immediately after a tool completes successfully." PostToolUseFailure "Runs when a tool that started executing fails". PostToolBatch "Runs once after every tool call in a batch has resolved, before Claude Code sends the next request to the model." "There is no matcher for this event." | F1 adds PostToolUseFailure: today a failed call leaves "running" on the status line. PostToolBatch is not used: its minimum version is not stated |

Also read, and used by the plan:
- [guide]: "When an event fires, Claude Code runs the matching hooks in parallel".
- [hooks], exit code 2 per event: PreToolUse "Blocks the tool call"; SessionStart "Shows stderr to user only".
- [hooks], "Debug hooks": from v2.1.296 each command hook leaves a line such as `Hooks: PostToolUse:Write [...] finished with status 0 (31ms)`. This is the plan's measuring method.
- [hooks], `ConfigChange`: fires when a settings file changes in a session and can block the change. Not used (plan §2).
- `https://code.claude.com/docs/en/permission-modes`, "Protected paths": the `.claude` folder is protected. A file-tool write there is "Prompted" in default and acceptEdits, "Routed to the classifier" in auto, "Denied" in dontAsk and "Allowed" in bypassPermissions. So in bypass mode the plugin's own hooks are the only layer in front of the switch (plan F5).
- The README's floor is Claude Code 2.1.300. Every field used here needs 2.1.296 or older.

## 6. Own work first (the owner's knowledge base: reuse map, lessons, decisions; last entries 2026-11-10)
| Source | Verdict | Use here |
|---|---|---|
| Decision 2026-10-15: writable state never supplies a command | **reuse as-is** | The switch lives in Claude Code's own plugin options. No smartuse file, flag or typed word switches a guard |
| Lesson 2026-10-15: anchor a guard pattern to the segment that runs or writes | **reuse as-is** | F2: `sudo` counts only as a command word, never as text carried by a message |
| Lesson 2026-10-15: a heredoc body is data unless a shell consumes it | **reuse as-is** | The same "what reads standard input as code" test moves to pipes (ROADMAP's own note) |
| Lesson 2026-10-25: a path guard matches every reading and fails closed | **reuse as-is** | F5: the settings file is matched as written, as Windows reads it, and resolved |
| Lesson 2026-10-25: profile a slow step before naming its fix | **reuse as-is** | F0 measures before anything is built; targets are filled from it |
| Lesson 2026-10-25: release text claims what was measured; never an open gap's method | **reuse as-is** | F8's wording rule; limits are named by class |
| Lesson 2026-10-26: at most 2–3 heavy jobs at once on the laptop | **reuse as-is** | Two builders; one suite at a time each; T2 one suite at a time |
| Lesson 2026-11-05: a failure must be loud in the next session, never a silent flag | **reuse as-is** | F3: the missing-Python line; F5: a switched-off rule shows at session start |
| Lesson 2026-11-08: every "as today" claim in a builder brief gets a file:line | **reuse as-is** | The `~/.ssh` correction in §1 came from this check |
| Decision 2026-10-16 (class kits): no hooks, because trainees on Windows often lack Python | **adapt** | The plugin keeps hooks, but says so when Python is missing |
| `recall.py:166`, the adapter value pattern with its comment "an empty value must not swallow the next line" | **reuse as-is** | F3 copies it into `until-done.py:105` |
| `bash-guard.py` `words()` `:90`, `reads_stdin_as_code()` `:105`, `command_segments()` `:617`, `command_start()` `:863`, `complexity()` `:753` | **reuse as-is** | F2's two waivers are built from them; no new parser |
| `wait-gate.py:229` `gate_off()`, the adapter's `wait_gate: off` | **reuse as-is** | Stays as the per-project off switch; F6 adds the level in front of it |
| `heartbeat.py --json` and the status skill | **adapt** | F7: doctor is one more renderer and one more skill, not a new hook |
| The owner's private setup plugin: a "light / heavy" mode file written when the owner types a word, and a typed one-time allow | **avoid now, adapt later** | A mode file is state a model can write, so it must not switch a guard. The typed-word idea is the owner-quote check of 0.7.0. Its word "light" means something else there: deny texts here say "guards: light" |
| The same plugin's copy of this repo's shell reader | **avoid** | No second copy is made; this repo stays the source |
| Security batch §7e–§7h: ten review rounds, one reverted | **avoid repeating** | No deeper parsing. New checks are text-level, named by class, with their limit written once |

## 7. Build or reuse
| Candidate | Gives | Licence · upkeep | Fit | Effort | Verdict |
|---|---|---|---|---|---|
| **A. Claude Code's own features**: `async` hooks, `userConfig` with `/plugin configure`, `PostToolUseFailure`, exit code 2, the debug log's hook timings | The speed fix, the switch and its screen, the honest status line, the measuring method | built in · Anthropic | high: no file to edit, no new state | hours each | **reuse** |
| **B. A typed word that writes a mode file** (the owner's private setup plugin) | A switch from the phone | own · ours | the file can be written by the model; needs a prompt hook | 1 day | **avoid** for this release |
| **C. cc-safety-net** (outside guard plugin; has `doctor` and `explain` commands and a rules folder in the project) | A second guard with its own switchable rules | MIT as listed on package mirrors, not yet read on its official page · active | needs Node at every event; its rules live in a project file | none to install | **avoid** as a dependency; **adapt** the ideas of a self-test and rule names in messages. The README may say the two can sit side by side |
| **D. Native deny rules instead of the regex floor** (`permissions.deny`) | Per-rule, edited by the user, no process start | built in | a plugin cannot ship permission rules; the fresh-source gate still needs its hook | a redesign | **later**: a 1.0 question (plan §10) |
| **E. Small changes inside the existing hooks** | The two false denies, the level, the protection of the switch, doctor | MIT (this repo) · ours | exact | about 5 builder-days | **build**, on top of A |

Pick: **A + E.** Reason: A removes the need for any new file or state, and E is small edits in files that already have suites.

## 8. Risks
- **A new guard surface.** Protecting the switch means reading edits to a settings file. This must not start another hardening spiral: three keys, text-level, one review round, the limit written once.
- **A changed default.** After the update two deny classes and the wait gate are off unless Strict is on. The CHANGELOG says so first.
- **Background writes can land out of order.** The heartbeat gets a real lock on Windows and remembers finished call ids.
- **The auto-mode safety check refused a rule edit once.** Rule edits need the owner at the prompt; the plan groups them.
- **Two facts are not in the docs** (the text of a boolean option, live or restart). Both have a fallback.
- **Time.** About 5.5 builder-days before the reach check on Thu 26 Nov. The plan names a cut line after about 3 days and a drop order.
