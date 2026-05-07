#!/usr/bin/env bash
# pixel-cleanup.sh — Remove handoff debris from the Pixel Linux environment.
# Safe to run: only touches artifacts created by the accidental claude-code
# handoff session. All intentional dev tools, configs, and projects are kept.
set -euo pipefail

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

removed=0
skipped=0

rm_if_exists() {
  local path="$1"
  local reason="$2"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    echo -e "  ${GREEN}removed${NC}  $path  ($reason)"
    removed=$((removed + 1))
  else
    skipped=$((skipped + 1))
  fi
}

echo ""
echo -e "${BOLD}=== Pixel handoff debris cleanup ===${NC}"
echo ""

# ── Handoff staging artifacts ─────────────────────────────────────────────────
echo "Claude Desktop Debian staging (created by accidental handoff run):"
rm_if_exists "$HOME/.cache/claude-desktop-debian" "handoff staging dir"

echo ""
echo "Claude / node cache bloat (safe to clear — auto-regenerated):"
rm_if_exists "$HOME/.cache/claude-cli-nodejs" "cli node cache"
rm_if_exists "$HOME/.cache/pip" "pip cache"
rm_if_exists "$HOME/.cache/mesa_shader_cache" "GPU shader cache"
rm_if_exists "$HOME/.cache/mesa_shader_cache_db" "GPU shader cache db"

echo ""
echo "Stale installer deb (already installed, no longer needed):"
rm_if_exists "$HOME/AionUi-1.9.23-linux-arm64.deb" "installed, safe to remove"

echo ""
echo "Handoff-generated guide files (if you want to keep them, Ctrl-C now):"
# Only remove if they were created after May 1 2026 (handoff date).
# Adjust the reference date if needed.
for f in \
  "$HOME/ISL/guides/PIXEL_CLEANUP_HANDOFF.md" \
  "$HOME/ISL/guides/PIXEL_SETUP_HANDOFF.md"
do
  if [[ -f "$f" ]]; then
    created="$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1 || echo "unknown")"
    echo -e "  ${YELLOW}found${NC}   $f  (modified: $created)"
    read -rp "  Delete this file? [y/N] " answer
    if [[ "${answer,,}" == "y" ]]; then
      rm -f "$f"
      echo -e "  ${GREEN}removed${NC}  $f"
      removed=$((removed + 1))
    else
      echo "  kept."
      skipped=$((skipped + 1))
    fi
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=== Done: ${removed} removed, ${skipped} skipped ===${NC}"
echo ""
echo "Intentionally kept (these belong on the Pixel):"
echo "  ~/.config/AionUi/       — AionUi config + logs"
echo "  ~/.config/Claude/       — Claude Desktop config + MCP"
echo "  ~/.claude/              — Claude Code settings"
echo "  ~/.coderabbit/          — CodeRabbit CLI logs"
echo "  ~/.hermes/              — Hermes gateway"
echo "  ~/.openclaw/            — OpenClaw plugins"
echo "  ~/.local/bin/           — claude, openclaw, coderabbit, etc."
echo "  ~/.local/node_modules/  — openclaw package install"
echo "  ~/soundforge-clearwave/ — Android project"
echo "  ~/ISL/                  — master context + memory"
