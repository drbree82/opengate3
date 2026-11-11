class_name DevTools
extends RefCounted
## Developer shortcuts driven by command-line arguments after "--":
##   ./run.sh -- --campaign=hollowmere --hero=kaelen     skip the title screen, start playing at once
##   ./run.sh -- --shots=/tmp/shots --tour=play           run a scripted tour and save screenshots, then quit
##   ./run.sh -- --shots=/tmp/shots --tour=live --campaign=hollowmere --hero=kaelen
##        plays the real window with REAL mouse and keyboard events (click to walk, WASD, talk, number keys,
##        doors, a trap, a fight, quick save/load) and writes live_log.txt with one "ok"/"FAIL" line per step
##   extra flags:  --hero=<companion id> | --hero=custom   --campaign=<id>   --skip-intro
## Tours are the quickest way to SEE whether a UI change works without playing by hand.
## To add one, write a `_tour_<name>()` coroutine below and call it from _run_tour().

var main
var shots := ""
var tour := "play"
var campaign := ""
var hero := ""
var skip_intro := false
var _n := 0


func _init(main_node) -> void:
	main = main_node


func handle(args: PackedStringArray) -> bool:
	for a in args:
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--tour="):
			tour = a.trim_prefix("--tour=")
		elif a.begins_with("--campaign="):
			campaign = a.trim_prefix("--campaign=")
		elif a.begins_with("--hero="):
			hero = a.trim_prefix("--hero=")
		elif a == "--skip-intro":
			skip_intro = true
	if shots == "" and campaign == "":
		return false
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		# Render at a fixed 1600x900 whatever size the window manager gives the window,
		# so screenshots always look the same.
		var win: Window = main.get_window()
		win.content_scale_size = Vector2i(1600, 900)
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		_run_tour()
	else:
		_quick_start()
	return true


func _spec() -> Dictionary:
	var comps: Dictionary = main.game.campaign.get("companions", {})
	if hero != "" and comps.has(hero):
		var s: Dictionary = comps[hero].duplicate(true)
		s["id"] = hero
		return s
	return {"id": "player", "name": "Aria", "race": "half_elf", "cls": "wizard", "racialChoice": "int",
		"abilities": {"str": 8, "dex": 14, "con": 12, "int": 16, "wis": 10, "cha": 10},
		"feats": ["toughness"], "skillRanks": {"knowledge_arcana": 1, "spellcraft": 1, "perception": 1},
		"spells": ["acid_splash", "ray_of_frost", "daze", "disrupt_undead", "magic_missile", "burning_hands", "sleep", "mage_armor"],
		"look": {"body": "feminine", "build": "curvy", "skin": "#e0ac82", "hair": "#b8452a", "hairStyle": "long", "outfit": "dress", "top": "#2a4a7a", "trim": "#d9b45a"}}


func _quick_start() -> void:
	var g: Game = main.game
	if not g.load_campaign(campaign):
		main.show_title()
		return
	if skip_intro and g.campaign.start.has("do"):
		g.campaign.start["do"] = g.campaign.start["do"].filter(func(a): return a.get("op", "") != "cutscene.play")
	main.audio.set_campaign(g.campaign.get("dir", ""))
	main.journal.reload()
	g.new_game(_spec())


func wait(seconds: float) -> void:
	await main.get_tree().create_timer(seconds).timeout


func shot(label: String) -> void:
	await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	_n += 1
	var path := "%s/%02d_%s.png" % [shots, _n, label]
	main.get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


## Waits until no script / dialogue / cutscene / fight is running (or the timeout passes).
func idle(timeout := 30.0) -> void:
	var t := 0.0
	while (main.game.busy > 0 or main.game.mode == "combat") and t < timeout:
		await main.get_tree().process_frame
		t += main.get_process_delta_time()


