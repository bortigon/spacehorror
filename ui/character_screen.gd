extends "res://ui/holo_window.gd"
## CHARACTER / INVENTORY SCREEN (David's sketch, left panel).
## NAME top-left, X top-right, a black figure silhouette on the left, an EMPTY reserved space under
## the figure (undecided: nothing is drawn there on purpose), and a tall item grid on the right
## (3 columns x 5 rows). The selected item's name + detail show under the grid.
## Placeholder art only: everything is drawn with Control / StyleBox / draw code.

signal close_requested
signal item_selected(item: Dictionary)
## A button under the grid: "drop" or "wear" (after the Put on? prompt was confirmed).
signal item_action(action: String, item: Dictionary)

const COLS := 3
const ROWS := 5
## Smaller cells than the first version (64 x 42): 50 x 46, labels wrap to two lines.
const CELL_W := 50.0
const CELL_H := 46.0
const CELL_GAP := 3.0
const GRID_PAD := 4.0
const FIGURE_COLOR := Color(0.02, 0.06, 0.03, 1.0)
## Suit worn: green figure with a white highlight (placeholder art, drawn in code).
const FIGURE_SUIT := Color(0.24, 0.62, 0.32, 1.0)
const FIGURE_SUIT_HI := Color(0.95, 1.0, 0.95, 0.95)

var name_label: Label
var close_button: Button
var figure: Control
var reserved_space: Control      # the "?" area in the sketch: intentionally left blank
var grid_bg: Panel
var slots: Array = []            # InvSlot controls, row-major
var desc_title: Label
var desc_body: Label
var actions_row: HBoxContainer
var action_buttons: Array[Button] = []
var selected_id := ""
var suit_worn := false
var confirm_text := ""           # "Put on? (1 hr)" while the prompt is up, else ""
## Owner hooks for drag-and-drop from a container: Callable(data) -> bool / Callable(data).
var can_drop_cb: Callable
var drop_cb: Callable


func _init() -> void:
	panel_size = Vector2(330, 384)
	build()


func _build_body() -> void:
	var bg := make_panel_bg()
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # a container item can be dropped anywhere on the screen
	bg.set_drag_forwarding(Callable(), func(_at: Vector2, d: Variant) -> bool: return can_drop(d),
		func(_at: Vector2, d: Variant) -> void: drop(d))
	body.add_child(bg)
	name_label = make_label("NAME", 17, true)
	name_label.position = Vector2(12, 8)
	name_label.size = Vector2(240, 24)
	name_label.clip_text = true
	body.add_child(name_label)
	close_button = make_button("X", Vector2(26, 24))
	close_button.name = "Close"
	close_button.position = Vector2(panel_size.x - 36, 8)
	close_button.size = Vector2(26, 24)
	close_button.add_theme_stylebox_override("normal", _btn_style(Color(0.05, 0.19, 0.10, 0.97), Color(0.55, 0.85, 0.58)))
	close_button.pressed.connect(func() -> void:
		if is_interactive():
			close_requested.emit())
	body.add_child(close_button)

	figure = Control.new()
	figure.name = "Figure"
	figure.position = Vector2(12, 40)
	figure.size = Vector2(96, 150)
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	figure.draw.connect(_draw_figure)
	body.add_child(figure)

	# Reserved for the undecided "?" space under the figure. Left empty on purpose.
	reserved_space = Control.new()
	reserved_space.name = "ReservedSpace"
	reserved_space.position = Vector2(12, 196)
	reserved_space.size = Vector2(96, 132)
	reserved_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(reserved_space)

	var gw := GRID_PAD * 2.0 + CELL_W * COLS + CELL_GAP * (COLS - 1)
	var gh := GRID_PAD * 2.0 + CELL_H * ROWS + CELL_GAP * (ROWS - 1)
	grid_bg = make_grid_bg(Rect2(panel_size.x - 12.0 - gw, 40, gw, gh))
	grid_bg.name = "InventoryGrid"
	body.add_child(grid_bg)
	for i in COLS * ROWS:
		var s: Control = preload("res://ui/inv_slot.gd").new()
		s.position = grid_bg.position + Vector2(GRID_PAD + float(i % COLS) * (CELL_W + CELL_GAP),
			GRID_PAD + float(i / COLS) * (CELL_H + CELL_GAP))
		s.size = Vector2(CELL_W, CELL_H)
		s.drop_target = self
		s.pressed.connect(_on_slot_pressed)
		body.add_child(s)
		slots.append(s)
	grid_bg.set_drag_forwarding(Callable(), func(_at: Vector2, d: Variant) -> bool: return can_drop(d),
		func(_at: Vector2, d: Variant) -> void: drop(d))

	var tx := grid_bg.position.x
	var tw := gw
	desc_title = make_label("", 12, false)
	desc_title.position = Vector2(tx, grid_bg.position.y + gh + 4.0)
	desc_title.size = Vector2(tw, 15)
	desc_title.clip_text = true
	desc_title.add_theme_font_override("font", _mono_bold)
	body.add_child(desc_title)
	desc_body = make_label("", 9, false, INK_DIM)
	desc_body.position = Vector2(tx, desc_title.position.y + 15.0)
	desc_body.size = Vector2(tw, 34)
	desc_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_body.clip_text = true
	body.add_child(desc_body)
	make_notice(Rect2(12, panel_size.y - 48.0, panel_size.x - 24.0, 13))
	actions_row = HBoxContainer.new()
	actions_row.name = "Actions"
	actions_row.position = Vector2(12, panel_size.y - 34.0)
	actions_row.size = Vector2(panel_size.x - 24.0, 26)
	actions_row.add_theme_constant_override("separation", 6)
	actions_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(actions_row)


