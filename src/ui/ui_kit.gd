class_name UiKit
extends RefCounted
## Shared look of the interface: colours, the Theme, and small helpers to build controls in code.
## The whole UI is built in GDScript (no .tscn editing needed) so it can be changed with a text editor.

const BG := Color("#100e15")
const PANEL := Color("#1b1823")
const PANEL_2 := Color("#262230")
const PANEL_3 := Color("#322c3f")
const BORDER := Color("#4a4258")
const GOLD := Color("#d9b45a")
const TEXT := Color("#e6dfd0")
const DIM := Color("#9a93a4")
const RED := Color("#d0554e")
const GREEN := Color("#74c26e")
const BLUE := Color("#6aa6e0")
const PURPLE := Color("#b08ae0")


static func box(bg: Color, border: Color = BORDER, bw := 1, radius := 5, pad_h := 8, pad_v := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 1, 6, 8, 8))
	t.set_stylebox("panel", "Panel", box(PANEL, BORDER, 1, 6))
	t.set_stylebox("normal", "Button", box(PANEL_2, BORDER, 1, 4, 10, 4))
	t.set_stylebox("hover", "Button", box(PANEL_3, GOLD, 1, 4, 10, 4))
	t.set_stylebox("pressed", "Button", box(PANEL_3.lightened(0.08), GOLD, 1, 4, 10, 4))
	t.set_stylebox("disabled", "Button", box(PANEL, BORDER.darkened(0.3), 1, 4, 10, 4))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD.darkened(0.2), 1, 4, 10, 4))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", DIM.darkened(0.3))
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(state, "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 4, 1))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	t.set_color("font_pressed_color", "CheckBox", GOLD)
	t.set_color("font_hover_pressed_color", "CheckBox", GOLD)
	t.set_color("font_disabled_color", "CheckBox", DIM.darkened(0.35))
	t.set_stylebox("normal", "OptionButton", box(PANEL_2, BORDER, 1, 4, 10, 4))
	t.set_stylebox("hover", "OptionButton", box(PANEL_3, GOLD, 1, 4, 10, 4))
	t.set_stylebox("pressed", "OptionButton", box(PANEL_3, GOLD, 1, 4, 10, 4))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 10, 4))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "LineEdit", box(BG, BORDER, 1, 4, 8, 4))
	t.set_stylebox("focus", "LineEdit", box(BG, GOLD, 1, 4, 8, 4))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_2, GOLD.darkened(0.3), 1, 4, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(PANEL_3, PANEL_3, 0, 2, 4, 2))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("panel", "TooltipPanel", box(BG, GOLD.darkened(0.3), 1, 4, 8, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_stylebox("scroll", "VScrollBar", box(BG, BG, 0, 3, 3, 0))
	t.set_stylebox("grabber", "VScrollBar", box(BORDER, BORDER, 0, 3, 3, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD.darkened(0.3), BORDER, 0, 3, 3, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, BORDER, 0, 3, 3, 0))
	return t


static func label(text: String, size := 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## A scrolling BBCode text area. Connect meta_clicked to handle [url=...] links.
static func rich(font_size := 15) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = true
	r.selection_enabled = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_font_size_override("bold_font_size", font_size)
	r.add_theme_font_size_override("italics_font_size", font_size)
	r.add_theme_font_size_override("bold_italics_font_size", font_size)
	r.add_theme_constant_override("line_separation", 3)
	return r


static func hbox(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func panel(bg: Color = PANEL, border: Color = BORDER, pad := 8) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 1, 6, pad, pad))
	return p


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## BBCode colour tag helper: UiKit.c("text", UiKit.GOLD)
static func c(text, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), str(text)]


## Escapes "[" so story text can never break the BBCode of a RichTextLabel.
static func esc(text) -> String:
	return str(text).replace("[", "[lb]")


## A row of toggle buttons that work like tabs. Returns the HBoxContainer; on_pick(name) is called.
static func tabs(names: Array, on_pick: Callable, selected := "") -> HBoxContainer:
	var row := hbox(4)
	var group := ButtonGroup.new()
	for n in names:
		var b := Button.new()
		b.text = n
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = n == (selected if selected != "" else names[0])
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): on_pick.call(n))
		row.add_child(b)
	return row


## A thin horizontal progress bar drawn with two ColorRects (used for HP and XP).
static func bar(value: float, max_value: float, fill: Color, height := 10) -> Control:
	var back := ColorRect.new()
	back.color = BG
	back.custom_minimum_size = Vector2(40, height)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var front := ColorRect.new()
	front.color = fill
	front.anchor_right = clampf(value / maxf(1.0, max_value), 0.0, 1.0)
	front.anchor_bottom = 1.0
	back.add_child(front)
	return back


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()
