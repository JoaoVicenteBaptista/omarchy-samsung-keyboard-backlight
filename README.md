# omarchy-samsung-keyboard-backlight

Automatic keyboard backlight for Samsung Galaxy Book on [Omarchy](https://omarchy.org/) (ALS → brightness, idle-off, manual pause).

## Requirements

- `samsung-galaxybook` (or any `*kbd_backlight*` LED)
- IIO ambient light (`in_illuminance_raw`)
- `brightnessctl`, `libinput` (for idle), systemd user session

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
