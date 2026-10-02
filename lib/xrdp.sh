#!/bin/bash
#
# vps-ai-stack/lib/xrdp.sh
# Installs LXQt desktop + XRDP for native Remote Desktop Connection (mstsc / Remmina).
# Configures swap, UFW, Polkit rules, certificates, and access mode (SSH tunnel vs public).
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
USER_HOME=$(eval echo ~"$USERNAME")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

export DEBIAN_FRONTEND=noninteractive

info "Updating apt..."
apt-get update -y

info "Installing LXQt + XRDP stack and desktop components..."
apt-get install -y --no-install-recommends \
  lxqt-core lxqt-session lxqt-panel pcmanfm-qt openbox \
  xrdp xorgxrdp xserver-xorg-core \
  x11-xserver-utils x11-utils libxcb-cursor0 \
  xterm xinit dbus-x11 \
  curl wget unzip git ca-certificates \
  ufw net-tools

# ---- Fix Xorg Xwrapper permission for non-root users ----
info "Configuring Xwrapper to allow X server for all users..."
echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# ---- Add users to ssl-cert group & fix key.pem permissions ----
info "Configuring SSL certificate permissions for XRDP..."
adduser "$USERNAME" ssl-cert >/dev/null 2>&1 || true
adduser xrdp ssl-cert >/dev/null 2>&1 || true
chown root:ssl-cert /etc/xrdp/key.pem 2>/dev/null || true
chmod 640 /etc/xrdp/key.pem 2>/dev/null || true

# ---- Swap (user choice, default 2048 MB) ----
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

if swapon --show | grep -q "/swapfile"; then
  ok "Swapfile already active, skipping creation."
else
  info "Creating swapfile $((SWAP_TARGET_KB/1024)) MB..."
  fallocate -l "${SWAP_TARGET_KB}K" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1K count="$SWAP_TARGET_KB"
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q "^/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "Swap ready: $(swapon --show=SIZE --noheadings | tr -d ' ')"
fi

# ---- Pre-configure LXQt default window manager to Openbox ----
info "Pre-configuring LXQt default window manager to Openbox..."
mkdir -p "$USER_HOME/.config/lxqt"
cat > "$USER_HOME/.config/lxqt/session.conf" <<'EOF'
[General]
window_manager=openbox
EOF
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config/lxqt"

# ---- User ~/.xsession for LXQt ----
info "Configuring ~/.xsession for LXQt session..."
cat > "$USER_HOME/.xsession" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startlxqt
EOF
chmod +x "$USER_HOME/.xsession"
chown "$USERNAME":"$USERNAME" "$USER_HOME/.xsession"

# Configure /etc/xrdp/startwm.sh to unset conflicting managers and execute ~/.xsession
if [[ -f /etc/xrdp/startwm.sh ]]; then
  if ! grep -q "unset SESSION_MANAGER" /etc/xrdp/startwm.sh; then
    sed -i '1i unset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS' /etc/xrdp/startwm.sh
  fi
  if ! grep -q "exec ~/.xsession" /etc/xrdp/startwm.sh; then
    sed -i '/test -x \/etc\/X11\/Xsession && exec \/etc\/X11\/Xsession/i \
if [ -r ~/.xsession ]; then \
  exec ~/.xsession \
fi' /etc/xrdp/startwm.sh 2>/dev/null || true
  fi
fi

# ---- Fix Polkit popup for color manager (Ubuntu XRDP fix) ----
info "Configuring Polkit rules to prevent color-manager popups..."
mkdir -p /etc/polkit-1/localauthority/50-local.d
cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<'EOF'
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/45-allow-colord.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.color-manager.create-device" ||
         action.id == "org.freedesktop.color-manager.create-profile" ||
         action.id == "org.freedesktop.color-manager.delete-device" ||
         action.id == "org.freedesktop.color-manager.delete-profile" ||
         action.id == "org.freedesktop.color-manager.modify-device" ||
         action.id == "org.freedesktop.color-manager.modify-profile") &&
        subject.isInGroup("users")) {
        return polkit.Result.YES;
    }
});
EOF

# ---- Access Configuration (SSH tunnel vs Public IP) ----
CONF_DIR="/etc/vps-ai-stack"
mkdir -p "$CONF_DIR"

echo
echo "XRDP Remote Desktop access method:"
echo "  [1] SSH tunnel only (127.0.0.1:3389) [RECOMMENDED - secure, nothing exposed]"
echo "  [2] Public IP (0.0.0.0:3389)         [exposes RDP port to the internet]"
read -r -p "Select access method [1]: " ACCESS
ACCESS="${ACCESS:-1}"

if [[ "$ACCESS" == "2" ]]; then
  XRDP_BIND="0.0.0.0"
  # Replace port only in [Globals] section
  sed -i '0,/^port=/s/^port=.*/port=3389/' /etc/xrdp/xrdp.ini
  ufw allow 3389/tcp comment 'XRDP public' >/dev/null 2>&1 || true
  iptables -I INPUT 1 -p tcp --dport 3389 -j ACCEPT 2>/dev/null || true
  ufw --force enable >/dev/null 2>&1 || true
  warn "XRDP listening on 0.0.0.0:3389 (public). Ensure Cloud NSG/Firewall permits port 3389."
else
  XRDP_BIND="127.0.0.1"
  # Replace port only in [Globals] section
  sed -i '0,/^port=/s/^port=.*/port=tcp:\/\/127.0.0.1:3389/' /etc/xrdp/xrdp.ini
  ufw delete allow 3389/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
  ok "XRDP bound to 127.0.0.1:3389 (access via SSH tunnel only)."
fi

# ALWAYS ensure backend [Xorg] port stays -1 (never loopback to port 3389!)
sed -i '/^\[Xorg\]/,/^\[/ s/^port=.*/port=-1/' /etc/xrdp/xrdp.ini

echo "XRDP_BIND=$XRDP_BIND" > "$CONF_DIR/xrdp.conf"
echo "DESKTOP_BACKEND=xrdp" > "$CONF_DIR/desktop.conf"
chmod 644 "$CONF_DIR/xrdp.conf" "$CONF_DIR/desktop.conf"

# ---- Enable & Restart XRDP ----
info "Enabling and starting XRDP service..."
systemctl daemon-reload
systemctl enable xrdp >/dev/null 2>&1 || true
systemctl restart xrdp

sleep 2
if systemctl is-active --quiet xrdp; then
  ok "XRDP is active and running!"
else
  warn "XRDP service not active yet. Check 'systemctl status xrdp'."
fi

echo
ok "Base XRDP system install complete!"
if [[ "$XRDP_BIND" == "127.0.0.1" ]]; then
  echo "Connect via SSH tunnel from your laptop:"
  echo "  ssh -L 3389:localhost:3389 $USERNAME@<VPS_IP>"
  echo "Then connect Remote Desktop (mstsc) to: localhost:3389"
else
  echo "Connect Remote Desktop (mstsc) directly to: <VPS_IP>:3389"
fi
echo "Log in using username '$USERNAME' and the user's Linux password."
