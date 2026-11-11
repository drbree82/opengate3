class_name CampaignValidator
extends RefCounted
## Finds mistakes in a campaign's JSON before anyone plays it: unknown ids, missing dialogue nodes,
## misspelled script ops, textures or markers that do not exist, and so on.
##   - ./check.sh runs it for every campaign (tests/test_campaigns.gd) and fails on any ERROR.
##   - tools/validate_campaign.gd prints the full report (errors and warnings) for one campaign.
## When you add a script op, condition or data field, teach the validator about it here.
##
##   var report := CampaignValidator.check(game)     # game has a campaign loaded
##   report.errors, report.warnings                   # Arrays of "where: what is wrong" strings

const CUTSCENE_OPS := [
	"wait", "parallel", "sequence", "camera.set", "camera.move", "camera.auto", "camera.script", "camera.shake",
	"actor.spawn", "actor.remove", "actor.teleport", "actor.move", "actor.face", "actor.anim", "actor.show", "actor.hide",
	"say", "narrate", "title", "fade",
]
const COND_PARAMS := ["equals", "stage", "status", "atLeast", "qty", "state", "min"]

var game
var c: Dictionary
var db: Dictionary
var errors: Array = []
var warnings: Array = []
var maps: Dictionary = {}      # map id -> MapData
var groups: Dictionary = {}    # monster group -> true
var where := ""


static func check(g) -> Dictionary:
	var v := CampaignValidator.new()
	v.game = g
	v.c = g.campaign
	v.db = g.db
	v._run()
	return {"errors": v.errors, "warnings": v.warnings}


func _err(msg: String) -> void:
	errors.append("%s: %s" % [where, msg])


func _warn(msg: String) -> void:
	warnings.append("%s: %s" % [where, msg])


func _run() -> void:
	where = "campaign.json"
	for e in c.get("errors", []):
		_err(str(e))
	if not c.has("start"):
		_err("missing \"start\"")
		return
	TexFactory.campaign_dir = c.get("dir", "")
	for mid in c.get("maps", {}):
		maps[mid] = MapData.parse(c.maps[mid], mid)
	_collect_groups()
	_start()
	_companions()
	_entities()
	_monsters()
	_quests()
	_maps()
	_dialogues()
	_cutscenes()
	_encounters()
	_shops()


# ----------------------------------------------------------------------------------------------
# Lookups
# ----------------------------------------------------------------------------------------------

func _template(template_id) -> Dictionary:
	var tid := str(template_id)
	if c.get("entities", {}).has(tid):
		return c.entities[tid]
	if db.props.has(tid):
		return db.props[tid]
	if c.get("companions", {}).has(tid):
		return {"kind": "npc", "companion": tid}
	if db.monsters.has(tid):
		return {"kind": "monster", "monster": tid}
	return {}


func _collect_groups() -> void:
	for mid in maps:
		var m: MapData = maps[mid]
		for p in m.placements:
			var t: Dictionary = _template(p.entity).duplicate()
			t.merge(p.overrides, true)
			if t.get("kind", "") == "monster":
				groups[t.get("group", "wild")] = true
	_scan_spawn_groups(c)


func _scan_spawn_groups(v) -> void:
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			_scan_spawn_groups(x)
	elif typeof(v) == TYPE_DICTIONARY:
		if v.get("op", "") == "entity.spawn" and v.has("group"):
			groups[v.group] = true
		for k in v:
			if typeof(v[k]) == TYPE_ARRAY or typeof(v[k]) == TYPE_DICTIONARY:
				_scan_spawn_groups(v[k])


func _marker_ok(map_id, marker) -> bool:
	if typeof(marker) != TYPE_STRING:
		return true
	return maps.has(map_id) and maps[map_id].markers.has(marker)


func _item(item_id, what := "item") -> void:
	if not db.items.has(str(item_id)):
		_err("unknown %s \"%s\" (not in data/items.json or the campaign's items.json)" % [what, item_id])


