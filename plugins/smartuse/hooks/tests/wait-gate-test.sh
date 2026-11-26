#!/usr/bin/env bash
# Self-contained test for hooks/wait-gate.py — the Stop gate that blocks, once, a session that handed work to another session and
# ends its turn with nothing armed to wake it (docs/notes/one-session-design.md, M2). Every transcript is SYNTHETIC: records in the
# shapes Claude Code 2.1.308 writes (checked on real transcripts: assistant tool_use blocks, user tool_result blocks, the background
# Bash result text, queue-operation + user task notifications, TaskStop / SendMessage / send_message / send_later records, the
# fields that tell a genuine human prompt from an injected one) with made-up text, ids and sessions; no real path, name or message.
# Covered: the INCIDENT REPLAY (a watcher armed, stopped with TaskStop "to save tokens", then "Paste this into the builder: ... I'll ping
# you when it's done" -> BLOCK, the reason names the stopped watcher and the hand-off) · a watcher armed after the hand-off · a reply
# starting STOPPED: · no hand-off · the second Stop in a scope · SendMessage to a subagent / to another session · send_message (and a
# failed one) · a watcher that finished before the hand-off · send_later ahead / behind · a hand-off before the last human prompt ·
# missing / garbage transcripts and stdin · wait_gate: off · wait.json (watching / stopped / blocked, cleared) · every kind of watcher
# (Bash in the background or moved there at its timeout, Monitor, background Agent and Workflow, ScheduleWakeup, CronCreate,
# create_trigger, subscribe_pr_activity, watch_url) alive and ended · the hand-off answered by a notification or a message (the
# designed flow must not block itself) · which user records start a scope · the Stop input's own background_tasks / session_crons /
# last_assistant_message · the hand-off phrases, matched and not matched · the 6-line reason, its watch.py command (bash-guard allows
# it, the branch comes from .git/HEAD) · the block marker per prompt and per answer · a blocked hand-off that stands in wait.json until
# something answers it · a long reply (the STOPPED: search stays linear) · the state dir equal to ledger.py's · the hooks.json entry.
# One temp dir under ${TMPDIR:-/tmp}/smartuse-wait.XXXXXX, the only thing removed on exit; temp HOME. Every PASS / FAIL line is one
# check; exit 1 on failure.
set -u
H="$(cd "$(dirname "$0")/.." && pwd)"; GATE="$H/wait-gate.py"
D=$(mktemp -d "${TMPDIR:-/tmp}/smartuse-wait.XXXXXX") && [ -d "$D" ] || { echo "FAIL could not create a temp dir under ${TMPDIR:-/tmp}"; exit 1; }
trap 'case "$D" in */smartuse-wait.*) rm -rf "$D" 2>/dev/null;; esac' EXIT   # removes this run's own dir and nothing else
REAL_HOME="${HOME:-}"; export HOME="$D/home"; mkdir -p "$HOME/.claude/smartuse" "$D/proj" "$D/t"   # ~/.claude/smartuse exists, so py.sh remembers the interpreter: one start per call
export CLAUDE_PLUGIN_OPTION_STRICT=true; unset CLAUDE_PLUGIN_OPTION_WAIT_GATE   # 0.6.1 F6: the gate is on in strict (and with the wait_gate option), off in light, which is the default; every case below this line is the strict bar, the light block near the end sets the options itself
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
REAL=$(py -c "import sys; sys.stdout.write(sys.executable)")   # the interpreter the launcher found: the cp1252 case starts it directly, because the launcher's -I ignores PYTHONIOENCODING (0.7.5)
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, not inside JSON strings (cygpath -m -> C:/Users/...); elsewhere unchanged
key() { py -c "import re,sys,pathlib; print(re.sub(r'[^A-Za-z0-9._-]','-',str(pathlib.Path(sys.argv[1]).resolve())).lstrip('-'))" "$1"; }   # the hooks' state-dir rule: the full resolved path, every character outside [A-Za-z0-9._-] -> "-", no leading "-" (~/.claude/smartuse/projects/<key>/)
fail=0
ok() { echo "PASS $1"; }
ko() { echo "FAIL $1"; fail=1; }
skip() { echo "SKIP $1"; }   # a case that did not run on this machine: never a PASS, never sets fail
[ "$(py -c 'print("ok")' </dev/null 2>/dev/null)" = ok ] || { echo "FAIL no python 3 (python3, python or py -3) through $H/py.sh"; exit 1; }
PW=$(wp "$D/proj"); K=$(key "$PW"); P="$HOME/.claude/smartuse/projects/$K"; W="$P/wait.json"; M="$P/wait-block.json"   # the state dir of the project every case runs in; each case starts with it removed
PL=$(wp "$(cd "$H/.." && pwd -P)")   # the plugin dir as the hook spells it in the command it recommends: absolute, resolved, forward slashes

# --- the synthetic transcripts: mk.py writes every case to $D/t/<case>.jsonl (and the phrase table to $D/t/phrases.tsv) in one start
cat > "$D/mk.py" <<'PY'
import datetime, json, os, sys

OUT = sys.argv[1]
NOW = datetime.datetime.now(datetime.timezone.utc)
RC = "mcp__claude-code-remote__"
PASTE = "Paste this into the builder: build step 3 and push docs/STEP3-RESULT.md. I'll ping you when it's done."


