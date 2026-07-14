#!/bin/bash
#
# vps-ai-stack/lib/start_novnc.sh
# Installed to /opt/vps-ai-stack/start-novnc.sh by base.sh.
# Robust launcher for TigerVNC + websockify. Designed to NEVER hard-exit,
# so a slow/transient VNC startup or a websockify crash cannot trigger a
# systemd restart storm ("disconnect loop").
#
set -u

VNC_DISPLAY=":1"
VNC_PORT="5901"
NOVNC_WEB="/opt/novnc"
LISTEN_PORT="6080"
CONF="/etc/vps-ai-stack/vnc.conf"
LOG="/tmp/vps-ai-stack-novnc.log"

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

# Singleton: never run two launchers at once — they would fight over the
# listen port (each kills the other's websockify). If another instance is
# already running, exit and let it keep the port.
if pgrep -f "start-novnc.sh" | grep -v -x "$$" >/dev/null 2>&1; then
  log "another start-novnc.sh already running (pid $(pgrep -f 'start-novnc.sh' | grep -v -x "$$" | head -1)) — exiting to avoid port fight"
  exit 1
fi

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

port_up() {
  local p="$1" i=0
  while (( i++ < 75 )); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then
      exec 3>&- 3<&-
      return 0
    fi
    sleep 0.4
  done
  return 1
}

ensure_vnc() {
  if port_up "$VNC_PORT"; then
    return 0
  fi
  log "vnc not up on $VNC_PORT, starting $VNCSERVER $VNC_DISPLAY"
  "$VNCSERVER" -kill "$VNC_DISPLAY" >>"$LOG" 2>&1 || true
  rm -f "/tmp/.X${VNC_DISPLAY#:}-lock" "/tmp/.X11-unix/X${VNC_DISPLAY#:}" 2>/dev/null || true
  # Log output (do NOT discard) and bound the start so a stuck vncserver
  # cannot hang the launcher forever.
  timeout 30 "$VNCSERVER" "$VNC_DISPLAY" -geometry 1280x720 -depth 24 >>"$LOG" 2>&1 || \
    log "vncserver exited with code $? (see log above)"
  if port_up "$VNC_PORT"; then
    log "vnc up"
    return 0
  fi
  return 1
}

# Outer loop: keep the whole thing alive forever (systemd Restart=always is
# just a backstop). If vnc fails to start we wait and retry; if websockify
# exits we restart it while leaving vnc running.
while true; do
  if ! ensure_vnc; then
    log "vnc failed to start, retry in 5s"
    sleep 5
    continue
  fi
  log "starting websockify on ${VNC_BIND}:${LISTEN_PORT} -> localhost:${VNC_PORT}"
  # Free the listen port in case a stale websockify is still bound to it.
  pkill -9 -f 'websockify' >/dev/null 2>&1 || true
  pkill -9 -f 'novnc_proxy' >/dev/null 2>&1 || true
  "$WEBSOCKIFY" --web "$NOVNC_WEB" "${VNC_BIND}:${LISTEN_PORT}" "localhost:${VNC_PORT}" >>"$LOG" 2>&1
  log "websockify exited, restarting in 2s"
  sleep 2
done
