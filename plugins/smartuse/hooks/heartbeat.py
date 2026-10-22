#!/usr/bin/env python3
"""heartbeat.py — smartuse heartbeat: "is Claude working, waiting on an agent, waiting on me, or stalled?" in ONE line.
Deterministic, 0 model tokens, no network, stdlib only.

Hook (stdin = the event JSON; prints nothing; exit 0 always): SessionStart · UserPromptSubmit · PreToolUse · PostToolUse ·
SubagentStart · SubagentStop · Notification (idle_prompt | permission_prompt) · Stop · SessionEnd. Every event updates
~/.claude/smartuse/projects/<repo dir name>/status.json (same state dir as ledger.py; atomic tmp + os.replace):
  session_id · started (first event of the session) · updated (every event) · source (SessionStart's source) ·
  turn (UserPromptSubmit count) · turn_ended (Stop sets it; UserPromptSubmit / PreToolUse / PostToolUse clear it) ·
  waiting_since (when the wait on the human began: Stop, idle_prompt or permission_prompt; cleared when work resumes) ·
  tool_calls (this turn, reset on UserPromptSubmit) · tool_running {name, tool_use_id, since} (PreToolUse sets, any
  PostToolUse clears) · last_tool {name, at} · agents {agent_id: {type, since}} (SubagentStart adds, SubagentStop removes;
  entries older than 3 h are ignored when rendering) · agents_done · notification (idle_prompt | permission_prompt | null;
  Notification sets, UserPromptSubmit / PreToolUse / PostToolUse / Stop clear) · ended + end_reason (SessionEnd).
SessionStart resets the file for the new session (counters at 0) — except source "compact" of the same session, which
keeps the state (an agent may be mid-flight). An event whose session_id differs from the file's starts fresh: ONE FILE
PER REPO, LAST WRITER WINS — two sessions in the same repo overwrite each other's line (session_id says whose it is).
A SessionEnd of another session never overwrites the live one. Stop sets turn_ended unless the until-done gate will
refuse the stop (active until_done run with units pending / running / fail, no needs_human, blocks < max_blocks, not
stop_hook_active) — then the turn continues and the line stays "working". Parallel tool calls share one
tool_running slot (the latest PreToolUse wins); the counters are best-effort under a lock.

Render (no model tokens):
  --line                 one line, first rule wins: NEEDS YOU (routing.json needs_human) · session ended · waiting on you:
                         permission prompt · working · waiting on agent · working · <tool> running · waiting on you (turn ended,
                         idle_prompt, or no prompt yet) · working · last <tool> (prefixed "stalled? " + "no activity <ago>" after SMARTUSE_STALL_MIN
                         minutes, default 5, without any event). Then "· step <id>/<n> <tier>·<model> "<title>"" when
                         routing.json has a running unit and "· loop block <blocks>/<max>" in an until-done run.
  --json                 status.json + the derived "state" (needs_human | ended | waiting_on_you | waiting_on_agent |
                         working | stalled | none) and "line".
  --statusline           for ~/.claude/settings.json statusLine: reads Claude Code's status JSON on stdin and prints
                         "[<model>] ctx <used>% · $<cost> · <line without the smartuse prefix>".
  --subagent-statusline  for the plugin's subagentStatusLine: one JSON line per task {"id", "content"}.
Never blocks a turn. Any error -> exit 0 silently (a heartbeat must never stop the work).
"""
import json, os, sys, datetime, pathlib

HOME = pathlib.Path(os.path.expanduser("~"))
EVENTS = {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop",
          "Notification", "Stop", "SessionEnd"}
WAITS = ("idle_prompt", "permission_prompt")
STALE_AGENT_S = 3 * 3600
PREFIX = "smartuse · "


def utcnow():
    return datetime.datetime.now(datetime.timezone.utc)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_ts(s):
    try:
        t = datetime.datetime.fromisoformat(str(s).replace("Z", "+00:00"))
        return t if t.tzinfo else t.replace(tzinfo=datetime.timezone.utc)
    except Exception:
        return None


