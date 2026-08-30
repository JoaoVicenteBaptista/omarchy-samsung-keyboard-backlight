# Omarchy KBD Backlight Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an Omarchy bar widget + styled popup panel to turn keyboard backlight on/off, set intensity steps, and toggle ambient Auto.

**Architecture:** Pure `Model.js` helpers (testable). `Service.qml` polls/sets brightness via `brightnessctl` and Auto via `kbd-ambientctl`. `BarWidget.qml` is the bar entry (icon + level dots); `Panel.qml` is the popup. Install copies plugin to `~/.config/omarchy/plugins/joao.kbd-backlight/` and enables it on the bar.

**Tech Stack:** QML/Quickshell (`qs.Ui`, `qs.Commons`), `brightnessctl`, `kbd-ambientctl`, Omarchy plugin CLI.

**Spec:** `docs/superpowers/specs/2026-08-31-kbd-backlight-omarchy-plugin-design.md`

**Reference patterns (read-only):**
- `~/.config/omarchy/plugins/tharin.protonvpn/{BarWidget,Panel,Service,manifest}.qml|json`
- `/usr/share/omarchy/shell/plugins/panels/audio/Panel.qml` (BarIconButton + KeyboardPanel)
- `/usr/share/omarchy/shell/plugins/panels/weather/BarWidget.qml` (Loader panel inject)

---

## File map

| Path | Role |
|------|------|
| `plugin/joao.kbd-backlight/manifest.json` | Plugin metadata |
| `plugin/joao.kbd-backlight/Model.js` | Labels, auto parse, segment helpers |
| `plugin/joao.kbd-backlight/Service.qml` | Discover LED, poll/set brightness, auto pause/resume |
| `plugin/joao.kbd-backlight/BarWidget.qml` | Bar slot + panel loader + IPC |
| `plugin/joao.kbd-backlight/Panel.qml` | Styled popup UI |
| `tests/test-plugin-model.sh` | Node/bash tests for Model.js pure logic (duplicate critical funcs in shell OR run via `node -e` if Model stays pure ES) |
| `install.sh` / `uninstall.sh` / `README.md` | Deploy plugin |

**Note on Model tests:** Keep `Model.js` free of Qt imports. Test by extracting the same pure functions into `tests/model-pure.js` that mirrors Model.js, OR use:

```bash
node --check plugin/joao.kbd-backlight/Model.js  # syntax only
```

and a `tests/test-model.js` that **duplicates** the pure functions under test (keep in sync) — preferred: put pure functions only in `Model.js` and test with:

```bash
# Model.js uses function foo(){} without export — wrap for node:
node -e '
const fs=require("fs");
const code=fs.readFileSync("plugin/joao.kbd-backlight/Model.js","utf8");
eval(code);
// call functions...
'
```

---

### Task 1: Model.js + unit tests

**Files:**
- Create: `plugin/joao.kbd-backlight/Model.js`
- Create: `tests/test-plugin-model.sh`

- [ ] **Step 1: Write failing test script**

Create `tests/test-plugin-model.sh`:

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
node <<'NODE'
const fs = require("fs");
const path = require("path");
const root = process.env.ROOT || ".";
const code = fs.readFileSync(path.join(root, "plugin/joao.kbd-backlight/Model.js"), "utf8");
eval(code);

function assertEq(name, exp, act) {
  if (String(exp) !== String(act)) {
    console.error("FAIL:", name, "expected", exp, "got", act);
    process.exit(1);
  }
  console.log("PASS:", name);
}

assertEq("levelLabel 0", "Off", levelLabel(0, 3));
assertEq("levelLabel 1 max3", "Low", levelLabel(1, 3));
assertEq("levelLabel 2 max3", "Med", levelLabel(2, 3));
assertEq("levelLabel 3 max3", "High", levelLabel(3, 3));
assertEq("levelLabel 2 max5", "Level 2", levelLabel(2, 5));

assertEq("clamp", "0", clampLevel(-1, 3));
assertEq("clamp hi", "3", clampLevel(9, 3));

assertEq("auto paused", "true", String(isAutoPausedFromStatus("state: MANUAL_PAUSE\nmanual_until: 9999999999\n")));
assertEq("auto active", "false", String(isAutoPausedFromStatus("state: ACTIVE_AUTO\nmanual_until: 0\n")));

