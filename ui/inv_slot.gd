extends Control
## One inventory grid cell, drawn in code (placeholder art until the 2D icons exist).
## Click = `pressed(self)`. A slot that holds an item can be dragged (`drag_started`): the window
## manager then keeps the item on the cursor (character <-> container, out to the map, onto a lock).

signal pressed(slot: Control)
## The item was pressed and dragged a few pixels: the window manager makes it stick to the cursor.
signal drag_started(slot: Control, global_pos: Vector2)

const DRAG_THRESHOLD := 5.0
const Icons := preload("res://ui/item_icons.gd")

const MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"
const MONO_BOLD := "res://assets/fonts/IBMPlexMono-SemiBold.ttf"
const SLOT_BG := Color(0.07, 0.31, 0.24, 1.0)
const SLOT_BG_HOVER := Color(0.10, 0.40, 0.31, 1.0)
const SLOT_LINE := Color(0.03, 0.17, 0.13, 1.0)
const SELECT := Color(0.92, 1.0, 0.90, 1.0)
const ITEM_FILL := Color(0.52, 0.86, 0.45, 1.0)
const ITEM_EDGE := Color(0.82, 1.0, 0.78, 1.0)
const LABEL_COLOR := Color(0.86, 1.0, 0.86, 1.0)

## {id, label, detail, hours, required, actions, ...} or {} for an empty cell.
var item: Dictionary = {}
var dim := false          # "Not issued." placeholder: outline only, faded label
var selected := false
var draggable := false
var _pressing := false
var _press_pos := Vector2.ZERO
var _hover := false
var _font: Font
var _font_b: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	focus_mode = Control.FOCUS_NONE
	_font = load(MONO) if ResourceLoader.exists(MONO) else null
	_font_b = load(MONO_BOLD) if ResourceLoader.exists(MONO_BOLD) else _font
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func set_item(it: Dictionary, p_dim := false) -> void:
	item = it
	dim = p_dim
	var label := str(it.get("label", ""))
	var detail := str(it.get("detail", ""))
	tooltip_text = "" if it.is_empty() else (label if detail == "" else "%s\n%s" % [label, detail])
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not it.is_empty() else Control.CURSOR_ARROW
	queue_redraw()


func is_empty_slot() -> bool:
	return item.is_empty()


func set_selected(on: bool) -> void:
	selected = on
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, SLOT_BG_HOVER if (_hover and not item.is_empty()) else SLOT_BG)
	draw_rect(r, SLOT_LINE, false, 1.0)
	if item.is_empty():
		return
	var fade := 0.45 if dim else 1.0
	var text := str(item.get("label", ""))
	var lay := _fit_label(text, size.x - 4.0)
	var fs: int = lay["fs"]
	var lines: Array = lay["lines"]
	var line_h := float(fs) + 2.0
	var icon_room := size.y - 5.0 - float(lines.size()) * line_h - 2.0
	var sq := clampf(minf(size.x - 14.0, icon_room), 8.0, 30.0)
	var box := Rect2(Vector2((size.x - sq) * 0.5, 3.0 + maxf(0.0, (icon_room - sq) * 0.5)), Vector2(sq, sq))
	var iid := str(item.get("icon", item.get("id", "")))   # floor cells carry the real id in "icon"
	if Icons.has_icon(iid):
		Icons.draw_icon(self, iid, box.grow(2.0), fade)    # code-drawn art (THERMOS, SUIT, LANTERN, keycards)
	elif dim:
		draw_rect(box, Color(ITEM_EDGE, 0.35), false, 1.0)
	else:
		draw_rect(box, ITEM_FILL)
		draw_rect(box, ITEM_EDGE, false, 1.0)
		# little bevel so the placeholder reads as an object
		draw_rect(Rect2(box.position + Vector2(2, 2), Vector2(sq - 4.0, 2.0)), Color(1, 1, 1, 0.25))
	if _font_b:
		var y := size.y - 3.0 - float(lines.size() - 1) * line_h
		for ln: Variant in lines:
			draw_string(_font_b, Vector2(2.0, y), str(ln), HORIZONTAL_ALIGNMENT_CENTER, size.x - 4.0, fs, Color(LABEL_COLOR, fade))
			y += line_h
	if selected:
		draw_rect(r.grow(-1.0), SELECT, false, 2.0)


## Label layout for a small cell: one line, or two (split at a space) when it is too wide; the font
## shrinks (9 -> 6) until it fits. Returns {fs, lines}.
func _fit_label(text: String, w: float) -> Dictionary:
	if _font_b == null:
		return {"fs": 8, "lines": [text]}
	var words := text.split(" ", false)
	for fs in [9, 8, 7, 6]:
		if _font_b.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
			return {"fs": fs, "lines": [text]}
		if words.size() >= 2:
			# best split: the two halves as even as possible
			var best: Array = []
			var best_w := 1e9
			for k in range(1, words.size()):
				var l1 := " ".join(words.slice(0, k))
				var l2 := " ".join(words.slice(k))
				var mw := maxf(_font_b.get_string_size(l1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
					_font_b.get_string_size(l2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
				if mw < best_w:
					best_w = mw
					best = [l1, l2]
			if best_w <= w:
				return {"fs": fs, "lines": best}
	return {"fs": 6, "lines": [text]}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not item.is_empty():
				_pressing = draggable
				_press_pos = mb.global_position
				pressed.emit(self)
				accept_event()
			elif not mb.pressed:
				_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		var mm := event as InputEventMouseMotion
		if (mm.global_position - _press_pos).length() >= DRAG_THRESHOLD and not item.is_empty():
			_pressing = false
			drag_started.emit(self, mm.global_position)
			accept_event()


## A drag begins (button held and moved a few pixels). The window manager takes the item over: it
## sticks to the cursor (see window_manager.gd), so this is not Godot's built-in drag and drop.
func start_drag_now(global_pos: Vector2) -> void:
	if draggable and not item.is_empty():
		_pressing = false
		drag_started.emit(self, global_pos)
