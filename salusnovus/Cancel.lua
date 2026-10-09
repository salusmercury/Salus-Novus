--[[ Salus Novus -- Cancel: your auctions, undercut ones first.

  C.Query()        ask the client for your auctions (OWNED_AUCTIONS_UPDATED),
                   then look each distinct item up once -- a queue minding
                   the throttle like Investing's -- and mark every auction:
                     "undercut"  someone else lists it cheaper (per unit)
                     "cheapest"  nobody else is under you
                     "alone"     nobody else lists it at all
  C.Cancel(row)    from a click (the client requires one): CancelAuction.
                   The deposit isn't refunded on a cancel.
  C.CancelNext()   the next undercut auction, one per click

Owned auctions' buyoutAmount is the whole auction's (Blizzard's own table
shows it unchanged, Blizzard_AuctionHouseTableBuilder); per unit = / qty.
]]

local _, ns = ...

local C = {}
ns.Cancel = C

local Num = ns.Num
local SEARCH_TIMEOUT = 2

local function AH() return rawget(_G, "C_AuctionHouse") end
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

C.gone = {}            -- auctionIDs cancelled this session: never shown again
C.rows = {}            -- { auctionID, id, key, keyStr, qty, buyout, unit, secs, band, status, cheapest }
C.run = { state = "idle" }
C.sel = nil

local function Changed() if C.OnChange then C.OnChange() end end
local function Say(m) C.message = m; Changed() end
local function KeyStr(k) return ns.Sell and ns.Sell.KeyStr(k) or tostring(k and k.itemID) end

local RANK = { undercut = 1, cheapest = 2, alone = 2 }
local function Sort()
    table.sort(C.rows, function(a, b)
        local ra, rb = RANK[a.status] or 3, RANK[b.status] or 3
        if ra ~= rb then return ra < rb end
        local ta, tb = a.secs or math.huge, b.secs or math.huge
        if ta ~= tb then return ta < tb end
        return a.auctionID < b.auctionID
    end)
end

--- Your active auctions, as the client holds them now.
local function Read()
    local ah = AH()
    local out = {}
    local ok, n = Call(ah.GetNumOwnedAuctions)
    for i = 1, (ok and Num(n)) and n or 0 do
        local okI, a = Call(ah.GetOwnedAuctionInfo, i)
        -- status 0 = active (1 = sold, waiting in the mail)
        if okI and type(a) == "table" and Num(a.auctionID) and type(a.itemKey) == "table" and (a.status or 0) == 0
                and not C.gone[a.auctionID] then
            local qty = (Num(a.quantity) and a.quantity > 0) and a.quantity or 1
            local buyout = Num(a.buyoutAmount) and a.buyoutAmount or nil
            -- A commodity's owned buyoutAmount is already per unit (Spider
            -- Ichor 50c x100 read 0c divided again); an item's is the auction's
            local isC, known = ns.Auction.IsCommodity(a.itemKey.itemID)
            local per = (known and not isC) and qty or 1
            out[#out + 1] = { auctionID = a.auctionID, id = a.itemKey.itemID, key = a.itemKey, keyStr = KeyStr(a.itemKey),
                              qty = qty, buyout = buyout, unit = buyout and math.floor(buyout / per) or nil,
                              secs = Num(a.timeLeftSeconds) and a.timeLeftSeconds or nil,
                              band = Num(a.timeLeft) and a.timeLeft or nil, link = a.itemLink, status = "checking" }
        end
    end
    return out
end

-- ------------------------------------------------------------ the checks

