# Samsung KBD Ambient Backlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a user-level Omarchy-friendly daemon that maps ALS lux to Samsung Galaxy Book keyboard backlight levels, with idle-off and manual override pause.

**Architecture:** Pure-bash library (`lib/kbd-ambient-lib.sh`) holds lux math, hysteresis mapping, config parse, and device discovery. `bin/kbd-ambientd` runs the poll loop, idle watcher, and brightness writes via `brightnessctl`. `bin/kbd-ambientctl` talks to the daemon via a runtime state dir. Install drops a systemd user unit and an Omarchy `post-boot` hook.

**Tech Stack:** Bash, brightnessctl, sysfs (leds + IIO), libinput (idle activity), systemd --user, Omarchy hooks.

**Spec:** `docs/superpowers/specs/2026-08-30-samsung-kbd-ambient-backlight-design.md`

---

## File map

| Path | Responsibility |
|------|----------------|
| `lib/kbd-ambient-lib.sh` | Pure functions: defaults, config load, lux read helpers (injectable paths), median, map lux→level with hysteresis, state helpers |
| `bin/kbd-ambientd` | Daemon: discover devices, idle subprocess, main loop, dry-run, logging |
| `bin/kbd-ambientctl` | CLI: status, pause, resume, enable/disable (systemctl) |
| `tests/run-tests.sh` | Minimal bash test runner (no bats dependency) |
| `tests/test-lib.sh` | Unit tests for lib functions |
| `config/config.example` | Documented defaults |
| `systemd/kbd-ambientd.service` | User unit template |
| `hooks/post-boot/kbd-ambientd` | Enable/start when hardware present |
| `install.sh` / `uninstall.sh` | Install/remove user files + hook + unit |
| `README.md` | User docs |

Runtime (not in repo):

- `~/.config/omarchy-samsung-kbd-backlight/config`
- `~/.local/bin/kbd-ambientd`, `kbd-ambientctl`
- `~/.config/systemd/user/kbd-ambientd.service`
- `$XDG_RUNTIME_DIR/kbd-ambientd/` — `state`, `manual_until`, `last_input`, `pid`, `last_set_brightness`

---

### Task 1: Test runner + lib skeleton

**Files:**
- Create: `tests/run-tests.sh`
- Create: `tests/test-lib.sh`
- Create: `lib/kbd-ambient-lib.sh`

- [ ] **Step 1: Write failing tests for defaults and lux_from_raw**

Create `tests/test-lib.sh`:

```bash
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
assert_eq "lux 802*0.001" "0" "$(kbd_ambient_lux_from_raw 802 0.001 | cut -d. -f1)"  # integer lux via printf
# Prefer integer millilux internally — see implementation: function returns integer lux (floored)
assert_eq "lux 20000*0.001" "20" "$(kbd_ambient_lux_from_raw 20000 0.001)"
assert_eq "lux 80000*0.001" "80" "$(kbd_ambient_lux_from_raw 80000 0.001)"
```

Create `tests/run-tests.sh`:

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
for t in "$ROOT"/tests/test-*.sh; do
  echo "== $(basename "$t")"
  bash "$t" || fail=1
done
exit "$fail"
```

- [ ] **Step 2: Run tests — expect fail (missing lib)**

Run: `bash tests/run-tests.sh`

Expected: FAIL (cannot source lib or function not found)

- [ ] **Step 3: Implement lib skeleton**

Create `lib/kbd-ambient-lib.sh`:

```bash
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
```

- [ ] **Step 4: Run tests — expect pass**

Run: `bash tests/run-tests.sh`

Expected: all PASS

- [ ] **Step 5: Commit**

```bash
chmod +x tests/run-tests.sh tests/test-lib.sh
git add lib/kbd-ambient-lib.sh tests/run-tests.sh tests/test-lib.sh
git commit -m "feat: add kbd-ambient lib skeleton and tests"
```

---

### Task 2: Median filter + lux→level with hysteresis

**Files:**
- Modify: `lib/kbd-ambient-lib.sh`
- Modify: `tests/test-lib.sh`

- [ ] **Step 1: Add failing tests**

Append to `tests/test-lib.sh`:

```bash
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

