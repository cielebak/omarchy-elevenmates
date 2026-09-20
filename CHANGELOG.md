# Changelog

## 1.1.0 - 2026-09-20

- Ekstraklasa. ESPN carries no Polish football at all, so `pol.1` is served by
  Sofascore instead, folded into the same shape as everything else: scorers,
  the running minute, club colours and the match numbers all read the same.
- The plugin id is now `elevenmates`, without the vendor prefix. An install
  under the old id has to be added again; the settings file and the score cache
  are untouched, so nothing picked is lost.
- The README lists every competition on the picker with its slug.

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
- Expandable match card: scorers with minutes, then possession, shots, shots on
  target, corners, cards and fouls, each with a meter.
- Today's fixtures only, plus anything still being played.
- Halftime, full time, extra time and shootouts read as themselves rather than
  as a running clock.
- Requires Omarchy 4.0 or newer.
