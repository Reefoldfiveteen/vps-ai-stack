# vps-ai-stack

One-shot interactive setup for an Ubuntu 24.04 VPS that turns a small Azure VM
(2 vCPU / 1 GiB RAM) into a remote desktop workstation running an AI agent stack:

- **noVNC + TigerVNC + LXQt** — lightweight remote desktop, accessed only through an SSH tunnel
- **Hermes Agent** — self-improving AI coding agent (Nous Research)
- **9Router** — smart AI provider router / OpenAI-compatible gateway

Everything is installed; the AI tools are **not** pre-configured — you configure
Hermes and 9Router yourself via their dashboards / CLIs after install.

## Why noVNC over xrdp?

On a 1 GiB RAM machine every megabyte counts. TigerVNC + noVNC is the lightest
combo: noVNC is browser-based (no RDP client needed) and the VNC backend idles
at ~50–100 MB. xrdp pulls in a heavier session stack. noVNC is bound to
`localhost:6080` only and reached through an SSH tunnel, so nothing is exposed
to the internet.

## Requirements

- Ubuntu 24.04 LTS (tested on Azure B2ats v2: 2 vCPU, 1 GiB RAM, ~30 GB disk)
- Root / sudo access
- SSH (port 22) reachable from your laptop
- A swap file is auto-created (50% of RAM, capped 512 MB–2 GB)

## Quick start

```bash
# On the VPS, as root:
sudo apt-get update -y && sudo apt-get install -y git
git clone https://github.com/Reefoldfiveteen/vps-ai-stack.git
cd vps-ai-stack
sudo bash setup.sh
```

You will be prompted for:

1. **Target username** (default `reefii`) — services run as this user.
2. **VNC password** (6–8 chars) — used to unlock the remote desktop.

Then pick a menu option:

| Option | What it does |
|--------|--------------|
| `1` | Install base system (LXQt + TigerVNC + noVNC + swap + UFW) |
| `2` | Install Hermes Agent (download + deps only) |
| `3` | Install 9Router (`npm install -g`, runs as your user) |
| `4` | Install Falkon (lightweight Qt browser for LXQt) |
| `5` | Install everything (1 → 2 → 3 → 4) |
| `6` | Print the access & security guide |
| `7` | Exit |

> **Browser note:** Falkon is a lightweight Qt/QtWebEngine browser that blends
> with LXQt. On a 1 GiB VPS keep tabs minimal and close it when not in use —
> browse from your laptop via the SSH tunnel when you can. |

After install, a reboot is recommended so the per-user systemd services start cleanly.

## Accessing the remote desktop

noVNC is **not** exposed to the internet. From your laptop, open an SSH tunnel:

```bash
ssh -L 6080:localhost:6080 reefii@<VPS_IP>
```

Then open your browser:

```
http://localhost:6080
```

Enter the VNC password you set during install. The VPS public IP is auto-detected
and shown at the end of the base install.

## Configuring the AI tools

### 9Router
Forward its dashboard port too (or open it inside the noVNC browser):

```bash
ssh -L 20128:localhost:20128 reefii@<VPS_IP>
```

Open `http://localhost:20128/dashboard` and connect providers (Kiro AI, OpenCode
Free, etc.). 9Router serves the OpenAI-compatible endpoint at
`http://localhost:20128/v1`.

### Hermes
Inside the noVNC desktop terminal:

```bash
hermes            # start chatting
hermes model      # pick a provider — point it at 9Router: http://localhost:20128/v1
hermes setup      # full setup wizard
```

## Service management

All services run as **user** systemd units (auto-start on boot via
`loginctl enable-linger`). Manage them as the target user:

```bash
systemctl --user status novnc-desktop
systemctl --user status 9router
systemctl --user restart novnc-desktop
systemctl --user restart 9router
```

If the user bus is unavailable (e.g. before the first reboot, or a host where
`systemctl --user` cannot connect), start everything directly without systemd:

```bash
sudo bash start-services.sh reefii
# tunnel: ssh -L 6080:localhost:6080 -L 20128:localhost:20128 reefii@<VPS_IP>
```

After a reboot the systemd services come up on their own (linger is enabled).

## Updating the repo (push to GitHub)

`update.sh` commits all local changes and pushes to the GitHub repo. Run it from
inside the cloned directory:

```bash
bash update.sh                 # auto message: "update: <timestamp>"
bash update.sh "fix: vnc bind" # custom commit message
```

To update the running **Hermes / 9Router** services on the VPS instead, use the
tools themselves (e.g. `hermes update`, `npm update -g 9router`) and then
`systemctl --user restart ...`.

## Security notes

- **UFW** is enabled: deny all inbound, allow SSH only.
- **noVNC** binds to `127.0.0.1` — port 6080 is never open to the internet.
- In the Azure NSG, do **not** open ports `6080` or `20128` to `0.0.0.0/0`.
- If you ever need external access, put it behind a reverse proxy with TLS + auth.

## Uninstall

```bash
# Stop + disable services
systemctl --user disable --now novnc-desktop 9router

# Remove packages
sudo apt-get remove -y lxqt-core tigervnc-standalone-server

# Remove swap
sudo swapoff /swapfile && sudo rm -f /swapfile
sudo sed -i '/\/swapfile/d' /etc/fstab
```

## Resource budget (1 GiB RAM)

| Component | Idle RAM |
|-----------|----------|
| Ubuntu base | ~200 MB |
| LXQt + TigerVNC | ~300 MB |
| noVNC (websockify) | ~50 MB |
| 9Router | ~150 MB |
| Hermes (idle) | ~300 MB |
| **Total** | **~1000 MB** |

Swap absorbs the overflow. Keep heavy browser tabs closed on the VPS; do your
browsing on your laptop and only use the remote desktop for terminal + Hermes.

## License

MIT — use freely.
