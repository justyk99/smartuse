#!/usr/bin/env bash
# Self-contained test for hooks/watch.py — the background watcher a session arms after it hands work to another session, so a git
# push or a file wakes it (docs/notes/one-session-design.md, M1). Every scenario has a fixture of its own: a bare remote, a clone "a"
# where the watcher runs and a clone "b" the "builder" pushes from. The scenarios run side by side and print in a fixed order; the
# watcher polls every second here (SMARTUSE_WATCH_TEST=1 lowers the 5 s floor of --every, nothing else). The builder pushes only
# once the watcher's GIT_TRACE shows two ls-remote calls — the first took the baseline — so no case races a sleep.
# Covered: push + --path (and a push without the file: still waiting; a second push with it fires, naming that commit) · a push
# without --path · a branch that does not exist yet (its first push fires) and one that never does (the line says so) · a tag named
# like the branch is no push · no push → exit 3 · --file appears / is already there / never comes · a dead remote (from the start and
# mid-wait) → exit 4 · usage errors → exit 2 · the incident: the builder pushes and its "step done" chat message is lost, the watcher
# fires anyway · armed late (or re-armed after a restart): --since <the hand-off's commit> still catches a push made before the
# watcher started, and without it that push is the baseline · UTF-8 output under a cp1252 console · the pure functions and the poll loop (a fake remote: the failure counter, the
# baseline, the new-sha rule, the time limits). Each scenario prints its PASS / FAIL lines; a scenario that dies before printing
# them all is itself a FAIL (the expected count is part of the task call). Everything lives under one temp dir,
# ${TMPDIR:-/tmp}/smartuse-watch.XXXXXX, which is the only thing removed on exit; temp HOME, system git config off. Exit 1 on failure.
set -u
H="$(cd "$(dirname "$0")/.." && pwd)"; WATCH="$H/watch.py"
D=$(mktemp -d "${TMPDIR:-/tmp}/smartuse-watch.XXXXXX") && [ -d "$D" ] || { echo "FAIL could not create a temp dir under ${TMPDIR:-/tmp}"; exit 1; }   # a name of its own: nothing here is shared with another suite or another agent's /tmp/tmp.*
trap 'case "$D" in */smartuse-watch.*) rm -rf "$D" 2>/dev/null;; esac' EXIT   # removes this run's own dir and nothing else
export HOME="$D/home" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 SMARTUSE_WATCH_TEST=1
export GIT_AUTHOR_NAME=builder GIT_AUTHOR_EMAIL=builder@example.com GIT_COMMITTER_NAME=builder GIT_COMMITTER_EMAIL=builder@example.com
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CEILING_DIRECTORIES
mkdir -p "$HOME"
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, not inside other text (cygpath -m -> C:/Users/...); elsewhere unchanged
ok() { echo "PASS $1"; }
ko() { echo "FAIL $1"; }
command -v git >/dev/null 2>&1 || { echo "FAIL no git on PATH"; exit 1; }
[ "$(py -c 'print("ok")' </dev/null 2>/dev/null)" = ok ] || { echo "FAIL no python 3 (python3, python or py -3) through $H/py.sh"; exit 1; }

