# Samsung Galaxy Book keyboard ambient backlight

**Date:** 2026-08-30  
**Status:** Approved design  
**Hardware target:** Samsung Galaxy Book (Book 2 Pro SE and other `samsung-galaxybook` devices) on Omarchy  
**Problem:** Keyboard backlight does not turn on automatically in dark environments (Windows-like ambient behavior missing on Linux).

## Goals

- Turn keyboard backlight on/up when ambient light is low; off/down when bright.
- Dim/off after idle; restore on activity.
- Fit Omarchy user-layer patterns (user systemd unit, optional `post-boot` hook, no edits under `/usr/share/omarchy/`).
- Portable across Galaxy Book models that expose `*kbd_backlight*` LED + IIO illuminance (ALS).
- Coexist with manual controls (`omarchy brightness keyboard`, XF86 kbd brightness keys).

## Non-goals

- Upstream Omarchy package changes or edits to `/usr/share/omarchy/`.
- RGB theme colors for the keyboard.
- Controlling display backlight from ALS.
- Kernel driver patches.

## Observed hardware (Book 2 Pro SE)

| Resource | Path / name |
|----------|-------------|
| Keyboard LED | `/sys/class/leds/samsung-galaxybook::kbd_backlight` (brightness 0–3) |
| ALS | IIO `iio:device0` name `als` (`in_illuminance_raw`, `in_illuminance_scale`) |
| Manual control | `brightnessctl -d '…kbd_backlight…'`; `omarchy brightness keyboard` |
| Platform | `SAM0430:00` / `samsung-galaxybook` module |

Lux estimate: `lux = in_illuminance_raw × in_illuminance_scale`.

## Architecture

```
┌─────────────────┐     lux      ┌──────────────────┐
│  IIO ALS sysfs  │─────────────▶│   kbd-ambientd   │
└─────────────────┘              │  (user daemon)   │
                                 │                  │
┌─────────────────┐  activity    │  ambient map +   │    brightnessctl
│ idle / input    │─────────────▶│  idle + override │──────────────────▶ *kbd_backlight*
└─────────────────┘              └──────────────────┘
```

| Component | Responsibility |
|-----------|----------------|
| `kbd-ambientd` | Poll ALS, compute target level, apply brightness, honor idle and manual pause |
| Idle tracker | Detect no keyboard/pointer activity for `idle_timeout`; force level 0 until activity |
| Config | Thresholds, levels, timeouts, poll interval |
| `kbd-ambientctl` | status / enable / disable / pause / resume |
| systemd user unit | Start with graphical session |
| post-boot hook | Ensure unit enabled when hardware present (Omarchy hook) |

### Device discovery

1. **Keyboard:** first match `/sys/class/leds/*kbd_backlight*`.
2. **ALS:** prefer IIO device with `name == als` and `in_illuminance_raw`; else first IIO device with `in_illuminance_raw`.
3. If either missing: log once, exit 0 (service stays inactive / does not loop).

### Control path

- Set brightness with `brightnessctl -d "$device" set N` (no OSD).
- Do not call `omarchy-osd` from the daemon.

## Behavior

### Ambient mapping (defaults)

| Ambient | Condition | Target level |
|---------|-----------|--------------|
| Dark | lux ≤ 20 | 3 |
| Dim | lux ≤ 80 | 2 |
| Indoor | lux ≤ 200 | 1 |
| Bright | lux > 200 | 0 |

- **Hysteresis:** `hysteresis_ratio` default **0.2** (20%). When moving to a *higher* backlight level (darker ambient), use the nominal thresholds. When moving to a *lower* backlight level (brighter ambient), require lux to exceed `threshold × (1 + hysteresis_ratio)` before stepping down. This prevents chatter at boundaries.
- **Poll interval:** 1 second.
- **Smoothing:** 3-sample median of lux before mapping.

### Idle

- After **60s** with no keyboard or pointer activity → force keyboard backlight **0**.
- On activity → restore ambient-derived target immediately.
- While session is locked (if detectable cheaply): keep backlight **0**. If lock state is not reliably available without heavy deps, idle-off alone is sufficient for v1.

### Manual override

- If sysfs brightness changes to a value the daemon did not just write, treat as manual (hw key or `omarchy brightness keyboard`).
- **Pause auto for 45 seconds**, then resume ambient+idle logic.
- `kbd-ambientctl pause` / `resume` for explicit user control.

