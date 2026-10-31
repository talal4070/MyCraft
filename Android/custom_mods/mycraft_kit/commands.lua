--[[
MyCraft Kit - chat commands
Copyright (C) 2026 MyCraft contributors, LGPL-3.0-or-later

The buttons are the main interface; these commands exist so the same
actions can be reached from chat (and from the on-screen buttons used
while playing on servers).

If a game already provides /sethome, /home, /spawn or /protect, MyCraft
does not fight it: our command is registered under a "kit_" name and the
short name is left to the game. Either way the Kit page keeps working.
]]

local K = mycraft_kit
local S = K.S

local function with_player(func)
	return function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false
		end
		return func(player, param)
	end
end

local function register(preferred, def)
	local name = preferred
	if core.chatcommands[name] then
		name = "kit_" .. preferred
	end
	def.params = def.params or ""
	core.register_chatcommand(name, def)
	return name
end

K.commands = {}

K.commands.sethome = register("sethome", {
	description = S("MyCraft: save your home point here"),
	func = with_player(function(player) return K.set_home(player) end),
})
K.commands.home = register("home", {
	description = S("MyCraft: teleport back to your home point"),
	func = with_player(function(player) return K.go_home(player) end),
})
K.commands.delhome = register("delhome", {
	description = S("MyCraft: forget your home point"),
	func = with_player(function(player) return K.del_home(player) end),
})

-- spawn: keep the engine's own /spawn if a game or the engine provides it
if not core.chatcommands["spawn"] then
	K.commands.spawn = register("spawn", {
		description = S("Teleport to the world spawn"),
		func = with_player(function(player) return K.go_spawn(player) end),
	})
end
if not core.chatcommands["setspawn"] then
	K.commands.setspawn = register("setspawn", {
		description = S("Move the world spawn to your position"),
		func = with_player(function(player) return K.set_spawn(player) end),
	})
end

K.commands.protect = register("protect", {
	params = S("[radius]"),
	description = S("MyCraft: protect the land around you"),
	func = with_player(function(player, param)
		local radius = tonumber(param)
		if not radius then
			radius = K.radius and K.radius[player:get_player_name()] or 12
		end
		radius = math.max(4, math.min(32, math.floor(radius)))
		return K.claim_around(player:get_player_name(), radius)
	end),
})

K.commands.kit = register("kit", {
	params = S("[list | open]"),
	description = S("MyCraft: open the home/spawn/protection page"),
	func = with_player(function(player, param)
		param = (param or ""):lower()
		if param == "list" then
			local name = player:get_player_name()
			local zones = K.zones_of(name)
			if #zones == 0 then
				return true, S("You have no protected areas yet. Tap Protect here on the MyCraft page.")
			end
			local lines = {}
			for _, z in ipairs(zones) do
				lines[#lines + 1] = S("Area #@1 @2 (@3 to @4) @5",
					z.id, z.name, core.pos_to_string(z.p1), core.pos_to_string(z.p2),
					z.open and S("open") or S("closed"))
			end
			return true, table.concat(lines, "\n")
		end
		K.show(player)
		return true
	end),
})

core.log("action", "[mycraft_kit] commands ready: /" .. table.concat({
	K.commands.sethome, K.commands.home, K.commands.delhome,
	K.commands.protect, K.commands.kit,
}, ", /"))
