--[[ Salus Novus -- Fonts: the font list and the one safe way to set a font.

MerkUI/Fonts.lua without LibSharedMedia (no LibStub on Forever). The
load-bearing fact (MerkUI landmine 23): SetFont with a bad path does NOT
error and does NOT clear the old font -- it returns false and the string
draws nothing once re-rendered. So the test is the RETURN VALUE; pcall's ok
and GetFont() both stay truthy and detect nothing.
]]

local _, ns = ...

-- Blizzard's own font files, each probed once for presence (a locale may
-- lack one). MEASURED on Forever (2026-09-19): an addon font file's FIRST
-- SetFont returns false while the client loads it in the background, yet
-- the font then works (Alex runs the whole UI in Bazooka). So the probe
-- is a presence check for Blizzard's files only; addon fonts from
-- LibSharedMedia are listed unprobed and the picker re-applies its rows
-- after a moment so their names draw.
local BUILTIN_FONTS = {
    { name = "Friz Quadrata (default)", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",            path = "Fonts\\ARIALN.TTF"   },
    { name = "Morpheus",                path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri",                  path = "Fonts\\SKURRI.TTF"   },
    { name = "2002",                    path = "Fonts\\2002.ttf"     },
    { name = "2002 Bold",               path = "Fonts\\2002B.ttf"    },
    { name = "Nimrod",                  path = "Fonts\\NIM_____.ttf" },
    { name = "AR Hei",                  path = "Fonts\\ARHei.ttf"    },
    { name = "AR Kai (chat)",           path = "Fonts\\ARKai_C.ttf"  },
    { name = "AR Kai (text)",           path = "Fonts\\ARKai_T.ttf"  },
    { name = "K Damage",                path = "Fonts\\K_Damage.ttf" },
    { name = "K Pagetext",              path = "Fonts\\K_Pagetext.ttf" },
    { name = "Friz Quadrata (Cyrillic)", path = "Fonts\\FRIZQT___CYR.TTF" },
    { name = "Morpheus (Cyrillic)",     path = "Fonts\\MORPHEUS_CYR.TTF" },
    { name = "Skurri (Cyrillic)",       path = "Fonts\\SKURRI_CYR.TTF" },
    { name = "bLEI00D",                 path = "Fonts\\bLEI00D.ttf"  },
    { name = "bHEI00M",                 path = "Fonts\\bHEI00M.ttf"  },
    { name = "bHEI01B",                 path = "Fonts\\bHEI01B.ttf"  },
    { name = "bKAI00M",                 path = "Fonts\\bKAI00M.ttf"  },
    { name = "bLEI01B",                 path = "Fonts\\bLEI01B.ttf"  },
}

-- Does the client load this font? Asked once per path on a hidden string
-- and remembered: the answer is the ONLY thing that keeps a blank font out
-- of the picker (a rejected path returns false and draws nothing).
local usable = {}
local probeFS
local function Usable(path)
    if type(path) ~= "string" or path == "" then return false end
    local known = usable[path]
    if known ~= nil then return known end
    if not probeFS then
        probeFS = UIParent:CreateFontString(nil, "OVERLAY")
        probeFS:Hide()
    end
    local ok, applied = pcall(probeFS.SetFont, probeFS, path, 12, "")
    usable[path] = (ok and applied ~= false) and true or false
    return usable[path]
end
ns.FontUsable = Usable

-- FRIZQT does not exist on zhCN/zhTW/koKR: ask the client for its own default.
local function StockFont()
    return (type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
end
ns.StockFont = StockFont

-- LibSharedMedia, when some addon on the client carries it (a font pack
-- like SharedMediaAdditionalFonts). Resolved lazily, never captured at
-- file scope: an addon that loads after Salus Novus can register it later.
local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end
ns.LSM = LSM

--- { {name, path}, ... }, leading with the client's own default, then
-- every font the client will actually load: LibSharedMedia's (when an
-- addon registers any and the client accepts the files) and Blizzard's.
-- Second return: whether any LibSharedMedia font made the list.
function ns.GetFonts()
    local list = { { name = "Game default", path = StockFont() } }
    local seen = { [StockFont()] = true }
    local fromLSM = false
    local function Add(name, path)
        if type(path) == "string" and not seen[path] and Usable(path) then
            seen[path] = true
            list[#list + 1] = { name = name, path = path }
            return true
        end
        return false
    end
    -- LibSharedMedia's fonts are listed WITHOUT the probe: on Forever the
    -- probe rejected Prototype while the picker drew it (Alex uses it), so
    -- the probe is not the truth about addon files. Blizzard's set is
    -- probed only for presence (a locale may lack a file).
    local lsm = LSM()
    if lsm and lsm.List and lsm.HashTable then
        local names = lsm:List("font")
        local paths = lsm:HashTable("font")
        for _, name in ipairs(names or {}) do
            local path = paths and paths[name]
            if type(path) == "string" and not seen[path] then
                seen[path] = true
                list[#list + 1] = { name = name, path = path }
                fromLSM = true
            end
        end
    end
    for i = 1, #BUILTIN_FONTS do Add(BUILTIN_FONTS[i].name, BUILTIN_FONTS[i].path) end
    return list, fromLSM
end

-- Memoised: called once per SetFont, dozens of times per layout. Only
-- ApplyAll can change the font, so that is where the cache is dropped.
local fontCache
function ns.InvalidateFontCache() fontCache = nil end

-- The picked font, or the game's default. One picker, no on/off switch
-- (Alex: "Use a custom font" was redundant).
function ns.ActiveFont()
    if fontCache then return fontCache end
    local opts = ns.db and ns.db.font
    local path = opts and opts.path
    -- The Quality of Life module off = the stock font everywhere.
    if ns.ModuleOn and not ns.ModuleOn("qol") then path = nil end
    fontCache = (type(path) == "string" and path ~= "") and path or StockFont()
    return fontCache
end

-- Every fontstring that follows the global font, with the size and flags
-- it was set with, so a font change re-fonts ALL of them -- the windows'
-- titles and rows as much as the anchors (Alex: "absolutely everything").
-- Weak keys: a discarded fontstring leaves on its own. A string set with an
-- explicit path (the picker's previews) is not enrolled: it is showing a
-- font, not using one.
local following = setmetatable({}, { __mode = "k" })
ns._following = following
local lastApplied

ns.fontFellBack = 0
--- Set a font and CHECK it took. Falls back through the configured font,
-- the stock font, then each builtin, never retrying a path already tried.
function ns.SetFontSafe(fs, size, flags, path)
    if not fs then return end
    flags = flags or "OUTLINE"
    if path == nil then
        -- Reuse the spec: Bars.Refresh calls this twice per bar per refresh.
        local spec = following[fs]
        if spec then spec.size, spec.flags = size, flags else following[fs] = { size = size, flags = flags } end
    else
        following[fs] = nil
    end
    local want = path or ns.ActiveFont()
    local ok, applied = pcall(fs.SetFont, fs, want, size, flags)
    if ok and applied ~= false then return end
    ns.fontFellBack = (ns.fontFellBack or 0) + 1
    ns.fontLastBad = tostring(want)
    ns.fontWarned = ns.fontWarned or {}
    -- The first SetFont of an addon font returns false while the client
    -- loads it in the background (measured), so a global-font failure is
    -- retried once a second later, and only a failure of THAT retry warns.
    -- An explicit-path call (the picker's previews) never warns: sixty
    -- warnings at once is noise.
    if path == nil and not ns.fontWarned[ns.fontLastBad] then
        ns.fontWarned[ns.fontLastBad] = true
        local bad = ns.fontLastBad
        C_Timer.After(1, function()
            if ns.ActiveFont() ~= bad then return end
            local probe = ns._fontProbe or UIParent:CreateFontString(nil, "OVERLAY")
            ns._fontProbe = probe
            local okR, appliedR = pcall(probe.SetFont, probe, bad, 12, "")
            if okR and appliedR ~= false then
                ns.RefontAll(true)
            else
                ns.Print("the client rejected the font \"" .. bad .. "\"; using the stock font instead.")
            end
        end)
    end
    if path then
        local ok2, applied2 = pcall(fs.SetFont, fs, ns.ActiveFont(), size, flags)
        if ok2 and applied2 ~= false then return end
    end
    local tried = { [want] = true }
    local stock = StockFont()
    if not tried[stock] then
        tried[stock] = true
        local okS, appliedS = pcall(fs.SetFont, fs, stock, size, flags)
        if okS and appliedS ~= false then return end
    end
    for i = 1, #BUILTIN_FONTS do
        local p = BUILTIN_FONTS[i].path
        if not tried[p] then
            tried[p] = true
            local okB, appliedB = pcall(fs.SetFont, fs, p, size, flags)
            if okB and appliedB ~= false then return end
        end
    end
    ns.fontAllFailed = (ns.fontAllFailed or 0) + 1
end

--- Re-font everything that follows the global font. Only when the active
-- font actually changed: ApplyAll runs on every slider step.
function ns.RefontAll(force)
    local want = ns.ActiveFont()
    if not force and want == lastApplied then return end
    lastApplied = want
    local n = 0
    for fs, spec in pairs(following) do
        if fs.SetFont then
            ns.SetFontSafe(fs, spec.size, spec.flags)
            n = n + 1
        end
    end
    return n
end
ns.RegisterApply(function() ns.RefontAll() end, "Fonts")

-- The whole game UI. Blizzard draws its frames, chat, tooltips, quest
-- text and numbers through named font objects; re-fonting those changes
-- everything the default UI shows (addons with their own font settings
-- and engine-drawn combat text excepted). Sizes and flags are kept; the
-- original font of each object is remembered so the switch can be turned
-- back off without a reload. Not protected, so no taint.
local UI_FONT_OBJECTS = {
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalSmall2", "GameFontNormalMed1", "GameFontNormalMed2",
    "GameFontNormalMed3", "GameFontNormalLarge", "GameFontNormalLarge2", "GameFontNormalHuge", "GameFontNormalHuge2",
    "GameFontNormalHuge3", "GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightSmall2",
    "GameFontHighlightMedium", "GameFontHighlightLarge", "GameFontHighlightLarge2", "GameFontHighlightHuge",
    "GameFontDisable", "GameFontDisableSmall", "GameFontDisableLarge", "GameFontGreen", "GameFontGreenSmall",
    "GameFontRed", "GameFontRedSmall", "GameFontRedLarge", "GameFontWhite", "GameFontWhiteSmall", "GameFontBlack",
    "GameFontBlackSmall", "GameFontDarkGraySmall", "GameFontNormalLeft", "GameFontNormalLeftGreen",
    "GameFontNormalLeftRed", "GameFontNormalLeftYellow", "GameFontNormalLeftGrey",
    "GameTooltipText", "GameTooltipTextSmall", "GameTooltipHeaderText", "GameTooltipHeader",
    "ChatFontNormal", "ChatFontSmall", "ChatBubbleFont",
    "NumberFontNormal", "NumberFontNormalSmall", "NumberFontNormalSmallGray", "NumberFontNormalLarge",
    "NumberFontNormalHuge", "NumberFontNormalRight", "NumberFontNormalRightRed", "NumberFontNormalRightYellow",
    "NumberFont_Shadow_Small", "NumberFont_Shadow_Med", "NumberFont_Shadow_Large", "NumberFont_OutlineThick_Mono_Small",
    "NumberFont_Outline_Med", "NumberFont_Outline_Large", "NumberFont_Outline_Huge",
    "QuestFont", "QuestFontNormalSmall", "QuestFontHighlight", "QuestTitleFont", "QuestTitleFontBlackShadow",
    "QuestFont_Large", "QuestFont_Huge", "QuestFont_Shadow_Huge", "QuestFont_Super_Huge", "QuestFont_Enormous",
    "MailFont_Large", "MailTextFontNormal", "InvoiceFont_Med", "InvoiceFont_Small",
    "SystemFont_Small", "SystemFont_Med1", "SystemFont_Med2", "SystemFont_Med3", "SystemFont_Large",
    "SystemFont_Huge1", "SystemFont_Huge2", "SystemFont_Shadow_Small", "SystemFont_Shadow_Med1",
    "SystemFont_Shadow_Med2", "SystemFont_Shadow_Med3", "SystemFont_Shadow_Large", "SystemFont_Shadow_Large2",
    "SystemFont_Shadow_Huge1", "SystemFont_Shadow_Huge2", "SystemFont_Shadow_Huge3", "SystemFont_Shadow_Outline_Huge2",
    "SystemFont_Outline_Small", "SystemFont_Outline", "SystemFont_OutlineThick_Huge2", "SystemFont_OutlineThick_Huge4",
    "SystemFont_OutlineThick_WTF", "SystemFont_Tiny", "SystemFont_Tiny2", "SystemFont_InverseShadow_Small",
    "SystemFont_Shadow_Small2", "SystemFont_Shadow_Med1_Outline", "SystemFont_Shadow_Huge1_Outline",
    "SystemFont_Shadow_Med3_Outline", "SystemFont_World", "SystemFont_World_ThickOutline", "SystemFont_NamePlate",
    "SystemFont_NamePlateFixed", "SystemFont_LargeNamePlate", "SystemFont_LargeNamePlateFixed",
    "ZoneTextFont", "SubZoneTextFont", "PVPInfoTextFont", "ErrorFont", "TextStatusBarText", "CombatTextFont",
    "Game11Font", "Game12Font", "Game13Font", "Game13FontShadow", "Game15Font", "Game16Font", "Game18Font",
    "Game20Font", "Game24Font", "Game27Font", "Game30Font", "Game32Font", "Game36Font", "Game40Font", "Game42Font",
    "Game46Font", "Game48Font", "Game48FontShadow", "Game60Font", "Game72Font", "Game120Font",
    "FriendsFont_Normal", "FriendsFont_Small", "FriendsFont_Large", "FriendsFont_UserText",
    "AchievementFont_Small", "ReputationDetailFont", "SpellFont_Small", "Tooltip_Med", "Tooltip_Small",
    "GameFont_Gigantic", "DestinyFontLarge", "DestinyFontHuge", "CoreAbilityFont", "BossEmoteNormalHuge",
}
local uiOriginal = {}          -- name -> { path, size, flags } before we touched it
local uiApplied                -- the font path the UI currently carries, or nil
local everApplied = {}         -- every path Salus Novus has ever put on the UI
ns._uiOriginal = uiOriginal

-- Every font object the client knows, when it will tell us (the global
-- GetFonts lists them all: the objective tracker's, the nameplates', the
-- lot), else the hand list above. Chat frames are added by name: the chat
-- settings code sets their font directly, over the font object.
local function UIFontTargets()
    local names = {}
    local seen = {}
    local function Take(name)
        if type(name) == "string" and not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    local ok, list = pcall(function() return _G.GetFonts and _G.GetFonts() end)
    if ok and type(list) == "table" then
        for _, name in ipairs(list) do Take(name) end
    end
    for _, name in ipairs(UI_FONT_OBJECTS) do Take(name) end
    -- Every font object in the global table, whoever made it: the client's
    -- enumeration may be absent on this build, and load-on-demand Blizzard
    -- addons (Professions, the objective tracker's pieces) create their own
    -- objects after login. Walked once per apply; cheap enough at login.
    for name, v in pairs(_G) do
        if type(name) == "string" and type(v) == "table" and not seen[name] and rawget(v, 0) ~= nil
            and v.GetObjectType and v.SetFont and v.GetFont then
            local okT, t = pcall(v.GetObjectType, v)
            if okT and t == "Font" then Take(name) end
        end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = "ChatFrame" .. i
        if not seen[f] then seen[f] = true; names[#names + 1] = f end
        local e = "ChatFrame" .. i .. "EditBox"
        if not seen[e] then seen[e] = true; names[#names + 1] = e end
    end
    return names
end

function ns.ApplyUIFont(on, again)
    local want = on and ns.ActiveFont() or nil
    if want == uiApplied and not again then return 0 end
    local n = 0
    for _, name in ipairs(UIFontTargets()) do
        local obj = _G[name]
        if type(obj) == "table" and obj.GetFont and obj.SetFont then
            if want then
                local ok, path, size, flags = pcall(obj.GetFont, obj)
                if ok and type(path) == "string" and not ns.IsSecret(path) then
                    -- An object first seen already wearing a font Salus Novus
                    -- applied (a load-on-demand frame inheriting from
                    -- GameFontNormal) must not remember THAT as its original,
                    -- or turning the switch off would pin it to our font.
                    if not uiOriginal[name] then
                        uiOriginal[name] = { everApplied[path] and StockFont() or path, size, flags }
                    end
                    everApplied[want] = true
                    local o = uiOriginal[name]
                    local okS, applied = pcall(obj.SetFont, obj, want, o[2] or size, o[3] or flags or "")
                    if okS and applied ~= false then n = n + 1 end
                end
            elseif uiOriginal[name] then
                local o = uiOriginal[name]
                pcall(obj.SetFont, obj, o[1], o[2], o[3] or "")
                uiOriginal[name] = nil
                n = n + 1
            end
        end
    end
    uiApplied = want
    return n
end

-- A chat window's font size change re-sets that frame's font from the
-- chat settings, dropping ours: put it back after each such call.
if type(hooksecurefunc) == "function" and type(_G.FCF_SetChatWindowFontSize) == "function" then
    hooksecurefunc("FCF_SetChatWindowFontSize", function(_, chatFrame)
        if not uiApplied or not chatFrame or not chatFrame.GetFont then return end
        local ok, _, size, flags = pcall(chatFrame.GetFont, chatFrame)
        if ok then pcall(chatFrame.SetFont, chatFrame, uiApplied, size, flags or "") end
    end)
end
local function WholeUIWanted()
    return ns.db and ns.db.font and ns.db.font.wholeUI and ns.ModuleOn("qol") and true or false
end
ns.WholeUIFontWanted = WholeUIWanted
ns.RegisterApply(function()
    ns.ApplyUIFont(WholeUIWanted())
end, "Whole-UI font")

-- A Blizzard addon loading on demand (Professions, Collections, the
-- Encounter Journal...) brings font objects of its own: font them too.
-- Objects already fonted keep their remembered original.
ns.On("ADDON_LOADED", function(name)
    if name == "SalusNovus" then return end
    if WholeUIWanted() then ns.ApplyUIFont(true, true) end
end)
ns.On("PLAYER_ENTERING_WORLD", function()
    if WholeUIWanted() then ns.ApplyUIFont(true, true) end
    -- Strings set once during loading (anchor captions) may have caught
    -- the first-load false: the whole following set gets the font again.
    ns.RefontAll(true)
end)

-- /sn fonts: ask the client about every listed font. For each: what
-- SetFont returned, what GetFont reads back, and the width of a sample
-- string (0 = it renders nothing). A diagnostic, printed compactly.
ns.Commands.fonts = function()
    local list, fromLSM = ns.GetFonts()
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    -- A fontstring with no font yet throws on SetText: give it the stock
    -- font first, and set the text again after every SetFont.
    pcall(probe.SetFont, probe, StockFont(), 14, "")
    probe:SetText("Sample Abc 123")
    local okN, blank, bad = 0, {}, {}
    for _, f in ipairs(list) do
        local ok, applied = pcall(probe.SetFont, probe, f.path, 14, "")
        local w = 0
        if ok and applied ~= false then
            probe:SetText("Sample Abc 123")
            w = probe:GetStringWidth() or 0
            if w > 0 then okN = okN + 1 else blank[#blank + 1] = f.name end
        else
            bad[#bad + 1] = f.name
        end
    end
    ns.Print(("fonts: %d listed (%s), %d render, %d accepted but blank, %d rejected"):format(
        #list, fromLSM and "LibSharedMedia" or "builtins", okN, #blank, #bad))
    if #blank > 0 then
        ns.Print("  blank: " .. table.concat(blank, ", ", 1, math.min(#blank, 12)) .. (#blank > 12 and (" ... +" .. (#blank - 12)) or ""))
        local path
        for _, f in ipairs(list) do if f.name == blank[1] then path = f.path end end
        ns.Print("  first blank path: " .. tostring(path))
    end
    if #bad > 0 then
        ns.Print("  rejected: " .. table.concat(bad, ", ", 1, math.min(#bad, 12)) .. (#bad > 12 and (" ... +" .. (#bad - 12)) or ""))
    end
end