# --- fixtures and drivers (each scenario runs in its own subshell, so these globals are per scenario)
fixture() { # $1 = dir: $1/remote.git (bare, main has one commit) · $1/a = the watcher's clone · $1/b = the builder's clone
  mkdir -p "$1" && git init -q --bare "$1/remote.git" >/dev/null 2>&1 && git -C "$1/remote.git" symbolic-ref HEAD refs/heads/main \
  && git init -q "$1/seed" >/dev/null 2>&1 \
  && ( cd "$1/seed" && git symbolic-ref HEAD refs/heads/main && echo seed > README && git add README && git commit -q -m seed && git push -q "$1/remote.git" main ) >/dev/null 2>&1 \
  && git clone -q "$1/remote.git" "$1/a" >/dev/null 2>&1 && git clone -q "$1/remote.git" "$1/b" >/dev/null 2>&1
}
bpush() { # $1 = fixture dir, $2 = commit subject, rest = files to add (each gets the subject as its text; none -> an empty commit): the builder commits and pushes main
  local f=$1 msg=$2 p; shift 2
  ( cd "$f/b" || exit 1
    for p in "$@"; do mkdir -p "$(dirname "$p")"; printf '%s\n' "$msg" > "$p"; git add -- "$p"; done
    if [ $# -gt 0 ]; then git commit -q -m "$msg"; else git commit -q --allow-empty -m "$msg"; fi
    git push -q origin main ) >/dev/null 2>&1
}
sha7() { git -C "$1/b" rev-parse HEAD | cut -c1-7; }   # the builder's head, as the watcher prints it
startw() { # $1 = fixture dir, rest = watch.py arguments: the watcher runs in clone a, in the background; stdout -> $1/w.out, stderr -> $1/w.err, GIT_TRACE -> $1/trace; $XENV = one more NAME=value for it
  local f=$1; shift
  ( cd "$f/a" && env GIT_TRACE="$(wp "$f/trace")" ${XENV:+"$XENV"} bash "$H/py.sh" "$WATCH" "$@" > "$f/w.out" 2> "$f/w.err" ) &
  WPID=$!
}
armed() { # $1 = fixture dir: waits (40 s at most) until the watcher has made two ls-remote calls: the first took the baseline, the second shows the loop runs. 1 = it ended first or never got there
  local n=0 c
  while [ $n -lt 200 ]; do
    kill -0 "$WPID" 2>/dev/null || return 1
    c=$(grep -c 'ls-remote' "$1/trace" 2>/dev/null); [ "${c:-0}" -ge 2 ] && return 0   # one trace line per call (the sub-commands it starts are named upload-pack); old gits quote the words, hence no "git " in front
    sleep 0.2; n=$((n + 1))
  done
  return 1
}
polled_after() { # $1 = fixture dir, $2 = text: true once a trace line holding $2 is followed by another ls-remote (the watcher has been through its check and polled again)
  awk -v pat="$2" 'index($0, pat) { seen = NR } /ls-remote/ { if (seen && NR > seen) ok = 1 } END { exit ok ? 0 : 1 }' "$1/trace" 2>/dev/null
}
endw() { # $1 = fixture dir, $2 = most seconds to wait (default 60): sets RC OUT ERR (CRs dropped); a watcher still running by then gets RC=999
  local n=0 lim=$(( ${2:-60} * 5 ))
  while kill -0 "$WPID" 2>/dev/null && [ $n -lt $lim ]; do sleep 0.2; n=$((n + 1)); done
  if kill -0 "$WPID" 2>/dev/null; then kill "$WPID" 2>/dev/null; RC=999; else wait "$WPID"; RC=$?; fi
  OUT=$(tr -d '\r' < "$1/w.out" 2>/dev/null); ERR=$(tr -d '\r' < "$1/w.err" 2>/dev/null)
}
verdict() { # $1 = label, $2 = the exit code, $3 = the whole stdout it must be (and nothing on stderr), $4 = optional: the most seconds since T0 -> one PASS/FAIL line; a PASS shows the line
  local slow=""
  if [ -n "${4:-}" ] && [ $((SECONDS - T0)) -gt "$4" ]; then slow=" — took $((SECONDS - T0)) s, more than $4"; fi
  if [ "$RC" = "$2" ] && [ "$OUT" = "$3" ] && [ -z "$ERR" ] && [ -z "$slow" ]; then ok "$1: $OUT"; else ko "$1: exit $RC (want $2), stdout '$OUT' (want '$3'), stderr '$ERR'$slow"; fi
}
fixture_or_ko() { fixture "$1" || { ko "$2: could not build the fixture remote and clones in $1"; return 1; }; }
never_armed() { endw "$1" 2; ko "$2: the watcher never took its baseline (exit $RC, stdout '$OUT', stderr '$ERR', trace: $(grep -c 'ls-remote' "$1/trace" 2>/dev/null) ls-remote calls)"; }

# --- 1. the core: a push with the file under --path wakes the watcher
scn_push_path() {
  local f="$D/push-path" head0 want
  fixture_or_ko "$f" "push + --path" || return
  head0=$(git -C "$f/a" rev-parse HEAD)
  startw "$f" --git origin main --path docs/M3-RESULT.md --every 1 --max 40s
  armed "$f" || { never_armed "$f" "push + --path"; return; }
  bpush "$f" "M3: render + result" docs/M3-RESULT.md; want="pushed $(sha7 "$f") \"M3: render + result\" · docs/M3-RESULT.md"
  T0=$SECONDS; endw "$f" 40
  verdict "push with docs/M3-RESULT.md under --path → exit 0 within 30 s of the push (a 1 s poll), one line naming the commit and the file" 0 "$want" 30
  if [ "$(git -C "$f/a" rev-parse HEAD)" = "$head0" ] && [ -z "$(git -C "$f/a" status --porcelain)" ] && [ "$(git -C "$f/a" rev-parse refs/remotes/origin/main)" = "$(git -C "$f/b" rev-parse HEAD)" ]; then
    ok "the watcher only fetched: clone a's HEAD and work tree are as they were, origin/main moved to the pushed commit"
  else ko "the watcher touched clone a: HEAD $(git -C "$f/a" rev-parse HEAD) (was $head0), status '$(git -C "$f/a" status --porcelain)', origin/main $(git -C "$f/a" rev-parse refs/remotes/origin/main)"; fi
}

# --- 2. a push WITHOUT the file under --path is not a signal
scn_push_nofile() {
  local f="$D/push-nofile"
  fixture_or_ko "$f" "push without the file" || return
  startw "$f" --git origin main --path docs/M3-RESULT.md --every 1 --max 10s   # the longest case of the suite: it runs out its --max
  armed "$f" || { never_armed "$f" "push without the file"; return; }
  bpush "$f" "wip: notes only" notes.md
  endw "$f" 40
  if grep -q -E "built-in: git '?fetch" "$f/trace"; then verdict "push WITHOUT docs/M3-RESULT.md under --path → the watcher fetched the new head, found no file, kept waiting → exit 3 at --max" 3 "no signal after 10s (git origin/main · docs/M3-RESULT.md)"
  else ko "push without the file: the watcher never looked at the new head (no fetch in its trace) — exit $RC, stdout '$OUT'"; fi
}

# --- 3. ... and the next push, with the file, fires: the watcher kept waiting from the new sha
scn_two_pushes() {
  local f="$D/two-pushes" n=0 first want
  fixture_or_ko "$f" "two pushes" || return
  startw "$f" --git origin main --path docs/M3-RESULT.md --every 1 --max 40s
  armed "$f" || { never_armed "$f" "two pushes"; return; }
  bpush "$f" "wip: notes only" notes.md; first=$(sha7 "$f")
  while ! polled_after "$f" 'cat-file' && [ $n -lt 150 ]; do sleep 0.2; n=$((n + 1)); done   # the watcher has been through its file check on push 1 and polled again
  if ! kill -0 "$WPID" 2>/dev/null; then endw "$f" 1; ko "two pushes: the watcher ended on a push without the file (exit $RC, stdout '$OUT')"; return; fi
  if [ -s "$f/w.out" ]; then endw "$f" 1; ko "two pushes: the watcher printed while it was waiting: '$(cat "$f/w.out")'"; return; fi
  bpush "$f" "M3: render + result" docs/M3-RESULT.md; want="pushed $(sha7 "$f") \"M3: render + result\" · docs/M3-RESULT.md"
  endw "$f" 40
  if [ "$first" != "$(sha7 "$f")" ]; then verdict "silent while waiting; push 1 without the file is no signal, push 2 with it fires and names push 2's commit (it kept waiting from the new sha)" 0 "$want"
  else ko "two pushes: both pushes have the same sha"; fi
}

# --- 4. nothing happens: the session is still woken
scn_no_push() {
  local f="$D/no-push"
  fixture_or_ko "$f" "no push" || return
  startw "$f" --git origin main --every 1 --max 3s; T0=$SECONDS; endw "$f" 60
  verdict "no push → silent, then exit 3 at --max with the 'no signal after' line" 3 "no signal after 3s (git origin/main)" 45
}

# --- 5-7. --file
scn_file_appears() {
  local f="$D/file-appears" p; mkdir -p "$f/a"; p=$(wp "$f/DONE")
  startw "$f" --file "$p" --every 1 --max 40s
  sleep 2
  if ! kill -0 "$WPID" 2>/dev/null; then endw "$f" 1; ko "--file appears: the watcher ended before the file existed (exit $RC, stdout '$OUT')"; return; fi
  printf 'hello' > "$f/DONE.tmp" && mv "$f/DONE.tmp" "$f/DONE"   # created atomically, the way a writer should
  endw "$f" 40
  verdict "--file appears while the watcher waits → exit 0, 'file <path> (<n> bytes)'" 0 "file $p (5 bytes)"
}
scn_file_exists() {
  local f="$D/file-exists" p out rc t=$SECONDS; mkdir -p "$f"; p=$(wp "$f/READY"); printf 'twelve bytes' > "$f/READY"
  out=$(py "$WATCH" --file "$p" --every 1 --max 30s 2>"$f/err"); rc=$?; out=$(printf '%s' "$out" | tr -d '\r')
  if [ "$rc" = 0 ] && [ "$out" = "file $p (12 bytes)" ] && [ ! -s "$f/err" ] && [ $((SECONDS - t)) -le 30 ]; then ok "--file that is already there → exit 0 at once: $out"
  else ko "--file already there: exit $rc, stdout '$out', stderr '$(cat "$f/err")', $((SECONDS - t)) s"; fi
}
scn_file_never() {
  local f="$D/file-never" p; mkdir -p "$f/a"; p=$(wp "$f/NEVER")
  startw "$f" --file "$p" --every 1 --max 2s; endw "$f" 30
  verdict "--file that never comes → exit 3 at --max, naming the file" 3 "no signal after 2s (file $p)"
}

# --- 8-9. a dead remote ends the watcher (exit 4), it never spins
scn_dead_start() {
  local f="$D/dead-start" t=$SECONDS
  fixture_or_ko "$f" "dead remote" || return
  git -C "$f/a" remote set-url origin "$f/gone.git"   # nothing there
  startw "$f" --git origin main --every 1 --max 100s; endw "$f" 90
  case "$OUT" in
    "cannot reach origin: "*gone.git*) if [ "$RC" = 4 ] && [ -z "$ERR" ] && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && [ $((SECONDS - t)) -le 60 ]; then ok "a remote that cannot be reached from the start → exit 4 after 3 failed polls, one line: $OUT"
      else ko "dead remote: exit $RC (want 4), stderr '$ERR', $((SECONDS - t)) s, stdout '$OUT'"; fi;;
    *) ko "dead remote: want 'cannot reach origin: … gone.git…', got exit $RC, stdout '$OUT', stderr '$ERR'";;
  esac
}
scn_dead_mid() {
  local f="$D/dead-mid" i
  fixture_or_ko "$f" "remote lost mid-wait" || return
  startw "$f" --git origin main --every 1 --max 40s
  armed "$f" || { never_armed "$f" "remote lost mid-wait"; return; }
  for i in 1 2 3 4 5 6 7 8 9 10; do mv "$f/remote.git" "$f/remote.moved" 2>/dev/null && break; sleep 0.5; done   # Windows may hold the directory for a moment
  endw "$f" 40
  case "$OUT" in
    "cannot reach origin: "?*) if [ "$RC" = 4 ] && [ -z "$ERR" ]; then ok "the remote disappears while the watcher waits → exit 4, not exit 3 and not a hang: $OUT"
      else ko "remote lost mid-wait: exit $RC (want 4), stderr '$ERR', stdout '$OUT'"; fi;;
    *) ko "remote lost mid-wait: want 'cannot reach origin: …', got exit $RC, stdout '$OUT', stderr '$ERR'";;
  esac
}

