@tool
extends VBoxContainer
const SceneOrder := preload("res://ui/scene_order.gd")
## SCENE WRITER main screen: write a scene (title, speed, screens with effect markup, VO,
## sounds, endings), preview it with the game's fonts / theme / effects, save the JSON and
## build scenes/authored/<id>.tscn. No AI needed: everything is plain fields and buttons.
## Works in Godot 4.6 and 4.7 (no 4.7-only API). Guide: docs/SCENE_WRITER.md.

const SceneData := preload("res://ui/story_scene.gd")
const StageScript := preload("res://ui/story_stage.gd")
const Markup := preload("res://ui/story_markup.gd")
const Builder := preload("res://addons/scene_writer/scene_builder.gd")
const VoTiming := preload("res://addons/scene_writer/vo_timing.gd")
const THEME_PATH := "res://templates/pda_theme.tres"
const ACCENT := Color("#6fbf73")
const DIM := Color("#5f8f69")
const WARN := Color("#e0b040")
const ERR := Color("#e07040")
const NEW_CHAPTER := "New chapter…"
const NEW_SCENE := "New scene…"
const END_TYPES: Array[String] = ["continue", "choices", "death", "qte", "map_tour", "transition", "hold"]
const END_LABELS: Array[String] = ["CONTINUE button", "Choices", "Death", "O2 countdown (quick-time)",
	"Map walkthrough (HIGHLIGHT + TIP)", "Transition (time card)", "Hold (the scene stops here)"]
const RED_MODES: Array[String] = ["off", "static", "ramp"]
const RED_LABELS: Array[String] = ["Off", "Static", "Ramp (grows while the text types)"]
const LIST_UNDO_MAX := 20
const MARKUP_HELP := "[error]word[/error]  glitch   ·   [error level=6]  intensity 0-10   ·   [error=DEMON delay=1.5]name[/error]  readable, then the glitch text   ·   [expo]prose[/expo]  exposition font   ·   [shake]text[/shake]  or [shake=12]   ·   [pause=1.0]   ·   [b]bold[/b]  [i]italic[/i]   ·   empty line = paragraph   ·   {v:callsign}   ·   [act=locker]locker[/act]  act word, shown as LOCKER. Clicking replaces the screen. Back returns"

var editor_plugin = null           # the EditorPlugin (null in tests)
var data: Dictionary = {}
var cur := -1
var loaded_path := ""
var dirty := false
var _loading := false
var _check_t := -1.0
var _preview_t := -1.0
var _death_t := -1.0
var _death_retry := ""
var _death_fallback := 0
var _prev_screen := -1
var _built_ui := false
var _rebuilding := false
var _animated := false
var _scale := 1.0
var _confirm_action: Callable
var _outline_fill := false
## key -> true when that chapter or scene row is folded. Missing = use the default.
var _folded := {}
var audio_files: PackedStringArray = PackedStringArray()
var sound_files: PackedStringArray = PackedStringArray()
var ambiance_files: PackedStringArray = PackedStringArray()
var narration_files: PackedStringArray = PackedStringArray()
var image_files: PackedStringArray = PackedStringArray()

# top bar
var scene_pick: OptionButton
var status_label: Label
# scene column
var id_edit: LineEdit
var title_edit: LineEdit
var speed_slider: HSlider
var speed_value: Label
var bg_pick: OptionButton
var bg_alpha: HSlider
var bg_alpha_value: Label
var amb_pick: OptionButton
var narr_pick: OptionButton
var hud_check: CheckBox
var ui_check: CheckBox
var fade_spin: SpinBox
var after_pick: OptionButton
var screen_list: ItemList
# screen column
var screen_title: Label
var sid_edit: LineEdit
var heading_edit: LineEdit
var chapter_pick: OptionButton
var chapter_name: LineEdit
var scene_outline_pick: OptionButton
var scene_name: LineEdit
var on_list: CheckBox
var outline_earlier: Button
var outline_later: Button
var add_button: Button
var add_menu: PopupMenu
var name_dialog: ConfirmationDialog
var name_edit: LineEdit
var _name_kind := ""
var _pending_row := -1
var _did_drag := false
var _force_row := false
var undo_button: Button
var _list_undo: Array = []
var morph_edit: LineEdit
var error_level: OptionButton
var error_delay: SpinBox
var shake_spin: SpinBox
var pause_spin: SpinBox
var act_id_edit: LineEdit
var act_text_edit: TextEdit
var act_box: VBoxContainer
var act_container_check: CheckBox
var act_container_box: VBoxContainer
var act_title_edit: LineEdit
var act_cols_spin: SpinBox
var act_rows_spin: SpinBox
var act_add_button: Button
var act_back_note: Label
var text_edit: TextEdit
var question_edit: LineEdit
var sspeed_slider: HSlider
var sspeed_value: Label
var wshake_slider: HSlider
var wshake_value: Label
var red_mode: OptionButton
var red_from: HSlider
var red_from_label: Label
var red_from_value: Label
var red_to: HSlider
var red_to_value: Label
var red_to_row: HBoxContainer
var vo_pick: OptionButton
var vo_from: SpinBox
var vo_to: SpinBox
var cues_edit: TextEdit
var cue_info: Label
var sfx_box: VBoxContainer
var end_mode: OptionButton
var end_panels: Dictionary = {}
var cont_target: OptionButton
var choice_box: VBoxContainer
var death_heading: LineEdit
var death_message: LineEdit
var death_retry: OptionButton
var qte_label: LineEdit
var qte_seconds: SpinBox
var qte_target: OptionButton
var qte_fail: LineEdit
var qte_retry: OptionButton
var tour_box: VBoxContainer
var tour_move: OptionButton
var tour_prompt: LineEdit
var tour_arrive: LineEdit
var tour_target: OptionButton
var hold_target: OptionButton
var card_edit: LineEdit
var card_target: OptionButton
# preview column
var preview_vp: SubViewport
var preview_rect: TextureRect
var preview_bg: TextureRect
var stage: Control
var preview_death: Control
var preview_death_heading: Label
var preview_death_msg: Label
var preview_note: Label
var sound_check: CheckBox
var checks: RichTextLabel
var confirm: ConfirmationDialog


func _ready() -> void:
	_ensure_ui()


func _ui_current() -> bool:
	return chapter_pick != null and is_instance_valid(chapter_pick) \
		and scene_outline_pick != null and is_instance_valid(scene_outline_pick) \
		and on_list != null and is_instance_valid(on_list) \
		and screen_list != null and is_instance_valid(screen_list)


## Drop a dock left over from an older script (Add/Up/Down, no Chapter dropdown).
## A tool-script reload keeps those children and clears the new variables, so the
## next selected-access would hit Nil and the list would never fill.
func _discard_stale_ui() -> void:
	chapter_pick = null
	chapter_name = null
	scene_outline_pick = null
	scene_name = null
	on_list = null
	outline_earlier = null
	outline_later = null
	screen_list = null
	var kids := get_children()
	for c in kids:
		remove_child(c)
		c.free()


func _ensure_ui() -> void:
	if _ui_current():
		return
	if _rebuilding:
		return
	_rebuilding = true
	var keep: Dictionary = data.duplicate(true) if not data.is_empty() else {}
	var keep_cur := cur
	var keep_path := loaded_path
	var keep_dirty := dirty
	if get_child_count() > 0:
		_discard_stale_ui()
	_built_ui = true
	var ei = _ei()
	if ei and ei.has_method("get_editor_scale"):
		_scale = ei.get_editor_scale()
	_scan_assets()
	_build_ui()
	if keep.has("screens"):
		data = keep
		cur = keep_cur
		loaded_path = keep_path
		dirty = keep_dirty
		_load_scene_ui()
	else:
		var list := SceneData.list_scenes()
		var first := ""
		for e: Dictionary in preload("res://ui/scene_order.gd").flat_screens():   # the first scene on the outline
			var t := str(e.get("target", ""))
			if first == "" and t.begins_with("scene:") and list.has(t.substr(6).get_slice("/", 0)):
				first = t.substr(6).get_slice("/", 0)
		if first == "" and not list.is_empty():
			first = list[0]
		if first != "":
			open_scene(first)
		else:
			new_scene()
	_rebuilding = false


func on_shown() -> void:
	_ensure_ui()
	_refresh_scene_pick()


func _ei():
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		return null
	return Engine.get_singleton("EditorInterface")


func _s(v: float) -> float:
	return v * _scale


# ======================================================== UI BUILD

