#!/usr/bin/env bash
# ISL Nexus Terminal — AionUi + OpenClaw verification suite (8 tests).
# Run after completing setup to confirm everything is wired correctly.
#
# Usage:
#   ./scripts/verify-aionui-setup.sh
set -uo pipefail

# Resolve port: OPENCLAW_GATEWAY_PORT env var → gateway.port in config → 18789.
# Mirrors resolveGatewayPort() in src/config/paths.ts so tests probe the right endpoint.
_OPENCLAW_CFG="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}/openclaw.json"
_CFG_PORT=""
if [[ -f "$_OPENCLAW_CFG" ]]; then
  _CFG_PORT="$(node -e "try{const c=JSON.parse(require('fs').readFileSync('${_OPENCLAW_CFG}','utf8'));process.stdout.write(String(c?.gateway?.port||''))}catch(_){}" 2>/dev/null || true)"
fi
PORT="${OPENCLAW_GATEWAY_PORT:-${_CFG_PORT:-18789}}"
BASE="http://localhost:${PORT}"

PASS=0
FAIL=0

green() { printf '\033[0;32m%s\033[0m' "$*"; }
red()   { printf '\033[0;31m%s\033[0m' "$*"; }

pass() { echo "  $(green PASS) — $1"; PASS=$((PASS + 1)); }
fail() { echo "  $(red FAIL) — $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "=============================================="
echo " ISL Nexus Terminal — AionUi Setup Verification"
echo " OpenClaw port: ${PORT}"
echo "=============================================="
echo ""

# ── TEST 1: Gateway health ────────────────────────────────────────────────────
echo "TEST 1 — Gateway health"
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${BASE}/health" 2>/dev/null || true)"
HTTP_CODE="${HTTP_CODE:-000}"
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "GET /health → HTTP ${HTTP_CODE}"
else
  fail "GET /health → HTTP ${HTTP_CODE} (gateway not running — run: scripts/start-openclaw-aionui.sh)"
fi

# ── TEST 2: Process running ───────────────────────────────────────────────────
echo "TEST 2 — OpenClaw gateway process"
if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
  PID="$(pgrep -f "openclaw gateway" | head -1)"
  pass "openclaw gateway running (PID ${PID})"
else
  fail "openclaw gateway not running — start with: scripts/start-openclaw-aionui.sh"
fi

# ── TEST 3: Agent discovery endpoint ─────────────────────────────────────────
echo "TEST 3 — Agent discovery endpoint"
DISCOVERY="$(curl -s "${BASE}/.well-known/openclaw-gateway" 2>/dev/null || echo "")"
if echo "$DISCOVERY" | grep -q '"type":"openclaw-gateway"'; then
  VERSION_VAL="$(echo "$DISCOVERY" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)"
  pass "/.well-known/openclaw-gateway returns agent manifest (version: ${VERSION_VAL})"
else
  fail "/.well-known/openclaw-gateway did not return expected JSON"
fi

# ── TEST 4: Tailscale connectivity ────────────────────────────────────────────
echo "TEST 4 — Tailscale"
if tailscale status > /dev/null 2>&1; then
  TS_IP="$(tailscale ip -4 2>/dev/null || echo "unknown")"
  pass "Tailscale connected (IP: ${TS_IP})"
else
  fail "Tailscale not connected — run: sudo tailscale up --accept-routes"
fi

# ── TEST 5: Cross-device access via Tailscale ─────────────────────────────────
echo "TEST 5 — Cross-device access (Tailscale)"
TS_IP="$(tailscale ip -4 2>/dev/null || echo "")"
if [[ -z "$TS_IP" ]]; then
  fail "Skipped — Tailscale IP unavailable"
else
  TS_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${TS_IP}:${PORT}/health" 2>/dev/null || true)"
  TS_CODE="${TS_CODE:-000}"
  if [[ "$TS_CODE" == "200" ]]; then
    pass "http://${TS_IP}:${PORT}/health → HTTP ${TS_CODE}"
  else
    fail "http://${TS_IP}:${PORT}/health → HTTP ${TS_CODE} (ensure gateway uses --bind lan)"
  fi
fi

# ── TEST 6: Claude Code CLI ───────────────────────────────────────────────────
echo "TEST 6 — Claude Code CLI"
CLAUDE_OK=false
if CLAUDE_VER="$(claude --version 2>/dev/null)"; then
  pass "claude --version → ${CLAUDE_VER}"
  CLAUDE_OK=true
else
  fail "claude not found — run: npm install -g @anthropic-ai/claude-code"
fi

# ── TEST 7: Gemini CLI ────────────────────────────────────────────────────────
echo "TEST 7 — Gemini CLI"
GEMINI_OK=false
if GEMINI_VER="$(gemini --version 2>/dev/null)"; then
  pass "gemini --version → ${GEMINI_VER}"
  GEMINI_OK=true
else
  fail "gemini not found — run: npm install -g @google/gemini-cli && gemini auth login"
fi

# ── TEST 8: Multi-agent readiness (Postbox loop prerequisites) ────────────────
echo "TEST 8 — Multi-agent readiness (Postbox loop)"
OPENCLAW_OK=false
[[ "$HTTP_CODE" == "200" ]] && OPENCLAW_OK=true

if $CLAUDE_OK && $GEMINI_OK && $OPENCLAW_OK; then
  pass "claude ✓  gemini ✓  openclaw-gateway ✓ — ready for AionUi Team mode"
else
  MISSING=""
  $CLAUDE_OK   || MISSING="${MISSING} claude"
  $GEMINI_OK   || MISSING="${MISSING} gemini"
  $OPENCLAW_OK || MISSING="${MISSING} openclaw-gateway"
  fail "Missing:${MISSING} — resolve failing tests above first"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
TOTAL=$((PASS + FAIL))
echo " Results: ${PASS}/${TOTAL} passed"
echo "=============================================="
echo ""

# ── Deployment report ─────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENCLAW_VER="$(node -e "console.log(require('${REPO_ROOT}/package.json').version)" 2>/dev/null || echo "unknown")"
TS_IP_REPORT="$(tailscale ip -4 2>/dev/null || echo "NOT CONNECTED")"
NODE_VER="$(node --version 2>/dev/null || echo "unknown")"
PYTHON_VER="$(python3 --version 2>/dev/null || echo "unknown")"
CLAUDE_REPORT="$(claude --version 2>/dev/null || echo "NOT INSTALLED")"
GEMINI_REPORT="$(gemini --version 2>/dev/null || echo "NOT INSTALLED")"
OPENCODE_REPORT="$(opencode --version 2>/dev/null || echo "NOT INSTALLED")"
AIDER_REPORT="$(aider --version 2>/dev/null || echo "NOT INSTALLED")"

cat << EOF
================================================
ISL NEXUS TERMINAL — DEPLOYMENT REPORT
$(date)
================================================
OpenClaw Version:  ${OPENCLAW_VER}
Gateway Status:    HTTP ${HTTP_CODE}
Tailscale IP:      ${TS_IP_REPORT}
Node Version:      ${NODE_VER}
Python Version:    ${PYTHON_VER}

CLI TOOLS:
Claude Code:  ${CLAUDE_REPORT}
Gemini CLI:   ${GEMINI_REPORT}
OpenCode:     ${OPENCODE_REPORT}
Aider:        ${AIDER_REPORT}

ACCESS URLS:
Local:        ${BASE}
Discovery:    ${BASE}/.well-known/openclaw-gateway
Tailscale:    http://${TS_IP_REPORT}:${PORT}

PROCESS:
$(pgrep -af "openclaw gateway" 2>/dev/null || echo "not running")

DISK:
$(df -h ~ 2>/dev/null | tail -1 || echo "unknown")

MEMORY:
$(free -h 2>/dev/null | grep Mem || echo "unknown")
================================================
STATUS: $([ "$FAIL" -eq 0 ] && echo "✅ ALL TESTS PASSED" || echo "❌ ${FAIL} TEST(S) FAILED — see details above")
================================================
EOF

exit "$FAIL"
