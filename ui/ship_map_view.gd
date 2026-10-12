class_name ShipMapView
extends Control
## Draws the REC-7 vessel schematic from a map Dictionary (see data/vessel.gd).
## compact = minimap: fixed zoom centred on the current room, labels for explored rooms.
## full    = whole ship fitted to the rect, labels, hover readout, legend strip.

signal map_clicked
signal room_hovered(room_id: String)
## Full map only: left click on a room (click-to-move, see PdaScreen.map_try_move).
signal room_clicked(room_id: String)
## A padlock (or a door the host marked clickable) was clicked. key = "a|b" (see find_door).
signal door_clicked(key: String)
## A map marker (LOCKER / COFFEE POT label or a dropped item) was clicked.
signal marker_clicked(marker_id: String)

@export var compact := false
@export var show_legend := false
## Minimap zoom: screen pixels per schematic unit.
@export var compact_scale := 0.95
## false = display only (no hover, no click, mouse passes through), e.g. intro overlay.
@export var interactive := true

# ---- palette (phosphor CRT) ----
const COL_BG := Color(0.015, 0.03, 0.022, 0.94)
const COL_FRAME := Color(0.22, 0.38, 0.26, 1)
const COL_GRID := Color(0.2, 0.36, 0.24, 0.10)
const COL_EXPLORED_FILL := Color(0.16, 0.36, 0.2, 1)
const COL_EXPLORED_EDGE := Color(0.49, 0.85, 0.5, 1)
const COL_UNEXPLORED_FILL := Color(0.17, 0.19, 0.185, 1)
const COL_UNEXPLORED_EDGE := Color(0.36, 0.39, 0.38, 1)
const COL_LOCKED_FILL := Color(0.075, 0.075, 0.07, 1)
const COL_LOCKED_EDGE := Color(0.5, 0.33, 0.2, 1)
const COL_DOOR_OPEN := Color(0.62, 0.95, 0.6, 1)
const COL_DOOR_LOCKED := Color(0.95, 0.62, 0.25, 1)
const COL_YOU := Color(0.98, 0.9, 0.5, 1)
const COL_LABEL := Color(0.9, 0.98, 0.9, 1)
const COL_LABEL_DIM := Color(0.5, 0.6, 0.54, 1)
const COL_HOVER := Color(0.93, 0.72, 0.38, 1)
const COL_RESTRICTED := Color(0.92, 0.34, 0.26, 1)

## "restricted" rooms: red outline + this stamp. pop_stamp() animates it in (scale + fade + flash).
const STAMP_TEXT := "RESTRICTED"
const STAMP_POP := 0.45      # seconds: stamp scales 1.9 → 1 and fades in
const STAMP_FLASH := 0.9     # seconds: red flash over the room fades out

const LEGEND_H := 34.0
const LEGEND_W := 176.0

var map_data: Dictionary = {}
var hovered_id := ""
var _font_label: Font
var _font_mono: Font
var _xf := Transform2D.IDENTITY
var _t := 0.0
var _pops: Dictionary = {}   # room id → Time.get_ticks_msec() of its stamp pop
var _label_pops: Dictionary = {}   # room id → ticks: its name was just revealed (stamp-in like RESTRICTED)
var _unlocks: Dictionary = {}  # door key → Time.get_ticks_msec() of its unlock animation
var hover_marker := ""
var hover_door := ""

## Lock-opening animation: the lock shakes, then pops open, fades, and the open-door graphic remains.
const UNLOCK_SHAKE := 0.45
const UNLOCK_TIME := 0.9
## A padlock / marker is this much easier to hit than it is to see (px).
const HIT_GROW := 5.0
const DOT_R := 2.6
const COL_DOT := Color(0.88, 1.0, 0.82, 1.0)
const COL_DOT_RING := Color(0.02, 0.12, 0.05, 0.95)
const COL_MARKER := Color(0.42, 0.78, 0.38, 0.97)
const COL_MARKER_EDGE := Color(0.82, 1.0, 0.8, 1.0)
const COL_MARKER_COST := Color(0.98, 0.58, 0.16, 1.0)   # marker "cost": true (clicking it costs time)
const COL_MARKER_INK := Color(0.02, 0.12, 0.05, 1.0)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if compact and interactive else Control.CURSOR_ARROW
	_font_label = load("res://assets/fonts/Oxanium-SemiBold.ttf")
	_font_mono = load("res://assets/fonts/IBMPlexMono-SemiBold.ttf")


func set_map(data: Dictionary) -> void:
	map_data = data
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree() and (str(map_data.get("current", "")) != "" or not _pops.is_empty() or not _unlocks.is_empty() or not _label_pops.is_empty()):
		_t += delta
		queue_redraw()


## Animate a room's RESTRICTED stamp in (PdaScreen.map_restrict_room calls this).
func pop_stamp(id: String) -> void:
	_pops[id] = Time.get_ticks_msec()
	queue_redraw()


## Animate a room's NAME in, same stamp-in as RESTRICTED (scale 1.9 -> 1, fade, flash): a room
## unlocked with its keycard (AIR LOCK). PdaScreen._unlock_door calls this.
func pop_label(id: String) -> void:
	_label_pops[id] = Time.get_ticks_msec()
	queue_redraw()


func label_age(id: String) -> float:
	if not _label_pops.has(id):
		return 999.0
	return (Time.get_ticks_msec() - int(_label_pops[id])) / 1000.0


## Seconds since the room's stamp popped (large if it never did: fully shown).
func stamp_age(id: String) -> float:
	if not _pops.has(id):
		return 999.0
	return (Time.get_ticks_msec() - int(_pops[id])) / 1000.0


