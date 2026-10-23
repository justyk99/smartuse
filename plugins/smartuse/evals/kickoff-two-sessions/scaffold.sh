#!/usr/bin/env bash
# Stages the working directory for kickoff-two-sessions (run by `claude plugin eval --scaffold`, cwd = the case's workspace):
# the room-renders repo as the planner sees it, where the renderer (`roomrender`) is NOT installed. Nothing here installs or fakes it.
set -eu
mkdir -p rooms tools .task/ACTIVE .task/COMPLETED
for n in living kitchen bedroom; do printf 'stub scene file (the real scenes are on the laptop)\n' > "rooms/$n.blend"; done
cat > tools/render.sh <<'EOF'
#!/bin/sh
# Renders every rooms/*.blend to renders/<name>.png with roomrender.
for f in rooms/*.blend; do
  n=$(basename "$f" .blend)
  roomrender --scene "$f" --out "renders/$n.png" || exit 1
done
EOF
cat > README.md <<'EOF'
# Room renders
Batch pipeline: renders the scenes in `rooms/` to PNG with `roomrender` (see `tools/render.sh`).
Batch 1 (the living room) is done. The next step is batch 2 (kitchen, bedroom). Renders go to `renders/`, which git ignores.
EOF
printf 'renders/\n' > .gitignore
: > .task/ACTIVE/.gitkeep
: > .task/COMPLETED/.gitkeep
git init -q .
git symbolic-ref HEAD refs/heads/main
git add -A
git -c user.name="Dana" -c user.email="dana@example.invalid" commit -q -m "room renders: batch 1 pipeline"
