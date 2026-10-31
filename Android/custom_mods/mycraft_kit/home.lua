--[[
MyCraft Kit - home / spawn
Copyright (C) 2026 MyCraft contributors, LGPL-3.0-or-later

Home data lives in player metadata (survives restarts and works in every
game that has a player). This file only provides the logic; gui.lua and
commands.lua expose it with buttons and chat commands.
]]

local K = mycraft_kit
local S = K.S

local META_KEY = "mycraft_kit:home"

function K.get_home(player)
	local raw = player:get_meta():get_string(META_KEY)
	if raw == "" then
		return nil
	end
	return core.string_to_pos(raw)
end

function K.set_home(player)
	local pos = player:get_pos()
	if not core.is_valid_pos(pos) then
		return false, S("You are outside the map limits.")
	end
	player:get_meta():set_string(META_KEY, core.pos_to_string(pos))
	return true, S("Home saved at @1. Tap Home any time to return.", core.pos_to_string(vector.round(pos)))
end

--- Returns true, message. Teleports the player to their home.
function K.go_home(player)
	local pos = K.get_home(player)
	if not pos then
		return false, S("No home yet. Stand where you want it and tap Set home.")
	end
	if not core.is_valid_pos(pos) then
		return false, S("Your saved home is outside the map limits.")
	end
	local ok, err = player:set_pos(pos)
	if ok == false then
		return false, err or S("Could not teleport home.")
	end
	return true, S("Welcome home!")
end

function K.del_home(player)
	if not K.get_home(player) then
		return false, S("You have no home saved.")
	end
	player:get_meta():set_string(META_KEY, "")
	return true, S("Home removed.")
end

--- Where respawns and /spawn send you.
function K.get_spawn()
	local pos, yaw, pitch = core.get_world_spawnpoint()
	if not pos then
		pos = core.setting_get_pos("static_spawnpoint")
	end
	return pos
end

function K.go_spawn(player)
	local pos, yaw, pitch = core.get_world_spawnpoint()
	if not pos then
		pos = core.setting_get_pos("static_spawnpoint")
	end
	if not pos then
		return false, S("This world has no spawn point yet.")
	end
	if not core.is_valid_pos(pos) then
		return false, S("The spawn point is outside the map limits.")
	end
	player:set_pos(pos)
	if yaw and player.set_look_horizontal then
		player:set_look_horizontal(yaw)
	end
	return true, S("Back at spawn.")
end

--- Moves the world spawn to the player (needs the "server" privilege,
--- which singleplayer always has).
function K.set_spawn(player)
	local name = player:get_player_name()
	if not core.check_player_privs(name, { server = true }) then
		return false, S("Only the world owner can move the spawn point.")
	end
	local pos = player:get_pos()
	if not core.is_valid_pos(pos) then
		return false, S("You are outside the map limits.")
	end
	pos = vector.round(pos)
	if core.settings:get("static_spawnpoint") then
		core.settings:remove("static_spawnpoint")
		core.settings:write()
	end
	local yaw = math.floor((player:get_look_horizontal() or 0) * 100) / 100
	local pitch = math.floor((player:get_look_vertical() or 0) * 100) / 100
	core.set_world_spawnpoint(pos, yaw, pitch)
	return true, S("Spawn point moved here (@1).", core.pos_to_string(pos))
end
