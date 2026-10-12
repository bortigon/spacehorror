extends "res://ui/holo_window.gd"
## LOG WINDOW: the TRM-CUFF log as a hologram pop-up (same CRT open / close and look as the
## inventory windows, centred). Left: the entries, grouped under category headers (SHIP, COMPANY,
## TUTORIALS... any category an entry names). Right: the selected entry's text. Top: a "Search Log"
## bar (code-drawn magnifying glass) that filters the list by title and text. EXIT bottom right
## (Esc closes it too, through the window manager).
## Entries: [{id, title, text, category}] from the owner (PdaScreen.log_entries()).

signal exit_requested
signal entry_selected(entry_id: String)

const CATEGORY_ORDER := ["SHIP", "COMPANY", "TUTORIALS"]
const LIST_W := 168.0

var entries: Array = []
var selected_id := ""
var title_label: Label
var search_edit: LineEdit
var search_icon: Control
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var text_box: RichTextLabel
var exit_button: Button
var entry_buttons: Dictionary = {}     # id -> Button (what is listed now)


func _init() -> void:
	panel_size = Vector2(540, 340)
	build()


func _build_body() -> void:
	body.add_child(make_panel_bg())
	title_label = make_label("LOG", 15, true)
	title_label.position = Vector2(12, 8)
	title_label.size = Vector2(80, 22)
	body.add_child(title_label)
	# search bar: a LineEdit with room on the left for the drawn magnifying glass
	search_edit = LineEdit.new()
	search_edit.name = "SearchLog"
	search_edit.placeholder_text = "Search Log"
	search_edit.position = Vector2(12 + 70, 8)
	search_edit.size = Vector2(panel_size.x - 24.0 - 70.0, 24)
	search_edit.add_theme_font_override("font", _mono)
	search_edit.add_theme_font_size_override("font_size", 11)
	search_edit.add_theme_color_override("font_color", Color(0.86, 1.0, 0.86))
	search_edit.add_theme_color_override("font_placeholder_color", Color(0.62, 0.82, 0.66, 0.8))
	search_edit.add_theme_color_override("caret_color", Color(0.86, 1.0, 0.86))
	var sb := StyleBoxFlat.new()
	sb.bg_color = GRID_BG
	sb.border_color = GRID_LINE
	sb.set_border_width_all(1)
	sb.content_margin_left = 24
	sb.content_margin_right = 6
	search_edit.add_theme_stylebox_override("normal", sb)
	var sbf := sb.duplicate() as StyleBoxFlat
	sbf.border_color = WIN_EDGE
	search_edit.add_theme_stylebox_override("focus", sbf)
	search_edit.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	body.add_child(search_edit)
	search_icon = Control.new()
	search_icon.name = "SearchIcon"
	search_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	search_icon.position = search_edit.position + Vector2(5, 4)
	search_icon.size = Vector2(16, 16)
	search_icon.draw.connect(func() -> void:
		var col := Color(0.86, 1.0, 0.86, 0.9)
		search_icon.draw_arc(Vector2(6.5, 6.5), 4.5, 0.0, TAU, 18, col, 1.6, true)
		search_icon.draw_line(Vector2(10, 10), Vector2(14.5, 14.5), col, 2.2, true))
	body.add_child(search_icon)
	# entry list (left)
	var list_bg := make_grid_bg(Rect2(12, 40, LIST_W, 248))
	list_bg.name = "LogList"
	body.add_child(list_bg)
	list_scroll = ScrollContainer.new()
	list_scroll.position = Vector2(16, 44)
	list_scroll.size = Vector2(LIST_W - 8.0, 240)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 2)
	list_scroll.add_child(list_box)
	# entry text (right)
	text_box = RichTextLabel.new()
	text_box.name = "LogText"
	text_box.bbcode_enabled = true
	text_box.scroll_active = true
	text_box.position = Vector2(12 + LIST_W + 12, 40)
	text_box.size = Vector2(panel_size.x - LIST_W - 36.0, 248)
	text_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_theme_color_override("default_color", INK)
	text_box.add_theme_font_override("normal_font", _mono)
	text_box.add_theme_font_override("bold_font", _mono_bold)
	text_box.add_theme_font_size_override("normal_font_size", 11)
	text_box.add_theme_font_size_override("bold_font_size", 12)
	text_box.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	body.add_child(text_box)
	exit_button = make_button("EXIT", Vector2(84, 30))
	exit_button.name = "Exit"
	exit_button.position = Vector2(panel_size.x - 94.0, 298)
	exit_button.size = Vector2(84, 30)
	exit_button.pressed.connect(func() -> void:
		if is_interactive():
			exit_requested.emit())
	body.add_child(exit_button)


