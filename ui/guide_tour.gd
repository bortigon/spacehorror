class_name GuideTour
extends MapTour
## GUIDED WALKTHROUGH for things that are not on the map (the inventory tutorial). Same look and
## behaviour as the map walkthrough (ui/map_tour.gd): dim everything except the target, a pulsing
## bracket + outline, one tip in a small panel with a CONTINUE button. The target is any rectangle on
## screen, given as a Callable (global coordinates) so it can follow a window that is still sliding.
## Used by templates/authored_scene.gd ("tutorial" screens). Tutorials are exempt from the no-hints rule.

var rect_cb: Callable
## Optional looping hint animation: anim_cb() -> {"from": Vector2, "to": Vector2, "item": id, "label": text}
## (global coordinates). A small ghost item icon slides from -> to with an arrow, again and again.
var anim_cb: Callable
const Icons := preload("res://ui/item_icons.gd")
const ANIM_LOOP := 1.8
## A "click it" tip (TIP: This is your MAP. Click on it to zoom in.): no CONTINUE button, Space/Enter
## do nothing, a click inside the highlighted hole continues.
var click_only := false


func _init() -> void:
	super()
	name = "GuideTour"
	visible = false


## n = 0-based step of `count`. rect_cb() -> Rect2 in global coordinates (Rect2() = no highlight).
func show_step(n: int, count: int, text: String, p_rect_cb: Callable, p_anim_cb := Callable()) -> void:
	rect_cb = p_rect_cb
	anim_cb = p_anim_cb
	step = n
	total = count
	target = "rect"
	header_label.text = "TIP %d/%d" % [n + 1, count]
	text_label.text = text
	_t = 0.0
	show()
	continue_button.visible = not click_only
	_layout()
	queue_redraw()


func target_rect_in_map() -> Rect2:
	return Rect2()


## The un-dimmed hole in this control's coordinates.
func hole_rect() -> Rect2:
	if not rect_cb.is_valid():
		return Rect2()
	var g: Rect2 = rect_cb.call()
	if g.size.x <= 1.0 or g.size.y <= 1.0:
		return Rect2()
	return Rect2(g.position - global_position, g.size).grow(HOLE_PAD * 0.6)


## The animation's current frame: {} when there is none.
func anim_frame() -> Dictionary:
	if not anim_cb.is_valid():
		return {}
	var a: Dictionary = anim_cb.call()
	if a.is_empty():
		return {}
	var u := fmod(_t, ANIM_LOOP) / ANIM_LOOP
	var k := clampf((u - 0.12) / 0.7, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var from: Vector2 = a["from"] - global_position
	var to: Vector2 = a["to"] - global_position
	var fr: Rect2 = a.get("frame", Rect2())
	if fr.size != Vector2.ZERO:
		fr.position -= global_position
	return {"frame": fr, "from": from, "to": to, "pos": from.lerp(to, k), "alpha": clampf(minf(u, 1.0 - u) * 8.0, 0.0, 1.0),
		"item": str(a.get("item", "")), "label": str(a.get("label", ""))}


const ANIM_PANEL_W := 470.0

func _layout() -> void:
	var wide := anim_cb.is_valid()
	panel.custom_minimum_size.x = ANIM_PANEL_W if wide else PANEL_W
	text_label.custom_minimum_size.x = (ANIM_PANEL_W if wide else PANEL_W) - 24.0
	super()
	if wide:
		# a tip with an animation sits low and wide (two lines), out of the way of what it shows
		panel.size = panel.get_combined_minimum_size()
		panel.position = Vector2(roundf((size.x - panel.size.x) * 0.5), roundf(size.y - panel.size.y - 8.0))


func _draw() -> void:
	var hole := hole_rect()
	var full := Rect2(Vector2.ZERO, size)
	if hole.size == Vector2.ZERO:
		draw_rect(full, DIM)
		_draw_anim()
		return
	hole = hole.intersection(full)
	draw_rect(Rect2(0, 0, size.x, hole.position.y), DIM)
	draw_rect(Rect2(0, hole.end.y, size.x, size.y - hole.end.y), DIM)
	draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), DIM)
	draw_rect(Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y), DIM)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var col := Color(HILITE, 0.55 + 0.45 * pulse)
	var br := hole.grow(2.0 + 2.0 * pulse)
	var arm := clampf(minf(br.size.x, br.size.y) * 0.3, 7.0, 22.0)
	for c: Vector2 in [br.position, Vector2(br.end.x, br.position.y), br.end, Vector2(br.position.x, br.end.y)]:
		var sx := 1.0 if c.x <= br.get_center().x else -1.0
		var sy := 1.0 if c.y <= br.get_center().y else -1.0
		draw_line(c, c + Vector2(arm * sx, 0), col, 2.0, true)
		draw_line(c, c + Vector2(0, arm * sy), col, 2.0, true)
	draw_rect(hole, Color(HILITE, 0.35 + 0.5 * pulse), false, 1.5)
	_draw_anim()


