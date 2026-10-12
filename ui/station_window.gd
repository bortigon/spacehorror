extends "res://ui/holo_window.gd"
## STATION WINDOW: a hologram window for a thing in the room that has a picture and a few options,
## not an item grid (the COFFEE POT in the ready room). Same look, same turn-on / turn-off as the
## container window. The owner supplies a `provider` Callable returning the current state:
##   {"text": "description / status", "options": [{"id": "brew", "label": "Brew a Pot (1 hr)"}],
##    "pot": "empty" | "full", "disabled": false}
## and handles `option_pressed(station_id, option_id)`; call refresh() after the state changes.
## An act in a scene is `{"station": "coffee", "title": "COFFEE POT", "text": "..."}`; the options are
## code-defined (see PdaScreen coffee_* helpers), so the Scene Writer does not edit them.

signal option_pressed(station_id: String, option_id: String)
signal exit_requested

var station_id := ""
var title := ""
var provider: Callable
var info: Dictionary = {}   # what the provider returned last
var title_label: Label
var picture: Control
var text_label: Label
var actions_row: HBoxContainer
var exit_button: Button
var option_buttons: Array[Button] = []
var _anim := 0.0


func _init() -> void:
	panel_size = Vector2(300, 292)
	build()


func _build_body() -> void:
	body.add_child(make_panel_bg())
	title_label = make_label("", 15, true)
	title_label.position = Vector2(12, 8)
	title_label.size = Vector2(panel_size.x - 24.0, 22)
	title_label.clip_text = true
	body.add_child(title_label)
	picture = make_grid_bg(Rect2(12, 36, panel_size.x - 24.0, 136))
	picture.name = "Picture"
	picture.draw.connect(_draw_picture)
	body.add_child(picture)
	text_label = make_label("", 10, false)
	text_label.position = Vector2(12, 178)
	text_label.size = Vector2(panel_size.x - 24.0, 44)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.clip_text = true
	body.add_child(text_label)
	make_notice(Rect2(12, 224, panel_size.x - 24.0, 14))
	actions_row = HBoxContainer.new()
	actions_row.name = "Actions"
	actions_row.position = Vector2(12, 250)
	actions_row.size = Vector2(panel_size.x - 120.0, 32)
	actions_row.add_theme_constant_override("separation", 6)
	actions_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(actions_row)
	exit_button = make_button("EXIT", Vector2(84, 30))
	exit_button.name = "Exit"
	exit_button.position = Vector2(panel_size.x - 94.0, 250)
	exit_button.size = Vector2(84, 30)
	exit_button.pressed.connect(func() -> void:
		if is_interactive():
			exit_requested.emit())
	body.add_child(exit_button)


func configure(p_id: String, spec: Dictionary, p_provider: Callable) -> void:
	station_id = p_id
	title = str(spec.get("title", "")).strip_edges()
	if title == "":
		title = p_id.to_upper()
	title_label.text = title.to_upper()
	provider = p_provider
	refresh()


func _on_opening() -> void:
	refresh()


## Re-reads the owner's state: text, picture and the option buttons.
func refresh() -> void:
	info = provider.call() if provider.is_valid() else {}
	text_label.text = str(info.get("text", ""))
	for b in option_buttons:
		if is_instance_valid(b):
			b.queue_free()
	option_buttons.clear()
	for o: Variant in info.get("options", []):
		if not (o is Dictionary):
			continue
		var oid := str((o as Dictionary).get("id", ""))
		var b := make_button(str((o as Dictionary).get("label", oid)), Vector2(0, 30))
		b.name = "Option_" + oid
		b.pressed.connect(_on_option.bind(oid))
		actions_row.add_child(b)
		option_buttons.append(b)
	picture.queue_redraw()


func option_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for o: Variant in info.get("options", []):
		out.append(str((o as Dictionary).get("id", "")))
	return out


