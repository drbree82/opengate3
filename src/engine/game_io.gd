class_name GameIO
extends RefCounted
## Everything the game engine needs from "the outside world" (screen, speakers, the player).
## The engine only ever talks to the player through game.io, so it can run without any UI:
##   - This base class is the HEADLESS implementation: nothing is shown, waits are instant and
##     choices are picked automatically. Tests and tools use it.
##   - src/ui/ui_io.gd extends it with the real windowed implementation.
## When you add a new kind of player interaction, add a method here first (with a headless
## default), then override it in ui_io.gd.

var game
## How choices are answered when there is no player: "random", "first", or a Callable(choices) -> int.
var policy = "random"
var choice_log: Array = []


## A line of story text was added to the journal (speech or narration). May wait for a voice clip.
func say(entry: Dictionary) -> void:
	pass


## Shows a list of choices and returns the index picked. choices: [{text, tag?, disabled?}]
func choose(choices: Array) -> int:
	var enabled: Array = []
	for i in choices.size():
		if not choices[i].get("disabled", false):
			enabled.append(i)
	if enabled.is_empty():
		return 0
	var pick: int = enabled[0]
	if typeof(policy) == TYPE_CALLABLE:
		pick = policy.call(choices)
	elif policy == "random":
		pick = enabled[game.rng.range_i(0, enabled.size() - 1)]
	choice_log.append(choices[pick].get("text", ""))
	return pick


## Animates a roll in the dice tray. `quick` = short animation (enemy rolls, repeated rolls).
func show_roll(result: Dictionary, quick := false) -> void:
	pass


func delay(seconds: float) -> void:
	pass


func fade(to_black: bool, seconds: float) -> void:
	pass


## Big location / event text across the 3D view.
func banner(text: String, sub := "") -> void:
	pass


## Small text floating up from an entity ("-7", "Miss", "Dazed").  kind: damage|heal|miss|info|crit
func float_text(ent, text: String, kind := "info") -> void:
	pass


## Cutscene line at the bottom of the view. Waits for the voice clip or a reading pause.
func subtitle(speaker: String, text: String, voice := "") -> void:
	pass


func letterbox(on: bool) -> void:
	pass


func shake(seconds: float) -> void:
	pass


func sfx(sound: String) -> void:
	pass


func music(track: String) -> void:
	pass


## Spell / projectile flash from one entity to another entity or map position.
func spell_fx(from_ent, to, color: String) -> void:
	pass


func title_card(text: String, sub: String, seconds: float) -> void:
	pass


func open_shop(shop_id: String) -> void:
	pass


## The character has enough XP: let the player make level-up choices. Headless = automatic.
func level_up(character: Dictionary) -> void:
	game.auto_level(character)


func game_over(victory: bool, text: String) -> void:
	pass
