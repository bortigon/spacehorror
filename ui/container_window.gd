extends "res://ui/holo_window.gd"
## CONTAINER WINDOW (David's sketch, right panel): a window for a green ACT word that is a container.
## Left 25 %: the title (top-left) and the description text under it. Right ~75 %: a darker teal item
## grid. Bottom: buttons for the highlighted item (TAKE ITEM today, but each item lists its own
## "actions", see ACTIONS) and EXIT at the bottom right. Placeholder art, all drawn in code.
##
## Spec (an act with "container": true, see docs/SCENE_WRITER.md):
##   {container, title, text, grid: {cols, rows}, items: [{id, label, hours, required, detail, actions}]}

signal take_requested(act_id: String, item: Dictionary)
## Any action other than "take" (use, inspect, ...). Nothing handles these yet: room to grow.
signal action_requested(act_id: String, action: String, item: Dictionary)
signal exit_requested
signal selection_changed(item: Dictionary)

## Known item actions and the button text pattern ({item} = LABEL). Only "take" does anything built-in.
const ACTIONS := {
	"take": "Take {item}",
	"use": "Use {item}",
	"inspect": "Inspect {item}",
}
## Left column (title + description) is 140 px of the 360 px window (was a 25 % column, ~86 px, too
## narrow for the locker text). The item cells are smaller too: up to CELL_W x CELL_H.
const LEFT_W := 140.0
const CELL_W := 56.0
const CELL_H := 52.0
const CELL_GAP := 4.0
const GRID_PAD := 6.0
## The description shrinks through these font sizes until it fits without a scroll bar.
const DESC_SIZES := [10, 9, 8]

var act_id := ""
var title := ""
var description := ""
var cols := 3
var rows := 3
var items: Array = []             # normalized item dictionaries (+ "taken": bool)
var selected_id := ""

var title_label: Label
var desc_box: RichTextLabel
var grid_bg: Panel
var slots: Array = []
var actions_row: HBoxContainer
var exit_button: Button
var action_buttons: Array[Button] = []


func _init() -> void:
	panel_size = Vector2(360, 300)
	build()


func _build_body() -> void:
	body.add_child(make_panel_bg())
	var left_w := LEFT_W
	title_label = make_label("", 15, true)
	title_label.position = Vector2(12, 8)
	title_label.size = Vector2(left_w, 22)
	title_label.clip_text = true
	body.add_child(title_label)
	desc_box = RichTextLabel.new()
	desc_box.bbcode_enabled = true
	desc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_box.position = Vector2(12, 34)
	desc_box.size = Vector2(left_w, 204)
	desc_box.scroll_active = false          # never a scroll bar: the font shrinks instead
	desc_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_box.add_theme_color_override("default_color", INK)
	desc_box.add_theme_color_override("font_selected_color", INK)
	desc_box.add_theme_font_override("normal_font", _mono)
	desc_box.add_theme_font_override("bold_font", _mono_bold)
	_set_desc_font(int(DESC_SIZES[0]))
	desc_box.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	body.add_child(desc_box)

	var gx := 12.0 + left_w + 8.0
	grid_bg = make_grid_bg(Rect2(gx, 10, panel_size.x - gx - 12.0, 228))
	grid_bg.name = "ContainerGrid"
	grid_bg.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and is_interactive():
			select_id(""))
	body.add_child(grid_bg)

	make_notice(Rect2(12, 240, panel_size.x - 24.0, 14))
	actions_row = HBoxContainer.new()
	actions_row.name = "Actions"
	actions_row.position = Vector2(12, 258)
	actions_row.size = Vector2(panel_size.x - 120.0, 32)
	actions_row.add_theme_constant_override("separation", 6)
	actions_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(actions_row)
	exit_button = make_button("EXIT", Vector2(84, 30))
	exit_button.name = "Exit"
	exit_button.position = Vector2(panel_size.x - 94.0, 258)
	exit_button.size = Vector2(84, 30)
	exit_button.pressed.connect(func() -> void:
		if is_interactive():
			exit_requested.emit())
	body.add_child(exit_button)


