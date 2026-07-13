#!/bin/bash
#
# vps-ai-stack/lib/restart.sh
# Restart all project services for the target user (novnc-desktop, 9router).
# Uses systemd --user when available; otherwise falls back to a manual
# kill + start (same path as start-services.sh).
#
set -euo pipefail

USERNAME="${SETUP_USER:-}"
if [[ -z "$USERNAME" ]]; then
  read -r -p "Target username for services (default: reefii): " USERNAME
  USERNAME="${USERNAME:-reefii}"
fi
if ! id "$USERNAME" &>/dev/null; then
  echo "[-] User '$USERNAME' does not exist."
  exit 1
fi
export SETUP_USER="$USERNAME"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")"

# Try systemd --user first
if su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user restart novnc-desktop 9router >/dev/null 2>&1"; then
  ok "Restarted via systemd --user (novnc-desktop, 9router)."
  su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user status --no-pager novnc-desktop 9router 2>/dev/null" || true
  exit 0
fi

warn "systemd --user unavailable — falling back to manual restart."
bash "$SCRIPT_DIR/start-services.sh" "$USERNAME"