func _run_tour() -> void:
	if campaign == "":
		var list := Campaign.list()
		campaign = list[0].id if not list.is_empty() else "_template"
	await wait(0.3)
	match tour:
		"title":
			await _tour_title()
		"combat":
			await _tour_combat()
		"live":
			await _tour_live()
		"live-dungeon":
			var g: Game = main.game
			g.load_campaign(campaign)
			g.campaign.start["do"] = g.campaign.start["do"].filter(func(a): return a.get("op", "") != "cutscene.play")
			main.audio.set_campaign(g.campaign.get("dir", ""))
			main.journal.reload()
			g.new_game(_spec())
			await wait(0.8)
			for cid in ["pip", "brunhild"]:
				Party.add(g, cid)
			await _live_dungeon()
		_:
			await _tour_play()
	print("tour finished")
	main.get_tree().quit()


func _tour_title() -> void:
	main.show_title()
	await wait(0.5)
	await shot("title")
	main.open_builder(campaign)
	await wait(0.5)
	await shot("heroes")
	main.overlay._show_custom()
	await wait(0.5)
	await shot("builder")


## New game -> intro cutscene -> exploring -> first dialogue with choices.
func _tour_play() -> void:
	var g: Game = main.game
	g.load_campaign(campaign)
	main.audio.set_campaign(g.campaign.get("dir", ""))
	main.journal.reload()
	g.new_game(_spec())
	await wait(2.2)
	await shot("intro_cutscene")
	g.skip_cutscene = true
	g.anims.finish_all()
	main.io.request_skip()
	await idle(10.0)
	await wait(1.0)
	await shot("explore")
	g.cam.prefer_chase = true
	g.cam.snap()
	await wait(0.4)
	await shot("chase_camera")
	g.cam.prefer_chase = false
	var talker: Ent = null
	for e in g.world.ents:
		if e.kind == "npc" and e.dialogue != "" and talker == null:
			talker = e
	if talker != null:
		g.world.interact(talker)
		await wait(2.5)
		await shot("dialogue")
		var guard := 0
		while g.in_dialogue and guard < 12:
			guard += 1
			if main.journal.has_choices():
				main.journal.pick(0)
			else:
				main.io.request_skip()
			await wait(1.6)
			if guard == 2:
				await shot("dialogue_roll")
		await idle(8.0)
	main.sheet._set_tab("Skills")
	await wait(0.3)
	await shot("sheet_skills")
	main.sheet._set_tab("Gear")
	main.journal._select_tab("Quests")
	await wait(0.3)
	await shot("gear_and_quests")


## Starts the first hostile group on the map and screenshots a few moments of the fight.
func _tour_combat() -> void:
	var g: Game = main.game
	g.load_campaign(campaign)
	if g.campaign.start.has("do"):
		g.campaign.start["do"] = g.campaign.start["do"].filter(func(a): return a.get("op", "") != "cutscene.play")
	main.audio.set_campaign(g.campaign.get("dir", ""))
	main.journal.reload()
	g.new_game(_spec())
	await wait(0.6)
	for cid in g.campaign.get("companions", {}):
		if g.state.party.size() < 3:
			Party.add(g, cid)
	var foe: Ent = null
	for e in g.world.ents:
		if e.kind == "monster" and e.hostile and foe == null:
			foe = e
	if foe == null:
		print("no monsters on the start map")
		return
	for d in g.world.map.raw.get("rows", []).size():
		for x in g.world.map.w:
			if g.world.map.door(x, d) != null:
				g.world.open_door(Vector2i(x, d))
	var spot: Vector2i = g.world.free_cell_near(foe.cell() + Vector2i(-3, 0))
	var i := 0
	for e in g.world.party_ents():
		e.set_cell(g.world.free_cell_near(spot + Vector2i(0, i), e))
		i += 1
	g.cam.snap()
	g.start_combat(foe.group)
	await wait(1.0)
	await shot("initiative")
	var t := 0.0
	while not main.view.combat.waiting() and t < 25.0 and g.encounter != null:
		await main.get_tree().process_frame
		t += main.get_process_delta_time()
	await wait(0.3)
	await shot("player_turn")
	if main.view.combat.waiting() and g.encounter != null:
		var me: Ent = main.view.combat.ent
		var foes: Array = g.encounter.enemies_of(me)
		if not foes.is_empty():
			main.view.combat.on_pick({"ent": foes[0], "cell": foes[0].cell()})
			await wait(1.4)
			await shot("after_click")
			if main.view.combat.waiting():
				main.view.combat.on_pick({"ent": foes[0], "cell": foes[0].cell()})
				await wait(1.2)
				await shot("attack_roll")
	g.player_controller = null
	if main.view.combat.waiting():
		main.view.combat.end_turn()
	g.settings["dice_speed"] = 6.0
	await idle(60.0)
	await wait(0.8)
	await shot("after_combat")