func _set_desc_font(px: int) -> void:
	desc_box.add_theme_font_size_override("normal_font_size", px)
	desc_box.add_theme_font_size_override("bold_font_size", px)
	desc_box.add_theme_font_size_override("italics_font_size", px)


## Picks the biggest font that lets the whole text fit in the box (no scroll bar ever).
func _fit_description() -> void:
	for px: int in DESC_SIZES:
		_set_desc_font(px)
		if desc_box.get_content_height() <= int(desc_box.size.y):
			return


func description_fits() -> bool:
	return desc_box.get_content_height() <= int(desc_box.size.y)


## Loads an act spec. `is_taken`: Callable(item) -> bool for items already in the inventory.
func configure(p_act_id: String, spec: Dictionary, is_taken := Callable()) -> void:
	act_id = p_act_id
	title = str(spec.get("title", "")).strip_edges()
	if title == "":
		title = p_act_id.to_upper()
	description = str(spec.get("text", ""))
	var g: Dictionary = spec.get("grid", {}) if spec.get("grid", {}) is Dictionary else {}
	cols = clampi(int(g.get("cols", 3)), 1, 8)
	rows = clampi(int(g.get("rows", 3)), 1, 8)
	items.clear()
	for raw: Variant in spec.get("items", []):
		if raw is Dictionary:
			var it: Dictionary = (raw as Dictionary).duplicate(true)
			it["taken"] = is_taken.is_valid() and bool(is_taken.call(it))
			items.append(it)
	selected_id = ""
	title_label.text = title.to_upper()
	_rebuild_grid()
	_refresh_text()
	_refresh_actions()


func _rebuild_grid() -> void:
	for s: Control in slots:
		s.queue_free()
	slots.clear()
	var avail := Vector2(panel_size.x - (12.0 + LEFT_W + 8.0) - 12.0, 228.0)
	var gap := CELL_GAP
	var pad := GRID_PAD
	var sw := minf(CELL_W, (avail.x - pad * 2.0 - gap * float(cols - 1)) / float(cols))
	var sh := minf(CELL_H, (avail.y - pad * 2.0 - gap * float(rows - 1)) / float(rows))
	sw = floorf(sw)
	sh = floorf(sh)
	# the teal backdrop hugs the cells (right-aligned in the column)
	var gw := pad * 2.0 + sw * float(cols) + gap * float(cols - 1)
	var gh := pad * 2.0 + sh * float(rows) + gap * float(rows - 1)
	grid_bg.position = Vector2(panel_size.x - 12.0 - gw, 10.0)
	grid_bg.size = Vector2(gw, gh)
	for i in cols * rows:
		var s: Control = preload("res://ui/inv_slot.gd").new()
		s.position = grid_bg.position + Vector2(pad + float(i % cols) * (sw + gap), pad + float(i / cols) * (sh + gap))
		s.size = Vector2(sw, sh)
		s.draggable = true
		s.drag_kind = "container_item"
		s.drag_tag = act_id
		s.pressed.connect(_on_slot_pressed)
		body.add_child(s)
		slots.append(s)
	# items fill the grid in order (an item may pin itself with "slot": n)
	var at: Dictionary = {}          # cell index -> item index
	for k in items.size():
		var pin := int((items[k] as Dictionary).get("slot", -1))
		if pin >= 0 and pin < slots.size() and not at.has(pin):
			at[pin] = k
	var placed: Dictionary = {}
	for cell in at:
		placed[int(at[cell])] = true
	var next := 0
	for k in items.size():
		if placed.has(k):
			continue
		while at.has(next):
			next += 1
		if next >= slots.size():
			break   # more items than cells (the Scene Writer warns about this)
		at[next] = k
		next += 1
	for i in slots.size():
		var s2: Control = slots[i]
		var it2: Dictionary = items[int(at[i])] if at.has(i) else {}
		s2.set_item({} if it2.is_empty() or bool(it2.get("taken", false)) else it2)
		s2.set_selected(false)


