class_name Game
extends RefCounted
## The one object that owns a play session: rules data, the loaded campaign, the saved state,
## the world (current map) and all the engine services. Everything else receives `game`.
##
## Nothing in src/engine or src/rules touches the screen. The engine talks to the player ONLY
## through game.io (see game_io.gd), so the whole game also runs headless for tests.
##
## game.state is the save file. It must stay JSON-friendly: Dictionaries with STRING keys, Arrays,
## numbers, strings, bools. Never store objects (Ent, Vector2, ...) in it.
##   campaignId, flags {}, quests {}, roster {id: character}, party [ids], leader, playerId,
##   companions {id: absent|party|camp|player}, approval {}, gold, inventory [{id, qty}],
##   mapId, pos {x, y}, maps {mapId: per-map state}, journal [entries], day, campReturn,
##   bestiary {monsterId: {met, slain}} (creatures fought so far - the journal's Creatures tab)

signal journal_added(entry)   # a line was added to the journal
signal state_changed          # party, inventory, quests, hp... changed: panels should redraw
signal map_loaded             # a new map is active
signal mode_changed           # explore/combat/dialogue/cutscene status changed
signal combat_changed         # turn order, active combatant or action economy changed

const SAVE_VERSION := 1
const JOURNAL_LIMIT := 500

var base_db: Dictionary = {}
var db: Dictionary = {}
var campaign: Dictionary = {}
var state: Dictionary = {}
var world: World
var io: GameIO
var rng: Rng
var cam: CamRig
var anims: Anims
var scripts: ScriptRunner
var encounter = null            # the running Encounter, or null
var mode := "menu"              # "menu" | "explore" | "combat"
var busy := 0                   # > 0 while a script, dialogue, cutscene or fight owns the game
var in_dialogue := false
var in_cutscene := false
var skip_cutscene := false
var instant := false            # true = no waiting or animation (tests, tools)
var over := false               # the campaign has ended (victory or defeat)
var tree: SceneTree = null
var player_controller = null    # object with decide(ent, encounter); null = AI plays the party
var settings := {"show_dc": true, "autosave": true, "dice_speed": 1.0}


func _init(io_impl: GameIO = null, seed_value: int = -1) -> void:
	rng = Rng.new(seed_value)
	io = io_impl if io_impl != null else GameIO.new()
	io.game = self
	base_db = RulesDB.load_base()
	db = base_db
	state = _blank_state("")
	anims = Anims.new(self)
	cam = CamRig.new(self)
	world = World.new(self)
	scripts = ScriptRunner.new(self)
	scripts.ops["party.lead"] = func(a, _ctx): Party.set_leader(self, a.id)


# ----------------------------------------------------------------------------------------------
# Starting, saving, loading
# ----------------------------------------------------------------------------------------------

func load_campaign(campaign_id: String) -> bool:
	var c := Campaign.load_campaign(campaign_id)
	for e in c.get("errors", []):
		push_error("Campaign %s: %s" % [campaign_id, e])
	if not c.has("start"):
		return false
	campaign = c
	db = RulesDB.with_campaign(base_db, c.dir)
	return true


func _blank_state(campaign_id: String) -> Dictionary:
	return {
		"campaignId": campaign_id, "flags": {}, "quests": {}, "roster": {}, "party": [], "leader": "", "playerId": "",
		"companions": {}, "approval": {}, "gold": 0, "inventory": [], "mapId": "", "pos": {}, "maps": {},
		"journal": [], "day": 1, "campReturn": null, "bestiary": {},
	}


