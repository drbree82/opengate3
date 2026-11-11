class_name Ent
extends RefCounted
## One thing standing on the current map: a party member, NPC, monster or prop.
## Entities are plain data; src/render/world_view.gd draws a billboard sprite for each one.
## Positions are in tile coordinates: the centre of tile (3, 5) is x = 3.5, y = 5.5.

var id := ""
var template := ""
var kind := "prop"            # "party" | "npc" | "monster" | "prop"
var name := ""
var x := 0.0
var y := 0.0
var facing := PI / 2.0        # radians: 0 = east (+x), PI/2 = south (+y, towards the bottom of the map text)
var sprite: Dictionary = {}   # {template, height, look}  see docs/SPRITES.md
var anim := "idle"            # idle | walk | attack | cast | talk | hurt | dead
var anim_t := 0.0
var blocking := true
var actor = null              # character Dictionary or monster actor Dictionary (null for props)
var char_id := ""             # roster id for party members and companion NPCs
var side := "neutral"         # "party" | "enemy" | "neutral"
var group := ""               # encounter group (monsters with the same group fight together)
var hostile := false
var dialogue := ""
var interact = null           # Array of script actions run when the player uses this entity
var light = null              # {radius, color, power}
var hidden := false
var dead := false
var data: Dictionary = {}     # the full template (with legend overrides)
var combat = null             # per-encounter state Dictionary while fighting
var path: Array = []          # exploration path: Array of Vector2i tiles
var flash := 0.0              # seconds of white "hit" flash left
var temp := false             # spawned by a cutscene; removed when it ends


func cell() -> Vector2i:
	return Vector2i(floori(x), floori(y))


func pos() -> Vector2:
	return Vector2(x, y)


func set_cell(c: Vector2i) -> void:
	x = c.x + 0.5
	y = c.y + 0.5


func dist_to(other: Ent) -> float:
	return pos().distance_to(other.pos())


func face_point(p: Vector2) -> void:
	var d := p - pos()
	if d.length() > 0.01:
		facing = atan2(d.y, d.x)


func set_anim(a: String) -> void:
	if anim != a:
		anim = a
		anim_t = 0.0


## Is this a creature that still exists in the fight / world (may be unconscious)?
func alive() -> bool:
	return actor != null and not dead and not hidden


## Unconscious (0 hp or less) but not dead.
func down() -> bool:
	return actor != null and int(actor.get("hp", 1)) <= 0


## Alive and conscious.
func can_act() -> bool:
	return alive() and not down()


static func facing_from(v) -> float:
	if typeof(v) == TYPE_STRING:
		match str(v).to_upper():
			"E":
				return 0.0
			"S":
				return PI / 2.0
			"W":
				return PI
			"N":
				return -PI / 2.0
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return deg_to_rad(float(v))
	return PI / 2.0
