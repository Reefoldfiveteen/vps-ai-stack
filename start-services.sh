#!/bin/bash
#
# vps-ai-stack/start-services.sh
# Manual start of desktop (noVNC) + 9Router as the target user, WITHOUT systemd.
# Use this if the systemd user services are not running (e.g. before first reboot,
# or on a host where the user bus is unavailable). Run as root.
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

USERNAME="${1:-reefii}"
if ! id "$USERNAME" &>/dev/null; then err "User '$USERNAME' not found."; exit 1; fi
USER_HOME=$(eval echo ~"$USERNAME")
NOVNC_DIR="/opt/novnc"
VNCSERVER_BIN="$(command -v vncserver 2>/dev/null || echo /usr/bin/vncserver)"
WEBSOCKIFY_BIN="$(command -v websockify 2>/dev/null || echo /usr/bin/websockify)"
NPM_BIN="$USER_HOME/.npm-global/bin"
# VNC bind address (toggled by setup menu [9]); default localhost
VNC_BIND="$(. /etc/vps-ai-stack/vnc.conf 2>/dev/null; echo "${VNC_BIND:-127.0.0.1}")"

mkdir -p "$USER_HOME/.vnc"
chown "$USERNAME":"$USERNAME" "$USER_HOME/.vnc"

# ---- XRDP (if installed) ----
if command -v xrdp &>/dev/null; then
  info "Restarting XRDP service..."
  systemctl restart xrdp >/dev/null 2>&1 || true
  ok "XRDP should be active on port 3389"
fi

# ---- noVNC desktop ----
if [[ -f "$NOVNC_DIR/vnc.html" || -f "$NOVNC_DIR/index.html" ]]; then
  info "Starting noVNC desktop (vncserver :1 + websockify :6080)..."
  su - "$USERNAME" -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) $VNCSERVER_BIN -kill :1 >/dev/null 2>&1 || true"
  su - "$USERNAME" -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) nohup $VNCSERVER_BIN :1 -geometry 1280x720 -depth 24 >/tmp/novnc_vnc.log 2>&1 &"
  sleep 3
  su - "$USERNAME" -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) nohup $WEBSOCKIFY_BIN --web $NOVNC_DIR ${VNC_BIND}:6080 localhost:5901 >/tmp/novnc_ws.log 2>&1 &"
  ok "noVNC should be up on ${VNC_BIND}:6080 (tunnel: ssh -L 6080:localhost:6080 $USERNAME@host)"
fi

# ---- 9Router ----
if [[ -x "$NPM_BIN/9router" ]]; then
  info "Starting 9Router..."
  su - "$USERNAME" -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) PATH='$NPM_BIN:\$PATH' nohup $NPM_BIN/9router --host 127.0.0.1 >/tmp/9router.log 2>&1 &"
  ok "9Router should be up on 127.0.0.1:20128"
else
  warn "9Router not found at $NPM_BIN/9router (run setup option [4] first)."
fi

echo
echo "Tunnel from laptop:"
TUNNEL_PORTS="-L 20128:localhost:20128"
command -v xrdp &>/dev/null && TUNNEL_PORTS="-L 3389:localhost:3389 $TUNNEL_PORTS"
[[ -f "$NOVNC_DIR/vnc.html" || -f "$NOVNC_DIR/index.html" ]] && TUNNEL_PORTS="-L 6080:localhost:6080 $TUNNEL_PORTS"
echo "  ssh $TUNNEL_PORTS $USERNAME@<VPS_IP>"
