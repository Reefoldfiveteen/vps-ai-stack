#!/bin/bash
#
# vps-ai-stack/lib/restart.sh
# Restart all project services for the target user (novnc-desktop, 9router).
#
# Robust approach: kill EVERY leftover VNC/websockify/start-novnc process
# (both manual nohup instances AND systemd ones) before starting fresh via the
# manual nohup path. This avoids the start-novnc.sh singleton guard fighting
# itself when a manual instance and the systemd service are both present.
#
set -u

USERNAME="${SETUP_USER:-}"
if [[ -z "$USERNAME" ]]; then
  read -r -p "Target username for services (default: reefii): " USERNAME
  USERNAME="${USERNAME:-reefii}"
fi
if ! id "$USERNAME" &>/dev/null; then
  echo "[-] User '$USERNAME' does not exist."
  exit 1
fi
export SETUP_USER="$USERNAME"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }

UID_="$USERNAME"
XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")"
export XDG_RUNTIME_DIR

# ---- 1. Stop systemd user services (so they don't fight the manual start) ----
su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user stop novnc-desktop 9router >/dev/null 2>&1" || true

# ---- 2. Kill ALL leftover processes for this user ----
pkill -9 -u "$USERNAME" -f 'start-novnc.sh'     >/dev/null 2>&1 || true
pkill -9 -u "$USERNAME" -f 'Xtigervnc'          >/dev/null 2>&1 || true
pkill -9 -u "$USERNAME" -f 'websockify'         >/dev/null 2>&1 || true
pkill -9 -u "$USERNAME" -f 'novnc_proxy'        >/dev/null 2>&1 || true
su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' vncserver -kill :1 >/dev/null 2>&1" || true
sleep 2

# ---- 3. Start noVNC desktop fresh (manual nohup — reliable path) ----
info "Starting noVNC desktop (fresh)..."
su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' nohup /opt/vps-ai-stack/start-novnc.sh >/tmp/vps-ai-stack-novnc.\$(id -u).log 2>&1 &"
sleep 6

if su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' bash -c 'exec 3<>/dev/tcp/127.0.0.1/6080' >/dev/null 2>&1"; then
  ok "noVNC listening on 127.0.0.1:6080"
else
  warn "6080 not up yet — check /tmp/vps-ai-stack-novnc.$(id -u "$USERNAME").log"
fi

# ---- 4. Restart 9Router ----
if su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user restart 9router >/dev/null 2>&1"; then
  ok "9Router restarted via systemd --user."
else
  warn "systemd 9router unavailable — starting manually."
  pkill -9 -u "$USERNAME" -f '9router' >/dev/null 2>&1 || true
  su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' PATH='\$HOME/.npm-global/bin:\$PATH' nohup 9router --host 127.0.0.1 >/tmp/9router.log 2>&1 &"
  ok "9Router started manually on 127.0.0.1:20128"
fi

echo
echo "Tunnel from laptop:"
echo "  ssh -L 6080:localhost:6080 -L 20128:localhost:20128 $USERNAME@<VPS_IP>"
