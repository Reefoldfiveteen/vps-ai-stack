#!/bin/bash
#
# vps-ai-stack/lib/backup.sh
# Backup & restore settings/data for Hermes Agent and 9Router.
# Supports simple (per-app) and full (all-in-one with sessions/tokens/cron/system)
# backups. Full backups can be uploaded to Google Drive via gdrive CLI.
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
BACKUP_DIR="$USER_HOME/backup"
mkdir -p "$BACKUP_DIR"
chown "$USERNAME":"$USERNAME" "$BACKUP_DIR" 2>/dev/null || true

# ---- Directory lists for simple backup ----
HERMES_DIRS=("$USER_HOME/.hermes" "$USER_HOME/.config/hermes" "$USER_HOME/.local/share/hermes" "$USER_HOME/.cache/hermes" "$USER_HOME/.local/state/hermes" "$USER_HOME/HERMES")
NINEROUTER_DIRS=("$USER_HOME/.config/9router" "$USER_HOME/.9router" "$USER_HOME/.local/share/9router" "$USER_HOME/.config/9Router" "$USER_HOME/9Router")

# ---- Directory lists for full backup ----
FULL_HERMES_DIRS=("$USER_HOME/.hermes" "$USER_HOME/.local/state/hermes")
FULL_NINEROUTER_DIRS=("$USER_HOME/.config/9router" "$USER_HOME/.9router" "$USER_HOME/.local/share/9router" "$USER_HOME/.config/9Router" "$USER_HOME/9Router")

# ---- Config ----
BACKUP_CONF="$BACKUP_DIR/.backup.conf"
BACKUP_KEEP=5
if [ -f "$BACKUP_CONF" ]; then
  source "$BACKUP_CONF"
fi

# ====================================================================
# UTILITY
# ====================================================================

rel_paths() {
  local out=""
  for d in "$@"; do
    [ -e "$d" ] && out+=" ${d#"$USER_HOME"/}"
  done
  echo "$out"
}

run_as_user() {
  sudo -u "$USERNAME" bash -c "$*"
}

# ====================================================================
# SIMPLE BACKUP / RESTORE
# ====================================================================

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
  tar -czf "$out" -C "$USER_HOME" $rel
  chown "$USERNAME":"$USERNAME" "$out"
  ok "Backed up $label -> $out"
  info "  included:$(echo "$rel" | sed 's/[^ ]*/ &/g')"
}