# --- 10. the incident this exists for (docs/notes/one-session-design.md, "The 'step done' message that never arrived")
scn_incident() {
  local f="$D/incident" want
  fixture_or_ko "$f" "incident replay" || return
  # the manager hands the step to the builder and arms the watcher first; from here nothing but the remote can tell it anything
  startw "$f" --git origin main --path docs/M3-RESULT.md --every 1 --max 40s
  armed "$f" || { never_armed "$f" "incident replay"; return; }
  # the builder finishes at 20:57 and pushes the result ...
  bpush "$f" "M3: render + result" docs/M3-RESULT.md; want="pushed $(sha7 "$f") \"M3: render + result\" · docs/M3-RESULT.md"
  # ... then sends "step done" with its own messaging tool. The message goes nowhere: no reader, nothing delivered.
  mkdir -p "$f/chat"; echo "step done" > "$f/chat/to-manager"; rm -f "$f/chat/to-manager"
  T0=$SECONDS; endw "$f" 40
  verdict "incident replay — builder pushes, its chat message is lost → the watcher still fires (within 30 s of the push, a 1 s poll), naming the commit and docs/M3-RESULT.md" 0 "$want" 30
}

# --- 11-15. the rest of the --git paths
scn_push_branch() {
  local f="$D/push-branch" want
  fixture_or_ko "$f" "push without --path" || return
  startw "$f" --git origin main --every 1 --max 40s
  armed "$f" || { never_armed "$f" "push without --path"; return; }
  bpush "$f" "docs: handover notes"; want="pushed $(sha7 "$f") \"docs: handover notes\" · main"
  endw "$f" 40
  verdict "push without --path → exit 0, the line ends with the branch" 0 "$want"
}
scn_new_branch() {
  local f="$D/new-branch" want
  fixture_or_ko "$f" "new branch" || return
  startw "$f" --git origin feature/m3-render --every 1 --max 40s   # the remote has no such branch yet: that is the baseline
  armed "$f" || { never_armed "$f" "new branch"; return; }
  ( cd "$f/b" && git checkout -q -b feature/m3-render && echo r > render.txt && git add render.txt && git commit -q -m "M3: first render" && git push -q origin feature/m3-render ) >/dev/null 2>&1
  want="pushed $(sha7 "$f") \"M3: first render\" · feature/m3-render"
  endw "$f" 40
  verdict "a branch the remote does not have yet: its first push is the signal" 0 "$want"
}
scn_path_spelling() {
  local f="$D/path-spelling" want
  fixture_or_ko "$f" "--path spelling" || return
  startw "$f" --git origin main --path '.\docs\M3-RESULT.md' --every 1 --max 40s   # a Windows spelling: backslashes and a leading .\
  armed "$f" || { never_armed "$f" "--path spelling"; return; }
  bpush "$f" "M3: render + result" docs/M3-RESULT.md; want="pushed $(sha7 "$f") \"M3: render + result\" · docs/M3-RESULT.md"
  endw "$f" 40
  verdict "--path '.\\docs\\M3-RESULT.md' is read as docs/M3-RESULT.md (git's spelling)" 0 "$want"
}
scn_utf8() {
  local f="$D/utf8" want
  fixture_or_ko "$f" "UTF-8" || return
  XENV=PYTHONIOENCODING=cp1252 startw "$f" --git origin main --every 1 --max 40s   # a console in the Windows ANSI code page: 中文 and → do not exist there
  armed "$f" || { never_armed "$f" "UTF-8"; return; }
  bpush "$f" "Ünï 中文 → done" docs/u.md; want="pushed $(sha7 "$f") \"Ünï 中文 → done\" · main"
  endw "$f" 40
  verdict "a non-ASCII subject under PYTHONIOENCODING=cp1252 → the line is UTF-8 (· Ü 中文 →), not an error and not mojibake" 0 "$want"
}
scn_every_gt_max() {
  local f="$D/every-gt-max"
  fixture_or_ko "$f" "--every longer than --max" || return
  startw "$f" --git origin main --every 120 --max 2s; T0=$SECONDS; endw "$f" 100
  verdict "--every 120 --max 2s → the sleep is cut at the deadline: exit 3 after about 2 s (checked: under 60), not after 120" 3 "no signal after 2s (git origin/main)" 60
}
scn_no_branch() {
  local f="$D/no-branch"
  fixture_or_ko "$f" "a branch typo" || return
  startw "$f" --git origin mian --every 1 --max 3s; T0=$SECONDS; endw "$f" 60
  verdict "a branch the remote never had (a typo) → exit 3 at --max, and the line says the branch never showed" 3 "no signal after 3s (git origin/mian · no such branch on the remote)" 45
}
scn_tag_not_branch() {
  local f="$D/tag-not-branch"
  fixture_or_ko "$f" "a tag named like the branch" || return
  startw "$f" --git origin main --every 1 --max 8s
  armed "$f" || { never_armed "$f" "a tag named like the branch"; return; }
  ( cd "$f/b" && git tag main && git push -q origin refs/tags/main ) >/dev/null 2>&1   # a TAG called main lands on the remote: the branch has not moved
  git -C "$f/remote.git" show-ref --verify -q refs/tags/main || { endw "$f" 1; ko "a tag named like the branch: the tag never reached the remote, nothing was tested"; return; }
  T0=$SECONDS; endw "$f" 60
  verdict "a pushed tag that is named like the branch is not a push to the branch → no signal, exit 3" 3 "no signal after 8s (git origin/main)" 50
}

