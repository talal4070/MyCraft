--[[
MyCraft Kit - protection engine
Copyright (C) 2026 MyCraft contributors, LGPL-3.0-or-later

A deliberately small, tap-friendly protection system:
  * one tap claims a square of land around the player
  * two taps claim a box between two marked corners
  * zones can be opened (anyone may build) or closed (owner only)
  * it hooks into minetest.is_protected so every core interaction path
    (digging, placing, using, buckets, pistons, ...) is covered

This file knows nothing about formspecs; gui.lua drives it.
]]

local K = mycraft_kit
local S = K.S

local DELIM = core.get_worldpath() .. DIR_DELIM
K.file = DELIM .. "mycraft_kit.json"

-- id -> {id=, owner=, name=, p1={x,y,z}, p2={x,y,z}, open=bool}
K.zones = {}
K.next_id = 1

local function sort_pos(a, b)
	local p1, p2 = {}, {}
	p1.x = math.min(a.x, b.x); p2.x = math.max(a.x, b.x)
	p1.y = math.min(a.y, b.y); p2.y = math.max(a.y, b.y)
	p1.z = math.min(a.z, b.z); p2.z = math.max(a.z, b.z)
	return p1, p2
end
K.sort_pos = sort_pos

local function inside(pos, p1, p2)
	return pos.x >= p1.x and pos.x <= p2.x
		and pos.y >= p1.y and pos.y <= p2.y
		and pos.z >= p1.z and pos.z <= p2.z
end

--------------------------------------------------------------------------
-- persistence
--------------------------------------------------------------------------
function K.load()
	K.zones = {}
	K.next_id = 1
	local f = io.open(K.file, "r")
	if not f then
		return
	end
	local raw = f:read("*a")
	f:close()
	local data = core.parse_json(raw)
	if type(data) ~= "table" then
		core.log("warning", "[mycraft_kit] unreadable protection file, starting empty")
		return
	end
	for _, z in pairs(data.zones or {}) do
		if z.id and z.owner and z.p1 and z.p2 then
			K.zones[z.id] = z
			if z.id >= K.next_id then
				K.next_id = z.id + 1
			end
		end
	end
	core.log("action", "[mycraft_kit] loaded " .. K.count_all() .. " protection zone(s)")
end

