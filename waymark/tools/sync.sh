#!/bin/sh
# Waymark docs sync (Mac / Linux). Stages ONLY the waymark/ folder.
# Code commits under ios/ are made by hand with a "test on device:" line, not here.
# Usage: waymark/tools/sync.sh "short message"
set -e
cd "$(git rev-parse --show-toplevel)"
git status --short waymark/ | head -40
git pull --rebase --autostash origin main
git add waymark/
if ! git diff --cached --quiet; then
  git commit -m "waymark: ${1:-sync}"
fi
git push origin HEAD:main
git log -1 --format='synced: %h %cI'
