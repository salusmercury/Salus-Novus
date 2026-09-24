--[[ Salus Novus -- ChatFilter: drop chat lines that mention a blocked word.

Alex (2026-09-21): any chat line whose text or sender contains one of a set
of words (case-insensitive, substring) never reaches a chat frame. The set
is the user's to edit on the Chat tab under Quality of Life; it ships with
asmon, olympus, trump, republican and democrat.

Storage: ns.db.chatFilter.words is a SET, word -> true. A removed default
is stored as FALSE rather than deleted, because CopyDefaults re-seeds any
nil key on the next load and the word would come back. Only `true` counts.

Mechanics: ChatFrame_AddMessageEventFilter runs a filter for every chat
frame before the line is added; returning true swallows it. Filters are
installed once at load and read the setting on each call, so the module
switch and the word list need no re-registration. Chat text is never a secret
value on this client, but the guards below make a secret line pass through
untouched rather than throw inside Blizzard's chat handler.
]]

local _, ns = ...

local C = {}
ns.ChatFilter = C

-- Every event a player-written line can arrive on (system lines excluded:
-- a blocked word in a quest reward or a loot roll is not chatter).
C.EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local function O() return ns.db and ns.db.chatFilter end

-- On/off is the Quality of Life module's master switch.
local function Enabled()
    return ns.ModuleOn("qol") and true or false
end

--- A word as stored: trimmed, lower-cased; nil when nothing is left.
function C.Normalize(text)
    if type(text) ~= "string" or ns.IsSecret(text) then return nil end
    local w = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if w == "" then return nil end
    return w
end

--- The active words, sorted, skipping anything that is not word -> true
-- (a corrupt saved set must not throw per chat line). An older array
-- form ({ "asmon" }) still reads.
function C.List()
    local o = O()
    local set = o and o.words
    if type(set) ~= "table" then return {} end
    local out = {}
    for k, v in pairs(set) do
        if type(k) == "string" and v == true and k ~= "" then
            out[#out + 1] = k:lower()
        elseif type(k) == "number" and type(v) == "string" and v ~= "" then
            out[#out + 1] = v:lower()
        end
    end
    table.sort(out)
    return out
end

--- Add a word; returns the stored form, or nil when empty or already there.
function C.AddWord(text)
    local w = C.Normalize(text)
    local o = O()
    if not w or not o then return nil end
    if type(o.words) ~= "table" then o.words = {} end
    if o.words[w] == true then return nil end
    o.words[w] = true
    return w
end

--- Remove a word. FALSE, not nil: see the header.
function C.RemoveWord(w)
    local o = O()
    if not o or type(o.words) ~= "table" or type(w) ~= "string" then return end
    o.words[w] = false
end

--- True when `text` contains any blocked word. Plain substring, case-
-- insensitive, so "ASMONGOLD", "asmon's stream" and "xXasmonXx" all match.
function C.Matches(text)
    if type(text) ~= "string" or ns.IsSecret(text) then return false end
    local lower = text:lower()
    for _, w in ipairs(C.List()) do
        if lower:find(w, 1, true) then return true end
    end
    return false
end

--- Should this line be swallowed? The message body and the sender's name
-- are both checked: a player called "Asmonfan" saying "hi" is still noise.
function C.ShouldBlock(msg, author)
    if not Enabled() then return false end
    return C.Matches(msg) or C.Matches(author)
end

--- The filter Blizzard calls: (chatFrame, event, msg, author, ...).
-- Returning true drops the line; returning false passes it unchanged.
function C.Filter(_, _, msg, author, ...)
    local ok, block = pcall(C.ShouldBlock, msg, author)
    if ok and block then return true end
    return false, msg, author, ...
end

local installed = false
local function Install()
    if installed then return end
    if type(ChatFrame_AddMessageEventFilter) ~= "function" then return end
    for _, ev in ipairs(C.EVENTS) do
        ChatFrame_AddMessageEventFilter(ev, C.Filter)
    end
    installed = true
end
C.Install = Install                                  -- test seam
function C.IsInstalled() return installed end        -- test seam

table.insert(ns.OnLoad, Install)
