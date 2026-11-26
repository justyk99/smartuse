#!/usr/bin/env bash
# py.sh — run a smartuse hook with the Python 3 this machine really has. Claude Code runs hook commands through bash
# (Git Bash on Windows). On a stock Windows install `python3` on PATH is the Microsoft Store stub: it prints "Python was
# not found; run without arguments to install from the Microsoft Store…" and exits 9009, so a plain `python3 hook.py`
# ran nothing there; the real interpreter is `python` or `py -3`. Try the candidates in that order and exec the first one
# that can run `-c "import sys"`. The probe takes its stdin from /dev/null and discards its errors, so the hook's stdin
# (the event JSON) reaches the interpreter untouched. None works -> print nothing, exit 0: a hook must never block.
# The probe is a full interpreter start, and on that laptop every start took 0.4–3.6 s (2 s per event through this file, the
# stub probed first), on every hook event. So the candidate a probe proved is remembered by NAME (python3, python or py -3,
# never a path) plus the mark -I (the file holds python3 -I, python -I or py -3 -I: proven to start isolated, see below) in
# ~/.claude/smartuse/interpreter, and next time that name is looked up on PATH and run directly: one start per event, no
# stub. The file is a hint about which probe step to skip, never a command, and never the start mode: a state file that
# anything can write must not choose what the hooks execute, and no content of it can select the un-isolated start. Any other
# content (a bare name from 0.7.4, a path, another word, a word with a tail), a name PATH no longer has (or has as a file that
# is not executable), or a Windows Store alias (WindowsApps, any case) is ignored and probed again, and the file is rewritten. The file is
# read up to 16 characters and written only when ~/.claude/smartuse/ already exists (the hooks create it) and the file is a
# regular file or a new one (never a symlink, a FIFO or another special file), so a first event costs no extra process.
# Every Python this file starts (the remembered name, the probe, the proven path, the candidate itself) gets the same flags, $ISO = -I -S -X utf8, so no PYTHON* variable and no site folder changes how a hook
# starts. bash itself is not isolated: it reads its own start-up settings and PATH from the session's environment before this file's first line (SECURITY.md). -I: every PYTHON* variable is ignored (a PYTHONPATH folder with a json.py, a
# wrong PYTHONHOME), the user site folder is left out, and no entry for the working folder or the script's folder goes on sys.path. -S: `site` is never imported,
# so no .pth line and no sitecustomize in the interpreter's own site folder runs (-I alone still reads them). -X utf8 is the UTF-8 mode PYTHONUTF8=1 gave every hook (on
# Windows, stdin/stdout and open() would otherwise use the ANSI code page), by option, because -I ignores the variable. The probe carries the flags too, so an
# interpreter that refuses one fails the probe and is skipped, as the Store stub is. One variable is carried over, as -B: PYTHONDONTWRITEBYTECODE, the documented opt-out
# of the bytecode cache below. PYTHONUTF8=1 is still exported and nothing is unset: a hook's own child process (until-done's check:) inherits the environment as before.
# The file's -I is a proof for the Python PATH gave that name then, not the one it gives now. So the remembered start is not an exec: Python exits 2 on an option it does not know,
# exit 2 blocks a call, and on a 2 the same name is asked once more with the flags. It starts: the 2 is the hook's own and is handed on. It refuses: the event is unread, and the probe below runs. A Python that cannot start isolated (it refuses a flag, or needs PYTHONHOME to find its library) still runs the hooks: when all three candidates
# failed the isolated probe, a second try starts them the 0.7.4 way (no flags, a WindowsApps hit skipped: the Store stub was already started once), and writes nothing, so it is never remembered.
# One optional FIRST word, --say-missing (an exact comparison, dropped before the hook path; in any later position it reaches the
# interpreter untouched): with no interpreter the launcher prints one fixed sentence on stderr and exits 2 instead of exiting 0 in
# silence. Only the SessionStart heartbeat command carries it: the docs say a SessionStart hook that exits 2 "shows stderr to user
# only" and the session goes on, so the user learns the guards are off. With an interpreter nothing changes.
# Usage: bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" [--say-missing] "${CLAUDE_PLUGIN_ROOT}/hooks/<hook>.py" [args…]
export PYTHONUTF8=1
ISO="-I -S -X utf8"; [ -n "${PYTHONDONTWRITEBYTECODE:-}" ] && ISO="$ISO -B"   # the flags of every start below, unquoted there on purpose: several words
SAY=""; [ "${1:-}" = "--say-missing" ] && { SAY=1; shift; }
# A second optional first word, --guard (the three guard commands carry it; not together with --say-missing): with no interpreter and Strict
# guards on (the plugin option's text is anything but empty / off / false / no / 0), one fixed sentence on stderr and exit 2, which blocks
# the call and shows Claude why. Light (the default, also with no option set) -> silent exit 0 as before.
GUARD=""; [ -z "$SAY" ] && [ "${1:-}" = "--guard" ] && { GUARD=1; shift; }
# The bytecode cache (0.7.0 D-YK15): Python compiles a MAIN script on every start and never keeps the result; bash-guard.py's compile alone
# is ~60 ms on every Bash call. When the first word (after the two options above) is an existing *.py file, it runs through a short loader
# passed with -c: one Python start, no extra file, and the script is read through importlib's source loader, which keeps its bytecode in
# hooks/__pycache__/ and reuses it while the source's mtime and size are unchanged. The cache is only a speed-up: PYTHONDONTWRITEBYTECODE,
# or a folder that cannot be written, means no pyc and the same run as before. With the flags above Python adds no entry of its own
# to sys.path (`-c` alone would put '' there: the cwd, the user's project), so the loader leaves sys.path alone, as it does with PYTHONSAFEPATH set, and a json.py
# planted in the project or beside the hooks is never imported. (Started without -I the loader would replace that '' with the script's own folder BEFORE it imports
# anything beyond sys and os, both loaded at start-up.) Anything that is not an existing *.py file (-c "...", -, a missing path) is passed to the interpreter untouched.
LDR='import sys,os; p=sys.argv[1]; sys.path[0]=sys.path[0] or os.path.dirname(os.path.realpath(p)); sys.argv=sys.argv[1:]; import types; from importlib.machinery import SourceFileLoader as L; a=os.path.abspath(p); l=L("__main__",a); m=types.ModuleType("__main__"); m.__file__=a; m.__loader__=l; sys.modules["__main__"]=m; exec(l.get_code("__main__"),m.__dict__)'
case "$1" in -*) ;; *.py) [ -f "$1" ] && set -- -c "$LDR" "$@";; esac
C="${HOME:+$HOME/.claude/smartuse/interpreter}"; P=""
if [ -n "$C" ] && [ -f "$C" ] && { read -r -n 16 P || [ -n "$P" ]; } < "$C"; then   # a regular file, read capped at 16 characters: a name is at most 7
  P=${P%$'\r'}
  case "$P" in "python3 -I"|"python -I"|"py -3 -I") P=${P% -I}; W=${P%% *}   # one of three exact marked words; P is the name from here on; W the word to look up: py for "py -3"
    if command -v "$W" >/dev/null 2>&1; then                        # builtin: PATH scan, no process
      R=""; [ "${BASH_VERSINFO[0]}" -ge 4 ] && { hash "$W" 2>/dev/null; R=${BASH_CMDS[$W]}; }   # bash 3.2 has no BASH_CMDS: there $W would be read as arithmetic (an env var named python aborted the launcher)
      [ -n "$R" ] || R=$(command -v "$W")                           # the fork happens on bash 3.2, or when hash cannot find the name
      # a Store alias (any case) is never trusted, and the hit must be executable or it is probed instead (exec of a non-executable hit exits 2, which blocks a PreToolUse hook); $P unquoted: "py -3" is two words
      case "$R" in *[Ww][Ii][Nn][Dd][Oo][Ww][Ss][Aa][Pp][Pp][Ss]*) ;; *) if [ -x "$R" ]; then
        command $P $ISO "$@"; E=$?                                             # not exec: bash must see the exit code. `command`: PATH only, never a shell function, as exec did
        [ "$E" = 2 ] || exit "$E"                                              # every code but 2 is handed on at once: one Python start per event
        command $P $ISO -c "import sys" </dev/null >/dev/null 2>&1 && exit 2   # the same name starts with the flags, so the 2 was the hook's own (or Python's for a script that is not there)
      fi;; esac                                                                # it refuses the flags: Python stopped at the option before it read stdin, the event is unread: probe again below
    fi;;
  esac