## Starts a new game in the loaded campaign. spec = character builder output or a companion spec
## (with "id" set to the companion id when the player picked a pre-made hero).
func new_game(spec: Dictionary) -> void:
	state = _blank_state(campaign.id)
	over = false
	encounter = null
	busy = 0
	in_dialogue = false
	in_cutscene = false
	var pid: String = spec.get("id", "player")
	var pc := CharRules.create(spec, db)
	pc["id"] = pid
	state.playerId = pid
	state.leader = pid
	state.roster[pid] = pc
	state.party = [pid]
	for cid in campaign.get("companions", {}):
		state.companions[cid] = "player" if cid == pid else "absent"
	var kit: Dictionary = db.classes[pc.cls].get("startingKit", {})
	for it in spec.get("inventory", kit.get("inventory", [])):
		add_item(it.id, int(it.get("qty", 1)))
	var start: Dictionary = campaign.start
	state.gold = int(spec.get("gold", kit.get("gold", 0))) + int(start.get("gold", 0))
	mode = "explore"
	world.load_map(start.map, start.get("marker", "start"), start.get("facing"))
	cam.mode = "auto"
	cam.snap()
	mode_changed.emit()
	state_changed.emit()
	if start.has("do"):
		await run_actions(start["do"], {})
	else:
		io.banner(world.map.name)


func save_data() -> Dictionary:
	world.store_state()
	var lead := leader()
	return {
		"version": SAVE_VERSION, "campaignId": state.campaignId, "savedAt": int(Time.get_unix_time_from_system()),
		"summary": "%s, level %d %s - %s (day %d)" % [lead.name, lead.level, db.classes[lead.cls].name, world.map.name, state.day],
		"state": state.duplicate(true),
	}


func load_data(data: Dictionary) -> bool:
	if not load_campaign(str(data.get("campaignId", ""))):
		return false
	var blank := _blank_state(campaign.id)
	state = data.state
	for k in blank:
		if not state.has(k):
			state[k] = blank[k]
	over = false
	encounter = null
	busy = 0
	in_dialogue = false
	in_cutscene = false
	mode = "explore"
	var pos: Dictionary = state.get("pos", {})
	world.load_map(state.mapId, Vector2(float(pos.x), float(pos.y)) if pos.has("x") else null)
	cam.mode = "auto"
	cam.snap()
	mode_changed.emit()
	state_changed.emit()
	return true


func autosave() -> void:
	if instant or over or not settings.get("autosave", true) or world.map == null:
		return
	SaveGame.write(self, "autosave")


# ----------------------------------------------------------------------------------------------
# Per-frame update (called by src/main.gd)
# ----------------------------------------------------------------------------------------------

func update(delta: float) -> void:
	anims.update(delta)
	if mode == "menu":
		return
	world.update(delta)
	cam.update(delta)


# ----------------------------------------------------------------------------------------------
# Characters
# ----------------------------------------------------------------------------------------------

func leader() -> Dictionary:
	return state.roster.get(state.get("leader", ""), state.roster.get(state.get("playerId", ""), {}))


func party() -> Array:
	var out: Array = []
	for cid in state.get("party", []):
		out.append(state.roster[cid])
	return out


func max_party() -> int:
	return int(campaign.get("maxPartySize", 4))


## Derived stats of a character or monster actor (see CharRules.derive for the shape).
func stats(actor: Dictionary) -> Dictionary:
	return Stats.of(actor, db)


func ent_of(character: Dictionary) -> Ent:
	if world.map == null:
		return null
	for e in world.ents:
		if e.actor != null and is_same(e.actor, character):
			return e
	return null


# ----------------------------------------------------------------------------------------------
# Journal and story text
# ----------------------------------------------------------------------------------------------

## Adds a journal entry. kind: narration | speech | choice | system | quest | roll | combat | foes
func journal(kind: String, text: String, extra: Dictionary = {}) -> Dictionary:
	var e := {"kind": kind, "text": text}
	e.merge(extra)
	state.journal.append(e)
	if state.journal.size() > JOURNAL_LIMIT:
		state.journal = state.journal.slice(state.journal.size() - JOURNAL_LIMIT)
	journal_added.emit(e)
	return e


## Replaces {player}, {leader}, {race}, {class}, {gold} in story text.
func fmt(text) -> String:
	var s := str(text)
	if not s.contains("{"):
		return s
	var pc: Dictionary = state.roster.get(state.playerId, {})
	s = s.replace("{player}", str(pc.get("name", "")))
	s = s.replace("{leader}", str(leader().get("name", "")))
	s = s.replace("{race}", str(db.races.get(pc.get("race", ""), {}).get("name", "")).to_lower())
	s = s.replace("{class}", str(db.classes.get(pc.get("cls", ""), {}).get("name", "")).to_lower())
	s = s.replace("{gold}", str(state.gold))
	return s


