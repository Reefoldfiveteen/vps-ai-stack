#!/bin/bash
#
# vps-ai-stack/lib/hermes.sh
# Downloads Hermes Agent + dependencies only. Manual config by user.
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

info "Installing Hermes Agent dependencies..."
apt-get update -y
apt-get install -y --no-install-recommends \
  curl wget git ca-certificates python3 python3-venv python3-pip \
  nodejs npm ripgrep ffmpeg

info "Running official Hermes installer as user '$USERNAME'..."
set +e
su - "$USERNAME" -c "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
HERMES_RC=$?
set -e
if [[ $HERMES_RC -ne 0 ]]; then
  err "Hermes installer exited with code $HERMES_RC — Hermes may NOT be installed."
  err "Re-run 'bash lib/hermes.sh' manually and paste the output so we can see the exact error."
else
  ok "Hermes installer finished (exit 0)."
fi

# Reload shell config so 'hermes' is on PATH
su - "$USERNAME" -c "source ~/.bashrc 2>/dev/null; source ~/.profile 2>/dev/null; hash -r; command -v hermes" \
  || warn "hermes may need a fresh login to appear on PATH"

ok "Hermes Agent installed (download + deps only)."
warn "Configure it yourself: run 'hermes' then 'hermes model' / 'hermes setup'."
warn "To use 9Router as provider, point Hermes at http://localhost:20128/v1 after 9Router is running."