fi
for cand in "python3" "python" "py -3"; do
  # sys.executable with forward slashes: Git Bash runs C:/Users/... as it is. $cand unquoted on purpose: "py -3" is two words.
  P=$($cand $ISO -c "import sys; print(sys.executable.replace(chr(92), '/'))" </dev/null 2>/dev/null) || continue
  P=${P%$'\r'}
  if [ -n "$P" ] && [ -x "$P" ]; then
    [ -n "$C" ] && [ -d "${C%/*}" ] && [ ! -L "$C" ] && { [ -f "$C" ] || [ ! -e "$C" ]; } && printf '%s -I\n' "$cand" > "$C" 2>/dev/null   # remember the NAME with its mark (it just started isolated), only into a regular file or a new one: never through a symlink, never a FIFO or other special file (a write to a FIFO blocks)
    exec "$P" $ISO "$@"
  fi
  exec $cand $ISO "$@"
done
# No candidate started isolated: the 0.7.4 start, a second try. Never remembered (nothing is written), never spent on a Store alias (a WindowsApps hit was started once above), no flag at all.
for cand in "python3" "python" "py -3"; do
  R=$(command -v "${cand%% *}" 2>/dev/null); [ -n "$R" ] || continue
  case "$R" in *[Ww][Ii][Nn][Dd][Oo][Ww][Ss][Aa][Pp][Pp][Ss]*) continue;; esac
  P=$($cand -c "import sys; print(sys.executable.replace(chr(92), '/'))" </dev/null 2>/dev/null) || continue
  P=${P%$'\r'}
  [ -n "$P" ] && [ -x "$P" ] && exec "$P" "$@"
  exec $cand "$@"
done
[ -n "$SAY" ] && { echo "smartuse: Python 3 was not found (tried python3, python, py -3). Its guards, gates and status line are OFF. Install Python 3.9 or newer and restart Claude Code." >&2; exit 2; }
if [ -n "$GUARD" ]; then
  S=${CLAUDE_PLUGIN_OPTION_STRICT:-}; S=${S#"${S%%[![:space:]]*}"}; S=${S%"${S##*[![:space:]]}"}   # trimmed without a fork (bash 3.2 safe)
  case "$S" in ""|[Oo][Ff][Ff]|[Ff][Aa][Ll][Ss][Ee]|[Nn][Oo]|0) ;;
    *) echo "smartuse: Python 3 was not found (tried python3, python, py -3), so this call is blocked: Strict guards is on and its guard cannot run. Install Python 3.9 or newer and restart Claude Code, or switch Strict guards off in /plugin configure." >&2; exit 2;; esac
fi
exit 0
