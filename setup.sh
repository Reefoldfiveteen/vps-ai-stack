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
  echo "  [1] Install Base System (LXQt + TigerVNC + noVNC + swap + UFW)"
  echo "  [2] Install Hermes Agent (download + deps only)"
  echo "  [3] Install 9Router (npm install only)"
  echo "  [4] Install Brave Browser"
  echo "  [5] Install All (1 -> 2 -> 3 -> 4)"
  echo "  [6] Print Access & Security Guide"
  echo "  [7] Restart All Services (novnc-desktop, 9router)"
  echo "  [8] Configure Swap Size"
  echo "  [9] Configure VNC Access (SSH tunnel / Public IP)"
  echo "  [10] Exit"
  echo
}

while true; do
  show_menu
  read -r -p "Select option: " CHOICE
  case "$CHOICE" in
    1) bash "$LIB_DIR/base.sh" ;;
    2) bash "$LIB_DIR/hermes.sh" ;;
    3) bash "$LIB_DIR/9router.sh" ;;
    4)
      bash "$LIB_DIR/brave.sh"
      ;;
    5)
      for s in base hermes 9router brave; do
        info "=== step: $s ==="
        if bash "$LIB_DIR/$s.sh"; then
          ok "$s complete"
        else
          err "$s failed (exit $?) — continuing with next step"
        fi
      done
      ;;
    6)
      bash "$LIB_DIR/access_guide.sh"
      ;;
    7)
      bash "$LIB_DIR/restart.sh"
      ;;
    8)
      bash "$LIB_DIR/swap.sh"
      ;;
    9)
      bash "$LIB_DIR/access.sh"
      ;;
    10) ok "Goodbye."; exit 0 ;;
    *) warn "Invalid option." ;;
  esac
done
