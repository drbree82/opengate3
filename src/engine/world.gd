class_name World
extends RefCounted
## The current map and everything standing on it. Handles exploration movement (leader + followers),
## clicking/interacting, doors, triggers, exits, monster aggro and per-map saved state.
## Pure logic: the 3D picture is drawn by src/render/world_view.gd, which listens to the signals below.

signal rebuilt        # walls / doors / lights changed: the view rebuilds the room mesh
signal ents_changed   # entities were added or removed: the view syncs its sprites

const WALK_SPEED := 3.4
const RADIUS := 0.24
const INTERACT_RANGE := 1.8
const AGGRO_RANGE := 4.5

var game
var map: MapData = null
var ents: Array = []
var move_input := Vector2.ZERO     # set by the UI every frame: world-space walk direction (WASD)
var pending: Ent = null            # entity to interact with once the leader arrives
var pending_door = null            # Vector2i door tile to try once the leader arrives
var seen := PackedByteArray()      # minimap fog of war (1 = seen)
var highlights: Dictionary = {}    # Vector2i -> Color, floor overlays drawn by the view (combat ranges)
var _last_cell := Vector2i(-99, -99)
var _follow_t := 0.0
var _door_cooldown := 0.0


func _init(g) -> void:
	game = g


# ----------------------------------------------------------------------------------------------
# Loading
# ----------------------------------------------------------------------------------------------

## Loads a map and places the party. `at` = marker name, Vector2 position, or null (marker "start").
func load_map(map_id: String, at = null, facing = null) -> bool:
	var raw = game.campaign.get("maps", {}).get(map_id)
	if raw == null:
		push_error("Unknown map '%s'" % map_id)
		return false
	map = MapData.parse(raw, map_id)
	for e in map.errors:
		push_error("Map %s: %s" % [map_id, e])
	ents.clear()
	highlights.clear()
	pending = null
	pending_door = null
	game.state["mapId"] = map_id
	var ms := map_state()
	for c in ms.opened:
		map.open_door(int(c[0]), int(c[1]))
	for t in ms.tiles:
		map.set_char(int(t[0]), int(t[1]), str(t[2]))
	seen = PackedByteArray()
	if str(ms.get("seen", "")).length() == map.w * map.h * 2:
		seen = str(ms.seen).hex_decode()
	else:
		seen.resize(map.w * map.h)
	var counts := {}
	for p in map.placements:
		var ent_id := _placement_id(p, counts)
		if ent_id in ms.removed or not _placement_wanted(p):
			continue
		var e := make_ent(p.entity, p.overrides)
		e.id = ent_id
		e.set_cell(Vector2i(p.x, p.y))
		if ent_id in ms.get("used", []):
			e.interact = null
		ents.append(e)
	for sp in ms.spawned:
		if sp.id in ms.removed:
			continue
		var e := make_ent(sp.template, sp.get("overrides", {}))
		e.id = sp.id
		e.x = float(sp.x)
		e.y = float(sp.y)
		ents.append(e)
	var pos: Vector2 = map.any_open()
	if typeof(at) == TYPE_VECTOR2:
		pos = at
	else:
		var mp = map.marker_pos(str(at) if at != null else "start")
		if mp == null:
			mp = map.marker_pos("start")
		if mp != null:
			pos = mp
	sync_party(pos)
	var lead := leader_ent()
	if lead != null:
		if facing != null:
			for pe in party_ents():
				pe.facing = Ent.facing_from(facing)
		_last_cell = lead.cell()
		reveal(lead.cell())
	rebuilt.emit()
	ents_changed.emit()
	game.map_loaded.emit()
	game.io.music(str(map.raw.get("music", "")))
	return true


func _placement_id(p: Dictionary, counts: Dictionary) -> String:
	if p.overrides.has("id"):
		return str(p.overrides.id)
	var n: int = int(counts.get(p.entity, 0)) + 1
	counts[p.entity] = n
	return str(p.entity) if n == 1 else "%s#%d" % [p.entity, n]


## Companion placements only appear while the companion is in the matching state
## ("absent" = not recruited yet, "camp" = waiting at camp). Placements with an "if" are conditional.
func _placement_wanted(p: Dictionary) -> bool:
	var t := template(p.entity)
	t.merge(p.overrides, true)
	if t.has("if") and not game.scripts.test(t["if"]):
		return false
	if t.has("companion"):
		var st: String = game.state.companions.get(t.companion, "absent")
		var when = t.get("when", ["absent"])
		if typeof(when) == TYPE_STRING:
			when = [when]
		return st in when
	return true


