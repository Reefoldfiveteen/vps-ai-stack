#!/bin/bash
#
# vps-ai-stack/lib/firefox.sh
# Installs Firefox (real .deb) via Mozilla's official apt repository.
# NOTE: On Ubuntu 24.04 the default `apt install firefox` pulls a SNAP
# transitional package. We add Mozilla's own apt repo and pin it so apt
# installs the native .deb instead (dependencies resolved automatically).
# Firefox is also memory-heavy (~300-500 MB with a tab). On a 1 GiB VPS keep
# it closed when not in use and ensure adequate swap. Launched from the LXQt
# menu (Internet > Firefox).
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

info "Adding Mozilla apt repository for the native Firefox .deb (avoids the snap transitional package)..."
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  -o /etc/apt/keyrings/packages.mozilla.org.asc
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
  > /etc/apt/sources.list.d/mozilla.list

# Pin Firefox to the Mozilla repo so apt prefers the .deb over Ubuntu's
# snap transitional package (which carries an epoch and would otherwise win).
cat > /etc/apt/preferences.d/99-mozilla-firefox <<'EOF'
Package: firefox*
Pin: origin packages.mozilla.org
Pin-Priority: 1001
EOF

apt-get update -y
apt-get install -y firefox

USER_HOME=$(eval echo ~"$USERNAME")
su - "$USERNAME" -c "update-desktop-database ~/.local/share/applications 2>/dev/null || true"

ok "Firefox installed. Launch it from the LXQt menu (Internet > Firefox) inside the remote desktop."
warn "Firefox is memory-heavy (like Brave). On a 1 GiB VPS close it when not in use and keep swap sized (see menu [8])."
