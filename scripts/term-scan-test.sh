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
# F1 (0.7.2): the scan reads every line whole. Invented terms only; every repo is a temp dir with its own private list.
W=$(mktemp -d); trap 'rm -rf "$T" "$U" "$W"' EXIT
scan2() { bash "$H/plugins/smartuse/hooks/py.sh" "$H/scripts/term-scan.py" --repo "$1" "${@:2}" 2>&1; }
sect() { printf '%s\n' "$1" | awk -v n="$2" '/^## /{s=($2==n)} s'; } # the lines of one "## <pattern>" block
gcm() { git -C "$1" -c user.name=yk -c user.email=yk@example.com -c commit.gpgsign=false commit -q "${@:2}"; }
mkr() { mkdir "$W/$1"; git -C "$W/$1" init -q; } # $1 = a short name; the repo is $W/$1
okc() { case "$2" in ""|*[!1]*) echo "FAIL $1: ${3:0:240}"; fail=1;; *) echo "PASS $1";; esac; } # $2 = one 1 per check; any 0 fails
has() { case "$1" in *"$2"*) echo 1;; *) echo 0;; esac; }
lacks() { case "$1" in *"$2"*) echo 0;; *) echo 1;; esac; }
ex1() { [ "$got" = 1 ] && echo 1 || echo 0; } # the scan's exit was 1, a hit
mkr r1; printf 'mail bob@corp-x.io zebrafish\n' > "$W/r1/mail.txt"; printf 'zebrafish\n' > "$W/r1/.smartuse-terms.local"
git -C "$W/r1" add mail.txt; gcm "$W/r1" -m 'add mail note'
out=$(scan2 "$W/r1" --history); got=$?
okc "r1 history: a private term on a line with an e-mail is a history@ private#1 hit" "$(ex1)$(has "$(sect "$out" private#1)" 'history@')" "exit $got; $out"
okc "r2 tree and history: the e-mail hit's excerpt never shows the term" "$(has "$out" "## email")$(lacks "$out" zebrafish)" "$out"
out=$(scan2 "$W/r1" --history --max-hits 1); got=$?
okc "r5 --max-hits 1 keeps the private hit, not the e-mail hit" "$(ex1)$(has "$(sect "$out" private#1)" 'mail.txt')" "exit $got; $out"
mkr r3; printf 'nothing here\n' > "$W/r3/plain.txt"; printf 'zebrafish\n' > "$W/r3/.smartuse-terms.local"
git -C "$W/r3" add plain.txt; gcm "$W/r3" -m 'notes on zebrafish handling'
out=$(scan2 "$W/r3" --history); got=$?
okc "r3 a private term in a commit subject is a history@ private#1 hit, never printed" "$(ex1)$(has "$(sect "$out" private#1)" 'history@')$(lacks "$out" zebrafish)" "exit $got; $out"
mkr r3b; printf 'nothing here\n' > "$W/r3b/plain.txt"; printf 'zebrafish\n' > "$W/r3b/.smartuse-terms.local"
git -C "$W/r3b" add plain.txt; gcm "$W/r3b" -m 'plain subject' -m 'the body mentions zebrafish too'
out=$(scan2 "$W/r3b" --history); got=$?
okc "r3b a private term in a commit body line is a history@ hit too" "$(ex1)$(has "$(sect "$out" private#1)" 'history@')$(lacks "$out" zebrafish)" "exit $got; $out"
mkr r4; printf 'z\303\251brafish\n' > "$W/r4/.smartuse-terms.local"; printf 'a line\nz\351brafish\n' > "$W/r4/cp.txt"
git -C "$W/r4" add cp.txt; gcm "$W/r4" -m 'add cp1252 note'
out=$(scan2 "$W/r4" --history); got=$?
sec=$(sect "$out" private#1)
okc "r4 a term saved as cp1252: a tree hit, a history hit, the not-UTF-8 clause, never printed" "$(ex1)$(has "$sec" 'cp.txt:2')$(has "$sec" 'history@')$(has "$out" 'lines not UTF-8')$(lacks "$out" brafish)" "exit $got; $out"
mkr r6; printf 'zebrafish\n' > "$W/r6/.smartuse-terms.local"; printf '\377\376z\000e\000b\000r\000a\000f\000i\000s\000h\000\n\000' > "$W/r6/u16.txt"
git -C "$W/r6" add u16.txt; gcm "$W/r6" -m 'add utf-16 note'
out=$(scan2 "$W/r6" --history); got=$?
okc "r6 a UTF-16LE file: a tree hit, a history hit (git log --text reads it), no binary diff left unread, never printed" "$(ex1)$(has "$(sect "$out" private#1)" 'u16.txt:')$(has "$(sect "$out" private#1)" 'history@')$(lacks "$out" 'binary diffs not read')$(lacks "$out" zebrafish)" "exit $got; $out"
mkr r7; printf 'zebrafish\n' > "$W/r7/.smartuse-terms.local"; printf 'hello\n' > "$W/r7/zebrafish-notes.txt"
git -C "$W/r7" add zebrafish-notes.txt; gcm "$W/r7" -m 'add notes'
out=$(scan2 "$W/r7" --history); got=$?
okc "r7 a file name holding the term is a private#1 hit (tree and history), the name is starred" "$(ex1)$(has "$(sect "$out" private#1)" 'history@')$(lacks "$out" zebrafish)" "exit $got; $out"
# 0.7.2 review fix round A (D10-D12). Same temp-repo style.
mkr r8; printf 'z\303\251brafish\n' > "$W/r8/.smartuse-terms.local"; printf 'mail bob@corp-x.io z\351brafish\n' > "$W/r8/cp.txt"
git -C "$W/r8" add cp.txt; gcm "$W/r8" -m 'add cp1252 mail note'
out=$(scan2 "$W/r8" --history); got=$?
okc "r8 D10 a cp1252 term on an e-mail line: the private hit is found, no excerpt shows the term in any reading" "$(ex1)$(has "$(sect "$out" private#1)" 'cp.txt:1')$(has "$out" '## email')$(lacks "$out" brafish)" "exit $got; $out"
mkr r8b; printf 'z\303\251brafish\n' > "$W/r8b/.smartuse-terms.local"; printf 'caf\351\222s r\351sum\351 na\357ve mail a.b@foo.org z\351brafish\n' > "$W/r8b/notes.txt"
git -C "$W/r8b" add notes.txt; gcm "$W/r8b" -m 'add a cp1252 note with several bad runs'
out=$(scan2 "$W/r8b" --history); got=$?
okc "r8b D10 a cp1252 line with a 2-byte bad run before the term: the offsets stay aligned, no excerpt shows the term" "$(ex1)$(has "$(sect "$out" private#1)" 'notes.txt:1')$(has "$out" '## email')$(lacks "$out" brafish)" "exit $got; $out"
mkr r9; printf 'zebrafish\n' > "$W/r9/.smartuse-terms.local"; printf 'bob@corp-x.io z\000e\000b\000r\000a\000f\000i\000s\000h\000\n' > "$W/r9/u16.txt"
git -C "$W/r9" add u16.txt; gcm "$W/r9" -m 'add utf-16 mail note'
out=$(scan2 "$W/r9" --history); got=$?
okc "r9 D10 a UTF-16LE term on an e-mail line: the private hit is found, the e-mail excerpt stars it" "$(ex1)$(has "$(sect "$out" private#1)" 'u16.txt:1')$(has "$out" '## email')$(lacks "$out" zebrafish)" "exit $got; $out"
mkr r10; printf 'zebrafish\n' > "$W/r10/.smartuse-terms.local"; printf '\377\376z\000e\000b\000r\000a\000f\000i\000s\000h\000\n\000' > "$W/r10/old.txt"
git -C "$W/r10" add old.txt; gcm "$W/r10" -m 'add utf-16 note'; git -C "$W/r10" rm -q old.txt; gcm "$W/r10" -m 'remove it'
out=$(scan2 "$W/r10" --history); got=$?
okc "r10 D11 a UTF-16 file added then removed: history reports a private hit (git log --text), never printed" "$(ex1)$(has "$(sect "$out" private#1)" 'history@')$(lacks "$out" zebrafish)" "exit $got; $out"
mkr r11; printf 'zebrafish\n' > "$W/r11/.smartuse-terms.local"; printf 'mail bob@corp-x.io\nmail amy@corp-y.io\n' > "$W/r11/a.txt"; printf 'the term zebrafish\n' > "$W/r11/z.txt"
git -C "$W/r11" add a.txt z.txt; gcm "$W/r11" -m 'add notes'
out=$(scan2 "$W/r11" --max-hits 2); got=$?
okc "r11 D12 --max-hits caps generic rows only: a later private hit is kept, the summary says the cap was reached" "$(ex1)$(has "$(sect "$out" private#1)" 'z.txt')$(has "$out" '(1 private)')$(has "$out" 'cap reached at 2')$(lacks "$out" zebrafish)" "exit $got; $out"
out=$(scan2 "$W/r11"); case "$out" in *"cap reached"*) echo "FAIL r11b no cap clause when the cap did not bite: $out"; fail=1;; *) echo "PASS r11b no cap clause when the cap is not reached";; esac
mkr r12; printf 'zebrafish\n' > "$W/r12/.smartuse-terms.local"; printf 'nothing here\n' > "$W/r12/plain.txt"
git -C "$W/r12" add plain.txt; git -C "$W/r12" -c user.name=zebrafish -c user.email=bob@corp-x.io -c commit.gpgsign=false commit -q -m 'plain subject'
out=$(scan2 "$W/r12" --history); got=$?
okc "r12 D12 an author name holding the term is a history@ private hit; the author's e-mail is no generic hit" "$(ex1)$(has "$(sect "$out" private#1)" 'history@')$(lacks "$out" '## email')$(lacks "$out" zebrafish)" "exit $got; $out"
mkr r13; printf 'zebrafish
' > "$W/r13/.smartuse-terms.local"; printf -- '-- zebrafish
' > "$W/r13/a.txt"; printf -- '++ zebrafish
' > "$W/r13/b.txt"
git -C "$W/r13" add a.txt b.txt; gcm "$W/r13" -m 'add two notes'; git -C "$W/r13" rm -q a.txt b.txt; gcm "$W/r13" -m 'remove them'
out=$(scan2 "$W/r13" --history); got=$?
n=$(sect "$out" private#1 | grep -c 'history@')
okc "r13 a patch line that looks like a file header (--- term, +++ term) inside a hunk is scanned: 4 history hits, not 2" "$(ex1)$([ "$n" = 4 ] && echo 1 || echo 0)$(lacks "$out" zebrafish)" "exit $got; n=$n; $out"
# 0.7.3 F3: the history reader frames git's output on newlines only. A bare carriage return (CR, octal 015) inside a file line or a
# commit message stays inside that line, so the text after it must not pass for one of git's own lines. Each repo turns core.autocrlf off,
# so the bytes git stores are the bytes written here.
mkc() { mkr "$1"; git -C "$W/$1" config core.autocrlf false; printf 'zebrafish\n' > "$W/$1/.smartuse-terms.local"; } # $1 = a short name
nh() { sect "$1" private#1 | grep -c 'history@'; } # how many history@ private#1 hits the output holds
mkc c1; printf 'x\015commit zebrafish and more\n' > "$W/c1/a.txt"
git -C "$W/c1" add a.txt; gcm "$W/c1" -m 'add a note'; git -C "$W/c1" rm -q a.txt; gcm "$W/c1" -m 'remove it'
out=$(scan2 "$W/c1" --history); got=$?
n=$(nh "$out")
okc "c1 F3 a term after a bare CR and the word commit, in a file since removed: history@ private#1 hits (added and removed line), never printed" "$(ex1)$([ "$n" = 2 ] && echo 1 || echo 0)$(lacks "$out" zebrafish)" "exit $got; n=$n; $out"
mkc c2; printf 'plain subject\n\nbody x\015commit zebrafish more\n' > "$W/c2msg.txt"
gcm "$W/c2" --allow-empty -F "$W/c2msg.txt"
out=$(scan2 "$W/c2" --history); got=$?
n=$(nh "$out")
okc "c2 F3 the same in a commit message body (git keeps a bare CR there): one history@ private#1 hit, never printed" "$(ex1)$([ "$n" = 1 ] && echo 1 || echo 0)$(lacks "$out" zebrafish)" "exit $got; n=$n; $out"
mkc c3; printf 'x\015diff --git a b\n++ zebrafish\n' > "$W/c3/a.txt"
git -C "$W/c3" add a.txt; gcm "$W/c3" -m 'add a note'
out=$(scan2 "$W/c3" --history); got=$?
n=$(nh "$out")
okc "c3 F3 a bare CR then diff --git inside a hunk does not turn header mode on: the added line '++ term' is a history@ hit" "$(ex1)$([ "$n" = 1 ] && echo 1 || echo 0)$(lacks "$out" zebrafish)" "exit $got; n=$n; $out"
mkc c4; printf 'x\015Binary files zebrafish differ\n' > "$W/c4/a.txt"
git -C "$W/c4" add a.txt; gcm "$W/c4" -m 'add a note'; git -C "$W/c4" rm -q a.txt; gcm "$W/c4" -m 'remove it'
out=$(scan2 "$W/c4" --history); got=$?
n=$(nh "$out")
okc "c4 F3 a bare CR then 'Binary files term differ' in a file since removed: history@ hits, and no binary diff counted" "$(ex1)$([ "$n" = 2 ] && echo 1 || echo 0)$(lacks "$out" 'binary diffs not read')$(lacks "$out" zebrafish)" "exit $got; n=$n; $out"
mkc c5; printf 'zebrafish\015\n' > "$W/c5/crlf.txt"
git -C "$W/c5" add crlf.txt; gcm "$W/c5" -m 'add a crlf note'
out=$(scan2 "$W/c5" --history); got=$?
n=$(nh "$out")
okc "c5 F3 pin: a CRLF file holding the term: the tree hit crlf.txt:1, one history@ hit, 2 hits in all" "$(ex1)$(has "$(sect "$out" private#1)" 'crlf.txt:1')$([ "$n" = 1 ] && echo 1 || echo 0)$(has "$out" '2 hits (2 private)')$(lacks "$out" zebrafish)" "exit $got; n=$n; $out"
mkc c6; printf 'a\015b\015zebrafish\n' > "$W/c6/cr.txt"
git -C "$W/c6" add cr.txt; gcm "$W/c6" -m 'add a cr-only note'
out=$(scan2 "$W/c6" --history); got=$?
okc "c6 F3 pin: a file with bare CRs only, the term in its third piece: the tree label keeps cr.txt:3, and history reports it" "$(ex1)$(has "$(sect "$out" private#1)" 'cr.txt:3')$(has "$(sect "$out" private#1)" 'history@')$(lacks "$out" zebrafish)" "exit $got; $out"
# 0.7.3 fix round A: the author / committer name lines are scanned in their carriage-return pieces too, as a file line is, so a private
# pattern anchored with ^ or $ next to a bare CR still matches; no raw CR is printed in an excerpt. Private patterns here are invented regexes.
mkc c7; printf 're:^zebrafish\nre:okapi$\n' > "$W/c7/.smartuse-terms.local"; printf 'nothing here\n' > "$W/c7/plain.txt"
git -C "$W/c7" add plain.txt
GIT_AUTHOR_NAME=$'okapi\ryk\rzebrafish' gcm "$W/c7" -m 'plain subject'
an=$(git -C "$W/c7" cat-file -p HEAD | grep '^author ' | head -c 40 | od -An -c | tr -d ' \n') # git keeps the CRs in the stored name
out=$(scan2 "$W/c7" --history); got=$?
n=$(nh "$out"); n2=$(sect "$out" private#2 | grep -c 'history@')
crs=$(printf '%s\n' "$out" | sed 's/\r$//' | grep -c "$(printf '\r')") # raw CRs left once a CRLF line end is dropped (Windows Python prints \r\n)
okc "c7 an author name 'okapi<CR>yk<CR>zebrafish' with the anchored private patterns ^term / term\$: one history@ hit each (2 in all), and no raw CR in the output" "$(ex1)$(has "$an" '\r')$([ "$n" = 1 ] && [ "$n2" = 1 ] && echo 1 || echo 0)$(has "$out" '2 hits (2 private)')$([ "$crs" = 0 ] && echo 1 || echo 0)$(lacks "$out" zebrafish)$(lacks "$out" okapi)" "exit $got; stored $an; n=$n n2=$n2 crs=$crs; $out"
mkc c8; printf 'x\015ident bob@corp-x.io\n' > "$W/c8/a.txt"
git -C "$W/c8" add a.txt; gcm "$W/c8" -m 'add a note'; git -C "$W/c8" rm -q a.txt; gcm "$W/c8" -m 'remove it'
out=$(scan2 "$W/c8" --history); got=$?
okc "c8 F3 pin: the text 'ident <e-mail>' after a bare CR in a file since removed is a file line, not an ident line: a history@ hit under ## email" "$(ex1)$(has "$(sect "$out" email)" 'history@')$(lacks "$out" zebrafish)" "exit $got; $out"
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