## Re-evaluates companion placements after the party changed (recruit / send to camp).
func refresh_companions() -> void:
	if map == null:
		return
	var ms := map_state()
	var counts := {}
	for p in map.placements:
		var ent_id := _placement_id(p, counts)
		var t := template(p.entity)
		if not t.has("companion"):
			continue
		var existing := by_id(ent_id)
		var wanted: bool = _placement_wanted(p) and not (ent_id in ms.removed)
		if wanted and existing == null:
			var e := make_ent(p.entity, p.overrides)
			e.id = ent_id
			e.set_cell(Vector2i(p.x, p.y))
			ents.append(e)
		elif not wanted and existing != null and existing.kind != "party":
			ents.erase(existing)
	ents_changed.emit()


## Looks a template up in: campaign entities -> base props -> companions -> monsters.
func template(template_id: String) -> Dictionary:
	var c: Dictionary = game.campaign
	if c.get("entities", {}).has(template_id):
		return c.entities[template_id].duplicate(true)
	if game.db.props.has(template_id):
		return game.db.props[template_id].duplicate(true)
	if c.get("companions", {}).has(template_id):
		return {"kind": "npc", "companion": template_id}
	if game.db.monsters.has(template_id):
		return {"kind": "monster", "monster": template_id}
	push_warning("Unknown entity template '%s'" % template_id)
	return {"kind": "prop", "name": template_id, "sprite": {"template": "crate", "height": 0.4}}


func make_ent(template_id: String, overrides: Dictionary = {}) -> Ent:
	var t := template(template_id)
	t.merge(overrides, true)
	var e := Ent.new()
	e.template = template_id
	e.id = template_id
	e.data = t
	e.kind = t.get("kind", "prop")
	e.name = t.get("name", Util.title(template_id))
	e.blocking = t.get("blocking", e.kind != "prop")
	e.dialogue = t.get("dialogue", "")
	e.interact = t.get("interact")
	e.light = t.get("light")
	e.hidden = t.get("hidden", false)
	e.group = t.get("group", "")
	e.sprite = t.get("sprite", {})
	e.facing = Ent.facing_from(t.get("facing", "S"))
	if e.kind == "monster":
		var mid: String = t.get("monster", template_id)
		var block: Dictionary = game.db.monsters.get(mid, {})
		if block.is_empty():
			push_warning("Unknown monster '%s'" % mid)
			e.kind = "prop"
			return e
		e.actor = MonsterRules.create_actor(mid, game.db)
		e.name = t.get("name", block.name)
		e.actor["name"] = e.name
		if e.sprite.is_empty():
			e.sprite = block.get("sprite", {})
		e.hostile = t.get("hostile", true)
		e.side = "enemy" if e.hostile else "neutral"
		if e.group == "":
			e.group = "wild"
	elif t.has("companion"):
		var comp: Dictionary = game.campaign.companions.get(t.companion, {})
		e.kind = "npc"
		e.char_id = t.companion
		e.name = comp.get("name", e.name)
		e.sprite = sprite_for_spec(comp)
		if e.dialogue == "":
			e.dialogue = comp.get("dialogue", "")
		e.blocking = true
	return e


## Sprite definition for a character Dictionary (or companion spec): class outfit + personal look
## + the weapon/shield currently equipped.
func sprite_for_spec(c: Dictionary) -> Dictionary:
	var race: Dictionary = game.db.races.get(c.get("race", "human"), {})
	var cls: Dictionary = game.db.classes.get(c.get("cls", "fighter"), {})
	var look: Dictionary = cls.get("look", {}).duplicate(true)
	look.merge(c.get("look", {}), true)
	var eq: Dictionary = c.get("equipped", cls.get("startingKit", {}).get("equipped", {}))
	var main = game.db.items.get(eq.get("mainHand", ""), null) if eq.get("mainHand") != null else null
	if main == null and eq.get("ranged") != null:
		main = game.db.items.get(eq.get("ranged", ""), null)
	look["weapon"] = main.get("sprite", "none") if main != null else "none"
	var off = game.db.items.get(eq.get("offHand", ""), null) if eq.get("offHand") != null else null
	look["shield"] = off != null and off.get("type", "") == "shield" and not (main != null and int(main.get("hands", 1)) == 2)
	# the sprite generator shapes the body from the race (elf ears, dwarf proportions, orc tusks...)
	if not look.has("race"):
		look["race"] = c.get("race", "human")
	return {"template": "humanoid", "height": float(race.get("height", 0.8)), "look": look}


