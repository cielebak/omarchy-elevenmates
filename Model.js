.pragma library

// Presentation helpers shared by the bar button and the panel. Everything here
// takes the match objects written by bin/elevenmates and returns strings; no
// QML types, no side effects.

// In step with RECENT_MATCH_AGE in bin/elevenmates: the helper keeps a
// finished match on today's card for five hours, and the bar used to stop
// offering it after three, so a late kick-off vanished from the button while
// it was still sitting in the panel.
var FINISHED_GRACE_MS = 5 * 60 * 60 * 1000

function isLive(match) {
  return match && match.state === "in"
}

function isFinished(match) {
  return match && match.state === "post"
}

function isUpcoming(match) {
  return match && match.state === "pre"
}

// A match that never started has no score. ESPN reports 0-0 for both a
// fixture still to come and one that was called off, and printing that reads
// as a goalless draw rather than as a game that was not played.
function neverStarted(match) {
  if (isUpcoming(match)) return true
  var name = match.statusName || ""
  return name.indexOf("POSTPONED") !== -1
    || name.indexOf("CANCELED") !== -1
    || name.indexOf("CANCELLED") !== -1
    || name.indexOf("ABANDONED") !== -1
}

function scoreLine(match) {
  if (neverStarted(match)) return "–"
  return (match.home.score || "0") + "-" + (match.away.score || "0")
}

// ESPN keeps the running clock at "45'+1'" through the break and only says
// halftime in the short detail, so a match on its tea break used to read as a
// match still being played. The short detail is the minute while the ball is
// rolling and the label (HT, FT, AET, Pens) the rest of the time, so it is the
// honest reading in both cases.
function clockLabel(match) {
  if (isLive(match)) return match.statusShort || match.clock || ""
  if (isFinished(match)) return match.statusShort || "FT"
  return match.kickoffLocal || ""
}

// True while the match is stopped but not over: the bar should not look like
// the minute is still climbing.
function isBreak(match) {
  return isLive(match) && /^[A-Za-z]/.test(match.statusShort || "")
}

// What the bar carries: "BOU 0-1 LIV 67'" while it runs, "BOU–LIV 15:00" before.
function barLabel(match) {
  if (!match) return ""
  var core = match.home.abbr + " " + scoreLine(match) + " " + match.away.abbr
  var clock = clockLabel(match)
  return clock ? core + " " + clock : core
}

// Everything the goal line says after the word itself:
// "  G. Kvernadze (Frosinone, pen.) 45'+3'  1-0"
function goalRest(goal) {
  var who = goal.scorer || "Goal"
  var club = goal.teamName || goal.team || ""
  if (goal.note) club = club ? club + ", " + goal.note : goal.note
  if (club) who += " (" + club + ")"
  var minute = goal.minute ? " " + goal.minute : ""
  return "  " + who + minute + "  " + (goal.score || "")
}

// One scorer on the open match card. The minute has its own column between
// the two sides, so it is not repeated here - only the name, and whatever
// qualifies it. Note that a scoreboard goal carries the two flags rather than
// the ready-made `note` the bar's own goal object has.
function scorerLine(goal) {
  if (!goal) return ""
  var who = goal.scorer || "Goal"
  if (goal.ownGoal) return who + " (o.g.)"
  if (goal.penalty) return who + " (pen.)"
  return who
}

// One team's side of a statistic. ESPN sends the number without its unit, and
// a row a side has no entry for reads as a dash rather than as a blank that
// looks like a layout fault.
function statValueLabel(value, suffix) {
  if (value === undefined || value === null || value === "") return "-"
  var text = String(value)
  if (suffix && text.indexOf(suffix) === -1) text += suffix
  return text
}

// The word is drawn letter by letter on the bar, so it is kept apart from the
// rest of the line. This form is for measuring and for the tooltip.
function goalLabel(goal) {
  return "GOAL" + goalRest(goal)
}

