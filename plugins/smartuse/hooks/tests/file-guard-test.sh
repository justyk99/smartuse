#!/usr/bin/env bash
H="$(cd "$(dirname "$0")/.." && pwd)"; fail=0
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
chk() { # $1 = deny|allow, $2 = event JSON, $3 = label, $4 = code page the guard's stdin is decoded in (optional; cp1252 = Windows ANSI)
  out=$(printf '%s' "$2" | env ${4:+PYTHONIOENCODING=$4} bash "$H/py.sh" "$H/file-guard.py"); if [ "$1" = deny ]; then [ -n "$out" ] && echo "PASS deny $3" || { echo "FAIL expected deny $3"; fail=1; }; else [ -z "$out" ] && echo "PASS allow $3" || { echo "FAIL expected allow $3"; fail=1; }; fi; }
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude/smartuse.local.md","content":"x"}}' "Write adapter"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/trusted-checks.json"}}' "Edit pin file"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude/SmartUse.Local.MD","content":"x"}}' "Write adapter in mixed case (APFS and NTFS are case-insensitive)"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/x/../trusted-checks.json"}}' "Edit pin file through x/.."
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"C:\\Users\\u\\.claude\\smartuse\\trusted-checks.json"}}' "Edit pin file with backslashes"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:/Users/李雷/proj/.claude/smartuse.local.md","content":"x"}}' "Write adapter under a non-ASCII path, stdin in cp1252 (Windows ANSI; 0x9D of 李 is undefined there)" cp1252
chk deny  '{"tool_name":"MultiEdit","tool_input":{"file_path":"/etc/smartuse/trusted-checks.json"}}' "MultiEdit the root-owned pin file"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/docs/features/x/DEV.md","content":"x"}}' "Write a doc"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/Docs/SmartUse/Notes.md","content":"x"}}' "Write a doc under a SmartUse/ folder"
chk allow '{"tool_name":"Bash","tool_input":{"command":"cat .claude/smartuse.local.md"}}' "not a write tool"
# --- the launcher's remembered interpreter name (~/.claude/smartuse/interpreter): human-only too, anchored to .claude/smartuse/ and the end
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/interpreter","content":"python"}}' "Write the launcher's interpreter file"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"C:\\Users\\u\\.claude\\smartuse\\Interpreter"}}' "Edit the interpreter file with backslashes and mixed case"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/x/../interpreter"}}' "Edit the interpreter file through x/.."
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/docs/smartuse/interpreter.md","content":"x"}}' "Write a doc named interpreter.md under a smartuse/ folder"
# Windows maps these spellings to the same file: a trailing dot or space is dropped, and ::$DATA is the file's own data stream
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude\\smartuse\\interpreter::$DATA","content":"python"}}' "Write the interpreter file as interpreter::\$DATA"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/interpreter.","content":"python"}}' "Write the interpreter file with a trailing dot"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/interpreter ","content":"python"}}' "Write the interpreter file with a trailing space"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude.\\smartuse \\interpreter","content":"python"}}' "Write the interpreter file through folder names with a trailing dot or space"
chk deny  '{"tool_name":"Edit","tool_input":{"file_path":"/home/u/.claude/smartuse/x/.. /interpreter"}}' "Edit the interpreter file through a '.. ' part (a part of only dots and spaces: fail closed)"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/.. /../interpreter","content":"python"}}' "Write the interpreter file through a POSIX folder named '.. ' (a name there, so the path as written is the file)"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude\\smartuse\\q\\... \\interpreter","content":"python"}}' "Write under smartuse through a part of only dots and spaces ('... ' may be read as a name, . or ..: fail closed)"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/docs/.../notes.md","content":"x"}}' "Write a path with a '...' part that names no smartuse file"
case "$OSTYPE" in   # the path the OS resolves is matched too (links here; Windows short 8.3 names the same way)
  msys*|cygwin*) echo "PASS (skipped on Windows: no symlinks)"; echo "PASS (skipped on Windows: no symlinks; a leading //)";;
  *) T=$(mktemp -d); mkdir -p "$T/h/.claude/smartuse"; : > "$T/h/.claude/smartuse/interpreter"; ln -s "$T/h/.claude/smartuse" "$T/lnk"
     chk deny "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$T/lnk/interpreter\",\"content\":\"python\"}}" "Write the interpreter file through a symlinked folder (the resolved path is matched)"
     chk deny "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/$T/lnk/interpreter\",\"content\":\"python\"}}" "the same with a leading // (a local path on POSIX: resolved too)"; rm -rf "$T";;
