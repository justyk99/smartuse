# Competitor landscape — model routing + orchestration for Claude Code (checked 2026-10-15)

Question: is the "AI company" idea (brain interprets the lazy prompt, then routes work down to cheaper models) still the best, most token-saving and most practical thing to build, and how does he make his name with it?

## 1. Who is building what

| Project | What it does | Adoption / evidence | What it lacks |
|---|---|---|---|
| **gstack** (Garry Tan) | 23 role skills (CEO review, eng review, QA, security, ship) in a Think→Plan→Build→Review→Test→Ship sprint; model pinned by config, not routed | ~136k stars; sold on author credibility, "virtual engineering team" story, 30-second install | no per-task routing, no token-saving claim, no orchestration visibility |
| **Claude-Flow / Ruflo** | queen-led hive mind, 100+ agents, 27 hooks, "30–50% token reduction" | ~59–66k stars; all numbers self-reported; an independent test: 120k tokens just to initialise, 20 min of agent negotiation, overrode the user's explicit choice — "skip it" for a solo dev | overhead; unverified claims |
| **Maestro** | 39 specialists, 4-phase workflow, main agent assigns work | lighter than Ruflo; ~80k tokens per feature in the same test | one model plays every role |
| **Claude Octopus** | 8 model providers vote with a 75% consensus gate | highest ceiling on critical changes; needs several subscriptions, 30-min setup | wasteful for normal work |
| **Codex Peer Review** | 3 sequential reviewers gate every change | "best value" in the independent comparison; ~50k tokens, < $0.10 extra | needs a second vendor |
| **tzachbon/claude-model-router-hook** | hooks warn or set the tier for the next session; subagent enforcement | small | advisory only in-session |
| **shaaz1000/claude-router** | 40 ms local keyword classifier per prompt → Haiku/Sonnet/Opus subagents; shows `🧭 fast → Haiku` per prompt; 89% on unseen prompts | 4 stars | classifies the prompt text (the thing the author's idea avoids); no measured savings |
| **NawkaRouter** | SessionStart injects a routing policy; rungs = agents pinned to model+effort; break-even rule; `ESCALATE:` one rung up on failed verification; PreToolUse blocks `effort: max`; a 6-task bench | 1 star | the main model still judges from the prompt; nothing shown to the user |
| **gearbox** (author of the GitHub feature request #67898) | SessionStart policy, tiered subagents, escalation ladder, Haiku verifier, JSONL telemetry | new; the feature request itself was auto-closed "not planned" | same shape as the two above |
| **Anthropic native** | `opusplan` (Opus plans, Sonnet executes), subagent `model:` pinning, Workflow tool with a model per agent, Agent Teams (experimental), Agent view, `/batch` | official; no automatic per-task routing ("users are their own router"; one Max user measured 93.8% of tokens on Opus) | nothing decides WHEN to delegate; no receipts |

A commenter on the feature request asked for exactly what nobody ships: **auditable routing receipts** (decision id, model + effort chosen, reason, escalation, verifier outcome, cost delta, user override) and a **dry-run / backtest** mode.

## 2. Verdict on the author's idea

| Part of the idea | Status in the market | Keep? |
|---|---|---|
| Smart model interprets the lazy prompt FIRST (intent above routing) | **Nobody does it.** All routers judge from the prompt text or inject a policy and hope. the author already built it: `make-prompt` (tested on both systems) | **Yes — this is the differentiator** |
| Tiered agents + escalation + verifier | Built by 4 small projects, ~0 adoption each; the mechanics are table stakes | Reuse the pattern, do not compete on it |
| Lower-model "hands" | Works only for small, well-specified, checkable units (NawkaRouter's own finding; Haiku costs 5× above 100k context) | A dial: off / safe / aggressive; default safe |
| Token saving | Every number in the field is self-reported; the independent test punished overhead | **Measure on real tasks, publish the ledger** — that alone would be new |
| Visibility / stuck | Nobody addresses it; the docs give `/tasks`, `/workflows`, `subagentStatusLine`, stall timeouts | Receipts + heartbeat + dry-run = the second differentiator |
| Big "org chart" story | gstack proves the story sells; Ruflo proves weight kills | Story yes, weight no: native-only, ≤ 5 files per layer |

**Answer: the idea is still good, but the part worth the author's name is not the router. It is the front door (interpret → spec), the receipts (what went where, why, what it cost, what verified it) and the docs that stay current (living-docs). Those three are unbuilt in the field and two of them already exist on his machine.**

## 3. The product that would stand out (working name: `smartuse`, later "founder mode")

1. `/make-prompt` — lazy line → kickoff spec (exists).
2. **Tier plan with a dry-run**: the brain tags each deliverable `judgment / build / mechanical / verify`, shows the routing table (what → which model → why → expected cost) and waits for "go". Routing dial in config; roles map to whatever models the user's plan has (detect the session model, never assume).
3. **Execute with receipts**: Workflow or pinned agents; every job labelled, turn-capped, heartbeat line per step; stale → killed and re-run one tier up; `/tasks` and the subagent status line show it; a `receipts.jsonl` ledger per task.
4. **Verify by a fresh agent** (the official ladder's top rung) before anything is called done.
5. `/living-docs` after the commit (exists); `/reply-style` for the voice (exists); `bash-guard` + deny list as the safety floor (exists).
6. **The number**: tokens and plan usage per task, routed vs single-model, from real work over a month. Publish it with the method.

## 4. How a name gets made in this community (what the data says)

- **Easy install + a story + an author with a real workplace**: gstack won on "my daily setup" + 30-second install. the author's story nobody else has: a Claude setup grown inside a legacy ASP.NET back office AND a Vue/.NET rebuild, every rule born from a dated incident, measured with his own `history.jsonl`.
- **Light beats heavy**: the only independent comparison recommends the lightest gate. Ship ≤ 10 files per piece, native mechanisms only (survives harness updates — the spec's own point).
- **Numbers beat adjectives**: everyone's savings are self-reported; a receipts ledger across 30 real tasks is a post people will cite.
- **Where**: own marketplace repo (`/plugin marketplace add yk/smartuse`), the community marketplace form (official listing requires Anthropic review), PRs to `jqueryscript/awesome-claude-code` and `ccplugins/awesome-claude-code-plugins`, the `skills.sh` registry for the single skills, r/ClaudeAI and X with the roast story ("one line in, planner-grade kickoff out"), and a course as the long tail.
- **Order**: ship the three existing pieces as `smartuse` v0.1 this month (road guide C1), measure for a month, then the routing layer with receipts as v0.2, then the write-up.

## 5. Sources
GitHub: nawka12/NawkaRouter · shaaz1000/claude-router · tzachbon/claude-model-router-hook · Adityaraj0421/gearbox (via anthropics/claude-code issue #67898, auto-closed "not planned" 2026-08-02) · garrytan/gstack · jqueryscript/awesome-claude-code · ccplugins/awesome-claude-code-plugins. Independent comparison: chenguangliang.com "Claude Code Multi-Agent Orchestration Plugins Compared 2026" (Ruflo, Maestro, Octopus, Codex Peer Review). Ruflo guides: pasqualepillitteri.it, codex.danielvaughan.com. Planner/executor cost write-ups (vendor): morphllm.com, sorceress.games, stack-archive.com (unverified). Official: code.claude.com/docs (plugins, discover-plugins, workflows, sub-agents, agent-view, statusline).
