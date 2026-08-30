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

kbd_ambient_median() {
  local -a s=("$@")
  local n=${#s[@]} i j tmp
  for ((i = 0; i < n; i++)); do
    for ((j = i + 1; j < n; j++)); do
      if (( s[j] < s[i] )); then
        tmp=${s[i]}; s[i]=${s[j]}; s[j]=$tmp
      fi
    done
  done
  echo "${s[$((n / 2))]}"
}

kbd_ambient_map_level() {
  local lux="$1" cur="${2:-}"
  local hr="$KBD_AMBIENT_HYSTERESIS_RATIO"
  local d="$KBD_AMBIENT_LUX_DARK" m="$KBD_AMBIENT_LUX_DIM" i="$KBD_AMBIENT_LUX_INDOOR"

  _kbd_ambient_band() {
    local x="$1" a="$2" b="$3" c="$4"
    if (( x <= a )); then echo 3
    elif (( x <= b )); then echo 2
    elif (( x <= c )); then echo 1
    else echo 0
    fi
  }

  local nominal step_down_a step_down_b step_down_c
  nominal=$(_kbd_ambient_band "$lux" "$d" "$m" "$i")
  step_down_a=$(awk -v t="$d" -v h="$hr" 'BEGIN{printf "%d", int(t*(1+h)+1e-9)}')
  step_down_b=$(awk -v t="$m" -v h="$hr" 'BEGIN{printf "%d", int(t*(1+h)+1e-9)}')
  step_down_c=$(awk -v t="$i" -v h="$hr" 'BEGIN{printf "%d", int(t*(1+h)+1e-9)}')

  if [[ -z "$cur" ]]; then echo "$nominal"; return; fi
  if (( nominal >= cur )); then echo "$nominal"; return; fi
  local down
  down=$(_kbd_ambient_band "$lux" "$step_down_a" "$step_down_b" "$step_down_c")
  if (( down < cur )); then echo "$down"; else echo "$cur"; fi
}
