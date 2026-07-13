#!/bin/bash
#
# vps-ai-stack/lib/base.sh
# Installs LXQt desktop, TigerVNC, noVNC, swap, UFW.
# Binds noVNC to localhost:6080 only (access via SSH tunnel).
#
set -euo pipefail

USERNAME="${SETUP_USER:?SETUP_USER not set}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

export DEBIAN_FRONTEND=noninteractive

info "Updating apt..."
apt-get update -y

info "Installing desktop + VNC stack..."
apt-get install -y --no-install-recommends \
  lxqt-core lxqt-session openbox \
  tigervnc-standalone-server tigervnc-common \
  xterm xinit dbus-x11 websockify \
  curl wget unzip git ca-certificates \
  ufw net-tools

# ---- noVNC + websockify ----
NOVNC_DIR="/opt/novnc"
info "Installing noVNC 1.4.0 to $NOVNC_DIR..."
rm -rf "$NOVNC_DIR"
mkdir -p "$NOVNC_DIR"
curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz -o /tmp/novnc.tar.gz
tar -xzf /tmp/novnc.tar.gz -C /tmp
cp -r /tmp/noVNC-1.4.0/* "$NOVNC_DIR/"
# websockify bundled inside utils
chmod +x "$NOVNC_DIR"/utils/novnc_proxy "$NOVNC_DIR"/utils/websockify

# ---- Swap (50% RAM, capped 512M-2G) ----
TOTAL_RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
SWAP_TARGET_KB=$(( TOTAL_RAM_KB / 2 ))
# floor 512M, cap 2G
(( SWAP_TARGET_KB < 524288 )) && SWAP_TARGET_KB=524288
(( SWAP_TARGET_KB > 2097152 )) && SWAP_TARGET_KB=2097152
if swapon --show | grep -q "/swapfile"; then
  warn "Swapfile already active, skipping."
else
  info "Creating swapfile $((SWAP_TARGET_KB/1024)) MB..."
  fallocate -l "${SWAP_TARGET_KB}K" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1K count="$SWAP_TARGET_KB"
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q "^/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
ok "Swap ready: $(swapon --show=SIZE --noheadings | tr -d ' ')"

# ---- VNC password ----
info "Setting VNC password for user '$USERNAME'..."
while true; do
  read -r -s -p "Enter VNC password (6-8 chars): " VNC_PASS1
  echo
  read -r -s -p "Confirm VNC password: " VNC_PASS2
  echo
  if [[ "$VNC_PASS1" != "$VNC_PASS2" ]]; then
    warn "Passwords do not match. Try again."
    continue
  fi
  if [[ ${#VNC_PASS1} -lt 6 || ${#VNC_PASS1} -gt 8 ]]; then
    warn "Password must be 6-8 characters."
    continue
  fi
  break
done

USER_HOME=$(eval echo ~"$USERNAME")
VNC_DIR="$USER_HOME/.vnc"
mkdir -p "$VNC_DIR"
chown "$USERNAME":"$USERNAME" "$VNC_DIR"
echo "$VNC_PASS1" | su - "$USERNAME" -c "vncpasswd -f > $VNC_DIR/passwd"
chmod 600 "$VNC_DIR/passwd"
chown "$USERNAME":"$USERNAME" "$VNC_DIR/passwd"

# ---- VNC xstartup (LXQt) ----
cat > "$VNC_DIR/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startlxqt
EOF
chmod +x "$VNC_DIR/xstartup"
chown "$USERNAME":"$USERNAME" "$VNC_DIR/xstartup"

# ---- systemd user service: novnc desktop ----
info "Creating systemd user service for desktop..."
SERVICE_DIR="$USER_HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config"

cat > "$SERVICE_DIR/novnc-desktop.service" <<EOF
[Unit]
Description=noVNC + TigerVNC Desktop (LXQt)
After=network.target

[Service]
Type=simple
WorkingDirectory=$USER_HOME
ExecStartPre=/bin/sh -c 'vncserver -kill :1 >/dev/null 2>&1 || true'
ExecStart=/bin/sh -c 'vncserver :1 -geometry 1280x720 -depth 24 && sleep 2 && websockify --web $NOVNC_DIR 127.0.0.1:6080 localhost:5901'
ExecStop=/bin/sh -c 'vncserver -kill :1 || true'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
chown "$USERNAME":"$USERNAME" "$SERVICE_DIR/novnc-desktop.service"

# Enable linger so user services run without active session
loginctl enable-linger "$USERNAME" 2>/dev/null || true
# Start the user systemd manager immediately (so --user works before first login)
systemctl start "user@$(id -u "$USERNAME").service" 2>/dev/null || true
su - "$USERNAME" -c "systemctl --user daemon-reload && systemctl --user enable novnc-desktop.service"
su - "$USERNAME" -c "systemctl --user start novnc-desktop.service" || warn "Service start deferred (may need reboot)"

# ---- UFW ----
info "Configuring UFW (SSH only, deny rest)..."
SSH_PORT=$(ss -tlnp 2>/dev/null | grep -oP ':\K\d+(?=.*sshd)' | head -1 || echo 22)
SSH_PORT="${SSH_PORT:-22}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw --force enable

ok "Base system installed."
ok "noVNC bound to localhost:6080 (not exposed to internet)."
warn "Reboot recommended so user services start cleanly."
echo
echo "  Access from laptop:"
echo "    ssh -L 6080:localhost:6080 $USERNAME@$VPS_IP"
echo "    then open http://localhost:6080 in your browser"
