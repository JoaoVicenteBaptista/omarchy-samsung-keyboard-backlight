# omarchy-samsung-keyboard-backlight

Automatic keyboard backlight for Samsung Galaxy Book on [Omarchy](https://omarchy.org/) (ALS → brightness, idle-off, manual pause).

## Requirements

- `samsung-galaxybook` (or any `*kbd_backlight*` LED)
- IIO ambient light (`in_illuminance_raw`)
- `brightnessctl`, systemd user session
- Idle detection: `libinput` CLI (`libinput-tools`) if present, else Python 3 reading `/dev/input` (user in group `input`)

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

## Omarchy bar plugin

Install copies `plugin/joao.kbd-backlight` into `~/.config/omarchy/plugins/` and enables it on the right bar section (before power when possible).

| Control | Action |
|---------|--------|
| Left-click bar icon | Open panel (power, intensity levels, ambient auto) |
| Right-click bar icon | Toggle backlight on/off |
| Middle-click bar icon | Refresh state |
| Panel power switch | On/off |
| Panel intensity buttons | Set level 0…max |
| Panel ambient auto | Pause/resume `kbd-ambientd` auto mode |
| Keyboard in panel | Arrows navigate; Enter activates; `t` power; `a` auto |

```bash
# Enable / place on bar (if install did not)
omarchy plugin enable joao.kbd-backlight --section right
omarchy bar put joao.kbd-backlight --section right --before omarchy.power

# Disable
omarchy plugin disable joao.kbd-backlight

# Validate
omarchy plugin validate ~/.config/omarchy/plugins/joao.kbd-backlight
```

`./uninstall.sh` disables the plugin and removes the plugin directory.

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
