#!/bin/bash
#
# vps-ai-stack/update.sh
# Commits all local changes and pushes to GitHub.
# Run from inside the cloned repo directory.
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

# Must run inside a git repo
if [[ ! -d .git ]]; then
  err "Run this from inside the vps-ai-stack repo directory."
  exit 1
fi

# Remote must exist
if ! git remote get-url origin &>/dev/null; then
  err "No 'origin' remote set. Add it first:"
  err "  git remote add origin https://github.com/Reefoldfiveteen/vps-ai-stack.git"
  exit 1
fi

# Optional commit message
MSG="${1:-update: $(date '+%Y-%m-%d %H:%M')}"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

info "Staging changes..."
git add -A

if git diff --cached --quiet; then
  ok "Nothing to commit. Working tree clean."
  exit 0
fi

info "Committing: $MSG"
git commit -q -m "$MSG"

info "Pushing to origin/$BRANCH..."
git push origin "$BRANCH"

ok "Pushed to GitHub: $(git remote get-url origin)"
