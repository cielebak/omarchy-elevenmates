import QtQuick
import qs.Commons
import qs.Ui

// Competitions, followed clubs, bar mode, notifications, Stremio toggle, and
// refresh intervals.
Column {
  id: root

  property var bar: null
  property var hostWidget: null
  property var leagues: []
  property var favorites: []
  property var helper: []
  property string pluginDir: ""
  property bool stremioEnabled: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.4)
  property string fontFamily: Style.font.family

  signal settingChanged(string key, var value)
  signal demoGoalRequested()

  spacing: Style.spacing.rowGap

  MultiSelect {
    width: root.width
    label: "Competitions"
    values: root.leagues
    optionsCommand: root.helper.concat(["leagues"])
    optionsCommandCwd: root.pluginDir
    placeholderText: "Search competitions..."
    noSelectionText: "No competitions"
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onChanged: function (values) { root.settingChanged("leagues", values) }
  }

  MultiSelect {
    id: clubPicker
    width: root.width
    label: "Your clubs"
    values: root.favorites
    optionsCommand: root.helper.concat(["teams"])
    optionsCommandCwd: root.pluginDir
    placeholderText: "Search clubs..."
    noSelectionText: "No clubs picked"
    triggerLabel: clubPicker.loadingOptions ? "Loading clubs…" : ""
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onChanged: function (values) { root.settingChanged("favoriteTeams", values) }
  }

  Dropdown {
    width: root.width
    label: "What the bar shows"
    value: root.hostWidget ? root.hostWidget.barMode : "Auto"
    options: ["Auto", "Favorites only", "Any live match", "Picked match only"]
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onChanged: function (value) { root.settingChanged("barMode", value) }
  }

  Toggle {
    width: root.width
    label: "Notify on goals"
    description: "A desktop notification when the score changes or a match ends."
    checked: root.hostWidget ? root.hostWidget.goalNotifications : true
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.settingChanged(
      "goalNotifications",
      !(root.hostWidget && root.hostWidget.goalNotifications)
    )
  }

  Toggle {
    width: root.width
    visible: root.hostWidget ? root.hostWidget.goalNotifications : true
    label: "Notify for every match"
    description: "Off keeps the alerts to the clubs you follow."
    checked: root.hostWidget ? root.hostWidget.notifyAll : false
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.settingChanged(
      "notifyAll",
      !(root.hostWidget && root.hostWidget.notifyAll)
    )
  }

  Toggle {
    width: root.width
    label: "Stremio / MPV integration"
    description: "Show Stremio tab and ▶ buttons for live matches."
    checked: root.stremioEnabled
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.settingChanged("stremioEnabled", !root.stremioEnabled)
  }

  Item {
    width: root.width
    implicitHeight: testGoal.implicitHeight + Style.space(6)

    Text {
      id: testGoal
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "\uf1e3  Test the goal alert"
      color: testGoalHover.containsMouse ? Color.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.underline: testGoalHover.containsMouse
    }

    MouseArea {
      id: testGoalHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.demoGoalRequested()
    }
  }

  Text {
    width: root.width
    textFormat: Text.PlainText
    text: "Refresh while a match is live: " + Math.round(liveSlider.liveValue) + " s"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  PanelSlider {
    id: liveSlider
    width: root.width
    bar: root.bar
    minimum: root.hostWidget ? root.hostWidget.minLiveRefreshSec : 15
    maximum: 300
    step: 5
    integer: true
    value: root.hostWidget ? root.hostWidget.liveRefreshSec : 25
    onReleased: function (v) { root.settingChanged("liveRefreshSec", Math.round(v)) }
  }

  Text {
    width: root.width
    textFormat: Text.PlainText
    text: "Refresh when nothing is live: " + Math.round(idleSlider.liveValue) + " min"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  PanelSlider {
    id: idleSlider
    width: root.width
    bar: root.bar
    minimum: 1
    maximum: 180
    step: 1
    integer: true
    value: root.hostWidget ? root.hostWidget.idleRefreshMin : 12
    onReleased: function (v) { root.settingChanged("idleRefreshMin", Math.round(v)) }
  }

  Text {
    width: root.width
    textFormat: Text.PlainText
    text: "Scores come from ESPN's public scoreboard (and LiveScore for Ekstraklasa). No account, no key."
    wrapMode: Text.WordWrap
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
