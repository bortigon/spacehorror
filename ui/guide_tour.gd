class_name GuideTour
extends MapTour
## GUIDED WALKTHROUGH for things that are not on the map (the inventory tutorial). Same look and
## behaviour as the map walkthrough (ui/map_tour.gd): dim everything except the target, a pulsing
## bracket + outline, one tip in a small panel with a CONTINUE button. The target is any rectangle on
## screen, given as a Callable (global coordinates) so it can follow a window that is still sliding.
## Used by templates/authored_scene.gd ("tutorial" screens). Tutorials are exempt from the no-hints rule.

var rect_cb: Callable


func _init() -> void:
	super()
	name = "GuideTour"
	visible = false


## n = 0-based step of `count`. rect_cb() -> Rect2 in global coordinates (Rect2() = no highlight).
func show_step(n: int, count: int, text: String, p_rect_cb: Callable) -> void:
	rect_cb = p_rect_cb
	step = n
	total = count
	target = "rect"
	header_label.text = "TIP %d/%d" % [n + 1, count]
	text_label.text = text
	_t = 0.0
	show()
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


func _draw() -> void:
	var hole := hole_rect()
	var full := Rect2(Vector2.ZERO, size)
	if hole.size == Vector2.ZERO:
		draw_rect(full, DIM)
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