func _build_ui() -> void:
	add_theme_constant_override("separation", int(_s(6)))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(_s(6)))
	add_child(top)
	var title := Label.new()
	title.text = "SCENE WRITER"
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_font_size_override("font_size", int(_s(16)))
	top.add_child(title)
	top.add_child(_vsep())
	top.add_child(_button("New", new_scene_pressed, "Start a new, empty scene."))
	scene_pick = OptionButton.new()
	scene_pick.custom_minimum_size.x = _s(190)
	scene_pick.tooltip_text = "Scenes in res://story/scenes/"
	top.add_child(scene_pick)
	top.add_child(_button("Open", open_pressed, "Open the scene selected on the left."))
	top.add_child(_button("Save", save_pressed, "Save res://story/scenes/<id>.json"))
	top.add_child(_button("Build", build_pressed, "Save + write res://scenes/authored/<id>.tscn (uses the PDA template)."))
	top.add_child(_button("Play", play_pressed, "Build, then run the built scene."))
	top.add_child(_vsep())
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status_label.add_theme_color_override("font_color", DIM)
	top.add_child(status_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := _build_scene_column()
	split.add_child(left)
	var split2 := HSplitContainer.new()
	split2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(split2)
	split2.add_child(_build_screen_column())
	split2.add_child(_build_preview_column())

	confirm = ConfirmationDialog.new()
	confirm.title = "Scene Writer"
	confirm.confirmed.connect(func() -> void:
		if _confirm_action.is_valid():
			_confirm_action.call())
	add_child(confirm)


func _build_scene_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = _s(250)
	col.add_theme_constant_override("separation", int(_s(4)))
	col.add_child(_section("SCENE"))
	id_edit = _line(col, "Scene id", "file name, e.g. cargo_bay")
	id_edit.text_changed.connect(func(t: String) -> void: _set_scene("id", t))
	title_edit = _line(col, "Title", "shown at the top of every screen")
	title_edit.text_changed.connect(func(t: String) -> void: _set_scene("title", t))
	var sp := _slider_row(col, "Text speed", 5, 120, 1)
	speed_slider = sp[0]
	speed_value = sp[1]
	speed_slider.value_changed.connect(func(v: float) -> void:
		speed_value.text = "%d chars/s" % int(v)
		_set_scene("speed", int(v)))
	bg_pick = _option_row(col, "Background")
	bg_pick.item_selected.connect(func(i: int) -> void: _set_scene("background", str(bg_pick.get_item_metadata(i))))
	var ba := _slider_row(col, "Background dim", 0.0, 1.0, 0.01)
	bg_alpha = ba[0]
	bg_alpha_value = ba[1]
	bg_alpha.value_changed.connect(func(v: float) -> void:
		bg_alpha_value.text = "%d%%" % int(round(v * 100.0))
		_set_scene("background_alpha", v))
	amb_pick = _option_row(col, "Ambience")
	amb_pick.tooltip_text = "Loops for this scene. Lists assets/sounds/ambiance. Drag a wav, mp3, or ogg here. Game default is silence from this scene."
	amb_pick.item_selected.connect(func(i: int) -> void: _set_scene("ambience", str(amb_pick.get_item_metadata(i))))
	amb_pick.set_drag_forwarding(func(_at: Vector2): return null, _audio_can_drop, _drop_ambiance)
	hud_check = CheckBox.new()
	hud_check.text = "Show O2 bar + minimap"
	hud_check.toggled.connect(func(on: bool) -> void: _set_scene("show_hud", on))
	col.add_child(hud_check)
	ui_check = CheckBox.new()
	ui_check.text = "Main game UI (tab rail + map)"
	ui_check.tooltip_text = "On: the screens play inside the game's main UI (header, O2, LOG / DECK tabs, title,\nminimap; the full map opens). Off: the full-screen story stage (like the intro)."
	ui_check.toggled.connect(func(on: bool) -> void: _set_scene("ui", "game" if on else "stage"))
	col.add_child(ui_check)
	var fr := HBoxContainer.new()
	fr.add_child(_label("Fade in (s)", 110))
	fade_spin = _spin(0.0, 10.0, 0.1, 0.0)
	fade_spin.tooltip_text = "Seconds the scene fades in from black when it opens (0 = no fade)."
	fade_spin.value_changed.connect(func(v: float) -> void: _set_scene("fade_in", snappedf(v, 0.01)))
	fr.add_child(fade_spin)
	col.add_child(fr)
	after_pick = _option_row(col, "When it ends")
	after_pick.tooltip_text = "Where \"Next screen\" goes after the last screen. NEXT follows the next subscene in story/SCENE_ORDER.md."
	after_pick.item_selected.connect(func(i: int) -> void: _set_scene("after", str(after_pick.get_item_metadata(i))))

	col.add_child(_section("SCREENS"))
	chapter_pick = _option_row(col, "Chapter")
	chapter_pick.tooltip_text = "Chapter in story/SCENE_ORDER.md. Add puts a new subscene here. The list below is the whole outline."
	chapter_pick.item_selected.connect(_on_chapter_picked)
	chapter_name = _line(col, "Chapter name", "e.g. CHAPTER 1")
	chapter_name.tooltip_text = "Used when Chapter is New chapter…."
	chapter_name.focus_exited.connect(_apply_outline)
	scene_outline_pick = _option_row(col, "Scene")
	scene_outline_pick.tooltip_text = "Scene in that chapter. Add puts a new subscene here. The debug menu has one button per scene."
	scene_outline_pick.item_selected.connect(_on_scene_picked)
	scene_name = _line(col, "Scene name", "e.g. AIRLOCK")
	scene_name.tooltip_text = "Used when Scene is New scene…."
	scene_name.focus_exited.connect(_apply_outline)
	screen_list = ItemList.new()
	screen_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_list.custom_minimum_size.y = _s(160)
	screen_list.tooltip_text = "Drag a chapter, scene, or subscene to reorder it. Drop a subscene on a scene to move it. Click a chapter or scene to fold it. Double-click a subscene to open it."
	screen_list.item_selected.connect(_on_subscene_row)
	screen_list.item_activated.connect(_on_row_activated)
	screen_list.gui_input.connect(_on_list_gui)
	screen_list.set_drag_forwarding(_screen_drag_data, _screen_can_drop, _screen_drop)
	col.add_child(screen_list)
	var row := HBoxContainer.new()
	add_button = _button("Add", _show_add_menu, "Add a chapter, a scene, or a subscene.")
	row.add_child(add_button)
	add_menu = PopupMenu.new()
	add_menu.add_item("Chapter", 0)
	add_menu.add_item("Scene", 1)
	add_menu.add_item("Subscene", 2)
	add_menu.id_pressed.connect(_on_add_kind)
	add_child(add_menu)
	name_dialog = ConfirmationDialog.new()
	name_dialog.title = "Add"
	name_dialog.ok_button_text = "Add"
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name"
	name_dialog.add_child(name_edit)
	name_dialog.confirmed.connect(_on_add_name_ok)
	name_edit.text_submitted.connect(func(_t: String) -> void:
		name_dialog.hide()
		_on_add_name_ok())
	add_child(name_dialog)
	row.add_child(_button("Duplicate", duplicate_screen, "Copy the selected screen in the open file."))
	row.add_child(_button("Delete", delete_screen, "Delete the selected screen from the open file and take it off the list."))
	undo_button = _button("Undo", undo_list, "Undo the last chapter, scene, or subscene change (Ctrl+Z). Does not undo screen text.")
	row.add_child(undo_button)
	col.add_child(row)
	var ord := HBoxContainer.new()
	outline_earlier = _button("Earlier", _outline_nudge.bind(-1), "Move this subscene earlier in the scene.")
	outline_later = _button("Later", _outline_nudge.bind(1), "Move this subscene later in the scene.")
	ord.add_child(outline_earlier)
	ord.add_child(outline_later)
	col.add_child(ord)
	on_list = CheckBox.new()
	on_list.text = "On the list"
	on_list.tooltip_text = "Checked: the screen you are editing is a subscene of the chapter and scene above."
	on_list.toggled.connect(_on_list_toggled)
	col.add_child(on_list)
	return col


func _build_screen_column() -> Control:
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.x = _s(400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(_s(4)))
	sc.add_child(col)
	screen_title = _section("SCREEN")
	col.add_child(screen_title)
	sid_edit = _line(col, "Screen id", "short name, e.g. s1 or airlock")
	sid_edit.text_submitted.connect(func(_t: String) -> void: _commit_screen_id())
	sid_edit.focus_exited.connect(_commit_screen_id)
	heading_edit = _line(col, "Heading", "optional big line above the text")
	heading_edit.text_changed.connect(func(t: String) -> void: _set_screen("heading", t))

	var tb := HFlowContainer.new()
	tb.add_theme_constant_override("h_separation", int(_s(4)))
	tb.add_child(_button("ERROR glitch", func() -> void: _wrap(_error_open(""), "[/error]"),
		"Selected word scrambles while it types, then settles amber. Level 0 is this look. Level 10 is hard to read."))
	error_level = OptionButton.new()
	for i in 11:
		error_level.add_item("Level %d" % i)
	error_level.select(0)
	error_level.tooltip_text = "Glitch intensity. Level 0 is the current ERROR look. Level 10 is so erratic it is hard to read."
	tb.add_child(error_level)
	error_delay = _spin(0.0, 10.0, 0.1, Markup.MORPH_HOLD)
	error_delay.custom_minimum_size.x = _s(72)
	error_delay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	error_delay.suffix = "s"
	error_delay.tooltip_text = "How long the original text stays readable before the glitch text overwrites it."
	tb.add_child(error_delay)
	tb.add_child(_button("Becomes:", func() -> void: _wrap(_error_open(_morph_word()), "[/error]"),
		"Selected text stays readable, then after the delay it is overwritten by this glitch text."))
	morph_edit = LineEdit.new()
	morph_edit.text = "ERROR"
	morph_edit.custom_minimum_size.x = _s(80)
	morph_edit.tooltip_text = "What the selected text turns into."
	tb.add_child(morph_edit)
	tb.add_child(_vsep())
	tb.add_child(_button("Shake", func() -> void:
		var lv := int(shake_spin.value)
		_wrap("[shake]" if lv == Markup.SHAKE_DEFAULT else "[shake=%d]" % lv, "[/shake]"),
		"Selected text shakes."))
	shake_spin = _spin(1, 20, 1, Markup.SHAKE_DEFAULT)
	shake_spin.tooltip_text = "Shake strength (1-20)."
	shake_spin.prefix = "level"
	tb.add_child(shake_spin)
	tb.add_child(_vsep())
	tb.add_child(_button("Pause", func() -> void: _insert("[pause=%s]" % _num(pause_spin.value)),
		"Typing stops here for the seconds on the right."))
	pause_spin = _spin(0.1, 10.0, 0.1, 1.0)
	pause_spin.suffix = "s"
	tb.add_child(pause_spin)
	tb.add_child(_vsep())
	tb.add_child(_button("Bold", func() -> void: _wrap("[b]", "[/b]")))
	tb.add_child(_button("Italic", func() -> void: _wrap("[i]", "[/i]")))
	tb.add_child(_button("Exposition", func() -> void: _wrap("[expo]", "[/expo]"),
		"Selected text uses the exposition serif (IBM Plex Serif), for describing a room."))
	tb.add_child(_vsep())
	tb.add_child(_button("Interactable", func() -> void:
		var id := SceneData.sanitize_id(act_id_edit.text)
		if id == "":
			id = "act"
		_wrap("[act=%s]" % id, "[/act]"),
		"Wraps the selection as an act word. It is shown in capitals, bold, and underlined. Clicking it replaces this screen with the act."))
	var id_lab := Label.new()
	id_lab.text = "Id"
	tb.add_child(id_lab)
	act_id_edit = LineEdit.new()
	act_id_edit.text = "locker"
	act_id_edit.custom_minimum_size.x = _s(88)
	act_id_edit.placeholder_text = "id"
	act_id_edit.tooltip_text = "Act id. The body tag is [act=id]word[/act]. The word is shown in capitals."
	act_id_edit.text_changed.connect(func(_t: String) -> void:
		if not _loading:
			_rebuild_act_editor())
	tb.add_child(act_id_edit)
	tb.add_child(_button("Remove effects", _strip_selection, "Remove effect tags from the selection."))
	col.add_child(tb)

	text_edit = TextEdit.new()
	text_edit.custom_minimum_size.y = _s(190)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.placeholder_text = "Write the screen text here. One line per sentence / VO line."
	text_edit.syntax_highlighter = _highlighter()
	text_edit.text_changed.connect(func() -> void:
		_set_screen("text", text_edit.text)
		_update_list_item(cur)
		_update_cue_info())
	col.add_child(text_edit)
	var help := Label.new()
	help.text = MARKUP_HELP
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", DIM)
	help.add_theme_font_size_override("font_size", int(_s(11)))
	col.add_child(help)
	var act_head := HBoxContainer.new()
	act_head.add_child(_section("ACT"))
	act_add_button = _button("Add option", _add_act_action, "Adds a choice. Hours show as (1 hr) or (N hrs). Back is not a choice.")
	act_head.add_child(act_add_button)
	act_container_check = CheckBox.new()
	act_container_check.name = "ActContainer"
	act_container_check.text = "Container"
	act_container_check.tooltip_text = "A container opens as a window (with the character screen beside it) instead of replacing the screen text. Its items are taken one by one."
	act_container_check.toggled.connect(_on_act_container_toggled)
	act_head.add_child(act_container_check)
	col.add_child(act_head)
	act_back_note = Label.new()
	act_back_note.name = "ActBackNote"
	act_back_note.text = "Back is added automatically and is not a row you edit. Back returns to the text that called this act."
	act_back_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	act_back_note.add_theme_color_override("font_color", DIM)
	act_back_note.add_theme_font_size_override("font_size", int(_s(11)))
	col.add_child(act_back_note)
	act_container_box = VBoxContainer.new()
	act_container_box.name = "ContainerFields"
	act_container_box.add_theme_constant_override("separation", int(_s(4)))
	var title_row := HBoxContainer.new()
	title_row.add_child(_label("Window title", 110))
	act_title_edit = LineEdit.new()
	act_title_edit.name = "ContainerTitle"
	act_title_edit.placeholder_text = "LOCKER"
	act_title_edit.tooltip_text = "Title at the top-left of the window. Empty = the act id in capitals."
	act_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act_title_edit.text_changed.connect(_on_container_title_changed)
	title_row.add_child(act_title_edit)
	title_row.add_child(_label("Grid", 40))
	act_cols_spin = _spin(1, 8, 1, 3)
	act_cols_spin.name = "ContainerCols"
	act_cols_spin.suffix = "cols"
	act_cols_spin.value_changed.connect(func(_v: float) -> void: _on_container_grid_changed())
	title_row.add_child(act_cols_spin)
	act_rows_spin = _spin(1, 8, 1, 3)
	act_rows_spin.name = "ContainerRows"
	act_rows_spin.suffix = "rows"
	act_rows_spin.value_changed.connect(func(_v: float) -> void: _on_container_grid_changed())
	title_row.add_child(act_rows_spin)
	act_container_box.add_child(title_row)
	col.add_child(act_container_box)
	act_text_edit = TextEdit.new()
	act_text_edit.name = "ActText"
	act_text_edit.custom_minimum_size.y = _s(72)
	act_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	act_text_edit.placeholder_text = "Replacement text (container: description under the title)"
	act_text_edit.tooltip_text = "Function: this replaces the screen when the act word is clicked (it may contain [act=id]word[/act]). Container: the description shown under the window title."
	act_text_edit.text_changed.connect(_on_act_text_changed)
	col.add_child(act_text_edit)
	act_box = VBoxContainer.new()
	act_box.name = "ActOptions"
	act_box.add_theme_constant_override("separation", int(_s(4)))
	col.add_child(act_box)
	question_edit = _line(col, "Pinned question", "automatic: last line of this screen")
	question_edit.tooltip_text = "After a response, the next screen shows this line + the response at the top."
	question_edit.text_changed.connect(func(t: String) -> void: _set_screen("question", t))

	col.add_child(_section("EFFECTS"))
	var ss := _slider_row(col, "Speed override", 0, 120, 1)
	sspeed_slider = ss[0]
	sspeed_value = ss[1]
	sspeed_slider.value_changed.connect(func(v: float) -> void:
		sspeed_value.text = "scene speed" if v <= 0 else "%d chars/s" % int(v)
		_set_screen("speed", int(v)))
	var ws := _slider_row(col, "Whole-screen shake", 0, 20, 1)
	wshake_slider = ws[0]
	wshake_value = ws[1]
	wshake_slider.value_changed.connect(func(v: float) -> void:
		wshake_value.text = "off" if v <= 0 else str(int(v))
		_set_screen("shake", int(v)))
	red_mode = _option_row(col, "Red edges")
	for i in RED_LABELS.size():
		red_mode.add_item(RED_LABELS[i])
	red_mode.item_selected.connect(func(i: int) -> void:
		_set_red("mode", RED_MODES[i])
		_update_red_rows())
	var rf := _slider_row(col, "Red level", 0.0, 1.0, 0.01)
	red_from = rf[0]
	red_from_value = rf[1]
	red_from_label = rf[2]
	red_from.value_changed.connect(func(v: float) -> void:
		red_from_value.text = "%d%%" % int(round(v * 100.0))
		_set_red("from", v))
	var rt := _slider_row(col, "Red at the end", 0.0, 1.0, 0.01)
	red_to = rt[0]
	red_to_value = rt[1]
	red_to_row = red_to.get_parent() as HBoxContainer
	red_to.value_changed.connect(func(v: float) -> void:
		red_to_value.text = "%d%%" % int(round(v * 100.0))
		_set_red("to", v))

	col.add_child(_section("VOICE (optional)"))
	narr_pick = _option_row(col, "Narration")
	narr_pick.tooltip_text = "This screen's narration. It is the voice clip, so the screen plays it with the text. Lists assets/sounds/narration. Drag a sound here."
	narr_pick.item_selected.connect(func(i: int) -> void:
		if _loading:
			return
		_set_vo("clip", str(narr_pick.get_item_metadata(i)))
		_sync_voice_dropdowns()
		_update_cue_info())
	narr_pick.set_drag_forwarding(func(_at: Vector2): return null, _audio_can_drop, _drop_narration)
	vo_pick = _option_row(col, "Voice clip")
	vo_pick.tooltip_text = "Same voice clip as Narration. Use this for a file that already lives in assets/sounds."
	vo_pick.item_selected.connect(func(i: int) -> void:
		if _loading:
			return
		_set_vo("clip", str(vo_pick.get_item_metadata(i)))
		_sync_voice_dropdowns()
		_update_cue_info())
	var vr := HBoxContainer.new()
	vr.add_child(_label("Play from", 110))
	vo_from = _spin(0.0, 600.0, 0.01, 0.0)
	vo_from.suffix = "s"
	vo_from.value_changed.connect(func(v: float) -> void: _set_vo("from", v))
	vr.add_child(vo_from)
	vr.add_child(_label("  to", 0))
	vo_to = _spin(-1.0, 600.0, 0.01, -1.0)
	vo_to.suffix = "s"
	vo_to.tooltip_text = "-1 = end of the clip"
	vo_to.value_changed.connect(func(v: float) -> void: _set_vo("to", v))
	vr.add_child(vo_to)
	col.add_child(vr)
	var cr := HBoxContainer.new()
	cr.add_child(_button("Auto-time from pauses", auto_time_pressed,
		"WAV only: finds the pauses in the voice and gives each text line its start / end time."))
	cr.add_child(_button("Spread evenly", spread_pressed, "Spread the lines over the clip (any audio type)."))
	cr.add_child(_button("Clear times", func() -> void:
		cues_edit.text = ""
		_cues_changed(), "No cue times: the text types at the screen speed while the voice plays."))
	col.add_child(cr)
	cues_edit = TextEdit.new()
	cues_edit.custom_minimum_size.y = _s(84)
	cues_edit.placeholder_text = "Cue times, one per text line:  start - end  (seconds in the clip)\n1.09 - 3.16\n3.94 - 8.22"
	cues_edit.text_changed.connect(_cues_changed)
	col.add_child(cues_edit)
	cue_info = Label.new()
	cue_info.add_theme_color_override("font_color", DIM)
	col.add_child(cue_info)

	col.add_child(_section("SOUNDS (optional)"))
	sfx_box = VBoxContainer.new()
	col.add_child(sfx_box)
	col.add_child(_button("Add sound", add_sfx, "Play a sound when a line starts typing or after some seconds."))

	col.add_child(_section("ENDING"))
	end_mode = _option_row(col, "Screen ends with")
	for i in END_LABELS.size():
		end_mode.add_item(END_LABELS[i])
	end_mode.item_selected.connect(func(i: int) -> void: _set_end_type(END_TYPES[i]))
	# continue
	var pc := VBoxContainer.new()
	cont_target = _option_row(pc, "CONTINUE goes to")
	cont_target.item_selected.connect(func(i: int) -> void: _set_end("goto", str(cont_target.get_item_metadata(i))))
	end_panels["continue"] = pc
	col.add_child(pc)
	# choices
	var pch := VBoxContainer.new()
	choice_box = VBoxContainer.new()
	pch.add_child(choice_box)
	pch.add_child(_button("Add choice", add_choice))
	end_panels["choices"] = pch
	col.add_child(pch)
	# death
	var pd := VBoxContainer.new()
	death_heading = _line(pd, "Heading", "SIGNAL LOST")
	death_heading.text_changed.connect(func(t: String) -> void: _set_end("heading", t))
	death_message = _line(pd, "Message", "OPERATOR DECEASED")
	death_message.text_changed.connect(func(t: String) -> void: _set_end("message", t))
	death_retry = _option_row(pd, "RETRY goes to")
	death_retry.item_selected.connect(func(i: int) -> void: _set_end("retry", str(death_retry.get_item_metadata(i))))
	end_panels["death"] = pd
	col.add_child(pd)
	# qte
	var pq := VBoxContainer.new()
	qte_label = _line(pq, "Button text", SceneData.DEFAULT_QTE_LABEL)
	qte_label.text_changed.connect(func(t: String) -> void: _set_end("label", t))
	var qr := HBoxContainer.new()
	qr.add_child(_label("Seconds", 110))
	qte_seconds = _spin(1.0, 120.0, 0.5, 10.0)
	qte_seconds.value_changed.connect(func(v: float) -> void: _set_end("seconds", v))
	qr.add_child(qte_seconds)
	pq.add_child(qr)
	qte_target = _option_row(pq, "In time goes to")
	qte_target.item_selected.connect(func(i: int) -> void: _set_end("goto", str(qte_target.get_item_metadata(i))))
	qte_fail = _line(pq, "Too late message", "OPERATOR DECEASED")
	qte_fail.text_changed.connect(func(t: String) -> void: _set_end("fail_message", t))
	qte_retry = _option_row(pq, "RETRY goes to")
	qte_retry.item_selected.connect(func(i: int) -> void: _set_end("retry", str(qte_retry.get_item_metadata(i))))
	end_panels["qte"] = pq
	col.add_child(pq)
	# map walkthrough
	var pm := VBoxContainer.new()
	var mhelp := _label("One tip at a time over the full map: the target is highlighted, the rest dimmed, tip text + CONTINUE next to it.", 0)
	mhelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mhelp.add_theme_color_override("font_color", DIM)
	pm.add_child(mhelp)
	tour_box = VBoxContainer.new()
	pm.add_child(tour_box)
	pm.add_child(_button("Add tip", add_tip, "Add a tip at the end."))
	tour_move = _option_row(pm, "Then walk to")
	tour_move.tooltip_text = "After the last tip the map stays open and the player clicks rooms to move until they reach this room."
	tour_move.item_selected.connect(func(i: int) -> void: _set_end("move_to", str(tour_move.get_item_metadata(i))))
	tour_prompt = _line(pm, "Walk prompt", "e.g. Please proceed to the READY ROOM.")
	tour_prompt.tooltip_text = "Shown in the map's info line while the player walks."
	tour_prompt.text_changed.connect(func(t: String) -> void: _set_end("move_prompt", t))
	tour_arrive = _line(pm, "On arrival (ops)", "e.g. map_restrict_room:stbd_hold")
	tour_arrive.tooltip_text = "State ops run on the still-open map when the player arrives (comma-separated), e.g. map_restrict_room:stbd_hold pops a RESTRICTED stamp."
	tour_arrive.text_changed.connect(func(t: String) -> void: _set_end("on_arrive", arrive_ops_from_text(t)))
	tour_target = _option_row(pm, "Then goes to")
	tour_target.item_selected.connect(func(i: int) -> void: _set_end("goto", str(tour_target.get_item_metadata(i))))
	end_panels["map_tour"] = pm
	col.add_child(pm)
	# hold
	var ph := VBoxContainer.new()
	var hhelp := _label("The scene stops on this screen. With a target a CONTINUE button leads on (the hook for the next chapter).", 0)
	hhelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hhelp.add_theme_color_override("font_color", DIM)
	ph.add_child(hhelp)
	hold_target = _option_row(ph, "CONTINUE goes to")
	hold_target.item_selected.connect(func(i: int) -> void: _set_end("goto", str(hold_target.get_item_metadata(i))))
	end_panels["hold"] = ph
	col.add_child(ph)
	# transition card
	var pt := VBoxContainer.new()
	var thelp := _label("A black card, like ONE HOUR LATER. It fades in, holds, and fades out, then continues. Keys do nothing while it is up.", 0)
	thelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thelp.add_theme_color_override("font_color", DIM)
	pt.add_child(thelp)
	card_edit = _line(pt, "Card text", "ONE HOUR LATER")
	card_edit.tooltip_text = "The line on the black card, for example ONE HOUR LATER."
	card_edit.text_changed.connect(func(t: String) -> void: _set_end("card", t))
	card_target = _option_row(pt, "Then goes to")
	card_target.item_selected.connect(func(i: int) -> void: _set_end("goto", str(card_target.get_item_metadata(i))))
	end_panels["transition"] = pt
	col.add_child(pt)
	return sc


func _build_preview_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = _s(440)
	col.add_theme_constant_override("separation", int(_s(4)))
	var head := HBoxContainer.new()
	head.add_child(_section("PREVIEW"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	sound_check = CheckBox.new()
	sound_check.text = "Sound"
	sound_check.button_pressed = true
	head.add_child(sound_check)
	head.add_child(_button("Replay", replay_preview, "Play this screen from the start (typing, voice, effects)."))
	head.add_child(_button("Skip", func() -> void: stage.press(), "Finish the typing (like pressing Space in the game)."))
	col.add_child(head)

	preview_vp = SubViewport.new()
	preview_vp.size = Vector2i(960, 540)
	preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_vp.transparent_bg = false
	col.add_child(preview_vp)
	var root := Control.new()
	root.name = "PreviewRoot"
	root.size = Vector2(960, 540)
	if ResourceLoader.exists(THEME_PATH):
		root.theme = load(THEME_PATH)
	preview_vp.add_child(root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(960, 540)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(black)
	preview_bg = TextureRect.new()
	preview_bg.size = Vector2(960, 540)
	preview_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(preview_bg)
	stage = StageScript.new()
	stage.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stage.size = Vector2(960, 540)
	root.add_child(stage)
	stage.continue_pressed.connect(_pv_continue)
	stage.choice_pressed.connect(_pv_choice)
	stage.qte_pressed.connect(_pv_qte)
	stage.qte_expired.connect(_pv_qte_expired)
	stage.typing_done.connect(_pv_typing_done)
	_build_preview_death(root)

	preview_rect = TextureRect.new()
	preview_rect.texture = preview_vp.get_texture()
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_rect.custom_minimum_size = Vector2(_s(432), _s(243))
	preview_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_rect.gui_input.connect(_preview_input)
	col.add_child(preview_rect)
	preview_note = Label.new()
	preview_note.add_theme_color_override("font_color", DIM)
	preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(preview_note)

	col.add_child(_section("CHECKS"))
	checks = RichTextLabel.new()
	checks.bbcode_enabled = true
	checks.custom_minimum_size.y = _s(120)
	checks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	checks.meta_clicked.connect(func(meta: Variant) -> void:
		var s := str(meta)
		if s.begins_with("screen:"):
			select_screen(int(s.substr(7))))
	col.add_child(checks)
	return col


func _build_preview_death(root: Control) -> void:
	preview_death = ColorRect.new()
	(preview_death as ColorRect).color = Color(0, 0, 0, 0.92)
	preview_death.size = Vector2(960, 540)
	preview_death.hide()
	root.add_child(preview_death)
	var cc := CenterContainer.new()
	cc.size = Vector2(960, 540)
	preview_death.add_child(cc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	cc.add_child(box)
	preview_death_heading = Label.new()
	preview_death_heading.theme_type_variation = &"PauseTitle"
	preview_death_heading.add_theme_color_override("font_color", ERR)
	preview_death_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(preview_death_heading)
	preview_death_msg = Label.new()
	preview_death_msg.theme_type_variation = &"OsLabel"
	preview_death_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_death_msg.custom_minimum_size.x = 480
	preview_death_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(preview_death_msg)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	box.add_child(gap)
	var retry := Button.new()
	retry.text = "RETRY"
	retry.custom_minimum_size = Vector2(220, 40)
	retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry.focus_mode = Control.FOCUS_NONE
	retry.pressed.connect(_pv_retry)
	box.add_child(retry)


# ---------------------------------------------------------------- small widgets

## Effect tags in green, {v:...} variables in amber, everything else plain.
func _highlighter() -> SyntaxHighlighter:
	var hl := CodeHighlighter.new()
	var plain := get_theme_color("font_color", "TextEdit")
	hl.number_color = plain
	hl.symbol_color = plain
	hl.function_color = plain
	hl.member_variable_color = plain
	hl.add_color_region("[", "]", ACCENT, false)
	hl.add_color_region("{", "}", WARN, false)
	return hl


## Scrolls the middle (screen) column, e.g. down to VOICE / ENDING (screenshots).
func scroll_screen_column(px: int) -> void:
	var sc := text_edit.get_parent().get_parent() as ScrollContainer
	if sc:
		sc.scroll_vertical = px


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ACCENT)
	return l


func _label(text: String, width: float) -> Label:
	var l := Label.new()
	l.text = text
	if width > 0:
		l.custom_minimum_size.x = _s(width)
	return l


func _vsep() -> VSeparator:
	return VSeparator.new()


func _button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _spin(mn: float, mx: float, step: float, val: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size.x = _s(90)
	return s


func _line(parent: Control, label: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_child(_label(label, 110))
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	parent.add_child(row)
	return e


func _option_row(parent: Control, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_child(_label(label, 110))
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	row.add_child(o)
	parent.add_child(row)
	return o


## [slider, value label, name label]
func _slider_row(parent: Control, label: String, mn: float, mx: float, step: float) -> Array:
	var row := HBoxContainer.new()
	var name_l := _label(label, 110)
	row.add_child(name_l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := _label("", 96)
	v.add_theme_color_override("font_color", ACCENT)
	row.add_child(v)
	parent.add_child(row)
	return [s, v, name_l]


func _num(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0") and not s.ends_with(".0"):
		s = s.substr(0, s.length() - 1)
	return s


func _morph_word() -> String:
	var w := morph_edit.text.strip_edges().replace("]", "").replace("[", "")
	return w if w != "" else "ERROR"


## [error], [error level=N], or [error=WORD level=N delay=S]. Defaults match the old tags.
func _error_open(replacement: String) -> String:
	var lv := error_level.selected if error_level != null else 0
	var d := error_delay.value if error_delay != null else Markup.MORPH_HOLD
	var extra := ""
	if lv > 0:
		extra += " level=%d" % lv
	if not is_equal_approx(d, Markup.MORPH_HOLD):
		extra += " delay=%s" % _num(d)
	if replacement == "":
		return "[error]" if extra == "" else "[error%s]" % extra
	return "[error=%s%s]" % [replacement, extra]


# ======================================================== ASSET LISTS

const AMBIANCE_DIR := "res://assets/sounds/ambiance"
const NARRATION_DIR := "res://assets/sounds/narration"


func _scan_assets() -> void:
	audio_files = _files("res://assets", ["wav", "mp3", "ogg"])
	sound_files = _files("res://assets/sounds", ["wav", "mp3", "ogg"])
	ambiance_files = _files(AMBIANCE_DIR, ["wav", "mp3", "ogg"])
	narration_files = _files(NARRATION_DIR, ["wav", "mp3", "ogg"])
	image_files = _files("res://assets", ["png", "jpg", "jpeg", "webp"])


func _files(dir: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in exts:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		out.append_array(_files(dir.path_join(d), exts))
	out.sort()
	return out


func _fill_files(o: OptionButton, files: PackedStringArray, value: String, none_label: String) -> void:
	o.clear()
	o.add_item(none_label)
	o.set_item_metadata(0, "")
	var sel := 0
	for f in files:
		o.add_item(f.trim_prefix("res://assets/sounds/").trim_prefix("res://"))
		o.set_item_tooltip(o.item_count - 1, f)
		o.set_item_metadata(o.item_count - 1, f)
		if f == value:
			sel = o.item_count - 1
	if value != "" and sel == 0:
		o.add_item("(missing) " + value)
		o.set_item_metadata(o.item_count - 1, value)
		sel = o.item_count - 1
	o.select(sel)


## Target dropdown: next / screens / other scenes / intro passages (+ the current value if custom).
func _fill_target(o: OptionButton, value: String, with_next: bool, default_label := "") -> void:
	o.clear()
	var items: Array = []
	if default_label != "":
		items.append([default_label, ""])
	items.append(["NEXT", "order:next"])
	if with_next:
		items.append(["Next screen", "next"])
	for s: Dictionary in data.get("screens", []):
		items.append(["Screen: " + str(s["id"]), str(s["id"])])
	for sc in SceneData.list_scenes():
		if sc != str(data.get("id", "")):
			items.append(["Scene: " + sc, "scene:" + sc])
	for p in SceneData.INTRO_PASSAGES:
		items.append(["Intro: " + p, "intro:" + p])
	var sel := -1
	var v := value
	if with_next and v == "":
		v = "next"
	for it: Array in items:
		o.add_item(str(it[0]))
		o.set_item_metadata(o.item_count - 1, str(it[1]))
		if str(it[1]) == v:
			sel = o.item_count - 1
	if sel < 0 and v != "":
		o.add_item("Custom: " + v)
		o.set_item_metadata(o.item_count - 1, v)
		sel = o.item_count - 1
	o.select(maxi(sel, 0))


func _refresh_scene_pick() -> void:
	if scene_pick == null:
		return
	var keep := str(data.get("id", ""))
	scene_pick.clear()
	var list := SceneData.list_scenes()
	for sc in list:
		scene_pick.add_item(sc)
		if sc == keep:
			scene_pick.select(scene_pick.item_count - 1)
	if list.is_empty():
		scene_pick.add_item("(no scenes yet)")
		scene_pick.disabled = true
	else:
		scene_pick.disabled = false


# ======================================================== SCENE / SCREEN LOADING

func new_scene_pressed() -> void:
	_guard_dirty(new_scene)


func new_scene() -> void:
	_ensure_ui()
	var base := "new_scene"
	var id := base
	var n := 2
	var existing := SceneData.list_scenes()
	while existing.has(id):
		id = "%s_%d" % [base, n]
		n += 1
	data = SceneData.new_scene(id)
	(data["screens"][0] as Dictionary)["text"] = "Write your first screen here."
	data["after"] = "order:next"   # When it ends = NEXT (story/SCENE_ORDER.md)
	loaded_path = ""
	cur = 0
	_load_scene_ui()
	dirty = true
	_status("New scene \"%s\" (not saved yet)." % id)


func open_pressed() -> void:
	if scene_pick.disabled or scene_pick.selected < 0:
		return
	var id := scene_pick.get_item_text(scene_pick.selected)
	_guard_dirty(open_scene.bind(id))


func open_file(path: String) -> bool:
	_ensure_ui()
	var d := SceneData.load_file(path)
	if d.is_empty():
		_status(SceneData.last_error, true)
		return false
	data = d
	loaded_path = path
	cur = 0 if not (data["screens"] as Array).is_empty() else -1
	_load_scene_ui()
	dirty = false
	_status("Opened %s" % path)
	return true


func open_scene(id: String) -> bool:
	return open_file(SceneData.json_path(id))


func _guard_dirty(action: Callable) -> void:
	if not dirty:
		action.call()
		return
	_confirm_action = action
	confirm.dialog_text = "The scene \"%s\" has unsaved changes.\nDiscard them?" % str(data.get("id", ""))
	confirm.popup_centered()


func _load_scene_ui() -> void:
	_loading = true
	id_edit.text = str(data["id"])
	title_edit.text = str(data["title"])
	speed_slider.value = float(data["speed"])
	speed_value.text = "%d chars/s" % int(data["speed"])
	_fill_files(bg_pick, image_files, str(data["background"]), "(none)")
	bg_alpha.value = float(data["background_alpha"])
	bg_alpha_value.text = "%d%%" % int(round(float(data["background_alpha"]) * 100.0))
	_fill_files(amb_pick, ambiance_files, str(data["ambience"]), "(game default)")
	hud_check.button_pressed = bool(data["show_hud"])
	ui_check.button_pressed = str(data.get("ui", "stage")) == "game"
	fade_spin.value = float(data.get("fade_in", 0.0))
	_fill_target(after_pick, str(data["after"]), false, "(nothing)")
	_rebuild_screen_list()
	_loading = false
	_refresh_scene_pick()
	_load_screen_ui()
	_schedule_checks()


func _visible_subscenes() -> Array:
	if chapter_pick == null or scene_outline_pick == null:
		return []
	var ch_title := _chosen_chapter()
	var sc_title := _chosen_scene()
	if ch_title == "" or sc_title == "":
		return []
	for ch in SceneOrder.chapters():
		if str(ch.get("title", "")) != ch_title:
			continue
		for sc in ch.get("scenes", []):
			if str(sc.get("title", "")) != sc_title:
				continue
			var out: Array = []
			for sub in sc.get("screens", []):
				var row: Dictionary = (sub as Dictionary).duplicate()
				row["chapter"] = ch_title
				row["scene"] = sc_title
				out.append(row)
			return out
	return []


func _end_tag(end_type: String) -> String:
	return {"continue": "", "choices": "  [choices]", "death": "  [death]", "qte": "  [O2]",
		"map_tour": "  [map]", "transition": "  [card]", "hold": "  [hold]"}.get(end_type, "")


func _json_catalog() -> Dictionary:
	var out := {}
	var open_id := str(data.get("id", ""))
	if open_id != "" and data.has("screens"):
		out[open_id] = data
	for id in SceneData.list_scenes():
		if out.has(id):
			continue
		var loaded := SceneData.load_file(SceneData.json_path(id))
		if not loaded.is_empty():
			out[id] = loaded
	return out


func _screen_facts(catalog: Dictionary, file_id: String, screen_id: String) -> Dictionary:
	if not catalog.has(file_id):
		return {}
	for s in catalog[file_id].get("screens", []):
		if str(s.get("id", "")) == screen_id:
			var end := ""
			if s.get("end") is Dictionary:
				end = str((s["end"] as Dictionary).get("type", ""))
			return {"heading": str(s.get("heading", "")).strip_edges(), "end": end}
	return {}


## The outline only. A story/scenes file that has no line in SCENE_ORDER.md is not shown.
func _tree_chapters(_catalog: Dictionary) -> Array:
	return SceneOrder.chapters().duplicate(true)


func _fold_key_chapter(title: String) -> String:
	return "ch\n" + title


func _fold_key_scene(chapter: String, scene_title: String) -> String:
	return "sc\n%s\n%s" % [chapter, scene_title]


func _row_open(key: String, default_open: bool) -> bool:
	if _folded.has(key):
		return not bool(_folded[key])
	return default_open


var _fold_tick := 0
var _fold_last := ""


func _toggle_row(key: String, default_open: bool) -> void:
	# A double-click is two selects. Fold once, so the row does not spring back open.
	var now := Time.get_ticks_msec()
	if key == _fold_last and now - _fold_tick < 400:
		return
	_fold_tick = now
	_fold_last = key
	_folded[key] = _row_open(key, default_open)
	_rebuild_screen_list()


func _current_target() -> String:
	var scr := _cur_screen()
	if scr.is_empty():
		return ""
	return "scene:%s/%s" % [str(data.get("id", "")), str(scr.get("id", ""))]


func list_row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if screen_list == null:
		return out
	for i in screen_list.item_count:
		out.append(screen_list.get_item_text(i))
	return out


func _rebuild_screen_list() -> void:
	if screen_list == null:
		return
	var catalog := _json_catalog()
	var here := _current_target()
	var ch_now := _chosen_chapter()
	var sc_now := _chosen_scene()
	screen_list.set_block_signals(true)
	screen_list.clear()
	for ch in _tree_chapters(catalog):
		var ch_title := str(ch.get("title", ""))
		var ch_has_here := false
		for sc in ch.get("scenes", []):
			for sub in sc.get("screens", []):
				if str(sub.get("target", "")) == here:
					ch_has_here = true
		var ch_default := ch_title == ch_now or ch_has_here
		var ch_open := _row_open(_fold_key_chapter(ch_title), ch_default)
		var ch_i := screen_list.item_count
		screen_list.add_item("%s %s" % ["▾" if ch_open else "▸", ch_title])
		screen_list.set_item_metadata(ch_i, {"kind": "chapter", "chapter": ch_title, "key": _fold_key_chapter(ch_title), "default_open": ch_default})
		if not ch_open:
			continue
		for sc in ch.get("scenes", []):
			var sc_title := str(sc.get("title", ""))
			var sc_has_here := false
			for sub in sc.get("screens", []):
				if str(sub.get("target", "")) == here:
					sc_has_here = true
			var sc_default := sc_has_here or (ch_title == ch_now and sc_title == sc_now)
			var sc_open := _row_open(_fold_key_scene(ch_title, sc_title), sc_default)
			var sc_i := screen_list.item_count
			screen_list.add_item("  %s %s" % ["▾" if sc_open else "▸", sc_title])
			screen_list.set_item_metadata(sc_i, {"kind": "scene", "key": _fold_key_scene(ch_title, sc_title), "default_open": sc_default,
				"chapter": ch_title, "scene": sc_title})
			if not sc_open:
				continue
			for sub in sc.get("screens", []):
				var name := str(sub.get("screen", "")) if str(sub.get("screen", "")) != "" else str(sub.get("id", ""))
				var note := str(sub.get("label", ""))
				var tag := ""
				if str(sub.get("kind", "")) == "scene":
					var facts := _screen_facts(catalog, str(sub.get("id", "")), str(sub.get("screen", "")))
					tag = _end_tag(str(facts.get("end", "")))
					if note == "":
						note = str(facts.get("heading", ""))
				var text := "    %s" % name
				if note != "" and note != name:
					text += "  " + note
				text += tag
				var i := screen_list.item_count
				screen_list.add_item(text)
				var meta := (sub as Dictionary).duplicate()
				meta["kind_row"] = "sub"
				meta["chapter"] = ch_title
				meta["scene"] = sc_title
				screen_list.set_item_metadata(i, meta)
	_highlight_current_subscene()
	screen_list.set_block_signals(false)


func _highlight_current_subscene() -> void:
	var want := _current_target()
	if want == "":
		return
	for i in screen_list.item_count:
		var meta = screen_list.get_item_metadata(i)
		if meta is Dictionary and str(meta.get("target", "")) == want:
			screen_list.select(i)
			screen_list.ensure_current_is_visible()
			return


func _update_list_item(_i: int) -> void:
	_rebuild_screen_list()


func _on_list_gui(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	var pending := _pending_row
	var dragged := _did_drag
	_pending_row = -1
	_did_drag = false
	if dragged or pending < 0:
		return
	_force_row = true
	_on_subscene_row(pending)
	_force_row = false


func _row_kind(meta: Dictionary) -> String:
	if str(meta.get("kind_row", "")) == "sub":
		return "sub"
	if str(meta.get("kind", "")) == "chapter":
		return "chapter"
	if str(meta.get("kind", "")) == "scene":
		return "scene"
	return ""


func _screen_drag_data(at: Vector2) -> Variant:
	if screen_list == null:
		return null
	var i := screen_list.get_item_at_position(at, true)
	if i < 0:
		return null
	var meta = screen_list.get_item_metadata(i)
	if not (meta is Dictionary):
		return null
	if _row_kind(meta) == "" or str(meta.get("chapter", "")) == "NOT ON THE LIST":
		return null
	_did_drag = true
	_pending_row = -1
	var preview := Label.new()
	preview.text = screen_list.get_item_text(i).strip_edges()
	screen_list.set_drag_preview(preview)
	return (meta as Dictionary).duplicate()


func _screen_can_drop(at: Vector2, data: Variant) -> bool:
	if screen_list == null or not (data is Dictionary):
		return false
	var i := screen_list.get_item_at_position(at, true)
	if i < 0:
		return false
	var dst = screen_list.get_item_metadata(i)
	if not (dst is Dictionary):
		return false
	return _drop_allowed(data, dst)


func _screen_drop(at: Vector2, data: Variant) -> void:
	if screen_list == null or not (data is Dictionary):
		return
	var i := screen_list.get_item_at_position(at, true)
	if i < 0:
		return
	var dst = screen_list.get_item_metadata(i)
	if not (dst is Dictionary):
		return
	var after := false
	if screen_list.has_method("get_item_rect"):
		var rect: Rect2 = screen_list.call("get_item_rect", i)
		after = at.y >= rect.position.y + rect.size.y * 0.5
	_apply_drop(data, dst, after)


func _drop_allowed(src: Dictionary, dst: Dictionary) -> bool:
	var sk := _row_kind(src)
	var dk := _row_kind(dst)
	if sk == "" or dk == "" or str(src.get("chapter", "")) == "NOT ON THE LIST" or str(dst.get("chapter", "")) == "NOT ON THE LIST":
		return false
	if sk == "sub":
		return dk == "sub" or dk == "scene"
	if sk == "scene":
		return dk == "scene" or dk == "chapter" or dk == "sub"
	if sk == "chapter":
		return true
	return false


## Headless tests call this. A real drop uses the same rules. Upper half inserts before, lower half after.
func _apply_drop(src: Dictionary, dst: Dictionary, after: bool) -> void:
	if not _drop_allowed(src, dst):
		return
	var sk := _row_kind(src)
	var dk := _row_kind(dst)
	if sk == "sub":
		var anchor := ""
		var chapter := str(dst.get("chapter", ""))
		var scene_title := str(dst.get("scene", ""))
		if dk == "sub":
			anchor = str(dst.get("target", ""))
			if anchor == str(src.get("target", "")):
				return
		_snapshot_list(false)
		SceneOrder.move_subscene(str(src.get("target", "")), chapter, scene_title, anchor, after if dk == "sub" else false)
		_folded[_fold_key_chapter(chapter)] = false
		_folded[_fold_key_scene(chapter, scene_title)] = false
	elif sk == "scene":
		var to_ch := str(dst.get("chapter", ""))
		var anchor_scene := ""
		if dk == "chapter":
			after = false
		else:
			anchor_scene = str(dst.get("scene", ""))
			if anchor_scene == str(src.get("scene", "")) and to_ch == str(src.get("chapter", "")):
				return
		_snapshot_list(false)
		SceneOrder.move_scene(str(src.get("chapter", "")), str(src.get("scene", "")), to_ch, anchor_scene, after)
		_folded[_fold_key_chapter(to_ch)] = false
		if anchor_scene != "":
			_folded[_fold_key_scene(to_ch, str(src.get("scene", "")))] = false
	else:
		var anchor := str(dst.get("chapter", ""))
		if anchor == str(src.get("chapter", "")):
			return
		_snapshot_list(false)
		SceneOrder.move_chapter(str(src.get("chapter", "")), anchor, after)
		_folded[_fold_key_chapter(str(src.get("chapter", "")))] = false
	_rebuild_screen_list()
	_status("Moved on the list.")


func _on_subscene_row(i: int) -> void:
	if _loading or _outline_fill or screen_list == null:
		return
	if i < 0 or i >= screen_list.item_count:
		return
	var meta = screen_list.get_item_metadata(i)
	if not (meta is Dictionary):
		return
	var kind := str(meta.get("kind_row", meta.get("kind", "")))
	if kind == "chapter" or kind == "scene":
		_toggle_row(str(meta.get("key", "")), bool(meta.get("default_open", false)))
		return
	if str(meta.get("kind", "")) == "scene" and str(meta.get("id", "")) == str(data.get("id", "")):
		var idx := _json_screen_index(str(meta.get("screen", "")))
		if idx >= 0 and idx != cur:
			select_screen(idx)
		return
	if str(meta.get("kind", "")) == "scene":
		_status("That subscene is in %s. Double-click it to open that file." % str(meta.get("id", "")))
		return
	_status("%s is an intro passage in scenes/intro.gd. It is on the list, not a Scene Writer file." % str(meta.get("id", "")))


func _on_row_activated(i: int) -> void:
	if _loading or _outline_fill or screen_list == null:
		return
	if i < 0 or i >= screen_list.item_count:
		return
	var meta = screen_list.get_item_metadata(i)
	if not (meta is Dictionary):
		return
	var kind := str(meta.get("kind_row", meta.get("kind", "")))
	if kind == "chapter" or kind == "scene":
		_toggle_row(str(meta.get("key", "")), bool(meta.get("default_open", false)))
		return
	_open_listed_subscene(meta)


## Save the open scene, then load this subscene. Intro passages stay put.
## A scene with no id, or one that would replace a different file, is not saved and not thrown away.
func _open_listed_subscene(meta: Dictionary) -> void:
	var target := str(meta.get("target", ""))
	if target.begins_with("intro:") or str(meta.get("kind", "")) == "intro":
		_status("%s is an intro passage in scenes/intro.gd. There is no Scene Writer file to open, so this scene was left as it is." % str(meta.get("id", target)), true)
		return
	if not target.begins_with("scene:"):
		return
	var rest := target.substr(6)
	var file_id := rest.get_slice("/", 0).strip_edges()
	var screen_id := rest.get_slice("/", 1).strip_edges() if rest.contains("/") else ""
	if file_id == "":
		return
	if file_id == str(data.get("id", "")):
		var same := _json_screen_index(screen_id)
		if same >= 0:
			select_screen(same)
		return
	if not _save_for_navigation():
		return
	if not open_scene(file_id):
		_status("No Scene Writer file for %s. Your text is still here." % file_id, true)
		return
	var idx := _json_screen_index(screen_id)
	if idx >= 0:
		select_screen(idx)


func _save_for_navigation() -> bool:
	if not dirty:
		return true
	_commit_screen_id()
	var d := SceneData.normalize(data)
	if str(d.get("id", "")) == "":
		_status("This scene has no id, so it was not saved and your text is still here.", true)
		return false
	var path := SceneData.json_path(str(d["id"]))
	if path != loaded_path and FileAccess.file_exists(path):
		_status("Not saved: %s already exists. Your text is still here." % path, true)
		return false
	if SceneData.save_file(d, path) != OK:
		_status(str(SceneData.last_error) + " Your text is still here.", true)
		return false
	data = d
	loaded_path = path
	dirty = false
	_scan()
	_refresh_scene_pick()
	_status("Saved %s" % path)
	return true


func _json_screen_index(screen_id: String) -> int:
	var screens: Array = data.get("screens", [])
	for i in screens.size():
		if str(screens[i].get("id", "")) == screen_id:
			return i
	return -1


func select_screen(i: int) -> void:
	var screens: Array = data.get("screens", [])
	if i < 0 or i >= screens.size():
		return
	_commit_screen_id()
	cur = i
	_load_screen_ui()


func _load_screen_ui() -> void:
	var screens: Array = data.get("screens", [])
	var has := cur >= 0 and cur < screens.size()
	if not has:
		screen_title.text = "SCREEN (none — press Add)"
		return
	_loading = true
	var s: Dictionary = screens[cur]
	screen_title.text = "SCREEN %d of %d" % [cur + 1, screens.size()]
	sid_edit.text = str(s["id"])
	heading_edit.text = str(s["heading"])
	_refresh_outline_ui()
	if text_edit.text != str(s["text"]):
		text_edit.text = str(s["text"])
		text_edit.clear_undo_history()
	question_edit.text = str(s["question"])
	sspeed_slider.value = float(s["speed"])
	sspeed_value.text = "scene speed" if int(s["speed"]) <= 0 else "%d chars/s" % int(s["speed"])
	wshake_slider.value = float(s["shake"])
	wshake_value.text = "off" if int(s["shake"]) <= 0 else str(int(s["shake"]))
	var red: Dictionary = s["red"]
	red_mode.select(maxi(0, RED_MODES.find(str(red["mode"]))))
	red_from.value = float(red["from"])
	red_from_value.text = "%d%%" % int(round(float(red["from"]) * 100.0))
	red_to.value = float(red["to"])
	red_to_value.text = "%d%%" % int(round(float(red["to"]) * 100.0))
	_update_red_rows()
	var vo: Dictionary = s["vo"]
	_fill_files(narr_pick, narration_files, str(vo["clip"]), "(no narration)")
	_fill_files(vo_pick, sound_files, str(vo["clip"]), "(no voice)")
	vo_from.value = float(vo["from"])
	vo_to.value = float(vo["to"])
	cues_edit.text = _cues_text(vo["cues"])
	_update_cue_info()
	_rebuild_sfx()
	_load_end_ui()
	var raw_acts: Variant = s.get("acts", {})
	var act_pick := "locker"
	if raw_acts is Dictionary and not (raw_acts as Dictionary).is_empty():
		act_pick = str((raw_acts as Dictionary).keys()[0])
	elif raw_acts is Array and not (raw_acts as Array).is_empty() and (raw_acts as Array)[0] is Dictionary:
		act_pick = str(((raw_acts as Array)[0] as Dictionary).get("id", "locker"))
	act_id_edit.text = act_pick
	_rebuild_act_editor()
	_loading = false
	_schedule_preview()


func _load_end_ui() -> void:
	var was := _loading
	_loading = true
	var end: Dictionary = data["screens"][cur]["end"]
	var t := str(end["type"])
	end_mode.select(maxi(0, END_TYPES.find(t)))
	for k: String in end_panels:
		(end_panels[k] as Control).visible = k == t
	match t:
		"continue":
			_fill_target(cont_target, str(end["goto"]), true)
		"choices":
			_rebuild_choices()
		"death":
			death_heading.text = str(end["heading"])
			death_message.text = str(end["message"])
			_fill_target(death_retry, str(end["retry"]), false, "(the screen before)")
		"qte":
			qte_label.text = str(end["label"])
			qte_seconds.value = float(end["seconds"])
			_fill_target(qte_target, str(end["goto"]), true)
			qte_fail.text = str(end["fail_message"])
			_fill_target(qte_retry, str(end["retry"]), false, "(this screen again)")
		"map_tour":
			_rebuild_tips()
			_fill_rooms(tour_move, str(end["move_to"]))
			tour_prompt.text = str(end["move_prompt"])
			tour_arrive.text = ", ".join(PackedStringArray(end.get("on_arrive", [])))
			_fill_target(tour_target, str(end["goto"]), true)
		"hold":
			_fill_target(hold_target, str(end["goto"]), false, "(stop here / \"When it ends\")")
		"transition":
			card_edit.text = str(end.get("card", ""))
			_fill_target(card_target, str(end.get("goto", "next")), true)
	_loading = was


## "a, b" → ["a", "b"] (walkthrough "On arrival" ops).
static func arrive_ops_from_text(t: String) -> Array:
	var out: Array = []
	for part in t.split(",", false):
		if part.strip_edges() != "":
			out.append(part.strip_edges())
	return out


## Rooms of the ship map (walkthrough "Then walk to").
func _fill_rooms(o: OptionButton, value: String) -> void:
	o.clear()
	o.add_item("(no walking: straight on)")
	o.set_item_metadata(0, "")
	var sel := 0
	var rooms: Dictionary = preload("res://data/vessel.gd").default_map().get("rooms", {})
	for id in rooms:
		o.add_item("%s (%s)" % [str(rooms[id].get("label", id)), id])
		o.set_item_metadata(o.item_count - 1, str(id))
		if str(id) == value:
			sel = o.item_count - 1
	if value != "" and sel == 0:
		o.add_item("(missing) " + value)
		o.set_item_metadata(o.item_count - 1, value)
		sel = o.item_count - 1
	o.select(sel)


## Walkthrough tips: number, target dropdown, tip text, remove.
func _rebuild_tips() -> void:
	for c in tour_box.get_children():
		c.queue_free()
	var list: Array = (_cur_screen()["end"] as Dictionary).get("tips", [])
	var targets := SceneData.tour_targets()
	for i in list.size():
		var tip: Dictionary = list[i]
		var row := HBoxContainer.new()
		row.add_child(_label("%d/%d" % [i + 1, list.size()], 36))
		var tgt := OptionButton.new()
		tgt.custom_minimum_size.x = _s(170)
		tgt.clip_text = true
		tgt.tooltip_text = "What the tip highlights on the map."
		var sel := -1
		for tg in targets:
			tgt.add_item(SceneData.tour_target_label(tg))
			tgt.set_item_metadata(tgt.item_count - 1, tg)
			if tg == str(tip["target"]):
				sel = tgt.item_count - 1
		if sel < 0:
			tgt.add_item("Custom: " + str(tip["target"]))
			tgt.set_item_metadata(tgt.item_count - 1, str(tip["target"]))
			sel = tgt.item_count - 1
		tgt.select(sel)
		tgt.item_selected.connect(func(k: int) -> void:
			tip["target"] = str(tgt.get_item_metadata(k))
			_mark())
		row.add_child(tgt)
		var txt := LineEdit.new()
		txt.placeholder_text = "Tip text"
		txt.text = str(tip["text"])
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.text_changed.connect(func(s: String) -> void:
			tip["text"] = s
			_mark())
		row.add_child(txt)
		row.add_child(_button("✕", func() -> void:
			list.remove_at(i)
			_rebuild_tips()
			_mark(), "Remove this tip."))
		tour_box.add_child(row)


func add_tip() -> void:
	var e: Dictionary = _cur_screen().get("end", {})
	if not e.has("tips"):
		return
	(e["tips"] as Array).append({"text": "", "target": "map"})
	_rebuild_tips()
	_mark()


func _update_red_rows() -> void:
	var m := RED_MODES[maxi(0, red_mode.selected)]
	red_from.get_parent().visible = m != "off"
	red_to_row.visible = m == "ramp"
	red_from_label.text = "Red at the start" if m == "ramp" else "Red level"


# ======================================================== EDITING

func _mark() -> void:
	if _loading:
		return
	dirty = true
	_schedule_checks()
	_schedule_preview()


## Setters ignore unchanged values (TextEdit reports loads a frame late; that is not an edit).
func _sync_voice_dropdowns() -> void:
	if narr_pick == null or vo_pick == null:
		return
	var clip := ""
	var scr := _cur_screen()
	if not scr.is_empty() and scr.get("vo") is Dictionary:
		clip = str((scr["vo"] as Dictionary).get("clip", ""))
	var was := _loading
	_loading = true
	_fill_files(narr_pick, narration_files, clip, "(no narration)")
	_fill_files(vo_pick, sound_files, clip, "(no voice)")
	_loading = was


func _audio_ext(path: String) -> bool:
	return path.get_extension().to_lower() in ["wav", "mp3", "ogg"]


func _audio_paths(data: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	var files: Array = []
	if data is Dictionary and (str(data.get("type", "")) == "files" or data.has("files")):
		files = data.get("files", [])
	elif data is PackedStringArray:
		for f in data:
			files.append(f)
	elif data is Array:
		files = data
	for f in files:
		var path := str(f)
		if _audio_ext(path):
			out.append(path)
	return out


func _audio_can_drop(_at: Vector2, data: Variant) -> bool:
	return not _audio_paths(data).is_empty()


func _drop_ambiance(_at: Vector2, data: Variant) -> void:
	_assign_dropped("ambiance", _audio_paths(data))


func _drop_narration(_at: Vector2, data: Variant) -> void:
	_assign_dropped("narration", _audio_paths(data))


## Copy a sound into the ambiance or narration folder if it is not already there, then select it.
func _assign_dropped(kind: String, paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	if kind == "narration" and _cur_screen().is_empty():
		_status("Open a screen first.", true)
		return
	var dir := AMBIANCE_DIR if kind == "ambiance" else NARRATION_DIR
	var dest := _import_audio(str(paths[0]), dir)
	if dest == "":
		return
	_scan_assets()
	if kind == "ambiance":
		_set_scene("ambience", dest)
		var was := _loading
		_loading = true
		_fill_files(amb_pick, ambiance_files, dest, "(game default)")
		_loading = was
	else:
		_set_vo("clip", dest)
		_sync_voice_dropdowns()
		_update_cue_info()
	_status("Using %s." % dest.get_file())


func _import_audio(src: String, dir: String) -> String:
	var path := src.replace("\\", "/")
	if not _audio_ext(path):
		_status("Drop a wav, mp3, or ogg.", true)
		return ""
	var abs_dir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if path.begins_with(dir.trim_suffix("/") + "/"):
		return path
	var dest := _unique_audio(dir, path.get_file())
	var from_abs := path if not path.begins_with("res://") else ProjectSettings.globalize_path(path)
	var err := DirAccess.copy_absolute(from_abs, ProjectSettings.globalize_path(dest))
	if err != OK:
		_status("Could not copy %s into %s." % [path.get_file(), dir], true)
		return ""
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		var ei = Engine.get_singleton("EditorInterface")
		if ei and ei.get_resource_filesystem():
			ei.get_resource_filesystem().update_file(dest)
	return dest


func _unique_audio(dir: String, filename: String) -> String:
	var dest := dir.path_join(filename)
	if not FileAccess.file_exists(dest):
		return dest
	var stem := filename.get_basename()
	var ext := filename.get_extension()
	var n := 2
	while FileAccess.file_exists(dir.path_join("%s_%d.%s" % [stem, n, ext])):
		n += 1
	return dir.path_join("%s_%d.%s" % [stem, n, ext])


func _set_scene(key: String, v: Variant) -> void:
	if _loading or (data.has(key) and data[key] == v):
		return
	data[key] = v
	if key == "background" or key == "background_alpha":
		_update_preview_bg()
	_mark()


func _cur_screen() -> Dictionary:
	var screens: Array = data.get("screens", [])
	return screens[cur] if cur >= 0 and cur < screens.size() else {}


func _set_screen(key: String, v: Variant) -> void:
	if _loading or _cur_screen().is_empty() or _cur_screen().get(key) == v:
		return
	_cur_screen()[key] = v
	if key == "heading" and on_list != null and on_list.button_pressed:
		SceneOrder.set_label(str(data.get("id", "")), str(_cur_screen().get("id", "")), _outline_label())
	_mark()


func _set_red(key: String, v: Variant) -> void:
	if _loading or _cur_screen().is_empty() or (_cur_screen()["red"] as Dictionary).get(key) == v:
		return
	(_cur_screen()["red"] as Dictionary)[key] = v
	_mark()


func _set_vo(key: String, v: Variant) -> void:
	if _loading or _cur_screen().is_empty() or (_cur_screen()["vo"] as Dictionary).get(key) == v:
		return
	(_cur_screen()["vo"] as Dictionary)[key] = v
	_mark()


func _set_end(key: String, v: Variant) -> void:
	if _loading or _cur_screen().is_empty() or (_cur_screen()["end"] as Dictionary).get(key) == v:
		return
	(_cur_screen()["end"] as Dictionary)[key] = v
	_update_list_item(cur)
	_mark()


func _set_end_type(t: String) -> void:
	if _loading or _cur_screen().is_empty():
		return
	var old: Dictionary = _cur_screen()["end"]
	var e := {"type": t}
	if t == "choices" and not old.has("choices"):
		e["choices"] = [{"label": "YES", "goto": "next", "ops": [], "if": ""}, {"label": "NO", "goto": "next", "ops": [], "if": ""}]
	if t == "map_tour" and not old.has("tips"):
		e["tips"] = [{"text": "", "target": "map"}]
	if old.has("goto") and t in ["continue", "qte", "map_tour", "transition"]:
		e["goto"] = old["goto"]
	if t == "transition" and old.has("card"):
		e["card"] = old["card"]
	_cur_screen()["end"] = SceneData.normalize_end(e)
	_load_end_ui()
	_update_list_item(cur)
	_mark()


func _commit_screen_id() -> void:
	var s := _cur_screen()
	if s.is_empty() or _loading:
		return
	var nid := SceneData.sanitize_id(sid_edit.text)
	var old := str(s["id"])
	if nid == "" or nid == old:
		sid_edit.text = old
		return
	s["id"] = nid
	sid_edit.text = nid
	SceneOrder.rename_screen(str(data.get("id", "")), old, nid)
	# keep links pointing at the renamed screen
	for o: Dictionary in data["screens"]:
		var e: Dictionary = o["end"]
		for k in ["goto", "retry"]:
			if str(e.get(k, "")) == old:
				e[k] = nid
		for c: Dictionary in e.get("choices", []):
			if str(c["goto"]) == old:
				c["goto"] = nid
	_rebuild_screen_list()
	_load_end_ui()
	_mark()


func _show_add_menu() -> void:
	if add_menu == null or add_button == null:
		return
	var r := add_button.get_global_rect()
	add_menu.position = Vector2i(r.position.x, r.position.y + r.size.y)
	add_menu.reset_size()
	add_menu.popup()


func _on_add_kind(id: int) -> void:
	if id == 0:
		_ask_outline_name("chapter")
	elif id == 1:
		_ask_outline_name("scene")
	else:
		add_screen()


func _ask_outline_name(kind: String) -> void:
	_name_kind = kind
	name_dialog.title = "Add chapter" if kind == "chapter" else "Add scene"
	name_edit.text = ""
	name_edit.placeholder_text = "CHAPTER 1" if kind == "chapter" else "AIRLOCK"
	name_dialog.popup_centered()
	name_edit.grab_focus()


func _on_add_name_ok() -> void:
	var name := name_edit.text.strip_edges()
	if _name_kind == "chapter":
		add_chapter_named(name)
	elif _name_kind == "scene":
		add_scene_named(name)


## Append a chapter to story/SCENE_ORDER.md and select it. Does not touch the open scene file.
func _snapshot_list(save_screens: bool) -> void:
	var rec := {"outline": SceneOrder.text()}
	if save_screens:
		rec["screens"] = (data.get("screens", []) as Array).duplicate(true)
		rec["cur"] = cur
	_list_undo.append(rec)
	while _list_undo.size() > LIST_UNDO_MAX:
		_list_undo.pop_front()


func undo_list() -> void:
	if _list_undo.is_empty():
		_status("Nothing to undo on the list.")
		return
	var rec: Dictionary = _list_undo.pop_back()
	SceneOrder.save_text(str(rec.get("outline", "")))
	if rec.has("screens"):
		data["screens"] = (rec["screens"] as Array).duplicate(true)
		cur = int(rec.get("cur", 0))
		if cur >= (data["screens"] as Array).size():
			cur = (data["screens"] as Array).size() - 1
		_load_screen_ui()
	else:
		_refresh_outline_ui()
	_status("Undid the last list change.")


func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if not key.ctrl_pressed or key.shift_pressed or key.alt_pressed:
		return
	if key.keycode != KEY_Z and key.physical_keycode != KEY_Z:
		return
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if focus is LineEdit or focus is TextEdit:
		return
	undo_list()
	get_viewport().set_input_as_handled()


func add_chapter_named(title: String) -> void:
	var name := title.strip_edges()
	if name == "":
		_status("Type a chapter name.", true)
		return
	_snapshot_list(false)
	SceneOrder.add_chapter(name)
	_refresh_outline_ui()
	_select_chapter_scene(name, "")
	_status("Added chapter %s." % name)


## Append a scene under the selected chapter (or the chapter typed in Chapter name) and select it.
func add_scene_named(title: String) -> void:
	var name := title.strip_edges()
	var chapter := _chosen_chapter()
	if name == "":
		_status("Type a scene name.", true)
		return
	if chapter == "":
		_status("Pick a chapter first (or choose New chapter and type its name).", true)
		return
	_snapshot_list(false)
	SceneOrder.add_scene(chapter, name)
	_refresh_outline_ui()
	_select_chapter_scene(chapter, name)
	_status("Added scene %s under %s." % [name, chapter])


func _select_chapter_scene(chapter: String, scene_title: String) -> void:
	if chapter_pick == null:
		return
	_outline_fill = true
	for i in chapter_pick.item_count:
		if chapter_pick.get_item_text(i) == chapter:
			chapter_pick.select(i)
			break
	_fill_scene_items({"scene": scene_title})
	if scene_title != "":
		for i in scene_outline_pick.item_count:
			if scene_outline_pick.get_item_text(i) == scene_title:
				scene_outline_pick.select(i)
				break
	_outline_fill = false
	_unfold_chosen()
	_rebuild_screen_list()
	_sync_on_list_checkbox()


func add_screen() -> void:
	var screens: Array = data["screens"]
	var prev_id := str(screens[cur]["id"]) if cur >= 0 and cur < screens.size() else ""
	var n := screens.size() + 1
	var ids := {}
	for s: Dictionary in screens:
		ids[str(s["id"])] = true
	while ids.has("s%d" % n):
		n += 1
	var at := cur + 1 if cur >= 0 else screens.size()
	var new_id := "s%d" % n
	_snapshot_list(true)
	screens.insert(at, SceneData.new_screen(new_id))
	cur = at
	_outline_auto_insert(prev_id, new_id)
	_rebuild_screen_list()
	_load_screen_ui()
	_mark()


func duplicate_screen() -> void:
	var s := _cur_screen()
	if s.is_empty():
		return
	var copy: Dictionary = s.duplicate(true)
	var ids := {}
	for o: Dictionary in data["screens"]:
		ids[str(o["id"])] = true
	var base := str(s["id"]) + "_copy"
	var nid := base
	var n := 2
	while ids.has(nid):
		nid = "%s%d" % [base, n]
		n += 1
	copy["id"] = nid
	(data["screens"] as Array).insert(cur + 1, copy)
	cur += 1
	_rebuild_screen_list()
	_load_screen_ui()
	_mark()


func delete_screen() -> void:
	var screens: Array = data["screens"]
	if cur < 0 or cur >= screens.size():
		return
	_snapshot_list(true)
	SceneOrder.remove_screen(str(data.get("id", "")), str(screens[cur].get("id", "")))
	screens.remove_at(cur)
	cur = mini(cur, screens.size() - 1)
	_rebuild_screen_list()
	_load_screen_ui()
	_mark()


func move_screen(dir: int) -> void:
	var screens: Array = data["screens"]
	var j := cur + dir
	if cur < 0 or j < 0 or j >= screens.size():
		return
	var tmp: Variant = screens[cur]
	screens[cur] = screens[j]
	screens[j] = tmp
	cur = j
	_rebuild_screen_list()
	_load_screen_ui()
	_mark()


## Wraps the selection (or inserts an empty pair at the caret) in effect tags.

func _on_act_text_changed() -> void:
	if _loading or act_text_edit == null or _cur_screen().is_empty():
		return
	var id := SceneData.sanitize_id(act_id_edit.text)
	if id == "":
		id = "act"
		act_id_edit.text = id
	var t := act_text_edit.text
	if t.strip_edges() == "" and _find_act(id).is_empty():
		return
	var spec := _ensure_act()
	spec["text"] = t
	_drop_act_if_empty(id, spec)
	_mark()


func _find_act(id: String) -> Dictionary:
	if id == "" or _cur_screen().is_empty():
		return {}
	var raw: Variant = _cur_screen().get("acts", {})
	if raw is Dictionary and (raw as Dictionary).has(id) and (raw as Dictionary)[id] is Dictionary:
		return (raw as Dictionary)[id]
	return {}


func _ensure_act() -> Dictionary:
	var id := SceneData.sanitize_id(act_id_edit.text)
	if id == "":
		id = "act"
		act_id_edit.text = id
	var s := _cur_screen()
	var found := _find_act(id)
	if not found.is_empty():
		return found
	if not s.has("acts") or not (s["acts"] is Dictionary):
		s["acts"] = {}   # (screens without acts have no "acts" key at all)
	var made := {"text": "", "choices": []}
	(s["acts"] as Dictionary)[id] = made
	return made


func _add_act_action() -> void:
	if _cur_screen().is_empty() or _loading:
		return
	var spec := _ensure_act()
	if spec.has("station"):
		return   # a station (coffee pot) has code-defined options
	if bool(spec.get("container", false)):
		_add_container_item(spec)
		return
	var choices: Array = spec["choices"]
	var n := choices.size() + 1
	choices.append({
		"label": "Option" if n == 1 else "Option %d" % n,
		"hours": 1,
		"item": "",
		"detail": "",
		"required": false,
	})
	_mark()
	_rebuild_act_editor()


## Container checkbox: turns the act into a window (items) or back into a function (choices). No data is lost.
func _on_act_container_toggled(on: bool) -> void:
	if _loading or _cur_screen().is_empty():
		return
	var spec := _ensure_act()
	if spec.has("station"):
		_rebuild_act_editor()   # stations stay stations
		return
	if on and not bool(spec.get("container", false)):
		var items: Array = []
		for c: Dictionary in spec.get("choices", []):
			items.append(SceneData.normalize_container_item(c))
		spec.erase("choices")
		spec["container"] = true
		spec["title"] = str(spec.get("title", SceneData.sanitize_id(act_id_edit.text).to_upper()))
		spec["grid"] = {"cols": SceneData.CONTAINER_COLS, "rows": SceneData.CONTAINER_ROWS}
		spec["items"] = items
	elif not on and bool(spec.get("container", false)):
		var choices: Array = []
		for it: Dictionary in spec.get("items", []):
			if "take" in (it.get("actions", ["take"]) as Array):
				choices.append({"label": str(it.get("label", "")), "hours": int(it.get("hours", 0)), "item": str(it.get("id", "")),
					"detail": str(it.get("detail", "")), "required": bool(it.get("required", false))})
		for k in ["container", "title", "grid", "items"]:
			spec.erase(k)
		spec["choices"] = choices
	_mark()
	_rebuild_act_editor()


func _on_container_title_changed(t: String) -> void:
	if _loading or _cur_screen().is_empty():
		return
	var spec := _find_act(SceneData.sanitize_id(act_id_edit.text))
	if spec.is_empty() or not bool(spec.get("container", false)):
		return
	spec["title"] = t
	_mark()


func _on_container_grid_changed() -> void:
	if _loading or _cur_screen().is_empty():
		return
	var spec := _find_act(SceneData.sanitize_id(act_id_edit.text))
	if spec.is_empty() or not bool(spec.get("container", false)):
		return
	spec["grid"] = {"cols": int(act_cols_spin.value), "rows": int(act_rows_spin.value)}
	_mark()


func _add_container_item(spec: Dictionary) -> void:
	var items: Array = spec["items"]
	var n := items.size() + 1
	var id := "item_%d" % n
	while items.any(func(it: Dictionary) -> bool: return str(it.get("id", "")) == id):
		n += 1
		id = "item_%d" % n
	items.append({"id": id, "label": id.to_upper().replace("_", " "), "hours": 1, "required": false, "detail": "", "actions": ["take"]})
	_mark()
	_rebuild_act_editor()


func _drop_act_if_empty(id: String, spec: Dictionary) -> void:
	if str(spec.get("text", "")).strip_edges() != "":
		return
	if bool(spec.get("container", false)) or spec.has("station"):
		return   # an act marked Container stays until the box is unticked (it has a window title and grid)
	if not (spec.get("choices", []) as Array).is_empty():
		return
	var raw: Variant = _cur_screen().get("acts", {})
	if not (raw is Dictionary):
		return
	(raw as Dictionary).erase(id)
	if (raw as Dictionary).is_empty():
		_cur_screen().erase("acts")


func _rebuild_act_editor() -> void:
	if act_box == null:
		return
	for c in act_box.get_children():
		c.queue_free()
	var id := SceneData.sanitize_id(act_id_edit.text)
	var spec := _find_act(id)
	if act_text_edit != null:
		var was := _loading
		_loading = true
		var body := str(spec.get("text", ""))
		if act_text_edit.text != body:
			act_text_edit.text = body
		_loading = was
	var is_container := bool(spec.get("container", false))
	var is_station := spec.has("station")
	var was2 := _loading
	_loading = true
	act_container_check.button_pressed = is_container
	act_container_check.disabled = is_station
	act_add_button.disabled = is_station
	act_container_box.visible = is_container
	act_back_note.visible = not is_container
	act_back_note.text = ("STATION (%s): a window with a picture and options, defined in code. Only its text is edited here." % str(spec.get("station", ""))) \
		if is_station else "Back is added automatically and is not a row you edit. Back returns to the text that called this act."
	act_add_button.text = "Add item" if is_container else "Add option"
	act_add_button.tooltip_text = "Adds an item to the container window. Take is its action." if is_container \
		else "Adds a choice. Hours show as (1 hr) or (N hrs). Back is not a choice."
	if is_container:
		act_title_edit.text = str(spec.get("title", ""))
		act_cols_spin.value = float((spec.get("grid", {}) as Dictionary).get("cols", SceneData.CONTAINER_COLS))
		act_rows_spin.value = float((spec.get("grid", {}) as Dictionary).get("rows", SceneData.CONTAINER_ROWS))
	_loading = was2
	if spec.is_empty():
		return
	if is_container:
		_rebuild_container_items(spec)
		return
	var choices: Array = spec.get("choices", [])
	for ad: Dictionary in choices:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(_s(4)))
		var lab := LineEdit.new()
		lab.text = str(ad.get("label", ""))
		lab.placeholder_text = "Label"
		lab.tooltip_text = "Choice label. A hour cost is added on the button, like (1 hr)."
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.text_changed.connect((func(t: String, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["label"] = t
			_mark()).bind(ad))
		row.add_child(lab)
		var hrs := _spin(0, 8, 1, float(ad.get("hours", 0)))
		hrs.suffix = "hr"
		hrs.tooltip_text = "Hours. 1 reads (1 hr). Any other count reads (N hrs). 0 adds nothing."
		hrs.value_changed.connect((func(v: float, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["hours"] = int(v)
			_mark()).bind(ad))
		row.add_child(hrs)
		var item := LineEdit.new()
		item.text = str(ad.get("item", ""))
		item.placeholder_text = "item id"
		item.tooltip_text = "Item id added to inventory when this choice is taken. suit and lantern already exist."
		item.custom_minimum_size.x = _s(80)
		item.text_changed.connect((func(t: String, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["item"] = SceneData.sanitize_id(t)
			_mark()).bind(ad))
		row.add_child(item)
		var req := CheckBox.new()
		req.text = "Required"
		req.tooltip_text = "Marks this choice required. Leaving still uses the screen's require item, such as require:suit."
		req.button_pressed = bool(ad.get("required", false))
		req.toggled.connect((func(on: bool, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["required"] = on
			_mark()).bind(ad))
		row.add_child(req)
		row.add_child(_button("Remove", (func(row_data: Dictionary) -> void:
			choices.erase(row_data)
			_drop_act_if_empty(id, spec)
			_mark()
			_rebuild_act_editor()).bind(ad)))
		act_box.add_child(row)


## One row per container item: id, label, hours, Required, detail.
func _rebuild_container_items(spec: Dictionary) -> void:
	var items: Array = spec.get("items", [])
	for ad: Dictionary in items:
		var row := VBoxContainer.new()
		row.name = "ItemRow"
		row.add_theme_constant_override("separation", int(_s(2)))
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", int(_s(4)))
		var iid := LineEdit.new()
		iid.name = "ItemId"
		iid.text = str(ad.get("id", ""))
		iid.placeholder_text = "id"
		iid.tooltip_text = "Item id added to the inventory when it is taken (sets the flag has_<id>). suit and lantern already exist."
		iid.custom_minimum_size.x = _s(90)
		iid.text_changed.connect((func(t: String, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["id"] = SceneData.sanitize_id(t)
			_mark()).bind(ad))
		top.add_child(iid)
		var lab := LineEdit.new()
		lab.name = "ItemLabel"
		lab.text = str(ad.get("label", ""))
		lab.placeholder_text = "Label"
		lab.tooltip_text = "Name shown on the item cell, in the description and on the button (Take LABEL)."
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.text_changed.connect((func(t: String, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["label"] = t
			_mark()).bind(ad))
		top.add_child(lab)
		var hrs := _spin(0, 8, 1, float(ad.get("hours", 0)))
		hrs.name = "ItemHours"
		hrs.suffix = "hr"
		hrs.tooltip_text = "Hours. 1 reads (1 hr) on the Take button. 0 adds nothing."
		hrs.value_changed.connect((func(v: float, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["hours"] = int(v)
			_mark()).bind(ad))
		top.add_child(hrs)
		var req := CheckBox.new()
		req.name = "ItemRequired"
		req.text = "Required"
		req.tooltip_text = "Marks this item required. Leaving still uses the screen's require item, such as require:suit."
		req.button_pressed = bool(ad.get("required", false))
		req.toggled.connect((func(on: bool, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["required"] = on
			_mark()).bind(ad))
		top.add_child(req)
		top.add_child(_button("Remove", (func(row_data: Dictionary) -> void:
			items.erase(row_data)
			_mark()
			_rebuild_act_editor()).bind(ad)))
		row.add_child(top)
		var detail := LineEdit.new()
		detail.name = "ItemDetail"
		detail.text = str(ad.get("detail", ""))
		detail.placeholder_text = "Detail text (shown when the item is highlighted and as its hover tip)"
		detail.text_changed.connect((func(t: String, row_data: Dictionary) -> void:
			if _loading:
				return
			row_data["detail"] = t
			_mark()).bind(ad))
		row.add_child(detail)
		act_box.add_child(row)


func _wrap(open: String, close: String) -> void:
	if _cur_screen().is_empty():
		return
	text_edit.begin_complex_operation()
	if text_edit.has_selection():
		var sel := text_edit.get_selected_text()
		text_edit.delete_selection()
		text_edit.insert_text_at_caret(open + sel + close)
	else:
		text_edit.insert_text_at_caret(open + close)
		text_edit.set_caret_column(text_edit.get_caret_column() - close.length())
	text_edit.end_complex_operation()
	text_edit.grab_focus()


func _insert(t: String) -> void:
	if _cur_screen().is_empty():
		return
	if text_edit.has_selection():
		text_edit.deselect()
	text_edit.insert_text_at_caret(t)
	text_edit.grab_focus()


func _strip_selection() -> void:
	if not text_edit.has_selection():
		return
	var re := RegEx.new()
	re.compile("\\[/?(error|shake|pause|b|i|expo|act)[^\\]]*\\]")
	var sel := text_edit.get_selected_text()
	text_edit.begin_complex_operation()
	text_edit.delete_selection()
	text_edit.insert_text_at_caret(re.sub(sel, "", true))
	text_edit.end_complex_operation()


# ---------------------------------------------------------------- choices

func _rebuild_choices() -> void:
	for c in choice_box.get_children():
		c.queue_free()
	var list: Array = (_cur_screen()["end"] as Dictionary).get("choices", [])
	for i in list.size():
		var c: Dictionary = list[i]
		var row := HBoxContainer.new()
		var num := _label("%d." % (i + 1), 24)
		row.add_child(num)
		var lab := LineEdit.new()
		lab.placeholder_text = "Choice text"
		lab.text = str(c["label"])
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.text_changed.connect(func(t: String) -> void:
			c["label"] = t
			_mark())
		row.add_child(lab)
		var tgt := OptionButton.new()
		tgt.custom_minimum_size.x = _s(150)
		tgt.clip_text = true
		_fill_target(tgt, str(c["goto"]), true)
		tgt.item_selected.connect(func(k: int) -> void:
			c["goto"] = str(tgt.get_item_metadata(k))
			_mark())
		row.add_child(tgt)
		var ops := LineEdit.new()
		ops.placeholder_text = "ops (optional)"
		ops.tooltip_text = "Game ops, comma separated, e.g.  set_flag:brave, give_item:worklamp"
		ops.custom_minimum_size.x = _s(120)
		ops.text = ", ".join(PackedStringArray((c["ops"] as Array).map(func(o: Variant) -> String: return str(o))))
		ops.text_changed.connect(func(t: String) -> void:
			var arr: Array = []
			for part in t.split(",", false):
				if part.strip_edges() != "":
					arr.append(part.strip_edges())
			c["ops"] = arr
			_mark())
		row.add_child(ops)
		row.add_child(_button("✕", func() -> void:
			list.remove_at(i)
			_rebuild_choices()
			_update_list_item(cur)
			_mark(), "Remove this choice."))
		choice_box.add_child(row)


func add_choice() -> void:
	var e: Dictionary = _cur_screen().get("end", {})
	if not e.has("choices"):
		return
	(e["choices"] as Array).append({"label": "", "goto": "next", "ops": [], "if": ""})
	_rebuild_choices()
	_mark()


# ---------------------------------------------------------------- sounds

func _rebuild_sfx() -> void:
	for c in sfx_box.get_children():
		c.queue_free()
	var list: Array = _cur_screen().get("sfx", [])
	for i in list.size():
		var e: Dictionary = list[i]
		var row := HBoxContainer.new()
		var clip := OptionButton.new()
		clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clip.custom_minimum_size.x = _s(130)
		clip.clip_text = true
		_fill_files(clip, sound_files, str(e["clip"]), "(pick a sound)")
		clip.item_selected.connect(func(k: int) -> void:
			e["clip"] = str(clip.get_item_metadata(k))
			_mark())
		row.add_child(clip)
		var when := OptionButton.new()
		when.add_item("when line starts")
		when.add_item("after seconds")
		when.select(1 if e.has("at") else 0)
		row.add_child(when)
		var val := _spin(0.0 if e.has("at") else 1.0, 600.0, 0.1 if e.has("at") else 1.0, float(e.get("at", e.get("line", 1))))
		val.suffix = "s" if e.has("at") else ""
		val.prefix = "" if e.has("at") else "line"
		row.add_child(val)
		when.item_selected.connect(func(k: int) -> void:
			if k == 1:
				e.erase("line")
				e["at"] = 1.0
			else:
				e.erase("at")
				e["line"] = 1
			_rebuild_sfx()
			_mark())
		val.value_changed.connect(func(v: float) -> void:
			if e.has("at"):
				e["at"] = snappedf(v, 0.01)
			else:
				e["line"] = maxi(1, int(v))
			_mark())
		row.add_child(_button("✕", func() -> void:
			list.remove_at(i)
			_rebuild_sfx()
			_mark(), "Remove this sound."))
		sfx_box.add_child(row)


func add_sfx() -> void:
	var s := _cur_screen()
	if s.is_empty():
		return
	(s["sfx"] as Array).append({"clip": "res://assets/sounds/UI-4.mp3" if sound_files.has("res://assets/sounds/UI-4.mp3") else "", "line": 1})
	_rebuild_sfx()
	_mark()


# ---------------------------------------------------------------- VO cues

func _cues_text(cues: Array) -> String:
	var lines := PackedStringArray()
	for c: Array in cues:
		lines.append("%.2f - %.2f" % [float(c[0]), float(c[1])])
	return "\n".join(lines)


func _parse_cues(t: String) -> Array:
	var re := RegEx.new()
	re.compile("\\d+(?:\\.\\d+)?")
	var out: Array = []
	for line in t.split("\n", false):
		var ms := re.search_all(line)
		if ms.size() >= 2:
			out.append([snappedf(ms[0].get_string().to_float(), 0.01), snappedf(ms[1].get_string().to_float(), 0.01)])
	return out


func _cues_changed() -> void:
	if _loading:
		return
	_set_vo("cues", _parse_cues(cues_edit.text))
	_update_cue_info()


func _text_lines() -> PackedStringArray:
	var m = Markup.new().parse(str(_cur_screen().get("text", "")))
	return m.plain_lines()


func _clip_length(path: String) -> float:
	if path == "" or not ResourceLoader.exists(path):
		return 0.0
	var st := load(path) as AudioStream
	return st.get_length() if st else 0.0


func _update_cue_info() -> void:
	var s := _cur_screen()
	if s.is_empty():
		return
	var vo: Dictionary = s["vo"]
	var n := _text_lines().size()
	var cues := _parse_cues(cues_edit.text)
	var clip := str(vo["clip"])
	if clip == "":
		cue_info.text = "%d text line%s · no voice (types at the screen speed)" % [n, "" if n == 1 else "s"]
	else:
		cue_info.text = "%d text line%s · %d cue time%s · clip %.1f s%s" % [n, "" if n == 1 else "s", cues.size(),
			"" if cues.size() == 1 else "s", _clip_length(clip),
			"" if not cues.is_empty() else " · no times: types at the screen speed while the voice plays"]


func auto_time_pressed() -> void:
	var s := _cur_screen()
	if s.is_empty():
		return
	var vo: Dictionary = s["vo"]
	var clip := str(vo["clip"])
	if clip == "":
		_status("Pick a voice clip first.", true)
		return
	var lines := _text_lines()
	var n := lines.size()
	var cues := VoTiming.auto_time(clip, n, float(vo["from"]), float(vo["to"]), lines)
	if cues.is_empty():
		_status(VoTiming.last_error + " Try Spread evenly.", true)
		return
	cues_edit.text = _cues_text(cues)
	_cues_changed()
	_status("Auto-timed %d line%s from the pauses in %s. Replay to check; edit any time by hand." % [n, "" if n == 1 else "s", clip.get_file()])


func spread_pressed() -> void:
	var s := _cur_screen()
	if s.is_empty():
		return
	var vo: Dictionary = s["vo"]
	var clip := str(vo["clip"])
	var length := _clip_length(clip)
	if length <= 0.0:
		_status("Pick a voice clip first.", true)
		return
	var to := float(vo["to"]) if float(vo["to"]) > 0.0 else length
	var cues := VoTiming.spread(_text_lines(), float(vo["from"]), to)
	cues_edit.text = _cues_text(cues)
	_cues_changed()
	_status("Spread %d lines evenly over %.1f s. Adjust the times by hand if needed." % [cues.size(), to - float(vo["from"])])


# ======================================================== SAVE / BUILD / PLAY

func save_pressed() -> void:
	save_scene()


func save_scene() -> bool:
	_commit_screen_id()
	var d := SceneData.normalize(data)
	if str(d["id"]) == "":
		_status("Give the scene an id first (it becomes the file name).", true)
		return false
	var path := SceneData.json_path(str(d["id"]))
	if path != loaded_path and FileAccess.file_exists(path) and not _overwrite_ok:
		_confirm_action = func() -> void:
			_overwrite_ok = true
			save_scene()
			_overwrite_ok = false
		confirm.dialog_text = "%s already exists.\nReplace it with this scene?" % path
		confirm.popup_centered()
		return false
	if SceneData.save_file(d, path) != OK:
		_status(SceneData.last_error, true)
		return false
	loaded_path = path
	dirty = false
	_scan()
	_refresh_scene_pick()
	_status("Saved %s" % path)
	return true


var _overwrite_ok := false


func build_pressed() -> void:
	build_scene()


## Save JSON + write the .tscn. Returns the built .tscn path or "".
func build_scene() -> String:
	_commit_screen_id()
	var path := SceneData.json_path(str(SceneData.normalize(data)["id"]))
	if path != loaded_path and FileAccess.file_exists(path) and not _overwrite_ok:
		_confirm_action = func() -> void:
			_overwrite_ok = true
			build_scene()
			_overwrite_ok = false
		confirm.dialog_text = "%s already exists.\nReplace it with this scene?" % path
		confirm.popup_centered()
		return ""
	var res := Builder.build(data)
	_show_checks(res["problems"])
	if not bool(res["ok"]):
		_status(str(res["message"]), true)
		return ""
	loaded_path = str(res["json"])
	dirty = false
	_scan()
	_refresh_scene_pick()
	_status("Built %s  (data: %s)" % [res["tscn"], res["json"]])
	return str(res["tscn"])


func play_pressed() -> void:
	var tscn := build_scene()
	if tscn == "":
		return
	var ei = _ei()
	if ei:
		ei.play_custom_scene(tscn)
		_status("Playing %s" % tscn)


func _scan() -> void:
	var ei = _ei()
	if ei:
		ei.get_resource_filesystem().scan()


func _status(msg: String, bad := false) -> void:
	if status_label == null:
		return
	status_label.text = msg
	status_label.add_theme_color_override("font_color", ERR if bad else ACCENT)
	if bad:
		push_warning("Scene Writer: " + msg)


# ======================================================== CHECKS

func _schedule_checks() -> void:
	_check_t = 0.3


func _run_checks() -> void:
	_show_checks(SceneData.validate(data))


func _show_checks(problems: Array) -> void:
	if checks == null:
		return
	if problems.is_empty():
		checks.text = "[color=#%s]No problems. Ready to build.[/color]" % ACCENT.to_html(false)
		return
	var lines := PackedStringArray()
	var ne := 0
	for p: Dictionary in problems:
		var err := str(p["level"]) == "error"
		if err:
			ne += 1
		var col := ERR if err else WARN
		var txt := Markup.esc(str(p["msg"]))
		if int(p["screen"]) >= 0:
			txt = "[url=screen:%d]%s[/url]" % [int(p["screen"]), txt]
		lines.append("[color=#%s]%s[/color] %s" % [col.to_html(false), "ERROR" if err else "note", txt])
	var head := "[color=#%s]%d problem%s must be fixed before Build.[/color]\n" % [ERR.to_html(false), ne, "" if ne == 1 else "s"] if ne > 0 \
		else "[color=#%s]Can build (notes only).[/color]\n" % ACCENT.to_html(false)
	checks.text = head + "\n".join(lines)


# ======================================================== PREVIEW

func _schedule_preview() -> void:
	_preview_t = 0.35


func _process(delta: float) -> void:
	# Editor hot-reload keeps the old dock and nulls the new dropdowns. Rebuild once.
	if not _ui_current():
		_ensure_ui()
	if _check_t >= 0.0:
		_check_t -= delta
		if _check_t < 0.0:
			_run_checks()
	if _preview_t >= 0.0:
		_preview_t -= delta
		if _preview_t < 0.0:
			_preview_play(true)
	if _death_t >= 0.0:
		_death_t -= delta
		if _death_t < 0.0:
			var end: Dictionary = _cur_screen().get("end", {})
			_pv_show_death(str(end.get("heading", "")), str(end.get("message", "")), str(end.get("retry", "")),
				_prev_screen if _prev_screen >= 0 else cur)


func _update_preview_bg() -> void:
	if preview_bg == null:
		return
	var bg := str(data.get("background", ""))
	preview_bg.texture = load(bg) as Texture2D if bg != "" and ResourceLoader.exists(bg) else null
	preview_bg.modulate.a = float(data.get("background_alpha", 0.12))


## complete = show the finished screen (live while typing in the editor); else animate with sound.
func _preview_play(complete: bool, pin_q := "", pin_r := "") -> void:
	var s := _cur_screen()
	if stage == null or s.is_empty():
		return
	_death_t = -1.0
	_animated = not complete
	preview_death.hide()
	preview_note.text = ""
	_update_preview_bg()
	stage.audio_enabled = sound_check.button_pressed and not complete
	stage.text_filter = _preview_filter
	stage.play(SceneData.normalize_screen(s), {"speed": data.get("speed", 40), "title": data.get("title", ""),
		"pin_q": pin_q, "pin_r": pin_r, "complete": complete})
	if complete:
		preview_note.text = "Finished screen shown. Replay to watch it type."


func _preview_filter(t: String) -> String:
	# {v:callsign} etc. show as the default values used by the game
	return t.replace("{v:callsign}", "OPERATOR").replace("{v:o2}", "100")


func replay_preview() -> void:
	_preview_t = -1.0
	_prev_screen = -1
	_preview_play(false)


## Rendered preview frame (for screenshots).
func preview_image() -> Image:
	return preview_vp.get_texture().get_image() if preview_vp else null


func _preview_input(event: InputEvent) -> void:
	if not (event is InputEventMouse):
		return
	var sz := preview_rect.size
	var k := minf(sz.x / 960.0, sz.y / 540.0)
	if k <= 0.0:
		return
	var off := (sz - Vector2(960, 540) * k) * 0.5
	var ev := event.duplicate() as InputEventMouse
	ev.position = ((event as InputEventMouse).position - off) / k
	ev.global_position = ev.position
	preview_vp.push_input(ev, true)
	preview_rect.accept_event()


func _refresh_outline_ui() -> void:
	if chapter_pick == null:
		return
	var file_id := str(data.get("id", ""))
	var scr := ""
	if cur >= 0 and cur < (data.get("screens", []) as Array).size():
		scr = str(data["screens"][cur]["id"])
	var loc: Dictionary = SceneOrder.locate(file_id, scr) if scr != "" else {}
	var chs: Array = SceneOrder.chapters()
	_outline_fill = true
	chapter_pick.clear()
	var chapter_sel := 0
	for i in chs.size():
		chapter_pick.add_item(str(chs[i]["title"]))
		if not loc.is_empty() and str(chs[i]["title"]) == str(loc.get("chapter", "")):
			chapter_sel = i
		elif loc.is_empty() and str(chs[i]["title"]) == "PROLOGUE":
			chapter_sel = i
	chapter_pick.add_item(NEW_CHAPTER)
	if loc.is_empty() and chapter_pick.item_count > 1:
		pass
	if loc.is_empty():
		chapter_sel = 0 if chapter_pick.item_count > 1 else 0
		for i in chapter_pick.item_count:
			if chapter_pick.get_item_text(i) == "PROLOGUE":
				chapter_sel = i
	chapter_pick.select(mini(chapter_sel, chapter_pick.item_count - 1))
	_fill_scene_items(loc)
	on_list.set_pressed_no_signal(not loc.is_empty())
	outline_earlier.disabled = false
	outline_later.disabled = false
	_outline_fill = false
	_rebuild_screen_list()


func _fill_scene_items(loc: Dictionary) -> void:
	scene_outline_pick.clear()
	var making_chapter := chapter_pick.get_item_text(chapter_pick.selected) == NEW_CHAPTER
	chapter_name.get_parent().visible = making_chapter
	var scene_sel := 0
	if not making_chapter:
		var title := chapter_pick.get_item_text(chapter_pick.selected)
		for ch in SceneOrder.chapters():
			if str(ch.get("title", "")) != title:
				continue
			for sc in ch.get("scenes", []):
				scene_outline_pick.add_item(str(sc.get("title", "")))
				if str(sc.get("title", "")) == str(loc.get("scene", "")):
					scene_sel = scene_outline_pick.item_count - 1
	scene_outline_pick.add_item(NEW_SCENE)
	if making_chapter:
		scene_sel = scene_outline_pick.item_count - 1
	scene_outline_pick.select(mini(scene_sel, scene_outline_pick.item_count - 1))
	var making_scene := scene_outline_pick.get_item_text(scene_outline_pick.selected) == NEW_SCENE
	scene_name.get_parent().visible = making_scene
	if not making_chapter:
		chapter_name.text = ""
	if not making_scene:
		scene_name.text = ""


func _on_chapter_picked(_i: int) -> void:
	if _loading or _outline_fill:
		return
	_outline_fill = true
	_fill_scene_items({})
	_outline_fill = false
	_unfold_chosen()
	_rebuild_screen_list()
	_sync_on_list_checkbox()


func _on_scene_picked(_i: int) -> void:
	if _loading or _outline_fill:
		return
	_outline_fill = true
	var making_scene := scene_outline_pick.get_item_text(scene_outline_pick.selected) == NEW_SCENE
	scene_name.get_parent().visible = making_scene
	if not making_scene:
		scene_name.text = ""
	_outline_fill = false
	_unfold_chosen()
	_rebuild_screen_list()
	_sync_on_list_checkbox()


func _unfold_chosen() -> void:
	var ch := _chosen_chapter()
	var sc := _chosen_scene()
	if ch != "":
		_folded[_fold_key_chapter(ch)] = false
	if ch != "" and sc != "":
		_folded[_fold_key_scene(ch, sc)] = false


func _sync_on_list_checkbox() -> void:
	if on_list == null:
		return
	var scr := _cur_screen()
	var loc: Dictionary = {}
	if not scr.is_empty():
		loc = SceneOrder.locate(str(data.get("id", "")), str(scr.get("id", "")))
	var here := not loc.is_empty() and str(loc.get("chapter", "")) == _chosen_chapter() and str(loc.get("scene", "")) == _chosen_scene()
	on_list.set_pressed_no_signal(here)
	outline_earlier.disabled = false
	outline_later.disabled = false


func _on_list_toggled(on: bool) -> void:
	if _loading or _outline_fill:
		return
	var scr := _cur_screen()
	if scr.is_empty():
		return
	var file_id := str(data.get("id", ""))
	var screen_id := str(scr.get("id", ""))
	if not on:
		_snapshot_list(false)
		SceneOrder.remove_screen(file_id, screen_id)
		outline_earlier.disabled = true
		outline_later.disabled = true
		_rebuild_screen_list()
		_status("Removed %s from the list." % screen_id)
		return
	if not _apply_outline():
		on_list.set_pressed_no_signal(false)
	else:
		_rebuild_screen_list()


func _outline_nudge(dir: int) -> void:
	if _loading:
		return
	var target := ""
	var picked := screen_list.get_selected_items()
	if not picked.is_empty():
		var meta = screen_list.get_item_metadata(picked[0])
		if meta is Dictionary:
			target = str(meta.get("target", ""))
		else:
			target = str(meta)
	if target == "":
		var scr := _cur_screen()
		if scr.is_empty():
			return
		target = "scene:%s/%s" % [str(data.get("id", "")), str(scr.get("id", ""))]
	_snapshot_list(false)
	SceneOrder.move_target(target, dir)
	_rebuild_screen_list()
	_status("Moved on the list.")


func _outline_label() -> String:
	var scr := _cur_screen()
	var heading := str(scr.get("heading", "")).strip_edges()
	return heading if heading != "" else str(scr.get("id", ""))


func _chosen_chapter() -> String:
	if chapter_pick == null or not is_instance_valid(chapter_pick) or chapter_pick.selected < 0:
		return ""
	if chapter_pick.get_item_text(chapter_pick.selected) == NEW_CHAPTER:
		return chapter_name.text.strip_edges() if chapter_name != null and is_instance_valid(chapter_name) else ""
	return chapter_pick.get_item_text(chapter_pick.selected)


func _chosen_scene() -> String:
	if scene_outline_pick == null or not is_instance_valid(scene_outline_pick) or scene_outline_pick.selected < 0:
		return ""
	if scene_outline_pick.get_item_text(scene_outline_pick.selected) == NEW_SCENE:
		return scene_name.text.strip_edges() if scene_name != null and is_instance_valid(scene_name) else ""
	return scene_outline_pick.get_item_text(scene_outline_pick.selected)


func _apply_outline() -> bool:
	if _loading or _outline_fill or on_list == null or not on_list.button_pressed:
		return false
	var scr := _cur_screen()
	if scr.is_empty():
		return false
	var chapter := _chosen_chapter()
	var scene_title := _chosen_scene()
	if chapter == "" or scene_title == "":
		_status("Type a chapter and a scene, then check On the list.", true)
		return false
	_snapshot_list(false)
	SceneOrder.place(chapter, scene_title, str(data.get("id", "")), str(scr.get("id", "")), _outline_label())
	outline_earlier.disabled = false
	outline_later.disabled = false
	_status("On the list: %s / %s." % [chapter, scene_title])
	return true


func _outline_auto_insert(prev_id: String, new_id: String) -> void:
	var file_id := str(data.get("id", ""))
	var ch := _chosen_chapter()
	var sc_title := _chosen_scene()
	var loc: Dictionary = SceneOrder.locate(file_id, prev_id) if prev_id != "" else {}
	if loc.is_empty():
		loc = SceneOrder.locate_file(file_id)
	if ch != "" and sc_title != "":
		var prev_loc: Dictionary = SceneOrder.locate(file_id, prev_id) if prev_id != "" else {}
		if not prev_loc.is_empty() and str(prev_loc.get("chapter", "")) == ch and str(prev_loc.get("scene", "")) == sc_title:
			SceneOrder.insert_after(ch, sc_title, file_id, new_id, new_id, prev_id)
		else:
			SceneOrder.place(ch, sc_title, file_id, new_id, new_id)
		return
	if loc.is_empty():
		return
	if prev_id != "" and str(loc.get("target", "")).ends_with("/" + prev_id):
		SceneOrder.insert_after(str(loc["chapter"]), str(loc["scene"]), file_id, new_id, new_id, prev_id)
	else:
		SceneOrder.place(str(loc["chapter"]), str(loc["scene"]), file_id, new_id, new_id)


func _pv_go(target: String, pin_q := "", pin_r := "") -> void:
	var t := target.strip_edges()
	var screens: Array = data["screens"]
	var idx := -1
	if t == "" or t == "next":
		idx = cur + 1 if cur + 1 < screens.size() else -1
		if idx < 0:
			t = str(data.get("after", ""))
			if t == "":
				preview_note.text = "End of the scene (no \"When it ends\" target)."
				return
	if t == "order:next":
		var here := ""
		if cur >= 0 and cur < screens.size():
			here = "scene:%s/%s" % [str(data.get("id", "")), str(screens[cur]["id"])]
		t = SceneOrder.next_after(here)
		if t == "":
			preview_note.text = "The next scene isn't written."
			return
		if t.begins_with("scene:"):
			var rest := t.substr(6)
			if rest.get_slice("/", 0) == str(data.get("id", "")) and rest.contains("/"):
				t = rest.get_slice("/", 1)
	if not t.begins_with("scene:") and not t.begins_with("intro:") and not t.begins_with("tscn:"):
		for i in screens.size():
			if str(screens[i]["id"]) == t:
				idx = i
	if idx < 0:
		stage.stop()
		preview_note.text = "In the game this leaves the scene → %s" % SceneData.target_label(t)
		return
	_prev_screen = cur
	var keep := _prev_screen
	select_screen(idx)
	_preview_t = -1.0
	_prev_screen = keep
	_preview_play(false, pin_q, pin_r)


func _pv_continue() -> void:
	_pv_go(str(_cur_screen()["end"].get("goto", "next")))


func _pv_choice(i: int) -> void:
	var list: Array = _cur_screen()["end"].get("choices", [])
	if i < 0 or i >= list.size():
		return
	_pv_go(str(list[i]["goto"]), stage.question_text(), "> " + _preview_filter(str(list[i]["label"])))


func _pv_qte() -> void:
	var end: Dictionary = _cur_screen()["end"]
	_pv_go(str(end.get("goto", "next")), stage.question_text(), "> " + str(end.get("label", "")))


func _pv_qte_expired() -> void:
	var end: Dictionary = _cur_screen()["end"]
	_pv_show_death("", str(end.get("fail_message", "")), str(end.get("retry", "")), cur)


func _pv_typing_done() -> void:
	if stage.end_type() == "death" and _animated:
		_death_t = 1.2
	elif stage.end_type() == "map_tour":
		var n := ((_cur_screen()["end"] as Dictionary).get("tips", []) as Array).size()
		preview_note.text = "Map walkthrough: %d tip%s over the full map (plays in the game; Play Scene to try it)." % [n, "" if n == 1 else "s"]
	elif stage.end_type() == "hold":
		preview_note.text = "The scene holds on this screen."


func _pv_show_death(heading: String, message: String, retry: String, fallback: int) -> void:
	stage.stop()
	preview_death_heading.text = heading.to_upper() if heading != "" else "SIGNAL LOST"
	preview_death_msg.text = message.to_upper() if message != "" else "OPERATOR DECEASED"
	_death_retry = retry
	_death_fallback = fallback
	preview_death.show()


func _pv_retry() -> void:
	preview_death.hide()
	stage.reset_fx()
	if _death_retry == "":

		select_screen(clampi(_death_fallback, 0, (data["screens"] as Array).size() - 1))
		_preview_t = -1.0
		_prev_screen = -1
		_preview_play(false)
	else:
		_pv_go(_death_retry)
