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
su - "$USERNAME" -c "export PATH=\"$NPM_PREFIX/bin:\$PATH\"; npm install -g 9router"

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
ExecStart=$NPM_PREFIX/bin/9router
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
chown "$USERNAME":"$USERNAME" "$SERVICE_DIR/9router.service"

loginctl enable-linger "$USERNAME" 2>/dev/null || true
systemctl start "user@$(id -u "$USERNAME").service" 2>/dev/null || true
su - "$USERNAME" -c "systemctl --user daemon-reload && systemctl --user enable 9router.service"
su - "$USERNAME" -c "systemctl --user start 9router.service" || warn "9Router start deferred (may need reboot)"

ok "9Router installed. Dashboard: http://localhost:20128 (inside VPS / via tunnel)."
warn "Configure providers via dashboard yourself. Then point Hermes at http://localhost:20128/v1"