func room_restricted(id: String) -> bool:
	return bool(((map_data.get("rooms", {}) as Dictionary).get(id, {}) as Dictionary).get("restricted", false))


## Starts the lock-opening animation on door "a|b" (PdaScreen.map_unlock_with_key calls this).
func pop_unlock(key: String) -> void:
	_unlocks[_canon_key(key)] = Time.get_ticks_msec()
	queue_redraw()


## Seconds since the door's unlock animation started (999 if it never ran).
func unlock_age(key: String) -> float:
	var k := _canon_key(key)
	if not _unlocks.has(k):
		return 999.0
	return (Time.get_ticks_msec() - int(_unlocks[k])) / 1000.0


func unlocking(key: String) -> bool:
	return unlock_age(key) < UNLOCK_TIME


static func door_key(d: Dictionary) -> String:
	return "%s|%s" % [str(d.get("a", "")), str(d.get("b", ""))]


func _canon_key(key: String) -> String:
	var d := find_door(key)
	return door_key(d) if not d.is_empty() else key


## Doors that react to a click right now: locked ones, and the ones the host lists in "click_doors".
func _door_clickable(d: Dictionary) -> bool:
	if str(d.get("state", "open")) != "open":
		return true
	return door_key(d) in (map_data.get("click_doors", []) as Array)


## Which clickable door's lock / doorway is at this local point ("" if none).
func door_at(local_pos: Vector2) -> String:
	if size.x <= 0.0:
		return ""
	for d: Dictionary in map_data.get("doors", []):
		if not _door_visible(d) or not _door_clickable(d):
			continue
		if door_rect_local(door_key(d)).grow(HIT_GROW).has_point(local_pos):
			return door_key(d)
	return ""


func _door_visible(d: Dictionary) -> bool:
	var rooms: Dictionary = map_data.get("rooms", {})
	var sa := str((rooms.get(str(d.get("a", "")), {}) as Dictionary).get("state", "unexplored"))
	var sb := str((rooms.get(str(d.get("b", "")), {}) as Dictionary).get("state", "unexplored"))
	return sa == "explored" or sb == "explored" or bool(d.get("always_show", false)) or bool(d.get("known", false))


## ---- markers: small green labelled rectangles inside a room ("LOCKER", "COFFEE POT", "WINDOW") and
## dots with a name (dropped items).
## A marker is {id, room, label, rect: [x, y, w, h] as fractions of the room's bounding box, kind}.
func markers() -> Array:
	var out: Array = []
	var rooms: Dictionary = map_data.get("rooms", {})
	for m: Variant in map_data.get("markers", []):
		if m is Dictionary and str((rooms.get(str((m as Dictionary).get("room", "")), {}) as Dictionary).get("state", "")) == "explored":
			out.append(m)
	return out


func find_marker(id: String) -> Dictionary:
	for m: Dictionary in markers():
		if str(m.get("id", "")) == id:
			return m
	return {}


## Screen rect of a marker in this view's local coordinates (Rect2() if unknown / not visible).
func marker_rect_local(id: String) -> Rect2:
	var m := find_marker(id)
	if m.is_empty() or size.x <= 0.0:
		return Rect2()
	_update_xform()
	var room: Dictionary = (map_data.get("rooms", {}) as Dictionary).get(str(m.get("room", "")), {})
	var pts := PackedVector2Array()
	for p in room.get("poly", []):
		pts.append(p)
	var bb := _pts_rect(pts)
	var f: Array = m.get("rect", [0.0, 0.0, 0.2, 0.2])
	var tl := bb.position + Vector2(float(f[0]) * bb.size.x, float(f[1]) * bb.size.y)
	var br := tl + Vector2(float(f[2]) * bb.size.x, float(f[3]) * bb.size.y)
	var a := _xf * tl
	var b := _xf * br
	return Rect2(a, b - a)


## Dropped items ("drop", "pile") are a small DOT with the name beside it (like a city on a map), not a box.
func is_dot(m: Dictionary) -> bool:
	var k := str(m.get("kind", ""))
	return k == "drop" or k == "pile"


## Dot markers: the dot sits at the left of the marker cell, the name to its right.
func dot_center_local(id: String) -> Vector2:
	var r := marker_rect_local(id)
	return Vector2(r.position.x + DOT_R + 1.0, r.position.y + r.size.y * 0.5)


func dot_label_font_size(r: Rect2) -> int:
	return clampi(int(r.size.y * 0.62), 7, 11)


## The label of a dot marker as drawn (shortened with "." to fit its cell).
func dot_label(m: Dictionary, r: Rect2) -> String:
	var label := str(m.get("label", m.get("id", ""))).to_upper()
	var fs := dot_label_font_size(r)
	var room := r.size.x - (DOT_R * 2.0 + 6.0)
	while label.length() > 3 and _font_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		label = label.substr(0, label.length() - 2).strip_edges() + "."
	return label


