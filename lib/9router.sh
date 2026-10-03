#!/bin/bash
#
# vps-ai-stack/lib/9router.sh
# Installs 9Router globally via npm. Runs as $SETUP_USER on port 20128.
# Manual config by user via dashboard.
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

export DEBIAN_FRONTEND=noninteractive

info "Installing Node.js tooling..."
apt-get update -y
apt-get install -y --no-install-recommends curl wget git ca-certificates nodejs npm

# Ensure npm global bin on user PATH
USER_HOME=$(eval echo ~"$USERNAME")
NPM_PREFIX="$USER_HOME/.npm-global"
su - "$USERNAME" -c "mkdir -p $NPM_PREFIX && npm config set prefix '$NPM_PREFIX'"

# Add to PATH for future logins
if ! grep -q "npm-global/bin" "$USER_HOME/.bashrc"; then
  echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$USER_HOME/.bashrc"
fi
chown "$USERNAME":"$USERNAME" "$USER_HOME/.bashrc"

info "Installing 9Router globally as '$USERNAME'..."
su - "$USERNAME" -c "export PATH=\"$NPM_PREFIX/bin:\$PATH\"; npm install -g sql.js 9router"

# ---- Fix 9Router sql-wasm.wasm ENOENT crash ----
info "Applying 9Router WebAssembly SQLite (sql.js) fix..."
MODULE_DIR="$NPM_PREFIX/lib/node_modules/9router"
WASM_SRC="$NPM_PREFIX/lib/node_modules/sql.js/dist"
APP_SQL_DIST="$MODULE_DIR/app/node_modules/sql.js/dist"
ROOT_SQL_DIST="$MODULE_DIR/node_modules/sql.js/dist"

su - "$USERNAME" -c "mkdir -p '$APP_SQL_DIST' '$ROOT_SQL_DIST'"
su - "$USERNAME" -c "cp -r '$WASM_SRC/'* '$APP_SQL_DIST/' 2>/dev/null || true"
su - "$USERNAME" -c "cp -r '$WASM_SRC/'* '$ROOT_SQL_DIST/' 2>/dev/null || true"

# ---- Disable aggressive Ubuntu 24.04 systemd-oomd auto-killer ----
if systemctl is-active --quiet systemd-oomd 2>/dev/null; then
  info "Disabling systemd-oomd to protect Node.js processes from premature kill..."
  systemctl stop systemd-oomd >/dev/null 2>&1 || true
  systemctl disable --now systemd-oomd >/dev/null 2>&1 || true
  systemctl mask systemd-oomd >/dev/null 2>&1 || true
fi

# ---- Firewall for 9Router (port 20128) ----
command -v ufw &>/dev/null && ufw allow 20128/tcp comment '9Router' >/dev/null 2>&1 || true
iptables -I INPUT 1 -p tcp --dport 20128 -j ACCEPT 2>/dev/null || true

# ---- systemd user service for 9Router ----
SERVICE_DIR="$USER_HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config"

cat > "$SERVICE_DIR/9router.service" <<EOF
[Unit]
Description=9Router AI Provider Router
After=network.target

[Service]
Type=simple
Environment=PATH=$NPM_PREFIX/bin:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$USER_HOME
ExecStart=$NPM_PREFIX/bin/9router --host 0.0.0.0 --tray --no-browser --log
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
chown "$USERNAME":"$USERNAME" "$SERVICE_DIR/9router.service"

loginctl enable-linger "$USERNAME" 2>/dev/null || true

WANTS_DIR="$USER_HOME/.config/systemd/user/default.target.wants"
mkdir -p "$WANTS_DIR"
ln -sf "../9router.service" "$WANTS_DIR/9router.service"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config"

export XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")"
systemctl start "user@$(id -u "$USERNAME").service" >/dev/null 2>&1 || true
if su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user daemon-reload >/dev/null 2>&1 && XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user restart 9router.service >/dev/null 2>&1"; then
  ok "9Router service started."
else
  warn "9Router not started now (no user bus during setup). It auto-starts after reboot (linger enabled)."
fi

ok "9Router installed. Dashboard: http://localhost:20128 (or http://<VPS_IP>:20128)."
warn "Configure providers via dashboard yourself. Then point Hermes at http://localhost:20128/v1"
