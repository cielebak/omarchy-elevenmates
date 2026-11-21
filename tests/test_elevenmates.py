"""Regression tests for Elevenmates goal attribution, timelines, and sweeps."""

import importlib.machinery
import importlib.util
import os
import sys
import time
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN_DIR = os.path.join(REPO_ROOT, "bin")
if BIN_DIR not in sys.path:
    sys.path.insert(0, BIN_DIR)

from elevenmates_lib.announce import (  # noqa: E402
    announce_changes,
    describe_goal,
    score_at,
    take_placeholder,
)
from elevenmates_lib.constants import FULL_SWEEP_INTERVAL  # noqa: E402
from elevenmates_lib.providers.espn import (  # noqa: E402
    parse_espn_timeline,
    parse_goals,
)
from elevenmates_lib.providers.livescore import (  # noqa: E402
    ls_parse_goals,
    ls_parse_timeline,
)
from elevenmates_lib.storage import compact_player_name  # noqa: E402

_loader = importlib.machinery.SourceFileLoader(
    "elevenmates_cli", os.path.join(BIN_DIR, "elevenmates")
)
_spec = importlib.util.spec_from_loader("elevenmates_cli", _loader)
cli = importlib.util.module_from_spec(_spec)
_loader.exec_module(cli)


def make_match(home_score="0", away_score="0", goals=None, state="in"):
    return {
        "id": "m1",
        "league": "fra.1",
        "leagueName": "Ligue 1",
        "state": state,
        "clock": "10'",
        "statusShort": "10'",
        "home": {
            "id": "10",
            "abbr": "NIC",
            "name": "Nice",
            "color": "#ef2f24",
            "score": str(home_score),
        },
        "away": {
            "id": "20",
            "abbr": "PSG",
            "name": "PSG",
            "color": "#004170",
            "score": str(away_score),
        },
        "goals": list(goals or []),
    }


class TestEspnParsing(unittest.TestCase):
    def test_parse_goals_fallbacks_and_own_goal_flip(self):
        comp = {
            "details": [
                {
                    "scoringPlay": True,
                    "clock": {"displayValue": "8'"},
                    "team": {},
                    "athletesInvolved": [{"shortName": "M. Amoura", "team": {"id": "10"}}],
                    "ownGoal": False,
                },
                {
                    "scoringPlay": True,
                    "clock": {"displayValue": "22'"},
                    "team": {},
                    "athletesInvolved": [{"shortName": "X. Def", "team": {"id": "20"}}],
                    "ownGoal": True,
                },
                {
                    "scoringPlay": True,
                    "clock": {"displayValue": "35'"},
                    "team": {},
                    "athletesInvolved": [{"shortName": "Mystery"}],
                    "ownGoal": False,
                },
            ]
        }
        goals = parse_goals(comp, "10", "20")
        self.assertEqual([g["team"] for g in goals], ["10", "10", ""])

    def test_parse_espn_timeline_goals_cards_subs(self):
        payload = {
            "keyEvents": [
                {"clock": {"displayValue": ""}, "type": {"text": "Kickoff"}},
                {
                    "clock": {"displayValue": "8'"},
                    "type": {"text": "Goal"},
                    "team": {"id": "10"},
                    "scoringPlay": True,
                    "participants": [
                        {"athlete": {"displayName": "Mohamed Amoura"}},
                        {"athlete": {"displayName": "Jonathan Clauss"}},
                    ],
                },
                {
                    "clock": {"displayValue": "38'"},
                    "type": {"text": "Yellow Card"},
                    "team": {"id": "20"},
                    "participants": [{"athlete": {"displayName": "Trai Hume"}}],
                },
                {
                    "clock": {"displayValue": "60'"},
                    "type": {"text": "Substitution"},
                    "team": {"id": "10"},
                    "participants": [
                        {"athlete": {"displayName": "John McGinn"}},
                        {"athlete": {"displayName": "Johan Manzambi"}},
                    ],
                },
                {
                    "clock": {"displayValue": "82'"},
                    "type": {"text": "Red Card"},
                    "team": {"id": "20"},
                    "participants": [{"athlete": {"displayName": "Dawid Michalski"}}],
                },
            ]
        }
        events = parse_espn_timeline(payload, "10", "20")
        self.assertEqual([e["kind"] for e in events], ["goal", "yellow", "sub", "red"])
        self.assertEqual(events[0]["player"], "M. Amoura")
        self.assertEqual(events[0]["secondary"], "J. Clauss")
        self.assertEqual(events[2]["player"], "J. McGinn")
        self.assertEqual(events[2]["secondary"], "J. Manzambi")

    def test_compact_player_name(self):
        self.assertEqual(compact_player_name("Mohamed Amoura"), "M. Amoura")
        self.assertEqual(compact_player_name("M. Amoura"), "M. Amoura")
        self.assertEqual(compact_player_name("Evanilson"), "Evanilson")


