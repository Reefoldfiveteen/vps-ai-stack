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
# NOTE (2026-10-10): --allow-downgrades is REQUIRED. Ubuntu's transitional
# package carries an epoch (1:1snap1-0ubuntu5) so apt treats Mozilla's real
# build (157.0.1~build1, no epoch) as a *downgrade* and refuses to install it
# without this flag -- even with pin priority 1001. Without it you silently
# end up with the slow snap version.
apt-get install -y --allow-downgrades firefox

# If the firefox snap was installed before (e.g. by the transitional deb),
# remove it to avoid two competing Firefoxs and free ~264 MB.
if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
  info "Removing the firefox snap (replaced by the native .deb)..."
  snap remove firefox || warn "Could not remove firefox snap; continuing."
fi

# The snap stored the profile under the XDG path (~/.config/mozilla/firefox);
# the native .deb uses ~/.mozilla/firefox. Migrate once so bookmarks,
# logins and extensions survive the switch.
USER_HOME=$(eval echo ~"$USERNAME")
if [[ -d "$USER_HOME/.config/mozilla/firefox" && ! -d "$USER_HOME/.mozilla/firefox" ]]; then
  info "Migrating Firefox profile to ~/.mozilla/firefox ..."
  su - "$USERNAME" -c "mkdir -p ~/.mozilla && cp -a ~/.config/mozilla/firefox ~/.mozilla/firefox"
fi

USER_HOME=$(eval echo ~"$USERNAME")
su - "$USERNAME" -c "update-desktop-database ~/.local/share/applications 2>/dev/null || true"

# ---- Create Desktop shortcut ----
DESKTOP_DIR="$USER_HOME/Desktop"
mkdir -p "$DESKTOP_DIR"
if [[ -f /usr/share/applications/firefox.desktop ]]; then
  cp /usr/share/applications/firefox.desktop "$DESKTOP_DIR/"
  chmod +x "$DESKTOP_DIR/firefox.desktop"
  chown -R "$USERNAME":"$USERNAME" "$DESKTOP_DIR"
  ok "Desktop shortcut created at ~/Desktop/firefox.desktop"
fi

ok "Firefox installed. Launch it from Desktop shortcut or LXQt menu (Internet > Firefox)."
warn "Firefox is memory-heavy. On a 1 GiB VPS close it when not in use and keep swap sized (see menu [9])."
