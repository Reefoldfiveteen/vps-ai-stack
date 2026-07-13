#!/bin/bash
#
# vps-ai-stack/lib/swap.sh
# Configure swap SIZE-SAFELY. Never swaps off an active swap (that can OOM
# when RAM is nearly full). Instead it adds a new swap file and leaves any
# currently-active swap in place.
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){ echo -e "${RED}[-]${NC} $*"; }

show_current() {
  echo "Current memory + swap:"
  free -h
  echo
  echo "Active swap:"
  swapon --show 2>/dev/null || echo "  (none)"
}

active_swaps() { swapon --show=NAME --noheadings 2>/dev/null; }

total_ram_mb() { awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo; }

show_current

RAM_MB=$(total_ram_mb)
AUTO_MB=$(( RAM_MB / 2 ))
(( AUTO_MB < 512 )) && AUTO_MB=512
(( AUTO_MB > 4096 )) && AUTO_MB=4096
info "Auto size = 50% of RAM (capped 512M-4G) = ${AUTO_MB}M"

echo
echo "Choose swap size to ADD:"
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

ACTIVE="$(active_swaps)"

# If a swap of this exact size is already active, do nothing.
if echo "$ACTIVE" | grep -qx "/swapfile_${SIZE_MB}"; then
  ok "Swap /swapfile_${SIZE_MB} already active. Nothing to do."
  show_current
  exit 0
fi

# Pick a target path that is NOT currently an active swap.
TARGET="/swapfile_${SIZE_MB}"
n=1
while echo "$ACTIVE" | grep -qx "$TARGET"; do
  TARGET="/swapfile_${SIZE_MB}_$n"; n=$((n+1))
done

# If the target file exists but is NOT active, remove it first.
if [[ -f "$TARGET" ]] && ! echo "$ACTIVE" | grep -qx "$TARGET"; then
  rm -f "$TARGET"
fi

info "Creating ${SIZE_MB}M swap at $TARGET (additive — active swaps left untouched)..."
dd if=/dev/zero of="$TARGET" bs=1M count="$SIZE_MB" status=progress
chmod 600 "$TARGET"
mkswap "$TARGET"
swapon "$TARGET"
grep -q "$TARGET" /etc/fstab || echo "$TARGET none swap sw 0 0" >> /etc/fstab

ok "Swap added. Total swap now:"
swapon --show
echo
free -h
warn "Existing active swap(s) were left in place (safe). To remove an old one later,"
warn "first free RAM, then: swapoff <path>  (never swapoff when RAM is nearly full)."
