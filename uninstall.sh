#!/bin/bash
set -euo pipefail
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

systemctl --user disable --now kbd-ambientd.service 2>/dev/null || true
rm -f "$HOME/.local/bin/kbd-ambientd" "$HOME/.local/bin/kbd-ambientctl"
rm -f "$HOME/.local/lib/kbd-ambient-lib.sh"
rm -f "$HOME/.config/systemd/user/kbd-ambientd.service"
rm -f "$HOME/.config/omarchy/hooks/post-boot.d/kbd-ambientd"
rm -f "$HOME/.config/omarchy/hooks/post-boot.d/"*kbd-ambient* 2>/dev/null || true
systemctl --user daemon-reload
if [[ "$PURGE" -eq 1 ]]; then
  rm -rf "$HOME/.config/omarchy-samsung-kbd-backlight"
fi
# Ambient uninstall does not remove a git-managed bar plugin.
# Use: omarchy plugin remove joao.kbd-backlight
if [[ ! -d "$HOME/.config/omarchy/plugins/joao.kbd-backlight/.git" ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin disable joao.kbd-backlight 2>/dev/null || true
  fi
  rm -rf "$HOME/.config/omarchy/plugins/joao.kbd-backlight"
fi
echo "Uninstalled kbd-ambientd"

