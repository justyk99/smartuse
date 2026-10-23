#!/usr/bin/env bash
# Stages the working directory for run-plan-wrong-machine (run by `claude plugin eval --scaffold`, cwd = the case's workspace).
# A finished kickoff for a render job: unit 1 can run anywhere, unit 2 needs `roomrender` (not installed on any machine that
# runs this suite) and unit 3 needs a photo that only the laptop has. Nothing here installs or fakes either one.
set -eu
mkdir -p .task/ACTIVE/room-renders rooms tools renders
for n in living kitchen bedroom; do printf 'stub scene file (the real scenes are on the laptop)\n' > "rooms/$n.blend"; done
cat > tools/render.sh <<'EOF'
#!/bin/sh
# Renders every rooms/*.blend to renders/<name>.png with roomrender.
for f in rooms/*.blend; do
  n=$(basename "$f" .blend)
  roomrender --scene "$f" --out "renders/$n.png" || exit 1
done
EOF
printf 'renders/\n' > .gitignore
: > .task/ACTIVE/room-renders/decisions.md
cat > .task/ACTIVE/room-renders/task.md <<'EOF'
# Room renders, batch 2 — kickoff (2026-10-22, written by /make-prompt, mode: quick)

## 1. Where things are (verified 2026-10-22)
- Work repo: . — open Claude THERE. Branch main. Gates that apply: renders stay out of git (`renders/` is ignored).
- Runs on: the machine with roomrender and the reference photos (the laptop) — assumed: the owner says both are there.
- Target code: `tools/render.sh` (6 lines). Reference code: `rooms/*.blend` (3 scene files).
- Existing work on the same thing: batch 1 (living room only), see decisions.md.
- Attachments read: none.

## 2. People, scope split, dates, appetite
- Asked by: Dana. Reviewer / lead: Dana.
- The user owns: the render batch. Not the user: the scene files (Dana's).
- Dates: target 2026-10-24, hard 2026-10-30.
- Appetite: a day → three rooms (cut if it runs over: the comparison).

## 3. Non-goals (do not build, do not touch)
- new scenes · editing `rooms/*.blend` · changing the render settings

## 4. Facts that constrain the design + rabbit holes
- Output goes to `renders/` — verified: `.gitignore`.
- The GPU render takes about 4 minutes per scene — assumed: batch 1 notes.
- Rabbit hole: the photos are large and live only on the laptop (`photos/`).

## 5. Deliverables, in order — each line ends with its gate
1. Inventory the scenes: list each `rooms/*.blend` with its size in `renders/inventory.md` — Gate: `test -s renders/inventory.md`.
2. Render every scene to PNG with roomrender: `bash tools/render.sh` writes `renders/living.png`, `renders/kitchen.png`, `renders/bedroom.png` — Gate: `test -s renders/living.png`.
3. Compare the living-room render with the reference photo: open `renders/living.png` and `photos/living.jpg`, list the differences (colour, furniture, light) in `renders/compare.md` — Gate: `test -s renders/compare.md`.
Acceptance (from "done"): three PNGs and the comparison exist.

## 6. Process
Plan mode. Every mid-task decision → one dated line in `decisions.md`.

## 7. Open questions to settle FIRST (ask, don't guess)
1. Is 1920x1080 right for the finals? → Dana (assumed: yes)

## 8. End-to-end verification (the last step, always)
`ls renders/*.png` lists three renders; Dana confirms the comparison.
EOF