## Display name for a speaker id: an entity on the map, a companion, an entity template, or itself.
func speaker_name(speaker: String) -> String:
	if speaker == "":
		return ""
	if speaker in ["player", "leader"]:
		return str(leader().get("name", "You"))
	if state.roster.has(speaker):
		return state.roster[speaker].name
	if campaign.get("companions", {}).has(speaker):
		return campaign.companions[speaker].get("name", speaker)
	if campaign.get("entities", {}).has(speaker):
		return campaign.entities[speaker].get("name", Util.title(speaker))
	if world.map != null:
		var e := world.by_id(speaker)
		if e != null:
			return e.name
	return speaker


## Records that the party has met a creature (and optionally killed one). state.bestiary is what the
## journal's Creatures tab lists: {monsterId: {"met": times fought, "slain": count}}.
func note_creature(monster_id: String, slain := 0) -> void:
	if monster_id == "" or not db.monsters.has(monster_id):
		return
	if not state.has("bestiary"):
		state["bestiary"] = {}
	var rec: Dictionary = state.bestiary.get(monster_id, {"met": 0, "slain": 0})
	if slain > 0:
		rec.slain = int(rec.slain) + slain
	else:
		rec.met = int(rec.met) + 1
	state.bestiary[monster_id] = rec


## Journal line naming the creatures the party is up against ("You face: 2 Skeletons, Cultist") and
## their entry in the bestiary. The journal pane turns each name into a hover tooltip.
func note_foes(foes: Array) -> void:
	var ids: Array = []
	var counts := {}
	for e in foes:
		var mid := str(e.actor.get("monsterId", "")) if e.actor != null else ""
		if mid == "" or not db.monsters.has(mid):
			continue
		if not counts.has(mid):
			ids.append(mid)
			counts[mid] = 0
			note_creature(mid)
		counts[mid] += 1
	if ids.is_empty():
		return
	var names: Array = []
	var list: Array = []
	for mid in ids:
		var label := str(db.monsters[mid].name)
		names.append(label if counts[mid] == 1 else "%d x %s" % [counts[mid], label])
		list.append({"id": mid, "count": counts[mid]})
	journal("foes", "You face: %s." % ", ".join(names), {"creatures": list})


## GM narration (journal + voice if a clip exists).
func narrate(text, voice := "") -> void:
	var entry := journal("narration", fmt(text), {"voice": voice})
	await io.say(entry)


## A character speaks (journal + talk animation + voice).
func speak(speaker: String, text, voice := "") -> void:
	var e: Ent = world.by_id(speaker) if world.map != null else null
	var entry := journal("speech", fmt(text), {"speaker": speaker_name(speaker), "speakerId": speaker, "voice": voice})
	if e != null and e.can_act():
		e.set_anim("talk")
		if in_dialogue and e != world.leader_ent():
			cam.frame_other = e
	await io.say(entry)
	if e != null and e.anim == "talk":
		e.set_anim("idle")


## Shows a roll in the dice tray and records it in the journal's log.
func show_roll(result: Dictionary, quick := false) -> void:
	journal("roll", roll_text(result), {"roll": result})
	await io.show_roll(result, quick)


static func roll_text(r: Dictionary) -> String:
	var s := "%s - %s: " % [r.get("actor", ""), r.get("label", "Roll")]
	var dice: Array = r.get("dice", [])
	if dice.is_empty():
		s += str(r.get("note", "no roll"))
	else:
		var faces: Array = []
		for d in dice:
			faces.append(str(d.value))
		s += "[%s]" % ", ".join(faces)
		if int(r.get("modifier", 0)) != 0:
			s += " %s" % Util.signed(r.modifier)
		s += " = %d" % int(r.total)
	if r.has("dc"):
		s += " vs %s %d" % ["AC" if r.kind == "attack" else "DC", int(r.dc)]
	if r.has("success"):
		s += " - %s" % ("success" if r.success else "failure")
	return s


