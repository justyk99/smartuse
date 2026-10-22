#!/usr/bin/env bash
# py.sh — run a smartuse hook with the Python 3 this machine really has. Claude Code runs hook commands through bash
# (Git Bash on Windows). On a stock Windows install `python3` on PATH is the Microsoft Store stub: it prints "Python was
# not found; run without arguments to install from the Microsoft Store…" and exits 9009, so a plain `python3 hook.py`
# ran nothing there; the real interpreter is `python` or `py -3`. Try the candidates in that order and exec the first one
# that can run `-c "import sys"`. The probe takes its stdin from /dev/null and discards its output, so the hook's stdin
# (the event JSON) reaches the interpreter untouched. None works -> print nothing, exit 0: a hook must never block.
# Usage: bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/<hook>.py" [args…]
works() { "$@" -c "import sys" </dev/null >/dev/null 2>&1; }
works python3 && exec python3 "$@"
works python && exec python "$@"
works py -3 && exec py -3 "$@"
exit 0
