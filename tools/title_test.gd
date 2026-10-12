extends SceneTree
# Title screen test (headless):
#   godot --headless --audio-driver Dummy --path <project> --script res://tools/title_test.gd
# Boot scene = title; REC-7 logo; PLAY / QUIT in the standard button style inside 960x540;
# CRT screen shader; tap sound; no key hints; debug args skip to the intro;
# PLAY (debug build) opens the mission select; with dev_menu forced off, PLAY opens the intro at the thaw.

const TITLE := "res://scenes/title.tscn"
const INTRO := "res://scenes/intro.tscn"
const MISSION := "res://scenes/mission_select.tscn"

var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func wait_s(sec: float) -> void:
	await create_timer(sec).timeout


func _init() -> void:
	_run.call_deferred()


func _spawn() -> Control:
	var t: Control = (load(TITLE) as PackedScene).instantiate()
	root.add_child(t)
	current_scene = t
	await process_frame
	await process_frame
	return t


func _texts(n: Node, out: Array) -> void:
	if n is Label or n is Button or n is RichTextLabel:
		out.append(str(n.get("text")))
	for c in n.get_children():
		_texts(c, out)


func _run() -> void:
	check("boot scene is the title", str(ProjectSettings.get_setting("application/run/main_scene")) == TITLE)
	check("viewport 960x540", int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 960
		and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 540)

	var t := await _spawn()
	check("not skipped without debug args", not t.skipped_to_game and current_scene == t)
	var logo: TextureRect = t.get_node("%Logo")
	check("logo texture = rec7_logo.png", logo.texture != null and logo.texture.resource_path == "res://assets/rec7_logo.png")
	check("logo visible, native size 237x189", logo.is_visible_in_tree() and logo.size == Vector2(237, 189))
	var lr := logo.get_global_rect()
	check("logo centred horizontally", absf(lr.get_center().x - 480.0) <= 1.0)
	var screen: ColorRect = t.get_node("Screen")
	var mat := screen.material as ShaderMaterial
	check("CRT screen_refresh shader on the screen", mat != null and mat.shader.resource_path == "res://shaders/screen_refresh.gdshader")
	check("title uses pda_theme", t.theme != null and t.theme.resource_path == "res://templates/pda_theme.tres")

	var play: Button = t.get_node("%PlayButton")
	var quit_b: Button = t.get_node("%QuitButton")
	check("button labels PLAY / QUIT", play.text == "PLAY" and quit_b.text == "QUIT")
	var screen_rect := Rect2(0, 0, 960, 540)
	for b: Button in [play, quit_b]:
		check("%s is 220x38" % b.text, b.size == Vector2(220, 38))
		check("%s inside 960x540" % b.text, screen_rect.encloses(b.get_global_rect()))
		check("%s standard style (no overrides)" % b.text, not b.has_theme_stylebox_override("normal")
			and b.get_theme_stylebox("normal") == t.theme.get_stylebox("normal", "Button"))
		check("%s pointing-hand cursor" % b.text, b.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
		check("%s enabled" % b.text, not b.disabled and b.is_visible_in_tree())
	check("PLAY above QUIT, same column", play.global_position.y < quit_b.global_position.y
		and play.global_position.x == quit_b.global_position.x)
	check("buttons below the logo", play.global_position.y > lr.end.y)
	var sfx: AudioStreamPlayer = t.get_node("%SfxTap")
	check("tap sound = UI-1 on Sfx bus (same as the PDA)", sfx.stream != null
		and sfx.stream.resource_path == "res://assets/sounds/UI-1.mp3" and sfx.bus == &"Sfx")

	var texts := []
	_texts(t, texts)
	var hint := false
	for s: String in texts:
		var u := s.to_upper()
		for w in ["PRESS", "ENTER", "ESC", "SPACE", "CLICK", "KEY", "[", "WHEEL"]:
			if u.contains(w):
				hint = true
	check("no key hints on screen (%s)" % ", ".join(texts), not hint)

	await wait_s(0.8)
	check("content faded in", is_equal_approx(t.get_node("%Content").modulate.a, 1.0))

	# debug-arg passthrough (debug builds): intro args skip the title; title-only args do not
	check("no args -> stay", not t._wants_game({}))
	check("--shot/--shot_delay -> stay", not t._wants_game({"shot": "x.png", "shot_delay": "1"}))
	check("--title_hover/--nodev -> stay", not t._wants_game({"title_hover": "play", "nodev": "1"}))
	check("--jump=exam -> intro", t._wants_game({"jump": "exam"}))
	check("--thaw_at -> intro", t._wants_game({"thaw_at": "20", "shot": "x.png"}))
	check("--skip_title -> intro", t._wants_game({"skip_title": "1"}))
	check("release build reads no args", OS.is_debug_build() or t._read_debug_args().is_empty())

	# QUIT (stubbed so the test keeps running)
	t.allow_quit = false
	quit_b.emit_signal("pressed")
	await process_frame
	check("QUIT requests quit", t.quit_requested and t.leaving)
	play.emit_signal("pressed")
	await wait_s(0.5)
	check("QUIT then ignores PLAY", current_scene == t and not play.disabled)
	t.queue_free()
	await process_frame

	# PLAY in a debug build opens the mission select, not the intro
	t = await _spawn()
	check("debug build offers the mission select", t.dev_menu)
	play = t.get_node("%PlayButton")
	play.emit_signal("pressed")
	await process_frame
	check("PLAY disables both buttons while leaving", play.disabled and t.get_node("%QuitButton").disabled)
	check("PLAY does not quit", not t.quit_requested)
	await wait_s(0.7)
	var menu = current_scene
	check("PLAY opened the mission select", menu != null and menu.scene_file_path == MISSION)
	check("title is gone", not is_instance_valid(t) or not t.is_inside_tree())
	if menu != null and menu.scene_file_path == MISSION:
		menu.queue_free()
		await process_frame

	# release path: dev_menu forced off, PLAY still opens the thaw
	t = await _spawn()
	t.dev_menu = false
	t.get_node("%PlayButton").emit_signal("pressed")
	await wait_s(0.7)
	var intro = current_scene
	check("release PLAY opened scenes/intro.tscn", intro != null and intro.scene_file_path == INTRO)
	if intro != null and intro.scene_file_path == INTRO:
		await wait_s(0.8)
		check("release PLAY starts at the thaw", intro.current_id == &"thaw")
		check("thaw overlay open", intro.get_node("%Thaw").visible)
		intro.queue_free()
		await process_frame

	print("TITLE TEST DONE: %d fails" % fails)
	quit(fails)