esac
# a share that does not answer (192.0.2.7 is a documentation address) must not hold the guard past the hook's 10 s timeout: the text
# forms decide first, and resolving the path gives up after 3 s (then the path cannot be checked: denied with its own reason)
t0=$(date +%s); out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"//192.0.2.7/share/proj/.claude/smartuse.local.md","content":"x"}}' | bash "$H/py.sh" "$H/file-guard.py"); t1=$(date +%s)
[ -n "$out" ] && [ $((t1 - t0)) -lt 10 ] && echo "PASS deny Write the adapter on a network share that does not answer, in $((t1 - t0)) s (the text match decides; no network call)" || { echo "FAIL network share: $((t1 - t0)) s, output '${out:0:40}'"; fail=1; }
t0=$(date +%s); out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"//192.0.2.7/share/proj/notes.md","content":"x"}}' | bash "$H/py.sh" "$H/file-guard.py"); t1=$(date +%s)
case "$out" in ""|*"could not be resolved"*) ok=1;; *) ok=0;; esac   # allowed (resolved, or refused at once) or not checkable; never human-only
[ $ok = 1 ] && [ $((t1 - t0)) -lt 10 ] && echo "PASS an ordinary file on a network share that does not answer is decided in $((t1 - t0)) s: $([ -z "$out" ] && echo allowed || echo 'denied as not checkable')" || { echo "FAIL network share, ordinary file: $((t1 - t0)) s, output '${out:0:60}'"; fail=1; }
# --- 0.6.1 F5b: the switch is human-only. An edit of a Claude Code settings file (settings.json / settings.local.json in a .claude folder, or
# in the folder CLAUDE_CONFIG_DIR names) is compared before and after on three values: this plugin's pluginConfigs entry (its options), its
# enabledPlugins entry, and disableAllHooks. Any difference is denied; other edits pass. A result that cannot be parsed (or a file over 1 MB)
# is denied when the edit names one of the three, allowed when it names none. Key names: code.claude.com/docs/en/settings-reference.
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it (JSON strings are not converted by Git Bash)
swj() { # $1 tool, $2 file_path, then Write: content · Edit: old new · MultiEdit: old1 new1 old2 new2 ... -> the PreToolUse event JSON
  py -c "
import json,sys
a=sys.argv[1:]; t,p=a[0],a[1]; r=a[2:]
if t=='Write': ti={'file_path':p,'content':r[0]}
elif t=='Edit': ti={'file_path':p,'old_string':r[0],'new_string':r[1]}
else: ti={'file_path':p,'edits':[{'old_string':r[i],'new_string':r[i+1]} for i in range(0,len(r),2)]}
sys.stdout.write(json.dumps({'tool_name':t,'tool_input':ti}))" "$@"
}
chke() { # like chk, with one environment variable: $1 VAR=value, $2 deny|allow, $3 event JSON, $4 label
  out=$(printf '%s' "$3" | env "$1" bash "$H/py.sh" "$H/file-guard.py"); if [ "$2" = deny ]; then [ -n "$out" ] && echo "PASS deny $4" || { echo "FAIL expected deny $4"; fail=1; }; else [ -z "$out" ] && echo "PASS allow $4" || { echo "FAIL expected allow $4"; fail=1; }; fi; }
