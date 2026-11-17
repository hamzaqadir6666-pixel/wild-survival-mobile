# Dust &amp; Iron — Wild Survival

An open-world Western survival adventure built with **Godot 4.7** (GDScript).
You ride into the **Red Hollow Territory**, a 576 × 576 m procedural frontier of
grassland, pine forest, badlands and mountain, with the town of **Dustwater** at
its heart.

---

## Running the game

```bash
# with the Godot 4.7 editor / runtime on PATH
godot --path .                       # boots res://scenes/ui/main_menu.tscn
godot --path . -e                    # open in the editor

# headless smoke test
godot --headless --path . --quit-after 600
```

Desktop builds default to the **Forward+** renderer (SSAO, volumetric fog,
reflections); the mobile and web overrides fall back to **GL Compatibility** so
phones and browsers can still run it. Start the game and choose **New Game** on
the title screen to ride into the territory.

### Controls

| Action | Key | Action | Key |
| --- | --- | --- | --- |
| Move | `W A S D` | Reload | `R` |
| Sprint | `Shift` | Interact / mount / talk | `E` |
| Jump | `Space` | Weapon 1 / 2 / 3 | `1` `2` `3` |
| Crouch (toggle) | `Ctrl` | Cycle weapon | `X` |
| Look | Mouse | Whistle for Juniper | `F` |
| Change camera | `C` | Journal | `I` |
| Aim (hold) | Right mouse | World map | `M` |
| Fire | Left mouse | Pause | `Esc` |
| Quick save / load | `F5` / `F9` | | |

Gamepad analogue sticks and the face buttons are mapped as well.

### On phones

When the platform reports a touchscreen, an on-screen thumb stick, look pad and
fire / aim / jump / sprint / interact / reload / horse / map / menu buttons are
drawn automatically (`scripts/ui/touch_controls.gd`). They press the same input
actions as the keyboard, and the mouse is left uncaptured. Export presets for a
Linux build and a signed Android APK live in `export_presets.cfg`; the mobile
renderer falls back to GL Compatibility and is capped at 60 fps.

Set `DUST_TOUCH_UI=1` (or `0`) to force the touch overlay on desktop for testing.

---

## What is in here

### Measured on this machine (headless, 2 vCPU)

World build 4.4 s, steady state 3.3 ms physics + 2.9 ms script per frame, about
175 MB of static memory for the fully populated scene (1 300 nodes, 42 animals,
19 NPCs, 72 terrain chunks).

### World generation

* `scripts/world/terrain_generator.gd` — 6 × 6 chunk heightfield (96 m chunks,
  33 verts per edge) from layered `FastNoiseLite` fields: grassland valley,
  forested western hills, eastern desert, northern mountains, a river carved
  along a spline and a lake in the southern basin. Vertex colours encode the
  grass / forest-floor / sand / rock blend weights consumed by
  `shaders/ground.gdshader`, which mixes five PBR albedo + normal pairs with
  macro noise and slope- and altitude-driven snow.
* `scripts/world/vegetation.gd` — ~26 000 wind-animated grass cards near the
  player (custom `MultiMesh` vertex shader with distance fade), plus 1 100 trees
  of eight species, 1 400 bushes, 900 rocks and 200 cacti scattered by biome and
  slope with `MultiMeshInstance3D`.
* `scripts/world/world_builder.gd` — assembles everything at runtime: sky, sun,
  moon, water, the town of Dustwater (saloon, market, mill, tower, cabins,
  boardwalks, street lamps), Barrett Ranch, trapper camps, Rattler Gulch bandit
  hideout, the abandoned mine, Old Timer's Bridge, the chapel ruins and
  Silverthread Falls.
* `scripts/world/day_night_cycle.gd` — full 24 h clock (one in-game minute per
  1.6 s) driving sun/moon transforms, sky-shader uniforms, ambient light, fog
  and glow.
* `scripts/world/weather_system.gd` — clear / overcast / rain / storm / fog
  states with transitions, rain particles, thunder and ambient audio.

### Player &amp; combat

* `scenes/player/player.tscn` — `CharacterBody3D` with capsule collision,
  spring-arm camera and `ModelRoot` for the skinned model.
