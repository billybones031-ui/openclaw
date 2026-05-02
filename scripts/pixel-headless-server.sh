#!/usr/bin/env bash
# pixel-headless-server.sh — Configure the Pixel Linux AVF as a persistent
# headless server. Run this on the Pixel (user: droid).
#
# What it does:
#   - Starts OpenSSH server so the laptop can SSH in
#   - Creates systemd user services for OpenClaw Gateway + AionUi
#   - Enables lingering so services survive logout
#   - Prints Tailscale IP + all access URLs
#
# Run once after a fresh setup or AVF restart:
#   bash scripts/pixel-headless-server.sh
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

OPENCLAW_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
AIONUI_PORT="${AIONUI_PORT:-25808}"
OPENCODE_PORT="${OPENCODE_PORT:-8080}"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo ""
echo -e "${BOLD}=== Pixel ISL Headless Server Setup ===${NC}"
echo ""

# ── 1. SSH server ─────────────────────────────────────────────────────────────
echo "1. SSH server"
if command -v sshd > /dev/null 2>&1; then
  if ! pgrep -x sshd > /dev/null 2>&1; then
    sudo service ssh start 2>/dev/null || sudo sshd 2>/dev/null || true
  fi
  if pgrep -x sshd > /dev/null 2>&1; then
    echo -e "   ${GREEN}running${NC}  sshd"
  else
    echo -e "   ${YELLOW}warning${NC}  sshd not started — install with: sudo apt install openssh-server"
  fi
else
  echo -e "   ${YELLOW}missing${NC}  openssh-server — run: sudo apt install -y openssh-server"
fi

# ── 2. Systemd user directory ─────────────────────────────────────────────────
echo "2. Systemd user services"
mkdir -p "$SYSTEMD_USER_DIR"

# Detect openclaw binary / pnpm path
OPENCLAW_BIN="$(command -v openclaw 2>/dev/null || echo "$HOME/.local/bin/openclaw")"
PNPM_BIN="$(command -v pnpm 2>/dev/null || echo "$HOME/.local/bin/pnpm")"
NODE_BIN="$(command -v node 2>/dev/null || echo "$HOME/.local/bin/node")"

