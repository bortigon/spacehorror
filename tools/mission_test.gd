extends SceneTree
# Mission select test (headless):
#   godot --headless --audio-driver Dummy --path <project> --script res://tools/mission_test.gd
# Buttons are the scenes in story/SCENE_ORDER.md (INTRO, READY ROOM) plus BACK.
# INTRO opens the intro at thaw. READY ROOM opens excursion1_prep on ready_room.
# BACK returns to the title. A forced release build leaves the menu for the thaw.

const MENU := "res://scenes/mission_select.tscn"
const Order := preload("res://ui/scene_order.gd")
const TITLE := "res://scenes/title.tscn"
const INTRO := "res://scenes/intro.tscn"
const HINTS := ["PRESS", "ENTER", "ESC", "SPACE", "CLICK", "KEY", "[", "WHEEL"]

var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func wait_s(sec: float) -> void:
	await create_timer(sec).timeout


func _init() -> void:
	_run.call_deferred()


func _texts(n: Node, out: Array) -> void:
	if n is Label or n is Button or n is RichTextLabel:
		out.append(str(n.get("text")))
	for c in n.get_children():
		_texts(c, out)


func _spawn(release := false) -> Control:
	var m: Control = (load(MENU) as PackedScene).instantiate()
	m.treat_as_release = release
	root.add_child(m)
	current_scene = m
	await process_frame
	await process_frame
	return m


func _run() -> void:
	var want := PackedStringArray()
	for r in Order.menu_rows():
		want.append(str(r["label"]))
	want.append("BACK")
	var m := await _spawn()
	check("labels are the outline screens then BACK", m.labels() == want and want.size() >= 3)
	var joined := ", ".join(m.labels())
	check("sample_scene is not listed", not joined.contains("SAMPLE") and not joined.contains("sample"))
	check("menu is INTRO and READY ROOM only", want == PackedStringArray(["INTRO", "READY ROOM", "BACK"]))
	check("no per-subscene buttons", not joined.contains("THAW") and not joined.contains("BRIEF") and not joined.contains("MAP"))

	var screen: ColorRect = m.get_node("Screen")
	var mat := screen.material as ShaderMaterial
	check("CRT screen_refresh shader", mat != null and mat.shader.resource_path == "res://shaders/screen_refresh.gdshader")
	check("uses pda_theme", m.theme != null and m.theme.resource_path == "res://templates/pda_theme.tres")
	var sfx: AudioStreamPlayer = m.get_node("%SfxTap")
	check("tap sound = UI-1 on Sfx", sfx.stream != null and sfx.stream.resource_path == "res://assets/sounds/UI-1.mp3" and sfx.bus == &"Sfx")
	var rect := Rect2(0, 0, 960, 540)
	var buttons := m.get_node("%Rows").get_children()
	check("one button per outline row plus BACK", buttons.size() == want.size())
	for b in buttons:
		check("%s is 220x38" % b.text, b.size == Vector2(220, 38))
		check("%s inside 960x540" % b.text, rect.encloses(b.get_global_rect()))
		check("%s standard style" % b.text, not b.has_theme_stylebox_override("normal")
			and b.get_theme_stylebox("normal") == m.theme.get_stylebox("normal", "Button"))
	var texts := []
	_texts(m, texts)
	var hint := false
	for t in texts:
		var u := str(t).to_upper()
		for w in HINTS:
			if u.contains(w):
				hint = true
	check("no key hints (%s)" % ", ".join(texts), not hint)

	# BACK -> title
	_press(m, "BACK")
	await process_frame
	await process_frame
	check("BACK opened the title", current_scene != null and current_scene.scene_file_path == TITLE)
	if current_scene and current_scene.scene_file_path == TITLE:
		current_scene.queue_free()
		await process_frame

	# INTRO -> first subscene, thaw
	m = await _spawn()
	_press(m, "INTRO")
	await process_frame
	await wait_s(0.5)
	check("INTRO opened the intro", current_scene != null and current_scene.scene_file_path == INTRO)
	if current_scene and current_scene.scene_file_path == INTRO:
		check("INTRO starts at thaw", current_scene.current_id == &"thaw")
		current_scene.queue_free()
		await process_frame

	# READY ROOM -> ready_room subscene
	m = await _spawn()
	_press(m, "READY ROOM")
	await process_frame
	await wait_s(0.5)
	var pda = current_scene
	check("READY ROOM opened excursion1_prep", pda != null and str(pda.scene_file_path).ends_with("excursion1_prep.tscn"))
	if pda != null and pda.has_method("current_screen"):
		check("READY ROOM landed on the ready_room subscene", str(pda.current_screen().get("id", "")) == "ready_room")
		check("carry: callsign OPERATOR, exam done, O2 full", str(pda.vars.get("callsign", "")) == "OPERATOR"
			and pda.has_flag("exam_done") and is_equal_approx(float(pda.o2_level), 100.0))
		pda.queue_free()
		await process_frame

	# release guard
	m = await _spawn(true)
	await process_frame
	await wait_s(0.4)
	check("release guard left the menu", current_scene != null and current_scene.scene_file_path == INTRO)
	if current_scene and current_scene.scene_file_path == INTRO:
		await wait_s(0.5)
		check("release guard opens the thaw", current_scene.current_id == &"thaw")
		current_scene.queue_free()

	print("MISSION TEST DONE: %d fails" % fails)
	quit(fails)


func _press(m: Node, label: String) -> void:
	for b in m.get_node("%Rows").get_children():
		if str(b.text) == label:
			b.emit_signal("pressed")
			return
	check("button %s exists" % label, false)