def fmt_dur(seconds):
    """8s · 4m12s · 1h03m"""
    s = max(0, int(seconds))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{(s % 3600) // 60:02d}m"


def age_s(ts, now):
    t = parse_ts(ts)
    return (now - t).total_seconds() if t else 0


def since(ts, now):
    return fmt_dur(age_s(ts, now))


def oneline(text, n):
    return " ".join(str(text or "").split())[:n]


def to_int(v, default=0):
    try:
        return int(v)
    except Exception:
        return default


def project_dir(data=None):
    return pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or (data or {}).get("cwd") or os.getcwd())


def state_dir(project, create=False):
    """Per-project state lives under the user's home, never inside the repo (same rule as ledger.py)."""
    d = HOME / ".claude" / "smartuse" / "projects" / project.name
    if create:
        d.mkdir(parents=True, exist_ok=True)
    return d


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def read_dict(path):
    d = read_json(path)
    return d if isinstance(d, dict) else None


def write_json(path, obj):
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def lock(sdir):
    """Best-effort exclusive lock so two hooks firing at once (parallel tool calls) do not lose each other's update.
    Released when the fd closes; no fcntl (Windows) -> unlocked, last writer wins."""
    try:
        import fcntl
        fd = os.open(str(sdir / "status.lock"), os.O_CREAT | os.O_RDWR, 0o644)
        fcntl.flock(fd, fcntl.LOCK_EX)
        return fd
    except Exception:
        return None


def unlock(fd):
    try:
        if fd is not None:
            os.close(fd)
    except Exception:
        pass


# ---------------------------------------------------------------- state machine

def fresh(sid, now):
    return {"session_id": sid, "started": iso(now), "updated": iso(now), "source": None, "turn": 0, "turn_ended": False,
            "waiting_since": None, "tool_calls": 0, "tool_running": None, "last_tool": None, "agents": {},
            "agents_done": 0, "notification": None, "ended": False, "end_reason": None}


def live_agents(st, now):
    """The agents still counted: SubagentStop missed for 3 h (crash, kill) -> the entry is ignored."""
    out = {}
    for aid, a in (st.get("agents") or {}).items():
        if isinstance(a, dict):
            t = parse_ts(a.get("since"))
            if t is None or (now - t).total_seconds() <= STALE_AGENT_S:
                out[aid] = a
    return out


def running_units(r):
    units = [u for u in (r.get("units") or []) if isinstance(u, dict)] if r else []
    return units, [u for u in units if u.get("status") == "running"]


def active_routing(sdir):
    r = read_dict(sdir / "routing.json")
    return r if r and r.get("active") else None


def gate_will_block(sdir, data):
    """Mirror of until-done.py's unit rule: the Stop gate refuses the stop while an active until_done run has units
    pending / running / fail. The gate's check command cannot be predicted here: when only the check fails the line
    says "waiting on you" until the next tool call clears it."""
    if data.get("stop_hook_active"):
        return False
    r = active_routing(sdir)
    if not r or not r.get("until_done") or r.get("needs_human"):
        return False
    if to_int(r.get("blocks")) >= to_int(r.get("max_blocks"), 6):
        return False
    units, _ = running_units(r)
    return any((u.get("status") or "pending") in ("pending", "running", "fail") for u in units)


def resume(st):
    st["turn_ended"] = False
    st["waiting_since"] = None
    st["notification"] = None


