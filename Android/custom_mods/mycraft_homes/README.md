# MyCraft Homes

A tiny original mod bundled with MyCraft. It gives every player one personal
home point, saved in the player's own metadata (so it is remembered per world).

| Command    | Privilege | What it does                                  |
|------------|-----------|-----------------------------------------------|
| `/sethome` | `home`    | Save your current position as your home       |
| `/home`    | `home`    | Teleport back to your saved home position     |
| `/delhome` | `home`    | Delete your saved home position               |

Notes:

- `/spawn` and `/setspawn` are **already built into the MultiCraft/Luanti
  engine itself** (`builtin/game/chat.lua`), so you don't need a mod for them.
  `/setspawn` needs the `server` privilege; `/spawn` works for everyone once a
  spawn point exists.
- The `home` privilege is given to singleplayer and to admins automatically.
  On a server, an admin can grant it with `/grant <player> home`, or add
  `home` to `default_privs` in the world/server config so everyone gets it.
- If a game installed from ContentDB already ships its own sethome mod
  (Minetest Game does), this mod detects the existing commands at load time
  and leaves them in charge — nothing is overridden and there are no conflicts.

License: GNU LGPL 3.0 or later (same family as the engine). Written from
scratch for MyCraft in 2026.