# hysteresis: at level 0 (bright), entering indoor uses nominal 200 (higher backlight = darker ambient, nominal)
assert_eq "enter indoor from bright at 200" "1" "$(kbd_ambient_map_level 200 0)"
assert_eq "stay bright at 201" "0" "$(kbd_ambient_map_level 201 0)"
```

- [ ] **Step 2: Run tests — expect fail**

Run: `bash tests/run-tests.sh`

Expected: FAIL on missing functions

- [ ] **Step 3: Implement median + map_level**

Append to `lib/kbd-ambient-lib.sh`:

```bash
kbd_ambient_median() {
  # args: integers; print median
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

# Map lux to level. current_level may be empty on first call.
# Higher backlight when darker. Stepping UP (higher level): nominal thresholds.
# Stepping DOWN (lower level): require lux > threshold*(1+hysteresis_ratio).
kbd_ambient_map_level() {
  local lux="$1"
  local cur="${2:-}"
  local hr ratio_up
  hr="$KBD_AMBIENT_HYSTERESIS_RATIO"

  # Compute step-down thresholds (brighter ambient needed to reduce level)
  local t_dark t_dim t_indoor
  t_dark=$(awk -v t="$KBD_AMBIENT_LUX_DARK" -v h="$hr" 'BEGIN { printf "%d", int(t * (1 + h) + 0.999) }')
  t_dim=$(awk -v t="$KBD_AMBIENT_LUX_DIM" -v h="$hr" 'BEGIN { printf "%d", int(t * (1 + h) + 0.999) }')
  t_indoor=$(awk -v t="$KBD_AMBIENT_LUX_INDOOR" -v h="$hr" 'BEGIN { printf "%d", int(t * (1 + h) + 0.999) }')

  if [[ -z "$cur" ]]; then
    if (( lux <= KBD_AMBIENT_LUX_DARK )); then echo "$KBD_AMBIENT_LEVEL_DARK"; return; fi
    if (( lux <= KBD_AMBIENT_LUX_DIM )); then echo "$KBD_AMBIENT_LEVEL_DIM"; return; fi
    if (( lux <= KBD_AMBIENT_LUX_INDOOR )); then echo "$KBD_AMBIENT_LEVEL_INDOOR"; return; fi
    echo "$KBD_AMBIENT_LEVEL_BRIGHT"
    return
  fi

  # Desired nominal level
  local want
  if (( lux <= KBD_AMBIENT_LUX_DARK )); then want=$KBD_AMBIENT_LEVEL_DARK
  elif (( lux <= KBD_AMBIENT_LUX_DIM )); then want=$KBD_AMBIENT_LEVEL_DIM
  elif (( lux <= KBD_AMBIENT_LUX_INDOOR )); then want=$KBD_AMBIENT_LEVEL_INDOOR
  else want=$KBD_AMBIENT_LEVEL_BRIGHT
  fi

  if (( want > cur )); then
    # darker ambient / higher backlight: allow immediate step up to want
    echo "$want"
    return
  fi
  if (( want == cur )); then
    echo "$cur"
    return
  fi

  # want < cur: only step down when past hysteresis thresholds from current band
  if (( cur >= KBD_AMBIENT_LEVEL_DARK )); then
    if (( lux > t_dark )); then
      # drop at least one step via re-map with empty? stepwise:
      if (( lux <= KBD_AMBIENT_LUX_DIM )); then echo "$KBD_AMBIENT_LEVEL_DIM"; return; fi
      if (( lux <= KBD_AMBIENT_LUX_INDOOR )); then echo "$KBD_AMBIENT_LEVEL_INDOOR"; return; fi
      if (( lux > t_indoor )); then echo "$KBD_AMBIENT_LEVEL_BRIGHT"; return; fi
      echo "$KBD_AMBIENT_LEVEL_INDOOR"; return
    fi
    echo "$cur"; return
  fi
  if (( cur >= KBD_AMBIENT_LEVEL_DIM )); then
    if (( lux > t_dim )); then
      if (( lux <= KBD_AMBIENT_LUX_INDOOR )); then echo "$KBD_AMBIENT_LEVEL_INDOOR"; return; fi
      if (( lux > t_indoor )); then echo "$KBD_AMBIENT_LEVEL_BRIGHT"; return; fi
      echo "$KBD_AMBIENT_LEVEL_INDOOR"; return
    fi
    echo "$cur"; return
  fi
  if (( cur >= KBD_AMBIENT_LEVEL_INDOOR )); then
    if (( lux > t_indoor )); then echo "$KBD_AMBIENT_LEVEL_BRIGHT"; return; fi
    echo "$cur"; return
  fi
  echo "$KBD_AMBIENT_LEVEL_BRIGHT"
}
```

**Note for implementer:** If tests fail due to off-by-one on `t_dark` (20×1.2 = 24, int rounding), adjust awk so `hyst leave dark at 25` passes and `22` stays. Prefer `printf "%d", (t * (1+h)) == 24` with `lux > 24` for leave. Use `int(t*(1+h)+1e-9)` and compare `lux > t_dark` where t_dark=24.

Simpler hysteresis algorithm (preferred if above is buggy) — implement this instead if tests fail:

```bash
kbd_ambient_map_level() {
  local lux="$1" cur="${2:-}"
  local hr="$KBD_AMBIENT_HYSTERESIS_RATIO"
  local d="$KBD_AMBIENT_LUX_DARK" m="$KBD_AMBIENT_LUX_DIM" i="$KBD_AMBIENT_LUX_INDOOR"

  _band() {
    local x="$1" a="$2" b="$3" c="$4"
    if (( x <= a )); then echo 3
    elif (( x <= b )); then echo 2
    elif (( x <= c )); then echo 1
    else echo 0
    fi
  }

  local nominal step_down_a step_down_b step_down_c
  nominal=$(_band "$lux" "$d" "$m" "$i")
  step_down_a=$(awk -v t="$d" -v h="$hr" 'BEGIN{printf "%d", int(t*(1+h)+1e-9)}')
  step_down_b=$(awk -v t="$m" -v h="$hr" 'BEGIN{printf "%d", int(t*(1+h)+1e-9)}')
  step_down_c=$(awk -v t="$i" -v h="$hr" 'BEGIN{printf "%d", int(t*(1+h)+1e-9)}')

  if [[ -z "$cur" ]]; then echo "$nominal"; return; fi
  if (( nominal >= cur )); then echo "$nominal"; return; fi
  # stepping down: use inflated thresholds for band decision
  local down
  down=$(_band "$lux" "$step_down_a" "$step_down_b" "$step_down_c")
  if (( down < cur )); then echo "$down"; else echo "$cur"; fi
}
```

Use the **simpler** algorithm in the actual implementation. Tests:

- `map_level 22 3` → stay 3 (22 ≤ 24)
- `map_level 25 3` → 2 (25 > 24, band with inflated thresholds)

- [ ] **Step 4: Run tests — expect pass**

Run: `bash tests/run-tests.sh`

Expected: all PASS. Fix hysteresis math until they do.

- [ ] **Step 5: Commit**

```bash
git add lib/kbd-ambient-lib.sh tests/test-lib.sh
git commit -m "feat: median filter and lux-to-level hysteresis mapping"
```

---

### Task 3: Config load + device discovery

**Files:**
- Modify: `lib/kbd-ambient-lib.sh`
- Modify: `tests/test-lib.sh`
- Create: `tests/fixtures/` (fake sysfs trees as needed)

- [ ] **Step 1: Write failing tests for config and discovery**

Append to `tests/test-lib.sh`:

```bash
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
```

- [ ] **Step 2: Run tests — expect fail**

Run: `bash tests/run-tests.sh`

- [ ] **Step 3: Implement load_config + discover_***

```bash
kbd_ambient_load_config() {
  local file="$1" key val
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    key="${key// /}"; val="${val#"${val%%[![:space:]]*}"}"
    case "$key" in
      poll_interval_sec) KBD_AMBIENT_POLL_INTERVAL_SEC=$val ;;
      idle_timeout_sec) KBD_AMBIENT_IDLE_TIMEOUT_SEC=$val ;;
      manual_pause_sec) KBD_AMBIENT_MANUAL_PAUSE_SEC=$val ;;
      lux_dark) KBD_AMBIENT_LUX_DARK=$val ;;
      lux_dim) KBD_AMBIENT_LUX_DIM=$val ;;
      lux_indoor) KBD_AMBIENT_LUX_INDOOR=$val ;;
      level_dark) KBD_AMBIENT_LEVEL_DARK=$val ;;
      level_dim) KBD_AMBIENT_LEVEL_DIM=$val ;;
      level_indoor) KBD_AMBIENT_LEVEL_INDOOR=$val ;;
      level_bright) KBD_AMBIENT_LEVEL_BRIGHT=$val ;;
      hysteresis_ratio) KBD_AMBIENT_HYSTERESIS_RATIO=$val ;;
      median_samples) KBD_AMBIENT_MEDIAN_SAMPLES=$val ;;
      kbd_device) KBD_AMBIENT_KBD_DEVICE=$val ;;
      als_device) KBD_AMBIENT_ALS_DEVICE=$val ;;
      *) echo "kbd-ambient: unknown config key: $key" >&2 ;;
    esac
  done <"$file"
}

