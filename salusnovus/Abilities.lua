--[[ Salus Novus -- Abilities: what Alex says about an ability, on top of what
the logs say.

MerkUI's Abilities.lua (retail) cut to what Salus Novus has a use for: a
RENAME, a COLOUR the name carries in every anchor, the ROLES it shows for,
and ROUTING to the anchors that are opt-outable (Ability Queue, Ability
Preview) or opt-in (Messages). No instruction, no categories, no audio,
no aura sounds (Alex, 2026-09-19).

Stored in ns.db.abilities keyed by tostring(spellID):
  { rename = "Knock", color = { r, g, b },
    roles = nil | "none" | { tank = true, healer = true, dps = true },
    route = { queue = false, preview = false, messages = true } }
Absent field = the default. A record with no fields left is removed.
]]

local _, ns = ...

local A = {}
ns.Abilities = A

-- Which anchors an ability goes to when it says nothing: opt-out for the
-- queue and the preview, opt-in for Messages (big text is for the casts
-- you pick -- Alex).
A.ROUTE_DEFAULT = { queue = true, preview = true, messages = false }
A.ROLES = { "tank", "healer", "dps" }

-- Keys are spell ids from OUR data files, never the client's secret ids;
-- a secret key still has no usable identity, so refuse it (MerkUI: every
-- secret key collapsed onto one record that they then overwrote in turn).
local function K(key)
    if key == nil or ns.IsSecret(key) then return nil end
    if type(key) == "string" then return key end
    local ok, s = pcall(tostring, key)
    return ok and s or nil
end
A.Key = K

local function DB()
    if not ns.db then return nil end
    ns.db.abilities = ns.db.abilities or {}
    return ns.db.abilities
end

--- The override record for an ability (nil unless one exists, or `create`).
function A.Get(key, create)
    local db = DB()
    local k = K(key)
    if not db or k == nil then return nil end
    local e = db[k]
    if not e and create then
        e = {}
        db[k] = e
    end
    return e
end

-- Drop the record once nothing is left in it, so a cleared ability leaves
-- no trace in the saved variables.
local function Purge(k, e)
    if e.route and next(e.route) == nil then e.route = nil end
    if next(e) == nil then DB()[k] = nil end
end

function A.Set(key, field, value)
    local e = A.Get(key, true)
    if not e then return end
    if value == "" then value = nil end
    e[field] = value
    Purge(K(key), e)
    ns.ApplyAll()
end

--- Clear everything said about an ability.
function A.Reset(key)
    local db, k = DB(), K(key)
    if not db or k == nil then return end
    db[k] = nil
    ns.ApplyAll()
end

function A.Rename(key)
    local e = A.Get(key)
    local s = e and e.rename
    if type(s) == "string" and s ~= "" then return s end
    return nil
end

--- r, g, b of the override, or nil.
function A.Color(key)
    local e = A.Get(key)
    local c = e and e.color
    if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        return c.r, c.g, c.b
    end
    return nil
end

--------------------------------------------------------------------------------
-- Roles
--------------------------------------------------------------------------------
--- "tank" | "healer" | "dps" | nil. Forever assigns roles through the
-- group finder only; GetSpecialization is unknown on this content, so an
-- unassigned role is nil, which means NO filtering -- an ability is never
-- hidden because the client would not say who you are.
function A.MyRole()
    if type(UnitGroupRolesAssigned) ~= "function" then return nil end
    local ok, role = pcall(UnitGroupRolesAssigned, "player")
    if not ok or ns.IsSecret(role) then return nil end
    if role == "TANK" then return "tank" end
    if role == "HEALER" then return "healer" end
    if role == "DAMAGER" then return "dps" end
    return nil
end

--- nil -> everyone; "none" -> nobody; a set -> those roles.
function A.RoleOK(key)
    local e = A.Get(key)
    local r = e and e.roles
    if r == nil then return true end
    if r == "none" then return false end
    if type(r) == "table" then
        local mine = A.MyRole()
        if mine == nil then return true end     -- no role assigned: fail open
        return r[mine] and true or false
    end
    return true
end

--- Is `role` in the ability's set (as the card's toggles read it)?
function A.HasRole(key, role)
    local e = A.Get(key)
    local r = e and e.roles
    if r == nil then return true end
    if r == "none" then return false end
    return type(r) == "table" and r[role] and true or false
end

--- Toggle one role. A full set collapses to nil, an empty one to "none".
function A.ToggleRole(key, role)
    local set = {}
    for _, r in ipairs(A.ROLES) do set[r] = A.HasRole(key, r) or nil end
    set[role] = (not set[role]) and true or nil
    if set.tank and set.healer and set.dps then
        A.Set(key, "roles", nil)
    elseif not (set.tank or set.healer or set.dps) then
        A.Set(key, "roles", "none")
    else
        A.Set(key, "roles", set)
    end
end

--------------------------------------------------------------------------------
-- Routing
--------------------------------------------------------------------------------
--- The raw route entry: true / false / nil (default).
function A.Route(key, anchor)
    local e = A.Get(key)
    local r = e and e.route
    if type(r) ~= "table" then return nil end
    return r[anchor]
end

--- Does this ability go to `anchor`? Role first: an ability hidden from
-- the player's role goes nowhere. nil in the record means the default.
function A.Routed(key, anchor)
    if not A.RoleOK(key) then return false end
    local r = A.Route(key, anchor)
    if r == nil then return A.ROUTE_DEFAULT[anchor] ~= false end
    return r and true or false
end

--- Set a route; storing the default clears the entry so the record can
-- vanish again.
function A.SetRoute(key, anchor, on)
    local e = A.Get(key, true)
    if not e then return end
    on = on and true or false
    e.route = e.route or {}
    if on == (A.ROUTE_DEFAULT[anchor] ~= false) then e.route[anchor] = nil else e.route[anchor] = on end
    Purge(K(key), e)
    ns.ApplyAll()
end
