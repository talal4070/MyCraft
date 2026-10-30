--[[
MyCraft Homes
Copyright (C) 2026 MyCraft contributors

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 3.0 of the License, or
(at your option) any later version.

Adds a personal home point for every player:
	/sethome  -- remember your current position as your home
	/home     -- teleport back to it
	/delhome  -- forget it

World spawn is already provided by the engine itself (/spawn, /setspawn),
so this mod deliberately does not re-register those commands.

If a game the player installed already provides its own /sethome + /home
(e.g. Minetest Game's "sethome" mod), this mod detects that at load time
and leaves the game's commands in charge instead of overriding them.
]]

local MODNAME = "mycraft_homes"
local META_KEY = MODNAME .. ":home"

core.register_privilege("home", {
	description = "Can set a home position and teleport back to it with /home",
	give_to_singleplayer = true,
	give_to_admin = true,
})

local function get_home(player)
	local raw = player:get_meta():get_string(META_KEY)
	if raw == "" then
		return nil
	end
	return core.string_to_pos(raw)
end

if core.chatcommands["sethome"] or core.chatcommands["home"] then
	core.log("action", "[" .. MODNAME .. "] Another mod already provides "
		.. "/sethome and/or /home - keeping that one, mine stays inactive.")
else
	core.register_chatcommand("sethome", {
		description = "Set your home position to where you are standing",
		privs = {home = true},
		func = function(name)
			local player = core.get_player_by_name(name)
			if not player then
				return false
			end
			local pos = player:get_pos()
			if not core.is_valid_pos(pos) then
				return false, "You are outside the map limits!"
			end
			player:get_meta():set_string(META_KEY, core.pos_to_string(pos))
			return true, "Home set at " .. core.pos_to_string(pos)
				.. ". Use /home to come back here."
		end,
	})

	core.register_chatcommand("home", {
		description = "Teleport to your home position (set it with /sethome)",
		privs = {home = true},
		func = function(name)
			local player = core.get_player_by_name(name)
			if not player then
				return false
			end
			local pos = get_home(player)
			if not pos then
				return false, "You have no home yet. Stand where you want "
					.. "it and type /sethome first."
			end
			if not core.is_valid_pos(pos) then
				return false, "Your home is outside the map limits!"
			end
			player:set_pos(pos)
			return true, "Teleporting home..."
		end,
	})

	core.register_chatcommand("delhome", {
		description = "Delete your home position",
		privs = {home = true},
		func = function(name)
			local player = core.get_player_by_name(name)
			if not player then
				return false
			end
			if not get_home(player) then
				return false, "You have no home to delete."
			end
			player:get_meta():set_string(META_KEY, "")
			return true, "Home deleted."
		end,
	})

	core.log("action", "[" .. MODNAME .. "] /sethome, /home and /delhome ready.")
end
