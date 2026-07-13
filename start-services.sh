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

mkdir -p "$USER_HOME/.vnc"
chown "$USERNAME":"$USERNAME" "$USER_HOME/.vnc"

# ---- noVNC desktop ----
info "Starting noVNC desktop (vncserver :1 + websockify :6080)..."
su - "$USERNAME" -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) $VNCSERVER_BIN -kill :1 >/dev/null 2>&1 || true"
su - "$USERNAME" -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) nohup $VNCSERVER_BIN :1 -geometry 1280x720 -depth 24 >/tmp/novnc_vnc.log 2>&1 &"
sleep 3
su - "$USERNAME" -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) nohup $WEBSOCKIFY_BIN --web $NOVNC_DIR 127.0.0.1:6080 localhost:5901 >/tmp/novnc_ws.log 2>&1 &"
ok "noVNC should be up on 127.0.0.1:6080 (tunnel: ssh -L 6080:localhost:6080 $USERNAME@host)"

# ---- 9Router ----
if [[ -x "$NPM_BIN/9router" ]]; then
  info "Starting 9Router..."
  su - "$USERNAME" -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) PATH='$NPM_BIN:\$PATH' nohup $NPM_BIN/9router --host 127.0.0.1 >/tmp/9router.log 2>&1 &"
  ok "9Router should be up on 127.0.0.1:20128"
else
  warn "9Router not found at $NPM_BIN/9router (run setup option [3] first)."
fi

echo
echo "Tunnel from laptop:"
echo "  ssh -L 6080:localhost:6080 -L 20128:localhost:20128 $USERNAME@<VPS_IP>"