# --- 20. armed late (or re-armed after a restart killed the first watcher): --since <the hand-off's commit> still catches the push
scn_since_late() {
  local f="$D/since-late" s0 want
  fixture_or_ko "$f" "armed late with --since" || return
  s0=$(git -C "$f/a" rev-parse --short=7 HEAD)   # the remote's head at the hand-off, abbreviated: --since matches by prefix
  bpush "$f" "M3: render + result" docs/M3-RESULT.md; want="pushed $(sha7 "$f") \"M3: render + result\" · docs/M3-RESULT.md"
  startw "$f" --git origin main --path docs/M3-RESULT.md --since "$s0" --every 1 --max 30s   # the builder pushed BEFORE this watcher started
  T0=$SECONDS; endw "$f" 30
  verdict "armed after the builder's push, with --since <the hand-off's commit> → it fires on its first poll" 0 "$want" 20
  startw "$f" --git origin main --path docs/M3-RESULT.md --every 1 --max 3s
  endw "$f" 20
  verdict "the same late arm without --since takes that push as its baseline → no signal (why --since exists)" 3 "no signal after 3s (git origin/main · docs/M3-RESULT.md)"
}

# --- 18. usage errors: exit 2, ONE line on stderr, nothing on stdout
uerr() { # $1 = label, $2 = text the line must contain, rest = the arguments; NOTEST=1 runs without SMARTUSE_WATCH_TEST (the real --every floor)
  local label=$1 want=$2 rc so se; shift 2
  if [ "${NOTEST:-}" = 1 ]; then env -u SMARTUSE_WATCH_TEST bash "$H/py.sh" "$WATCH" "$@" > "$T/so" 2> "$T/se"; rc=$?
  else bash "$H/py.sh" "$WATCH" "$@" > "$T/so" 2> "$T/se"; rc=$?; fi
  so=$(tr -d '\r' < "$T/so"); se=$(tr -d '\r' < "$T/se")
  if [ "$rc" = 2 ] && [ -z "$so" ] && [ "$(printf '%s\n' "$se" | wc -l | tr -d ' ')" = 1 ] && case "$se" in "watch: "*"$want"*) true;; *) false;; esac; then ok "usage: $label → exit 2, one line on stderr ($want)"
  else ko "usage: $label: exit $rc (want 2), stdout '$so', stderr '$se' (want one line with '$want')"; fi
}
scn_usage() {
  local f="$D/usage" T="$D/usage-tmp" p so rc; mkdir -p "$T" "$D/not-a-repo"
  fixture_or_ko "$f" "usage" || return
  cd "$f/a" || return
  uerr "no arguments" "give --git <remote> <branch> or --file <path>"
  uerr "--git without a branch" "--git needs <remote> <branch>" --git origin
  uerr "--git and --file together" "two modes" --git origin main --file "$D/x"
  uerr "--pid (there is none: the command itself is the background task)" "unknown option --pid" --pid 123 --git origin main
  uerr "--path with --file" "--path goes with --git" --file "$D/x" --path docs/x.md
  uerr "--since with --file" "--since goes with --git" --file "$D/x" --since abc1234
  uerr "--since that is not a sha" "--since must be a commit sha" --git origin main --since HEAD
  NOTEST=1 uerr "--every 1 without SMARTUSE_WATCH_TEST (the floor is 5 s)" "--every must be whole seconds, 5 or more" --git origin main --every 1
  uerr "--every that is not a whole number" "--every must be whole seconds, 1 or more" --git origin main --every 1.5
  uerr "--max with no unit" "--max must look like 90s, 30m or 4h" --git origin main --max 5
  uerr "--max 4d (days are not a unit)" "--max must look like" --git origin main --max 4d
  uerr "--max 0s" "--max must look like" --git origin main --max 0s
  uerr "--max with no value" "--max needs a value" --git origin main --max
  uerr "an option given twice" "--max given twice" --git origin main --max 1h --max 2h
  uerr "a stray argument" "unexpected argument 'extra'" --git origin main extra
  uerr "a remote that starts with '-' (it would be read as a git option)" "must not start with '-'" --git -x main
  uerr "an empty --path" "--path is empty" --git origin main --path ""
  uerr "--file on a directory" "is a directory" --file "$D"
  uerr "a branch name git refuses" "is not a valid branch name" --git origin "bad..name"
  ( cd "$D/not-a-repo" && uerr "--git outside a git clone" "not inside a git clone" --git origin main )
  p=$(wp "$D/usage-file"); printf 'x' > "$D/usage-file"
  py "$WATCH" --file "$p" --every 1 --max 5s > "$T/so" 2> "$T/se"; rc=$?; so=$(tr -d '\r' < "$T/so")
  if [ "$rc" = 0 ] && [ "$so" = "file $p (1 bytes)" ] && [ ! -s "$T/se" ]; then ok "SMARTUSE_WATCH_TEST=1 lowers the --every floor to 1: --every 1 is accepted"; else ko "--every 1 with SMARTUSE_WATCH_TEST=1: exit $rc, stdout '$so', stderr '$(cat "$T/se")'"; fi
  py "$WATCH" --help > "$T/so" 2> "$T/se"; rc=$?; so=$(tr -d '\r' < "$T/so")
  case "$so" in "usage: watch.py --git <remote> <branch>"*"--file <path>"*) [ "$rc" = 0 ] && [ ! -s "$T/se" ] && ok "--help → the usage on stdout, exit 0" || ko "--help: exit $rc, stderr '$(cat "$T/se")'";; *) ko "--help: exit $rc, stdout '$so'";; esac
}

