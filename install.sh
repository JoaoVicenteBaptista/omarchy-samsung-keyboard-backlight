#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/lib"
UNIT_DIR="$HOME/.config/systemd/user"
CFG_DIR="$HOME/.config/omarchy-samsung-kbd-backlight"

mkdir -p "$BIN_DIR" "$LIB_DIR" "$UNIT_DIR" "$CFG_DIR"

install -m 0755 "$ROOT/bin/kbd-ambientd" "$BIN_DIR/kbd-ambientd"
install -m 0755 "$ROOT/bin/kbd-ambientctl" "$BIN_DIR/kbd-ambientctl"
install -m 0644 "$ROOT/lib/kbd-ambient-lib.sh" "$LIB_DIR/kbd-ambient-lib.sh"
install -m 0644 "$ROOT/systemd/kbd-ambientd.service" "$UNIT_DIR/kbd-ambientd.service"

if [[ ! -f "$CFG_DIR/config" ]]; then
  install -m 0644 "$ROOT/config/config.example" "$CFG_DIR/config"
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy hook install post-boot "$ROOT/hooks/post-boot/kbd-ambientd" || {
    mkdir -p "$HOME/.config/omarchy/hooks/post-boot.d"
    install -m 0755 "$ROOT/hooks/post-boot/kbd-ambientd" "$HOME/.config/omarchy/hooks/post-boot.d/kbd-ambientd"
  }
else
  mkdir -p "$HOME/.config/omarchy/hooks/post-boot.d"
  install -m 0755 "$ROOT/hooks/post-boot/kbd-ambientd" "$HOME/.config/omarchy/hooks/post-boot.d/kbd-ambientd"
fi

systemctl --user daemon-reload

has_kbd=0 has_als=0
for d in /sys/class/leds/*kbd_backlight*; do [[ -e "$d" ]] && has_kbd=1 && break; done
for d in /sys/bus/iio/devices/iio:device*; do [[ -e "$d/in_illuminance_raw" ]] && has_als=1 && break; done

if [[ "$has_kbd" -eq 1 && "$has_als" -eq 1 ]]; then
  systemctl --user enable --now kbd-ambientd.service
  echo "Installed and started kbd-ambientd.service"
else
  echo "Installed (hardware not detected; unit not started)"
fi

echo "ctl: kbd-ambientctl status"
