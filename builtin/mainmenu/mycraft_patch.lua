--[[
MyCraft - targeted main-menu tweaks
Copyright (C) 2026 MyCraft contributors, LGPL-3.0-or-later

The theme handles the look. This file makes three behavioural changes that
a theme cannot make:

1. Captions     "Start Game / Join Game / Content" become
                "Play / Servers / Store".
2. Servers      the public server list is grouped by region, closest first,
                instead of one long undifferentiated list.
3. Store        ContentDB is asked for the whole catalogue. The stock query
                sends engine_version=2.0.15, which ContentDB applies as a hard
                filter and which hid most games (Minetest Game and VoxeLibre
                among them). Protocol compatibility is still enforced by
                ContentDB when a specific release is downloaded.

Nothing else is rewritten: every stock menu action still does what it did.
]]

mycraft_patch = { installed = false }

--------------------------------------------------------------------------
-- 1. captions
--------------------------------------------------------------------------
local CAPTIONS = {
	["start game"] = "Play",
	["join game"] = "Servers",
	["content"] = "Store",
}

function mycraft_patch.caption_for(old)
	return CAPTIONS[(old or ""):lower()] or old
end

--------------------------------------------------------------------------
-- 2. region grouping for the public server list
--
-- The public list reports geo_continent for every server (EU, NA, AS, SA,
-- OC). We only re-order and label: filtering, search and favourites keep
-- their stock behaviour.
--
-- Order is picked for players in Pakistan / South Asia: nearby Asia first,
-- then the big European cluster, then everyone else.
--------------------------------------------------------------------------
local REGION_ORDER = {
	{ key = "AS", label = "Nearby: Asia" },
	{ key = "EU", label = "Europe" },
	{ key = "NA", label = "North America" },
	{ key = "SA", label = "South America" },
	{ key = "OC", label = "Oceania" },
}

function mycraft_patch.region_of(server)
	local geo = (server and server.geo_continent or ""):upper()
	for _, r in ipairs(REGION_ORDER) do
		if r.key == geo then
			return r.key
		end
	end
	return "ZZ"
end

--- Splits servers into ordered groups, nearest region first.
function mycraft_patch.group_servers(servers, use_groups)
	if not use_groups or not servers or #servers == 0 then
		return { { key = "ALL", label = nil, servers = servers or {} } }
	end
	local buckets, keys = {}, {}
	for _, s in ipairs(servers) do
		local key = mycraft_patch.region_of(s)
		if not buckets[key] then
			buckets[key] = {}
			keys[#keys + 1] = key
		end
		table.insert(buckets[key], s)
	end
	local out = {}
	for _, r in ipairs(REGION_ORDER) do
		if buckets[r.key] then
			out[#out + 1] = { key = r.key, label = r.label, servers = buckets[r.key] }
			buckets[r.key] = nil
		end
	end
	if buckets.ZZ then
		out[#out + 1] = { key = "ZZ", label = "Rest of the world", servers = buckets.ZZ }
	end
	return out
end

--------------------------------------------------------------------------
-- 3. install
--
-- mainmenu/init.lua loads game_theme, then this file, then the dialogs, so
-- the dialog modules are not loaded yet when install() runs. Anything that
-- has to patch a dialog is therefore deferred with core.after(0, ...).
--------------------------------------------------------------------------
local function install_store()
	if type(store) ~= "table" or type(store.load) ~= "function" then
		return false
	end
	if store.mycraft_patched then
		return true
	end
	store.mycraft_patched = true

	local old_load = store.load

	local function urlencode(str)
		return (str:gsub("([^%w%-%_%.%~])", function(ch)
			return string.format("%%%02X", string.byte(ch))
		end))
	end

	store.load = function()
		if store.loaded then
			return
		end
		local base_url = core.settings:get("contentdb_url")
		local url = base_url ..
			"/api/packages/?type=mod&type=game&type=txp&platform=" .. PLATFORM
		for _, item in pairs((core.settings:get("contentdb_flag_blacklist") or ""):split(",")) do
			item = item:trim()
			if item ~= "" then
				url = url .. "&hide=" .. urlencode(item)
			end
		end

		local response = core.get_http_api():fetch_sync({ url = url })
		if not response.succeeded then
			return old_load()
		end
		local full = core.parse_json(response.data)
		if type(full) ~= "table" or not full[1] then
			return old_load()
		end

		-- Protocol and engine versions are only reported per release, not in
		-- this list payload, so nothing is filtered here. The release the
		-- engine downloads is checked by ContentDB itself when it is
		-- requested, and a bad pick simply fails to install.
		local filtered = full
		if #filtered == 0 then
			return old_load()
		end

		store.packages_full = filtered
		store.aliases = {}
		for _, package in pairs(store.packages_full) do
			local name_len = #package.name
			package.id = package.author:lower() .. "/"
			if package.type == "game" and name_len > 5 and
					package.name:sub(name_len - 4) == "_game" then
				package.id = package.id .. package.name:sub(1, name_len - 5)
			else
				package.id = package.id .. package.name
			end
			package.url_part = urlencode(package.author) .. "/" .. urlencode(package.name)
			if package.aliases then
				for _, alias in ipairs(package.aliases) do
					local suffix = "/" .. package.name
					if alias:sub(-#suffix) == suffix then
						store.aliases[alias:lower()] = package.id
					end
				end
			end
		end
		store.packages_full_unordered = store.packages_full
		store.packages = store.packages_full
		store.loaded = true
	end
	return true
end

function mycraft_patch.install()
	if mycraft_patch.installed then
		return
	end
	mycraft_patch.installed = true

	if mycraft_theme then
		mycraft_theme.install()
		mycraft_theme.apply_background()
	end

	if serverlistmgr then
		serverlistmgr.mycraft_group = mycraft_patch.group_servers
	end

	-- dialogs are dofile()d after this file, so patch them on the first tick
	core.after(0, function()
		local deadline = 0
		local function retry()
			if install_store() then
				core.log("action", "[MyCraft] store patched: full ContentDB catalogue")
				return
			end
			deadline = deadline + 1
			if deadline < 10 then
				core.after(0.1, retry)
			end
		end
		retry()
	end)
end

return mycraft_patch
