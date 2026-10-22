#!/usr/bin/env bash
# py.sh — run a smartuse hook with the Python 3 this machine really has. Claude Code runs hook commands through bash
# (Git Bash on Windows). On a stock Windows install `python3` on PATH is the Microsoft Store stub: it prints "Python was
# not found; run without arguments to install from the Microsoft Store…" and exits 9009, so a plain `python3 hook.py`
# ran nothing there; the real interpreter is `python` or `py -3`. Try the candidates in that order and exec the first one
# that can run `-c "import sys"`. The probe takes its stdin from /dev/null and discards its errors, so the hook's stdin
# (the event JSON) reaches the interpreter untouched. None works -> print nothing, exit 0: a hook must never block.
# The probe is a full interpreter start, and on that laptop every start took 0.4–3.6 s (2 s per event through this file, the
# stub probed first), on every hook event. So the interpreter a probe proved is remembered as its absolute path in
# ~/.claude/smartuse/interpreter and run directly next time: one start per event, no stub. A remembered path that no longer
# exists, is not executable or is not named python* is ignored and probed again. The file is written only when
# ~/.claude/smartuse/ already exists (the hooks create it), so a first event costs no extra process.
# PYTHONUTF8=1 puts every hook in UTF-8 mode: on Windows, stdin/stdout and open() would otherwise use the ANSI code page.
# Usage: bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/<hook>.py" [args…]
export PYTHONUTF8=1
C="${HOME:+$HOME/.claude/smartuse/interpreter}"
P=""
if [ -n "$C" ] && [ -f "$C" ] && { read -r P || [ -n "$P" ]; } < "$C" && [ -n "$P" ] && [ -x "$P" ]; then
  case "${P##*/}" in [Pp][Yy][Tt][Hh][Oo][Nn]*) exec "$P" "$@";; esac
fi
for cand in "python3" "python" "py -3"; do
  # sys.executable with forward slashes: Git Bash runs C:/Users/... as it is. $cand unquoted on purpose: "py -3" is two words.
  P=$($cand -c "import sys; print(sys.executable.replace(chr(92), '/'))" </dev/null 2>/dev/null) || continue
  P=${P%$'\r'}
  if [ -n "$P" ] && [ -x "$P" ]; then
    [ -n "$C" ] && [ -d "${C%/*}" ] && printf '%s\n' "$P" > "$C" 2>/dev/null
    exec "$P" "$@"
  fi
  exec $cand "$@"
done
exit 0
