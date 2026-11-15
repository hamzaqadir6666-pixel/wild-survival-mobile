# Credits

Every third-party file in the game, its author, source and licence.

**Licence summary:** most files are CC0 or CC BY. The 0 A.D. animal models (lion, tiger, cheetah, crocodile, boar, gazelle, goat)
are **CC BY-SA 3.0**: you may use them commercially, but you must credit Wildfire Games and share any changes to *those models*
under the same licence. Nothing here is under a non-commercial licence.

## Animal models and animations

### Quaternius - Ultimate Animated Animals - CC0 1.0

https://quaternius.com/packs/ultimateanimatedanimals.html (downloaded through the GitHub mirror `xxfrigorizxx/The-Legacy-Of-Seroka`;
originals kept in `assets_src/quaternius_animals/`). Re-coloured by `tools/build_animals.py`; all clips are the pack's own.

| Game file | Pack model | Triangles | Clips |
|---|---|---|---|
| `assets/models/animals/deer.glb` | Deer | 2098 | attack, death, eat, hit, idle, idle2, jump, run, walk |
| `assets/models/animals/wolf.glb` | Wolf | 1962 | attack, death, eat, hit, idle, idle2, jump, run, walk |
| `assets/models/animals/fox.glb` | Fox | 1848 | attack, death, eat, hit, idle, idle2, jump, run, walk |
| `assets/models/animals/buffalo.glb` | Bull | 2418 | attack, death, eat, hit, idle, idle2, jump, run, walk |

### 0 A.D. fauna - Wildfire Games - CC BY-SA 3.0

