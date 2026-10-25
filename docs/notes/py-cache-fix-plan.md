# 0.5.1 — the launcher's remembered interpreter: lock + check (plan, 2026-10-25)

Status: **approved by YK 2026-10-25, both defaults in §8 accepted.** Nothing built yet. Planner: flow-planner on claude-fable-5-1. Every name below was grepped before it was written.

## 0. The problem (class, not recipe)
0.5.0's launcher (`hooks/py.sh`) ran an interpreter path read from a user-state file (`~/.claude/smartuse/interpreter`) that neither guard protected: a writable state file chose what every hook ran, in every repo. YK's pick (STATUS 3a): make the file human-only in both guards, and make py.sh refuse anything that is not the machine's real Python. yk-brain decision 2026-10-15 already says why: a hook that executes a string from writable state is an execution path outside the guard. 0.5.0 broke that decision; 0.5.1 restores it.

## 1. Own work first
| Source | Verdict |
|---|---|
| yk-brain decisions 2026-10-15 (a gate may only run what a human wrote; writable state must not supply a command) | **reuse as-is** — the design rule below follows from it |
| yk-brain lessons 2026-10-15 (anchor guard patterns to the segment that writes; a heredoc body is data, test both shapes) | **reuse as-is** — the new file name goes inside the existing verb-anchored rule; one heredoc allow case |
| until-done.py `TRUSTED` + `pins_are_trustworthy()` (lines 51, 127–134): root-owned pin, never trusted on Windows (st_uid 0) | **avoid** for this file — the cache must work on Windows, where ownership proves nothing; a pin in a user-writable file proves nothing anywhere |
| reuse-map row "Claude Code hooks, guards" (smartuse hooks with tests) and "one-command test gate" (`all.sh`) | **reuse as-is** — new cases go into the three suites that already hold launcher and guard cases |
| yk-brain `.claude/hooks/py.sh` (a pre-0.5.0 copy, no cache: grep `interpreter` finds comments only) | **leave** — not affected; if it is ever refreshed, copy 0.5.1, never 0.5.0 (outside this repo, not one of the ten files) |

## 2. Build-vs-reuse: four ways to check the cache
| Design | Stops | Misses | Cost per event | Windows |
|---|---|---|---|---|
| A. keep the path; accept it only if `[ "$P" -ef "$(command -v python3\|python\|py)" ]` | any path not on PATH | a `py -3` winner (its `sys.executable` is not `py`) can never be cached → those users fall back to 0.4.0 speed | up to 3 `$(…)` forks: ~1 ms Linux, 30–90 ms Git Bash (MSYS fork) | `/c/…/python` vs `C:/…/python.exe`: needs `-ef` through MSYS's `.exe` magic (unverified) or string normalising |
| B. keep the path; allow only a real install layout (`python3*.dll` + `Lib/` beside `python.exe`; `../lib/python3.X/os.py` on POSIX) plus a deny list (temp, repo, `~/.claude`) | a copy in a temp folder or the repo | a faked layout (three commands); macOS CLT Python, Nix, Scoop, venv launchers → silently slow | ~0 (`[ -e ]` builtins) | works for python.org, hostedtoolcache and Store Python; not for venvs |
| C. path + fingerprint (size+mtime or sha256) in the same file | nothing: the writer writes a matching fingerprint | everything | `stat`/`sha256sum` fork+exec: 5–20 ms Linux, 50–150 ms Windows | pins are not trusted on Windows (CHANGELOG 0.4.0) |
| **D. remember the NAME that won, not a path** — the file may hold only `python3`, `python` or `py -3`; py.sh runs that word through PATH, exactly as the probe loop would | every path, of any name, anywhere: nothing in the file is ever a command path; any other word; a Store alias (`WindowsApps`) resolution | a bad write that picks a word whose PATH target is broken → hooks silently off until the file is deleted (needs a guard bypass AND a broken interpreter on PATH; the Store alias case is caught) | builtins only (`read`, `case`, `command -v`, `hash`); +1 fork (~2 ms) only on bash 3.2 (macOS `/bin/bash`, no `BASH_CMDS`) | `python` and `py -3` work by name; `py -3` costs one extra `py.exe` start (~50 ms, not a Python start) where only `py` is on PATH; Store Python users (aliases under `WindowsApps`) are never trusted → 2 starts, as in 0.4.0 |

