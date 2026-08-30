import QtQuick
import QtQuick.Controls
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
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  readonly property bool kbdAvailable: service && service.available
  readonly property bool kbdOn: service && service.isOn
  readonly property string heroMeta: kbdAvailable ? service.levelText : "Unavailable"
  readonly property int maxLevel: service ? service.maxBrightness : 0
  readonly property int levelCount: maxLevel + 1

  property string focusSection: "power"
  property int intensityIndex: 0
  property bool cursorActive: false

  readonly property bool powerHasCursor: cursorActive && focusSection === "power"
  readonly property bool intensityHasCursor: cursorActive && focusSection === "intensity"
  readonly property bool autoHasCursor: cursorActive && focusSection === "auto"

  function clampIntensityIndex() {
    var max = Math.max(0, maxLevel)
    if (intensityIndex < 0) intensityIndex = 0
    if (intensityIndex > max) intensityIndex = max
  }

  function syncIntensityFromService() {
    if (!service) return
    intensityIndex = Model.clampLevel(service.brightness, service.maxBrightness)
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }
    if (dy !== 0) {
      if (dy > 0) {
        if (focusSection === "power") focusSection = "intensity"
        else if (focusSection === "intensity") focusSection = "auto"
      } else {
        if (focusSection === "auto") focusSection = "intensity"
        else if (focusSection === "intensity") focusSection = "power"
      }
      return
    }
    if (dx !== 0 && focusSection === "intensity" && levelCount > 0) {
      intensityIndex = Model.clampLevel(intensityIndex + dx, maxLevel)
      if (service && service.available) service.setLevel(intensityIndex)
    }
  }

  function activateCursor() {
    if (!cursorActive || !service) return
    if (focusSection === "power") service.togglePower()
    else if (focusSection === "auto") {
      if (service.autoAvailable) service.toggleAuto()
    } else if (focusSection === "intensity") {
      service.setLevel(intensityIndex)
    }
  }

  function focusPower() {
    cursorActive = true
    focusSection = "power"
  }

  function focusIntensity(level) {
    cursorActive = true
    focusSection = "intensity"
    intensityIndex = Model.clampLevel(level, maxLevel)
  }

  function focusAuto() {
    cursorActive = true
    focusSection = "auto"
  }

  onOpenedChanged: {
    if (opened) {
      focusSection = "power"
      cursorActive = false
      if (service) {
        service.refresh()
        syncIntensityFromService()
      }
    }
  }

  Connections {
    target: root.service
    function onBrightnessChanged() {
      if (root.focusSection !== "intensity" || !root.cursorActive)
        root.syncIntensityFromService()
    }
    function onMaxBrightnessChanged() {
      root.clampIntensityIndex()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") {
          if (root.service) root.service.togglePower()
        } else if (t === "a" || t === "A") {
          if (root.service && root.service.autoAvailable) root.service.toggleAuto()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.powerHasCursor
            function focusHero() { root.focusPower() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Keyboard backlight"
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.kbdOn ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: "⌨"
                  color: root.kbdOn ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  checked: root.kbdOn
                  busy: root.service ? root.service.busy : false
                  enabled: root.kbdAvailable
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: {
                    if (root.service) root.service.togglePower()
                  }
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "INTENSITY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              id: intensityRow
              width: parent.width
              spacing: Style.space(6)
              visible: root.kbdAvailable && root.maxLevel > 0

              Repeater {
                model: root.levelCount

                delegate: CursorSurface {
                  id: levelBtn
                  required property int index
                  readonly property int level: index
                  readonly property bool isActive: root.service && root.service.brightness === level
                  readonly property bool isSelected: root.intensityHasCursor && root.intensityIndex === level

                  width: Math.floor((intensityRow.width - intensityRow.spacing * Math.max(0, root.levelCount - 1)) / Math.max(1, root.levelCount))
                  implicitHeight: Style.space(36)
                  hasCursor: isSelected
                  current: isActive
                  foreground: root.foreground
                  accent: Color.accent
                  fill: root.hoverFill
                  currentFill: root.selectedFill
                  bordered: true

                  Text {
                    anchors.centerIn: parent
                    text: Model.levelLabel(levelBtn.level, root.maxLevel)
                    color: levelBtn.isActive || levelBtn.isSelected ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.focusIntensity(levelBtn.level)
                    onClicked: {
                      root.focusIntensity(levelBtn.level)
                      if (root.service) root.service.setLevel(levelBtn.level)
                    }
                  }
                }
              }
            }

            Text {
              visible: !root.kbdAvailable
              width: parent.width
              text: "No keyboard backlight device found"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          CursorSurface {
            id: autoRow
            width: parent.width
            implicitHeight: Math.max(Style.space(54), autoContent.implicitHeight + Style.space(16))
            hasCursor: root.autoHasCursor
            foreground: root.foreground
            accent: Color.accent
            fill: root.hoverFill
            opacity: root.service && root.service.autoAvailable ? 1.0 : 0.55

            Row {
              id: autoContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              Column {
                width: parent.width - autoSwitch.width - parent.spacing
                spacing: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  text: "Ambient auto"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  width: parent.width
                  elide: Text.ElideRight
                }

                Text {
                  text: root.service && root.service.autoAvailable
                    ? (root.service.autoOn ? "Following ambient light" : "Paused — manual control")
                    : "kbd-ambientd not installed"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  width: parent.width
                  wrapMode: Text.WordWrap
                }
              }

              ToggleSwitch {
                id: autoSwitch
                anchors.verticalCenter: parent.verticalCenter
                checked: root.service ? root.service.autoOn : false
                busy: root.service ? root.service.busy : false
                enabled: root.service && root.service.autoAvailable
                interactive: false
                cursorRing: false
                foreground: root.foreground
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.service && root.service.autoAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
              onContainsMouseChanged: if (containsMouse) root.focusAuto()
              onClicked: {
                root.focusAuto()
                if (root.service && root.service.autoAvailable) root.service.toggleAuto()
              }
            }
          }

          Text {
            width: parent.width
            text: "Fn keyboard keys still work"
            color: Qt.darker(root.foreground, 1.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