### State machine (summary)

```
ACTIVE_AUTO  --(idle timeout)--> IDLE_OFF
IDLE_OFF     --(activity)------> ACTIVE_AUTO
ACTIVE_AUTO  --(manual change)-> MANUAL_PAUSE
MANUAL_PAUSE --(45s elapsed)---> ACTIVE_AUTO
*            --(lock)-----------> IDLE_OFF (optional v1)
```

## Configuration

Path: `~/.config/omarchy-samsung-kbd-backlight/config`

Example keys (shell-friendly `key=value`):

```
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
# optional overrides:
# kbd_device=samsung-galaxybook::kbd_backlight
# als_device=iio:device0
```

Missing config file → built-in defaults (same as above). Install copies `config.example` only if config does not exist.

## Install layout

Repository:

```
bin/kbd-ambientd
bin/kbd-ambientctl
config/config.example
systemd/kbd-ambientd.service
hooks/post-boot/kbd-ambientd
install.sh
uninstall.sh
README.md
docs/superpowers/specs/…
```

Installed locations:

| Source | Destination |
|--------|-------------|
| `bin/*` | `~/.local/bin/` |
| `config/config.example` | `~/.config/omarchy-samsung-kbd-backlight/config` (if absent) |
| `systemd/kbd-ambientd.service` | `~/.config/systemd/user/` |
| post-boot script | via `omarchy hook install post-boot <script>` |

### systemd user unit

- `Type=simple`
- `ExecStart=%h/.local/bin/kbd-ambientd`
- `Restart=on-failure`
- `WantedBy=graphical-session.target`
- After install: `systemctl --user daemon-reload && systemctl --user enable --now kbd-ambientd.service`

### post-boot hook

- If kbd LED + ALS present: `systemctl --user enable --now kbd-ambientd.service`
- Else: no-op

### install.sh / uninstall.sh

- `install.sh`: copy files, install hook, reload/enable/start unit when hardware present.
- `uninstall.sh`: stop/disable unit, remove installed files and hook script; leave user config unless `--purge`.

## Implementation language

- **Bash** for daemon and ctl (consistent with Omarchy scripts, no extra runtime).
- Prefer `brightnessctl` already used by Omarchy.
- Idle/activity: **primary** approach is monitoring `/dev/input/event*` for EV_KEY / EV_REL / EV_ABS (user is in group `input` on Omarchy). Fallback: Hyprland idle signal if input monitoring is impractical. Must not require new privileged daemons or setuid helpers.

## Error handling

| Case | Behavior |
|------|----------|
| No kbd or ALS | Exit 0 after one log line |
| brightnessctl fails | Log at debug rate-limit; retry next poll |
| Config parse error | Log and use defaults for bad keys |
| ALS read fails | Keep last good lux for up to 10s, then treat as bright (level 0) |

No notifications/OSD from the daemon under normal operation.

## Testing

1. **Dry-run:** `kbd-ambientd --dry-run` prints lux, mapped level, state each tick without writing sysfs.
2. **Ambient:** cover/uncover ALS (or shine light); confirm levels move per table with hysteresis.
3. **Idle:** stop input 60s → level 0; press key → restore.
4. **Manual:** `omarchy brightness keyboard up` → auto paused 45s; then resumes.
5. **Lifecycle:** install, reboot/re-login, unit running; uninstall cleans unit.
6. **No hardware:** run on machine without devices → clean exit, no crash loop.

## Security / privileges

- Runs as the logged-in user.
- Uses existing `brightnessctl` path Omarchy already uses for keyboard brightness.
- Read-only ALS sysfs; no root install required for core path.
- Do not ship setuid helpers.

## Documentation

README covers: hardware prerequisites, install/uninstall, config keys, ctl commands, troubleshooting (`brightnessctl -l`, IIO paths, unit status).

## Open decisions resolved

| Topic | Decision |
|-------|----------|
| Behavior | Windows-like stepped ambient + idle off |
| Placement | Omarchy-style user service + post-boot hook |
| Ambient defaults | 20/80/200 lux → 3/2/1/0; 60s idle; 45s manual pause |
| Language | Bash |
| Scope | User install from this repo; not upstream Omarchy tree |