func option_button(oid: String) -> Button:
	for b in option_buttons:
		if is_instance_valid(b) and b.name == "Option_" + oid:
			return b
	return null


func do_option(oid: String) -> void:
	_on_option(oid)


func _on_option(oid: String) -> void:
	if is_interactive():
		option_pressed.emit(station_id, oid)


func _process(delta: float) -> void:
	super(delta)
	if info.get("pot", "empty") == "full" and visible:
		_anim += delta
		picture.queue_redraw()


# ---------------------------------------------------------------- the picture (placeholder art)

func _draw_picture() -> void:
	var r := Rect2(Vector2.ZERO, picture.size)
	var cx := r.size.x * 0.5
	var base_y := r.size.y - 16.0
	var steel := Color(0.62, 0.78, 0.68, 1.0)
	var steel_dark := Color(0.30, 0.48, 0.40, 1.0)
	var glass := Color(0.78, 1.0, 0.88, 0.22)
	var full: bool = info.get("pot", "empty") == "full"
	var off: bool = bool(info.get("disabled", false))
	# base plate + hot plate
	picture.draw_rect(Rect2(cx - 52, base_y, 104, 10), steel_dark)
	picture.draw_rect(Rect2(cx - 52, base_y, 104, 3), steel)
	var plate_col := Color(0.95, 0.55, 0.25, 0.9) if (full and not off) else Color(0.20, 0.30, 0.25, 1.0)
	picture.draw_rect(Rect2(cx - 38, base_y - 4, 76, 4), plate_col)
	# back column + brew head
	picture.draw_rect(Rect2(cx + 30, 18, 18, base_y - 18), steel_dark)
	picture.draw_rect(Rect2(cx - 40, 18, 88, 16), steel)
	picture.draw_rect(Rect2(cx - 40, 30, 88, 4), steel_dark)
	picture.draw_rect(Rect2(cx - 6, 34, 12, 6), steel_dark)   # nozzle
	# carafe (trapezoid), coffee level, handle, lid
	var top_y := 52.0
	var carafe := PackedVector2Array([Vector2(cx - 26, top_y), Vector2(cx + 26, top_y),
		Vector2(cx + 32, base_y - 6), Vector2(cx - 32, base_y - 6)])
	picture.draw_colored_polygon(carafe, glass)
	if full:
		var lvl := top_y + 26.0
		var t := (lvl - top_y) / (base_y - 6.0 - top_y)
		var wl := lerpf(26.0, 32.0, t)
		picture.draw_colored_polygon(PackedVector2Array([Vector2(cx - wl, lvl), Vector2(cx + wl, lvl),
			Vector2(cx + 32, base_y - 6), Vector2(cx - 32, base_y - 6)]), Color(0.22, 0.10, 0.04, 0.95))
	picture.draw_polyline(PackedVector2Array([carafe[0], carafe[3], carafe[2], carafe[1]]), Color(0.92, 1.0, 0.94, 0.9), 2.0, true)
	picture.draw_arc(Vector2(cx + 33, 82), 14.0, -PI * 0.5, PI * 0.5, 14, Color(0.92, 1.0, 0.94, 0.9), 3.0, true)
	picture.draw_rect(Rect2(cx - 29, top_y - 5, 58, 5), steel)
	if full and not off:
		for k in 3:
			var ph := _anim * 1.4 + float(k) * 2.1
			var pts := PackedVector2Array()
			for j in 9:
				var y := top_y - 8.0 - float(j) * 3.6
				pts.append(Vector2(cx - 12.0 + float(k) * 12.0 + sin(ph + float(j) * 0.7) * 3.0, y))
			picture.draw_polyline(pts, Color(1, 1, 1, 0.45 - 0.04 * float(k)), 1.5, true)
	if off:
		picture.draw_line(Vector2(cx - 50, 14), Vector2(cx + 50, base_y), Color(0.9, 0.2, 0.15, 0.8), 3.0)
