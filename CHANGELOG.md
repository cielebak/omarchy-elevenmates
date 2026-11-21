# Changelog

## 1.1.0 - 2026-11-21

- Match timeline in expanded cards: goals with assists, yellow and red cards,
  missed penalties, and a FotMob-style `Key | All` toggle to reveal
  substitutions (`↑ in / ↓ out`). Both timeline and stat meters align directly
  under the match score without clipping names.
- Goal attribution and alert fixes: missing `team.id` (ESPN) or nested `Nm`
  (LiveScore) no longer defaults to the away side, and a lagging scoreboard no
  longer announces `0-0` or fires a duplicate placeholder alert.
- Faster live refresh: during live play only competitions with matches today
  are polled (with a full sweep every 15 minutes), lowering the live refresh
  floor (defaults now `25 s` live / `12 min` idle).
- Optional Stremio / MPV integration (off by default in **SETTINGS**): adds a
  **STREMIO** tab, live bridge status/expiry notices, and one-click `▶` stream
  playback in MPV or Stremio via the bundled zero-dependency `stremio-bridge/`.
- Modularized Python backend (`bin/elevenmates_lib/`), split QML tabs
  (`SettingsTab.qml`, `StremioTab.qml`), and added `tests/test_elevenmates.py`.

## 1.0.1 - 2026-10-16

- Ekstraklasa works again. Sofascore started refusing every request that does
  not come from a browser, so the Polish row showed an HTTP 403 error instead
  of the round; Ekstraklasa now comes from LiveScore, still without an account
  or a key.
- A goal whose scorer is published a moment after the score moves now gets its
  name once it is out, rather than staying anonymous for the rest of the match.
- Ekstraklasa clubs followed before this release need following again: the new
  source numbers them differently.

## 1.0.0 - 2026-09-20

First release.

- Live scores in the bar for the competitions and clubs you follow.
- One match on the bar at a time, picked with the eye on its row, or chosen
  automatically when nothing is picked - unless the bar is set to
  `Picked match only`, which carries nothing until an eye says otherwise.
- Goal alerts per match with the bell, hidden on the row the eye already
  carries because that match is alerted on regardless, and on a match that has
  already been played.
- A goal pulses the widget in the scoring club's colour and names the scorer.
  Two goals inside one refresh interval are two celebrations: the bar takes
  them in turn, each at the score it was actually scored at.
- Expandable match card: scorers with minutes, then possession, shots, shots on
  target, corners, cards and fouls, each with a meter.
- 44 competitions on the picker. Forty-three come from ESPN; Ekstraklasa comes
  from Sofascore, because ESPN publishes no Polish football at all. Neither
  needs an account or a key.
- Today's fixtures only, plus anything still being played.
- Halftime, full time, extra time and shootouts read as themselves rather than
  as a running clock.
- Requires Omarchy 4.0 or newer.
