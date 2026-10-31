--[[
MyCraft Kit
Copyright (C) 2026 MyCraft contributors, LGPL-3.0-or-later

One tab in the player inventory that makes the everyday things tap-sized:

    Home      set / go / forget a personal home point
    Spawn     go back to spawn, move the spawn (world owner only)
    Protect   claim the land around you in one tap, or mark two corners

It also adds an always-available on-screen button (top right) that opens
the same page, so the kit is reachable even in games with a custom
inventory, and it registers chat commands for everything.

Design notes
  * Works in Minetest Game, VoxeLibre and Mineclonia: the inventory
    integration is chosen at runtime (sfinv, unified_inventory, or the
    built-in popup fallback).
  * Never fights an existing command: if the game already has /sethome
    or /protect, that one keeps the short name and ours becomes /kit_*.
  * Protection only ever limits other players; the owner can always build.
]]

local MODNAME = "mycraft_kit"

mycraft_kit = {}
local K = mycraft_kit

K.S = core.get_translator(MODNAME)
local S = K.S
K.modpath = core.get_modpath(MODNAME)

dofile(K.modpath .. "/protect.lua")
dofile(K.modpath .. "/home.lua")
dofile(K.modpath .. "/gui.lua")
dofile(K.modpath .. "/commands.lua")
dofile(K.modpath .. "/hud.lua")

--------------------------------------------------------------------------
-- hooks: register the inventory page once the game's inventory is loaded
--------------------------------------------------------------------------
local tries = 0
local function try_register()
	if K.ui then
		return
	end
	tries = tries + 1
	K.register_inventory()
	if K.ui then
		core.log("action", "[" .. MODNAME .. "] inventory page ready (" .. K.ui .. ")")
		return
	end
	if tries < 20 then
		core.after(0.5, try_register)
	else
		core.log("warning", "[" .. MODNAME .. "] no known inventory found; "
			.. "use the on-screen button or /kit to open the page")
	end
end

core.after(0, try_register)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "" or not fields.btn_mycraft_kit then
		return false
	end
	K.show(player)
	return true
end)

--------------------------------------------------------------------------
-- friendly first-run hint (once per player, singleplayer only)
--------------------------------------------------------------------------
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local meta = player:get_meta()
	if meta:get_string("mycraft_kit:hinted") == "1" then
		return
	end
	if not core.is_singleplayer() then
		return
	end
	meta:set_string("mycraft_kit:hinted", "1")
	core.after(4, function()
		local p = core.get_player_by_name(name)
		if not p then
			return
		end
		core.chat_send_player(name, core.colorize("#8ee9a0",
			S("[MyCraft] Open your inventory: there is a new tab with Home, Spawn and Protection buttons.")))
	end)
end)