# ----------------------------------------------------------------------------------------------
# Lookups
# ----------------------------------------------------------------------------------------------

func party_ents() -> Array:
	var out: Array = []
	for cid in game.state.get("party", []):
		for e in ents:
			if e.kind == "party" and e.char_id == cid:
				out.append(e)
	return out


func leader_ent() -> Ent:
	var first: Ent = null
	for e in ents:
		if e.kind == "party":
			if e.char_id == game.state.get("leader", ""):
				return e
			if first == null:
				first = e
	return first


## Finds an entity by id. "player" / "leader" = the party leader; a character id = that party member.
func by_id(ent_id: String) -> Ent:
	if ent_id in ["player", "leader"]:
		return leader_ent()
	for e in ents:
		if e.id == ent_id:
			return e
	for e in ents:
		if e.char_id == ent_id and ent_id != "":
			return e
	for e in ents:
		if e.template == ent_id:
			return e
	return null


func ents_in_group(group: String) -> Array:
	var out: Array = []
	for e in ents:
		if e.group == group and e.kind == "monster" and e.alive():
			out.append(e)
	return out


## The blocking entity standing on a tile (ignoring `ignore`), or null.
func ent_at(c: Vector2i, ignore: Ent = null) -> Ent:
	for e in ents:
		if e != ignore and e.blocking and not e.dead and not e.hidden and e.cell() == c:
			return e
	return null


## Walls, blocked tiles and blocking entities. Party members never block each other while exploring.
func is_blocked(c: Vector2i, mover: Ent = null) -> bool:
	if map.blocks_move(c.x, c.y):
		return true
	var e := ent_at(c, mover)
	if e == null:
		return false
	if game.mode != "combat" and e.kind == "party" and mover != null and mover.kind == "party":
		return false
	return true


func free_cell_near(c: Vector2i, mover: Ent = null) -> Vector2i:
	if not is_blocked(c, mover) and ent_at(c, mover) == null:
		return c
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := Vector2i(c.x + dx, c.y + dy)
				if not map.blocks_move(n.x, n.y) and ent_at(n, mover) == null:
					return n
	return c


# ----------------------------------------------------------------------------------------------
# Party entities
# ----------------------------------------------------------------------------------------------

## Makes the party entities match game.state.party (call after any party / equipment change).
func sync_party(pos = null) -> void:
	if map == null:
		return
	var wanted: Array = game.state.get("party", [])
	for e in ents.duplicate():
		if e.kind == "party" and not (e.char_id in wanted):
			ents.erase(e)
	var lead := leader_ent()
	var base: Vector2 = pos if pos != null else (lead.pos() if lead != null else map.any_open())
	for cid in wanted:
		var c: Dictionary = game.state.roster[cid]
		var e: Ent = null
		for x in ents:
			if x.kind == "party" and x.char_id == cid:
				e = x
		if e == null:
			e = Ent.new()
			e.kind = "party"
			e.id = cid
			e.char_id = cid
			e.side = "party"
			e.blocking = true
			var spot := free_cell_near(Vector2i(floori(base.x), floori(base.y)), e)
			e.set_cell(spot)
			ents.append(e)
		e.actor = c
		e.name = c.name
		e.sprite = sprite_for_spec(c)
		e.dead = c.get("dead", false)
		if e.down():
			e.set_anim("dead")
	ents_changed.emit()


# ----------------------------------------------------------------------------------------------
# Spawning / removing
# ----------------------------------------------------------------------------------------------

func spawn(template_id: String, pos: Vector2, overrides: Dictionary = {}, persist := true) -> Ent:
	var e := make_ent(template_id, overrides)
	var base_id: String = overrides.get("id", template_id)
	var n := 1
	e.id = base_id
	while _id_taken(e.id):
		n += 1
		e.id = "%s#%d" % [base_id, n]
	e.x = pos.x
	e.y = pos.y
	ents.append(e)
	if persist:
		map_state().spawned.append({"template": template_id, "x": pos.x, "y": pos.y, "id": e.id, "overrides": overrides})
	else:
		e.temp = true
	if e.light != null:
		rebuilt.emit()
	ents_changed.emit()
	return e


func _id_taken(ent_id: String) -> bool:
	for e in ents:
		if e.id == ent_id:
			return true
	return false