def stamp(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (dt.microsecond // 1000)


def plain(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


class T(object):
    """One synthetic transcript: 11 s between records, the first 12 minutes ago, so a timer armed in it has a known time from now."""

    def __init__(self, step=11):
        self.recs, self.n, self.t, self.step = [], 0, NOW - datetime.timedelta(minutes=12), step

    def uid(self):
        self.n += 1
        return "00000000-0000-4000-8000-%012d" % self.n

    def rec(self, **r):
        self.t += datetime.timedelta(seconds=self.step)
        r.setdefault("uuid", self.uid())
        r.setdefault("timestamp", stamp(self.t))
        r.setdefault("sessionId", "sid-test")
        r.setdefault("isSidechain", False)
        self.recs.append(r)
        return r

    # ---- user side
    def human(self, text):
        return self.rec(type="user", userType="external", entrypoint="remote", turnOrigin="human", promptSource="sdk",
                        origin={"kind": "human"}, promptId=self.uid(), message={"role": "user", "content": text})

    def user(self, content, **kw):
        return self.rec(type="user", userType="external", entrypoint="remote", message={"role": "user", "content": content}, **kw)

    def meta(self, text):
        return self.user(text, isMeta=True)

    def peer(self, text):
        return self.user("Another Claude session sent a message: <agent-message from=\"builder\">" + text + "</agent-message>", isMeta=True,
                         turnOrigin="peer", promptSource="system", origin={"kind": "peer", "from": "builder", "name": "builder"})

    # ---- assistant side
    def say(self, text):
        self.n += 1
        return self.rec(type="assistant", requestId="req_TEST%04d" % self.n, message={"id": "msg_TEST%04d" % self.n, "type": "message", "role": "assistant",
                        "model": "test-model", "content": [{"type": "text", "text": text}], "stop_reason": "end_turn"})

    def use(self, name, inp, **kw):
        self.n += 1
        tid = "toolu_TEST%04d" % self.n
        self.rec(type="assistant", requestId="req_TEST%04d" % self.n, message={"id": "msg_TEST%04d" % self.n, "type": "message", "role": "assistant",
                 "model": "test-model", "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp, "caller": {"type": "direct"}}],
                 "stop_reason": "tool_use"}, **kw)
        return tid

    def result(self, tid, text, err=False, tur=None, **kw):
        b = {"type": "tool_result", "tool_use_id": tid, "content": text}
        if err:
            b["is_error"] = True
        return self.user([b], toolUseResult=tur if tur is not None else {"stdout": "", "stderr": ""}, sourceToolAssistantUUID=self.uid(), **kw)

    def task_id(self):
        self.n += 1
        return "b%08d" % self.n

    # ---- tools
    def bash_bg(self, cmd="watch.py --git origin main --path docs/STEP3-RESULT.md", auto=False, idless=False):
        bid = self.task_id()
        inp = {"command": cmd, "description": "test watcher"}
        if not auto:
            inp["run_in_background"] = True
        call = self.use("Bash", inp)
        if idless:
            txt = "The command was moved to the background. You will be notified when it completes."
        elif auto:
            txt = ("Command did not complete within its 120s timeout and was moved to the background (ID: %s). Output is being written to: "
                   "/tmp/test/%s.output. You will be notified when it completes." % (bid, bid))
        else:
            txt = "Command running in background with ID: %s. Output is being written to: /tmp/test/%s.output" % (bid, bid)
        self.result(call, txt, tur={"stdout": "", "stderr": "", "interrupted": False, "isImage": False, "noOutputExpected": False, "backgroundTaskId": bid})
        return call, bid

    def bash_fg(self):
        call = self.use("Bash", {"command": "ls", "description": "list"})
        self.result(call, "docs\nREADME", tur={"stdout": "docs\nREADME", "stderr": "", "interrupted": False})
        return call

    def taskstop(self, bid):
        call = self.use("TaskStop", {"task_id": bid})
        self.result(call, json.dumps({"message": "Successfully stopped task: %s (test watcher)" % bid, "task_id": bid, "task_type": "local_bash",
                                      "command": "test watcher"}), tur={"message": "Successfully stopped task: %s" % bid, "task_id": bid, "task_type": "local_bash"})

    def notify(self, task, call, status="completed", code=0, mode="turn", what="Background command \"test watcher\""):
        if status is None:   # a Monitor event: no <status>, no <tool-use-id>
            xml = "<task-notification>\n<task-id>%s</task-id>\n<summary>Monitor event: \"test log\"</summary>\n<event>line 1 of the log</event>\n</task-notification>" % task
        else:
            tail = "completed (exit code 0)" if status == "completed" else "failed with exit code %d" % code
            xml = ("<task-notification>\n<task-id>%s</task-id>\n<tool-use-id>%s</tool-use-id>\n<output-file>/tmp/test/%s.output</output-file>\n"
                   "<status>%s</status>\n<summary>%s %s</summary>\n</task-notification>" % (task, call, task, status, what, tail))
        if mode not in ("attachment", "bare"):
            self.rec(type="queue-operation", operation="enqueue", content=xml)
        if mode == "turn":
            self.rec(type="queue-operation", operation="dequeue")
            self.rec(type="user", userType="external", entrypoint="remote", turnOrigin="task_notification", promptSource="system", promptId=self.uid(),
                     origin={"kind": "task-notification", "producer": "session-task", "runId": "test-run"}, message={"role": "user", "content": xml})
        elif mode == "absorbed":   # the notification arrived while the model was mid-turn: an attachment, no user record
            self.rec(type="attachment", attachment={"type": "queued_command", "prompt": xml, "commandMode": "task-notification",
                                                    "origin": {"kind": "task-notification", "producer": "session-task"}})
            self.rec(type="queue-operation", operation="remove", reason="absorbed_mid_turn", content=xml)
        elif mode == "bare":       # an older version: the notification is a plain user string and carries no origin fields
            self.user(xml)
        elif mode == "attachment":   # only the attachment: no enqueue record
            self.rec(type="attachment", attachment={"type": "queued_command", "prompt": xml, "commandMode": "task-notification",
                                                    "origin": {"kind": "task-notification", "producer": "session-task"}})

    def send_message(self, to="session_TEST0001", text="Step 3: render the intro and push docs/STEP3-RESULT.md", err=False):
        call = self.use(RC + "send_message", {"session_id": to, "message": text, "priority": "now"})
        if err:
            self.result(call, "non-retryable (test_refusal): a message into that session is not allowed.", err=True, tur="Error: refused")
        else:
            self.result(call, "{\"status\":\"delivered\"}", tur="{\"status\":\"delivered\"}")
        return call

    def send_msg(self, to, kind, text="Please look at step 3", **extra):
        inp = {"to": to, "summary": "look at step 3", "message": text, "type": "message", "recipient": to, "recipient_kind": kind, "content": text[:50]}
        inp.update(extra)
        call = self.use("SendMessage", inp)
        self.result(call, "{\"success\":true,\"message\":\"Message sent\"}", tur={"success": True, "message": "Message sent"})
        return call

    def send_later(self, fire, has_result=True, delay=60):
        call = self.use(RC + "send_later", {"delay_minutes": delay, "message": "check the builder", "name": "check-in", "initiation": "own_followup"})
        txt = "{\"fire_at\":\"%s\",\"now\":\"%s\",\"trigger_id\":\"trig_TESTLATER%d\"}" % (plain(fire), plain(NOW), self.n)
        self.result(call, txt if has_result else "scheduled", tur=[{"type": "text", "text": txt}])
        return call

    def wakeup(self, delay, scheduled_for=None, stop=False):
        if stop:
            call = self.use("ScheduleWakeup", {"stop": True})
            self.result(call, "{\"stopped\":true}")
            return call
        call = self.use("ScheduleWakeup", {"delaySeconds": delay, "reason": "check the builder", "prompt": "check the builder", "noop": False})
        if scheduled_for is None:
            self.result(call, "scheduled")
        else:
            self.result(call, json.dumps({"scheduledFor": int(scheduled_for.timestamp() * 1000), "clampedDelaySeconds": delay, "wasClamped": False}))
        return call

    def monitor(self, timeout_ms=3600000, persistent=False, says=None):
        inp = {"command": "tail -f /tmp/test.log", "description": "watch the test log", "timeout_ms": timeout_ms}
        if persistent:
            inp["persistent"] = True
        call = self.use("Monitor", inp)
        mid = self.task_id()
        mins = says if says is not None else timeout_ms // 60000   # the expiry the result states: the harness caps timeout_ms at 30 minutes
        self.result(call, "Monitor started (task %s, expires in %dm unless the source ends first; you get one notice at expiry — re-arm if you still need the watch). You will be notified." % (mid, mins))
        return call, mid

    def agent_bg(self, flag=True, name=None):
        inp = {"description": "check the build", "prompt": "check it", "subagent_type": "general-purpose"}
        if flag:
            inp["run_in_background"] = True
        if name:
            inp["name"] = name
        call = self.use("Agent", inp)
        aid = "a%016d" % self.n
        self.result(call, "Async agent launched successfully. (This tool result is internal metadata.)\nagentId: %s (internal ID)\nThe agent is working in the background." % aid,
                    tur={"isAsync": True, "status": "async_launched", "agentId": aid, "description": "check the build"})
        return call, aid

    def agent_fg(self):
        call = self.use("Agent", {"description": "read a file", "prompt": "read it", "subagent_type": "general-purpose"})
        self.result(call, "[Subagent hand-back] The text below is the final report of a subagent.\nThe file is fine.")
        return call

    def workflow(self):
        call = self.use("Workflow", {"script": "// test"})
        wid = "w%08d" % self.n
        self.result(call, "Workflow launched in background. Task ID: %s Summary: a test workflow" % wid,
                    tur={"taskId": wid, "taskType": "local_workflow", "status": "launched", "workflowName": "test"})
        return call, wid

    def cron(self, recurring=True, next_fire=None):
        call = self.use("CronCreate", {"cron": "*/5 * * * *", "prompt": "check the builder", "recurring": recurring})
        cid = "cron-test-%d" % self.n
        d = {"id": cid, "humanSchedule": "every 5 minutes", "recurring": recurring, "durable": False}
        if next_fire is not None:
            d["nextFireAt"] = int(next_fire.timestamp() * 1000)
        self.result(call, json.dumps(d))
        return call, cid

    def cron_delete(self, cid):
        call = self.use("CronDelete", {"id": cid})
        self.result(call, "deleted")

    def trigger(self, once=None, noid=False):
        inp = {"name": "check the builder", "prompt": "check it", "initiation": "own_followup"}
        if once is None:
            inp["cron_expression"] = "0 * * * *"
        else:
            inp["run_once_at"] = plain(once)
        call = self.use(RC + "create_trigger", inp)
        tid = "trig_TEST%d" % self.n
        self.result(call, json.dumps({"status": "created"} if noid else {"status": "created", "trigger": {"id": tid, "name": "check the builder"}}))
        return call, tid

    def trigger_delete(self, tid):
        call = self.use(RC + "delete_trigger", {"trigger_id": tid})
        self.result(call, json.dumps({"trigger": {"id": tid}}))

    def subscribe(self, owner="acme", repo="widgets", n=7, taken=False):
        call = self.use(RC + "subscribe_pr_activity", {"owner": owner, "repo": repo, "pullNumber": n})
        self.result(call, ("Subscribed. A Claude agent is already watching the PR: the call succeeded but this session will not receive events." if taken
                           else "Subscribed to activity on %s/%s#%d." % (owner, repo, n)))

    def unsubscribe(self, owner="acme", repo="widgets", n=7):
        call = self.use(RC + "unsubscribe_pr_activity", {"owner": owner, "repo": repo, "pullNumber": n})
        self.result(call, "Unsubscribed.")

    def watch_url(self):
        call = self.use(RC + "watch_url", {})
        tid = "trig_TESTURL%d" % self.n
        self.result(call, json.dumps({"url": "https://hooks.example.test/in/abc", "trigger_id": tid, "sealed_secret": "x"}))
        return tid

    def unwatch_url(self, tid):
        call = self.use(RC + "unwatch_url", {"trigger_id": tid})
        self.result(call, "stopped")

    def write(self, name):
        with open(os.path.join(OUT, name + ".jsonl"), "w", encoding="utf-8") as fh:
            for r in self.recs:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")


CASES = {}


def case(f):
    CASES[f.__name__] = f
    return f


def start(first="Hand step 3 to the builder and tell me when it is done."):
    t = T()
    t.human(first)
    return t


# ---- the incident and the cases the task names
@case
def incident():          # a watcher armed, stopped "to save tokens", then the hand-off in the reply
    t = start()
    call, bid = t.bash_bg()
    t.say("The watcher is armed on the builder's branch.")
    t.taskstop(bid)
    t.say(PASTE)
    return t


@case
def armed_after():       # the hand-off, then the watcher
    t = start(); t.send_message(); t.bash_bg(); t.say("Handed step 3 over; a watcher is armed."); return t


@case
def armed_before_phrase():   # the hand-off is in the final reply, the watcher armed earlier in the turn is alive
    t = start(); t.bash_bg(); t.say(PASTE); return t


@case
def stopped_start():     # the watcher was stopped; the reply hands off but starts by saying so
    t = start(); call, bid = t.bash_bg(); t.taskstop(bid); t.say(PASTE.replace("Paste", "STOPPED: nothing will wake me; the owner must. Paste", 1)); return t


@case
def stopped_only():
    t = start(); t.say("STOPPED: nothing will wake me; the owner must paste the prompt into the builder."); return t


@case
def stopped_bold():
    t = start(); t.say("**STOPPED: nothing will wake me; the owner must.** " + PASTE); return t


@case
def stopped_bold_word():
    t = start(); t.say("**STOPPED**: nothing will wake me; the owner must. " + PASTE); return t


@case
def stopped_quote():
    t = start(); t.say("> STOPPED: nothing will wake me; the owner must.\n\n" + PASTE); return t


@case
def stopped_last_line():
    t = start(); t.say(PASTE + "\n\nSTOPPED: nothing will wake me; the owner must."); return t


@case
def stopped_colon_next_line():   # the word alone on a line, a colon at the start of the next: not the marker
    t = start(); t.say("STOPPED\n: nothing will wake me.\n\n" + PASTE); return t


@case
def stopped_mid_long():  # a long reply (12 000 characters on either side of the line): the line is found wherever it is
    t = start(); t.say(PASTE + "\n" + "x " * 6000 + "\nSTOPPED: nothing will wake me; the owner must.\n" + "y " * 6000); return t


@case
def long_blank():        # 200 000 blank lines, then the hand-off: nothing in the gate may be quadratic in the length of the reply
    t = start(); t.say("\n" * 200000 + PASTE); return t


@case
def long_quotes():       # the same with a quote mark on every line (the marker may follow quote marks)
    t = start(); t.say(">\n" * 100000 + PASTE); return t


@case
def stopped_lower():     # the marker is the upper-case word
    t = start(); t.say("stopped: nothing will wake me. " + PASTE); return t


@case
def stopped_nocolon():
    t = start(); t.say("STOPPED. " + PASTE); return t


@case
def nohand():
    t = start(); t.bash_fg(); t.say("Done. The tests pass."); return t


@case
def subagent_msg():      # a message to an in-session subagent is not a hand-off, also when the agent was stopped
    t = start(); call, aid = t.agent_bg(); t.send_msg(aid, "agent"); t.taskstop(aid); t.say("Sent the follow-up to the agent."); return t


@case
def subagent_msg_plain():
    t = start(); t.send_msg("a0000000000000042", "agent"); t.say("Sent the follow-up to the agent."); return t


@case
def session_msg():       # to another session: a hand-off
    t = start(); t.send_msg("builder", "name"); t.say("Sent the brief to the builder."); return t


@case
def session_msg_control():   # a control message (shutdown_request) is not a hand-off
    t = start(); t.send_msg("builder", "name", type="shutdown_request"); t.say("Asked the builder to shut down."); return t


@case
def send_message_block():
    t = start(); t.send_message(); t.say("Sent."); return t


@case
def send_message_failed():   # the call failed: nothing was sent
    t = start(); t.send_message(err=True); t.say("The message could not be sent."); return t


@case
def two_dead():          # two watchers armed and stopped: the one named is the newer
    t = start(); c1, b1 = t.bash_bg(); t.taskstop(b1); c2, b2 = t.bash_bg(); t.taskstop(b2); t.say(PASTE)
    with open(os.path.join(OUT, "two_dead.second"), "w") as fh:
        fh.write(b2)
    return t


@case
def finished_before():   # the watcher's notification (completed) came BEFORE the hand-off
    t = start(); call, bid = t.bash_bg(); t.notify(bid, call); t.say("Step 2 is done."); t.send_message(); t.say("Sent step 3 to the builder."); return t


@case
def later_future():
    t = start(); t.send_message(); t.send_later(NOW + datetime.timedelta(hours=2)); t.say("Handed off; a check-in is scheduled."); return t


@case
def later_past():
    t = start(); t.send_message(); t.send_later(NOW - datetime.timedelta(minutes=10)); t.say("Handed off; a check-in was scheduled."); return t


@case
def later_noresult():    # the result has no fire_at: the input's delay_minutes (60) from the call is used (the call is 11 min old: still ahead)
    t = start(); t.send_message(); t.send_later(NOW, has_result=False); t.say("Handed off."); return t


@case
def later_noresult_past():   # no fire_at in the result, delay_minutes 1 from a call made 11 minutes ago: it has fired
    t = start(); t.send_message(); t.send_later(NOW, has_result=False, delay=1); t.say("Handed off."); return t


@case
def before_prompt():     # the hand-off belongs to an earlier prompt: out of scope
    t = start(); t.send_message(); t.say("Sent the brief."); t.human("Thanks. What is the weather like?"); t.say("No idea, I have no weather tool."); return t


@case
def phrase_a():          # the reply hands off in words only: the first Stop blocks it
    t = start(); t.say(PASTE); return t


@case
def phrase_stopped_plain():  # ... after the block the session says STOPPED: and does not repeat the phrase
    t = phrase_a(); t.meta("Stop hook feedback:\nwait gate: you handed off and nothing will wake you."); t.say("STOPPED: nothing will wake me; the owner must."); return t


@case
def phrase_armed():      # ... or arms a watcher and ends without repeating it
    t = phrase_a(); t.meta("Stop hook feedback:\nwait gate: you handed off and nothing will wake you."); t.bash_bg(); t.say("Armed the watcher."); return t


@case
def phrase_ends():       # ... or just ends
    t = phrase_a(); t.meta("Stop hook feedback:\nwait gate: you handed off and nothing will wake you."); t.say("Understood."); return t


@case
def phrase_new_prompt():     # ... and a new prompt from the owner is a new scope
    t = phrase_stopped_plain(); t.human("Thanks, I will do it."); t.say("You are welcome."); return t


@case
def phrase_answered():       # ... and a message from the builder answers it
    t = phrase_stopped_plain(); t.peer("step 3 is done"); t.say("Great, thanks."); return t


@case
def scope_a():
    t = start(); t.send_message(); t.say("Sent the brief."); return t


@case
def scope_b():           # scope_a, then a new prompt with a new hand-off
    t = scope_a(); t.human("Now step 4."); t.send_message(text="Step 4: render the outro"); t.say("Sent step 4."); return t


# ---- every kind of watcher
@case
def bash_auto():
    t = start(); t.send_message(); t.bash_bg(auto=True); t.say("Handed off."); return t


@case
def bash_denied():       # the launch was refused (bash-guard): nothing runs, so nothing is armed
    t = start(); t.send_message(); call = t.use("Bash", {"command": "watch.py --git origin main", "description": "test watcher", "run_in_background": True})
    t.result(call, "PreToolUse:Bash hook error: bash-guard: refused", err=True, tur="Error: refused"); t.say("The watcher could not be armed."); return t


@case
def bash_idless():       # moved to the background; the text names no id, toolUseResult.backgroundTaskId does
    t = start(); t.send_message(); t.bash_bg(auto=True, idless=True); t.say("Handed off."); return t


@case
def bash_fg_only():      # a foreground command is not a watcher
    t = start(); t.send_message(); t.bash_fg(); t.say("Handed off."); return t


@case
def monitor_alive():
    t = start(); t.send_message(); t.monitor(); t.say("Handed off."); return t


@case
def monitor_event():     # a Monitor event has no status: the monitor is still there
    t = start(); t.send_message(); call, mid = t.monitor(); t.notify(mid, call, status=None); t.say("An event came in."); return t


@case
def monitor_ended():
    t = start(); call, mid = t.monitor(); t.notify(mid, call, what="Monitor \"test log\" stream ended"); t.say("The monitor ended."); t.send_message(); t.say("Handed off."); return t


@case
def monitor_expired():   # armed 11 min ago for 2 minutes: no notice yet, so it counts as armed
    t = start(); t.send_message(); t.monitor(timeout_ms=120000); t.say("Handed off."); return t


@case
def monitor_persistent():
    t = start(); t.send_message(); t.monitor(timeout_ms=120000, persistent=True); t.say("Handed off."); return t


@case
def agent_alive():
    t = start(); t.send_message(); t.agent_bg(); t.say("Handed off; an agent works on step 2."); return t


@case
def agent_unflagged():   # run_in_background not set, but the result says the agent was launched async
    t = start(); t.send_message(); t.agent_bg(flag=False); t.say("Handed off."); return t


@case
def named_agent_rearm():     # a named background agent finished; the session sends it more work by name (recipient_kind name): not a hand-off, and it runs again
    t = start(); call, aid = t.agent_bg(name="reviewer"); t.notify(aid, call, what="Agent \"check the build\" finished"); t.say("The reviewer finished.")
    t.send_msg("reviewer", "name", text="One more thing: check the docs"); t.say("Asked the reviewer to continue."); return t


@case
def named_agent_stopped():   # ... and one that was stopped: a message to it is still no hand-off to another session
    t = start(); call, aid = t.agent_bg(name="reviewer"); t.taskstop(aid); t.send_msg("reviewer", "name", text="Never mind"); t.say("Told the reviewer to stand down."); return t


@case
def other_name_msg():        # a name that is no agent of this session
    t = start(); call, aid = t.agent_bg(name="reviewer"); t.taskstop(aid); t.send_msg("builder", "name"); t.say("Sent the brief to the builder."); return t


@case
def agent_foreground():
    t = start(); t.send_message(); t.agent_fg(); t.say("Handed off."); return t


@case
def agent_done():
    t = start(); call, aid = t.agent_bg(); t.notify(aid, call, what="Agent \"check the build\" finished"); t.say("The agent finished."); t.send_message(); t.say("Handed off."); return t


@case
def agent_resumed():     # the agent finished; more work sent to it by SendMessage: it runs again
    t = start(); call, aid = t.agent_bg(); t.notify(aid, call, what="Agent \"check the build\" finished"); t.say("The agent finished.")
    t.send_message(); t.send_msg(aid, "agent", text="One more thing: check the docs"); t.say("Handed off; the agent continues."); return t


@case
def workflow_alive():
    t = start(); t.send_message(); t.workflow(); t.say("Handed off."); return t


@case
def workflow_done():
    t = start(); call, wid = t.workflow(); t.notify(wid, call, what="Dynamic workflow \"a test workflow\""); t.say("The workflow finished."); t.send_message(); t.say("Handed off."); return t


@case
def wakeup_future():
    t = start(); t.send_message(); t.wakeup(3600, NOW + datetime.timedelta(minutes=50)); t.say("Handed off; I wake in an hour."); return t


@case
def wakeup_past():       # armed 11 min ago for 2 minutes
    t = start(); t.send_message(); t.wakeup(120, NOW - datetime.timedelta(minutes=8)); t.say("Handed off."); return t


@case
def wakeup_noresult():   # no scheduledFor in the result: the call's time plus the clamped delay (3600 s from 11 min ago: still ahead)
    t = start(); t.send_message(); t.wakeup(3600); t.say("Handed off."); return t


@case
def wakeup_stopped():
    t = start(); t.send_message(); t.wakeup(3600, NOW + datetime.timedelta(minutes=50)); t.wakeup(0, stop=True); t.say("Handed off; the loop is ended."); return t


@case
def cron_alive():
    t = start(); t.send_message(); t.cron(); t.say("Handed off."); return t


@case
def cron_deleted():
    t = start(); t.send_message(); call, cid = t.cron(); t.cron_delete(cid); t.say("Handed off."); return t


@case
def cron_oneshot_past():
    t = start(); t.send_message(); t.cron(recurring=False, next_fire=NOW - datetime.timedelta(minutes=5)); t.say("Handed off."); return t


@case
def trigger_alive():
    t = start(); t.send_message(); t.trigger(); t.say("Handed off."); return t


@case
def trigger_deleted():
    t = start(); t.send_message(); call, tid = t.trigger(); t.trigger_delete(tid); t.say("Handed off."); return t


@case
def trigger_deleted_noid():  # the create result carried no id: the delete ends the trigger without an id
    t = start(); t.send_message(); t.trigger(noid=True); t.trigger_delete("trig_UNKNOWN"); t.say("Handed off."); return t


@case
def trigger_once_future():
    t = start(); t.send_message(); t.trigger(once=NOW + datetime.timedelta(hours=1)); t.say("Handed off."); return t


@case
def trigger_once_past():
    t = start(); t.send_message(); t.trigger(once=NOW - datetime.timedelta(minutes=5)); t.say("Handed off."); return t


@case
def pr_alive():
    t = start(); t.send_message(); t.subscribe(); t.say("Handed off."); return t


@case
def pr_unsubscribed():
    t = start(); t.send_message(); t.subscribe(); t.unsubscribe(); t.say("Handed off."); return t


@case
def pr_taken():          # another session holds the PR: this one will not hear from it
    t = start(); t.send_message(); t.subscribe(taken=True); t.say("Handed off."); return t


@case
def url_alive():
    t = start(); t.send_message(); t.watch_url(); t.say("Handed off."); return t


@case
def url_unwatched():
    t = start(); t.send_message(); tid = t.watch_url(); t.unwatch_url(tid); t.say("Handed off."); return t


# ---- a hand-off answered, and what is not an answer
@case
def answered():          # the designed flow: arm the watcher, hand off, wake on its notification, review: the hand-off is answered
    t = start(); call, bid = t.bash_bg(); t.send_message(); t.say("Handed off; watching.")
    t.notify(bid, call); t.say("The builder pushed. I reviewed it: the intro renders fine."); return t


@case
def answered_late_watcher():   # hand off, THEN arm (the gate's own advice), the watcher fires, review
    t = start(); t.send_message(); call, bid = t.bash_bg(); t.say("Handed off; watching.")
    t.notify(bid, call); t.say("The builder pushed. I reviewed it: fine."); return t


@case
def answered_absorbed():     # the notification was absorbed mid-turn (an attachment, no user record)
    t = start(); call, bid = t.bash_bg(); t.send_message(); t.say("Handed off; watching.")
    t.notify(bid, call, mode="absorbed"); t.say("The builder pushed. Reviewed: fine."); return t


@case
def answered_attachment_only():   # a task this transcript never launched (started before a resume) completes: the only record of it is an attachment
    t = start(); t.send_message(); t.say("Handed off.")
    t.notify("b00077777", "toolu_NEVERLAUNCHED", mode="attachment"); t.say("The builder pushed. Reviewed: fine."); return t


@case
def answered_enqueue_only():     # ... the only record is the queue-operation enqueue (every notification in a real transcript has one)
    t = start(); t.send_message(); t.say("Handed off.")
    t.notify("b00077777", "toolu_NEVERLAUNCHED", mode="enqueue"); t.say("The builder pushed. Reviewed: fine."); return t


@case
def answered_bare():     # ... the only record is a plain user string (an older version)
    t = start(); t.send_message(); t.say("Handed off.")
    t.notify("b00077777", "toolu_NEVERLAUNCHED", mode="bare"); t.say("The builder pushed. Reviewed: fine."); return t


@case
def answered_then_new_phrase():   # answered, then the reply hands off again: a new hand-off needs a new watcher
    t = start(); call, bid = t.bash_bg(); t.send_message(); t.say("Handed off; watching.")
    t.notify(bid, call); t.say("Step 3 is fine. " + PASTE.replace("step 3", "step 4")); return t


@case
def answered_then_new_send():
    t = start(); call, bid = t.bash_bg(); t.send_message(); t.say("Handed off; watching.")
    t.notify(bid, call); t.say("Step 3 is fine."); t.send_message(text="Step 4: render the outro"); t.say("Sent step 4."); return t


@case
def kill_echo():         # the session stopped the watcher itself; if the harness then reports the task ("failed with exit code 143"), that is no answer
    t = start(); call, bid = t.bash_bg(); t.send_message(); t.taskstop(bid); t.notify(bid, call, status="failed", code=143); t.say("Sent."); return t


@case
def kill_echo_completed():   # the same, if the harness reports the stopped task as completed: still no answer
    t = start(); call, bid = t.bash_bg(); t.send_message(); t.taskstop(bid); t.notify(bid, call, status="completed"); t.say("Sent."); return t


@case
def failed_watcher():    # watch.py gave up (exit 3: no signal): a wake-up, not an answer
    t = start(); t.send_message(); call, bid = t.bash_bg(); t.notify(bid, call, status="failed", code=3); t.say("No signal after 4h."); return t


@case
def peer_answers():      # the builder wrote back
    t = start(); t.send_message(); t.say("Handed off."); t.peer("step 3 is done, pushed docs/STEP3-RESULT.md"); t.say("Got it, reviewing."); return t


# ---- which user records start a scope
@case
def meta_not_prompt():   # the Stop hook's own feedback is isMeta: the hand-off stays in scope
    t = start(); t.send_message(); t.say("Sent."); t.meta("Stop hook feedback: run-plan --until-done: keep going."); t.say("Still sent."); return t


@case
def cron_turn_not_prompt():      # a scheduled check-in starts a turn (turnOrigin cron): not a prompt, the hand-off it was set for stays open
    t = start(); t.send_message(); t.say("Handed off; a check-in is scheduled."); t.user("Check on the builder.", turnOrigin="cron", promptSource="system")
    t.say("Nothing yet."); return t


@case
def wakeup_kind_not_prompt():    # ... whatever the harness calls it: an origin.kind that is neither human nor sdk
    t = start(); t.send_message(); t.say("Handed off."); t.user("Check on the builder.", origin={"kind": "scheduled-wakeup"}); t.say("Nothing yet."); return t


@case
def unknown_turn_not_prompt():
    t = start(); t.send_message(); t.say("Handed off."); t.user("Check on the builder.", turnOrigin="wakeup"); t.say("Nothing yet."); return t


@case
def skill_text_not_prompt():   # skill text injected by a slash command: isMeta, and no text marker to give it away (real records start "Base directory for this skill")
    t = start(); t.send_message(); t.say("Sent."); t.meta("Base directory for this skill: /tmp/test/skills/status\n\n# status\nPrint the line."); t.say("Still sent."); return t


@case
def system_reminder_not_prompt():
    t = start(); t.send_message(); t.say("Sent."); t.user("<system-reminder>\nA reminder the harness added.\n</system-reminder>"); t.say("Still sent."); return t


@case
def epoch_a():
    t = start(); t.send_message(); t.say("Sent."); return t


@case
def epoch_b():           # epoch_a, the builder wrote back (an answer), then a second hand-off in the same human scope
    t = epoch_a(); t.peer("step 3 is done"); t.say("Got it."); t.send_message(text="Step 4: render the outro"); t.say("Sent step 4."); return t


@case
def notification_not_prompt():   # a failed unrelated task's notification: not a prompt, not an answer
    t = start(); t.send_message(); t.say("Sent."); t.notify("b00000999", "toolu_TESTOTHER", status="failed", code=1); t.say("An unrelated task failed."); return t


@case
def notification_bare():     # an older version: a plain user string, no fields
    t = start(); t.send_message(); t.say("Sent."); t.notify("b00000998", "toolu_TESTOTHER2", status="failed", code=1, mode="bare"); t.say("An unrelated task failed."); return t


@case
def compact_not_prompt():
    t = start(); t.send_message(); t.say("Sent."); t.user("This session is being continued from a previous conversation. Summary: step 3 was handed off.",
                                                           turnOrigin="human", isCompactSummary=True); t.say("Continuing."); return t


@case
def slash_is_prompt():   # a skill invoked by the human starts a turn
    t = start(); t.send_message(); t.say("Sent."); t.user("<command-message>status</command-message>\n<command-name>/status</command-name>", turnOrigin="sdk")
    t.say("Status shown."); return t


@case
def local_command_not_prompt():   # a local command's echo is no prompt and starts no turn
    t = start(); t.send_message(); t.say("Sent."); t.user("<command-name>/usage</command-name>\n<command-message>usage</command-message>")
    t.user("<local-command-stdout>ok</local-command-stdout>"); t.say("Sent, still."); return t


@case
def interrupt_not_prompt():
    t = start(); t.send_message(); t.say("Sent."); t.user([{"type": "text", "text": "[Request interrupted by user]"}]); t.say("Stopped there."); return t


@case
def queued_human():      # the owner typed mid-turn: an attachment, no user record
    t = start(); t.send_message(); t.say("Sent.")
    t.rec(type="attachment", attachment={"type": "queued_command", "prompt": "also, what is the weather?", "commandMode": "prompt", "origin": {"kind": "human"}})
    t.say("No idea."); return t


@case
def headless_prompt():   # claude -p: turnOrigin sdk, no origin
    t = T(); t.rec(type="user", userType="external", entrypoint="sdk-cli", turnOrigin="sdk", promptSource="sdk", promptId=t.uid(), message={"role": "user", "content": "Run step 3."})
    t.send_message(); t.say("Sent."); return t


@case
def old_prompt_before():   # an older version: the prompt is a plain user string with no fields at all
    t = T(); t.user("Run step 3."); t.send_message(); t.say("Sent."); return t


@case
def old_prompt_after():
    t = T(); t.send_message(); t.say("Sent."); t.user("What is the weather?"); t.say("No idea."); return t


@case
def image_prompt():      # a picture alone is a prompt too
    t = start(); t.send_message(); t.say("Sent.")
    t.user([{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "AAAA"}}], turnOrigin="human", promptSource="sdk", origin={"kind": "human"})
    t.say("Nice picture."); return t


@case
def sidechain():         # records of a subagent are not this session's
    t = start(); t.say("Done."); call = t.use(RC + "send_message", {"session_id": "session_TEST0001", "message": "x"}, isSidechain=True)
    t.result(call, "{\"status\":\"delivered\"}", isSidechain=True); t.say("Done again."); return t


@case
def no_prompt():         # no human prompt at all: the whole transcript is the scope
    t = T(); t.send_message(); t.say("Sent."); return t


@case
def compact_keeps_watcher():     # a watcher armed before a compaction is still armed after it
    t = start(); t.bash_bg(); t.send_message(); t.say("Sent.")
    t.user("This session is being continued from a previous conversation.", turnOrigin="human", isCompactSummary=True); t.say("Continuing."); return t


@case
def unicode_incident():
    t = start("Schicke Schritt 3 an den Builder. 中文 Á"); call, bid = t.bash_bg(); t.taskstop(bid)
    t.say("Paste this into the builder: Schritt 3 — Á中文. I'll ping you when it's done."); return t


@case
def junk_lines():        # garbage between the records, and a last line cut in the middle (the file is being written)
    t = scope_a(); t.write("junk_lines")
    with open(os.path.join(OUT, "junk_lines.jsonl"), "r", encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    with open(os.path.join(OUT, "junk_lines.jsonl"), "wb") as fh:
        fh.write(("not json at all\n" + "\n".join(lines[:2]) + "\n").encode("utf-8") + b"\x00\x01 binary \xff\n" +
                 ("\n".join(lines[2:]) + "\n[1, 2, 3]\n{\"type\": \"assistant\", \"message\": {\"content\": [{\"type\": \"te").encode("utf-8"))
    return None


@case
def big():               # a long session: 4500 records of tool use, then a hand-off with nothing armed
    t = T(step=0.01); t.human("Read the files.")
    for i in range(1500):
        c = t.use("Read", {"file_path": "/tmp/test/file%d.txt" % i}); t.result(c, "line of text " * 20); t.say("Read file %d." % i)
    t.send_message(); t.say("Sent."); return t


# ---- the hand-off phrases: (reply, blocks?)
PHRASES = [
    ("Paste this into the builder: step 3.", 1), ("Paste the following into your laptop session and I will take it from there.", 1),
    ("paste the prompt in the other session", 1), ("Paste it in.", 1), ("Paste that into the cloud session.", 1), ("Paste the line into the builder.", 1),
    ("Paste the brief into the builder.", 1), ("PASTE THIS INTO the builder", 1), ("Paste this prompt into the builder.", 1),
    ("I'll ping you when it's done.", 1), ("I will tell you when the build finishes.", 1), ("I'll notify you.", 1), ("I'll message you when it lands.", 1),
    ("I will update you once it's merged.", 1), ("I'll let you know.", 1), ("I will let you know how it goes.", 1), ("I'll check back in ten minutes.", 1),
    ("I'll come back to this after the render.", 1), ("I will report back.", 1), ("I\u2019ll ping you when it\u2019s done.", 1), ("I'll tell you when it is done.", 1),
    ("Step 3 is queued. Everything else can wait.\n\nI'll let you know when the render is in.", 1),
    ("Paste this into Claude and I'll take it from there.", 1), ("paste the following into a new session", 1), ("Paste this into the other terminal", 1),
    ("Paste the line into the builder.", 1), ("Paste it in the builder.", 1),
    ("I'll check the file now.", 0), ("I'll update the docs and run the tests.", 0), ("I'll tell the team about the change.", 0),
    ("I'll tell you what I found: the intro renders.", 0), ("I will tell you why: the cache was cold.", 0), ("Paste: x", 0),
    ("You can paste it here if you want.", 0), ("I'll look into it.", 0), ("The builder will ping you.", 0), ("Let me know when it is done.", 0),
    ("Done. All tests pass.", 0), ("I will check the logs.", 0), ("paste this inside the config", 0), ("Please repaste this into the builder", 0),
    ("Here is the brief:\n```\nI'll ping you when it is done. Paste this into the builder.\n```\nThat is all.", 0),
    ("Use `I'll ping you` as the sentence.", 0), ("I can't ping you from here.", 0), ("", 0),
    ("Paste this into settings.json.", 0), ("paste this into your browser console", 0), ("Paste the following into ~/.zshrc", 0), ("Paste this into the config file", 0),
    ("Paste it in src/app.py", 0), ("Paste this into your editor", 0), ("paste it into the shell", 0), ("Paste this into .env", 0), ("paste this in ./run.sh", 0),
    ("Paste it in the chat.", 0), ("paste this into your reply", 0),
    ("Paste this into your terminal.", 0), ("paste the following into a terminal and press enter", 0), ("Paste this in Slack.", 0),
    ("Paste it into the PR description.", 0), ("paste this into the issue", 0), ("Paste this into Excel.", 0), ("Paste the line into your command prompt", 0),
    ("paste this into your command line", 0), ("Paste this into PowerShell.", 0), ("paste that into a Jira ticket", 0),
    ("Paste this into the builder terminal", 1), ("Paste the prompt into the laptop session's terminal", 1),
    ("Paste this into another terminal", 1), ("Paste it into another chat", 1),
    ("Don't paste the prompt into the builder; I ran it here.", 0), ("Do not paste this into the other session.", 0),
    ("No need to paste it into the builder: step 3 is done.", 0),
]
with open(os.path.join(OUT, "phrases.tsv"), "w", encoding="utf-8") as fh:
    for i, (text, blocks) in enumerate(PHRASES):
        t = start("What is the status of step 3?")
        t.say(text)
        t.write("phrase_%d" % i)
        fh.write("phrase_%d\t%s\t%s\n" % (i, "block" if blocks else "pass", json.dumps(text, ensure_ascii=True)[:90]))

for name, f in CASES.items():
    t = f()
    if t is not None:
        t.write(name)
PY

# --- small checkers (arguments, not stdin: a Windows pipe would be decoded as cp1252)
cat > "$D/chk.py" <<'PY'
import json, re, sys, datetime
mode = sys.argv[1]
if mode == "block":      # block <the hook's stdout> <text the reason must hold>...
    try:
        d = json.loads(sys.argv[2])
    except Exception:
        print("not JSON: %r" % sys.argv[2][:200]); sys.exit(0)
    r = d.get("reason", "") if isinstance(d, dict) else ""
    if not isinstance(d, dict) or sorted(d) != ["decision", "reason"] or d["decision"] != "block":
        print("not the Stop-hook block shape {decision, reason}: %r" % (sorted(d) if isinstance(d, dict) else d)); sys.exit(0)
    if len(r.split("\n")) > 6 or len(r) > 1800:
        print("reason is %d lines / %d chars" % (len(r.split("\n")), len(r))); sys.exit(0)
    miss = [s for s in sys.argv[3:] if s not in r]
    print("ok" if not miss else "reason lacks %r in: %s" % (miss, r.replace("\n", " | ")))
elif mode == "wait":     # wait <wait.json> <python expression over d>
    try:
        d = json.load(open(sys.argv[2], encoding="utf-8"))
        print("ok" if eval(sys.argv[3]) else "false for %r" % (d,))
    except Exception as e:
        print("%s: %s" % (type(e).__name__, e))
elif mode == "scope":    # scope <wait-block.json> <transcript>: the marker holds exactly one scope, session id + the uuid of the first human prompt
    try:
        scopes = list(json.load(open(sys.argv[2], encoding="utf-8"))["scopes"])
        first = next(json.loads(l) for l in open(sys.argv[3], encoding="utf-8") if json.loads(l).get("turnOrigin") == "human")["uuid"]
        print("ok" if scopes == ["sid-test:" + first + "@-1"] else "scopes %r, first prompt %s" % (scopes, first))
    except Exception as e:
        print("%s: %s" % (type(e).__name__, e))
elif mode == "hhmm":     # hhmm <the hook's stdout> <wait.json>: the reason holds the local HH:MM of the hand-off
    r = json.loads(sys.argv[2])["reason"]
    s = json.load(open(sys.argv[3], encoding="utf-8"))["since"]
    t = datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone().strftime("%H:%M")
    print("ok" if ("handed off at " + t) in r else "no 'handed off at %s' in %s" % (t, r.replace("\n", " | ")))
elif mode == "guard":    # guard <the hook's stdout>: the bash-guard payload of the command the reason recommends, placeholders filled in
    r = json.loads(sys.argv[2])["reason"]
    m = re.search(r'(bash "[^\n]*)', r)
    cmd = m.group(1).replace("<branch>", "main").replace("<result file>", "docs/STEP3-RESULT.md").replace("<the commit you handed off at>", "0123abc")
    print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd, "run_in_background": True}}))
