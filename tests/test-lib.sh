#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/kbd-ambient-lib.sh
source "$ROOT/lib/kbd-ambient-lib.sh"

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $name (expected='$expected' actual='$actual')" >&2
    return 1
  fi
  echo "PASS: $name"
}

# defaults
kbd_ambient_set_defaults
assert_eq "default lux_dark" "20" "$KBD_AMBIENT_LUX_DARK"
assert_eq "default level_dark" "3" "$KBD_AMBIENT_LEVEL_DARK"
assert_eq "default idle" "60" "$KBD_AMBIENT_IDLE_TIMEOUT_SEC"

# lux = raw * scale (scale as decimal string)
assert_eq "lux 802*0.001" "0" "$(kbd_ambient_lux_from_raw 802 0.001 | cut -d. -f1)"
assert_eq "lux 20000*0.001" "20" "$(kbd_ambient_lux_from_raw 20000 0.001)"
assert_eq "lux 80000*0.001" "80" "$(kbd_ambient_lux_from_raw 80000 0.001)"
