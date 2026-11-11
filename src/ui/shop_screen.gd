class_name ShopScreen
extends Modal
## Buying and selling, opened by the "shop.open" script op. Shops live in a campaign's shops.json:
##   "smith": {"name": "Tova's Forge", "greeting": "...", "stock": [{"id": "longsword"}, {"id": "chain_shirt", "price": 90}]}
## Price defaults to the item's "cost"; the shop buys anything with a cost for half of it.

var main
var game: Game
var shop: Dictionary = {}
var stock_box: VBoxContainer
var pack_box: VBoxContainer
var gold_label: Label


func setup(main_node, shop_id: String) -> void:
	main = main_node
	game = main.game
	shop = game.campaign.get("shops", {}).get(shop_id, {"name": "Shop", "stock": []})
	build_frame(shop.get("name", "Shop"), Vector2(900, 560))
	if shop.get("greeting", "") != "":
		content.add_child(UiKit.label(shop.greeting, 15, UiKit.DIM))
	gold_label = UiKit.label("", 16, UiKit.GOLD)
	content.add_child(gold_label)
	var cols := UiKit.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	for side in ["For sale", "Your pack"]:
		var v := UiKit.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UiKit.label(side, 15, UiKit.DIM))
		var sl := Modal.scroll_list(Vector2(400, 380))
		v.add_child(sl[0])
		if side == "For sale":
			stock_box = sl[1]
		else:
			pack_box = sl[1]
		cols.add_child(v)
	content.add_child(UiKit.button("Done", close))
	_draw()


func _price(entry: Dictionary) -> int:
	return int(entry.get("price", game.db.items.get(entry.id, {}).get("cost", 1)))


func _draw() -> void:
	gold_label.text = "Your gold: %d gp" % int(game.state.gold)
	UiKit.clear(stock_box)
	for entry in shop.get("stock", []):
		var item: Dictionary = game.db.items.get(entry.id, {})
		if item.is_empty():
			continue
		var price := _price(entry)
		var b := UiKit.button("%s   -   %d gp" % [item.name, price], _buy.bind(entry), SheetPanel._item_summary(item))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = int(game.state.gold) < price
		stock_box.add_child(b)
	UiKit.clear(pack_box)
	for it in game.state.inventory:
		var item: Dictionary = game.db.items.get(it.id, {})
		var value := int(item.get("cost", 0)) / 2
		if value <= 0 or item.get("type", "") == "quest":
			pack_box.add_child(UiKit.label("   %s x%d" % [item.get("name", it.id), int(it.qty)], 14, UiKit.DIM))
			continue
		var b := UiKit.button("%s x%d   -   sell for %d gp" % [item.name, int(it.qty), value], _sell.bind(str(it.id), value))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pack_box.add_child(b)


func _buy(entry: Dictionary) -> void:
	var price := _price(entry)
	if int(game.state.gold) < price:
		return
	game.state.gold = int(game.state.gold) - price
	game.add_item(entry.id, 1)
	game.io.sfx("coin")
	game.journal("system", "Bought %s for %d gold." % [game.db.items[entry.id].name, price])
	_draw()


func _sell(item_id: String, value: int) -> void:
	if game.remove_item(item_id, 1):
		game.state.gold = int(game.state.gold) + value
		game.io.sfx("coin")
		game.journal("system", "Sold %s for %d gold." % [game.db.items[item_id].name, value])
		game.state_changed.emit()
	_draw()