elif mode == "command":  # command <the hook's stdout>: the recommended command, as it is
    r = json.loads(sys.argv[2])["reason"]
    m = re.search(r'(bash "[^\n]*)', r)
    print(m.group(1) if m else "")
elif mode == "imports":  # imports <wait-gate.py>: stdlib only, no subprocess, the 3.9 grammar
    import ast
    src = open(sys.argv[2], encoding="utf-8").read()
    tree = ast.parse(src, feature_version=(3, 9))
    mods = sorted({a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names} |
                  {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module})
    calls = sorted({n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id == "os"
                    and (n.attr in ("system", "popen", "fork", "startfile") or n.attr.startswith(("exec", "spawn")))})
    ok = set(mods) <= {"json", "os", "re", "sys", "time", "pathlib", "datetime", "hashlib", "winreg"} and not calls   # hashlib: 0.7.1 F1, winreg: 0.7.1 D8, both imported inside fit_key only
    print("ok" if ok else "imports %s, process calls %s" % (mods, calls))
elif mode == "hooks":    # hooks <hooks.json>: the Stop entry runs ledger, until-done, wait-gate (timeout 10), heartbeat, in that order
    d = json.load(open(sys.argv[2], encoding="utf-8"))
    cmds = [(re.search(r"hooks/([a-z-]+)\.py", h["command"]).group(1), h.get("timeout")) for h in d["hooks"]["Stop"][0]["hooks"]]
    print("ok" if cmds == [("ledger", 20), ("until-done", 330), ("wait-gate", 10), ("heartbeat", 5)] else "Stop hooks: %r" % cmds)
