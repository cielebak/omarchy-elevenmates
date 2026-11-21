"""Config/cache storage, file locking, validation, and match helpers."""

import errno
import fcntl
import json
import os
import sys
import tempfile
import time
from datetime import datetime

from .constants import (
    DEFAULT_CONFIG,
    RECENT_MATCH_AGE,
    SLUG_PATTERN,
    STATE_ORDER,
    STATS_AGE,
    STATS_KEEP,
)

_warned = set()


def valid_slug(slug):
    """Slugs are interpolated into URL paths; keep them strictly safe."""
    return bool(slug) and bool(SLUG_PATTERN.match(slug))


def compact_player_name(name):
    """Turn 'Mohamed Amoura' into 'M. Amoura' so timeline lines stay compact."""
    raw = str(name or "").strip()
    if not raw or "." in raw.split()[0]:
        return raw
    parts = raw.split()
    if len(parts) < 2:
        return raw
    return "%s. %s" % (parts[0][0], " ".join(parts[1:]))


def as_string_list(value):
    if isinstance(value, str):
        return [part for part in value.split(",") if part]
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value if str(item)]
    return []


def load_config(path):
    config = dict(DEFAULT_CONFIG)
    try:
        with open(path, "r", encoding="utf-8") as handle:
            stored = json.load(handle)
    except (OSError, ValueError):
        return config
    if isinstance(stored, dict):
        config.update(stored)
    return config


def load_cache(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def write_json_atomic(path, data):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=directory, delete=False
    )
    try:
        json.dump(data, handle, ensure_ascii=False)
        handle.flush()
        os.fsync(handle.fileno())
    finally:
        handle.close()
    os.replace(handle.name, path)


def warn(message):
    """Print each warning once per run on stderr."""
    if message in _warned:
        return
    _warned.add(message)
    print("elevenmates: " + message, file=sys.stderr)


class FetchLock:
    """Non-blocking exclusive cross-process lock."""

    def __init__(self, path):
        self.path = path
        self.handle = None
        self.acquired = False

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        try:
            self.handle = open(self.path, "w")
            os.chmod(self.path, 0o600)
            fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.acquired = True
        except OSError as error:
            if self.handle:
                self.handle.close()
                self.handle = None
            if error.errno not in (errno.EACCES, errno.EAGAIN):
                raise
        return self

    def __exit__(self, *_):
        if not self.handle:
            return
        try:
            if self.acquired:
                fcntl.flock(self.handle, fcntl.LOCK_UN)
        finally:
            self.handle.close()
            self.handle = None


def sort_key(match, favorites):
    involves_favorite = (
        match["home"]["id"] in favorites or match["away"]["id"] in favorites
    )
    state_rank = STATE_ORDER.get(match["state"], 3)
    time_rank = -match["kickoffEpoch"] if state_rank == 2 else match["kickoffEpoch"]
    return (state_rank, 0 if involves_favorite else 1, time_rank, match["id"])


def is_today(match, today, now):
    if match["state"] == "in":
        return True
    if not match["kickoffEpoch"]:
        return False
    elapsed = now - match["kickoffEpoch"]
    if 0 <= elapsed < RECENT_MATCH_AGE:
        return True
    return datetime.fromtimestamp(match["kickoffEpoch"]).date() == today


def merge_stats(stored, fetched):
    """Keep fresh per-match stats/timeline entries, newest first."""
    now = time.time()
    kept = {}
    for match_id, entry in (stored if isinstance(stored, dict) else {}).items():
        if isinstance(entry, dict) and now - float(entry.get("at") or 0) < STATS_AGE:
            kept[str(match_id)] = entry
    if fetched:
        kept[str(fetched["matchId"])] = fetched
    if len(kept) > STATS_KEEP:
        newest = sorted(kept.items(), key=lambda item: -float(item[1].get("at") or 0))
        kept = dict(newest[:STATS_KEEP])
    return kept
