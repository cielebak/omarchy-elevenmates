"""LiveScore provider for competitions absent from ESPN (e.g. Ekstraklasa)."""

import time
from datetime import datetime, timezone

from ..announce import scoreline_of
from ..constants import (
    COMPETITION_LABELS,
    LS_API,
    LS_IMAGES,
    LS_MAX_DETAIL,
    LS_PREFIX,
    LS_STAGES,
    LS_STAT_KEYS,
    SUMMARY_STATS,
)
from ..http_client import NETWORK_ERRORS, read_json_url
from ..storage import compact_player_name, is_today

LS_SPECIAL_STATES = {
    "HT": ("in", "STATUS_HALFTIME"),
    "Postp.": ("post", "STATUS_POSTPONED"),
    "Canc.": ("post", "STATUS_CANCELED"),
    "Aband.": ("post", "STATUS_ABANDONED"),
    "Abd": ("post", "STATUS_ABANDONED"),
    "Susp.": ("in", "STATUS_SUSPENDED"),
    "Int.": ("in", "STATUS_SUSPENDED"),
}

LS_PHASES = {
    1: ("in", "STATUS_IN_PROGRESS"),
    2: ("post", "STATUS_FULL_TIME"),
    3: ("post", "STATUS_CANCELED"),
    4: ("post", "STATUS_POSTPONED"),
    6: ("in", "STATUS_SUSPENDED"),
    8: ("post", "STATUS_ABANDONED"),
}

LS_GOAL, LS_PENALTY_GOAL, LS_OWN_GOAL = 36, 37, 39


def ls_events(slug, deadline=None):
    payload = read_json_url(
        "%s/stage/soccer/%s/0?MD=1" % (LS_API, LS_STAGES[slug]), deadline
    )
    stages = payload.get("Stages") or []
    return (stages[0].get("Events") or []) if stages else []


def ls_kickoff(event):
    try:
        return datetime.strptime(str(event.get("Esd")), "%Y%m%d%H%M%S").replace(
            tzinfo=timezone.utc
        )
    except (TypeError, ValueError):
        return None


def ls_competitor(team, score):
    name = team.get("Nm") or "?"
    colour = team.get("firstColor") or ""
    return {
        "id": LS_PREFIX + str(team.get("ID") or ""),
        "abbr": (team.get("Abr") or name[:3]).upper(),
        "name": name,
        "fullName": name,
        "logo": "%s/%s" % (LS_IMAGES, team["Img"]) if team.get("Img") else "",
        "color": "#" + colour if colour else "",
        "score": str(score) if score not in (None, "") else "",
        "winner": False,
    }


def ls_parse_goals(board):
    incidents = []
    periods = board.get("Incs-s") or {}
    for period in sorted(periods, key=lambda key: int(key) if key.isdigit() else 99):
        for incident in periods[period] or []:
            parent_nm = incident.get("Nm")
            for sub in incident.get("Incs") or [incident]:
                incidents.append((sub, parent_nm))

    goals = []
    prev_h, prev_a = 0, 0
    for incident, parent_nm in incidents:
        kind = incident.get("IT")
        if kind not in (LS_GOAL, LS_PENALTY_GOAL, LS_OWN_GOAL):
            continue
        minute = incident.get("Min")
        added = incident.get("MinEx")
        if minute is None:
            label = ""
        elif added:
            label = "%d'+%d'" % (minute, added)
        else:
            label = "%d'" % minute
        nm = incident.get("Nm") if incident.get("Nm") is not None else parent_nm
        sc = incident.get("Sc")
        is_home = None
        if isinstance(sc, list) and len(sc) >= 2:
            try:
                nh, na = int(sc[0]), int(sc[1])
                if nh > prev_h and na == prev_a:
                    is_home = True
                elif na > prev_a and nh == prev_h:
                    is_home = False
                prev_h, prev_a = nh, na
            except (TypeError, ValueError):
                pass
        if is_home is None:
            is_home = nm == 1
        goals.append(
            {
                "minute": label,
                "team": "",
                "scorer": incident.get("Pn") or incident.get("Ln") or "",
                "ownGoal": kind == LS_OWN_GOAL,
                "penalty": kind == LS_PENALTY_GOAL,
                "isHome": bool(is_home),
            }
        )
    return goals