PY

py "$D/mk.py" "$D/t" || { echo "FAIL could not build the synthetic transcripts"; exit 1; }
[ -s "$D/t/incident.jsonl" ] && [ -s "$D/t/phrases.tsv" ] || { echo "FAIL the synthetic transcripts are missing"; exit 1; }

# --- drivers. XTRA = more fields for the Stop input (e.g. ,"background_tasks":[]); KEEP = non-empty: do not reset the state dir first
XTRA=""; KEEP=""
gate() { # $1 = a case (a file in $D/t) or a path -> OUT RC ERR (the hook's stdout, exit code, stderr)
  local tp=$1; [ -f "$D/t/$1.jsonl" ] && tp="$D/t/$1.jsonl"
  [ -n "$KEEP" ] || rm -rf "$P"
  IN=$(printf '{"hook_event_name":"Stop","session_id":"sid-test","transcript_path":"%s","cwd":"%s","stop_hook_active":false%s}' "$(wp "$tp")" "$PW" "$XTRA")
  OUT=$(printf '%s' "$IN" | CLAUDE_PROJECT_DIR="$PW" py "$GATE" 2>"$D/err"; echo "rc=$?"); RC=${OUT##*rc=}; OUT=${OUT%rc=*}; OUT=${OUT%$'\n'}; ERR=$(cat "$D/err")
}
quiet() { [ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; }   # exit 0, nothing on stdout, nothing on stderr
want_pass() { # $1 = label, $2 = case
  gate "$2"
  if quiet; then ok "pass: $1"; else ko "expected a pass (exit 0, nothing printed): $1 -> rc=$RC out='${OUT:0:200}' err='${ERR:0:200}'"; fi
}
want_block() { # $1 = label, $2 = case, then the texts the reason must hold
  gate "$2"; local label=$1; shift 2
  if [ "$RC" != 0 ] || [ -n "$ERR" ]; then ko "expected a block: $label -> rc=$RC out='${OUT:0:200}' err='${ERR:0:200}'"; return; fi
  local r; r=$(py "$D/chk.py" block "$OUT" "$@" </dev/null)
  if [ "$r" = ok ]; then ok "block: $label"; else ko "expected a block: $label -> $r"; fi
}
wj() { # $1 = label, $2 = python expression over d (wait.json)
  local r; r=$(py "$D/chk.py" wait "$W" "$2" </dev/null)
  if [ "$r" = ok ]; then ok "wait.json: $1"; else ko "wait.json: $1 -> $r"; fi
}
no_wj() { if [ ! -e "$W" ]; then ok "wait.json: $1"; else ko "wait.json: $1 -> still there: $(cat "$W")"; fi; }

# ===== 1. the incident, and the cases the task names
want_block 'INCIDENT REPLAY: a watcher armed, stopped with TaskStop "to save tokens", then "Paste this into the builder: ... I'"'"'ll ping you when it'"'"'s done" -> BLOCK; the reason names the stopped watcher and the hand-off' incident \
  "wait gate: you handed off at" 'your reply says "Paste this into the builder"' "nothing will wake you" "the watcher started at" "was stopped (background Bash)." "watch.py" "--git origin" "STOPPED: nothing will wake me; <who> must."
r=$(py "$D/chk.py" hhmm "$OUT" "$W" </dev/null); [ "$r" = ok ] && ok "the reason gives the hand-off's local time (HH:MM of the reply's record)" || ko "the reason's time: $r"
wj "blocked: what is the quoted phrase, the stopped watcher is named, session and times are set" \
  "d['state']=='blocked' and d['what']=='\"Paste this into the builder\"' and d['watcher']['kind']=='bash' and d['watcher']['state']=='stopped' and d['watcher']['id'] and d['watcher']['armed'] and d['session_id']=='sid-test' and d['since'] and d['at']"
r=$(py "$D/chk.py" scope "$M" "$D/t/incident.jsonl" </dev/null); [ "$r" = ok ] && ok "the block marker names the scope: session id + the uuid of the last human prompt + the last answer (none: @-1)" || ko "block marker: $r"
KEEP=1; want_pass "SECOND STOP in the same scope -> pass (blocked once, never a trap)" incident
wj "after the second Stop the state is stopped: the session chose to stop, the status line says so" "d['state']=='stopped' and d['watcher']['state']=='stopped'"
want_pass "a third Stop is as quiet" incident; KEEP=""
want_block "a new human prompt is a new scope: scope_a (one prompt, one hand-off) blocks" scope_a "send_message to session_TEST0001"
KEEP=1; want_block "... scope_b (a second prompt, a second hand-off) blocks once more" scope_b "send_message to session_TEST0001"
want_pass "... and then the second Stop of scope_b passes"  scope_b; KEEP=""
want_block "epoch: one prompt, a hand-off (blocked once) ..." epoch_a "send_message to session_TEST0001"
KEEP=1; want_block "... the builder wrote back (an answer), a second hand-off in the same prompt's scope is gated again" epoch_b "send_message to session_TEST0001"
want_pass "... and its second Stop passes" epoch_b; KEEP=""
want_block "a hand-off in words only (the reply says paste this into the builder) blocks" phrase_a 'your reply says "Paste this into the builder"'
KEEP=1; want_pass "... the reply after the block says STOPPED: and does not repeat the phrase -> pass" phrase_stopped_plain
wj "... the blocked hand-off stands: state stopped, its what and its time (the first reply's) kept" "d['state']=='stopped' and d['what']=='\"Paste this into the builder\"' and d['since'] < d['at'] and d['scope'].endswith('@-1')"
want_pass "... and a later Stop in that scope keeps it" phrase_stopped_plain
wj "... still stopped" "d['state']=='stopped' and d['what']=='\"Paste this into the builder\"'"; KEEP=""
want_block "... again: blocked (phrase_a)" phrase_a "wait gate: you handed off"
KEEP=1; want_pass "... the session armed a watcher after the block and ended without repeating the phrase -> pass" phrase_armed
wj "... watching: the hand-off stands and the watcher is named" "d['state']=='watching' and d['what']=='\"Paste this into the builder\"' and d['watcher']['kind']=='bash' and d['watcher']['state']=='alive'"; KEEP=""
want_block "... again: blocked (phrase_a)" phrase_a "wait gate: you handed off"
KEEP=1; want_pass "... the session just ended its turn after the block -> pass" phrase_ends
wj "... stopped: the status line says so" "d['state']=='stopped' and d['what']=='\"Paste this into the builder\"'"; KEEP=""
want_block "... again: blocked (phrase_a)" phrase_a "wait gate: you handed off"
KEEP=1; want_pass "... a new prompt from the owner is a new scope: the carried hand-off is dropped" phrase_new_prompt
no_wj "... wait.json removed"; KEEP=""
want_block "... again: blocked (phrase_a)" phrase_a "wait gate: you handed off"
KEEP=1; want_pass "... a message from the builder answers it: the carried hand-off is dropped" phrase_answered
no_wj "... wait.json removed"; KEEP=""
want_pass "a watcher armed AFTER the hand-off -> pass" armed_after
wj "watching: what is the recipient, the live watcher is named" "d['state']=='watching' and d['what']=='session_TEST0001' and d['watcher']['kind']=='bash' and d['watcher']['state']=='alive' and d['watcher']['armed'] and d['since']"
want_pass "a watcher armed earlier in the turn is alive when the reply hands off" armed_before_phrase
wj "watching, handed off in the reply" "d['state']=='watching' and d['what'].startswith('\"Paste this into')"
want_pass "a reply starting STOPPED: -> pass (the watcher was stopped; the reply says plainly that it is stopped)" stopped_start
wj "stopped: the stopped watcher is named" "d['state']=='stopped' and d['watcher']['state']=='stopped'"
want_pass "STOPPED: alone" stopped_only
want_pass "**STOPPED: ...** (bold)" stopped_bold
want_pass "**STOPPED**: ... (the word bold)" stopped_bold_word
want_pass "> STOPPED: ... (a quote)" stopped_quote
want_pass "STOPPED: on the last line (the block text says: end your reply with it)" stopped_last_line
want_block "STOPPED on one line and a colon at the start of the next is not the marker" stopped_colon_next_line "your reply says"
want_pass "STOPPED: in the middle of a long reply (12 000 characters either side) is found: the search is not cut to the ends of the reply" stopped_mid_long
T0=$(date +%s); want_block "a reply of 200 000 blank lines, then a hand-off, still blocks ..." long_blank 'your reply says "Paste this into the builder"'; T1=$(date +%s)
if [ $((T1 - T0)) -lt 12 ]; then ok "... and the STOPPED: search is linear: $((T1 - T0)) s (a class that ran across line ends cost 10 s for 60 000 blank lines)"; else ko "a reply of 200 000 blank lines took $((T1 - T0)) s: the STOPPED: search is not linear"; fi
T0=$(date +%s); want_block "a reply of 100 000 quoted blank lines, then a hand-off, still blocks ..." long_quotes 'your reply says "Paste this into the builder"'; T1=$(date +%s)
if [ $((T1 - T0)) -lt 12 ]; then ok "... in $((T1 - T0)) s"; else ko "a reply of 100 000 quoted blank lines took $((T1 - T0)) s: the STOPPED: search is not linear"; fi
want_block "lower-case 'stopped:' is not the marker" stopped_lower "your reply says"
want_block "'STOPPED.' without the colon is not the marker" stopped_nocolon "your reply says"
want_pass "no hand-off -> pass" nohand
no_wj "cleared when no hand-off is open"
[ ! -e "$P" ] && ok "no hand-off: the gate wrote nothing and did not even make the state dir" || ko "state dir made without a hand-off: $(ls "$P")"
want_pass "SendMessage to a subagent (recipient_kind agent) is not a hand-off" subagent_msg_plain
want_pass "... also with a background agent that was stopped by TaskStop" subagent_msg
want_block "SendMessage to another session (recipient_kind name) -> block" session_msg "SendMessage to builder"
wj "blocked: what is the recipient; no watcher was ever armed" "d['state']=='blocked' and d['what']=='builder' and d['watcher'] is None"
want_pass "a control message (SendMessage type shutdown_request) is not a hand-off" session_msg_control
want_block "send_message -> block" send_message_block "send_message to session_TEST0001" "No watcher is armed: none was ever started in this session."
want_pass "a send_message that failed (is_error) sent nothing: no hand-off" send_message_failed
want_block "two watchers armed and stopped: the reason names one of them ..." two_dead "was stopped (background Bash)."
wj "... the newer one is on record" "d['watcher']['id']=='$(cat "$D/t/two_dead.second")' and d['watcher']['state']=='stopped'"
want_block "a watcher whose notification completed before the hand-off is not alive -> block" finished_before "send_message to session_TEST0001" "has finished (background Bash)."
want_pass "send_later with fire_at ahead -> pass" later_future
wj "watching: a send_later" "d['state']=='watching' and d['watcher']['kind']=='send_later'"
want_block "send_later with fire_at behind -> block" later_past "has already fired (send_later)."
want_pass "send_later with no fire_at in the result: the call's delay_minutes from the call is ahead -> pass" later_noresult
want_block "... and when that delay has run out -> block" later_noresult_past "has already fired (send_later)."
want_pass "a hand-off before the last human prompt -> pass" before_prompt
no_wj "cleared: the hand-off belongs to an earlier prompt"

# ===== 2. missing / garbage input: exit 0, nothing printed
gate "$D/t/does-not-exist.jsonl"; quiet && ok "missing transcript -> exit 0, nothing printed" || ko "missing transcript: rc=$RC out='$OUT' err='$ERR'"
printf 'garbage, not json\n\x00\x01\x02\xff\xfe\n{"type":\n' > "$D/garbage.jsonl"; gate "$D/garbage.jsonl"; quiet && ok "garbage transcript -> exit 0, nothing printed" || ko "garbage transcript: rc=$RC out='$OUT' err='$ERR'"
: > "$D/empty.jsonl"; gate "$D/empty.jsonl"; quiet && ok "empty transcript -> exit 0, nothing printed" || ko "empty transcript: rc=$RC out='$OUT' err='$ERR'"
mkdir -p "$D/adir"; gate "$D/adir"; quiet && ok "a transcript path that is a directory -> exit 0, nothing printed" || ko "directory transcript: rc=$RC out='$OUT' err='$ERR'"
bad=0
for body in 'not json' '' '[]' 'null' '{"hook_event_name":"Stop"}' '{"hook_event_name":"Stop","transcript_path":42}' '{"hook_event_name":"Stop","transcript_path":["x"],"cwd":7}'; do
  o=$(printf '%s' "$body" | CLAUDE_PROJECT_DIR="$PW" py "$GATE" 2>&1; echo "rc=$?"); [ "$o" = "rc=0" ] || { ko "stdin '$body' -> $o"; bad=1; }
done
[ $bad = 0 ] && ok "garbage / empty / non-object / field-less stdin -> exit 0, nothing printed, nothing on stderr"
o=$(printf '%s' "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"sid-test\",\"transcript_path\":\"$(wp "$D/t/incident.jsonl")\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$GATE" 2>&1; echo "rc=$?"); [ "$o" = "rc=0" ] && ok "an event that is not Stop is ignored" || ko "SubagentStop: $o"
want_block "garbage lines, a binary line, a JSON array and a last line cut in the middle: the readable records still decide" junk_lines "send_message to session_TEST0001"
want_block "a 4500-record session is read in one pass inside the budget" big "send_message to session_TEST0001"
# 0.7.5 F3: started directly, because the launcher's -I ignores PYTHONIOENCODING. The event itself now carries non-ASCII bytes too (a Stop input field the gate ignores, prompt_id): with ASCII-only stdin a gate that read it as text would still pass, so the case could not fail.
XTRA=',"prompt_id":"Á中文"'; gate unicode_incident; XTRA=""; rm -rf "$P"; OUT=$(printf '%s' "$IN" | PYTHONUTF8=1 PYTHONIOENCODING=cp1252 CLAUDE_PROJECT_DIR="$PW" "$REAL" "$GATE" 2>&1)
r=$(py "$D/chk.py" block "$OUT" "wait gate: you handed off" </dev/null); [ "$r" = ok ] && ok "block: non-ASCII text (Á 中文) in the transcript, stdin under PYTHONIOENCODING=cp1252 (a Windows pipe)" || ko "cp1252: $r"

# ===== 3. wait_gate: off (the adapter's frontmatter; the body does not count)
mkdir -p "$D/proj/.claude"
printf -- '---\ncheck: true\nwait_gate: off\n---\nbody\n' > "$D/proj/.claude/smartuse.local.md"; want_pass "wait_gate: off in the adapter frontmatter -> pass, though the incident is open" incident
[ ! -e "$P" ] && ok "wait_gate: off writes nothing (no marker, no wait.json)" || ko "wait_gate: off wrote: $(ls "$P")"
printf -- '---\nwait_gate: "OFF"   # the owner turned it off\n---\n' > "$D/proj/.claude/smartuse.local.md"; want_pass "wait_gate: \"OFF\" with a comment (quotes, case, comment)" incident
printf -- '---\r\nwait_gate: off\r\n---\r\n' > "$D/proj/.claude/smartuse.local.md"; want_pass "wait_gate: off in a CRLF file" incident
printf -- '---\nwait_gate: false\n---\n' > "$D/proj/.claude/smartuse.local.md"; want_pass "wait_gate: false" incident
printf -- '---\nwait_gate: on\ncheck: true\n---\n' > "$D/proj/.claude/smartuse.local.md"; want_block "wait_gate: on -> the gate works" incident "wait gate: you handed off"
printf -- '---\ncheck: true\n---\nwait_gate: off\n' > "$D/proj/.claude/smartuse.local.md"; want_block "a wait_gate: off line in the body, outside the frontmatter, does not count" incident "wait gate: you handed off"
printf 'wait_gate: off\n' > "$D/proj/.claude/smartuse.local.md"; want_block "no frontmatter at all: not the adapter's switch" incident "wait gate: you handed off"
rm -f "$D/proj/.claude/smartuse.local.md"; want_block "no adapter -> the gate works" incident "wait gate: you handed off"

# ===== 4. every kind of watcher, alive and ended
want_pass "a foreground Bash that did not finish in time and was moved to the background (ID: ...) is a watcher" bash_auto
want_pass "... also when only toolUseResult.backgroundTaskId says so (the text names no id)" bash_idless
want_block "a foreground Bash is no watcher" bash_fg_only "No watcher is armed: none was ever started in this session."
want_block "a background launch that was refused (is_error) armed nothing" bash_denied "No watcher is armed: none was ever started in this session."
want_pass "Monitor armed -> alive" monitor_alive
wj "watching: a Monitor" "d['watcher']['kind']=='monitor'"
want_pass "a Monitor event (no <status>) is not the end of the monitor" monitor_event
want_block "a Monitor whose end notification came before the hand-off -> block" monitor_ended "has finished (Monitor)."
want_pass "a Monitor stays armed until its end notice, whatever timeout_ms says (the harness sends one at expiry)" monitor_expired
want_pass "... also a persistent one" monitor_persistent
want_pass "background Agent -> alive" agent_alive
wj "watching: a background agent" "d['watcher']['kind']=='agent' and d['watcher']['id'].startswith('a0')"
want_pass "an Agent launched async without run_in_background (the result says so) is a watcher" agent_unflagged
want_block "a foreground Agent is no watcher" agent_foreground "No watcher is armed: none was ever started"
want_pass "a message BY NAME to a named background agent that finished is no hand-off and runs it again" named_agent_rearm
want_pass "a message by name to a named agent that was stopped is no hand-off to another session" named_agent_stopped
want_block "a message to a name that is no agent of this session is a hand-off" other_name_msg "SendMessage to builder"
want_block "a background Agent that finished before the hand-off -> block" agent_done "has finished (background agent)."
want_pass "SendMessage to a finished background agent runs it again: alive" agent_resumed
want_pass "background Workflow -> alive" workflow_alive
want_block "a Workflow that finished before the hand-off -> block" workflow_done "has finished (background workflow)."
want_pass "ScheduleWakeup whose scheduledFor is ahead -> pass" wakeup_future
want_block "ScheduleWakeup whose time has passed -> block" wakeup_past "has already fired (ScheduleWakeup)."
want_pass "ScheduleWakeup without scheduledFor: the call's time + delaySeconds (3600) is ahead" wakeup_noresult
want_block "ScheduleWakeup stop:true ends the loop -> block" wakeup_stopped "was stopped (ScheduleWakeup)."
want_pass "CronCreate -> alive" cron_alive
want_block "CronCreate then CronDelete -> block" cron_deleted "was stopped (cron job)."
want_block "a one-shot cron whose nextFireAt has passed -> block" cron_oneshot_past "has already fired (cron job)."
want_pass "create_trigger (cron_expression) -> alive" trigger_alive
want_block "create_trigger then delete_trigger -> block" trigger_deleted "was stopped (scheduled task)."
want_block "... also when the create result carried no id" trigger_deleted_noid "was stopped (scheduled task)."
want_pass "create_trigger with run_once_at ahead -> alive" trigger_once_future
want_block "create_trigger with run_once_at behind -> block" trigger_once_past "has already fired (scheduled task)."
want_pass "subscribe_pr_activity -> alive" pr_alive
want_block "subscribe_pr_activity then unsubscribe_pr_activity -> block" pr_unsubscribed "was stopped (PR subscription)."
want_block "subscribe_pr_activity answered 'this session will not receive events' -> not a watcher" pr_taken "No watcher is armed: none was ever started"
want_pass "watch_url -> alive" url_alive
want_block "watch_url then unwatch_url -> block" url_unwatched "was stopped (webhook)."

# ===== 5. a hand-off that has been answered: the designed flow must not block itself
want_pass "ARM, HAND OFF, wake on the watcher's notification, review (no new hand-off) -> pass: the notification answered it" answered
no_wj "answered: wait.json cleared"
want_pass "HAND OFF, then arm the watcher (the gate's own advice), it fires, review -> pass" answered_late_watcher
want_pass "the notification absorbed mid-turn (an attachment, no user record) answers too" answered_absorbed
want_pass "a completed task this transcript never launched answers the hand-off: its only record is an attachment" answered_attachment_only
want_pass "... its only record is a plain user string (an older version)" answered_bare
want_pass "... its only record is the queue-operation enqueue (every real notification has one)" answered_enqueue_only
want_block "answered, then the reply hands off AGAIN (paste this ...) with nothing armed -> block" answered_then_new_phrase 'your reply says "Paste this into the builder"' "has finished (background Bash)."
want_block "answered, then a NEW send_message with nothing armed -> block" answered_then_new_send "send_message to session_TEST0001"
want_block "the notification of a task the session stopped itself (failed, exit 143), if a version sends one, is no answer -> block" kill_echo "was stopped (background Bash)."
want_block "... also if the stopped task is reported as completed: the session caused it, it answers nothing" kill_echo_completed "was stopped (background Bash)."
want_block "a watcher that failed (watch.py: no signal, exit 3) woke the session but answered nothing -> block" failed_watcher "has finished (background Bash)."
want_pass "a message from the other session (the builder wrote back) answers the hand-off" peer_answers

# ===== 6. which user records start a scope (the hand-off is in scope unless a genuine human prompt came after it)
want_block "the Stop hook's own feedback (isMeta) is no prompt: the hand-off stays in scope" meta_not_prompt "send_message to session_TEST0001"
want_block "skill text with no marker, only isMeta (as on real records) is no prompt" skill_text_not_prompt "send_message to session_TEST0001"
want_block "a <system-reminder> user record is no prompt" system_reminder_not_prompt "send_message to session_TEST0001"
want_block "a task notification of an unrelated failed task is no prompt and no answer" notification_not_prompt "send_message to session_TEST0001"
want_block "... also in the older form (a plain user string, no origin fields)" notification_bare "send_message to session_TEST0001"
want_block "a compact summary (isCompactSummary) is no prompt" compact_not_prompt "send_message to session_TEST0001"
want_block "a scheduled check-in (turnOrigin cron) is no prompt: the hand-off it was set for stays open" cron_turn_not_prompt "send_message to session_TEST0001"
want_block "... nor is a record whose origin.kind is neither human nor sdk" wakeup_kind_not_prompt "send_message to session_TEST0001"
want_block "... nor an unknown turnOrigin" unknown_turn_not_prompt "send_message to session_TEST0001"
want_pass "a slash command the owner typed (<command-message>) is a prompt" slash_is_prompt
want_block "a local command's echo (<command-name>, <local-command-stdout>) is no prompt" local_command_not_prompt "send_message to session_TEST0001"
want_block "an interrupt marker is no prompt" interrupt_not_prompt "send_message to session_TEST0001"
want_pass "a message the owner typed mid-turn (attachment queued_command, origin human) is a prompt" queued_human
want_block "a headless prompt (turnOrigin sdk, no origin) is a prompt: the hand-off after it is in scope" headless_prompt "send_message to session_TEST0001"
want_block "an older prompt with no fields at all (a plain user string): the hand-off after it is in scope" old_prompt_before "send_message to session_TEST0001"
want_pass "... and a hand-off before such a prompt is out of scope" old_prompt_after
want_pass "a picture alone is a prompt" image_prompt
want_pass "records of a subagent (isSidechain) are not this session's: its send_message is no hand-off" sidechain
want_block "no genuine prompt anywhere: the whole transcript is the scope" no_prompt "send_message to session_TEST0001"
want_pass "a watcher armed before a compaction is still armed after it" compact_keeps_watcher

# ===== 7. the Stop input's own fields
XTRA=',"background_tasks":[{"id":"bz000001","type":"shell","status":"running","description":"d","command":"sleep 600"}]'
want_pass "background_tasks lists a running task -> pass (the transcript shows no watcher)" send_message_block
wj "watching: the watcher comes from the Stop input" "d['state']=='watching' and d['watcher']['kind']=='task' and d['watcher']['id']=='bz000001' and d['watcher']['armed'] is None"
XTRA=',"background_tasks":[]'; want_block "background_tasks: [] proves nothing: the hand-off blocks" send_message_block "send_message to session_TEST0001"
XTRA=',"background_tasks":[{"id":"bz000002","type":"shell","status":"completed"}]'; want_block "background_tasks lists only a finished task -> block" send_message_block "send_message to session_TEST0001"
XTRA=',"session_crons":[{"id":"c1","cron":"*/5 * * * *"}]'; want_pass "session_crons lists a cron -> pass" send_message_block
XTRA=',"last_assistant_message":"STOPPED: nothing will wake me; the owner must."'; want_pass "last_assistant_message (the Stop input) is the reply: it says STOPPED: -> pass" send_message_block
XTRA=',"last_assistant_message":"Paste this into the builder: step 3."'; want_block "last_assistant_message carries the hand-off phrase the transcript lacks -> block" nohand 'your reply says "Paste this into the builder"'
XTRA=',"last_assistant_message":"Done. Nothing was handed off."'; want_pass "last_assistant_message wins over the transcript's final text (which says Paste this into ...)" incident
XTRA=""

# ===== 8. the phrases: a pattern match, tight (table made by mk.py: reply -> blocks or not)
n=0; bad=0
while IFS=$'\t' read -r name want label <&3; do
  n=$((n + 1)); gate "$name"
  if [ "$want" = block ]; then
    r=$(py "$D/chk.py" block "$OUT" "wait gate: you handed off" </dev/null); [ "$r" = ok ] || { ko "phrase $label should block -> rc=$RC $r"; bad=$((bad + 1)); }
  else
    quiet || { ko "phrase $label should pass -> rc=$RC out='${OUT:0:120}'"; bad=$((bad + 1)); }
  fi
done 3< "$D/t/phrases.tsv"
[ "$bad" = 0 ] && ok "all $n hand-off phrases decide as listed (matched: paste this ... into / I'll ping, tell, notify, message, update you / let you know / check, come, report back; not matched: look-alikes, an idiom (I'll tell you what), code, a quote)"

# ===== 9. the reason: 6 lines, the watch.py command, the branch from .git/HEAD
gate incident; cmd=$(py "$D/chk.py" command "$OUT" </dev/null)
pre="bash \"$PL/hooks/py.sh\" \"$PL/hooks/watch.py\" --git origin "; suf=" --path <result file> --since <the commit you handed off at>"
case "$cmd" in "$pre"*"$suf") ok "the recommended command is bash \"<plugin>/hooks/py.sh\" \"<plugin>/hooks/watch.py\" --git origin <branch> --path <result file> --since <the commit you handed off at>, <plugin> the absolute dir of this file's plugin";; *) ko "recommended command: $cmd (wanted $pre... $suf)";; esac
g=$(py "$D/chk.py" guard "$OUT" </dev/null | py "$H/bash-guard.py" 2>&1); [ -z "$g" ] && ok "the plugin's own bash-guard allows the watch command the gate recommends (placeholders filled in)" || ko "bash-guard refused the recommended command: $g"
brcase() { # $1 = a project dir -> the recommended command, in a fresh state dir
  rm -rf "$HOME/.claude/smartuse/projects"; local pw; pw=$(wp "$1")
  IN=$(printf '{"hook_event_name":"Stop","session_id":"sid-test","transcript_path":"%s","cwd":"%s"}' "$(wp "$D/t/incident.jsonl")" "$pw")
  OUT=$(printf '%s' "$IN" | CLAUDE_PROJECT_DIR="$pw" py "$GATE" 2>&1); py "$D/chk.py" command "$OUT" </dev/null
}
mkdir -p "$D/br/.git" "$D/br/sub/dir"; printf 'ref: refs/heads/feat/step-3.1\n' > "$D/br/.git/HEAD"
c=$(brcase "$D/br"); case "$c" in *" --git origin feat/step-3.1 --path "*) ok "<branch> is read from .git/HEAD: feat/step-3.1";; *) ko "branch from .git/HEAD: $c";; esac
c=$(brcase "$D/br/sub/dir"); case "$c" in *" --git origin feat/step-3.1 --path "*) ok "... found from a subdirectory of the repo";; *) ko "branch from a subdirectory: $c";; esac
mkdir -p "$D/wt/real.git" "$D/wt/work"; printf 'ref: refs/heads/wip/waitgate\n' > "$D/wt/real.git/HEAD"; printf 'gitdir: ../real.git\n' > "$D/wt/work/.git"
c=$(brcase "$D/wt/work"); case "$c" in *" --git origin wip/waitgate --path "*) ok "... and from a worktree (.git is a file naming the git dir)";; *) ko "branch from a worktree: $c";; esac
for badhead in 'ref: refs/heads/a$(touch x)' 'ref: refs/heads/a;b' 'ref: refs/heads/a`b`' 'ref: refs/heads/-x' 'ref: refs/heads/a..b' '0123456789abcdef0123456789abcdef01234567' 'garbage'; do
  mkdir -p "$D/bad/.git"; printf '%s\n' "$badhead" > "$D/bad/.git/HEAD"; c=$(brcase "$D/bad")
  case "$c" in *" --git origin <branch> --path "*) ok "HEAD '$badhead' -> the placeholder <branch>, never the text (it goes into a command)";; *) ko "HEAD '$badhead' -> $c";; esac
