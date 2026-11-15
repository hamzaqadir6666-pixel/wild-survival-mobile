#!/usr/bin/env python3
"""Writes CREDITS.md from the asset tables (run from the repo root)."""
import json, re
src = json.load(open('assets_src/esc50/sources.json'))
animals = json.load(open('assets/models/animals/animals.json'))
nature = json.load(open('assets/models/nature/nature.json'))
code = open('tools/build_audio.py').read()
use = {}
for out, f in re.findall(r"'(\w+)': \(?'([\w-]+\.wav)'", code): use[out] = f
use.update({f'step{i}': '4-218304-A-25.wav' for i in range(1, 5)}); use.update({f'splash{i}': '1-50623-A-15.wav' for i in range(1, 4)})
use['click'] = '2-152964-A-31.wav'; use['thud'] = '1-103995-A-30.wav'
L = ['# Credits', '', 'Every third-party file in the game, its author, source and licence.', '',
     '**Licence summary:** most files are CC0 or CC BY. The 0 A.D. animal models (lion, tiger, cheetah, crocodile, boar, gazelle, goat)',
     'are **CC BY-SA 3.0**: you may use them commercially, but you must credit Wildfire Games and share any changes to *those models*',
     'under the same licence. Nothing here is under a non-commercial licence.', '',
     '## Animal models and animations', '',
     '### Quaternius - Ultimate Animated Animals - CC0 1.0', '',
     'https://quaternius.com/packs/ultimateanimatedanimals.html (downloaded through the GitHub mirror `xxfrigorizxx/The-Legacy-Of-Seroka`;',
     'originals kept in `assets_src/quaternius_animals/`). Re-coloured by `tools/build_animals.py`; all clips are the pack\'s own.', '',
     '| Game file | Pack model | Triangles | Clips |', '|---|---|---|---|']
def rows(pred):
    for k, v in animals.items():
        if pred(v['base']): L.append(f"| `assets/models/animals/{k}.glb` | {v['base']} | {v['tris']} | {', '.join(v['clips'])} |")
rows(lambda b: '/' not in b)
L += ['', '### 0 A.D. fauna - Wildfire Games - CC BY-SA 3.0', '',
      'Author and copyright: **Wildfire Games** (https://www.wildfiregames.com/), 0 A.D. art, https://gitlab.com/0ad/0ad - licence **CC BY-SA 3.0**',
      '(http://creativecommons.org/licenses/by-sa/3.0/). glTF conversions with Idle and Walk clips taken from the GitHub project `Vitexus/ishtaria-client`',
      '(`assets/zeroad/fauna`, licence note copied to `assets_src/zeroad_fauna/License.txt`); originals in `assets_src/zeroad_fauna/`.',
      'Changes made here (`tools/build_animals2.py`): clips renamed, second UV set added, colour texture resized to 256 px and saved as',
      '`assets/models/animals/tex_*.png`. The tiger and the cheetah are the 0 A.D. **lioness** mesh with a tint and a stripe / spot pattern.',
      'These modified files are released under CC BY-SA 3.0 as well.', '',
      '| Game file | Source file | Triangles | Clips |', '|---|---|---|---|']
rows(lambda b: b.startswith('zeroad'))
L += ['', '### Poly by Google - CC BY 3.0', '',
      'Spotted hyena (https://poly.pizza/m/0yU1LU3Nkpu), Elephant (https://poly.pizza/m/cx0-TiCjDOx), Rhinoceros (https://poly.pizza/m/11qk1uy0YGH)',
      'by **Poly by Google**, licence **CC BY 3.0** (https://creativecommons.org/licenses/by/3.0/). The rigged versions used here (meshes bound to the',
      'Quaternius wolf / bull skeletons and clips, CC0) come from the GitHub project `g0ddest/renethack` (`client/godot/art/ccby/polypizza`);',
      'originals in `assets_src/poly_google/`. Changes made here: clips renamed, second UV set added, texture saved as `tex_*.png`.', '',
      '| Game file | Source file | Triangles | Clips |', '|---|---|---|---|']
