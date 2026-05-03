# AionUi Integration

OpenClaw Gateway works as a first-class agent inside [AionUi](https://aionui.dev) (v1.9.23+).
AionUi auto-detects OpenClaw on startup by locating the `openclaw` binary and querying the
agent discovery endpoint.

---

## Phase 1: Network access

### 1.1 Start AionUi bound to all interfaces

```bash
AIONUI_HOST=0.0.0.0 AionUi --no-sandbox --webui > ~/aionui.log 2>&1 &
```

AionUi's WebUI runs on port **25808** by default.

### 1.2 Start OpenClaw Gateway in LAN mode

Use the provided helper script so the gateway is reachable on the same network:

```bash
./scripts/start-openclaw-aionui.sh
```

This starts the gateway with `--bind lan` (binds to `0.0.0.0`) on port **18789** and prints
the local, LAN, and Tailscale access URLs.

To auto-start on login, add to `~/.bashrc`:

```bash
if ! pgrep -f "openclaw gateway" > /dev/null; then
  /path/to/openclaw/scripts/start-openclaw-aionui.sh
fi
```

### 1.3 Tailscale (cross-device access)

```bash
sudo tailscale up --accept-routes
tailscale ip -4   # save this — format 100.x.x.x
```

From another device (Chromebook, phone), access both services via Tailscale:

| Service | URL |
|---------|-----|
| AionUi | `http://<tailscale-ip>:25808` |
| OpenClaw Gateway | `http://<tailscale-ip>:18789` |
| OpenClaw discovery | `http://<tailscale-ip>:18789/.well-known/openclaw-gateway` |

---

## Phase 2: AionUi first login

```
URL:      http://localhost:25808
Username: admin
Password: (set during AionUi installation)
```

Add your API keys under **Settings → Models → Add Provider**.

---

## Phase 3: Agent configuration

### 3.1 Auto-detected agents

AionUi scans `$PATH` for known CLI tools. Ensure all agents are installed and reachable:

```bash
# Claude Code
npm install -g @anthropic-ai/claude-code
claude --version

# Gemini CLI
npm install -g @google/gemini-cli
gemini auth login
gemini --version

# OpenCode, Aider
npm install -g opencode
pip install aider-chat

# Verify OpenClaw is on PATH
openclaw --version
```

### 3.2 OpenClaw discovery endpoint

OpenClaw exposes a machine-readable agent manifest at:

```
GET /.well-known/openclaw-gateway
```

Example response:

```json
{
  "name": "OpenClaw Gateway",
  "type": "openclaw-gateway",
  "version": "2025.x.x",
  "protocol": "openclaw-gateway/v1",
  "capabilities": ["chat", "agents", "channels", "cron", "mcp", "skills"],
  "healthUrl": "/health",
  "wsPath": "/"
}
```

No authentication is required for this endpoint.

### 3.3 Configure OpenClaw in AionUi

In AionUi: **Settings → Agents → OpenClaw Gateway → Configure**

- Set the gateway URL: `http://localhost:18789` (or your Tailscale URL)
- Set your `ANTHROPIC_API_KEY` as the backend key
- AionUi will connect over WebSocket (`ws://localhost:18789`)

### 3.4 MCP tools

Configure MCP servers once in AionUi under **Settings → MCP Tools**. AionUi syncs the
configuration to all connected agents automatically.

---

## Phase 4: Persistence

The `scripts/start-openclaw-aionui.sh` script manages a PID file at
`~/.openclaw-aionui.pid` and logs to `~/openclaw-aionui.log`. Re-running it after an AVF
restart cleanly replaces any stale process.

For Chromebook SSH access, add to `~/.ssh/config`:

```
Host gateway-host
  HostName <gateway-ip>
  User <username>
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

---

## Phase 5: Verification

Run the full 8-test verification suite:

```bash
./scripts/verify-aionui-setup.sh
```

Tests covered:

| # | Test | Pass condition |
|---|------|----------------|
| 1 | Gateway health | `GET /health` → HTTP 200 |
| 2 | Process running | `pgrep openclaw` returns PID |
| 3 | Agent discovery | `/.well-known/openclaw-gateway` returns JSON manifest |
| 4 | Tailscale | `tailscale status` succeeds |
| 5 | Cross-device access | Tailscale IP health check → HTTP 200 |
| 6 | Claude Code CLI | `claude --version` returns version |
| 7 | Gemini CLI | `gemini --version` returns version |
| 8 | Multi-agent readiness | `claude` + `gemini` + openclaw-gateway all available |

The script exits with the number of failed tests (0 = all pass) and prints a full
deployment report.

---

## Team mode (Postbox loop)

AionUi's **Team mode** orchestrates multiple agents as Leader + Teammates. OpenClaw
participates as a teammate alongside other CLI agents.

To run the Postbox loop from the guide:

1. In AionUi, create a new **Team**
2. Set **Gemini** as Leader
3. Add **Claude Code** as Teammate
4. Send task: `"Review ~/your-project and list 3 improvements"`

Both agents receive the task, respond independently, and AionUi merges the results.

Prerequisite: Tests 6, 7, and 8 above must all pass (all CLI tools on PATH, gateway
reachable).

---

## Troubleshooting

**Gateway not detected by AionUi**
- Confirm `openclaw` is on `$PATH`: `which openclaw`
- Confirm gateway is running in LAN mode: `curl http://localhost:18789/.well-known/openclaw-gateway`

**Cross-device access fails (Test 5)**
- Gateway must be started with `--bind lan`. Use `scripts/start-openclaw-aionui.sh`.
- Tailscale must be running on both devices.

**Tailscale IP unreachable**
- Run `sudo tailscale up --accept-routes` on the AVF side.
- Confirm both devices appear in `tailscale status`.
