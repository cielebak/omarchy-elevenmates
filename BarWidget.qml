import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar entry. Owns the refresh loop and the cache file; the panel is a
// passive view that gets the parsed state injected into it.
BarWidget {
  id: root
  moduleName: "elevenmates"

  readonly property string home: Quickshell.env("HOME") || ""
  // Derived from where this file actually is, so a clone under another name,
  // or a development symlink, still finds its own helper.
  readonly property string pluginDir: {
    var here = Qt.resolvedUrl(".").toString()
    if (here.indexOf("file://") === 0) here = here.substring(7)
    return here.replace(/\/$/, "")
  }
  // Spelled out rather than run through the script's own shebang: Quickshell
  // starts processes with a bare environment, so `/usr/bin/env python3` finds
  // no PATH and the process fails to start.
  readonly property var helper: ["/usr/bin/python3", pluginDir + "/bin/elevenmates"]
  readonly property string stateDir: home + "/.local/state/omarchy/elevenmates"
  readonly property string statePath: stateDir + "/state.json"

  // Settings live in the plugin's own file, not in the widget's shell.json
  // entry: `omarchy bar set` sends the value over an IPC call that flattens a
  // JSON array into separate arguments, so a list of competitions came back as
  // a bare string - or was rejected outright. Writing here also means a pin no
  // longer rewrites shell.json and reloads the whole bar.
  readonly property string configPath: home + "/.config/omarchy/elevenmates.json"
  property var config: ({})
  property string configStamp: ""

  function asList(value, fallback) {
    // The helper accepts a comma-separated string as well, and someone editing
    // the config by hand will write one sooner or later.
    if (typeof value === "string") {
      var parts = value.split(",")
      var trimmed = []
      for (var p = 0; p < parts.length; p++) {
        var piece = parts[p].replace(/^\s+|\s+$/g, "")
        if (piece !== "") trimmed.push(piece)
      }
      return trimmed.length > 0 ? trimmed : fallback
    }
    if (!value || typeof value.length !== "number") return fallback
    var out = []
    for (var i = 0; i < value.length; i++) out.push(String(value[i]))
    return out
  }

  function conf(key, fallback) {
    var value = config ? config[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property var leagues: asList(conf("leagues", null), [])
  readonly property var favoriteTeams: asList(conf("favoriteTeams", null), [])
  readonly property var alertMatches: asList(conf("alertMatches", null), [])
  readonly property string pinnedMatch: String(conf("pinnedMatch", ""))
  readonly property string barMode: String(conf("barMode", "Auto"))
  readonly property bool goalNotifications: conf("goalNotifications", true) !== false
  readonly property bool notifyAll: conf("notifyAll", false) === true
  // Every competition is its own request, so the shortest sensible interval is
  // not a constant: twenty seconds is polite for a couple of leagues and forty
  // requests a minute to ESPN for the whole picker list. Two seconds apiece
  // keeps the sweep near one request every two seconds whatever is followed.
  readonly property int minLiveRefreshSec:
    Math.max(20, Math.min(120, root.leagues.length * 2))
  readonly property int liveRefreshSec:
    Math.max(root.minLiveRefreshSec, Number(conf("liveRefreshSec", 60)) || 60)
  readonly property int idleRefreshMin: Math.max(1, Number(conf("idleRefreshMin", 20)) || 20)

  // Only a change to what is fetched is worth a round trip; pinning and the
  // display options are read straight off the cache already in hand.
  readonly property string fetchSignature: leagues.join(",") + "|" + favoriteTeams.join(",")
  // Forced, because the helper skips a sweep that another monitor ran in the
  // last fifteen seconds - and a competition just added would then sit out the
  // whole idle interval before appearing.
  onFetchSignatureChanged: refresh(true)

  // Writes are queued rather than dropped: a Process that is already running
  // ignores a new command, and two quick clicks would lose the second one.
  property var writeQueue: []

  function put(key, jsonValue) {
    // The file is the truth, but it is a process away. Until it answers, act
    // on the value just written, or a second click computed from the stale
    // config would undo the first.
    try {
      var merged = {}
      for (var name in root.config) merged[name] = root.config[name]
      merged[key] = JSON.parse(String(jsonValue))
      root.config = merged
    } catch (error) {}

    var argv = root.helper.concat(["config", "set", key, String(jsonValue)])
    if (writer.running) {
      var queue = root.writeQueue.slice()
      queue.push(argv)
      root.writeQueue = queue
      return
    }
    writer.command = argv
    writer.running = true
  }

  property var scores: ({ updatedAt: 0, matches: [], liveCount: 0, error: "", statsByMatch: {} })
  property string scoresStamp: ""
  // The goal the bar is celebrating right now, and the last one it has already
  // seen. seenGoalSeq starts negative so the first cache read after login does
  // not replay whatever happened while the machine was off.
  property var goalFlash: null
  property int seenGoalSeq: -1
  property double seenGoalAt: 0
  // Goals found in one sweep that have not had their turn on the bar yet. Two
  // can easily land inside one refresh interval, and celebrating only the
  // later one threw the first away.
  property var goalPending: []

  // The celebration: the ball rolls to the right while the scorer scrolls
  // through the same slot the score normally occupies. Spin only ever
  // increases by whole turns, so it never snaps back when the flash ends.
  // seenGoalAt, not seenGoalSeq, is what decides whether a goal is news.
  property real ballSpin: 0
  // Where the ball is, in pixels across the widget. It leaves past the right
  // edge and comes back in from the left, which is what rolling looks like;
  // rolling out and then reversing looks like a mistake.
  property real ballX: 0
  property real labelX: 0
  property real labelFade: 1

  // The match whose statistics the panel has open. Deliberately not a setting:
  // it changes with every click and has no business churning shell.json.
  property string expandedMatch: ""
  property string expandedLeague: ""
  property bool refreshing: false
  property var refreshQueued: false
  // Ticks once a second only while something is live, so "67'" and the
  // "updated 20s ago" line do not sit frozen between fetches.
  property double nowMs: Date.now()

  // With no competitions picked there is nothing to show, whatever the cache
  // still holds from a moment ago. Guaranteed here rather than waiting for the
  // refresh that empties the file.
  readonly property var matches: leagues.length === 0 ? [] : (scores.matches || [])
  // Kept per match rather than in one slot: the widget exists once per monitor
  // and the two can have different cards open.
  readonly property var stats: (expandedMatch !== "" && scores.statsByMatch)
    ? (scores.statsByMatch[expandedMatch] || null) : null
  readonly property int liveCount: matches.length === 0 ? 0 : (scores.liveCount || 0)
  readonly property var headline: Model.headlineMatch(matches, favoriteTeams, barMode, nowMs, pinnedMatch)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = widget
    if ("hostWidget" in target) target.hostWidget = root
  }

  function expand(league, id) {
    root.expandedLeague = id === "" ? "" : league
    root.expandedMatch = id
    // Collapsing needs no data, and neither does reopening a card whose
    // numbers are already in the cache.
    if (id === "") return
    if (root.scores.statsByMatch && root.scores.statsByMatch[id]) return
    root.refresh()
  }

  function refresh(force) {
    // An expand or a settings change while a fetch is in flight would
    // otherwise wait out the whole interval for its numbers.
    if (root.refreshing) {
      root.refreshQueued = force === true ? "force" : true
      return
    }
    root.refreshing = true
    var argv = root.helper.concat(["fetch", "--out", root.statePath])
    if (force === true) argv.push("--force")
    if (root.headline && root.headline.id) argv.push("--headline", root.headline.id)
    if (root.expandedMatch !== "" && root.expandedLeague !== "") {
      argv.push("--stats", root.expandedLeague + ":" + root.expandedMatch)
    }
    fetchProcess.command = argv
    fetchProcess.running = true
    fetchWatchdog.restart()
  }

  // Whether a goal is news is decided by when it happened, not by the counter
  // in the cache file. That counter restarts from one whenever the file is
  // deleted rather than rewritten, and comparing against the old high-water
  // mark then swallowed real goals - which is exactly what it did.
  function noteGoals(feed) {
    if (!feed) return
    // An older cache carries a single goal rather than a feed of them.
    var list = (typeof feed.length === "number") ? feed : [feed]

    var fresh = []
    for (var i = 0; i < list.length; i++) {
      var goal = list[i]
      if (!goal) continue
      var at = Number(goal.at) * 1000
      var seq = Number(goal.seq)
      if (!isFinite(at) || at <= 0) continue
      var known = at < root.seenGoalAt
        || (at === root.seenGoalAt && isFinite(seq) && seq <= root.seenGoalSeq)
      if (known) continue
      fresh.push(goal)
    }
    if (fresh.length === 0) return

    fresh.sort(function (a, b) {
      return (Number(a.at) - Number(b.at)) || (Number(a.seq) - Number(b.seq))
    })

    var first = root.seenGoalAt === 0
    var newest = fresh[fresh.length - 1]
    root.seenGoalAt = Number(newest.at) * 1000
    root.seenGoalSeq = isFinite(Number(newest.seq)) ? Number(newest.seq) : 0

    // The first cache read after a restart carries whatever the day already
    // held; replay only what is still fresh enough to be worth announcing.
    if (first) {
      var recent = []
      for (var j = 0; j < fresh.length; j++) {
        if (Date.now() - Number(fresh[j].at) * 1000 <= 120000) recent.push(fresh[j])
      }
      fresh = recent
      if (fresh.length === 0) return
    }

    root.goalPending = root.goalPending.concat(fresh)
    // One is on the bar already; it will call for the next when its turn ends.
    if (!root.goalFlash) root.showNextGoal()
  }

  // Hand the bar the goal at the head of the queue, or give the slot back to
  // the score when there is nothing waiting.
  function showNextGoal() {
    if (root.goalPending.length === 0) {
      if (root.goalFlash) goalOutro.restart()
      return
    }
    var queue = root.goalPending.slice()
    var goal = queue.shift()
    root.goalPending = queue

    root.goalFlash = goal
    root.flashColor = root.goalColor
    rollOut.to = root.ballSpin + 1080
    goalOutro.stop()
    // A goal on its own is read at leisure; a queue behind it is not, or three
    // goals would hold the bar for the better part of a minute.
    goalHold.interval = queue.length > 0 ? 6000 : 14000
    goalHold.restart()
    goalAnim.restart()

    // A goal arriving while the previous one is still up would otherwise keep
    // the letters that have already finished popping and the scroll position
    // of a line that no longer exists.
    root.labelX = 0
    // Torn down and put back, which is what re-pops the letters. The binding
    // has to be handed back afterwards: assigning `active` outright replaces
    // it, and the line then had no way of ever switching itself off again -
    // "GOAL" simply stayed on the bar over the score.
    goalLine.active = false
    goalLine.active = Qt.binding(function () { return root.goalFlash !== null })
    marquee.restart()
  }

  function forceRefresh() { root.refresh(true) }
  function reloadState() { stateFile.reload() }

  // The popup is built the first time it is asked for. Loader is synchronous,
  // so the item exists by the time the next line runs.
  function ensurePanel() {
    if (!panelLoader.active) panelLoader.active = true
    return panelLoader.item
  }

  function open() { var p = ensurePanel(); if (p) p.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }

  // Closing the popup gives back everything it was holding: the delegates it
  // rebuilds on every cache write, and the extra request its open match costs.
  onOpenedChanged: {
    if (opened) return
    root.expandedMatch = ""
    root.expandedLeague = ""
    releasePanel.restart()
  }

  Timer {
    id: releasePanel
    interval: 800
    repeat: false
    onTriggered: if (!root.opened) panelLoader.active = false
  }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function toggle() { var p = ensurePanel(); if (p) p.toggle() }

  readonly property string barText: goalFlash
    ? Model.goalLabel(goalFlash)
    : Model.barLabel(headline)

  // The bar is a fixed row of widgets: growing to fit a goal line would shove
  // everything beside it sideways for fourteen seconds, and on a full bar
  // there may be nowhere to grow into. So the slot keeps the width of the
  // score, and anything longer scrolls through it.
  readonly property int scoreWidth: Math.ceil(scoreMetrics.width)
  readonly property int goalWidth: Math.ceil(goalMetrics.width)

  // Measured once off a representative line rather than off the current one,
  // so the slot keeps the same width whether the clock reads 9' or 45'+2',
  // whether the score is 0-0 or 10-0, and whether a goal is being announced.
  // A slot that resizes shoves every widget beside it.
  // Nothing to say, no room taken: with no match on the bar the slot collapses
  // to the ball alone rather than leaving a score-wide hole in the row.
  readonly property int windowWidth:
    (matches.length === 0 || (!headline && !goalFlash))
      ? 0 : Math.ceil(slotMetrics.width)
  // The geometry of the one button: a slot for the ball, a gap, the line.
  readonly property int edgePad: Style.space(5)
  readonly property int ballSlot: Math.round(Style.font.icon * 1.25)
  readonly property int unitWidth: root.edgePad * 2 + root.ballSlot
    + (windowWidth > 0 ? Style.space(7) + windowWidth : 0)
  readonly property int ballHome: root.edgePad
  readonly property bool marqueeNeeded: goalFlash !== null && goalWidth > windowWidth
  readonly property int marqueeDuration:
    Math.round((windowWidth + goalWidth) * 1000 / Style.space(70))
  implicitWidth: unitWidth
  implicitHeight: widget.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Component.onCompleted: {
    root.ballX = root.ballHome
    injectPanel()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var raw = text()
        if (raw === root.configStamp) return
        var parsed = JSON.parse(raw)
        if (parsed && typeof parsed === "object") {
          root.configStamp = raw
          root.config = parsed
        }
      } catch (error) {}
    }
  }

  Process {
    id: writer
    // The config file is replaced, not rewritten in place, so the inotify
    // watch on the old inode never fires. Read it back by hand.
    onExited: function (code) {
      configFile.reload()
      if (root.writeQueue.length > 0) {
        var queue = root.writeQueue.slice()
        var next = queue.shift()
        root.writeQueue = queue
        writer.command = next
        writer.running = true
      }
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        // Cheapest check first: the sweep re-reads this file every few seconds
        // and it usually has not moved, so do not parse 17 KB to find that out.
        var raw = text()
        if (raw === root.scoresStamp) return
        root.scoresStamp = raw

        var parsed = JSON.parse(raw)
        if (!parsed || typeof parsed !== "object") return

        // The sweep re-reads this file every few seconds whether or not it
        // moved. Replacing `scores` with an identical object would still
        // invalidate every binding downstream and rebuild the whole match
        // list, losing hover and scroll position with it.
        root.scores = parsed
        root.nowMs = Date.now()
        root.noteGoals(parsed.goalFeed || parsed.lastGoal)
        root.armKickoffTimer()
        root.injectPanel()
      } catch (error) {}
    }
  }

  Process {
    id: fetchProcess
    onExited: function (code) {
      root.refreshing = false
      fetchWatchdog.stop()
      stateFile.reload()
      // The reload above only reaches noteGoals when the file actually moved,
      // and the next kick-off has to be aimed at either way.
      root.armKickoffTimer()
      if (root.refreshQueued) {
        var wasForced = root.refreshQueued === "force"
        root.refreshQueued = false
        root.refresh(wasForced)
      }
    }
  }

  // Between 01:00 and 07:00 local. Flipped from the sweep rather than
  // computed in the binding below, so the interval changes twice a day instead
  // of on every evaluation - a Timer restarts its countdown whenever its
  // interval is assigned, and one that is reassigned every few seconds never
  // fires at all.
  property bool quietHours: false

  // The ceiling on the stretch below. The helper's staleness guard has to
  // clear this, or a quiet night would be mistaken for a suspend and the first
  // goals after it would never be announced; IDLE_STRETCH_CAP in
  // bin/elevenmates is the same number on the other side.
  readonly property int idleStretchCapMs: 45 * 60 * 1000

  readonly property int refreshIntervalMs: {
    if (root.liveCount > 0) return root.liveRefreshSec * 1000
    var base = root.idleRefreshMin * 60 * 1000
    // Nothing at all on today's card: no score can move, and the only thing a
    // sweep can turn up is a fixture that is still hours away. Overnight there
    // is not even that until the next day's list is published.
    if (root.matches.length === 0) {
      return Math.min(base * (root.quietHours ? 6 : 3), root.idleStretchCapMs)
    }
    return base
  }

  // A fixture about to start is the one thing the idle interval cannot handle
  // on its own: the widget learns a match is live only by sweeping, so a
  // kick-off a minute after a sweep went unseen for the whole interval and its
  // first goals arrived twenty minutes late, all at once. This is a single
  // shot aimed at the whistle, re-armed after every sweep.
  function armKickoffTimer() {
    kickoffTimer.stop()
    var away = Model.msToNextKickoff(root.matches, Date.now())
    if (away < 0) return
    // A little after the hour: the scoreboard takes a moment to turn the
    // fixture over, and arriving early only costs a second sweep.
    kickoffTimer.interval = Math.max(5000, Math.min(away + 20000, 6 * 60 * 60 * 1000))
    kickoffTimer.start()
  }

  Timer {
    id: kickoffTimer
    repeat: false
    running: false
    onTriggered: {
      // Still not due - the timer was capped rather than aimed. Aim again
      // rather than spending a request on a match that has not started.
      if (Model.msToNextKickoff(root.matches, Date.now()) > 60000) {
        root.armKickoffTimer()
        return
      }
      root.refresh()
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalMs
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // The celebration: a short blink of the whole widget, then the goal line
  // holds the bar for a few seconds before the score takes it back.
  Timer {
    id: goalHold
    interval: 14000
    repeat: false
    onTriggered: root.showNextGoal()
  }

  SequentialAnimation {
    id: goalAnim
    onStopped: root.opacity = 1

    ParallelAnimation {
      NumberAnimation {
        id: rollOut
        target: root; property: "ballSpin"
        duration: 1580; easing.type: Easing.Linear
      }
      SequentialAnimation {
        // Off the right edge...
        NumberAnimation {
          target: root; property: "ballX"
          to: root.unitWidth
          duration: 720; easing.type: Easing.InQuad
        }
        // ...round the back...
        PropertyAction { target: root; property: "ballX"; value: -root.ballSlot }
        // ...and in again from the left, settling into its slot.
        NumberAnimation {
          target: root; property: "ballX"
          to: root.ballHome
          duration: 860; easing.type: Easing.OutQuad
        }
      }
      NumberAnimation {
        target: root; property: "labelFade"
        from: 0; to: 1; duration: 420
      }
    }

    SequentialAnimation {
      loops: 3
      ParallelAnimation {
        ColorAnimation { target: root; property: "flashColor"; to: Color.accent; duration: 240 }
        // Not far enough to read as the widget disappearing - a pulse, not a
        // gap in the bar.
        NumberAnimation { target: root; property: "opacity"; to: 0.55; duration: 240; easing.type: Easing.InOutQuad }
      }
      ParallelAnimation {
        ColorAnimation { target: root; property: "flashColor"; to: root.goalColor; duration: 300 }
        NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: 300; easing.type: Easing.OutQuad }
      }
    }
  }

  // The way back: the ball rolls home, turning the other way, and only then is
  // the goal let go - otherwise the line would snap back under it.
  SequentialAnimation {
    id: goalOutro

    NumberAnimation { target: root; property: "labelFade"; to: 0; duration: 380 }

    ScriptAction {
      script: {
        root.goalFlash = null
        root.opacity = 1
        root.labelX = 0
        root.labelFade = 1
        root.ballX = root.ballHome
      }
    }
  }

  // Both files are replaced rather than rewritten, so their inotify watches
  // never fire. A write made through the widget reloads the file it touched
  // straight away; this sweep is what catches everything else - the other
  // monitor's refresh, and anything written from a terminal.
  // The helper has its own deadline, but a process that fails to start, or is
  // stopped, never reports an exit - and `refreshing` is only cleared there.
  // Without this the widget would stop fetching for the life of the shell.
  Timer {
    id: fetchWatchdog
    interval: 60000
    repeat: false
    onTriggered: {
      if (!root.refreshing) return
      fetchProcess.running = false
      root.refreshing = false
    }
  }

  Timer {
    id: sweep
    // Five seconds is for catching the other monitor's refresh while something
    // is running or the panel is open. With nothing live and the panel shut
    // the file only moves once an idle interval, and reading it twelve times a
    // minute through the night buys nothing.
    interval: (root.liveCount > 0 || root.opened) ? 5000 : 30000
    running: true
    repeat: true
    onTriggered: {
      var hour = new Date().getHours()
      root.quietHours = hour >= 1 && hour < 7
      configFile.reload()
      stateFile.reload()
    }
  }

  Timer {
    id: clockTimer
    interval: 1000
    // Nothing on the bar moves between fetches - the minute comes from the
    // cache. Only the panel's "updated Ns ago" line needs a second hand.
    running: root.liveCount > 0 && root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Loader {
    id: panelLoader
    active: false
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "elevenmates"

    function refresh(): void { root.broadcast("forceRefresh") }
    function expand(league: string, id: string): void { root.expand(league, id) }
    function settings(): void {
      var p = root.ensurePanel()
      if (p) { p.tab = "settings"; p.open() }
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // While a goal is on the bar the widget wears the scoring club's own colour,
  // pulsed against the accent. Club colours are picked for shirts, not for a
  // dark bar, so a dark one is lifted until it can be read.
  readonly property color goalColor: goalFlash
    ? Model.readableColor(goalFlash.teamColor, Color.accent, Color.bar.background)
    : Color.accent
  property color flashColor: Color.accent

  // A live match one of his clubs is in is the only thing that earns the
  // accent colour; everything else stays bar-coloured so the bar stays calm.
  readonly property color tint: {
    if (goalFlash) return flashColor
    if (opened) return Color.accent
    if (headline && headline.favorite && Model.isLive(headline)) return Color.accent
    return bar ? bar.barForeground : Color.foreground
  }

  // Icon and line are one button, not two items that happen to sit together:
  // one hover, one tooltip, one click target, one slot in the bar.
  WidgetButton {
    id: widget
    bar: root.bar
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.unitWidth
    // So the ball actually disappears at the edge instead of scribbling over
    // whatever widget sits next to it.
    clip: true

    tooltipText: {
      if (root.goalFlash) {
        return root.goalFlash.league + "  ·  " + root.goalFlash.home + " "
          + root.goalFlash.score + " " + root.goalFlash.away + "  ·  "
          + root.goalFlash.teamName + ", " + root.goalFlash.headline
      }
      if (root.scores.error && root.matches.length === 0) return "Elevenmates: " + root.scores.error
      if (root.headline) return Model.matchTooltip(root.headline)
      if (root.liveCount > 0) return "Elevenmates: " + root.liveCount + " live"
      return "Elevenmates: nothing live"
    }

    onPressed: function (pressedButton) {
      if (pressedButton === Qt.MiddleButton) root.refresh(true)
      else root.toggle()
    }

    // The slot the line lives in. It never changes width, so a goal cannot
    // shove the rest of the bar sideways; a line too long for it scrolls.
    Item {
      id: labelWindow
      visible: root.windowWidth > 0
      x: root.edgePad + root.ballSlot + Style.space(7)
      anchors.verticalCenter: parent.verticalCenter
      width: root.windowWidth
      height: Math.ceil(Style.font.body * 2.2)
      clip: root.goalFlash !== null

      Text {
        id: scoreLabel
        visible: !root.goalFlash
        x: root.labelX
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.barLabel(root.headline)
        color: root.tint
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: root.headline ? Model.isLive(root.headline) : false
      }

      // Torn down and rebuilt for every goal - see showNextGoal - which is
      // what makes the letters pop again each time one goes in. It needs the
      // id to be torn down by name; without it every goal threw a reference
      // error halfway through, and the rebuild never happened.
      Loader {
        id: goalLine
        active: root.goalFlash !== null
        x: root.labelX
        anchors.verticalCenter: parent.verticalCenter

        sourceComponent: Row {
          spacing: 0

          Repeater {
            model: ["G", "O", "A", "L"]

            Text {
              required property int index
              required property string modelData
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData
              color: root.tint
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              transformOrigin: Item.Center

              // One letter at a time, overshooting and settling: the way an
              // arcade cabinet announces something.
              SequentialAnimation on scale {
                running: true
                PauseAnimation { duration: 60 + index * 105 }
                NumberAnimation { to: 1.75; duration: 130; easing.type: Easing.OutBack }
                NumberAnimation { to: 1.0; duration: 260; easing.type: Easing.OutBounce }
              }

              SequentialAnimation on opacity {
                running: true
                PropertyAction { value: 0.2 }
                PauseAnimation { duration: 60 + index * 105 }
                NumberAnimation { to: 1.0; duration: 120 }
              }
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.goalFlash ? Model.goalRest(root.goalFlash) : ""
            color: root.tint
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            opacity: root.labelFade
          }
        }
      }
    }

    // Declared after the window so it rolls over the line rather than under it.
    //
    // The glyph does not sit in the middle of its own text box - it hangs off
    // the baseline like a letter does - so spinning the Text made the ball
    // orbit instead of turning on the spot. The box is squared off and the
    // glyph nudged until its ink is centred, and that box is what rotates.
    Item {
      id: ballBox
      x: root.ballX
      anchors.verticalCenter: parent.verticalCenter
      width: root.ballSlot
      height: root.ballSlot
      rotation: root.ballSpin
      transformOrigin: Item.Center

      Text {
        id: ballText
        anchors.horizontalCenter: parent.horizontalCenter
        // tightBoundingRect is measured from the baseline, so the ink centre
        // within the text box is ascent + rect.y + rect.height / 2.
        y: Math.round(parent.height / 2 - (ballFont.ascent
          + ballMetrics.tightBoundingRect.y
          + ballMetrics.tightBoundingRect.height / 2))
        textFormat: Text.PlainText
        text: "\uf1e3"
        color: root.tint
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }
    }
  }

  FontMetrics {
    id: ballFont
    font: ballText.font
  }

  TextMetrics {
    id: ballMetrics
    font: ballText.font
    text: "\uf1e3"
  }

  TextMetrics {
    id: slotMetrics
    font: scoreMetrics.font
    text: "MNC 0-0 SUN 45'+2'"
  }

  TextMetrics {
    id: scoreMetrics
    font: scoreLabel.font
    text: Model.barLabel(root.headline)
  }

  TextMetrics {
    id: goalMetrics
    font.family: scoreLabel.font.family
    font.pixelSize: scoreLabel.font.pixelSize
    font.bold: true
    text: root.goalFlash ? Model.goalLabel(root.goalFlash) : ""
  }

  // Runs only while a goal is holding the slot and the line is too long for
  // it; a short one simply sits there and is read in one go.
  SequentialAnimation {
    id: marquee
    running: root.marqueeNeeded
    loops: Animation.Infinite
    onStopped: root.labelX = 0

    PauseAnimation { duration: 1400 }
    NumberAnimation {
      target: root; property: "labelX"
      from: 0; to: -root.goalWidth - Style.space(14)
      duration: root.marqueeDuration; easing.type: Easing.Linear
    }
    PropertyAction { target: root; property: "labelX"; value: root.windowWidth }
    NumberAnimation {
      target: root; property: "labelX"
      to: 0
      duration: Math.max(200, Math.round(root.windowWidth * 1000 / Style.space(70)))
      easing.type: Easing.Linear
    }
  }
}