**Pick: D.** It is the only design where the file cannot change *what* runs, only *which probe step* is skipped — the strongest reading of YK's "nothing outside a real Python install", with no cross-platform layout list to maintain. The 0.5.0 cache on every machine holds a path, so it fails the new check once, is probed and rewritten: no migration. The lock (both guards) is still built: it stops the honest mistake; D makes the dishonest one harmless.

## 3. Exact rules
**py.sh** (replaces lines 16–20 and 26; comment block rewritten in the same voice):
```bash
C="${HOME:+$HOME/.claude/smartuse/interpreter}"; P=""
if [ -n "$C" ] && [ -f "$C" ] && { read -r P || [ -n "$P" ]; } < "$C"; then
  P=${P%$'\r'}
  case "$P" in python3|python|"py -3") W=${P%% *}                 # the word to look up: py for "py -3"
    if command -v "$W" >/dev/null 2>&1; then                        # builtin: PATH scan, no process
      hash "$W" 2>/dev/null; R=${BASH_CMDS[$W]}; [ -n "$R" ] || R=$(command -v "$W")   # resolved path; the fork only on bash 3.2
      case "$R" in *[Ww]indows[Aa]pps*) ;; *) exec $P "$@";; esac   # a Store alias (stub or real) is never trusted; $P unquoted: "py -3" is two words
    fi;;
  esac
fi
# probe loop unchanged except the write: remember the NAME, never through a symlink
[ -n "$C" ] && [ -d "${C%/*}" ] && [ ! -L "$C" ] && printf '%s\n' "$cand" > "$C" 2>/dev/null
```
Step costs: `[ -f ]`, `read`, `case`: 0. `command -v` builtin: <0.1 ms Linux, ≤5 ms Git Bash (one stat per PATH entry). `hash` + `BASH_CMDS`: 0 on bash ≥ 4 (Git Bash 5.2, Linux); macOS `/bin/bash` 3.2 → one `$(command -v)` fork, ~2 ms. Then one Python start — the 0.5.0 claim holds. No new process on the cached path, ever. Anything not accepted falls into the existing probe loop (line 21): correct, slower, never a failure (`exit 0` at line 31 stays).

**file-guard.py line 10:** `HUMAN_ONLY = re.compile(r"(smartuse\.local\.md|smartuse/trusted-checks\.json|/etc/smartuse(/|$)|\.claude/smartuse/interpreter$)", re.I)` — anchored to `.claude/smartuse/` and to the end, so `docs/smartuse/interpreter.md` stays writable. Reason text (line 24): "… (it decides what the until-done gate may execute, or which Python runs the hooks). Ask the user to edit it." Docstring line 2: "three files are human-only", one clause for the launcher file.

**bash-guard.py line 37:** the file group becomes `(smartuse\.local\.md|trusted-checks\.json|\.claude[/\\]smartuse[/\\]interpreter(?![\w.-]))`; verbs unchanged (`>`, `tee`, `sed -i`, `cp`, `mv`, `python3?`, `py.sh`). `rm` stays allowed: deleting the file only costs one probe. Reason text (line 38): "human-only file (it decides what the until-done gate may run, or which Python runs the hooks) — ask the user to edit it".

**What the lock stops / does not.** Stops Write/Edit/MultiEdit/NotebookEdit of the file, and bash writes by the seven verbs in the same segment. Does not stop (known, STATUS step 4 D, ROADMAP line 32): a write after `;`, `ln`/`dd`/`perl`/`node`/`ruby`/`awk`/`install`, a path held in a variable. With D those leaks can only slow hooks down or (broken interpreter on PATH) switch them off; they can no longer run a file the model made.

## 4. Acceptance criteria (what a person does and sees)
1. A fresh install on Windows (python.org Python on PATH) runs hooks with one Python start per event; `~/.claude/smartuse/interpreter` reads `python`.
2. A machine upgrading from 0.5.0 keeps working: the first event replaces the stored path with a name; nothing to delete by hand.
3. A cache that names an executable in a temp folder, the repo, or anywhere else is ignored; the probe runs; the stand-in never runs.
4. Claude asked to edit or redirect into `~/.claude/smartuse/interpreter` is denied by file-guard (Write/Edit) and bash-guard (`>`, `tee`, `cp`, `mv`, `sed -i`, `python -c`), with the human-only reason.
5. A user whose `python3` is the Store alias never has the alias run as a hook; a user without any Python still gets silent hooks (exit 0), never a block.
6. `bash plugins/smartuse/hooks/tests/all.sh | tail -1` prints `run 134 · ledger 46 · until-done 40 · file-guard 14 · heartbeat 110 · ab 36 · watch 63 · wait 187` — after the review fixes (§8) `run 138 · ledger 46 · until-done 40 · file-guard 23 · heartbeat 114 · ab 36 · watch 63 · wait 187`.

