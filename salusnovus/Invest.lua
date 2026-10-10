--[[ Salus Novus -- Investing: is a commodity's cheap tail worth buying?

Alex's rules (2026-10-05):
  * commodities with at least `minListed` units on the AH (default 250)
  * a budget of `pct` percent of the gold you have (default 20)
  * buy the cheapest listings within the budget, relist everything one
    copper under the cheapest listing left, sell it all, the AH keeps 5%
  * never more than `investMaxShare` percent of the whole supply (default
    10%: proposing to buy 99% of a market is silly -- Alex)
  * the cut with the BEST MARGIN that still makes at least `investMinProfit`
    gold in total (default 1g): a big buy at 5% loses to a small one at 20%
  * sort by margin (profit / cost), widest first; a click buys up to there

  I.Evaluate(ladder, budget)   the best cut through a price ladder:
        buy whole price levels from the bottom while the cost fits the
        budget; for each such cut, relist at the next level's price - 1c;
        of the cuts making at least the profit floor, keep the best margin
        (a tie goes to the bigger profit). A partial level is never
        bought: relisting under a price you also paid loses on those units.
        (The deposit isn't counted: the client returns it on a sale.)
  I.Scan()        an AH scan (Auction.Scan), then one search per qualifying
                  commodity for its ladder, queued, minding the throttle
  I.Select(row)   a fresh search for one commodity, re-evaluated
  I.Buy()         from a click: StartCommoditiesPurchase for the cut; the
                  client's quote is re-checked (still profitable at the
                  quoted total, within budget) before I.Confirm (a second
                  click) buys
]]

local _, ns = ...

local I = {}
ns.Invest = I

local Num = ns.Num
local CUT = 0.05
-- Measured (/sn probe ah invest, 2026-10-05): an answer comes in 0.05-0.4 s
-- or not at all, and after ~160 searches the server stops answering most of
-- them (a rate limit that drops, not refuses). So: give up on an answer
-- after 2 s, put that commodity back at the end of the queue (up to
-- MAX_TRIES asks), and space the searches out while answers go missing.
local SEARCH_TIMEOUT = 2
local MAX_TRIES = 3
local MAX_GAP = 8               -- s between searches, at the most

local function A() return ns.Auction end
local function O() return ns.db and ns.db.auction end
local function AH() return rawget(_G, "C_AuctionHouse") end
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
local function Now() return (GetTime and GetTime()) or 0 end

local function Pct()
    local v = O() and tonumber(O().investPct)
    return (v and v > 0 and v <= 100) and v or 20
end
--- The least total profit worth a buy, in copper (the setting is in gold).
function I.MinProfit()
    local v = O() and tonumber(O().investMinProfit)
    return math.floor(((v and v >= 0) and v or 1) * 10000 + 0.5)   -- (0.0029 g is 29c, not 28.999...)
end

--- The most of a commodity's whole supply a buy may take, 0..1.
function I.MaxShare()
    local v = O() and tonumber(O().investMaxShare)
    return ((v and v > 0 and v <= 100) and v or 10) / 100
end

local function MinListed()
    local v = O() and tonumber(O().investMinListed)
    return (v and v > 0) and v or 250
end

--- The gold this budget is a share of, and the budget.
function I.Budget()
    local ok, money = Call(rawget(_G, "GetMoney"))
    money = (ok and Num(money)) and money or 0
    return math.floor(money * Pct() / 100), money
end

--- What the AH pays out for `qty` sold at `unit` each, after its cut.
function I.Net(qty, unit) return math.floor(qty * unit * (1 - CUT)) end