## Removes an entity. permanent = it stays gone when the map is loaded again.
func remove(e: Ent, permanent := true) -> void:
	if e == null:
		return
	ents.erase(e)
	if permanent and e.kind != "party" and not e.temp:
		mark_removed(e)
	if e.light != null:
		rebuilt.emit()
	ents_changed.emit()


func mark_removed(e: Ent) -> void:
	var ms := map_state()
	if not (e.id in ms.removed):
		ms.removed.append(e.id)


func map_state() -> Dictionary:
	var maps: Dictionary = game.state.maps
	if not maps.has(map.id):
		maps[map.id] = {"removed": [], "opened": [], "tiles": [], "fired": [], "spawned": [], "seen": ""}
	return maps[map.id]


## Copies live state (leader position, fog of war) into game.state before saving or leaving the map.
func store_state() -> void:
	if map == null:
		return
	map_state()["seen"] = seen.hex_encode()
	var lead := leader_ent()
	if lead != null:
		game.state["pos"] = {"x": lead.x, "y": lead.y}


func set_tile(c: Vector2i, ch: String) -> void:
	map.set_char(c.x, c.y, ch)
	map_state().tiles.append([c.x, c.y, ch])
	rebuilt.emit()


# ----------------------------------------------------------------------------------------------
# Per-frame update (exploration)
# ----------------------------------------------------------------------------------------------

func update(delta: float) -> void:
	if map == null:
		return
	_door_cooldown = maxf(0.0, _door_cooldown - delta)
	for e in ents:
		e.anim_t += delta
		if e.flash > 0.0:
			e.flash = maxf(0.0, e.flash - delta)
	if game.mode != "explore" or game.busy > 0 or game.over:
		return
	var lead := leader_ent()
	if lead == null:
		return
	if lead.down():
		_pick_standing_leader()
		return
	_update_leader(lead, delta)
	_update_followers(lead, delta)
	_cell_events(lead)


func _pick_standing_leader() -> void:
	for e in party_ents():
		if e.can_act():
			game.state["leader"] = e.char_id
			game.state_changed.emit()
			return
	game.party_wiped()


func _update_leader(lead: Ent, delta: float) -> void:
	if move_input.length() > 0.1:
		lead.path = []
		pending = null
		pending_door = null
		var dir := move_input.normalized()
		var step := dir * WALK_SPEED * delta
		var moved := false
		if _can_stand(lead.x + step.x, lead.y, lead):
			lead.x += step.x
			moved = true
		if _can_stand(lead.x, lead.y + step.y, lead):
			lead.y += step.y
			moved = true
		lead.facing = atan2(dir.y, dir.x)
		lead.set_anim("walk" if moved else "idle")
		if not moved and _door_cooldown <= 0.0:
			var ahead := Vector2i(floori(lead.x + dir.x * 0.7), floori(lead.y + dir.y * 0.7))
			if map.door(ahead.x, ahead.y) != null:
				_door_cooldown = 1.0
				try_door(ahead)
		return
	if not lead.path.is_empty():
		if _follow_path(lead, delta, WALK_SPEED):
			lead.set_anim("idle")
			_arrived(lead)
		return
	lead.set_anim("idle")


func _arrived(lead: Ent) -> void:
	if pending != null:
		var target := pending
		pending = null
		if lead.dist_to(target) <= INTERACT_RANGE:
			interact(target)
	elif pending_door != null:
		var c: Vector2i = pending_door
		pending_door = null
		if Grid.cheb(lead.cell(), c) <= 1:
			try_door(c)


func _follow_path(e: Ent, delta: float, speed: float) -> bool:
	if e.path.is_empty():
		return true
	var c: Vector2i = e.path[0]
	var target := Vector2(c.x + 0.5, c.y + 0.5)
	var to := target - e.pos()
	var step := speed * delta
	if to.length() <= step:
		e.x = target.x
		e.y = target.y
		e.path.pop_front()
	else:
		var n := to.normalized()
		e.x += n.x * step
		e.y += n.y * step
		e.facing = atan2(n.y, n.x)
	e.set_anim("walk")
	return e.path.is_empty()