func _draw_figure() -> void:
	# Placeholder silhouette: head, torso, two arms, two legs. Black; green with a white highlight
	# once the suit is worn.
	var col := FIGURE_SUIT if suit_worn else FIGURE_COLOR
	var cx := figure.size.x * 0.5
	figure.draw_circle(Vector2(cx, 14), 12.0, col)
	figure.draw_rect(Rect2(cx - 19, 30, 38, 52), col)
	figure.draw_rect(Rect2(cx - 31, 31, 9, 40), col)
	figure.draw_rect(Rect2(cx + 22, 31, 9, 40), col)
	figure.draw_rect(Rect2(cx - 19, 85, 17, 58), col)
	figure.draw_rect(Rect2(cx + 2, 85, 17, 58), col)
	if suit_worn:
		var hi := FIGURE_SUIT_HI
		figure.draw_arc(Vector2(cx, 14), 9.0, PI * 1.05, PI * 1.65, 10, hi, 2.0, true)   # helmet glint
		figure.draw_rect(Rect2(cx - 8, 11, 16, 4), Color(hi, 0.55))                      # visor
		figure.draw_rect(Rect2(cx - 17, 32, 2, 48), hi)                                  # torso, left edge
		figure.draw_rect(Rect2(cx - 29, 33, 2, 36), hi)
		figure.draw_rect(Rect2(cx + 24, 33, 2, 36), hi)
		figure.draw_rect(Rect2(cx - 17, 87, 2, 54), hi)
		figure.draw_rect(Rect2(cx + 4, 87, 2, 54), hi)
		figure.draw_rect(Rect2(cx - 19, 54, 38, 2), Color(hi, 0.6))                      # belt line


## The figure turns green with a white highlight (suit on) or back to black.
func set_suit_worn(on: bool) -> void:
	suit_worn = on
	if figure != null:
		figure.queue_redraw()


func set_name_text(text: String) -> void:
	name_label.text = text if text.strip_edges() != "" else "NAME"


## items: [{"item": Dictionary, "dim": bool}, ...] in grid order (extra entries are cut off).
func set_slots(entries: Array) -> void:
	var keep := selected_id
	for i in slots.size():
		var s: Control = slots[i]
		if i < entries.size():
			var e: Dictionary = entries[i]
			s.set_item(e.get("item", {}), bool(e.get("dim", false)))
		else:
			s.set_item({})
		s.set_selected(false)
	selected_id = ""
	if keep != "":
		select_id(keep)
	else:
		confirm_text = ""
		_show_detail({})
		_refresh_actions()


