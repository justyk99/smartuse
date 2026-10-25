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
# write must not choose what the hooks execute. Any other content (a path, another word), a name PATH no longer has, or
# a Windows Store alias (WindowsApps) is ignored and probed again. The file is written only when ~/.claude/smartuse/
# already exists (the hooks create it) and is not a symlink, so a first event costs no extra process.
# PYTHONUTF8=1 puts every hook in UTF-8 mode: on Windows, stdin/stdout and open() would otherwise use the ANSI code page.
# Usage: bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/<hook>.py" [args…]
export PYTHONUTF8=1
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
for cand in "python3" "python" "py -3"; do
  # sys.executable with forward slashes: Git Bash runs C:/Users/... as it is. $cand unquoted on purpose: "py -3" is two words.
  P=$($cand -c "import sys; print(sys.executable.replace(chr(92), '/'))" </dev/null 2>/dev/null) || continue
  P=${P%$'\r'}
  if [ -n "$P" ] && [ -x "$P" ]; then
    [ -n "$C" ] && [ -d "${C%/*}" ] && [ ! -L "$C" ] && printf '%s\n' "$cand" > "$C" 2>/dev/null   # remember the NAME, never through a symlink
    exec "$P" "$@"
  fi
  exec $cand "$@"
done
exit 0
