#!/bin/bash
#
# vps-ai-stack/lib/start_novnc.sh
# Installed to /opt/vps-ai-stack/start-novnc.sh by base.sh.
# Robust launcher for TigerVNC + websockify:
#   - kills any stale :1 display before starting
#   - starts vncserver in background, waits for port 5901
#   - runs websockify in a restart loop so a websockify crash does NOT
#     tear down the whole systemd service (avoids the "disconnect loop")
#
set -u

VNC_DISPLAY=":1"
VNC_PORT="5901"
NOVNC_WEB="/opt/novnc"
LISTEN_PORT="6080"
CONF="/etc/vps-ai-stack/vnc.conf"

# Read VNC_BIND (default localhost only)
VNC_BIND="127.0.0.1"
if [[ -f "$CONF" ]]; then
  while IFS='=' read -r k v; do
    case "$k" in
      VNC_BIND) VNC_BIND="${v//[[:space:]]/}" ;;
    esac
  done < "$CONF"
fi
[[ -z "$VNC_BIND" ]] && VNC_BIND="127.0.0.1"

VNCSERVER="$(command -v vncserver 2>/dev/null || echo /usr/bin/vncserver)"
WEBSOCKIFY="$(command -v websockify 2>/dev/null || echo /usr/bin/websockify)"

cleanup_stale() {
  "$VNCSERVER" -kill "$VNC_DISPLAY" >/dev/null 2>&1 || true
  rm -f "/tmp/.X${VNC_DISPLAY#:}-lock" "/tmp/.X11-unix/X${VNC_DISPLAY#:}" 2>/dev/null || true
}

wait_for_port() {
  local host="$1" port="$2" tries=50
  while (( tries-- > 0 )); do
    if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
      exec 3>&- 3<&-
      return 0
    fi
    sleep 0.2
  done
  return 1
}

cleanup_stale

# Start VNC server (background by default on TigerVNC)
"$VNCSERVER" "$VNC_DISPLAY" -geometry 1280x720 -depth 24 >/dev/null 2>&1
if ! wait_for_port 127.0.0.1 "$VNC_PORT"; then
  echo "ERROR: vncserver did not come up on $VNC_PORT" >&2
  exit 1
fi

# Keep websockify alive; restart on exit without restarting vncserver.
while true; do
  echo "[start-novnc] websockify listening on ${VNC_BIND}:${LISTEN_PORT} -> localhost:${VNC_PORT}"
  "$WEBSOCKIFY" --web "$NOVNC_WEB" "${VNC_BIND}:${LISTEN_PORT}" "localhost:${VNC_PORT}"
  echo "[start-novnc] websockify exited, restarting in 2s..."
  sleep 2
done
