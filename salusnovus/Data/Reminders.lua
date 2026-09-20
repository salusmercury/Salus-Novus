-- Mercury shipped reminders. Deliberately EMPTY: reminders are yours,
-- placed on the Boss Visualizer (Alex, 2026-09-19). The table stays so a
-- future release could seed some; a shipped one would carry an id of the
-- form "default:N" and could be hidden per id (MercuryDB.options.reminders.hidden).
--
-- Record shape (the same the anchor stores for your own reminders):
--   id, encounterID, trigger = "pull" | "time" | "cast" | "emote",
--   arg (seconds for time, a word for emote), text, lead, sound

local _, ns = ...

ns.DefaultReminders = {}