func delay(seconds: float) -> void:
	if instant or seconds <= 0.0 or (in_cutscene and skip_cutscene):
		return
	await io.delay(seconds)


# ----------------------------------------------------------------------------------------------
# Scripts, dialogue, travel, combat
# ----------------------------------------------------------------------------------------------

## Runs script actions as a blocking story beat (exploration input is paused meanwhile).
func run_actions(actions, ctx: Dictionary = {}) -> void:
	busy += 1
	await scripts.run(actions, ctx)
	busy -= 1
	state_changed.emit()
	check_party_alive()


func run_dialogue(dialogue_id: String, ctx: Dictionary = {}) -> void:
	var data = campaign.get("dialogues", {}).get(dialogue_id)
	if data == null:
		push_warning("Unknown dialogue '%s'" % dialogue_id)
		return
	await run_dialogue_data(data, dialogue_id, ctx)


func run_dialogue_data(data: Dictionary, dialogue_id: String, ctx: Dictionary = {}) -> void:
	busy += 1
	in_dialogue = true
	var lead := world.leader_ent()
	if lead != null:
		lead.path = []
		if lead.can_act():
			lead.set_anim("idle")
	var other = ctx.get("ent")
	if other != null and other != lead and other.kind != "prop":
		cam.frame_other = other
	ctx["deferred"] = []
	if not ctx.has("who"):
		ctx["who"] = "leader"
	mode_changed.emit()
	await Dialogue.run(self, data, dialogue_id, ctx)
	in_dialogue = false
	cam.frame_other = null
	mode_changed.emit()
	var deferred: Array = ctx.deferred
	ctx.erase("deferred")
	await scripts.run(deferred, ctx)
	busy -= 1
	state_changed.emit()


## Positions used by scripts and cutscenes: [x, y] tile coordinates (centre of that tile),
## a marker name on the current map, or an entity id. Returns Vector2 or null.
func resolve_pos(v):
	if v == null:
		return null
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_ARRAY:
		if v.size() < 2 or v[0] == null or v[1] == null:
			return null
		return Vector2(float(v[0]) + 0.5, float(v[1]) + 0.5)
	if world.map == null:
		return null
	var m = world.map.marker_pos(str(v))
	if m != null:
		return m
	var e := world.by_id(str(v))
	return e.pos() if e != null else null


## Fades out, switches map, fades in and runs the map's onEnter script. marker may be a Vector2.
func travel(map_id: String, marker = "start") -> void:
	if not campaign.get("maps", {}).has(map_id):
		push_warning("travel: unknown map '%s'" % map_id)
		return
	busy += 1
	await io.fade(true, 0.35)
	world.store_state()
	world.load_map(map_id, marker)
	cam.snap()
	io.banner(world.map.name, str(world.map.raw.get("subtitle", "")))
	await io.fade(false, 0.35)
	var on_enter = world.map.raw.get("onEnter")
	if on_enter != null:
		await scripts.run(on_enter, {"who": "best"})
	busy -= 1
	state_changed.emit()
	autosave()
	world.check_aggro()


func can_camp() -> bool:
	return campaign.has("camp") and world.map != null and world.map.id != campaign.camp.map and world.map.raw.get("allowCamp", true) and encounter == null


func go_to_camp() -> void:
	if not campaign.has("camp") or world.map.id == campaign.camp.map:
		return
	if not can_camp():
		journal("system", "You cannot make camp here.")
		return
	var lead := world.leader_ent()
	state.campReturn = {"map": world.map.id, "x": lead.x, "y": lead.y}
	await travel(campaign.camp.map, campaign.camp.get("marker", "start"))


func leave_camp() -> void:
	var r = state.get("campReturn")
	state.campReturn = null
	if r == null:
		await travel(campaign.start.map, campaign.start.get("marker", "start"))
	else:
		await travel(r.map, Vector2(float(r.x), float(r.y)))


