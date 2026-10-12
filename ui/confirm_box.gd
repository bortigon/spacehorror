extends Control
## YES / NO PROMPT: a dimmed screen with one small panel in the game's button style.
## PdaScreen.ask_confirm(text, on_yes, on_no) creates it. Mouse only (plus Esc = No), no key hints.

signal answered(yes: bool)

const MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"
const PANEL_W := 380.0

var panel: PanelContainer
var text_label: Label
var yes_button: Button
var no_button: Button
var _on_yes: Callable
var _on_no: Callable


func _init() -> void:
	name = "ConfirmBox"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0.01, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.name = "ConfirmPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.045, 0.032, 0.98)
	sb.border_color = Color(0.93, 0.62, 0.3, 0.95)    # amber: this is a warning
	sb.set_border_width_all(1)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	text_label = Label.new()
	text_label.name = "ConfirmText"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(PANEL_W - 32.0, 0)
	if ResourceLoader.exists(MONO):
		text_label.add_theme_font_override("font", load(MONO))
	text_label.add_theme_font_size_override("font_size", 15)
	text_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.5))
	col.add_child(text_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	yes_button = _button("YES", "Yes")
	no_button = _button("NO", "No")
	yes_button.pressed.connect(answer.bind(true))
	no_button.pressed.connect(answer.bind(false))
	row.add_child(yes_button)
	row.add_child(no_button)


func _button(text: String, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(120, 38)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	return b


func ask(text: String, on_yes: Callable, on_no := Callable()) -> void:
	text_label.text = text
	_on_yes = on_yes
	_on_no = on_no
	show()


## Closes the box and runs the matching callback (also used by Esc = No and by tests).
func answer(yes: bool) -> void:
	if not visible:
		return
	hide()
	var cb := _on_yes if yes else _on_no
	_on_yes = Callable()
	_on_no = Callable()
	answered.emit(yes)
	if cb.is_valid():
		cb.call()


## Screen rectangle of `sub` inside the text (e.g. "1 hr"): the tutorial highlights it. The text is
## set in a monospace font, so the wrapping is replayed here: greedy word wrap at the label width.
func highlight_rect(sub: String) -> Rect2:
	var text := text_label.text
	var at := text.find(sub)
	if at < 0 or not is_inside_tree():
		return Rect2()
	var font: Font = text_label.get_theme_font("font")
	var fs := text_label.get_theme_font_size("font_size")
	var width := maxf(text_label.size.x, PANEL_W - 32.0)
	var lines: Array = []
	var cur := ""
	for w in text.split(" "):
		var trial: String = w if cur == "" else cur + " " + w
		if cur != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			lines.append(cur)
			cur = w
		else:
			cur = trial
	lines.append(cur)
	var ln := 0
	var offset := 0
	var before := ""
	for k in lines.size():
		var l: String = lines[k]
		if at < offset + l.length() + 1:
			ln = k
			before = l.substr(0, maxi(0, at - offset))
			break
		offset += l.length() + 1
	var x := font.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w3 := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return Rect2(text_label.global_position + Vector2(x, float(ln) * font.get_height(fs)), Vector2(w3, font.get_height(fs)))
