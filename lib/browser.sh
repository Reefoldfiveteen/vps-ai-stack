#!/bin/bash
#
# vps-ai-stack/lib/browser.sh
# Lets the user choose which browser to install (Brave or Firefox), then
# delegates to the matching installer. Both are memory-heavy on a 1 GiB VPS.
#
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "Which browser do you want to install?"
echo "  [1] Brave   (Chromium-based, official Brave apt repo)"
echo "  [2] Firefox (native .deb via Mozilla apt repo; avoids Ubuntu's snap)"
echo
read -r -p "Selection [1]: " B
B="${B:-1}"

case "$B" in
  1) bash "$LIB_DIR/brave.sh" ;;
  2) bash "$LIB_DIR/firefox.sh" ;;
  *) err(){ :; }; echo "[-] Invalid selection."; exit 1 ;;
esac
