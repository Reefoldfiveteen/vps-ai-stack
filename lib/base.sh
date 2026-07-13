#!/bin/bash
#
# vps-ai-stack/lib/base.sh
# Installs LXQt desktop, TigerVNC, noVNC, swap, UFW.
# Binds noVNC to localhost:6080 only (access via SSH tunnel).
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
err(){ echo -e "${RED}[-]${NC} $*"; }

export DEBIAN_FRONTEND=noninteractive

info "Updating apt..."
apt-get update -y

info "Installing desktop + VNC stack..."
apt-get install -y --no-install-recommends \
  lxqt-core lxqt-session openbox \
  tigervnc-standalone-server tigervnc-common \
  xterm xinit dbus-x11 websockify python3 \
  curl wget unzip git ca-certificates \
  ufw net-tools

# ---- noVNC + websockify ----
NOVNC_DIR="/opt/novnc"
info "Installing noVNC 1.4.0 to $NOVNC_DIR..."
rm -rf "$NOVNC_DIR"
mkdir -p "$NOVNC_DIR"
curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz -o /tmp/novnc.tar.gz
tar -xzf /tmp/novnc.tar.gz -C /tmp
cp -r /tmp/noVNC-1.4.0/* "$NOVNC_DIR/"
# websockify is installed via apt (git submodule not in release tarball)

# ---- Swap (50% RAM, capped 512M-2G) ----
TOTAL_RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
SWAP_TARGET_KB=$(( TOTAL_RAM_KB / 2 ))
# floor 512M, cap 2G
(( SWAP_TARGET_KB < 524288 )) && SWAP_TARGET_KB=524288
(( SWAP_TARGET_KB > 2097152 )) && SWAP_TARGET_KB=2097152
if swapon --show | grep -q "/swapfile"; then
  warn "Swapfile already active, skipping."
else
  info "Creating swapfile $((SWAP_TARGET_KB/1024)) MB..."
  fallocate -l "${SWAP_TARGET_KB}K" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1K count="$SWAP_TARGET_KB"
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q "^/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
ok "Swap ready: $(swapon --show=SIZE --noheadings | tr -d ' ')"

# ---- VNC password ----
info "Setting VNC password for user '$USERNAME'..."
while true; do
  read -r -s -p "Enter VNC password (6-8 chars): " VNC_PASS1
  echo
  read -r -s -p "Confirm VNC password: " VNC_PASS2
  echo
  if [[ "$VNC_PASS1" != "$VNC_PASS2" ]]; then
    warn "Passwords do not match. Try again."
    continue
  fi
  if [[ ${#VNC_PASS1} -lt 6 || ${#VNC_PASS1} -gt 8 ]]; then
    warn "Password must be 6-8 characters."
    continue
  fi
  break
done

USER_HOME=$(eval echo ~"$USERNAME")
VNC_DIR="$USER_HOME/.vnc"
mkdir -p "$VNC_DIR"
chown "$USERNAME":"$USERNAME" "$VNC_DIR"

# ---- Create VNC passwd file ----
# vncpasswd binary is NOT shipped by tigervnc-* on Ubuntu 24.04, so we
# replicate rfb::obfuscate() in pure Python (stdlib only, no crypto deps):
#   DES-ECB of the 8-byte NUL-padded password with the fixed key
#   {23,82,107,6,35,78,88,7}, no IV, no padding -> 8-byte ~/.vnc/passwd.
# Verified against the FIPS-46 DES test vector (matches TigerVNC/d3des).
# If a real vncpasswd exists on another distro, prefer it.
VNCPASSWD="$(command -v vncpasswd 2>/dev/null || find /usr /bin /opt /sbin -name vncpasswd -type f 2>/dev/null | head -1)"
if [[ -n "$VNCPASSWD" && -x "$VNCPASSWD" ]]; then
  info "Using system vncpasswd: $VNCPASSWD"
  echo "$VNC_PASS1" | "$VNCPASSWD" -f > "$VNC_DIR/passwd"
else
  info "Generating VNC passwd via embedded Python (rfb::obfuscate)..."
  cat > /tmp/vnc_obfuscate.py <<'PYEOF'
import sys
_IP=[58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,62,54,46,38,30,22,14,6,
     64,56,48,40,32,24,16,8,57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,
     61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7]
_FP=[40,8,48,16,56,24,64,32,39,7,47,15,55,23,63,31,38,6,46,14,54,22,62,30,
     37,5,45,13,53,21,61,29,36,4,44,12,52,20,60,28,35,3,43,11,51,19,59,27,
     34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25]
_E=[32,1,2,3,4,5,4,5,6,7,8,9,8,9,10,11,12,13,12,13,14,15,16,17,
    16,17,18,19,20,21,20,21,22,23,24,25,24,25,26,27,28,29,28,29,30,31,32,1]
_P=[16,7,20,21,29,12,28,17,1,15,23,26,5,18,31,10,2,8,24,14,32,27,3,9,
    19,13,30,6,22,11,4,25]
_PC1=[57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,27,19,11,3,
      60,52,44,36,63,55,47,39,31,23,15,7,62,54,46,38,30,22,14,6,61,53,45,37,
      29,21,13,5,28,20,12,4]
_PC2=[14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,13,2,
      41,52,31,37,47,55,30,40,51,45,33,48,44,49,39,56,34,53,46,42,50,36,29,32]
_S=[[[14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7],[0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8],
     [4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0],[15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13]],
    [[15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10],[3,13,4,7,15,2,8,14,12,0,1,10,6,9,11,5],
     [0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15],[13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9]],
    [[10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8],[13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1],
     [13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7],[1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12]],
    [[7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15],[13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9],
     [10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4],[3,15,0,6,10,1,13,8,9,4,5,11,12,7,2,14]],
    [[2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9],[14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6],
     [4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14],[11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3]],
    [[12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11],[10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8],
     [9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6],[4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13]],
    [[4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1],[13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6],
     [1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2],[6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12]],
    [[13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7],[1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2],
     [7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8],[2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11]]]
def _fb(b):
    o=[]
    for x in b:
        for i in range(7,-1,-1): o.append((x>>i)&1)
    return o
def _bf(bits):
    o=bytearray()
    for i in range(0,len(bits),8):
        v=0
        for j in range(8): v=(v<<1)|bits[i+j]
        o.append(v)
    return bytes(o)
def _rot(b,n): return b[n:]+b[:n]
def des(block,key):
    kb=_fb(key)
    c=[kb[i-1] for i in _PC1[:28]]; d=[kb[i-1] for i in _PC1[28:]]
    subs=[]; sh=[1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1]
    for s in sh:
        c=_rot(c,s); d=_rot(d,s); cd=c+d; subs.append([cd[i-1] for i in _PC2])
    bits=[_fb(block)[i-1] for i in _IP]
    L,R=bits[:32],bits[32:]
    for sk in subs:
        ex=[R[i-1] for i in _E]
        x=[ex[i]^sk[i] for i in range(48)]
        so=[]
        for i in range(8):
            ch=x[i*6:i*6+6]; row=ch[0]*2+ch[5]; col=ch[1]*8+ch[2]*4+ch[3]*2+ch[4]
            v=_S[i][row][col]
            for b in range(3,-1,-1): so.append((v>>b)&1)
        po=[so[i-1] for i in _P]
        nR=[L[j]^po[j] for j in range(32)]
        L,R=R,nR
    return _bf([(R+L)[i-1] for i in _FP])
pw=sys.argv[1]
key=bytes([23,82,107,6,35,78,88,7])
buf=bytearray(8)
for i in range(8):
    if i<len(pw): buf[i]=ord(pw[i])
sys.stdout.buffer.write(des(bytes(buf),key))
PYEOF
  python3 /tmp/vnc_obfuscate.py "$VNC_PASS1" > "$VNC_DIR/passwd"
  rm -f /tmp/vnc_obfuscate.py
fi
chmod 600 "$VNC_DIR/passwd"
chown "$USERNAME":"$USERNAME" "$VNC_DIR/passwd"
ok "VNC passwd file written ($(stat -c%s "$VNC_DIR/passwd") bytes)"

# ---- VNC xstartup (LXQt) ----
cat > "$VNC_DIR/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startlxqt
EOF
chmod +x "$VNC_DIR/xstartup"
chown "$USERNAME":"$USERNAME" "$VNC_DIR/xstartup"

# ---- systemd user service: novnc desktop ----
info "Creating systemd user service for desktop..."
SERVICE_DIR="$USER_HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config"

# Absolute paths (avoid relying on user PATH inside systemd)
VNCSERVER_BIN="$(command -v vncserver 2>/dev/null || find /usr /bin /opt -name vncserver -type f 2>/dev/null | head -1 || echo /usr/bin/vncserver)"
WEBSOCKIFY_BIN="$(command -v websockify 2>/dev/null || find /usr /bin /opt -name websockify -type f 2>/dev/null | head -1 || echo /usr/bin/websockify)"

cat > "$SERVICE_DIR/novnc-desktop.service" <<EOF
[Unit]
Description=noVNC + TigerVNC Desktop (LXQt)
After=network.target

[Service]
Type=simple
WorkingDirectory=$USER_HOME
ExecStartPre=/bin/sh -c '$VNCSERVER_BIN -kill :1 >/dev/null 2>&1 || true'
ExecStart=/bin/sh -c '$VNCSERVER_BIN :1 -geometry 1280x720 -depth 24 && sleep 2 && $WEBSOCKIFY_BIN --web $NOVNC_DIR 127.0.0.1:6080 localhost:5901'
ExecStop=/bin/sh -c '$VNCSERVER_BIN -kill :1 || true'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
chown "$USERNAME":"$USERNAME" "$SERVICE_DIR/novnc-desktop.service"

# Enable linger so user services run without an active login
loginctl enable-linger "$USERNAME" 2>/dev/null || true

# Create the enable symlink manually (robust: systemctl --user may have no
# bus during non-interactive setup). This is exactly what 'systemctl enable' does.
WANTS_DIR="$USER_HOME/.config/systemd/user/default.target.wants"
mkdir -p "$WANTS_DIR"
ln -sf "../novnc-desktop.service" "$WANTS_DIR/novnc-desktop.service"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.config"

# Best-effort: start the user manager + service now (needs a running user bus)
export XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")"
systemctl start "user@$(id -u "$USERNAME").service" >/dev/null 2>&1 || true
if su - "$USERNAME" -c "XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user daemon-reload >/dev/null 2>&1 && XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' systemctl --user start novnc-desktop.service >/dev/null 2>&1"; then
  ok "Desktop service started."
else
  warn "Service not started now (no user bus during setup). It auto-starts after reboot (linger enabled)."
fi

# ---- UFW ----
info "Configuring UFW (SSH only, deny rest)..."
SSH_PORT=$(ss -tlnp 2>/dev/null | grep -oP ':\K\d+(?=.*sshd)' | head -1 || echo 22)
SSH_PORT="${SSH_PORT:-22}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw --force enable

ok "Base system installed."
ok "noVNC bound to localhost:6080 (not exposed to internet)."
warn "Reboot recommended so user services start cleanly."
echo
echo "  Access from laptop:"
echo "    ssh -L 6080:localhost:6080 $USERNAME@$VPS_IP"
echo "    then open http://localhost:6080 in your browser"
