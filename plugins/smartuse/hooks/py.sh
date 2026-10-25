#!/usr/bin/env bash
# py.sh — run a smartuse hook with the Python 3 this machine really has. Claude Code runs hook commands through bash
# (Git Bash on Windows). On a stock Windows install `python3` on PATH is the Microsoft Store stub: it prints "Python was
# not found; run without arguments to install from the Microsoft Store…" and exits 9009, so a plain `python3 hook.py`
# ran nothing there; the real interpreter is `python` or `py -3`. Try the candidates in that order and exec the first one
# that can run `-c "import sys"`. The probe takes its stdin from /dev/null and discards its errors, so the hook's stdin
# (the event JSON) reaches the interpreter untouched. None works -> print nothing, exit 0: a hook must never block.
# The probe is a full interpreter start, and on that laptop every start took 0.4–3.6 s (2 s per event through this file, the
# stub probed first), on every hook event. So the candidate a probe proved is remembered by NAME (python3, python or py -3,
# never a path) in ~/.claude/smartuse/interpreter, and next time that name is looked up on PATH and run directly: one start
# per event, no stub. The file is a hint about which probe step to skip, never a command: a state file that anything can
# write must not choose what the hooks execute. Any other content (a path, another word), a name PATH no longer has (or has
# as a file that is not executable), or a Windows Store alias (WindowsApps, any case) is ignored and probed again. The file is
# read up to 16 characters and written only when ~/.claude/smartuse/ already exists (the hooks create it) and the file is a
# regular file or a new one (never a symlink, a FIFO or another special file), so a first event costs no extra process.
# PYTHONUTF8=1 puts every hook in UTF-8 mode: on Windows, stdin/stdout and open() would otherwise use the ANSI code page.
# Usage: bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/<hook>.py" [args…]
export PYTHONUTF8=1
C="${HOME:+$HOME/.claude/smartuse/interpreter}"; P=""
if [ -n "$C" ] && [ -f "$C" ] && { read -r -n 16 P || [ -n "$P" ]; } < "$C"; then   # a regular file, read capped at 16 characters: a name is at most 7
  P=${P%$'\r'}
  case "$P" in python3|python|"py -3") W=${P%% *}                 # the word to look up: py for "py -3"
    if command -v "$W" >/dev/null 2>&1; then                        # builtin: PATH scan, no process
      R=""; [ "${BASH_VERSINFO[0]}" -ge 4 ] && { hash "$W" 2>/dev/null; R=${BASH_CMDS[$W]}; }   # bash 3.2 has no BASH_CMDS: there $W would be read as arithmetic (an env var named python aborted the launcher)
      [ -n "$R" ] || R=$(command -v "$W")                           # the fork happens on bash 3.2, or when hash cannot find the name
      case "$R" in *[Ww][Ii][Nn][Dd][Oo][Ww][Ss][Aa][Pp][Pp][Ss]*) ;; *) [ -x "$R" ] && exec $P "$@";; esac   # a Store alias (any case) is never trusted, and the hit must be executable or it is probed instead (exec of a non-executable hit exits 2, which blocks a PreToolUse hook); $P unquoted: "py -3" is two words
    fi;;
  esac
fi
for cand in "python3" "python" "py -3"; do
  # sys.executable with forward slashes: Git Bash runs C:/Users/... as it is. $cand unquoted on purpose: "py -3" is two words.
  P=$($cand -c "import sys; print(sys.executable.replace(chr(92), '/'))" </dev/null 2>/dev/null) || continue
  P=${P%$'\r'}
  if [ -n "$P" ] && [ -x "$P" ]; then
    [ -n "$C" ] && [ -d "${C%/*}" ] && [ ! -L "$C" ] && { [ -f "$C" ] || [ ! -e "$C" ]; } && printf '%s\n' "$cand" > "$C" 2>/dev/null   # remember the NAME, only into a regular file or a new one: never through a symlink, never a FIFO or other special file (a write to a FIFO blocks)
    exec "$P" "$@"
  fi
  exec $cand "$@"
done
exit 0