do_restore() {
  local label="$1"; shift
  local dirs=("$@")
  local latest; latest="$(ls -t "$BACKUP_DIR/${label}-${USERNAME}-"*.tar.gz 2>/dev/null | head -1)"
  if [[ -z "$latest" ]]; then
    warn "No $label backup found in $BACKUP_DIR."
    return 1
  fi
  read -r -p "Restore $label from: $(basename "$latest") ? [y/N]: " GO
  [[ "$GO" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
  tar -xzf "$latest" -C "$USER_HOME"
  local rel; rel="$(rel_paths "${dirs[@]}")"
  chown -R "$USERNAME":"$USERNAME" $rel 2>/dev/null || true
  ok "Restored $label from $latest"
}

# ====================================================================
# FULL BACKUP (by_HERMES-style)
# ====================================================================

do_full_backup() {
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local work_dir="/tmp/backup-work-${stamp}"
  local archive_name="full-${USERNAME}-${stamp}.tar.gz"
  local archive_path="$BACKUP_DIR/${archive_name}"

  mkdir -p "$work_dir"
  trap "rm -rf '$work_dir'" RETURN

  info "=== FULL BACKUP ==="
  info "User: $USERNAME  Home: $USER_HOME"
  info "Output: $archive_path"
  echo

  #---------- 1. Hermes Agent config ----------
  info "[1/8] Hermes Agent config..."
  local hermes_count=0
  for d in "${FULL_HERMES_DIRS[@]}"; do
    [ -d "$d" ] || continue
    mkdir -p "$work_dir/hermes"
    rsync -a --exclude='hermes-agent' --exclude='node' --exclude='bin' \
      --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' \
      "$d" "$work_dir/hermes/$(basename "$d")" 2>/dev/null || \
    cp -a "$d" "$work_dir/hermes/$(basename "$d")" 2>/dev/null || true
    ((hermes_count++))
  done
  [ "$hermes_count" -gt 0 ] && ok "Hermes config backed up" || warn "No Hermes config found"

  #---------- 2. HERMES work directory ----------
  info "[2/8] HERMES work directory..."
  if [ -d "$USER_HOME/HERMES" ]; then
    mkdir -p "$work_dir/hermes-work"
    rsync -a --exclude='__pycache__' --exclude='node_modules' --exclude='*.pyc' \
      --exclude='.git' --exclude='Backup/' --exclude='hermes-agent' \
      "$USER_HOME/HERMES/" "$work_dir/hermes-work/HERMES/" 2>/dev/null || \
    cp -a "$USER_HOME/HERMES" "$work_dir/hermes-work/HERMES" 2>/dev/null || true
    ok "HERMES work directory backed up"
  else
    warn "No HERMES directory found"
  fi

  #---------- 3. 9Router ----------
  info "[3/8] 9Router..."
  local nr_count=0
  for d in "${FULL_NINEROUTER_DIRS[@]}"; do
    [ -d "$d" ] || continue
    mkdir -p "$work_dir/9router"
    cp -a "$d" "$work_dir/9router/$(basename "$d")" 2>/dev/null || true
    ((nr_count++))
  done
  [ "$nr_count" -gt 0 ] && ok "9Router backed up" || warn "No 9Router config found"

  #---------- 4. Session chats ----------
  info "[4/8] Session chats..."
  local session_found=0
  for s in "$USER_HOME/.hermes/sessions" "$USER_HOME/.hermes/state.db"; do
    [ -e "$s" ] || continue
    mkdir -p "$work_dir/sessions"
    if [ -f "$s" ]; then
      cp "$s" "$work_dir/sessions/"
    elif [ -d "$s" ]; then
      rsync -a "$s/" "$work_dir/sessions/$(basename "$s")/" 2>/dev/null || \
      cp -a "$s" "$work_dir/sessions/$(basename "$s")" 2>/dev/null || true
    fi
    ((session_found++))
  done
  [ "$session_found" -gt 0 ] && ok "Sessions backed up" || warn "No session data found"

  #---------- 5. API keys & tokens ----------
  info "[5/8] API keys & tokens..."
  mkdir -p "$work_dir/tokens"
  local token_count=0
  [ -f "$USER_HOME/HERMES/hf_tokens.txt" ] && { cp "$USER_HOME/HERMES/hf_tokens.txt" "$work_dir/tokens/"; ((token_count++)); }
  [ -f "$USER_HOME/HERMES/TTS/google_tts/token.txt" ] && { cp "$USER_HOME/HERMES/TTS/google_tts/token.txt" "$work_dir/tokens/"; ((token_count++)); }
  [ -f "$USER_HOME/.hermes/.env" ] && { cp "$USER_HOME/.hermes/.env" "$work_dir/tokens/hermes-env"; ((token_count++)); }
  [ -f "$USER_HOME/.fb_credentials" ] && { cp "$USER_HOME/.fb_credentials" "$work_dir/tokens/"; ((token_count++)); }
  [ -f "$USER_HOME/.env" ] && { cp "$USER_HOME/.env" "$work_dir/tokens/env"; ((token_count++)); }
  [ -f "$USER_HOME/.config/9router/config.yaml" ] && { cp "$USER_HOME/.config/9router/config.yaml" "$work_dir/tokens/config-9router.yaml"; ((token_count++)); }
  [ -f "$USER_HOME/.9router/config.yaml" ] && { cp "$USER_HOME/.9router/config.yaml" "$work_dir/tokens/config-dot9router.yaml"; ((token_count++)); }
  [ -f "$USER_HOME/.config/9Router/config.yaml" ] && { cp "$USER_HOME/.config/9Router/config.yaml" "$work_dir/tokens/config-9Router.yaml"; ((token_count++)); }
  ok "Tokens/keys backed up ($token_count files)"

  #---------- 6. Cron jobs ----------
  info "[6/8] Cron jobs..."
  mkdir -p "$work_dir/cron"
  if [ -d "$USER_HOME/.hermes/cron" ]; then
    cp -a "$USER_HOME/.hermes/cron" "$work_dir/cron/" 2>/dev/null || true
  fi
  [ -f "$USER_HOME/.hermes/config.yaml" ] && cp "$USER_HOME/.hermes/config.yaml" "$work_dir/cron/" 2>/dev/null || true
  ok "Cron backed up"

  #---------- 7. System snapshot ----------
  info "[7/8] System snapshot..."
  mkdir -p "$work_dir/system"
  run_as_user "pip list --format=freeze" > "$work_dir/system/pip-packages.txt" 2>/dev/null || true
  run_as_user "npm list -g --depth=0" > "$work_dir/system/npm-global.txt" 2>/dev/null || true
  timedatectl > "$work_dir/system/timezone.txt" 2>/dev/null || true
  run_as_user "crontab -l" > "$work_dir/system/crontab-user.txt" 2>/dev/null || true
  systemctl --user list-unit-files --state=enabled > "$work_dir/system/systemd-user.txt" 2>/dev/null || true
  if [ -f "$USER_HOME/HERMES/requirements.txt" ]; then
    cp "$USER_HOME/HERMES/requirements.txt" "$work_dir/system/hermes-requirements.txt" 2>/dev/null || true
  fi
  ok "System snapshot saved"

  #---------- 8. Camofox patches (if present) ----------
  info "[8/8] Camofox patches..."
  local camofox_server="$USER_HOME/.npm-global/lib/node_modules/@askjo/camofox-browser/server.js"
  if [ -f "$camofox_server" ]; then
    mkdir -p "$work_dir/camofox"
    grep -n "await localVirtualDisplay\|!process.env.DISPLAY\|viewport: null" \
      "$camofox_server" > "$work_dir/camofox/patches.txt" 2>/dev/null || true
    local camofox_config="$USER_HOME/.npm-global/lib/node_modules/@askjo/camofox-browser/camofox.config.json"
    [ -f "$camofox_config" ] && cp "$camofox_config" "$work_dir/camofox/" 2>/dev/null || true
    ok "Camofox patches backed up"
  else
    warn "No camofox found — skipping"
  fi

  #---------- Create archive ----------
  echo
  info "Creating archive..."
  tar -czf "$archive_path" -C /tmp "backup-work-${stamp}"
  chown "$USERNAME":"$USERNAME" "$archive_path"
  local size; size="$(du -h "$archive_path" | cut -f1)"
  ok "Full backup created: $archive_path ($size)"

  #---------- Generate restore.sh ----------
  local restore_script="$BACKUP_DIR/restore.sh"
  generate_restore_script "$restore_script"
  chown "$USERNAME":"$USERNAME" "$restore_script"
  chmod +x "$restore_script"
  ok "Restore script generated: $restore_script"

  echo
  info "Contents:"
  tar -tzf "$archive_path" | head -30
  [ "$(tar -tzf "$archive_path" | wc -l)" -gt 30 ] && echo "  ... (truncated)"

  rm -rf "$work_dir"

  # Cleanup — keep only last N full backups
  cleanup_old_backups
  cleanup_gdrive_backups
}

# ====================================================================
# FULL RESTORE
# ====================================================================

do_full_restore() {
  local latest; latest="$(ls -t "$BACKUP_DIR/full-${USERNAME}-"*.tar.gz 2>/dev/null | head -1)"
  if [[ -z "$latest" ]]; then
    warn "No full backup found in $BACKUP_DIR."
    return 1
  fi
  read -r -p "Restore full backup from: $(basename "$latest") ? [y/N]: " GO
  [[ "$GO" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }

  local extract_dir="/tmp/restore-work-$$"
  mkdir -p "$extract_dir"
  trap "rm -rf '$extract_dir'" RETURN
  trap 'rm -rf "$extract_dir"; exit 1' INT TERM

  info "Extracting archive..."
  tar -xzf "$latest" -C "$extract_dir"
  local work_dir; work_dir="$(ls -d "$extract_dir"/backup-work-* 2>/dev/null | head -1)"
  if [ -z "$work_dir" ]; then
    err "Invalid archive format — no backup-work-* directory found inside tarball"
    return 1
  fi

  #---------- 1. Hermes Agent ----------
  info "[1/7] Restoring Hermes Agent..."
  if [ -d "$work_dir/hermes/.hermes" ]; then
    mkdir -p "$USER_HOME/.hermes"
    rsync -a "$work_dir/hermes/.hermes/" "$USER_HOME/.hermes/" 2>/dev/null || \
    cp -a "$work_dir/hermes/.hermes/." "$USER_HOME/.hermes/" 2>/dev/null || true
    ok "Hermes config restored"
  fi
  if [ -d "$work_dir/hermes/state" ]; then
    mkdir -p "$USER_HOME/.local/state/hermes"
    rsync -a "$work_dir/hermes/state/" "$USER_HOME/.local/state/hermes/" 2>/dev/null || \
    cp -a "$work_dir/hermes/state/." "$USER_HOME/.local/state/hermes/" 2>/dev/null || true
    ok "Hermes state restored"
  fi

  #---------- 2. HERMES Work Dir ----------
  info "[2/7] Restoring HERMES work directory..."
  if [ -d "$work_dir/hermes-work/HERMES" ]; then
    mkdir -p "$USER_HOME/HERMES"
    rsync -a "$work_dir/hermes-work/HERMES/" "$USER_HOME/HERMES/" 2>/dev/null || \
    cp -a "$work_dir/hermes-work/HERMES/." "$USER_HOME/HERMES/" 2>/dev/null || true
    ok "HERMES work directory restored"
  fi

  #---------- 3. 9Router ----------
  info "[3/7] Restoring 9Router..."
  if [ -d "$work_dir/9router" ]; then
    for d in "$work_dir/9router"/*; do
      [ -d "$d" ] || continue
      local dirname; dirname="$(basename "$d")"
      case "$dirname" in
        .config) mkdir -p "$USER_HOME/.config"; cp -a "$d" "$USER_HOME/.config/" 2>/dev/null || true ;;
        .9router) cp -a "$d" "$USER_HOME/" 2>/dev/null || true ;;
        .local) mkdir -p "$USER_HOME/.local/share"; cp -a "$d/share/"* "$USER_HOME/.local/share/" 2>/dev/null || true ;;
        9Router) cp -a "$d" "$USER_HOME/" 2>/dev/null || true ;;
        *) cp -a "$d" "$USER_HOME/$dirname" 2>/dev/null || true ;;
      esac
    done
    ok "9Router restored"
  fi

  #---------- 4. Sessions ----------
  info "[4/7] Restoring sessions..."
  if [ -d "$work_dir/sessions" ]; then
    mkdir -p "$USER_HOME/.hermes"
    for item in "$work_dir/sessions"/*; do
      [ -e "$item" ] || continue
      cp -a "$item" "$USER_HOME/.hermes/" 2>/dev/null || true
    done
    ok "Sessions restored"
  fi

  #---------- 5. Tokens ----------
  info "[5/7] Restoring API keys & tokens..."
  if [ -d "$work_dir/tokens" ]; then
    [ -f "$work_dir/tokens/hf_tokens.txt" ] && mkdir -p "$USER_HOME/HERMES" && cp "$work_dir/tokens/hf_tokens.txt" "$USER_HOME/HERMES/"
    [ -f "$work_dir/tokens/token.txt" ] && mkdir -p "$USER_HOME/HERMES/TTS/google_tts/" && cp "$work_dir/tokens/token.txt" "$USER_HOME/HERMES/TTS/google_tts/"
    [ -f "$work_dir/tokens/hermes-env" ] && cp "$work_dir/tokens/hermes-env" "$USER_HOME/.hermes/.env"
    [ -f "$work_dir/tokens/.fb_credentials" ] && cp "$work_dir/tokens/.fb_credentials" "$USER_HOME/"
    [ -f "$work_dir/tokens/env" ] && cp "$work_dir/tokens/env" "$USER_HOME/.env"
    [ -f "$work_dir/tokens/config-9router.yaml" ] && { mkdir -p "$USER_HOME/.config/9router"; cp "$work_dir/tokens/config-9router.yaml" "$USER_HOME/.config/9router/config.yaml"; }
    [ -f "$work_dir/tokens/config-dot9router.yaml" ] && { mkdir -p "$USER_HOME/.9router"; cp "$work_dir/tokens/config-dot9router.yaml" "$USER_HOME/.9router/config.yaml"; }
    [ -f "$work_dir/tokens/config-9Router.yaml" ] && { mkdir -p "$USER_HOME/.config/9Router"; cp "$work_dir/tokens/config-9Router.yaml" "$USER_HOME/.config/9Router/config.yaml"; }
    ok "Tokens/keys restored"
  fi

  #---------- 6. Cron ----------
  info "[6/7] Restoring cron jobs..."
  if [ -d "$work_dir/cron/cron" ]; then
    mkdir -p "$USER_HOME/.hermes/cron"
    cp -a "$work_dir/cron/cron/." "$USER_HOME/.hermes/cron/" 2>/dev/null || true
  fi
  [ -f "$work_dir/cron/config.yaml" ] && cp "$work_dir/cron/config.yaml" "$USER_HOME/.hermes/config.yaml"
  ok "Cron restored"

  #---------- 7. Fix permissions ----------
  info "[7/7] Fixing permissions..."
  chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.hermes" 2>/dev/null || true
  chown -R "$USERNAME":"$USERNAME" "$USER_HOME/HERMES" 2>/dev/null || true
  chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config/9router" "$USER_HOME/.9router" 2>/dev/null || true
  ok "Permissions fixed"

  ok "=== FULL RESTORE COMPLETE ==="
  echo
  info "Next steps:"
  info "1. Install dependencies: pip install -r ~/HERMES/requirements.txt (if available)"
  info "2. Install Hermes: pip install hermes-agent"
  info "3. Install 9Router: check ~/HERMES/Backup/ docs or npm install -g 9router"
  info "4. Start services: systemctl --user restart novnc-desktop 9router"
  trap - INT TERM RETURN
}

# ====================================================================
# GENERATE RESTORE SCRIPT
# ====================================================================

generate_restore_script() {
  local out="${1:-$BACKUP_DIR/restore.sh}"
  cat > "$out" << 'RESTORE_EOF'
#!/bin/bash
# vps-ai-stack auto-generated restore script for full backups
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "Usage: $0 <full-<user>-<stamp>.tar.gz>"
  exit 1
fi

USER_HOME="$HOME"
EXTRACT_DIR="/tmp/restore-work-$$"
mkdir -p "$EXTRACT_DIR"
trap "rm -rf '$EXTRACT_DIR'; exit 1" INT TERM
trap "rm -rf '$EXTRACT_DIR'" EXIT

info "=== FULL SYSTEM RESTORE ==="
info "Archive: $(basename "$ARCHIVE")"
info "Target: $USER_HOME"

info "Extracting archive..."
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
WORK_DIR=$(ls -d "$EXTRACT_DIR"/backup-work-* 2>/dev/null | head -1)
if [ -z "$WORK_DIR" ]; then
  err "Invalid archive format"
  exit 1
fi

# 1. Hermes Agent
info "[1/7] Restoring Hermes Agent..."
if [ -d "$WORK_DIR/hermes/.hermes" ]; then
  mkdir -p "$USER_HOME/.hermes"
  rsync -a "$WORK_DIR/hermes/.hermes/" "$USER_HOME/.hermes/" 2>/dev/null || \
  cp -a "$WORK_DIR/hermes/.hermes/." "$USER_HOME/.hermes/" 2>/dev/null || true
  ok "Hermes config restored"
fi
if [ -d "$WORK_DIR/hermes/state" ]; then
  mkdir -p "$USER_HOME/.local/state/hermes"
  rsync -a "$WORK_DIR/hermes/state/" "$USER_HOME/.local/state/hermes/" 2>/dev/null || true
fi

# 2. HERMES Work Dir
info "[2/7] Restoring HERMES work directory..."
if [ -d "$WORK_DIR/hermes-work/HERMES" ]; then
  mkdir -p "$USER_HOME/HERMES"
  rsync -a "$WORK_DIR/hermes-work/HERMES/" "$USER_HOME/HERMES/" 2>/dev/null || \
  cp -a "$WORK_DIR/hermes-work/HERMES/." "$USER_HOME/HERMES/" 2>/dev/null || true
  ok "HERMES work directory restored"
fi

# 3. 9Router
info "[3/7] Restoring 9Router..."
if [ -d "$WORK_DIR/9router" ]; then
  for d in "$WORK_DIR/9router"/*; do
    [ -d "$d" ] || continue
    dirname=$(basename "$d")
    case "$dirname" in
      .config) mkdir -p "$USER_HOME/.config"; cp -a "$d" "$USER_HOME/.config/" 2>/dev/null || true ;;
      .9router) cp -a "$d" "$USER_HOME/" 2>/dev/null || true ;;
      .local) mkdir -p "$USER_HOME/.local/share"; cp -a "$d/share/"* "$USER_HOME/.local/share/" 2>/dev/null || true ;;
      9Router) cp -a "$d" "$USER_HOME/" 2>/dev/null || true ;;
      *) cp -a "$d" "$USER_HOME/$dirname" 2>/dev/null || true ;;
    esac
  done
  ok "9Router restored"
fi

# 4. Sessions
info "[4/7] Restoring sessions..."
if [ -d "$WORK_DIR/sessions" ]; then
  mkdir -p "$USER_HOME/.hermes"
  for item in "$WORK_DIR/sessions"/*; do
    [ -e "$item" ] || continue
    cp -a "$item" "$USER_HOME/.hermes/" 2>/dev/null || true
  done
  ok "Sessions restored"
fi

# 5. Tokens
info "[5/7] Restoring API keys & tokens..."
if [ -d "$WORK_DIR/tokens" ]; then
  [ -f "$WORK_DIR/tokens/hf_tokens.txt" ] && mkdir -p "$USER_HOME/HERMES" && cp "$WORK_DIR/tokens/hf_tokens.txt" "$USER_HOME/HERMES/"
  [ -f "$WORK_DIR/tokens/token.txt" ] && mkdir -p "$USER_HOME/HERMES/TTS/google_tts/" && cp "$WORK_DIR/tokens/token.txt" "$USER_HOME/HERMES/TTS/google_tts/"
  [ -f "$WORK_DIR/tokens/hermes-env" ] && cp "$WORK_DIR/tokens/hermes-env" "$USER_HOME/.hermes/.env"
  [ -f "$WORK_DIR/tokens/.fb_credentials" ] && cp "$WORK_DIR/tokens/.fb_credentials" "$USER_HOME/"
  [ -f "$WORK_DIR/tokens/env" ] && cp "$WORK_DIR/tokens/env" "$USER_HOME/.env"
  [ -f "$WORK_DIR/tokens/config-9router.yaml" ] && { mkdir -p "$USER_HOME/.config/9router"; cp "$WORK_DIR/tokens/config-9router.yaml" "$USER_HOME/.config/9router/config.yaml"; }
  [ -f "$WORK_DIR/tokens/config-dot9router.yaml" ] && { mkdir -p "$USER_HOME/.9router"; cp "$WORK_DIR/tokens/config-dot9router.yaml" "$USER_HOME/.9router/config.yaml"; }
  [ -f "$WORK_DIR/tokens/config-9Router.yaml" ] && { mkdir -p "$USER_HOME/.config/9Router"; cp "$WORK_DIR/tokens/config-9Router.yaml" "$USER_HOME/.config/9Router/config.yaml"; }
  ok "Tokens/keys restored"
fi

# 6. Cron
info "[6/7] Restoring cron jobs..."
if [ -d "$WORK_DIR/cron/cron" ]; then
  mkdir -p "$USER_HOME/.hermes/cron"
  cp -a "$WORK_DIR/cron/cron/." "$USER_HOME/.hermes/cron/" 2>/dev/null || true
fi
[ -f "$WORK_DIR/cron/config.yaml" ] && cp "$WORK_DIR/cron/config.yaml" "$USER_HOME/.hermes/config.yaml"
ok "Cron restored"

# 7. Fix permissions
info "[7/7] Fixing permissions..."
chown -R "$(whoami):$(whoami)" "$USER_HOME/.hermes" 2>/dev/null || true
chown -R "$(whoami):$(whoami)" "$USER_HOME/HERMES" 2>/dev/null || true
ok "Permissions fixed"

echo
ok "=== RESTORE COMPLETE ==="
echo
info "Next steps:"
info "1. Install dependencies: pip install -r ~/HERMES/requirements.txt (if available)"
info "2. Install Hermes: pip install hermes-agent"
info "3. Install 9Router: npm install -g 9router"
info "4. Start services: systemctl --user restart novnc-desktop 9router"
RESTORE_EOF
}

# ====================================================================
# GOOGLE DRIVE UPLOAD
# ====================================================================

install_gdrive() {
  if command -v gdrive &>/dev/null; then
    ok "gdrive CLI already installed: $(gdrive version 2>/dev/null | head -1)"
    return 0
  fi
  info "Installing gdrive CLI (glotlabs/gdrive v3.9.1)..."
  local gdrive_url="https://github.com/glotlabs/gdrive/releases/download/3.9.1/gdrive_linux-x64.tar.gz"
  local tmp_dir="/tmp/gdrive-install-$$"
  mkdir -p "$tmp_dir" || return 1
  cd "$tmp_dir" || return 1

  if command -v wget &>/dev/null; then
    wget -q "$gdrive_url" -O gdrive.tar.gz || { err "wget download failed"; rm -rf "$tmp_dir"; return 1; }
  elif command -v curl &>/dev/null; then
    curl -sL "$gdrive_url" -o gdrive.tar.gz || { err "curl download failed"; rm -rf "$tmp_dir"; return 1; }
  else
    err "Neither wget nor curl available."
    rm -rf "$tmp_dir"
    return 1
  fi

  if [ ! -s gdrive.tar.gz ]; then
    err "Downloaded file is empty."
    rm -rf "$tmp_dir"
    return 1
  fi

  tar -xzf gdrive.tar.gz || { err "Extract failed (corrupt download?)"; rm -rf "$tmp_dir"; return 1; }

  # Binary name in glotlabs tarball is just "gdrive"
  if [ ! -f gdrive ]; then
    err "gdrive binary not found in extracted archive."
    rm -rf "$tmp_dir"
    return 1
  fi

  if mv gdrive /usr/local/bin/gdrive 2>/dev/null; then
    chmod +x /usr/local/bin/gdrive
  elif mv gdrive /usr/bin/gdrive 2>/dev/null; then
    chmod +x /usr/bin/gdrive
  else
    err "No write permission to /usr/local/bin or /usr/bin"
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"

  if ! command -v gdrive &>/dev/null; then
    err "gdrive installed but not in PATH. Try: export PATH=\$PATH:/usr/local/bin"
    return 1
  fi

  ok "gdrive CLI installed: $(gdrive version 2>/dev/null | head -1)"
  warn "Authenticate once: run 'gdrive account add' as $USERNAME, follow URL, paste code."
}

upload_to_gdrive() {
  local tarball; tarball="$(ls -t "$BACKUP_DIR"/full-*.tar.gz "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)"
  if [[ -z "$tarball" ]]; then
    warn "No backup tarballs found in $BACKUP_DIR. Create a backup first."
    return 1
  fi

  if ! command -v gdrive &>/dev/null; then
    warn "gdrive not installed."
    read -r -p "Install gdrive CLI now? [y/N]: " GI
    [[ "$GI" =~ ^[Yy]$ ]] || { info "Aborted."; return 0; }
    install_gdrive || return 1
  fi

  if ! run_as_user "gdrive files list --max 1 2>/dev/null" >/dev/null; then
    warn "gdrive not authenticated. Run: sudo -u $USERNAME gdrive account add"
    info "Follow URL, paste verification code, then re-run upload."
    return 1
  fi

  local folder_name="AI_Stack_Backup"
  local folder_id

  folder_id="$(run_as_user "gdrive files list --skip-header --query \"name='${folder_name}' and mimeType='application/vnd.google-apps.folder' and trashed=false\" --field-separator '|' --max 10 2>/dev/null" | head -1 | cut -d'|' -f1)"
  if [[ -z "$folder_id" ]]; then
    info "Creating '${folder_name}' folder on Google Drive..."
    folder_id="$(run_as_user "gdrive files mkdir --print-only-id '${folder_name}' 2>/dev/null")"
    if [[ -z "$folder_id" ]]; then
      err "Failed to create folder on Google Drive."
      return 1
    fi
    ok "Created folder '${folder_name}' (id: ${folder_id})"
  else
    ok "Found folder '${folder_name}' (id: ${folder_id})"
  fi

  info "Uploading '$(basename "$tarball")' to '${folder_name}'..."
  if run_as_user "gdrive files upload --parent '${folder_id}' '$tarball' 2>&1"; then
    ok "Upload complete: $(basename "$tarball") -> Google Drive /${folder_name}/"
  else
    err "Upload failed."
    return 1
  fi
}

# ====================================================================
# AUTO-BACKUP SCHEDULE (cron)
# ====================================================================

setup_auto_backup() {
  local auto_script="$BACKUP_DIR/auto-backup.sh"
  local cron_log="$BACKUP_DIR/auto-backup.log"

  cat > "$auto_script" << AUTOEOF
#!/bin/bash
# Auto-backup script generated by vps-ai-stack
# Runs full backup and optionally uploads to Google Drive.
BACKUP_DIR="\$HOME/backup"
LOG="\$BACKUP_DIR/auto-backup.log"

echo "===== Auto Backup \$(date) =====" >> "\$LOG"

# 1. Full backup
bash "$LIB_DIR/backup.sh" --full-backup >> "\$LOG" 2>&1
echo "[\$?] Full backup done" >> "\$LOG"

# 2. Upload to Google Drive (if configured)
if command -v gdrive &>/dev/null; then
  LATEST=\$(ls -t "\$BACKUP_DIR"/full-*.tar.gz 2>/dev/null | head -1)
  if [ -n "\$LATEST" ]; then
    if ! grep -q "\$(basename "\$LATEST")" "\$LOG" 2>/dev/null; then
      FOLDER_ID=\$(gdrive files list --skip-header --query "name='AI_Stack_Backup' and mimeType='application/vnd.google-apps.folder' and trashed=false" --field-separator '|' --max 10 2>/dev/null | head -1 | cut -d'|' -f1)
      [ -n "\$FOLDER_ID" ] && gdrive files upload --parent "\$FOLDER_ID" "\$LATEST" >> "\$LOG" 2>&1 && echo "[\$?] Upload done: \$(basename "\$LATEST")" >> "\$LOG"
    fi
  fi
fi

echo "===============================" >> "\$LOG"
AUTOEOF
  chmod +x "$auto_script"
  chown "$USERNAME":"$USERNAME" "$auto_script"
  ok "Auto-backup script created: $auto_script"

  if ! command -v gdrive &>/dev/null; then
    warn "gdrive not installed — auto-backup will skip upload."
    read -r -p "Install gdrive now? [y/N]: " GI
    [[ "$GI" =~ ^[Yy]$ ]] && install_gdrive
  fi

  echo
  echo "Select backup schedule (cron):"
  echo "  [1] Daily at 2 AM"
  echo "  [2] Weekly (Sunday at 2 AM)"
  echo "  [3] Custom cron expression"
  read -r -p "Choice: " SCHED_CHOICE

  local cron_expr
  case "$SCHED_CHOICE" in
    1) cron_expr="0 2 * * *" ;;
    2) cron_expr="0 2 * * 0" ;;
    3)
      read -r -p "Enter cron expression (min hour dom mon dow): " cron_expr
      ;;
    *) warn "Invalid choice — using daily at 2 AM"; cron_expr="0 2 * * *" ;;
  esac

  local cron_job="${cron_expr} bash ${auto_script}"
  if run_as_user "crontab -l 2>/dev/null" | grep -qF "$auto_script"; then
    warn "Auto-backup cron job already exists. Removing old one..."
    run_as_user "(crontab -l 2>/dev/null | grep -vF '$auto_script') | crontab -"
  fi
  run_as_user "(crontab -l 2>/dev/null; echo '$cron_job') | crontab -"
  ok "Cron job installed: $cron_expr → $auto_script"
  info "Logs: $cron_log"
  info "To remove auto-backup: 'crontab -e' and delete the line"
}

# ====================================================================
# LIST BACKUPS
# ====================================================================

list_backups() {
  echo
  echo "Available backups in $BACKUP_DIR:"
  ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  (none yet)"
}

# ====================================================================
# CLEANUP — keep only last N full backups
# ====================================================================

save_backup_keep() {
  echo "BACKUP_KEEP=$BACKUP_KEEP" > "$BACKUP_CONF"
  chown "$USERNAME":"$USERNAME" "$BACKUP_CONF" 2>/dev/null || true
}

cleanup_old_backups() {
  local pattern="full-${USERNAME}-*.tar.gz"
  local all; all=($(ls -t "$BACKUP_DIR"/$pattern 2>/dev/null))
  local count=${#all[@]}
  local keep=${BACKUP_KEEP:-5}

  if [ "$count" -le "$keep" ]; then
    return 0
  fi

  info "Local cleanup: $count full backups, keeping $keep..."
  local deleted=0
  for ((i=keep; i<count; i++)); do
    rm -f "${all[$i]}"
    info "  Deleted: $(basename "${all[$i]}")"
    ((deleted++))
  done
  ok "Local cleanup done — removed $deleted old backup(s)"
}

cleanup_gdrive_backups() {
  local keep=${BACKUP_KEEP:-5}

  if ! command -v gdrive &>/dev/null; then
    return 0
  fi

  # Find folder ID
  local folder_id
  folder_id="$(run_as_user "gdrive files list --skip-header --query \"name='AI_Stack_Backup' and mimeType='application/vnd.google-apps.folder' and trashed=false\" --field-separator '|' --max 10 2>/dev/null" | head -1 | cut -d'|' -f1)"
  if [[ -z "$folder_id" ]]; then
    return 0
  fi

  # List backup files in GDrive folder, sorted by name (desc = newest first)
  local files
  files="$(run_as_user "gdrive files list --parent '$folder_id' --skip-header --order-by 'name desc' --field-separator '|' --max 50 2>/dev/null" | grep "full-${USERNAME}-.*tar\.gz" | head -50)"
  if [[ -z "$files" ]]; then
    return 0
  fi

  local total; total="$(echo "$files" | wc -l)"
  if [ "$total" -le "$keep" ]; then
    return 0
  fi

  info "GDrive cleanup: $total backups, keeping $keep..."
  local deleted=0
  while IFS='|' read -r fid fname rest; do
    run_as_user "gdrive files delete '$fid' 2>/dev/null" && info "  Deleted: $fname" && ((deleted++))
  done <<< "$(echo "$files" | tail -n +$((keep + 1)))"
  ok "GDrive cleanup done — removed $deleted old backup(s)"
}

configure_keep_count() {
  echo
  echo "Current keep count: ${BACKUP_KEEP:-5}"
  read -r -p "New keep count (minimum 1, default 5): " NEW_KEEP
  NEW_KEEP="${NEW_KEEP:-5}"
  if [[ "$NEW_KEEP" -lt 1 ]]; then
    NEW_KEEP=5
  fi
  BACKUP_KEEP="$NEW_KEEP"
  save_backup_keep
  ok "Keep count set to $BACKUP_KEEP. Only last $BACKUP_KEEP full backups will be kept."
}

# ====================================================================
# NON-INTERACTIVE FULL BACKUP (called by cron)
# ====================================================================

if [[ "${1:-}" == "--full-backup" ]]; then
  do_full_backup
  exit $?
fi

# ====================================================================
# INTERACTIVE MENU
# ====================================================================

while true; do
  echo
  echo -e "${BLUE}========================================${NC}"
  echo -e "  BACKUP & RESTORE — user: ${GREEN}$USERNAME${BLUE}"
  echo -e "${BLUE}========================================${NC}"
  echo "  [1] Backup Hermes (simple)"
  echo "  [2] Backup 9Router (simple)"
  echo "  [3] Backup both (simple)"
  echo "  [4] List backups"
  echo "  [5] Restore Hermes (newest)"
  echo "  [6] Restore 9Router (newest)"
  echo "  [7] Full Backup (Hermes + 9Router + sessions + tokens + system)"
  echo "  [8] Full Restore (newest full backup)"
  echo "  [9] Upload latest backup to Google Drive"
  echo "  [0] Configure Auto-Backup (cron)"
  echo "  [c] Cleanup old full backups (keep last ${BACKUP_KEEP:-5})"
  echo "  [k] Change keep count (current: ${BACKUP_KEEP:-5})"
  echo "  [e] Exit"
  echo
  read -r -p "Select option: " C
  case "$C" in
    1) do_backup "Hermes" "${HERMES_DIRS[@]}" ;;
    2) do_backup "9Router" "${NINEROUTER_DIRS[@]}" ;;
    3) do_backup "Hermes" "${HERMES_DIRS[@]}"; do_backup "9Router" "${NINEROUTER_DIRS[@]}" ;;
    4) list_backups ;;
    5) do_restore "Hermes" "${HERMES_DIRS[@]}" ;;
    6) do_restore "9Router" "${NINEROUTER_DIRS[@]}" ;;
    7) do_full_backup ;;
    8) do_full_restore ;;
    9) upload_to_gdrive ;;
     0) setup_auto_backup ;;
    c|C) cleanup_old_backups; cleanup_gdrive_backups ;;
    k|K) configure_keep_count ;;
    e|E) ok "Goodbye."; exit 0 ;;
    *) warn "Invalid option." ;;
  esac
done
