--[[ Salus Novus -- Sell: post what's in your bags.

Alex's rules (2026-10-05):
  * the price each is 1c under the cheapest listing -- but when the
    cheapest is yours, match it (never undercut yourself)
  * never under the vendor price after the AH's 5% cut: the floor is
    ceil(vendor / 0.95); when the rule lands under it, post at the floor
  * nothing listed: no price (you type one)
  * the quantity starts at everything you have of it
  * the duration starts at 8h and remembers your last pick
  * posting tees up the next item (the next in the grid)

  S.Bags()         what you can sell, one entry per item, grouped (recipes,
                   weapons, armor, containers, consumables, trade goods,
                   other) -- soulbound and quest items left out (the AH
                   won't take them)
  S.Select(entry)  look its listings up (at the client's first free moment)
                   and price it by the rules above
  S.Post()         from a click (the client requires one): PostCommodity /
                   PostItem; a price far off the market needs S.Confirm()

Measured on Forever: duration indexes 1/2/3 are 2h/8h/24h (deposits 4s/16s/
48s for 20 Runecloth). Signatures from Blizzard's AuctionHouseDocumentation.
]]

local _, ns = ...

local S = {}
ns.Sell = S

local Num = ns.Num
local CUT = 0.05
local ANSWER_WAIT, MAX_ASKS = 4, 3     -- s for an answer; asks before giving up
local NO_ANSWER = "No answer from the auction house; pick it again to retry"
S.HOURS = { 2, 8, 24 }

S.GROUPS = { "Recipes", "Weapons", "Armor", "Containers", "Consumables", "Trade goods", "Other" }
-- Enum.ItemClass -> group: Recipe 9, Weapon 2, Armor 4, Container 1 / Quiver 11,
-- Consumable 0, Tradegoods 7 / Reagent 5; the rest is Other
local CLASS_GROUP = { [9] = 1, [2] = 2, [4] = 3, [1] = 4, [11] = 4, [0] = 5, [7] = 6, [5] = 6 }

local function O() return ns.db and ns.db.auction end
local function AH() return rawget(_G, "C_AuctionHouse") end
local function Now() return (GetTime and GetTime()) or 0 end
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

S.items = {}
S.sel = nil

local function Changed() if S.OnChange then S.OnChange() end end
local function Say(m) S.message = m; Changed() end

-- ------------------------------------------------------------ rules

--- The duration index (1/2/3 = 2h/8h/24h): 8h until you pick another.
function S.Duration()
    local v = O() and tonumber(O().sellDuration)
    return (v == 1 or v == 2 or v == 3) and v or 2
end

function S.SetDuration(d)
    if O() and (d == 1 or d == 2 or d == 3) then O().sellDuration = d end
    if S.sel then S.sel.confirm = nil end      -- a confirm is for what was asked, nothing else
    Changed()
end

--- The least price each that nets the vendor price after the cut, rounded
-- up to the copper (ceil(vendor / 0.95), in integer math).
function S.Floor(vendor)
    if not (Num(vendor) and vendor > 0) then return nil end
    return math.floor((vendor * 100 + 94) / 95)
end

--- The price each from a ladder { { unit, qty, mine }, ... } and the vendor
-- price: price, why ("under" | "mine" | "floor" | "none"), cheapest, floor.
function S.Price(levels, vendor)
    local floor = S.Floor(vendor)
    local cheapest
    for _, l in ipairs(levels or {}) do
        if Num(l.unit) and l.unit > 0 and (not cheapest or l.unit < cheapest.unit
                or (l.unit == cheapest.unit and l.mine)) then
            cheapest = l
        end
    end
    if not cheapest then return nil, "none", nil, floor end
    local price, why = cheapest.unit - 1, "under"
    if cheapest.mine then price, why = cheapest.unit, "mine" end
    if floor and price < floor then price, why = floor, "floor" end
    if price < 1 then price = 1 end
    return price, why, cheapest.unit, floor
end

--- What the AH pays out for `qty` at `unit` each.
function S.Net(qty, unit) return math.floor(qty * unit * (1 - CUT)) end

-- ------------------------------------------------------------ bags

local function Group(id)
    local ci = rawget(_G, "C_Item")
    local ok, _, _, _, _, _, class = Call(ci and ci.GetItemInfoInstant, id)
    return CLASS_GROUP[ok and Num(class) and class or -1] or #S.GROUPS
end


--- An item key as a string: id:level:suffix (gear of one itemID differs by
-- suffix and level -- "of the Eagle" isn't "of the Monkey").
local function KeyStr(k)
    if type(k) ~= "table" then return nil end
    return ("%s:%s:%s"):format(tostring(k.itemID), tostring(k.itemLevel or 0), tostring(k.itemSuffix or 0))
end
S.KeyStr = KeyStr

local function Name(id)
    local ci = rawget(_G, "C_Item")
    local ok, n = Call(ci and ci.GetItemNameByID, id)
    return (ok and ns.Str(n)) or ""
end

--- Everything in the bags the AH will take, grouped and sorted.
function S.Bags()
    local cc, IL, ah = rawget(_G, "C_Container"), rawget(_G, "ItemLocation"), AH()
    -- the bags and the reagent bag (Forever has them; it's bag 5 -- the sweep)
    local last = rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS")
        or ((rawget(_G, "NUM_BAG_SLOTS") or 4) + (rawget(_G, "NUM_REAGENTBAG_SLOTS") or 0))
    local by, out = {}, {}
    for bag = 0, last do
        local okN, n = Call(cc and cc.GetContainerNumSlots, bag)
        for slot = 1, (okN and Num(n)) and n or 0 do
            local okI, info = Call(cc.GetContainerItemInfo, bag, slot)
            if okI and type(info) == "table" and Num(info.itemID) and not info.isBound then
                local okL, loc = Call(IL and IL.CreateFromBagAndSlot, IL, bag, slot)
                local okV, valid = Call(ah and ah.IsSellItemValid, loc, false)
                if okL and loc and okV and valid == true then
                    -- asked by the bag slot (the call takes a location; an
                    -- itemID errors); else what stacks is a commodity
                    local commodity, known = ns.Auction.IsCommodity(info.itemID, loc)
                    -- Commodities are one entry per itemID; items one per item
                    -- key, so suffixes and levels don't merge.
                    local key, okK, ik = tostring(info.itemID), false, nil
                    if not commodity then
                        okK, ik = Call(ah.GetItemKeyFromItem, loc)
                        key = (okK and KeyStr(ik)) or key
                    end
                    local e = by[key]
                    if not e then
                        e = { id = info.itemID, key = key, itemKey = okK and ik or nil, icon = info.iconFileID,
                              quality = info.quality, link = info.hyperlink, count = 0, locs = {},
                              group = Group(info.itemID), name = Name(info.itemID), commodity = commodity, known = known }
                        by[key] = e
                        out[#out + 1] = e
                    end
                    local c = Num(info.stackCount) and info.stackCount or 1
                    e.count = e.count + c
                    e.locs[#e.locs + 1] = { bag = bag, slot = slot, loc = loc, count = c }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        if a.name ~= b.name then return a.name < b.name end
        if a.id ~= b.id then return a.id < b.id end
        return a.key < b.key
    end)
    return out
end

function S.Refresh()
    S.items = S.Bags()
    local sel = S.sel
    if sel then
        local still
        for _, e in ipairs(S.items) do if e.key == sel.entry.key then still = e end end
        if not still then
            -- a settled guess re-keys the entry (an id became an item key, or
            -- back): the one entry of that item is still it (the sweep). Two
            -- item keys that differ are two items (another suffix): not it,
            -- its price isn't theirs (sweep 3)
            local n
            for _, e in ipairs(S.items) do if e.id == sel.entry.id then still, n = e, (n or 0) + 1 end end
            local bare = function(k) return not tostring(k):find(":", 1, true) end
            if n ~= 1 or not (bare(sel.entry.key) or bare(still.key)) then still = nil end
        end
        if still then
            sel.entry = still
            if sel.qty > still.count then sel.qty = still.count end
        else
            S.sel = nil
        end
    end
    Changed()
end

-- ------------------------------------------------------------ one item

--- The vendor price for the floor: the client's live answer, or -- when it
-- hasn't loaded the item yet -- the item table's. Without the fallback the
-- floor vanished and 7 Light Feathers (vendor 7c) went up at 1c each (Alex).
-- The table errs high where it's wrong, so the floor errs safe.
function S.Vendor(id)
    local live = ns.Auction.LiveVendor(id)
    if ns.Num(live) then return live end
    local t = ns.VendorSell and ns.VendorSell[id]
    return ns.Num(t) and t or nil
end

local function Reprice(sel)
    if sel.edited then return end
    sel.confirm = nil
    local price, why, cheapest, floor = S.Price(sel.levels, S.Vendor(sel.id))
    sel.price, sel.why, sel.cheapest, sel.floor = price, why, cheapest, floor
    sel.level = cheapest                       -- the row the price came from
end

--- The selected item's lookup, at the client's first free moment (the
-- ready event, or a 1 s backstop) -- a busy client never turns it away.
local function AskSel()
    local sel = S.sel
    if not (sel and sel.needAsk) then return end
    local ah = AH()
    local okR, ready = Call(ah.IsThrottledMessageSystemReady)
    if okR and ready == false then
        if C_Timer and C_Timer.After then C_Timer.After(1, AskSel) end
        return
    end
    sel.needAsk = nil
    local key
    if sel.commodity then
        local ok, k = Call(ah.MakeItemKey, sel.id)
        key = ok and k or nil
    else
        local ok, k = Call(ah.GetItemKeyFromItem, sel.entry.locs[1].loc)
        key = ok and k or nil
    end
    sel.key = key
    sel.askedItem = not sel.commodity
    if key then Call(ah.SendSearchQuery, key, {}, false) end
    -- No answer: ask again (the other kind of search, when it was a guess),
    -- then say so -- never "Looking it up" forever.
    sel.asks = (sel.asks or 0) + 1
    local n = sel.asks
    if C_Timer and C_Timer.After then
        C_Timer.After(ANSWER_WAIT, function()
            if S.sel ~= sel or sel.fresh or sel.needAsk or sel.asks ~= n then return end
            if n >= MAX_ASKS then Say(NO_ANSWER) return end
            if not sel.entry.known then sel.commodity = not sel.commodity end
            sel.needAsk = true
            AskSel()
            Changed()
        end)
    end
end
S.AskSel = AskSel

--- A pick waiting for its lookup: the Investing queue gives way to it.
function S.Wants() return S.sel ~= nil and S.sel.needAsk == true end

function S.Select(entry)
    if not entry then S.sel = nil Changed() return false end
    S.sel = { id = entry.id, entry = entry, commodity = entry.commodity, qty = entry.count,
              levels = {}, fresh = false, needAsk = true }
    S.message = nil
    AskSel()
    Changed()
    return true
end

--- You typed a price (copper each): it stays until another item is picked.
function S.SetPrice(c)
    local sel = S.sel
    if not (sel and Num(c)) then return end
    sel.price, sel.edited, sel.why, sel.level = math.max(1, math.floor(c)), true, "typed", nil
    sel.confirm = nil
    Changed()
end

--- A clicked listing row: 1c under it -- matching it when it's yours --
-- never under the floor (Alex). It stays like a typed price.
function S.Undercut(unit, mine)
    local sel = S.sel
    if not (sel and Num(unit) and unit > 0) then return end
    local price, why = unit - 1, "under"
    if mine then price, why = unit, "mine" end
    local floor = S.Floor(S.Vendor(sel.id))
    if floor and price < floor then price, why = floor, "floor" end
    sel.price, sel.edited, sel.why, sel.level = math.max(1, price), true, why, unit
    sel.confirm = nil
    Changed()
end

function S.SetQty(n)
    local sel = S.sel
    if not (sel and Num(n)) then return end
    sel.qty = math.max(1, math.min(sel.entry.count, math.floor(n)))
    sel.confirm = nil
    Changed()
end

--- The deposit for the selection at the chosen duration, or nil.
function S.Deposit()
    local sel = S.sel
    if not sel then return nil end
    local ah, d = AH(), S.Duration()
    local ok, v
    if sel.commodity then ok, v = Call(ah.CalculateCommodityDeposit, sel.id, d, sel.qty)
    else ok, v = Call(ah.CalculateItemDeposit, sel.entry.locs[1].loc, d, sel.qty) end
    return (ok and Num(v)) and v or nil
end

--- The item after `id` in the grid (or before it, at the end).
local function After(key)
    for i, e in ipairs(S.items) do
        if e.key == key then return S.items[i + 1] or S.items[i - 1] end
    end
end

--- Posted: take it off the grid now (the bags confirm on their update) and
-- tee up the next item (Alex) -- or the same one, if some is left.
local function Posted(sel, qty, price)
    local left = sel.entry.count - qty
    S.message = ("Posted %d at %s each"):format(qty, ns.AuctionUI and ns.AuctionUI.Money(price) or tostring(price))
    local nextEntry
    if left > 0 then
        sel.entry.count = left
        nextEntry = sel.entry
    else
        nextEntry = After(sel.entry.key)
        for i, e in ipairs(S.items) do if e.key == sel.entry.key then table.remove(S.items, i) break end end
    end
    local msg = S.message
    S.Select(nextEntry)
    S.message = msg
    Changed()
end

--- A click: post the selection.
function S.Post()
    local sel = S.sel
    if not (sel and sel.fresh and Num(sel.price) and sel.price > 0 and sel.qty > 0) then return false end
    -- Confirm only exactly what the client questioned: a price, quantity or
    -- duration changed since then posts afresh (the hunt: a corrected 1c
    -- mistype still went up at 1c through the old Confirm).
    local c = sel.confirm
    if c then
        if c.price == sel.price and c.qty == sel.qty and c.d == S.Duration() then return S.Confirm() end
        sel.confirm = nil
    end
    local ah, d, loc = AH(), S.Duration(), sel.entry.locs[1].loc
    if not sel.commodity then
        -- An item posts what that location can: never more copies than the client says
        local okA, avail = Call(ah.GetAvailablePostCount, loc)
        if okA and Num(avail) and avail > 0 and sel.qty > avail then sel.qty = avail end
    end
    local ok, needs
    S.postedAt = Now()                             -- (Blizzard's own popup for it is put away)
    if sel.commodity then ok, needs = Call(ah.PostCommodity, loc, d, sel.qty, sel.price)
    else ok, needs = Call(ah.PostItem, loc, d, sel.qty, nil, sel.price) end
    if not ok then Say("Couldn't post that") return false end
    if needs == true then
        sel.confirm = { d = d, qty = sel.qty, price = sel.price }
        Say("That price is far from the market: Confirm to post it anyway")
        return true
    end
    Posted(sel, sel.qty, sel.price)
    return true
end

--- The second click when the client asked for one.
function S.Confirm()
    local sel = S.sel
    local c = sel and sel.confirm
    if not c then return false end
    local ah, loc = AH(), sel.entry.locs[1].loc
    local ok
    if sel.commodity then ok = Call(ah.ConfirmPostCommodity, loc, c.d, c.qty, c.price)
    else ok = Call(ah.ConfirmPostItem, loc, c.d, c.qty, nil, c.price) end
    sel.confirm = nil
    if not ok then Say("Couldn't post that") return false end
    Posted(sel, c.qty, c.price)
    return true
end

-- ------------------------------------------------------------ events

--- Blizzard's popup for a post of ours: hidden now and next frame
-- (whichever of its handler and ours runs first); its OnHide drops the AH's overlay.
local function HidePopup(which)
    local hide = function() local f = rawget(_G, "StaticPopup_Hide") if f then pcall(f, which) end end
    hide()
    if C_Timer and C_Timer.After then C_Timer.After(0, hide) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
                     "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "BAG_UPDATE_DELAYED", "AUCTION_HOUSE_CLOSED",
                     "AUCTION_HOUSE_POST_ERROR", "AUCTION_HOUSE_POST_WARNING" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, event, a1)
    local sel = S.sel
    local ah = AH()
    if event == "AUCTION_HOUSE_CLOSED" then
        S.sel, S.message = nil, nil
        Changed()
    elseif event == "BAG_UPDATE_DELAYED" then
        if ns.Auction.IsOpen() then S.Refresh() end
    elseif event == "AUCTION_HOUSE_POST_WARNING" then
        -- Our post: Blizzard's AH also pops its own "Are you sure" for it,
        -- whose Accept posts nothing (its sell frames hold no post). Ours is
        -- the Confirm click. Put it away after Blizzard's handler shows it.
        if S.postedAt and Now() - S.postedAt < 5 then HidePopup(event) end
    elseif event == "AUCTION_HOUSE_POST_ERROR" then
        if S.postedAt and Now() - S.postedAt < 5 then HidePopup(event) end
        Say("The auction house didn't take that post")
        if ns.Auction.IsOpen() then S.Refresh() end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if sel and sel.needAsk then AskSel() end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        -- Either kind of answer settles what it is (the guess can be wrong)
        if not (sel and not sel.needAsk and (Num(a1) and a1 == sel.id or (not Num(a1) and sel.commodity))) then return end
        sel.commodity, sel.entry.commodity, sel.entry.known = true, true, true
        local levels = {}
        local ok, n = Call(ah.GetNumCommoditySearchResults, sel.id)
        for i = 1, (ok and Num(n)) and n or 0 do
            local okR, r = Call(ah.GetCommoditySearchResultInfo, sel.id, i)
            if okR and type(r) == "table" and Num(r.unitPrice) and Num(r.quantity) then
                levels[#levels + 1] = { unit = r.unitPrice, qty = r.quantity,
                                        mine = r.containsOwnerItem == true or (Num(r.numOwnerItems) and r.numOwnerItems > 0) or false }
            end
        end
        sel.levels, sel.fresh = levels, true
        if S.message == NO_ANSWER then S.message = nil end
        Reprice(sel)
        Changed()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        if not (sel and not sel.needAsk and type(a1) == "table" and a1.itemID == sel.id) then return end
        -- Only the key we asked for: another suffix's answer (a Snipe click on
        -- "of the Monkey") mustn't price "of the Eagle". When we searched it
        -- as a commodity (a guess), the server's item answer is ours.
        if sel.askedItem then
            if KeyStr(a1) ~= KeyStr(sel.key) then return end
        elseif sel.entry.known then
            return
        else
            sel.key = a1
        end
        sel.commodity, sel.entry.commodity, sel.entry.known = false, false, true
        local levels = {}
        local ok, n = Call(ah.GetNumItemSearchResults, sel.key)
        for i = 1, (ok and Num(n)) and n or 0 do
            local okR, r = Call(ah.GetItemSearchResultInfo, sel.key, i)
            if okR and type(r) == "table" and Num(r.buyoutAmount) and r.buyoutAmount > 0 then
                local q = Num(r.quantity) and r.quantity > 0 and r.quantity or 1
                levels[#levels + 1] = { unit = math.floor(r.buyoutAmount / q), qty = q, mine = r.containsOwnerItem == true }
            end
        end
        sel.levels, sel.fresh = levels, true
        if S.message == NO_ANSWER then S.message = nil end
        Reprice(sel)
        Changed()
    end
end)