func _quest(quest_id) -> bool:
	if not c.get("quests", {}).has(str(quest_id)):
		_err("unknown quest \"%s\"" % quest_id)
		return false
	return true


# ----------------------------------------------------------------------------------------------
# Scripts
# ----------------------------------------------------------------------------------------------

func _actions(list, cutscene := false) -> void:
	if list == null:
		return
	if typeof(list) != TYPE_ARRAY:
		_err("a script must be a list of actions [ {...}, {...} ]")
		return
	for a in list:
		if typeof(a) != TYPE_DICTIONARY:
			_err("every action must be an object like {\"op\": \"...\"}")
			continue
		_action(a, cutscene)


func _action(a: Dictionary, cutscene: bool) -> void:
	var op: String = a.get("op", "")
	if op == "":
		_err("action without \"op\": %s" % JSON.stringify(a).left(80))
		return
	if not game.scripts.ops.has(op) and not (cutscene and op in CUTSCENE_OPS):
		_err("unknown op \"%s\"%s" % [op, "" if cutscene else " (cutscene-only ops work only inside cutscenes)" if op in CUTSCENE_OPS else ""])
		return
	if a.has("if"):
		_cond(a["if"])
	match op:
		"narrate", "say", "log":
			if str(a.get("text", "")) == "":
				_err("%s needs \"text\"" % op)
		"quest.start", "quest.complete", "quest.fail":
			_quest(a.get("id", ""))
		"quest.stage":
			if _quest(a.get("id", "")):
				var ids: Array = c.quests[a.id].get("stages", []).map(func(s): return s.get("id", ""))
				if not (a.get("stage", "") in ids):
					_err("quest \"%s\" has no stage \"%s\" (stages: %s)" % [a.id, a.get("stage", ""), ", ".join(ids)])
		"item.give", "item.take":
			_item(a.get("id", ""))
		"party.add", "party.remove", "party.lead", "approval.add":
			if not c.get("companions", {}).has(a.get("id", "")):
				_err("%s: unknown companion \"%s\"" % [op, a.get("id", "")])
		"gold.add", "xp.add":
			if typeof(a.get("amount")) != TYPE_INT:
				_err("%s needs a whole-number \"amount\"" % op)
		"map.goto":
			if not maps.has(a.get("map", "")):
				_err("map.goto: unknown map \"%s\"" % a.get("map", ""))
			elif not _marker_ok(a.map, a.get("marker", "start")):
				_err("map.goto: map \"%s\" has no marker \"%s\"" % [a.map, a.get("marker", "start")])
		"combat.start", "group.hostile", "group.remove":
			if not groups.has(a.get("group", "")):
				_err("%s: no monsters use the group \"%s\" (groups: %s)" % [op, a.get("group", ""), ", ".join(groups.keys())])
		"cutscene.play":
			if not c.get("cutscenes", {}).has(a.get("id", "")):
				_err("unknown cutscene \"%s\"" % a.get("id", ""))
		"dialogue.start":
			if not c.get("dialogues", {}).has(a.get("id", "")):
				_err("unknown dialogue \"%s\"" % a.get("id", ""))
		"shop.open":
			if not c.get("shops", {}).has(a.get("id", "")):
				_err("unknown shop \"%s\"" % a.get("id", ""))
		"entity.spawn", "actor.spawn":
			if _template(a.get("template", "")).is_empty():
				_err("%s: unknown entity template \"%s\"" % [op, a.get("template", "")])
		"check":
			_check_spec(a)
			_actions(a.get("success"), cutscene)
			_actions(a.get("failure"), cutscene)
		"choice":
			var options = a.get("options", [])
			if typeof(options) != TYPE_ARRAY or options.is_empty():
				_err("choice needs a non-empty \"options\" list")
			else:
				for o in options:
					if str(o.get("text", "")) == "":
						_err("a choice option has no \"text\"")
					if o.has("if"):
						_cond(o["if"])
					if o.has("check"):
						_check_spec(o.check)
					_actions(o.get("do"), cutscene)
					_actions(o.get("success"), cutscene)
					_actions(o.get("failure"), cutscene)
		"damage":
			if Dice.parse(a.get("dice", "1d6")).terms.is_empty() and int(Dice.parse(a.get("dice", "1d6")).flat) == 0:
				_err("damage: bad dice \"%s\"" % a.get("dice", ""))
			if a.has("save") and not (a.save.get("type", "") in ["fort", "ref", "will"]):
				_err("damage: save type must be fort, ref or will")
		"effect.add":
			for cid in a.get("effect", {}).get("conditions", []):
				if not db.conditions.has(cid):
					_err("effect.add: unknown condition \"%s\"" % cid)
		"parallel", "sequence":
			_actions(a.get("steps"), cutscene)
		"title":
			if str(a.get("text", "")) == "":
				_err("title needs \"text\"")