def ls_goals(event_id, deadline=None):
    try:
        board = read_json_url(
            "%s/scoreboard/soccer/%s?locale=en" % (LS_API, event_id), deadline
        )
    except NETWORK_ERRORS:
        return None, None
    try:
        return ls_parse_goals(board), board
    except (AttributeError, TypeError, KeyError, IndexError, ValueError):
        return None, None


def ls_event(event, slug, league_name, goals, board=None):
    home_team = (event.get("T1") or [{}])[0]
    away_team = (event.get("T2") or [{}])[0]
    if not home_team.get("ID") or not away_team.get("ID"):
        return None
    if board:
        home_team = dict(home_team, **((board.get("T1") or [{}])[0]))
        away_team = dict(away_team, **((board.get("T2") or [{}])[0]))

    label = event.get("Eps") or ""
    state, status_name = LS_SPECIAL_STATES.get(label) or LS_PHASES.get(
        event.get("Epr"), ("pre", "STATUS_SCHEDULED")
    )
    home = ls_competitor(home_team, event.get("Tr1"))
    away = ls_competitor(away_team, event.get("Tr2"))

    resolved = []
    for goal in goals or []:
        entry = dict(goal)
        entry["team"] = home["id"] if entry.get("isHome") else away["id"]
        resolved.append(entry)

    when = ls_kickoff(event)
    short = (when.astimezone().strftime("%H:%M") if when else "") if state == "pre" else label

    return {
        "id": LS_PREFIX + str(event.get("Eid") or ""),
        "league": slug,
        "leagueName": league_name,
        "state": state,
        "statusName": status_name,
        "statusShort": short,
        "statusDetail": label,
        "clock": short if state == "in" else "",
        "period": 0,
        "kickoff": when.isoformat() if when else "",
        "kickoffEpoch": int(when.timestamp()) if when else 0,
        "kickoffLocal": when.astimezone().strftime("%H:%M") if when else "",
        "note": "",
        "goals": resolved,
        "home": home,
        "away": away,
    }


def goal_total(match):
    try:
        return int(match["home"]["score"] or 0) + int(match["away"]["score"] or 0)
    except ValueError:
        return -1


def fetch_livescore_league(slug, deadline=None, previous=None):
    name = COMPETITION_LABELS.get(slug, slug)
    try:
        events = ls_events(slug, deadline)
    except NETWORK_ERRORS as error:
        return slug, name, [], str(error)
    except Exception as error:  # noqa: BLE001
        return slug, name, [], repr(error)

    before = {
        match["id"]: match
        for match in (previous or [])
        if isinstance(match, dict) and match.get("id")
    }
    today = datetime.now().date()
    now = time.time()
    matches = []
    detailed = 0

    for event in events:
        try:
            skeleton = ls_event(event, slug, name, None)
        except (AttributeError, TypeError, KeyError, IndexError, ValueError):
            continue
        if skeleton is None or not is_today(skeleton, today, now):
            continue

        prior = before.get(skeleton["id"])
        prior_goals = prior.get("goals") if prior else None
        if prior_goals and not all("isHome" in goal for goal in prior_goals):
            prior_goals = None
        reused = (
            isinstance(prior_goals, list)
            and scoreline_of(prior) == scoreline_of(skeleton)
            and len(prior_goals) == goal_total(skeleton)
        )
        goals = prior_goals
        board = None
        if not reused and skeleton["state"] != "pre" and detailed < LS_MAX_DETAIL:
            detailed += 1
            fetched, board = ls_goals(str(event["Eid"]), deadline)
            if fetched is not None:
                goals = fetched
        if goals or board:
            try:
                skeleton = ls_event(event, slug, name, goals, board) or skeleton
            except (AttributeError, TypeError, KeyError, IndexError, ValueError):
                pass
        if not board and prior:
            for side in ("home", "away"):
                skeleton[side]["color"] = (prior.get(side) or {}).get("color") or ""
        matches.append(skeleton)
    return slug, name, matches, None


