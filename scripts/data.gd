class_name D
extends RefCounted
## All fixed game tables: species, rare plants, levels, achievements.

const DAY_LENGTH := 360.0        # seconds for 24 game hours
const START_HOUR := 8.0
const DISCOVERY_TOTAL := 18      # 6 safe thickets + 9 landmarks + 3 lakes
const WILDLIFE_TOTAL := 16

# style: how the hunter behaves.  sight/hear in metres, chase = max seconds of pursuit.
const SPECIES := {
	"deer": {"name": "Deer", "model": "deer", "scale": 0.34, "fur": "plain", "pat": Color(0.3, 0.2, 0.12), "pat_k": 0.25, "uv": Vector2(3, 3), "walk": 3.4, "run": 8.5},
	"fawn": {"name": "Fawn", "model": "deer", "scale": 0.2, "fur": "fawn", "pat": Color(0.95, 0.92, 0.85), "pat_k": 1.0, "uv": Vector2(2.5, 2.5), "walk": 3.0, "run": 8.0},
	"lion": {"name": "Lion", "kind": "predator", "tex": "lion", "power": 5, "model": "lion", "scale": 0.37, "fur": "plain", "pat": Color(0.45, 0.3, 0.15), "pat_k": 0.3, "uv": Vector2(3, 3),
		"walk": 1.6, "run": 8.6, "sight": 34.0, "hear": 1.0, "stalk": 3.0, "charge": 20.0, "chase": 7.0, "memory": 4.0, "dmg": 34.0, "reach": 2.3, "cool": 1.6, "style": "ambush", "sound": "roar", "pitch": 0.62,
		"info": "Ambush hunter. Hits very hard but only chases for a few seconds."},
	"tiger": {"name": "Tiger", "kind": "predator", "tex": "lioness", "tint": Color(1.25, 0.86, 0.42), "power": 5, "model": "tiger", "scale": 0.38, "fur": "stripes", "pat": Color(0.06, 0.04, 0.03), "pat_k": 1.0, "uv": Vector2(1.6, 1.6),
		"walk": 1.5, "run": 8.2, "sight": 38.0, "hear": 1.2, "stalk": 14.0, "charge": 9.0, "chase": 6.0, "memory": 5.0, "dmg": 30.0, "reach": 2.3, "cool": 1.5, "style": "stalk", "sound": "snarl", "pitch": 0.6,
		"info": "Stalks silently until it is very close, then pounces."},
	"cheetah": {"name": "Cheetah", "kind": "predator", "tex": "lioness", "tint": Color(1.2, 1.05, 0.72), "power": 2, "model": "cheetah", "scale": 0.29, "wide": 0.82, "fur": "spots", "pat": Color(0.07, 0.05, 0.04), "pat_k": 1.0, "uv": Vector2(3.0, 3.0),
		"walk": 1.7, "run": 11.5, "sight": 46.0, "hear": 0.9, "stalk": 2.0, "charge": 30.0, "chase": 5.0, "memory": 3.0, "dmg": 22.0, "reach": 2.0, "cool": 1.3, "style": "sprint", "sound": "snarl", "pitch": 0.95,
		"info": "By far the fastest hunter, but it gives up after a short sprint."},
	"hyena": {"name": "Hyena", "kind": "predator", "tex": "hyena", "power": 3, "model": "hyena", "scale": 0.30, "fur": "blotch", "pat": Color(0.16, 0.12, 0.09), "pat_k": 0.0, "uv": Vector2(2.0, 2.0),
		"walk": 1.6, "run": 6.8, "sight": 36.0, "hear": 1.3, "stalk": 4.0, "charge": 16.0, "chase": 40.0, "memory": 9.0, "dmg": 14.0, "reach": 1.9, "cool": 1.4, "style": "pack_circle", "sound": "laugh", "pitch": 1.25, "pack": 3,
		"info": "Hunts in packs of three, circles its prey and almost never gives up."},
	"wolf": {"name": "Wolf", "kind": "predator", "power": 3, "model": "wolf", "scale": 0.33, "fur": "plain", "pat": Color(0.2, 0.2, 0.2), "pat_k": 0.35, "uv": Vector2(3, 3),
		"walk": 1.7, "run": 7.3, "sight": 40.0, "hear": 1.4, "stalk": 3.0, "charge": 22.0, "chase": 30.0, "memory": 7.0, "dmg": 16.0, "reach": 1.9, "cool": 1.3, "style": "pack_chase", "sound": "howl", "pitch": 0.55, "pack": 3,
		"info": "Packs of three that keep chasing for a very long time."},
	"crocodile": {"name": "Crocodile", "kind": "predator", "tex": "crocodile", "power": 6, "model": "crocodile", "scale": 0.30, "fur": "scales", "pat": Color(0.08, 0.1, 0.05), "pat_k": 0.0, "uv": Vector2(1.5, 1.5),
		"walk": 0.9, "run": 5.4, "sight": 12.0, "hear": 0.5, "stalk": 0.5, "charge": 9.0, "chase": 4.0, "memory": 2.0, "dmg": 40.0, "reach": 2.6, "cool": 2.0, "style": "water", "sound": "hiss", "pitch": 0.6,
		"info": "Lies at the water's edge. Attacks swimmers and animals that drink."},
	"gazelle": {"name": "Gazelle", "kind": "prey", "tex": "gazelle", "hp": 40, "model": "gazelle", "scale": 0.34, "fur": "plain", "pat": Color(0.2, 0.13, 0.08), "pat_k": 0.0, "uv": Vector2(3, 3), "walk": 1.3, "run": 8.5, "herd": 4, "sound": "", "info": "Fast, nervous grazer of the clearings."},
	"boar": {"name": "Boar", "kind": "prey", "tex": "boar", "hp": 75, "model": "boar", "scale": 0.40, "fur": "plain", "pat": Color(0.1, 0.07, 0.05), "pat_k": 0.0, "uv": Vector2(3, 3), "walk": 1.1, "run": 5.5, "herd": 3, "sound": "grunt", "pitch": 0.9, "info": "Roots around the forest floor in small groups."},
	"goat": {"name": "Goat", "kind": "prey", "tex": "goat", "hp": 45, "model": "goat", "scale": 0.34, "fur": "plain", "pat": Color(0.5, 0.45, 0.4), "pat_k": 0.0, "uv": Vector2(3, 3), "walk": 1.1, "run": 4.7, "herd": 3, "sound": "bleat", "pitch": 1.1, "info": "Sure-footed browser found near rocks and glades."},
	"buffalo": {"name": "Buffalo", "kind": "prey", "hp": 150, "model": "buffalo", "scale": 0.36, "fur": "plain", "pat": Color(0.05, 0.04, 0.04), "pat_k": 0.4, "uv": Vector2(3, 3), "walk": 1.0, "run": 6.0, "herd": 3, "sound": "moo", "pitch": 0.7, "info": "Heavy grazer. Slow, but hunters think twice."},
	"fox": {"name": "Fox", "kind": "prey", "hp": 25, "model": "fox", "scale": 0.16, "fur": "plain", "pat": Color(0.4, 0.2, 0.08), "pat_k": 0.3, "uv": Vector2(3, 3), "walk": 1.2, "run": 4.1, "herd": 1, "sound": "", "info": "Small, shy and usually alone."},
	"junglefowl": {"name": "Junglefowl", "kind": "prey", "hp": 10, "bird": true, "scale": 1.0, "walk": 0.8, "run": 4.5, "herd": 3, "sound": "rooster", "pitch": 1.0, "info": "Colourful ground bird that scatters when startled."},
	"elephant": {"name": "Elephant", "kind": "prey", "giant": true, "tex": "elephant", "model": "elephant", "scale": 0.5, "fur": "plain", "pat": Color(0.2, 0.2, 0.2), "pat_k": 0.0, "uv": Vector2(3, 3), "walk": 1.3, "run": 5.0, "herd": 2, "sound": "", "info": "Giant of the plains. Fears nothing and nothing hunts it."},
	"rhino": {"name": "Rhinoceros", "kind": "prey", "giant": true, "tex": "rhino", "model": "rhino", "scale": 0.45, "fur": "plain", "pat": Color(0.2, 0.2, 0.2), "pat_k": 0.0, "uv": Vector2(3, 3), "walk": 1.2, "run": 4.5, "herd": 1, "sound": "grunt", "pitch": 0.55, "info": "Armoured loner. Even lions leave it alone."},
	"hawk": {"name": "Hawk", "kind": "sky", "info": "Circles high above the clearings."},
	"crow": {"name": "Crow", "kind": "sky", "info": "Noisy flocks crossing the sky."},
}
const WILDLIFE_ORDER := ["lion", "tiger", "cheetah", "hyena", "wolf", "crocodile", "gazelle", "boar", "goat", "buffalo", "fox", "junglefowl", "elephant", "rhino", "hawk", "crow"]
const PREY_ORDER := ["gazelle", "boar", "goat", "buffalo", "fox", "junglefowl"]
# which animals live at herd home number i (repeats)
const HERD_ORDER := ["gazelle", "boar", "goat", "buffalo", "fox", "junglefowl", "gazelle", "elephant", "boar", "goat", "gazelle", "rhino", "buffalo", "junglefowl"]