func _update_followers(lead: Ent, delta: float) -> void:
	_follow_t -= delta
	var repath := _follow_t <= 0.0
	if repath:
		_follow_t = 0.35
	var i := 0
	for e in party_ents():
		if e == lead:
			continue
		i += 1
		if e.down():
			e.set_anim("dead")
			continue
		var want := 0.9 + 0.8 * i
		var d: float = e.dist_to(lead)
		if d > 14.0:
			e.set_cell(free_cell_near(lead.cell(), e))
			e.path = []
			continue
		if d <= want:
			e.path = []
			e.set_anim("idle")
			continue
		if repath or e.path.is_empty():
			e.path = Grid.find_path(e.cell(), lead.cell(), func(c): return is_blocked(c, e), true, 500)
		if e.path.is_empty():
			e.set_anim("idle")
			continue
		_follow_path(e, delta, WALK_SPEED * (1.3 if d > want + 2.0 else 1.0))


func _can_stand(px: float, py: float, mover: Ent) -> bool:
	for off in [Vector2(-RADIUS, -RADIUS), Vector2(RADIUS, -RADIUS), Vector2(-RADIUS, RADIUS), Vector2(RADIUS, RADIUS)]:
		if map.blocks_move(floori(px + off.x), floori(py + off.y)):
			return false
	var p := Vector2(px, py)
	for e in ents:
		if e == mover or not e.blocking or e.dead or e.hidden or e.kind == "party":
			continue
		if p.distance_to(e.pos()) < 0.6:
			return false
	return true


func _cell_events(lead: Ent) -> void:
	var c := lead.cell()
	if c == _last_cell:
		return
	_last_cell = c
	reveal(c)
	var ex = map.exit_at(c.x, c.y)
	if ex != null:
		lead.path = []
		game.travel(ex.map, ex.get("marker", "start"))
		return
	var trig := map.trigger_at(c.x, c.y)
	if trig != "":
		fire_trigger(trig)
		if game.busy > 0:
			return
	check_aggro()


func fire_trigger(trigger_id: String) -> void:
	var def = map.raw.get("triggers", {}).get(trigger_id)
	if def == null:
		push_warning("Map %s has no trigger '%s'" % [map.id, trigger_id])
		return
	var ms := map_state()
	if def.get("once", true) and trigger_id in ms.fired:
		return
	if def.has("if") and not game.scripts.test(def["if"]):
		return
	if not (trigger_id in ms.fired):
		ms.fired.append(trigger_id)
	var lead := leader_ent()
	if lead != null:
		lead.path = []
		lead.set_anim("idle")
	game.run_actions(def.get("do", []), {"who": "best", "trigger": trigger_id})


## Starts a fight when a hostile monster can see a party member nearby.
func check_aggro() -> void:
	if game.encounter != null or game.busy > 0:
		return
	for e in ents:
		if e.kind != "monster" or not e.hostile or not e.can_act():
			continue
		var reach: float = float(e.data.get("aggro", AGGRO_RANGE))
		for p in party_ents():
			if p.dist_to(e) <= reach and Grid.line_of_sight(map, e.cell(), p.cell()):
				game.start_combat(e.group)
				return


func reveal(c: Vector2i, radius := 7) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var n := Vector2i(c.x + dx, c.y + dy)
			if not map.in_bounds(n.x, n.y) or dx * dx + dy * dy > radius * radius:
				continue
			if seen[n.y * map.w + n.x] == 0 and Grid.line_of_sight(map, c, n):
				seen[n.y * map.w + n.x] = 1


# ----------------------------------------------------------------------------------------------
# Player intent (called by the UI)
# ----------------------------------------------------------------------------------------------

## The player clicked a floor tile (or a door) while exploring.
func click_cell(c: Vector2i) -> void:
	if game.mode != "explore" or game.busy > 0:
		return
	var lead := leader_ent()
	if lead == null:
		return
	pending = null
	pending_door = null
	if map.door(c.x, c.y) != null:
		if Grid.cheb(lead.cell(), c) <= 1:
			try_door(c)
		else:
			pending_door = c
			lead.path = Grid.find_path(lead.cell(), c, func(n): return is_blocked(n, lead), true)
		return
	if is_blocked(c, lead):
		return
	lead.path = Grid.find_path(lead.cell(), c, func(n): return is_blocked(n, lead))


## The player clicked an entity while exploring: walk up to it, then use it.
func click_ent(e: Ent) -> void:
	if game.mode != "explore" or game.busy > 0 or e == null:
		return
	var lead := leader_ent()
	if lead == null or e == lead:
		return
	if lead.dist_to(e) <= INTERACT_RANGE:
		lead.path = []
		interact(e)
		return
	pending = e
	pending_door = null
	lead.path = Grid.find_path(lead.cell(), e.cell(), func(n): return is_blocked(n, lead), true)
	if lead.path.is_empty():
		pending = null


