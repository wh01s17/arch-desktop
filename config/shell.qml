import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Widgets

ShellRoot {
  id: root
  property bool menuVisible: false
  property bool barVisible: true
  property string menuName: "root"
  readonly property color bg: "#11161a"
  readonly property color fg: "#cbd5ce"
  readonly property color accent: "#84c959"
  readonly property color cyan: "#45d9ea"
  readonly property var entries: menuName === "system" ? [
    { label: "Bloquear", action: "lock" },
    { label: "Cerrar sesión", action: "logout" },
    { label: "Reiniciar", action: "reboot" },
    { label: "Apagar", action: "poweroff" }
  ] : menuName === "calendar" ? [
    { label: Qt.formatDateTime(new Date(), "dddd d MMMM yyyy"), action: "noop" }
  ] : menuName === "audio" ? [
    { label: "Volumen +", action: "volume-up" },
    { label: "Volumen -", action: "volume-down" },
    { label: "Silenciar", action: "volume-mute" },
    { label: "Mezclador", action: "audio" }
  ] : [
    { label: "Aplicaciones", action: "apps" },
    { label: "Terminal", action: "terminal" },
    { label: "Archivos", action: "files" },
    { label: "Audio", action: "audio" },
    { label: "Red", action: "network" },
    { label: "Bluetooth", action: "bluetooth" },
    { label: "Captura", action: "screenshot" },
    { label: "Notificaciones", action: "notifications" },
    { label: "Sistema", action: "system-menu" }
  ]

  IpcHandler {
    target: "arch-look"
    function toggle(name: string): string {
      var requested = name || "root"
      root.menuVisible = root.menuName === requested ? !root.menuVisible : true
      root.menuName = requested
      return "ok"
    }
    function hide(): string { root.menuVisible = false; return "ok" }
    function bar(): string { root.barVisible = !root.barVisible; return "ok" }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      visible: root.barVisible
      screen: modelData
      anchors { top: true; left: true; right: true }
      implicitHeight: 32
      color: root.bg

      Rectangle {
        anchors.fill: parent
        color: root.bg
        border.color: "#243038"
        border.width: 1
      }
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12
        Image {
          source: "logo.svg"
          sourceSize.width: 20
          sourceSize.height: 20
          Layout.preferredWidth: 20
          Layout.preferredHeight: 20
          MouseArea { anchors.fill: parent; onClicked: { root.menuName = "root"; root.menuVisible = !root.menuVisible } }
        }
        Repeater {
          model: [1, 2, 3, 4, 5]
          Text {
            required property int modelData
            text: modelData
            color: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData ? root.accent : "#748178"
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 13; bold: true }
            MouseArea {
              anchors.fill: parent
              onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + modelData + "\" })"])
            }
          }
        }
        Text { text: "│"; color: "#33454f" }
        Text {
          text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : "Escritorio"
          color: root.fg
          elide: Text.ElideRight
          Layout.maximumWidth: 260
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
        }
        Item { Layout.fillWidth: true }
        Text {
          id: clock
          text: Qt.formatDateTime(new Date(), "ddd d MMM HH:mm:ss")
          color: root.accent
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 13; bold: true }
          Timer { interval: 1000; repeat: true; running: true; onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd d MMM HH:mm:ss") }
        }
        Item { Layout.fillWidth: true }
        Repeater {
          model: SystemTray.items.values
          Item {
            required property var modelData
            width: 22; height: 24
            IconImage { anchors.centerIn: parent; width: 17; height: 17; source: modelData.icon }
            MouseArea { anchors.fill: parent; onClicked: modelData.activate() }
          }
        }
        Repeater {
          model: [
            { icon: "󰕾", action: "audio" },
            { icon: "󰖩", action: "network" },
            { icon: "󰂯", action: "bluetooth" },
            { icon: "󰃠", action: "display" },
            { icon: "󰐥", action: "system-menu" }
          ]
          Text {
            required property var modelData
            text: modelData.icon
            color: root.cyan
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 15 }
            MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/arch-look-action", modelData.action]) }
          }
        }
      }
    }
  }

  PanelWindow {
    visible: root.menuVisible
    anchors { top: true; right: true }
    margins { top: 36; right: 10 }
    implicitWidth: 220
    implicitHeight: menuColumn.implicitHeight + 14
    color: root.bg
    Column {
      id: menuColumn
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
      spacing: 2
      Repeater {
        model: root.entries
        Rectangle {
          required property var modelData
          width: menuColumn.width
          height: 32
          color: hover.containsMouse ? "#2b4221" : "transparent"
          Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; text: modelData.label; color: root.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
              root.menuVisible = false
              Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/arch-look-action", modelData.action])
            }
          }
        }
      }
    }
  }
}