class TestLiveScoreParsing(unittest.TestCase):
    def test_nested_incidents_inherit_parent_nm_and_sc_delta(self):
        board = {
            "Incs-s": {
                "1": [
                    {"Nm": 1, "Incs": [{"IT": 36, "Min": 15, "Pn": "J. Kowalski", "Sc": [1, 0]}]},
                    {"Incs": [{"IT": 39, "Min": 40, "Pn": "X. Defender", "Sc": [1, 1]}]},
                ]
            }
        }
        goals = ls_parse_goals(board)
        self.assertEqual([g["isHome"] for g in goals], [True, False])

    def test_ls_timeline_assists_and_cards(self):
        doc = {
            "Incs": {
                "1": [
                    {
                        "Nm": 1,
                        "Incs": [
                            {"IT": 36, "Min": 18, "Nm": 1, "Pn": "L. Nordås"},
                            {"IT": 63, "Min": 18, "Nm": 1, "Pn": "M. Berte"},
                        ],
                    },
                    {"IT": 43, "Min": 25, "Nm": 2, "Pn": "T. Romanczuk"},
                    {"IT": 45, "Min": 82, "Nm": 2, "Pn": "D. Michalski"},
                ]
            }
        }
        events = ls_parse_timeline(doc, {1: "ls-1", 2: "ls-2"})
        self.assertEqual([e["kind"] for e in events], ["goal", "yellow", "red"])
        self.assertEqual(events[0]["secondary"], "M. Berte")
        self.assertEqual(events[1]["team"], "ls-2")
        self.assertEqual(events[2]["team"], "ls-2")


class TestGoalAnnouncements(unittest.TestCase):
    def test_unknown_team_not_defaulted_to_away(self):
        old = make_match("0", "0", [])
        now = make_match("0", "0", [])
        goal = {"minute": "12'", "team": "", "scorer": "X", "ownGoal": False, "penalty": False}
        self.assertIsNone(describe_goal(now, goal, 1, old=old))

    def test_lagging_scoreboard_scores_correctly_and_no_duplicate(self):
        old = make_match("0", "0", [])
        goal = {"minute": "8'", "team": "10", "scorer": "M. Amoura", "ownGoal": False, "penalty": False}
        # Sweep 1: ESPN attaches goal detail before incrementing score
        lagging = make_match("0", "0", [goal])
        feed1 = announce_changes(
            {"matches": [old], "lastGoal": {"seq": 10}},
            [lagging],
            set(),
            {"m1"},
            set(),
            False,
            False,
            [],
        )
        self.assertEqual(len(feed1), 1)
        self.assertEqual(feed1[0]["team"], "NIC")
        self.assertEqual(feed1[0]["score"], "1-0")

        # Sweep 2: scoreboard catches up to 1-0 — must NOT fire a duplicate placeholder
        caught_up = make_match("1", "0", [goal])
        feed2 = announce_changes(
            {"matches": [lagging], "lastGoal": feed1[-1]},
            [caught_up],
            set(),
            {"m1"},
            set(),
            False,
            False,
            feed1,
        )
        self.assertEqual(len(feed2), 1)

    def test_take_placeholder_prefers_matching_team(self):
        feed = [
            {"matchId": "m1", "team": "NIC", "placeholder": True, "seq": 1},
            {"matchId": "m1", "team": "PSG", "placeholder": True, "seq": 2},
        ]
        idx, entry = take_placeholder(feed, "m1", "PSG")
        self.assertEqual(idx, 1)
        self.assertEqual(entry["seq"], 2)

    def test_score_at_multi_goal(self):
        goals = [
            {"minute": "8'", "team": "10"},
            {"minute": "31'", "team": "20"},
            {"minute": "32'", "team": "20"},
        ]
        m = make_match("1", "2", goals)
        self.assertEqual(score_at(m, goals, 0), "1-0")
        self.assertEqual(score_at(m, goals, 1), "1-1")
        self.assertEqual(score_at(m, goals, 2), "1-2")


class TestPartialLiveSweep(unittest.TestCase):
    def test_live_sweep_polls_only_active_leagues_until_interval_expires(self):
        now = time.time()
        leagues = ["eng.1", "fra.1", "fifa.world", "uefa.euro"]
        prev = {
            "fullSweepAt": now - 60,
            "leagues": {s: s for s in leagues},
            "matches": [make_match("1", "0", state="in")],
        }
        targets, partial, _ = cli.select_fetch_targets(leagues, prev, force=False, now=now)
        self.assertTrue(partial)
        self.assertEqual(targets, ["fra.1"])

        # Force always runs full sweep
        targets_f, partial_f, _ = cli.select_fetch_targets(leagues, prev, force=True, now=now)
        self.assertFalse(partial_f)
        self.assertEqual(targets_f, leagues)

        # After FULL_SWEEP_INTERVAL runs full sweep
        targets_t, partial_t, _ = cli.select_fetch_targets(
            leagues, prev, force=False, now=now + FULL_SWEEP_INTERVAL + 1
        )
        self.assertFalse(partial_t)
        self.assertEqual(targets_t, leagues)


if __name__ == "__main__":
    unittest.main()