func _check_spec(spec) -> void:
	if typeof(spec) != TYPE_DICTIONARY:
		_err("a check must be an object like {\"skill\": \"perception\", \"dc\": 15}")
		return
	var kinds := 0
	if spec.has("skill"):
		kinds += 1
		if not db.skills.has(spec.skill):
			_err("check: unknown skill \"%s\" (ids are in data/skills.json)" % spec.skill)
	if spec.has("save"):
		kinds += 1
		if not (spec.save in ["fort", "ref", "will"]):
			_err("check: save must be fort, ref or will")
	if spec.has("ability"):
		kinds += 1
		if not (spec.ability in CharRules.ABILITIES):
			_err("check: unknown ability \"%s\"" % spec.ability)
	if kinds != 1:
		_err("check needs exactly one of \"skill\", \"save\" or \"ability\"")
	if spec.has("dc") and typeof(spec.dc) != TYPE_INT:
		_err("check: \"dc\" must be a whole number")
	if spec.has("who") and not (spec.who in ["leader", "best"]) and not c.get("companions", {}).has(spec.who):
		_err("check: \"who\" must be leader, best or a companion id")


func _cond(cond) -> void:
	if typeof(cond) != TYPE_DICTIONARY:
		return
	for key in cond:
		if key in COND_PARAMS:
			continue
		if not game.scripts.conds.has(key):
			_err("unknown condition \"%s\" (known: %s)" % [key, ", ".join(game.scripts.conds.keys())])
			continue
		match key:
			"not":
				_cond(cond["not"])
			"all", "any":
				if typeof(cond[key]) != TYPE_ARRAY:
					_err("condition \"%s\" needs a list" % key)
				else:
					for sub in cond[key]:
						_cond(sub)
			"quest":
				if _quest(cond.quest):
					var ids: Array = c.quests[cond.quest].get("stages", []).map(func(s): return s.get("id", ""))
					for k in ["stage", "atLeast"]:
						if cond.has(k) and not (cond[k] in ids):
							_err("condition: quest \"%s\" has no stage \"%s\"" % [cond.quest, cond[k]])
					if cond.has("status") and not (cond.status in ["none", "active", "completed", "failed"]):
						_err("condition: quest status must be none, active, completed or failed")
			"hasItem":
				_item(cond.hasItem)
			"inParty", "companion":
				if not c.get("companions", {}).has(cond[key]) and cond[key] != "player":
					_err("condition: unknown companion \"%s\"" % cond[key])
			"cls", "partyCls":
				if not db.classes.has(cond[key]):
					_err("condition: unknown class \"%s\"" % cond[key])
			"race":
				if not db.races.has(cond.race):
					_err("condition: unknown race \"%s\"" % cond.race)
			"skill":
				if not db.skills.has(cond.skill):
					_err("condition: unknown skill \"%s\"" % cond.skill)
			"map":
				if not maps.has(cond.map):
					_err("condition: unknown map \"%s\"" % cond.map)


