"""Competition data providers (ESPN, LiveScore)."""

from ..constants import LS_PREFIX, LS_STAGES
from ..storage import valid_slug
from .espn import fetch_espn_league, fetch_espn_stats, fetch_espn_teams
from .livescore import (
    fetch_livescore_league,
    fetch_livescore_stats,
    fetch_livescore_teams,
)


def fetch_league(slug, deadline=None, previous=None):
    if not valid_slug(slug):
        return slug, slug, [], "not a valid competition id"
    if slug in LS_STAGES:
        return fetch_livescore_league(slug, deadline, previous)
    return fetch_espn_league(slug, deadline)


def fetch_stats(league, event_id, deadline=None):
    if not valid_slug(league) or not valid_slug(str(event_id)):
        return None
    if league in LS_STAGES:
        raw_id = str(event_id)
        if raw_id.startswith(LS_PREFIX):
            raw_id = raw_id[len(LS_PREFIX):]
        return fetch_livescore_stats(raw_id, deadline)
    return fetch_espn_stats(league, event_id, deadline)


def fetch_teams(slug):
    if slug in LS_STAGES:
        return fetch_livescore_teams(slug)
    return fetch_espn_teams(slug)
