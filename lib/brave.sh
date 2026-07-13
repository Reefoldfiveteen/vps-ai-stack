#!/bin/bash
#
# vps-ai-stack/lib/brave.sh
# Installs Brave Browser via the official Brave apt repository.
# NOTE: Brave is heavier than Falkon (~300-400 MB idle, ~600-900 MB with a
# dashboard tab). On a 1 GiB VPS keep it closed when not in use and ensure
# adequate swap. Launched from the LXQt menu (Internet > Brave).
#
set -euo pipefail

USERNAME="${SETUP_USER:-}"
if [[ -z "$USERNAME" ]]; then
  read -r -p "Target username for services (default: reefii): " USERNAME
  USERNAME="${USERNAME:-reefii}"
fi
if ! id "$USERNAME" &>/dev/null; then
  echo "[-] User '$USERNAME' does not exist. Create it first (or run via setup.sh)."
  exit 1
fi
export SETUP_USER="$USERNAME"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

export DEBIAN_FRONTEND=noninteractive

info "Installing Brave Browser (official apt repo)..."
apt-get update -y
apt-get install -y --no-install-recommends curl gnupg ca-certificates apt-transport-https

KEYRING=/usr/share/keyrings/brave-browser-archive-keyring.gpg
curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
  -o "$KEYRING"
echo "deb [signed-by=$KEYRING] https://brave-browser-apt-release.s3.brave.com/ stable main" \
  > /etc/apt/sources.list.d/brave-browser-release.list

apt-get update -y
apt-get install -y brave-browser

USER_HOME=$(eval echo ~"$USERNAME")
su - "$USERNAME" -c "update-desktop-database ~/.local/share/applications 2>/dev/null || true"

ok "Brave installed. Launch it from the LXQt menu (Internet > Brave) inside the remote desktop."
warn "Brave is memory-heavy. On a 1 GiB VPS close it when not in use and keep swap sized (see menu [8])."
