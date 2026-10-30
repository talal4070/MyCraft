# MyCraft — customisation & build notes

MyCraft is a personal rebrand of the open-source MultiCraft engine
(https://github.com/MultiCraft/MultiCraft). This file lists every change made
on top of upstream, so the fork stays easy to update and audit.

## Identity

| Thing | Upstream | MyCraft |
|---|---|---|
| App name (`@string/app_name`) | MultiCraft | **MyCraft** |
| Android package (`applicationId`) | `com.multicraft.game` | **`com.mycraft.game`** |
| Launcher icon | MultiCraft icon | Custom voxel grass-block icon (all densities) |

The Java/Kotlin package and Gradle `namespace` stay `com.multicraft.game`
on purpose: the native engine and the Kotlin sources reference those class
names. Only the install identity (`applicationId`) changed, so MyCraft can be
installed **side-by-side** with the official MultiCraft app.

Engine code, credits and licences are unchanged. MultiCraft (and the
Minetest/Luanti code it is based on) is mostly LGPL-3.0 — keep the source of
your fork available if you share builds, and keep the existing copyright
notices. "MyCraft" must not be presented as an official MultiCraft release.

## Device support

- `minSdk 23` (Android 6.0+) — unchanged from upstream, covers almost every
  Android device still in use.
- ABI splits for **armeabi-v7a** (old 32-bit phones), **arm64-v8a** (almost all
  modern phones) and **x86_64** (emulators/Chromebooks) — unchanged.
- **Added `isUniversalApk = true`** in `Android/app/build.gradle.kts`, so the
  build also produces one fat universal APK containing all ABIs. If you are
  sending the game to friends and don't know their device, send the universal
  one; it's bigger but installs everywhere.

## Bundled mods (`Android/custom_mods/`)

Two mods are copied into the app's `assets.zip` at build time
(`prepareAssetsFiles` in `Android/app/build.gradle.kts`) and extracted on the
phone to `<internal storage>/mods` on first launch / after an update:

1. **`areas`** — area protection (`/protect`, `/set_owner`, `/area_pos`, …),
   from https://github.com/MultiCraft/mod-areas (LGPL-3.0+). Self-protection
   is on by default in this version (players with `interact` can `/protect`
   up to 16 areas of 128×128×128 — see its `settingtypes.txt`).
2. **`mycraft_homes`** — tiny original mod: `/sethome`, `/home`, `/delhome`
   (privilege `home`, auto-granted in singleplayer). If an installed game
   already provides `/sethome` (Minetest Game does), this mod detects it and
   stays inactive.

`/spawn` and `/setspawn` needed no mod: they are already built into the
engine (`builtin/game/chat.lua`).

### Engine tweak that makes bundled mods work with ContentDB games

Upstream only searched `<share>/mods` when the game itself came from the
share directory. Games installed from ContentDB live in the user directory,
so bundled mods would have been invisible for exactly the games players use.
Two small changes fix that:

- `src/content/subgames.cpp` — always add `share/mods` to the mod search paths.
- `src/client/clientlauncher.cpp` — include `mods` in the asset folders that
  are wiped and re-extracted on app updates, so bundled mods stay current.
  (Mods the player installs themselves live in the *user* `mods` folder and
  are not touched.)

### Using the bundled mods in-game

Bundled ≠ auto-enabled. Luanti enables server mods **per world**:

1. Start MyCraft → install a game from ContentDB if you haven't (see below).
2. Create/select a world → **Select Mods** → enable `Areas` and
   `MyCraft Homes` → Save.
3. In-game: `/sethome`, `/home`, `/spawn`, and the Areas commands above.

## Game content (clean start, by design)

This build deliberately ships **without a bundled game** (only the engine's
`devtest`). On first launch, open the ContentDB tab in the main menu and
install a game (for example *Minetest Game*) plus any extra mods/texture
packs you like. The Play Store version's encrypted commercial game content
is not part of the open-source project and is not included here.

## Building

### On GitHub Actions (recommended)

1. Fork (or push this tree to) your own GitHub repo.
2. Repo → **Actions** → enable workflows if asked → **MyCraft Android** →
   **Run workflow**.
   - `release` (default): fast/optimised, **unsigned** APKs.
   - `debug`: signed with the debug key, installs immediately, slower —
     good for a first smoke test.
   - `both`: does both (takes longest).
   Pushes that touch `Android/**` or C/C++ sources also build `release`
   automatically.
3. When the run finishes, download the **MyCraft-APKs** artifact (a zip).
   Inside you get per-ABI APKs **and** the universal APK.

A full build is a complete C++ engine compile (JDK 21, NDK
30.0.16248370, compileSdk 37; Gradle wants ~4 GB+ RAM), so expect the
Actions run to take a while.

### Signing a release APK (required before it will install)

Release outputs are `*-release-unsigned.apk`. Sign one with your own key and
**keep that key safe — every future update must use the same key**:

```bash
# one time: create your key (remember the passwords!)
keytool -genkeypair -v -keystore mycraft.jks -alias mycraft \
  -keyalg RSA -keysize 2048 -validity 10000

# every build: align + sign (uber-apk-signer does both)
java -jar uber-apk-signer.jar --apks app-universal-release-unsigned.apk \
  --ks mycraft.jks --ksAlias mycraft
```

Alternatively put `keystore`, `keystore.password`, `key` and `key.password`
into `Android/local.properties` (do NOT commit that file) and Gradle will
sign release builds itself.

### On a PC instead

Android Studio (or just the command-line tools) with JDK 21 and the SDK/NDK
versions above, then:

```bash
cd Android
./gradlew assemblerelease        # or assembleDebug for a test build
```

## Updating from upstream later

```bash
git remote add upstream https://github.com/MultiCraft/MultiCraft.git   # once
git fetch upstream
git merge upstream/main
```

Conflicts, if any, should be limited to the files listed in this document:
`Android/app/build.gradle.kts`, `Android/app/src/main/res/…` (name/icons),
`.github/workflows/android.yml`, `src/content/subgames.cpp`,
`src/client/clientlauncher.cpp`, plus the added `Android/custom_mods/` tree.