# OpenClaw Gateway service
cat > "$SYSTEMD_USER_DIR/openclaw-gateway.service" << EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
ExecStart=${OPENCLAW_BIN} gateway --bind lan --port ${OPENCLAW_PORT}
Restart=on-failure
RestartSec=5
Environment=OPENCLAW_GATEWAY_PORT=${OPENCLAW_PORT}
Environment=PATH=${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:/usr/bin:/bin
StandardOutput=append:%h/openclaw-gateway.log
StandardError=append:%h/openclaw-gateway.log

[Install]
WantedBy=default.target
EOF
echo -e "   ${GREEN}written${NC}  openclaw-gateway.service (port ${OPENCLAW_PORT})"

# AionUi service — detect binary
AIONUI_BIN="$(command -v AionUi 2>/dev/null || command -v aionui 2>/dev/null || echo "")"
if [[ -n "$AIONUI_BIN" ]]; then
  mkdir -p "$HOME/.config/AionUi/logs"
  cat > "$SYSTEMD_USER_DIR/aionui.service" << EOF
[Unit]
Description=AionUi
After=network.target openclaw-gateway.service

[Service]
Type=simple
ExecStart=${AIONUI_BIN} --no-sandbox
Restart=on-failure
RestartSec=5
Environment=AIONUI_HOST=0.0.0.0
Environment=AIONUI_PORT=${AIONUI_PORT}
Environment=PATH=${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:/usr/bin:/bin
StandardOutput=append:%h/.config/AionUi/logs/aionui.log
StandardError=append:%h/.config/AionUi/logs/aionui.log

[Install]
WantedBy=default.target
EOF
  echo -e "   ${GREEN}written${NC}  aionui.service (port ${AIONUI_PORT})"
else
  echo -e "   ${YELLOW}skipped${NC}  aionui.service — AionUi binary not found on PATH"
fi

# ── 3. Reload + enable ────────────────────────────────────────────────────────
echo "3. Enabling services"
SYSTEMD_USER_OK=false
if command -v systemctl > /dev/null 2>&1 && systemctl --user --no-pager show > /dev/null 2>&1; then
  SYSTEMD_USER_OK=true
fi

if $SYSTEMD_USER_OK; then
  systemctl --user daemon-reload
else
  echo -e "   ${YELLOW}warning${NC}  systemd --user unavailable; services won't auto-start — start manually with:"
  echo "     OPENCLAW_GATEWAY_PORT=${OPENCLAW_PORT} ${OPENCLAW_BIN} gateway --bind lan --port ${OPENCLAW_PORT} &"
  [[ -n "${AIONUI_BIN:-}" ]] && echo "     AIONUI_HOST=0.0.0.0 AIONUI_PORT=${AIONUI_PORT} ${AIONUI_BIN} --no-sandbox &"
fi

if $SYSTEMD_USER_OK; then
  if systemctl --user enable openclaw-gateway.service 2>/dev/null; then
    echo -e "   ${GREEN}enabled${NC}  openclaw-gateway"
  else
    echo -e "   ${YELLOW}warning${NC}  could not enable openclaw-gateway"
  fi
fi

if [[ -f "$SYSTEMD_USER_DIR/aionui.service" ]] && $SYSTEMD_USER_OK; then
  if systemctl --user enable aionui.service 2>/dev/null; then
    echo -e "   ${GREEN}enabled${NC}  aionui"
  else
    echo -e "   ${YELLOW}warning${NC}  could not enable aionui"
  fi
fi

# ── 4. Enable lingering (survive logout) ──────────────────────────────────────
echo "4. Lingering (services persist after logout)"
loginctl enable-linger "$USER" 2>/dev/null && \
  echo -e "   ${GREEN}enabled${NC}  linger for $USER" || \
  echo -e "   ${YELLOW}skipped${NC}  loginctl not available (services will stop on logout)"

# ── 5. Start services now ─────────────────────────────────────────────────────
echo "5. Starting services"
systemctl --user start openclaw-gateway.service 2>/dev/null && \
  echo -e "   ${GREEN}started${NC}  openclaw-gateway" || \
  echo -e "   ${YELLOW}warning${NC}  start failed — check: journalctl --user -u openclaw-gateway"

if [[ -f "$SYSTEMD_USER_DIR/aionui.service" ]]; then
  systemctl --user start aionui.service 2>/dev/null && \
    echo -e "   ${GREEN}started${NC}  aionui" || true
fi

# ── 6. Summary ────────────────────────────────────────────────────────────────
TS_IP="$(tailscale ip -4 2>/dev/null || echo "not-connected")"
LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")"

echo ""
echo -e "${BOLD}=== Access URLs ===${NC}"
echo ""
echo -e "  ${CYAN}From laptop via Tailscale (SSH tunnel):${NC}"
echo "    ssh -L ${OPENCLAW_PORT}:localhost:${OPENCLAW_PORT} -L ${AIONUI_PORT}:localhost:${AIONUI_PORT} droid@${TS_IP}"
echo ""
echo -e "  ${CYAN}Direct LAN:${NC}"
echo "    OpenClaw Gateway:  http://${LAN_IP}:${OPENCLAW_PORT}"
echo "    AionUi:            http://${LAN_IP}:${AIONUI_PORT}"
echo ""
echo -e "  ${CYAN}Tailscale direct:${NC}"
echo "    OpenClaw Gateway:  http://${TS_IP}:${OPENCLAW_PORT}"
echo "    AionUi:            http://${TS_IP}:${AIONUI_PORT}"
echo "    Discovery:         http://${TS_IP}:${OPENCLAW_PORT}/.well-known/openclaw-gateway"
echo ""
echo -e "  ${CYAN}SSH config (~/.ssh/config on laptop):${NC}"
cat << SSHEOF
    Host pixel-isl
      HostName ${TS_IP}
      User droid
      LocalForward ${OPENCLAW_PORT} localhost:${OPENCLAW_PORT}
      LocalForward ${AIONUI_PORT} localhost:${AIONUI_PORT}
      LocalForward ${OPENCODE_PORT} localhost:${OPENCODE_PORT}
      ServerAliveInterval 30
      ServerAliveCountMax 3
SSHEOF
echo ""
echo -e "${BOLD}Done. Run 'bash scripts/laptop-connect-pixel.sh ${TS_IP}' from your laptop.${NC}"