func _draw_anim() -> void:
	var f := anim_frame()
	if f.is_empty():
		return
	var from: Vector2 = f["from"]
	var to: Vector2 = f["to"]
	var col := Color(HILITE, 0.8)
	var fr: Rect2 = f.get("frame", Rect2())
	if fr.size != Vector2.ZERO:     # a ghost of the inventory window the item comes out of
		draw_rect(fr, Color(0.39, 0.72, 0.30, 0.18))
		draw_rect(fr, Color(0.80, 1.0, 0.78, 0.55), false, 1.5)
		if ResourceLoader.exists(MONO):
			draw_string(load(MONO), fr.position + Vector2(10, 20), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 1.0, 0.86, 0.8))
	# arrow from -> to
	draw_dashed_line(from, to, Color(HILITE, 0.55), 2.0, 7.0, true)
	var d := (to - from).normalized()
	if d != Vector2.ZERO:
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([to, to - d * 12.0 + n * 6.0, to - d * 12.0 - n * 6.0]), col)
	# the ghost item
	var a: float = f["alpha"]
	var box := Rect2(f["pos"] - Vector2(14, 14), Vector2(28, 28))
	draw_rect(box, Color(0.52, 0.86, 0.45, 0.85 * a))
	draw_rect(box, Color(0.82, 1.0, 0.78, a), false, 1.0)
	if not Icons.draw_icon(self, str(f["item"]), box.grow(-2.0), a):
		draw_rect(box.grow(-7.0), Color(0.82, 1.0, 0.78, 0.6 * a))
	if f["pos"].distance_to(to) < 1.0 and a > 0.05:    # at the end: the click that drops / uses it
		var u := fmod(_t, ANIM_LOOP) / ANIM_LOOP
		draw_arc(to, 6.0 + 26.0 * clampf((u - 0.82) / 0.18, 0.0, 1.0), 0.0, TAU, 24, Color(1, 1, 1, a), 2.0, true)
		if ResourceLoader.exists(MONO):
			draw_string(load(MONO), to + Vector2(-16, -22), "CLICK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, a))
	# the mouse pointer holding it
	var tip: Vector2 = f["pos"] + Vector2(6, 6)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(0, 14), tip + Vector2(4, 10), tip + Vector2(9, 10)]), Color(1, 1, 1, a))
	var lbl := str(f["label"])
	if lbl != "" and ResourceLoader.exists(MONO):
		draw_string(load(MONO), f["pos"] + Vector2(18, 26), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, a))


func press() -> void:
	if click_only:
		return       # only the click on the highlighted thing moves on
	super()


func _gui_input(event: InputEvent) -> void:
	if not click_only or not visible:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var h := hole_rect()
		if h.size != Vector2.ZERO and h.has_point((event as InputEventMouseButton).position):
			click_hole()
			accept_event()


## The highlighted thing was clicked (tests call this too).
func click_hole() -> void:
	if visible:
		continued.emit()