done
r=$(py "$D/chk.py" imports "$GATE" </dev/null); [ "$r" = ok ] && ok "wait-gate.py: stdlib only (json os re sys time pathlib datetime, hashlib and winreg inside fit_key), no subprocess / socket / urllib, parses as the Python 3.9 grammar" || ko "wait-gate.py imports: $r"

# ===== 10. the state dir is the one ledger.py, until-done.py and heartbeat.py use (project_key copied, tested equal)
for sub in "plain" "with space.v1/x y" "a+b/c_d (e)"; do
  mkdir -p "$D/keys/$sub"; pw=$(wp "$D/keys/$sub"); rm -rf "$HOME/.claude/smartuse/projects"
  IN=$(printf '{"hook_event_name":"Stop","session_id":"sid-test","transcript_path":"%s","cwd":"%s"}' "$(wp "$D/t/send_message_block.jsonl")" "$pw")
  printf '%s' "$IN" | CLAUDE_PROJECT_DIR="$pw" py "$GATE" >/dev/null 2>&1
  lk=$(CLAUDE_PROJECT_DIR="$pw" py "$H/ledger.py" --state-dir </dev/null); lk=${lk##*[/\\]}; lk=${lk%$'\r'}
  got=$(ls "$HOME/.claude/smartuse/projects" 2>/dev/null); [ -n "$lk" ] && [ "$got" = "$lk" ] && [ -f "$HOME/.claude/smartuse/projects/$lk/wait.json" ] && ok "state dir for '$sub' equals ledger.py's --state-dir ($lk)" || ko "state dir for '$sub': the gate wrote '$got', ledger.py says '$lk'"
done

# ===== 10b. 0.7.1 F1: a long Windows path keeps its state. fit_key (one helper copied into the six hooks, tested equal below) keeps today's key while
# the state folder plus its longest file name fit (259 characters for a whole path on Windows, E1; 255 for one name elsewhere) and past that names the
# folder with the last 40 characters of the key, "-", and 12 hex of the sha1 of the whole key. A project path is keyed, never made: a path that does
# not exist reaches the limit without a deep folder. Every case runs in the temp HOME; the real ~/.claude/smartuse is checked at the end.
NT=$(py -c 'import os, sys; sys.stdout.write("1" if os.name == "nt" else "0")' </dev/null)   # the rule reads os.name: the long-path cases below are Windows-only where the key is under 255, the 300-character ones run everywhere
BL=$(py -c 'import os, sys, pathlib; sys.stdout.write(str(len(str(pathlib.Path(os.environ.get("HOME") or os.path.expanduser("~")) / ".claude" / "smartuse" / "projects"))))' </dev/null)   # the length of <HOME>/.claude/smartuse/projects as the hooks see it
PROJ10=$HOME/.claude/smartuse/projects
lp() { # $1 = a key length -> a project path (forward slashes, never made) whose key is that long: C:/p/xxx -> C--p-xxx (Windows), /p/xxx -> p-xxx
  local n s; if [ "$NT" = 1 ]; then n=$(( $1 - 5 )); else n=$(( $1 - 2 )); fi
  s=$(printf '%*s' "$n" ''); s=${s// /x}; if [ "$NT" = 1 ]; then printf 'C:/p/%s' "$s"; else printf '/p/%s' "$s"; fi
}
fname() { # $1 = a project path -> the folder name ledger.py --state-dir prints for it
  local o; o=$(CLAUDE_PROJECT_DIR="$1" py "$H/ledger.py" --state-dir </dev/null); o=${o##*[/\\]}; printf '%s' "${o%$'\r'}"
}
fire() { # $1 = hook (heartbeat|recall|wait-gate|until-done), $2 = a project path -> runs it once; FILE = the file it leaves in its state folder (until-done: it leaves none, it blocks on a routing.json put there)
  local hook=$1 pw=$2 ev o; FILE=""
  case "$hook" in
    heartbeat) FILE=status.json; ev="{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s1\",\"source\":\"startup\",\"cwd\":\"$pw\"}";;
    recall)    FILE=recall.json; ev="{\"hook_event_name\":\"SessionStart\",\"session_id\":\"sid-test\",\"source\":\"compact\",\"cwd\":\"$pw\"}";;
    wait-gate) FILE=wait.json;   ev="{\"hook_event_name\":\"Stop\",\"session_id\":\"sid-test\",\"transcript_path\":\"$(wp "$D/t/send_message_block.jsonl")\",\"cwd\":\"$pw\"}";;
    until-done) FILE=routing.json; ev="{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"cwd\":\"$pw\",\"stop_hook_active\":false}"
      o=$(CLAUDE_PROJECT_DIR="$pw" py "$H/ledger.py" --state-dir --create </dev/null 2>/dev/null) && [ -d "$o" ] && echo '{"active":true,"until_done":true,"units":[{"id":1,"title":"u","status":"pending"}]}' > "$o/routing.json";;
  esac
  printf '%s' "$ev" | CLAUDE_PROJECT_DIR="$pw" py "$H/$hook.py" > "$D/o10b" 2>&1
}
wrote() { # $1 = hook, $2 = a project path -> the folder name where the hook left its file ("" when nowhere); the state is reset first
  local d n; rm -rf "$PROJ10"; if [ -n "${PRESET_SHORT:-}" ]; then mkdir -p "$PROJ10/$PRESET_FULL" "$PROJ10/$PRESET_SHORT" && printf '{}' > "$PROJ10/$PRESET_SHORT/paid-runs.json"; [ -z "${PRESET_FCNT:-}" ] || printf '{}' > "$PROJ10/$PRESET_FULL/paid-runs.json"; fi   # 0.7.2 F2: a made full-key folder and a short-key folder holding the paid counter, put back before every hook (D9: PRESET_FCNT set, the full-key folder holds one too)
  fire "$1" "$2"
  for d in "$PROJ10"/*/; do
    if [ -f "${d}$FILE" ]; then
      if [ "$1" = until-done ] && ! grep -q '"block"' "$D/o10b"; then continue; fi   # until-done proves its folder by reading routing.json there and blocking
      n=${d%/}; printf '%s' "${n##*/}"; return
    fi
  done
}
same6() { # $1 = label, $2 = a project path: every hook that writes a state file names the folder ledger.py --state-dir names, and its file is there
  local want h got bad=""; want=$(fname "$2")
  for h in heartbeat recall wait-gate until-done; do got=$(wrote "$h" "$2"); [ -n "$want" ] && [ "$got" = "$want" ] || bad="$bad $h:'$got'"; done
  [ -z "$bad" ] && ok "$1: ledger.py, heartbeat.py, recall.py, until-done.py and wait-gate.py name one folder ($want)" || ko "$1: ledger.py names '$want' (${#want} characters), but these wrote elsewhere or nowhere:$bad"
}
if [ "$NT" = 1 ]; then LONGK=$(( 239 - BL )); FULLEDGE=$(( 194 - BL - 1 )); else LONGK=240; FULLEDGE=255; fi   # a key that puts the state folder at 240 characters (E1: no file reaches it on Windows) · the longest key that keeps its full name (dirlen 194 on Windows, 255 elsewhere)
# b: the same folder for a short, a long and a 300-character path
SHORTP=$(wp "$D/keys/plain"); [ -d "$D/keys/plain" ] || SHORTP=$(wp "$D/proj")
same6 "b short path" "$SHORTP"
if [ "$LONGK" -ge 20 ]; then same6 "b long path (key $LONGK, state folder $(( BL + 1 + LONGK )) characters)" "$(lp "$LONGK")"; else skip "b long path: HOME is $BL characters, too long to build a folder of 240"; fi
same6 "b 300-character path" "$(lp 300)"
# c: a short path, and a path at the edge of the limit, give today's key byte for byte (the suite's key() helper); one character more gives the short key
for p in "$SHORTP" "$(wp "$D/keys/with space.v1/x y")" "$(lp "$FULLEDGE")"; do
  [ "$(fname "$p")" = "$(key "$p")" ] && ok "c key unchanged for a ${#p}-character path: $(key "$p" | cut -c1-30)... (${#p}) = key() byte for byte" || ko "c key changed for '$p': ledger.py '$(fname "$p")', key() '$(key "$p")'"
