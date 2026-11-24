# smartuse 0.7.1 — the hardening release (plan, 2026-11-23)

Base: public main = dev branch `paid-0.7.0` = `8a38454` (0.7.0, released 2026-11-23 at `3c7c92d`; `8a38454` fixed three release lines that still said not released). Line numbers below are of `3c7c92d`; five were spot-checked on `8a38454` and hold.
Work branch (proposed): `fix-0.7.1` from it; every feature merged `--no-ff`. Five features, three lanes, each feature one day or less.

## 1. Brief
- **What the owner gets.** A long Windows path no longer drops state. The paid refusals say what to do. The term scan runs on Windows as `CLAUDE.md` types it. The two-Stop ledger race is traced. The README tells a stranger how to remove smartuse and what it touches.
- **Why this scope.** Each item is a finding somebody already hit (`docs/STATUS.md`, Unknowns). None changes how a command is parsed, so the 0.6.2 rule holds and no merge reopens the guard's review rounds (`docs/notes/paid-guard-next-brief.md`, Lessons).
- **Maintainer clicks: two.** The yes on this plan and the release word. Two optional checks, 3 minutes together (§8).
- **Version.** 0.7.1: fixes and docs; no new rule, gate, adapter key or option.

## 2. Not in this (said once)
- 0.6.2 "On a report" items (other-shell hand-offs, PowerShell tokenisation, runner unwrapping): no report yet.
- Every rule linear · removing the round C–F parsing paths · the `command_segments` line-join: each re-reads shell text in `bash-guard.py`, each is more than a day, and a slip is a wrong deny for every user. Own plan, on a report or the maintainer's word.
- The staged settings copy (`SECURITY.md:50`): a new pattern in an always-on rule, see D-YK17.
- The 1.0 items that are not docs-only: README rewrite and lead line, make-prompt template, `Bash(bash *)` grants, evals CI, one ledger and receipts view; the listing form, the demo gif and the 30-days post (the maintainer's).
- `docs/STATUS.md` lows not taken: the two-valued Stop wait (method M); recall-test 210 against 203 (F5 quotes only numbers this release's T2 prints).

## 3. Rules for every feature
- Frozen: `RULE_NAMES` (`bash-guard.py:162`), `GATE_NAMES` (`:167`), `FLOOR` (`:171`), `KNOWN_RULES` (`heartbeat.py:79`), `hooks/hooks.json`, `all.sh` NAMES, `ci.yml` steps. No feature needs them changed.
- Never touched: `.claude/*.local.md`, the private terms file, `.agents/`, `.codex/`. Stage by file name.
- A bug gets its failing case first, shown red on `3c7c92d`, then the fix. Every "as today" claim in a builder brief carries a file:line.
- Fixtures with Windows paths, a paid host or a settings path go in a file, written with forward slashes. Tests set `HOME` to a temp folder and assert the real state folder is untouched.
- After a merge's automated security review: classify each finding against the next-brief's class list first. Build only a finding in new code that moves a run toward paid. One fix round, then stop and report.

## 4. Features

### F1 · a long Windows path keeps its state (lane A · 1 day)
- **Evidence.** The key is the whole project path: `heartbeat.py:164–168`, copied in `ledger.py:214`, `recall.py:81`, `until-done.py:73`, `wait-gate.py:130`, `bash-guard.py:2021`. `heartbeat.py:177` makes the folder; `:439` swallows the error. Past the Windows limit nothing is written and nothing says so.
- **E1 first (unknown → experiment).** A project folder whose state path passes 230 characters, in the session scratchpad; one `SessionStart` event into `heartbeat.py`. Record the length that fails and the error in §10. No code before that.
- **Rule (D2).** The key stays as today while the state folder plus its longest file name fits (the limit E1 measures on Windows; 255 bytes for the key elsewhere). Past it: the last 40 characters of the key, `-`, 12 hex of the sha1 of the whole key. A project whose full-key folder already exists keeps it. One helper, copied into the six files and tested equal, as today (`wait-gate-test.sh:1241`).
- **Acceptance (the user does).** 1 Opens Claude Code on Windows in a repo with a 200+ character path, sends one prompt, runs `/smartuse:status`: a live line, not "no event". 2 Runs `/smartuse:doctor` there: `state folder: writable`. 3 In a repo used before the upgrade: `/smartuse:receipts` still lists the old runs and a paid go keeps its used count.
- **Unit (red first).** a `heartbeat-test.sh`: `SessionStart` in the long folder writes `status.json` (red on Windows today). b The six hooks name the same folder for a short, a long and a 300-character path (through `ledger.py --state-dir`, the `wait-gate-test.sh:1246` shape). c A short path gives the old key byte for byte (the suites' `key()` helper, `ledger-test.sh:10`, unchanged). d Two long paths that differ only in the middle get two folders. e An existing full-key folder is still used.
- **Integration.** `paid-guard-test.sh`: long folder plus an adapter go → run 1 allowed, the counter sits in the short-key folder, and `file-guard` (`file-guard.py:27`) and `owner-file` (`bash-guard.py:126`) still refuse a write to it.
- **Interactive.** Headless Claude Code with the worktree's plugin, as the 0.7.0 live pass ran (`paid-guard-plan.md` §8.10), in the E1 folder: one Bash call, then the status and doctor lines of acceptance 1 and 2.
- **Must not change.** The key of any path that works today. The printed shape of `ledger.py --state-dir` (the skills read it, `make-prompt/SKILL.md:41`). `legacy_dir` (`ledger.py:231`). No shared module; no new top-level import in `bash-guard.py` (`:2024`). One Python start per hook. The rule reads folder names only, never file content.

### F2 · paid refusals say what to do (lane A, after F1 · half a day)
- **Evidence.** a `bash-guard.py:3096`: run 2 of a typed go is told to "add `, test ok` to that paid: line", and a typed go has no such line. `go["go_from"]` already tells the two apart (`:2921` adapter, `:2812` session). b `:3058` `mkdir` raises outside the `try`; `:3226` turns it into "the check failed", and `:3228` adds "put it in .claude/smartuse.local.md", which is not the fix.
- **Fix.** a Typed go: the reason leads with `the owner types "test ok" in this session`. Adapter go and subagent calls: today's text. b A named cause, `the state folder cannot be written`, with `run /smartuse:doctor`; still a deny at both levels.
- **Acceptance.** 1 The owner types `paid go: render.py x 3`, lets run 1 finish and asks for run 2: the refusal's first instruction is to type `test ok`. 2 With the go in the adapter, the refusal reads as in 0.7.0. 3 With a state folder that cannot be written, a paid run is refused and the reason names the state folder and doctor.
- **Unit (red first).** `paid-guard-test.sh` §37a (`:1884`): typed go, the reason leads with the typed instruction and lacks "to that paid: line" (red today). `:587–588`: the adapter text pinned as it is. `:527` (a file sits where the folder goes): the reason holds "state folder" (red today).
- **Integration.** The existing typed flow, go → run 1 → `test ok` → run 2, green with the new text; the text-only paid cases of `run.sh` unchanged.
- **Interactive.** Headless, adapter go `render.py x 2` on a fixture script that names a host and calls nothing: run 1 passes, run 2 shows the adapter wording. The typed wording stays synthetic (a headless prompt is never a go); optional live check in §8.
- **Must not change.** Every other reason text (`paid-guard-test.sh:520–632` pins them). Allow and deny outcomes: only words move. The `[rule paid]` ending.

### F3 · the term scan runs on Windows as typed (lane B · 2 hours)
- **Evidence.** `scripts/term-scan.py:66` and `:91` read git with `text=True` (the ANSI code page on Windows; git writes UTF-8). `:104–113` print `·`, `…` and file text to that console. The suite stays green because it runs through `py.sh` (`term-scan-test.sh:6`), which exports `PYTHONUTF8=1` (`py.sh:22`); `CLAUDE.md`'s publish line and `.github/workflows/ci.yml:55` call the script directly.
- **Fix.** `encoding="utf-8", errors="replace"` on both `subprocess.run` calls; stdout set to UTF-8 with replace at the top of `main()` (`:70`).
- **Acceptance.** 1 On Windows, with no `PYTHONUTF8`, the maintainer types `python scripts/term-scan.py --history --max-hits 1000000`: the summary line prints, no traceback, exit code by the documented rule. 2 A private term is still never printed.
- **Unit (red first).** `term-scan-test.sh`: a tracked file and a commit that hold `中文 → Á`, the script run without the launcher's UTF-8 mode and with a cp1252 console: summary line, no traceback (red today on Windows; the print half red everywhere). The six existing cases unchanged.
- **Integration.** The script over this repo's whole history, plain `python`, no variables: the same hit counts as the `PYTHONUTF8=1` run.
- **Interactive.** The publish command of `CLAUDE.md`, typed as written, on the laptop.
- **Must not change.** Exit codes 0, 1, 2 (`:118`), `mask()` (`:48`), the patterns, the hit lines, `--no-private`.

### F4 · two Stop hooks at once: one ledger line, never none (lane B, after F1's merge · half a day)
- **Evidence.** `ledger.py:263–267` claims `pending.json` by rename and returns on any `OSError`. `ledger-test.sh:52` failed once and passed on a rerun. The cause is a guess.
- **E2 first (unknown → experiment).** Loop `ledger-test.sh:49–52` 200 times on the laptop with the error's number printed. Not reproduced in 200: close it in `docs/STATUS.md`, build nothing.
- **Fix, only if E2 shows it.** A sharing error while `pending.json` still exists: retry the rename 5 times, 20 ms apart (the `write_json` shape, `heartbeat.py:200`). File gone: the other hook won, return.
- **Acceptance.** With a user-level copy of the hook beside the plugin's, the user runs a skill that writes a receipt, then `/smartuse:ledger`: exactly one line for it.
- **Unit (red first).** The E2 loop as a 50-round case, under 60 s (red at E2's rate); a `pending.json` held open and then released → one line.
- **Integration.** `ledger-test.sh` whole, three runs in a row green on the laptop.
- **Interactive.** In a temp `HOME`: `ledger.py --put pending.json …` as the skill types it, two real `Stop` events at once, then the `/smartuse:ledger` table: one line.
- **Must not change.** One line per run; the claim file's name; the receipt fields; `--put`, `--unit`, `--run`, `--get`.

### F5 · README: uninstall, what it reads and writes, release lines made true (lane C, last · half a day)
- **Evidence.** No uninstall or privacy section (only `README.md:61`, `SECURITY.md:13`, `:32`); the state list is one paragraph, `README.md:163`. Stale since today's release: the three "not released" lines were fixed in `8a38454`; left: `README.md:7` badge 3632 against a release sum of 4,322 (`CHANGELOG.md:28`).
- **Build.** `## Uninstall`: the documented plugin commands, typed by the owner in their own terminal because `config-switch` refuses them to Claude (`bash-guard.py:99–104`); then what stays and how to remove it (the state folder, a copied output style and its `outputStyle` key, the `statusLine` entry, each repo's adapter, the Linux trust file). `## What it reads and writes`: reads (the event, the session transcript, the adapter, the first 256 KB of a script a command runs); writes (the `README.md:163` list as a table); network (the hooks: none; `watch.py` runs git against your remote when a session arms it; `until-done` runs your `check:`). Then the stale lines, CHANGELOG 0.7.1, one `SECURITY.md` line for F1, both manifests, ROADMAP boxes.
- **Acceptance.** 1 A stranger follows `## Uninstall`: the state folder is gone and a new session prints no smartuse line. 2 The same stranger can say, from the README alone, which files smartuse reads and whether it uses the network. 3 The README says 0.7.0 was released on 2026-11-23, and the badge equals this release's T2 sum.
- **Unit.** Greps, output pasted: the three stale strings gone; `0.7.1` in `plugins/smartuse/.claude-plugin/plugin.json:3`, `.claude-plugin/marketplace.json:14` and the CHANGELOG head; every state file name the six hooks write appears in the new table (the claim → file:line list goes in the commit message).
- **Integration.** A removal dry run in a temp `HOME` (a scratchpad script, not committed): one event through each hook; every file made lies under `.claude/smartuse/` and is in the table; delete that folder; nothing of smartuse is left.
- **Interactive.** A fresh agent that sees only the two sections answers "what do I type to remove everything, and what does it read?"; its answer matches the claim list.
- **Must not change.** Every other README section (the first-time-reader rewrite and the lead line are 1.0, in the maintainer's words). The `SECURITY.md` classes. Release text states only what was fixed and measured, and never an open gap's method. Counts come from this release's T2 output.

## 5. Lanes and order
- Lane A (state and paid): F1 → F2. Lane B (tools): F3 → F4, with F4 rebased on F1's merge (both edit `ledger.py`). Lane C (docs): F5, after A and B are merged.
- Lanes A and B may build side by side. Suites never do: one suite at a time on the laptop, across all lanes.

## 6. Test tiers
- **T1:** the suites the feature names, one at a time. F1: heartbeat, ledger, until-done, wait-gate, recall, paid-guard, file-guard. F2: paid-guard, run. F3: term-scan-test. F4: ledger.
- **T2 (after each merge), one at a time, in this order:** `file-guard-test.sh`, `ledger-test.sh`, `until-done-test.sh`, `watch-test.sh`, `heartbeat-test.sh`, `wait-gate-test.sh`, `recall-test.sh`, `run.sh`, `fresh-gate-test.sh`, `paid-guard-test.sh` (each `bash plugins/smartuse/hooks/tests/<name>`), then `bash bench/tests/ab-test.sh`, then `bash scripts/term-scan-test.sh`. Twelve suites, never two at once, never `all.sh` on the laptop. Counts only grow from the 0.7.0 floors (`CHANGELOG.md:28`).
- **T3 (before the push):** `claude plugin validate --strict plugins/smartuse` and `claude plugin validate --strict .`; the five interactive scenarios; a fresh review of the merged code and a security review of the release diff; then `PYTHONUTF8=1 python scripts/term-scan.py --repo <repo> --history --max-hits 1000000` with 0 private hits. The push waits for the maintainer's word.

## 7. Reuse before build
| Need | Candidates | Pick |
|---|---|---|
| Long path | 1 shorten the key past the limit (stdlib `hashlib`, about 10 lines, ours) · 2 the extended-length path prefix (stdlib, but `pathlib` does not add it, and Git Bash and the skills read the same folder) · 3 the OS long-path switch (needs admin; not ours to set) · 4 hash every key (orphans every user's receipts and restarts every paid count) | 1 |
| Saying a write failed | `can_write()` (`heartbeat.py:553`) and doctor's `state folder:` line (`:603`): own code, tested (`heartbeat-test.sh:627`) | reuse as-is |
| Term scan encoding | stdlib `encoding=` and `reconfigure` · "always run through `py.sh`" (changes the documented command and CI) | stdlib |
| Rename race | the `write_json` retry (`heartbeat.py:200`), own code | adapt |
| Uninstall steps | Claude Code's official plugin commands reference (`claude plugin uninstall`, `claude plugin marketplace remove`) | reuse the documented commands |

All stdlib or the repo's own MIT code: no new dependency, nothing downloaded.
Own lessons applied: a path guard matches every reading (F1 integration) · release text claims only what was measured (F5) · review before the push and a security review before main (T3) · one heavy job at a time (§5) · a from-zero reader tests a guide (F5 interactive) · writable state never supplies a command (F1 rule).

## 8. Decisions
Made here: D1 this scope, 0.7.1. D2 the key rule of F1. D3 the helper stays copied in six files (`bash-guard.py` imports no other hook, `:2022–2023`). D4 the term scan is fixed in the script, not by changing the documented command. D5 F4 builds only what E2 reproduces. D6 no new suite; F5's checks are greps and a scratch dry run.
For the maintainer (recommendation first):
- **D-YK16 · scope.** Yes to this plan. The other scope is Card A's `Alt:` line. **Decided 2026-11-23: yes (the maintainer's tap 1).**
- **D-YK17 · the staged settings copy (`SECURITY.md:50`).** Keep it out; it leads the next guard batch. It is a new pattern in an always-on rule, and each guard merge has drawn a review round. Silence means agreed. **Taken as agreed 2026-11-23 (the tap on Card A, no objection).**

Steps that need the maintainer: 1 the tap on Card A, once. 2 the release word after T3, once. 3 optional, once, 2 minutes: type the uninstall commands in a throwaway config folder (the guard refuses them to Claude). 4 optional, once, 1 minute: type a `paid go:` and read the run-2 wording live.

## 9. Risks
- F1 edits six hooks. A wrong key orphans receipts or restarts a paid count: cases c and e are the gate, and the review reads the rule against the published limit "a delete of the state folder resets the count".
- Interactive runs set `HOME` to a scratch folder so no state lands in the real one (assumed: the variable reaches the hooks on Windows; if not, one leftover state folder is listed for the maintainer).
- F3's red case needs an interpreter without the launcher's UTF-8 mode on every CI system; if that cannot be had portably, the case runs on Windows only and says so.
- A full T2 is about an hour on the laptop, so five merges are five hours of suites. F2 and F3 are small enough to share one T2 if time is short.

## 10. Results (filled during the build)
E1 (2026-11-23, Windows 11 laptop, `LongPathsEnabled` = 0, temp `HOME` of 110 characters, one `SessionStart` into `heartbeat.py` through `py.sh`, project paths keyed but never made): state folder of 238 characters → `status.json` written; 240 → missing, nothing printed. `mkdir` still made folders of 242 and 246 characters (empty): the folder is made, then every file write fails. The failing call is the temp file `status.json.<pid>.tmp` (21 characters with a 5-digit pid): the whole file path may hold at most 259 characters (MAX_PATH 260 with its NUL). The raw error, `mkdir` of a 373-character folder: `FileNotFoundError` errno 2, winerror 3. Longest names the hooks write in the folder: `paid.<tool_use_id>.<8>.done` 49 (a real `tool_use_id` is 30, measured), `paid-runs.json.<pid>.tmp` up to 29, `status.json.<pid>.tmp` up to 26; `runs/<started_at>_<task>.json` up to 186 (two `safe_name` parts of 80, `ledger.py:192`, `:206`) is not covered, see §12 F1 limits.
E2 (2026-11-24, the laptop, temp `HOME`, `ledger.py` unchanged and run through a wrapper that logs each failed `os.rename` and each failed read of the claimed file; two `Stop` events at once on one `pending.json` per round): run 1, 200 rounds, rename only logged: 196 one line, **4 no line**, 0 two lines; 3 failed renames, all `errno 13 / winerror 5` with the source already gone. Run 2, 200 rounds, rename and read logged: 200 one line; 1 read of a claimed file failed `FileNotFoundError` (the other hook's rename moved the same file a second time; that hook wrote the line). Run 3, 600 rounds: 600 one line; 11 such reads, 3 renames `winerror 2` with the source gone. Result: the drop is real (4 in 1000, about 0.4%) but its cause is not traced: no failed rename ever saw the source still there, so §4 F4's fix (retry while `pending.json` exists) would not have fired. D5 applied: **F4 not built in 0.7.1**; recorded in `docs/STATUS.md` (Unknowns) and ROADMAP for a release with a file-handle trace.
T2 counts: after F1 (`433f026`), 12 of 12 ALL PASS: file-guard 107 · ledger 46 · until-done 50 · watch 63 · heartbeat 206 · wait-gate 209 · recall 203 · run 1340 · fresh-gate 758 · paid 1365 · ab 36 · term-scan 6 (one run stopped by Claude Code on low memory after the first 8, the last 4 run again on the maintainer's word); after F2 and F3 (`445314e`, one shared T2, §9), 12 of 12 ALL PASS: the same counts except paid 1369 and term-scan 7 (stopped on low memory twice, after 8 and after 7 suites; the rest run again on the maintainer's word) · T3:

## 11. Card A
FINISH LINE: smartuse 0.7.1, the hardening release
So you want: the bugs already hit fixed, with two taps from you and no new guard parsing
Sample: before `could not verify the go (the check failed)` and no status in a long folder | after: state written, the reason names the fix, `python scripts/term-scan.py --history` runs bare
Done when: 1 in a 200+ character Windows folder `/smartuse:status` shows a live line and doctor says `state folder: writable` 2 the publish scan typed as in `CLAUDE.md`, no `PYTHONUTF8`, ends with its summary line and 0 private hits 3 the README has `## Uninstall` and `## What it reads and writes` and says 0.7.0 was released
Proven on: this repo's own git history (the scan) and a 230-character project folder on the maintainer's Windows laptop through real Claude Code | synthetic: the typed-go wording (only the owner's typing is a go)
Unknown: the failing length and error → experiment E1 · the ledger race's cause → experiment E2 · the uninstall commands end to end → assumed: the official commands reference
Not in this: any change to how a command is parsed · the README rewrite, template, grants, evals CI · the listing, gif and post
Alt: 0.8.0 "first 1.0 items" (README rewrite, make-prompt template, narrowed grants, evals CI): closer to 1.0, but needs your lead line, a README read and CI runs on your token
Tap: 1 yes · 2 send a reference · 3 no

## 12. Contract (phase 3, 2026-11-23)
Line numbers are of `f882756` (the plan commit on `fix-0.7.1`; the hooks are as at `8a38454`). New names are marked *new*. A name the builder cannot find → stop and ask.

### F1 · the key rule (D2 made exact by E1; D7)
- **One helper, *new* `fit_key(full, base, nt)`**, copied byte for byte into `heartbeat.py`, `ledger.py`, `recall.py`, `until-done.py`, `wait-gate.py` and `bash-guard.py`. `import hashlib` sits inside `fit_key` in all six (as `until-done.py:121` and `bash-guard.py:2801` do): no new top-level import anywhere. `wait-gate-test.sh`'s import check (§9, "stdlib only (json os re sys time pathlib datetime)") may need `hashlib` added to its list: the builder shows that diff and says why. `full` is today's key; `base` is `str(<HOME>/.claude/smartuse/projects)`; `nt` is `os.name == "nt"`. Returns the key to use. Never raises (any error → `full`).
- **Today's `project_key()` / `paid_project_key()` keep their names and callers**; each computes `full` exactly as today (`heartbeat.py:168`) and returns `fit_key(full, base, os.name == "nt")`. `state_dir()`, `paid_state_dir()`, `ledger.py --state-dir` and `legacy_dir()` change no line.
- **Constants (*new*, same in all six):** `WIN_PATH_MAX = 259` (E1) · `NAME_ROOM = 64` (the longest fixed name, 49, plus room) · `KEPT_ROOM = 26` (`status.json.<pid>.tmp` with a 10-digit pid) · `KEY_MAX = 255` (one name on Linux and macOS) · `TAIL = 40` · `HASH = 12`.
- **Rule, in this order:**
  1 `short = full[-TAIL:].lstrip("-") + "-" + sha1(full.encode()).hexdigest()[:HASH]`; `dirlen = len(base) + 1 + len(full)`.
  2 `nt` and `os.path.isdir(base + os.sep + full)` and `dirlen + 1 + KEPT_ROOM <= WIN_PATH_MAX` → `full` (a folder that works today keeps working: D7a).
  3 not `nt` and `os.path.isdir(…)` → `full`.
  4 `len(full) > KEY_MAX` → `short`.
  5 `nt` and `dirlen + 1 + NAME_ROOM > WIN_PATH_MAX` → `short`.
  6 else `full`.
- **D7 (made here, inside D2).** a An existing full-key folder is kept only where `status.json` could be written in it (≤ 232 characters on Windows); a longer one, which `mkdir` made but no file reached (E1: 242, 246), is left behind empty and the short key is used. b "Longest file name" means the fixed names (≤ 49), not `runs/` archives: counting those (186) would move the limit to about 72 characters and give new short keys to ordinary repos. c On Linux and macOS only the 255-byte name limit applies (the key is ASCII, so characters = bytes).
- **Limits written into `SECURITY.md` / ROADMAP (F5), not fixed:** a `runs/` archive with a long task name can still fail in a folder near the limit (`ledger.py:206`, as today); a `HOME` so long that even the short key leaves no room (base over 140 characters on Windows) still fails, and doctor's `state folder:` line is the only sign; on Windows the rule is `os.name`, so WSL keys as Linux (its own HOME, as today).
- **Tests the builder adds (red first, on `f882756`):** the plan's a–e in §4 F1, plus f: a Python check that pulls `fit_key` out of all six files with `ast` (no import of the hooks) and asserts the six sources are identical and agree on a table of inputs, both `nt` values: a 20-character key, a key making `dirlen` 194 and 195 on Windows (the edge of rule 5), 256 and 255 characters (rule 4), an existing folder at 232 and at 233 (rule 2). Fixtures in files with forward slashes; `HOME` a temp folder; assert the real `~/.claude/smartuse` gains nothing.
- **Watch:** every suite's own `key()` helper (`ledger-test.sh:10` and its copies) still names the folder, because test paths are short; a suite that builds a path past 194 characters on Windows must say so and use `ledger.py --state-dir`.

### F2 · the reason texts
- **a Typed go.** At `bash-guard.py:3096`, when `go["go_from"]` starts with `session:` (`:2811`): `run {used} of {runs} is done; the batch waits for the owner's "test ok": the owner types "test ok" in this session. Show the owner the one output first.` Any other `go_from` (`adapter`, `:2921`): today's text, byte for byte.
- **b State folder.** `:3058` `sdir.mkdir(…)` moves inside `try … except OSError: return True, PAID_SDIR, 0` with *new* `PAID_SDIR = "the state folder cannot be written"`. At `:3227`: `why == PAID_SDIR` → `head(first) + "could not verify the go (the state folder cannot be written); run /smartuse:doctor. Nothing was spent."`; every other `why` keeps today's tail. Outcome unchanged: a deny at both levels.
- **Not changed (minor, noted):** `"the counter is not writable"` (`:3061`, `:3091`) keeps its `.claude/smartuse.local.md` tail, though a long path can cause it too; after F1 it should not happen. Change it only on the maintainer's word.

### F3 · the scan
- `:66` and `:91`: `encoding="utf-8", errors="replace"` added to both `subprocess.run` calls (`text=True` stays). First line of `main()` (`:70`): `sys.stdout.reconfigure(encoding="utf-8", errors="replace")` inside `try/except (AttributeError, ValueError)`. Nothing else moves.

### F4 · only after E2
- E2's loop script lives in the session scratchpad, prints the `OSError` errno and winerror of each failed claim, and runs only when no other suite runs. No contract until E2 shows a cause.

### F5 · the claim list
- The builder writes, before any README text, a list `claim → file:line` for every file the six hooks read or write (grep `write_json\|os.open\|open(\|read_text\|\.mkdir` in the hooks) and every network call (`subprocess` in `watch.py`, `until-done.py`); the README tables are built from that list, and it goes in the commit message.

### Order (changed from §5, one line)
- Builders run one at a time, not lanes side by side: §5's "one suite at a time on the laptop" holds across builders, and each builder runs its own T1. Order: F1 → F2 → F3 → E2 (→ F4) → F5, T2 after each merge (F2 and F3 may share one T2, §9).

### Review fix round (phase 7, 2026-11-24; one round, then report)
Fresh review (Opus xhigh) of `8a38454..25fbfe9`: judge 1, 3, 4 PASS; 5 PASS (exit code with real hits not checked); 2 FAIL (narrow) → M1.
- **M1 → D8.** E1 ran with `LongPathsEnabled` = 0. With it on, a full-key folder of 233–293 characters works today and D7a would move it, restarting its paid count. New rule 2: `nt` and the full-key folder exists and (`dirlen + 1 + KEPT_ROOM <= WIN_PATH_MAX` or *new* `win_long_paths()`) → `full`. `win_long_paths()` (inside `fit_key`, called only when the first test fails): `import winreg`, read `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem` value `LongPathsEnabled`, true when it is 1; any error → false. Safe with the switch off: a folder over 232 characters never held a paid count (`paid-runs.json.<pid>.tmp` needs ≤ 229, the claim marker ≤ 218), so moving it cannot reset one. Reads a registry value and folder names only.
- **Nits taken:** `short` built only when returned (no `hashlib` import or sha1 on the common path; the review measured ~6.6 ms per hook start); `short` never starts with `-` (`(tail + "-" + hex).lstrip("-")`); the `KEPT_ROOM` comment names the real sizes (temp names up to 29, claim markers 40/49); the module headers `heartbeat.py:9`, `ledger.py:13`, `wait-gate.py:38` describe the key rule in one clause; `paid-guard-test.sh` §39's file-guard check asserts the deny, not any output.
- **m1 → docs (F5's SECURITY line):** "making or deleting a state folder resets the count" (a project on the short key moves to a full-key folder once one of ≤ 232 characters exists; the shell may `mkdir` it). Same class as `SECURITY.md`'s delete line.
- **Recorded, not fixed (pre-existing, kept by D7a):** a kept folder of 219–232 characters denies every paid run (the claim marker passes 259) with the adapter tail, and doctor still says writable (its probe name is ~17 characters) → ROADMAP next-release item. Skipped cases print as PASS and count toward floors → ROADMAP.