## What a click / a dropped item hits: the whole box for box markers, dot + name for dot markers.
func marker_hit_rect(id: String) -> Rect2:
	var m := find_marker(id)
	var r := marker_rect_local(id)
	if m.is_empty() or r.size.x <= 0.0 or not is_dot(m) or _font_label == null:
		return r
	var fs := dot_label_font_size(r)
	var w := _font_label.get_string_size(dot_label(m, r), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := dot_center_local(id)
	return Rect2(Vector2(c.x - DOT_R, r.position.y), Vector2(DOT_R * 2.0 + 5.0 + w, r.size.y))


func marker_at(local_pos: Vector2) -> String:
	for m: Dictionary in markers():
		if marker_hit_rect(str(m.get("id", ""))).grow(2.0).has_point(local_pos):
			return str(m.get("id", ""))
	return ""


func _update_hover(pos: Vector2) -> void:
	var mk := marker_at(pos)
	var dk := door_at(pos) if mk == "" else ""
	if mk != hover_marker or dk != hover_door:
		hover_marker = mk
		hover_door = dk
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	if event is InputEventMouseMotion and not compact:
		var id := room_at((event as InputEventMouseMotion).position)
		if id != hovered_id:
			hovered_id = id
			room_hovered.emit(id)
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var mk := marker_at(mb.position)
			if mk != "":
				marker_clicked.emit(mk)
				accept_event()
				return
			var dk := door_at(mb.position)
			if dk != "":
				door_clicked.emit(dk)
				accept_event()
				return
			map_clicked.emit()
			if not compact:
				var rid := room_at(mb.position)
				if rid != "":
					room_clicked.emit(rid)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if hover_marker != "" or hover_door != "":
			hover_marker = ""
			hover_door = ""
			queue_redraw()
		if hovered_id != "":
			hovered_id = ""
			room_hovered.emit("")
			queue_redraw()


# ---------------------------------------------------------------- layout

func _map_rect() -> Rect2:
	var r := Rect2(Vector2.ZERO, size).grow(-6.0 if compact else -10.0)
	if show_legend and not compact:
		if _legend_vertical():
			r.size.x -= LEGEND_W
		else:
			r.size.y -= LEGEND_H
	return r


func _legend_vertical() -> bool:
	return size.x > size.y * 1.3


func _bounds() -> Rect2:
	var have := false
	var b := Rect2()
	for room in (map_data.get("rooms", {}) as Dictionary).values():
		for p in (room as Dictionary).get("poly", []):
			if not have:
				b = Rect2(p, Vector2.ZERO)
				have = true
			else:
				b = b.expand(p)
	return b if have else Rect2(0, 0, 100, 100)


func _update_xform() -> void:
	var area := _map_rect()
	if compact:
		var s := compact_scale
		var focus := _room_center(str(map_data.get("current", "")))
		var b := _bounds().grow(6.0)
		if focus == Vector2.INF:
			focus = b.get_center()
		var half := area.size / (2.0 * s)   # half view size in schematic units
		for axis in 2:
			if half[axis] * 2.0 >= b.size[axis]:
				focus[axis] = b.get_center()[axis]
			else:
				focus[axis] = clampf(focus[axis], b.position[axis] + half[axis], b.end[axis] - half[axis])
		_xf = Transform2D(Vector2(s, 0), Vector2(0, s), area.get_center() - focus * s)
	else:
		var b := _bounds().grow(8.0)
		var s := minf(area.size.x / b.size.x, area.size.y / b.size.y)
		var off := area.position + (area.size - b.size * s) * 0.5 - b.position * s
		_xf = Transform2D(Vector2(s, 0), Vector2(0, s), off)


func _scale() -> float:
	return _xf.x.x


# ---------------------------------------------------------------- drawing

## Background of the drawing (pda_screen sets the holo windows' green, WIN_BG, for the game maps).
var bg_color := COL_BG


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), bg_color)
	if map_data.is_empty():
		return
	_update_xform()
	_draw_grid()
	var rooms: Dictionary = map_data.get("rooms", {})
	for id in rooms:
		_draw_room(str(id), rooms[id])
	for d in map_data.get("doors", []):
		_draw_door(d)
	for id in rooms:
		_draw_room_label(str(id), rooms[id])
	_draw_markers()
	_draw_you()
	if show_legend and not compact:
		_draw_legend()
	draw_rect(Rect2(Vector2.ZERO, size), COL_FRAME, false, 1.0)


func _draw_grid() -> void:
	var step := 20.0 * _scale()
	if step < 6.0:
		return
	var origin := _xf.origin
	var x := fposmod(origin.x, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), COL_GRID, 1.0)
		x += step
	var y := fposmod(origin.y, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), COL_GRID, 1.0)
		y += step