done
EP=$(lp $(( FULLEDGE + 1 ))); EK=$(key "$EP"); EXP=$(py -c "import hashlib, sys; k = sys.argv[1]; sys.stdout.write(k[-40:].lstrip('-') + '-' + hashlib.sha1(k.encode()).hexdigest()[:12])" "$EK" </dev/null)
[ "$(fname "$EP")" = "$EXP" ] && [ "$(fname "$EP")" != "$EK" ] && ok "c one character past the edge ($(( FULLEDGE + 1 )) -> ${#EXP}): the last 40 characters, -, 12 hex of the sha1 of the whole key" || ko "c past the edge: wanted '$EXP', ledger.py says '$(fname "$EP")'"
# d: two long paths that differ only in the middle get two folders, each with its state
A=$(lp 300); B=${A:0:150}y${A:151}; rm -rf "$PROJ10"; fire wait-gate "$A"; fire wait-gate "$B"; na=$(fname "$A"); nb=$(fname "$B")
[ "$na" != "$nb" ] && [ "${na:0:$(( ${#na} - 13 ))}" = "${nb:0:$(( ${#nb} - 13 ))}" ] && [ "$(ls "$PROJ10" 2>/dev/null | wc -l | tr -d ' ')" = 2 ] && [ -f "$PROJ10/$na/wait.json" ] && [ -f "$PROJ10/$nb/wait.json" ] \
  && ok "d two 300-character paths that differ in the middle: two folders, the same last 40 characters, two hashes, each holds its wait.json" || ko "d middle-differing paths: ledger.py says '$na' and '$nb', folders: $(ls "$PROJ10" 2>&1 | tr '\n' ' ')"