assertEq("segments max3", "3", segmentCount(3));
assertEq("segments max10", "4", segmentCount(10));

assertEq("restore", "2", restoreOnLevel(0, 2, 3));
assertEq("restore empty last", "3", restoreOnLevel(0, 0, 3));
console.log("all ok");
NODE
```

Run with `ROOT=$ROOT` — fix the script to export ROOT:

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROOT
node <<NODE
const fs = require("fs");
const path = require("path");
const root = process.env.ROOT;
const code = fs.readFileSync(path.join(root, "plugin/joao.kbd-backlight/Model.js"), "utf8");
eval(code);
function assertEq(name, exp, act) {
  if (String(exp) !== String(act)) {
    console.error("FAIL:", name, "expected", JSON.stringify(exp), "got", JSON.stringify(act));
    process.exit(1);
  }
  console.log("PASS:", name);
}
assertEq("levelLabel 0", "Off", levelLabel(0, 3));
assertEq("levelLabel 1 max3", "Low", levelLabel(1, 3));
assertEq("levelLabel 2 max3", "Med", levelLabel(2, 3));
assertEq("levelLabel 3 max3", "High", levelLabel(3, 3));
assertEq("levelLabel 2 max5", "Level 2", levelLabel(2, 5));
assertEq("clamp", 0, clampLevel(-1, 3));
assertEq("clamp hi", 3, clampLevel(9, 3));
assertEq("auto paused", true, isAutoPausedFromStatus("state: MANUAL_PAUSE\\nmanual_until: 9999999999\\n"));
assertEq("auto active", false, isAutoPausedFromStatus("state: ACTIVE_AUTO\\nmanual_until: 0\\n"));
assertEq("segments max3", 3, segmentCount(3));
assertEq("segments max10", 4, segmentCount(10));
assertEq("restore", 2, restoreOnLevel(0, 2, 3));
assertEq("restore empty last", 3, restoreOnLevel(0, 0, 3));
console.log("all ok");
NODE
```

- [ ] **Step 2: Run test — expect fail (missing Model.js)**

Run: `bash tests/test-plugin-model.sh`  
Expected: FAIL cannot read Model.js

- [ ] **Step 3: Implement Model.js**

```javascript
// Pure helpers for joao.kbd-backlight (no Qt).

function clampLevel(level, max) {
  var n = Number(level) || 0;
  var m = Number(max) || 0;
  if (m < 0) m = 0;
  if (n < 0) n = 0;
  if (n > m) n = m;
  return n | 0;
}

function levelLabel(level, max) {
  level = clampLevel(level, max);
  max = Number(max) || 0;
  if (level <= 0) return "Off";
  if (max === 3) {
    if (level === 1) return "Low";
    if (level === 2) return "Med";
    if (level === 3) return "High";
  }
  return "Level " + level;
}

function segmentCount(max) {
  max = Number(max) || 0;
  if (max <= 0) return 0;
  if (max > 4) return 4;
  return max | 0;
}

// Map display segment index 0..segCount-1 to actual brightness level 1..max
// (segment i represents roughly evenly spaced non-zero levels; level 0 is off separate)
function segmentToLevel(segIndex, max) {
  max = Number(max) || 0;
  var segs = segmentCount(max);
  if (segs <= 0) return 0;
  if (segIndex < 0) return 0;
  if (segs === max) return clampLevel(segIndex + 1, max); // 1..max
  // spread
  return clampLevel(Math.round(((segIndex + 1) * max) / segs), max);
}

function levelFillsSegment(level, segIndex, max) {
  var threshold = segmentToLevel(segIndex, max);
  return level >= threshold && level > 0;
}

function isAutoPausedFromStatus(text) {
  var s = String(text || "");
  if (s.indexOf("state: MANUAL_PAUSE") === -1) return false;
  var m = s.match(/manual_until:\s*(\d+)/);
  if (!m) return true;
  var until = Number(m[1]) || 0;
  var now = Date.now() / 1000;
  // long pause from ctl uses far-future until
  return until > now + 60;
}

function isAutoAvailableFromStatus(text) {
  var s = String(text || "");
  if (!s || s.indexOf("runtime: not running") !== -1 && s.indexOf("unit: inactive") !== -1) {
    // still available if unit exists — availability is PATH check in Service
  }
  return s.indexOf("unit:") !== -1 || s.indexOf("state:") !== -1;
}

function restoreOnLevel(current, lastNonZero, max) {
  max = Number(max) || 0;
  var last = Number(lastNonZero) || 0;
  if (last > 0) return clampLevel(last, max);
  return max > 0 ? max : 0;
}

function barIconGlyph(level) {
  // Nerd Font / icon font keyboard; Omarchy bar uses icon font as BarIconButton.text
  return level > 0 ? "󰌓" : "󰌐"; // keyboard / keyboard-off style; if missing glyphs, use "⌨"
}
```

