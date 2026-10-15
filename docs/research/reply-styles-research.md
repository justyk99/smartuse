# Reply styles — what "LCD" really is, what the evidence says, and a switchable catalogue (2026-10-15)

## 1. What "lowest common denominator" means

| Sense | Meaning | Source |
|---|---|---|
| Arithmetic | the smallest number every fraction in a set can be written over — the **common base** that lets different things be compared | dictionary.com, Merriam-Webster |
| Figurative (since 1854) | "something of small intellectual content designed to appeal to a lowbrow audience" — **dumbing down to please everyone, pleasing no one** (a critic on chefs "aiming for the lowest common denominator") | Merriam-Webster |
| Neutral use | what unifies a huge audience (the Super Bowl argument) | WYPR 2013 |

the author's rule uses the **first** sense, not the second. His test is "someone who never opened the code understands it AND can explain it to a senior". That is the common base of the room, with the senior as the precision check. The pejorative sense (dumbing down) is exactly what the second half of the test prevents. So the refined definition:

> **LCD (common-base writing):** every reader in the room, including the least technical one, can act on the reply and relay it correctly to the most technical one. Two tests: the **relay test** (a non-coder can explain it to a senior) and the **precision test** (the senior accepts it: exact names, one real example, before → after).

Fails the relay test → too technical. Fails the precision test → dumbed down. LCD is the narrow band that passes both.

## 2. What the evidence supports (and what it does not)

| Finding | Evidence | Which rule it backs |
|---|---|---|
| People scan screens; they do not read | NN/g: 79% of users scanned, 16% read word by word. Cutting words by half → +58% usability; scannable layout → +47%; objective wording → +27%; all three → **+124%** | word caps · labelled blocks · tables · no hype |
| Experts want plain language too | NN/g expert study (qualitative): an IT manager on a jargon page — "a whole lot of jargon and technical terms I'm not aware of"; rules: 15–20-word sentences, one idea per paragraph, inverted pyramid, grade 10–12 reading level for experts, "when you write for everyone, you write for no one" | plain words · one idea per line · **write for a named audience** |
| Conclusion first | BLUF from US Army AR 25-50 ("putting the main point at the beginning … is essential"); Minto's Pyramid Principle at McKinsey; journalism's inverted pyramid | lead with the answer |
| The writer cannot see their own jargon | Pinker, *The Sense of Style*: the "curse of knowledge" is the main cause of opaque writing; empathy alone does not fix it — test on a representative reader | 3-word gloss on first use · the relay test |
| Confidence drops when you must explain | Rozenblit & Keil 2002, illusion of explanatory depth: people rate their understanding high until asked to explain a mechanism, then lower it | **What → How → Impact is a check on Claude too**: if the How cannot be written, the trace is missing |
| Models over-generate | YapBench 2026: 76 chat models, an order-of-magnitude spread in excess length; filler on ambiguous prompts, explanation overhead on one-line coding asks. "Verbosity compensation" 2024: verbose answers correlate with lower accuracy; preference training rewards length | explicit caps · "short for simple, longer on request" |
| Preference depends on task and person | Utrecht thesis (bank assistant): immediate answers for simple asks, clarifying questions and reasoning for complex ones; CHI 2025 workshop: verbosity can be mistaken for authority, preferences vary by population | **one style does not fit all → a switchable catalogue** |
| Bullets hide reasoning | Amazon's six-page narrative memo (Bezos 2004): bullet lists leave the reader with little; full sentences expose the causal link and let a question on page 2 be answered on page 4 | the **con** of LCD for design decisions → a narrative style exists in the catalogue |
| Plain language sells | Labrador/BVA 2020 survey (vendor-sponsored): +38% understanding, +41% retention; Aha Media (vendor-sponsored): ~80% of healthcare professionals chose the plainer version | directional only — sponsored |

Net: the universal part is small and strong (answer first, scannable, plain, capped, evidence). The rest is audience-dependent, so the style must be a **choice**, with LCD as one option.

## 3. Universal base — in every style, never switched off
1. Lead with the answer or outcome. No preamble, no restating the question.
2. Evidence, not assertion: the command and its output, the test result, file and line.
3. Every name verified (grep / MCP) before it is used.
4. Sentences ≤ 20 words; one idea per paragraph; code blocks language-tagged.
5. Short by default; "explain / why / walk me through / deep dive" unlocks length.
6. Any destructive or irreversible action gets a one-line risk statement, whatever the style.

