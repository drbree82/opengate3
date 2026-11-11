class_name Modal
extends Control
## Base class for full-screen overlays (title screen, character builder, menus, shop, level-up).
## It dims the game behind it and centres a panel. Subclasses call build_frame() and then add
## their controls to `content`. Close with close(); `closed` fires so callers can await it.

signal closed

var content: VBoxContainer
var heading: Label
var frame: PanelContainer
## false = Esc does not close it (title screen, game over)
var escapable := true


func build_frame(title: String, min_size: Vector2, dim := 0.72) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, dim)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	frame = UiKit.panel(UiKit.PANEL, UiKit.GOLD.darkened(0.35), 18)
	frame.custom_minimum_size = min_size
	centre.add_child(frame)
	content = UiKit.vbox(10)
	frame.add_child(content)
	if title != "":
		heading = UiKit.label(title, 26, UiKit.GOLD)
		content.add_child(heading)


func close() -> void:
	closed.emit()
	queue_free()


## A scrolling column, handy for long lists inside a modal.
static func scroll_list(min_size: Vector2) -> Array:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = min_size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return [sc, v]
