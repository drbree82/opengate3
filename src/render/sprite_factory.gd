class_name SpriteFactory
extends RefCounted
## Builds animated sprite sheets from small JSON descriptions, so a campaign needs no art files.
## Full guide with every template and "look" option: docs/SPRITES.md.
##
## A sprite definition:  {"template": "humanoid", "height": 0.95, "look": {...}}
##                  or:  {"sheet": "sprites/hero.png", "frameW": 48, "frameH": 48, "views": 1,
##                        "height": 0.95, "anims": {"idle": {"row": 0, "frames": 2, "fps": 2}}}
##
## get_set(def) returns a cached "sprite set":
##   texture, fw, fh, cols, rows, views (3 = front/back/side rows per animation, 1 = single view),
##   anims {name: {row, frames, fps, loop}}, height (world units for one frame)
## Sheet layout: one row per animation and view (row = anim.row + view index), one column per frame.
##
## To add a prop/creature template: add a branch in _draw_simple() (and _simple_frames() if it animates).

const COLS := 4
const VIEWS := ["front", "back", "side"]
const HUMANOID_ANIMS := [
	["idle", 2, 2.0, true], ["walk", 4, 7.0, true], ["attack", 3, 9.0, false], ["cast", 2, 5.0, true],
	["talk", 2, 5.0, true], ["hurt", 1, 1.0, false], ["dead", 1, 1.0, false],
]
const CREATURE_ANIMS := [["idle", 2, 2.0, true], ["walk", 2, 6.0, true], ["attack", 2, 7.0, false], ["hurt", 1, 1.0, false], ["dead", 1, 1.0, false]]
const CREATURES := ["rat", "wolf", "spider"]
## Every template name _draw_simple() knows (plus "humanoid"). The campaign validator checks against this.
const TEMPLATES := [
	"humanoid", "rat", "wolf", "spider", "barrel", "crate", "sack", "chest", "table", "bed", "bookshelf", "torch", "brazier",
	"campfire", "lamp_post", "tree", "pine", "bush", "rock", "log", "tent", "well", "sign", "market_stall", "anvil", "pillar",
	"statue", "altar", "coffin", "gravestone", "bones", "stairs", "loot",
]
const BIG := {"tree": Vector2i(64, 96), "pine": Vector2i(64, 96), "tent": Vector2i(72, 48), "market_stall": Vector2i(72, 48)}
const STEEL := Color("#c9cdd6")
const WOOD := Color("#6b4a2a")
const DARK := Color("#1a141c")

static var _cache: Dictionary = {}
static var campaign_dir := ""


static func get_set(def: Dictionary) -> Dictionary:
	var key := JSON.stringify(def)
	if _cache.has(key):
		return _cache[key]
	var out: Dictionary
	if def.has("sheet"):
		out = _from_sheet(def)
	else:
		var template: String = def.get("template", "crate")
		if template == "humanoid":
			out = _build_humanoid(def.get("look", {}))
		else:
			out = _build_simple(template, def.get("look", {}))
	out["height"] = float(def.get("height", 0.9))
	_cache[key] = out
	return out


static func clear_cache() -> void:
	_cache.clear()


## The first idle frame facing the viewer, as a texture for portraits in the UI.
static func portrait(def: Dictionary) -> AtlasTexture:
	var s := get_set(def)
	var at := AtlasTexture.new()
	at.atlas = s.texture
	var row: int = s.anims.get("idle", {"row": 0}).row
	at.region = Rect2(0, row * int(s.fh), int(s.fw), int(s.fh))
	return at


static func _from_sheet(def: Dictionary) -> Dictionary:
	var path := "%s/%s" % [campaign_dir, def.sheet]
	var img: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null:
		push_warning("Sprite sheet not found: %s" % path)
		return _build_simple("crate", {})
	var fw: int = def.get("frameW", 48)
	var fh: int = def.get("frameH", 48)
	var anims := {}
	for a in def.get("anims", {"idle": {"row": 0, "frames": 1}}):
		var d: Dictionary = def.anims[a] if def.has("anims") else {"row": 0, "frames": 1}
		anims[a] = {"row": int(d.get("row", 0)), "frames": int(d.get("frames", 1)), "fps": float(d.get("fps", 4.0)), "loop": d.get("loop", true)}
	return {"texture": ImageTexture.create_from_image(img), "fw": fw, "fh": fh, "cols": maxi(1, img.get_width() / fw), "rows": maxi(1, img.get_height() / fh), "views": int(def.get("views", 1)), "anims": anims}


# ----------------------------------------------------------------------------------------------
# Humanoids: 48x48 frames, 3 views (front / back / side), 7 animations
# ----------------------------------------------------------------------------------------------
# A figure is described by a few numbers (see _figure): head size, shoulder / waist / hip widths,
# torso and leg length. The look's "body", "build", "race" and "age" change those numbers, which
# is what gives every kind of character its own silhouette: an hourglass figure with flowing hair,
# a broad-shouldered square-jawed hero, a stocky farmer, a wide bearded dwarf, a big-headed gnome,
# a tusked half-orc, a big-eared goblin. All look options are documented in docs/SPRITES.md.

static func _build_humanoid(look: Dictionary) -> Dictionary:
	var fw := 48
	var fh := 48
	var rows := HUMANOID_ANIMS.size() * 3
	var img := Image.create(fw * COLS, fh * rows, false, Image.FORMAT_RGBA8)
	var anims := {}
	var row := 0
	for a in HUMANOID_ANIMS:
		anims[a[0]] = {"row": row, "frames": a[1], "fps": a[2], "loop": a[3]}
		for view in VIEWS:
			for f in int(a[1]):
				var p := Px.new()
				_humanoid(p, look, view, "idle" if a[0] == "dead" else a[0], f)
				p.stamp(img, f * fw, row * fh, fw, fh, false, a[0] == "dead")
			row += 1
	return {"texture": ImageTexture.create_from_image(img), "image": img, "fw": fw, "fh": fh, "cols": COLS, "rows": rows, "views": 3, "anims": anims}


## Body measurements in pixels for a look. All widths are even so the figure is symmetric.
##   hw/hh head width/height, neck, sh/wa/hip shoulder/waist/hip width, th torso height,
##   lh leg length, lw leg width, aw arm width, bust 0-2, jaw soft|square|pointed,
##   eyes normal|big|narrow|skull, ear ""|point|long|big, nose (big nose), tusks, brow, barefoot
static func _figure(look: Dictionary) -> Dictionary:
	var race: String = look.get("race", "human")
	var fem: bool = look.get("body", "masculine") == "feminine"
	var build: String = look.get("build", "")
	var F := {
		"fem": fem, "race": race, "hw": 10, "hh": 10, "neck": 1, "sh": 14, "wa": 12, "hip": 12, "th": 12, "lh": 15,
		"lw": 4, "aw": 3, "bust": 0, "jaw": "square", "eyes": "normal", "ear": "", "nose": false, "tusks": false,
		"brow": false, "barefoot": false,
	}
	if fem:
		F.merge({"sh": 12, "wa": 8, "hip": 12, "th": 11, "lh": 16, "aw": 2, "bust": 1, "jaw": "pointed", "eyes": "big"}, true)
	match race:
		"elf":
			F.merge({"hh": 11, "lh": int(F.lh) + 1, "th": int(F.th) - 1, "jaw": "pointed", "ear": "long"}, true)
			if build == "":
				build = "slender"
		"half_elf":
			F["ear"] = "point"
		"dwarf":
			F.merge({"hw": 12, "neck": 0, "th": 11, "lh": 9, "lw": 5, "nose": true}, true)
			if build == "":
				build = "stout"
		"gnome":
			F.merge({"hw": 12, "hh": 12, "neck": 0, "th": 9, "lh": 8, "lw": 3, "nose": true, "ear": "point", "eyes": "big"}, true)
			if build == "":
				build = "small"
		"halfling":
			F.merge({"hw": 12, "hh": 11, "neck": 0, "th": 10, "lh": 9, "lw": 3, "eyes": "big", "barefoot": true, "jaw": "soft"}, true)
			if build == "":
				build = "small"
		"half_orc", "orc":
			F.merge({"hw": 12, "tusks": true, "eyes": "narrow", "jaw": "square", "ear": "point", "brow": true}, true)
			if build == "":
				build = "athletic" if fem else "heroic"
		"goblin":
			F.merge({"hw": 12, "hh": 9, "neck": 0, "th": 9, "lh": 8, "lw": 3, "ear": "big", "eyes": "narrow", "jaw": "pointed"}, true)
			if build == "":
				build = "small"
	var builds := {}
	if fem:
		builds = {
			"curvy": {"sh": 12, "wa": 8, "hip": 14, "bust": 2},
			"slender": {"sh": 10, "wa": 8, "hip": 10, "bust": 1},
			"athletic": {"sh": 12, "wa": 8, "hip": 12, "bust": 1, "aw": 3},
			"heavy": {"sh": 14, "wa": 14, "hip": 16, "bust": 2, "aw": 3, "jaw": "soft"},
			"stout": {"sh": 14, "wa": 12, "hip": 14, "bust": 2, "aw": 3},
			"small": {"sh": 10, "wa": 8, "hip": 10, "bust": 1},
			"rustic": {"sh": 12, "wa": 10, "hip": 12, "bust": 1, "aw": 3, "jaw": "soft"},
		}
	else:
		builds = {
			"heroic": {"sh": 16, "wa": 10, "hip": 10, "aw": 4},
			"athletic": {"sh": 16, "wa": 10, "hip": 10, "aw": 4},
			"slim": {"sh": 12, "wa": 10, "hip": 10},
			"heavy": {"sh": 16, "wa": 16, "hip": 14, "aw": 4, "jaw": "soft"},
			"rustic": {"sh": 14, "wa": 14, "hip": 12, "aw": 4, "jaw": "soft"},
			"stout": {"sh": 16, "wa": 16, "hip": 14, "aw": 4},
			"small": {"sh": 12, "wa": 10, "hip": 10},
		}
	F.merge(builds.get(build, {}), true)
	F["build"] = build
	if look.get("style", "") == "skeleton":
		F.merge({"sh": 12, "wa": 6, "hip": 8, "aw": 2, "lw": 2, "bust": 0, "eyes": "skull", "tusks": false, "brow": false}, true)
	return F