# --- 19. the pure functions and the poll loop, in one interpreter (a fake remote drives the loop: no sleeps, no git)
scn_unit() {
  py - "$WATCH" "$D/unit-home" <<'PY'
import contextlib, io, os, sys, time
path = sys.argv[1]
ns = {"__name__": "watch_under_test", "__file__": path}
exec(compile(open(path, encoding="utf-8").read(), path, "exec"), ns)
def check(label, ok, detail=""):
    print(("PASS " + label) if ok else ("FAIL " + label + (": " + str(detail) if detail != "" else "")))
# --- --max
pd = ns["parse_duration"]
def rejects(x):
    try:
        pd(x)
        return False
    except ValueError:
        return True
refused = ["", "5", "0s", "0h", "1.5h", "h", "4d", "-3s", "90 s", "1e3s", "\u0663s"]
check("--max: 90s, 30m, 4h (any case, padded) → seconds and normalised text; a bare number, 0, a decimal, another unit, a non-ASCII digit → refused",
      pd("90s") == (90, "90s") and pd("30m") == (1800, "30m") and pd("4h") == (14400, "4h") and pd(" 2H ") == (7200, "2h") and pd("007s") == (7, "7s")
      and all(rejects(x) for x in refused), [x for x in refused if not rejects(x)])
check("--path: backslashes, a leading .\\ or / are dropped (git's spelling)", ns["norm_path"](".\\docs\\x.md") == "docs/x.md" and ns["norm_path"]("/docs/x.md") == "docs/x.md" and ns["norm_path"]("./a/b") == "a/b" and ns["norm_path"]("docs/x.md") == "docs/x.md")
# --- text that comes from outside
cl = ns["clean"]
got = cl("fix:\x1b[31m red\x1b[0m\ttab\nnewline  \u202edrow  \u200bzw")
check("a commit subject: ESC, tabs, newlines, bidi and zero-width characters become single spaces", got == "fix: [31m red [0m tab newline drow zw", repr(got))
check("a commit subject is cut at 100 characters with an ellipsis; a short one is untouched", cl("x" * 300) == "x" * 99 + "…" and len(cl("é" * 100)) == 100 and cl("é" * 100).endswith("é") and cl("  a  b ") == "a b")
el = ns["error_line"]
e_path = "fatal: '/x/y.git' does not appear to be a git repository\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.\n"
e_ssh = "ssh: Could not resolve hostname github.invalid: Name or service not known\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.\n"
e_403 = "remote: Permission to x/y.git denied to bob.\nfatal: unable to access 'https://github.com/x/y/': The requested URL returned error: 403\n"
e_rpc = "error: RPC failed; HTTP 502 curl 22 The requested URL returned error: 502\nfatal: expected flush after ref listing\n"
check("'cannot reach' keeps git's last fatal:/error: line without its generic trailer, else the first line, else nothing",
      el(e_path) == "fatal: '/x/y.git' does not appear to be a git repository" and el(e_ssh) == "ssh: Could not resolve hostname github.invalid: Name or service not known"
      and el(e_403) == "fatal: unable to access 'https://github.com/x/y/': The requested URL returned error: 403" and el(e_rpc) == "fatal: expected flush after ref listing" and el("") == "" and el("\n \n") == "",
      [el(e_path), el(e_ssh), el(e_403), el(e_rpc)])
mk = ns["mask"]
check("a credential in a URL remote never reaches the output (the remote's name and git's error line)",
      mk("https://bob:s3cr3t@example.com/x/y.git") == "https://example.com/x/y.git" and mk("https://tok@h/x") == "https://h/x" and mk("git@example.com:x/y.git") == "git@example.com:x/y.git"
      and "pw" not in el("fatal: unable to access 'https://bob:pw@h/x/': Could not resolve host: h") and "h/x/" in el("fatal: unable to access 'https://bob:pw@h/x/': Could not resolve host: h"))
# --- deadline arithmetic
b = ns["budget"]
check("a git call's time limit: its own cap, never past the deadline, never under 5 s", b(60, 1000) == 60 and b(600, 100) == 100 and b(60, 2) == 5 and b(60, -3) == 5)
real_clock = ns["clock"]
t0 = (1000.0, 50.0)
ns["clock"] = lambda: (1000.0 + 7200, 50.0 + 10)
slept = ns["elapsed"](t0)
ns["clock"] = lambda: (1000.0 - 5, 50.0 + 20)
stepped = ns["elapsed"](t0)
ns["clock"] = real_clock
check("--max by the clock that ran further: a laptop that slept (wall 2 h, monotonic 10 s) is 2 h in; a wall clock stepped back is not rewound", slept == 7200 and stepped == 20, (slept, stepped))
# --- running git: bounded, UTF-8
t = time.time()
rc, out, err = ns["run"]([sys.executable, "-c", "import time; time.sleep(30)"], 1)
check("a call still running after its limit is killed and reported (rc None, 'timed out'), well before it would have ended", rc is None and "timed out" in err and time.time() - t < 15, (rc, err, time.time() - t))
rc, out, err = ns["run"]([sys.executable, "-c", "import sys; sys.stdout.buffer.write(b'caf\\xc3\\xa9 \\xff'); sys.stderr.buffer.write(b'\\xe4')"], 30)
check("a call's output is decoded as UTF-8 with replacement, never an error", rc == 0 and out == "caf\u00e9 \ufffd" and err == "\ufffd", (rc, out, err))
rc, out, err = ns["run"](["no-such-program-for-watch-test"], 5)
check("a program that cannot start is reported (rc None, 'cannot run'), not raised", rc is None and "cannot run" in err and out == "", (rc, err))
class Ascii(io.StringIO):
    def write(self, s):
        s.encode("ascii")
        return super().write(s)
s = Ascii()
code = ns["say"]("pushed abc1234 \"x\" \u00b7 main", 0, s)
check("a stream that cannot take the line in UTF-8 gets it with escapes instead of nothing (the exit code is still returned)", code == 0 and s.getvalue() == "pushed abc1234 \"x\" \\xb7 main\n", s.getvalue())
# --- native_path, as in ledger.py
np_ = ns["native_path"]
off_windows = os.name == "nt" or np_("/c/Users/x/DONE") == "/c/Users/x/DONE"
real_name = os.name
os.name = "nt"
simulated = np_("/c/Users/x/DONE") == "C:/Users/x/DONE" and np_("/tmp/tmp.X/DONE") == "/tmp/tmp.X/DONE" and np_("C:/Users/x") == "C:/Users/x" and np_("") == "" and np_(None) is None
os.name = real_name
check("native_path: /c/Users/x -> C:/Users/x on Windows only; /tmp/... and C:/... untouched; a no-op elsewhere", off_windows and simulated)
# --- the poll loop with a fake remote
U = ns["Unreachable"]
SHA_A, SHA_B, SHA_C = "a" * 40, "b" * 40, "c" * 40
def drive(ls, path=None, has=None, have=None, max_s=0.5):
    """watch_git over a fake remote: ls(remote, branch, timeout) is the head listing, has(sha, path) / have(sha) answer the checks on
    the fetched commit. -> (exit code, what it printed, the time limits each call was given, by call)."""
    saved = {k: ns[k] for k in ("ls_remote", "fetch", "have_commit", "has_path", "subject_of")}
    lm = {"ls": [], "fetch": [], "have": [], "has": [], "subject": []}
    ns["ls_remote"] = lambda remote, branch, timeout=None: (lm["ls"].append(timeout), ls(remote, branch, timeout))[1]
    ns["fetch"] = lambda remote, branch, timeout=None: lm["fetch"].append(timeout)
    ns["have_commit"] = lambda sha, timeout=None: (lm["have"].append(timeout), have(sha) if have else True)[1]
    ns["has_path"] = lambda sha, p, timeout=None: (lm["has"].append(timeout), has(sha, p) if has else True)[1]
    ns["subject_of"] = lambda sha, timeout=None: (lm["subject"].append(timeout), "subj")[1]
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = ns["watch_git"]("origin", "main", path, 0, max_s, "1s")
    finally:
        ns.update(saved)
    return rc, buf.getvalue().strip(), lm
def script(*heads):
    state = {"i": 0, "calls": 0}
    def ls(remote, branch, timeout=None):
        state["calls"] += 1
        h = heads[min(state["i"], len(heads) - 1)]
        state["i"] += 1
        if isinstance(h, Exception):
            raise h
        return h
    ls.state = state
    return ls
dead = script(U("boom"))
rc, out, _ = drive(dead)
check("3 failed polls in a row → exit 4 'cannot reach origin: <the error>' (exactly 3 calls, not a spin)", rc == 4 and out == "cannot reach origin: boom" and dead.state["calls"] == 3, (rc, out, dead.state["calls"]))
n = {"i": 0}
def blip(remote, branch, timeout=None):
    n["i"] += 1
    if n["i"] % 3:
        raise U("blip")
    return SHA_A
rc, out, _ = drive(blip)
check("two failures then a good poll, again and again → the counter resets: no 'cannot reach', the deadline ends it (exit 3)", rc == 3 and out == "no signal after 1s (git origin/main)" and n["i"] > 6, (rc, out, n["i"]))
rc, out, lm = drive(script(SHA_A, SHA_A, SHA_B, SHA_B, SHA_B, SHA_C), path="docs/x.md", has=lambda sha, p: sha == SHA_C)
check("--path: a head without the file is no signal and is not looked at again; the next head with it fires (2 fetches, the line names the last)",
      rc == 0 and out == 'pushed ccccccc "subj" · docs/x.md' and len(lm["fetch"]) == 2, (rc, out, lm["fetch"]))
rc, out, lm = drive(script(None, None, SHA_A))
check("a branch the remote lacks is a baseline; its first push fires", rc == 0 and out == 'pushed aaaaaaa "subj" · main' and len(lm["fetch"]) == 1, (rc, out, lm["fetch"]))
rc, out, lm = drive(script(SHA_A, None, None, SHA_A, SHA_A), max_s=0.3)
check("a branch that vanishes is not a signal; when it is back (new baseline: none) its head is", rc == 0 and out == 'pushed aaaaaaa "subj" · main', (rc, out, lm["fetch"]))
looks = {"n": 0}
def there_second_time(sha):
    looks["n"] += 1
    return looks["n"] > 1
rc, out, lm = drive(script(SHA_A, SHA_B, SHA_B), have=there_second_time)
check("a head whose commit is missing after the fetch (a force-push in between) is no signal yet and is not swallowed: the next poll fetches it again and fires",
      rc == 0 and out == 'pushed bbbbbbb "subj" · main' and len(lm["fetch"]) == 2, (rc, out, lm["fetch"]))
rc, out, lm = drive(script(SHA_A, SHA_B), path="docs/x.md", max_s=1000)
roomy = (lm["ls"], lm["fetch"], lm["have"], lm["has"], lm["subject"])
rc2, out2, lm2 = drive(script(SHA_A, SHA_A, SHA_B), path="docs/x.md", max_s=0.2)
tight = [t for v in lm2.values() for t in v]
check("every git call of the loop gets its own limit (60 s ls-remote, 10 min fetch, 2 min checks), cut to the time left before --max and never under 5 s",
      roomy == ([60, 60], [600], [120], [120], [120]) and tight and all(t == 5 for t in tight), (roomy, tight))
# --- --file: a quoted ~ reaches the watcher unexpanded
import shutil
home = sys.argv[2]   # under the suite's own temp dir, removed with it
os.makedirs(home, exist_ok=True)
open(os.path.join(home, "f.txt"), "w").close()
saved_env = {k: os.environ.get(k) for k in ("HOME", "USERPROFILE")}
os.environ["HOME"] = os.environ["USERPROFILE"] = home   # POSIX reads HOME, Windows USERPROFILE
tilde = os.path.isfile(ns["real_path"]("~/f.txt"))
for k, v in saved_env.items():
    if v is None:
        os.environ.pop(k, None)
    else:
        os.environ[k] = v
shutil.rmtree(home, ignore_errors=True)
check("--file '~/f.txt': a quoted ~ is expanded before the file is looked for", tilde)
PY
}

