# omarchy-samsung-keyboard-backlight

Omarchy bar plugin for keyboard backlight (on/off, intensity, ambient auto) plus an optional ambient daemon for Samsung Galaxy Book (and any `*kbd_backlight*` LED).

**Plugin id:** `joao.kbd-backlight`  
**License:** MIT

## Install the Omarchy plugin

```bash
omarchy plugin add https://github.com/JoaoVicenteBaptista/omarchy-samsung-keyboard-backlight.git --enable
```

Place on the bar (if needed):

```bash
omarchy bar put joao.kbd-backlight --section right --before omarchy.power
```

### Remove the plugin

```bash
omarchy plugin remove joao.kbd-backlight
```

### Update the plugin

```bash
omarchy plugin update joao.kbd-backlight
```

## Bar controls

| Control | Action |
|---------|--------|
| Left-click bar icon | Open panel (power, intensity, ambient auto) |
| Right-click bar icon | Toggle backlight on/off |
| Middle-click bar icon | Refresh state |
| Panel power switch | On/off |
| Panel intensity buttons | Set level 0…max |
| Panel ambient auto | Pause/resume ambient daemon (if installed) |
| Keyboard in panel | Arrows navigate; Enter activates; `t` power; `a` auto |

**Note:** Ambient Auto needs the optional daemon below (`kbd-ambientctl` on `PATH`). Without it, on/off and intensity still work.

## Optional: ambient daemon

ALS → brightness, idle-off, manual pause.

### Requirements

- `samsung-galaxybook` (or any `*kbd_backlight*` LED)
- IIO ambient light (`in_illuminance_raw`)
- `brightnessctl`, systemd user session
- Idle detection: `libinput` CLI (`libinput-tools`) if present, else Python 3 reading `/dev/input` (user in group `input`)

### Install

```bash
git clone https://github.com/JoaoVicenteBaptista/omarchy-samsung-keyboard-backlight.git
cd omarchy-samsung-keyboard-backlight
./install.sh
kbd-ambientctl status
```

### Uninstall

```bash
./uninstall.sh          # keeps config
./uninstall.sh --purge  # removes config too
```

### Config

`~/.config/omarchy-samsung-kbd-backlight/config` (see `config/config.example`)

Defaults: lux 20/80/200 → levels 3/2/1/0; idle 60s off; manual pause 45s.

### Commands

| Command | Meaning |
|---------|---------|
| `kbd-ambientctl status` | Unit + runtime state |
| `kbd-ambientctl pause` | Stop auto until resume |
| `kbd-ambientctl resume` | Resume auto |
| `kbd-ambientctl enable` / `disable` | systemd user unit |
| `kbd-ambientd --dry-run` | Log lux/targets without writing |

## Develop / validate

```bash
omarchy plugin validate .
bash tests/run-tests.sh
```

## Publish (maintainers)

1. Repo is public; `manifest.json` is at the **repository root**.
2. `omarchy plugin validate .` passes.
3. Push to GitHub.
4. Submit at: https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml  
   - Category: **Hardware** or **System**  
   - Tags: e.g. **Bar**, **System**, **Power management** (max 3)

## Troubleshooting

```bash
brightnessctl -l | grep kbd
cat /sys/bus/iio/devices/iio:device0/name
systemctl --user status kbd-ambientd.service
journalctl --user -u kbd-ambientd.service -f
omarchy plugin list --json | jq '.[] | select(.id=="joao.kbd-backlight")'
```