# ----------------------------------------------------------------------------------------------
# Sections
# ----------------------------------------------------------------------------------------------

func _start() -> void:
	where = "campaign.json start"
	var s: Dictionary = c.start
	if not maps.has(s.get("map", "")):
		_err("start map \"%s\" does not exist in maps/" % s.get("map", ""))
	elif not _marker_ok(s.map, s.get("marker", "start")):
		_err("start map has no marker \"%s\"" % s.get("marker", "start"))
	_actions(s.get("do"))
	if c.has("camp"):
		where = "campaign.json camp"
		if not maps.has(c.camp.get("map", "")):
			_err("camp map \"%s\" does not exist" % c.camp.get("map", ""))
		elif not _marker_ok(c.camp.map, c.camp.get("marker", "start")):
			_err("camp map has no marker \"%s\"" % c.camp.get("marker", "start"))


func _companions() -> void:
	for cid in c.get("companions", {}):
		where = "companions.json %s" % cid
		var s: Dictionary = c.companions[cid]
		if not db.races.has(s.get("race", "")):
			_err("unknown race \"%s\"" % s.get("race", ""))
			continue
		if not db.classes.has(s.get("cls", "")):
			_err("unknown class \"%s\" (use the key \"cls\")" % s.get("cls", ""))
			continue
		for f in s.get("feats", []):
			if not db.feats.has(CharRules.parse_feat(f).id):
				_err("unknown feat \"%s\"" % f)
		for sid in s.get("skillRanks", {}):
			if not db.skills.has(sid):
				_err("unknown skill \"%s\"" % sid)
		for sid in s.get("spells", []):
			if not db.spells.has(sid):
				_err("unknown spell \"%s\"" % sid)
		for slot in s.get("equipped", {}):
			if s.equipped[slot] != null:
				_item(s.equipped[slot], "equipped item")
		if CharRules.point_buy_total(s.get("abilities", {})) > CharRules.POINT_BUY_BUDGET:
			_warn("ability scores cost more than %d points" % CharRules.POINT_BUY_BUDGET)
		var built := CharRules.create(s, db)
		if int(CharRules.derive(built, db).hpMax) <= 0:
			_err("character could not be built")


func _sprite(sprite) -> void:
	if typeof(sprite) != TYPE_DICTIONARY or sprite.is_empty():
		return
	if sprite.has("sheet"):
		if not FileAccess.file_exists("%s/%s" % [c.get("dir", ""), sprite.sheet]):
			_err("sprite sheet \"%s\" not found in the campaign folder" % sprite.sheet)
	elif not (sprite.get("template", "") in SpriteFactory.TEMPLATES):
		_err("unknown sprite template \"%s\" (see docs/SPRITES.md)" % sprite.get("template", ""))


func _entities() -> void:
	for eid in c.get("entities", {}):
		where = "entities.json %s" % eid
		var e: Dictionary = c.entities[eid]
		if e.has("companion"):
			if not c.get("companions", {}).has(e.companion):
				_err("unknown companion \"%s\"" % e.companion)
		elif not (e.get("kind", "") in ["npc", "monster", "prop"]):
			_err("\"kind\" must be npc, monster or prop")
		if e.get("kind", "") == "monster" and not db.monsters.has(e.get("monster", eid)):
			_err("unknown monster \"%s\"" % e.get("monster", eid))
		if e.get("dialogue", "") != "" and not c.get("dialogues", {}).has(e.dialogue):
			_err("unknown dialogue \"%s\"" % e.dialogue)
		_sprite(e.get("sprite"))
		_actions(e.get("interact"))


func _monsters() -> void:
	for mid in db.monsters:
		where = "monster %s" % mid
		var m: Dictionary = db.monsters[mid]
		_sprite(m.get("sprite"))
		for sp in m.get("spells", []):
			if not db.spells.has(sp.get("id", "")):
				_err("unknown spell \"%s\"" % sp.get("id", ""))
		if m.get("attacks", []).is_empty():
			_err("needs at least one attack")