## Starts a fight against every living monster of `group` on this map. Returns "victory"/"defeat".
func start_combat(group: String, surprise := "") -> String:
	if encounter != null or over or world.map == null:
		return ""
	var foes: Array = world.ents_in_group(group)
	if foes.is_empty():
		return ""
	for e in foes:
		e.hostile = true
		e.side = "enemy"
	busy += 1
	var enc := Encounter.new(self, group, foes, surprise)
	var res: String = await enc.run()
	busy -= 1
	state_changed.emit()
	return res


func end_campaign(victory: bool, text: String) -> void:
	if over:
		return
	over = true
	journal("system", fmt(text) if text != "" else ("The adventure is complete." if victory else "Your party has fallen."))
	mode_changed.emit()
	await io.game_over(victory, fmt(text))


func check_party_alive() -> void:
	if over or encounter != null or state.party.is_empty():
		return
	for c in party():
		if int(c.hp) > 0:
			return
	party_wiped()


func party_wiped() -> void:
	if not over:
		end_campaign(false, "Your party has fallen.")


# ----------------------------------------------------------------------------------------------
# Flags, inventory, gold, experience
# ----------------------------------------------------------------------------------------------

func set_flag(flag: String, value = true) -> void:
	state.flags[flag] = value
	state_changed.emit()


func flag(flag_name: String):
	return state.flags.get(flag_name)


func count_item(item_id: String) -> int:
	for it in state.inventory:
		if it.id == item_id:
			return int(it.qty)
	return 0


func add_item(item_id: String, qty := 1, announce := false) -> void:
	if not db.items.has(item_id):
		push_warning("Unknown item '%s'" % item_id)
		return
	var found := false
	for it in state.inventory:
		if it.id == item_id:
			it.qty = int(it.qty) + qty
			found = true
	if not found:
		state.inventory.append({"id": item_id, "qty": qty})
	if announce:
		journal("system", "Received: %s%s" % [db.items[item_id].name, " x%d" % qty if qty > 1 else ""])
		io.sfx("item")
	state_changed.emit()


func remove_item(item_id: String, qty := 1, announce := false) -> bool:
	for it in state.inventory:
		if it.id == item_id and int(it.qty) >= qty:
			it.qty = int(it.qty) - qty
			if int(it.qty) <= 0:
				state.inventory.erase(it)
			if announce:
				journal("system", "Lost: %s" % db.items.get(item_id, {}).get("name", item_id))
			state_changed.emit()
			return true
	return false


func add_gold(amount: int) -> void:
	state.gold = maxi(0, int(state.gold) + amount)
	if amount != 0:
		journal("system", "%s %d gold." % ["Gained" if amount > 0 else "Spent", absi(amount)])
		io.sfx("coin")
	state_changed.emit()


## Gives XP to every character in the roster (so companions waiting at camp keep up).
func give_xp(amount: int) -> void:
	if amount <= 0:
		return
	journal("system", "Each character gains %d experience." % amount)
	for cid in state.roster:
		var c: Dictionary = state.roster[cid]
		c.xp = int(c.xp) + amount
	state_changed.emit()
	for cid in state.roster:
		var c: Dictionary = state.roster[cid]
		if Progression.can_level_up(c):
			await io.level_up(c)


## Levels a character up with sensible automatic choices (used headless and for the "auto" button).
func auto_level(c: Dictionary) -> void:
	var guard := 0
	while Progression.can_level_up(c) and guard < 20:
		guard += 1
		var req := Progression.requirements(c, db)
		var choices := {"skillRanks": {}, "feats": [], "spells": []}
		var trained: Array = c.skillRanks.keys()
		if trained.is_empty():
			trained = ["perception"]
		var points: int = req.skillPoints
		var i := 0
		while points > 0 and i < 200:
			var sid: String = trained[i % trained.size()]
			if int(c.skillRanks.get(sid, 0)) + int(choices.skillRanks.get(sid, 0)) < int(req.newLevel):
				choices.skillRanks[sid] = int(choices.skillRanks.get(sid, 0)) + 1
				points -= 1
			i += 1
		for fid in ["toughness", "improved_initiative", "iron_will", "great_fortitude", "lightning_reflexes", "alertness", "dodge"]:
			if choices.feats.size() >= int(req.feats):
				break
			if not CharRules.has_feat(c, fid):
				choices.feats.append(fid)
		var cls: Dictionary = db.classes[c.cls]
		choices["ability"] = cls.casting.ability if cls.has("casting") else "str"
		if int(req.spells) > 0:
			for sid in db.spells:
				if choices.spells.size() >= int(req.spells):
					break
				var lv = db.spells[sid].get("levels", {}).get(c.cls)
				if lv != null and int(lv) > 0 and int(lv) <= ceili(int(req.newLevel) / 2.0) and not (sid in c.spells):
					choices.spells.append(sid)
		var res := Progression.level_up(c, db, choices, rng)
		journal("system", "%s reaches level %d! (+%d hp)" % [c.name, res.level, res.hpGained])
	io.sfx("levelup")
	state_changed.emit()


