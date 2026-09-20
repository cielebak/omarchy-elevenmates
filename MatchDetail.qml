import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// What unfolds under a match when it is opened: who scored, and the handful of
// team numbers worth reading at a glance.
//
// Everything is hung off one geometry - a left column, a centre gutter and a
// right column - so the scorers, the labels and the numbers all line up on the
// same edges, and the home side is always on the left of centre.
//
// The scorers come free with the scoreboard; `stats` costs its own request and
// arrives a moment later, so the block has to read sensibly while it is null.
Rectangle {
  id: root

  property var match: null
  property var stats: null
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.4)
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int indent: 0
  property int rightInset: 0

  readonly property var goals: (match && match.goals) ? match.goals : []
  readonly property bool hasStats: stats && stats.rows && stats.rows.length > 0
  readonly property bool kickedOff: match && match.state !== "pre"

  readonly property int pad: Style.space(8)
  // Wide enough for the longest label ("Yellow cards") plus air on both sides,
  // so a number never collides with the word it belongs to.
  readonly property int gutter: Style.space(116)
  readonly property int columnWidth: Math.max(
    Style.space(40), Math.round((width - indent - rightInset - gutter) / 2))

  // Scorers only need room for a minute between the two names, so they get a
  // narrower gutter than the stat labels and keep their names unclipped. Both
  // blocks stay centred on the same axis as the score above.
  readonly property int goalGutter: Style.space(64)
  readonly property int goalColumnWidth: Math.max(
    Style.space(40), Math.round((width - indent - rightInset - goalGutter) / 2))

  function statValue(teamId, key) {
    var team = hasStats ? stats.teams[teamId] : null
    var value = team ? team[key] : ""
    return (value === undefined || value === null || value === "") ? "" : String(value)
  }

  // The home share of a stat, for the meter. Two zeroes split the bar evenly
  // rather than collapsing it to one side.
  function homeShare(key) {
    var home = parseFloat(statValue(match.home.id, key))
    var away = parseFloat(statValue(match.away.id, key))
    if (!isFinite(home) || !isFinite(away) || home + away <= 0) return 0.5
    return home / (home + away)
  }

  implicitHeight: body.implicitHeight + pad * 2
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
  radius: Style.cornerRadius

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.indent
    anchors.rightMargin: root.rightInset
    anchors.topMargin: root.pad
    spacing: Style.space(3)

    // ------------------------------------------------------------- scorers
    Repeater {
      model: root.goals

      Item {
        required property var modelData
        readonly property bool home: root.match && modelData.team === root.match.home.id
        width: body.width
        implicitHeight: Math.round(Style.font.caption * 1.8)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: root.goalColumnWidth
          rightPadding: Style.space(8)
          horizontalAlignment: Text.AlignRight
          visible: parent.home
          textFormat: Text.PlainText
          text: Model.scorerLine(modelData)
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: root.goalGutter
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: modelData.minute
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: root.goalColumnWidth
          leftPadding: Style.space(8)
          visible: !parent.home
          textFormat: Text.PlainText
          text: Model.scorerLine(modelData)
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Rectangle {
      width: body.width
      height: 1
      visible: root.goals.length > 0 && root.hasStats
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
    }

    Item {
      width: body.width
      height: Style.space(4)
      visible: root.goals.length > 0 && root.hasStats
    }

    Text {
      width: body.width
      visible: !root.hasStats
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.kickedOff ? "Fetching the numbers…" : "Not kicked off yet."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // ---------------------------------------------------------------- stats
    Repeater {
      model: root.hasStats ? root.stats.rows : []

      Item {
        required property var modelData
        readonly property real share: root.homeShare(modelData.key)
        width: body.width
        implicitHeight: Math.round(Style.font.caption * 2.4)

        Text {
          anchors.left: parent.left
          anchors.top: parent.top
          width: root.columnWidth
          rightPadding: Style.space(8)
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: Model.statValueLabel(root.statValue(root.match.home.id, modelData.key),
                                     modelData.suffix)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: parent.share > 0.5
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: root.gutter
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: modelData.label
          elide: Text.ElideRight
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.right: parent.right
          anchors.top: parent.top
          width: root.columnWidth
          leftPadding: Style.space(8)
          textFormat: Text.PlainText
          text: Model.statValueLabel(root.statValue(root.match.away.id, modelData.key),
                                     modelData.suffix)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: parent.share < 0.5
        }

        // One meter per row, split where the two sides meet, so the shape of
        // the match is readable without reading a single number.
        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(3)
          width: root.gutter - Style.space(24)
          height: Style.space(3)

          Rectangle {
            anchors.left: parent.left
            width: Math.max(1, Math.round(parent.width * parent.parent.share) - 1)
            height: parent.height
            radius: height / 2
            color: root.accent
          }

          Rectangle {
            anchors.right: parent.right
            width: Math.max(1, parent.width - Math.round(parent.width * parent.parent.share) - 1)
            height: parent.height
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
          }
        }
      }
    }
  }
}
