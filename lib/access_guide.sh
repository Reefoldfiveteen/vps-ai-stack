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

1) REMOTE DESKTOP (noVNC) - SSH tunnel only
--------------------------------------------------------
From your laptop terminal:

    ssh -L 6080:localhost:6080 $USERNAME@$VPS_IP

Then open in your browser:

    http://localhost:6080

Enter the VNC password you set during install.
Port 6080 is NOT open to the internet (UFW blocks it).

2) 9ROUTER DASHBOARD
--------------------------------------------------------
Start 9Router desktop session via the noVNC browser, OR
forward its port too:

    ssh -L 20128:localhost:20128 $USERNAME@$VPS_IP

Then open: http://localhost:20128/dashboard

3) HERMES
--------------------------------------------------------
Inside the noVNC desktop, open terminal and run:

    hermes            # chat
    hermes model      # pick provider (point to 9Router: http://localhost:20128/v1)
    hermes setup      # full wizard

4) SECURITY NOTES
--------------------------------------------------------
- UFW: deny all inbound, allow SSH only.
- noVNC binds to 127.0.0.1 (localhost) inside VPS.
- Never open port 6080 / 20128 to 0.0.0.0 in Azure NSG.
- If you must expose, put behind reverse proxy + TLS + auth.

5) SERVICE MANAGEMENT (as $USERNAME on VPS)
--------------------------------------------------------
systemctl --user status novnc-desktop
systemctl --user status 9router
systemctl --user restart novnc-desktop
systemctl --user restart 9router

========================================================
EOF
