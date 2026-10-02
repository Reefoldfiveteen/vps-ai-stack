#!/bin/bash
#
# vps-ai-stack/lib/access_guide.sh
# Prints access + security guide using detected VPS IP.
#
set -uo pipefail

USERNAME="${SETUP_USER:-reefii}"
VPS_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
[[ -z "$VPS_IP" ]] && VPS_IP="<VPS_IP>"

cat <<EOF

========================================================
  ACCESS & SECURITY GUIDE  (user: $USERNAME)
========================================================

1) REMOTE DESKTOP
--------------------------------------------------------
A) If you use XRDP (Native Remote Desktop / mstsc):
   From your laptop terminal:
       ssh -L 3389:localhost:3389 $USERNAME@$VPS_IP

   Then open Remote Desktop Connection (mstsc) on Windows:
       Computer: localhost:3389
       Username: $USERNAME
       Password: (your user Linux password)

B) If you use noVNC (Browser-based):
   From your laptop terminal:
       ssh -L 6080:localhost:6080 $USERNAME@$VPS_IP

   Then open in your browser:
       http://localhost:6080
   (Enter the VNC password you set during install)

2) 9ROUTER DASHBOARD
--------------------------------------------------------
Start 9Router desktop session via your remote desktop browser, OR
forward its port directly to your laptop:

    ssh -L 20128:localhost:20128 $USERNAME@$VPS_IP

Then open: http://localhost:20128/dashboard

3) HERMES
--------------------------------------------------------
Inside the remote desktop terminal, run:

    hermes            # chat
    hermes model      # pick provider (point to 9Router: http://localhost:20128/v1)
    hermes setup      # full wizard

4) SECURITY NOTES
--------------------------------------------------------
- UFW: deny all inbound, allow SSH only.
- Services bind to 127.0.0.1 (localhost) inside VPS.
- Never open port 3389, 6080, or 20128 to 0.0.0.0 in Cloud NSG / Firewall.
- All connections are safely tunneled through SSH.

5) SERVICE MANAGEMENT
--------------------------------------------------------
# XRDP (system service):
sudo systemctl status xrdp
sudo systemctl restart xrdp

# noVNC & 9Router (user services):
systemctl --user status novnc-desktop
systemctl --user status 9router
systemctl --user restart novnc-desktop
systemctl --user restart 9router

========================================================
EOF
