import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The popup behind the bar button: today's matches, then the pickers.
//
// Omarchy's manifest `schema` is metadata - this shell exposes it but has no
// surface that renders it - so the plugin draws its own controls. They are
// written to the plugin's own config file through the widget, not to the
// widget's shell.json entry; see the note in BarWidget.qml for why.
Panel {
  id: root
  moduleName: "jarek.elevenmates"
  ipcTarget: "jarek.elevenmates"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string uiFont: bar ? bar.fontFamily : Style.font.family

  readonly property var scores: hostWidget ? hostWidget.scores : ({})
  readonly property var matches: hostWidget ? hostWidget.matches : []
  readonly property var favorites: hostWidget ? hostWidget.favoriteTeams : []
  readonly property var leagues: hostWidget ? hostWidget.leagues : []
  readonly property string pluginDir: hostWidget ? hostWidget.pluginDir : ""
  readonly property var helper: hostWidget ? hostWidget.helper : []
  readonly property var sections: Model.sections(matches)
  readonly property string pinnedMatch: hostWidget ? hostWidget.pinnedMatch : ""
  readonly property string expandedMatch: hostWidget ? hostWidget.expandedMatch : ""
  readonly property var alertMatches: hostWidget ? hostWidget.alertMatches : []


  // The bar shows one match; goal alerts can cover as many as you like.
  function toggleAlert(id) {
    var next = []
    var found = false
    for (var i = 0; i < root.alertMatches.length; i++) {
      if (root.alertMatches[i] === id) { found = true; continue }
      next.push(root.alertMatches[i])
    }
    if (!found) next.push(id)
    root.put("alertMatches", next)
  }
  readonly property var stats: hostWidget ? hostWidget.stats : null
  readonly property string statePath: hostWidget ? hostWidget.statePath : ""

  // Waiting for a real goal is a poor way to check a colour, so the alert can
  // be fired on demand off whatever match is in the cache.
  function demoGoal() {
    if (root.helper.length === 0 || root.statePath === "") return
    demo.command = root.helper.concat(["demo-goal", "--out", root.statePath])
    demo.running = true
    root.close()
  }

  // Whether a side reads at full strength: the one that is ahead, or both
  // when the match is level or has not started.
  function leads(match, side) {
    if (match.state === "pre") return true
    var home = Number(match.home.score || 0)
    var away = Number(match.away.score || 0)
    if (home === away) return true
    return side.id === (home > away ? match.home.id : match.away.id)
  }

  function setExpanded(id, league) {
    if (hostWidget) hostWidget.expand(league, id)
  }

  // Which half of the card is showing. Two tabs rather than a line of text to
  // click at the bottom: that had to be found first, and it moved whenever the
  // list above it changed.
  property string tab: "matches"
  readonly property bool settingsOpen: tab === "settings"

  // Every setting goes through the widget, which writes the plugin's own
  // config file. Values are JSON, so a list stays a list.
  function put(key, value) {
    if (hostWidget) hostWidget.put(key, JSON.stringify(value))
  }

  Process {
    id: demo
    onExited: function (code) { if (hostWidget) hostWidget.reloadState() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      // A full Saturday across five leagues is a long list, and the settings
      // sit under it, so the card scrolls rather than growing off the screen.
      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: scroll.width - (scrollBar.visible ? Style.space(8) : 0)
          spacing: Style.spacing.rowGap

          // ------------------------------------------------------------ header
          Item {
            width: parent.width
            implicitHeight: Math.max(title.implicitHeight, refreshButton.height)

            Text {
              id: title
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.hostWidget && root.hostWidget.liveCount > 0
                ? "LIVE · " + root.hostWidget.liveCount
                : "TODAY"
              color: root.hostWidget && root.hostWidget.liveCount > 0 ? Color.accent : root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }

            Text {
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.hostWidget && root.hostWidget.refreshing
                ? "refreshing…"
                : Model.updatedLabel(root.scores.updatedAt, root.hostWidget ? root.hostWidget.nowMs : Date.now())
              color: root.dim
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              tooltipText: "Refresh now"
              foreground: root.fg
              hoverColor: Color.accent
              fontFamily: root.uiFont
              // Forced: a refresh asked for by hand must not be dropped by the
              // helper's fifteen-second skip window.
              onClicked: if (root.hostWidget) root.hostWidget.refresh(true)
            }
          }

          Item {
            width: parent.width
            implicitHeight: Style.spacing.controlHeight

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Repeater {
                model: [
                  { key: "matches", label: "MATCHES" },
                  { key: "settings", label: "SETTINGS" }
                ]

                Item {
                  required property var modelData
                  readonly property bool current: root.tab === modelData.key
                  width: tabLabel.implicitWidth + Style.space(20)
                  height: Style.spacing.controlHeight

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: parent.current
                      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                      : (tabHover.containsMouse
                          ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07)
                          : "transparent")
                  }

                  Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.modelData.label
                    color: parent.current ? Color.accent : root.dim
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.6
                  }

                  MouseArea {
                    id: tabHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.tab = parent.modelData.key
                      // The open card is destroyed with the list, so stop
                      // fetching its numbers too.
                      if (root.tab !== "matches") root.setExpanded("", "")
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.scores.error !== undefined && root.scores.error !== ""
            textFormat: Text.PlainText
            text: root.scores.error || ""
            wrapMode: Text.WordWrap
            color: Color.accent
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: root.tab === "matches" && root.matches.length === 0
            textFormat: Text.PlainText
            text: root.leagues.length === 0
              ? "No competitions picked yet. Open the SETTINGS tab."
              : "Nothing on today in the competitions you follow."
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: root.tab === "matches" && root.matches.length > 0
            textFormat: Text.PlainText
            text: "Click a match for its numbers. The eye picks the one the bar "
              + "shows, the bell adds it to the goal alerts."
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
          }

          // ----------------------------------------------------------- matches
          Repeater {
            model: root.tab === "matches" ? root.sections : []

            Column {
              id: section
              required property var modelData
              width: column.width
              spacing: Style.space(2)

              PanelSectionHeader {
                text: section.modelData.title
                foreground: section.modelData.title === "LIVE" ? Color.accent : root.fg
                fontFamily: root.uiFont
              }

              Repeater {
                model: section.modelData.matches

                Column {
                  id: row
                  required property var modelData
                  readonly property bool pinned: root.pinnedMatch === modelData.id
                  readonly property bool expanded: root.expandedMatch === modelData.id
                  readonly property bool alerted: root.alertMatches.indexOf(modelData.id) !== -1
                  // Nothing left to follow or be told about, so neither switch
                  // has any work to do - unless it is already on, in which case
                  // it stays until it is turned off, or the row would carry a
                  // setting with no way to clear it.
                  readonly property bool finished: Model.isFinished(modelData)
                  readonly property bool highlighted: modelData.favorite || pinned || Model.isLive(modelData)
                  width: section.width
                  spacing: 0

                  Item {
                    id: header
                    width: parent.width
                    implicitHeight: Style.spacing.controlHeight

                    // Clicking a match opens its numbers; clicking the eye on
                    // the left moves the bar onto it. Only one eye is ever on,
                    // because the bar carries one match.
                    //
                    // A flick of the list is a press and a release on some row,
                    // and taking that as a click used to move the bar to
                    // whatever was under the finger. Only a press and release
                    // in the same spot, with the list standing still, counts.
                    MouseArea {
                      id: rowHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      property point pressPoint: Qt.point(0, 0)
                      onPressed: function (event) { pressPoint = Qt.point(event.x, event.y) }
                      onClicked: function (event) {
                        if (scroll.moving || scroll.dragging) return
                        if (Math.abs(event.x - pressPoint.x) > Style.space(5)) return
                        if (Math.abs(event.y - pressPoint.y) > Style.space(5)) return
                        // A slot that is not showing its switch is not a
                        // target; the click belongs to the row underneath it.
                        if (event.x < eyeSlot.x + eyeSlot.width) {
                          if (eyeSlot.visible) {
                            root.put("pinnedMatch", row.pinned ? "" : row.modelData.id)
                            return
                          }
                        } else if (event.x < bellSlot.x + bellSlot.width) {
                          if (bellSlot.visible) {
                            root.toggleAlert(row.modelData.id)
                            return
                          }
                        }
                        root.setExpanded(row.expanded ? "" : row.modelData.id,
                                         row.modelData.league)
                      }
                    }

                    Rectangle {
                      anchors.fill: parent
                      anchors.leftMargin: -Style.space(6)
                      anchors.rightMargin: -Style.space(6)
                      radius: Style.cornerRadius
                      visible: row.pinned || row.expanded || rowHover.containsMouse
                      color: row.pinned
                        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.13)
                        : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                    }

                    // Both switches are the same square chip with the glyph
                    // centred in it, so the two sit on one rhythm and the lit
                    // state is a full square rather than a clipped edge.
                    Item {
                      id: eyeSlot
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(2)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(24)
                      height: Math.min(header.height - Style.space(4), width)
                      // A match that has been played cannot be followed into
                      // anything; the bar would only be holding a final score.
                      visible: !row.finished || row.pinned

                      Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width
                        radius: Style.cornerRadius
                        visible: row.pinned
                        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
                      }

                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "\uf06e"
                        color: row.pinned
                          ? Color.accent
                          : (rowHover.containsMouse
                              ? root.fg
                              : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18))
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Item {
                      id: bellSlot
                      anchors.left: eyeSlot.right
                      anchors.leftMargin: Style.space(2)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(24)
                      height: eyeSlot.height
                      // The match the bar is holding is already watched, so its
                      // bell would be a switch that changes nothing, and a match
                      // that is over has no goals left to announce. Hidden
                      // rather than removed: the slot keeps its width, so no row
                      // shifts sideways, and the bell's own state survives to
                      // come back when it is useful again.
                      visible: !row.pinned && (!row.finished || row.alerted)

                      Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width
                        radius: Style.cornerRadius
                        visible: row.alerted
                        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
                      }

                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "\uf0f3"
                        color: row.alerted
                          ? Color.accent
                          : (rowHover.containsMouse
                              ? root.fg
                              : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18))
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      id: leagueTag
                      anchors.left: bellSlot.right
                      anchors.leftMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: row.modelData.leagueName
                      elide: Text.ElideRight
                      width: Style.space(86)
                      color: root.dim
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                    }

                    // Home name, score and away name each own a column inside
                    // one field, so every score in the list sits on the same
                    // vertical line and the detail block can share it.
                    Item {
                      id: field
                      anchors.left: leagueTag.right
                      anchors.right: clock.left
                      anchors.rightMargin: Style.space(8)
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom

                      Text {
                        anchors.left: parent.left
                        anchors.right: score.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        textFormat: Text.PlainText
                        text: row.modelData.home.name
                        elide: Text.ElideRight
                        color: root.leads(row.modelData, row.modelData.home) ? root.fg : root.dim
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall
                        font.bold: row.highlighted
                      }

                      Text {
                        id: score
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(44)
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: Model.scoreLine(row.modelData)
                        color: row.highlighted ? Color.accent : root.fg
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }

                      Text {
                        anchors.left: score.right
                        anchors.leftMargin: Style.space(8)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: row.modelData.away.name
                        elide: Text.ElideRight
                        color: root.leads(row.modelData, row.modelData.away) ? root.fg : root.dim
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall
                        font.bold: row.highlighted
                      }
                    }

                    Text {
                      id: clock
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(52)
                      horizontalAlignment: Text.AlignRight
                      textFormat: Text.PlainText
                      text: Model.clockLabel(row.modelData)
                      // A break is still "live", but a full-strength accent
                      // makes it look like the clock is running.
                      color: Model.isBreak(row.modelData)
                        ? Qt.darker(Color.accent, 1.4)
                        : (Model.isLive(row.modelData) ? Color.accent : root.dim)
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // Scorers come with the scoreboard; the team numbers cost an
                  // extra request, so they are only fetched for the open match.
                  Loader {
                    width: row.width
                    active: row.expanded
                    visible: active
                    sourceComponent: MatchDetail {
                      match: row.modelData
                      stats: root.stats
                      foreground: root.fg
                      dim: root.dim
                      accent: Color.accent
                      fontFamily: root.uiFont
                      // Same left edge and same right edge as the score field
                      // above, so the minute column lines up with the score.
                      indent: bellSlot.x + bellSlot.width + Style.space(6) + leagueTag.width
                      rightInset: clock.width + Style.space(8)
                    }
                  }
                }
              }
            }
          }

          // The pickers each spawn a process as soon as they exist, so the
          // whole block stays unbuilt until the section is opened.
          Loader {
            width: column.width
            active: root.settingsOpen
            visible: active
            sourceComponent: Component {
              Column {
                width: parent.width
                spacing: Style.spacing.rowGap

                MultiSelect {
                  width: parent.width
                  label: "Competitions"
                  values: root.leagues
                  optionsCommand: root.helper.concat(["leagues"])
                  // MultiSelect assigns its cwd unconditionally, and an empty
                  // string stops the process from starting at all.
                  optionsCommandCwd: root.pluginDir
                  placeholderText: "Search competitions..."
                  noSelectionText: "No competitions"
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.uiFont
                  onChanged: function (values) { root.put("leagues", values) }
                }

                MultiSelect {
                  id: clubPicker
                  width: parent.width
                  label: "Your clubs"
                  values: root.favorites
                  // Teams come from the competitions that are actually
                  // followed, read from the config by the helper itself, so
                  // the list stays short and holds nothing that can never show
                  // up in the panel.
                  optionsCommand: root.helper.concat(["teams"])
                  optionsCommandCwd: root.pluginDir
                  placeholderText: "Search clubs..."
                  noSelectionText: "No clubs picked"
                  // Favourites are stored as ESPN team ids, and until the
                  // options have been fetched there is nothing to turn them
                  // into names with. A trigger reading "86, 359" looks like a
                  // bug rather than a wait.
                  triggerLabel: clubPicker.loadingOptions ? "Loading clubs…" : ""
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.uiFont
                  onChanged: function (values) { root.put("favoriteTeams", values) }
                }

                Dropdown {
                  width: parent.width
                  label: "What the bar shows"
                  value: root.hostWidget ? root.hostWidget.barMode : "Auto"
                  options: ["Auto", "Favorites only", "Any live match",
                            "Picked match only"]
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.uiFont
                  onChanged: function (value) { root.put("barMode", value) }
                }

                Toggle {
                  width: parent.width
                  label: "Notify on goals"
                  description: "A desktop notification when the score changes or a match ends."
                  checked: root.hostWidget ? root.hostWidget.goalNotifications : true
                  foreground: root.fg
                  fontFamily: root.uiFont
                  onClicked: root.put("goalNotifications",
                    !(root.hostWidget && root.hostWidget.goalNotifications))
                }

                Toggle {
                  width: parent.width
                  visible: root.hostWidget ? root.hostWidget.goalNotifications : true
                  label: "Notify for every match"
                  description: "Off keeps the alerts to the clubs you follow."
                  checked: root.hostWidget ? root.hostWidget.notifyAll : false
                  foreground: root.fg
                  fontFamily: root.uiFont
                  onClicked: root.put("notifyAll", !(root.hostWidget && root.hostWidget.notifyAll))
                }

                Item {
                  width: parent.width
                  implicitHeight: testGoal.implicitHeight + Style.space(6)

                  Text {
                    id: testGoal
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "\uf1e3  Test the goal alert"
                    color: testGoalHover.containsMouse ? Color.accent : root.fg
                    font.family: root.uiFont
                    font.pixelSize: Style.font.bodySmall
                    font.underline: testGoalHover.containsMouse
                  }

                  MouseArea {
                    id: testGoalHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.demoGoal()
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Refresh while a match is live: "
                    + Math.round(liveSlider.liveValue) + " s"
                  color: root.dim
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                }

                PanelSlider {
                  id: liveSlider
                  width: parent.width
                  bar: root.bar
                  // Each competition is a request, so the floor rises with the
                  // list: twenty seconds for a couple of leagues, two minutes
                  // for the whole picker.
                  minimum: root.hostWidget ? root.hostWidget.minLiveRefreshSec : 20
                  maximum: 300
                  step: 10
                  integer: true
                  value: root.hostWidget ? root.hostWidget.liveRefreshSec : 60
                  onReleased: function (v) { root.put("liveRefreshSec", Math.round(v)) }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Refresh when nothing is live: "
                    + Math.round(idleSlider.liveValue) + " min"
                  color: root.dim
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                }

                PanelSlider {
                  id: idleSlider
                  width: parent.width
                  bar: root.bar
                  minimum: 1
                  maximum: 180
                  step: 1
                  integer: true
                  value: root.hostWidget ? root.hostWidget.idleRefreshMin : 20
                  onReleased: function (v) { root.put("idleRefreshMin", Math.round(v)) }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Scores come from ESPN's public scoreboard, one request per "
                    + "competition. No account, no key."
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }

      // Flickable draws no indicator of its own, and a panel that scrolls
      // without saying so reads as a panel that is missing rows.
      Rectangle {
        id: scrollBar
        anchors.right: parent.right
        width: Style.space(3)
        radius: width / 2
        visible: scroll.contentHeight > scroll.height + 1
        y: scroll.visibleArea.yPosition * scroll.height
        height: Math.max(Style.space(24), scroll.visibleArea.heightRatio * scroll.height)
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
      }
    }
  }
}
