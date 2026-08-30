import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property string device: ""
  property int brightness: 0
  property int maxBrightness: 0
  property int lastNonZero: 0
  property bool available: false
  property bool autoAvailable: false
  property bool autoPaused: false
  property bool autoUnitActive: false
  property bool busy: false

  readonly property bool isOn: brightness > 0
  readonly property string levelText: Model.levelLabel(brightness, maxBrightness)
  readonly property bool autoOn: autoAvailable && autoUnitActive && !autoPaused

  function refresh() {
    if (!discover.running) discover.running = true
  }

  function setLevel(level) {
    level = Model.clampLevel(level, maxBrightness)
    if (!available || device === "") return
    if (setProc.running) return
    busy = true
    setProc.command = ["brightnessctl", "-d", device, "set", String(level)]
    setProc.running = true
  }

  function setPower(on) {
    if (on) setLevel(Model.restoreOnLevel(brightness, lastNonZero, maxBrightness))
    else setLevel(0)
  }

  function setAuto(on) {
    if (!autoAvailable) return
    if (autoProc.running) return
    busy = true
    if (on) {
      autoProc.command = ["bash", "-lc",
        "command -v kbd-ambientctl >/dev/null && kbd-ambientctl resume; " +
        "systemctl --user enable --now kbd-ambientd.service 2>/dev/null; true"]
    } else {
      autoProc.command = ["bash", "-lc", "kbd-ambientctl pause"]
    }
    autoProc.running = true
  }

  function togglePower() { setPower(!isOn) }
  function toggleAuto() { setAuto(!autoOn) }

  Timer {
    id: poll
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: discover
    command: ["bash", "-lc",
      "dev=''; for c in /sys/class/leds/*kbd_backlight*; do [ -e \"$c\" ] && dev=$(basename \"$c\") && break; done; " +
      "if [ -z \"$dev\" ]; then echo 'NONE'; exit 0; fi; " +
      "echo \"$dev\"; brightnessctl -d \"$dev\" get; brightnessctl -d \"$dev\" max; " +
      "if command -v kbd-ambientctl >/dev/null; then echo AUTO_YES; kbd-ambientctl status; " +
      "systemctl --user is-active kbd-ambientd.service 2>/dev/null || echo inactive; else echo AUTO_NO; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split("\n")
        if (!lines.length || lines[0] === "NONE" || lines[0] === "") {
          root.available = false
          root.device = ""
          return
        }
        root.device = lines[0]
        root.brightness = parseInt(lines[1], 10) || 0
        root.maxBrightness = parseInt(lines[2], 10) || 0
        root.available = true
        if (root.brightness > 0) root.lastNonZero = root.brightness

        var autoIdx = -1
        for (var i = 0; i < lines.length; i++) {
          if (lines[i] === "AUTO_YES") { autoIdx = i; break }
          if (lines[i] === "AUTO_NO") { root.autoAvailable = false; return }
        }
        if (autoIdx < 0) { root.autoAvailable = false; return }
        root.autoAvailable = true
        var statusBlob = lines.slice(autoIdx + 1, lines.length - 1).join("\n")
        root.autoPaused = Model.isAutoPausedFromStatus(statusBlob)
        var unitLine = lines[lines.length - 1] || ""
        root.autoUnitActive = (unitLine === "active")
      }
    }
  }

  Process {
    id: setProc
    onExited: function() {
      root.busy = false
      root.refresh()
    }
  }

  Process {
    id: autoProc
    onExited: function() {
      root.busy = false
      root.refresh()
    }
  }

  Component.onCompleted: refresh()
}