func _quests() -> void:
	for qid in c.get("quests", {}):
		where = "quests.json %s" % qid
		var q: Dictionary = c.quests[qid]
		var stages = q.get("stages", [])
		if typeof(stages) != TYPE_ARRAY or stages.is_empty():
			_err("needs a non-empty \"stages\" list")
			continue
		var seen := {}
		for s in stages:
			if str(s.get("id", "")) == "" or seen.has(s.get("id", "")):
				_err("every stage needs a unique \"id\"")
			seen[s.get("id", "")] = true
		for it in q.get("rewards", {}).get("items", []):
			_item(it.get("id", ""), "reward item")


func _texture(tex_name, what: String) -> void:
	var n := str(tex_name)
	if n in ["", "sky", "none"]:
		return
	if not TexFactory.has(n):
		_err("unknown %s texture \"%s\" (built-in names are listed in src/render/tex_factory.gd; or add textures/%s.png)" % [what, n, n])


func _maps() -> void:
	for mid in maps:
		var m: MapData = maps[mid]
		where = "maps/%s.json" % mid
		for e in m.errors:
			_err(str(e))
		for k in ["wall", "floor", "ceiling"]:
			_texture(m.defaults.get(k, ""), "default " + k)
		var used_triggers := {}
		var triggers: Dictionary = m.raw.get("triggers", {})
		for ch in m.legend:
			var e: Dictionary = m.legend[ch]
			where = "maps/%s.json legend \"%s\"" % [mid, ch]
			_texture(e.get("wall", ""), "wall")
			_texture(e.get("floor", ""), "floor")
			_texture(e.get("ceiling", ""), "ceiling")
			_texture(e.get("door", ""), "door")
			if e.has("entity"):
				var t := _template(e.entity)
				if t.is_empty():
					_err("unknown entity \"%s\" (not in entities.json, data/props.json, companions.json or the bestiary)" % e.entity)
			if e.has("exit"):
				var ex: Dictionary = e.exit
				if not maps.has(ex.get("map", "")):
					_err("exit to unknown map \"%s\"" % ex.get("map", ""))
				elif not _marker_ok(ex.map, ex.get("marker", "start")):
					_err("exit: map \"%s\" has no marker \"%s\"" % [ex.map, ex.get("marker", "start")])
			if e.has("trigger"):
				used_triggers[e.trigger] = true
				if not triggers.has(e.trigger):
					_err("trigger \"%s\" is not defined in this map's \"triggers\"" % e.trigger)
			if e.has("locked") and e.locked.has("key"):
				_item(e.locked.key, "key item")
		for tid in triggers:
			where = "maps/%s.json trigger \"%s\"" % [mid, tid]
			if not used_triggers.has(tid):
				_warn("no legend character uses this trigger")
			if triggers[tid].has("if"):
				_cond(triggers[tid]["if"])
			_actions(triggers[tid].get("do"))
		where = "maps/%s.json onEnter" % mid
		_actions(m.raw.get("onEnter"))
		where = "maps/%s.json" % mid
		var track: String = m.raw.get("music", "")
		if track != "" and not c.get("music", {}).has(track) and not FileAccess.file_exists("%s/music/%s.mp3" % [c.get("dir", ""), track]):
			_warn("music \"%s\" has no prompt in campaign.json \"music\" and no file in music/" % track)


