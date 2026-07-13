#!/bin/bash
#
# vps-ai-stack/lib/access.sh
# Toggle VNC/noVNC access mode:
#   [1] SSH tunnel only  -> bind 127.0.0.1 (secure, default)
#   [2] Public IP       -> bind 0.0.0.0 (exposed; needs Azure NSG + caution)
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

CONF_DIR="/etc/vps-ai-stack"
CONF="$CONF_DIR/vnc.conf"
mkdir -p "$CONF_DIR"

CURRENT="127.0.0.1"
[[ -f "$CONF" ]] && CURRENT="$(. "$CONF" 2>/dev/null; echo "${VNC_BIND:-127.0.0.1}")"

echo
echo "Current VNC bind: $CURRENT"
echo
echo "  [1] SSH tunnel only  (bind 127.0.0.1 - secure, access via: ssh -L 6080:localhost:6080)"
echo "  [2] Public IP       (bind 0.0.0.0  - exposed to internet, needs Azure NSG + care)"
echo
read -r -p "Select access mode [1/2]: " M

case "$M" in
  2) BIND="0.0.0.0" ;;
  *) BIND="127.0.0.1" ;;
esac

echo "VNC_BIND=$BIND" > "$CONF"
chmod 644 "$CONF"

# ---- UFW rule ----
if [[ "$BIND" == "0.0.0.0" ]]; then
  ufw allow 6080/tcp comment 'noVNC public' >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
  warn "VNC is now bound to 0.0.0.0:6080 (exposed to the internet)."
  warn "  - Open port 6080 in the AZURE NSG (Network Security Group) too."
  warn "  - VNC auth is sent in PLAINTEXT. Use a reverse proxy + TLS + auth"
  warn "    (e.g. nginx/caddy with basic auth) before exposing in production."
  warn "  - Prefer the SSH tunnel unless you absolutely need public access."
else
  ufw delete allow 6080/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
  ok "VNC bound to 127.0.0.1 only. Access via SSH tunnel."
fi

# ---- Restart the desktop service to apply new bind ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")"
if su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user restart novnc-desktop >/dev/null 2>&1"; then
  ok "Desktop service restarted with bind $BIND."
else
  warn "systemd --user unavailable — restarting manually."
  bash "$SCRIPT_DIR/start-services.sh" "$USERNAME"
fi

echo
if [[ "$BIND" == "0.0.0.0" ]]; then
  echo "  Public URL:  http://<VPS_IP>:6080   (your VPS public IP)"
  echo "  VNC password: the one you set during base install."
else
  echo "  Access from laptop:"
  echo "    ssh -L 6080:localhost:6080 $USERNAME@<VPS_IP>"
  echo "    then open http://localhost:6080"
fi
