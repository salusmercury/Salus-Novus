--[[ Salus Novus -- /sn probe ah: can an auction house module be built on Forever?

Read-only. Nothing here bids, buys, posts or cancels.

    /sn probe ah              anywhere: which C_AuctionHouse calls exist, the
                              vendor price of a few items, a deposit quote,
                              whether the AH is open
    /sn probe ah scan         at the AH: one full scan (ReplicateItems) -- how
                              many listings, how long, a few rows' values,
                              how many lacked full info, secret values?
                              (The client allows one every ~15 minutes.)
    /sn probe ah browse       at the AH: an empty browse search, paged to the
                              end: one row per item with its cheapest price
    /sn probe ah read         at the AH: what the client holds from the last
                              full scan, without asking for a new one
    /sn probe ah search ID    at the AH: one item's live listings (commodity
                              or item search), cheapest first
    /sn probe ah invest       at the AH: an Investing run, watched: per
                              commodity how long its search took, whether
                              it answered, how much of the listed supply its
                              price list held, and why it isn't worth it;
                              the per-item records are saved too (items)

Every line is printed and kept in SalusNovusDB.lastProbe (what = "ah",
"ah scan", "ah search") so it can be read off the saved file after /reload.
]]

local _, ns = ...

local P = ns.Probe or {}
ns.Probe = P

local S = function(v) return ns.S(v) end
local AH = function() return rawget(_G, "C_AuctionHouse") end

local TEST_ITEMS = { 2589, 14047, 2592, 3575 }     -- Linen, Runecloth, Wool, Iron Bar

-- Each kind kept on its own (SalusNovusDB.ahProbe["ah scan"] ...): one
-- run of another kind used to overwrite the scan nobody had read yet.
local function Save(what, lines, items)
    if type(SalusNovusDB) ~= "table" then return end
    SalusNovusDB.lastProbe = { what = what, t = time(), lines = lines }
    SalusNovusDB.ahProbe = SalusNovusDB.ahProbe or {}
    SalusNovusDB.ahProbe[what] = { t = time(), lines = lines, items = items }
end

local function Emit(what, lines, items)
    for _, l in ipairs(lines) do ns.Print(l) end
    Save(what, lines, items)
    P.ahLast = lines
end

local function Secret(v) return ns.IsSecret(v) and "SECRET" or nil end

--- Is the AH window open? (The scan and searches need it.)
function P.AHOpen()
    local f = rawget(_G, "AuctionHouseFrame")
    local ok, shown = false, false
    if f then ok, shown = pcall(f.IsShown, f) end
    return (ok and shown == true) and true or false
end

local function Try(fn, ...)
    if type(fn) ~= "function" then return false, "MISSING" end
    return pcall(fn, ...)
end