func _screen_poly(room: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in room.get("poly", []):
		pts.append(_xf * (p as Vector2))
	return pts


func _draw_room(id: String, room: Dictionary) -> void:
	var pts := _screen_poly(room)
	if pts.size() < 3:
		return
	var state := str(room.get("state", "unexplored"))
	var fill := COL_UNEXPLORED_FILL
	var edge := COL_UNEXPLORED_EDGE
	if state == "explored":
		fill = COL_EXPLORED_FILL
		edge = COL_EXPLORED_EDGE
	elif state == "locked":
		fill = COL_LOCKED_FILL
		edge = COL_LOCKED_EDGE
	var restricted := bool(room.get("restricted", false))
	if restricted:
		fill = COL_LOCKED_FILL
		edge = COL_RESTRICTED.darkened(0.1)
	if id == str(map_data.get("current", "")):
		fill = fill.lightened(0.12)
	draw_colored_polygon(pts, fill)
	if restricted and stamp_age(id) < STAMP_FLASH:
		draw_colored_polygon(pts, Color(COL_RESTRICTED, 0.4 * (1.0 - stamp_age(id) / STAMP_FLASH)))
	var closed := pts.duplicate()
	closed.append(pts[0])
	var w := 2.0 if (id == hovered_id and not compact) else (1.0 if compact else 1.5)
	draw_polyline(closed, COL_HOVER if (id == hovered_id and not compact) else edge, w, true)
	if state == "locked" and not restricted:
		var c := _poly_center(pts)
		var ls := clampf(_scale() * 7.0, 7.0, 15.0)
		_draw_lock(c, ls, COL_LOCKED_EDGE.lightened(0.25))


func _draw_room_label(id: String, room: Dictionary) -> void:
	if bool(room.get("restricted", false)):
		_draw_stamp(id)
		return
	var explored := str(room.get("state", "")) == "explored"
	if not explored and not bool(room.get("known", false)):
		return   # unexplored rooms stay nameless until their name is known
	var label := str(room.get("label", id)).to_upper()
	var eg := edge_label_geom(id, label)
	if not eg.is_empty():
		_draw_label_at(id, label, eg["c"], float(eg["rot"]), int(eg["fs"]), explored)
		return
	var pts := _screen_poly(room)
	var c := _poly_center(pts)
	var fs := 10 if compact else clampi(int(_scale() * 7.0), 11, 18)
	var poly_w := _poly_width_at(pts, c.y)
	var want := _font_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if want > poly_w - 6.0 and id != str(map_data.get("current", "")):
		# small/tapered room: use its widest horizontal slice instead of the centroid
		var bb := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			bb = bb.expand(q)
		for k in range(1, 12):
			var yy := bb.position.y + bb.size.y * k / 12.0
			var w := _poly_width_at(pts, yy)
			if w > poly_w:
				poly_w = w
				c = Vector2(_slice_mid(pts, yy), yy)
	# shrink to fit the room (never below 8 px; tiny rooms may overhang)
	while fs > 8 and _font_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > poly_w - 6.0:
		fs -= 1
	var sz := _font_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var y_off := 0.0
	if id == str(map_data.get("current", "")):
		y_off = fs * 0.9 + (4.0 if compact else 8.0)  # sit under the you-are-here marker
	var pos := Vector2(c.x - sz.x * 0.5, c.y + y_off + fs * 0.35)
	var age := label_age(id)
	if age < STAMP_FLASH + 0.2:
		# stamp-in: the name lands like the RESTRICTED stamp (scaled down from 1.9, fading in, a flash)
		var k := clampf(age / STAMP_POP, 0.0, 1.0)
		var sc := lerpf(1.9, 1.0, 1.0 - pow(1.0 - k, 3.0))
		var a := clampf(age / 0.18, 0.0, 1.0)
		var mid := pos + Vector2(sz.x * 0.5, -fs * 0.35)
		var box := Vector2(sz.x + 10.0, fs + 6.0)
		draw_set_transform(mid, 0.0, Vector2(sc, sc))
		var flash := clampf(1.0 - age / STAMP_FLASH, 0.0, 1.0)
		draw_rect(Rect2(-box * 0.5, box), Color(COL_LABEL, 0.35 * flash * a))
		draw_rect(Rect2(-box * 0.5, box), Color(COL_LABEL, a * flash), false, 1.5)
		draw_string(_font_label, Vector2(-sz.x * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(COL_LABEL if explored else COL_LABEL.lerp(COL_LABEL_DIM, 1.0 - flash), a))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if age > STAMP_FLASH + 0.15:
			_label_pops.erase(id)
		return
	draw_string(_font_label, pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(_font_label, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_LABEL if explored else COL_LABEL_DIM)


## ROOM LABELS RELATIVE TO THE PLAYER: a room next to the player's room (a door between them) gets
## its name along the edge by that door, oriented so it reads from the player's side: a room to the
## WEST reads bottom to top (rotated -90, the AIR LOCK beside the READY ROOM), a room to the EAST reads
## top to bottom (+90; STBD HOLD / RESTRICTED), rooms north / south read normally along their edge.
## Letters always stand on the shared edge. Recomputed from map_data["current"] at every draw, so
## moving rooms re-lays every label. {} = not adjacent (centred label as before).
## Returns {c (centre), rot, fs, side ("w" | "e" | "n" | "s" = which side of the player the room is)}.
func edge_label_geom(id: String, text: String) -> Dictionary:
	var here := str(map_data.get("current", ""))
	if here == "" or id == here:
		return {}
	var door := {}
	for d: Dictionary in map_data.get("doors", []):
		var da := str(d.get("a", ""))
		var db := str(d.get("b", ""))
		if (da == here and db == id) or (db == here and da == id):
			door = d
			break
	if door.is_empty():
		return {}
	var pts := _screen_poly((map_data.get("rooms", {}) as Dictionary).get(id, {}))
	if pts.size() < 3:
		return {}
	var rr := _pts_rect(pts)
	var dc: Vector2 = _xf * (door.get("pos", rr.get_center()) as Vector2)
	var dl := absf(dc.x - rr.position.x)
	var dr := absf(rr.end.x - dc.x)
	var dt := absf(dc.y - rr.position.y)
	var dbm := absf(rr.end.y - dc.y)
	var m := minf(minf(dl, dr), minf(dt, dbm))
	var vertical := m == dl or m == dr
	var avail := (rr.size.y if vertical else rr.size.x) - 8.0
	var fs := 10 if compact else clampi(int(_scale() * 7.0), 11, 18)
	var tw := _font_label.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while fs > 7 and tw > avail:
		fs -= 1
		tw = _font_label.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var inset := fs * 0.8 + 3.0
	var half := minf(tw * 0.5 + 4.0, (avail + 8.0) * 0.5)
	var c := Vector2.ZERO
	var rot := 0.0
	var side := ""
	if m == dr:      # the door is on the room's east edge: the room is WEST of the player
		c = Vector2(rr.end.x - inset, clampf(dc.y, rr.position.y + half, rr.end.y - half))
		rot = -PI * 0.5
		side = "w"
	elif m == dl:    # the room is EAST of the player
		c = Vector2(rr.position.x + inset, clampf(dc.y, rr.position.y + half, rr.end.y - half))
		rot = PI * 0.5
		side = "e"
	elif m == dt:    # door on its north edge: the room is SOUTH of the player
		c = Vector2(clampf(dc.x, rr.position.x + half, rr.end.x - half), rr.position.y + inset)
		side = "s"
	else:            # the room is NORTH of the player
		c = Vector2(clampf(dc.x, rr.position.x + half, rr.end.x - half), rr.end.y - inset)
		side = "n"
	return {"c": c, "rot": rot, "fs": fs, "tw": tw, "side": side}


## One (possibly rotated) room name centred on c, with the stamp-in reveal when it was just unlocked.
func _draw_label_at(id: String, label: String, c: Vector2, rot: float, fs: int, explored: bool) -> void:
	var sz := _font_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var age := label_age(id)
	var sc := 1.0
	var a := 1.0
	var flash := 0.0
	if age < STAMP_FLASH + 0.2:
		var k := clampf(age / STAMP_POP, 0.0, 1.0)
		sc = lerpf(1.9, 1.0, 1.0 - pow(1.0 - k, 3.0))
		a = clampf(age / 0.18, 0.0, 1.0)
		flash = clampf(1.0 - age / STAMP_FLASH, 0.0, 1.0)
		if age > STAMP_FLASH + 0.15:
			_label_pops.erase(id)
	draw_set_transform(c, rot, Vector2(sc, sc))
	if flash > 0.0:
		var box := Vector2(sz.x + 10.0, fs + 6.0)
		draw_rect(Rect2(-box * 0.5, box), Color(COL_LABEL, 0.35 * flash * a))
		draw_rect(Rect2(-box * 0.5, box), Color(COL_LABEL, a * flash), false, 1.5)
	var o := Vector2(-sz.x * 0.5, fs * 0.35)
	draw_string(_font_label, o + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6 * a))
	draw_string(_font_label, o, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COL_LABEL if explored else COL_LABEL_DIM, a))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## RESTRICTED stamp geometry: centre, rotation (tall narrow rooms get it vertical), font size,
## box size (unscaled).
func _stamp_geom(id: String) -> Dictionary:
	var pts := _screen_poly((map_data.get("rooms", {}) as Dictionary).get(id, {}))
	if pts.size() < 3:
		return {}
	var rr := _pts_rect(pts)
	var eg := edge_label_geom(id, STAMP_TEXT)
	if not eg.is_empty():
		# next to the player's room: along the shared edge, readable from there (see edge_label_geom)
		var efs := mini(int(eg["fs"]), 9 if compact else 15)
		var etw := _font_label.get_string_size(STAMP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, efs).x
		return {"c": eg["c"], "rot": eg["rot"], "fs": efs, "tw": etw, "box": Vector2(etw + 10.0, efs + 8.0)}
	var fs := 9 if compact else clampi(int(_scale() * 5.5), 10, 15)
	var tw := _font_label.get_string_size(STAMP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rot := 0.0
	var room_w := rr.size.x
	if tw + 10.0 > rr.size.x - 4.0 and rr.size.y > rr.size.x:
		rot = -PI * 0.5
		room_w = rr.size.y
	while fs > 7 and tw + 10.0 > room_w - 4.0:
		fs -= 1
		tw = _font_label.get_string_size(STAMP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return {"c": rr.get_center(), "rot": rot, "fs": fs, "tw": tw, "box": Vector2(tw + 10.0, fs + 8.0)}


func _draw_stamp(id: String) -> void:
	var g := _stamp_geom(id)
	if g.is_empty():
		return
	var age := stamp_age(id)
	var k := clampf(age / STAMP_POP, 0.0, 1.0)
	var sc := lerpf(1.9, 1.0, 1.0 - pow(1.0 - k, 3.0))
	var a := clampf(age / 0.18, 0.0, 1.0)
	var box: Vector2 = g["box"]
	var fs: int = g["fs"]
	draw_set_transform(g["c"], g["rot"], Vector2(sc, sc))
	draw_rect(Rect2(-box * 0.5, box), Color(COL_BG, 0.9 * a))
	draw_rect(Rect2(-box * 0.5, box), Color(COL_RESTRICTED, a), false, 1.5)
	draw_string(_font_label, Vector2(-float(g["tw"]) * 0.5, fs * 0.36), STAMP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(COL_RESTRICTED.lightened(0.25), a))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Screen rect the RESTRICTED stamp covers once settled (Rect2() if the room isn't restricted).
func stamp_rect_local(id: String) -> Rect2:
	if not room_restricted(id) or size.x <= 0.0:
		return Rect2()
	_update_xform()
	var g := _stamp_geom(id)
	if g.is_empty():
		return Rect2()
	var box: Vector2 = g["box"]
	if absf(float(g["rot"])) > 0.1:
		box = Vector2(box.y, box.x)
	return Rect2(g["c"] - box * 0.5, box)


func _any_restricted() -> bool:
	for r: Variant in (map_data.get("rooms", {}) as Dictionary).values():
		if bool((r as Dictionary).get("restricted", false)):
			return true
	return false


func _draw_door(d: Dictionary) -> void:
	if not _door_visible(d):
		return  # doors are only known once you've seen one side (or "known")
	var key := door_key(d)
	var age := unlock_age(key)
	var anim := age < UNLOCK_TIME
	var open := str(d.get("state", "open")) == "open" and not anim   # still looks locked while the lock opens
	var col := COL_DOOR_OPEN if open else COL_DOOR_LOCKED
	if open and key in (map_data.get("click_doors", []) as Array):
		col = COL_DOOR_OPEN.lerp(Color.WHITE, 0.25 + 0.25 * sin(_t * 4.0))   # a doorway you can step through
	if key == hover_door and not anim:
		col = col.lightened(0.3)
	var c: Vector2 = _xf * (d.get("pos", Vector2.ZERO) as Vector2)
	var along := Vector2.RIGHT if str(d.get("axis", "h")) == "h" else Vector2.DOWN
	var across := Vector2(-along.y, along.x)
	var half := maxf(9.0 * _scale(), 5.0)
	var cap := maxf(3.0 * _scale(), 2.5)
	# cut a gap in the wall, then draw the doorway bracket |—| like the mockup
	draw_line(c - along * half, c + along * half, bg_color, maxf(5.0 * _scale(), 4.0))
	var w := 2.0 if not compact else 1.5
	if open:
		draw_line(c - along * half, c + along * half, col, w, true)
	else:
		_draw_dashes(c - along * half, c + along * half, col, w)
	draw_line(c - along * half - across * cap, c - along * half + across * cap, col, w, true)
	draw_line(c + along * half - across * cap, c + along * half + across * cap, col, w, true)
	var ls := clampf(_scale() * 6.0, 8.0, 12.0)
	if not open and not anim:
		_draw_lock(c, ls, col)
	elif anim:
		if age < UNLOCK_SHAKE:
			# shake: the lock rattles side to side, calming a little
			var k := 1.0 - age / UNLOCK_SHAKE
			_draw_lock(c + Vector2(sin(age * 70.0) * 2.4 * k, 0.0), ls, col.lerp(COL_DOOR_OPEN, 1.0 - k))
		else:
			# pop: the shackle springs open, the lock lifts, grows and fades out
			var k2 := (age - UNLOCK_SHAKE) / (UNLOCK_TIME - UNLOCK_SHAKE)
			var a := 1.0 - k2
			_draw_lock(c + Vector2(0.0, -k2 * ls * 1.2), ls * (1.0 + 0.5 * k2), Color(COL_DOOR_OPEN, a), minf(1.0, k2 * 3.0))
			draw_arc(c, ls * (0.6 + 1.6 * k2), 0.0, TAU, 20, Color(COL_DOOR_OPEN, 0.8 * a), 1.5, true)


func _draw_markers() -> void:
	for m: Dictionary in markers():
		var id := str(m.get("id", ""))
		var r := marker_rect_local(id)
		if r.size.x < 4.0:
			continue
		var hot := id == hover_marker
		if is_dot(m):
			_draw_dot_marker(m, r, hot)
			continue
		draw_rect(r, COL_MARKER.lightened(0.18) if hot else COL_MARKER)
		if bool(m.get("cost", false)):
			# costs TIME (an unsearched LOCKER): orange border, the colour of the time-cost / lock cues
			draw_rect(r, COL_MARKER_COST, false, 2.0 if hot else 1.6)
		else:
			draw_rect(r, Color.WHITE if hot else COL_MARKER_EDGE, false, 1.5 if hot else 1.0)
		var label := str(m.get("label", id)).to_upper()
		var fs := clampi(int(r.size.y * 0.62), 7, 14)
		while fs > 7 and _font_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 4.0:
			fs -= 1
		while label.length() > 3 and _font_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 3.0:
			label = label.substr(0, label.length() - 2).strip_edges() + "."
		var sz := _font_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(_font_label, Vector2(r.position.x + (r.size.x - sz.x) * 0.5, r.position.y + (r.size.y + float(fs) * 0.7) * 0.5),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_MARKER_INK)


func _draw_dot_marker(m: Dictionary, r: Rect2, hot: bool) -> void:
	var id := str(m.get("id", ""))
	var c := dot_center_local(id)
	var pile := str(m.get("kind", "")) == "pile"
	var col := COL_HOVER if hot else COL_DOT
	draw_circle(c, DOT_R + 1.4, COL_DOT_RING)
	draw_circle(c, DOT_R, col)
	if pile:
		draw_arc(c, DOT_R + 2.6, 0.0, TAU, 16, col, 1.0, true)
	var fs := dot_label_font_size(r)
	var label := dot_label(m, r)
	var pos := Vector2(c.x + DOT_R + 4.0, c.y + float(fs) * 0.35)
	draw_string(_font_label, pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_DOT_RING)
	draw_string(_font_label, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if hot:
		var hr := marker_hit_rect(id)
		draw_line(Vector2(pos.x, pos.y + 2.0), Vector2(hr.end.x, pos.y + 2.0), col, 1.0)


func _draw_dashes(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var n := 5
	for i in n:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, w, true)


func _draw_you() -> void:
	var c := _room_center(str(map_data.get("current", "")))
	if c == Vector2.INF:
		return
	var p := _xf * c
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var r := 3.5 if compact else 5.0
	draw_circle(p, r + 3.0 + pulse * 3.0, Color(COL_YOU, 0.18 + 0.12 * (1.0 - pulse)))
	draw_arc(p, r + 2.0 + pulse * 2.5, 0.0, TAU, 24, Color(COL_YOU, 0.8 - 0.5 * pulse), 1.2, true)
	draw_circle(p, r, COL_YOU)


## Vector padlock (no font glyph): shackle arc + body + keyhole.
func _draw_lock(c: Vector2, s: float, col: Color, open_amt := 0.0) -> void:
	var body := Rect2(c.x - s * 0.62, c.y - s * 0.1, s * 1.24, s * 0.95)
	# open_amt 0..1 lifts the shackle off the body (the "pop")
	var lift := open_amt * s * 0.55
	draw_arc(Vector2(c.x, body.position.y - lift), s * 0.4, PI, TAU, 14, col, maxf(s * 0.18, 1.3), true)
	draw_line(Vector2(c.x - s * 0.4, body.position.y - lift), Vector2(c.x - s * 0.4, body.position.y + 1), col, maxf(s * 0.18, 1.3))
	if open_amt < 0.5:
		draw_line(Vector2(c.x + s * 0.4, body.position.y - lift), Vector2(c.x + s * 0.4, body.position.y + 1), col, maxf(s * 0.18, 1.3))
	draw_rect(body.grow(1.0), Color(COL_BG.r, COL_BG.g, COL_BG.b, COL_BG.a * col.a))
	draw_rect(body, col)
	draw_circle(Vector2(c.x, body.position.y + body.size.y * 0.42), maxf(s * 0.14, 1.0), COL_BG)
	draw_line(Vector2(c.x, body.position.y + body.size.y * 0.42), Vector2(c.x, body.position.y + body.size.y * 0.78), COL_BG, maxf(s * 0.1, 1.0))


func _legend_entries() -> Array:
	return [
		["room", COL_EXPLORED_FILL, COL_EXPLORED_EDGE, "EXPLORED"],
		["room", COL_UNEXPLORED_FILL, COL_UNEXPLORED_EDGE, "UNEXPLORED"],
		["lockroom", COL_LOCKED_FILL, COL_LOCKED_EDGE, "LOCKED ROOM"],
		["door", COL_DOOR_OPEN, COL_DOOR_OPEN, "OPEN DOOR"],
		["lockdoor", COL_DOOR_LOCKED, COL_DOOR_LOCKED, "LOCKED DOOR"],
		["you", COL_YOU, COL_YOU, "YOU ARE HERE"],
	] + ([["restricted", COL_LOCKED_FILL, COL_RESTRICTED, "RESTRICTED"]] if _any_restricted() else [])


func _draw_legend() -> void:
	if _legend_vertical():
		_draw_legend_vertical()
	else:
		_draw_legend_horizontal()


func _draw_legend_vertical() -> void:
	var x0 := size.x - LEGEND_W
	draw_line(Vector2(x0, 10), Vector2(x0, size.y - 10), COL_FRAME, 1.0)
	var fs := 12
	var y := 30.0
	draw_string(_font_mono, Vector2(x0 + 16, y), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_LABEL_DIM)
	y += 28.0
	for e in _legend_entries():
		_draw_legend_icon(e, Rect2(x0 + 16, y - 9, 22, 18))
		draw_string(_font_mono, Vector2(x0 + 48, y + fs * 0.38), e[3], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_LABEL)
		y += 34.0


func _draw_legend_icon(e: Array, icon: Rect2) -> void:
	var y := icon.get_center().y
	match str(e[0]):
		"room", "lockroom", "restricted":
			draw_rect(icon, e[1])
			draw_rect(icon, e[2], false, 1.5)
			if e[0] == "lockroom":
				_draw_lock(icon.get_center(), 8.0, COL_LOCKED_EDGE.lightened(0.25))
			elif e[0] == "restricted":
				draw_line(icon.position + Vector2(4, icon.size.y - 4), icon.end - Vector2(4, icon.size.y - 4), e[2], 2.0, true)
		"door", "lockdoor":
			var a := Vector2(icon.position.x + 1, y)
			var b := Vector2(icon.end.x - 1, y)
			if e[0] == "door":
				draw_line(a, b, e[1], 2.0)
			else:
				_draw_dashes(a, b, e[1], 2.0)
			draw_line(a + Vector2(0, -5), a + Vector2(0, 5), e[1], 2.0)
			draw_line(b + Vector2(0, -5), b + Vector2(0, 5), e[1], 2.0)
			if e[0] == "lockdoor":
				_draw_lock(icon.get_center(), 7.5, e[1])
		"you":
			draw_circle(icon.get_center(), 8.0, Color(COL_YOU, 0.25))
			draw_circle(icon.get_center(), 4.5, COL_YOU)


func _draw_legend_horizontal() -> void:
	var y := size.y - LEGEND_H * 0.5 - 4.0
	draw_line(Vector2(10, size.y - LEGEND_H - 2.0), Vector2(size.x - 10, size.y - LEGEND_H - 2.0), COL_FRAME, 1.0)
	var entries := [
		["room", COL_EXPLORED_FILL, COL_EXPLORED_EDGE, "EXPLORED"],
		["room", COL_UNEXPLORED_FILL, COL_UNEXPLORED_EDGE, "UNEXPLORED"],
		["lockroom", COL_LOCKED_FILL, COL_LOCKED_EDGE, "LOCKED"],
		["door", COL_DOOR_OPEN, COL_DOOR_OPEN, "OPEN DOOR"],
		["lockdoor", COL_DOOR_LOCKED, COL_DOOR_LOCKED, "LOCKED DOOR"],
		["you", COL_YOU, COL_YOU, "YOU ARE HERE"],
	]
	if _any_restricted():
		entries.append(["restricted", COL_LOCKED_FILL, COL_RESTRICTED, "RESTRICTED"])
	var fs := 11
	var total := 0.0
	var widths: Array[float] = []
	for e in entries:
		var w := 26.0 + _font_mono.get_string_size(e[3], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0
		widths.append(w)
		total += w
	var x := maxf(10.0, (size.x - total) * 0.5)
	for i in entries.size():
		var e: Array = entries[i]
		var icon := Rect2(x, y - 7, 18, 14)
		match str(e[0]):
			"room", "lockroom", "restricted":
				draw_rect(icon, e[1])
				draw_rect(icon, e[2], false, 1.5)
				if e[0] == "lockroom":
					_draw_lock(icon.get_center(), 7.0, COL_LOCKED_EDGE.lightened(0.25))
				elif e[0] == "restricted":
					draw_line(icon.position + Vector2(3, icon.size.y - 3), icon.end - Vector2(3, icon.size.y - 3), e[2], 2.0, true)
			"door", "lockdoor":
				var a := Vector2(icon.position.x + 1, y)
				var b := Vector2(icon.end.x - 1, y)
				if e[0] == "door":
					draw_line(a, b, e[1], 2.0)
				else:
					_draw_dashes(a, b, e[1], 2.0)
				draw_line(a + Vector2(0, -4), a + Vector2(0, 4), e[1], 2.0)
				draw_line(b + Vector2(0, -4), b + Vector2(0, 4), e[1], 2.0)
				if e[0] == "lockdoor":
					_draw_lock(icon.get_center(), 6.5, e[1])
			"you":
				draw_circle(icon.get_center(), 7.0, Color(COL_YOU, 0.25))
				draw_circle(icon.get_center(), 4.0, COL_YOU)
		draw_string(_font_mono, Vector2(x + 24, y + fs * 0.38), e[3], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_LABEL_DIM)
		x += widths[i]


# ---------------------------------------------------------------- geometry helpers

func _room_center(id: String) -> Vector2:
	var room: Dictionary = (map_data.get("rooms", {}) as Dictionary).get(id, {})
	if room.is_empty():
		return Vector2.INF
	var pts := PackedVector2Array()
	for p in room.get("poly", []):
		pts.append(p)
	if room.has("center"):
		return room["center"]
	return _poly_center(pts)


## Label anchor: centroid of the largest rectangle-ish part (area-weighted centroid).
func _poly_center(pts: PackedVector2Array) -> Vector2:
	var a := 0.0
	var cx := 0.0
	var cy := 0.0
	for i in pts.size():
		var p0 := pts[i]
		var p1 := pts[(i + 1) % pts.size()]
		var cr := p0.x * p1.y - p1.x * p0.y
		a += cr
		cx += (p0.x + p1.x) * cr
		cy += (p0.y + p1.y) * cr
	if absf(a) < 0.001:
		var s := Vector2.ZERO
		for p in pts:
			s += p
		return s / maxf(1.0, pts.size())
	a *= 0.5
	var c := Vector2(cx / (6.0 * a), cy / (6.0 * a))
	if not Geometry2D.is_point_in_polygon(c, pts):
		# concave (the L room): fall back to the widest horizontal slice's middle
		var best := c
		var best_w := 0.0
		var b := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			b = b.expand(p)
		for k in range(1, 20):
			var yy := b.position.y + b.size.y * k / 20.0
			var w := _poly_width_at(pts, yy)
			if w > best_w:
				best_w = w
				best = Vector2(_slice_mid(pts, yy), yy)
		return best
	return c


func _poly_width_at(pts: PackedVector2Array, y: float) -> float:
	var xs := _slice_xs(pts, y)
	return (xs[1] - xs[0]) if xs.size() >= 2 else 0.0


func _slice_mid(pts: PackedVector2Array, y: float) -> float:
	var xs := _slice_xs(pts, y)
	return (xs[0] + xs[1]) * 0.5 if xs.size() >= 2 else pts[0].x


func _slice_xs(pts: PackedVector2Array, y: float) -> Array[float]:
	var xs: Array[float] = []
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
			xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
	xs.sort()
	return xs


func room_at(local_pos: Vector2) -> String:
	for id in (map_data.get("rooms", {}) as Dictionary):
		var pts := _screen_poly(map_data["rooms"][id])
		if pts.size() >= 3 and Geometry2D.is_point_in_polygon(local_pos, pts):
			return str(id)
	return ""


## ---- public geometry (local coordinates of this view; for the map walkthrough) ----

## Screen-space polygon of a room (empty if unknown).
func room_poly_local(id: String) -> PackedVector2Array:
	var room: Dictionary = (map_data.get("rooms", {}) as Dictionary).get(id, {})
	if room.is_empty() or size.x <= 0.0:
		return PackedVector2Array()
	_update_xform()
	return _screen_poly(room)


func room_rect_local(id: String) -> Rect2:
	return _pts_rect(room_poly_local(id))


## Every room together (the ship outline).
func ship_rect_local() -> Rect2:
	var r := Rect2()
	var have := false
	for id in (map_data.get("rooms", {}) as Dictionary):
		var rr := room_rect_local(str(id))
		if rr.size == Vector2.ZERO:
			continue
		r = rr if not have else r.merge(rr)
		have = true
	return r


func _pts_rect(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	return r


## Door "a|b" (order-insensitive): its bracket's rect, lock included.
func door_rect_local(key: String) -> Rect2:
	var d := find_door(key)
	if d.is_empty() or size.x <= 0.0:
		return Rect2()
	_update_xform()
	var c: Vector2 = _xf * (d.get("pos", Vector2.ZERO) as Vector2)
	var half := maxf(9.0 * _scale(), 5.0)
	var ext := Vector2(half, maxf(clampf(_scale() * 6.0, 8.0, 12.0), 3.0 * _scale())) if str(d.get("axis", "h")) == "h" \
		else Vector2(maxf(clampf(_scale() * 6.0, 8.0, 12.0), 3.0 * _scale()), half)
	return Rect2(c - ext, ext * 2.0)


func find_door(key: String) -> Dictionary:
	var parts := key.split("|", false)
	if parts.size() < 2:
		return {}
	var a := parts[0].strip_edges()
	var b := parts[1].strip_edges()
	for d: Dictionary in map_data.get("doors", []):
		var da := str(d.get("a", ""))
		var db := str(d.get("b", ""))
		if (da == a and db == b) or (da == b and db == a):
			return d
	return {}


## Centre of the you-are-here dot (Vector2.INF if none).
func you_pos_local() -> Vector2:
	var c := _room_center(str(map_data.get("current", "")))
	if c == Vector2.INF or size.x <= 0.0:
		return Vector2.INF
	_update_xform()
	return _xf * c


func room_state(id: String) -> String:
	return str(((map_data.get("rooms", {}) as Dictionary).get(id, {}) as Dictionary).get("state", ""))