func can_interact(e: Ent) -> bool:
	if e == null or e.hidden:
		return false
	if e.kind == "party":
		return e.char_id != game.state.get("leader", "")
	if e.kind == "monster":
		return e.can_act() and (e.dialogue != "" or e.interact != null)
	return e.dialogue != "" or e.interact != null or e.char_id != ""


func interact(e: Ent) -> void:
	var lead := leader_ent()
	if lead == null or not can_interact(e):
		return
	lead.face_point(e.pos())
	if e.kind != "prop":
		e.face_point(lead.pos())
	if e.kind == "party" or (e.char_id != "" and e.dialogue == ""):
		game.run_dialogue_data(Dialogue.companion_default(game, e.char_id), "companion." + e.char_id, {"ent": e})
	elif e.dialogue != "":
		game.run_dialogue(e.dialogue, {"ent": e})
	elif e.interact != null:
		if e.data.get("once", false):
			var keep: bool = e.data.get("keep", false)
			var actions: Array = e.interact
			e.interact = null
			if keep:
				mark_used(e)
			else:
				remove(e)
			game.run_actions(actions, {"ent": e, "who": "leader"})
		else:
			game.run_actions(e.interact, {"ent": e, "who": "leader"})


## A once-only prop that stays visible after use (e.g. an opened chest) is remembered as used.
func mark_used(e: Ent) -> void:
	var ms := map_state()
	if not ms.has("used"):
		ms["used"] = []
	if not (e.id in ms.used):
		ms.used.append(e.id)


# ----------------------------------------------------------------------------------------------
# Doors
# ----------------------------------------------------------------------------------------------

func open_door(c: Vector2i) -> void:
	if map.door(c.x, c.y) == null:
		return
	map.open_door(c.x, c.y)
	map_state().opened.append([c.x, c.y])
	game.io.sfx("door")
	rebuilt.emit()
	var lead := leader_ent()
	if lead != null:
		reveal(lead.cell())


## Opens a door, or - when it is locked - lets the player choose how to deal with the lock.
func try_door(c: Vector2i) -> void:
	var d = map.door(c.x, c.y)
	if d == null:
		return
	var lock = d.get("locked")
	if lock == null:
		open_door(c)
		return
	game.busy += 1
	game.journal("narration", lock.get("text", "The door is locked."))
	var opts: Array = []
	if lock.has("key") and game.count_item(lock.key) > 0:
		opts.append({"text": "Unlock it with the %s." % game.db.items.get(lock.key, {}).get("name", lock.key), "act": "key"})
	if lock.has("dc"):
		opts.append({"text": "Pick the lock.", "tag": "Disable Device DC %d" % int(lock.dc), "act": "pick"})
	if lock.has("break"):
		opts.append({"text": "Force it open.", "tag": "Strength DC %d" % int(lock["break"]), "act": "break"})
	opts.append({"text": "Leave it.", "act": "leave"})
	var choice: int = await game.io.choose(opts)
	var ok := false
	match opts[choice].act:
		"key":
			ok = true
			game.journal("system", "You unlock the door.")
		"pick":
			ok = await GM.check(game, {"skill": "disable_device", "dc": lock.dc, "who": "best"})
			game.journal("narration", "The lock clicks open." if ok else "The lock refuses to give.")
		"break":
			ok = await GM.check(game, {"ability": "str", "dc": lock["break"], "who": "best"})
			game.journal("narration", "The door bursts open!" if ok else "The door holds firm.")
	if ok:
		open_door(c)
	game.busy -= 1


# ----------------------------------------------------------------------------------------------
# Scripted movement / animation (combat steps, cutscenes)
# ----------------------------------------------------------------------------------------------

## Moves an entity in a straight line to `to` at `speed` tiles per second. Await it.
func walk(e: Ent, to: Vector2, speed := 4.0) -> void:
	var d := e.pos().distance_to(to)
	if d < 0.01:
		return
	e.face_point(to)
	e.set_anim("walk")
	await game.anims.run(e, {"x": to.x, "y": to.y}, d / maxf(speed, 0.1), "linear")
	e.x = to.x
	e.y = to.y


## Plays a one-shot animation (attack, cast, hurt) for `seconds`, then returns to idle.
func play_anim(e: Ent, anim: String, seconds := 0.4) -> void:
	e.set_anim(anim)
	await game.delay(seconds)
	if e.anim == anim:
		e.set_anim("dead" if (e.dead or e.down()) else "idle")