# e: an existing full-key folder is still used while a file fits in it (232 characters on Windows), and left behind beyond (a longer one was made by mkdir and no file reached it, E1)
if [ "$NT" = 1 ]; then
  LPON=$(py -c 'import sys
try:
    import winreg
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\FileSystem") as k:
        sys.stdout.write("1" if winreg.QueryValueEx(k, "LongPathsEnabled")[0] == 1 else "0")
except Exception:
    sys.stdout.write("0")' </dev/null)   # D8: this machine's long-path switch (read only): with it on, the 233-character folder is kept too
  for L in 220 232 233; do
    ep=$(lp $(( L - BL - 1 ))); full=$(key "$ep"); rm -rf "$PROJ10"; before=$(fname "$ep"); mkdir -p "$PROJ10/$full"; after=$(fname "$ep"); fire wait-gate "$ep"
    if [ "$L" -le 232 ] || [ "$LPON" = 1 ]; then
      [ "$before" != "$full" ] && [ "$after" = "$full" ] && [ -f "$PROJ10/$full/wait.json" ] && ok "e state folder of $L characters: new without its folder it gets the short key, with its folder it keeps the full key and the state goes there" || ko "e folder of $L: before '$before', after '$after', wait.json in the full folder: $([ -f "$PROJ10/$full/wait.json" ] && echo yes || echo no)"
    else
      [ "$after" != "$full" ] && [ -f "$PROJ10/$after/wait.json" ] && [ ! -f "$PROJ10/$full/wait.json" ] && ok "e an existing folder of $L characters (no file fits in it) is left behind empty, the short key is used" || ko "e folder of $L: ledger.py says '$after', wait.json: short $([ -f "$PROJ10/$after/wait.json" ] && echo yes || echo no), full $([ -f "$PROJ10/$full/wait.json" ] && echo yes || echo no)"
    fi
  done
else skip "e (not Windows: only the 255-character name limit applies and an existing folder cannot be longer than it; fit_key's rules 2 and 3 are in case f)"; fi
# e2: 0.7.2 F2 (D-YK19): a project on the short key has a paid counter there; a shell then makes its full-key folder (220 characters: a file fits in it). The counter wins:
# ledger.py and the four hooks that write a state file (bash-guard.py has its own cases: case f's table and paid-guard-test.sh 39b) still name the short folder, and the made folder stays empty
# (before, they moved to it and the paid count restarted). e3 (D9): when the full-key folder holds a counter too (a folder copy planted one in the short folder), the full folder stays.
same6k() { # $1 = label, $2 = a project path whose full-key folder is made and whose short-key folder holds paid-runs.json; $3 = both: the full-key folder holds a counter too, so it is the one named
  local want h got bad=""; PRESET_FULL=$(key "$2"); [ "${3:-}" = both ] && PRESET_FCNT=1
  PRESET_SHORT=$(py -c "import hashlib, sys; k = sys.argv[1]; sys.stdout.write((k[-40:] + '-' + hashlib.sha1(k.encode()).hexdigest()[:12]).lstrip('-'))" "$PRESET_FULL" </dev/null)
  want=$PRESET_SHORT; [ "${3:-}" = both ] && want=$PRESET_FULL
  rm -rf "$PROJ10"; mkdir -p "$PROJ10/$PRESET_FULL" "$PROJ10/$PRESET_SHORT" && printf '{}' > "$PROJ10/$PRESET_SHORT/paid-runs.json"; [ "${3:-}" = both ] && printf '{}' > "$PROJ10/$PRESET_FULL/paid-runs.json"
  [ "$(fname "$2")" = "$want" ] || bad="$bad ledger:'$(fname "$2")'"
  for h in heartbeat recall wait-gate until-done; do got=$(wrote "$h" "$2"); [ "$got" = "$want" ] || bad="$bad $h:'$got'"; done
  [ "${3:-}" = both ] || [ -z "$(ls -A "$PROJ10/$PRESET_FULL" 2>/dev/null)" ] || bad="$bad full-folder-not-empty"
  PRESET_SHORT=; PRESET_FULL=; PRESET_FCNT=
  if [ "${3:-}" = both ]; then [ -z "$bad" ] && ok "$1: ledger.py, heartbeat.py, recall.py, until-done.py and wait-gate.py all name the full-key folder ($want)" || ko "$1: wanted '$want', but:$bad"
  else [ -z "$bad" ] && ok "$1: ledger.py, heartbeat.py, recall.py, until-done.py and wait-gate.py all name the short folder ($want), and the made full-key folder stays empty" || ko "$1: wanted '$want', but:$bad"; fi
}
if [ "$NT" = 1 ]; then
  same6k "e2 state folder of 220 characters, its full-key folder made, a paid counter in the short-key folder" "$(lp $(( 220 - BL - 1 )))"
  same6k "e3 state folder of 220 characters, a paid counter in the full-key folder AND in the short-key folder (D9)" "$(lp $(( 220 - BL - 1 )))" both
else skip "e2 (not Windows: a short key arises only past 255 characters, where its full-key folder cannot be made; the rule itself is in case f g5)"; fi
rm -rf "$PROJ10"
# f: fit_key is one helper, byte for byte in the six hooks (read with ast, no hook imported), and agrees with the rule on a table, for nt True and False
cat > "$D/fk.py" <<'PY'
import ast, hashlib, os, shutil, sys, tempfile, types
H = sys.argv[1]
FILES = ["heartbeat.py", "ledger.py", "recall.py", "until-done.py", "wait-gate.py", "bash-guard.py"]
srcs = {}
for f in FILES:
    text = open(os.path.join(H, f), encoding="utf-8").read()
    tree = ast.parse(text, feature_version=(3, 9))
    fns = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "fit_key"]
    if len(fns) != 1:
        print("%s: %d module-level fit_key (wanted 1)" % (f, len(fns))); sys.exit()
    # 0.7.2 F4: every import in the whole module, module-level try/if and nested blocks included, not only the top-level statements.
    # One naming hashlib must sit inside a function; one naming winreg must sit inside fit_key. Anything else crashes the hook on Linux CI.
    def walk(node, anc):
        for ch in ast.iter_child_nodes(node):
            if isinstance(ch, (ast.Import, ast.ImportFrom)):
                roots = {a.name.split(".")[0] for a in ch.names} if isinstance(ch, ast.Import) else {(ch.module or "").split(".")[0]}
                if "hashlib" in roots and not any(isinstance(a, (ast.FunctionDef, ast.AsyncFunctionDef)) for a in anc):
                    print("%s: hashlib imported outside a function (line %d)" % (f, ch.lineno)); sys.exit()
                if "winreg" in roots and not any(a is fns[0] for a in anc):
                    print("%s: winreg imported outside fit_key (line %d)" % (f, ch.lineno)); sys.exit()
            walk(ch, anc + [ch])
    walk(tree, [tree])
    if not any(isinstance(n, ast.Import) and any(a.name == "hashlib" for a in n.names) for n in ast.walk(fns[0])):
        print("%s: fit_key does not import hashlib inside itself" % f); sys.exit()
    srcs[f] = ast.get_source_segment(text, fns[0])
if len(set(srcs.values())) != 1:
    print("fit_key differs: %s" % [f for f in FILES if srcs[f] != srcs[FILES[0]]]); sys.exit()
ns = {"os": os}
exec(srcs[FILES[0]], ns)
fit_key = ns["fit_key"]
# D8: fit_key reads HKLM\SYSTEM\CurrentControlSet\Control\FileSystem LongPathsEnabled through `import winreg`. A fake winreg module stands in for the real one
# for the whole run (the table must not depend on this machine's switch, and nothing here reads or writes the real registry): .value is what the value says,
# .boom makes any read raise, .reads counts the reads.
class FakeReg(types.ModuleType):
    HKEY_LOCAL_MACHINE = 1
    value, boom, reads, path = 0, False, 0, None
    class _Key:
        def __enter__(self): return self
        def __exit__(self, *a): return False
    def OpenKey(self, root, sub, *a):
        self.reads += 1; self.path = (root, sub)
        if self.boom: raise OSError("registry read refused")
        return self._Key()
    def QueryValueEx(self, key, name):
        if self.boom: raise OSError("registry read refused")
        if name != "LongPathsEnabled": raise FileNotFoundError(name)
        return (self.value, 4)