rows(lambda b: b.startswith('poly'))
L += ['', '## Bird models and animations', '',
      'From **DOGWALK** by **Blender Studio** - (CC) Blender Foundation | studio.blender.org - https://studio.blender.org/projects/dogwalk/ - **CC BY 4.0**',
      '(downloaded from the GitHub copy `nikitalita/DOGWALK`, folder `assets/char/birds` and `animations/world`; licence text in `assets/models/birds/LICENCE-DOGWALK.md`).',
      'Changes: texture resized to 512 px, sound tracks removed from the animations, colours tinted in the game.', '',
      '| Game file | Original | Used for |', '|---|---|---|',
      '| `assets/models/birds/bird_01.gltf` + `.bin` | bird_01 | junglefowl |', '| `assets/models/birds/bird_02.gltf` + `.bin` | bird_02 | crows |', '| `assets/models/birds/bird_03.gltf` + `.bin` | bird_03 | hawks |',
      '| `assets/models/birds/textures/birds-albedo.png` | birds-albedo.png | all birds |',
      '| `assets/models/birds/anim_idle.tres` | LOOP-bird-look | idle |', '| `assets/models/birds/anim_walk.tres` | LOOP-bird-stroll01 | walk |', '| `assets/models/birds/anim_eat.tres` | LOOP-bird-eat | eat |',
      '| `assets/models/birds/anim_fly.tres`, `anim_fly2.tres` | ACTN-bird-fly01 / fly02 | flight |', '',
      '## Trees, plants and rocks', '',
      'Pack: **Ultimate Nature Pack** by **Quaternius** - https://quaternius.com/packs/ultimatenature.html - **CC0 1.0**',
      '(downloaded through the GitHub mirror `flo-bit/tiny-planets`; originals in `assets_src/quaternius_nature/`).',
      'Baked by `tools/build_nature.py` (triangle reduction, colours into vertices, lighter `_lod1` / `_lod2` versions for far trees).', '',
      '| Game file | Pack model | Triangles (lod1 / lod2) |', '|---|---|---|']
for k, v in nature.items():
    lod = f" ({v['lod1_tris']} / {v['lod2_tris']})" if 'lod1_tris' in v else ''
    L.append(f"| `assets/models/nature/{k}.glb` | {v['source']} | {v['tris']}{lod} |")
L += ['', '## Sounds', '',
      'All sound effects are cut from single freesound.org clips as redistributed in the **ESC-50** dataset (https://github.com/karolpiczak/ESC-50).',
      'Only clips individually marked CC0 or CC-BY in the dataset\'s attribution table were used. Processing (`tools/build_audio.py`): mono, 22 kHz, trimmed, loop cross-fade; pitch is changed in the game for some animals.', '',
      '| Game file | Original clip | Author | Link | Licence |', '|---|---|---|---|---|']
for out in sorted(use):
    s = src[use[out]]
    L.append(f"| `assets/audio/{out}.wav` | {s[2]} | {s[4]} | {s[3]} | {s[5]} |")
L += ['', '## Music', '',
      '| Game file | Title | Author | Link | Licence |', '|---|---|---|---|---|',
      '| `assets/audio/music.ogg` | House In a Forest Loop | HorrorPen (c) 2012 - https://opengameart.org/users/horrorpen | https://opengameart.org/content/loop-house-in-a-forest | CC BY 3.0 |', '',
      '(taken unchanged from `godotengine/godot-demo-projects`, `2d/dodge_the_creeps/art/`).', '',
      '## Made for this project (no third party)', '',
      '- `assets/textures/*.png` - ground, fur pattern, leaf/bark detail, water, cloud and glow textures, generated by `tools/build_textures.py`.',
      '- `assets/ui/*.png`, `icon.png` - icons drawn by `tools/build_icons.py`.',
      '- `assets/audio/chase.wav`, `assets/audio/heartbeat.wav` - chase music and heartbeat, synthesised by `tools/build_chase_audio.py`.',
      '- `assets/world/*` - the map (heights, ground blend, plant and animal positions), generated once by `tools/build_world.py` and then fixed.',
      '- Engine: Godot Engine 4 (MIT) - https://godotengine.org/license', '']
open('CREDITS.md', 'w').write('\n'.join(L))
missing = [o for o in use if use[o] not in src]
print('lines', len(L), 'missing', missing)