--- /sn probe ah: what exists, vendor prices, a deposit quote.
function P.AHStatic()
    local out = {}
    local ah = AH()
    out[#out + 1] = ("C_AuctionHouse: %s   AH open: %s"):format(ah and "present" or "MISSING", tostring(P.AHOpen()))
    if ah then
        local names = { "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo", "SendSearchQuery",
            "SendBrowseQuery", "GetCommoditySearchResultInfo", "GetItemSearchResultInfo", "GetNumCommoditySearchResults",
            "GetNumItemSearchResults", "MakeItemKey", "GetItemCommodityStatus", "CalculateCommodityDeposit",
            "CalculateItemDeposit", "IsThrottledMessageSystemReady", "PlaceBid", "StartCommoditiesPurchase",
            "ConfirmCommoditiesPurchase", "PostCommodity", "PostItem" }
        local missing = {}
        for _, n in ipairs(names) do if type(ah[n]) ~= "function" then missing[#missing + 1] = n end end
        out[#out + 1] = ("functions: %d of %d present%s"):format(#names - #missing, #names,
            #missing > 0 and ("; missing " .. table.concat(missing, ", ")) or "")
        local okT, ready = Try(ah.IsThrottledMessageSystemReady)
        out[#out + 1] = "throttle ready: " .. (okT and (Secret(ready) or S(ready)) or S(ready))
    end
    local gii = C_Item and C_Item.GetItemInfo
    for _, id in ipairs(TEST_ITEMS) do
        local ok, name, _, _, _, _, _, _, stack, _, _, sell = Try(gii, id)
        local status = "-"
        if ah and ah.GetItemCommodityStatus then
            -- Takes the item (its ID), not an item key (measured: "Usage: ...(item)")
            local okS, st = pcall(ah.GetItemCommodityStatus, id)
            status = okS and (Secret(st) or S(st)) or ("ERROR " .. S(st))
        end
        if ok and name == nil then
            out[#out + 1] = ("item %d: not cached yet (run it again in a moment); commodity status %s"):format(id, status)
        else
            out[#out + 1] = ("item %d %s: vendor sell %s, stack %s, commodity status %s"):format(id,
                ok and S(name) or "?", ok and (Secret(sell) or S(sell)) or S(name), ok and S(stack) or "?", status)
        end
    end
    if ah and ah.CalculateCommodityDeposit then
        for _, dur in ipairs({ 1, 2, 3 }) do
            local ok, d = pcall(ah.CalculateCommodityDeposit, 14047, dur, 20)
            out[#out + 1] = ("deposit, 20 Runecloth, duration %d: %s"):format(dur, ok and (Secret(d) or S(d)) or ("ERROR " .. S(d)))
        end
    end
    return out
end

-- ------------------------------------------------------------ events

local ev = CreateFrame("Frame")
local pending = nil            -- { kind = "scan"|"search", t0, id, key }
P.ahPending = function() return pending end

local function Reg(e) pcall(ev.RegisterEvent, ev, e) end
for _, e in ipairs({ "REPLICATE_ITEM_LIST_UPDATE", "COMMODITY_SEARCH_RESULTS_UPDATED",
                     "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_CLOSED",
                     "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" }) do Reg(e) end

local SCAN_GIVE_UP = 300        -- s: Forever answered nothing in 885 s (2026-10-05)
local BROWSE_PAGES = 40         -- RequestMoreBrowseResults calls at most

local function Now() return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime() end

--- The scan's answer: count, time, a few rows, info gaps, secrets.
function P.AHScanResult()
    local ah = AH()
    local out = {}
    local okN, n = Try(ah and ah.GetNumReplicateItems)
    n = (okN and ns.Num(n)) and n or 0
    out[#out + 1] = ("scan: %d listings in %.1f s"):format(n, Now() - (pending and pending.t0 or Now()))
    local noInfo, secrets, items, sample = 0, 0, {}, {}
    for i = 0, n - 1 do
        local r = { pcall(ah.GetReplicateItemInfo, i) }
        if r[1] then
            local name, count, buyout, itemID, all = r[2], r[4], r[11], r[18], r[19]
            if Secret(count) or Secret(buyout) or Secret(itemID) then secrets = secrets + 1 end
            if all == false then noInfo = noInfo + 1 end
            if ns.Num(itemID) then items[itemID] = true end
            if #sample < 5 and ns.Num(buyout) and buyout > 0 then
                sample[#sample + 1] = ("  #%d %s x%s buyout %s (item %s, full info %s)"):format(i, S(name), S(count), S(buyout), S(itemID), S(all))
            end
        end
    end
    local distinct = 0
    for _ in pairs(items) do distinct = distinct + 1 end
    out[#out + 1] = ("distinct items %d; rows without full info %d; rows with secret values %d"):format(distinct, noInfo, secrets)
    for _, l in ipairs(sample) do out[#out + 1] = l end
    return out
end

--- The browse so far: rows, pages, full?, a few cheapest, secrets.
function P.AHBrowseResult(note)
    local ah = AH()
    local out = {}
    local ok, rows = Try(ah.GetBrowseResults)
    rows = (ok and type(rows) == "table") and rows or {}
    local okF, full = Try(ah.HasFullBrowseResults)
    out[#out + 1] = ("browse: %d items over %d pages in %.1f s; full: %s%s"):format(#rows, pending.pages or 1,
        Now() - pending.t0, okF and S(full) or "?", note and ("; " .. note) or "")
    local secrets, sample = 0, {}
    for i, r in ipairs(rows) do
        if type(r) == "table" then
            if Secret(r.minPrice) or Secret(r.totalQuantity) then secrets = secrets + 1 end
            if i <= 5 then
                local key = type(r.itemKey) == "table" and r.itemKey or {}
                sample[#sample + 1] = ("  item %s (ilvl %s, suffix %s): %s listed, cheapest %s"):format(S(key.itemID),
                    S(key.itemLevel), S(key.itemSuffix), S(r.totalQuantity), S(r.minPrice))
            end
        end
    end
    out[#out + 1] = ("rows with secret values %d"):format(secrets)
    for _, l in ipairs(sample) do out[#out + 1] = l end
    return out
end

--- One item's live listings, cheapest first.
function P.AHSearchResult()
    local ah = AH()
    local out = {}
    local id, key = pending.id, pending.key
    local okC, nc = Try(ah.GetNumCommoditySearchResults, id)
    if okC and ns.Num(nc) and nc > 0 then
        out[#out + 1] = ("commodity %d: %d price points"):format(id, nc)
        for i = 1, math.min(5, nc) do
            local ok, r = pcall(ah.GetCommoditySearchResultInfo, id, i)
            if ok and type(r) == "table" then
                out[#out + 1] = ("  %d: qty %s at %s each%s"):format(i, S(r.quantity), S(r.unitPrice), Secret(r.unitPrice) and " (SECRET)" or "")
            end
        end
        return out
    end
    local okI, ni = Try(ah.GetNumItemSearchResults, key)
    out[#out + 1] = ("item %d: %s listings (commodity results: %s)"):format(id, okI and S(ni) or "ERROR", okC and S(nc) or "ERROR")
    if okI and ns.Num(ni) then
        for i = 1, math.min(5, ni) do
            local ok, r = pcall(ah.GetItemSearchResultInfo, key, i)
            if ok and type(r) == "table" then
                out[#out + 1] = ("  %d: buyout %s, bid %s, qty %s, auctionID %s"):format(i, S(r.buyoutAmount), S(r.bidAmount), S(r.quantity), S(r.auctionID))
            end
        end
    end
    return out
end

ev:SetScript("OnEvent", function(_, event, a1)
    if not pending then return end
    if event == "AUCTION_HOUSE_CLOSED" then
        local okN, n = Try(AH() and AH().GetNumReplicateItems)
        Emit(pending.what, { ("probe: the auction house closed before the answer came (waited %.0f s; replicate count then %s)"):format(
            Now() - pending.t0, okN and S(n) or "?") })
        if pending.ticker then pending.ticker:Cancel() end
        pending = nil
    elseif (event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
            and pending.kind == "browse" then
        -- another browse replaced ours (a Buy search, a scan): its pages aren't ours to page
        if pending.seq and ns.Auction and ns.Auction.browseSeq ~= pending.seq then
            pending = nil
            Emit("ah browse", { "probe: another search replaced this browse; stopped (run it again with nothing else searching)" })
            return
        end
        pending.answered = pending.pages or 1
        P.AHBrowseMore()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" and pending.kind == "scan" then
        if pending.ticker then pending.ticker:Cancel() end
        local lines = P.AHScanResult()
        pending = nil
        Emit("ah scan", lines)
    elseif (event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED") and pending.kind == "search" then
        if event == "COMMODITY_SEARCH_RESULTS_UPDATED" and ns.Num(a1) and a1 ~= pending.id then return end
        if event == "ITEM_SEARCH_RESULTS_UPDATED" and not (type(a1) == "table" and a1.itemID == pending.id) then return end
        local lines = P.AHSearchResult()
        pending = nil
        Emit("ah search", lines)
    end
end)

--- /sn probe ah scan
function P.AHScan()
    local ah = AH()
    if not (ah and ah.ReplicateItems) then Emit("ah scan", { "probe: C_AuctionHouse.ReplicateItems is missing" }) return end
    if not P.AHOpen() then Emit("ah scan", { "probe: open the auction house first (talk to an auctioneer)" }) return end
    if pending then ns.Print("probe: still waiting on the last " .. pending.kind) return end
    local okB, before = Try(ah.GetNumReplicateItems)
    pending = { kind = "scan", what = "ah scan", t0 = Now() }
    local ok, err = pcall(ah.ReplicateItems)
    if not ok then
        pending = nil
        Emit("ah scan", { "probe: ReplicateItems failed: " .. S(err) })
        return
    end
    ns.Print(("probe: full scan asked for (replicate count before: %s); the answer prints when it arrives -- keep the AH open"):format(okB and S(before) or "?"))
    -- Progress every 15 s: is anything arriving, or was the ask ignored?
    if C_Timer and C_Timer.NewTicker then
        pending.ticker = C_Timer.NewTicker(15, function()
            if not (pending and pending.kind == "scan") then return end
            local okN, n = Try(ah.GetNumReplicateItems)
            if Now() - pending.t0 >= SCAN_GIVE_UP then
                pending.ticker:Cancel()
                pending = nil
                Emit("ah scan", { ("probe: no answer to the full scan after %d s (replicate count %s): it looks unavailable here -- try /sn probe ah browse"):format(
                    SCAN_GIVE_UP, okN and S(n) or "?") })
                return
            end
            ns.Print(("probe: still waiting on the scan, %.0f s; replicate count %s"):format(Now() - pending.t0, okN and S(n) or "?"))
        end)
    end
end

--- /sn probe ah read: whatever the client holds from the last full scan,
-- without asking for a new one (the answer may have landed unannounced).
function P.AHRead()
    local ah = AH()
    if not (ah and ah.GetNumReplicateItems) then Emit("ah read", { "probe: GetNumReplicateItems is missing" }) return end
    local lines = P.AHScanResult()
    lines[1] = lines[1]:gsub(" in [%d%.]+ s", " held now")
    Emit("ah read", lines)
end

--- /sn probe ah search <itemID>
function P.AHSearch(id)
    local ah = AH()
    id = tonumber(id)
    if not id then ns.Print("probe: /sn probe ah search <itemID>, e.g. 14047 (Runecloth)") return end
    if not (ah and ah.SendSearchQuery and ah.MakeItemKey) then Emit("ah search", { "probe: SendSearchQuery / MakeItemKey missing" }) return end
    if not P.AHOpen() then Emit("ah search", { "probe: open the auction house first (talk to an auctioneer)" }) return end
    if pending then ns.Print("probe: still waiting on the last " .. pending.kind) return end
    local okR, ready = Try(ah.IsThrottledMessageSystemReady)
    if okR and ready == false then ns.Print("probe: the auction house is throttled; try again in a moment") return end
    local okK, key = pcall(ah.MakeItemKey, id)
    if not okK then Emit("ah search", { "probe: MakeItemKey failed: " .. S(key) }) return end
    pending = { kind = "search", what = "ah search", t0 = Now(), id = id, key = key }
    local ok, err = pcall(ah.SendSearchQuery, key, {}, true)
    if not ok then
        pending = nil
        Emit("ah search", { "probe: SendSearchQuery failed: " .. S(err) })
        return
    end
    -- a dropped answer mustn't block every probe until the AH closes (sweep 3)
    local mine = pending
    if C_Timer and C_Timer.After then
        C_Timer.After(10, function()
            if pending ~= mine then return end
            pending = nil
            Emit("ah search", { ("probe: no answer to the search for item %d after 10 s (dropped?)"):format(id) })
        end)
    end
    ns.Print(("probe: searching item %d; the answer prints when it arrives"):format(id))
end

--- Page on while the client says there's more, waiting out the throttle.
function P.AHBrowseMore()
    local ah = AH()
    if not pending or pending.kind ~= "browse" then return end
    local okF, full = Try(ah.HasFullBrowseResults)
    if (okF and full == true) or (pending.pages or 1) >= BROWSE_PAGES then
        local note = nil                       -- (x and nil or y) is always y in Lua
        if not (okF and full == true) then note = ("stopped at the %d-page cap"):format(BROWSE_PAGES) end
        local lines = P.AHBrowseResult(note)
        pending = nil
        Emit("ah browse", lines)
        return
    end
    local function Next()
        if not pending or pending.kind ~= "browse" then return end
        local okR, ready = Try(ah.IsThrottledMessageSystemReady)
        if okR and ready == false then
            if C_Timer and C_Timer.After then C_Timer.After(0.5, Next) end
            return
        end
        pending.pages = (pending.pages or 1) + 1
        local ok, err = Try(ah.RequestMoreBrowseResults)
        if not ok then
            local lines = P.AHBrowseResult("RequestMoreBrowseResults failed: " .. S(err))
            pending = nil
            Emit("ah browse", lines)
            return
        end
        P.BrowseWatch()
    end
    Next()
end

--- A page asked for and never answered ends the probe (it stayed on
-- "browse" until the AH closed: sweep 3).
function P.BrowseWatch()
    if not pending then return end
    local mine, page = pending, pending.pages or 1
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(10, function()
        if pending ~= mine or (pending.pages or 1) ~= page or pending.answered == page then return end
        local lines = P.AHBrowseResult(("no answer to page %d after 10 s"):format(page))
        pending = nil
        Emit("ah browse", lines)
    end)
end

--- /sn probe ah browse: an empty browse search, paged to the end -- the
-- whole AH as one row per item with its cheapest price (the sniper's view).
function P.AHBrowse()
    local ah = AH()
    if not (ah and ah.SendBrowseQuery and ah.GetBrowseResults) then Emit("ah browse", { "probe: SendBrowseQuery / GetBrowseResults missing" }) return end
    if not P.AHOpen() then Emit("ah browse", { "probe: open the auction house first (talk to an auctioneer)" }) return end
    if pending then ns.Print("probe: still waiting on the last " .. pending.kind) return end
    local okR, ready = Try(ah.IsThrottledMessageSystemReady)
    if okR and ready == false then ns.Print("probe: the auction house is throttled; try again in a moment") return end
    pending = { kind = "browse", what = "ah browse", t0 = Now(), pages = 1 }
    local query = { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} }
    if ns.Auction and ns.Auction.HookBrowse then ns.Auction.HookBrowse() end      -- (every browse counted)
    local ok, err = pcall(ah.SendBrowseQuery, query)
    pending.seq = ns.Auction and ns.Auction.browseSeq
    if ok then P.BrowseWatch() end
    if not ok then
        pending = nil
        Emit("ah browse", { "probe: SendBrowseQuery failed: " .. S(err) })
        return
    end
    ns.Print("probe: browsing the whole auction house; the answer prints when the last page arrives -- keep the AH open")
end

-- ------------------------------------------------------------ investing

--- Why a ladder isn't worth it, Invest.Evaluate's rules spelled out:
-- "worth it", "no listings", "one price level", "no price jump" (no gap
-- anywhere the 5% cut leaves a profit on), "cheapest level over the share
-- cap", "cheapest level over budget", "under the profit floor" (a cut
-- makes money, not enough), "jump only past the share cap or budget".
function P.InvestWhy(ladder, budget, floor, share)
    local I = ns.Invest
    local levels = {}
    for _, l in ipairs(ladder or {}) do
        if ns.Num(l.unit) and ns.Num(l.qty) and l.unit > 0 and l.qty > 0 then levels[#levels + 1] = l end
    end
    table.sort(levels, function(a, b) return a.unit < b.unit end)
    if #levels == 0 then return "no listings" end
    if #levels == 1 then return "one price level" end
    -- (the whole ladder: your own levels set the relist price, as in Invest -- sweep 3)
    if I.Evaluate(ladder, budget, floor, share) then return "worth it" end
    -- No gap anywhere the 5% cut leaves a profit on, whatever the limits:
    -- the market itself (checked first: it's the answer even when a limit
    -- would also have stopped it)
    if not I.Evaluate(levels, math.huge, 1, 1) then return "no price jump" end
    local supply = 0
    for _, l in ipairs(levels) do supply = supply + l.qty end
    if levels[1].qty > math.floor(supply * share) then return "cheapest level over the share cap" end
    if levels[1].unit * levels[1].qty > budget then return "cheapest level over budget" end
    if I.Evaluate(levels, budget, 1, share) then return "under the profit floor" end
    return "jump only past the share cap or budget"
end

local inv     -- the watched run: { t0, tStart, queued, items = { [id] = rec }, order, throttles, fullYes }

local function Median(xs)
    if #xs == 0 then return 0 end
    table.sort(xs)
    return xs[math.floor((#xs + 1) / 2)]
end

--- The run's summary lines.
function P.InvestReport(note)
    local out = {}
    local now = Now()
    local tStart = inv.tStart or now
    local answered, times, timeouts, partial, maxT = 0, {}, 0, 0, 0
    local reasons, reasonOrder = {}, {}
    local items, retried, recovered = 0, 0, 0
    for _, id in ipairs(inv.order) do
        local r = inv.items[id]
        if (r.tries or 1) > 1 then
            retried = retried + 1
            if r.dt then recovered = recovered + 1 end
        end
        if r.item then
            items = items + 1
        elseif r.timeout then
            timeouts = timeouts + 1
        elseif r.dt then
            answered = answered + 1
            times[#times + 1] = r.dt
            if r.dt > maxT then maxT = r.dt end
            if r.held and r.held < 0.9 then partial = partial + 1 end
            if not reasons[r.why] then reasons[r.why] = 0 reasonOrder[#reasonOrder + 1] = r.why end
            reasons[r.why] = reasons[r.why] + 1
        end
    end
    out[#out + 1] = ("investing probe: %d commodities queued, %d asked, %d skipped (cheapest over budget); scan %.1f s, searches %.1f s%s"):format(
        inv.queued or 0, #inv.order, inv.skipped or 0, tStart - inv.t0, now - tStart, note and ("; " .. note) or "")
    out[#out + 1] = ("answers %d (median %.2f s, max %.2f s); not commodities (item answers) %d; never answered %d; throttle waits %d"):format(
        answered, Median(times), maxT, items, timeouts, inv.throttles)
    out[#out + 1] = ("asks %d; retried %d commodities, %d answered on a retry; first miss at ask #%s, %s s in"):format(
        #inv.asks, retried, recovered, inv.firstMiss and tostring(inv.firstMiss.n) or "-",
        inv.firstMiss and ("%.0f"):format(inv.firstMiss.t) or "-")
    -- Asks per minute and misses per minute: the server's limit, read off
    local perMin, last = {}, 0
    for _, a in ipairs(inv.asks) do
        local m = math.floor(a.t / 60) + 1
        if m > last then last = m end
        perMin[m] = perMin[m] or { 0, 0 }
        perMin[m][1] = perMin[m][1] + 1
        if a.missed then perMin[m][2] = perMin[m][2] + 1 end
    end
    local bits = {}
    for m = 1, last do local v = perMin[m] or { 0, 0 } bits[#bits + 1] = ("%d/%d"):format(v[1], v[2]) end   -- quiet minutes too
    out[#out + 1] = "asks/misses by minute: " .. (#bits > 0 and table.concat(bits, " ") or "-")
    out[#out + 1] = ("price list held under 90%% of the scan's listed count: %d of %d%s"):format(partial, answered,
        inv.fullKnown and ("; client says full: " .. inv.fullYes .. " of " .. answered) or "")
    table.sort(reasonOrder, function(a, b) return reasons[a] > reasons[b] end)
    local parts = {}
    for _, w in ipairs(reasonOrder) do parts[#parts + 1] = ("%s %d"):format(w, reasons[w]) end
    out[#out + 1] = "why: " .. (#parts > 0 and table.concat(parts, ", ") or "-")
    -- A few of each, to look at: bottom = the cheapest levels, qty x copper
    local shown = {}
    for _, id in ipairs(inv.order) do
        local r = inv.items[id]
        if r.why and (shown[r.why] or 0) < 3 then
            shown[r.why] = (shown[r.why] or 0) + 1
            out[#out + 1] = ("  %s: item %d, listed %s, list held %s, bottom %s"):format(r.why, id, S(r.listed),
                r.held and ("%d%%"):format(math.floor(r.held * 100 + 0.5)) or "?", r.bottom or "")
        end
    end
    return out
end

local function InvestFinish(note)
    if not inv then return end
    local items = {}
    for _, id in ipairs(inv.order) do
        local r = inv.items[id]
        items[#items + 1] = { id = id, dt = r.dt, timeout = r.timeout, listed = r.listed, held = r.held,
                              full = r.full, levels = r.levels, why = r.why, bottom = r.bottom,
                              at = r.at, tries = r.tries, item = r.item }
    end
    local lines = P.InvestReport(note)
    inv = nil
    if ns.Invest then ns.Invest.trace = nil end
    Emit("ah invest", lines, items)
end

local function InvestTrace(kind, id, ladder)
    if not inv then return end
    local I = ns.Invest
    if kind == "start" then
        inv.tStart, inv.queued, inv.skipped = Now(), id, ladder
    elseif kind == "throttle" then
        inv.throttles = inv.throttles + 1
    elseif kind == "ask" then
        local r = inv.items[id]
        if not r then
            inv.order[#inv.order + 1] = id
            r = { tries = 0, at = Now() - (inv.tStart or inv.t0) }
            inv.items[id] = r
        end
        r.t, r.tries, r.timeout = Now(), r.tries + 1, nil
        inv.asks[#inv.asks + 1] = { t = Now() - (inv.tStart or inv.t0), id = id }
        r.ask = inv.asks[#inv.asks]
    elseif kind == "timeout" then
        local r = inv.items[id]
        if r then
            r.timeout = true
            if r.ask then r.ask.missed = true end
            if not inv.firstMiss then inv.firstMiss = { n = #inv.asks, t = Now() - (inv.tStart or inv.t0) } end
        end
    elseif kind == "unask" then
        -- a row click put this ask back: its re-ask isn't a retry
        local r = inv.items[id]
        if r then r.tries = math.max(0, r.tries - 1) end
    elseif kind == "item" then
        local r = inv.items[id]
        if r then r.item, r.why = true, "not a commodity" end
    elseif kind == "answer" then
        local r = inv.items[id]
        if not r then return end
        r.dt = Now() - r.t
        local held, levels = 0, {}
        for _, l in ipairs(ladder or {}) do held = held + (l.qty or 0) + (l.own or 0) levels[#levels + 1] = l end   -- (listed counts yours too)
        table.sort(levels, function(a, b) return a.unit < b.unit end)
        local rec = ns.Auction.LastScanItems()[tostring(id)]
        r.listed = rec and rec.q
        r.held = (r.listed and r.listed > 0) and (held / r.listed) or nil
        r.levels = #levels
        local bits = {}
        for k = 1, math.min(4, #levels) do bits[#bits + 1] = ("%dx%d"):format(levels[k].qty, levels[k].unit) end
        r.bottom = table.concat(bits, " ")
        local okF, full = Try(AH().HasFullCommoditySearchResults, id)
        if okF and type(full) == "boolean" then
            r.full = full
            inv.fullKnown = true
            if full then inv.fullYes = inv.fullYes + 1 end
        end
        r.why = P.InvestWhy(ladder, I.budget or (I.Budget()), I.MinProfit(), I.MaxShare())
    elseif kind == "done" then
        InvestFinish(nil)
    elseif kind == "closed" then
        InvestFinish(type(id) == "string" and id or "the auction house closed before the end")
    end
end
P.InvestTrace = InvestTrace

--- /sn probe ah invest
function P.AHInvest()
    local I = ns.Invest
    if not I then Emit("ah invest", { "probe: Investing isn't loaded" }) return end
    if not P.AHOpen() then Emit("ah invest", { "probe: open the auction house first (talk to an auctioneer)" }) return end
    if inv then ns.Print("probe: already watching an Investing run") return end
    if I.run.state ~= "idle" then ns.Print("probe: an Investing run is going; let it finish, then try again") return end
    inv = { t0 = Now(), items = {}, order = {}, asks = {}, throttles = 0, fullYes = 0 }
    I.trace = InvestTrace
    if not I.Scan() then
        inv, I.trace = nil, nil
        Emit("ah invest", { "probe: the Investing scan didn't start (is the Snipe tab on?)" })
        return
    end
    if ns.AuctionUI and ns.AuctionUI.Show then pcall(ns.AuctionUI.Show, "invest") end   -- not a toggle
    ns.Print("probe: watching an Investing run; the summary prints when it finishes -- keep the AH open")
end

--- The /sn probe ah entry point (Probe.lua's command routes here).
function P.AH(arg, rest)
    if arg == "scan" then P.AHScan()
    elseif arg == "invest" then P.AHInvest()
    elseif arg == "read" then P.AHRead()
    elseif arg == "browse" then P.AHBrowse()
    elseif arg == "search" then P.AHSearch(rest)
    else Emit("ah", P.AHStatic()) end
end