# root default /sys
kbd_ambient_discover_kbd() {
  local root="${1:-/sys}"
  if [[ -n "${KBD_AMBIENT_KBD_DEVICE:-}" ]]; then
    echo "$KBD_AMBIENT_KBD_DEVICE"; return 0
  fi
  local d
  for d in "$root"/class/leds/*kbd_backlight*; do
    [[ -e "$d" ]] || continue
    basename "$d"
    return 0
  done
  return 1
}

kbd_ambient_discover_als() {
  local root="${1:-/sys}"
  if [[ -n "${KBD_AMBIENT_ALS_DEVICE:-}" ]]; then
    echo "$KBD_AMBIENT_ALS_DEVICE"; return 0
  fi
  local d name
  for d in "$root"/bus/iio/devices/iio:device*; do
    [[ -e "$d/in_illuminance_raw" ]] || continue
    name=$(cat "$d/name" 2>/dev/null || true)
    if [[ "$name" == "als" ]]; then basename "$d"; return 0; fi
  done
  for d in "$root"/bus/iio/devices/iio:device*; do
    [[ -e "$d/in_illuminance_raw" ]] || continue
    basename "$d"
    return 0
  done
  return 1
}

kbd_ambient_read_lux() {
  local root="${1:-/sys}" als_dev="$2"
  local base raw scale
  base="$root/bus/iio/devices/$als_dev"
  raw=$(cat "$base/in_illuminance_raw")
  scale=$(cat "$base/in_illuminance_scale" 2>/dev/null || echo 1)
  kbd_ambient_lux_from_raw "$raw" "$scale"
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `bash tests/run-tests.sh`

- [ ] **Step 5: Commit**

```bash
git add lib/kbd-ambient-lib.sh tests/test-lib.sh
git commit -m "feat: config loading and sysfs device discovery"
```

---

### Task 4: Daemon core (ambient loop, dry-run, brightness apply)

**Files:**
- Create: `bin/kbd-ambientd`
- Modify: `lib/kbd-ambient-lib.sh` (runtime dir helpers if needed)

- [ ] **Step 1: Implement `bin/kbd-ambientd`**

```bash
#!/bin/bash
set -euo pipefail

ROOT_LIB="$(cd "$(dirname "$0")/.." && pwd)/lib/kbd-ambient-lib.sh"
if [[ -f "$ROOT_LIB" ]]; then
  # shellcheck source=../lib/kbd-ambient-lib.sh
  source "$ROOT_LIB"
elif [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/kbd-ambient/kbd-ambient-lib.sh" ]]; then
  source "${XDG_DATA_HOME:-$HOME/.local/share}/kbd-ambient/kbd-ambient-lib.sh"
elif [[ -f "$HOME/.local/lib/kbd-ambient-lib.sh" ]]; then
  source "$HOME/.local/lib/kbd-ambient-lib.sh"
else
  echo "kbd-ambientd: cannot find kbd-ambient-lib.sh" >&2
  exit 1
fi

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

kbd_ambient_set_defaults
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-samsung-kbd-backlight"
kbd_ambient_load_config "$CONFIG_DIR/config"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/kbd-ambientd"
mkdir -p "$RUNTIME_DIR"
echo $$ >"$RUNTIME_DIR/pid"
echo "ACTIVE_AUTO" >"$RUNTIME_DIR/state"
echo 0 >"$RUNTIME_DIR/manual_until"
date +%s >"$RUNTIME_DIR/last_input"
echo "" >"$RUNTIME_DIR/last_set_brightness"

SYS_ROOT=/sys
KBD_DEV=$(kbd_ambient_discover_kbd "$SYS_ROOT") || {
  echo "kbd-ambientd: no *kbd_backlight* LED found" >&2
  exit 0
}
ALS_DEV=$(kbd_ambient_discover_als "$SYS_ROOT") || {
  echo "kbd-ambientd: no IIO illuminance (ALS) found" >&2
  exit 0
}

log() { echo "kbd-ambientd: $*" >&2; }

apply_brightness() {
  local level="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry-run set $KBD_DEV -> $level"
    echo "$level" >"$RUNTIME_DIR/last_set_brightness"
    return 0
  fi
  if brightnessctl -d "$KBD_DEV" set "$level" >/dev/null; then
    echo "$level" >"$RUNTIME_DIR/last_set_brightness"
  else
    log "brightnessctl failed for level $level"
  fi
}

read_hw_brightness() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    cat "$RUNTIME_DIR/last_set_brightness" 2>/dev/null || echo 0
    return
  fi
  brightnessctl -d "$KBD_DEV" get
}

# Idle watcher: libinput debug-events updates last_input
start_idle_watcher() {
  if ! command -v libinput >/dev/null; then
    log "libinput not found; idle-off disabled"
    return 0
  fi
  (
    # shellcheck disable=SC2034
    stdbuf -oL libinput debug-events 2>/dev/null | while IFS= read -r _line; do
      date +%s >"$RUNTIME_DIR/last_input"
    done
  ) &
  echo $! >"$RUNTIME_DIR/idle_watcher_pid"
}

cleanup() {
  if [[ -f "$RUNTIME_DIR/idle_watcher_pid" ]]; then
    kill "$(cat "$RUNTIME_DIR/idle_watcher_pid")" 2>/dev/null || true
  fi
  rm -f "$RUNTIME_DIR/pid"
}
trap cleanup EXIT INT TERM

start_idle_watcher

current_level=""
declare -a lux_hist=()
als_fail_since=0

log "kbd=$KBD_DEV als=$ALS_DEV dry_run=$DRY_RUN"

while true; do
  now=$(date +%s)
  manual_until=$(cat "$RUNTIME_DIR/manual_until" 2>/dev/null || echo 0)
  last_input=$(cat "$RUNTIME_DIR/last_input" 2>/dev/null || echo "$now")
  state=$(cat "$RUNTIME_DIR/state" 2>/dev/null || echo ACTIVE_AUTO)

  # Detect external brightness changes
  hw=$(read_hw_brightness)
  last_set=$(cat "$RUNTIME_DIR/last_set_brightness" 2>/dev/null || echo "")
  if [[ -n "$last_set" && "$hw" != "$last_set" && "$state" != "MANUAL_PAUSE" ]]; then
    manual_until=$((now + KBD_AMBIENT_MANUAL_PAUSE_SEC))
    echo "$manual_until" >"$RUNTIME_DIR/manual_until"
    echo "MANUAL_PAUSE" >"$RUNTIME_DIR/state"
    state=MANUAL_PAUSE
    current_level=$hw
    log "manual override detected hw=$hw pause until $manual_until"
  fi

  if [[ "$state" == "MANUAL_PAUSE" ]]; then
    if (( now >= manual_until )); then
      echo "ACTIVE_AUTO" >"$RUNTIME_DIR/state"
      state=ACTIVE_AUTO
      log "manual pause ended"
    else
      [[ "$DRY_RUN" -eq 1 ]] && log "state=$state lux=? level=hold"
      sleep "$KBD_AMBIENT_POLL_INTERVAL_SEC"
      continue
    fi
  fi

  # Idle
  idle_for=$((now - last_input))
  if (( idle_for >= KBD_AMBIENT_IDLE_TIMEOUT_SEC )); then
    if [[ "$state" != "IDLE_OFF" ]]; then
      echo "IDLE_OFF" >"$RUNTIME_DIR/state"
      state=IDLE_OFF
      apply_brightness 0
      log "idle ${idle_for}s -> off"
    fi
    [[ "$DRY_RUN" -eq 1 ]] && log "state=$state idle_for=$idle_for"
    sleep "$KBD_AMBIENT_POLL_INTERVAL_SEC"
    continue
  elif [[ "$state" == "IDLE_OFF" ]]; then
    echo "ACTIVE_AUTO" >"$RUNTIME_DIR/state"
    state=ACTIVE_AUTO
    log "activity -> auto"
  fi

  # ALS
  if lux=$(kbd_ambient_read_lux "$SYS_ROOT" "$ALS_DEV" 2>/dev/null); then
    als_fail_since=0
  else
    if (( als_fail_since == 0 )); then als_fail_since=$now; fi
    if (( now - als_fail_since > 10 )); then
      lux=99999
    else
      lux=${lux_hist[-1]:-99999}
    fi
  fi

  lux_hist+=("$lux")
  if (( ${#lux_hist[@]} > KBD_AMBIENT_MEDIAN_SAMPLES )); then
    lux_hist=("${lux_hist[@]:$(( ${#lux_hist[@]} - KBD_AMBIENT_MEDIAN_SAMPLES ))}")
  fi
  if (( ${#lux_hist[@]} >= 1 )); then
    med=$(kbd_ambient_median "${lux_hist[@]}")
  else
    med=$lux
  fi

  target=$(kbd_ambient_map_level "$med" "$current_level")
  if [[ "$target" != "$current_level" ]]; then
    apply_brightness "$target"
    current_level=$target
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "state=$state lux=$med target=$target current=$current_level"
  fi

  sleep "$KBD_AMBIENT_POLL_INTERVAL_SEC"
done
```

**Install note:** `install.sh` must place lib at `~/.local/lib/kbd-ambient-lib.sh` so the daemon finds it after install (daemon checks repo path first when run from git tree).

- [ ] **Step 2: Manual dry-run smoke on this machine**

Run:

```bash
chmod +x bin/kbd-ambientd
# short dry-run (timeout)
timeout 5 bin/kbd-ambientd --dry-run || true
```

Expected: log lines with kbd/als names, lux, target; no crash. Exit via timeout (124).

- [ ] **Step 3: Commit**

```bash
git add bin/kbd-ambientd lib/kbd-ambient-lib.sh
git commit -m "feat: add kbd-ambientd ambient/idle/manual loop"
```

---

### Task 5: kbd-ambientctl

**Files:**
- Create: `bin/kbd-ambientctl`

- [ ] **Step 1: Implement ctl**

```bash
#!/bin/bash
set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/kbd-ambientd"
UNIT=kbd-ambientd.service

cmd="${1:-status}"

case "$cmd" in
  status)
    echo "unit: $(systemctl --user is-active "$UNIT" 2>/dev/null || echo n/a)"
    if [[ -f "$RUNTIME_DIR/state" ]]; then
      echo "state: $(cat "$RUNTIME_DIR/state")"
      echo "last_set: $(cat "$RUNTIME_DIR/last_set_brightness" 2>/dev/null || echo n/a)"
      echo "manual_until: $(cat "$RUNTIME_DIR/manual_until" 2>/dev/null || echo 0)"
      echo "last_input: $(cat "$RUNTIME_DIR/last_input" 2>/dev/null || echo n/a)"
      echo "pid: $(cat "$RUNTIME_DIR/pid" 2>/dev/null || echo n/a)"
    else
      echo "runtime: not running (no $RUNTIME_DIR)"
    fi
    ;;
  pause)
    now=$(date +%s)
    # long pause: 10 years effectively until resume
    mkdir -p "$RUNTIME_DIR"
    echo $((now + 3650*24*3600)) >"$RUNTIME_DIR/manual_until"
    echo MANUAL_PAUSE >"$RUNTIME_DIR/state"
    echo "paused"
    ;;
  resume)
    mkdir -p "$RUNTIME_DIR"
    echo 0 >"$RUNTIME_DIR/manual_until"
    echo ACTIVE_AUTO >"$RUNTIME_DIR/state"
    date +%s >"$RUNTIME_DIR/last_input"
    echo "resumed"
    ;;
  enable)
    systemctl --user enable --now "$UNIT"
    ;;
  disable)
    systemctl --user disable --now "$UNIT"
    ;;
  *)
    echo "Usage: kbd-ambientctl {status|pause|resume|enable|disable}" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 2: Smoke ctl status**

Run: `chmod +x bin/kbd-ambientctl && bin/kbd-ambientctl status`

Expected: prints unit/runtime info without error

- [ ] **Step 3: Commit**

```bash
git add bin/kbd-ambientctl
git commit -m "feat: add kbd-ambientctl status/pause/resume/enable"
```

---

### Task 6: Config example, systemd unit, post-boot hook

**Files:**
- Create: `config/config.example`
- Create: `systemd/kbd-ambientd.service`
- Create: `hooks/post-boot/kbd-ambientd`

- [ ] **Step 1: Write config.example**

```bash
# ~/.config/omarchy-samsung-kbd-backlight/config
poll_interval_sec=1
idle_timeout_sec=60
manual_pause_sec=45
lux_dark=20
lux_dim=80
lux_indoor=200
level_dark=3
level_dim=2
level_indoor=1
level_bright=0
hysteresis_ratio=0.2
median_samples=3
# kbd_device=samsung-galaxybook::kbd_backlight
# als_device=iio:device0
```

- [ ] **Step 2: Write systemd user unit**

```ini
[Unit]
Description=Samsung Galaxy Book ambient keyboard backlight
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/kbd-ambientd
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
```

- [ ] **Step 3: Write post-boot hook**

```bash
#!/bin/bash
# Enable ambient kbd backlight when Galaxy Book hardware is present.
set -euo pipefail

has_kbd=0
has_als=0
for d in /sys/class/leds/*kbd_backlight*; do
  [[ -e "$d" ]] && has_kbd=1 && break
done
for d in /sys/bus/iio/devices/iio:device*; do
  [[ -e "$d/in_illuminance_raw" ]] && has_als=1 && break
done

if [[ "$has_kbd" -eq 1 && "$has_als" -eq 1 ]]; then
  systemctl --user enable --now kbd-ambientd.service 2>/dev/null || true
fi
```

- [ ] **Step 4: Commit**

```bash
git add config/config.example systemd/kbd-ambientd.service hooks/post-boot/kbd-ambientd
git commit -m "feat: add config example, user unit, post-boot hook"
```

---

### Task 7: install.sh + uninstall.sh

**Files:**
- Create: `install.sh`
- Create: `uninstall.sh`

- [ ] **Step 1: Write install.sh**

```bash
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

# Ensure daemon finds lib after install (rewrite shebang path already handled via ~/.local/lib)
# Patch installed daemon to prefer ~/.local/lib — already in search path order.

if command -v omarchy >/dev/null && omarchy hook install --help &>/dev/null; then
  omarchy hook install post-boot "$ROOT/hooks/post-boot/kbd-ambientd" || {
    # fallback: copy into hooks dir
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
```

**Important:** Fix `bin/kbd-ambientd` lib search so installed copy finds `$HOME/.local/lib/kbd-ambient-lib.sh` (already in Task 4). When run from `$HOME/.local/bin`, `$(dirname "$0")/..` is `$HOME/.local` — so also check `$HOME/.local/lib/kbd-ambient-lib.sh` via:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CANDIDATES=(
  "$SCRIPT_DIR/../lib/kbd-ambient-lib.sh"
  "$HOME/.local/lib/kbd-ambient-lib.sh"
)
```

Update daemon header accordingly in this task if not already correct.

- [ ] **Step 2: Write uninstall.sh**

```bash
#!/bin/bash
set -euo pipefail
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

systemctl --user disable --now kbd-ambientd.service 2>/dev/null || true
rm -f "$HOME/.local/bin/kbd-ambientd" "$HOME/.local/bin/kbd-ambientctl"
rm -f "$HOME/.local/lib/kbd-ambient-lib.sh"
rm -f "$HOME/.config/systemd/user/kbd-ambientd.service"
rm -f "$HOME/.config/omarchy/hooks/post-boot.d/kbd-ambientd"
# also remove if installed as flat hook name variants
rm -f "$HOME/.config/omarchy/hooks/post-boot.d/"*kbd-ambient*
systemctl --user daemon-reload
if [[ "$PURGE" -eq 1 ]]; then
  rm -rf "$HOME/.config/omarchy-samsung-kbd-backlight"
fi
echo "Uninstalled kbd-ambientd"
```

- [ ] **Step 3: Commit**

```bash
chmod +x install.sh uninstall.sh hooks/post-boot/kbd-ambientd
git add install.sh uninstall.sh bin/kbd-ambientd
git commit -m "feat: add install and uninstall scripts"
```

---

### Task 8: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

```markdown
# omarchy-samsung-keyboard-backlight

Automatic keyboard backlight for Samsung Galaxy Book on [Omarchy](https://omarchy.org/) (ALS → brightness, idle-off, manual pause).

## Requirements

- `samsung-galaxybook` (or any `*kbd_backlight*` LED)
- IIO ambient light (`in_illuminance_raw`)
- `brightnessctl`, `libinput`, systemd user session

## Install

```bash
./install.sh
kbd-ambientctl status
```

## Uninstall

```bash
./uninstall.sh          # keeps config
./uninstall.sh --purge  # removes config too
```

## Config

`~/.config/omarchy-samsung-kbd-backlight/config` (see `config/config.example`)

Defaults: lux 20/80/200 → levels 3/2/1/0; idle 60s off; manual pause 45s.

## Commands

| Command | Meaning |
|---------|---------|
| `kbd-ambientctl status` | Unit + runtime state |
| `kbd-ambientctl pause` | Stop auto until resume |
| `kbd-ambientctl resume` | Resume auto |
| `kbd-ambientctl enable` / `disable` | systemd user unit |
| `kbd-ambientd --dry-run` | Log lux/targets without writing |

## Tests

```bash
bash tests/run-tests.sh
```

## Troubleshooting

```bash
brightnessctl -l | grep kbd
cat /sys/bus/iio/devices/iio:device0/name
systemctl --user status kbd-ambientd.service
journalctl --user -u kbd-ambientd.service -f
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README for install and usage"
```

---

### Task 9: Install on this machine and verify

**Files:** none (runtime verification)

- [ ] **Step 1: Run unit tests**

Run: `bash tests/run-tests.sh`  
Expected: all PASS

- [ ] **Step 2: Install**

Run: `./install.sh`  
Expected: "Installed and started kbd-ambientd.service"

- [ ] **Step 3: Verify service**

Run:

```bash
systemctl --user is-active kbd-ambientd.service
kbd-ambientctl status
brightnessctl -d 'samsung-galaxybook::kbd_backlight' get
```

Expected: `active`; state `ACTIVE_AUTO` or `IDLE_OFF`; brightness 0–3 consistent with room light.

- [ ] **Step 4: Ambient check**

Cover the ALS (top of screen bezel area) for ~5s; confirm kbd level rises (or dry-run logs if uncertain). Uncover / shine light; level drops toward 0.

- [ ] **Step 5: Manual pause check**

```bash
omarchy brightness keyboard up
sleep 1
kbd-ambientctl status   # expect MANUAL_PAUSE
```

- [ ] **Step 6: Final commit if install path fixes were needed**

```bash
git status
# commit any fixes
git add -A && git commit -m "fix: install path / daemon lib resolution" || true
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| ALS → stepped levels 3/2/1/0 | 2, 4 |
| Hysteresis 0.2 | 2 |
| Median 3 samples | 2, 4 |
| Poll 1s | 4 |
| Idle 60s → 0 | 4 |
| Manual pause 45s | 4, 5 |
| Device discovery | 3, 4 |
| Config file | 3, 6 |
| brightnessctl no OSD | 4 |
| systemd user unit | 6, 7 |
| post-boot hook | 6, 7 |
| install/uninstall | 7 |
| dry-run | 4 |
| ctl status/pause/resume | 5 |
| README | 8 |
| Exit 0 if no hardware | 4 |
| No /usr/share/omarchy edits | 7 |

## Self-review notes

- Hysteresis: use **simpler** `_band` algorithm in Task 2 if the long form fails tests.
- Daemon lib path: must work both from git `bin/` and `~/.local/bin`.
- `libinput debug-events` may need the user in group `input` (already true on this machine).
- ALS on this device currently reports raw≈802 scale=0.001 → lux≈0 (very dark) — backlight should sit at level 3 when active; if always-dark is wrong for the sensor, calibrate `lux_*` after observing real lux with light changes (`kbd-ambientd --dry-run`).
- `omarchy hook install` CLI may differ; install.sh has filesystem fallback to `~/.config/omarchy/hooks/post-boot.d/`.