T5=$(mktemp -d); mkdir -p "$T5/proj/.claude" "$T5/cfg" "$T5/docs"
BASE='{"permissions":{"allow":["Bash(ls)"]},"enabledPlugins":{"smartuse@smartuse":true,"other@m":true},"pluginConfigs":{"smartuse@smartuse":{"options":{"strict":true,"rules_off":"force-push"}}}}'
printf '%s' "$BASE" > "$T5/proj/.claude/settings.json"; printf '%s' "$BASE" > "$T5/cfg/settings.json"; printf '%s' "$BASE" > "$T5/docs/settings.json"
SP=$(wp "$T5/proj/.claude/settings.json"); SL=$(wp "$T5/proj/.claude/settings.local.json"); CP=$(wp "$T5/cfg/settings.json"); DP=$(wp "$T5/docs/settings.json"); CD=$(wp "$T5/cfg")
chk deny  "$(swj Write "$SP" '{"permissions":{"allow":["Bash(ls)"]},"enabledPlugins":{"smartuse@smartuse":true,"other@m":true},"pluginConfigs":{"smartuse@smartuse":{"options":{"strict":true,"rules_off":""}}}}')" "F5b Write: Rules off emptied"
chk deny  "$(swj Write "$SP" '{"permissions":{"allow":["Bash(ls)"]},"enabledPlugins":{"smartuse@smartuse":true,"other@m":true},"pluginConfigs":{"smartuse@smartuse":{"options":{"strict":false,"rules_off":"force-push"}}}}')" "F5b Write: Strict switched off"
chk deny  "$(swj Write "$SP" '{"enabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: the plugin's on/off entry set to false"
chk deny  "$(swj Write "$SP" '{"permissions":{"allow":["Bash(ls)"]},"enabledPlugins":{"other@m":true},"pluginConfigs":{"smartuse@smartuse":{"options":{"strict":true,"rules_off":"force-push"}}}}')" "F5b Write: the plugin's on/off entry removed (absent = default)"
chk deny  "$(swj Write "$SP" '{"disableAllHooks":true}')" "F5b Write: disableAllHooks"
chk deny  "$(swj Edit "$SP" '"strict":true' '"strict":false')" "F5b Edit: Strict true -> false"
chk deny  "$(swj Edit "$SP" '"smartuse@smartuse":true' '"smartuse@smartuse":false')" "F5b Edit: the on/off entry true -> false"
chk deny  "$(swj Edit "$SP" '"permissions"' '"disableAllHooks":true,"permissions"')" "F5b Edit: adds disableAllHooks"
chk deny  "$(swj Edit "$SP" '"rules_off":"force-push"' '"rules_off":"force-push,sudo"')" "F5b Edit: Rules off gains a name"
chk deny  "$(swj MultiEdit "$SP" '"other@m":true' '"other@m":false' '"strict":true' '"strict":false')" "F5b MultiEdit: the second edit switches Strict off"
chk deny  "$(swj Write "$SL" '{"enabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: a settings.local.json that turns the plugin off (first write of the file)"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\proj\\.claude\\settings.json","content":"{\"enabledPlugins\":{\"smartuse@smartuse\":false}}"}}' "F5b Write: backslash spelling of a settings file"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/repo/.CLAUDE/Settings.JSON","content":"{\"disableAllHooks\":true}"}}' "F5b Write: mixed case spelling"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude./settings.json ","content":"{\"disableAllHooks\":true}"}}' "F5b Write: trailing dot and space as Windows drops them"
chk deny  '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude\\settings.json::$DATA","content":"{\"disableAllHooks\":true}"}}' "F5b Write: settings.json::\$DATA"
chk deny  "$(swj Write "$SP" '{"enabledPlugins":{"smartuse@smartuse":false},}')" "F5b Write: a result that does not parse and names enabledPlugins"
chk deny  "$(swj Write "$SP" '{"\u0065nabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: a key spelled with a JSON escape (parsed, compared)"
chk deny  "$(swj Write "$SP" '{"\u0065nabledPlugins": ,}')" "F5b Write: an unparsable result with a JSON escape (fail closed)"
chk deny  "$(swj Edit "$SP" '"nothing-like-this"' '"disableAllHooks":true')" "F5b Edit: old_string not found but new_string names a switch (fail closed)"
chk allow "$(swj Write "$SP" '{"permissions":{"allow":["Bash(ls)"]},"enabledPlugins":{"smartuse@smartuse":true,"other@m":true},"pluginConfigs":{"smartuse@smartuse":{"options":{"strict":true,"rules_off":"force-push"}}},"statusLine":{"type":"command","command":"x"}}')" "F5b Write: a status line added, the three values unchanged"
chk allow "$(swj Write "$SP" "$BASE")" "F5b Write: a rewrite that changes nothing"
chk allow "$(swj Edit "$SP" '"permissions"' '"statusLine":{"type":"command","command":"x"},"permissions"')" "F5b Edit: adds a status line"
chk allow "$(swj Edit "$SP" '"other@m":true' '"other@m":false')" "F5b Edit: another plugin switched off"
chk allow "$(swj MultiEdit "$SP" '"other@m":true' '"other@m":false' '"Bash(ls)"' '"Bash(ls)","Bash(pwd)"')" "F5b MultiEdit: edits that touch none of the three"
chk allow "$(swj Write "$SL" '{"model":"x"}')" "F5b Write: a first settings.local.json without the plugin"
chk allow "$(swj Write "$SL" '{ this is not json }')" "F5b Write: an unparsable result that names none of the three, over a file that holds none"
chk deny  "$(swj Write "$SP" '{ this is not json }')" "F5b Write: an unparsable result over a file that holds the switches (they would be lost)"
chk allow "$(swj Edit "$SL" '"nothing-like-this"' '"model":"x"')" "F5b Edit: old_string not found, nothing named, in a settings file that holds none of the three"
chk deny  "$(swj Edit "$SP" '"nothing-like-this"' '"model":"x"')" "F5b Edit: old_string not found in a settings file that holds the switches (the result cannot be shown to keep them)"
# Claude Code's Edit may still match an old_string after folding typographic quotes to ASCII: the guard folds too, so the comparison runs
chk deny  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SP\",\"old_string\":\"\\u201cstrict\\u201d:true\",\"new_string\":\"\\u201cstrict\\u201d:false\"}}" "F5b Edit: typographic quotes in old_string and new_string flip Strict (folded, compared)"
chk deny  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SP\",\"old_string\":\"\\u201crules_off\\u201d:\\u201cforce-push\\u201d\",\"new_string\":\"\\u201crules_off\\u201d:\\u201c\\u201d\"}}" "F5b Edit: typographic quotes, the Rules off value emptied"
chk deny  "{\"tool_name\":\"MultiEdit\",\"tool_input\":{\"file_path\":\"$SP\",\"edits\":[{\"old_string\":\"\\u201cother@m\\u201d:true\",\"new_string\":\"\\u201cother@m\\u201d:false\"},{\"old_string\":\"\\u201cstrict\\u201d:true\",\"new_string\":\"\\u201cstrict\\u201d:false\"}]}}" "F5b MultiEdit: typographic quotes, the second edit flips Strict"
chk deny  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SP\",\"old_string\":\"\\u201cother@m\\u201d:true\",\"new_string\":\"\\u201cother@m\\u201d:false\"}}" "F5b Edit: a match only after folding typographic quotes, on a file that holds the switches, leaving them as they are (no result is predicted: the accepted cost)"
mkdir -p "$T5/p2/.claude"; printf '%s' '{"model":"x"}' > "$T5/p2/.claude/settings.json"; P2=$(wp "$T5/p2/.claude/settings.json")
chk allow "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P2\",\"old_string\":\"\\u201cmodel\\u201d:\\u201cx\\u201d\",\"new_string\":\"\\u201cmodel\\u201d:\\u201cy\\u201d\"}}" "F5b Edit: a folded-only match on a settings file that holds no switches, the strings name none"
chk deny  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P2\",\"old_string\":\"\\u201cmodel\\u201d:\\u201cx\\u201d\",\"new_string\":\"\\u201cdisableAllHooks\\u201d:true\"}}" "F5b Edit: a folded-only match on a file that holds none, but new_string names a switch"
chk allow "$(swj Write "$DP" '{"enabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: a settings.json outside any .claude folder"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude/settings.json.bak","content":"{\"disableAllHooks\":true}"}}' "F5b Write: settings.json.bak is not a settings file"
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/repo/.claude/notes/settings.json","content":"{\"disableAllHooks\":true}"}}' "F5b Write: .claude/notes/settings.json is not a settings file"
chke "CLAUDE_CONFIG_DIR=$CD" deny "$(swj Write "$CP" '{"enabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: settings.json in the folder CLAUDE_CONFIG_DIR names"
chke "CLAUDE_CONFIG_DIR=$CD" allow "$(swj Edit "$CP" '"other@m":true' '"other@m":false')" "F5b Edit: that file, another plugin switched off"
chke "SMARTUSE_NO_SUCH=1" allow "$(swj Write "$CP" '{"enabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: the same file with CLAUDE_CONFIG_DIR not set is just another settings.json"
# a file over 1 MB cannot be compared: denied when the edit names a switch, allowed when it names none
BIG="$T5/big/.claude"; mkdir -p "$BIG"; { printf '{}'; head -c 1100000 /dev/zero | tr '\0' ' '; } > "$BIG/settings.json"; BP=$(wp "$BIG/settings.json")
chk deny  "$(swj Edit "$BP" '{}' '{"disableAllHooks":true}')" "F5b Edit: a settings file over 1 MB and the edit names a switch"
chk allow "$(swj Edit "$BP" '{}' '{"model":"x"}')" "F5b Edit: a settings file over 1 MB and the edit names none"
# --- review 11 (M2a): the `env` block of a settings file can set CLAUDE_PLUGIN_OPTION_* (the variables the guards read as the plugin's options),
#     so every env entry with that prefix (any case) is compared too: adding, changing or removing one is the owner's action. Other entries pass.
mkdir -p "$T5/p3/.claude"; ENVB='{"model":"x","env":{"CLAUDE_PLUGIN_OPTION_STRICT":"true","FOO":"1"}}'; printf '%s' "$ENVB" > "$T5/p3/.claude/settings.json"; P3=$(wp "$T5/p3/.claude/settings.json")
chk deny  "$(swj Write "$P2" '{"model":"x","env":{"CLAUDE_PLUGIN_OPTION_STRICT":"false"}}')" "M2a Write: adds a CLAUDE_PLUGIN_OPTION_ env entry to a file that holds none"
chk deny  "$(swj Edit "$P2" '"model":"x"' '"env":{"claude_plugin_option_rules_off":"sudo"}')" "M2a Edit: adds one spelled in lower case"
chk deny  "$(swj Edit "$P3" '"CLAUDE_PLUGIN_OPTION_STRICT":"true"' '"CLAUDE_PLUGIN_OPTION_STRICT":"false"')" "M2a Edit: changes the value of an existing entry"
chk deny  "$(swj Write "$P3" '{"model":"x","env":{"FOO":"1"}}')" "M2a Write: removes the entry"
chk deny  "$(swj Write "$P2" '{ not json, CLAUDE_PLUGIN_OPTION_STRICT }')" "M2a Write: an unparsable result that names a CLAUDE_PLUGIN_OPTION_ variable"
chk allow "$(swj Write "$P2" '{"model":"x","env":{"FOO":"2"}}')" "M2a Write: adds an env entry with another name"
chk allow "$(swj Edit "$P3" '"FOO":"1"' '"FOO":"2"')" "M2a Edit: changes another env entry, the CLAUDE_PLUGIN_OPTION_ one stays"
chk allow "$(swj Write "$P3" "$ENVB")" "M2a Write: a rewrite that changes nothing"
chk allow "$(swj Write "$P2" '{"model":"x","env":{"MY_CLAUDE_PLUGIN_OPTION_X":"1"}}')" "M2a Write: a name that only contains the prefix"
# decided within a second inside the process: a 30 KB settings file of 1,500 env entries, one of them a CLAUDE_PLUGIN_OPTION_ variable
r=$(py - "$H/file-guard.py" "$P2" <<'PY'
import contextlib, io, json, sys, time, types
src = open(sys.argv[1], encoding="utf-8").read()
env = {"VAR_%d" % i: "value-%d" % i for i in range(1500)}
env["CLAUDE_PLUGIN_OPTION_RULES_OFF"] = "sudo"
ev = {"tool_name": "Write", "tool_input": {"file_path": sys.argv[2], "content": json.dumps({"model": "x", "env": env})}}
sys.stdin = types.SimpleNamespace(buffer=io.BytesIO(json.dumps(ev).encode()))
out = io.StringIO()
t0 = time.monotonic()
with contextlib.redirect_stdout(out):
    exec(compile(src, "file-guard", "exec"), {"__name__": "timing"})
dt = time.monotonic() - t0
print(("ok %.2f" % dt) if "smartuse's switches" in out.getvalue() and dt < 1.0 and len(ev["tool_input"]["content"]) > 30000 else "bad %.2f %s" % (dt, out.getvalue()[-90:]))
PY
)
case "$r" in ok*) echo "PASS deny a 30 KB settings file of 1,500 env entries is judged in ${r#ok } s inside the process (limit 1 s)";; *) echo "FAIL env timing -> '${r:0:120}'"; fail=1;; esac
# CLAUDE_CONFIG_DIR on a case-insensitive file system (Windows, macOS): the same folder in another case is the same folder. On Linux it is not.
CDU=$(py -c "import sys; print(sys.argv[1].upper())" "$CD"); CPU=$(py -c "import sys; print(sys.argv[1].upper())" "$CP")
case "$OSTYPE" in
  msys*|cygwin*|darwin*) chke "CLAUDE_CONFIG_DIR=$CDU" deny "$(swj Write "$CP" '{"enabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: CLAUDE_CONFIG_DIR spelled in upper case (a case-insensitive system)"
                         chke "CLAUDE_CONFIG_DIR=$CD" deny "$(swj Write "$CPU" '{"enabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: the file path spelled in upper case (a case-insensitive system)";;
  *) chke "CLAUDE_CONFIG_DIR=$CDU" allow "$(swj Write "$CP" '{"enabledPlugins":{"smartuse@smartuse":false}}')" "F5b Write: another case of the config folder is another folder on Linux";;
