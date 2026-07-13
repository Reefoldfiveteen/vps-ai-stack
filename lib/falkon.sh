#!/bin/bash
#
# vps-ai-stack/lib/falkon.sh
# Installs Falkon - a lightweight Qt/QtWebEngine browser that fits LXQt.
# Runs as the target user (no systemd service; launched from the desktop menu).
#
set -euo pipefail

USERNAME="${SETUP_USER:-}"
if [[ -z "$USERNAME" ]]; then
  read -r -p "Target username for services (default: reefii): " USERNAME
  USERNAME="${USERNAME:-reefii}"
fi
if ! id "$USERNAME" &>/dev/null; then
  err() { echo "[-] User '$USERNAME' does not exist. Create it first (or run via setup.sh)."; }
  err
  exit 1
fi
export SETUP_USER="$USERNAME"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

export DEBIAN_FRONTEND=noninteractive

info "Installing Falkon (lightweight Qt browser for LXQt)..."
apt-get update -y
apt-get install -y --no-install-recommends falkon

# Make sure the user can launch it from the LXQt menu (icon cache refresh)
USER_HOME=$(eval echo ~"$USERNAME")
su - "$USERNAME" -c "gtk-update-icon-cache -f ~/.local/share/icons 2>/dev/null || true; update-desktop-database ~/.local/share/applications 2>/dev/null || true"

ok "Falkon installed. Launch it from the LXQt menu (Internet > Falkon) inside the remote desktop."
warn "On a 1 GiB VPS, keep browser tabs minimal — close Falkon when not in use to free RAM."