If glyphs render wrong on Omarchy, switch to ASCII `"K"` / `"K○"` during Task 4 verification.

- [ ] **Step 4: Run tests — expect pass**

Run: `bash tests/test-plugin-model.sh`  
Expected: all PASS

Wire into `tests/run-tests.sh` by appending a call:

```bash
# existing loop already runs tests/test-*.sh — name file test-plugin-model.sh so it is included
```

Ensure `tests/run-tests.sh` still works with both test-lib and test-plugin-model.

- [ ] **Step 5: Commit**

```bash
chmod +x tests/test-plugin-model.sh
git add plugin/joao.kbd-backlight/Model.js tests/test-plugin-model.sh
git commit -m "feat: kbd backlight plugin Model.js helpers and tests"
```

---

### Task 2: manifest.json + validate

**Files:**
- Create: `plugin/joao.kbd-backlight/manifest.json`

- [ ] **Step 1: Write manifest**

```json
{
  "schemaVersion": 1,
  "id": "joao.kbd-backlight",
  "name": "Keyboard Backlight",
  "version": "1.0.0",
  "author": "Joao",
  "license": "MIT",
  "description": "Keyboard backlight on/off, intensity, and ambient auto for Omarchy.",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Keyboard Backlight",
    "description": "Control keyboard backlight brightness and ambient auto.",
    "category": "System",
    "allowMultiple": false,
    "defaultSection": "right"
  }
}
```

- [ ] **Step 2: Validate** (may fail until BarWidget exists — if validate requires entry file, create stub BarWidget in this task)

Minimal stub `BarWidget.qml` if needed:

```qml
import qs.Ui
BarWidget {
  moduleName: "joao.kbd-backlight"
}
```

- [ ] **Step 3: Run validate**

Run: `omarchy plugin validate plugin/joao.kbd-backlight`  
Expected: success / no errors

- [ ] **Step 4: Commit**

```bash
git add plugin/joao.kbd-backlight/manifest.json plugin/joao.kbd-backlight/BarWidget.qml
git commit -m "feat: add joao.kbd-backlight plugin manifest"
```

---

### Task 3: Service.qml (brightness + auto backend)

**Files:**
- Create: `plugin/joao.kbd-backlight/Service.qml`

- [ ] **Step 1: Implement Service.qml**

```qml
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
```

- [ ] **Step 2: Commit**

```bash
git add plugin/joao.kbd-backlight/Service.qml
git commit -m "feat: kbd backlight Service.qml brightness and auto backend"
```

---

### Task 4: BarWidget.qml (icon + level dots + panel loader)

**Files:**
- Modify: `plugin/joao.kbd-backlight/BarWidget.qml` (replace stub)

- [ ] **Step 1: Implement full BarWidget**