static func _palette(look: Dictionary, F: Dictionary) -> Dictionary:
	var default_skin := "#d9a877"
	if F.race in ["half_orc", "orc"]:
		default_skin = "#8fa06a"
	elif F.race == "goblin":
		default_skin = "#6f9440"
	var outfit: String = look.get("outfit", "robe" if look.get("robe", false) else "tunic")
	var top := Util.color(look.get("top", "#7a4030"))
	var hair := Util.color(look.get("hair", "#4a3020"))
	if look.get("age", "") == "old" and not look.has("hair"):
		hair = Color("#c8c8c8")
	return {
		"skin": Util.color(look.get("skin", default_skin)), "hair": hair, "top": top,
		"bottom": Util.color(look.get("bottom", "#3a3a48")), "boots": Util.color(look.get("boots", "#2a1c12")),
		"trim": Util.color(look.get("trim", "#c9a84a")), "cloak": Util.color(look.get("cloak", "#333333")),
		"has_cloak": look.get("cloak") != null, "lips": Util.color(look.get("lips", "#c0504a")),
		"eye": Util.color(look.get("eyes", "#2a1a14")), "outfit": outfit,
		"skirt": Util.color(look.get("skirt", look.get("top", "#7a4030"))),
		"sleeves": look.get("sleeves", outfit != "bodice"),
	}


static func _pose(anim: String, f: int) -> Dictionary:
	var A := {"bob": 0, "leg_a": 0, "leg_b": 0, "pose": 0, "raise": false, "mouth": false, "lean": 0, "stride": 0, "f": f}
	match anim:
		"idle":
			A.bob = f % 2
		"walk":
			A.bob = f % 2
			A.leg_a = 3 if f == 0 else 0
			A.leg_b = 3 if f == 2 else 0
			A.stride = [4, 0, -4, 0][f]
		"attack":
			A.pose = [1, 2, 0][f]
			A.lean = [0, 1, 0][f]
		"cast":
			A.raise = true
			A.bob = f % 2
		"talk":
			A.mouth = f == 1
		"hurt":
			A.lean = -2
	return A


## Width of torso row r (0 = shoulders, th-1 = hips): shoulders taper to the waist, then widen to the hips.
static func _tw(F: Dictionary, r: int) -> int:
	var th: int = F.th
	var t := float(r) / maxf(1.0, th - 1.0)
	var w: float = lerpf(F.sh, F.wa, t / 0.55) if t < 0.55 else lerpf(F.wa, F.hip, (t - 0.55) / 0.45)
	var wi := int(round(w / 2.0)) * 2
	if r == 0:
		wi -= 2
	if int(F.bust) >= 2 and absi(r - int(th * 0.38)) <= 1:
		wi += 2
	return maxi(6, wi)


static func _humanoid(p: Px, look: Dictionary, view: String, anim: String, f: int) -> void:
	var F := _figure(look)
	var C := _palette(look, F)
	var A := _pose(anim, f)
	if look.get("style", "") == "zombie":
		A.raise = false
	if view == "side":
		_side(p, look, F, C, A)
	else:
		_front_back(p, look, F, C, A, view == "front")


static func _front_back(p: Px, look: Dictionary, F: Dictionary, C: Dictionary, A: Dictionary, front: bool) -> void:
	var cx: int = 24 + int(A.lean)
	var bob: int = A.bob
	var sh: int = F.sh
	var th: int = F.th
	var aw: int = F.aw
	var hip_y: int = 44 - int(F.lh)
	var base_y: int = hip_y - th
	var torso_y: int = base_y + bob
	var head_y: int = torso_y - int(F.neck) - int(F.hh)
	var skin: Color = C.skin
	var top: Color = C.top
	var outfit: String = C.outfit
	var style: String = look.get("style", "")
	var bones: bool = style == "skeleton"
	var zombie: bool = style == "zombie"

	# --- behind the body (seen from the front) ---
	if front:
		_wings(p, look, cx, base_y, A)
		_tail(p, look, cx, hip_y, A)
		if C.has_cloak:
			p.rect(cx - sh / 2 - 1, torso_y + 1, sh + 2, th + 9, C.cloak.darkened(0.25))
		_hair_behind(p, look, F, C, cx, head_y)

	_legs(p, F, C, A, cx, hip_y, bones)

	# --- torso, one pixel row at a time ---
	for r in range(bob, th):
		var w := _tw(F, r)
		var y := base_y + r
		var col := top
		if r == th - 2 and not (outfit in ["robe", "dress"]) and not bones:
			col = top.darkened(0.45)
		p.rect(cx - w / 2, y, w, 1, col)
		p.rect(cx - w / 2, y, 1, 1, col.lightened(0.18), false)
		p.rect(cx + w / 2 - 1, y, 1, 1, col.darkened(0.22), false)
	if bones:
		for ry in range(torso_y + 2, base_y + th - 1, 2):
			p.rect(cx - 4, ry, 8, 1, DARK, false)
		p.rect(cx - 1, torso_y + 1, 2, th - 2 - bob, top.lightened(0.1), false)
	elif front:
		_torso_details(p, F, C, cx, base_y, bob)

	# --- arms: the weapon arm is on the viewer's right from the front, left from the back ---
	var ws := 1 if front else -1
	var ax_r: int = cx + sh / 2 - 1
	var ax_l: int = cx - sh / 2 - aw + 1
	var wx: int = ax_r if ws > 0 else ax_l
	var sx: int = ax_l if ws > 0 else ax_r
	var arm_y: int = torso_y + 1
	var al: int = th - 3
	var sleeve: Color = top.darkened(0.12) if C.sleeves else skin
	var weapon: String = look.get("weapon", "none")
	if A.raise:
		for x in [wx, sx]:
			p.shaded(x, torso_y - 6, aw, 9, sleeve)
			p.rect(x, torso_y - 8, aw, 2, skin)
			if int(A.f) % 2 == 1:
				p.rect(x, torso_y - 12, 3, 3, C.trim.lightened(0.4), false)
		_weapon(p, weapon, wx + 1, torso_y - 7, ws, 0, C.trim)
	else:
		var off_len: int = al - 2 if zombie else al
		p.shaded(sx, arm_y, aw, off_len, sleeve)
		p.rect(sx, arm_y + off_len, aw, 2, skin)
		if look.get("shield", false):
			var shx: int = sx - 3 if ws > 0 else sx - 1
			p.shaded(shx, arm_y + 1, 8, 11, Color("#7a5a34") if front else Color("#5c4428"))
			if front:
				p.rect(shx + 3, arm_y + 5, 2, 3, STEEL, false)
				p.rect(shx, arm_y + 1, 8, 1, STEEL.darkened(0.2), false)
		var pose: int = A.pose
		if pose == 1:
			p.shaded(wx, torso_y - 5, aw, 8, sleeve)
			p.rect(wx, torso_y - 7, aw, 2, skin)
			_weapon(p, weapon, wx + 1, torso_y - 6, ws, 1, C.trim)
		elif pose == 2:
			p.shaded(wx if ws > 0 else wx - 2, torso_y + 2, aw + 2, 4, sleeve)
			p.rect(wx + aw + 2 if ws > 0 else wx - 4, torso_y + 3, 2, 3, skin)
			_weapon(p, weapon, wx + aw + 3 if ws > 0 else wx - 4, torso_y + 3, ws, 2, C.trim)
		else:
			p.shaded(wx, arm_y, aw, al, sleeve)
			p.rect(wx, arm_y + al, aw, 2, skin)
			_weapon(p, weapon, wx + (1 if aw > 2 else 0), arm_y + al, ws, 0, C.trim)

	# --- on the back (seen from behind) ---
	if not front:
		if C.has_cloak:
			p.shaded(cx - sh / 2 - 1, torso_y, sh + 2, th + 10, C.cloak)
		_wings(p, look, cx, base_y, A)
		_tail(p, look, cx, hip_y, A)

	_head(p, look, F, C, A, cx, head_y, front)
	_hair(p, look, F, C, cx, head_y, front)
	_ears(p, F, C, cx, head_y, look.get("hairStyle", "short") in ["hood", "helm", "hat"])
	_horns(p, look, F, cx, head_y)


