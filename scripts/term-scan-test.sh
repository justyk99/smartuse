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
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