def apply(st, ev, data, now, sdir):
    """One event -> the new status (None = leave the file alone)."""
    sid = data.get("session_id")
    if ev == "SessionStart":
        if not (st and data.get("source") == "compact" and st.get("session_id") == sid):
            st = fresh(sid, now)
        st["source"] = data.get("source")
    elif st is None or st.get("session_id") != sid:
        if ev == "SessionEnd" and st is not None:
            return None   # a dying session never overwrites the live one
        st = fresh(sid, now)   # hooks installed mid-session, or another session in this repo: last writer wins
    st["updated"] = iso(now)
    if ev == "UserPromptSubmit":
        st["turn"] = to_int(st.get("turn")) + 1
        st["tool_calls"] = 0
        st["tool_running"] = None
        resume(st)
    elif ev == "PreToolUse":
        st["tool_calls"] = to_int(st.get("tool_calls")) + 1
        st["tool_running"] = {"name": data.get("tool_name") or "tool", "tool_use_id": data.get("tool_use_id"), "since": iso(now)}
        resume(st)
    elif ev == "PostToolUse":
        name = data.get("tool_name") or (st.get("tool_running") or {}).get("name") or "tool"
        st["last_tool"] = {"name": name, "at": iso(now)}
        st["tool_running"] = None
        resume(st)
    elif ev == "SubagentStart":
        agents = live_agents(st, now)
        agents[str(data.get("agent_id") or f"agent-{int(now.timestamp())}")] = {"type": data.get("agent_type") or "agent", "since": iso(now)}
        st["agents"] = agents
    elif ev == "SubagentStop":
        agents = st.get("agents") or {}
        agents.pop(str(data.get("agent_id")), None)
        st["agents"] = agents
        st["agents_done"] = to_int(st.get("agents_done")) + 1
    elif ev == "Notification":
        nt = data.get("notification_type")
        if nt in WAITS:
            st["notification"] = nt
            st["waiting_since"] = st.get("waiting_since") or iso(now)
    elif ev == "Stop":
        st["tool_running"] = None
        st["notification"] = None
        if not gate_will_block(sdir, data):
            st["turn_ended"] = True
            st["waiting_since"] = st.get("waiting_since") or iso(now)
    elif ev == "SessionEnd":
        st["ended"] = True
        st["end_reason"] = data.get("reason")
        st["tool_running"] = None
    return st


def on_event():
    try:
        data = json.load(sys.stdin)
        if not isinstance(data, dict):
            return
        ev = data.get("hook_event_name") or ""
        if ev not in EVENTS:
            return
        now = utcnow()
        sdir = state_dir(project_dir(data), create=True)
        path = sdir / "status.json"
        fd = lock(sdir)
        try:
            st = apply(read_dict(path), ev, data, now, sdir)
            if st is not None:
                write_json(path, st)
        finally:
            unlock(fd)
    except Exception:
        pass


# ---------------------------------------------------------------- rendering

def stall_min():
    try:
        return max(0.0, float(os.environ.get("SMARTUSE_STALL_MIN") or 5))
    except Exception:
        return 5.0


def routing_suffix(r):
    if not r:
        return ""
    units, running = running_units(r)
    s = ""
    if running:
        u = running[0]
        tm = "·".join(str(x) for x in (u.get("tier"), u.get("model")) if x)
        s += f" · step {u.get('id')}/{len(units)}" + (f" {tm}" if tm else "") + (f' "{oneline(u["title"], 30)}"' if u.get("title") else "")
    if r.get("until_done"):
        s += f" · loop block {to_int(r.get('blocks'))}/{to_int(r.get('max_blocks'), 6)}"
    return s


def render(sdir, now=None):
    """-> {"state", "line" (with the smartuse prefix), "short" (without), "status"}"""
    now = now or utcnow()
    r = active_routing(sdir)
    st = read_dict(sdir / "status.json")
    flag, state = "", ""
    if r and r.get("needs_human"):
        state, body = "needs_human", "NEEDS YOU: " + oneline(r["needs_human"], 80)
    elif st is None:
        state, body = "none", f"no activity recorded for {sdir.name}"
    elif st.get("ended"):
        state, body = "ended", f"session ended {since(st.get('updated'), now)} ago"
    elif st.get("notification") == "permission_prompt":
        state, body = "waiting_on_you", f"waiting on you: permission prompt · {since(st.get('waiting_since') or st.get('updated'), now)}"
    else:
        agents = sorted(live_agents(st, now).items(), key=lambda kv: str(kv[1].get("since") or ""))
        tr = st.get("tool_running") if isinstance(st.get("tool_running"), dict) else None
        lt = st.get("last_tool") if isinstance(st.get("last_tool"), dict) else None
        calls = to_int(st.get("tool_calls"))
        n_calls = f"{calls} call{'' if calls == 1 else 's'} this turn"
        if agents:
            a = agents[0][1]
            state, body = "waiting_on_agent", f"working · waiting on agent: {a.get('type') or 'agent'} {since(a.get('since'), now)}"
            if len(agents) > 1:
                body += f", {len(agents) - 1} more"
        elif tr:
            state, body = "working", f"working · {tr.get('name') or 'tool'} running {since(tr.get('since'), now)}"
        elif st.get("turn_ended") or st.get("notification") == "idle_prompt":
            state, body = "waiting_on_you", f"waiting on you · {since(st.get('waiting_since') or st.get('updated'), now)}"
        elif not to_int(st.get("turn")) and not calls and not lt:
            state, body = "waiting_on_you", f"waiting on you · no prompt yet · {since(st.get('started') or st.get('updated'), now)}"
        else:
            quiet = age_s(st.get("updated"), now)
            if quiet > stall_min() * 60:
                flag, state = "stalled? ", "stalled"
                body = f"no activity {fmt_dur(quiet)}" + (f" · last {lt.get('name')}" if lt and calls else "") + f" · {n_calls}"
            else:
                state = "working"
                body = "working · " + (f"last {lt.get('name')} {since(lt.get('at'), now)}" if lt and calls else f"thinking {fmt_dur(quiet)}") + f" · {n_calls}"
    body += routing_suffix(r)
    return {"state": state, "line": flag + PREFIX + body, "short": flag + body, "status": st}