--- Is it a commodity, and does the client know? Unknown (its data not
-- loaded) is searched as one; the answer -- of either kind -- settles it
-- (Alex's screenshot: commodities stuck on "..." as unanswered item searches).
local function Commodity(id) return ns.Auction.IsCommodity(id) end

--- Mark every row of one item from the cheapest listing that isn't yours.
local function Mark(keyStr, others)
    for _, row in ipairs(C.rows) do
        if row.keyStr == keyStr then
            row.cheapest = others
            if not row.unit then row.status = "unknown"          -- bid only: no buyout to compare (the sweep)
            elseif not others then row.status = "alone"
            elseif row.unit and others < row.unit then row.status = "undercut"
            else row.status = "cheapest" end
        end
    end
end

local Next

local function Done(r)
    r.waiting = nil
    r.i = r.i + 1
    Sort()
    Changed()
    Next()
end

Next = function()
    local r = C.run
    if r.state ~= "checking" or r.waiting then return end
    if not ns.Auction.IsOpen() then r.state = "idle" Changed() return end
    if r.i > #r.queue then r.state = "idle" Changed() return end
    local ah = AH()
    local okR, ready = Call(ah.IsThrottledMessageSystemReady)
    -- a background check gives way to a pick waiting on another tab (it
    -- starved Buy's look-up until every check was done: sweep 3)
    local yield = (ns.Sell and ns.Sell.Wants and ns.Sell.Wants()) or (ns.Buy and ns.Buy.Wants and ns.Buy.Wants())
        or (ns.Auction.Wants and ns.Auction.Wants())
    if (okR and ready == false) or yield then
        r.throttleSeq = (r.throttleSeq or 0) + 1
        local seq = r.throttleSeq
        r.throttled = seq
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() if r.throttled == seq then r.throttled = nil Next() end end)
        end
        return
    end
    local q = r.queue[r.i]
    local key = q.key
    if q.commodity then
        local okK, k = Call(ah.MakeItemKey, q.id)
        key = okK and k or nil
    end
    if not (key and Call(ah.SendSearchQuery, key, {}, false)) then r.i = r.i + 1 return Next() end
    r.waiting = q
    r.askSeq = (r.askSeq or 0) + 1
    local seq = r.askSeq
    if C_Timer and C_Timer.After then
        C_Timer.After(SEARCH_TIMEOUT, function()
            if r.waiting == q and r.askSeq == seq then                     -- no answer: "?", not "..." for ever
                for _, row in ipairs(C.rows) do if row.keyStr == q.keyStr and row.status == "checking" then row.status = "unknown" end end
                Done(r)
            end
        end)
    end
    Changed()
end

--- One check per distinct item, the soonest to expire first.
local function StartChecks()
    local seen, queue = {}, {}
    for _, row in ipairs(C.rows) do
        if not seen[row.keyStr] then
            seen[row.keyStr] = true
            local commodity, known = Commodity(row.id)
            queue[#queue + 1] = { keyStr = row.keyStr, id = row.id, key = row.key, commodity = commodity, known = known }
        end
    end
    local r = C.run
    r.queue, r.i, r.state, r.waiting, r.throttled = queue, 1, "checking", nil, nil
    Changed()
    Next()
end

--- Ask for your auctions; the checks follow the answer.
function C.Query()
    local ah = AH()
    if not (ah and ns.Auction.IsOpen()) then return false end
    C.run.state = "loading"
    -- what was read before is stale now: nothing reads as undercut (or is
    -- cancelled as one) until it's checked again (the sweep)
    for _, row in ipairs(C.rows) do row.status = "checking" end
    Call(ah.QueryOwnedAuctions, {})
    Changed()
    return true
end

function C.Progress()
    local r = C.run
    if r.state == "loading" then return 0.05, "Loading your auctions" end
    if r.state == "checking" then
        local n = #r.queue
        return (r.i - 1) / math.max(1, n), ("Checking %d of %d"):format(math.min(r.i, n), n)
    end
    return nil
end

function C.Counts()
    local under = 0
    for _, row in ipairs(C.rows) do if row.status == "undercut" then under = under + 1 end end
    return #C.rows, under
end

-- ------------------------------------------------------------ cancelling

function C.Select(row)
    C.sel = row
    C.message = nil
    Changed()
end

--- What cancelling costs (beyond the deposit, which isn't refunded).
function C.Cost(row)
    if not row then return nil end
    local ok, v = Call(AH().GetCancelCost, row.auctionID)
    return (ok and Num(v)) and v or nil
end

--- A click: cancel one auction.
function C.Cancel(row)
    row = row or C.sel
    if not row then return false end
    local ah = AH()
    local okC, can = Call(ah.CanCancelAuction, row.auctionID)
    if okC and can == false then Say("That one can't be cancelled") return false end
    if not Call(ah.CancelAuction, row.auctionID) then Say("Couldn't cancel that") return false end
    -- Gone from view at once (Alex), and kept out of a re-read until the
    -- client stops listing it
    C.gone[row.auctionID] = true
    for i, x in ipairs(C.rows) do if x == row then table.remove(C.rows, i) break end end
    if C.sel == row then C.sel = nil end
    Say("Cancelled")
    return true
end

--- A click: the next undercut auction (top of the list), one per click.
function C.CancelNext()
    if C.run.state == "loading" then return false end
    for _, row in ipairs(C.rows) do
        if row.status == "undercut" and not row.cancelling then return C.Cancel(row) end
    end
    Say("Nothing undercut")
    return false
end

-- ------------------------------------------------------------ events

local ev = CreateFrame("Frame")
for _, e in ipairs({ "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED", "COMMODITY_SEARCH_RESULTS_UPDATED",
                     "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_CLOSED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, event, a1)
    local r = C.run
    local ah = AH()
    if event == "AUCTION_HOUSE_CLOSED" then
        C.sel, C.message = nil, nil
        r.state, r.waiting, r.throttled = "idle", nil, nil
        Changed()
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        if r.state ~= "loading" then return end           -- only the list we asked for
        local was = C.sel and C.sel.auctionID
        C.rows = Read()
        C.sel = nil
        for _, row in ipairs(C.rows) do if row.auctionID == was then C.sel = row end end   -- keep the pick
        Sort()
        StartChecks()
    elseif event == "AUCTION_CANCELED" then
        for i, row in ipairs(C.rows) do
            if row.auctionID == a1 then
                table.remove(C.rows, i)
                if C.sel == row then C.sel = nil end
                Changed()
                return
            end
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if r.throttled then r.throttled = nil Next() end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local q = r.waiting
        if not (r.state == "checking" and q and Num(a1) and a1 == q.id) then return end      -- either kind of search
        local cheapest
        local ok, n = Call(ah.GetNumCommoditySearchResults, q.id)
        for i = 1, (ok and Num(n)) and n or 0 do
            local okR, x = Call(ah.GetCommoditySearchResultInfo, q.id, i)
            if okR and type(x) == "table" and Num(x.unitPrice) and Num(x.quantity) then
                local theirs = x.quantity - (Num(x.numOwnerItems) and x.numOwnerItems or (x.containsOwnerItem and x.quantity or 0))
                if theirs > 0 and (not cheapest or x.unitPrice < cheapest) then cheapest = x.unitPrice end
            end
        end
        Mark(q.keyStr, cheapest)
        Done(r)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local q = r.waiting
        if not (r.state == "checking" and q and type(a1) == "table"
                and (KeyStr(a1) == q.keyStr or (q.commodity and a1.itemID == q.id))) then return end   -- (the plain key only when that's what was asked: sweep 3)
        -- read under the key the server ANSWERED with (a guess searched the
        -- plain key; the owned key read nothing: 'Only yours' -- the sweep)
        local cheapest
        local ok, n = Call(ah.GetNumItemSearchResults, a1)
        for i = 1, (ok and Num(n)) and n or 0 do
            local okR, x = Call(ah.GetItemSearchResultInfo, a1, i)
            if okR and type(x) == "table" and not x.containsOwnerItem and Num(x.buyoutAmount) and x.buyoutAmount > 0 then
                local u = math.floor(x.buyoutAmount / ((Num(x.quantity) and x.quantity > 0) and x.quantity or 1))
                if not cheapest or u < cheapest then cheapest = u end
            end
        end
        Mark(q.keyStr, cheapest)
        Done(r)
    end
end)
