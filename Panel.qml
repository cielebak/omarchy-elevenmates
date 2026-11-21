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
  moduleName: "elevenmates"
  ipcTarget: "elevenmates"
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

  // Local Stremio football bridge (`stremio-football-board.service`) that maps
  // live matches to playable HLS streams for one-click playback in MPV.
  readonly property bool stremioEnabled: hostWidget ? hostWidget.stremioEnabled : false
  readonly property string stremioPlayer: hostWidget ? hostWidget.stremioPlayer : "mpv"
  readonly property string streamApiBase: {
    var raw = (hostWidget && hostWidget.stremioUrl) ? String(hostWidget.stremioUrl).trim() : "http://127.0.0.1:7040"
    if (/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/i.test(raw)) return raw.replace(/\/$/, "")
    return "http://127.0.0.1:7040"
  }
  property var streamMatches: ({})
  property string streamMatchesStamp: ""
  property bool streamBridgeOnline: false
  property int streamBridgeCount: 0
  property string streamBridgeNotice: ""
  property string launchingMatchId: ""
  property var expandedStreams: []
  property string expandedStreamsStamp: ""
  property string expandedStreamsMatchId: ""
  property bool loadingExpandedStreams: false

  function validStreamUrl(u) {
    if (typeof u !== "string") return false
    var s = u.trim()
    return s.length > 0 && s.length < 2048 && /^https?:\/\//i.test(s)
  }

  function checkStreamBridge() {
    if (!root.stremioEnabled) return
    var xhr = new XMLHttpRequest()
    xhr.open("GET", root.streamApiBase + "/health")
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE || !root) return
      if (xhr.status === 200) {
        try {
          var parsed = JSON.parse(xhr.responseText)
          if (parsed && parsed.ok) {
            root.streamBridgeOnline = true
            root.streamBridgeCount = Number(parsed.matches || 0)
            root.streamBridgeNotice = String(parsed.notice || "").slice(0, 120)
            return
          }
        } catch (err) {}
      }
      root.streamBridgeOnline = false
      root.streamBridgeCount = 0
      root.streamBridgeNotice = ""
    }
    xhr.send()
  }

  function refreshStreamMatches() {
    if (!root.stremioEnabled) {
      root.streamMatches = ({})
      root.expandedStreams = []
      root.loadingExpandedStreams = false
      return
    }
    var list = root.matches || []
    if (list.length === 0) {
      root.streamMatches = ({})
      return
    }
    var payload = []
    for (var i = 0; i < list.length && payload.length < 200; i++) {
      var m = list[i]
      if (!m || !m.id || !m.home || !m.away) continue
      payload.push({
        id: String(m.id),
        home: String(m.home.name || ""),
        homeFull: String(m.home.fullName || ""),
        away: String(m.away.name || ""),
        awayFull: String(m.away.fullName || "")
      })
    }
    var xhr = new XMLHttpRequest()
    xhr.open("POST", root.streamApiBase + "/api/resolve")
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE || !root) return
      if (xhr.status === 200) {
        try {
          var parsed = JSON.parse(xhr.responseText)
          if (parsed && parsed.resolved) {
            root.streamBridgeOnline = true
            root.streamBridgeNotice = String(parsed.notice || "").slice(0, 120)
            var nextStamp = JSON.stringify(parsed.resolved)
            if (nextStamp !== root.streamMatchesStamp) {
              root.streamMatchesStamp = nextStamp
              root.streamMatches = parsed.resolved
            }
            if (root.expandedMatch !== "" && root.expandedStreamsMatchId !== root.expandedMatch) {
              root.fetchExpandedStreams(root.expandedMatch)
            }
            return
          }
        } catch (err) {}
      }
      root.streamBridgeOnline = false
      root.streamBridgeNotice = ""
      if (root.streamMatchesStamp !== "{}") {
        root.streamMatchesStamp = "{}"
        root.streamMatches = ({})
      }
    }
    xhr.send(JSON.stringify({ matches: payload }))
  }

  function fetchExpandedStreams(matchId) {
    if (!root.stremioEnabled || !matchId) {
      root.expandedStreams = []
      root.expandedStreamsStamp = ""
      root.expandedStreamsMatchId = ""
      root.loadingExpandedStreams = false
      return
    }
    var entry = root.streamMatches[matchId]
    if (!entry || !entry.streamMatchId) {
      root.expandedStreams = []
      root.expandedStreamsStamp = ""
      root.expandedStreamsMatchId = ""
      root.loadingExpandedStreams = false
      return
    }
    var switching = root.expandedStreamsMatchId !== matchId
    if (switching) {
      root.expandedStreams = []
      root.expandedStreamsStamp = ""
      root.loadingExpandedStreams = true
    }
    var requestedId = matchId
    var xhr = new XMLHttpRequest()
    xhr.open("GET", root.streamApiBase + "/api/streams/" + encodeURIComponent(entry.streamMatchId))
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE || !root) return
      if (root.expandedMatch !== requestedId) return
      root.loadingExpandedStreams = false
      if (xhr.status !== 200) return
      try {
        var parsed = JSON.parse(xhr.responseText)
        var list = parsed && parsed.streams ? parsed.streams : []
        var clean = []
        for (var i = 0; i < list.length && clean.length < 8; i++) {
          var s = list[i]
          if (!s || !root.validStreamUrl(s.url)) continue
          clean.push({
            name: String(s.name || "Stream").slice(0, 80),
            title: String(s.title || "").slice(0, 120),
            url: s.url.trim(),
            isBackup: s.isBackup === true
          })
        }
        root.expandedStreamsMatchId = requestedId
        var stamp = JSON.stringify(clean)
        if (stamp !== root.expandedStreamsStamp) {
          root.expandedStreamsStamp = stamp
          root.expandedStreams = clean
        }
      } catch (err) {}
    }
    xhr.send()
  }

  function launchMpvUrls(match, urls) {
    var safe = []
    for (var i = 0; i < urls.length; i++) {
      if (root.validStreamUrl(urls[i])) safe.push(urls[i].trim())
    }
    if (safe.length === 0) return
    var title = (match && match.home && match.away)
      ? (String(match.home.name || "") + " vs " + String(match.away.name || ""))
      : "Live Match"
    Util.execArgv(["mpv", "--force-window=immediate", "--title=" + title, "--"].concat(safe))
    root.close()
  }

  function playInMpv(match, specificUrl) {
    if (!root.stremioEnabled || !match || !match.id) return
    if (specificUrl && root.validStreamUrl(specificUrl)) {
      root.launchMpvUrls(match, [specificUrl])
      return
    }
    var entry = root.streamMatches[match.id]
    if (!entry || !entry.streamMatchId) return
    if (root.stremioPlayer === "stremio" && typeof entry.stremioUrl === "string"
        && /^stremio:\/\/\//i.test(entry.stremioUrl)) {
      Util.execArgv(["xdg-open", entry.stremioUrl])
      root.close()
      return
    }
    root.launchingMatchId = match.id
    var targetId = match.id
    var xhr = new XMLHttpRequest()
    xhr.open("GET", root.streamApiBase + "/api/streams/" + encodeURIComponent(entry.streamMatchId))
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE || !root) return
      if (root.launchingMatchId === targetId) root.launchingMatchId = ""
      if (xhr.status !== 200) return
      try {
        var parsed = JSON.parse(xhr.responseText)
        var list = parsed && parsed.streams ? parsed.streams : []
        var urls = []
        for (var i = 0; i < list.length && urls.length < 6; i++) {
          if (list[i] && root.validStreamUrl(list[i].url)) urls.push(list[i].url.trim())
        }
        if (urls.length > 0) root.launchMpvUrls(match, urls)
      } catch (err) {}
    }
    xhr.send()
  }

  onOpenedChanged: {
    if (opened && root.stremioEnabled) {
      root.refreshStreamMatches()
      if (root.tab === "stremio") root.checkStreamBridge()
    }
  }

  onMatchesChanged: {
    if (root.opened && root.stremioEnabled) root.refreshStreamMatches()
  }

  onStremioEnabledChanged: {
    if (root.stremioEnabled) {
      if (root.opened) root.refreshStreamMatches()
      root.checkStreamBridge()
    } else {
      if (root.tab === "stremio") root.tab = "settings"
      root.streamMatches = ({})
      root.streamMatchesStamp = ""
      root.streamBridgeOnline = false
      root.streamBridgeCount = 0
      root.streamBridgeNotice = ""
      root.expandedStreams = []
      root.expandedStreamsStamp = ""
      root.expandedStreamsMatchId = ""
      root.loadingExpandedStreams = false
    }
  }

  onExpandedMatchChanged: {
    root.fetchExpandedStreams(root.expandedMatch)
  }


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
  readonly property bool stremioOpen: tab === "stremio"
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
    contentWidth: panel.fittedContentWidth(Style.space(root.stremioEnabled ? 508 : 480))
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
                model: root.stremioEnabled
                  ? [
                      { key: "matches", label: "MATCHES" },
                      { key: "stremio", label: "STREMIO" },
                      { key: "settings", label: "SETTINGS" }
                    ]
                  : [
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

                  Row {
                    id: tabLabel
                    anchors.centerIn: parent
                    spacing: Style.space(5)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: parent.parent.modelData.label
                      color: parent.parent.current ? Color.accent : root.dim
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1.6
                    }

                    Rectangle {
                      visible: parent.parent.modelData.key === "stremio" && root.streamBridgeNotice !== ""
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(6)
                      height: width
                      radius: width / 2
                      color: "#eb5757"
                    }
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
                      if (root.tab === "stremio") root.checkStreamBridge()
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

          Rectangle {
            width: parent.width
            visible: root.tab === "matches" && root.stremioEnabled && root.streamBridgeNotice !== ""
            implicitHeight: noticeText.implicitHeight + Style.space(10)
            radius: Style.cornerRadius
            color: Qt.rgba(0.92, 0.34, 0.34, 0.14)

            Text {
              id: noticeText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              textFormat: Text.PlainText
              text: "Stremio: " + root.streamBridgeNotice
              elide: Text.ElideRight
              color: "#eb5757"
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.tab = "stremio"
                root.checkStreamBridge()
              }
            }
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
            text: root.stremioEnabled
              ? "Click a match for its numbers. Eye pins to bar, bell adds goal alerts, play opens in MPV."
              : "Click a match for its numbers. The eye picks the one the bar shows, the bell adds it to the goal alerts."
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
                  readonly property bool hasStream: Boolean(root.streamMatches && root.streamMatches[modelData.id])
                  readonly property bool launching: root.launchingMatchId === modelData.id
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
                        } else if (event.x < playSlot.x + playSlot.width) {
                          if (playSlot.visible) {
                            root.playInMpv(row.modelData, "")
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

                    Item {
                      id: playSlot
                      anchors.left: bellSlot.right
                      anchors.leftMargin: root.stremioEnabled ? Style.space(2) : 0
                      anchors.verticalCenter: parent.verticalCenter
                      width: root.stremioEnabled ? Style.space(24) : 0
                      height: eyeSlot.height
                      visible: root.stremioEnabled && !row.finished && row.hasStream

                      Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width
                        radius: Style.cornerRadius
                        visible: row.launching || rowHover.containsMouse
                        color: row.launching
                          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.30)
                          : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                      }

                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "\uf04b"
                        color: (row.launching || rowHover.containsMouse)
                          ? Color.accent
                          : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.72)
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      id: leagueTag
                      anchors.left: playSlot.right
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
                      streams: (root.stremioEnabled && row.expanded) ? root.expandedStreams : []
                      loadingStreams: root.stremioEnabled && row.expanded && root.loadingExpandedStreams
                      hasStream: root.stremioEnabled && !row.finished && row.hasStream
                      foreground: root.fg
                      dim: root.dim
                      accent: Color.accent
                      fontFamily: root.uiFont
                      // Same left edge and same right edge as the score field
                      // above, so the minute column lines up with the score.
                      indent: playSlot.x + playSlot.width + Style.space(6) + leagueTag.width
                      rightInset: clock.width + Style.space(8)
                      onPlayStreamRequested: function (streamUrl) {
                        root.playInMpv(row.modelData, streamUrl)
                      }
                    }
                  }
                }
              }
            }
          }

          // ------------------------------------------------------------ stremio
          Loader {
            width: column.width
            active: root.stremioEnabled && root.stremioOpen
            visible: active
            sourceComponent: StremioTab {
              width: column.width
              bar: root.bar
              foreground: root.fg
              dim: root.dim
              fontFamily: root.uiFont
              bridgeOnline: root.streamBridgeOnline
              bridgeCount: root.streamBridgeCount
              bridgeNotice: root.streamBridgeNotice
              bridgeBaseUrl: root.streamApiBase
              playerMode: root.stremioPlayer
              onSettingChanged: function (key, value) { root.put(key, value) }
            }
          }

          // The pickers each spawn a process as soon as they exist, so the
          // whole block stays unbuilt until the section is opened.
          Loader {
            width: column.width
            active: root.settingsOpen
            visible: active
            sourceComponent: SettingsTab {
              width: column.width
              bar: root.bar
              hostWidget: root.hostWidget
              leagues: root.leagues
              favorites: root.favorites
              helper: root.helper
              pluginDir: root.pluginDir
              stremioEnabled: root.stremioEnabled
              foreground: root.fg
              dim: root.dim
              fontFamily: root.uiFont
              onSettingChanged: function (key, value) { root.put(key, value) }
              onDemoGoalRequested: root.demoGoal()
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