function K.save()
	local list = {}
	for _, z in pairs(K.zones) do
		list[#list + 1] = z
	end
	core.safe_file_write(K.file, core.write_json({ version = 1, zones = list }))
end

--------------------------------------------------------------------------
-- queries
--------------------------------------------------------------------------
function K.count_all()
	local n = 0
	for _ in pairs(K.zones) do
		n = n + 1
	end
	return n
end

function K.count_of(name)
	local n = 0
	for _, z in pairs(K.zones) do
		if z.owner == name then
			n = n + 1
		end
	end
	return n
end

function K.owner_of(name)
	local n = 0
	for _, z in pairs(K.zones) do
		if z.owner == name then
			n = n + 1
		end
	end
	return n
end

--- Zone covering pos, if any. Returns the zone or nil.
function K.zone_at(pos)
	for _, z in pairs(K.zones) do
		if inside(pos, z.p1, z.p2) then
			return z
		end
	end
	return nil
end

function K.zones_of(name)
	local list = {}
	for _, z in pairs(K.zones) do
		if z.owner == name then
			list[#list + 1] = z
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

--- True when name may build at pos.
function K.can_build(name, pos)
	local z = K.zone_at(pos)
	if not z then
		return true
	end
	if z.open then
		return true
	end
	if z.owner == name then
		return true
	end
	return core.check_player_privs(name, { protection_bypass = true })
end

--------------------------------------------------------------------------
-- creating / removing
--------------------------------------------------------------------------
local MAX_ZONES = 16
K.max_zones = MAX_ZONES

--- Validates and stores a new zone. Returns id or nil, message.
function K.add_zone(owner, p1, p2, label)
	local count = K.count_of(owner)
	if count >= MAX_ZONES then
		return nil, S("You already protect the maximum of @1 areas. Remove one first.", MAX_ZONES)
	end
	p1, p2 = sort_pos(vector.round(p1), vector.round(p2))
	local sx = p2.x - p1.x + 1
	local sz = p2.z - p1.z + 1
	if sx * sz > K.max_footprint or sx <= 0 or sz <= 0 then
		return nil, S("That area is too large. Try a smaller one.")
	end
	-- refuse zones that overlap somebody else's closed zone
	for _, z in pairs(K.zones) do
		local overlaps = p1.x <= z.p2.x and p2.x >= z.p1.x
			and p1.y <= z.p2.y and p2.y >= z.p1.y
			and p1.z <= z.p2.z and p2.z >= z.p1.z
		if overlaps and z.owner ~= owner and not z.open then
			return nil, S("That overlaps land protected by @1.", z.owner)
		end
	end
	local id = K.next_id
	K.next_id = K.next_id + 1
	K.zones[id] = {
		id = id,
		owner = owner,
		name = label or (S("Area") .. " " .. id),
		p1 = p1,
		p2 = p2,
		open = false,
	}
	K.save()
	return id
end

function K.remove_zone(id, name)
	local z = K.zones[id]
	if not z then
		return false, S("That area no longer exists.")
	end
	if z.owner ~= name and not core.check_player_privs(name, { protection_bypass = true }) then
		return false, S("That area is not yours.")
	end
	K.zones[id] = nil
	K.save()
	return true, S("Protection removed.")
end

function K.set_open(id, name, open)
	local z = K.zones[id]
	if not z then
		return false, S("That area no longer exists.")
	end
	if z.owner ~= name and not core.check_player_privs(name, { protection_bypass = true }) then
		return false, S("That area is not yours.")
	end
	z.open = open or nil
	K.save()
	return true, open and S("Area opened: everyone may build here now.")
		or S("Area closed: only you may build here.")
end

--------------------------------------------------------------------------
-- claim helpers (one tap / two corners)
--------------------------------------------------------------------------
K.max_footprint = 128 * 128

local function player_pos(name)
	local player = core.get_player_by_name(name)
	if not player then
		return nil
	end
	return player:get_pos()
end

--- Claims a square of `radius` around the player.
function K.claim_around(name, radius)
	local pos = player_pos(name)
	if not pos then
		return false, S("You are not in the game.")
	end
	radius = tonumber(radius) or 12
	local p = vector.round(pos)
	local p1 = { x = p.x - radius, y = p.y - 24, z = p.z - radius }
	local p2 = { x = p.x + radius, y = p.y + 48, z = p.z + radius }
	local id, err = K.add_zone(name, p1, p2, (S("Home area") .. " " .. (K.count_of(name) + 1)))
	if not id then
		return false, err
	end
	return true, S("Protected! This land is now yours (area #@1).", id)
end

--- Uses the two marked corners.
function K.claim_between(name, first, second)
	if not (first and second) then
		return false, S("Mark both corners first: stand at a corner and tap Mark.")
	end
	local id, err = K.add_zone(name, first, second, (S("Area") .. " " .. (K.count_of(name) + 1)))
	if not id then
		return false, err
	end
	return true, S("Protected the marked area (area #@1).", id)
end

--------------------------------------------------------------------------
-- hook into the engine
--
-- Order matters: this has to fail closed. If another protection mod (Areas,
-- for example) is also enabled, we still say "protected" rather than
-- letting its zones through - and we hand the question on to it first so
-- its own admin and open-area rules keep working.
--------------------------------------------------------------------------
local old_is_protected = core.is_protected
function core.is_protected(pos, name)
	if old_is_protected(pos, name) then
		return true
	end
	if not K.can_build(name, pos) then
		return true
	end
	return false
end

local last_warn = {}
core.register_on_protection_violation(function(pos, name)
	local zone = K.zone_at(pos)
	if not zone or K.can_build(name, pos) then
		return
	end
	local now = core.get_us_time() / 1000000
	if last_warn[name] and now - last_warn[name] < 5 then
		return
	end
	last_warn[name] = now
	core.chat_send_player(name, core.colorize("#ff9d5c",
		S("This land is protected by @1 - you cannot build here.", zone.owner)))
end)

core.register_on_leaveplayer(function(player)
	last_warn[player:get_player_name()] = nil
end)

--------------------------------------------------------------------------
-- interop with the Areas mod, when the player enabled both
--
-- The Kit page drives Areas too, so a world with "areas" ticked keeps
-- working through the same buttons, and Areas' own area limits, admin
-- privileges and open/closed flag are respected instead of duplicated.
--------------------------------------------------------------------------
local has_areas = core.global_exists("areas") and type(areas) == "table"
	and type(areas.areas) == "table"

function K.using_areas()
	return has_areas and not K.force_own
end

function K.areas_of(name)
	local list = {}
	for id, area in pairs(areas.areas) do
		if area.owner == name then
			local copy = {}
			for k, v in pairs(area) do
				copy[k] = v
			end
			copy.id = id
			list[#list + 1] = copy
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

local function areas_claim(name, pos1, pos2)
	local can, err = areas:canPlayerAddArea(pos1, pos2, name)
	if not can then
		return false, err
	end
	local id = areas:add(name, S("Area") .. " " .. (areas:getAreasCount(name) + 1), pos1, pos2)
	areas:save()
	return true, S("Protected! This land is now yours (area #@1).", id)
end

-- take over the two claim paths when Areas is the active backend
local own_claim_around = K.claim_around
function K.claim_around(name, radius)
	if not K.using_areas() then
		return own_claim_around(name, radius)
	end
	local player = core.get_player_by_name(name)
	if not player then
		return false, S("You are not in the game.")
	end
	radius = tonumber(radius) or 12
	local p = vector.round(player:get_pos())
	return areas_claim(name,
		{ x = p.x - radius, y = p.y - 24, z = p.z - radius },
		{ x = p.x + radius, y = p.y + 48, z = p.z + radius })
end

local own_claim_between = K.claim_between
function K.claim_between(name, first, second)
	if not K.using_areas() then
		return own_claim_between(name, first, second)
	end
	if not (first and second) then
		return false, S("Mark both corners first: stand at a corner and tap Mark.")
	end
	return areas_claim(name, first, second)
end

local own_remove = K.remove_zone
function K.remove_zone(id, name)
	if not K.using_areas() then
		return own_remove(id, name)
	end
	if not areas:isAreaOwner(id, name) then
		return false, S("That area is not yours.")
	end
	areas:remove(id)
	areas:save()
	return true, S("Protection removed.")
end

local own_open = K.set_open
function K.set_open(id, name, open)
	if not K.using_areas() then
		return own_open(id, name, open)
	end
	if not areas:isAreaOwner(id, name) then
		return false, S("That area is not yours.")
	end
	areas.areas[id].open = open or nil
	areas:save()
	return true, open and S("Area opened: everyone may build here now.")
		or S("Area closed: only you may build here.")
end

--------------------------------------------------------------------------
-- backend-aware accessors used by the page and the HUD badge
--------------------------------------------------------------------------
function K.list_zones(name)
	if K.using_areas() then
		return K.areas_of(name)
	end
	return K.zones_of(name)
end

function K.visible_count(name)
	if K.using_areas() then
		return areas:getAreasCount(name)
	end
	return K.count_of(name)
end

function K.visible_limit()
	if K.using_areas() and areas.config then
		return areas.config.self_protection_max_areas or K.max_zones
	end
	return K.max_zones
end

--- One-line description of the protection covering pos for name.
function K.status_at(name, pos)
	if not pos then
		return nil
	end
	if K.using_areas() then
		local mine, other = false, nil
		for _, area in pairs(areas:getAreasAtPos(pos)) do
			if area.owner == name then
				mine = true
			elseif not other then
				other = area.owner
			end
		end
		if mine then
			return S("Your protected area")
		elseif other then
			return S("Protected by @1", other)
		end
		return S("Open land - not protected")
	end
	local zone = K.zone_at(pos)
	if not zone then
		return S("Open land - not protected")
	elseif zone.owner == name then
		return S("Your protected area")
	end
	return S("Protected by @1", zone.owner)
end

--------------------------------------------------------------------------
-- backend-aware accessors used by the page and the HUD badge
--------------------------------------------------------------------------
function K.list_zones(name)
	if K.using_areas() then
		return K.areas_of(name)
	end
	return K.zones_of(name)
end

function K.visible_count(name)
	if K.using_areas() then
		return areas:getAreasCount(name)
	end
	return K.count_of(name)
end

function K.visible_limit()
	if K.using_areas() and areas.config then
		return areas.config.self_protection_max_areas or K.max_zones
	end
	return K.max_zones
end

--- One-line description of the protection covering pos for name.
function K.status_at(name, pos)
	if not pos then
		return nil
	end
	if K.using_areas() then
		local mine, other = false, nil
		for _, area in pairs(areas:getAreasAtPos(pos)) do
			if area.owner == name then
				mine = true
			elseif not other then
				other = area.owner
			end
		end
		if mine then
			return S("Your protected area")
		elseif other then
			return S("Protected by @1", other)
		end
		return S("Open land - not protected")
	end
	local zone = K.zone_at(pos)
	if not zone then
		return S("Open land - not protected")
	elseif zone.owner == name then
		return S("Your protected area")
	end
	return S("Protected by @1", zone.owner)
end

K.load()