```qml
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "joao.kbd-backlight"

  Service {
    id: kbd
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("service" in t) t.service = kbd
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Faster poll while panel open
  Connections {
    target: panelLoader.item
    function onOpenedChanged() {
      // Service timer stays 2s; panel can call service.refresh on open
      if (panelLoader.item && panelLoader.item.opened) kbd.refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: true

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "joao.kbd-backlight"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.togglePanel() }
    function status(): string {
      return JSON.stringify({
        available: kbd.available,
        brightness: kbd.brightness,
        max: kbd.maxBrightness,
        autoOn: kbd.autoOn
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: kbd.available
      ? ("Keyboard · " + kbd.levelText)
      : "No keyboard backlight"
    iconComponent: Component {
      Item {
        id: iconRoot
        property color fg: button.foreground
        property color dim: Qt.darker(button.foreground, 1.55)

        // Glyph
        Text {
          id: glyph
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: 1
          text: Model.barIconGlyph(kbd.brightness)
          color: kbd.available && kbd.isOn ? iconRoot.fg : iconRoot.dim
          font.family: button.fontFamily
          font.pixelSize: Math.max(10, Style.bar.iconFont - 2)
        }

        // Level segments
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: glyph.bottom
          anchors.topMargin: 2
          spacing: 2
          visible: kbd.available && kbd.maxBrightness > 0
          Repeater {
            model: Model.segmentCount(kbd.maxBrightness)
            Rectangle {
              width: 3
              height: 3
              radius: 0.5
              color: Model.levelFillsSegment(kbd.brightness, index, kbd.maxBrightness)
                ? iconRoot.fg
                : Qt.rgba(iconRoot.fg.r, iconRoot.fg.g, iconRoot.fg.b, 0.25)
            }
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (!kbd.available) return
      if (buttonCode === Qt.RightButton) kbd.togglePower()
      else if (buttonCode === Qt.MiddleButton) kbd.refresh()
      else root.togglePanel()
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugin/joao.kbd-backlight/BarWidget.qml
git commit -m "feat: kbd backlight BarWidget with level indicator"
```

---

### Task 5: Panel.qml (styled UI)

**Files:**
- Create: `plugin/joao.kbd-backlight/Panel.qml`

- [ ] **Step 1: Implement Panel**

Follow Omarchy `Panel` + content column. Keep keyboard nav simpler: focus sections power / intensity / auto.

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "joao.kbd-backlight"
  ipcTarget: "joao.kbd-backlight"
  manageIpc: false

  property var service: null
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  property string focusSection: "power" // power | intensity | auto
  property int intensityIndex: 0
  property bool cursorActive: false

  readonly property bool kbdOn: service ? service.isOn : false
  readonly property bool autoOn: service ? service.autoOn : false
  readonly property bool autoAvailable: service ? service.autoAvailable : false
  readonly property int brightness: service ? service.brightness : 0
  readonly property int maxBrightness: service ? service.maxBrightness : 0
  readonly property string heroMeta: service && service.available
    ? service.levelText
    : "Unavailable"

  function refresh() { if (service) service.refresh() }

  onOpenedChanged: if (opened) refresh()

  // ---- content ----
  // Panel base provides popout chrome; put content in default content item.
  // Check Panel.qml API: many panels set `content:` or children inside Panel.

  // IMPORTANT for implementer: open tharin.protonvpn/Panel.qml and omarchy.dropbox/Panel.qml
  // and match how they attach content (Column inside panel body). Copy the structural
  // wrapper (hero row, separators, ToggleSwitch) from protonvpn hero + power switch.

  // Content outline to implement by mirroring protonvpn layout:
  // 1. Hero row: title "Keyboard backlight", meta heroMeta, optional icon
  // 2. Row "Power" + ToggleSwitch { checked: kbdOn; onToggled: service.setPower(checked) }
  // 3. Label "Intensity" + Row of level buttons 0..maxBrightness
  // 4. Row "Ambient auto" + ToggleSwitch { checked: autoOn; enabled: autoAvailable; onToggled: service.setAuto(checked) }
  //    subtitle Text dim "Turns on in the dark · off when idle" or "Daemon not installed"
  // 5. Footer Text dim "Fn keyboard keys still work"

  // Intensity button:
  // Repeater model: maxBrightness+1 (levels 0..max)
  // Rectangle/Button each: width height ~28, text level number or "Off" for 0
  // background: level===brightness ? selectedFill : (hover ? hoverFill : transparent)
  // onClicked: service.setLevel(level)

  // Keyboard: if PanelKeyCatcher available, wire j/k between sections and left/right on intensity.
}
```

**Implementer must** open `~/.config/omarchy/plugins/tharin.protonvpn/Panel.qml` and copy the **Panel content attachment pattern** (how children are declared under `Panel { }`), then build the UI outlined above with real working bindings — do not leave the comment-only stub. Target ~150–250 lines, not 400+.

**Hero-level polish:** use `Style.space(...)`, `PanelSeparator`, `ToggleSwitch` from `qs.Ui`, typography sizes from `Style`.

- [ ] **Step 2: Validate plugin**

Run: `omarchy plugin validate plugin/joao.kbd-backlight`  
Expected: OK

- [ ] **Step 3: Commit**

```bash
git add plugin/joao.kbd-backlight/Panel.qml
git commit -m "feat: kbd backlight styled popup Panel"
```

---

### Task 6: install.sh / uninstall.sh / README

**Files:**
- Modify: `install.sh`
- Modify: `uninstall.sh`
- Modify: `README.md`

- [ ] **Step 1: Extend install.sh** after daemon install:

```bash
# --- Omarchy bar plugin ---
PLUGIN_SRC="$ROOT/plugin/joao.kbd-backlight"
PLUGIN_DST="$HOME/.config/omarchy/plugins/joao.kbd-backlight"
if [[ -d "$PLUGIN_SRC" ]]; then
  mkdir -p "$HOME/.config/omarchy/plugins"
  rm -rf "$PLUGIN_DST"
  mkdir -p "$PLUGIN_DST"
  cp -a "$PLUGIN_SRC"/. "$PLUGIN_DST"/
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin enable joao.kbd-backlight --section right 2>/dev/null || true
    omarchy bar put joao.kbd-backlight --section right --before omarchy.power 2>/dev/null \
      || omarchy bar put joao.kbd-backlight --section right 2>/dev/null \
      || true
    omarchy-shell shell rescanPlugins 2>/dev/null || true
  fi
  echo "Installed Omarchy plugin joao.kbd-backlight"
