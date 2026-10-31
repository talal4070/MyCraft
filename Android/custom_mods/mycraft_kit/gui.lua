--[[
MyCraft Kit - the in-inventory page
Copyright (C) 2026 MyCraft contributors, LGPL-3.0-or-later

Adds one tab to the player inventory (sfinv games) or one button to the
inventory (unified_inventory games) with three pages:

    Home      save / return / forget your home point
    Spawn     return to world spawn, move it (world owner only)
    Protect   claim land with one tap, or mark two corners

Every action is a button; nothing has to be typed. Layout is deliberately
left-aligned and free of icons that the base font cannot draw, so it looks
the same on every device and game.
]]

local K = mycraft_kit
local S = K.S
local FS = core.formspec_escape

K.page = K.page or "home"
K.mark = K.mark or {}          -- player name -> {first=pos, second=pos}
K.msg = K.msg or {}            -- player name -> {text=, colour=, at=}
K.radius = K.radius or {}      -- player name -> claim radius

local RADII = { 8, 12, 16, 24 }
local RADII_LABEL = { "8 x 8", "12 x 12", "16 x 16", "24 x 24" }

local function get_radius(name)
	local r = K.radius[name]
	if not r then
		r = 12
		K.radius[name] = r
	end
	return r
end

local function say(name, ok, text)
	K.msg[name] = { ok = ok, text = text, at = core.get_us_time() }
end

local function msg_of(name)
	local m = K.msg[name]
	if not m then
		return ""
	end
	-- messages are transient: hide after 12 seconds
	if core.get_us_time() - m.at > 12 * 1000000 then
		K.msg[name] = nil
		return ""
	end
	local colour = m.ok and "#8ee9a0" or "#ff9d8a"
	return core.colorize(colour, FS(m.text))
end