## 4. The catalogue (each = the base + these knobs)

| Style | Best for | Shape · cap | Jargon | Pros | Cons |
|---|---|---|---|---|---|
| **lcd** (the author's) | you relay replies to others; phone reading; mixed-skill room | What → How → Impact, labelled blocks ≤ 3 lines · ≤ 200 words | plain + 3-word gloss on first use | anyone can relay it; forces one real example; cheapest to read | glosses are noise for peers; caps squeeze reasoning; weak for design debates |
| **bluf** | managers, decision-makers | answer · 3 supports · recommendation · next action · ≤ 150 words | assumed, no glosses | fastest read; decision-ready | nuance lost; assumes domain |
| **engineer** | senior devs reading in an IDE | diff / command first, one line per decision, evidence line · ≤ 300 words, code unlimited | full jargon | zero filler; precise | unreadable for non-tech; terse replies hide assumptions unless the evidence line is enforced |
| **teacher** | juniors, onboarding, learning a codebase | answer first, then why before what, one concept per section, alternatives, a check question · ≤ 600 words | explained on first use | builds understanding; fewer repeat questions | slow; costs tokens; drifts into lecture |
| **minimal** | power users iterating fast | one line + the code / command; assumptions as bullets only if any · ≤ 60 words | full jargon | speed; matches YapBench "one-line task" ideal | risks hidden → the base rule 6 (risk line) is mandatory |
| **plain** | business owners, support staff, non-technical | no code, no paths; analogy allowed; next step as a click-level instruction · ≤ 150 words | none; max 3 glossed words | non-technical people can act | not implementable alone; pair with engineer when code is involved |
| **memo** | design decisions, counter-proposals, post-mortems | problem · options · recommendation · reasoning in full sentences · risks · ≤ 1 page | as the audience | reasoning is visible and debatable (Amazon's argument) | long; wrong for fixes and quick questions |

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

Switch with the `reply-style` skill (`library/skills/reply-style/`): it shows this table with the pros and cons, asks which style and where (global or project), and writes a marked block the user can change any time.

## 4b. Tested 2026-10-15 (headless, isolated scratch folder)
- `/reply-style bluf --project` → wrote `.claude/output-styles/bluf.md` + `"outputStyle": "bluf"` in `.claude/settings.local.json` (only that key), reported the trade-off, warned that a hand-written reply section in the user's CLAUDE.md wins on conflict, and noticed it was running in a scratch folder rather than the repo. 3 turns, $0.60 of plan usage.
- Same question ("What does git stash do?") under two custom styles via `--settings '{"outputStyle": …}'`: **minimal** → 114 words, one sentence + a command block + two bullets; **teacher** → 245 words, answer first, then "why it exists (the mechanism)", a worked example, sections. The custom style files load and change the reply shape as designed.

## 5. Sources
- Merriam-Webster, "lowest common denominator" (figurative sense, first use 1854) · dictionary.com (arithmetic sense) · WYPR 2013 essay on the phrase.
- Nielsen Norman Group, "How Users Read on the Web" (79% scan; +58 / +47 / +27 / +124%) and "Plain Language Is for Everyone, Even Experts".
- US Army AR 25-50 (BLUF) as summarised by thinkinsights.net · Barbara Minto, *The Pyramid Principle* (untools.co summary).
- Steven Pinker, *The Sense of Style* — curse of knowledge (Association for Psychological Science; Harvard Gazette 2012).
- Rozenblit & Keil 2002, "The misunderstood limits of folk science: an illusion of explanatory depth" (Wikipedia summary; Mills & Keil 2004).
- YapBench, arXiv 2601.00624 (2026) · "Verbosity compensation", arXiv 2411.07858 (2024) · Esposito 2025 preprint arXiv 2508.04713 (weak sample, concise + sourced preferred) · CHI 2025 workshop paper arXiv 2504.17083 · Utrecht thesis on a bank assistant (studenttheses.uu.nl).
- Amazon six-page narrative memos (anecdote.com; released.so; networkcapital.substack.com).
- Labrador/BVA 2020 (businesswire) and Aha Media (marketingprofs) — vendor-sponsored.
