class_name Dialogue
extends RefCounted
## Runs branching conversations (campaigns/<id>/dialogues/*.json). Format: docs/CAMPAIGN_FORMAT.md.
##
##   {"start": "greet",                       or [{"if": {...}, "node": "later"}, {"node": "greet"}]
##    "nodes": {
##      "greet": {"speaker": "bram", "text": "Welcome!", "do": [actions], "choices": [
##          {"text": "Any work?", "goto": "work"},
##          {"text": "Lower your price.", "check": {"skill": "diplomacy", "dc": 14}, "success": "cheap", "failure": "no"},
##          {"text": "Goodbye.", "if": {...}, "do": [actions], "goto": "end"}]},
##      "work": {"speaker": "bram", "text": "Rats.", "goto": "greet"}}}
##
## A node without choices continues to its "goto" (or ends). "end" always ends the conversation.
## speaker = an entity/companion id (its name is shown) or any plain name; no speaker = narration.


static func run(game, data: Dictionary, dialogue_id: String, ctx: Dictionary) -> void:
	var nodes: Dictionary = data.get("nodes", {})
	var node_id := _start_node(game, data, ctx)
	var guard := 0
	while node_id != "" and node_id != "end" and guard < 500:
		guard += 1
		var node = nodes.get(node_id)
		if typeof(node) != TYPE_DICTIONARY:
			push_warning("Dialogue %s: missing node '%s'" % [dialogue_id, node_id])
			break
		if node.has("if") and not game.scripts.test(node["if"], ctx):
			node_id = node.get("else", "end")
			continue
		if node.has("text"):
			if node.get("speaker", "") != "":
				await game.speak(node.speaker, node.text, node.get("voice", ""))
			else:
				await game.narrate(node.text, node.get("voice", ""))
		if node.has("do"):
			await game.scripts.run(node["do"], ctx)
		if node.has("check"):
			var passed: bool = await GM.check(game, node.check, ctx)
			node_id = node.get("success", "end") if passed else node.get("failure", "end")
			continue
		var choices: Array = []
		for ch in node.get("choices", []):
			if not ch.has("if") or game.scripts.test(ch["if"], ctx):
				choices.append(ch)
		if choices.is_empty():
			node_id = node.get("goto", "end")
			continue
		var shown: Array = []
		for ch in choices:
			shown.append({"text": game.fmt(ch.text), "tag": GM.check_tag(game, ch.get("check"))})
		var picked: Dictionary = choices[await game.io.choose(shown)]
		game.journal("choice", game.fmt(picked.text))
		if picked.has("do"):
			await game.scripts.run(picked["do"], ctx)
		if picked.has("check"):
			var ok: bool = await GM.check(game, picked.check, ctx)
			node_id = picked.get("success", picked.get("goto", "end")) if ok else picked.get("failure", picked.get("goto", "end"))
		else:
			node_id = picked.get("goto", "end")


static func _start_node(game, data: Dictionary, ctx: Dictionary) -> String:
	var start = data.get("start", "start")
	if typeof(start) == TYPE_STRING:
		return start
	for option in start:
		if not option.has("if") or game.scripts.test(option["if"], ctx):
			return option.get("node", "end")
	return "end"


## Built-in conversation for companions that have no dialogue file of their own, and for party
## members you click on while exploring: ask them to join, wait at camp, or take the lead.
static func companion_default(game, char_id: String) -> Dictionary:
	var comp: Dictionary = game.campaign.get("companions", {}).get(char_id, {})
	var in_party: bool = char_id in game.state.party
	var name: String = comp.get("name", char_id)
	var choices: Array = []
	if in_party:
		choices.append({"text": "Take the lead for a while.", "do": [{"op": "party.lead", "id": char_id}], "goto": "end"})
		if game.campaign.has("camp"):
			choices.append({"text": "Wait for me at camp.", "do": [{"op": "party.remove", "id": char_id}], "goto": "end"})
	else:
		choices.append({"text": "Come with me.", "if": {"partyFull": false}, "do": [{"op": "party.add", "id": char_id}], "goto": "end"})
		choices.append({"text": "(The party is full.)", "if": {"partyFull": true}, "goto": "end"})
	choices.append({"text": "Never mind.", "goto": "end"})
	return {"start": "talk", "nodes": {"talk": {"speaker": char_id, "text": comp.get("greeting", "What do you need?"), "choices": choices}}}