# ----------------------------------------------------------------------------------------------
# Damage, healing, resting
# ----------------------------------------------------------------------------------------------

## Applies damage to an entity with all the trimmings (floating text, animation, falling, dying).
func damage_ent(ent: Ent, amount: int, kind := "damage") -> void:
	if ent == null or ent.actor == null or ent.dead:
		return
	var st := stats(ent.actor)
	var was_down := ent.down()
	var life := CombatRules.apply_damage(ent.actor, st, amount)
	if life == "dead" and st.kind == "pc" and encounter == null:
		# Outside combat a hazard can knock a hero out but never kills outright.
		ent.actor.hp = -int(st.abilities.con.score) + 1
		life = "down"
	io.float_text(ent, "-%d" % amount, kind)
	io.sfx("crit" if kind == "crit" else "hit")
	ent.flash = 0.25
	if Effects.has_flag(ent.actor, db, "wakeOnDamage"):
		Effects.remove_condition(ent.actor, "asleep")
		journal("combat", "%s wakes up." % ent.name)
	match life:
		"ok":
			state_changed.emit()
			await world.play_anim(ent, "hurt", 0.25)
		"down":
			ent.set_anim("dead")
			ent.blocking = false
			if not was_down:
				journal("combat", "%s falls unconscious!" % ent.name)
				io.sfx("down")
		"dead":
			ent.dead = true
			ent.blocking = false
			ent.set_anim("dead")
			if st.kind == "pc":
				ent.actor["dead"] = true
			journal("combat", "%s %s" % [ent.name, "dies!" if st.kind == "pc" else "is slain."])
			if st.kind == "monster":
				note_creature(str(ent.actor.get("monsterId", "")), 1)
			io.sfx("down")
	state_changed.emit()
	combat_changed.emit()


func heal_ent(ent: Ent, amount: int) -> int:
	if ent == null or ent.actor == null or ent.dead:
		return 0
	var was_down := ent.down()
	var healed := CombatRules.heal(ent.actor, stats(ent.actor), amount)
	if healed > 0:
		io.float_text(ent, "+%d" % healed, "heal")
		io.sfx("heal")
		journal("combat", "%s recovers %d hit points." % [ent.name, healed])
	if was_down and not ent.down():
		ent.blocking = true
		ent.set_anim("idle")
		journal("combat", "%s is back on their feet." % ent.name)
	state_changed.emit()
	combat_changed.emit()
	return healed


func damage_character(c: Dictionary, amount: int, label := "") -> void:
	var ent := ent_of(c)
	journal("combat", "%s takes %d damage%s." % [c.name, amount, (" from the " + label.to_lower()) if label != "" else ""])
	if ent != null:
		damage_ent(ent, amount)
	else:
		c.hp = maxi(-int(stats(c).abilities.con.score) + 1, int(c.hp) - amount)
		state_changed.emit()


func heal_character(c: Dictionary, amount: int) -> void:
	var ent := ent_of(c)
	if ent != null:
		heal_ent(ent, amount)
	else:
		CombatRules.heal(c, stats(c), amount)
		state_changed.emit()