func find_item(id: String) -> Dictionary:
	for it: Dictionary in items:
		if str(it.get("id", "")) == id:
			return it
	return {}


func slot_for(id: String) -> Control:
	for s: Control in slots:
		if not s.item.is_empty() and str(s.item.get("id", "")) == id:
			return s
	return null


func selected_item() -> Dictionary:
	return find_item(selected_id) if selected_id != "" else {}


func select_id(id: String) -> void:
	var it := find_item(id)
	if it.is_empty() or bool(it.get("taken", false)):
		id = ""
	selected_id = id
	for s: Control in slots:
		s.set_selected(id != "" and not s.item.is_empty() and str(s.item.get("id", "")) == id)
	_refresh_text()
	_refresh_actions()
	selection_changed.emit(selected_item())


## The item left the container: its cell goes empty and the selection clears.
func mark_taken(id: String) -> void:
	var it := find_item(id)
	if it.is_empty():
		return
	it["taken"] = true
	var s := slot_for(id)
	if s != null:
		s.set_item({})
	if selected_id == id:
		selected_id = ""
	for s2: Control in slots:
		s2.set_selected(false)
	_refresh_text()
	_refresh_actions()


func remaining() -> int:
	var n := 0
	for it: Dictionary in items:
		if not bool(it.get("taken", false)):
			n += 1
	return n


func _on_slot_pressed(s: Control) -> void:
	if not is_interactive():
		return
	select_id(str(s.item.get("id", "")))


func _refresh_text() -> void:
	var bb := ""
	if description.strip_edges() != "":
		bb += _esc(description.strip_edges())
	var it := selected_item()
	if not it.is_empty():
		if bb != "":
			bb += "\n\n"
		bb += "[b]%s[/b]" % _esc(str(it.get("label", "")))
		var detail := str(it.get("detail", ""))
		if detail != "":
			bb += "\n" + _esc(detail)
		if bool(it.get("required", false)):
			bb += "\n[i]Required.[/i]"
	desc_box.text = bb
	_fit_description()


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _refresh_actions() -> void:
	for b in action_buttons:
		if is_instance_valid(b):
			b.queue_free()
	action_buttons.clear()
	var it := selected_item()
	if it.is_empty():
		return
	var acts: Array = it.get("actions", ["take"])
	for a: Variant in acts:
		var aid := str(a).strip_edges().to_lower()
		if aid == "":
			continue
		var b := make_button(action_text(aid, it), Vector2(0, 30))
		b.name = "Action_" + aid
		b.pressed.connect(_do_action.bind(aid))
		actions_row.add_child(b)
		action_buttons.append(b)


## "Take SUIT (1 hr)". Other actions: "Use LANTERN", "Inspect TAPE".
func action_text(aid: String, it: Dictionary) -> String:
	var label := str(it.get("label", it.get("id", "")))
	var pattern := str(ACTIONS.get(aid, aid.capitalize() + " {item}"))
	var text := pattern.replace("{item}", label)
	var hrs := int(it.get("hours", 0))
	if aid == "take" and hrs > 0:
		text += " (%s)" % hour_text(hrs)
	return text


static func hour_text(hrs: int) -> String:
	return "1 hr" if hrs == 1 else "%d hrs" % hrs


func do_action(aid: String) -> void:
	_do_action(aid)


func _do_action(aid: String) -> void:
	if not is_interactive():
		return
	var it := selected_item()
	if it.is_empty():
		return
	if aid == "take":
		take_requested.emit(act_id, it.duplicate(true))
	else:
		action_requested.emit(act_id, aid, it.duplicate(true))