* `scripts/player/player_controller.gd` — four locomotion speeds, sprint and
  stamina, crouch, jump, three camera modes (shoulder / far / aim), procedural
  revolver / rifle / shotgun with recoil, spread, pellets, reload timing and
  hitscan, melee-free interaction, horse mounting, footstep audio and death /
  respawn handling.
* `scripts/systems/fx_manager.gd` — impact decals, sparks, dust, blood,
  muzzle flashes and tracer lines.
* `scripts/animals/horse.gd` — mountable horse with stamina, gallop, whistle
  summon and a follow mode.

### Life in the territory

* `scripts/animals/animal_ai.gd` — deer, stag, fox, wolf and bull with grazing,
  fleeing, pack predation and hunting rewards.
* `scripts/ai/npc_ai.gd` — town residents and bandits with schedules, greetings,
  shop and mission dialogue, wanted-level reactions and ranged attacks.
* `scripts/missions/mission_manager.gd` — data-driven main story, side jobs
  (ranch, bounty, medicine run, hunting) and wandering encounters, with talk,
  reach and kill objectives.

### Systems

* `scripts/systems/game_state.gd` — the single source of truth for health,
  stamina, money, ammo, weapons, missions, collectibles, wanted level, clock and
  notifications; a plain `Node` autoload so it survives scene changes.
* `scripts/systems/save_system.gd` — JSON-in-`user://` save slots.
* `scripts/systems/audio_manager.gd` — music, ambience and 3D SFX with separate
  master / music / SFX / ambience buses.
* `scripts/systems/input_setup.gd` — registers every action at runtime so the
  project needs no hand-edited `InputMap` (and stays remappable).

### Interface

* `scenes/ui/main_menu.tscn` + `scripts/ui/main_menu.gd` — painted title screen
  (procedural sepia sky, mesas, drifting dust) with Continue gated on a save.
* `scripts/ui/hud.gd` — health / stamina / horse stamina, ammo, money, wanted
  stars, compass strip with objective bearing, live minimap, notifications,
  interaction prompt and death overlay.
* `scripts/ui/hud_panels.gd` — pause, journal (missions + relics), world map
  (terrain-sampled with roads, river, POIs and player arrow), shop, settings
  (volumes + mouse sensitivity) and controls panels.
* `ui/western_theme.tres` — global theme: DejaVu Serif faces, parchment text,
  brass-bordered buttons.

---

## Project layout

```
assets/       characters (rigged GLB), animals (GLTF), props (Kenney GLB), textures, audio
resources/    environment + audio bus layout
scenes/       player, animals, npcs, world, ui (.tscn)
scripts/      ai, animals, missions, player, systems, ui, world (.gd)
shaders/      ground, grass_blades, sky, water (.gdshader)
ui/           western_theme.tres, fonts/
```

Physics layers: `1 world · 2 player · 3 npc · 4 animals · 5 props · 6 interact ·
7 water · 8 hitbox`.

---

## Credits &amp; licences

| Asset | Source | Licence |
| --- | --- | --- |
| Kenney *Nature / Survival / Furniture / Building / Hexagon / Pirate / Weapon* kits (`assets/props/kenney`) | [Kenney](https://kenney.nl) | CC0 1.0 |
| Rigged characters, animations (`assets/characters`) | [Moorfall Assets](https://github.com/moorfall) | CC0 1.0 |
| Animals — horse, deer, stag, wolf, fox, cow, bull (`assets/animals`) | [Quaternius](https://quaternius.com) | CC0 1.0 |
| Cowboy hat mesh, terrain / wood / leather / bark textures | generated for this project (`tools/`) | CC BY 4.0 |
| Music, ambience, weapon and UI sound effects | synthesised for this project (`tools/`) | CC BY 4.0 |
| Engine | [Godot 4.7](https://godotengine.org) | MIT |

All third-party art is CC0; the synthesised audio and procedural textures are
original to this repository. Fonts shipped in `ui/fonts/` are **DejaVu Serif**
(Bitstream Vera / public-domain-derived licence, freely redistributable).
