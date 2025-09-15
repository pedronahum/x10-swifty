#!/usr/bin/env bash
# Bootstrap a new git repo and push to GitHub.
# Usage:
#   export REPO=youruser/x10-swifty
#   ./scripts/bootstrap_git.sh

set -euo pipefail

: "${REPO:?Set REPO to owner/name}"

git init
git add .
git commit -m "chore: bootstrap modern-swifty x10 scaffold"
git branch -M main

if command -v gh >/dev/null 2>&1; then
  gh repo create "$REPO" --public --source=. --remote=origin --push
else
  echo "GitHub CLI not found. Creating remote manually."
  echo "First create an empty repo at https://github.com/$REPO"
  read -p "Press Enter after creating the repo..."
  git remote add origin "git@github.com:$REPO.git"
  git push -u origin main
fi
