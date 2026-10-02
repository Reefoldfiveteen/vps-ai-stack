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
mkdir -p "$CONF_DIR"

XRDP_PRESENT=0
NOVNC_PRESENT=0
if command -v xrdp &>/dev/null || [[ -f /etc/xrdp/xrdp.ini ]]; then
  XRDP_PRESENT=1
fi
if [[ -f /opt/vps-ai-stack/start-novnc.sh || -f "$CONF_DIR/vnc.conf" ]]; then
  NOVNC_PRESENT=1
fi

TARGET="vnc"
if (( XRDP_PRESENT == 1 && NOVNC_PRESENT == 0 )); then
  TARGET="xrdp"
elif (( XRDP_PRESENT == 1 && NOVNC_PRESENT == 1 )); then
  echo
  echo "Which remote desktop service do you want to configure?"
  echo "  [1] XRDP  (Port 3389)"
  echo "  [2] noVNC (Port 6080)"
  read -r -p "Select [1/2, default: 1]: " T_CHOICE
  [[ "$T_CHOICE" == "2" ]] && TARGET="vnc" || TARGET="xrdp"
fi

if [[ "$TARGET" == "xrdp" ]]; then
  CONF="$CONF_DIR/xrdp.conf"
  CURRENT="127.0.0.1"
  [[ -f "$CONF" ]] && CURRENT="$(. "$CONF" 2>/dev/null; echo "${XRDP_BIND:-127.0.0.1}")"

  echo
  echo "Current XRDP bind: $CURRENT"
  echo "  [1] SSH tunnel only (bind 127.0.0.1 - secure, port 3389 blocked externally)"
  echo "  [2] Public IP       (bind 0.0.0.0   - port 3389 exposed to internet)"
  read -r -p "Select access mode [1/2]: " M

  case "$M" in
    2) BIND="0.0.0.0" ;;
    *) BIND="127.0.0.1" ;;
  esac

  echo "XRDP_BIND=$BIND" > "$CONF"
  chmod 644 "$CONF"

  if [[ "$BIND" == "0.0.0.0" ]]; then
    sed -i '0,/^port=/s/^port=.*/port=3389/' /etc/xrdp/xrdp.ini
    sed -i '/^\[Xorg\]/,/^\[/ s/^port=.*/port=-1/' /etc/xrdp/xrdp.ini
    ufw allow 3389/tcp comment 'XRDP public' >/dev/null 2>&1 || true
    iptables -I INPUT 1 -p tcp --dport 3389 -j ACCEPT 2>/dev/null || true
    ufw --force enable >/dev/null 2>&1 || true
    systemctl restart xrdp >/dev/null 2>&1 || true
    warn "XRDP is now bound to 0.0.0.0:3389 (public). Connect to <VPS_IP>:3389."
  else
    sed -i '0,/^port=/s/^port=.*/port=tcp:\/\/127.0.0.1:3389/' /etc/xrdp/xrdp.ini
    sed -i '/^\[Xorg\]/,/^\[/ s/^port=.*/port=-1/' /etc/xrdp/xrdp.ini
    ufw delete allow 3389/tcp >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    systemctl restart xrdp >/dev/null 2>&1 || true
    ok "XRDP bound to 127.0.0.1:3389. Connect via SSH tunnel:"
    echo "  ssh -L 3389:localhost:3389 $USERNAME@<VPS_IP>"
    echo "  mstsc to: localhost:3389"
  fi
else
  CONF="$CONF_DIR/vnc.conf"
  CURRENT="127.0.0.1"
  [[ -f "$CONF" ]] && CURRENT="$(. "$CONF" 2>/dev/null; echo "${VNC_BIND:-127.0.0.1}")"

  echo
  echo "Current noVNC bind: $CURRENT"
  echo "  [1] SSH tunnel only  (bind 127.0.0.1 - secure, access via: ssh -L 6080:localhost:6080)"
  echo "  [2] Public IP       (bind 0.0.0.0  - exposed to internet, needs firewall caution)"
  read -r -p "Select access mode [1/2]: " M

  case "$M" in
    2) BIND="0.0.0.0" ;;
    *) BIND="127.0.0.1" ;;
  esac

  echo "VNC_BIND=$BIND" > "$CONF"
  chmod 644 "$CONF"

  if [[ "$BIND" == "0.0.0.0" ]]; then
    ufw allow 6080/tcp comment 'noVNC public' >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    warn "noVNC is now bound to 0.0.0.0:6080 (public URL: http://<VPS_IP>:6080)."
  else
    ufw delete allow 6080/tcp >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    ok "noVNC bound to 127.0.0.1:6080. Access via SSH tunnel:"
    echo "  ssh -L 6080:localhost:6080 $USERNAME@<VPS_IP>"
  fi

  export XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")"
  su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user restart novnc-desktop >/dev/null 2>&1" || true
fi