PIDS=""; EXPECT=""
task() { # $1 = sort key, $2 = how many PASS/FAIL lines it must print, rest = the function: runs in the background, its output -> $D/res.$1
  local k=$1 n=$2; shift 2
  ( "$@" ) > "$D/res.$k" 2>&1 &
  PIDS="$PIDS $!"; EXPECT="$EXPECT $k:$n"
}
task 01 2 scn_push_path
task 02 1 scn_push_nofile
task 03 1 scn_two_pushes
task 04 1 scn_no_push
task 05 1 scn_file_appears
task 06 1 scn_file_exists
task 07 1 scn_file_never
task 08 1 scn_dead_start
task 09 1 scn_dead_mid
task 10 1 scn_incident
task 11 1 scn_push_branch
task 12 1 scn_new_branch
task 13 1 scn_path_spelling
task 14 1 scn_utf8
task 15 1 scn_every_gt_max
task 16 1 scn_no_branch
task 17 1 scn_tag_not_branch
task 18 22 scn_usage
task 19 21 scn_unit
task 20 2 scn_since_late
wait $PIDS
fail=0
for e in $EXPECT; do
  k=${e%%:*}; n=${e##*:}; r="$D/res.$k"
  cat "$r"
  got=$(grep -c -E '^(PASS|FAIL) ' "$r" 2>/dev/null)
  grep -q '^FAIL ' "$r" && fail=1
  [ "${got:-0}" = "$n" ] || { echo "FAIL scenario $k printed ${got:-0} result lines, expected $n"; fail=1; }
done
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
