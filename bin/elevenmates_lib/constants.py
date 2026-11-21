"""Shared constants, defaults, and competition metadata."""

import os
import re

SITE_API = "https://site.api.espn.com/apis/site/v2/sports/soccer"
LS_API = "https://prod-cdn-public-api.livescore.com/v1/api/app"
LS_IMAGES = "https://lsm-static-prod.livescore.com/medium"

LS_STAGES = {
    "pol.1": "poland/ekstraklasa",
}
LS_PREFIX = "ls-"
LS_MAX_DETAIL = 10

CONFIG_PATH = os.path.expanduser("~/.config/omarchy/elevenmates.json")
STATE_PATH = os.path.expanduser("~/.local/state/omarchy/elevenmates/state.json")

DEFAULT_CONFIG = {
    "leagues": [
        "eng.1", "esp.1", "ger.1", "ita.1", "fra.1",
        "uefa.champions", "uefa.europa", "uefa.europa.conf",
        "uefa.nations", "fifa.worldq.uefa",
    ],
    "favoriteTeams": [],
    "pinnedMatch": "",
    "alertMatches": [],
    "barMode": "Auto",
    "goalNotifications": True,
    "notifyAll": False,
    "liveRefreshSec": 25,
    "idleRefreshMin": 12,
    "stremioEnabled": False,
    "stremioUrl": "http://127.0.0.1:7040",
    "stremioPlayer": "mpv",
}

REQUEST_TIMEOUT = 12
MAX_PARALLEL_REQUESTS = 6
MAX_BODY_BYTES = 4 * 1024 * 1024
MAX_DECOMPRESSED_BYTES = 16 * 1024 * 1024
READ_CHUNK_BYTES = 64 * 1024
UNTIMED_BODY_BUDGET = 60

LOCK_NAME = "fetch.lock"
MIN_REFRESH_AGE = 10
FULL_SWEEP_INTERVAL = 15 * 60
FETCH_BUDGET = 40
TEAMS_CACHE_NAME = "teams.json"
TEAMS_CACHE_AGE = 7 * 24 * 60 * 60

SLUG_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")

DEMO_GOAL = {
    "matchId": "demo",
    "league": "LaLiga",
    "team": "RMA",
    "teamName": "Real Madrid",
    "teamColor": "#ffffff",
    "minute": "23'",
    "score": "1-0",
    "home": "RMA",
    "away": "BAR",
}

STALE_CACHE_AGE = 20 * 60
IDLE_STRETCH_CAP = 45 * 60
GOAL_FEED_KEEP = 12
RECENT_MATCH_AGE = 5 * 60 * 60
STATS_KEEP = 4
STATS_AGE = 15 * 60

SUMMARY_STATS = [
    ("possessionPct", "Possession", "%"),
    ("totalShots", "Shots", ""),
    ("shotsOnTarget", "On target", ""),
    ("wonCorners", "Corners", ""),
    ("yellowCards", "Yellow cards", ""),
    ("redCards", "Red cards", ""),
    ("foulsCommitted", "Fouls", ""),
]

LS_STAT_KEYS = {
    "possessionPct": ("Pss",),
    "totalShots": ("Shon", "Shof", "Shbl"),
    "shotsOnTarget": ("Shon",),
    "wonCorners": ("Cos",),
    "yellowCards": ("Ycs",),
    "redCards": ("Rcs",),
    "foulsCommitted": ("Fls",),
}

COMPETITIONS = [
    ("eng.1", "Premier League", "England"),
    ("eng.2", "Championship", "England"),
    ("eng.fa", "FA Cup", "England"),
    ("eng.league_cup", "EFL Cup", "England"),
    ("esp.1", "LaLiga", "Spain"),
    ("esp.copa_del_rey", "Copa del Rey", "Spain"),
    ("ger.1", "Bundesliga", "Germany"),
    ("ger.2", "2. Bundesliga", "Germany"),
    ("ger.dfb_pokal", "DFB-Pokal", "Germany"),
    ("ita.1", "Serie A", "Italy"),
    ("ita.coppa_italia", "Coppa Italia", "Italy"),
    ("fra.1", "Ligue 1", "France"),
    ("fra.coupe_de_france", "Coupe de France", "France"),
    ("ned.1", "Eredivisie", "Netherlands"),
    ("pol.1", "Ekstraklasa", "Poland"),
    ("por.1", "Primeira Liga", "Portugal"),
    ("sco.1", "Premiership", "Scotland"),
    ("bel.1", "Pro League", "Belgium"),
    ("tur.1", "Super Lig", "Turkey"),
    ("gre.1", "Super League", "Greece"),
    ("aut.1", "Bundesliga", "Austria"),
    ("swe.1", "Allsvenskan", "Sweden"),
    ("nor.1", "Eliteserien", "Norway"),
    ("den.1", "Superliga", "Denmark"),
    ("usa.1", "MLS", "United States"),
    ("mex.1", "Liga MX", "Mexico"),
    ("bra.1", "Brasileirao", "Brazil"),
    ("arg.1", "Liga Profesional", "Argentina"),
    ("ksa.1", "Saudi Pro League", "Saudi Arabia"),
    ("uefa.champions", "Champions League", "Europe"),
    ("uefa.champions_qual", "Champions League qualifying", "Europe"),
    ("uefa.europa", "Europa League", "Europe"),
    ("uefa.europa_qual", "Europa League qualifying", "Europe"),
    ("uefa.europa.conf", "Conference League", "Europe"),
    ("uefa.europa.conf_qual", "Conference League qualifying", "Europe"),
    ("uefa.super_cup", "UEFA Super Cup", "Europe"),
    ("fifa.cwc", "Club World Cup", "World"),
    ("fifa.world", "World Cup", "National teams"),
    ("fifa.worldq.uefa", "World Cup qualifying", "National teams, Europe"),
    ("uefa.euro", "European Championship", "National teams"),
    ("uefa.euroq", "European Championship qualifying", "National teams"),
    ("uefa.nations", "Nations League", "National teams"),
    ("uefa.euro_u21", "Euro U21", "National teams"),
    ("fifa.friendly", "International friendlies", "National teams"),
]

COMPETITION_LABELS = {slug: label for slug, label, _ in COMPETITIONS}
STATE_ORDER = {"in": 0, "pre": 1, "post": 2}
