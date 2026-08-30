# Omarchy plugin: keyboard backlight panel

**Date:** 2026-08-31  
**Status:** Approved design  
**Repo:** `omarchy-samsung-keyboard-backlight`  
**Depends on:** existing `kbd-ambientd` / `kbd-ambientctl` (optional for Auto toggle)

## Problem

Users need a discoverable, styled shell UI to turn keyboard backlight on/off, cycle intensity, and toggle ambient auto — not only Fn keys or CLI.

## Goals

- Omarchy **bar widget + popup panel** for keyboard backlight.
- **On/Off**, **intensity steps** (0…max), **Auto** (ambient daemon pause/resume).
- Theme-aware styling consistent with stock Omarchy panels (power, VPN, audio).
- Ship inside this repo; extend `install.sh` to deploy and enable the plugin.
- Work when ambient daemon is absent (Auto disabled); work on any `*kbd_backlight*` LED.

## Non-goals (v1)

- Editing lux thresholds / idle timeout in the UI.
- RGB / per-key colors.
- Scroll-wheel or middle-click on the bar (can add later).
- Upstream first-party Omarchy plugin (user plugin under `~/.config/omarchy/plugins/`).

## Architecture

```
┌─────────────────────┐     click      ┌──────────────────────┐
│  BarWidget.qml      │───────────────▶│  Panel.qml           │
│  icon + level dots  │                │  On/Off · steps · Auto│
└─────────┬───────────┘                └──────────┬───────────┘
          │ poll                                  │ set
          ▼                                       ▼
   brightnessctl get/set  ◀──────────────▶  *kbd_backlight*
          │
          ▼
   kbd-ambientctl status|pause|resume  (Auto row)
```

| File | Responsibility |
|------|----------------|
| `plugin/joao.kbd-backlight/manifest.json` | Plugin id, bar-widget entry, metadata |
| `plugin/joao.kbd-backlight/BarWidget.qml` | Bar slot: icon, level indicator, opens panel |
| `plugin/joao.kbd-backlight/Panel.qml` | Popup UI + IPC/actions |
| `plugin/joao.kbd-backlight/Model.js` | Pure helpers: labels, segment counts, state derive |
| `install.sh` / `uninstall.sh` | Deploy/remove plugin + bar placement |
| `README.md` | Document plugin usage |

**Plugin id:** `joao.kbd-backlight`  
**Kinds:** `["bar-widget"]`  
**Entry:** `barWidget` → `BarWidget.qml` (panel nested or same pattern as Proton VPN: widget hosts panel)

Follow existing community pattern (`tharin.protonvpn`): `BarWidget.qml` owns bar chrome + IPC; `Panel.qml` is the popup content.

## Device & process control

### Discovery

- Keyboard LED: first `/sys/class/leds/*kbd_backlight*` (same as ambient daemon).
- Read `max_brightness` and current via `brightnessctl -d "$dev" max|get`.
- If none: bar shows unavailable/hidden-friendly state; panel explains “No keyboard backlight”.

### Set brightness

```bash
brightnessctl -d "$device" set "$level"   # no OSD from plugin (shell may still show system OSD if keys used)
```

Optional: `omarchy brightness keyboard --no-osd …` when actions map cleanly to up/down/cycle/off; prefer direct `brightnessctl` for absolute levels.

### Auto (ambient)

| UI action | Backend |
|-----------|---------|
| Read Auto on? | `systemctl --user is-active kbd-ambientd.service` **and** runtime state ≠ forced long pause; or `kbd-ambientctl status` parse `state` (ACTIVE_AUTO / IDLE_OFF = auto engaged; MANUAL_PAUSE with far-future until = user paused) |
| Auto off | `kbd-ambientctl pause` (if ctl missing: no-op + toast/log) |
| Auto on | `kbd-ambientctl resume`; if unit inactive, `systemctl --user enable --now kbd-ambientd.service` when binary exists |

If `kbd-ambientctl` not on PATH: Auto row disabled with subtitle “Install ambient daemon”.

### Manual level change while Auto on

No extra plugin logic required: ambient daemon already detects external brightness changes and pauses ~45s.

## UI specification

### Bar widget

- Icon: keyboard / backlight glyph from Omarchy icon set (match stock style).
- Level indicator: up to `max_brightness` small segments (cap visual at 4 if max is large).
- Off (level 0): dimmed icon, empty segments.
- Unavailable: dimmed icon, no segments (or hide widget if shell supports — prefer visible disabled).
- Primary click: toggle panel open/close.
- No scroll/middle-click in v1.

### Panel layout (top → bottom)

1. **Hero** — title “Keyboard backlight”; meta line: `Off` | `Level N` | `Low`/`Med`/`High` when max==3.
2. **Power** — toggle switch; off → set 0 (remember last non-zero in panel property for restore); on → restore last non-zero or `max`.
3. **Intensity** — horizontal segment/button row for each level `0…max`; selected filled with accent/foreground.
4. **Auto** — toggle “Ambient auto”; subtitle “Turns on in the dark · off when idle”.
5. **Footer** — muted hint: “Fn keyboard keys still work”.

### Interaction / a11y

- Use Omarchy `Panel` + shared `Ui` components (`ToggleSwitch`, buttons, typography) like power/VPN.
- Keyboard cursor: navigate rows; activate toggles/segments; Esc closes.
- Colors from `bar.foreground`, `Color.accent`, `Style.hoverFillFor` / `selectedFillFor` — no hard-coded hex themes.

### Refresh

- Bar: poll brightness every 2–3s (and on panel close).
- Panel open: poll every ~1s brightness + auto status.
- After any set action: immediate re-read.

## Install / uninstall

### install.sh additions

1. Copy `plugin/joao.kbd-backlight/` → `~/.config/omarchy/plugins/joao.kbd-backlight/` (rsync/cp -a).
2. `omarchy plugin enable joao.kbd-backlight --section right` (ignore if already enabled).
3. Prefer bar placement: `omarchy bar put joao.kbd-backlight --section right --before omarchy.power` when command succeeds; else leave default section from enable.
4. Existing daemon install steps unchanged and still run.

### uninstall.sh additions

1. `omarchy plugin disable joao.kbd-backlight` (best-effort).
2. Remove `~/.config/omarchy/plugins/joao.kbd-backlight/`.
3. Do not remove bar layout entries aggressively if CLI lacks remove — disable is enough; document manual bar cleanup if needed.
4. Daemon uninstall unchanged (`--purge` still only config/daemon).

## Testing

1. `omarchy plugin validate plugin/joao.kbd-backlight` (or installed path).
2. Install → bar icon appears; click opens panel.
3. Off → brightness 0; On → restored level.
4. Segment clicks set absolute levels 0…max.
5. Auto off → `kbd-ambientctl status` shows MANUAL_PAUSE; Auto on → ACTIVE_AUTO/IDLE_OFF.
6. Without daemon binary: Auto disabled; intensity still works.
7. Without kbd LED: graceful unavailable UI (no crash).
8. Theme change: colors follow theme.

## Documentation

README section: plugin enable/disable, bar placement, Auto dependency on ambient daemon, screenshots optional later.

## Resolved decisions

| Topic | Choice |
|-------|--------|
| UI shape | Bar widget + popup panel |
| Auto | Toggle via kbd-ambientctl pause/resume |
| Location | This repo `plugin/` + install.sh |
| Plugin id | `joao.kbd-backlight` |
| Scroll on bar | Not in v1 |
