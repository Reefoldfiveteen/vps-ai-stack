#!/bin/bash
#
# vps-ai-stack/setup.sh
# Main entry point - interactive menu for VPS AI agent stack setup.
# Installs noVNC + LXQt + TigerVNC desktop, Hermes Agent, and 9Router.
# Access is via SSH tunnel only (port 6080 localhost).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[-]${NC} $*"; }

# ---- Must run as root (for package install + UFW) ----
if [[ $EUID -ne 0 ]]; then
  err "Run this script as root: sudo bash setup.sh"
  exit 1
fi

# ---- Prompt for target username ----
echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  VPS AI STACK SETUP${NC}"
echo -e "${BLUE}========================================${NC}"
echo
read -r -p "Target username for services (default: reefii): " USERNAME
USERNAME="${USERNAME:-reefii}"

if ! id "$USERNAME" &>/dev/null; then
  warn "User '$USERNAME' does not exist."
  read -r -p "Create user '$USERNAME' now? [y/N]: " CREATE_USER
  if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
    useradd -m -s /bin/bash "$USERNAME"
    echo "User '$USERNAME' created. Set a password:"
    passwd "$USERNAME"
  else
    err "Cannot continue without a valid user. Exiting."
    exit 1
  fi
fi
ok "Using user: $USERNAME"

# Export for lib scripts
export SETUP_USER="$USERNAME"
export SETUP_LIB="$LIB_DIR"

# ---- Auto-detect VPS public IP ----
VPS_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
[[ -z "$VPS_IP" ]] && VPS_IP="$(curl -fsS --max-time 5 https://api.ipify.org || echo '<VPS_IP>')"
ok "Detected VPS IP: $VPS_IP"

# ---- Menu ----
show_menu() {
  echo
  echo -e "${BLUE}========================================${NC}"
  echo -e "  VPS AI STACK - Menu (user: ${GREEN}$USERNAME${BLUE})"
  echo -e "${BLUE}========================================${NC}"
  echo "  [1] Install Base System: noVNC + LXQt (Browser-based, port 6080)"
  echo "  [2] Install Base System: XRDP + LXQt (Native RDP client, port 3389)"
  echo "  [3] Install Hermes Agent (download + deps only)"
  echo "  [4] Install 9Router (npm install only)"
  echo "  [5] Install Browser (Brave / Firefox)"
  echo "  [6] Install All (Desktop choice -> Hermes -> 9Router -> Browser)"
  echo "  [7] Print Access & Security Guide"
  echo "  [8] Restart All Services (Desktop, 9router)"
  echo "  [9] Configure Swap Size"
  echo "  [10] Configure Remote Desktop Access (SSH tunnel / Public IP)"
  echo "  [11] Backup & Restore (Simple + Full / GDrive / Auto-Backup)"
  echo "  [12] Exit"
  echo
}

while true; do
  show_menu
  read -r -p "Select option: " CHOICE
  case "$CHOICE" in
    1) bash "$LIB_DIR/base.sh" ;;
    2) bash "$LIB_DIR/xrdp.sh" ;;
    3) bash "$LIB_DIR/hermes.sh" ;;
    4) bash "$LIB_DIR/9router.sh" ;;
    5) bash "$LIB_DIR/browser.sh" ;;
    6)
      echo
      info "=== Step 1: Remote Desktop Base System ==="
      echo "Choose your Remote Desktop system:"
      echo "  [1] noVNC + LXQt (Browser-based via port 6080 - ultra-lightweight)"
      echo "  [2] XRDP + LXQt  (Native Remote Desktop via port 3389 - smooth & fast)"
      read -r -p "Selection [1/2, default: 2]: " DESK_CHOICE
      DESK_CHOICE="${DESK_CHOICE:-2}"
      if [[ "$DESK_CHOICE" == "1" ]]; then
        BASE_SCRIPT="base.sh"
      else
        BASE_SCRIPT="xrdp.sh"
      fi

      info "Installing desktop ($BASE_SCRIPT)..."
      bash "$LIB_DIR/$BASE_SCRIPT" || err "Desktop install encountered an issue"

      info "=== Step 2: Hermes Agent ==="
      bash "$LIB_DIR/hermes.sh" || err "Hermes install failed"

      info "=== Step 3: 9Router ==="
      bash "$LIB_DIR/9router.sh" || err "9Router install failed"

      info "=== Step 4: Browser ==="
      bash "$LIB_DIR/browser.sh" || err "Browser install failed"

      ok "Install All complete!"
      ;;
    7) bash "$LIB_DIR/access_guide.sh" ;;
    8) bash "$LIB_DIR/restart.sh" ;;
    9) bash "$LIB_DIR/swap.sh" ;;
    10) bash "$LIB_DIR/access.sh" ;;
    11) bash "$LIB_DIR/backup.sh" ;;
    12) ok "Goodbye."; exit 0 ;;
     *) warn "Invalid option." ;;
  esac
done
