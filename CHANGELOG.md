# Changelog

## 1.1.0 - 2026-09-20

- Ekstraklasa. ESPN carries no Polish football at all, so `pol.1` is served by
  Sofascore instead, folded into the same shape as everything else: scorers,
  the running minute, club colours and the match numbers all read the same.
- The plugin id is now `elevenmates`, without the vendor prefix. An install
  under the old id has to be added again; the settings file and the score cache
  are untouched, so nothing picked is lost.
- The README lists every competition on the picker with its slug.

Goal alerts, which were losing some of what they were meant to announce:

- Two goals inside one refresh interval are two celebrations. The cache now
  carries a short feed of goals rather than only the newest, and the bar takes
  them in turn - briefly when there is a queue behind, at leisure when there is
  not. Before, the first of them was simply dropped.
- Each goal is reported at the score it was scored at, not at the score the
  last one left behind.
- A fixture about to kick off no longer waits out the whole idle interval. The
  widget learns a match is live only by sweeping, so a kick-off just after one
  went unseen for twenty minutes and its first goals arrived late and together.
- A score that moves without a scoring play behind it now reaches the bar as
  well. It used to raise a desktop notification and nothing else, so with
  alerts switched off the one case the bar flash exists to cover was the one
  case it missed.
- The goal line on the bar is rebuilt properly for each goal. It was named in
  the code but never actually named in the layout, so every goal threw a
  reference error partway through announcing it.
- The staleness guard clears the longest gap the widget will actually leave.
  With a stretched idle interval it could be shorter than the wait it was
  meant to survive, which would have silently disabled goal alerts.
- Bells and the pin are forgotten once their match leaves today's card, instead
  of piling up in the config file for every Saturday ever watched.
- `--config` is honoured before the subcommand as well as after it. Before, it
  was silently ignored there, so `elevenmates --config mine.json config set`
  read and then rewrote the real config file.

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