esac
# the same rule where this machine cannot show it: the guard's functions with a macOS-like platform (posix paths, sys.platform darwin), and Linux
CI5=$(py - "$H/file-guard.py" <<'PY'
import os, posixpath, sys
src = open(sys.argv[1], encoding="utf-8").read().rsplit("\nmain()", 1)[0]
g = {"__name__": "fg"}
exec(compile(src, "file-guard", "exec"), g)
os.environ["CLAUDE_CONFIG_DIR"] = "/Users/x/Cfg"
os.path, os.name = posixpath, "posix"
res = []
for plat in ("darwin", "linux"):
    sys.platform = plat
    res.append(str(bool(g["is_settings_file"]("/users/x/cfg/settings.json"))))
print(" ".join(res))
PY
)
[ "$CI5" = "True False" ] && echo "PASS F5b the config folder is compared case-insensitively on macOS-like systems and exactly on Linux ($CI5)" || { echo "FAIL F5b case-insensitive folder compare: darwin/linux gave '$CI5', expected 'True False'"; fail=1; }
case "$OSTYPE" in   # a link to the folder: the resolved path is the settings file
  msys*|cygwin*) echo "PASS (skipped on Windows: no symlinks)";;
  *) ln -s "$T5/proj/.claude" "$T5/lnk"; chk deny "$(swj Write "$T5/lnk/settings.json" '{"disableAllHooks":true}')" "F5b Write: settings.json through a symlinked .claude folder"
     ln -s "$T5/proj/.claude/settings.json" "$T5/docs/linked.json"; chk deny "$(swj Write "$T5/docs/linked.json" '{"disableAllHooks":true}')" "F5b Write: a link whose target is a settings file";;