fi
```

- [ ] **Step 2: Extend uninstall.sh**

```bash
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable joao.kbd-backlight 2>/dev/null || true
fi
rm -rf "$HOME/.config/omarchy/plugins/joao.kbd-backlight"
```

- [ ] **Step 3: README section**

```markdown
## Omarchy bar plugin

After `./install.sh`, a **Keyboard Backlight** widget appears on the bar (right section).

| Action | Result |
|--------|--------|
| Click | Open panel |
| Right-click | Toggle on/off |
| Panel Power | On/off |
| Panel Intensity | Set level 0…max |
| Panel Ambient auto | Pause/resume `kbd-ambientd` |

```bash
omarchy plugin disable joao.kbd-backlight
omarchy plugin enable joao.kbd-backlight --section right
```
```

- [ ] **Step 4: Commit**

```bash
git add install.sh uninstall.sh README.md
git commit -m "feat: install Omarchy kbd backlight bar plugin"
```

---

### Task 7: Install on machine and verify

- [ ] **Step 1: Run unit tests**

`bash tests/run-tests.sh` → all PASS

- [ ] **Step 2: Install**

`./install.sh`  
Expected: plugin installed message; daemon still active

- [ ] **Step 3: Validate installed copy**

`omarchy plugin validate ~/.config/omarchy/plugins/joao.kbd-backlight`  
`omarchy plugin list` | grep kbd-backlight

- [ ] **Step 4: Rescan / restart shell if needed**

```bash
omarchy-shell shell rescanPlugins 2>/dev/null || omarchy restart shell
```

- [ ] **Step 5: Manual UI check** (user or agent with hyprctl)

- Bar shows keyboard widget  
- Click opens panel  
- Off/on and intensity change `brightnessctl -d 'samsung-galaxybook::kbd_backlight' get`  
- Auto toggle changes `kbd-ambientctl status`

- [ ] **Step 6: Fix any glyph/layout issues; commit fixes**

```bash
git add -A && git commit -m "fix: kbd plugin UI polish after install verify" || true
```

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| Bar widget + panel | 4, 5 |
| On/Off | 3, 5 |
| Intensity steps | 3, 5 |
| Auto toggle | 3, 5 |
| Theme-aware | 5 |
| install.sh deploy | 6 |
| Graceful no LED / no daemon | 3, 5 |
| Model helpers tested | 1 |
| validate | 2, 7 |

## Self-review notes

- Panel.qml must be real QML copied structurally from protonvpn/dropbox — comments in Task 5 are a checklist, not the deliverable.
- `manageIpc: false` on Panel because BarWidget owns `IpcHandler` target `joao.kbd-backlight`.
- Right-click toggle is a small extra beyond spec (handy); keep it.
- If `omarchy bar put --before` fails, fallback put without before is enough.
