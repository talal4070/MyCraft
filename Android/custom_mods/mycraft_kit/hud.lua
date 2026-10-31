--[[
MyCraft Kit - on-screen button + live status
Copyright (C) 2026 MyCraft contributors, LGPL-3.0-or-later

A small badge in the top-right corner shows the protection situation at a
glance (the MyCraft page itself opens from the inventory tab or /kit):

    shield closed    you are standing on protected land
    shield open      someone else protects this land
    home             open land, and your home is set
    home dim         open land, no home yet

Because the button lives on the server HUD, it also works in games whose
inventory is custom (where the kit has no tab), and in singleplayer.
]]

local K = mycraft_kit
local S = K.S

local SHOW_BUTTON = core.settings:get_bool("mycraft_kit_button")
if SHOW_BUTTON == nil then
	SHOW_BUTTON = true
end

local hud_ids = {}

local function button_image(name)
	local player = core.get_player_by_name(name)
	if not player then
		return "mycraft_btn_home.png"
	end
	local where = K.status_at(name, player:get_pos()) or ""
	if where == S("Your protected area") then
		return "mycraft_btn_shield.png"
	elseif where ~= S("Open land - not protected") then
		return "mycraft_btn_spawn.png"
	end
	if K.get_home(player) then
		return "mycraft_btn_home.png"
	end
	return "mycraft_btn_tools.png"
end

local function refresh(name)
	local player = core.get_player_by_name(name)
	if not player or not hud_ids[name] then
		return
	end
	player:hud_change(hud_ids[name], "text", button_image(name))
end

if SHOW_BUTTON then
	core.register_on_joinplayer(function(player)
		local name = player:get_player_name()
		local id = player:hud_add({
			hud_elem_type = "image",
			text = button_image(name),
			position = { x = 1, y = 0 },
			offset = { x = -14, y = 14 },
			alignment = { x = -1, y = 1 },
			scale = { x = 1, y = 1 },
			z_index = 5,
		})
		hud_ids[name] = id

	end)

	core.register_on_leaveplayer(function(player)
		hud_ids[player:get_player_name()] = nil
	end)

	-- keep the picture honest while walking between protected and open land
	core.after(1, function()
		local function tick()
			for _, player in ipairs(core.get_connected_players()) do
				refresh(player:get_player_name())
			end
			core.after(1.5, tick)
		end
		tick()
	end)
end
