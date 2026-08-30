import QtQuick
import Quickshell
import Quickshell.Io
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

  Connections {
    target: panelLoader.item
    function onOpenedChanged() {
      if (panelLoader.item && panelLoader.item.opened) kbd.refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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
    tooltipText: kbd.available ? ("Keyboard · " + kbd.levelText) : "No keyboard backlight"
    iconComponent: Component {
      Item {
        property color fg: button.foreground
        property color dimc: Qt.darker(button.foreground, 1.55)

        Text {
          id: glyph
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: kbd.available ? -3 : 0
          text: "⌨"
          color: kbd.available && kbd.isOn ? fg : dimc
          font.family: button.fontFamily
          font.pixelSize: Math.max(12, Style.bar.iconFont - 1)
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: glyph.bottom
          anchors.topMargin: 1
          spacing: 2
          visible: kbd.available && kbd.maxBrightness > 0
          Repeater {
            model: Model.segmentCount(kbd.maxBrightness)
            Rectangle {
              width: 3
              height: 3
              radius: 1
              color: Model.levelFillsSegment(kbd.brightness, index, kbd.maxBrightness)
                ? fg
                : Qt.rgba(fg.r, fg.g, fg.b, 0.22)
            }
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (!kbd.available) {
        root.togglePanel()
        return
      }
      if (buttonCode === Qt.RightButton) kbd.togglePower()
      else if (buttonCode === Qt.MiddleButton) kbd.refresh()
      else root.togglePanel()
    }
  }
}
