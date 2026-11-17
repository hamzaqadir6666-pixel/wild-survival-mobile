import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import glbmerge
from glbmerge import merge

# Point these at the unpacked Moorfall Assets download
# (https://github.com/moorfall/moorfall-assets) and the generated hat.
SRC = os.environ.get('MOORFALL_SRC', os.path.join(HERE, '..', '..', 'moorfall-assets'))
HAT = os.environ.get('HAT_GLB', os.path.join(SRC, 'hat.glb'))
L1 = SRC + '/animations/UAL1.glb'
L2 = SRC + '/animations/UAL2.glb'
OUT = os.path.join(HERE, '..', 'assets', 'characters', 'rigged')
os.makedirs(OUT, exist_ok=True)

KEEP = {
    'Idle_Loop', 'Walk_Loop', 'Jog_Fwd_Loop', 'Sprint_Loop', 'Crouch_Idle_Loop',
    'Crouch_Fwd_Loop', 'Jump_Start', 'Jump_Loop', 'Jump_Land', 'Pistol_Aim_Down',
    'Pistol_Aim_Neutral', 'Pistol_Aim_Up', 'Pistol_Idle_Loop', 'Pistol_Reload',
    'Pistol_Shoot', 'Hit_Chest', 'Hit_Head', 'Hit_Knockback', 'Death01', 'Roll',
    'Interact', 'Sitting_Enter', 'Sitting_Exit', 'Sitting_Idle_Loop',
    'Idle_Talking_Loop', 'Consume', 'Yes', 'Idle_FoldArms_Loop', 'Walk_Formal_Loop',
}

_orig = glbmerge.load


def filtered(path):
    js, b = _orig(path)
    if js.get('animations'):
        js['animations'] = [a for a in js['animations'] if a.get('name') in KEEP]
    return js, b


glbmerge.load = filtered

HAT_ATT = [dict(path=HAT, bone='Head', offset=(0.0, 0.055, 0.005), scale=1.0,
                rotate=(0, 0, 0), color=(0.085, 0.055, 0.035, 1.0))]

jobs = [
    ('player_cowboy.glb', 'outfits/Male_Ranger.glb', True),
    ('npc_bandit.glb', 'outfits/Male_Ranger.glb', True),
    ('npc_peasant_male.glb', 'outfits/Male_Peasant.glb', True),
    ('npc_peasant_female.glb', 'outfits/Female_Peasant.glb', False),
    ('npc_ranger_female.glb', 'outfits/Female_Ranger.glb', False),
]
for name, body, hat in jobs:
    merge(SRC + '/' + body, [L1, L2], OUT + '/' + name,
          attachments=HAT_ATT if hat else ())
print('done')