def ls_parse_timeline(incidents_doc, sides):
    """Parse goals (+assists) and yellow/red cards from LiveScore /incidents."""
    events = []
    periods = (incidents_doc or {}).get("Incs") or {}
    for period in sorted(periods, key=lambda key: int(key) if key.isdigit() else 99):
        for group in periods[period] or []:
            subs = group.get("Incs") or [group]
            parent_nm = group.get("Nm")
            assist_name = ""
            for s in subs:
                if s.get("IT") == 63:
                    assist_name = compact_player_name(s.get("Pn") or s.get("Ln") or "")
            for s in subs:
                it = s.get("IT")
                if it in (LS_GOAL, LS_PENALTY_GOAL, LS_OWN_GOAL):
                    kind = "goal"
                elif it == 43:
                    kind = "yellow"
                elif it in (44, 45):
                    kind = "red"
                else:
                    continue
                nm = s.get("Nm") if s.get("Nm") is not None else parent_nm
                team_id = sides.get(nm)
                if not team_id:
                    continue
                minute = s.get("Min")
                added = s.get("MinEx")
                if minute is None:
                    label = ""
                elif added:
                    label = "%d'+%d'" % (minute, added)
                else:
                    label = "%d'" % minute
                events.append({
                    "minute": label,
                    "team": team_id,
                    "kind": kind,
                    "player": compact_player_name(s.get("Pn") or s.get("Ln") or ""),
                    "secondary": assist_name if kind == "goal" and it != LS_OWN_GOAL else "",
                    "ownGoal": it == LS_OWN_GOAL,
                    "penalty": it == LS_PENALTY_GOAL,
                })
    return events


def fetch_livescore_stats(event_id, deadline=None):
    try:
        payload = read_json_url(
            "%s/statistics/soccer/%s?locale=en" % (LS_API, event_id), deadline
        )
        board = read_json_url(
            "%s/scoreboard/soccer/%s?locale=en" % (LS_API, event_id), deadline
        )
    except NETWORK_ERRORS:
        return None

    incidents_doc = None
    try:
        incidents_doc = read_json_url(
            "%s/incidents/soccer/%s?locale=en" % (LS_API, event_id), deadline
        )
    except NETWORK_ERRORS:
        pass

    home_id = str(((board.get("T1") or [{}])[0]).get("ID") or "")
    away_id = str(((board.get("T2") or [{}])[0]).get("ID") or "")
    if not home_id or not away_id or home_id == away_id:
        return None
    sides = {1: LS_PREFIX + home_id, 2: LS_PREFIX + away_id}

    by_id = {sides[1]: {}, sides[2]: {}}
    for team in payload.get("Stat") or []:
        side = sides.get(team.get("Tnb"))
        if side is None:
            continue
        for key, source in LS_STAT_KEYS.items():
            parts = [team.get(field) for field in source]
            try:
                by_id[side][key] = str(sum(int(part) for part in parts))
            except (TypeError, ValueError):
                continue

    rows = []
    for key, label, suffix in SUMMARY_STATS:
        if key not in by_id[sides[1]] and key not in by_id[sides[2]]:
            continue
        if key == "redCards" and all(str(by_id[s].get(key) or "0") in ("0", "") for s in (sides[1], sides[2])):
            continue
        rows.append({"key": key, "label": label, "suffix": suffix})

    events = ls_parse_timeline(incidents_doc, sides)
    if not rows and not events:
        return None
    return {
        "matchId": LS_PREFIX + str(event_id),
        "at": int(time.time()),
        "teams": by_id,
        "rows": rows,
        "events": events,
    }


def fetch_livescore_teams(slug):
    try:
        events = ls_events(slug)
    except NETWORK_ERRORS:
        return []
    league = COMPETITION_LABELS.get(slug, slug)
    teams = {}
    for event in events:
        for team in (event.get("T1") or []) + (event.get("T2") or []):
            if team.get("ID"):
                teams[team["ID"]] = {
                    "value": LS_PREFIX + str(team["ID"]),
                    "label": team.get("Nm") or "?",
                    "description": league,
                }
    return sorted(teams.values(), key=lambda team: team["label"])
