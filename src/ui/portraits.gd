class_name Portraits
extends RefCounted
## Finds the picture to show for a character.
## A painted portrait (campaigns/<id>/portraits/<character id>.png|jpg|webp, see docs/VOICE.md
## "Portraits") is used when it exists; otherwise the pixel sprite's idle frame.
##   Portraits.apply(texture_rect, game, character_or_id)     # sets texture + the right filtering

const EXTS := ["png", "jpg", "jpeg", "webp"]

static var _cache: Dictionary = {}


## The painted portrait for an id, or null.
static func painted(campaign_dir: String, id: String) -> Texture2D:
	if campaign_dir == "" or id == "":
		return null
	var key := campaign_dir + "|" + id
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	for ext in EXTS:
		var path := "%s/portraits/%s.%s" % [campaign_dir, id, ext]
		# Files inside the project are imported by Godot (./check.sh or the editor does it; the result is
		# the `<file>.import` sidecar). Loading the imported texture also works in an exported build,
		# where the raw image file no longer exists.
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				tex = res
				break
		# Not imported (a file dropped in while the game runs, or a campaign outside res://): read it raw.
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null:
				if img.get_width() > 512:
					img.resize(512, int(512.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
				break
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


## Sets `rect` to show the character: `who` is a character Dictionary (roster entry / companion spec) or an id.
static func apply(rect: TextureRect, game, who) -> void:
	var id := ""
	var spec: Dictionary = {}
	if typeof(who) == TYPE_DICTIONARY:
		spec = who
		id = str(who.get("id", ""))
	else:
		id = str(who)
		spec = game.state.get("roster", {}).get(id, game.campaign.get("companions", {}).get(id, {}))
	var tex := painted(game.campaign.get("dir", ""), id)
	if tex != null:
		rect.texture = tex
		# portraits are shown much smaller than they are painted: mipmaps keep them smooth
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		return
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if spec.has("race") and spec.has("cls"):
		rect.texture = SpriteFactory.portrait(game.world.sprite_for_spec(spec))
	else:
		var t: Dictionary = game.world.template(id) if game.campaign.has("entities") else {}
		var sprite: Dictionary = t.get("sprite", {})
		if sprite.is_empty() and t.get("kind", "") == "monster":
			sprite = game.db.monsters.get(t.get("monster", id), {}).get("sprite", {})
		rect.texture = SpriteFactory.portrait(sprite) if not sprite.is_empty() else null