esac
rm -rf "$T5"
# --- 0.6.1 F6: strict fails closed on an unexpected error. tool_input as a string makes the guard raise: strict (an option text that is not
# empty / off / false / no / 0) -> a deny with its own reason; light (the default) -> nothing printed, as before.
ERR='{"tool_name":"Write","tool_input":"not an object"}'
out=$(printf '%s' "$ERR" | env CLAUDE_PLUGIN_OPTION_STRICT=true bash "$H/py.sh" "$H/file-guard.py" 2>/dev/null)
case "$out" in *'"permissionDecision": "deny"'*"internal error; strict guards fail closed"*) echo "PASS F6 strict: an unexpected error denies, with its own reason";; *) echo "FAIL F6 strict error path: '${out:0:200}'"; fail=1;; esac
out=$(printf '%s' "$ERR" | env CLAUDE_PLUGIN_OPTION_STRICT=maybe bash "$H/py.sh" "$H/file-guard.py" 2>/dev/null)
case "$out" in *'"permissionDecision": "deny"'*) echo "PASS F6 a Strict text that is neither on nor off counts as strict: the error denies";; *) echo "FAIL F6 unreadable strict error path: '${out:0:200}'"; fail=1;; esac
for SV in off ""; do
  out=$(printf '%s' "$ERR" | env CLAUDE_PLUGIN_OPTION_STRICT="$SV" bash "$H/py.sh" "$H/file-guard.py" 2>/dev/null)
  [ -z "$out" ] && echo "PASS F6 light (Strict '$SV'): the same error prints nothing, as in 0.6.0" || { echo "FAIL F6 light error path ('$SV'): '${out:0:200}'"; fail=1; }