--- The best cut through a ladder { { unit, qty }, ... } (any order).
function I.Evaluate(ladder, budget, floor, share)
    floor = floor or I.MinProfit()
    local levels, mine = {}, nil
    for _, l in ipairs(ladder or {}) do
        if Num(l.unit) and Num(l.qty) and l.unit > 0 and l.qty > 0 then levels[#levels + 1] = l end
        -- your own listing: not for sale to you, but still the price to beat
        if Num(l.unit) and Num(l.own) and l.own > 0 and (not mine or l.unit < mine) then mine = l.unit end
    end
    table.sort(levels, function(a, b) return a.unit < b.unit end)
    local supply = 0
    for _, l in ipairs(levels) do supply = supply + l.qty end
    local cap = math.floor(supply * (share or I.MaxShare()))
    local best
    local qty, cost = 0, 0
    for k = 1, #levels - 1 do
        qty = qty + levels[k].qty
        cost = cost + levels[k].unit * levels[k].qty
        if cost > budget or qty > cap then break end     -- deeper only costs and takes more
        local relist = levels[k + 1].unit - 1
        if mine and mine <= relist then relist = mine end     -- yours is the cheapest left: match it (Sell's rule)
        if relist > levels[k].unit then
            local profit = I.Net(qty, relist) - cost
            local margin = profit / cost
            if profit > 0 and profit >= floor and (not best or margin > best.margin
                    or (margin == best.margin and profit > best.profit)) then
                best = { qty = qty, cost = cost, relist = relist, profit = profit, margin = margin, levels = k }
            end
        end
    end
    return best
end

-- ------------------------------------------------------------ the queue

I.results = {}                 -- evaluated commodities, widest margin first
I.ladders = {}                 -- id -> the ladder its last search returned (this run)
I.run = { state = "idle" }     -- idle | scanning | searching
I.sel = nil

local function Changed() if I.OnChange then I.OnChange() end end
--- `/sn probe ah invest` watches a run through this (ProbeAH.lua).
local function Trace(kind, ...) if I.trace then pcall(I.trace, kind, ...) end end
local function Say(m) I.message = m; Changed() end

local function Sort()
    table.sort(I.results, function(a, b)
        if a.best.margin ~= b.best.margin then return a.best.margin > b.best.margin end
        return a.id < b.id
    end)
end

local function Ladder(id)
    local ah = AH()
    local out = {}
    local ok, n = Call(ah.GetNumCommoditySearchResults, id)
    if not (ok and Num(n)) then return out end
    for i = 1, n do
        local okR, r = Call(ah.GetCommoditySearchResultInfo, id, i)
        if okR and type(r) == "table" and Num(r.unitPrice) and Num(r.quantity) then
            -- Your own listings aren't stock you can buy (the hunt: after a
            -- relist, the cut was scored on buying your own units back)
            local q = r.quantity
            if Num(r.numOwnerItems) then q = q - r.numOwnerItems
            elseif r.containsOwnerItem == true then q = 0 end
            -- (kept as `own`: the relist price still has to beat it -- the sweep)
            if q > 0 or q < r.quantity then out[#out + 1] = { unit = r.unitPrice, qty = math.max(q, 0), own = r.quantity - math.max(q, 0) } end
        end
    end
    return out
end

-- (what stacks is a commodity; unknown -> try it: Auction.IsCommodity)
local function Commodity(id) return (A().IsCommodity(id)) end

--- The queue of commodities to look up, from the last finished scan, and
-- how many were skipped unsearched. A skip must never hide a deal: the
-- only one that can't is the cheapest unit costing more than the budget
-- (any cut buys at least one). (A "market too small for the profit floor"
-- skip can't be safe: the relist price is the next level's, and nothing in
-- the scan bounds it.)
local function Candidates(budget)
    local out, skipped, listed = {}, 0, {}
    local floor = MinListed()
    for _, rec in pairs(A().LastScanItems()) do
        if (rec.q or 0) >= floor and Commodity(rec.id) then
            if Num(rec.m) and rec.m > budget then skipped = skipped + 1
            else out[#out + 1] = rec.id listed[rec.id] = rec.q end
        end
    end
    table.sort(out)
    return out, skipped, listed
end

--- How many the run's scan said were listed (kept from the run's start: a
-- scan running since mustn't change it, and one lookup beats one per row).
function I.Listed(id)
    local l = I.run.listed
    if l and l[id] then return l[id] end
    local rec = A().LastScanItems()[tostring(id)]
    return rec and rec.q or 0
end

--- A clicked commodity's lookup, and a purchase in progress, pause the
-- queue: one commodity search answers at a time, and the clicked one goes
-- first (Alex: buying mid-scan must work).
function I.Busy()
    local sel = I.sel
    return sel ~= nil and (not sel.fresh or sel.asked ~= nil)
end

local Next
local function Resume()
    local r = I.run
    if r.state == "searching" and not r.waiting and not I.Busy() then Next() end
end

local function Ask(id)
    local ah = AH()
    local okK, key = Call(ah.MakeItemKey, id)
    if not okK then return false end
    local r = I.run
    r.waiting, r.asked = id, Now()
    r.askSeq = (r.askSeq or 0) + 1
    Trace("ask", id)
    if not Call(ah.SendSearchQuery, key, {}, false) then r.waiting = nil return false end   -- never stuck "waiting"
    return true
end

--- An answer came (or a commodity was dealt with): ease the spacing off.
local function Eased(r)
    r.gap = (r.gap or 0) / 2
    if r.gap < 0.25 then r.gap = 0 end
    r.notBefore = Now() + r.gap
end

--- No answer: ask again later (at the end of the queue), and slow down.
local function Missed(r, id)
    Trace("timeout", id)
    r.tries[id] = (r.tries[id] or 1) + 1
    if r.tries[id] <= MAX_TRIES then r.queue[#r.queue + 1] = id
    else r.gaveUp = r.gaveUp + 1 Trace("giveup", id) end
    r.gap = math.min(MAX_GAP, math.max(1, (r.gap or 0) * 2))
    r.notBefore = Now() + r.gap
end

Next = function()
    local r = I.run
    if r.state ~= "searching" or r.waiting or I.Busy() then return end
    if I.paused then r.held = true return end               -- off the tab: carries on when it's back
    if not A().IsOpen() then r.state = "idle" Trace("closed") Say("The auction house closed") return end
    if r.i > #r.queue then
        r.state, r.waiting = "idle", nil
        Trace("done")
        -- what never answered is said, not read as "nothing worth buying" (sweep 3)
        if (r.gaveUp or 0) > 0 then Say(("%d never answered; scan again to check them"):format(r.gaveUp))
        -- ('Bought: relist at X' stays: the sweep -- that text only, not
        -- whatever came after it: sweep 2)
        elseif not (I.keepMessage and I.message == I.keepMessage) then Say(nil)
        else Changed() end                               -- (the bar and greyed Scan stayed up: sweep 5)
        return
    end
    local ah = AH()
    local okR, ready = Call(ah.IsThrottledMessageSystemReady)
    -- A Sell pick waiting to be looked up goes first: the queue running flat
    -- out took every free moment and the pick sat at "Looking it up" (Alex).
    local yield = (ns.Sell and ns.Sell.Wants and ns.Sell.Wants()) or (A().Wants and A().Wants())   -- (and a Snipe pick: sweep 3)
    if (okR and ready == false) or yield then
        -- The client says when it's ready (AUCTION_HOUSE_THROTTLED_SYSTEM_
        -- READY, in Forever's event census); the timer is only a backstop
        -- (polling every 0.3 s lost a fraction of a second per search:
        -- the client's limit, ~0.7 s a search, is what sets the pace).
        Trace("throttle")
        r.throttleSeq = (r.throttleSeq or 0) + 1
        local seq = r.throttleSeq
        r.throttled = seq
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() if r.throttled == seq then r.throttled = nil Next() end end)
        end
        return
    end
    local wait = (r.notBefore or 0) - Now()
    if wait > 0 then
        if not r.sleeping and C_Timer and C_Timer.After then
            r.sleeping = true
            C_Timer.After(wait, function() r.sleeping = false Next() end)
        end
        return
    end
    local id = r.queue[r.i]
    if not Ask(id) then r.i = r.i + 1 return Next() end
    Changed()
    -- An answer that never comes doesn't stall the queue. (This ask's own
    -- timer: one left from an ask a click interrupted mustn't count a miss
    -- on the re-ask of the same item.)
    local seq = r.askSeq
    if C_Timer and C_Timer.After then
        C_Timer.After(SEARCH_TIMEOUT, function()
            if r.state == "searching" and r.waiting == id and r.askSeq == seq then r.waiting = nil Missed(r, id) r.i = r.i + 1 Next() end
        end)
    end
end

local function StartSearches()
    local r = I.run
    I.budget = I.Budget()
    r.queue, r.skipped, r.listed = Candidates(I.budget)
    r.i, r.state, r.tries, r.gaveUp, r.gap, r.notBefore = 1, "searching", {}, 0, 0, 0
    r.waiting, r.throttled, r.sleeping, r.cut = nil, nil, false, nil   -- nothing left from a run cut short
    I.results, I.ladders = {}, {}
    Trace("start", #r.queue, r.skipped)
    Changed()
    Next()
end

--- Scan, then look every qualifying commodity up.
function I.Scan()
    if I.run.state ~= "idle" then return false end
    I.keepMessage = nil
    if not (A().Enabled() and A().IsOpen()) then return false end
    I.run.held = nil
    if A().scan.running then
        I.run.state = "scanning"                       -- ride the scan already going
        Changed()
        return true
    end
    if not A().Scan() then return false end
    I.run.state = "scanning"
    Changed()
    return true
end

table.insert(ns.Auction.onScanDone, function(ok)
    if I.run.state ~= "scanning" then return end
    if ok == false then
        I.run.state, I.run.cut = "idle", (A().endReason == "closed") and "closed" or "failed"   -- (a close says so: sweep 3)
        Trace("closed", "the scan was cut short or failed")   -- a probe watching lets go
        Say("The scan didn't finish; try again")
        return
    end
    StartSearches()
end)

--- Paused while neither Snipe nor Investing is showing (Alex).
I.paused = false
function I.SetPaused(p)
    p = p and true or false
    if I.paused == p then return end
    I.paused = p
    local r = I.run
    if not p and r.held then r.held = nil Next() end
end

--- How far it is: 0..1, a label, and whether a click has paused it (Alex:
-- make a pause clear) -- or nil when idle.
function I.Progress()
    local r = I.run
    if r.state == "scanning" then
        local p = A().Progress() or 0
        return p * 0.3, "Scanning the auction house"
    elseif r.state == "searching" then
        local n = #r.queue
        local label = ("Checking %d of %d"):format(math.min(r.i, n), n)
        local paused = I.Busy()
        if paused then
            label = label .. "  \194\183  " .. (I.sel.asked and "paused until you Confirm or Cancel" or "paused while it looks up")
        elseif (r.gap or 0) > 0 then
            label = label .. "  \194\183  slowed down: the server is busy"
        end
        return 0.3 + 0.7 * ((r.i - 1) / math.max(1, n)), label, paused
    end
    return nil
end

--- A setting changed: rank again from the ladders already searched, no new
-- searches (Alex changes these in the strip on the AH). Lowering "min
-- listed" can't add what was never searched; that needs a new Scan.
function I.Reevaluate()
    if not O() then return end
    I.budget = I.Budget()
    local floor = MinListed()
    local out = {}
    for id, ladder in pairs(I.ladders) do
        local best = I.Listed(id) >= floor and I.Evaluate(ladder, I.budget)
        if best then out[#out + 1] = { id = id, best = best } end
    end
    I.results = out
    Sort()
    local sel = I.sel
    if sel and sel.fresh and not sel.asked and I.ladders[sel.id] then
        sel.best = I.Evaluate(I.ladders[sel.id], I.budget)
    end
    Changed()
end
ns.RegisterApply(I.Reevaluate, "Investing")

-- ------------------------------------------------------------ one commodity

--- The clicked commodity's lookup, sent at the client's first free moment
-- (the ready event, or a 1 s backstop). A busy client used to turn the
-- click away -- and with the queue running flat out the client is nearly
-- always busy, so clicks couldn't pause it (Alex).
local function AskSel()
    local sel = I.sel
    if not (sel and sel.needAsk) then return end
    local ah = AH()
    local okR, ready = Call(ah.IsThrottledMessageSystemReady)
    if okR and ready == false then
        if C_Timer and C_Timer.After then C_Timer.After(1, AskSel) end
        return
    end
    sel.needAsk = nil
    local okK, key = Call(ah.MakeItemKey, sel.id)
    if okK then Call(ah.SendSearchQuery, key, {}, false) end
    -- No answer: ask again, then let it go -- a dropped answer mustn't hold
    -- the queue paused for ever (the hunt).
    sel.asks = (sel.asks or 0) + 1
    local n = sel.asks
    if C_Timer and C_Timer.After then
        C_Timer.After(SEARCH_TIMEOUT + 1, function()
            if I.sel ~= sel or sel.fresh or sel.needAsk or sel.asks ~= n then return end
            if n >= MAX_TRIES then
                I.sel = nil
                Say("No answer for that one; click it again to retry")
                Resume()
                return
            end
            sel.needAsk = true
            AskSel()
        end)
    end
end

function I.Select(row)
    if not row then return false end
    local old = I.sel
    if old and old.confirming then Say("Wait for the purchase to finish") return false end
    if old and old.asked and A().Owns("invest") then           -- a quote you walked away from
        Call(AH().CancelCommoditiesPurchase)
        A().Release("invest")
    end
    local r = I.run
    if r.state == "searching" and r.waiting then Trace("unask", r.waiting) r.waiting = nil end   -- asked again once this is done
    I.sel = { id = row.id, best = row.best, fresh = false, needAsk = true }   -- not fresh: the queue holds
    I.message = nil
    if not row.keepMessage then I.keepMessage = nil end
    AskSel()
    Changed()
    return true
end

--- A click: start buying the cut.
local STALE = 20      -- s: a cut looked up longer ago is looked up again before buying (sweep 3)

--- The cut's ladder may have changed: look again; Buy is clicked on the fresh cut.
local function Relook(sel, why)
    sel.fresh, sel.needAsk, sel.asks = false, true, 0
    Say(why)
    AskSel()
end

function I.Buy()
    local sel = I.sel
    if not (sel and sel.fresh and sel.best and not sel.asked) then return false end
    if sel.at and Now() - sel.at > STALE then Relook(sel, "Looking again; click Buy on the fresh cut") return false end
    if not A().Claim("invest", function()
        sel.asked, sel.quote, sel.confirming = nil, nil, nil
        Say("Another purchase started; this one was dropped")
        Resume()
    end) then
        Say("Another purchase is going through; try again in a moment")
        return false
    end
    local ok = Call(AH().StartCommoditiesPurchase, sel.id, sel.best.qty)
    if ok then sel.asked = { qty = sel.best.qty } Say("Getting a quote...") else A().Release("invest") end
    return ok
end

--- The second click: buy at the quoted total.
function I.Confirm()
    local sel = I.sel
    if not (sel and sel.quote and sel.asked) then return false end
    local ok = Call(AH().ConfirmCommoditiesPurchase, sel.id, sel.asked.qty)
    if ok then sel.quote, sel.confirming = nil, true A().Confirming("invest") Say("Buying...") end
    return ok
end

function I.Cancel()
    local sel = I.sel
    if sel and sel.confirming then return end                  -- sent: the server decides now
    if sel and sel.asked and A().Owns("invest") then Call(AH().CancelCommoditiesPurchase) end
    if sel then sel.asked, sel.quote = nil, nil end
    A().Release("invest")
    Changed()
    Resume()
end

-- ------------------------------------------------------------ events

local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
                     "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, event, a1, a2)
    local r, sel = I.run, I.sel
    if event == "AUCTION_HOUSE_CLOSED" then
        if sel and sel.asked and A().Owns("invest") then Call(AH().CancelCommoditiesPurchase) end
        A().Release("invest")
        I.sel = nil
        I.message, I.keepMessage = nil, nil            -- ('Buying...' greeted the next visit: sweep 2)
        if r.state ~= "idle" then r.state, r.cut = "idle", "closed" Trace("closed") end
        -- nothing left waiting: the next run starts clean (the hunt: it stalled)
        r.waiting, r.throttled, r.sleeping = nil, nil, false
        Changed()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if r.state == "searching" and r.waiting and (not Num(a1) or a1 == r.waiting) then
            local id = r.waiting
            r.waiting = nil
            I.ladders[id] = Ladder(id)
            local best = I.Evaluate(I.ladders[id], I.budget or I.Budget())
            Trace("answer", id, I.ladders[id], best)
            Eased(r)
            -- (min listed raised mid-run: what's under it now stays out)
            if best and I.Listed(id) >= MinListed() then I.results[#I.results + 1] = { id = id, best = best } Sort() end
            r.i = r.i + 1
            Changed()
            Next()
        elseif sel and not sel.asked and (not Num(a1) or a1 == sel.id) then
            I.ladders[sel.id] = Ladder(sel.id)
            sel.best = I.Evaluate(I.ladders[sel.id], (I.Budget()))   -- one value: Budget also returns the gold
            sel.fresh, sel.at = true, Now()
            -- its row follows the fresh look (after a buy: the cut left, or none)
            for i, row in ipairs(I.results) do
                if row.id == sel.id then
                    if sel.best then row.best = sel.best else table.remove(I.results, i) end
                    break
                end
            end
            Sort()
            Changed()
            Resume()      -- the lookup is in: the queue carries on until a Buy (a quote isn't a search)
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if I.sel and I.sel.needAsk then AskSel()                 -- a click goes before the queue
        elseif r.throttled then r.throttled = nil Next() end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        -- An item's answer to our search: it was never a commodity (its
        -- data wasn't loaded to tell); move on now, not after the timeout.
        local key = a1
        if r.state == "searching" and r.waiting and type(key) == "table" and key.itemID == r.waiting then
            Trace("item", r.waiting)
            r.waiting = nil
            Eased(r)
            r.i = r.i + 1
            Changed()
            Next()
        end
    elseif event == "COMMODITY_PRICE_UPDATED" then
        if not (sel and sel.asked and sel.best and A().Owns("invest")) then return end
        -- The quote is what it really costs now: still profitable at the
        -- relist price, and within budget? Else no deal.
        local total = a2
        -- a quote that isn't the cut's cost: the ladder changed under it, so
        -- its relist price is stale too -- no deal on old numbers (sweep 3)
        if Num(total) and total ~= sel.best.cost then
            Call(AH().CancelCommoditiesPurchase)
            sel.asked, sel.quote, sel.confirming = nil, nil, nil   -- (left set, it locked Investing: the sweep)
            A().Release("invest")
            Relook(sel, "The price moved; looking again")
            return
        end
        local budget = I.Budget()
        local left = Num(total) and (I.Net(sel.asked.qty, sel.best.relist) - total) or 0
        if Num(total) and total <= budget and left > 0 and left >= I.MinProfit() then
            sel.quote = { total = total, profit = I.Net(sel.asked.qty, sel.best.relist) - total }
            Say(nil)
        else
            Call(AH().CancelCommoditiesPurchase)
            sel.asked, sel.quote, sel.confirming = nil, nil, nil
            A().Release("invest")
            Say("The price moved; no longer worth it")
            Resume()
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if not (sel and sel.asked and A().Owns("invest")) then return end
        sel.asked, sel.quote, sel.confirming = nil, nil, nil
        A().Release("invest")
        Say("That price is gone")
        Resume()
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if not (sel and sel.asked and A().Owns("invest")) then return end
        A().Release("invest")
        sel.asked, sel.quote, sel.fresh, sel.confirming = nil, nil, false, nil
        I.budget = I.Budget()                                   -- the gold just spent
        local relist = sel.best.relist
        I.Select({ id = sel.id, best = sel.best })          -- fresh ladder for what's left
        Say("Bought: relist at " .. (ns.AuctionUI and ns.AuctionUI.Money(relist) or tostring(relist)) .. " each")
        I.keepMessage = I.message
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if not (sel and sel.asked and A().Owns("invest")) then return end
        A().Release("invest")
        sel.asked, sel.quote, sel.confirming = nil, nil, nil
        Say("Not bought")
        Resume()
    end
end)