static func _legs(p: Px, F: Dictionary, C: Dictionary, A: Dictionary, cx: int, hip_y: int, bones: bool) -> void:
	var lw: int = F.lw
	var hip: int = F.hip
	var lh: int = F.lh
	var outfit: String = C.outfit
	var skirt := 0
	if outfit == "robe":
		skirt = lh
	elif outfit == "dress":
		skirt = int(lh * 0.65)
	var leg_c: Color = C.skin if outfit == "dress" else C.bottom
	for side in [-1, 1]:
		var lift: int = A.leg_a if side < 0 else A.leg_b
		var x0: int = cx - 1 - lw if side < 0 else cx + 1
		var ln: int = lh - lift
		p.shaded(x0, hip_y, lw, ln, leg_c)
		var extra: int = (hip - (lw * 2 + 2)) / 2
		if extra > 0 and not bones:
			# fuller thighs up to the hip line
			p.rect(x0 - extra if side < 0 else x0 + lw, hip_y, extra, mini(5, ln), leg_c)
			if extra > 1:
				p.rect(x0 - extra + 1 if side < 0 else x0 + lw, hip_y + 5, extra - 1, mini(3, maxi(0, ln - 5)), leg_c)
		var by: int = 44 - lift
		if F.barefoot:
			p.rect(x0 - (1 if side < 0 else 0), by + 1, lw + 1, 2, C.skin)
		else:
			p.rect(x0 - (1 if side < 0 else 0), by, lw + 1, 3, C.boots)
			if outfit in ["armor", "leather"]:
				p.rect(x0, by - 5, lw, 5, C.boots.lightened(0.1), false)
	if skirt > 0:
		var flare := 4 if outfit == "dress" else 2
		var col: Color = C.skirt if outfit == "dress" else C.top
		for r in skirt:
			var w: int = int(round(lerpf(hip, hip + flare, float(r) / skirt) / 2.0)) * 2
			p.rect(cx - w / 2, hip_y + r, w, 1, col)
			p.rect(cx + w / 2 - 1, hip_y + r, 1, 1, col.darkened(0.2), false)
			p.rect(cx - w / 2, hip_y + r, 1, 1, col.lightened(0.15), false)
		var hem: int = int(round((hip + flare) / 2.0)) * 2
		p.rect(cx - hem / 2, hip_y + skirt - 1, hem, 1, C.trim, false)


## Clothing details on the chest (front view only): neckline, figure, belt buckle, armour plates, lacing.
static func _torso_details(p: Px, F: Dictionary, C: Dictionary, cx: int, base_y: int, bob: int) -> void:
	var th: int = F.th
	var sh: int = F.sh
	var top: Color = C.top
	var outfit: String = C.outfit
	var y0: int = base_y + bob
	if outfit in ["bodice", "dress"] or (F.fem and outfit in ["tunic", "leather"]):
		p.rect(cx - 2, y0, 4, 1, C.skin, false)
		p.rect(cx - 1, y0 + 1, 2, 1, C.skin, false)
	else:
		p.rect(cx - 2, y0, 4, 1, C.trim, false)
	if int(F.bust) > 0:
		var br := int(th * 0.38)
		var w := _tw(F, br)
		var by: int = base_y + br + 1
		p.rect(cx - w / 2 + 1, by, w / 2 - 2, 1, top.darkened(0.28), false)
		p.rect(cx + 1, by, w / 2 - 2, 1, top.darkened(0.28), false)
		p.rect(cx - w / 2 + 2, by - 2, 2, 1, top.lightened(0.22), false)
		p.rect(cx + 2, by - 2, 2, 1, top.lightened(0.22), false)
	match outfit:
		"armor":
			p.shaded(cx - sh / 2 - 2, y0, 5, 3, top.lightened(0.2))
			p.shaded(cx + sh / 2 - 3, y0, 5, 3, top.lightened(0.2))
			if int(F.bust) == 0:
				p.rect(cx - 3, base_y + 3, 6, 3, top.lightened(0.12), false)
			p.rect(cx - 1, base_y + th - 2, 2, 1, C.trim, false)
		"robe":
			p.rect(cx - 1, base_y + 2, 2, th - 2, C.trim, false)
			var sw := _tw(F, th - 3)
			p.rect(cx - sw / 2, base_y + th - 3, sw, 1, C.trim.darkened(0.25), false)
		"dress":
			var ww := _tw(F, int(th * 0.55))
			p.rect(cx - ww / 2, base_y + int(th * 0.55), ww, 1, C.trim, false)
		"bodice":
			for i in 3:
				p.rect(cx - 1, base_y + 4 + i * 2, 2, 1, C.trim, false)
			p.rect(cx - 1, base_y + th - 2, 2, 1, C.trim, false)
		"leather":
			p.line(cx - sh / 2 + 2, y0 + 1, cx + _tw(F, th - 3) / 2 - 2, base_y + th - 3, top.darkened(0.45), 1, false)
			p.rect(cx - 1, base_y + th - 2, 2, 1, C.trim, false)
		_:
			p.rect(cx - 1, base_y + th - 2, 2, 1, C.trim, false)


static func _head(p: Px, look: Dictionary, F: Dictionary, C: Dictionary, A: Dictionary, cx: int, head_y: int, front: bool) -> void:
	var hw: int = F.hw
	var hh: int = F.hh
	var skin: Color = C.skin
	var hair: Color = C.hair
	var x0: int = cx - hw / 2
	var jaw: String = F.jaw
	var bones: bool = F.eyes == "skull"
	var ey: int = head_y + int(hh * 0.45)
	var my: int = head_y + hh - 3
	if int(F.neck) > 0:
		p.rect(cx - 2, head_y + hh, 4, int(F.neck), skin.darkened(0.15))
	for r in hh:
		var inset := 0
		if r == 0:
			inset = 1
		elif jaw == "soft" and r == hh - 1:
			inset = 1
		elif jaw == "pointed" and r == hh - 1:
			inset = 2
		elif jaw == "pointed" and r == hh - 2:
			inset = 1
		p.rect(x0 + inset, head_y + r, hw - inset * 2, 1, skin)
	p.rect(x0 + hw - 1, head_y + 1, 1, hh - 3, skin.darkened(0.14), false)
	p.rect(x0, head_y + 1, 1, hh - 3, skin.lightened(0.1), false)
	if not front:
		return
	if bones:
		p.rect(cx - 3, ey - 1, 2, 3, DARK, false)
		p.rect(cx + 1, ey - 1, 2, 3, DARK, false)
		p.rect(cx - 1, ey + 2, 2, 1, DARK, false)
		for tx in range(cx - 3, cx + 3, 2):
			p.dot(tx, head_y + hh - 1, DARK)
		return
	match F.eyes:
		"big":
			p.rect(cx - 3, ey, 1, 2, Color.WHITE, false)
			p.rect(cx - 2, ey, 1, 2, C.eye, false)
			p.rect(cx + 1, ey, 1, 2, C.eye, false)
			p.rect(cx + 2, ey, 1, 2, Color.WHITE, false)
			if F.fem:
				p.rect(cx - 3, ey - 1, 2, 1, DARK, false)
				p.rect(cx + 1, ey - 1, 2, 1, DARK, false)
				p.dot(cx - 4, ey - 1, DARK)
				p.dot(cx + 3, ey - 1, DARK)
		"narrow":
			p.rect(cx - 3, ey, 2, 1, C.eye, false)
			p.rect(cx + 1, ey, 2, 1, C.eye, false)
		_:
			p.rect(cx - 2, ey, 1, 2, C.eye, false)
			p.rect(cx + 1, ey, 1, 2, C.eye, false)
			p.dot(cx - 3, ey, Color.WHITE)
			p.dot(cx + 2, ey, Color.WHITE)
	if F.brow:
		p.rect(cx - 4, ey - 1, 8, 1, skin.darkened(0.32), false)
	elif not F.fem and F.eyes == "normal":
		p.rect(cx - 3, ey - 2, 2, 1, hair.darkened(0.35), false)
		p.rect(cx + 1, ey - 2, 2, 1, hair.darkened(0.35), false)
	if F.nose:
		p.rect(cx - 1, ey + 1, 2, 2, skin.darkened(0.2), false)
	if look.get("age", "") == "old":
		p.dot(cx - 3, ey + 2, skin.darkened(0.25))
		p.dot(cx + 2, ey + 2, skin.darkened(0.25))
	var beard = look.get("beard", F.race == "dwarf" and not F.fem)
	if typeof(beard) == TYPE_STRING and beard == "stubble":
		p.rect(x0 + 1, my - 1, hw - 2, 3, skin.darkened(0.2), false)
		beard = false
	if typeof(beard) == TYPE_BOOL and beard:
		p.rect(x0, my - 1, hw, 4, hair)
		if F.race == "dwarf":
			p.rect(x0 + 1, my + 3, hw - 2, 5, hair)
			p.rect(x0 + 3, my + 8, hw - 6, 2, hair)
			p.rect(cx - 1, my + 4, 2, 5, hair.lightened(0.2), false)
		p.rect(cx - 1, my, 2, 1, hair.darkened(0.45), false)
	elif A.mouth:
		p.rect(cx - 1, my, 2, 2, DARK, false)
	elif F.fem:
		p.rect(cx - 1, my, 2, 1, C.lips, false)
	else:
		p.rect(cx - 1, my, 2, 1, skin.darkened(0.38), false)
	if A.mouth and typeof(beard) == TYPE_BOOL and beard:
		p.rect(cx - 1, my, 2, 2, DARK, false)
	if F.tusks:
		p.rect(cx - 3, my - 1, 1, 2, Color("#f0ead8"), false)
		p.rect(cx + 2, my - 1, 1, 2, Color("#f0ead8"), false)