# ----------------------------------------------------------------------------------------------
# Live tour: the real window driven by real input events
# ----------------------------------------------------------------------------------------------

var _log: Array = []
var _fails := 0


func _note(ok, text: String) -> void:
	var line := "%s  %s" % ["ok  " if ok else "FAIL", text]
	if not ok:
		_fails += 1
	_log.append(line)
	print("LIVE " + line)


## Presses and releases a key through Godot's input system (held for `hold` seconds).
func key(code: int, hold := 0.06) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await wait(hold if pressed else 0.06)


## A left mouse click at a position of the window's 1600x900 canvas.
func click_at(pos: Vector2) -> void:
	var vp: Viewport = main.get_viewport()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	vp.push_input(mv, true)
	await main.get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev, true)
		await main.get_tree().process_frame


## Where a point of the 3D world appears in the window.
func screen_of(p: Vector3) -> Vector2:
	return main.view.world.world_to_screen(p) * float(ViewPanel.SHRINK) + main.view.hud.global_position


## Clicks on a point of the 3D world (a floor tile, a door, a character).
func click_world(p: Vector3) -> void:
	await click_at(screen_of(p))


## Chase camera looking along `yaw` (0 = east, -PI/2 = north) so the click target is in view.
func _look(yaw: float) -> void:
	main.game.cam.prefer_chase = true
	main.game.cam.yaw = yaw
	main.game.cam.snap()
	await wait(0.3)


## Hurries text along with Space until the journal offers choices (or nothing is running any more).
func _until_choices(timeout := 25.0) -> bool:
	var t := 0.0
	while t < timeout:
		if main.journal.has_choices():
			return true
		if main.game.busy == 0 and not main.dice._busy:
			return false
		await key(KEY_SPACE)
		await wait(0.2)
		t += 0.4
	return main.journal.has_choices()


## Picks the choice whose text contains `text` by pressing its number key.
func _choose(text: String) -> bool:
	if not await _until_choices():
		return false
	var choices: Array = main.journal._choices
	for i in choices.size():
		if str(choices[i].get("text", "")).contains(text):
			await key(KEY_1 + i)
			return true
	return false


## Hurries text along with Space, picking the first reply if asked, until nothing is running.
func _finish(timeout := 40.0) -> void:
	var t := 0.0
	while main.game.busy > 0 and main.game.mode != "combat" and t < timeout:
		if main.journal.has_choices():
			await key(KEY_1)
		else:
			await key(KEY_SPACE)
		await wait(0.25)
		t += 0.4


func _wait_dice(label: String, timeout := 12.0) -> bool:
	var t := 0.0
	while t < timeout:
		if str(main.dice.title.text).contains(label) and str(main.dice.total.text) != "":
			return true
		await main.get_tree().process_frame
		t += main.get_process_delta_time()
	return false


