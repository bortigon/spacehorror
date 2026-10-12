extends SceneTree
# Headless keyboard smoke test: godot --headless -s res://tools/key_test.gd

var pda
var fails := 0

func key(kc: Key, shift := false, alt := false, uni := 0) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = kc
		e.keycode = kc
		e.unicode = uni
		e.shift_pressed = shift
		e.alt_pressed = alt
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await process_frame

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1

func skip_vo_section() -> void:
	# Space until the section is over (finish line, then skip).
	for _i in 4:
		if pda._thaw_phase != pda.ThawPhase.MAIN and pda._thaw_phase != pda.ThawPhase.REPLY:
			break
		await key(KEY_SPACE)

func wait_s(sec: float) -> void:
	await create_timer(sec).timeout

func exam_skip() -> void:
	# Space until the exam VO section is over (finish line, then skip).
	for _i in 4:
		if pda._thaw_phase != pda.ThawPhase.EXAM_VO:
			break
		await key(KEY_SPACE)

func type_text(t: String) -> void:
	for ch in t:
		var kc: Key = KEY_SPACE if ch == " " else OS.find_keycode_from_string(ch)
		await key(kc, false, false, ch.unicode_at(0))

func wait_text(t: String, sec: float) -> bool:
	for _w in int(sec * 10.0):
		if pda.thaw_text.text.contains(t):
			return true
		await wait_s(0.1)
	return pda.thaw_text.text.contains(t)

func wait_pin(t: String, sec: float) -> bool:
	for _w in int(sec * 10.0):
		if pda.thaw_pin.visible and pda.thaw_pin.text.contains(t):
			return true
		await wait_s(0.1)
	return pda.thaw_pin.visible and pda.thaw_pin.text.contains(t)

func pinned(q: String, r: String) -> bool:
	return pda.thaw_pin.visible and pda.thaw_pin.text.contains(q) and pda.thaw_pin.text.contains(r)

func rect_eq(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) < 0.6 and a.size.distance_to(b.size) < 0.6

func no_until_death() -> void:
	# From the exam YES/NO: NO x4 (NO1-NO3 bring the choices back), skipping each reply.
	for k in 4:
		await key(KEY_2)
		await exam_skip()

var _hint_re := RegEx.create_from_string("\\[|\\bSPACE\\b|\\bESC\\b|\\bENTER\\b|\\bCLICK|\\bHOVER|\\bTABS\\b|\\bPRESS\\b|MAX \\d+ CHAR")

## Visible labels / buttons / rich text / tooltips that still read like a tutorial or key hint.
func hint_offenders() -> Array:
	var out: Array = []
	_scan_hints(pda, out)
	return out