## Hair that hangs behind the shoulders (drawn before the body in the front view).
static func _hair_behind(p: Px, look: Dictionary, F: Dictionary, C: Dictionary, cx: int, head_y: int) -> void:
	var hw: int = F.hw
	var hh: int = F.hh
	var x0: int = cx - hw / 2
	var hair: Color = C.hair
	match look.get("hairStyle", "short"):
		"long":
			p.rect(x0 - 1, head_y + 2, hw + 2, hh + 5, hair.darkened(0.2))
		"wavy":
			p.rect(x0 - 3, head_y + 1, hw + 6, hh + 9, hair.darkened(0.2))


static func _hair(p: Px, look: Dictionary, F: Dictionary, C: Dictionary, cx: int, head_y: int, front: bool) -> void:
	var style: String = look.get("hairStyle", "short")
	var hw: int = F.hw
	var hh: int = F.hh
	var x0: int = cx - hw / 2
	var hair: Color = C.hair
	var hi := hair.lightened(0.28)
	var hood: Color = C.cloak if C.has_cloak else C.top.darkened(0.3)
	match style:
		"bald":
			return
		"hood":
			p.rect(x0 - 1, head_y - 2, hw + 2, 5, hood)
			p.rect(x0 - 1, head_y + 3, 2, hh, hood)
			p.rect(x0 + hw - 1, head_y + 3, 2, hh, hood)
			if front:
				p.rect(x0 + 1, head_y + 2, hw - 2, 1, hair, false)
			else:
				p.shaded(x0 - 1, head_y - 2, hw + 2, hh + 5, hood)
			return
		"helm":
			p.shaded(x0 - 1, head_y - 2, hw + 2, 6, STEEL.darkened(0.15))
			if front:
				p.rect(cx - 1, head_y + 4, 2, 4, STEEL.darkened(0.25), false)
			else:
				p.shaded(x0 - 1, head_y - 2, hw + 2, hh + 1, STEEL.darkened(0.2))
			return
		"hat":
			p.rect(x0 - 4, head_y + 1, hw + 8, 2, C.top.darkened(0.2))
			p.rect(x0, head_y - 3, hw, 4, C.top.darkened(0.1))
			p.rect(x0 + 2, head_y - 6, hw - 4, 3, C.top.darkened(0.1))
			p.rect(cx - 1, head_y - 9, 3, 3, C.top.darkened(0.1))
			p.rect(x0, head_y - 1, hw, 1, C.trim, false)
			if not front:
				p.rect(x0, head_y + 3, hw, 6, hair)
			return
		"mohawk":
			p.rect(cx - 1, head_y - 5, 2, 7, hair)
			p.rect(cx - 1, head_y - 4, 1, 3, hi, false)
			if not front:
				p.rect(cx - 1, head_y + 2, 2, hh - 4, hair)
			return
	# every other style starts with a cap of hair on top of the head
	p.rect(x0, head_y - 2, hw, 1, hair)
	p.rect(x0 - 1, head_y - 1, hw + 2, 3, hair)
	p.rect(x0 + 2, head_y - 1, 3, 1, hi, false)
	if front:
		match style:
			"long":
				p.rect(x0 - 1, head_y + 2, 2, hh + 5, hair)
				p.rect(x0 + hw - 1, head_y + 2, 2, hh + 5, hair)
				p.rect(x0 + 1, head_y + 2, 2, 1, hair, false)
			"wavy":
				p.rect(x0 - 2, head_y, hw + 4, 2, hair)
				for i in hh + 8:
					var off := 1 if (i / 2) % 2 == 0 else 0
					p.rect(x0 - 2 - off, head_y + 2 + i, 3, 1, hair)
					p.rect(x0 + hw - 1 + off, head_y + 2 + i, 3, 1, hair)
				p.rect(x0 - 1, head_y + 4, 1, hh, hi, false)
				p.rect(x0 + 1, head_y + 2, 3, 1, hair, false)
				p.rect(x0 + hw - 3, head_y + 2, 2, 1, hair, false)
			"ponytail":
				p.rect(x0 - 1, head_y + 2, 1, 3, hair)
				p.rect(x0 + hw, head_y + 2, 1, 3, hair)
				p.rect(x0 + hw, head_y + 4, 2, 8, hair)
			"bun":
				p.rect(cx - 2, head_y - 5, 4, 3, hair)
				p.rect(x0 - 1, head_y + 2, 1, 2, hair)
				p.rect(x0 + hw, head_y + 2, 1, 2, hair)
			"braids":
				for i in hh + 6:
					p.rect(x0 - 2 + (i % 2), head_y + 3 + i, 2, 1, hair)
					p.rect(x0 + hw - (i % 2), head_y + 3 + i, 2, 1, hair)
				p.rect(x0 - 2, head_y + hh + 8, 2, 1, C.trim, false)
				p.rect(x0 + hw, head_y + hh + 8, 2, 1, C.trim, false)
			"curly":
				for i in range(0, hw + 2, 2):
					p.dot(x0 - 1 + i, head_y - 3, hair, true)
				p.rect(x0 - 2, head_y + 1, 2, 5, hair)
				p.rect(x0 + hw, head_y + 1, 2, 5, hair)
				p.dot(x0 - 3, head_y + 3, hair, true)
				p.dot(x0 + hw + 2, head_y + 3, hair, true)
			"topknot":
				p.rect(cx - 1, head_y - 5, 3, 3, hair)
			_:
				p.rect(x0 - 1, head_y + 2, 2, 2, hair)
				p.rect(x0 + hw - 1, head_y + 2, 2, 2, hair)
	else:
		match style:
			"long":
				p.shaded(x0 - 1, head_y, hw + 2, hh + 7, hair)
			"wavy":
				p.shaded(x0 - 2, head_y, hw + 4, hh + 10, hair)
				for i in range(0, hh + 10, 4):
					p.rect(x0 - 3, head_y + 2 + i, 1, 2, hair)
					p.rect(x0 + hw + 2, head_y + 4 + i, 1, 2, hair)
				p.rect(x0 + 1, head_y + 3, 1, hh + 4, hi, false)
			"ponytail":
				p.rect(x0, head_y, hw, hh - 2, hair)
				p.rect(cx - 1, head_y + 3, 3, hh + 5, hair)
				p.rect(cx - 1, head_y + 3, 3, 1, C.trim, false)
			"bun":
				p.rect(x0, head_y, hw, hh - 2, hair)
				p.rect(cx - 2, head_y - 5, 4, 3, hair)
			"braids":
				p.rect(x0, head_y, hw, hh - 1, hair)
				for i in hh + 4:
					p.rect(x0 + (i % 2), head_y + hh - 1 + i, 2, 1, hair)
					p.rect(x0 + hw - 2 - (i % 2), head_y + hh - 1 + i, 2, 1, hair)
			"curly":
				p.rect(x0 - 2, head_y, hw + 4, hh - 1, hair)
				for i in range(0, hw + 2, 2):
					p.dot(x0 - 1 + i, head_y - 3, hair, true)
			"topknot":
				p.rect(x0, head_y, hw, hh - 2, hair)
				p.rect(cx - 1, head_y - 5, 3, 3, hair)
			_:
				p.rect(x0, head_y, hw, hh - 2, hair)


## Ears are drawn after the hair so that long elf ears and big goblin ears poke through it.
static func _ears(p: Px, F: Dictionary, C: Dictionary, cx: int, head_y: int, covered: bool) -> void:
	var hw: int = F.hw
	var x0: int = cx - hw / 2
	var ey: int = head_y + int(int(F.hh) * 0.45)
	var skin: Color = C.skin
	match F.ear:
		"long":
			p.rect(x0 - 2, ey, 3, 2, skin)
			p.rect(x0 + hw - 1, ey, 3, 2, skin)
			p.rect(x0 - 4, ey - 1, 3, 1, skin)
			p.rect(x0 + hw + 1, ey - 1, 3, 1, skin)
			p.dot(x0 - 5, ey - 2, skin, true)
			p.dot(x0 + hw + 4, ey - 2, skin, true)
		"point":
			if not covered:
				p.rect(x0 - 1, ey - 1, 1, 3, skin)
				p.rect(x0 + hw, ey - 1, 1, 3, skin)
				p.dot(x0 - 2, ey - 2, skin, true)
				p.dot(x0 + hw + 1, ey - 2, skin, true)
		"big":
			for i in 4:
				p.rect(x0 - (5 - i), ey - 2 + i, 5 - i, 1, skin)
				p.rect(x0 + hw, ey - 2 + i, 5 - i, 1, skin)


