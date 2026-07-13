#!/bin/bash
#
# vps-ai-stack/lib/swap.sh
# Configure the swap file size interactively. Safe to run repeatedly:
# disables the old swap, resizes, re-enables, and updates /etc/fstab.
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

SWAPFILE="/swapfile"

show_current() {
  echo "Current memory + swap:"
  free -h
  echo
  echo "Active swap:"
  swapon --show 2>/dev/null || echo "  (none)"
}

# Total RAM in MB
total_ram_mb() {
  awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo
}

show_current

RAM_MB=$(total_ram_mb)
AUTO_MB=$(( RAM_MB / 2 ))
(( AUTO_MB < 512 )) && AUTO_MB=512
(( AUTO_MB > 4096 )) && AUTO_MB=4096
info "Auto size = 50% of RAM (capped 512M-4G) = ${AUTO_MB}M"

echo
echo "Choose swap size:"
echo "  [a] Auto (${AUTO_MB}M)"
echo "  [1] 1G"
echo "  [2] 2G"
echo "  [4] 4G"
echo "  [8] 8G"
read -r -p "Selection [a/1/2/4/8]: " SEL

case "$SEL" in
  a|A) SIZE_MB=$AUTO_MB ;;
  1)   SIZE_MB=1024 ;;
  2)   SIZE_MB=2048 ;;
  4)   SIZE_MB=4096 ;;
  8)   SIZE_MB=8192 ;;
  *)   warn "Invalid selection, using auto (${AUTO_MB}M)."; SIZE_MB=$AUTO_MB ;;
esac

# Disable + remove existing swapfile if present
if swapon --show | grep -q "$SWAPFILE"; then
  info "Disabling existing $SWAPFILE..."
  swapoff "$SWAPFILE" || true
fi
if [[ -f "$SWAPFILE" ]]; then
  rm -f "$SWAPFILE"
  sed -i "\#^$SWAPFILE#d" /etc/fstab
fi

info "Creating ${SIZE_MB}M swap at $SWAPFILE..."
dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SIZE_MB" status=progress
chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE"
swapon "$SWAPFILE"
grep -q "^$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab

ok "Swap configured: $(swapon --show=SIZE --noheadings | tr -d ' ')"
show_current
warn "If the desktop session crashed earlier from OOM, raise swap and restart (menu [7])."