# playable animals.  walk / run in m/s, bite = damage per bite (hunters only)
const CHARACTERS := {
	"deer": {"side": "prey", "walk": 3.4, "run": 8.5, "hp": 100.0, "stamina": 100.0, "jump": 1.0, "text": "Balanced. The classic choice."},
	"gazelle": {"side": "prey", "walk": 3.6, "run": 9.8, "hp": 70.0, "stamina": 110.0, "jump": 1.15, "text": "Fastest runner, but fragile."},
	"boar": {"side": "prey", "walk": 3.0, "run": 7.2, "hp": 145.0, "stamina": 90.0, "jump": 0.8, "text": "Slow and tough."},
	"goat": {"side": "prey", "walk": 3.2, "run": 7.8, "hp": 90.0, "stamina": 135.0, "jump": 1.35, "text": "Great stamina and the highest jump."},
	"buffalo": {"side": "prey", "walk": 2.9, "run": 6.8, "hp": 210.0, "stamina": 80.0, "jump": 0.7, "text": "Slowest, but takes a lot of bites."},
	"lion": {"side": "pred", "walk": 3.3, "run": 8.9, "hp": 170.0, "stamina": 70.0, "jump": 1.0, "bite": 65.0, "text": "Strongest bite. Tires quickly. Only crocodiles dare attack you."},
	"tiger": {"side": "pred", "walk": 3.3, "run": 8.7, "hp": 150.0, "stamina": 85.0, "jump": 1.15, "bite": 55.0, "quiet": true, "text": "Silent stalker: prey notices you late."},
	"cheetah": {"side": "pred", "walk": 3.6, "run": 12.0, "hp": 85.0, "stamina": 60.0, "jump": 1.0, "bite": 35.0, "text": "Outruns everything for a few seconds. Weak: bigger hunters attack you."},
	"wolf": {"side": "pred", "walk": 3.4, "run": 8.2, "hp": 105.0, "stamina": 150.0, "jump": 1.0, "bite": 32.0, "text": "Can run for a very long time."},
	"hyena": {"side": "pred", "walk": 3.2, "run": 7.8, "hp": 120.0, "stamina": 160.0, "jump": 0.9, "bite": 36.0, "text": "Endless stamina and a strong stomach."},
	"crocodile": {"side": "pred", "walk": 2.2, "run": 5.0, "hp": 200.0, "stamina": 90.0, "jump": 0.0, "bite": 80.0, "swim": 6.5, "text": "Slow on land, fast in water, deadly bite. Fears nobody."},
}
const CHAR_ORDER := {"prey": ["deer", "gazelle", "boar", "goat", "buffalo"], "pred": ["lion", "tiger", "cheetah", "wolf", "hyena", "crocodile"]}
# hunter campaign: bring down `kills` animals before the time runs out; `hunters` are rivals
const PRED_LEVELS := [
	{"time": 240, "kills": 2, "hunters": {"lion": 1, "hyena": 3, "crocodile": 2}, "roam": 90.0},
	{"time": 270, "kills": 3, "hunters": {"lion": 1, "tiger": 1, "hyena": 3, "crocodile": 3}, "roam": 85.0},
	{"time": 300, "kills": 4, "hunters": {"lion": 2, "tiger": 1, "hyena": 3, "wolf": 3, "crocodile": 3}, "roam": 80.0},
	{"time": 330, "kills": 5, "hunters": {"lion": 2, "tiger": 2, "hyena": 6, "wolf": 3, "crocodile": 4}, "roam": 70.0},
	{"time": 360, "kills": 6, "hunters": {"lion": 3, "tiger": 2, "cheetah": 1, "hyena": 6, "wolf": 3, "crocodile": 5}, "roam": 62.0},
	{"time": 390, "kills": 7, "hunters": {"lion": 3, "tiger": 3, "cheetah": 2, "hyena": 6, "wolf": 6, "crocodile": 6}, "roam": 54.0},
	{"time": 420, "kills": 8, "hunters": {"lion": 4, "tiger": 3, "cheetah": 2, "hyena": 9, "wolf": 6, "crocodile": 7}, "roam": 46.0},
	{"time": 480, "kills": 10, "hunters": {"lion": 5, "tiger": 4, "cheetah": 3, "hyena": 9, "wolf": 9, "crocodile": 8}, "roam": 40.0},
]
const PRED_ENDLESS := {"time": 0, "kills": 0, "hunters": {"lion": 2, "tiger": 2, "hyena": 6, "wolf": 3, "crocodile": 5}, "roam": 60.0}