done
out=$(printf '%s' "$ERR" | env -u CLAUDE_PLUGIN_OPTION_STRICT bash "$H/py.sh" "$H/file-guard.py" 2>/dev/null)
[ -z "$out" ] && echo "PASS F6 light (no option at all): the same error prints nothing" || { echo "FAIL F6 light error path (unset): '${out:0:200}'"; fail=1; }
out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/repo/docs/x.md","content":"x"}}' | env CLAUDE_PLUGIN_OPTION_STRICT=true bash "$H/py.sh" "$H/file-guard.py" 2>/dev/null)
[ -z "$out" ] && echo "PASS F6 strict: an ordinary write is still allowed, nothing printed" || { echo "FAIL F6 strict ordinary write: '${out:0:200}'"; fail=1; }
# --- 0.6.1 F7: the doctor's canary. A write to ~/.claude/smartuse/doctor-canary is denied with a reason that says the guard is live and the level;
# a sibling file is not (the same folder is otherwise open: only the adapter, the pins and the launcher's file are human-only).
out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/doctor-canary","content":"canary"}}' | env -u CLAUDE_PLUGIN_OPTION_STRICT bash "$H/py.sh" "$H/file-guard.py")
case "$out" in *'"permissionDecision": "deny"'*"file-guard: doctor canary"*"the guard is live"*"light"*) echo "PASS F7 the canary file is denied: doctor canary, the guard is live, the level (light)";; *) echo "FAIL F7 canary deny: '${out:0:200}'"; fail=1;; esac
chk allow '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.claude/smartuse/doctor-canary2","content":"x"}}' "F7 a sibling of the canary file (doctor-canary2) is not the canary"
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
