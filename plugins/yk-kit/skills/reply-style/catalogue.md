# reply-style catalogue (shown to the user before choosing)

## Who you are → start with → switch when

| Who you are | Start with | Switch to |
|---|---|---|
| Developer / technical person reading in an IDE | **engineer** | `minimal` when iterating fast · `memo` for a design decision · `teacher` in a codebase you do not know |
| Senior / lead reviewing other people's work | **engineer** (or `bluf` for status) | `memo` for architecture calls |
| Entrepreneur · founder · idea person building with Claude | **lcd** | `memo` for product decisions · `plain` when forwarding to customers · `engineer` when you go into the code yourself |
| Developer who forwards replies to a boss, client or team, or reads on a phone | **lcd** | `engineer` when heads-down in code |
| Manager · product owner · team lead who decides | **bluf** | `memo` when the decision is big · `lcd` when relaying to a mixed team |
| Non-technical: operations, support, marketing, business owner | **plain** | `lcd` once a few terms are familiar |
| Student · junior · anyone learning a codebase | **teacher** | `engineer` once fluent |
| Analyst · researcher · writer | **memo** for findings, `bluf` for status | `lcd` when sharing with a mixed audience |
| Trainer · consultant who explains to clients | **lcd** | `teacher` for lessons · `plain` for client-facing text |
| Power user / vibe coder with nobody to relay to | **minimal** | `engineer` when something breaks · `memo` before a big change |

One person, several hats: the table is per situation, not for life. `/reply-style try <name>` switches for one conversation.

## The styles

| Style | Best for | Pros | Cons |
|---|---|---|---|
| **lcd** | you relay Claude's replies to others; phone reading; a room with mixed skills. | anyone can relay it; forces one real example; cheapest to read | glosses are noise for peers; caps squeeze reasoning; weak for design debates (use `memo` for those). |
| **bluf** | managers and decision-makers who read the first three lines. | fastest read; decision-ready | nuance lost; assumes the reader knows the domain. |
| **engineer** | senior developers reading in an IDE or terminal. | zero filler; precise names | unreadable for non-technical readers; terse replies can hide assumptions — the evidence line is mandatory. |
| **teacher** | juniors, onboarding, learning an unfamiliar codebase. | builds understanding; fewer repeat questions | slower; costs tokens; can drift into lecture. |
| **minimal** | power users iterating fast; one-line tasks. | speed; no overhead | hides risk and assumptions — the risk line is mandatory; wrong for anything that needs a decision. |
| **plain** | business owners, operators, support staff who will never open the code. | non-technical people can act | not implementable on its own — pair with `engineer` when code is involved. |
| **memo** | design decisions, counter-proposals, post-mortems. | reasoning is visible and debatable (Amazon's six-pager argument: bullets hide the causal link) | long; wrong for fixes and quick questions. |

Evidence behind the catalogue: `docs/reply-styles-research.md` in this plugin (NN/g scanning numbers, plain-language-for-experts, BLUF, curse of knowledge, illusion of explanatory depth, YapBench, Amazon memos).