# rare plants: mesh, tint, glow colour, model scale
const PLANTS := {
	"clover": {"name": "Swift Clover", "mesh": "p_flower", "scale": 1.3, "tint": Color(0.6, 1.3, 0.7), "glow": Color(0.3, 1.0, 0.45), "text": "+3.5% speed", "ability": true},
	"moonpetal": {"name": "Moonpetal", "mesh": "p_spike", "scale": 0.9, "tint": Color(0.8, 0.9, 1.5), "glow": Color(0.55, 0.7, 1.0), "text": "Night vision", "ability": true},
	"ironbark": {"name": "Ironbark Root", "mesh": "p_twig", "scale": 0.8, "tint": Color(1.3, 0.8, 0.6), "glow": Color(1.0, 0.45, 0.25), "text": "+10 max health", "ability": true},
	"sunberry": {"name": "Sunberry", "mesh": "p_berry", "scale": 0.7, "tint": Color(1.3, 1.2, 0.5), "glow": Color(1.0, 0.85, 0.2), "text": "+10 max stamina", "ability": true},
	"ghostfern": {"name": "Ghost Fern", "mesh": "fern_a", "scale": 1.5, "tint": Color(1.6, 1.8, 1.9), "glow": Color(0.8, 0.95, 1.0), "text": "Silent steps", "ability": true},
	"owleye": {"name": "Owl-eye Mushroom", "mesh": "p_log", "scale": 0.8, "tint": Color(1.4, 1.1, 0.6), "glow": Color(1.0, 0.7, 0.2), "text": "Nearest hunter on the minimap", "ability": true},
	"springlily": {"name": "Spring Lily", "mesh": "p_flower", "scale": 1.5, "tint": Color(1.5, 0.7, 1.3), "glow": Color(1.0, 0.4, 0.9), "text": "Higher jump", "ability": true},
	"lotus": {"name": "Lotus Root", "mesh": "lily", "scale": 1.6, "tint": Color(0.8, 1.3, 1.5), "glow": Color(0.3, 0.9, 1.0), "text": "Fast swimming", "ability": true},
	"herb": {"name": "Healing Herb", "mesh": "p_corn", "scale": 0.6, "tint": Color(0.7, 1.5, 0.9), "glow": Color(0.4, 1.0, 0.7), "text": "Heals 45", "ability": false},
	"honey": {"name": "Wild Honeycomb", "mesh": "p_stump", "scale": 0.9, "tint": Color(1.6, 1.2, 0.4), "glow": Color(1.0, 0.75, 0.1), "text": "Fills food and stamina", "ability": false},
	"toadstool": {"name": "Red Toadstool", "mesh": "p_log", "scale": 0.8, "tint": Color(1.7, 0.35, 0.3), "glow": Color(1.0, 0.1, 0.1), "text": "Poison! Avoid", "ability": false},
}
const PLANT_ORDER := ["clover", "moonpetal", "ironbark", "sunberry", "ghostfern", "owleye", "springlily", "lotus", "herb", "honey", "toadstool"]
const ABILITY_ORDER := ["clover", "moonpetal", "ironbark", "sunberry", "ghostfern", "owleye", "springlily", "lotus"]
const CLOVER_MAX := 13   # 0.80 + 13 * 0.035 = 1.255

