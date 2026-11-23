#!/usr/bin/env bash
# term-scan must never call a tree clean when the private list was not there to check. Temp repo, invented terms.
H="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
git -C "$T" init -q; echo "a plain note about a zebrafish" > "$T/note.txt"; git -C "$T" add note.txt
scan() { bash "$H/plugins/smartuse/hooks/py.sh" "$H/scripts/term-scan.py" --repo "$T" "$@" 2>&1; }
chk() { # $1 = expected exit, $2 = text the output must hold, $3 = label, the rest = the scan's flags
  want=$1; text=$2; label=$3; shift 3
  out=$(scan "$@"); got=$?
  case "$out" in *"$text"*) has=1;; *) has=0;; esac
  if [ "$got" = "$want" ] && [ $has = 1 ]; then echo "PASS $label"; else echo "FAIL $label: exit $got, wanted $want; output '${out:0:160}'"; fail=1; fi; }
chk 2 "NOT checked" "no private list: the run is not clean"
chk 0 "(0 private)" "--no-private: a generic-only run says so and passes" --no-private
printf '# only a comment\n' > "$T/.smartuse-terms.local"
chk 2 "NOT checked" "a list with no terms counts as no list"
printf 'okapi\n' > "$T/.smartuse-terms.local"
chk 0 "(1 private)" "a list whose term is not in the tree: clean"
printf 'zebrafish\n' > "$T/.smartuse-terms.local"
chk 1 "private#1" "a term in the tree: a hit"
out=$(scan); case "$out" in *zebrafish*) echo "FAIL the term was printed"; fail=1;; *) echo "PASS the term is never printed";; esac
# F3: the maintainer types `python scripts/term-scan.py --history` with no launcher, so no UTF-8 mode. py.sh forces PYTHONUTF8=1 and hid this.
# Here the interpreter is found the way py.sh finds it (python3, python, py -3; the Store stub fails the probe) but called directly,
# PYTHONUTF8=0 and PYTHONIOENCODING unset, stdout to a pipe: on Windows that is the ANSI code page (cp1252). 中文 → Á holds bytes (0x81 in Á's UTF-8)
# that cp1252 cannot decode, and characters it cannot print. Linux defaults to UTF-8, so the case passes there and was red only on Windows.
PY=""; for cand in "python3" "python" "py -3"; do $cand -c "import sys" </dev/null >/dev/null 2>&1 && { PY=$cand; break; }; done
U=$(mktemp -d); trap 'rm -rf "$T" "$U"' EXIT
git -C "$U" init -q
printf 'line one\n\344\270\255\346\226\207 \342\206\222 \303\201 mail bob@corp-x.io\n' > "$U/utf8.txt"; git -C "$U" add utf8.txt
git -C "$U" -c user.name=yk -c user.email=yk@example.com -c commit.gpgsign=false commit -q -m 'add utf8 note'
out=$(env -u PYTHONIOENCODING PYTHONUTF8=0 $PY "$H/scripts/term-scan.py" --repo "$U" --history --no-private 2>&1); got=$?
case "$out" in *Traceback*) tb=1;; *) tb=0;; esac
case "$out" in *"term-scan: "*"tree + history"*" 2 hits"*) sum=1;; *) sum=0;; esac
if [ -n "$PY" ] && [ "$got" = 1 ] && [ $tb = 0 ] && [ $sum = 1 ]; then echo "PASS non-ASCII text with no UTF-8 mode and a piped stdout: summary line, no traceback, exit 1 (red half is Windows-only)"
else echo "FAIL non-ASCII text, no UTF-8 mode: python '$PY', exit $got, wanted 1; traceback $tb, summary $sum; output '${out:0:200}'"; fail=1; fi
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
