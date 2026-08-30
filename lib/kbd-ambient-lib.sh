#!/bin/bash
# kbd-ambient pure functions (source from daemon/tests). No side effects on source.

kbd_ambient_set_defaults() {
  KBD_AMBIENT_POLL_INTERVAL_SEC=1
  KBD_AMBIENT_IDLE_TIMEOUT_SEC=60
  KBD_AMBIENT_MANUAL_PAUSE_SEC=45
  KBD_AMBIENT_LUX_DARK=20
  KBD_AMBIENT_LUX_DIM=80
  KBD_AMBIENT_LUX_INDOOR=200
  KBD_AMBIENT_LEVEL_DARK=3
  KBD_AMBIENT_LEVEL_DIM=2
  KBD_AMBIENT_LEVEL_INDOOR=1
  KBD_AMBIENT_LEVEL_BRIGHT=0
  KBD_AMBIENT_HYSTERESIS_RATIO=0.2
  KBD_AMBIENT_MEDIAN_SAMPLES=3
  KBD_AMBIENT_KBD_DEVICE="${KBD_AMBIENT_KBD_DEVICE:-}"
  KBD_AMBIENT_ALS_DEVICE="${KBD_AMBIENT_ALS_DEVICE:-}"
}

# Integer lux: floor(raw * scale). Uses awk for float.
kbd_ambient_lux_from_raw() {
  local raw="$1" scale="$2"
  awk -v r="$raw" -v s="$scale" 'BEGIN { printf "%d", int(r * s) }'
}
