--[[ Salus Novus -- ChatFilter: drop chat lines that mention a blocked word.

One rule, asked for by Alex (2026-09-21): any chat line whose text or sender
contains "asmon" (case-insensitive, substring) never reaches a chat frame.
The words live in ns.db.chatFilter.words so more can follow the same path.

Mechanics: ChatFrame_AddMessageEventFilter runs a filter for every chat
frame before the line is added; returning true swallows it. Filters are
installed once at load and read the setting on each call, so the Settings
toggle needs no re-registration. Chat text is never a secret value on this
client, but the guards below make a secret line pass through untouched
rather than throw inside Blizzard's chat handler.
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

local function Enabled()
    local o = O()
    return o and o.enabled and true or false
end

--- The blocked words, lower-cased, skipping anything that is not a
-- non-empty string (a corrupt saved list must not throw per chat line).
local function Words()
    local o = O()
    local list = o and o.words
    if type(list) ~= "table" then return {} end
    local out = {}
    for _, w in ipairs(list) do
        if type(w) == "string" and w ~= "" then out[#out + 1] = w:lower() end
    end
    return out
end

--- True when `text` contains any blocked word. Plain substring, case-
-- insensitive, so "ASMONGOLD", "asmon's stream" and "xXasmonXx" all match.
function C.Matches(text)
    if type(text) ~= "string" or ns.IsSecret(text) then return false end
    local lower = text:lower()
    for _, w in ipairs(Words()) do
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
