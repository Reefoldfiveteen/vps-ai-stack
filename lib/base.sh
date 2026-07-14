#!/bin/bash
#
# vps-ai-stack/lib/base.sh
# Installs LXQt desktop, TigerVNC, noVNC, swap, UFW.
# Binds noVNC to localhost:6080 only (access via SSH tunnel).
#
set -euo pipefail

USERNAME="${SETUP_USER:-}"
if [[ -z "$USERNAME" ]]; then
  read -r -p "Target username for services (default: reefii): " USERNAME
  USERNAME="${USERNAME:-reefii}"
fi
if ! id "$USERNAME" &>/dev/null; then
  err "User '$USERNAME' does not exist. Create it first (or run via setup.sh)."
  exit 1
fi
export SETUP_USER="$USERNAME"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

# ---- Kill any stale desktop session for this user (avoids :1 lock on reinstall) ----
info "Stopping any existing desktop session for '$USERNAME' (reinstall-safe)..."
# Stop the user manager entirely so the OLD systemd service cannot respawn
# a stale websockify that would hold port 6080.
systemctl stop "user@$(id -u "$USERNAME").service" >/dev/null 2>&1 || true
runuser -u "$USERNAME" -- systemctl --user stop novnc-desktop.service >/dev/null 2>&1 || true
pkill -9 -f 'start-novnc.sh' >/dev/null 2>&1 || true
pkill -9 -f 'websockify' >/dev/null 2>&1 || true
pkill -9 -f 'novnc_proxy' >/dev/null 2>&1 || true
runuser -u "$USERNAME" -- vncserver -kill :1 >/dev/null 2>&1 || true
pkill -9 -f 'Xtigervnc' >/dev/null 2>&1 || true
rm -f "/tmp/.X1-lock" "/tmp/.X11-unix/X1" 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive

info "Updating apt..."
apt-get update -y

info "Installing desktop + VNC stack..."
apt-get install -y --no-install-recommends \
  lxqt-core lxqt-session openbox \
  tigervnc-standalone-server tigervnc-common tigervnc-tools \
  xterm xinit dbus-x11 websockify python3 \
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
# websockify is installed via apt (git submodule not in release tarball)

# ---- Swap (user choice, default 2 GB) ----
DEFAULT_SWAP_MB=2048
read -r -p "Swap size in MB (Enter=${DEFAULT_SWAP_MB}, min 512, max 4096) [${DEFAULT_SWAP_MB}]: " SWAP_MB
SWAP_MB="${SWAP_MB:-$DEFAULT_SWAP_MB}"
if ! [[ "$SWAP_MB" =~ ^[0-9]+$ ]]; then
  warn "Invalid input, using default ${DEFAULT_SWAP_MB} MB."
  SWAP_MB=$DEFAULT_SWAP_MB
fi
(( SWAP_MB < 512 )) && SWAP_MB=512
(( SWAP_MB > 4096 )) && SWAP_MB=4096
SWAP_TARGET_KB=$(( SWAP_MB * 1024 ))
info "Swap target: ${SWAP_MB} MB"
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
USER_HOME=$(eval echo ~"$USERNAME")
VNC_DIR="$USER_HOME/.vnc"
mkdir -p "$VNC_DIR"
chown "$USERNAME":"$USERNAME" "$VNC_DIR"

if [[ -s "$VNC_DIR/passwd" ]]; then
  ok "Reusing existing VNC passwd ($VNC_DIR/passwd)."
  # Still need the plaintext for nothing here; the file is already valid.
  VNC_PASS1="__reuse__"
