"""Goal diffing, scoreline reconstruction, and desktop notifications."""

import subprocess
import time

from .constants import GOAL_FEED_KEEP
from .storage import warn


def goal_keys(match_id, goals):
    """Stable per-side ordinal identifiers so revised names/minutes don't re-fire."""
    seen = {}
    keys = []
    for goal in goals:
        team = goal.get("team", "")
        seen[team] = seen.get(team, 0) + 1
        keys.append("%s|%s|%s" % (match_id, team, seen[team]))
    return keys


def safe_score(side):
    try:
        return int(side.get("score") or 0)
    except (TypeError, ValueError):
        return 0


def goals_scored(match):
    total = 0
    for side in ("home", "away"):
        try:
            total += int(match[side]["score"] or 0)
        except (TypeError, ValueError):
            return -1
    return total


def scoreline_of(match):
    return "%s-%s" % (match["home"]["score"] or "0", match["away"]["score"] or "0")


def goal_note(goal):
    if goal["ownGoal"]:
        return "o.g."
    if goal["penalty"]:
        return "pen."
    return ""


def goal_headline(goal):
    scorer = goal["scorer"] or "Goal"
    if goal["ownGoal"]:
        scorer += " (o.g.)"
    elif goal["penalty"]:
        scorer += " (pen.)"
    return (scorer + " " + goal["minute"]).strip()


def score_at(match, goals, index):
    """Scoreline when goals[index] went in, tolerating lagging scoreboards."""
    home_id = match["home"]["id"]
    away_id = match["away"]["id"]
    home_goals = sum(1 for g in goals if g.get("team") == home_id)
    away_goals = sum(1 for g in goals if g.get("team") == away_id)
    home = max(safe_score(match["home"]), home_goals)
    away = max(safe_score(match["away"]), away_goals)
    for later in goals[index + 1:]:
        if later.get("team") == home_id:
            home -= 1
        elif later.get("team") == away_id:
            away -= 1
    return "%d-%d" % (max(0, home), max(0, away))


def describe_goal(match, goal, seq, score=None, old=None):
    team_id = goal.get("team") or ""
    if team_id == match["home"]["id"]:
        side = match["home"]
    elif team_id == match["away"]["id"]:
        side = match["away"]
    elif isinstance(old, dict):
        home_up = safe_score(match["home"]) > safe_score(old.get("home") or {})
        away_up = safe_score(match["away"]) > safe_score(old.get("away") or {})
        if home_up and not away_up:
            side = match["home"]
        elif away_up and not home_up:
            side = match["away"]
        else:
            return None
    else:
        return None
    return {
        "seq": seq,
        "at": int(time.time()),
        "matchId": match["id"],
        "league": match["leagueName"],
        "team": side["abbr"],
        "teamName": side["name"],
        "teamColor": side["color"],
        "scorer": goal["scorer"] or "",
        "minute": goal["minute"],
        "note": goal_note(goal),
        "headline": goal_headline(goal),
        "score": score or scoreline_of(match),
        "home": match["home"]["abbr"],
        "away": match["away"]["abbr"],
    }


def describe_score_move(match, old, seq):
    side = None
    for key in ("home", "away"):
        if safe_score(match[key]) > safe_score(old.get(key) or {}):
            side = match[key]
            break
    if side is None:
        return None
    minute = match["clock"] or match["statusShort"] or ""
    return {
        "seq": seq,
        "at": int(time.time()),
        "matchId": match["id"],
        "league": match["leagueName"],
        "team": side["abbr"],
        "teamName": side["name"],
        "teamColor": side["color"],
        "scorer": "",
        "minute": minute,
        "note": "",
        "headline": minute or "Goal",
        "score": scoreline_of(match),
        "home": match["home"]["abbr"],
        "away": match["away"]["abbr"],
        "placeholder": True,
    }


def take_placeholder(feed, match_id, team_abbr=None):
    """Pull this match's oldest unnamed goal off the feed, preferring the same side."""
    fallback = (None, None)
    for index, entry in enumerate(feed):
        if entry.get("placeholder") and entry.get("matchId") == match_id:
            if team_abbr and entry.get("team") == team_abbr:
                return index, entry
            if fallback[0] is None:
                fallback = (index, entry)
    return fallback


def notify(match, headline, detail="", score=None, clock=None):
    body = "%s %s %s  %s" % (
        match["home"]["name"],
        score or scoreline_of(match),
        match["away"]["name"],
        clock or match["clock"] or match["statusShort"],
    )
    if detail:
        body = detail + "\n" + body
    try:
        result = subprocess.run(
            ["notify-send", "-a", "Elevenmates", "-u", "low", headline, body],
            check=False,
            timeout=5,
            capture_output=True,
        )
    except FileNotFoundError:
        warn("notify-send is not installed, so goal alerts stay on the bar only")
        return
    except (OSError, subprocess.SubprocessError) as error:
        warn("notify-send could not be run: %s" % error)
        return
    if result.returncode != 0:
        detail_text = (result.stderr or b"").decode("utf-8", "replace").strip()
        warn(
            "notify-send exited %d%s"
            % (result.returncode, ": " + detail_text if detail_text else "")
        )


def announce_changes(
    previous, matches, favorites, alerts, watched_ids, notify_all, notify_enabled, feed
):
    previous_matches = previous.get("matches") or []
    before = {m["id"]: m for m in previous_matches}
    seq = int((previous.get("lastGoal") or {}).get("seq") or 0)
    feed = list(feed)

    for match in matches:
        old = before.get(match["id"])
        if not isinstance(old, dict) or "state" not in old:
            continue
        watched = (
            notify_all
            or match["id"] in alerts
            or match["id"] in watched_ids
            or match["home"]["id"] in favorites
            or match["away"]["id"] in favorites
        )
        if not watched:
            continue

        seen = set(goal_keys(match["id"], old.get("goals") or []))
        current = match.get("goals") or []
        fresh = [
            (index, goal)
            for index, (goal, key) in enumerate(
                zip(current, goal_keys(match["id"], current))
            )
            if key not in seen
        ]
        if fresh and match["state"] != "pre":
            for index, goal in fresh:
                score = score_at(match, current, index)
                entry = describe_goal(match, goal, seq + 1, score, old=old)
                if entry is None:
                    continue
                slot, placeholder = take_placeholder(feed, match["id"], entry["team"])
                if placeholder is not None:
                    entry["seq"] = placeholder["seq"]
                    entry["at"] = placeholder["at"]
                    feed[slot] = entry
                    continue

                seq += 1
                feed.append(entry)
                if notify_enabled:
                    notify(
                        match,
                        "Goal - " + match["leagueName"],
                        entry["teamName"] + ": " + entry["headline"],
                        entry["score"],
                        goal.get("minute") or None,
                    )
        elif (
            match["state"] == "in"
            and goals_scored(match) > goals_scored(old)
            and goals_scored(match) > len(current)
        ):
            seq += 1
            entry = describe_score_move(match, old, seq)
            if entry is not None:
                feed.append(entry)
            if notify_enabled:
                notify(match, "Goal - " + match["leagueName"])

        if notify_enabled and match["state"] == "post" and old["state"] == "in":
            notify(match, "Full time - " + match["leagueName"])

    return feed[-GOAL_FEED_KEEP:]