reg = FakeReg("winreg"); reg.value = 0
real_winreg = sys.modules.get("winreg"); sys.modules["winreg"] = reg
real_hashlib = sys.modules["hashlib"]
real_isdir = os.path.isdir
tmp = tempfile.mkdtemp(prefix="fitkey")
try:
    base = os.path.join(tmp, "projects"); os.makedirs(base); B = len(base)
    def full_of(dirlen, ch="x"):   # a key that makes the state folder dirlen characters
        return ch * (dirlen - B - 1)
    def short_of(full):
        return (full[-40:] + "-" + hashlib.sha1(full.encode()).hexdigest()[:12]).lstrip("-")   # never starts with "-" (an all-dash tail gives the 12 hex alone)
    bad = []
    def want(label, nt, full, exists, expect):
        if exists:
            os.makedirs(os.path.join(base, full), exist_ok=True)
        got = fit_key(full, base, nt)
        exp = full if expect == "full" else short_of(full)
        if got != exp:
            bad.append("%s nt=%s: got %r wanted the %s key" % (label, nt, got[:30] + "..." + str(len(got)), expect))
    for nt in (True, False):
        want("20 characters", nt, "C--p-" + "a" * 15, False, "full")
        want("dirlen 194", nt, full_of(194, "a"), False, "full")
        want("dirlen 195", nt, full_of(195, "b"), False, "short" if nt else "full")
        want("255 characters", nt, "c" * 255, False, "short" if nt else "full")
        want("256 characters", nt, "d" * 256, False, "short")
        want("dash tail", nt, "e" * 200 + "-" * 40, False, "short" if nt else "full")
    want("existing, dirlen 232", True, full_of(232, "f"), True, "full")
    want("existing, dirlen 233", True, full_of(233, "g"), True, "short")
    want("existing, dirlen 233", False, full_of(233, "h"), True, "full")
    want("existing, dirlen 220", True, full_of(220, "i"), True, "full")
    s = fit_key("j" * 300, base, True)
    if len(s) != 53 or s != short_of("j" * 300):
        bad.append("short key shape: %r" % s)
    if fit_key("k" * 300, None, True) != "k" * 300 or fit_key("k" * 300, 5, False) != "k" * 300:
        bad.append("fit_key must not raise: an error returns the full key")
    # D8: Windows long paths on keeps an existing full-key folder of any length (the fake winreg above; the folder is faked through os.path.isdir, a 248-character folder cannot be made without the switch)
    def exists_only(path):
        os.path.isdir = lambda p: p == path or real_isdir(p)
    def lp_case(label, value, boom, full, expect, reads=None):
        reg.value, reg.boom, reg.reads = value, boom, 0
        exists_only(base + os.sep + full)
        got = fit_key(full, base, True)
        os.path.isdir = real_isdir
        exp = full if expect == "full" else short_of(full)
        if got != exp:
            bad.append("%s: got %r wanted the %s key" % (label, got[:30] + "..." + str(len(got)), expect))
        if reads is not None and reg.reads != reads:
            bad.append("%s: the registry was read %d times, wanted %d" % (label, reg.reads, reads))
    f248 = full_of(248, "m")
    lp_case("long paths on, existing folder of 248", 1, False, f248, "full", 1)
    lp_case("long paths off, existing folder of 248", 0, False, f248, "short", 1)
    lp_case("registry read raises, existing folder of 248", 1, True, f248, "short", 1)
    lp_case("long paths on, existing folder of 233", 1, False, full_of(233, "n"), "full", 1)
    lp_case("long paths on, existing folder of 232 (fits: the switch is not read)", 1, False, full_of(232, "o"), "full", 0)
    reg.value, reg.boom, reg.reads = 1, False, 0
    if fit_key(f248, base, True) != short_of(f248) or reg.reads != 0:
        bad.append("long paths on but no folder: the short key, and the switch is not read")
    reg.value, reg.boom, reg.reads = 1, False, 0
    exists_only(base + os.sep + "p" * 300)
    got = fit_key("p" * 300, base, False); os.path.isdir = real_isdir
    if got != "p" * 300 or reg.reads != 0:
        bad.append("not Windows: the existing folder is kept and the registry is not read")
    reg.value, reg.boom, reg.reads = 0, False, 0
    # the common path imports no hashlib and runs no sha1; the short path does (a recording stand-in for hashlib)
    calls = []
    stub = types.ModuleType("hashlib")
    stub.sha1 = lambda b: (calls.append(1), real_hashlib.sha1(b))[1]
    sys.modules["hashlib"] = stub
    try:
        got_full = fit_key("C--p-" + "a" * 15, base, True)
        n_full = len(calls)
        got_short = fit_key("t" * 300, base, True)
        n_short = len(calls)
    finally:
        sys.modules["hashlib"] = real_hashlib
    if got_full != "C--p-" + "a" * 15 or n_full != 0:
        bad.append("a short key must come back as itself with no sha1 run (sha1 calls: %d)" % n_full)
    if got_short != short_of("t" * 300) or n_short != 1:
        bad.append("a long key must come back shortened by one sha1 run (calls: %d)" % n_short)
    # 0.7.2 F2 (D-YK19): past the length test, an existing full-key folder is kept unless the short-key folder already holds paid-runs.json (the counter
    # wins: a made full folder must not restart a paid count). The short folder and its counter are real files in the temp base; a folder too long to make
    # is faked through os.path.isdir as above; the registry is the fake winreg.
    def counter_for(full):      # a short-key folder holding the paid counter, as the hook leaves it
        d = os.path.join(base, short_of(full)); os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "paid-runs.json"), "w").write("{}")
    def g_case(label, nt, value, full, made, fake, counter, expect, full_counter=False):
        reg.value, reg.boom, reg.reads = value, False, 0
        if made: os.makedirs(os.path.join(base, full), exist_ok=True)
        if counter: counter_for(full)
        if full_counter: open(os.path.join(base, full, "paid-runs.json"), "w").write("{}")   # the full-key folder holds a counter too (0.7.2 D9)
        if fake: exists_only(base + os.sep + full)
        try:
            got = fit_key(full, base, nt)
        finally:
            os.path.isdir = real_isdir
        exp = full if expect == "full" else short_of(full)
        if got != exp:
            bad.append("%s: got %r wanted the %s key" % (label, got[:30] + "..." + str(len(got)), expect))
        reg.value = 0
    g_case("g1 nt, existing folder at 220 + a short folder with a counter", True, 0, full_of(220, "q"), True, False, True, "short")
    g_case("g2 nt, existing folder at 220, no counter beside it", True, 0, full_of(220, "r"), True, False, False, "full")
    g_case("g2b nt, existing folder at 232, no counter beside it", True, 0, full_of(232, "R"), True, False, False, "full")
    g_case("g3 nt, long paths on, existing folder at 248 + a counter", True, 1, full_of(248, "s"), False, True, True, "short")
    g_case("g3b nt, long paths on, existing folder at 248, no counter", True, 1, full_of(248, "S"), False, True, False, "full")
    g_case("g4 nt, no full folder + a counter", True, 0, full_of(220, "t"), False, False, True, "short")
    g_case("g4b not nt, no full folder + a counter", False, 0, "v" * 300, False, False, True, "short")
    g_case("g5 not nt, a 300-character folder (faked) + a counter", False, 0, "w" * 300, False, True, True, "short")
    g_case("g5b not nt, a 300-character folder (faked), no counter", False, 0, "W" * 300, False, True, False, "full")
    g_case("g5c not nt, a 256-character key whose folder exists (faked) + a counter", False, 0, "y" * 256, False, True, True, "short")
    g_case("g5d nt, a counter for a path that fits: the full key (not long: the counter is not looked at)", True, 0, full_of(194, "z"), True, False, True, "full")
    # 0.7.2 D9 (a folder copy can plant a counter in the short folder): the short key wins only when the short folder holds a counter AND the full-key folder does not
    g_case("g9 nt, existing folder at 220 holding a counter + a short folder with a counter", True, 0, full_of(220, "1"), True, False, True, "full", True)
    g_case("g9b nt, existing folder at 232 holding a counter + a short folder with a counter", True, 0, full_of(232, "2"), True, False, True, "full", True)
    g_case("g10 nt, existing folder at 220 holding a counter, no short counter", True, 0, full_of(220, "3"), True, False, False, "full", True)
    # a counter beside a folder that is not a file named paid-runs.json (a folder of that name) does not count
    dd = os.path.join(base, short_of(full_of(220, "x")), "paid-runs.json"); os.makedirs(dd, exist_ok=True)
    g_case("g1b nt, existing folder at 220 + a FOLDER named paid-runs.json in the short folder (no counter)", True, 0, full_of(220, "x"), True, False, False, "full")
    # g6: a short key whose folder exists makes no isdir, no isfile and no sha1 call (today it stats on every call; the common path stays free)
    isdir_calls, isfile_calls, sha_calls = [], [], []
    real_isfile = os.path.isfile
    os.path.isdir = lambda p: (isdir_calls.append(p), real_isdir(p))[1]
    os.path.isfile = lambda p: (isfile_calls.append(p), real_isfile(p))[1]
    stub2 = types.ModuleType("hashlib"); stub2.sha1 = lambda b: (sha_calls.append(1), real_hashlib.sha1(b))[1]
    sys.modules["hashlib"] = stub2
    try:
        k20 = "C--p-" + "g" * 15
        os.makedirs(os.path.join(base, k20), exist_ok=True)
        got6 = fit_key(k20, base, True); got6b = fit_key(k20, base, False)
        n6 = (len(isdir_calls), len(isfile_calls), len(sha_calls))
        # g7: a kept folder (long key, folder exists, no counter) costs one sha1 run; the answer is the full key
        kk = full_of(220, "k"); os.makedirs(os.path.join(base, kk), exist_ok=True)
        del sha_calls[:]
        got7 = fit_key(kk, base, True); n7 = len(sha_calls)
        # g8: a read that raises (isfile) never escapes: the full key comes back
        def boom_isfile(p): raise OSError("stat refused")
        os.path.isfile = boom_isfile
        got8 = fit_key(kk, base, True)
    finally:
        os.path.isdir = real_isdir; os.path.isfile = real_isfile; sys.modules["hashlib"] = real_hashlib
    if got6 != k20 or got6b != k20 or n6 != (0, 0, 0):
        bad.append("g6 a 20-character key whose folder exists: got %r, isdir/isfile/sha1 calls %r (wanted none)" % (got6, n6))
    if got7 != kk or n7 != 1:
        bad.append("g7 a kept folder: got the full key %s, sha1 runs %d (wanted 1)" % (got7 == kk, n7))
    if got8 != kk:
        bad.append("g8 isfile raises: fit_key must return the full key, got %r" % got8[:30])
    # the short key never starts with "-": an all-dash tail leaves the 12 hex alone
    dk = "u" * 200 + "-" * 60
    for nt in (True, False):
        got = fit_key(dk, base, nt)
        if got.startswith("-") or got != hashlib.sha1(dk.encode()).hexdigest()[:12]:
            bad.append("all-dash tail nt=%s: got %r" % (nt, got))
    print("ok" if not bad else "; ".join(bad))
finally:
    sys.modules["hashlib"] = real_hashlib
    os.path.isdir = real_isdir
    if real_winreg is None: sys.modules.pop("winreg", None)
    else: sys.modules["winreg"] = real_winreg
    shutil.rmtree(tmp, ignore_errors=True)
PY
r=$(py "$D/fk.py" "$H" </dev/null 2>&1); [ "$r" = ok ] && ok "f fit_key: one module-level function, hashlib imported inside it only, the six sources identical (ast, no hook imported), and the same answers for nt True and False on the table (20 characters; dirlen 194/195; 255/256 characters; an existing folder at 220, 232, 233); D8: with a fake winreg, Windows long paths on keeps an existing folder of 248 and off, or a read that raises, gives the short key; the switch is read only when the length test fails; no hashlib on the common path; a short key never starts with -; 0.7.2 F2 g1-g8: a short-key folder holding paid-runs.json wins over an existing full-key folder, on Windows (also with long paths on) and elsewhere, and a kept folder costs one sha1 and no counter is looked for on the common path; D9 g9-g10: not when the full-key folder holds a counter too" || ko "f fit_key: $r"
[ "$(ls "$REAL_HOME/.claude/smartuse/projects" 2>/dev/null | grep -c 'xxxxxxxx')" = 0 ] && ok "F1: the real ~/.claude/smartuse gained no folder from these cases (the temp HOME took them all)" || ko "F1: a test folder reached the real ~/.claude/smartuse/projects"

# ===== 11. what the owner's session gets: the Stop-hook JSON until-done.py prints; the hook is registered
gate incident; py -c "import json,sys; d=json.loads(sys.argv[1]); assert d['decision']=='block' and isinstance(d['reason'],str) and sorted(d)==['decision','reason'] and all(ord(c)<128 for c in sys.argv[1]), d" "$OUT" 2>/dev/null \
  && ok "the block is {\"decision\":\"block\",\"reason\":...} on one line with ASCII escapes (no console re-encoding needed)" || ko "block shape: $OUT"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && ok "exactly one line on stdout" || ko "stdout is not one line: $OUT"
r=$(py "$D/chk.py" hooks "$H/hooks.json" </dev/null); [ "$r" = ok ] && ok "hooks.json: Stop runs ledger, until-done, wait-gate (timeout 10), heartbeat" || ko "hooks.json: $r"
# ===== 6. 0.6.1 F6: the level. Light (the default, also when Claude Code passes no option) leaves at once: nothing read, nothing printed, nothing
# written. The gate runs when Strict guards is on, or the Wait gate option is on; a value that is neither on nor off counts as on (strict).
# The adapter's `wait_gate: off` still wins per project. The options are set here in the main shell so a failed case still counts.
rm -f "$D/proj/.claude/smartuse.local.md"
export CLAUDE_PLUGIN_OPTION_STRICT=false; unset CLAUDE_PLUGIN_OPTION_WAIT_GATE
want_pass "F6 light (Strict off, Wait gate unset): the incident passes, nothing printed" incident
[ ! -e "$P" ] && ok "F6 light writes nothing (no marker, no wait.json)" || ko "F6 light wrote: $(ls "$P")"
unset CLAUDE_PLUGIN_OPTION_STRICT
want_pass "F6 no option at all (Claude Code passed none): light, the incident passes" incident
export CLAUDE_PLUGIN_OPTION_STRICT=false CLAUDE_PLUGIN_OPTION_WAIT_GATE=on
want_block "F6 the Wait gate option alone turns the gate on" incident "wait gate: you handed off"
export CLAUDE_PLUGIN_OPTION_STRICT=false CLAUDE_PLUGIN_OPTION_WAIT_GATE=0
want_pass "F6 Strict off and Wait gate 0: the gate is off" incident
export CLAUDE_PLUGIN_OPTION_STRICT=maybe; unset CLAUDE_PLUGIN_OPTION_WAIT_GATE
want_block "F6 a Strict value that is neither on nor off counts as strict: the gate is on" incident "wait gate: you handed off"
export CLAUDE_PLUGIN_OPTION_STRICT=true
mkdir -p "$D/proj/.claude"; printf -- '---\nwait_gate: off\n---\n' > "$D/proj/.claude/smartuse.local.md"
want_pass "F6 the adapter's wait_gate: off beats Strict" incident
export CLAUDE_PLUGIN_OPTION_STRICT=false CLAUDE_PLUGIN_OPTION_WAIT_GATE=on
want_pass "F6 ... and beats the Wait gate option" incident
rm -f "$D/proj/.claude/smartuse.local.md"; export CLAUDE_PLUGIN_OPTION_STRICT=true; unset CLAUDE_PLUGIN_OPTION_WAIT_GATE
want_block "F6 strict: the incident replay blocks once, as in 0.6.0" incident "wait gate: you handed off"
CI="$H/../../../.github/workflows/ci.yml"
if [ -f "$CI" ]; then
  grep -q 'plugins/smartuse/hooks/wait-gate.py' "$CI" && grep -q 'bash plugins/smartuse/hooks/tests/wait-gate-test.sh' "$CI" && ok "ci.yml: wait-gate.py is in the py_compile step and this suite has a step of its own" || ko "ci.yml lacks wait-gate.py or the suite's step"
fi
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
