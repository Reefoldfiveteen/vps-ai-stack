#!/bin/bash
#
# vps-ai-stack/lib/backup.sh
# Backup & restore settings/data for Hermes Agent and 9Router.
# Data lives under the user's home (~/.hermes, ~/.config/...), so we tar it.
# Backups are stored in /opt/vps-ai-stack/backups as timestamped tarballs.
#
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

USER_HOME=$(eval echo ~"$USERNAME")
BACKUP_DIR="/opt/vps-ai-stack/backups"
mkdir -p "$BACKUP_DIR"

# Candidate data directories for each app (any that exist are backed up).
HERMES_DIRS=("$USER_HOME/.hermes" "$USER_HOME/.config/hermes" "$USER_HOME/.local/share/hermes")
NINEROUTER_DIRS=("$USER_HOME/.config/9router" "$USER_HOME/.9router" "$USER_HOME/.local/share/9router" "$USER_HOME/.config/9Router")

rel_paths() {
  # Print space-separated relative-to-$USER_HOME paths for dirs that exist.
  local out=""
  for d in "$@"; do
    [ -e "$d" ] && out+=" ${d#"$USER_HOME"/}"
  done
  echo "$out"
}

do_backup() {
  local label="$1"; shift
  local dirs=("$@")
  local rel; rel="$(rel_paths "${dirs[@]}")"
  if [[ -z "${rel// }" ]]; then
    warn "No $label data found under $USER_HOME — nothing to back up."
    return 1
  fi
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local out="$BACKUP_DIR/${label}-${USERNAME}-${stamp}.tar.gz"
  # shellcheck disable=SC2086
  tar -czf "$out" -C "$USER_HOME" $rel
  chown "$USERNAME":"$USERNAME" "$out"
  ok "Backed up $label -> $out"
  info "  included:$(echo "$rel" | sed 's/[^ ]*/ &/g')"
}

do_restore() {
  local label="$1"; shift
  local dirs=("$@")
  # Pick the newest backup tarball for this label.
  local latest; latest="$(ls -t "$BACKUP_DIR/${label}-${USERNAME}-"*.tar.gz 2>/dev/null | head -1)"
  if [[ -z "$latest" ]]; then
    warn "No $label backup found in $BACKUP_DIR."
    return 1
  fi
  read -r -p "Restore $label from: $(basename "$latest") ? [y/N]: " GO
  [[ "$GO" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
  tar -xzf "$latest" -C "$USER_HOME"
  # Restore ownership of the extracted paths.
  local rel; rel="$(rel_paths "${dirs[@]}")"
  # shellcheck disable=SC2086
  chown -R "$USERNAME":"$USERNAME" $rel 2>/dev/null || true
  ok "Restored $label from $latest"
}

list_backups() {
  echo
  echo "Available backups in $BACKUP_DIR:"
  ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  (none yet)"
}

while true; do
  echo
  echo -e "${BLUE}========================================${NC}"
  echo -e "  BACKUP & RESTORE — Hermes / 9Router (user: ${GREEN}$USERNAME${BLUE})"
  echo -e "${BLUE}========================================${NC}"
  echo "  [1] Backup Hermes"
  echo "  [2] Backup 9Router"
  echo "  [3] Backup both"
  echo "  [4] List backups"
  echo "  [5] Restore Hermes (newest)"
  echo "  [6] Restore 9Router (newest)"
  echo "  [7] Exit"
  echo
  read -r -p "Select option: " C
  case "$C" in
    1) do_backup "Hermes" "${HERMES_DIRS[@]}" ;;
    2) do_backup "9Router" "${NINEROUTER_DIRS[@]}" ;;
    3) do_backup "Hermes" "${HERMES_DIRS[@]}"; do_backup "9Router" "${NINEROUTER_DIRS[@]}" ;;
    4) list_backups ;;
    5) do_restore "Hermes" "${HERMES_DIRS[@]}" ;;
    6) do_restore "9Router" "${NINEROUTER_DIRS[@]}" ;;
    7) ok "Goodbye."; exit 0 ;;
    *) warn "Invalid option." ;;
  esac
done