static func _horns(p: Px, look: Dictionary, F: Dictionary, cx: int, head_y: int) -> void:
	var horns = look.get("horns")
	if horns == null or (typeof(horns) == TYPE_BOOL and not horns):
		return
	var hc := Util.color(horns, Color("#3a2028"))
	var hw: int = F.hw
	var x0: int = cx - hw / 2
	p.rect(x0, head_y - 4, 2, 3, hc)
	p.rect(x0 - 1, head_y - 6, 2, 2, hc)
	p.dot(x0 - 2, head_y - 7, hc, true)
	p.rect(x0 + hw - 2, head_y - 4, 2, 3, hc)
	p.rect(x0 + hw - 1, head_y - 6, 2, 2, hc)
	p.dot(x0 + hw + 1, head_y - 7, hc, true)


## Wings ("wings": "bat" or "feather"; colour "wingColor"). Behind the body from the front, over it from behind.
static func _wings(p: Px, look: Dictionary, cx: int, base_y: int, A: Dictionary) -> void:
	var kind := str(look.get("wings", ""))
	if kind == "" or kind == "false":
		return
	var wc := Util.color(look.get("wingColor", "#e8e4d8" if kind == "feather" else "#4a1a2a"))
	var flap: int = A.bob
	var profile := [4, 8, 11, 13, 13, 12, 12, 10, 9, 9, 7, 6, 4, 3]
	for i in profile.size():
		var w: int = profile[i]
		var y: int = base_y - 5 + i - flap
		p.rect(cx - 5 - w, y, w, 1, wc)
		p.rect(cx + 5, y, w, 1, wc)
	p.line(cx - 6, base_y + 2, cx - 17, base_y - 4 - flap, wc.lightened(0.25), 1, false)
	p.line(cx + 5, base_y + 2, cx + 16, base_y - 4 - flap, wc.lightened(0.25), 1, false)
	p.line(cx - 6, base_y + 2, cx - 13, base_y + 6 - flap, wc.lightened(0.25), 1, false)
	p.line(cx + 5, base_y + 2, cx + 12, base_y + 6 - flap, wc.lightened(0.25), 1, false)


static func _tail(p: Px, look: Dictionary, cx: int, hip_y: int, A: Dictionary) -> void:
	if not look.get("tail", false):
		return
	var tc := Util.color(look.get("wingColor", "#4a1a2a"))
	var sway: int = A.bob
	p.line(cx + 3, hip_y + 2, cx + 12, hip_y + 9, tc, 1)
	p.line(cx + 12, hip_y + 9, cx + 15, hip_y + 3 - sway, tc, 1)
	p.rect(cx + 14, hip_y + 1 - sway, 3, 2, tc)


## Side view (drawn facing RIGHT; the view mirrors it for characters facing left).
static func _side(p: Px, look: Dictionary, F: Dictionary, C: Dictionary, A: Dictionary) -> void:
	var cx: int = 24 + int(A.lean)
	var bob: int = A.bob
	var hw: int = int(F.hw) - 1
	var hh: int = F.hh
	var th: int = F.th
	var lh: int = F.lh
	var lw: int = int(F.lw) + 1
	var aw: int = F.aw
	var hip_y: int = 44 - lh
	var base_y: int = hip_y - th
	var torso_y: int = base_y + bob
	var head_y: int = torso_y - int(F.neck) - hh
	var stride: int = A.stride
	var skin: Color = C.skin
	var top: Color = C.top
	var hair: Color = C.hair
	var outfit: String = C.outfit
	var style: String = look.get("style", "")
	var bones: bool = style == "skeleton"
	var zombie: bool = style == "zombie"
	var hair_style: String = look.get("hairStyle", "short")
	var hx: int = cx - hw / 2 + 1
	var ey: int = head_y + int(hh * 0.45)
	var my: int = head_y + hh - 3

	# --- behind: wing, tail, cloak, long hair ---
	var wings := str(look.get("wings", ""))
	if wings != "" and wings != "false":
		var wc := Util.color(look.get("wingColor", "#e8e4d8" if wings == "feather" else "#4a1a2a"))
		var profile := [3, 6, 9, 11, 12, 12, 11, 10, 9, 8, 6, 5, 3, 2]
		for i in profile.size():
			var w: int = profile[i]
			p.rect(cx - 3 - w, base_y - 5 + i - bob, w, 1, wc)
		p.line(cx - 4, base_y + 2, cx - 14, base_y - 4 - bob, wc.lightened(0.25), 1, false)
	if look.get("tail", false):
		var tc := Util.color(look.get("wingColor", "#4a1a2a"))
		p.line(cx - 3, hip_y + 2, cx - 11, hip_y + 9, tc, 1)
		p.line(cx - 11, hip_y + 9, cx - 14, hip_y + 3 - bob, tc, 1)
		p.rect(cx - 16, hip_y + 1 - bob, 3, 2, tc)
	if C.has_cloak:
		p.shaded(cx - 7, torso_y, 5, th + 9, C.cloak)
	if hair_style == "long":
		p.rect(hx - 2, head_y + 2, 5, hh + 6, hair.darkened(0.12))
	elif hair_style == "wavy":
		for i in hh + 9:
			p.rect(hx - 3 - (1 if (i / 2) % 2 == 0 else 0), head_y + 1 + i, 6, 1, hair.darkened(0.12))
	elif hair_style == "ponytail":
		p.rect(hx - 3, head_y + 3, 3, hh + 3, hair)
	elif hair_style == "braids":
		for i in hh + 5:
			p.rect(hx - 1 + (i % 2), head_y + 4 + i, 2, 1, hair)

	# --- legs or skirt ---
	var hip_d: int = maxi(5, int(round(int(F.hip) * 0.6)))
	if outfit in ["robe", "dress"]:
		var skirt: int = lh if outfit == "robe" else int(lh * 0.65)
		var col: Color = C.top if outfit == "robe" else C.skirt
		if outfit == "dress":
			p.shaded(cx - 2 - stride / 2, hip_y, lw - 1, lh, skin.darkened(0.15))
			p.shaded(cx - 1 + stride / 2, hip_y, lw - 1, lh, skin)
		for r in skirt:
			var d: int = hip_d + int(round(3.0 * r / skirt))
			p.rect(cx - d / 2 - 1, hip_y + r, d + 2, 1, col)
			p.rect(cx - d / 2 - 1, hip_y + r, 1, 1, col.darkened(0.2), false)
		p.rect(cx - (hip_d + 3) / 2 - 1, hip_y + skirt - 1, hip_d + 5, 1, C.trim, false)
		p.rect(cx - 3 - stride / 2, 44, 5, 3, skin if F.barefoot else C.boots)
		p.rect(cx + stride / 2, 44, 5, 3, skin if F.barefoot else C.boots)
	else:
		var up_b: int = 2 if stride < 0 else 0
		var up_f: int = 2 if stride > 0 else 0
		p.shaded(cx - 3 - stride, hip_y, lw, lh - up_b, C.bottom.darkened(0.2))
		p.rect(cx - 3 - stride, 44 - up_b, lw + 2, 3, skin.darkened(0.15) if F.barefoot else C.boots)
		p.shaded(cx - 2 + stride, hip_y, lw, lh - up_f, C.bottom)
		p.rect(cx - 2 + stride, 44 - up_f, lw + 2, 3, skin if F.barefoot else C.boots)

	# --- torso ---
	var br := int(th * 0.38)
	for r in range(bob, th):
		var d: int = maxi(5, int(round(_tw(F, r) * 0.6)))
		var back_x: int = cx - d / 2 - (1 if (F.fem and r >= th - 3) else 0)
		var front_x: int = cx + (d + 1) / 2
		if int(F.bust) > 0 and absi(r - br) <= 1:
			front_x += int(F.bust) if r == br else int(F.bust) - 1
		var col := top
		if r == th - 2 and not (outfit in ["robe", "dress"]) and not bones:
			col = top.darkened(0.45)
		p.rect(back_x, base_y + r, front_x - back_x, 1, col)
		p.rect(back_x, base_y + r, 1, 1, col.darkened(0.2), false)
	if bones:
		for ry in range(torso_y + 2, base_y + th - 1, 2):
			p.rect(cx - 2, ry, 5, 1, DARK, false)
	elif outfit in ["bodice", "dress"] or (F.fem and outfit in ["tunic", "leather"]):
		p.rect(cx + 1, torso_y, 2, 1, skin, false)

	# --- head ---
	if int(F.neck) > 0:
		p.rect(cx - 1, head_y + hh, 3, int(F.neck), skin.darkened(0.15))
	for r in hh:
		var cut := 0
		if r == 0 or (r == hh - 1 and F.jaw != "square"):
			cut = 1
		p.rect(hx + cut, head_y + r, hw - cut - (1 if (r >= hh - 2 and F.jaw == "pointed") else 0), 1, skin)
	p.rect(hx, head_y + 1, 1, hh - 3, skin.darkened(0.14), false)
	if bones:
		p.rect(hx + hw - 4, ey - 1, 2, 3, DARK, false)
		p.rect(hx + hw - 3, head_y + hh - 1, 3, 1, DARK, false)
	else:
		p.dot(hx + hw, ey + 2, skin, true)
		if F.nose:
			p.rect(hx + hw, ey + 1, 2, 2, skin.darkened(0.1))
		if F.eyes == "narrow":
			p.rect(hx + hw - 3, ey, 2, 1, C.eye, false)
		else:
			p.rect(hx + hw - 3, ey, 1, 2, C.eye, false)
			if F.eyes == "big":
				p.dot(hx + hw - 2, ey, Color.WHITE)
				if F.fem:
					p.rect(hx + hw - 4, ey - 1, 3, 1, DARK, false)
		if F.brow:
			p.rect(hx + hw - 4, ey - 1, 5, 1, skin.darkened(0.32), false)
		var beard = look.get("beard", F.race == "dwarf" and not F.fem)
		if typeof(beard) == TYPE_BOOL and beard:
			p.rect(hx + hw - 5, my - 1, 6, 4, hair)
			if F.race == "dwarf":
				p.rect(hx + hw - 4, my + 3, 5, 6, hair)
		elif A.mouth:
			p.rect(hx + hw - 2, my, 2, 2, DARK, false)
		elif F.fem:
			p.rect(hx + hw - 2, my, 2, 1, C.lips, false)
		else:
			p.rect(hx + hw - 2, my, 2, 1, skin.darkened(0.38), false)
		if F.tusks:
			p.rect(hx + hw - 2, my - 1, 1, 2, Color("#f0ead8"), false)
	match F.ear:
		"long":
			p.rect(hx + 2, ey, 3, 2, skin.darkened(0.1), false)
			p.rect(hx, ey - 1, 3, 1, skin)
			p.dot(hx - 1, ey - 2, skin, true)
		"point":
			p.rect(hx + 2, ey - 1, 2, 3, skin.darkened(0.1), false)
			p.dot(hx + 1, ey - 2, skin, true)
		"big":
			for i in 4:
				p.rect(hx - 2 + i, ey - 3 + i, 5 - i, 1, skin.darkened(0.08))
	var hood: Color = C.cloak if C.has_cloak else top.darkened(0.3)
	match hair_style:
		"bald":
			pass
		"hood":
			p.shaded(hx - 1, head_y - 2, hw - 2, hh + 4, hood)
			p.rect(hx + hw - 3, head_y - 2, 4, 4, hood)
		"helm":
			p.shaded(hx - 1, head_y - 2, hw + 2, 6, STEEL.darkened(0.15))
			p.rect(hx - 1, head_y + 4, 5, 5, STEEL.darkened(0.2))
		"hat":
			p.rect(hx - 3, head_y + 1, hw + 7, 2, top.darkened(0.2))
			p.rect(hx, head_y - 3, hw, 4, top.darkened(0.1))
			p.rect(hx + 2, head_y - 7, hw - 5, 4, top.darkened(0.1))
			p.rect(hx - 1, head_y + 3, 5, 7, hair)
		"mohawk":
			p.rect(hx + 1, head_y - 5, hw - 2, 5, hair)
		_:
			p.rect(hx, head_y - 2, hw - 1, 1, hair)
			p.rect(hx - 1, head_y - 1, hw + 1, 3, hair)
			p.rect(hx - 1, head_y + 2, 4, hh - 4, hair)
			p.rect(hx + 2, head_y - 1, 3, 1, hair.lightened(0.28), false)
			if hair_style == "bun":
				p.rect(hx - 3, head_y - 1, 3, 4, hair)
			elif hair_style == "topknot":
				p.rect(hx + 2, head_y - 5, 3, 3, hair)
			elif hair_style == "curly":
				for i in range(0, hw, 2):
					p.dot(hx - 1 + i, head_y - 3, hair, true)
				p.rect(hx - 2, head_y + 1, 2, 5, hair)
			elif hair_style in ["long", "wavy"]:
				p.rect(hx + hw - 3, head_y + 2, 2, 3, hair, false)
	var horns = look.get("horns")
	if horns != null and not (typeof(horns) == TYPE_BOOL and not horns):
		var hc := Util.color(horns, Color("#3a2028"))
		p.rect(hx + hw - 4, head_y - 4, 2, 3, hc)
		p.rect(hx + hw - 3, head_y - 6, 2, 2, hc)
		p.dot(hx + hw - 1, head_y - 7, hc, true)

	# --- arm and weapon (in front of the body) ---
	var sleeve: Color = top.darkened(0.12) if C.sleeves else skin
	var weapon: String = look.get("weapon", "none")
	var al: int = th - 3
	var pose: int = A.pose
	if A.raise:
		p.shaded(cx, torso_y - 5, aw, 8, sleeve)
		p.rect(cx, torso_y - 7, aw, 2, skin)
		if int(A.f) % 2 == 1:
			p.rect(cx + 4, torso_y - 12, 3, 3, C.trim.lightened(0.4), false)
		_weapon(p, weapon, cx + 2, torso_y - 6, 1, 0, C.trim)
	elif zombie or pose == 2:
		p.shaded(cx, torso_y + 2, 9, aw, sleeve)
		p.rect(cx + 9, torso_y + 2, 2, aw, skin)
		if not zombie:
			_weapon(p, weapon, cx + 11, torso_y + 3, 1, 2, C.trim)
	elif pose == 1:
		p.shaded(cx - 2, torso_y - 6, aw, 9, sleeve)
		p.rect(cx - 2, torso_y - 8, aw, 2, skin)
		_weapon(p, weapon, cx - 1, torso_y - 7, 1, 1, C.trim)
	else:
		var swing: int = -stride / 2
		p.shaded(cx - 1 + swing, torso_y + 1, aw, al, sleeve)
		p.rect(cx - 1 + swing, torso_y + 1 + al, aw, 2, skin)
		_weapon(p, weapon, cx + 1 + swing, torso_y + 1 + al, 1, 0, C.trim)


