# Wild Survival (Mobile Edition)

A 3D survival game for Android (and iOS) made with **Godot 4.7** and GDScript only.
You are a deer in a jungle full of hunters. Landscape, touch only, built for low-end phones
(Compatibility / OpenGL ES 3 renderer).

## Open the project

1. Install **Godot 4.7.x (standard build, not .NET)** from https://godotengine.org/download
2. Start Godot, press **Import**, pick `project.godot` in this folder. The first import takes about a minute.
3. Press **F5** to play. On a PC the mouse acts as a finger; keyboard also works
   (WASD, Shift sprint, C sneak, Space jump, E eat/drink, M map, Esc pause/back).

## Export an Android APK

1. In Godot: **Editor > Manage Export Templates > Download and Install**.
2. **Editor > Editor Settings > Export > Android**: set the Java SDK (JDK 17) and Android SDK paths
   (the easiest way is to install Android Studio once).
3. **Project > Export**. The preset **Android** is already there (arm64 + armv7, immersive, vibration permission,
   world data files included). A debug keystore is created by Godot automatically.
4. Press **Export Project**, choose a file name ending in `.apk`, copy it to the phone and install it.
   Or plug the phone in with USB debugging on and press the Android icon at the top right of the editor.

An **iOS** preset is included as well; exporting it needs a Mac with Xcode and your Apple team ID.

## Prey or hunter

Main menu -> **Choose animal**. Two sides, each with its own 8-level campaign and endless mode:

| Side | Animals | Goal of a level | Food |
|---|---|---|---|
| Prey | deer, gazelle, boar, goat, buffalo | survive the time and eat rare plants | graze |
| Hunter | lion, tiger, cheetah, wolf, hyena, crocodile | bring down N animals before the time runs out | feed on kills |

Hunter rules: sneak close (animals see a walking hunter from about 16 m, a sneaking one from 5 m), sprint, press the paw button to
bite. Big animals need several bites; elephants and rhinos cannot be hunted. Stand at the carcass and press again to feed.
Only *stronger* hunters attack you (strength: crocodile > lion = tiger > hyena = wolf > cheetah); biting a weaker one drives it off.
Rare-plant abilities belong to the prey side only.

## Controls (touch)

| Control | What it does |
|---|---|
| Left stick (appears under your left thumb) | move |
| Drag on the right half of the screen | look around |
| Sprint button (hold) | run, drains stamina |
| Sneak button (tap on/off) | quiet and hard to see |
| Jump button | jump |
| Big leaf/drop button | graze on grass, drink at a shore, eat a rare plant - it shows what it will do |
| Map button / Pause button | full map / pause menu |
| Android back button | pause in the game, one screen back in menus |

## Graphics presets

Chosen automatically on first launch from RAM, CPU cores and GPU name; changed in **Settings**.
With **Auto quality** on, the game steps down by itself when it stays under 25 fps.
Only the preset number is saved - the values always come from `scripts/cfg.gd`.

| | Low | Medium | High |
|---|---|---|---|
| Frame limit | 30 | 60 | 60 |
| Render resolution | 60 % | 80 % | 100 % |
| Shadows | off (blob shadows under animals) | one 1024 sun shadow map | one 2048 sun shadow map |
| View distance / fog end | 170 m | 230 m | 270 m |
| Grass amount | 25 % | 60 % | 100 % |
| Wind sway, rain drops | off, 110 | on, 220 | on, 340 |
| Full-detail trees / animated animals within | ~50 m / 55 m | ~55 m / 80 m | ~58 m / 80 m |

## Tests

All tests start the real game scene and drive it (no display or GPU needed):

```
godot --headless --path . --import          # once
godot --headless --path . -- --test         # 139 feature checks, exit code 0 = all passed
godot --headless --path . -- --test-perf    # draw-call / triangle budget at 24 view points per preset
godot --headless --path . -- --soak=600     # a bot plays for 600 s and prints memory, objects, orphan nodes
```

## Where things are

- `scripts/` game code: `game.gd` (main), `player.gd`, `predator.gd`, `prey.gd`, `fauna.gd`, `sky.gd`, `plants.gd`,
  `terrain.gd`, `water.gd`, `vegetation.gd`, `grass.gd`, `data.gd` (all numbers: animals, plants, levels), `cfg.gd` (presets), `ui/`
- `shaders/` six small shaders (ground, water, vegetation, fur, sky, rain) - none reads the screen or depth
- `assets/` everything the game ships; `assets_src/` original downloads (not exported); `tools/` scripts that bake the assets
- `CREDITS.md` every third-party file with author, link and licence

## Asset substitutions (please read)

The sandbox this was built in could reach GitHub only, so models and sounds came from GitHub copies of free packs.
What that means in practice:

- **Animals come from three sources** (see `CREDITS.md`):
  - 0 A.D. (Wildfire Games, **CC BY-SA 3.0**): real textured **lion**, lioness, **crocodile**, **boar**, **gazelle**, **goat** meshes.
    They ship with only *idle* and *walk* clips, so running is the walk clip played faster, and biting, eating and dying are
    simple body poses (lunge, head-down tilt, falling on the side) instead of hand-made animations.
  - Poly by Google (CC BY 3.0): **hyena**, **elephant**, **rhinoceros**, with full clip sets.
  - Quaternius (CC0): deer / fawn, **wolf**, **fox**, buffalo (bull), with full clip sets.
  - There is still **no real tiger or cheetah mesh**: both use the 0 A.D. lioness body with a tint and a stripe / spot pattern
    (the cheetah is also slimmer). They are big cats now, not dogs, but they are not unique models.
  - CC BY-SA means: if you publish the game you must credit Wildfire Games and keep those animal files under the same licence.
- **Birds** (junglefowl, crows, hawks) share three small rigged bird models from Blender Studio's DOGWALK (CC BY 4.0)
  with idle, walk, eat and flight clips. They have no death clip (a killed junglefowl tips over), and the hawk has no call.
- The plant pack is **low-poly stylised**, not photo-real. A detail texture, colour variation and lighting are added,
  but up close trees are faceted.
- Rare plants reuse plant-pack models with a colour tint and glow.
- Ambience loops are short (4.4 s each) because the source clips are 5 s long.
- Ground, fur, water and sky textures are generated by script, not photographs.

## Not checked on a real device

The game was developed without a GPU or screen: logic, menus, layout rectangles, shader compilation (front end)
and the scene budget are tested, but **nobody has looked at a rendered frame or measured fps on a phone**.
See the report in the pull request / chat for the list of things that need eyes on a device.