# campaign: seconds to survive, rare plants to eat, hunters
const LEVELS := [
	{"time": 180, "plants": 2, "hunters": {"lion": 1, "tiger": 1, "cheetah": 1, "hyena": 3, "crocodile": 2}, "roam": 55.0},
	{"time": 240, "plants": 3, "hunters": {"lion": 2, "tiger": 1, "cheetah": 1, "hyena": 3, "crocodile": 3}, "roam": 50.0},
	{"time": 300, "plants": 4, "hunters": {"lion": 2, "tiger": 2, "cheetah": 2, "hyena": 3, "wolf": 3, "crocodile": 3}, "roam": 44.0},
	{"time": 360, "plants": 5, "hunters": {"lion": 3, "tiger": 2, "cheetah": 2, "hyena": 6, "wolf": 3, "crocodile": 4}, "roam": 38.0},
	{"time": 420, "plants": 6, "hunters": {"lion": 3, "tiger": 3, "cheetah": 3, "hyena": 6, "wolf": 6, "crocodile": 5}, "roam": 33.0},
	{"time": 480, "plants": 7, "hunters": {"lion": 4, "tiger": 4, "cheetah": 3, "hyena": 9, "wolf": 6, "crocodile": 6}, "roam": 28.0},
	{"time": 540, "plants": 8, "hunters": {"lion": 5, "tiger": 5, "cheetah": 4, "hyena": 9, "wolf": 9, "crocodile": 8}, "roam": 24.0},
	{"time": 600, "plants": 10, "hunters": {"lion": 6, "tiger": 6, "cheetah": 5, "hyena": 12, "wolf": 9, "crocodile": 10}, "roam": 20.0},
]
const ENDLESS := {"time": 0, "plants": 0, "hunters": {"lion": 3, "tiger": 2, "cheetah": 2, "hyena": 6, "wolf": 3, "crocodile": 5}, "roam": 36.0}

const ACHIEVEMENTS := {
	"first_escape": ["First Escape", "Shake off a hunt for the first time."],
	"night": ["Night Survivor", "Stay alive from dusk until dawn."],
	"landmarks": ["Pathfinder", "Find all 9 landmarks."],
	"plants": ["Botanist", "Eat every kind of rare plant."],
	"wildlife": ["Naturalist", "See all 16 kinds of wildlife."],
	"campaign": ["King of the Jungle", "Finish all 8 campaign levels."],
	"fawn": ["Not Alone", "Find the lost fawn."],
	"first_kill": ["First Hunt", "Bring down your first animal as a hunter."],
	"apex": ["Apex Predator", "Finish all 8 hunter levels."],
}
const LANDMARK_BONUS := {"salt_lick": "Stamina and health restored", "giant_tree": "+25 health", "berry_glade": "+40 food", "banana_grove": "Food filled"}

static func hunter_total(level: Dictionary) -> int:
	var n := 0
	for k in level.hunters: n += int(level.hunters[k])
	return n

static func fmt_time(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]