## Draws a held weapon. (hx, hy) = hand position, side = +1 (extends right) or -1 (left),
## pose 0 = held upright, 1 = raised to strike, 2 = struck forward.
static func _weapon(p: Px, kind: String, hx: int, hy: int, side: int, pose: int, trim: Color) -> void:
	if kind == "none" or kind == "":
		return
	if pose == 2:
		var x0 := hx if side > 0 else hx - 13
		match kind:
			"bow":
				p.rect(hx if side > 0 else hx - 1, hy - 8, 1, 17, WOOD)
				p.rect(x0 + (2 if side > 0 else 0), hy, 12, 1, Color("#e8e0c8"))
			"staff", "spear":
				p.rect(x0 - (4 if side > 0 else -4), hy, 18, 2, WOOD)
				p.rect(x0 + (14 if side > 0 else -3), hy - 1, 3, 4, STEEL if kind == "spear" else trim)
			"axe", "mace":
				p.rect(x0, hy, 11, 2, WOOD)
				p.rect(x0 + (9 if side > 0 else 0), hy - 2, 4, 6, STEEL)
			_:
				p.rect(x0 + (0 if side > 0 else 1), hy, 13 if kind != "dagger" else 7, 2, STEEL)
				p.rect(hx if side > 0 else hx - 1, hy - 2, 1, 6, trim)
		return
	var y := hy - (2 if pose == 1 else 0)
	match kind:
		"sword":
			p.rect(hx, y - 14, 2, 13, STEEL)
			p.rect(hx - 2, y - 1, 6, 1, trim)
			p.rect(hx, y, 2, 3, WOOD)
		"dagger":
			p.rect(hx, y - 7, 2, 6, STEEL)
			p.rect(hx - 1, y - 1, 4, 1, trim)
			p.rect(hx, y, 2, 2, WOOD)
		"axe":
			p.rect(hx, y - 13, 2, 17, WOOD)
			p.rect(hx + (2 if side > 0 else -4), y - 13, 4, 7, STEEL)
		"mace":
			p.rect(hx, y - 10, 2, 14, WOOD)
			p.rect(hx - 1, y - 14, 4, 5, STEEL)
			p.dot(hx - 2, y - 12, STEEL, true)
			p.dot(hx + 3, y - 12, STEEL, true)
		"staff":
			p.rect(hx, y - 24, 2, 36, WOOD)
			p.rect(hx - 1, y - 28, 4, 4, trim.lightened(0.2))
		"spear":
			p.rect(hx, y - 26, 2, 38, WOOD)
			p.rect(hx, y - 31, 2, 5, STEEL)
		"bow":
			p.rect(hx + side * 2, y - 9, 1, 18, WOOD)
			p.rect(hx + side, y - 12, 1, 4, WOOD)
			p.rect(hx + side, y + 8, 1, 4, WOOD)
			p.rect(hx, y - 12, 1, 24, Color("#e8e0c8"), false)


# ----------------------------------------------------------------------------------------------
# Props and simple creatures: one view
# ----------------------------------------------------------------------------------------------

static func _simple_frames(template: String) -> Array:
	if template in CREATURES:
		return CREATURE_ANIMS
	if template in ["torch", "brazier", "campfire", "lamp_post", "loot"]:
		return [["idle", 3, 6.0, true]]
	return [["idle", 1, 1.0, true]]


static func _build_simple(template: String, look: Dictionary) -> Dictionary:
	var size: Vector2i = BIG.get(template, Vector2i(48, 48))
	var defs := _simple_frames(template)
	var img := Image.create(size.x * COLS, size.y * defs.size(), false, Image.FORMAT_RGBA8)
	var anims := {}
	var row := 0
	for a in defs:
		anims[a[0]] = {"row": row, "frames": a[1], "fps": a[2], "loop": a[3]}
		for f in int(a[1]):
			var p := Px.new()
			var upside: bool = _draw_simple(p, template, look, a[0], f, size)
			if a[0] == "dead" and upside:
				_flip_ops_vertical(p, size.y)
			p.stamp(img, f * size.x, row * size.y, size.x, size.y)
		row += 1
	return {"texture": ImageTexture.create_from_image(img), "fw": size.x, "fh": size.y, "cols": COLS, "rows": defs.size(), "views": 1, "anims": anims}


