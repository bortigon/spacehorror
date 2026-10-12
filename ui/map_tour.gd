class_name MapTour
extends Control
## MAP WALKTHROUGH ("HIGHLIGHT + TIP"): one tip at a time over the full ship map.
## Dims everything except the target, draws a pulsing bracket + outline around it and shows
## the tip in a small panel next to it with a CONTINUE button (game button style).
## Blocks map clicks while it is up. Used by templates/authored_scene.gd ("map_tour" ending).
##
## Targets:  map            the whole ship + the yellow you-are-here dot
##           room:<id>      one room (e.g. room:stasis_3)
##           door:<a>|<b>   one door / passage (e.g. door:ready_room|stbd_hold)
##           rooms          every room (the clickable rooms)

signal continued

const DIM := Color(0, 0, 0, 0.62)
const HILITE := Color(0.95, 0.76, 0.4, 1)
const PANEL_W := 290.0
const GAP := 16.0
const EDGE := 10.0
const HOLE_PAD := 10.0
const TEXT_COLOR := Color(0.56, 0.8, 0.6)
const MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"
const CONTINUE_LABEL := "CONTINUE"

var map_view: ShipMapView
var target := "map"
var step := 0            # 0-based
var total := 1
var panel: PanelContainer
var header_label: Label
var text_label: Label
var continue_button: Button
var _t := 0.0


func _init() -> void:
	name = "MapTour"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # the map can't be clicked during a tip
	panel = PanelContainer.new()
	panel.name = "TipPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.045, 0.032, 0.97)
	sb.border_color = Color(0.49, 0.85, 0.5, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	header_label = Label.new()
	header_label.name = "TipHeader"
	header_label.theme_type_variation = &"OsLabelDim"
	col.add_child(header_label)
	text_label = Label.new()
	text_label.name = "TipText"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	if ResourceLoader.exists(MONO):
		text_label.add_theme_font_override("font", load(MONO))
	text_label.add_theme_font_size_override("font_size", 14)
	text_label.add_theme_color_override("font_color", TEXT_COLOR)
	col.add_child(text_label)
	continue_button = Button.new()
	continue_button.name = "Continue"
	continue_button.text = CONTINUE_LABEL
	continue_button.custom_minimum_size = Vector2(220, 38)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	continue_button.focus_mode = Control.FOCUS_NONE
	continue_button.pressed.connect(press)
	col.add_child(continue_button)


## n = 0-based tip index, of `count` tips.
func show_tip(view: ShipMapView, n: int, count: int, text: String, tgt: String) -> void:
	map_view = view
	step = n
	total = count
	target = tgt.strip_edges() if tgt.strip_edges() != "" else "map"
	header_label.text = "TIP %d/%d" % [n + 1, count]
	text_label.text = text
	_t = 0.0
	_layout()
	queue_redraw()


func press() -> void:
	if visible:
		continued.emit()


func _process(delta: float) -> void:
	_t += delta
	_layout()
	queue_redraw()


## Target bounds in the map view's local coordinates.
func target_rect_in_map() -> Rect2:
	if map_view == null:
		return Rect2()
	if target == "map" or target == "rooms":
		return map_view.ship_rect_local()
	if target.begins_with("room:"):
		return map_view.room_rect_local(target.substr(5))
	if target.begins_with("door:"):
		return map_view.door_rect_local(target.substr(5))
	return map_view.ship_rect_local()


## The un-dimmed hole, in this control's coordinates.
func hole_rect() -> Rect2:
	var r := target_rect_in_map()
	if r.size == Vector2.ZERO or map_view == null:
		return Rect2()
	var pad := HOLE_PAD if not target.begins_with("door:") else 6.0
	return Rect2(r.position + map_view.global_position - global_position, r.size).grow(pad)


func _layout() -> void:
	var hole := hole_rect()
	var ps := panel.get_combined_minimum_size()
	ps.x = maxf(ps.x, PANEL_W)
	panel.size = ps
	var area := Rect2(Vector2.ZERO, size)
	if hole.size == Vector2.ZERO:
		panel.position = (area.size - ps) * 0.5
		return
	var x := hole.end.x + GAP
	if x + ps.x > area.end.x - EDGE:
		x = hole.position.x - GAP - ps.x
		if x < EDGE:
			x = area.end.x - EDGE - ps.x
	var y := clampf(hole.get_center().y - ps.y * 0.5, EDGE + 40.0, area.end.y - EDGE - ps.y - 30.0)
	panel.position = Vector2(x, y).round()


func _draw() -> void:
	var hole := hole_rect()
	var full := Rect2(Vector2.ZERO, size)
	if hole.size == Vector2.ZERO:
		draw_rect(full, DIM)
		return
	hole = hole.intersection(full)
	# dim everything except the hole
	draw_rect(Rect2(0, 0, size.x, hole.position.y), DIM)
	draw_rect(Rect2(0, hole.end.y, size.x, size.y - hole.end.y), DIM)
	draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), DIM)
	draw_rect(Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y), DIM)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var col := Color(HILITE, 0.55 + 0.45 * pulse)
	# bracket corners, breathing outwards a little
	var br := hole.grow(2.0 + 2.0 * pulse)
	var arm := clampf(minf(br.size.x, br.size.y) * 0.3, 7.0, 22.0)
	for c: Vector2 in [br.position, Vector2(br.end.x, br.position.y), br.end, Vector2(br.position.x, br.end.y)]:
		var sx := 1.0 if c.x <= br.get_center().x else -1.0
		var sy := 1.0 if c.y <= br.get_center().y else -1.0
		draw_line(c, c + Vector2(arm * sx, 0), col, 2.0, true)
		draw_line(c, c + Vector2(0, arm * sy), col, 2.0, true)
	# the target itself
	var off := map_view.global_position - global_position
	var outline := Color(HILITE, 0.35 + 0.5 * pulse)
	if target.begins_with("room:"):
		_draw_poly(map_view.room_poly_local(target.substr(5)), off, outline, 2.0)
	elif target == "rooms":
		for id in (map_view.map_data.get("rooms", {}) as Dictionary):
			_draw_poly(map_view.room_poly_local(str(id)), off, outline, 1.5)
	elif target.begins_with("door:"):
		var dr := map_view.door_rect_local(target.substr(5))
		draw_rect(Rect2(dr.position + off, dr.size).grow(2.0), outline, false, 1.5)
	if target == "map":
		var you := map_view.you_pos_local()
		if you != Vector2.INF:
			draw_arc(you + off, 13.0 + 3.0 * pulse, 0.0, TAU, 32, col, 2.0, true)


func _draw_poly(pts: PackedVector2Array, off: Vector2, col: Color, w: float) -> void:
	if pts.size() < 3:
		return
	var closed := PackedVector2Array()
	for p in pts:
		closed.append(p + off)
	closed.append(pts[0] + off)
	draw_polyline(closed, col, w, true)