## Loads the entries; `select` picks one (else the current one if still there, else the first).
func configure(p_entries: Array, select := "") -> void:
	entries = p_entries.duplicate(true)
	if select != "":
		selected_id = select
	search_edit.text = ""      # every opening starts with the whole list
	_rebuild_list()


func _on_opening() -> void:
	_rebuild_list()


## Categories in display order: the known ones first, then any other, alphabetically.
func categories() -> PackedStringArray:
	var seen: Dictionary = {}
	for e: Dictionary in entries:
		seen[str(e.get("category", "SHIP")).to_upper()] = true
	var out := PackedStringArray()
	for c: String in CATEGORY_ORDER:
		if seen.has(c):
			out.append(c)
	var rest: Array = []
	for c: Variant in seen.keys():
		if not (str(c) in CATEGORY_ORDER):
			rest.append(str(c))
	rest.sort()
	for c: Variant in rest:
		out.append(str(c))
	return out


## The entries the search lets through (case-insensitive, title or text).
func visible_entries() -> Array:
	var q := search_edit.text.strip_edges().to_lower()
	var out: Array = []
	for e: Dictionary in entries:
		if q == "" or str(e.get("title", "")).to_lower().contains(q) or str(e.get("text", "")).to_lower().contains(q):
			out.append(e)
	return out


func set_search(text: String) -> void:
	search_edit.text = text
	_rebuild_list()


func _rebuild_list() -> void:
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	entry_buttons.clear()
	var shown := visible_entries()
	var ids: Array = []
	for cat: String in categories():
		var in_cat: Array = []
		for e: Dictionary in shown:
			if str(e.get("category", "SHIP")).to_upper() == cat:
				in_cat.append(e)
		if in_cat.is_empty():
			continue
		var h := make_label(cat, 10, true, Color(0.80, 1.0, 0.80))
		h.name = "Cat_" + cat
		list_box.add_child(h)
		for e: Dictionary in in_cat:
			var eid := str(e.get("id", ""))
			var b := make_button(str(e.get("title", eid)), Vector2(LIST_W - 22.0, 22))
			b.name = "Entry_" + eid
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.add_theme_font_size_override("font_size", 10)
			b.pressed.connect(select_entry.bind(eid))
			list_box.add_child(b)
			entry_buttons[eid] = b
			ids.append(eid)
	if shown.is_empty():
		list_box.add_child(make_label("NO MATCH." if search_edit.text.strip_edges() != "" else "NOTHING LOGGED.", 10, false, Color(0.80, 1.0, 0.80)))
	if not (selected_id in ids):
		selected_id = str(ids[0]) if not ids.is_empty() else ""
	_show_selected()


func select_entry(eid: String) -> void:
	selected_id = eid
	_show_selected()
	entry_selected.emit(eid)


func selected_entry() -> Dictionary:
	for e: Dictionary in entries:
		if str(e.get("id", "")) == selected_id:
			return e
	return {}


func _show_selected() -> void:
	for eid: Variant in entry_buttons:
		var b: Button = entry_buttons[eid]
		b.modulate = Color(1.25, 1.25, 1.25) if str(eid) == selected_id else Color(1, 1, 1)
	var e := selected_entry()
	if e.is_empty():
		text_box.text = ""
		return
	text_box.text = "[b]%s[/b]\n\n%s" % [str(e.get("title", "")).replace("[", "[lb]"), str(e.get("text", "")).replace("[", "[lb]")]


func listed_ids() -> Array:
	return entry_buttons.keys()


## Rectangles for the tutorial highlights (global coordinates).
func list_rect() -> Rect2:
	return Rect2(global_position + Vector2(12, 40), Vector2(LIST_W, 248))


func search_rect() -> Rect2:
	return Rect2(global_position + search_edit.position, search_edit.size)


func exit_rect() -> Rect2:
	return Rect2(global_position + exit_button.position, exit_button.size)
