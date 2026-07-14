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
warn(){ echo -e "${RED}[!]${NC} $*"; }

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
  warn "Git sees no trackable changes. If you DID edit files, check:"
  warn "  1) They are not inside an ignored path: void/, config/, .hermes/, .npm-global/, *.log, /swapfile"
  warn "  2) You are in the correct repo dir (run 'pwd') and not editing files on the VPS"
  warn "Diagnostic — current repo state:"
  git status --short
  git status --ignored --short | grep '^!!' | head -20 || true
  exit 0
fi

info "Committing: $MSG"
git commit -q -m "$MSG"

info "Pushing to origin/$BRANCH..."
if git push -u origin "$BRANCH"; then
  ok "Pushed to GitHub: $(git remote get-url origin)"
else
  warn "Normal push rejected — the remote history diverged (remote was likely force-pushed)."
  warn "Re-fetching, then force-pushing WITH LEASE to upload your local history."
  warn "(This overwrites the remote branch with your local commits; your local work is kept.)"
  git fetch origin "$BRANCH" || true
  git push --force-with-lease -u origin "$BRANCH"
  ok "Force-pushed to GitHub: $(git remote get-url origin)"
fi
