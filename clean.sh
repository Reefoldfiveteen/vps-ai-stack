#!/bin/bash
#
# vps-ai-stack/clean.sh
# Publishes current tree to GitHub main with a CLEAN history
# (single commit, no prior commit history). DESTRUCTIVE: force-pushes.
# The 'void/' folder is excluded via .gitignore and never uploaded.
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

if [[ ! -d .git ]]; then
  err "Run this from inside the vps-ai-stack repo directory."
  exit 1
fi
if ! git remote get-url origin &>/dev/null; then
  err "No 'origin' remote. Add it first:"
  err "  git remote add origin https://github.com/Reefoldfiveteen/vps-ai-stack.git"
  exit 1
fi

warn "This will FORCE-PUSH a single clean commit to origin/main (history rewritten)."
read -r -p "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }

MSG="${1:-clean publish: $(date '+%Y-%m-%d %H:%M')}"

# Discard any tracked files that are now ignored (e.g. void/) so they don't upload
git add -A
git rm -r --cached --ignore-unmatch void >/dev/null 2>&1 || true
git add -A

# Build a clean orphan branch
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
TMP_BRANCH="clean_publish_$$"
git checkout --orphan "$TMP_BRANCH"
git commit -q -m "$MSG"

info "Force-pushing clean history to origin/main..."
git push --force origin "$TMP_BRANCH:main"

# Return to prior branch and drop the temp branch
git checkout -q "$CURRENT_BRANCH" 2>/dev/null || git checkout -q main
git branch -D "$TMP_BRANCH" 2>/dev/null || true

ok "Clean publish done. History on GitHub main is now a single commit."