// Club colours are chosen for shirts, not for a bar, and the bar can be any
// colour the theme says. Rather than assume a dark background and lift towards
// white - which left Real Madrid's white invisible on a light theme - push the
// colour away from whatever the bar actually is, in whichever direction that
// happens to be, until it carries.
function relativeLuminance(color) {
  function channel(value) {
    return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
}

function contrastRatio(a, b) {
  var lighter = Math.max(a, b)
  var darker = Math.min(a, b)
  return (lighter + 0.05) / (darker + 0.05)
}

function readableColor(hex, fallback, background) {
  if (!hex) return fallback
  var color = Qt.color(hex)
  if (!color || !color.valid) return fallback

  var bg = (background && background.valid) ? background : Qt.rgba(0, 0, 0, 1)
  var bgLuminance = relativeLuminance(bg)
  // Away from the background: towards black on a light bar, towards white on
  // a dark one.
  var target = bgLuminance > 0.45 ? 0 : 1

  for (var i = 0; i < 6; i++) {
    if (contrastRatio(relativeLuminance(color), bgLuminance) >= 4) break
    color = Qt.rgba(color.r + (target - color.r) * 0.28,
                    color.g + (target - color.g) * 0.28,
                    color.b + (target - color.b) * 0.28,
                    1)
  }
  return color
}

function matchTooltip(match) {
  return match.leagueName + "  ·  " + match.home.name + " " + scoreLine(match)
    + " " + match.away.name + "  ·  " + clockLabel(match)
}

function involvesFavorite(match, favorites) {
  if (!favorites || favorites.length === 0) return false
  return favorites.indexOf(match.home.id) !== -1
    || favorites.indexOf(match.away.id) !== -1
}

function findById(matches, id) {
  if (!id) return null
  for (var i = 0; i < matches.length; i++) {
    if (matches[i].id === id) return matches[i]
  }
  return null
}

// The one match the bar button stands for. A pin wins; otherwise live beats
// anything, a club you follow beats a club you do not, and a finished match
// only holds the slot while it is still fresh news.
function headlineMatch(matches, favorites, barMode, nowMs, pinnedId) {
  if (!matches || matches.length === 0) return null

  // A pinned match overrides the mode and the ranking: it is an explicit
  // answer to "this is the one I care about today". It stops applying by
  // itself once the fixture drops out of the cache.
  var pinned = findById(matches, pinnedId)
  if (pinned) return pinned

  // With nothing picked, the other modes fall back to whatever ranks highest,
  // which is a match nobody asked for sitting in the bar. This one does not
  // fall back: no eye on a row means no match on the bar.
  if (barMode === "Picked match only") return null

  var favoritesOnly = barMode === "Favorites only"
  var anyLive = barMode === "Any live match"
  var pool = []
  for (var i = 0; i < matches.length; i++) {
    var match = matches[i]
    var mine = involvesFavorite(match, favorites)
    if (favoritesOnly && !mine) continue
    if (anyLive && !mine && !isLive(match)) continue
    pool.push({ match: match, mine: mine })
  }
  if (pool.length === 0) return null

  var best = null
  var bestRank = null
  for (var j = 0; j < pool.length; j++) {
    var rank = headlineRank(pool[j].match, pool[j].mine, nowMs)
    if (rank === null) continue
    if (bestRank === null || rank < bestRank) {
      bestRank = rank
      best = pool[j].match
    }
  }
  return best
}

function headlineRank(match, mine, nowMs) {
  var mineBonus = mine ? 0 : 1
  if (isLive(match)) return 10 + mineBonus
  if (isUpcoming(match)) {
    var kickoff = match.kickoffEpoch * 1000
    // Only today's fixtures; a match three days out is not bar material.
    if (kickoff - nowMs > 12 * 60 * 60 * 1000) return null
    return 30 + mineBonus
  }
  if (isFinished(match)) {
    if (nowMs - match.kickoffEpoch * 1000 > FINISHED_GRACE_MS) return null
    return 20 + mineBonus
  }
  return null
}

// How long until the next fixture kicks off, or -1 with none coming. The bar
// knows what is live only from the last sweep, so without this a match that
// starts just after one waits out a whole idle interval before anybody looks.
function msToNextKickoff(matches, nowMs) {
  var soonest = -1
  for (var i = 0; i < matches.length; i++) {
    if (!isUpcoming(matches[i])) continue
    var away = matches[i].kickoffEpoch * 1000 - nowMs
    if (away <= 0) continue
    if (soonest < 0 || away < soonest) soonest = away
  }
  return soonest
}

// Panel grouping: live, then today's fixtures, then what has just finished.
function sections(matches) {
  var live = []
  var upcoming = []
  var finished = []
  for (var i = 0; i < matches.length; i++) {
    var match = matches[i]
    if (isLive(match)) live.push(match)
    else if (isUpcoming(match)) upcoming.push(match)
    else finished.push(match)
  }
  var result = []
  if (live.length) result.push({ title: "LIVE", matches: live })
  if (upcoming.length) result.push({ title: "COMING UP", matches: upcoming })
  if (finished.length) result.push({ title: "FINISHED", matches: finished })
  return result
}

function updatedLabel(updatedAt, nowMs) {
  if (!updatedAt) return "never refreshed"
  var seconds = Math.max(0, Math.round(nowMs / 1000 - updatedAt))
  if (seconds < 60) return "updated " + seconds + "s ago"
  var minutes = Math.round(seconds / 60)
  if (minutes < 60) return "updated " + minutes + "m ago"
  return "updated " + Math.round(minutes / 60) + "h ago"
}
