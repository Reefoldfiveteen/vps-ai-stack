#!/bin/bash
#
# vps-ai-stack/update.sh
# Updates Hermes Agent + 9Router in place. Run as root on VPS.
#
set -euo pipefail

USERNAME="${1:-reefii}"
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
  err "Run as root: sudo bash update.sh [$USERNAME]"
  exit 1
fi
if ! id "$USERNAME" &>/dev/null; then
  err "User '$USERNAME' not found."
  exit 1
fi

info "Updating 9Router..."
su - "$USERNAME" -c 'export PATH="$HOME/.npm-global/bin:$PATH"; npm update -g 9router'

info "Updating Hermes Agent..."
su - "$USERNAME" -c 'hermes update' 2>/dev/null || \
  su - "$USERNAME" -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash'

info "Restarting services..."
su - "$USERNAME" -c 'systemctl --user restart 9router.service 2>/dev/null || true'
su - "$USERNAME" -c 'systemctl --user restart novnc-desktop.service 2>/dev/null || true'

ok "Update complete. Check status: systemctl --user status 9router novnc-desktop"