## A long rest: full hit points, spells and daily powers back, long effects end, a day passes.
func rest() -> void:
	busy += 1
	await io.fade(true, 0.6)
	for cid in state.roster:
		var c: Dictionary = state.roster[cid]
		Effects.clear(c, "rest")
		c.erase("dead")
		c.hp = stats(c).hpMax
		c.used = {"slots": {}, "pools": {}}
	state.day = int(state.day) + 1
	for e in world.party_ents():
		e.dead = false
		e.blocking = true
		e.set_anim("idle")
	journal("system", "The party rests until morning. Day %d." % state.day)
	io.sfx("rest")
	await io.fade(false, 0.6)
	busy -= 1
	state_changed.emit()
	autosave()


# ----------------------------------------------------------------------------------------------
# Equipment, items and spells outside combat
# ----------------------------------------------------------------------------------------------

func slot_for(item: Dictionary) -> String:
	match item.get("type", ""):
		"weapon":
			return "ranged" if item.get("ranged", false) else "mainHand"
		"armor":
			return "armor"
		"shield":
			return "offHand"
	return str(item.get("slot", ""))


func equip(c: Dictionary, item_id: String) -> bool:
	var item: Dictionary = db.items.get(item_id, {})
	var slot := slot_for(item)
	if slot == "" or count_item(item_id) <= 0:
		return false
	if encounter != null:
		journal("system", "You cannot change equipment in the middle of a fight.")
		return false
	unequip(c, slot)
	remove_item(item_id, 1)
	c.equipped[slot] = item_id
	_gear_changed(c)
	return true


func unequip(c: Dictionary, slot: String) -> void:
	var cur = c.equipped.get(slot)
	if cur == null or encounter != null:
		return
	c.equipped[slot] = null
	add_item(str(cur), 1)
	_gear_changed(c)


func _gear_changed(c: Dictionary) -> void:
	c.hp = mini(int(c.hp), int(stats(c).hpMax))
	world.sync_party()
	state_changed.emit()


## Uses a consumable from the shared inventory on a target entity (potions).
func use_item_on(user: Dictionary, item_id: String, target: Ent) -> void:
	var item: Dictionary = db.items.get(item_id, {})
	var use: Dictionary = item.get("use", {})
	if use.is_empty() or not remove_item(item_id, 1):
		return
	var tname: String = target.name if target != null else user.name
	journal("combat", "%s uses %s%s." % [user.name, item.name, "" if tname == user.name else " on " + tname])
	io.sfx("drink")
	if use.has("heal"):
		var r := Dice.as_result(Dice.roll(use.heal, rng), "heal", item.name, user.name)
		await show_roll(r, true)
		if target != null:
			heal_ent(target, int(r.total))
		else:
			heal_character(user, int(r.total))
	if use.has("effect"):
		var actor: Dictionary = target.actor if target != null else user
		Effects.add(actor, use.effect)
		if target != null:
			io.float_text(target, use.effect.get("name", "Effect"), "info")
	state_changed.emit()


## Casts a helpful spell while exploring (healing, buffs). Returns false when it cannot be cast.
func cast_outside_combat(caster: Dictionary, spell_id: String, target: Dictionary) -> bool:
	var spell: Dictionary = db.spells.get(spell_id, {})
	var st := stats(caster)
	if spell.is_empty() or encounter != null or busy > 0 or int(caster.hp) <= 0:
		return false
	if not (spell.get("target", "") in ["ally", "self", "allies_burst"]):
		journal("system", "%s can only be used in combat." % spell.get("name", spell_id))
		return false
	if not SpellRules.can_use(caster, st, spell, db):
		journal("system", "%s has no uses of %s left." % [caster.name, spell.name])
		return false
	var c_ent := ent_of(caster)
	var t_ent := ent_of(target)
	if c_ent == null or t_ent == null:
		return false
	SpellRules.spend(caster, st, spell)
	var targets: Array = [t_ent]
	if spell.target == "allies_burst":
		targets = world.party_ents()
	elif spell.target == "self":
		targets = [c_ent]
	busy += 1
	await Encounter.cast_spell(self, c_ent, spell, targets, targets[0], null)
	busy -= 1
	state_changed.emit()
	return true