func _on_opening() -> void:
	confirm_text = ""
	_show_detail(selected_item())
	_refresh_actions()


func select_id(id: String) -> void:
	selected_id = ""
	confirm_text = ""
	var found: Dictionary = {}
	for s: Control in slots:
		var hit: bool = not s.item.is_empty() and str(s.item.get("id", "")) == id
		s.set_selected(hit)
		if hit:
			found = s.item
			selected_id = id
	_show_detail(found)
	_refresh_actions()
	if not found.is_empty():
		item_selected.emit(found)


func selected_item() -> Dictionary:
	for s: Control in slots:
		if s.selected:
			return s.item
	return {}


func slot_for(id: String) -> Control:
	for s: Control in slots:
		if not s.item.is_empty() and str(s.item.get("id", "")) == id:
			return s
	return null


func filled_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Control in slots:
		if not s.item.is_empty() and not s.dim:
			out.append(str(s.item.get("id", "")))
	return out


func _on_slot_pressed(s: Control) -> void:
	if not is_interactive():
		return
	select_id(str(s.item.get("id", "")))


func _show_detail(it: Dictionary) -> void:
	desc_title.text = confirm_text if confirm_text != "" else str(it.get("label", ""))
	desc_body.text = str(it.get("detail", ""))
	desc_body.add_theme_font_size_override("font_size", 9)


## Buttons for the selected item: "Put on (1 hr)" (wearables) and "Drop"; while the Put on? prompt is
## up: YES / CANCEL.
func _refresh_actions() -> void:
	for b in action_buttons:
		if is_instance_valid(b):
			b.queue_free()
	action_buttons.clear()
	var it := selected_item()
	if it.is_empty():
		return
	if confirm_text != "":
		_add_action("yes", "YES", _on_confirm.bind(true))
		_add_action("cancel", "CANCEL", _on_confirm.bind(false))
		return
	for a: Variant in it.get("actions", ["drop"]):
		var aid := str(a)
		match aid:
			"wear":
				var hrs := int(it.get("wear_hours", 1))
				_add_action("wear", "Put on%s" % ((" (%s)" % hour_text(hrs)) if hrs > 0 else ""), _on_action_pressed.bind("wear"))
			"drop":
				_add_action("drop", "Drop", _on_action_pressed.bind("drop"))


func _add_action(aid: String, text: String, cb: Callable) -> void:
	var b := make_button(text, Vector2(0, 26))
	b.name = "Action_" + aid
	b.pressed.connect(cb)
	actions_row.add_child(b)
	action_buttons.append(b)


static func hour_text(hrs: int) -> String:
	return "1 hr" if hrs == 1 else "%d hrs" % hrs


func action_button(aid: String) -> Button:
	for b in action_buttons:
		if is_instance_valid(b) and b.name == "Action_" + aid:
			return b
	return null


func do_action(aid: String) -> void:
	_on_action_pressed(aid)


func _on_action_pressed(aid: String) -> void:
	if not is_interactive():
		return
	var it := selected_item()
	if it.is_empty():
		return
	if aid == "wear":
		var hrs := int(it.get("wear_hours", 1))
		confirm_text = "Put on?%s" % ((" (%s)" % hour_text(hrs)) if hrs > 0 else "")
		_show_detail(it)
		_refresh_actions()
		return
	item_action.emit(aid, it.duplicate(true))


func _on_confirm(yes: bool) -> void:
	if not is_interactive():
		return
	var it := selected_item()
	confirm_text = ""
	_show_detail(it)
	_refresh_actions()
	if yes and not it.is_empty():
		item_action.emit("wear", it.duplicate(true))


# drag-and-drop target (container items dropped on the inventory)
func can_drop(data: Variant) -> bool:
	return is_interactive() and can_drop_cb.is_valid() and bool(can_drop_cb.call(data))


func drop(data: Variant) -> void:
	if can_drop(data) and drop_cb.is_valid():
		drop_cb.call(data)