else
  info "Setting VNC password for user '$USERNAME'..."
  ATTEMPTS=0
  while (( ATTEMPTS < 5 )); do
    ATTEMPTS=$((ATTEMPTS+1))
    read -r -s -p "Enter VNC password (6-8 chars): " VNC_PASS1
    echo
    read -r -s -p "Confirm VNC password: " VNC_PASS2
    echo
    if [[ "$VNC_PASS1" != "$VNC_PASS2" ]]; then
      warn "Passwords do not match. Try again ($ATTEMPTS/5)."
      continue
    fi
    if [[ ${#VNC_PASS1} -lt 6 || ${#VNC_PASS1} -gt 8 ]]; then
      warn "Password must be 6-8 characters. Try again ($ATTEMPTS/5)."
      continue
    fi
    break
  done
  if (( ATTEMPTS >= 5 )); then
    err "Too many failed attempts. Aborting base install."
    exit 1
  fi
fi

# ---- Create VNC passwd file ----
# On Ubuntu 24.04 the password utility is `tigervncpasswd`, shipped by the
# `tigervnc-tools` package (NOT tigervnc-common, and NOT named vncpasswd).
# Always use the real binary — it produces a file Xtigervnc actually accepts.
if [[ "$VNC_PASS1" != "__reuse__" ]]; then
  VNCPASSWD="$(command -v tigervncpasswd 2>/dev/null)"
  if [[ -z "$VNCPASSWD" ]]; then
    info "tigervncpasswd not found, installing tigervnc-tools..."
    apt-get install -y tigervnc-tools
    VNCPASSWD="$(command -v tigervncpasswd 2>/dev/null)"
  fi
  if [[ -z "$VNCPASSWD" ]]; then
    err "tigervncpasswd unavailable. Install manually: apt-get install -y tigervnc-tools"
    exit 1
  fi
  info "Using $VNCPASSWD"
  # -f = filter mode: read password from stdin, write obfuscated file to stdout
  printf '%s' "$VNC_PASS1" | "$VNCPASSWD" -f > "$VNC_DIR/passwd"
fi
chmod 600 "$VNC_DIR/passwd"
chown "$USERNAME":"$USERNAME" "$VNC_DIR/passwd"
ok "VNC passwd file written ($(stat -c%s "$VNC_DIR/passwd") bytes)"

# ---- VNC xstartup (LXQt) ----
# Start a private D-Bus session bus (LXQt needs it) and keep the session
# alive: if the WM/session exits, restart it instead of ending the VNC
# session (which would drop the noVNC connection).
cat > "$VNC_DIR/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
  eval "$(dbus-launch --sh-syntax --exit-with-session)"
fi
while true; do
  startlxqt
  sleep 2
done
EOF
chmod +x "$VNC_DIR/xstartup"
chown "$USERNAME":"$USERNAME" "$VNC_DIR/xstartup"

# ---- Install robust launcher wrapper ----
INSTALL_DIR="/opt/vps-ai-stack"
mkdir -p "$INSTALL_DIR"
cp "$SETUP_LIB/start_novnc.sh" "$INSTALL_DIR/start-novnc.sh"
chmod +x "$INSTALL_DIR/start-novnc.sh"
ok "Launcher wrapper installed: $INSTALL_DIR/start-novnc.sh"

# ---- systemd user service: novnc desktop ----
info "Creating systemd user service for desktop..."
SERVICE_DIR="$USER_HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config"

# Absolute paths (avoid relying on user PATH inside systemd)
VNCSERVER_BIN="$(command -v vncserver 2>/dev/null || find /usr /bin /opt -name vncserver -type f 2>/dev/null | head -1 || echo /usr/bin/vncserver)"
WEBSOCKIFY_BIN="$(command -v websockify 2>/dev/null || find /usr /bin /opt -name websockify -type f 2>/dev/null | head -1 || echo /usr/bin/websockify)"

# Config directory for VNC bind address (toggled later by access.sh / menu [9])
CONF_DIR="/etc/vps-ai-stack"
mkdir -p "$CONF_DIR"

echo
echo "Remote desktop access method:"
echo "  [1] SSH tunnel only (127.0.0.1)  [RECOMMENDED - nothing exposed to the internet]"
echo "  [2] Public IP (0.0.0.0)          [exposes port 6080 in plaintext - only if you accept the risk]"
read -r -p "Select access method [1]: " ACCESS
ACCESS="${ACCESS:-1}"
if [[ "$ACCESS" == "2" ]]; then
  VNC_BIND="0.0.0.0"
  warn "VNC will bind 0.0.0.0:6080 (plaintext, exposed). Open port 6080 in the Azure NSG too; prefer the SSH tunnel unless required."
  ufw allow 6080/tcp comment 'noVNC public' >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
else
  VNC_BIND="127.0.0.1"
  info "VNC will bind 127.0.0.1:6080 - access via SSH tunnel: ssh -L 6080:127.0.0.1:6080 $USERNAME@<VPS_IP>"
  ufw delete allow 6080/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
fi
echo "VNC_BIND=$VNC_BIND" > "$CONF_DIR/vnc.conf"
chmod 644 "$CONF_DIR/vnc.conf"

cat > "$SERVICE_DIR/novnc-desktop.service" <<EOF
[Unit]
Description=noVNC + TigerVNC Desktop (LXQt)
After=network.target

[Service]
Type=simple
EnvironmentFile=$CONF_DIR/vnc.conf
WorkingDirectory=$USER_HOME
ExecStartPre=/bin/sh -c '$VNCSERVER_BIN -kill :1 >/dev/null 2>&1 || true'
ExecStart=$INSTALL_DIR/start-novnc.sh
ExecStop=/bin/sh -c '$VNCSERVER_BIN -kill :1 || true'
Restart=always
RestartSec=5
StartLimitIntervalSec=0
StartLimitBurst=0

[Install]
WantedBy=default.target
EOF
chown "$USERNAME":"$USERNAME" "$SERVICE_DIR/novnc-desktop.service"

# Enable linger so user services run without an active login
loginctl enable-linger "$USERNAME" 2>/dev/null || true

# Create the enable symlink manually (robust: systemctl --user may have no
# bus during non-interactive setup). This is exactly what 'systemctl enable' does.
WANTS_DIR="$USER_HOME/.config/systemd/user/default.target.wants"
mkdir -p "$WANTS_DIR"
ln -sf "../novnc-desktop.service" "$WANTS_DIR/novnc-desktop.service"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config"

# Best-effort: start the user manager + service now (needs a running user bus).
# Use runuser (no login shell) + timeout so setup never hangs. If the user bus
# is unavailable, fall back to launching the wrapper directly so :6080 comes up.
export XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")"
mkdir -p "$XDG_RUNTIME_DIR"

STARTED_VIA_SYSTEMD=0
timeout 25 systemctl start "user@$(id -u "$USERNAME").service" >/dev/null 2>&1 || true
if timeout 25 runuser -u "$USERNAME" -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
     systemctl --user daemon-reload >/dev/null 2>&1 && \
   timeout 25 runuser -u "$USERNAME" -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
     systemctl --user restart novnc-desktop.service >/dev/null 2>&1; then
  STARTED_VIA_SYSTEMD=1
  ok "Desktop service started (systemd --user)."
fi

if (( STARTED_VIA_SYSTEMD == 0 )); then
  warn "systemd --user unavailable during setup — launching desktop directly (not persistent)."
  warn "It will also start on next reboot (linger enabled)."
  runuser -u "$USERNAME" -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    setsid bash -c 'exec /opt/vps-ai-stack/start-novnc.sh' >/dev/null 2>&1 < /dev/null &
  sleep 3
  if runuser -u "$USERNAME" -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
       bash -c 'exec 3<>"/dev/tcp/127.0.0.1/6080"; exec 3>&-' 2>/dev/null; then
    ok "Desktop is up on 127.0.0.1:6080 (direct launch)."
  else
    err "Desktop did not come up. Check /tmp/vps-ai-stack-novnc.log"
  fi
fi

# ---- UFW ----
info "Configuring UFW (SSH only, deny rest)..."
SSH_PORT=$(ss -tlnp 2>/dev/null | grep -oP ':\K\d+(?=.*sshd)' | head -1 || echo 22)
SSH_PORT="${SSH_PORT:-22}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw --force enable || warn "ufw enable returned non-zero — verify firewall manually (ufw status)"

# ---- SSH keepalive (keep tunnels alive when idle) ----
info "Setting SSH server keepalive (ClientAliveInterval)..."
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/keepalive.conf <<'EOF'
ClientAliveInterval 30
ClientAliveCountMax 10
TCPKeepAlive yes
EOF
systemctl reload ssh >/dev/null 2>&1 || systemctl restart ssh >/dev/null 2>&1 || true
ok "SSH keepalive enabled (reload attempted)."

# VPS_IP may be passed by setup.sh; detect it if run standalone.
if [[ -z "${VPS_IP:-}" ]]; then
  VPS_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
  [[ -z "$VPS_IP" ]] && VPS_IP="$(curl -fsS --max-time 5 https://api.ipify.org || echo '<VPS_IP>')"
fi

ok "Base system installed."
ok "noVNC bound to localhost:6080 (not exposed to internet)."
warn "Reboot recommended so user services start cleanly."
echo
echo "  Access from laptop:"
echo "    ssh -L 6080:localhost:6080 $USERNAME@$VPS_IP"
echo "    then open http://localhost:6080 in your browser"
