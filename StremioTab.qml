import QtQuick
import qs.Commons
import qs.Ui

// Minimalist Stremio / MPV bridge status and player preference tab.
Column {
  id: root

  property var bar: null
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.4)
  property string fontFamily: Style.font.family
  property bool bridgeOnline: false
  property int bridgeCount: 0
  property string bridgeNotice: ""
  property string bridgeBaseUrl: "http://127.0.0.1:7040"
  property string playerMode: "mpv"

  signal settingChanged(string key, var value)

  spacing: Style.spacing.rowGap

  Rectangle {
    width: root.width
    implicitHeight: bridgeInfo.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

    Column {
      id: bridgeInfo
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(8)
      spacing: Style.space(6)

      Row {
        spacing: Style.space(6)

        Rectangle {
          width: Style.space(7)
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: (root.bridgeOnline && root.bridgeNotice === "") ? Color.accent : "#eb5757"
        }

        Text {
          textFormat: Text.PlainText
          text: !root.bridgeOnline
            ? "Offline (" + root.bridgeBaseUrl + ")"
            : (root.bridgeNotice !== ""
                ? root.bridgeNotice
                : "Online · " + root.bridgeCount + " matches ready")
          color: (root.bridgeOnline && root.bridgeNotice === "") ? root.foreground : "#eb5757"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Sports Streams (Highfly) → local Stremio Football Board (" + root.bridgeBaseUrl + "/manifest.json)."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Click \uf04b on a live match to watch (> in MPV switches to backup), or expand a match to pick a channel."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Dropdown {
    width: root.width
    label: "Open live match in"
    value: root.playerMode === "stremio" ? "Stremio" : "MPV"
    options: ["MPV", "Stremio"]
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onChanged: function (value) {
      root.settingChanged("stremioPlayer", value === "Stremio" ? "stremio" : "mpv")
    }
  }
}
