"""ESPN public soccer scoreboard, summary, timeline, and teams provider."""

import time
from datetime import datetime

from ..constants import COMPETITION_LABELS, SITE_API, SUMMARY_STATS
from ..http_client import NETWORK_ERRORS, read_json_url
from ..storage import compact_player_name


def parse_kickoff(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_competitor(competitor):
    team = competitor.get("team") or {}
    score = competitor.get("score")
    return {
        "id": str(team.get("id") or ""),
        "abbr": team.get("abbreviation") or team.get("shortDisplayName") or "?",
        "name": team.get("shortDisplayName") or team.get("displayName") or "?",
        "fullName": team.get("displayName") or "",
        "logo": team.get("logo") or "",
        "color": "#" + (team.get("color") or "").lstrip("#") if team.get("color") else "",
        "score": str(score) if score not in (None, "") else "",
        "winner": bool(competitor.get("winner")),
    }


def parse_goals(competition, home_id="", away_id=""):
    """Scoring plays ESPN attaches to a live match, oldest first."""
    valid_ids = {i for i in (home_id, away_id) if i}
    goals = []
    for detail in competition.get("details") or []:
        if not detail.get("scoringPlay") or detail.get("shootout"):
            continue
        athletes = detail.get("athletesInvolved") or []
        scorer = ""
        athlete_team_id = ""
        if athletes:
            scorer = athletes[0].get("shortName") or athletes[0].get("displayName") or ""
            athlete_team = athletes[0].get("team")
            if isinstance(athlete_team, dict):
                athlete_team_id = str(athlete_team.get("id") or "")
        own_goal = bool(detail.get("ownGoal"))
        team_id = str((detail.get("team") or {}).get("id") or "")
        if valid_ids and team_id not in valid_ids:
            if athlete_team_id in valid_ids:
                if own_goal and len(valid_ids) == 2:
                    team_id = away_id if athlete_team_id == home_id else home_id
                else:
                    team_id = athlete_team_id
            else:
                team_id = ""
        goals.append(
            {
                "minute": (detail.get("clock") or {}).get("displayValue") or "",
                "team": team_id,
                "scorer": scorer,
                "ownGoal": own_goal,
                "penalty": bool(detail.get("penaltyKick")),
            }
        )
    return goals


def parse_event(event, league_slug, league_name):
    competition = (event.get("competitions") or [{}])[0]
    competitors = competition.get("competitors") or []
    home = next((c for c in competitors if c.get("homeAway") == "home"), None)
    away = next((c for c in competitors if c.get("homeAway") == "away"), None)
    if home is None or away is None:
        return None

    status = competition.get("status") or {}
    status_type = status.get("type") or {}
    kickoff = parse_kickoff(competition.get("date") or event.get("date"))
    home_parsed = parse_competitor(home)
    away_parsed = parse_competitor(away)

    return {
        "id": str(event.get("id") or ""),
        "league": league_slug,
        "leagueName": league_name,
        "state": status_type.get("state") or "pre",
        "statusName": status_type.get("name") or "",
        "statusShort": status_type.get("shortDetail") or "",
        "statusDetail": status_type.get("detail") or "",
        "clock": status.get("displayClock") or "",
        "period": status.get("period") or 0,
        "kickoff": kickoff.isoformat() if kickoff else "",
        "kickoffEpoch": int(kickoff.timestamp()) if kickoff else 0,
        "kickoffLocal": kickoff.astimezone().strftime("%H:%M") if kickoff else "",
        "note": (competition.get("notes") or [{}])[0].get("headline", ""),
        "goals": parse_goals(competition, home_parsed["id"], away_parsed["id"]),
        "home": home_parsed,
        "away": away_parsed,
    }


def parse_espn_timeline(payload, home_id="", away_id=""):
    """Chronological match events (goals+assists, cards, subs) from ESPN summary."""
    valid_ids = {i for i in (home_id, away_id) if i}
    events = []
    for item in payload.get("keyEvents") or []:
        if item.get("shootout"):
            continue
        type_text = str((item.get("type") or {}).get("text") or "")
        tl = type_text.lower()
        scoring = bool(item.get("scoringPlay"))
        is_red = "red card" in tl or "second yellow" in tl or "yellow/red" in tl
        is_yellow = (not is_red) and ("yellow card" in tl)
        is_sub = "substitution" in tl
        is_missed_pen = (not scoring) and ("penalty" in tl) and ("miss" in tl or "save" in tl)
        if not (scoring or is_red or is_yellow or is_sub or is_missed_pen):
            continue

        participants = item.get("participants") or []
        names = []
        athlete_team_id = ""
        for idx, part in enumerate(participants):
            athlete = part.get("athlete") or {}
            nm = athlete.get("shortName") or athlete.get("displayName") or ""
            if nm:
                names.append(compact_player_name(nm))
            if idx == 0 and isinstance(athlete.get("team"), dict):
                athlete_team_id = str(athlete["team"].get("id") or "")

        own_goal = bool(item.get("ownGoal")) or "own goal" in tl
        penalty = bool(item.get("penaltyKick")) or "penalty" in tl
        team_id = str((item.get("team") or {}).get("id") or "")
        if valid_ids and team_id not in valid_ids:
            if athlete_team_id in valid_ids:
                if own_goal and len(valid_ids) == 2:
                    team_id = away_id if athlete_team_id == home_id else home_id
                else:
                    team_id = athlete_team_id
            else:
                continue
        if not team_id:
            continue

        kind = (
            "goal" if scoring
            else ("missed_pen" if is_missed_pen
            else ("red" if is_red
            else ("yellow" if is_yellow else "sub")))
        )
        player = names[0] if names else ""
        secondary = ""
        if kind == "goal" and len(names) > 1 and not own_goal and not penalty:
            secondary = names[1]
        elif kind == "sub" and len(names) > 1:
            secondary = names[1]

        events.append({
            "minute": str((item.get("clock") or {}).get("displayValue") or ""),
            "team": team_id,
            "kind": kind,
            "player": player,
            "secondary": secondary,
            "ownGoal": own_goal,
            "penalty": penalty,
        })
    return events


def fetch_espn_league(slug, deadline=None):
    try:
        payload = read_json_url("%s/%s/scoreboard" % (SITE_API, slug), deadline)
    except NETWORK_ERRORS as error:
        return slug, COMPETITION_LABELS.get(slug, slug), [], str(error)
    except Exception as error:  # noqa: BLE001
        return slug, COMPETITION_LABELS.get(slug, slug), [], repr(error)

    leagues = payload.get("leagues") or [{}]
    name = COMPETITION_LABELS.get(slug) or leagues[0].get("name") or slug
    matches = []
    for event in payload.get("events") or []:
        try:
            match = parse_event(event, slug, name)
        except (AttributeError, TypeError, KeyError, IndexError, ValueError):
            continue
        if match is not None:
            matches.append(match)
    return slug, name, matches, None


def fetch_espn_stats(league, event_id, deadline=None):
    try:
        payload = read_json_url(
            "%s/%s/summary?event=%s" % (SITE_API, league, event_id), deadline
        )
    except NETWORK_ERRORS:
        return None

    teams = ((payload.get("boxscore") or {}).get("teams")) or []
    header_comps = (((payload.get("header") or {}).get("competitions")) or [{}])[0].get("competitors") or []
    home_id = next((str((c.get("team") or {}).get("id") or "") for c in header_comps if c.get("homeAway") == "home"), "")
    away_id = next((str((c.get("team") or {}).get("id") or "") for c in header_comps if c.get("homeAway") == "away"), "")

    by_id = {}
    for team in teams:
        team_id = str((team.get("team") or {}).get("id") or "")
        values = {}
        for stat in team.get("statistics") or []:
            values[stat.get("name")] = stat.get("displayValue")
        by_id[team_id] = values

    rows = []
    for key, label, suffix in SUMMARY_STATS:
        present = [v.get(key) for v in by_id.values()]
        if not any(value not in (None, "") for value in present):
            continue
        if key == "redCards" and all(str(value or "0") in ("0", "") for value in present):
            continue
        rows.append({"key": key, "label": label, "suffix": suffix})

    events = parse_espn_timeline(payload, home_id, away_id)
    if not rows and not events:
        return None

    return {
        "matchId": str(event_id),
        "at": int(time.time()),
        "teams": by_id,
        "rows": rows,
        "events": events,
    }


def fetch_espn_teams(slug):
    try:
        payload = read_json_url("%s/%s/teams" % (SITE_API, slug))
    except NETWORK_ERRORS:
        return []
    try:
        entries = payload["sports"][0]["leagues"][0]["teams"]
    except (KeyError, IndexError, TypeError):
        return []
    league = COMPETITION_LABELS.get(slug, slug)
    teams = []
    for entry in entries:
        team = entry.get("team") or {}
        if not team.get("id"):
            continue
        teams.append(
            {
                "value": str(team["id"]),
                "label": team.get("displayName") or team.get("shortDisplayName") or "?",
                "description": league,
            }
        )
    return teams
