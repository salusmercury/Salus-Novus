--[[ Salus Novus -- Auction: the scanner, the price store, the sniper's engine.

Measured on Forever (/sn probe ah, 2026-10-05): the full scan
(ReplicateItems) never answers here, but an EMPTY BROWSE search paged to
the end is the whole auction house -- 7,027 items over 15 pages in 9 s,
one row per item: its key, how many are listed, the cheapest price. That
is the scan.

  A.Scan()        one browse pass (on opening the AH, if set, and the button)
  prices          SalusNovusDB.ah[realm-faction].items[key] =
                  { id, lvl, sfx, m = cheapest, q = listed, t = last seen, n = scan #,
                    d = { [day] = { lo, q } } }   (14 days kept)
  A.Snipes()      the last scan's items listed below what a vendor pays
                  (ns.VendorSell, from the client's item table), best first
  A.Select(id)    that item's live listings (a search), and what of it
                  is under vendor
  A.Buy()         from a click only: an item auction -> PlaceBid; a
                  commodity -> StartCommoditiesPurchase, the client quotes,
                  and A.Confirm() (a second click) buys -- only while the
                  quote is still under vendor

Nothing buys on its own: every purchase call runs inside the player's click
(the client requires it, and it's the line between a tool and a bot).
]]

local _, ns = ...

local A = {}
ns.Auction = A

local Num, Str = ns.Num, ns.Str
local DAY = 86400
local KEEP_DAYS = 14
local MAX_PAGES = 60

local function O() return ns.db and ns.db.auction end
function A.Enabled()
    local o = O()
    return o and o.enabled ~= false and ns.ModuleOn("qol") and true or false
end
local function AH() return rawget(_G, "C_AuctionHouse") end
local function Now() return (GetTime and GetTime()) or 0 end
local function Epoch() return (time and time()) or 0 end

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

function A.IsOpen()
    local f = rawget(_G, "AuctionHouseFrame")
    if not f then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown == true
end

local function Ready()
    local ah = AH()
    local ok, r = Call(ah and ah.IsThrottledMessageSystemReady)
    return not (ok and r == false)
end

-- ------------------------------------------------------------ store

function A.RealmKey()
    local okR, realm = Call(rawget(_G, "GetRealmName"))
    local okF, faction = Call(rawget(_G, "UnitFactionGroup"), "player")
    realm = okR and Str(realm) or nil
    faction = okF and Str(faction) or nil
    if not realm or realm == "" then return nil end
    return realm .. "-" .. (faction or "?")
end

function A.Store()
    local rk = A.RealmKey()
    if not rk or type(SalusNovusDB) ~= "table" then return nil end
    SalusNovusDB.ah = SalusNovusDB.ah or {}
    local s = SalusNovusDB.ah[rk]
    if type(s) ~= "table" then s = { items = {} }; SalusNovusDB.ah[rk] = s end
    if type(s.items) ~= "table" then s.items = {} end
    return s
end

--- The key an item is stored under: its ID, plus the suffix for gear "of the Bear".
function A.Key(id, sfx)
    if Num(sfx) and sfx > 0 then return id .. ":" .. sfx end
    return tostring(id)
end

--- One browse row into the store.
local function Record(items, row, now, day, seq)
    if type(row) ~= "table" then return nil end
    local k = row.itemKey
    if type(k) ~= "table" or not Num(k.itemID) then return nil end
    local m, q = row.minPrice, row.totalQuantity
    if not (Num(m) and m > 0) then return nil end
    local key = A.Key(k.itemID, k.itemSuffix)
    local rec = items[key]
    if type(rec) ~= "table" then rec = {}; items[key] = rec end
    rec.id, rec.lvl, rec.sfx = k.itemID, Num(k.itemLevel) and k.itemLevel or 0, Num(k.itemSuffix) and k.itemSuffix or 0
    -- s = the scan that saw it last; n = the last FINISHED scan that saw it
    -- (set by Finish): a scan cut short leaves the finished one's list whole.
    rec.m, rec.q, rec.t, rec.s = m, Num(q) and q or 0, now, seq
    rec.d = type(rec.d) == "table" and rec.d or {}
    local today = rec.d[day]
    if type(today) ~= "table" then rec.d[day] = { lo = m, q = rec.q }
    else
        if m < (today.lo or m) then today.lo = m end
        if rec.q > (today.q or 0) then today.q = rec.q end
    end
    for d in pairs(rec.d) do if day - d >= KEEP_DAYS then rec.d[d] = nil end end
    return key
end

-- ------------------------------------------------------------ scanner

A.scan = { running = false, pages = 0 }
A.onScanDone = {}               -- listeners for a scan's end: fn(true) finished, fn(false) failed or cut short

-- The client holds ONE pending commodity purchase, and its events don't say
-- whose it is: whoever starts one claims it (dropping the other tab's), and
-- each tab acts only on a purchase it owns (the hunt: Snipe's stale quote
-- cancelled Investing's purchase, or armed its Confirm with the wrong total).
A.purchase = nil                -- { owner = "snipe" | "invest" | ..., drop = fn }
--- Is an item a commodity? GetItemCommodityStatus wants an ITEM IN YOUR
-- BAGS (an ItemLocation): given an itemID it errors (measured on Forever,
-- "Usage: ...GetItemCommodityStatus(item)") -- so every check by id was a
-- guess. With a location, ask it; by id, what stacks is a commodity on the
-- AH (known = false: a guess). Returns isCommodity, known.
function A.IsCommodity(id, loc)
    local ah = AH()
    if loc ~= nil then
        local ok, st = Call(ah and ah.GetItemCommodityStatus, loc)
        if ok and Num(st) and (st == 1 or st == 2) then return st == 2, true end
    end
    local ci = rawget(_G, "C_Item")
    local okM, max = Call(ci and ci.GetItemMaxStackSizeByID, id)
    if not (okM and Num(max)) then
        local okI, name, _, _, _, _, _, _, stack = Call(ci and ci.GetItemInfo, id)
        okM, max = okI and name ~= nil, stack
    end
    -- (a guess either way: whichever kind of answer comes back settles it)
    return not (okM and Num(max) and max == 1), false
end

--- A purchase already confirmed is on its way to the server: nobody else
-- may take the claim then (its result belongs to the tab that sent it).
function A.Claim(owner, drop)
    local p = A.purchase
    if p and p.owner ~= owner and p.confirming then return false end
    if p and p.owner ~= owner and p.drop then pcall(p.drop) end
    A.purchase = { owner = owner, drop = drop }
    return true
end
function A.Confirming(owner) if A.Owns(owner) then A.purchase.confirming = true end end
function A.Owns(owner) return A.purchase ~= nil and A.purchase.owner == owner end
function A.Release(owner) if A.Owns(owner) then A.purchase = nil end end

local function Ended(ok) for _, fn in ipairs(A.onScanDone) do pcall(fn, ok) end end
--- A finished scan's rows: { [key] = rec } seen by it.
function A.LastScanItems()
    local s = A.Store()
    local out = {}
    if not s then return out end
    local want = tonumber(s.done) or tonumber(s.seq)
    for key, rec in pairs(s.items) do
        if type(rec) == "table" and rec.n == want then out[key] = rec end
    end
    return out
end

local function Changed() if A.OnChange then A.OnChange() end end
local function Say(msg) A.message = msg; Changed() end

--- Store a page's rows as it arrives (the list fills in during the scan).
local function Take(rows)
    local s = A.Store()
    if not (s and type(rows) == "table") then return end
    local now, day = Epoch(), math.floor(Epoch() / DAY)
    for _, row in ipairs(rows) do
        local key = Record(s.items, row, now, day, A.scan.seq)
        if key and not A.scan.seen[key] then
            A.scan.seen[key] = true
            A.scan.count = A.scan.count + 1
        end
    end
end

local function Finish()
    local ah = AH()
    local s = A.Store()
    A.scan.running = false
    if not s then Say("Scan failed") Ended(false) return end
    if A.scan.count == 0 then               -- no page came through the events: read it all now
        local ok, rows = Call(ah and ah.GetBrowseResults)
        if ok then Take(rows) end
    end
    if A.scan.count == 0 then Say("Scan failed") Ended(false) return end
    -- This scan is now the one the list stands on: what it didn't see has
    -- sold out (until now the last finished scan kept those listed).
    for key in pairs(A.scan.seen) do
        local rec = s.items[key]
        if type(rec) == "table" then rec.n = A.scan.seq end
    end
    s.done = A.scan.seq
    s.lastScan, s.lastCount = Epoch(), A.scan.count
    s.lastPages = A.scan.pages              -- the next scan's progress bar measures against this
    Ended(true)
    A.scan.secs = Now() - (A.scan.t0 or Now())
    Say(nil)
end

--- Paused while neither Snipe nor Investing is showing (Alex: the scan got in
-- the way of the other tabs); A.SetPaused(false) carries on where it was.
A.paused = false
local NextPage
function A.SetPaused(p)
    p = p and true or false
    if A.paused == p then return end
    A.paused = p
    if p then return end
    if A.scan.running and A.scan.held then A.scan.held = nil NextPage() end
    if A.scan.pending then
        A.scan.pending = nil
        if not A.Scan() and A.IsOpen() then                -- the client busy: try again in a moment
            A.scan.pending = true
            if C_Timer and C_Timer.After then C_Timer.After(1, function() if not A.paused and A.scan.pending then A.paused = true A.SetPaused(false) end end) end
        end
    end
    Changed()
end

--- A page asked for and never answered (dropped by the server) mustn't
-- leave the scan "running" until the AH closes (sweep 3): each ask stamps
-- A.scan.ask; still the same ask SCAN_WAIT later = the scan failed (not
-- Finish: that would call everything it never saw sold out).
local SCAN_WAIT = 8
local function Watch()
    A.scan.ask = (A.scan.ask or 0) + 1
    local ask, seq = A.scan.ask, A.scan.seq
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(SCAN_WAIT, function()
        if A.scan.running and A.scan.seq == seq and A.scan.ask == ask and not A.scan.held then
            A.scan.running = false
            Say("The scan got no answer; try again")
            Ended(false)
            Changed()
        end
    end)
end

NextPage = function()
    local ah = AH()
    if not A.scan.running then return end
    if A.paused then A.scan.held = true return end         -- picks up on SetPaused(false)
    local okF, full = Call(ah.HasFullBrowseResults)
    if (okF and full == true) or A.scan.pages >= MAX_PAGES then Finish() return end
    if not Ready() then
        if C_Timer and C_Timer.After then C_Timer.After(0.5, NextPage) end
        return
    end
    A.scan.pages = A.scan.pages + 1
    Changed()
    if not Call(ah.RequestMoreBrowseResults) then Finish() return end
    Watch()
end

--- Every SendBrowseQuery (ours or anyone's) bumps A.browseSeq; a browse that
-- isn't the scan's cuts the scan short. Installed once per C_AuctionHouse.
A.browseSeq = 0
function A.HookBrowse()
    local ah = AH()
    if not ah or A.hooked == ah then return end
    A.hooked = ah
    pcall(hooksecurefunc, ah, "SendBrowseQuery", function()
        A.browseSeq = A.browseSeq + 1
        if A.ownBrowse or not A.scan.running then return end
        A.scan.running, A.scan.held = false, nil
        Say("The scan was cut short by another search")
        Ended(false)
    end)
end

--- One browse pass over the whole auction house.
function A.Scan()
    local ah = AH()
    if not (A.Enabled() and ah and ah.SendBrowseQuery) then return false end
    if A.scan.running or not A.IsOpen() then return false end
    if A.paused then A.scan.pending = true Changed() return true end   -- starts when Snipe or Investing shows
    -- busy (Investing's queue keeps the client busy on this tab): starts on
    -- the client's ready event, and the queue gives way (sweep 3)
    if not Ready() then
        A.scan.wantStart = true
        if C_Timer and C_Timer.After then                -- (backstop for the ready event)
            C_Timer.After(1, function() if A.scan.wantStart and not A.scan.running and not A.paused then A.Scan() end end)
        end
        Changed()
        return true
    end
    A.scan.wantStart = nil
    local s = A.Store()
    if not s then return false end
    -- Which scan saw an item is a sequence number, not the time: two scans
    -- in one second must still tell "sold out since" apart.
    s.seq = (tonumber(s.seq) or 0) + 1
    A.scan.running, A.scan.pages, A.scan.t0, A.scan.held = true, 1, Now(), nil   -- (no hold left from a scan cut short)
    A.scan.seq, A.scan.seen, A.scan.count = s.seq, {}, 0
    A.message = nil
    -- Any OTHER browse while we page (Blizzard's Browse tab, a probe) replaces
    -- the client's one result set: our scan is over, cut short -- not
    -- "finished" on someone else's rows (the hunt).
    A.HookBrowse()
    A.ownBrowse = true
    local ok = Call(ah.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    A.ownBrowse = false
    if not ok then A.scan.running = false Say("Scan failed") Ended(false) return false end
    Watch()
    Changed()
    return true
end

--- How far the running scan is, 0..1, or nil. The client never says how
-- many pages a browse has (only "more" or "full"), so it's measured against
-- the last scan's count (15 when the probe ran, 2026-10-05), and held under
-- 95% until the client says it's done.
function A.Progress()
    if not A.scan.running then return nil end
    local s = A.Store()
    local total = (s and tonumber(s.lastPages)) or 15
    return math.min(0.95, (A.scan.pages or 1) / math.max(1, total)), total
end

-- ------------------------------------------------------------ snipes

--- What a vendor pays for one, from the client (the server's price), or
-- nil until the item is cached -- then it's asked for once. The shipped
-- table is NOT trusted for this: Forever's server changed many prices
-- (every wand sells for 1c; Venture Company Legguards 2s 84c where the
-- client's own data says 79s 29c -- Alex, 2026-10-05).
local requested = {}
function A.LiveVendor(id)
    local gii = C_Item and C_Item.GetItemInfo
    if gii then
        local ok, name, _, _, _, _, _, _, _, _, _, sell = pcall(gii, id)
        if ok and name ~= nil and Num(sell) then return sell end
    end
    if not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
    return nil
end
A.VendorPrice = A.LiveVendor

local function MinProfit()
    local o = O()
    local v = o and tonumber(o.minProfit)
    return (v and v >= 0) and v or 5
end

--- The last scan's items whose cheapest listing is under vendor price by
-- at least the minimum, best (profit x listed) first.
function A.Snipes()
    local s = A.Store()
    local out = {}
    if not s or (not s.lastScan and not A.scan.running) then return out end
    local vendor = ns.VendorSell or {}
    local floor = MinProfit()
    -- While a scan runs, only what it has seen so far (Alex: an old scan's
    -- items go when a new one starts); otherwise the last finished scan.
    local running = A.scan.running
    local want = running and A.scan.seq or (tonumber(s.done) or tonumber(s.seq))   -- (stores from before "done" existed)
    for key, rec in pairs(s.items) do
        if type(rec) == "table" and Num(rec.m) and (running and rec.s or rec.n) == want then
            -- The table only picks what to check; the client's live price
            -- decides (nil = not loaded yet: asked for, shown once it is).
            local v = vendor[rec.id]
            if v and v - rec.m >= math.max(1, floor) then v = A.LiveVendor(rec.id) else v = nil end
            if v and v - rec.m >= math.max(1, floor) then
                out[#out + 1] = { key = key, id = rec.id, lvl = rec.lvl, sfx = rec.sfx, price = rec.m,
                                  vendor = v, profit = v - rec.m, listed = rec.q or 0 }
            end
        end
    end
    table.sort(out, function(a, b)
        local pa, pb = a.profit * math.max(1, a.listed), b.profit * math.max(1, b.listed)
        if pa ~= pb then return pa > pb end
        return a.id < b.id
    end)
    return out
end

-- ------------------------------------------------------------ one item

A.sel = nil      -- { id, key, item, vendor, kind = "commodity"|"item", rows, under = { qty, cost }, quote }

local function UnderVendor(sel)
    local qty, cost = 0, 0
    local cap = sel.vendor - math.max(1, MinProfit())
    for _, r in ipairs(sel.rows or {}) do
        if r.unit <= cap then qty = qty + r.qty; cost = cost + r.unit * r.qty end
    end
    return { qty = qty, cost = cost, profit = sel.vendor * qty - cost }
end

--- Look one item up (its live listings).
local function Ask()
    local sel, ah = A.sel, AH()
    if not (sel and sel.needAsk) then return end
    if not Ready() then
        if C_Timer and C_Timer.After then C_Timer.After(1, Ask) end    -- (the ready event is the quick way)
        return
    end
    sel.needAsk, sel.sentAt = nil, Now()
    Call(ah.SendSearchQuery, sel.item, {}, true)
    Changed()
end

function A.Select(snipe)
    local ah = AH()
    if not (snipe and ah and ah.SendSearchQuery and ah.MakeItemKey) then return false end
    local old = A.sel
    -- a purchase sent: its result is still to come (a new pick orphaned the
    -- claim and locked Buy and Investing out -- sweep 3); a quote not yet
    -- confirmed is let go
    if old and old.asked and A.Owns("snipe") then
        if A.purchase.confirming then Say("Wait for the purchase to finish") return false end
        Call(ah.CancelCommoditiesPurchase)
        A.Release("snipe")
    end
    local okK, item = Call(ah.MakeItemKey, snipe.id, snipe.lvl or 0, snipe.sfx or 0)
    if not okK then return false end
    A.sel = { id = snipe.id, key = snipe.key, lvl = snipe.lvl, sfx = snipe.sfx, item = item,
              vendor = A.LiveVendor(snipe.id) or snipe.vendor, rows = nil, needAsk = true }
    A.message = nil
    Ask()                                           -- now, or when the client is ready (not "busy, try again")
    Changed()
    return true
end

--- A Snipe look-up or scan waiting for the client, or an answer on its way:
-- Investing's queue gives way (it kept the client busy and replaced Snipe's
-- answer on the very tab it runs on -- sweep 3).
function A.Wants()
    if A.scan.wantStart then return true end
    local sel = A.sel
    if not sel then return false end
    return sel.needAsk or (sel.rows == nil and sel.sentAt ~= nil and Now() - sel.sentAt < 3) or false
end

--- The selection's buy as of now (the min profit may have changed since it
-- was read): what the footer shows and the click buys agree.
function A.Under(sel)
    if sel and sel.rows and not sel.asked then sel.under = UnderVendor(sel) end
    return sel and sel.under
end
function A.Cap(sel) return sel.vendor - math.max(1, MinProfit()) end

local function ReadCommodity()
    local ah, sel = AH(), A.sel
    local ok, n = Call(ah.GetNumCommoditySearchResults, sel.id)
    sel.kind, sel.rows = "commodity", {}
    if not (ok and Num(n)) then return end
    for i = 1, n do
        local okR, r = Call(ah.GetCommoditySearchResultInfo, sel.id, i)
        if okR and type(r) == "table" and Num(r.unitPrice) and Num(r.quantity) then
            -- your own units aren't for sale to you (the sweep)
            local q = r.quantity - (Num(r.numOwnerItems) and r.numOwnerItems or (r.containsOwnerItem and r.quantity or 0))
            if q > 0 then sel.rows[#sel.rows + 1] = { unit = r.unitPrice, qty = q } end
        end
    end
    sel.under = UnderVendor(sel)
end

local function ReadItems(key)
    local ah, sel = AH(), A.sel
    key = key or sel.item
    local ok, n = Call(ah.GetNumItemSearchResults, key)
    sel.kind, sel.rows = "item", {}
    if not (ok and Num(n)) then return end
    for i = 1, n do
        local okR, r = Call(ah.GetItemSearchResultInfo, key, i)
        if okR and type(r) == "table" and Num(r.buyoutAmount) and r.buyoutAmount > 0 and Num(r.auctionID)
                and not r.containsOwnerItem then                          -- not your own auction
            local q = (Num(r.quantity) and r.quantity > 0) and r.quantity or 1
            sel.rows[#sel.rows + 1] = { unit = r.buyoutAmount / q, qty = q, buyout = r.buyoutAmount, auctionID = r.auctionID }
        end
    end
    table.sort(sel.rows, function(a, b) return a.unit < b.unit end)
    sel.under = UnderVendor(sel)
end

-- ------------------------------------------------------------ buying

--- A click: buy what's under vendor. Items: the cheapest one auction.
-- Commodities: start the purchase; the client's quote arms A.Confirm.
function A.Buy()
    local ah, sel = AH(), A.sel
    if sel and sel.rows then sel.under = UnderVendor(sel) end   -- the min profit may have changed since
    if sel and sel.rows and sel.under and sel.under.qty == 0 then Say("Nothing under vendor at this min profit") return false end
    if not (sel and sel.under and sel.under.qty > 0) then return false end
    if sel.kind == "item" then
        local cap = sel.vendor - math.max(1, MinProfit())
        for _, r in ipairs(sel.rows) do
            if r.unit <= cap then
                local ok = Call(ah.PlaceBid, r.auctionID, r.buyout)
                if ok then sel.pending = r.auctionID; Say("Buying...") end
                return ok
            end
        end
        return false
    elseif sel.kind == "commodity" then
        sel.quote = nil
        sel.asked = { qty = sel.under.qty, cost = sel.under.cost }
        if not A.Claim("snipe", function() sel.asked, sel.quote = nil, nil Changed() end) then
            sel.asked = nil
            Say("Another purchase is going through; try again in a moment")
            return false
        end
        local ok = Call(ah.StartCommoditiesPurchase, sel.id, sel.under.qty)
        if ok then Say("Getting a quote...")
        else sel.asked = nil A.Release("snipe") Say("Not bought") end          -- (Buy stayed greyed: sweep 3)
        return ok
    end
    return false
end

--- The second click on a commodity: buy at the quoted price.
function A.Confirm()
    local ah, sel = AH(), A.sel
    if not (sel and sel.quote and sel.asked) then return false end
    local ok = Call(ah.ConfirmCommoditiesPurchase, sel.id, sel.asked.qty)
    if ok then sel.quote = nil; A.Confirming("snipe") Say("Buying...") end
    return ok
end

function A.Cancel()
    local ah, sel = AH(), A.sel
    if sel and sel.quote and A.Owns("snipe") then Call(ah.CancelCommoditiesPurchase) end
    if sel then sel.quote, sel.asked = nil, nil end
    A.Release("snipe")
    Changed()
end

local function Refetch()
    local sel = A.sel
    if not sel then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() if A.sel == sel and A.IsOpen() then A.Select(sel) end end)
    end
end

-- ------------------------------------------------------------ events

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
                     "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "COMMODITY_SEARCH_RESULTS_UPDATED",
                     "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
                     "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
                     "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if A.sel and A.sel.needAsk then Ask()
        elseif A.scan.wantStart and not A.scan.running then A.Scan() end
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then
        A.sel = nil
        A.openSeq = (A.openSeq or 0) + 1
        local mine = A.openSeq
        local function Auto()
            local o = O()
            return A.Enabled() and o and o.autoScan ~= false
        end
        if Auto() and C_Timer and C_Timer.After then
            -- a beat later (the AH's own opening query goes first), and only
            -- for this opening, still wanted
            C_Timer.After(1, function() if A.openSeq == mine and A.IsOpen() and Auto() then A.Scan() end end)
        end
        Changed()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        A.scan.pending, A.scan.held, A.scan.wantStart = nil, nil, nil
        if A.scan.running then A.scan.running = false A.endReason = "closed" Ended(false) A.endReason = nil end   -- (listeners can tell a close from a failure)
        if A.sel and A.sel.quote and A.Owns("snipe") then Call(AH().CancelCommoditiesPurchase) end
        A.purchase = nil
        A.sel = nil
        Changed()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        if A.scan.running then
            -- UPDATED: the first page (read the whole result); ADDED: the
            -- new rows come with the event.
            if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" and type(a1) == "table" then Take(a1)
            else local ok, rows = Call(AH().GetBrowseResults) if ok then Take(rows) end end
            A.scan.ask = (A.scan.ask or 0) + 1                -- answered: the watch on it is off
            Changed()
            NextPage()
        end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if A.sel and (not Num(a1) or a1 == A.sel.id) then ReadCommodity() Changed() end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        -- Snipe's own answer only (any tab's item answer wiped a live snipe --
        -- sweep 3): its item, and its key unless it was asked as the plain key
        local sel = A.sel
        if not (sel and sel.kind ~= "commodity" and type(a1) == "table" and a1.itemID == sel.id) then return end
        local k = sel.item
        if type(k) == "table" and ((a1.itemLevel or 0) ~= (k.itemLevel or 0) or (a1.itemSuffix or 0) ~= (k.itemSuffix or 0))
                and not ((k.itemLevel or 0) == 0 and (k.itemSuffix or 0) == 0) then return end
        ReadItems(a1) Changed()
    elseif event == "COMMODITY_PRICE_UPDATED" then
        -- the client's quote (unit, total): still under vendor, or no deal
        local sel = A.sel
        if not (sel and sel.asked and A.Owns("snipe")) then return end
        local unit, total = a1, a2
        if Num(unit) and Num(total) and unit <= sel.vendor - math.max(1, MinProfit()) then
            sel.quote = { unit = unit, total = total }
            Say(nil)
        else
            Call(AH().CancelCommoditiesPurchase)
            sel.asked, sel.quote = nil, nil
            A.Release("snipe")
            Say("The price moved above vendor; not bought")
            Refetch()
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if not (A.sel and A.sel.asked and A.Owns("snipe")) then return end
        A.sel.asked, A.sel.quote = nil, nil
        A.Release("snipe")
        Say("That price is gone")
        Refetch()
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" or event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        -- ours: a commodity purchase we own, or the very auction we bid on
        local sel = A.sel
        if not sel then return end
        if event == "COMMODITY_PURCHASE_SUCCEEDED" then
            if not (sel.asked and A.Owns("snipe")) then return end
            A.Release("snipe")
        elseif not (sel.pending and (not Num(a1) or a1 == sel.pending)) then
            return
        end
        A.sel.pending, A.sel.asked = nil, nil
        A.bought = (A.bought or 0) + 1
        Say("Bought")
        Refetch()
    elseif event == "COMMODITY_PURCHASE_FAILED" or event == "AUCTION_HOUSE_SHOW_ERROR" then
        local sel = A.sel
        if not sel then return end
        if event == "COMMODITY_PURCHASE_FAILED" then
            if not (sel.asked and A.Owns("snipe")) then return end
            A.Release("snipe")
        elseif not sel.pending then
            return
        end
        A.sel.pending, A.sel.asked, A.sel.quote = nil, nil, nil
        Say("Not bought")
        Refetch()
    end
end)

ns.Commands = ns.Commands or {}
ns.Commands.snipe = function() if A.Scan() then ns.Print("auction: scanning") else ns.Print("auction: open the auction house first") end end