func _dialogues() -> void:
	for did in c.get("dialogues", {}):
		where = "dialogues/%s.json" % did
		var d: Dictionary = c.dialogues[did]
		var nodes = d.get("nodes", {})
		if typeof(nodes) != TYPE_DICTIONARY or nodes.is_empty():
			_err("needs a \"nodes\" object")
			continue
		var starts: Array = []
		var start = d.get("start", "start")
		if typeof(start) == TYPE_STRING:
			starts.append(start)
		else:
			for option in start:
				starts.append(option.get("node", ""))
				if option.has("if"):
					_cond(option["if"])
			if not start.is_empty() and start[start.size() - 1].has("if"):
				_warn("the last \"start\" option has a condition; add a final {\"node\": \"...\"} without \"if\" as the fallback")
		var reached := {}
		var todo: Array = []
		for s in starts:
			_target(nodes, s, "start")
			todo.append(s)
		for nid in nodes:
			var n = nodes[nid]
			where = "dialogues/%s.json node \"%s\"" % [did, nid]
			if typeof(n) != TYPE_DICTIONARY:
				_err("must be an object")
				continue
			if n.has("if"):
				_cond(n["if"])
			_actions(n.get("do"))
			for k in ["goto", "else", "success", "failure"]:
				if n.has(k):
					_target(nodes, n[k], k)
			if n.has("check"):
				_check_spec(n.check)
			var sp: String = n.get("speaker", "")
			if sp != "" and sp == sp.to_lower() and not sp.contains(" ") and _template(sp).is_empty() and not (sp in ["player", "leader"]):
				_warn("speaker \"%s\" is not an entity or companion id; it will be shown as written" % sp)
			for ch in n.get("choices", []):
				if str(ch.get("text", "")) == "":
					_err("a choice has no \"text\"")
				if ch.has("if"):
					_cond(ch["if"])
				if ch.has("check"):
					_check_spec(ch.check)
					if not ch.has("success") and not ch.has("goto"):
						_err("choice \"%s\" has a check but no \"success\"/\"failure\" node" % str(ch.get("text", "")).left(30))
				_actions(ch.get("do"))
				for k in ["goto", "success", "failure"]:
					if ch.has(k):
						_target(nodes, ch[k], k)
		# reachability
		while not todo.is_empty():
			var nid: String = todo.pop_back()
			if nid == "end" or reached.has(nid) or not nodes.has(nid):
				continue
			reached[nid] = true
			var n: Dictionary = nodes[nid]
			for k in ["goto", "else", "success", "failure"]:
				if n.has(k):
					todo.append(n[k])
			for ch in n.get("choices", []):
				for k in ["goto", "success", "failure"]:
					if ch.has(k):
						todo.append(ch[k])
		where = "dialogues/%s.json" % did
		for nid in nodes:
			if not reached.has(nid):
				_warn("node \"%s\" can never be reached" % nid)


func _target(nodes: Dictionary, target, key: String) -> void:
	if str(target) != "end" and not nodes.has(str(target)):
		_err("\"%s\" points to a node that does not exist: \"%s\"" % [key, target])


func _cutscenes() -> void:
	for cid in c.get("cutscenes", {}):
		where = "cutscenes/%s.json" % cid
		var cs: Dictionary = c.cutscenes[cid]
		if not cs.has("map"):
			_warn("add \"map\": \"<map id>\" so the cutscene always plays in the right place")
		elif not maps.has(cs.map):
			_err("unknown map \"%s\"" % cs.map)
		_actions(cs.get("steps", []), true)


func _encounters() -> void:
	for gid in c.get("encounters", {}):
		where = "encounters.json %s" % gid
		var e: Dictionary = c.encounters[gid]
		if not groups.has(gid):
			_warn("no monsters on any map use the group \"%s\"" % gid)
		for it in e.get("loot", []):
			_item(it.get("id", ""), "loot item")
		for k in ["onStart", "onVictory", "onDefeat"]:
			_actions(e.get(k))
		for hook in e.get("onRound", []):
			_actions(hook.get("do"))


func _shops() -> void:
	for sid in c.get("shops", {}):
		where = "shops.json %s" % sid
		for entry in c.shops[sid].get("stock", []):
			_item(entry.get("id", ""), "stock item")