func _scan_hints(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	var t := ""
	if n is Label:
		t = (n as Label).text
		if (n as Label).theme_type_variation == &"KeyHint":
			out.append("%s: KeyHint label '%s'" % [n.name, t])
	elif n is Button:
		t = (n as Button).text
	elif n is RichTextLabel:
		t = (n as RichTextLabel).get_parsed_text()
	elif n is LineEdit:
		t = (n as LineEdit).placeholder_text
	if n is Control and (n as Control).tooltip_text != "":
		t += " " + (n as Control).tooltip_text
	if t != "" and _hint_re.search(t) != null:
		out.append("%s: '%s'" % [n.name, t.substr(0, 60)])
	for c in n.get_children():
		_scan_hints(c, out)

func no_hints(where: String) -> void:
	var off := hint_offenders()
	check("no key hints / tutorials: " + where + ("" if off.is_empty() else "  " + str(off)), off.is_empty())

func wheel_up() -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP
		e.pressed = pressed
		e.position = Vector2(480, 20)
		Input.parse_input_event(e)
		await process_frame
	await process_frame

func new_intro(force_choice := "") -> void:
	if pda:
		pda.queue_free()
		await process_frame
	pda = load("res://scenes/intro.tscn").instantiate()
	pda._thaw_force_choice = force_choice
	root.add_child(pda)
	await process_frame
	await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await new_intro()
	check("thaw visible", pda.thaw.visible)
	check("pda chrome hidden", not pda.safe_area.visible)
	check("phase MAIN", pda._thaw_phase == pda.ThawPhase.MAIN)
	check("voice main playing", pda.voice_main.playing)
	check("voice on Voice bus", pda.voice_main.bus == &"Voice")
	await key(KEY_M)
	check("M ignored during thaw", not pda.map_overlay.visible)
	check("thaw: HUD minimap visible, STASIS-3 current", pda.hud_map.is_visible_in_tree()
		and str(pda.hud_map.map_data.get("current", "")) == "stasis_3")
	check("thaw: HUD O2 100%", is_equal_approx(pda.hud_o2.level, 100.0) and pda.hud_o2.danger == 0.0)
	check("ambience on Music bus", pda.ambience.bus == &"Music")
	no_hints("THAW main")
	check("dev_mode follows OS.is_debug_build()", pda.dev_mode == OS.is_debug_build())
	check("dev back: first screen, nothing to go back to", not pda.dev_back() and pda._thaw_phase == pda.ThawPhase.MAIN)
	# Pause freezes VO + reveal clock.
	await wait_s(0.3)
	await key(KEY_ESCAPE)
	check("pause open", pda.pause_menu.visible)
	check("vo stream_paused", pda.voice_main.stream_paused)
	var t_paused: float = pda._thaw_t
	await wait_s(0.4)
	check("reveal clock frozen while paused", is_equal_approx(t_paused, pda._thaw_t))
	await key(KEY_ESCAPE)
	check("unpause", not pda.pause_menu.visible)
	check("vo resumed", pda.voice_main.playing and not pda.voice_main.stream_paused)
	await wait_s(0.2)
	check("reveal clock moving again", pda._thaw_t > t_paused)
	# First press finishes the line being typed, VO keeps going.
	pda._thaw_t = 1.9  # inside fragment 1 ("The REC-7 corporation...")
	pda.voice_main.seek(1.9)
	await process_frame
	var typing: int = pda._thaw_typing_index()
	check("fragment typing at 1.9s", typing == 1)
	await key(KEY_SPACE)
	check("1st press: line complete", pda._thaw_forced >= 1 and pda._thaw_phase == pda.ThawPhase.MAIN)
	check("1st press: vo still playing", pda.voice_main.playing)
	check("line text shown", pda.thaw_text.text.contains("inform you"))
	await key(KEY_SPACE)
	check("2nd press: choices", pda.thaw_choices.visible and pda._thaw_phase == pda.ThawPhase.CHOICES)
	check("2nd press: main vo stopped", not pda.voice_main.playing)
	check("all main text shown", pda.thaw_text.text.contains("TRM-CUFF now?"))
	check("ERROR glitch settled x3", pda.thaw_text.text.count("ERROR") == 3)
	no_hints("THAW choices")
	check("THAW choices: no number prefix", pda._thaw_choice_btns[0].get_child_count() == 0
		and pda.thaw_choices_header.text == "RESPONSE")
	# Extra Space on the choice screen must not pick anything.
	await key(KEY_SPACE)
	check("space does not pick", pda._thaw_phase == pda.ThawPhase.CHOICES and not pda.has_flag("thaw_said_yes"))
	# 1 and 2 in the same frame: only the first counts.
	for kc in [KEY_1, KEY_2]:
		var e := InputEventKey.new()
		e.physical_keycode = kc
		e.keycode = kc
		e.pressed = true
		Input.parse_input_event(e)
	await process_frame
	await process_frame
	check("flag thaw_said_yes", pda.has_flag("thaw_said_yes"))
	check("no double pick", not pda.has_flag("thaw_said_no"))
	check("phase REPLY", pda._thaw_phase == pda.ThawPhase.REPLY)
	check("voice yes playing", pda.voice_yes.playing)
	check("choice buttons gone", pda._thaw_choice_btns.is_empty())
	# "Good," is cued at 0.69 s of the YES WAV; allow margin for the Dummy audio clock.
	for _w in 30:
		if pda.thaw_text.text.contains("Good,"):
			break
		await wait_s(0.1)
	check("YES text revealing", pda.thaw_text.text.contains("Good,"))
	check("> YES pinned (new screen)", pinned("Are you observing the TRM-CUFF now?", "> YES")
		and not pda.thaw_text.text.contains("Hello, OPERATOR"))
	await skip_vo_section()
	check("yes vo stopped", not pda.voice_yes.playing)
	check("THAW reply ends on CONTINUE", pda._thaw_phase == pda.ThawPhase.EXAM_WAIT and pda.exam_continue.visible)
	await key(KEY_SPACE)
	# --- MEMORY EXAMINATION ---
	var screens_before_name: Array = [pda._exam_screen]
	check("exam: screen 1 after YES", pda._thaw_phase == pda.ThawPhase.EXAM_VO and pda._exam_screen == 1)
	check("exam: header", pda.thaw_status.text == "STASIS THAW // MEMORY EXAMINATION")
	check("exam: voice memorytest1 on Voice bus", pda.voice_exam.playing and pda.voice_exam.bus == &"Voice"
		and pda.voice_exam.stream.resource_path.ends_with("memorytest1.wav"))
	check("exam: chrome hidden, HUD minimap + O2 shown", not pda.safe_area.visible
		and pda.hud_map.is_visible_in_tree() and pda.hud_o2.is_visible_in_tree())
	check("exam: no pin on a fresh (non-response) screen", not pda.thaw_pin.visible)
	await exam_skip()
	check("exam: screen 1 -> CONTINUE", pda._thaw_phase == pda.ThawPhase.EXAM_WAIT and pda.exam_continue.visible)
	check("exam: screen 1 = welcome + assess + warning", pda.thaw_text.text.contains("Welcome to the Memory Examination.")
		and pda.thaw_text.text.contains("will assess") and pda.thaw_text.text.contains("duties as assigned."))
	check("exam: vo stopped at continue", not pda.voice_exam.playing)
	check("exam: CONTINUE label has no key", pda.exam_continue.text == "CONTINUE")
	no_hints("exam screen 1 (CONTINUE, no footer)")
	pda.exam_continue.pressed.emit()
	pda.exam_continue.pressed.emit()   # double click must not skip a screen
	await process_frame
	screens_before_name.append(pda._exam_screen)
	check("exam: click continues once -> screen 2", pda._exam_screen == 2 and pda._thaw_phase == pda.ThawPhase.EXAM_VO)
	await exam_skip()
	check("exam: screen 2 heading + question", pda.thaw_text.text.contains("Memory Examination")
		and pda.thaw_text.text.contains("1) Do you remember your name?"))
	check("exam: name entry shown", pda._thaw_phase == pda.ThawPhase.EXAM_NAME and pda.exam_name_box.visible)
	check("exam: 2 screens before the name box", screens_before_name == [1, 2])
	await process_frame
	check("exam: LineEdit focused", pda.get_viewport().gui_get_focus_owner() == pda.exam_name_edit)
	check("exam: no helper line under the name box", not pda.exam_name_hint.visible and pda.exam_name_confirm.text == "SUBMIT")
	no_hints("name entry")
	await type_text("1M 2")
	check("exam: hotkeys typed, not fired", pda.exam_name_edit.text == "1M 2" and not pda.map_overlay.visible
		and pda._thaw_phase == pda.ThawPhase.EXAM_NAME and pda._thaw_choice_btns.is_empty())
	await key(KEY_ESCAPE)
	check("exam: Esc pauses from the name field", pda.pause_menu.visible)
	await key(KEY_ESCAPE)
	await process_frame
	check("exam: focus back after pause", pda.get_viewport().gui_get_focus_owner() == pda.exam_name_edit)
	pda.exam_name_edit.text = ""
	await type_text("   ")
	await key(KEY_ENTER)
	check("exam: blank name rejected", pda._thaw_phase == pda.ThawPhase.EXAM_NAME and pda.exam_name_box.visible
		and pda.exam_name_hint.visible and pda.exam_name_hint.text.contains("BLANK"))
	pda.exam_name_confirm.pressed.emit()
	check("exam: empty SUBMIT rejected", pda._thaw_phase == pda.ThawPhase.EXAM_NAME)
	await process_frame
	await type_text("ZED")
	await key(KEY_ENTER)
	check("exam: name accepted -> screen 3", pda._exam_screen == 3 and pda._thaw_phase == pda.ThawPhase.EXAM_VO)
	check("exam: typed_name var", str(pda.vars.get("typed_name", "")) == "ZED")
	check("exam: question + typed name pinned", pinned("1) Do you remember your name?", "> ZED"))
	check("exam: pinned name glitches to ERROR", await wait_pin("ERROR", 4.0) and not pda.thaw_pin.text.contains("ZED"))
	check("exam: body 'The name ERROR ... we have on file'", await wait_text("is not the name we have on file.", 5.0))
	await exam_skip()
	check("exam: YES/NO shown", pda._thaw_phase == pda.ThawPhase.EXAM_CHOICES and pda._thaw_choice_btns.size() == 2)
	await process_frame
	no_hints("exam YES/NO")
	var choice_rect: Rect2 = pda._thaw_choice_btns[0].get_global_rect()
	# NO loop: NO1 -> NO2 -> NO3 -> NO4, each on a new pinned screen
	var no_lines := ["not a valid option", "vital to the continuance", "severe brain damage may inhibit", "brain damage from stasis is severe"]
	for k in 4:
		await key(KEY_2)
		var q := "Please indicate that you understand." if k < 3 else "Please indicate in the affirmative if you understand this."
		check("exam: NO%d pinned (question + > NO)" % (k + 1), pinned(q, "> NO") and not pda.thaw_text.text.contains("> NO"))
		check("exam: NO%d reply" % (k + 1), pda._exam_no == k + 1 and int(pda.vars.get("exam_no_count", 0)) == k + 1
			and await wait_text(no_lines[k], 5.0))
		check("exam: NO%d stream" % (k + 1), pda.voice_exam.stream.resource_path.ends_with("memorytestB%d.wav" % (k + 1)))
		if k == 3:
			var r0: float = pda._exam_red
			await wait_s(1.0)
			check("exam: NO4 red edges creep in with the VO", r0 > 0.0 and pda._exam_red > r0 and pda.exam_fx.visible)
		await exam_skip()
		if k < 3:
			check("exam: choices again after NO%d" % (k + 1), pda._thaw_phase == pda.ThawPhase.EXAM_CHOICES)
	check("exam: NO4 -> QTE", pda._thaw_phase == pda.ThawPhase.EXAM_DEATH)
	await process_frame
	check("exam: QTE is the only choice", pda._thaw_choice_btns.size() == 1 and pda._exam_qte_btn != null)
	check("exam: QTE rect == choice button rect", rect_eq(pda._exam_qte_btn.get_global_rect(), choice_rect))
	check("exam: QTE header timer without key names", pda.thaw_choices_header.text.begins_with("RESPONSE  //  WINDOW CLOSING"))
	no_hints("QTE")
	# --- DEV BACK out of the QTE: previous screen (NO3) replays, O2 timer + red cancelled ---
	check("dev back: history has the NO screens", Array(pda.dev_history_labels()).has("EXAM > NO3")
		and pda.dev_history_labels()[-1] == "EXAM > NO4")
	await wait_s(0.3)
	await wheel_up()
	check("dev back (wheel up): NO3 screen restarts", pda._thaw_phase == pda.ThawPhase.EXAM_VO and pda._exam_no == 3
		and pinned("Please indicate that you understand.", "> NO")
		and pda.voice_exam.playing and pda.voice_exam.stream.resource_path.ends_with("memorytestB3.wav")
		and pda._thaw_t < 1.0 and pda._thaw_forced == -1)
	check("dev back: QTE gone, O2 timer + red cancelled", pda._exam_qte_btn == null and pda._exam_red_mode == ""
		and pda._exam_red < 0.05 and pda._exam_heart.playing == false)
	check("dev back: vars + map restored", int(pda.vars["exam_no_count"]) == 3
		and pda.vessel_map["doors"][0]["state"] == "open" and not pda.has_flag("stasis_sealed"))
	var o2_back: float = pda.o2_level
	await wait_s(0.6)
	check("dev back: O2 stays full (no countdown)", is_equal_approx(o2_back, 100.0) and is_equal_approx(pda.o2_level, 100.0)
		and pda._thaw_phase == pda.ThawPhase.EXAM_VO)
	pda.dev_mode = false
	await wait_s(0.35)
	await wheel_up()
	check("dev back disabled when not a debug build", pda._exam_no == 3 and pda.voice_exam.stream.resource_path.ends_with("memorytestB3.wav")
		and pinned("Please indicate that you understand.", "> NO"))
	pda.dev_mode = true
	var sc := ScrollContainer.new()
	sc.size = Vector2(200, 100)
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(100, 600)
	sc.add_child(tall)
	pda.add_child(sc)
	await process_frame
	sc.scroll_vertical = 80
	await process_frame
	var blocked: bool = pda._wheel_can_scroll_up(tall)
	sc.scroll_vertical = 0
	await process_frame
	check("dev back yields to a panel that can still scroll up", blocked and not pda._wheel_can_scroll_up(tall))
	sc.queue_free()
	# back to the QTE the normal way
	await exam_skip()
	await key(KEY_2)
	await exam_skip()
	check("exam: NO4 again -> QTE", pda._thaw_phase == pda.ThawPhase.EXAM_DEATH and int(pda.vars["exam_no_count"]) == 4)
	await process_frame
	check("exam: old centred O2 box gone", not pda.has_node("%ExamDeathBox"))
	check("exam: STASIS-3 door locked (map + HUD minimap)", pda.vessel_map["doors"][0]["state"] == "locked"
		and pda.hud_map.map_data["doors"][0]["state"] == "locked")
	check("exam: HUD minimap ignores mouse", pda.hud_map.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and pda.hud_map_frame.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	pda.hud_map._gui_input(click)
	await key(KEY_M)
	check("exam: minimap click / M do not open the map", not pda.map_overlay.visible and pda._thaw_phase == pda.ThawPhase.EXAM_DEATH)
	await wait_s(0.7)
	var lv: float = pda.o2_level
	check("exam: O2 ticks down in 5% steps", lv < 100.0 and lv > 0.0 and is_equal_approx(fmod(lv, 5.0), 0.0))
	check("exam: HUD O2 = header O2, pulsing", is_equal_approx(pda.hud_o2.level, lv) and is_equal_approx(pda.o2_bar.level, lv)
		and pda.hud_o2.danger > 0.0)
	check("exam: QTE timer drains inside the button", pda._exam_qte_fill.size.x < pda._exam_qte_btn.size.x
		and pda._exam_qte_fill.get_parent() == pda._exam_qte_btn)
	await key(KEY_ESCAPE)
	var o2_paused: float = pda._exam_o2_t
	await wait_s(0.4)
	check("exam: pause freezes O2 timer", is_equal_approx(o2_paused, pda._exam_o2_t))
	await key(KEY_ESCAPE)
	var red_before: float = pda._exam_red
	var o2_before: float = pda.o2_level
	await key(KEY_SPACE)
	check("exam: NO WAIT, I UNDERSTAND", pda.has_flag("exam_understood") and pda._thaw_phase == pda.ThawPhase.EXAM_VO
		and pda.voice_exam.stream.resource_path.ends_with("memorytest1C.wav"))
	check("exam: recovery screen pinned", pinned("Please indicate in the affirmative", "> NO WAIT, I UNDERSTAND"))
	check("exam: recovery text", await wait_text("Good.", 3.0))
	await wait_s(0.6)
	check("exam: O2 refilling, red fading", pda.o2_level > o2_before and pda._exam_red < red_before)
	await exam_skip()
	await wait_s(1.0)
	check("exam: O2 back to 100 calm, red cleared", is_equal_approx(pda.o2_level, 100.0) and pda.o2_danger == 0.0
		and pda._exam_red < 0.01)
	check("exam: door unlocked after recovery", pda.vessel_map["doors"][0]["state"] == "open")
	check("exam: recovery -> CONTINUE", pda._thaw_phase == pda.ThawPhase.EXAM_WAIT)
	await key(KEY_ENTER)
	check("enter -> Question 2", pda._exam_screen == 4 and pda.voice_exam.stream.resource_path.ends_with("memorytest2.wav"))
	pda._exam_finish()   # Q2/Q3 are covered by exam_test.gd; hand off to home_bunk (AFTER_EXAM path)
	check("exam hand-off -> home_bunk", pda.current_id == &"home_bunk")
	check("callsign OPERATOR", str(pda.vars["callsign"]) == "OPERATOR")
	check("vars: no=4 died=0 name=ZED", int(pda.vars["exam_no_count"]) == 4 and int(pda.vars["exam_died_count"]) == 0
		and str(pda.vars["typed_name"]) == "ZED")
	check("header line says OPERATOR", pda.os_line_label.text.contains("OPERATOR"))
	check("header O2 bar visible at 100%", pda.o2_bar.is_visible_in_tree() and is_equal_approx(pda.o2_bar.level, 100.0))
	check("fx cleared", not pda.exam_fx.visible and pda._exam_lowpass_idx < 0)
	check("thaw hidden", not pda.thaw.visible)
	check("pda chrome back", pda.safe_area.visible)
	no_hints("main UI (home_bunk)")
	check("main UI: choices without number prefix, ACTIONS header plain", pda._choice_buttons[0].get_child_count() == 0
		and (pda.find_child("ChoicesHeader", true, false) as Label).text == "ACTIONS"
		and pda.find_child("RailHint", true, false) == null)
	check("runner: no pin on arrival", not pda.story_text.text.contains("> "))
	# --- vessel map ---
	check("map: current room stasis_3", str(pda.vessel_map.get("current", "")) == "stasis_3")
	check("map: stasis explored", pda.vessel_map["rooms"]["stasis_3"]["state"] == "explored")
	check("map: ready room unexplored", pda.vessel_map["rooms"]["ready_room"]["state"] == "unexplored")
	check("minimap visible", pda.mini_map_frame.is_visible_in_tree())
	await key(KEY_M)
	check("M opens map", pda.map_overlay.visible)
	no_hints("vessel map")
	await key(KEY_1)
	check("choices blocked under map", not pda.has_flag("asked_split"))
	await key(KEY_ESCAPE)
	check("Esc closes map", not pda.map_overlay.visible)
	check("Esc did not pause", not pda.pause_menu.visible)
	await key(KEY_M)
	await key(KEY_M)
	check("M toggles map closed", not pda.map_overlay.visible)
	pda._mini_map.map_clicked.emit()
	await process_frame
	check("minimap click opens map", pda.map_overlay.visible)
	pda.map_close_button.pressed.emit()
	await process_frame
	check("close button closes map", not pda.map_overlay.visible)
	pda.open_dossier(&"orison")
	no_hints("dossier popup")
	pda.close_popup()
	await key(KEY_ESCAPE)
	no_hints("pause menu")
	await key(KEY_ESCAPE)
	pda.run_op("map_explore:ready_room")
	var door_was := str(pda.vessel_map["doors"][2]["state"])
	pda.run_op("map_unlock_door:stbd_hold|ready_room")
	pda.run_op("map_lock_room:stbd_hold")
	pda.run_op("map_set_room:ready_room")
	check("op map_explore", pda.vessel_map["rooms"]["ready_room"]["state"] == "explored")
	check("op map_unlock_door", door_was == "locked" and pda.vessel_map["doors"][2]["state"] == "open")
	check("op map_lock_room", pda.vessel_map["rooms"]["stbd_hold"]["state"] == "locked")
	check("op map_set_room", str(pda.vessel_map["current"]) == "ready_room")
	pda.run_op("map_explore:stbd_hold")
	check("explore skips locked room", pda.vessel_map["rooms"]["stbd_hold"]["state"] == "locked")
	pda.run_op("map_restrict_room:airlock")
	check("op map_restrict_room (flag + refusal RESTRICTED)", pda.map_room_restricted("airlock")
		and pda.map_move_refusal("airlock") == pda.MAP_MSG_RESTRICTED and pda._full_map.room_restricted("airlock"))
	pda.run_op("map_unrestrict_room:airlock")
	check("op map_unrestrict_room", not pda.map_room_restricted("airlock") and pda.map_move_refusal("airlock") == pda.MAP_MSG_KEYCARD)
	pda.run_op("map_set_room:stasis_3")
	# Minimap collapses when many choices need the ACTIONS column, then comes back.
	var many: Array = []
	for i in 8:
		many.append({"label": "Test choice %d" % (i + 1)})
	pda._build_choices(many)
	await process_frame
	await process_frame
	await process_frame
	check("minimap body hidden with 8 choices", not pda.mini_map_host.visible and pda.mini_map_frame.visible)
	pda.render_passage()
	await process_frame
	await process_frame
	await process_frame
	check("minimap body back with 2 choices", pda.mini_map_host.visible)

	# --- NO path: fresh instance, hold-to-skip, click the NO button ---
	await new_intro()
	var down := InputEventKey.new()
	down.physical_keycode = KEY_SPACE
	down.keycode = KEY_SPACE
	down.pressed = true
	Input.parse_input_event(down)
	await wait_s(0.9)
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	check("hold skips main", pda._thaw_phase == pda.ThawPhase.CHOICES and not pda.voice_main.playing)
	check("NO button exists", pda._thaw_choice_btns.size() == 2)
	var no_btn: Button = pda._thaw_choice_btns[1]
	no_btn.pressed.emit()
	await process_frame
	# A second emit after the phase has left CHOICES must be a no-op.
	pda._thaw_pick(false, 0.0)
	await process_frame
	check("flag thaw_said_no", pda.has_flag("thaw_said_no") and not pda.has_flag("thaw_said_yes"))
	check("double pick ignored", pda._thaw_phase == pda.ThawPhase.REPLY)
	check("voice no playing", pda.voice_no.playing)
	await key(KEY_ESCAPE)
	check("reply paused", pda.voice_no.stream_paused)
	await key(KEY_ESCAPE)
	check("reply resumed", pda.voice_no.playing)
	await skip_vo_section()
	check("THAW NO reply pinned + CONTINUE", pinned("Are you observing the TRM-CUFF now?", "> NO")
		and pda._thaw_phase == pda.ThawPhase.EXAM_WAIT)

	# --- forced choice (--thaw_choice=no) goes straight to the reply ---
	await new_intro("no")
	check("forced: reply phase", pda._thaw_phase == pda.ThawPhase.REPLY and pda.voice_no.playing)
	check("forced: main not playing", not pda.voice_main.playing)
	check("forced: flag no", pda.has_flag("thaw_said_no"))
	await skip_vo_section()
	await key(KEY_ENTER)
	check("forced: exam", pda._thaw_phase == pda.ThawPhase.EXAM_VO and pda._exam_screen == 1)

	# --- timer expiry: generic death screen, RETRY replays screen 3 (VO + typewriter) ---
	pda._exam_name = "ZED"
	pda._exam_show_screen(3, true)
	await process_frame
	check("death: choices", pda._thaw_phase == pda.ThawPhase.EXAM_CHOICES)
	await no_until_death()
	check("death: countdown", pda._thaw_phase == pda.ThawPhase.EXAM_DEATH)
	pda._exam_o2_t = 9.7   # MemoryExam.O2_SECONDS = 10
	await wait_s(0.6)
	check("death: timer expired", pda._thaw_phase == pda.ThawPhase.EXAM_DEAD and int(pda.vars["exam_died_count"]) == 1)
	pda.retry_death()
	check("death: retry ignored during fade", pda._thaw_phase == pda.ThawPhase.EXAM_DEAD and not pda.is_dead())
	await key(KEY_SPACE)
	check("death: Space ignored during fade", pda._thaw_phase == pda.ThawPhase.EXAM_DEAD and not pda.has_flag("exam_understood"))
	await wait_s(1.8)
	check("death: generic template death screen", pda.is_dead() and pda.death_heading.text == "SIGNAL LOST"
		and pda.death_message.text == "OPERATOR DECEASED" and pda.death_retry_button.text == "RETRY")
	check("death: every other layer hidden (header, overlay, HUD, pin, text, choices)", not pda.thaw.visible
		and not pda.safe_area.visible and not pda.hud_o2.is_visible_in_tree() and not pda.hud_map.is_visible_in_tree()
		and not pda.thaw_pin.is_visible_in_tree() and not pda.thaw_choices.is_visible_in_tree()
		and not pda.find_child("Frame", false, false).visible and pda.screen.visible)
	var dbox: Control = pda.death_screen.get_node("DeathCenter/DeathBox")
	check("death: message + RETRY centred on screen", dbox.get_global_rect().get_center().distance_to(
		pda.death_screen.get_global_rect().get_center()) < 2.0)
	check("death: O2 at 0", is_equal_approx(pda.o2_level, 0.0) and pda.hud_o2.percent_text() == "0%")
	no_hints("death screen")
	await key(KEY_ENTER)
	check("retry: screen 3 replays its VO", not pda.is_dead() and pda.thaw.visible and pda._exam_screen == 3
		and pda._thaw_phase == pda.ThawPhase.EXAM_VO and pda.voice_exam.playing
		and pda.voice_exam.stream.resource_path.ends_with("memorytest1.wav"))
	check("retry: typewriter starts from 0", pda._thaw_forced == -1 and pda._thaw_t < 23.5
		and pda.thaw_text.get_parsed_text().length() < 12)
	check("retry: name pinned as ERROR", pinned("1) Do you remember your name?", "ERROR"))
	check("retry: fx + door reset", pda._exam_fx_black == 0.0 and pda._exam_red < 0.01
		and pda.vessel_map["doors"][0]["state"] == "open")
	check("retry: text types in with the VO", await wait_text("The name", 4.0) and pda._thaw_phase == pda.ThawPhase.EXAM_VO)
	await exam_skip()
	check("retry -> YES/NO", pda._thaw_phase == pda.ThawPhase.EXAM_CHOICES and pda._exam_no == 0
		and pda.thaw_text.text.contains("Please indicate that you understand."))
	await wait_s(0.5)
	check("retry: O2 refilled", is_equal_approx(pda.o2_level, 100.0))
	await key(KEY_2)
	check("retry: NO loop restarts at NO1", pda._exam_no == 1)
	await exam_skip()
	await key(KEY_1)
	check("YES -> pinned + Acknowledged", pinned("Please indicate that you understand.", "> YES")
		and await wait_text("Acknowledged, Operator.", 3.0))
	await exam_skip()
	await key(KEY_SPACE)
	check("YES path -> CONTINUE -> Question 2", pda._exam_screen == 4 and pda.thaw.visible)
	pda._exam_finish()
	check("YES path -> home_bunk", pda.current_id == &"home_bunk" and pda.has_flag("exam_said_yes")
		and int(pda.vars["exam_died_count"]) == 1 and int(pda.vars["exam_no_count"]) == 5)
	check("comms greets OPERATOR", str(pda.format_text("MORNING, {v:callsign}.")) == "MORNING, OPERATOR.")
	await key(KEY_1)
	check("1 -> asked_split", pda.has_flag("asked_split"))
	check("runner: chosen label pinned at top", pda.story_text.text.begins_with("[color=")
		and pda.story_text.text.contains("> Ask about the salvage split"))
	await key(KEY_1)
	check("1 -> home_lock", pda.current_id == &"home_lock")
	pda.dev_back()
	check("dev back (passage): home_bunk with the pinned response", pda.current_id == &"home_bunk"
		and pda.story_text.text.contains("> Ask about the salvage split") and pda.has_flag("asked_split"))
	await key(KEY_1)
	check("forward again -> home_lock", pda.current_id == &"home_lock")
	await key(KEY_E)
	check("E skips locked DECK -> LOCKER", pda.current_tab == 2)
	await key(KEY_Q)
	check("Q -> LOG", pda.current_tab == 0)
	await key(KEY_1)
	check("1 -> took lamp", pda.has_flag("has_worklamp"))
	check("DECK forced open once", pda.current_tab == 1)
	await key(KEY_Q)
	pda.goto(&"home_airlock")
	check("airlock armed", pda.is_window_armed() and pda.hourglass.visible)
	# --- generic death from a story op ---
	pda.passages[&"kt_die"] = {"title": "TEST", "body": "Test room.", "choices": [
		{"label": "Step into the dark", "ops": ["checkpoint", {"die": {"message": "Hull breach", "retry": "home_lock"}}]}]}
	pda.goto(&"kt_die")
	await key(KEY_1)
	check("die op: death screen with the op message", pda.is_dead() and pda.death_message.text == "HULL BREACH"
		and pda.death_heading.text == "SIGNAL LOST")
	check("die op: main UI hidden, background kept", not pda.safe_area.visible and not pda.o2_bar.is_visible_in_tree()
		and pda.screen.visible)
	await key(KEY_1)
	check("die op: RETRY ignored in the first 350 ms", pda.is_dead())
	await wait_s(0.5)
	await key(KEY_ENTER)
	check("die op: RETRY -> retry passage, UI back", not pda.is_dead() and pda.current_id == &"home_lock" and pda.safe_area.visible)
	pda.run_op("die")
	pda._flush_after()
	check("die op (string, defaults)", pda.is_dead() and pda.death_message.text == "OPERATOR DECEASED")
	await wait_s(0.5)
	pda.death_retry_button.pressed.emit()
	check("die op: no retry target -> last checkpoint", not pda.is_dead() and pda.current_id == &"kt_die")
	print("DONE fails=%d" % fails)
	quit(fails)
