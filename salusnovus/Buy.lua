--[[ Salus Novus -- Buy: search by name, or a whole shopping list at once.

Alex's rules (2026-10-05):
  * a search box, and shopping lists: made here, imported (one item name
    per line, no quantities) and exported
  * "Search list" searches every line of a list at once
  * each line has an Exact check box: exact name, or the name contains it
  * no "want" column; a commodity's Buy starts at the cheapest listing's
    quantity

  B.Search(text)    one browse search
  B.SearchList()    every line of the current list, one browse at a time
                    (minding the throttle, and never during an AH scan: a
                    browse would cut the scan short)
  B.View()          the rows to show (a list shows every line, searched or not)
  B.Select(row)     look the item up: a commodity's price levels, or an
                    item's auctions (yours left out)
  B.Buy()           from a click: a commodity starts the purchase (the
                    client's quote arms B.Confirm, a second click); an item
                    buys the cheapest auction (PlaceBid)

Lists live account-wide in SalusNovusDB.ahLists = { lists = { { name,
items = { { name, exact } } } }, current }.
]]

local _, ns = ...

local B = {}
ns.Buy = B

local Num, Str = ns.Num, ns.Str
local BROWSE_TIMEOUT, MAX_PAGES, SEARCH_TIMEOUT = 4, 5, 3

local function AH() return rawget(_G, "C_AuctionHouse") end
local function A() return ns.Auction end
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
local function Changed() if B.OnChange then B.OnChange() end end
local function Say(m) B.message = m; Changed() end
local function KeyStr(k) return ns.Sell and ns.Sell.KeyStr(k) or tostring(k and k.itemID) end

-- ------------------------------------------------------------ lists

function B.Store()
    if type(SalusNovusDB) ~= "table" then return nil end
    local s = SalusNovusDB.ahLists
    if type(s) ~= "table" then s = { lists = {}, current = nil } SalusNovusDB.ahLists = s end
    if type(s.lists) ~= "table" then s.lists = {} end
    -- the list picked last session comes back picked: list mode with it
    -- (search mode with a saved list errored in View and stuck -- sweep 3)
    if not B.synced then
        B.synced = true
        if s.current and s.lists[s.current] then B.mode = "list" else s.current = nil end
    end
    return s
end

function B.Lists() local s = B.Store() return s and s.lists or {} end
function B.Current()
    local s = B.Store()
    return s and s.current and s.lists[s.current] or nil, s and s.current
end

--- A search under way stops: its answers would land on lines that moved,
-- or on another list (the sweep). Late answers find nothing waiting.
local function Abort()
    local r = B.run
    if r.state == "more" then r.state = "idle" r.moreAsk = (r.moreAsk or 0) + 1 return end   -- (its page landed on a list: sweep 3)
    if r.state ~= "searching" then return end
    r.state, r.waiting, r.throttled, r.afterScan, r.queue = "idle", nil, nil, nil, {}
end
B.Abort = Abort

function B.Pick(i)
    local s = B.Store()
    if not s then return end
    Abort()
    s.current = (i and s.lists[i]) and i or nil
    B.mode = s.current and "list" or "search"
    B.results = {}
    Changed()
end

local function Trim(x) return (tostring(x or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function B.NewList(name)
    local s = B.Store()
    name = Trim(name)
    if not s or name == "" then return nil end
    s.lists[#s.lists + 1] = { name = name, items = {} }
    B.Pick(#s.lists)
    return #s.lists
end

function B.DeleteList(i)
    local s = B.Store()
    if not (s and s.lists[i]) then return end
    table.remove(s.lists, i)
    B.Pick(nil)
end

--- One item name per line (blank lines skipped, no quantities -- Alex);
-- every line exact until you untick it.
function B.Parse(text)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local n = Trim(line)
        if n ~= "" then out[#out + 1] = { name = n, exact = true } end
    end
    return out
end

function B.Import(name, text)
    local items = B.Parse(text)
    if #items == 0 then return nil end
    local i = B.NewList(name ~= nil and Trim(name) ~= "" and name or "Imported")
    if i then B.Lists()[i].items = items end
    Changed()
    return i, #items
end

function B.Export(i)
    local l = B.Lists()[i]
    if not l then return "" end
    local lines = {}
    for _, it in ipairs(l.items) do lines[#lines + 1] = it.name end
    return table.concat(lines, "\n")
end

function B.AddItem(name)
    local l = B.Current()
    name = Trim(name)
    if not l or name == "" then return false end
    l.items[#l.items + 1] = { name = name, exact = true }
    Changed()
    return true
end

function B.RemoveItem(idx)
    local l = B.Current()
    if not (l and l.items[idx]) then return end
    if B.mode == "list" then Abort() end
    table.remove(l.items, idx)
    if B.results then table.remove(B.results, idx) end
    Changed()
end

function B.SetExact(idx, on)
    local l = B.Current()
    if not (l and l.items[idx]) then return end
    l.items[idx].exact = on and true or false
    Changed()
end

-- ------------------------------------------------------------ searching

B.mode = "search"
B.results = {}       -- search: { rows }; list: [line index] = { rows } (nil = not searched yet)
B.run = { state = "idle" }

local function NameOf(id)
    local ci = rawget(_G, "C_Item")
    local ok, n = Call(ci and ci.GetItemNameByID, id)
    n = ok and Str(n) or nil
    if not n and ci and ci.RequestLoadItemDataByID then Call(ci.RequestLoadItemDataByID, id) end
    return n
end

--- Does a browse row answer a list line? (A name not loaded yet counts, so
-- nothing vanishes before the client knows it; the view re-checks.)
function B.Matches(line, id)
    local n = NameOf(id)
    if not n then return true end
    local a, b = n:lower(), line.name:lower()
    if line.exact then return a == b end
    return a:find(b, 1, true) ~= nil
end

local function Rows()
    local ok, rows = Call(AH().GetBrowseResults)
    local out = {}
    for _, r in ipairs((ok and type(rows) == "table") and rows or {}) do
        if type(r) == "table" and type(r.itemKey) == "table" and Num(r.itemKey.itemID) then
            out[#out + 1] = { id = r.itemKey.itemID, key = r.itemKey, listed = Num(r.totalQuantity) and r.totalQuantity or 0,
                              cheapest = Num(r.minPrice) and r.minPrice or nil,
                              level = Num(r.itemKey.itemLevel) and r.itemKey.itemLevel or 0 }
        end
    end
    return out
end

-- ------------------------------------------------------------ browsing

-- Alex: the Buy tab browses like the AH's own -- categories, filters, sorts,
-- more results on demand. The categories are Blizzard's own tree
-- (AuctionCategories, built by its AH interface: name, filters =
-- itemClassFilters, implicitFilter, subCategories); a query is what its
-- AuctionHouseFrameMixin:SendBrowseQueryInternal sends.
B.cat = nil                     -- { i, j, k }: the picked category, nil = all
B.filters = { minLevel = nil, maxLevel = nil, quality = nil, usable = false }
B.sort = { key = "level", reverse = true }          -- highest level first (Alex)
B.QUALITIES = { { nil, "Any quality" }, { 1, "Common+" }, { 2, "Uncommon+" }, { 3, "Rare+" }, { 4, "Epic+" } }
local QUALITY_FILTER = { [0] = "PoorQuality", [1] = "CommonQuality", [2] = "UncommonQuality", [3] = "RareQuality",
                         [4] = "EpicQuality", [5] = "LegendaryQuality", [6] = "ArtifactQuality" }
local SORT_ORDER = { name = "Name", level = "Level", price = "Price" }

function B.Categories() return rawget(_G, "AuctionCategories") or {} end

--- The picked category's node, or nil (all).
function B.Category(path)
    path = path or B.cat
    if not path then return nil end
    local node, list = nil, B.Categories()
    for _, i in ipairs(path) do
        node = list[i]
        if not node then return nil end
        list = node.subCategories or {}
    end
    return node
end

local function FilterEnum(name)
    local e = rawget(_G, "Enum") and Enum.AuctionHouseFilter
    return e and e[name]
end

--- The browse query: the search text, the level range, the quality and
-- usable filters, the category's own filters, and the sort.
function B.Query(text)
    local f = B.filters
    -- The quality flags always go, every one for "Any" (as the AH's own
    -- defaults): a query with another filter (Usable only, a category's)
    -- and no quality flag allows no quality, and found nothing (Alex)
    local filters = {}
    for q = f.quality or 0, 6 do
        local v = FilterEnum(QUALITY_FILTER[q])
        if v ~= nil then filters[#filters + 1] = v end
    end
    if f.usable then
        local v = FilterEnum("UsableOnly")
        if v ~= nil then filters[#filters + 1] = v end
    end
    local node = B.Category()
    if node and node.implicitFilter ~= nil then filters[#filters + 1] = node.implicitFilter end
    local sorts = {}
    local so = rawget(_G, "Enum") and Enum.AuctionHouseSortOrder
    local order = so and so[SORT_ORDER[B.sort.key] or ""]
    if order ~= nil then sorts[1] = { sortOrder = order, reverseSort = B.sort.reverse and true or false } end
    return { searchString = text or "", sorts = sorts, minLevel = f.minLevel, maxLevel = f.maxLevel,
             filters = filters, itemClassFilters = node and node.filters or {} }
end

function B.PickCategory(path, text)
    B.cat = path
    return B.Browse(text or B.query or "")          -- what's in the box now (the sweep)
end

function B.SetFilter(k, v)
    B.filters[k] = v
    Changed()
end

--- Unfilter (Alex): back to All -- no category, no level range, any
-- quality, usable or not; the search text stays and is browsed again.
function B.Unfilter()
    B.cat = nil
    B.filters = { minLevel = nil, maxLevel = nil, quality = nil, usable = false }
    B.more = false
    -- the old category's answer mustn't land as All's (sweep 3): browsed
    -- afresh -- All with no text is everything, as picking All does
    if B.mode ~= "list" then
        local r = B.run
        if r.state == "searching" or r.state == "more" then r.state, r.waiting, r.afterScan = "idle", nil, nil end
        if B.Browse(B.query or "") then return true end
    end
    B.results = B.mode == "list" and B.results or {}
    Changed()
    return true
end

--- A category for the tree? Not the WoW Token (Forever has none -- Alex).
function B.Shown(c)
    if type(c) ~= "table" then return false end
    if type(c.flags) == "table" then
        for k, v in pairs(c.flags) do if v and tostring(k):upper():find("TOKEN") then return false end end
    end
    return not tostring(c.name or ""):lower():find("token", 1, true)
end

--- Sort by a column; the same column again reverses it. Sorted here at
-- once and asked of the server for what comes next.
function B.SortBy(key)
    if B.sort.key == key then B.sort.reverse = not B.sort.reverse
    else B.sort.key, B.sort.reverse = key, false end
    Changed()
end

local function SortRows(rows)
    local k, rev = B.sort.key, B.sort.reverse
    local function val(r)
        if k == "name" then return (NameOf(r.id) or ""):lower()
        elseif k == "level" then return r.level or 0
        elseif k == "listed" then return r.listed or 0 end
        return r.cheapest or math.huge
    end
    table.sort(rows, function(a, b)
        local va, vb = val(a), val(b)
        if va ~= vb then if rev then return va > vb end return va < vb end
        return a.id < b.id
    end)
    return rows
end

local Next
local Next2

--- Waiting for the scan: it may pause instead of ending (back on Buy, the
-- Gate holds it) -- then go ahead, as Next would (it waited for ever: sweep 3).
local function WaitScan(r)
    r.waitSeq = (r.waitSeq or 0) + 1
    local seq = r.waitSeq
    local function check()
        if not (r.afterScan and r.waitSeq == seq and r.state == "searching") then return end
        if A().paused or not A().scan.running then r.afterScan = nil B.message = nil Next() return end
        if C_Timer and C_Timer.After then C_Timer.After(1, check) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, check) end
end

local function Landed(r)
    local rows = Rows()
    if B.mode == "search" and r.queue[r.i].search then
        B.results = rows
        local okF, full = Call(AH().HasFullBrowseResults)
        B.more = okF and full == false                -- the rest comes on "More results"
        B.moreSeq = A().browseSeq                     -- ...of this browse, while it's the client's last
    else B.results[r.queue[r.i].line] = rows end
    r.waiting = nil
    r.i = r.i + 1
    Changed()
    Next()
end

Next = function()
    local r = B.run
    if r.state ~= "searching" or r.waiting then return end
    if not A().IsOpen() then r.state = "idle" Changed() return end
    if r.i > #r.queue then r.state = "idle" Changed() return end
    -- a browse would cut the scan short: after it -- unless it's paused
    -- (Alex: away from Snipe/Investing the scan gives way; this cuts it short)
    if A().scan.running and not A().paused then
        r.afterScan = true
        WaitScan(r)
        Say("Waiting for the scan to finish")
        return
    end
    local ah = AH()
    local okR, ready = Call(ah.IsThrottledMessageSystemReady)
    if okR and ready == false then
        r.throttleSeq = (r.throttleSeq or 0) + 1
        local seq = r.throttleSeq
        r.throttled = seq
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() if r.throttled == seq then r.throttled = nil Next() end end)
        end
        return
    end
    local q = r.queue[r.i]
    r.pages = 1
    r.askSeq = (r.askSeq or 0) + 1
    local seq = r.askSeq
    A().HookBrowse()                                  -- (every browse counted)
    if not Call(ah.SendBrowseQuery, q.query or { searchString = q.text, sorts = {}, filters = {}, itemClassFilters = {} }) then
        r.i = r.i + 1
        return Next()
    end
    r.browseSeq = A().browseSeq
    r.waiting = q
    B.message = nil
    Changed()
    if C_Timer and C_Timer.After then
        C_Timer.After(BROWSE_TIMEOUT, function()
            if not (r.waiting == q and r.askSeq == seq) then return end
            if A().browseSeq ~= r.browseSeq then              -- another browse (the scan's) replaced ours: ask again
                r.waiting = nil
                if A().scan.running and not A().paused then r.afterScan = true WaitScan(r) else Next() end
                return
            end
            Landed(r)                                         -- what came, if anything
        end)
    end
end

local function Start(queue)
    local r = B.run
    r.queue, r.i, r.state, r.waiting, r.throttled, r.afterScan = queue, 1, "searching", nil, nil, nil
    Changed()
    Next()
end

--- A browse: the text (may be empty with a category picked), the
-- category, the filters and the sort, as the AH's own search does.
function B.Browse(text)
    text = Trim(text)
    if not A().IsOpen() then return false end        -- no text and All: everything, as the AH's own
    if B.mode == "list" then B.Pick(nil) end
    B.mode, B.query, B.more = "search", text, false
    Start({ { text = text, search = true, query = B.Query(text) } })
    return true
end
function B.Search(text) return B.Browse(text) end

--- More to come of Buy's browse -- while it's still the client's last one
-- (a scan's browse replaces it: the sweep).
function B.HasMore() return B.more and B.moreSeq == A().browseSeq end

--- The next page of a browse.
function B.More()
    local r = B.run
    if not (B.mode == "search" and B.HasMore() and r.state == "idle" and A().IsOpen()) then return false end
    if not Call(AH().RequestMoreBrowseResults) then return false end
    r.state = "more"
    r.moreAsk = (r.moreAsk or 0) + 1
    local n = r.moreAsk
    if C_Timer and C_Timer.After then
        C_Timer.After(BROWSE_TIMEOUT, function() if r.state == "more" and r.moreAsk == n then r.state = "idle" Changed() end end)
    end
    Changed()
    return true
end

function B.SearchList()
    local l = B.Current()
    if not (l and #l.items > 0 and A().IsOpen()) then return false end
    B.mode = "list"                                 -- (the list's lines, whatever mode said: sweep 3)
    B.results = {}
    local queue = {}
    for i, it in ipairs(l.items) do queue[#queue + 1] = { text = it.name, line = i } end
    Start(queue)
    return true
end

function B.Progress()
    local r = B.run
    if r.state ~= "searching" or #r.queue < 2 then return nil end
    return (r.i - 1) / #r.queue, ("Searching %d of %d"):format(math.min(r.i, #r.queue), #r.queue)
end

table.insert(ns.Auction.onScanDone, function()
    local r = B.run
    -- a beat later: the scan ended inside a browse event that Buy's own
    -- handler sees next -- sent now, that page read as Buy's answer (sweep 3)
    if r.state == "searching" and r.afterScan then
        r.afterScan = nil
        B.message = nil
        if C_Timer and C_Timer.After then C_Timer.After(0, Next) else Next() end
    end
end)

--- One row per item (Alex: a random-suffix green came back once per suffix,
-- every row "Splitting Hatchet"): its versions' keys kept for the drill-down,
-- listed added up, the cheapest and the lowest level of them.
local function Group(rows)
    local by, out = {}, {}
    for _, row in ipairs(rows or {}) do
        local g = by[row.id]
        if not g then
            g = { id = row.id, key = row.key, keys = {}, listed = 0, cheapest = nil, level = row.level or 0 }
            by[row.id] = g
            out[#out + 1] = g
        end
        g.keys[#g.keys + 1] = row.key
        g.listed = g.listed + (row.listed or 0)
        if row.cheapest and (not g.cheapest or row.cheapest < g.cheapest) then g.cheapest = row.cheapest end
        if (row.level or 0) > 0 and (g.level == 0 or row.level < g.level) then g.level = row.level end
    end
    return out
end
B.Group = Group

--- What to show: a search's rows, or every line of the list (searched or not).
function B.View()
    local out = {}
    if B.mode ~= "list" then
        for _, row in ipairs(Group(B.results)) do out[#out + 1] = row end
        return SortRows(out)
    end
    local l = B.Current()
    if not l then return out end
    for i, it in ipairs(l.items) do
        local rows = B.results[i] and SortRows(Group(B.results[i]))      -- the headers sort within each line
        local first = true
        if rows then
            for _, row in ipairs(rows) do
                if B.Matches(it, row.id) then
                    out[#out + 1] = { id = row.id, key = row.key, keys = row.keys, listed = row.listed, cheapest = row.cheapest, level = row.level,
                                      line = i, first = first, lineName = it.name, exact = it.exact }
                    first = false
                end
            end
        end
        if first then
            out[#out + 1] = { line = i, first = true, lineName = it.name, exact = it.exact,
                              none = rows ~= nil, unsearched = rows == nil }
        end
    end
    return out
end

-- ------------------------------------------------------------ buying

B.sel = nil

local function Commodity(id) return (A().IsCommodity(id)) end   -- unknown: try it as one; the answer settles it

local function AskSel()
    local sel = B.sel
    if not (sel and sel.needAsk) then return end
    local ah = AH()
    local okR, ready = Call(ah.IsThrottledMessageSystemReady)
    if okR and ready == false then
        if C_Timer and C_Timer.After then C_Timer.After(1, AskSel) end
        return
    end
    sel.needAsk = nil
    local key = sel.keys[sel.k] or sel.key
    if sel.commodity then
        local okK, k = Call(ah.MakeItemKey, sel.id)
        key = okK and k or key
    end
    sel.askedKey = key
    Call(ah.SendSearchQuery, key, {}, false)
    sel.asks = (sel.asks or 0) + 1
    sel.keyAsks = (sel.keyAsks or 0) + 1
    local n = sel.asks
    if C_Timer and C_Timer.After then
        C_Timer.After(SEARCH_TIMEOUT, function()
            if B.sel ~= sel or (sel.fresh and not sel.more) or sel.needAsk or sel.asks ~= n then return end
            -- a gear item's version with no answer: the next one (not a
            -- commodity guess -- the later versions went unsearched: the sweep)
            if #sel.keys > 1 and not sel.commodity then
                if sel.k < #sel.keys or sel.fresh then sel.k = sel.k + 1 Next2(sel) return end
                if sel.keyAsks >= 3 then Say("No answer from the auction house; click it again to retry") return end
                sel.needAsk = true
                AskSel()
                return
            end
            if (sel.keyAsks or 0) >= 3 then Say("No answer from the auction house; click it again to retry") return end   -- (this look's asks)
            sel.commodity = not sel.commodity          -- maybe the other kind
            sel.needAsk = true
            AskSel()
        end)
    end
end

--- The next version of an item to look up, or done.
Next2 = function(sel)
    if B.sel ~= sel then return end
    sel.keyAsks = 0
    sel.more = sel.k <= #sel.keys
    if sel.more then sel.needAsk = true AskSel() end
    Changed()
end

function B.Select(row)
    if not (row and row.id) then return false end
    local old = B.sel
    if old and old.confirming then Say("Wait for the purchase to finish") return false end
    if old and old.asked and A().Owns("buy") then Call(AH().CancelCommoditiesPurchase) A().Release("buy") end
    -- A gear item's versions (suffixes, levels) are searched one by one and
    -- shown together; one key may still be a commodity (the answer settles it)
    local keys = row.keys or (row.key and { row.key }) or {}
    B.sel = { id = row.id, key = row.key, keys = keys, k = 1, commodity = #keys <= 1 and Commodity(row.id),
              levels = {}, fresh = false, needAsk = true }
    B.message = nil
    AskSel()
    Changed()
    return true
end

--- A look-up or browse of Buy's waiting for the client: background checks
-- (Cancel's) give way.
function B.Wants()
    local r = B.run
    return (B.sel ~= nil and B.sel.needAsk == true) or (r.state == "searching" and not r.waiting and not r.afterScan) or false
end

--- What `qty` costs off the cheapest levels, or nil when there aren't that many.
function B.Cost(qty)
    local sel = B.sel
    if not sel then return nil end
    local left, cost = qty, 0
    for _, l in ipairs(sel.levels) do
        local take = math.min(left, l.qty)
        cost = cost + take * l.unit
        left = left - take
        if left <= 0 then return cost end
    end
    return nil
end

function B.Available()
    local n = 0
    for _, l in ipairs(B.sel and B.sel.levels or {}) do n = n + l.qty end
    return n
end

function B.SetQty(n)
    local sel = B.sel
    if not (sel and Num(n)) or sel.asked then return end   -- a quote on its way: the amount it was asked for stands
    sel.qty = math.max(1, math.min(B.Available(), math.floor(n)))
    sel.quote = nil
    Changed()
end

--- A drilled-down listing clicked: a commodity buys through that price
-- level (every unit up to it); an item buys that very auction.
function B.PickListing(i)
    local sel = B.sel
    if not (sel and sel.fresh and sel.levels[i]) or sel.asked or sel.pending then return end
    if sel.commodity then
        local n = 0
        for k = 1, i do n = n + sel.levels[k].qty end
        sel.qty, sel.quote = n, nil
    else
        sel.pick = i
    end
    Changed()
end

--- A click: buy. A commodity starts the purchase (Confirm is the second
-- click, at the client's quote); an item buys the cheapest auction.
function B.Buy()
    local sel = B.sel
    if not (sel and sel.fresh and #sel.levels > 0 and not sel.asked and not sel.pending) then return false end
    local ah = AH()
    if sel.commodity then
        local qty = sel.qty or sel.levels[1].qty
        if not A().Claim("buy", function() sel.asked, sel.quote, sel.confirming = nil, nil, nil Changed() end) then
            Say("Another purchase is going through; try again in a moment")
            return false
        end
        if not Call(ah.StartCommoditiesPurchase, sel.id, qty) then A().Release("buy") return false end
        sel.asked = { qty = qty }
        Say("Getting a quote...")
        return true
    end
    local a = sel.levels[sel.pick or 1]
    if not Call(ah.PlaceBid, a.auctionID, a.buyout) then return false end
    sel.pending = a.auctionID
    Say("Buying...")
    return true
end

function B.Confirm()
    local sel = B.sel
    if not (sel and sel.quote and sel.asked and A().Owns("buy")) then return false end
    if not Call(AH().ConfirmCommoditiesPurchase, sel.id, sel.asked.qty) then return false end
    sel.quote, sel.confirming = nil, true
    A().Confirming("buy")                           -- nobody takes the claim from a purchase on its way
    Say("Buying...")
    return true
end

function B.Cancel()
    local sel = B.sel
    if sel and sel.confirming then return end
    if sel and sel.asked and A().Owns("buy") then Call(AH().CancelCommoditiesPurchase) end
    if sel then sel.asked, sel.quote = nil, nil end
    A().Release("buy")
    Changed()
end

local function Again(sel)
    if B.sel ~= sel then return end
    -- (asks keeps counting: rewound, a timer from before the buy took the
    -- new ask for its own and skipped a version -- sweep 3)
    sel.fresh, sel.needAsk, sel.qty = false, true, nil
    -- looked up afresh from the first version: what was bought isn't kept
    sel.levels, sel.k, sel.pick, sel.more, sel.keyAsks = {}, 1, nil, nil, 0
    AskSel()
end

-- ------------------------------------------------------------ events

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
                     "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
                     "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
                     "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
                     "AUCTION_HOUSE_CLOSED", "ITEM_DATA_LOAD_RESULT" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, event, a1, a2)
    local r, sel, ah = B.run, B.sel, AH()
    if event == "AUCTION_HOUSE_CLOSED" then
        if sel and sel.asked and A().Owns("buy") then Call(ah.CancelCommoditiesPurchase) end
        A().Release("buy")
        B.sel, B.message = nil, nil
        r.state, r.waiting, r.throttled, r.afterScan = "idle", nil, nil, nil
        B.more = false
        Changed()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        if r.state == "more" and B.mode == "search" and not A().scan.running and B.moreSeq == A().browseSeq then   -- a page asked for with "More results"
            B.results = Rows()
            local okF, full = Call(ah.HasFullBrowseResults)
            B.more = okF and full == false
            r.state = "idle"
            Changed()
            return
        end
        if not (r.state == "searching" and r.waiting) or A().scan.running or A().browseSeq ~= r.browseSeq then return end
        local okF, full = Call(ah.HasFullBrowseResults)
        -- a list line pages on its own; a browse shows its first page and
        -- the rest comes on "More results"
        if (okF and full == false) and r.pages < MAX_PAGES and not r.waiting.search then
            r.pages = r.pages + 1
            if Call(ah.RequestMoreBrowseResults) then return end
        end
        Landed(r)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if sel and sel.needAsk then AskSel()
        elseif r.throttled then r.throttled = nil Next() end
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if B.mode == "list" then Changed() end      -- names in: the exact matches settle
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if not (sel and not sel.needAsk and Num(a1) and a1 == sel.id) then return end
        local levels = {}
        local ok, n = Call(ah.GetNumCommoditySearchResults, sel.id)
        for i = 1, (ok and Num(n)) and n or 0 do
            local okR, x = Call(ah.GetCommoditySearchResultInfo, sel.id, i)
            if okR and type(x) == "table" and Num(x.unitPrice) and Num(x.quantity) then
                -- yours isn't for sale to you
                local q = x.quantity - (Num(x.numOwnerItems) and x.numOwnerItems or (x.containsOwnerItem and x.quantity or 0))
                if q > 0 then levels[#levels + 1] = { unit = x.unitPrice, qty = q } end
            end
        end
        table.sort(levels, function(p, q) return p.unit < q.unit end)
        sel.commodity, sel.levels, sel.fresh = true, levels, true
        -- the cheapest listing's quantity (Alex); a refresh keeps an amount
        -- typed (clamped to what's there) and never touches one asked for
        if not sel.asked then
            sel.qty = sel.qty and levels[1] and math.min(sel.qty, B.Available()) or (levels[1] and levels[1].qty or nil)
        end
        if B.message and B.message:find("^No answer") then B.message = nil end
        Changed()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        if not (sel and not sel.needAsk and type(a1) == "table" and a1.itemID == sel.id) then return end
        -- the version asked for (or, searched as a commodity by a guess, the
        -- server's item answer) -- read under the key it ANSWERED with (the
        -- drill-down came up empty reading the row's own key)
        if not sel.commodity and KeyStr(a1) ~= KeyStr(sel.askedKey) then return end   -- another version's
        local okI, info = Call(ah.GetItemKeyInfo, a1)
        local name = okI and type(info) == "table" and ns.Str(info.itemName) or nil
        local ok, n = Call(ah.GetNumItemSearchResults, a1)
        local have, picked = {}, sel.pick and sel.levels[sel.pick] and sel.levels[sel.pick].auctionID
        for _, l in ipairs(sel.levels) do have[l.auctionID] = true end
        for i = 1, (ok and Num(n)) and n or 0 do
            local okR, x = Call(ah.GetItemSearchResultInfo, a1, i)
            if okR and type(x) == "table" and not x.containsOwnerItem and Num(x.buyoutAmount) and x.buyoutAmount > 0
                    and Num(x.auctionID) and not have[x.auctionID] then        -- an answer again: once each
                have[x.auctionID] = true
                local q = (Num(x.quantity) and x.quantity > 0) and x.quantity or 1
                sel.levels[#sel.levels + 1] = { unit = math.floor(x.buyoutAmount / q), qty = q, buyout = x.buyoutAmount,
                                                auctionID = x.auctionID, name = name, key = a1,
                                                link = ns.Str(x.itemLink) }     -- that auction's own stats, for its tooltip
            end
        end
        table.sort(sel.levels, function(p, q) return p.unit < q.unit end)
        local wasCommodity = sel.commodity
        sel.commodity, sel.fresh, sel.pick = false, true, nil
        -- the auction picked stays picked as other versions merge in (the sweep)
        for i, l in ipairs(sel.levels) do if picked and l.auctionID == picked then sel.pick = i end end
        sel.qty = sel.levels[1] and sel.levels[1].qty or nil
        if wasCommodity then sel.k = #sel.keys + 1 else sel.k = sel.k + 1 end
        Next2(sel)
    elseif event == "COMMODITY_PRICE_UPDATED" then
        if not (sel and sel.asked and A().Owns("buy")) then return end
        if Num(a1) and Num(a2) then sel.quote = { unit = a1, total = a2 } Say(nil) end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if not (sel and sel.asked and A().Owns("buy")) then return end
        sel.asked, sel.quote = nil, nil
        A().Release("buy")
        Say("That price is gone")
        Again(sel)
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if not (sel and sel.asked and A().Owns("buy")) then return end
        A().Release("buy")
        local n = sel.asked.qty
        sel.asked, sel.quote, sel.confirming = nil, nil, nil
        Say(("Bought %d"):format(n))
        Again(sel)
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if not (sel and sel.asked and A().Owns("buy")) then return end
        A().Release("buy")
        sel.asked, sel.quote, sel.confirming = nil, nil, nil
        Say("Not bought")
        Again(sel)                                  -- what's there now (sweep 3)
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        if not (sel and sel.pending and (not Num(a1) or a1 == sel.pending)) then return end
        sel.pending = nil
        Say("Bought")
        Again(sel)
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        if not (sel and sel.pending) then return end
        sel.pending = nil
        Say("Not bought")
        Again(sel)                                  -- that auction's likely gone: look again (sweep 3)
    end
end)