Author and copyright: **Wildfire Games** (https://www.wildfiregames.com/), 0 A.D. art, https://gitlab.com/0ad/0ad - licence **CC BY-SA 3.0**
(http://creativecommons.org/licenses/by-sa/3.0/). glTF conversions with Idle and Walk clips taken from the GitHub project `Vitexus/ishtaria-client`
(`assets/zeroad/fauna`, licence note copied to `assets_src/zeroad_fauna/License.txt`); originals in `assets_src/zeroad_fauna/`.
Changes made here (`tools/build_animals2.py`): clips renamed, second UV set added, colour texture resized to 256 px and saved as
`assets/models/animals/tex_*.png`. The tiger and the cheetah are the 0 A.D. **lioness** mesh with a tint and a stripe / spot pattern.
These modified files are released under CC BY-SA 3.0 as well.

| Game file | Source file | Triangles | Clips |
|---|---|---|---|
| `assets/models/animals/lion.glb` | zeroad_fauna/lion.glb | 820 | idle, walk |
| `assets/models/animals/tiger.glb` | zeroad_fauna/lioness.glb | 980 | idle, walk |
| `assets/models/animals/cheetah.glb` | zeroad_fauna/lioness.glb | 980 | idle, walk |
| `assets/models/animals/crocodile.glb` | zeroad_fauna/crocodile.glb | 700 | idle, walk |
| `assets/models/animals/boar.glb` | zeroad_fauna/boar.glb | 362 | idle, walk |
| `assets/models/animals/gazelle.glb` | zeroad_fauna/gazelle.glb | 306 | idle, walk |
| `assets/models/animals/goat.glb` | zeroad_fauna/goat.glb | 366 | idle, walk |

### Poly by Google - CC BY 3.0

Spotted hyena (https://poly.pizza/m/0yU1LU3Nkpu), Elephant (https://poly.pizza/m/cx0-TiCjDOx), Rhinoceros (https://poly.pizza/m/11qk1uy0YGH)
by **Poly by Google**, licence **CC BY 3.0** (https://creativecommons.org/licenses/by/3.0/). The rigged versions used here (meshes bound to the
Quaternius wolf / bull skeletons and clips, CC0) come from the GitHub project `g0ddest/renethack` (`client/godot/art/ccby/polypizza`);
originals in `assets_src/poly_google/`. Changes made here: clips renamed, second UV set added, texture saved as `tex_*.png`.

| Game file | Source file | Triangles | Clips |
|---|---|---|---|
| `assets/models/animals/hyena.glb` | poly_google/Hyena.glb | 868 | attack, death, hit, idle, run, walk |
| `assets/models/animals/elephant.glb` | poly_google/Elephant.glb | 934 | attack, death, hit, idle, run, walk |
| `assets/models/animals/rhino.glb` | poly_google/Rhinoceros.glb | 742 | attack, death, hit, idle, run, walk |

## Bird models and animations

From **DOGWALK** by **Blender Studio** - (CC) Blender Foundation | studio.blender.org - https://studio.blender.org/projects/dogwalk/ - **CC BY 4.0**
(downloaded from the GitHub copy `nikitalita/DOGWALK`, folder `assets/char/birds` and `animations/world`; licence text in `assets/models/birds/LICENCE-DOGWALK.md`).
Changes: texture resized to 512 px, sound tracks removed from the animations, colours tinted in the game.

| Game file | Original | Used for |
|---|---|---|
| `assets/models/birds/bird_01.gltf` + `.bin` | bird_01 | junglefowl |
| `assets/models/birds/bird_02.gltf` + `.bin` | bird_02 | crows |
| `assets/models/birds/bird_03.gltf` + `.bin` | bird_03 | hawks |
| `assets/models/birds/textures/birds-albedo.png` | birds-albedo.png | all birds |
| `assets/models/birds/anim_idle.tres` | LOOP-bird-look | idle |
| `assets/models/birds/anim_walk.tres` | LOOP-bird-stroll01 | walk |
| `assets/models/birds/anim_eat.tres` | LOOP-bird-eat | eat |
| `assets/models/birds/anim_fly.tres`, `anim_fly2.tres` | ACTN-bird-fly01 / fly02 | flight |

## Trees, plants and rocks

Pack: **Ultimate Nature Pack** by **Quaternius** - https://quaternius.com/packs/ultimatenature.html - **CC0 1.0**
(downloaded through the GitHub mirror `flo-bit/tiny-planets`; originals in `assets_src/quaternius_nature/`).
Baked by `tools/build_nature.py` (triangle reduction, colours into vertices, lighter `_lod1` / `_lod2` versions for far trees).

| Game file | Pack model | Triangles (lod1 / lod2) |
|---|---|---|
| `assets/models/nature/tree_giant.glb` | Willow_2 | 600 (148 / 54) |
| `assets/models/nature/tree_big.glb` | Willow_4 | 560 (138 / 48) |
| `assets/models/nature/tree_a.glb` | CommonTree_2 | 519 (130 / 50) |
| `assets/models/nature/tree_b.glb` | CommonTree_5 | 480 (118 / 44) |
| `assets/models/nature/tree_c.glb` | Willow_3 | 460 (120 / 42) |
| `assets/models/nature/tree_d.glb` | CommonTree_1 | 518 (130 / 48) |
| `assets/models/nature/palm_a.glb` | PalmTree_1 | 420 (112 / 48) |
| `assets/models/nature/palm_b.glb` | PalmTree_4 | 378 (98 / 44) |
| `assets/models/nature/banana.glb` | Plant_1 | 179 |
| `assets/models/nature/fern_a.glb` | Plant_3 | 140 |
| `assets/models/nature/fern_b.glb` | Plant_4 | 160 |
| `assets/models/nature/bush_a.glb` | Bush_1 | 150 |
| `assets/models/nature/bush_b.glb` | Bush_2 | 129 |
| `assets/models/nature/bush_berry.glb` | BushBerries_1 | 260 |
| `assets/models/nature/grass_tuft.glb` | Grass_3 | 64 |
| `assets/models/nature/tall_grass.glb` | Wheat | 110 |
| `assets/models/nature/lily.glb` | Lilypad | 148 |
| `assets/models/nature/rock_a.glb` | Rock_Moss_4 | 128 |
| `assets/models/nature/rock_b.glb` | Rock_Moss_6 | 116 |
| `assets/models/nature/rock_c.glb` | Rock_1 | 70 |
| `assets/models/nature/p_flower.glb` | Flowers | 202 |
| `assets/models/nature/p_spike.glb` | Plant_5 | 240 |
| `assets/models/nature/p_corn.glb` | Corn_2 | 299 |
| `assets/models/nature/p_twig.glb` | Plant_2 | 160 |
| `assets/models/nature/p_log.glb` | WoodLog_Moss | 258 |
| `assets/models/nature/p_stump.glb` | TreeStump | 197 |
| `assets/models/nature/p_berry.glb` | BushBerries_2 | 258 |

## Sounds

All sound effects are cut from single freesound.org clips as redistributed in the **ESC-50** dataset (https://github.com/karolpiczak/ESC-50).
Only clips individually marked CC0 or CC-BY in the dataset's attribution table were used. Processing (`tools/build_audio.py`): mono, 22 kHz, trimmed, loop cross-fade; pitch is changed in the game for some animals.

| Game file | Original clip | Author | Link | Licence |
|---|---|---|---|---|
| `assets/audio/amb_day.wav` | Daintree Rainforrest Birds 1.wav | digifishmusic | http://www.freesound.org/people/digifishmusic/sounds/38559/ | CC-BY |
| `assets/audio/amb_night.wav` | emmentaler crickets.wav | Zozzy | http://www.freesound.org/people/Zozzy/sounds/59102/ | CC0 |
| `assets/audio/amb_rain.wav` | Louisiana Rain 1.wav | uberhuberman | http://www.freesound.org/people/uberhuberman/sounds/21189/ | CC0 |
| `assets/audio/amb_water.wav` | Gentle Sea On Flat Beach.wav | digifishmusic | http://www.freesound.org/people/digifishmusic/sounds/43760/ | CC-BY |
| `assets/audio/amb_wind.wav` | roaring wind.aiff | klangfabrik | http://www.freesound.org/people/klangfabrik/sounds/117773/ | CC0 |
| `assets/audio/bleat.wav` | 110419-000_sheep_bleating.wav | reinsamba | http://www.freesound.org/people/reinsamba/sounds/119161/ | CC-BY |
| `assets/audio/click.wav` | 003_click.wav | JL_barrett | http://www.freesound.org/people/JL_barrett/sounds/152964/ | CC0 |
| `assets/audio/crow.wav` | Crows_01.wav | Q.K. | http://www.freesound.org/people/Q.K./sounds/56233/ | CC0 |
| `assets/audio/drink.wav` | drinking.wav | sagetyrtle | http://www.freesound.org/people/sagetyrtle/sounds/37226/ | CC0 |
| `assets/audio/eat.wav` | Eating Oatmeal | qubodup | http://www.freesound.org/people/qubodup/sounds/169907/ | CC0 |
| `assets/audio/growl.wav` | angry_dogs.wav | polipa | http://www.freesound.org/people/polipa/sounds/117271/ | CC0 |
| `assets/audio/grunt.wav` | Pig_Grunts_Snorts_Breathing_Hackney_City_Farm.wav | tompallant | http://www.freesound.org/people/tompallant/sounds/257858/ | CC0 |
| `assets/audio/hiss.wav` | Werewolf breathing and sniffing  | kd_jack | http://www.freesound.org/people/kd_jack/sounds/261464/ | CC0 |
| `assets/audio/howl.wav` | catHowling2.wav | Zabuhailo | http://www.freesound.org/people/Zabuhailo/sounds/146965/ | CC0 |
| `assets/audio/laugh.wav` | Cackling Laugh.mp3 | fattirewhitey | http://www.freesound.org/people/fattirewhitey/sounds/259514/ | CC0 |
| `assets/audio/moo.wav` | Cow.wav | Benboncan | http://www.freesound.org/people/Benboncan/sounds/58277/ | CC-BY |
| `assets/audio/roar.wav` | Two bulls singing in the desert of Arizona | felix.blume | http://www.freesound.org/people/felix.blume/sounds/202111/ | CC0 |
| `assets/audio/rooster.wav` | cockeril.wav | Charliefarley | http://www.freesound.org/people/Charliefarley/sounds/34119/ | CC0 |
| `assets/audio/snarl.wav` | catHowling1.wav | Zabuhailo | http://www.freesound.org/people/Zabuhailo/sounds/146964/ | CC0 |
| `assets/audio/splash1.wav` | water_splash_10shots.wav | vibe_crc | http://www.freesound.org/people/vibe_crc/sounds/50623/ | CC0 |
| `assets/audio/splash2.wav` | water_splash_10shots.wav | vibe_crc | http://www.freesound.org/people/vibe_crc/sounds/50623/ | CC0 |
| `assets/audio/splash3.wav` | water_splash_10shots.wav | vibe_crc | http://www.freesound.org/people/vibe_crc/sounds/50623/ | CC0 |
| `assets/audio/step1.wav` | 01-21 Footsteps, sneakers on gravel and leaves.wav | MentalSanityOff | http://www.freesound.org/people/MentalSanityOff/sounds/218304/ | CC0 |
| `assets/audio/step2.wav` | 01-21 Footsteps, sneakers on gravel and leaves.wav | MentalSanityOff | http://www.freesound.org/people/MentalSanityOff/sounds/218304/ | CC0 |
| `assets/audio/step3.wav` | 01-21 Footsteps, sneakers on gravel and leaves.wav | MentalSanityOff | http://www.freesound.org/people/MentalSanityOff/sounds/218304/ | CC0 |
| `assets/audio/step4.wav` | 01-21 Footsteps, sneakers on gravel and leaves.wav | MentalSanityOff | http://www.freesound.org/people/MentalSanityOff/sounds/218304/ | CC0 |
| `assets/audio/thud.wav` | Bassdrum_Shell_Ticks.aif | RutgerMuller | http://www.freesound.org/people/RutgerMuller/sounds/103995/ | CC0 |
| `assets/audio/thunder1.wav` | thunderstorm.wav | raoul_slayer | http://www.freesound.org/people/raoul_slayer/sounds/101296/ | CC0 |
| `assets/audio/thunder2.wav` | thunderstorm.wav | raoul_slayer | http://www.freesound.org/people/raoul_slayer/sounds/101296/ | CC0 |

## Music

| Game file | Title | Author | Link | Licence |
|---|---|---|---|---|
| `assets/audio/music.ogg` | House In a Forest Loop | HorrorPen (c) 2012 - https://opengameart.org/users/horrorpen | https://opengameart.org/content/loop-house-in-a-forest | CC BY 3.0 |

(taken unchanged from `godotengine/godot-demo-projects`, `2d/dodge_the_creeps/art/`).

## Made for this project (no third party)

- `assets/textures/*.png` - ground, fur pattern, leaf/bark detail, water, cloud and glow textures, generated by `tools/build_textures.py`.
- `assets/ui/*.png`, `icon.png` - icons drawn by `tools/build_icons.py`.
- `assets/audio/chase.wav`, `assets/audio/heartbeat.wav` - chase music and heartbeat, synthesised by `tools/build_chase_audio.py`.
- `assets/world/*` - the map (heights, ground blend, plant and animal positions), generated once by `tools/build_world.py` and then fixed.
- Engine: Godot Engine 4 (MIT) - https://godotengine.org/license