## Dead creatures are drawn on their backs: mirror every rectangle around the creature's body line.
static func _flip_ops_vertical(p: Px, fh: int) -> void:
	var top := fh
	for o in p.ops:
		top = mini(top, o[1])
	for o in p.ops:
		o[1] = fh - 1 - (o[1] - top) - o[3] + 1


## Draws one frame. Creatures face RIGHT. Returns true when a "dead" frame should be flipped upside down.
static func _draw_simple(p: Px, t: String, look: Dictionary, anim: String, f: int, size: Vector2i) -> bool:
	var w := size.x
	var h := size.y
	var cx := w / 2
	var g := h - 1   # ground line
	match t:
		"rat":
			var fur := Util.color(look.get("fur", "#6b5a4a"))
			var lunge := 4 if (anim == "attack" and f == 1) else 0
			var step := 1 if (anim == "walk" and f == 1) else 0
			p.line(cx - 12, g - 6, cx - 19, g - 9 - (f % 2), Color("#c9a0a0"), 1)
			p.ellipse(cx - 2 + lunge, g - 7, 10, 5, fur)
			p.ellipse(cx + 9 + lunge, g - 6, 5, 4, fur.lightened(0.08))
			p.rect(cx + 6 + lunge, g - 12, 3, 3, fur.darkened(0.2))
			p.rect(cx + 13 + lunge, g - 6, 3, 2, Color("#d9a0a0"))
			p.dot(cx + 10 + lunge, g - 8, Color("#ff3030"))
			p.rect(cx - 8 + lunge + step, g - 2, 3, 3, fur.darkened(0.3))
			p.rect(cx + 3 + lunge - step, g - 2, 3, 3, fur.darkened(0.3))
			return true
		"wolf":
			var fur := Util.color(look.get("fur", "#7a7a80"))
			var lunge := 5 if (anim == "attack" and f == 1) else 0
			var step := 2 if (anim == "walk" and f == 1) else 0
			p.line(cx - 14, g - 15, cx - 20, g - 11 + (f % 2), fur.darkened(0.15), 3)
			p.shaded(cx - 13 + lunge, g - 19, 24, 10, fur)
			p.shaded(cx + 8 + lunge, g - 24, 9, 9, fur.lightened(0.06))
			p.rect(cx + 15 + lunge, g - 20, 5, 4, fur.lightened(0.12))
			p.rect(cx + 9 + lunge, g - 28, 3, 4, fur.darkened(0.2))
			p.rect(cx + 14 + lunge, g - 28, 3, 4, fur.darkened(0.2))
			p.dot(cx + 14 + lunge, g - 21, Color("#ffd040"))
			if anim == "attack" and f == 1:
				p.rect(cx + 16 + lunge, g - 16, 4, 2, Color.WHITE, false)
			for lxo in [-12, -7, 5, 9]:
				var s := step if (lxo == -12 or lxo == 5) else -step
				p.rect(cx + lxo + lunge + s, g - 9, 3, 10, fur.darkened(0.25))
			return true
		"spider":
			var body := Util.color(look.get("body", "#2a2430"))
			var lunge := 3 if (anim == "attack" and f == 1) else 0
			var wig := 1 if ((anim == "walk" or anim == "idle") and f == 1) else 0
			for i in 4:
				var ax := cx - 4 + i * 3 + lunge
				p.line(ax, g - 10, ax - 9 - i, g - 16 + wig * (i % 2), body.lightened(0.15), 1)
				p.line(ax - 9 - i, g - 16 + wig * (i % 2), ax - 13 - i, g, body.lightened(0.15), 1)
				p.line(ax + 2, g - 10, ax + 11 + i, g - 16 + wig * ((i + 1) % 2), body.lightened(0.15), 1)
				p.line(ax + 11 + i, g - 16 + wig * ((i + 1) % 2), ax + 15 + i, g, body.lightened(0.15), 1)
			p.ellipse(cx - 4 + lunge, g - 10, 8, 6, body)
			p.ellipse(cx + 6 + lunge, g - 8, 5, 4, body.lightened(0.1))
			p.dot(cx + 8 + lunge, g - 9, Color("#ff2020"))
			p.dot(cx + 10 + lunge, g - 9, Color("#ff2020"))
			p.dot(cx + 9 + lunge, g - 7, Color("#ff2020"))
			return true
		"barrel":
			p.shaded(cx - 11, g - 38, 22, 38, Color("#7a5630"))
			p.rect(cx - 13, g - 30, 26, 22, Color("#7a5630"), true)
			p.shaded(cx - 13, g - 30, 26, 22, Color("#86602f"))
			for by in [g - 33, g - 20, g - 6]:
				p.rect(cx - 13, by, 26, 2, Color("#4a4a52"), false)
			p.rect(cx - 2, g - 38, 1, 38, Color("#5a3e20"), false)
			p.rect(cx + 6, g - 38, 1, 38, Color("#5a3e20"), false)
		"crate":
			p.shaded(cx - 16, g - 32, 32, 32, Color("#8a6436"))
			p.rect(cx - 16, g - 32, 32, 3, Color("#5e4222"), false)
			p.rect(cx - 16, g - 3, 32, 3, Color("#5e4222"), false)
			p.rect(cx - 16, g - 32, 3, 32, Color("#5e4222"), false)
			p.rect(cx + 13, g - 32, 3, 32, Color("#5e4222"), false)
			p.line(cx - 13, g - 29, cx + 11, g - 5, Color("#5e4222"), 2, false)
		"sack":
			p.ellipse(cx, g - 10, 12, 10, Color("#b09a6a"))
			p.rect(cx - 3, g - 24, 6, 5, Color("#b09a6a"))
			p.rect(cx - 4, g - 20, 8, 1, Color("#6a5a3a"), false)
		"chest":
			p.shaded(cx - 17, g - 20, 34, 20, Color("#7a4f28"))
			p.shaded(cx - 17, g - 30, 34, 11, Color("#8c5c2e"))
			p.rect(cx - 17, g - 20, 34, 2, Color("#3a2614"), false)
			p.rect(cx - 17, g - 30, 3, 30, Color("#b89a3a"), false)
			p.rect(cx + 14, g - 30, 3, 30, Color("#b89a3a"), false)
			p.rect(cx - 3, g - 22, 6, 7, Color("#d8b84a"), false)
			p.rect(cx - 1, g - 19, 2, 2, DARK, false)
		"table":
			p.shaded(cx - 20, g - 24, 40, 5, Color("#8a6236"))
			p.rect(cx - 17, g - 19, 4, 19, Color("#5e4222"))
			p.rect(cx + 13, g - 19, 4, 19, Color("#5e4222"))
			p.rect(cx - 6, g - 29, 5, 5, Color("#c8ccd4"))
			p.rect(cx + 4, g - 28, 6, 4, Color("#a05a30"))
		"bed":
			p.shaded(cx - 21, g - 14, 42, 10, Color("#8a2f38"))
			p.rect(cx - 21, g - 4, 4, 4, Color("#5e4222"))
			p.rect(cx + 17, g - 4, 4, 4, Color("#5e4222"))
			p.shaded(cx - 22, g - 22, 5, 22, Color("#6b4a2a"))
			p.shaded(cx - 16, g - 18, 10, 5, Color("#e8e2d0"))
		"bookshelf":
			p.shaded(cx - 17, g - 45, 34, 45, Color("#5e4222"))
			var cols := [Color("#8a2a2a"), Color("#2a4a8a"), Color("#3a7a3a"), Color("#a07a2a"), Color("#6a3a7a")]
			for sh in 4:
				var sy := g - 43 + sh * 11
				p.rect(cx - 15, sy, 30, 9, Color("#2a1c12"), false)
				for b in 9:
					p.rect(cx - 15 + b * 3 + (b % 2), sy + 1 + (b * 7 + sh) % 3, 2, 8 - (b * 7 + sh) % 3, cols[(b + sh * 2) % 5], false)
		"torch":
			p.rect(cx - 1, g - 34, 3, 34, WOOD)
			p.rect(cx - 3, g - 37, 7, 4, Color("#3a3a40"))
			_flame(p, cx, g - 38, 4, f)
		"brazier":
			p.rect(cx - 2, g - 22, 4, 22, Color("#3a3a40"))
			p.rect(cx - 9, g - 2, 18, 2, Color("#3a3a40"))
			p.shaded(cx - 11, g - 28, 22, 7, Color("#4a4a52"))
			_flame(p, cx, g - 29, 7, f)
		"campfire":
			p.line(cx - 13, g - 2, cx + 11, g - 8, Color("#4a3018"), 4)
			p.line(cx + 13, g - 2, cx - 11, g - 8, Color("#5e3e20"), 4)
			for sx in [-16, -10, 9, 15]:
				p.rect(cx + sx, g - 3, 4, 4, Color("#77737a"))
			_flame(p, cx, g - 8, 9, f)
		"lamp_post":
			p.rect(cx - 1, g - 40, 3, 40, Color("#33333a"))
			p.rect(cx - 5, g - 3, 11, 3, Color("#33333a"))
			p.shaded(cx - 5, g - 47, 11, 9, Color("#33333a"))
			p.rect(cx - 3, g - 45, 7, 5, Color("#ffd870") if f != 1 else Color("#ffe9a0"), false)
		"tree":
			p.shaded(cx - 5, g - 44, 10, 44, Color("#5a3e22"))
			p.rect(cx - 9, g - 4, 18, 4, Color("#5a3e22"))
			p.ellipse(cx, g - 62, 26, 22, Color("#2f5e28"))
			p.ellipse(cx - 12, g - 52, 14, 12, Color("#3a7030"), false)
			p.ellipse(cx + 10, g - 68, 13, 11, Color("#3a7030"), false)
			p.ellipse(cx - 6, g - 72, 10, 8, Color("#4f8a3c"), false)
			p.ellipse(cx + 14, g - 50, 8, 6, Color("#264d20"), false)
		"pine":
			p.shaded(cx - 3, g - 22, 6, 22, Color("#4a3220"))
			for i in 5:
				var half := 24 - i * 4
				var by := g - 18 - i * 15
				for r in 16:
					var ww := int(half * (1.0 - r / 17.0))
					p.rect(cx - ww, by - r, ww * 2 + 1, 1, Color("#1f4a2a") if (r + i) % 5 != 0 else Color("#2f6a3a"))
		"bush":
			p.ellipse(cx, g - 11, 19, 11, Color("#2f5e28"))
			p.ellipse(cx - 7, g - 15, 8, 6, Color("#4f8a3c"), false)
			p.ellipse(cx + 9, g - 9, 6, 4, Color("#264d20"), false)
			p.dot(cx + 3, g - 16, Color("#d04a4a"))
			p.dot(cx - 11, g - 8, Color("#d04a4a"))
		"rock":
			p.ellipse(cx, g - 9, 17, 9, Color("#77737a"))
			p.ellipse(cx - 5, g - 13, 8, 5, Color("#918c92"), false)
			p.rect(cx + 4, g - 6, 9, 2, Color("#55525a"), false)
		"log":
			p.shaded(cx - 20, g - 11, 40, 11, Color("#6b4a2a"))
			p.ellipse(cx + 19, g - 6, 3, 5, Color("#b89a6a"))
			p.rect(cx - 12, g - 9, 10, 1, Color("#4a3018"), false)
		"tent":
			for r in 40:
				var ww := int(34.0 * r / 40.0)
				p.rect(cx - ww, g - 40 + r, ww * 2 + 1, 1, Color("#b9a67c") if r % 9 != 0 else Color("#9a8860"))
			for r in 26:
				var ww := int(9.0 * r / 26.0)
				p.rect(cx - ww, g - 26 + r, ww * 2 + 1, 1, Color("#2a2420"), false)
			p.rect(cx - 1, g - 46, 2, 8, WOOD)
		"well":
			p.shaded(cx - 15, g - 16, 30, 16, Color("#77737a"))
			p.rect(cx - 15, g - 16, 30, 3, Color("#918c92"), false)
			p.rect(cx - 14, g - 40, 3, 24, WOOD)
			p.rect(cx + 11, g - 40, 3, 24, WOOD)
			p.shaded(cx - 18, g - 46, 36, 7, Color("#7a3a2a"))
			p.rect(cx - 1, g - 39, 1, 14, Color("#d8d0b8"), false)
		"sign":
			p.rect(cx - 2, g - 28, 4, 28, WOOD)
			p.shaded(cx - 15, g - 38, 30, 14, Color("#9a7442"))
			p.rect(cx - 10, g - 34, 20, 1, DARK, false)
			p.rect(cx - 10, g - 30, 14, 1, DARK, false)
		"market_stall":
			p.rect(cx - 30, g - 40, 3, 40, WOOD)
			p.rect(cx + 27, g - 40, 3, 40, WOOD)
			p.shaded(cx - 30, g - 20, 60, 6, Color("#8a6236"))
			for i in 6:
				p.rect(cx - 33 + i * 11, g - 47, 11, 9, Color("#b03a3a") if i % 2 == 0 else Color("#e8e2d0"))
			p.ellipse(cx - 15, g - 24, 4, 3, Color("#d04a2a"))
			p.ellipse(cx - 2, g - 24, 4, 3, Color("#d9b83a"))
			p.ellipse(cx + 12, g - 24, 4, 3, Color("#5a9a3a"))
		"anvil":
			p.shaded(cx - 14, g - 20, 28, 7, Color("#4a4a52"))
			p.rect(cx + 12, g - 18, 7, 3, Color("#4a4a52"))
			p.shaded(cx - 6, g - 13, 12, 7, Color("#3a3a42"))
			p.shaded(cx - 10, g - 6, 20, 6, Color("#3a3a42"))
		"pillar":
			p.shaded(cx - 7, g - 44, 14, 44, Color("#8f8982"))
			p.shaded(cx - 10, g - 47, 20, 5, Color("#a59e96"))
			p.shaded(cx - 10, g - 4, 20, 4, Color("#a59e96"))
			p.rect(cx - 2, g - 42, 1, 38, Color("#6f6a66"), false)
			p.rect(cx + 3, g - 42, 1, 38, Color("#6f6a66"), false)
		"statue":
			p.shaded(cx - 11, g - 9, 22, 9, Color("#77737a"))
			p.shaded(cx - 6, g - 32, 12, 23, Color("#9a969c"))
			p.shaded(cx - 5, g - 42, 10, 10, Color("#a8a4aa"))
			p.rect(cx - 10, g - 30, 4, 12, Color("#8a868c"))
			p.rect(cx + 6, g - 30, 4, 12, Color("#8a868c"))
			p.rect(cx + 8, g - 44, 2, 16, Color("#8a868c"))
		"altar":
			p.shaded(cx - 19, g - 22, 38, 5, Color("#a59e96"))
			p.shaded(cx - 15, g - 17, 30, 17, Color("#77737a"))
			p.rect(cx - 2, g - 13, 4, 9, Color("#7a1f28"), false)
			p.rect(cx - 5, g - 10, 10, 3, Color("#7a1f28"), false)
			p.rect(cx - 13, g - 28, 3, 6, Color("#e8e2d0"))
			p.dot(cx - 12, g - 30, Color("#ffd040"), true)
			p.rect(cx + 10, g - 28, 3, 6, Color("#e8e2d0"))
			p.dot(cx + 11, g - 30, Color("#ffd040"), true)
		"coffin":
			p.shaded(cx - 20, g - 13, 40, 13, Color("#4a3220"))
			p.rect(cx - 20, g - 13, 40, 3, Color("#5e4222"), false)
			p.rect(cx - 1, g - 12, 2, 1, Color("#b89a3a"), false)
			p.rect(cx - 12, g - 8, 2, 2, Color("#b89a3a"), false)
			p.rect(cx + 10, g - 8, 2, 2, Color("#b89a3a"), false)
		"gravestone":
			p.shaded(cx - 9, g - 22, 18, 22, Color("#77737a"))
			p.ellipse(cx, g - 22, 9, 5, Color("#77737a"))
			p.rect(cx - 1, g - 19, 2, 10, Color("#4a464c"), false)
			p.rect(cx - 4, g - 16, 8, 2, Color("#4a464c"), false)
		"bones":
			p.line(cx - 12, g - 2, cx + 8, g - 5, Color("#d9d4c2"), 2)
			p.line(cx - 6, g - 6, cx + 12, g - 1, Color("#cfc8b4"), 2)
			p.ellipse(cx - 12, g - 6, 4, 4, Color("#d9d4c2"))
			p.dot(cx - 13, g - 6, DARK)
			p.dot(cx - 11, g - 6, DARK)
		"stairs":
			for i in 5:
				p.rect(cx - 18 + i * 2, g - 4 - i * 5, 36 - i * 4, 5, Color("#3a3640").darkened(i * 0.14))
			p.rect(cx - 9, g - 28, 18, 5, Color("#0c0a10"))
		"loot":
			p.ellipse(cx, g - 6, 7, 6, Color("#8a6a3a"))
			p.rect(cx - 2, g - 14, 4, 3, Color("#8a6a3a"))
			var tw: Vector2i = [Vector2i(-9, -16), Vector2i(8, -19), Vector2i(1, -24)][f]
			p.rect(cx + tw.x - 2, g + tw.y, 5, 1, Color("#fff2a8"), false)
			p.rect(cx + tw.x, g + tw.y - 2, 1, 5, Color("#fff2a8"), false)
		_:
			p.shaded(cx - 12, g - 24, 24, 24, Color("#a04aa0"))
	return false


static func _flame(p: Px, cx: int, base_y: int, r: int, f: int) -> void:
	var sway: int = [0, 1, -1][f % 3]
	var tall: int = [0, 2, 1][f % 3]
	p.ellipse(cx + sway, base_y - r, r, r + 1 + tall, Color("#e8581a"), false)
	p.ellipse(cx, base_y - r + 2, maxi(1, r - 2), r - 1, Color("#ffa52a"), false)
	p.ellipse(cx - sway, base_y - r + 3, maxi(1, r - 4), maxi(1, r - 3), Color("#ffe27a"), false)