--------------------------------------------------------------------------
-- formspec building blocks (plain, font-safe, left aligned)
--------------------------------------------------------------------------
local function tab_row(active)
	local out = {}
	local tabs = {
		{ "home", S("Home") },
		{ "protect", S("Protection") },
		{ "spawn", S("Spawn") },
	}
	for _, t in ipairs(tabs) do
		local key, label = t[1], t[2]
		if key == active then
			out[#out + 1] = "style[kit_tab_" .. key .. ";bgcolor=#28535f;textcolor=#ffe0a3;border=true;borderwidth=2;bordercolor=#5ed6be]"
		else
			out[#out + 1] = "style[kit_tab_" .. key .. ";bgcolor=#1c323a;textcolor=#c8d6d4;border=false]"
		end
	end
	local x = 0.3
	for _, t in ipairs(tabs) do
		local key, label = t[1], t[2]
		out[#out + 1] = ("button[%.2f,0.2;2.6,0.75;kit_tab_%s;%s]"):format(x, key, FS(label))
		x = x + 2.7
	end
	return table.concat(out)
end

local function panel()
	return "box[0.2,1.15;9.1,6.6;#101e24cc]"
end

local function status_line(name)
	local player = core.get_player_by_name(name)
	if not player then
		return ""
	end
	local home = K.get_home(player)
	local home_txt
	if home then
		home_txt = FS(S("Home:") .. " " .. core.pos_to_string(vector.round(home)))
	else
		home_txt = FS(S("Home: not set yet"))
	end
	local owned = K.visible_count(name)
	local where = K.status_at(name, player:get_pos()) or S("Open land - not protected")
	return "label[0.35,1.3;" .. home_txt .. "]" ..
		"label[0.35,1.7;" .. FS(S("Areas protected:") .. " " .. owned .. " / " .. K.visible_limit()) .. "]" ..
		"label[0.35,2.1;" .. FS(where) .. "]"
end

--------------------------------------------------------------------------
-- page: home
--------------------------------------------------------------------------
local function page_home(name)
	local out = { tab_row("home") }
	out[#out + 1] = panel()
	out[#out + 1] = "style[btn_set_home;bgcolor=#2b6169;textcolor=#ffffff]"
	out[#out + 1] = "style[btn_go_home;bgcolor=#2b6169;textcolor=#ffffff]"
	out[#out + 1] = "style[btn_del_home;bgcolor=#4a2c2c;textcolor=#ffd7d0]"

	out[#out + 1] = "label[0.4,2.65;" .. FS(S("Your home point")) .. "]"
	out[#out + 1] = "button[0.4,3.0;4.3,1.0;btn_go_home;" .. FS(S("Go home")) .. "]"
	out[#out + 1] = "button[4.85,3.0;4.3,1.0;btn_set_home;" .. FS(S("Set home here")) .. "]"
	out[#out + 1] = "button[0.4,4.15;4.3,0.85;btn_del_home;" .. FS(S("Forget home")) .. "]"
	out[#out + 1] = "label[0.4,5.25;" .. FS(S("Useful tips")) .. "]"
	out[#out + 1] = "textarea[0.4,5.6;8.7,2.2;;;" ..
		FS(S("Home is personal: every player has their own.\n" ..
			"The world spawn is separate - see the Spawn tab.\n" ..
			"On a server the same buttons also work from chat: /home and /sethome.")) .. "]"
	return table.concat(out)
end

--------------------------------------------------------------------------
-- page: spawn
--------------------------------------------------------------------------
local function page_spawn(name)
	local out = { tab_row("spawn") }
	out[#out + 1] = panel()
	local pos = K.get_spawn()
	local line = pos and (S("World spawn:") .. " " .. core.pos_to_string(vector.round(pos)))
		or S("World spawn: not set")
	out[#out + 1] = "label[0.4,2.65;" .. FS(line) .. "]"
	out[#out + 1] = "style[btn_go_spawn;bgcolor=#2b6169;textcolor=#ffffff]"
	out[#out + 1] = "style[btn_set_spawn;bgcolor=#3d5a3a;textcolor=#e6ffdf]"
	out[#out + 1] = "button[0.4,3.0;4.3,1.0;btn_go_spawn;" .. FS(S("Back to spawn")) .. "]"
	out[#out + 1] = "button[4.85,3.0;4.3,1.0;btn_set_spawn;" .. FS(S("Move spawn here")) .. "]"
	out[#out + 1] = "label[0.4,4.3;" .. FS(S("Moving the spawn needs the world owner privilege; in your own world you have it.")) .. "]"
	return table.concat(out)
end

--------------------------------------------------------------------------
-- page: protect
--------------------------------------------------------------------------
local function page_protect(name)
	local out = { tab_row("protect") }
	out[#out + 1] = panel()
	local m = K.mark[name] or {}
	local r = get_radius(name)

	out[#out + 1] = "label[0.4,2.55;" .. FS(S("One tap: protect the square around you")) .. "]"
	out[#out + 1] = "dropdown[0.4,2.9;2.4;kit_radius;" .. FS(table.concat(RADII_LABEL, ",")) .. ";" ..
		(tostring(table.indexof(RADII, r))) .. ";true]"
	out[#out + 1] = "style[btn_claim_now;bgcolor=#3f7a52;textcolor=#ffffff]"
	out[#out + 1] = "button[3.0,2.9;3.0,0.8;btn_claim_now;" .. FS(S("Protect here")) .. "]"
	out[#out + 1] = "label[6.2,2.95;" .. FS(S("blocks")) .. "]"

	out[#out + 1] = "label[0.4,4.0;" .. FS(S("Precise: mark two corners")) .. "]"
	local l1 = m.first and core.pos_to_string(vector.round(m.first)) or S("not marked")
	local l2 = m.second and core.pos_to_string(vector.round(m.second)) or S("not marked")
	out[#out + 1] = "label[0.4,4.35;" .. FS(S("Corner 1:") .. " " .. l1) .. "]"
	out[#out + 1] = "label[0.4,4.7;" .. FS(S("Corner 2:") .. " " .. l2) .. "]"
	out[#out + 1] = "button[0.4,5.05;2.2,0.8;btn_mark1;" .. FS(S("Mark 1")) .. "]"
	out[#out + 1] = "button[2.7,5.05;2.2,0.8;btn_mark2;" .. FS(S("Mark 2")) .. "]"
	out[#out + 1] = "style[btn_claim_marks;bgcolor=#3f7a52;textcolor=#ffffff]"
	out[#out + 1] = "button[5.0,5.05;2.2,0.8;btn_claim_marks;" .. FS(S("Protect")) .. "]"
	out[#out + 1] = "button[7.3,5.05;1.6,0.8;btn_clear_marks;" .. FS(S("Clear")) .. "]"

	-- list of owned zones, one row per zone with open/close + remove
	out[#out + 1] = "label[0.4,6.05;" .. FS(S("Your areas")) .. "]"
	local zones = K.list_zones(name)
	if #zones == 0 then
		out[#out + 1] = "label[0.4,6.45;" .. FS(S("None yet - protect some land with the buttons above.")) .. "]"
	else
		local shown = math.min(#zones, 4)
		for i = 1, shown do
			local z = zones[i]
			local y = 6.0 + (i - 1) * 0.42
			local state = z.open and S("open") or S("closed")
			out[#out + 1] = ("label[0.4,%.2f;%s]"):format(y,
				FS(S("Area #@1", z.id) .. " - " .. state))
			out[#out + 1] = ("button[5.0,%.2f;1.5,0.36;kit_toggle_%d;%s]"):format(
				y - 0.08, z.id, FS(z.open and S("Close") or S("Open")))
			out[#out + 1] = ("button[6.7,%.2f;1.5,0.36;kit_del_%d;%s]"):format(
				y - 0.08, z.id, FS(S("Remove")))
		end
		if #zones > shown then
			out[#out + 1] = ("label[0.4,%.2f;%s]"):format(6.0 + shown * 0.42,
				FS(S("@1 more - use /kit list", #zones - shown)))
		end
	end

	local msg = msg_of(name)
	if msg ~= "" then
		out[#out + 1] = "label[0.4,7.5;" .. msg .. "]"
	end
	return table.concat(out)
end

local function build(name)
	K.page = K.page or "home"
	if K.page == "protect" then
		return page_protect(name)
	elseif K.page == "spawn" then
		return page_spawn(name)
	end
	return page_home(name)
end

--------------------------------------------------------------------------
-- form handler
--------------------------------------------------------------------------
function K.handle_fields(player, fields)
	local name = player:get_player_name()
	local changed = false

	for _, key in ipairs({ "home", "protect", "spawn" }) do
		if fields["kit_tab_" .. key] then
			K.page = key
			changed = true
		end
	end
	if changed then
		return true
	end

	if fields["btn_set_home"] then
		say(name, K.set_home(player))
	elseif fields["btn_go_home"] then
		say(name, K.go_home(player))
	elseif fields["btn_del_home"] then
		say(name, K.del_home(player))
	elseif fields["btn_go_spawn"] then
		say(name, K.go_spawn(player))
	elseif fields["btn_set_spawn"] then
		say(name, K.set_spawn(player))
	elseif fields["btn_claim_now"] then
		say(name, K.claim_around(name, get_radius(name)))
	elseif fields["btn_mark1"] then
		K.mark[name] = K.mark[name] or {}
		K.mark[name].first = vector.round(player:get_pos())
		say(name, true, S("Corner 1 marked. Walk to the opposite corner and tap Mark 2."))
	elseif fields["btn_mark2"] then
		K.mark[name] = K.mark[name] or {}
		K.mark[name].second = vector.round(player:get_pos())
		say(name, true, S("Corner 2 marked. Now tap Protect."))
	elseif fields["btn_claim_marks"] then
		local m = K.mark[name] or {}
		say(name, K.claim_between(name, m.first, m.second))
		K.mark[name] = nil
	elseif fields["btn_clear_marks"] then
		K.mark[name] = nil
		say(name, true, S("Corners cleared."))
	elseif fields["kit_radius"] then
		local idx = tonumber(fields["kit_radius"])
		if idx and RADII[idx] then
			K.radius[name] = RADII[idx]
		end
	else
		return false
	end
	return true
end

-- kit_toggle_12 style button names arrive as a single field key
function K.handle_dynamic(player, fields)
	local name = player:get_player_name()
	for key in pairs(fields) do
		local id = tonumber(key:match("^kit_toggle_(%d+)$"))
		if id then
			local z = K.zones[id]
			say(name, K.set_open(id, name, not (z and z.open)))
			return true
		end
		id = tonumber(key:match("^kit_del_(%d+)$"))
		if id then
			say(name, K.remove_zone(id, name))
			return true
		end
	end
	return false
end

K.build_formspec = build

--! Register with whichever inventory the game uses -------------------------
function K.register_inventory()
	if core.global_exists("sfinv") and sfinv.register_page then
		sfinv.register_page("mycraft_kit:kit", {
			title = S("MyCraft"),
			get = function(self, player, context)
				return sfinv.make_formspec(player, context, build(player:get_player_name()), false)
			end,
			on_player_receive_fields = function(self, player, context, fields)
				if K.handle_fields(player, fields) then
					sfinv.set_player_inventory_formspec(player, context)
					return true
				end
				if K.handle_dynamic(player, fields) then
					sfinv.set_player_inventory_formspec(player, context)
					return true
				end
				return false
			end,
		})
		K.ui = "sfinv"
	elseif core.global_exists("unified_inventory") and unified_inventory.register_page then
		unified_inventory.register_page("mycraft_kit", {
			get_formspec = function(player)
				return { formspec = build(player:get_player_name()) }
			end,
		})
		unified_inventory.register_button("mycraft_kit", {
			type = "image",
			image = "mycraft_btn_home.png",
			tooltip = S("MyCraft: home, spawn, protection"),
		})
		K.ui = "unified_inventory"
	else
		K.ui = nil
	end
end

--! Escape hatch for games with a completely custom inventory --------------
-- Open the kit from chat or from the on-screen button.
function K.show(player)
	local name = player:get_player_name()
	if K.ui == "sfinv" then
		sfinv.set_page(player, "mycraft_kit:kit")
		return true
	end
	core.show_formspec(name, "mycraft_kit:popup", "size[9.5,8.1]" .. build(name))
	return true
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "mycraft_kit:popup" then
		return false
	end
	local name = player:get_player_name()
	if fields.quit then
		return true
	end
	if K.handle_fields(player, fields) or K.handle_dynamic(player, fields) then
		core.show_formspec(name, "mycraft_kit:popup", "size[9.5,8.1]" .. build(name))
		return true
	end
	return false
end)