func _tour_live() -> void:
	var g: Game = main.game
	g.load_campaign(campaign)
	main.audio.set_campaign(g.campaign.get("dir", ""))
	main.journal.reload()
	g.new_game(_spec())
	var lead_name: String = g.leader().name

	# --- intro cutscene, voice, skipping with Esc ---
	await wait(5.2)
	_note(g.in_cutscene, "the intro cutscene plays in the window")
	_note(main.audio.voice_playing(), "the narrator's voice clip is playing during the cutscene")
	await shot("live_cutscene")
	await key(KEY_ESCAPE)
	await idle(10.0)
	await wait(0.8)
	_note(not g.in_cutscene and g.mode == "explore" and g.busy == 0, "Esc skipped the cutscene; the game is in exploration")
	_note(main.audio._music.playing, "background music is playing on the town map")
	_note(g.state.quests.has("a_cold_welcome"), "mission 1 was given (journal: %s)" % str(g.state.journal[g.state.journal.size() - 1].text))

	# --- click to move ---
	var lead: Ent = g.world.leader_ent()
	await _look(0.0)
	var target: Vector2i = lead.cell() + Vector2i(3, 0)
	var from: Vector2i = lead.cell()
	await click_world(Vector3(target.x + 0.5, 0.0, target.y + 0.5))
	await wait(2.2)
	_note(lead.cell() == target, "a mouse click on the floor walked %s from %s to %s" % [lead_name, str(from), str(lead.cell())])

	# --- WASD ---
	var before := lead.pos()
	await key(KEY_W, 0.7)
	await wait(0.2)
	_note(lead.pos().distance_to(before) > 0.8, "holding W walked %.1f tiles forward" % lead.pos().distance_to(before))
	await shot("live_explore")

	# --- stat checks from the character sheet land in the dice tray ---
	main.sheet._on_link("skill:perception")
	await wait(0.45)
	await shot("live_dice_tumbling")
	_note(await _wait_dice("Perception"), "dice tray shows the Perception check: '%s' total %s" % [main.dice.title.text, main.dice.total.text])
	await shot("live_dice_perception")
	await wait(1.2)
	main.sheet._on_link("init")
	_note(await _wait_dice("Initiative"), "dice tray shows the Initiative roll: '%s' total %s" % [main.dice.title.text, main.dice.total.text])
	await wait(1.2)
	main.sheet._on_link("save:will")
	_note(await _wait_dice("Will"), "dice tray shows the saving throw: '%s' total %s" % [main.dice.title.text, main.dice.total.text])
	await wait(1.2)
	main.dice.free_roll(20)
	_note(await _wait_dice("d20"), "the free-roll d20 button works: total %s" % main.dice.total.text)
	await wait(1.2)

	# --- quick save / quick load ---
	var saved_cell: Vector2i = lead.cell()
	await key(KEY_F5)
	_note(SaveGame.exists("quicksave"), "F5 wrote a quick save")
	await key(KEY_S, 0.6)
	await wait(0.2)
	var moved: bool = g.world.leader_ent().cell() != saved_cell
	await key(KEY_F9)
	await wait(0.8)
	lead = g.world.leader_ent()
	_note(moved and lead.cell() == saved_cell, "F9 loaded it again (hero back at %s)" % str(lead.cell()))

	# --- talk to an NPC with the mouse, answer with number keys, skill check in dialogue ---
	lead.set_cell(Vector2i(18, 4))
	await _look(0.0)
	var reeve: Ent = g.world.by_id("reeve")
	await click_world(Vector3(reeve.x, 0.45, reeve.y))
	await wait(2.0)
	_note(g.in_dialogue, "clicking Reeve Maren walked over and started the conversation")
	_note(main.audio.voice_playing(), "her voice clip is playing")
	_note(main.journal.speaker_name.text.contains("Maren"), "the journal shows who is speaking: %s" % main.journal.speaker_name.text)
	await _until_choices()
	await shot("live_dialogue")
	_note(await _choose("What does the town pay"), "pressed a number key to choose a reply")
	await _until_choices()
	var tagged := false
	for ch in main.journal._choices:
		if str(ch.get("tag", "")).contains("Diplomacy DC 14"):
			tagged = true
	_note(tagged, "a reply is offered as a skill check: [Diplomacy DC 14]")
	await shot("live_dialogue_check_offer")
	await _choose("worth more than that")
	_note(await _wait_dice("Diplomacy"), "dice tray shows the Diplomacy check: '%s' total %s %s" % [main.dice.title.text, main.dice.total.text, main.dice.outcome.text])
	await shot("live_dice_diplomacy")
	await _choose("I will look into it")
	await _finish()
	_note(not g.in_dialogue and g.state.quests.a_cold_welcome.stage == "camp", "the conversation ended and the quest moved to its next stage")

	# --- recruit companions through their dialogue, then camp with G ---
	for cid in ["pip", "brunhild"]:
		if cid in g.state.party:
			continue
		g.run_dialogue(cid, {"ent": g.world.by_id(cid)})
		var guard := 0
		while g.in_dialogue and guard < 10:
			guard += 1
			if await _until_choices(6.0):
				var picked := false
				for want in ["open doors", "fair share", "Will you help me"]:
					for i in main.journal._choices.size():
						if not picked and str(main.journal._choices[i].text).contains(want):
							picked = true
							await key(KEY_1 + i)
				if not picked:
					await key(KEY_1)
			await wait(0.3)
		await idle(8.0)
	_note(g.state.party.size() >= 3, "companions joined through their conversations: party of %d" % g.state.party.size())
	await key(KEY_G)
	await wait(1.5)
	await idle(10.0)
	_note(g.world.map.id == "camp", "G travelled to the camp (mission 1 %s)" % g.state.quests.a_cold_welcome.status)
	await shot("live_camp")
	await key(KEY_G)
	await wait(1.5)
	await idle(10.0)
	_note(g.world.map.id == "town", "G again returned to town")

	await _live_dungeon()