def cli_sdir():
    return state_dir(project_dir())


def statusline():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    data = data if isinstance(data, dict) else {}
    ws = data.get("workspace") if isinstance(data.get("workspace"), dict) else {}
    cwd = ws.get("project_dir") or ws.get("current_dir") or data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    hb = render(state_dir(pathlib.Path(str(cwd))))
    head = []
    model = data.get("model") if isinstance(data.get("model"), dict) else {}
    if model.get("display_name"):
        head.append(f"[{model['display_name']}]")
    cw = data.get("context_window") if isinstance(data.get("context_window"), dict) else {}
    if isinstance(cw.get("used_percentage"), (int, float)):
        head.append(f"ctx {cw['used_percentage']:.0f}%")
    parts = [" ".join(head)] if head else []
    cost = data.get("cost") if isinstance(data.get("cost"), dict) else {}
    if isinstance(cost.get("total_cost_usd"), (int, float)):
        parts.append(f"${cost['total_cost_usd']:.2f}")
    parts.append(hb["short"])
    print(" · ".join(parts))


def elapsed(start, now):
    try:
        if isinstance(start, (int, float)):
            t = datetime.datetime.fromtimestamp(start / 1000 if start > 1e11 else start, datetime.timezone.utc)
        else:
            t = parse_ts(start)
        return fmt_dur((now - t).total_seconds()) if t else ""
    except Exception:
        return ""


def subagent_statusline():
    try:
        data = json.load(sys.stdin)
        tasks = data.get("tasks") if isinstance(data, dict) else None
        if not isinstance(tasks, list):
            return
        now, steps = utcnow(), {}
        for t in tasks:
            if not isinstance(t, dict) or t.get("id") is None:
                continue
            cwd = str(t.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
            if cwd not in steps:
                steps[cwd] = ""
                _, running = running_units(active_routing(state_dir(pathlib.Path(cwd))))
                if running:
                    u = running[0]
                    tm = "·".join(str(x) for x in (u.get("tier"), u.get("model")) if x)
                    steps[cwd] = f"step {u.get('id')}" + (f" {tm}" if tm else "") + " · "
            bits = [str(t.get("agentType") or t.get("type") or "agent")]
            el = elapsed(t.get("startTime"), now)
            if el:
                bits.append(el)
            if isinstance(t.get("tokenCount"), (int, float)):
                bits.append(f"{t['tokenCount'] / 1000:.1f}k tok")
            print(json.dumps({"id": t["id"], "content": steps[cwd] + " · ".join(bits)}, ensure_ascii=False))
    except Exception:
        pass


def main():
    args = sys.argv[1:]
    if "--line" in args:
        print(render(cli_sdir())["line"])
    elif "--json" in args:
        hb = render(cli_sdir())
        print(json.dumps({**(hb["status"] or {}), "project": cli_sdir().name, "state": hb["state"], "line": hb["line"]}, indent=2, ensure_ascii=False))
    elif "--statusline" in args:
        statusline()
    elif "--subagent-statusline" in args:
        subagent_statusline()
    else:
        on_event()


try:
    main()
except SystemExit:
    raise
except Exception as e:
    if sys.argv[1:] and sys.argv[1] in ("--line", "--json", "--statusline"):
        print(PREFIX + f"heartbeat error: {type(e).__name__}")   # a renderer still answers; hook events stay silent
