import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// What unfolds under a match when it is opened: FotMob-style chronological
// timeline (Key events by default: goals+assists, red cards, missed pens;
// compact Key / All segmented switch to reveal yellow cards & substitutions),
// key team numbers aligned under the score, and optional MPV stream pills.
Rectangle {
  id: root

  property var match: null
  property var stats: null
  property var streams: []
  property bool loadingStreams: false
  property bool hasStream: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.4)
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int indent: 0
  property int rightInset: 0

  signal playStreamRequested(string streamUrl)

  readonly property var goals: (match && match.goals) ? match.goals : []
  property bool showAllEvents: false
  readonly property var timelineEvents: {
    if (stats && stats.events && stats.events.length > 0) return stats.events
    var fallback = []
    for (var i = 0; i < goals.length; i++) {
      var g = goals[i]
      fallback.push({
        minute: g.minute || "",
        team: g.team || "",
        kind: "goal",
        player: g.scorer || "Goal",
        secondary: "",
        ownGoal: g.ownGoal === true,
        penalty: g.penalty === true
      })
    }
    return fallback
  }
  function isKeyEvent(ev) {
    var k = (ev && ev.kind) || "goal"
    return k !== "sub"
  }
  readonly property var visibleEvents: {
    if (showAllEvents) return timelineEvents
    var out = []
    for (var i = 0; i < timelineEvents.length; i++) {
      if (isKeyEvent(timelineEvents[i])) out.push(timelineEvents[i])
    }
    return out
  }
  readonly property int secondaryEventCount: {
    var n = 0
    for (var i = 0; i < timelineEvents.length; i++) {
      if (!isKeyEvent(timelineEvents[i])) n++
    }
    return n
  }
  readonly property bool hasTimelineBlock: visibleEvents.length > 0 || secondaryEventCount > 0
  readonly property bool hasStats: stats && stats.rows && stats.rows.length > 0
  readonly property bool kickedOff: match && match.state !== "pre"

  readonly property int pad: Style.space(8)
  readonly property int sidePad: Style.space(10)
  // Vertical axis directly under the match score (`Nice 1-2 PSG`).
  readonly property real scoreAxisX: {
    var fieldWidth = Math.max(0, width - indent - rightInset)
    return indent + fieldWidth / 2
  }
  // Centre axis inside `body` (which starts at `sidePad`).
  readonly property real axisInBody: Math.max(
    Style.space(80), Math.min(body.width - Style.space(80), scoreAxisX - sidePad))

  // Wide enough for "Yellow cards" plus air on both sides.
  readonly property int gutter: Style.space(116)
  readonly property int eventGutter: Style.space(44)
  readonly property real homeEventWidth: Math.max(
    Style.space(40), axisInBody - eventGutter / 2 - Style.space(6))
  readonly property real awayEventWidth: Math.max(
    Style.space(40), body.width - (axisInBody + eventGutter / 2 + Style.space(6)))
  readonly property real homeStatWidth: Math.max(
    Style.space(32), axisInBody - gutter / 2 - Style.space(8))
  readonly property real awayStatWidth: Math.max(
    Style.space(32), body.width - (axisInBody + gutter / 2 + Style.space(8)))

  function statValue(teamId, key) {
    var team = hasStats ? stats.teams[teamId] : null
    var value = team ? team[key] : ""
    return (value === undefined || value === null || value === "") ? "" : String(value)
  }

  function homeShare(key) {
    var home = parseFloat(statValue(match.home.id, key))
    var away = parseFloat(statValue(match.away.id, key))
    if (!isFinite(home) || !isFinite(away) || home + away <= 0) return 0.5
    return home / (home + away)
  }

  function primaryText(ev) {
    if (!ev) return ""
    var name = ev.player || (ev.kind === "goal" ? "Goal" : "")
    if (ev.kind === "goal") {
      if (ev.ownGoal) return name + " (o.g.)"
      if (ev.penalty) return name + " (pen.)"
    } else if (ev.kind === "missed_pen") {
      return name + " (pen. missed)"
    }
    return name
  }

  function secondaryText(ev) {
    if (!ev || !ev.secondary) return ""
    if (ev.kind === "goal") return "(" + ev.secondary + ")"
    if (ev.kind === "sub") return ev.secondary
    return ""
  }

  implicitHeight: body.implicitHeight + pad * 2
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
  radius: Style.cornerRadius

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.sidePad
    anchors.rightMargin: root.sidePad
    anchors.topMargin: root.pad
    spacing: Style.space(3)

    // ----------------------------------------- FotMob Key / All segmented pill
    Item {
      width: body.width
      visible: root.secondaryEventCount > 0
      implicitHeight: Math.round(Style.font.caption * 2.0)

      Rectangle {
        x: Math.round(root.axisInBody - width / 2)
        anchors.verticalCenter: parent.verticalCenter
        width: segRow.implicitWidth + Style.space(4)
        height: Style.space(20)
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

        Row {
          id: segRow
          anchors.centerIn: parent
          spacing: Style.space(2)

          Rectangle {
            width: keyLbl.implicitWidth + Style.space(14)
            height: Style.space(16)
            radius: Math.max(2, Style.cornerRadius - 1)
            color: !root.showAllEvents
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
              : (keyHover.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07) : "transparent")

            Text {
              id: keyLbl
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "Key"
              color: !root.showAllEvents ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption - 1
              font.bold: !root.showAllEvents
            }

            MouseArea {
              id: keyHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showAllEvents = false
            }
          }

          Rectangle {
            width: allLbl.implicitWidth + Style.space(14)
            height: Style.space(16)
            radius: Math.max(2, Style.cornerRadius - 1)
            color: root.showAllEvents
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
              : (allHover.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07) : "transparent")

            Text {
              id: allLbl
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "All · " + root.timelineEvents.length
              color: root.showAllEvents ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption - 1
              font.bold: root.showAllEvents
            }

            MouseArea {
              id: allHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showAllEvents = true
            }
          }
        }
      }
    }

    // ------------------------------------------------------------- timeline
    Repeater {
      model: root.visibleEvents

      Item {
        required property var modelData
        readonly property bool home: root.match && modelData.team === root.match.home.id
        readonly property string kind: modelData.kind || "goal"
        readonly property string primary: root.primaryText(modelData)
        readonly property string secondary: root.secondaryText(modelData)
        width: body.width
        implicitHeight: Math.round(Style.font.caption * 1.9)

        // Home side (right-aligned against the minute column)
        Row {
          visible: parent.home
          anchors.right: minuteLabel.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)
          layoutDirection: Qt.RightToLeft

          Item {
            width: Style.space(12)
            height: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              visible: parent.parent.parent.kind === "yellow" || parent.parent.parent.kind === "red"
              anchors.centerIn: parent
              width: Style.space(7)
              height: Style.space(10)
              radius: 1
              color: parent.parent.parent.kind === "red" ? "#eb5757" : "#f2c94c"
            }

            Text {
              visible: parent.parent.parent.kind === "goal" || parent.parent.parent.kind === "missed_pen"
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: parent.parent.parent.kind === "goal" ? "\uf1e3" : "\uf00d"
              color: parent.parent.parent.kind === "goal" ? root.accent : "#eb5757"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption - 1
            }

            Text {
              visible: parent.parent.parent.kind === "sub"
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "\u2191"
              color: "#4ade80"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(Style.space(40), root.homeEventWidth - Style.space(18)))
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: parent.parent.secondary !== ""
              ? (parent.parent.kind === "sub"
                  ? ("\u2193 " + parent.parent.secondary + "  " + parent.parent.primary)
                  : (parent.parent.secondary + " " + parent.parent.primary))
              : parent.parent.primary
            elide: Text.ElideLeft
            color: parent.parent.kind === "sub" ? root.dim : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: parent.parent.kind === "goal"
          }
        }

        // Minute gutter aligned directly under the score
        Text {
          id: minuteLabel
          x: Math.round(root.axisInBody - width / 2)
          anchors.verticalCenter: parent.verticalCenter
          width: root.eventGutter
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: modelData.minute || ""
          color: parent.kind === "goal" ? root.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Away side (left-aligned against the minute column)
        Row {
          visible: !parent.home
          anchors.left: minuteLabel.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)

          Item {
            width: Style.space(12)
            height: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              visible: parent.parent.parent.kind === "yellow" || parent.parent.parent.kind === "red"
              anchors.centerIn: parent
              width: Style.space(7)
              height: Style.space(10)
              radius: 1
              color: parent.parent.parent.kind === "red" ? "#eb5757" : "#f2c94c"
            }

            Text {
              visible: parent.parent.parent.kind === "goal" || parent.parent.parent.kind === "missed_pen"
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: parent.parent.parent.kind === "goal" ? "\uf1e3" : "\uf00d"
              color: parent.parent.parent.kind === "goal" ? root.accent : "#eb5757"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption - 1
            }

            Text {
              visible: parent.parent.parent.kind === "sub"
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "\u2191"
              color: "#4ade80"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(Style.space(40), root.awayEventWidth - Style.space(18)))
            horizontalAlignment: Text.AlignLeft
            textFormat: Text.PlainText
            text: parent.parent.secondary !== ""
              ? (parent.parent.kind === "sub"
                  ? (parent.parent.primary + "  \u2193 " + parent.parent.secondary)
                  : (parent.parent.primary + " " + parent.parent.secondary))
              : parent.parent.primary
            elide: Text.ElideRight
            color: parent.parent.kind === "sub" ? root.dim : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: parent.parent.kind === "goal"
          }
        }
      }
    }

    Rectangle {
      width: body.width
      height: 1
      visible: root.hasTimelineBlock && root.hasStats
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
    }

    Item {
      width: body.width
      height: Style.space(4)
      visible: root.hasTimelineBlock && root.hasStats
    }

    Text {
      width: body.width
      visible: !root.hasStats && !root.hasTimelineBlock
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
          anchors.right: statLabel.left
          anchors.rightMargin: Style.space(8)
          anchors.top: parent.top
          width: root.homeStatWidth
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
          id: statLabel
          x: Math.round(root.axisInBody - width / 2)
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
          anchors.left: statLabel.right
          anchors.leftMargin: Style.space(8)
          anchors.top: parent.top
          width: root.awayStatWidth
          textFormat: Text.PlainText
          text: Model.statValueLabel(root.statValue(root.match.away.id, modelData.key),
                                     modelData.suffix)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: parent.share < 0.5
        }

        // Meter centred directly under the stat label / match score.
        Item {
          x: Math.round(root.axisInBody - width / 2)
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

    // -------------------------------------------------------------- streams
    Rectangle {
      width: body.width
      height: 1
      visible: root.hasStream && (root.loadingStreams || root.streams.length > 0)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
    }

    Flow {
      width: body.width
      visible: root.hasStream && (root.loadingStreams || root.streams.length > 0)
      spacing: Style.space(6)
      topPadding: Style.space(4)

      Text {
        visible: root.loadingStreams && root.streams.length === 0
        textFormat: Text.PlainText
        text: "Loading streams…"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.streams

        Rectangle {
          required property var modelData
          width: Math.min(body.width, streamRow.implicitWidth + Style.space(14))
          height: Style.space(22)
          radius: Style.cornerRadius
          color: streamHover.containsMouse
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
            : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)

          Row {
            id: streamRow
            anchors.centerIn: parent
            spacing: Style.space(5)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "\uf04b"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption - 1
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, body.width - Style.space(32))
              textFormat: Text.PlainText
              text: modelData.name
              elide: Text.ElideRight
              color: streamHover.containsMouse ? root.foreground : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: streamHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.playStreamRequested(modelData.url)
          }
        }
      }
    }
  }
}