## 5. Tests (17 new, 4 rewritten; each suite already holds the matching cases)
**heartbeat-test.sh, launcher block (lines 298–313), fixtures `$D/stub` (prints the Store hint, exit 9009), `$D/real/python` (wrapper), `$CF`:**
| # | Input | Expected |
|---|---|---|
| R1 (line 304) | probe with `PATH=$D/stub:$D/real:$PATH` | `ran`; `$CF` holds exactly `python3`, `python` or `py -3` (a word, never a path) |
| R2 (307) | `$CF`=`python`, `PATH=$D/stub2:$D/real` (stub2 records a call) | `ran`; `stub2/called` absent — the remembered name runs straight away, the stub ahead of it on PATH is never started |
| R3 (310) | `$CF`=`python3`, `PATH=$D/real` (no python3 there) | `ran`; `$CF` now `python` — a name no longer on PATH is probed again and replaced |
| R4 (313) | `$CF`=`$D/tmp/python3` (a stand-in script that prints EVIL, executable), `PATH=$D/stub:$D/real` | output is the hook's normal output, no `EVIL`, rc 0 — a path is never run, whatever its name |
| N1 | `$CF`=`$REAL` (the real interpreter's absolute path, i.e. a 0.5.0 cache) | `ran`; `$CF` rewritten to a word |
| N2 | `$CF`=`python3; echo pwned` | `ran`, no `pwned` — the list is three exact words, not a pattern |
| N3 | `$CF` empty (`: > "$CF"`) | `ran` via the probe, rc 0 |
| N4 | `$D/WindowsApps/python3` = a copy of the stub, `PATH=$D/WindowsApps:$D/real`, `$CF`=`python3` | `ran` (the hint text is absent, so the alias was not exec'd); `$CF` now `python` |
| N5 | `$CF` is a symlink to `$D/target` holding `junk` (POSIX; on `$OSTYPE` msys print `PASS (skipped on Windows: no symlinks)`) | `ran`; `$D/target` still reads `junk` — the launcher never writes through a symlink |
**file-guard-test.sh (+4):** deny Write `/home/u/.claude/smartuse/interpreter` · deny Edit `C:\Users\u\.claude\smartuse\Interpreter` (backslashes, case) · deny Edit `/home/u/.claude/smartuse/x/../interpreter` · allow Write `/repo/docs/smartuse/interpreter.md`.
**run.sh (+8):** deny `echo python3 > ~/.claude/smartuse/interpreter` · deny `printf '%s\n' /tmp/t/python3 | tee "$HOME/.claude/smartuse/interpreter"` · deny `cp /tmp/t/cache ~/.claude/smartuse/interpreter` · deny `sed -i 's/.*/python/' ~/.claude/smartuse/interpreter` · deny `python3 -c "open('/home/u/.claude/smartuse/interpreter','w').write('python')"` · allow `cat ~/.claude/smartuse/interpreter` · allow `echo python3 > notes/interpreter` (same last segment, other folder) · allow `cat > notes.md <<'EOF'` whose body contains the deny line (heredoc body is data).
**Integration test:** `ci.yml` as it is — the eight suites on ubuntu 3.9 and 3.12, macOS 3.12, Windows 3.12; done when all four jobs are green and `all.sh` prints the line in criterion 6 on Linux.
**Interactive scenario, Linux (CI shell or any box):** a fresh `HOME` whose cache file holds a path (0.5.1 must never run one); `printf '{}' | bash plugins/smartuse/hooks/py.sh plugins/smartuse/hooks/heartbeat.py --line` prints the status line, not the stand-in's text; `cat` the cache → `python3`.
**Interactive scenario, Windows laptop (Git Bash, dev checkout):** (1) `cat ~/.claude/smartuse/interpreter` shows the 0.5.0 path. (2) run the same `printf '{}' | bash … heartbeat.py --line`; the status line prints. (3) `cat` again → `python` (if it says `py -3`, note the extra `py.exe` start). (4) `time` five runs of (2): 0.5–1.8 s each, as in 0.5.0. (5) In a Claude Code session with the plugin at 0.5.1 ask Claude to run `echo python3 > ~/.claude/smartuse/interpreter`, then to Write that file: both denied with the human-only reason. (6) `bash plugins/smartuse/hooks/tests/heartbeat-test.sh` alone (10+ min there) → ALL PASS.

## 6. Must not change
One Python start per hook event (hooks.json: 2–3 py.sh calls per tool call; no new process on the cached path). A hook never blocks: no interpreter → print nothing, `exit 0`. Test counts only grow (R1–R4 keep their slots). bash 3.2 syntax in py.sh (macOS `/bin/bash`): no `${x,,}`, no `declare -A`. Python 3.9 stdlib only in the guards. Nothing in the paid branches is touched by 0.5.1.

## 7. Release bits (two commits, each under ten files)
Commit 1, the fix: `py.sh`, `file-guard.py`, `bash-guard.py`, `heartbeat-test.sh`, `file-guard-test.sh`, `run.sh`. Commit 2, the release: `plugins/smartuse/.claude-plugin/plugin.json:3` and `.claude-plugin/marketplace.json:14` → `0.5.1`; `docs/releases/0.5.1.md` (shape of 0.5.0.md: what's new, tests line, upgrade line); `CHANGELOG.md` entry "0.5.1 — <date>, the launcher remembers a name, not a path" describing the class (a writable state file chose the hooks' interpreter; now it can only pick one of three PATH names, and both guards keep it human-only) — no steps; `docs/STATUS.md` state line + 3a done; `README.md` lines 36 (file-guard sentence; "94 regression cases" is stale: use the new count), 63 and 76 (the launcher remembers a name); `docs/ROADMAP.md` one `[x]` line under 0.5.0. Then: dev branch `claude/inspiring-galileo-8icw6s` → CI green → ff `main`, tag `v0.5.1`, release page, `claude plugin update smartuse@smartuse` on the laptop.
**Paid branches (unpushed, so rebase, not merge):** `git -C ~/smartuse rebase claude/inspiring-galileo-8icw6s paid-guard`, then `git -C ~/smartuse/.claude/worktrees/f3 rebase paid-guard`. Hunks that will conflict: `file-guard.py` docstring (lines 2–6), `HUMAN_ONLY` (f3 line 12 adds `paid-runs.json` and `.jsonl`), the reason text (f3 line 26); `bash-guard.py` human-only rule (f3 lines 58–59: `\brm\b` added to the verbs, two files added); the appended blocks at the end of `file-guard-test.sh` and `run.sh`; `CHANGELOG.md` top; `STATUS.md`; `README.md`. Resolution rule: union of the file alternations, f3's verb list, f3's reason text plus "or which Python runs the hooks", keep both test blocks. Re-run `run.sh`, `file-guard-test.sh`, `paid-guard-test.sh` one at a time after each rebase.

## 8. Decisions made here · open for YK
Made: D over YK's literal wording (a name, not a validated path) — reason in §2; the `WindowsApps` rule runs on every OS (a path with that segment is never legitimate elsewhere, and the test then runs on all four CI jobs); `rm` of the cache stays allowed; the write skips a symlinked cache file; new cases live in the three existing suites.
Open 1 — Store Python users: with D they keep 0.4.0 speed (two starts), because a `WindowsApps` alias is never trusted. **Default: accept**; the alternative (trust it) lets a bad write point hooks at the stub and switch them off silently.
Open 2 — close the human-only rule's `;` gap now? **Default: no** — it is paid-guard item D's hunk and would conflict with both branches; 0.6.0.
After the fresh review and the security review (YK, 2026-10-25): **fix in 0.5.1** — a cached name PATH has as a non-executable file is probed (its exec exited 2, which blocks a PreToolUse hook); bash 3.2 never reads `BASH_CMDS`; WindowsApps in any case; the read capped at 16 characters and the write only into a regular or new file; both guards match the Windows spellings of the file (a trailing dot or space of any part, `::$DATA`), and file-guard also the resolved path (links, junctions, 8.3 names of what exists) and fails closed on dot-and-space parts; the SQL rule anchored (pre-existing: quadratic, so a long command outlasted the 10 s hook timeout). The suite counts grow past criterion 6. **Accept** — the Python install manager (3.14+, python.org's default) puts its aliases under WindowsApps, so those users keep 0.4.0 speed like Store users; trusting real aliases safely goes to 0.6.0. **0.6.0** — bash-guard's directory targets and other path spellings, 8.3 names included (with the `;` gap), a cached name whose PATH target broke (no proof, no fallback: by design), the other rules' per-verb rescans on very long commands. **Reworded** — this plan's §0 and the Linux scenario describe the class; no personal paths.