## Second half of the live tour: door, trap (Perception check), fight (initiative + attack rolls).
## `--tour=live-dungeon` runs only this part (after a quick setup).
func _live_dungeon() -> void:
	var g: Game = main.game
	var lead: Ent = g.world.leader_ent()
	var t := 0.0
	g.travel("barrow", "entrance")
	await wait(2.0)
	await key(KEY_ESCAPE)
	await idle(12.0)
	await wait(0.5)
	lead = g.world.leader_ent()
	_note(g.world.map.id == "barrow" and g.busy == 0, "travelled to the dungeon")
	await _look(-PI / 2.0)
	await click_world(Vector3(5.5, 0.5, 18.5))
	await wait(3.0)
	_note(not g.world.map.is_solid(5, 18), "clicking the dungeon door walked up to it and opened it")
	await _look(-PI / 2.0)
	await click_world(Vector3(5.5, 0.0, 14.5))
	_note(await _wait_dice("Perception", 14.0), "walking onto the trap made the GM call a Perception check: '%s' total %s %s" % [main.dice.title.text, main.dice.total.text, main.dice.outcome.text])
	await shot("live_dice_trap")
	var guard2 := 0
	while g.busy > 0 and guard2 < 30:
		guard2 += 1
		if main.journal.has_choices():
			await _choose("Step carefully")
		else:
			await key(KEY_SPACE)
		await wait(0.3)
	_note(g.busy == 0 and "blade_trap" in g.world.map_state().fired, "the trap was resolved")
	await _look(-PI / 2.0)
	lead = g.world.leader_ent()
	await click_world(Vector3(5.5, 0.0, 12.5))
	await wait(1.8)
	await _look(-PI / 4.0)
	await click_world(Vector3(7.5, 0.0, 9.5))
	t = 0.0
	while g.encounter == null and t < 8.0:
		await main.get_tree().process_frame
		t += main.get_process_delta_time()
	_note(g.encounter != null, "walking into the hall started a fight with the skeletons")
	_note(await _wait_dice("Initiative", 10.0), "dice tray shows initiative rolls: '%s' total %s" % [main.dice.title.text, main.dice.total.text])
	await shot("live_dice_initiative")
	t = 0.0
	while not main.view.combat.waiting() and g.encounter != null and t < 40.0:
		main.io.request_skip()
		await wait(0.2)
		t += 0.2
	_note(main.view.combat.waiting(), "it is a player turn: %s" % main.view.combat.info.text)
	var attacked := false
	var tries := 0
	while g.encounter != null and tries < 12 and not attacked:
		# wait for the next player turn, hurrying the enemies' dice along
		var waited := 0.0
		while g.encounter != null and not main.view.combat.waiting() and waited < 45.0:
			main.io.request_skip()   # (Space would END the turn if a player turn starts right now)
			await wait(0.2)
			waited += 0.2
		if g.encounter == null or not main.view.combat.waiting():
			break
		tries += 1
		var me: Ent = main.view.combat.ent
		var foes: Array = g.encounter.enemies_of(me)
		if foes.is_empty():
			break
		var foe: Ent = foes[0]
		for f in foes:
			if me.dist_to(f) < me.dist_to(foe):
				foe = f
		# Room camera (the view from the corner of the hall), as a player would use in a fight.
		g.cam.prefer_chase = false
		g.cam.snap()
		await wait(0.4)
		var hp_before: int = foe.actor.hp
		var cell_before: Vector2i = me.cell()
		var how := "in the 3D view"
		if tries % 2 == 1:
			await click_world(Vector3(foe.x, 0.4, foe.y))
		else:
			# the minimap is the precise way to pick a tile when sprites overlap
			how = "on the minimap"
			var mm = main.view.minimap
			await click_at(mm.global_position + (Vector2(foe.cell()) + Vector2(0.5, 0.5)) * mm.scale_px())
		await wait(1.6)
		if tries == 1:
			await shot("live_combat_click")
		if str(main.dice.title.text).contains(me.name) and not str(main.dice.title.text).contains("Initiative"):
			attacked = true
			_note(true, "clicking an enemy %s made an attack roll: '%s' total %s %s (enemy hp %d -> %d)" % [how, main.dice.title.text, main.dice.total.text, main.dice.outcome.text, hp_before, int(foe.actor.hp)])
			await shot("live_dice_attack")
		elif me.cell() != cell_before:
			_note(true, "clicking a distant enemy %s walked %s towards it (%s -> %s)" % [how, me.name, str(cell_before), str(me.cell())])
		elif main.view.combat.waiting() and main.view.combat.ent == me:
			await key(KEY_SPACE)   # nothing left to do with this character: end the turn like a player would
			await wait(0.3)
	if not attacked:
		_note(false, "no attack roll was made by clicking an enemy")
	g.cam.focus = null
	# let the AI finish the fight quickly
	g.player_controller = null
	g.settings["dice_speed"] = 8.0
	# the turn in progress still belongs to the player: end it once its current action has finished
	var w := 0.0
	while g.encounter != null and w < 8.0:
		if main.view.combat.waiting():
			await key(KEY_SPACE)
			break
		await wait(0.2)
		w += 0.2
	await idle(120.0)
	await wait(1.0)
	var fight := "won" if g.world.ents_in_group("hall_dead").is_empty() else "not won"
	_note(g.encounter == null, "the fight ended (%s); party hp: %s" % [fight, ", ".join(g.party().map(func(c): return "%s %d" % [str(c.name).get_slice(" ", 0), int(c.hp)]))])
	await shot("live_after_fight")

	var rolls := 0
	for e in g.state.journal:
		if e.kind == "roll":
			rolls += 1
	_note(rolls >= 10, "%d rolls went through the dice tray during this session" % rolls)
	print("LIVE RESULT: %d of %d steps ok" % [_log.size() - _fails, _log.size()])
	var f := FileAccess.open(shots + "/live_log.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log) + "\nRESULT: %d of %d steps ok\n" % [_log.size() - _fails, _log.size()])
		f.close()
