# Salus Novus

A boss-warning addon for **WoW Forever** (the retail 12.x client on vanilla
content), built from your own combat logs. `/sn` opens it.

What it does
- **Boss Visualizer**: every dungeon and raid boss, with the casts observed in
  your logs laid out on time lanes; click an ability card to rename it, give it
  a colour, limit it to roles, or choose which anchors show it; click a lane to
  place a reminder.
- **Anchors** (all movable, all previewed on their settings page): Bars, Ability
  Queue, Ability Preview, Messages, Health Bars (the boss's health with a
  marker per health-triggered ability), Reminders.
- **Whole-UI font**: one font for the addon and, optionally, the whole game UI.

Nothing is predicted beyond what the logs recorded. The client keeps most live
values secret on Forever, so timings come from the log files, not from combat
events. See `wow_forever_notes.md` for what the client does and does not allow.

Install
- Easiest: download `SalusNovus-<version>.zip` from the Releases page and
  extract it into `World of Warcraft\_classic_beta_\Interface\AddOns\`
  (it unpacks as a `SalusNovus` folder).
- From source: copy the `salusnovus` folder into `Interface\AddOns\` and
  rename it `SalusNovus`, or run
  `python install_probe.py --addon SalusNovus --install wow_classic_beta`.
- `python make_release.py` builds the release zip into `dist/`. Pushing a tag
  `vX.Y.Z` makes GitHub build it and publish a Release automatically.

Data
- `build_salusnovus_data.py` regenerates `salusnovus/Data/*.lua` from
  `forever_logs/` (parsed combat logs), `forever_instances.json` and
  `forever_creatures.json`. Rerun it after every logged run.

Tests
- `python salusnovus_test/runner.py` runs the suite against a mock client
  (`merkui_test/wow_mock.lua`, real Lua 5.1 via lupa).
- `python salusnovus_test/mutate.py` is the red-green sweep: every listed
  guarantee is broken in a copy and the suite must notice.
