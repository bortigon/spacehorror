extends Control
## One inventory grid cell, drawn in code (placeholder art until the 2D icons exist).
## Click = `pressed(self)`. A slot that holds an item can be dragged (container -> character screen);
## a slot with `drop_target` set forwards drops to the owner.

signal pressed(slot: Control)

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
var drag_kind := ""       # payload "kind" for drag data
var drag_tag := ""        # payload "tag" (e.g. the container act id)
var drop_target: Object   # owner with can_drop(data) -> bool and drop(data)
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
	if dim:
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
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not item.is_empty():
			pressed.emit(self)
			accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or item.is_empty():
		return null
	var pv := Label.new()
	pv.text = " %s " % str(item.get("label", ""))
	pv.add_theme_color_override("font_color", Color(0.03, 0.13, 0.05))
	var bg := StyleBoxFlat.new()
	bg.bg_color = ITEM_FILL
	bg.border_color = ITEM_EDGE
	bg.set_border_width_all(1)
	pv.add_theme_stylebox_override("normal", bg)
	if is_inside_tree() and get_viewport().gui_is_dragging():
		set_drag_preview(pv)
	else:
		pv.free()
	pressed.emit(self)
	return {"kind": drag_kind, "tag": drag_tag, "id": str(item.get("id", ""))}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return drop_target != null and drop_target.has_method("can_drop") and bool(drop_target.call("can_drop", data))


func _drop_data(_at: Vector2, data: Variant) -> void:
	if drop_target != null and drop_target.has_method("drop"):
		drop_target.call("drop", data)
