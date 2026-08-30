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

# median of 3
assert_eq "median 1 5 3" "3" "$(kbd_ambient_median 1 5 3)"
assert_eq "median 10 10 2" "10" "$(kbd_ambient_median 10 10 2)"

# mapping without hysteresis (current_level empty / first sample)
assert_eq "map dark" "3" "$(kbd_ambient_map_level 10 "")"
assert_eq "map dim" "2" "$(kbd_ambient_map_level 50 "")"
assert_eq "map indoor" "1" "$(kbd_ambient_map_level 150 "")"
assert_eq "map bright" "0" "$(kbd_ambient_map_level 250 "")"

# hysteresis: at level 3 (dark), need lux > 20*1.2=24 to drop toward dim
assert_eq "hyst stay dark at 22" "3" "$(kbd_ambient_map_level 22 3)"
assert_eq "hyst leave dark at 25" "2" "$(kbd_ambient_map_level 25 3)"

# hysteresis: at level 0 (bright), entering indoor uses nominal 200
assert_eq "enter indoor from bright at 200" "1" "$(kbd_ambient_map_level 200 0)"
assert_eq "stay bright at 201" "0" "$(kbd_ambient_map_level 201 0)"

# config load
tmpcfg=$(mktemp)
cat >"$tmpcfg" <<'EOF'
# comment
lux_dark=15
idle_timeout_sec=30
bogus_key=1
level_dark=2
EOF
kbd_ambient_set_defaults
kbd_ambient_load_config "$tmpcfg"
assert_eq "cfg lux_dark" "15" "$KBD_AMBIENT_LUX_DARK"
assert_eq "cfg idle" "30" "$KBD_AMBIENT_IDLE_TIMEOUT_SEC"
assert_eq "cfg level_dark" "2" "$KBD_AMBIENT_LEVEL_DARK"
rm -f "$tmpcfg"

# discovery against fixtures
fix=$(mktemp -d)
mkdir -p "$fix/class/leds/samsung-galaxybook::kbd_backlight"
echo 3 >"$fix/class/leds/samsung-galaxybook::kbd_backlight/max_brightness"
mkdir -p "$fix/bus/iio/devices/iio:device0"
echo als >"$fix/bus/iio/devices/iio:device0/name"
echo 0 >"$fix/bus/iio/devices/iio:device0/in_illuminance_raw"
echo 0.001 >"$fix/bus/iio/devices/iio:device0/in_illuminance_scale"
assert_eq "discover kbd" "samsung-galaxybook::kbd_backlight" "$(kbd_ambient_discover_kbd "$fix")"
assert_eq "discover als" "iio:device0" "$(kbd_ambient_discover_als "$fix")"
rm -rf "$fix"
