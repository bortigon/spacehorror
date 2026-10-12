extends Control
## MISSION SELECT (debug builds only). Title PLAY opens this; a release build never does.
## One button per scene in story/SCENE_ORDER.md (opens that scene's first subscene), then BACK.
## Debug args (this scene only): --go=LABEL jumps straight to that button,
## --shot=PATH [--shot_delay=1.2] saves this screen (ignored when --go is set).

const INTRO_SCENE := "res://scenes/intro.tscn"
const Pda := preload("res://templates/pda_screen.gd")
const SceneOrder := preload("res://ui/scene_order.gd")

const BACK_LABEL := "BACK"
const BUTTON_SIZE := Vector2(220, 38)

@onready var rows_box: VBoxContainer = %Rows
@onready var sfx_tap: AudioStreamPlayer = %SfxTap

## Tests set this before the node enters the tree: behave like a release build.
var treat_as_release := false
var leaving := false


func _ready() -> void:
	if treat_as_release or not OS.is_debug_build():
		get_tree().change_scene_to_file.call_deferred(INTRO_SCENE)
		return
	_build_buttons()
	var d := _read_debug_args()
	if d.has("go"):
		_activate(_find_row(str(d["go"])))
		return
	if d.has("shot"):
		_shot(str(d["shot"]), float(str(d.get("shot_delay", "1.2"))))


func labels() -> PackedStringArray:
	var out := PackedStringArray()
	for r in _rows():
		out.append(str(r["label"]))
	out.append(BACK_LABEL)
	return out


func _build_buttons() -> void:
	for r in _rows():
		var b := _make_button(str(r["label"]))
		b.pressed.connect(_activate.bind(r))
		rows_box.add_child(b)
	var back := _make_button(BACK_LABEL)
	back.pressed.connect(_on_back)
	rows_box.add_child(back)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.custom_minimum_size = BUTTON_SIZE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _rows() -> Array:
	return SceneOrder.menu_rows()


func _find_row(want: String) -> Dictionary:
	var w := want.strip_edges().to_upper()
	for r in _rows():
		if str(r["label"]).to_upper() == w:
			return r
	return {}


func _activate(row: Dictionary) -> void:
	if leaving or row.is_empty():
		return
	leaving = true
	_play_tap()
	for c in rows_box.get_children():
		if c is Button:
			(c as Button).disabled = true
	if str(row.get("kind", "")) == "intro":
		Pda.next_passage = str(row.get("id", ""))
		Pda.next_authored = ""
		Pda.next_screen = ""
		Pda.carry = {}
		get_tree().change_scene_to_file.call_deferred(INTRO_SCENE)
		return
	Pda.next_passage = ""
	Pda.next_authored = "res://story/scenes/%s.json" % str(row.get("id", ""))
	Pda.next_screen = str(row.get("screen", ""))
	Pda.carry = {"flags": {"exam_done": true}, "vars": {"callsign": "OPERATOR"}, "o2": 100.0}
	var built := "res://scenes/authored/%s.tscn" % str(row.get("id", ""))
	var path := built if ResourceLoader.exists(built) else "res://templates/authored_scene.tscn"
	get_tree().change_scene_to_file.call_deferred(path)


func _on_back() -> void:
	if leaving:
		return
	leaving = true
	_play_tap()
	get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")


func _play_tap() -> void:
	if sfx_tap.stream != null and sfx_tap.is_inside_tree():
		sfx_tap.play()


func _exit_tree() -> void:
	sfx_tap.stop()


func _read_debug_args() -> Dictionary:
	var d := {}
	if not OS.is_debug_build():
		return d
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.trim_prefix("--").split("=", true, 1)
		d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return d


func _shot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		var err := img.save_png(path)
		print("SHOT %s -> %s (%dx%d)" % [error_string(err), path, img.get_width(), img.get_height()])
	get_tree().quit()
