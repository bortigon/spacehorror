extends SceneTree
## EXCURSION 1 PREP (headless):
##   godot --headless --audio-driver Dummy --path . --script res://tools/excursion_test.gd
## Covers: the chapter data (Scene Writer JSON, exact text + tips, VO clip + cues, stable
## rebuild), the RSV ABEYANCE map (READY ROOM = the big room above STASIS-15, AIRLOCK = the L,
## open / locked doors), the exam → chapter hand-off, the chapter fade-in (VO held until the
## scene is visible), the main game UI (tabs, header O2, minimap), the opening text + VO, the
## 7 map tips in order with their highlight targets, dev back through the walkthrough,
## click-to-move (open door moves, locked door refuses, non-adjacent refuses, RESTRICTED
## refuses), reaching the READY ROOM in one click, the RESTRICTED pop on STBD HOLD (full map +
## minimap), the holding screen, the intro still blocking map moves, and nothing overflowing.

const SceneData := preload("res://ui/story_scene.gd")
const Builder := preload("res://addons/scene_writer/scene_builder.gd")
const JSON_PATH := "res://story/scenes/excursion1_prep.json"
const SCENE := "res://scenes/authored/excursion1_prep.tscn"
const BRIEF_P1 := "OPERATOR, now that you have excreted waste, decontaminated yourself, and ingested nutrients, we will prepare for the EXCURSION. Reminder: Everything you do aboard any REC-7 vessel is recorded. The scheduled EXCURSION will begin now."
const BRIEF_P2 := "Please proceed to the READY ROOM."
const VO_CLIP := "res://assets/sounds/Exursion1prep.wav"
## Cue per voiced line (faster-whisper word times + silence gaps in the clip).
const VO_CUES := [[1.0, 6.72], [7.19, 8.78], [9.43, 14.44], [14.91, 17.14]]
const TIPS := [
	["map", "This is your TRM-CUFF Map. The yellow circle indicates your current position."],
	["room:stasis_15", "Green rooms have been explored."],
	["room:stbd_hold", "Dark rooms have not been explored."],
	["room:ready_room", "If a Dark Room is named, you might know what to expect, but you have not explored it."],
	["door:stasis_15|ready_room", "These lines indicate doors or other passages."],
	["door:ready_room|stbd_hold", "Lock symbols mean the door is locked, and you will need a KEYCARD to open it."],
	["rooms", "Click on the room you wish to move to. If there is an accessible passage, you will move there."],
]
const VIEW := Rect2(0, 0, 960, 540)

var fails := 0
var passes := 0
var pda
var _hint_re := RegEx.create_from_string("\\[|\\bSPACE\\b|\\bESC\\b|\\bENTER\\b|\\bPRESS\\b|\\bKEY\\b|\\bTAB\\b|\\(M\\)|\\bM\\b")


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if ok:
		passes += 1
	else:
		fails += 1


func key(kc: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = kc
		e.keycode = kc
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
	await process_frame


## A real left click at a screen position, through the viewport's GUI input (hits whatever
## control is on top there, like the player's mouse).
func click(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	root.push_input(mm, true)
	await process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e, true)
		await process_frame
	await process_frame


func wait_s(sec: float) -> void:
	await create_timer(sec).timeout


func frames(n := 3) -> void:
	for _i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	PdaScreen.tutorials_enabled = false
	test_data()
	test_map_data()
	await test_handoff()
	await test_chapter()
	await test_intro_blocks_moves()
	print("DONE fails=%d passes=%d" % [fails, passes])
	quit(fails)


# ---------------------------------------------------------------- data

func test_data() -> void:
	var d := SceneData.load_file(JSON_PATH)
	var screens: Array = d.get("screens", [])
	check("data: excursion1_prep.json loads (3 screens: brief, map, ready_room)", screens.size() == 3
		and str(screens[0]["id"]) == "brief" and str(screens[1]["id"]) == "map" and str(screens[2]["id"]) == "ready_room")
	var probs := SceneData.validate(d)
	var errs := probs.filter(func(p: Dictionary) -> bool: return p["level"] == "error")
	for p: Dictionary in probs:
		print("   note: ", p["msg"])
	check("data: validates with no errors / warnings (%d notes)" % probs.size(), probs.is_empty())
	check("data: title EXCURSION 1 // PREP, main game UI, fades in, no next chapter yet",
		str(d["title"]) == "EXCURSION 1 // PREP" and str(d["ui"]) == "game" and float(d["fade_in"]) >= 0.5 and str(d["after"]) == "order:next")
	var vo: Dictionary = screens[0]["vo"]
	var cues_ok: bool = (vo["cues"] as Array).size() == VO_CUES.size()
	for i in mini((vo["cues"] as Array).size(), VO_CUES.size()):
		cues_ok = cues_ok and is_equal_approx(float(vo["cues"][i][0]), VO_CUES[i][0]) and is_equal_approx(float(vo["cues"][i][1]), VO_CUES[i][1])
	check("data: opening voiced by %s (4 cues, one per voiced line; the READY ROOM line types after)" % VO_CLIP.get_file(),
		str(vo["clip"]) == VO_CLIP and cues_ok and ResourceLoader.exists(VO_CLIP))
	var stream := load(VO_CLIP) as AudioStream if ResourceLoader.exists(VO_CLIP) else null
	check("data: cues inside the clip (%.2f s), in order, no overlap" % (stream.get_length() if stream else -1.0),
		stream != null and float(VO_CUES[-1][1]) <= stream.get_length() and VO_CUES[0][0] < VO_CUES[0][1]
		and VO_CUES[1][0] >= VO_CUES[0][1] and VO_CUES[2][0] >= VO_CUES[1][1] and VO_CUES[3][0] >= VO_CUES[2][1])
	check("data: brief on_enter names the READY ROOM (the AIR LOCK stays nameless until its door is unlocked), opens the STASIS-15 door",
		(screens[0]["on_enter"] as Array).has("map_know_room:ready_room") and not (screens[0]["on_enter"] as Array).has("map_know_room:airlock")
		and (screens[0]["on_enter"] as Array).has("map_unlock_door:stasis_15|ready_room"))
	var tips: Array = (screens[1]["end"] as Dictionary).get("tips", [])
	var same := tips.size() == TIPS.size()
	for i in mini(tips.size(), TIPS.size()):
		same = same and str(tips[i]["target"]) == TIPS[i][0] and str(tips[i]["text"]) == TIPS[i][1]
	check("data: 7 tips, David's text exactly (\"you will move\" fixed) + targets", same)
	var all_tips := JSON.stringify(tips)
	check("data: no \"your will move\" typo left", not all_tips.contains("your will move") and all_tips.contains("you will move"))
	var e1: Dictionary = screens[1]["end"]
	check("data: walkthrough ends by walking to the READY ROOM", str(e1["type"]) == "map_tour" and str(e1["move_to"]) == "ready_room"
		and str(e1["move_prompt"]) == BRIEF_P2)
	check("data: no timed RESTRICTED stamp any more (on_arrive empty; it appears when the lock is clicked)", e1["on_arrive"] == [])
	var e2: Dictionary = screens[2]["end"]
	check("data: READY ROOM = locker + coffee pot links, arms the hours, leaves through the airlock door (no SUIT REQUIRED gate)",
		str(screens[2]["heading"]) == "READY ROOM" and str(screens[2]["text"]).contains("[act=locker]LOCKER[/act]")
		and str(screens[2]["text"]).contains("[act=coffee]COFFEE POT[/act]") and not str(screens[2]["text"]).contains("does not spend")
		and str(e2["type"]) == "hold" and str(e2["goto"]) == "order:next" and str(e2["exit"]) == "door:ready_room|airlock"
		and not e2.has("require") and str(screens[2]["tutorial"]) == "items"
		and (screens[2]["on_enter"] as Array).has("arm_hours") and not (screens[2]["on_enter"] as Array).has("map_restrict_room:stbd_hold")
		and bool(screens[2]["acts"]["locker"]["container"])
		and str(screens[2]["acts"]["locker"]["items"][0]["id"]) == "suit"
		and str(screens[2]["acts"]["locker"]["items"][0]["label"]) == "SUIT"
		and int(screens[2]["acts"]["locker"]["items"][1]["hours"]) == 1
		and str(screens[2]["acts"]["locker"]["items"][2]["id"]) == "airlock_keycard"
		and str(screens[2]["acts"]["coffee"]["station"]) == "coffee")
	var before := FileAccess.get_file_as_string(JSON_PATH)
	var res := Builder.build(d)
	check("data: Scene Writer builder rebuilds it unchanged (%s)" % res["message"], bool(res["ok"])
		and FileAccess.get_file_as_string(JSON_PATH) == before and ResourceLoader.exists(SCENE))
	# new end types + scene fields normalize / validate
	var n := SceneData.normalize({"id": "t", "ui": "bogus", "fade_in": "2", "screens": [
		{"text": "", "end": {"type": "map_tour", "tips": ["plain tip", {"text": "x", "target": "door:nowhere|x"}], "move_to": "bridge",
			"on_arrive": "map_restrict_room:stbd_hold"}},
		{"text": "a", "end": {"type": "hold"}}, {"text": "b", "end": {"type": "map_tour", "tips": ["t"], "on_arrive": ["map_explore:airlock"]}}]})
	check("normalize: ui falls back to stage, fade_in cast, string tip → map target, on_arrive string → list",
		n["ui"] == "stage" and is_equal_approx(float(n["fade_in"]), 2.0) and n["screens"][0]["end"]["tips"][0]["target"] == "map"
		and n["screens"][0]["end"]["on_arrive"] == ["map_restrict_room:stbd_hold"] and n["screens"][1]["end"].get("on_arrive") == null)
	var msgs := JSON.stringify(SceneData.validate(n))
	check("validate: bad tip target, unknown move_to room, hold not last, tour without game UI (no empty-screen note)",
		msgs.contains("unknown door") and msgs.contains("is not on the map") and msgs.contains("holds (ends the scene) but is not the last")
		and msgs.contains("main game UI") and not msgs.contains("is empty") and msgs.contains("on_arrive"))
	var legacy := SceneData.normalize({"id": "legacy_act", "screens": [{
		"text": "x",
		"acts": [{"id": "locker", "title": "LOCKER", "actions": [
			{"id": "suit", "label": "SUIT", "hours": 1, "item": "suit", "required": true}]}]
	}]})
	var leg_acts: Dictionary = legacy["screens"][0]["acts"]
	check("normalize: old act menu becomes a function", leg_acts.has("locker")
		and str(leg_acts["locker"]["choices"][0]["item"]) == "suit"
		and bool(leg_acts["locker"]["choices"][0]["required"]))


func test_map_data() -> void:
	var m := Vessel.default_map()
	var rooms: Dictionary = m["rooms"]
	var rr: Dictionary = rooms.get("ready_room", {})
	var al: Dictionary = rooms.get("airlock", {})
	check("map: READY ROOM = the big room above STASIS-15 (was COMMISSARY), unexplored",
		str(rr.get("label", "")) == "READY ROOM" and str(rr.get("state", "")) == "unexplored"
		and (rr.get("poly", []) as Array).size() == 4 and (rr["poly"][0] as Vector2).is_equal_approx(Vector2(45, 111)))
	check("map: AIR LOCK = the L on the left (was READY ROOM / PORT ACCESS), unexplored",
		str(al.get("label", "")) == "AIR LOCK" and str(al.get("state", "")) == "unexplored" and (al.get("poly", []) as Array).size() == 8)
	check("map: no COMMISSARY / PORT ACCESS left", not rooms.has("commissary") and not rooms.has("port_access"))
	var st := {}
	for dd: Dictionary in m["doors"]:
		var ids := [str(dd["a"]), str(dd["b"])]
		ids.sort()
		st["|".join(PackedStringArray(ids))] = str(dd["state"])
	check("map: STASIS-15 | READY ROOM open (one click)", st.get("ready_room|stasis_15", "") == "open")
	check("map: READY ROOM | STBD HOLD locked, READY ROOM | AIRLOCK locked (padlocks as in the mockup)",
		st.get("ready_room|stbd_hold", "") == "locked" and st.get("airlock|ready_room", "") == "locked")


# ---------------------------------------------------------------- exam → chapter

func test_handoff() -> void:
	var intro = (load("res://scenes/intro.tscn") as PackedScene).instantiate()
	root.add_child(intro)
	current_scene = intro
	await frames(4)
	intro.flags["exam_complete"] = true
	intro.o2_level = 60.0
	check("hand-off: intro AFTER_EXAM hook points at the new chapter", intro.after_exam_target == "scene:excursion1_prep")
	intro._exam_go_after(intro.after_exam_target)
	await frames(6)
	pda = current_scene
	var ok_scene: bool = pda != null and pda != intro and str(pda.scene_path) == JSON_PATH
	check("hand-off: exam leaves into scenes/authored/excursion1_prep.tscn", ok_scene)
	if not ok_scene:
		return
	check("hand-off: chapter starts on black and fades in (flags carried)", pda.fade_rect != null and pda.fade_rect.visible
		and pda.fade_rect.modulate.a > 0.8 and pda.has_flag("exam_complete") and pda.screen_index == 0)
	check("hand-off: O2 back to full for the chapter (%.0f%%)" % pda.o2_level, is_equal_approx(pda.o2_level, 100.0))
	pda.queue_free()
	await frames(3)


# ---------------------------------------------------------------- the chapter

func spawn() -> void:
	pda = (load(SCENE) as PackedScene).instantiate()
	root.add_child(pda)
	current_scene = pda
	await frames(3)


func fits_view(r: Rect2) -> bool:
	return VIEW.encloses(r.grow(-0.5))


func no_hints(s: String) -> bool:
	return _hint_re.search(s.to_upper()) == null


func room_center_global(id: String) -> Vector2:
	var pts: PackedVector2Array = pda._full_map.room_poly_local(id)
	var c: Vector2 = pda._full_map._poly_center(pts)
	return pda._full_map.global_position + c


func tip_matches(k: int) -> bool:
	return (pda.tour_phase == "tip" and pda.tour_step == k and pda.tour.visible and pda.tour.target == TIPS[k][0]
		and pda.tour.text_label.text == TIPS[k][1] and pda.tour.header_label.text == "TIP %d/7" % (k + 1))


func stage_fits(where: String) -> void:
	await frames(3)
	var st = pda.stage
	var sr: Rect2 = st.get_global_rect()
	var tr: Rect2 = st.text_label.get_global_rect()
	var vbar: VScrollBar = st.scroll.get_v_scroll_bar()
	var no_scroll := vbar.max_value - vbar.page <= 1.0
	var cont_ok: bool = not st.continue_button.visible or (fits_view(st.continue_button.get_global_rect())
		and st.continue_button.size.is_equal_approx(Vector2(220, 38)))
	check("%s: fits 960x540, no scrolling, stage inside the story column, CONTINUE standard size" % where,
		fits_view(sr) and no_scroll and tr.end.y <= sr.end.y + 0.5 and cont_ok and fits_view(pda.title_label.get_global_rect()))


func test_chapter() -> void:
	await spawn()
	check("fade: chapter opens on black, text waits for the fade", pda.fade_rect.visible and pda.fade_rect.modulate.a > 0.9
		and pda.stage.frozen)
	check("fade: VO clip loaded and held (paused) while the screen is black", pda.stage.voice.stream != null
		and pda.stage.voice.stream.resource_path == VO_CLIP and pda.stage.voice.stream_paused and pda.stage._use_voice_clock)
	await wait_s(float(pda.scene["fade_in"]) * 0.5)
	var mid: float = pda.fade_rect.modulate.a
	check("fade: halfway through (a=%.2f)" % mid, mid > 0.2 and mid < 0.8)
	await wait_s(float(pda.scene["fade_in"]) * 0.5 + 0.25)
	check("fade: done, black gone, text typing", not pda.fade_rect.visible and not pda.stage.frozen and pda.stage.is_typing())
	var vpos: float = pda.stage.voice.get_playback_position()
	check("VO: plays once the fade is done, from the start (pos %.2f s)" % vpos, pda.stage.voice.playing
		and not pda.stage.voice.stream_paused and vpos < 0.7)
	await wait_s(1.6)
	var shown: String = pda.stage.text_label.get_parsed_text()
	var c1: float = pda.stage.clock
	check("VO: text follows the voice clock (clock %.2f ≈ clip pos %.2f; line 1 typing, line 2 not yet)" % [c1, pda.stage.voice.get_playback_position()],
		absf(c1 - pda.stage.voice.get_playback_position()) < 0.15 and shown.length() > 3 and not shown.contains("we will prepare"))
	# main game UI
	var tabs_ok: bool = pda.tab_buttons[pda.Tab.LOG].is_visible_in_tree() and not pda.tab_buttons[pda.Tab.DECK].visible 		and not pda.tab_buttons[pda.Tab.LOCKER].visible and not pda.tab_buttons[pda.Tab.KIT].visible 		and pda.inv_button.visible and pda.inv_button.text == "INV"
	check("game UI: header + LOG/INV rail + journal visible (LOG tab)", pda.safe_area.visible and tabs_ok and pda.journal_button.visible
		and pda.current_tab == pda.Tab.LOG)
	var filled := 0
	for c in pda.time_bar.get_children():
		if c is ColorRect and (c as ColorRect).color.g > 0.5:
			filled += 1
	check("game UI: 8 hour blocks, full, not live yet (the intro screens do not arm them)", pda.time_bar.visible and filled == 8
		and pda.time_blocks == 8 and not pda.time_blocks_live and pda.spend_time_blocks(1) == false and pda.time_blocks == 8)
	var title_w: float = pda.title_label.get_theme_font("font").get_string_size(pda.title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		pda.title_label.get_theme_font_size("font_size")).x
	check("game UI: title bar reads EXCURSION 1 // PREP (fits)", pda.title_label.text == "EXCURSION 1 // PREP"
		and title_w <= pda.title_label.size.x)
	check("game UI: O2 full (100%)", is_equal_approx(pda.o2_level, 100.0) and pda.o2_danger == 0.0)
	check("game UI: minimap shown in the ACTIONS column, map interactive", pda.mini_map_frame.is_visible_in_tree()
		and pda._mini_map.interactive and pda.mini_map_host.is_visible_in_tree())
	check("game UI: story typed in the LOG column (stage embedded, no stage status line / overlay HUD)",
		pda.stage.get_parent() == pda.log_view and not pda.story_text.visible and not pda.stage.status_label.visible
		and pda.hud_map == null)
	check("map: READY ROOM name known but not explored; AIR LOCK + STBD HOLD nameless; side doors drawn",
		bool(pda.vessel_map["rooms"]["ready_room"].get("known", false)) and pda.vessel_map["rooms"]["ready_room"]["state"] == "unexplored"
		and pda._map_room_label("ready_room") == "READY ROOM" and pda._map_room_label("airlock") == "UNCHARTED COMPARTMENT"
		and pda.vessel_map["rooms"]["airlock"]["state"] == "unexplored" and pda._map_room_label("stbd_hold") == "UNCHARTED COMPARTMENT"
		and pda.map_door_between("ready_room", "stbd_hold").get("known", false) and pda.map_door_between("ready_room", "airlock").get("known", false)
		and not pda.map_room_restricted("stbd_hold"))
	check("map: click-to-move off until the walkthrough", not pda.map_moves_enabled())
	await key(KEY_SPACE)
	var txt: String = pda.stage.text_label.get_parsed_text()
	check("opening: OPERATOR paragraph exactly as scripted", txt.begins_with(BRIEF_P1))
	check("opening: \"Please proceed to the READY ROOM.\" is its own paragraph", txt.ends_with("\n\n" + BRIEF_P2) or txt.ends_with("\n" + BRIEF_P2))
	print("   opening text: ", txt.c_escape())
	check("opening: CONTINUE, no key hints", pda.stage.continue_button.visible and no_hints(txt) and no_hints(pda.stage.continue_button.text))
	await stage_fits("opening")
	# ---- walkthrough ----
	await key(KEY_SPACE)
	await frames(4)
	check("walkthrough: map screen opens the full map, locked open (no Close button)", pda.screen_index == 1
		and pda.map_overlay.visible and pda.map_locked_open and not pda.map_close_button.visible)
	var fmr: Rect2 = pda._full_map.get_global_rect()
	for k in TIPS.size():
		await frames(3)
		check("tip %d/7: in order, David's text, target %s" % [k + 1, TIPS[k][0]], tip_matches(k))
		var hole: Rect2 = pda.tour.hole_rect()
		var tgt: Rect2 = pda.tour.target_rect_in_map()
		tgt.position += pda._full_map.global_position
		var inside := hole.size.x > 4.0 and hole.encloses(tgt) and fmr.grow(12).encloses(hole)
		if TIPS[k][0] == "map":
			var you: Vector2 = pda._full_map.you_pos_local() + pda._full_map.global_position
			inside = inside and hole.has_point(you)
		var pr: Rect2 = pda.tour.panel.get_global_rect()
		var cb: Button = pda.tour.continue_button
		check("tip %d/7: highlight hole around the target (%s), rest dimmed, panel beside it inside the screen" % [k + 1, str(hole)],
			inside and fits_view(pr) and (TIPS[k][0] in ["map", "rooms"] or not pr.intersects(hole.grow(-2)))
			and pda.tour.mouse_filter == Control.MOUSE_FILTER_STOP and pda.tour.size.is_equal_approx(pda.map_overlay.size))
		check("tip %d/7: CONTINUE standard size (220x38), text fits the panel, no key hints" % (k + 1),
			cb.visible and cb.size.is_equal_approx(Vector2(220, 38)) and cb.text == "CONTINUE"
			and pr.encloses(cb.get_global_rect()) and pr.encloses(pda.tour.text_label.get_global_rect())
			and no_hints(pda.tour.header_label.text) and not pda.map_moves_enabled())
		if k == 0:
			await key(KEY_ESCAPE)
			await key(KEY_M)
			var paused: bool = pda.pause_menu.visible
			if paused:
				pda.hide_pause()
			check("tip 1/7: Esc / M don't close the walkthrough map", pda.map_overlay.visible and tip_matches(0))
		if k == 3 and pda.dev_mode:
			pda.dev_back()
			await frames(4)
			check("dev back: tip 4 → tip 3 (map still open, locked)", tip_matches(2) and pda.map_overlay.visible and pda.map_locked_open)
			pda._dev_back_ms = 0
			pda.dev_back()
			await frames(4)
			check("dev back: tip 3 → tip 2", tip_matches(1))
			pda._dev_back_ms = 0
			pda.tour.continue_button.pressed.emit()
			await frames(2)
			pda.tour.continue_button.pressed.emit()
			await frames(3)
			check("dev back: forward again to tip 4", tip_matches(3))
		if k % 2 == 0:
			await key(KEY_SPACE)
		else:
			pda.tour.continue_button.pressed.emit()
			await frames(2)
	await frames(3)
	check("after tip 7: walk phase (dim gone, map stays open, click-to-move on, prompt in the info line)",
		pda.tour_phase == "move" and not pda.tour.visible and pda.map_overlay.visible and pda.map_locked_open
		and pda.map_moves_enabled() and pda.map_info.text == BRIEF_P2.to_upper())
	check("walk: tip-7 text + prompt carry no key hints", no_hints(pda.map_info.text))
	# ---- click-to-move rules (real clicks on the full map) ----
	await click(room_center_global("stbd_hold"))
	check("walk: STBD HOLD from STASIS-15 (not adjacent) → NO ACCESSIBLE PASSAGE, no move",
		pda.map_last_message == pda.MAP_MSG_NO_PASSAGE and pda.map_info.text == pda.MAP_MSG_NO_PASSAGE
		and pda.vessel_map["current"] == "stasis_15" and pda.map_info.get_theme_color("font_color").is_equal_approx(pda.MAP_MSG_COLOR))
	await click(room_center_global("stasis_15"))
	check("walk: own room → YOU ARE HERE", pda.map_last_message == pda.MAP_MSG_HERE and pda.vessel_map["current"] == "stasis_15")
	await click(room_center_global("airlock"))
	check("walk: AIRLOCK (not adjacent) → NO ACCESSIBLE PASSAGE", pda.map_last_message == pda.MAP_MSG_NO_PASSAGE
		and pda.vessel_map["current"] == "stasis_15" and pda.vessel_map["rooms"]["airlock"]["state"] == "unexplored")
	await click(room_center_global("aft_port"))
	check("walk: non-adjacent room (AFT PORT) → NO ACCESSIBLE PASSAGE", pda.map_last_message == pda.MAP_MSG_NO_PASSAGE
		and pda.vessel_map["current"] == "stasis_15")
	if pda.dev_mode:
		pda._dev_back_ms = 0
		pda.dev_back()
		await frames(4)
		check("dev back: walk phase → tip 7 (still in STASIS-15, moves off again)", tip_matches(6)
			and pda.vessel_map["current"] == "stasis_15" and not pda.map_moves_enabled())
		await key(KEY_SPACE)
		await frames(2)
		check("walk phase again", pda.tour_phase == "move" and pda.map_moves_enabled())
	await click(room_center_global("ready_room"))
	var dot2: Vector2 = pda._full_map.you_pos_local()
	var rc: Vector2 = pda._full_map._poly_center(pda._full_map.room_poly_local("ready_room"))
	check("walk: READY ROOM in one click from STASIS-15 — explored (green), current, dot moved", pda.vessel_map["current"] == "ready_room"
		and pda.vessel_map["rooms"]["ready_room"]["state"] == "explored" and dot2.distance_to(rc) < 1.0 and pda.tour_phase == "arrived")
	check("arrival: STBD HOLD not restricted yet, door still locked", not pda.map_room_restricted("stbd_hold")
		and pda.map_door_between("ready_room", "stbd_hold")["state"] == "locked")
	await wait_s(pda.ARRIVE_WAIT + 0.4)
	var fm = pda._full_map
	check("arrival: NO timed RESTRICTED stamp (the label waits for a click on its lock), door still locked",
		not pda.map_room_restricted("stbd_hold") and fm.stamp_age("stbd_hold") > 100.0
		and pda.map_door_between("ready_room", "stbd_hold")["state"] == "locked" and fm._legend_entries().size() == 6)
	check("arrival: map closes by itself, holding screen READY ROOM", not pda.map_overlay.visible and not pda.map_locked_open
		and pda.map_close_button.visible and pda.screen_index == 2 and pda.stage.heading_label.text == "READY ROOM")
	pda.stage.skip_typing(true)
	await frames(2)
	var rtxt: String = pda.stage.text_label.get_parsed_text()
	check("arrival: ready room text (locker, coffee pot), no CONTINUE, hours armed", rtxt.contains("LOCKER") and rtxt.contains("COFFEE POT")
		and not pda.stage.continue_button.visible and pda.stage.end_type() == "hold" and no_hints(rtxt)
		and pda.time_blocks_live and pda.time_blocks == 8)
	await key(KEY_SPACE)
	await frames(2)
	check("arrival: Space does nothing here (no gate toast, no next screen)", pda.screen_index == 2
		and not str(pda.stage.text_label.get_parsed_text()).contains("The next scene isn't written.")
		and not pda.os_line_label.text.contains("SUIT REQUIRED"))
	var mm = pda._mini_map
	check("arrival: minimap shows READY ROOM current + explored, STBD HOLD NOT restricted yet, LOCKER + COFFEE POT markers",
		mm.map_data["current"] == "ready_room" and mm.room_state("ready_room") == "explored" and not mm.room_restricted("stbd_hold")
		and mm.marker_rect_local("locker").size.x > 10.0 and mm.marker_rect_local("coffee").size.x > 10.0)
	await stage_fits("READY ROOM holding screen")
	check("after the walkthrough: the map still opens and moves work (map usable from here on)", pda.map_moves_enabled())
	pda.open_map()
	await frames(2)
	await click(room_center_global("stbd_hold"))
	check("free walking: STBD HOLD room click → KEYCARD REQUIRED (amber), no move, no label reveal", pda.map_last_message == pda.MAP_MSG_KEYCARD
		and pda.map_info.text == pda.MAP_MSG_KEYCARD and pda.vessel_map["current"] == "ready_room" and not pda.map_room_restricted("stbd_hold")
		and pda.map_info.get_theme_color("font_color").is_equal_approx(pda.MAP_MSG_COLOR))
	await click(room_center_global("airlock"))
	check("free walking: AIRLOCK → KEYCARD REQUIRED (locked door), no move", pda.map_last_message == pda.MAP_MSG_KEYCARD
		and pda.vessel_map["current"] == "ready_room" and pda.vessel_map["rooms"]["airlock"]["state"] == "unexplored")
	pda._map_msg_until = 0
	pda._on_map_room_hovered("stbd_hold")
	check("free walking: hovering STBD HOLD reads UNCHARTED (nameless until its lock is clicked)", pda.map_info.text.begins_with("UNCHARTED COMPARTMENT"))
	await click(room_center_global("stasis_15"))
	check("free walking: READY ROOM → STASIS-15 through the open door", pda.vessel_map["current"] == "stasis_15" and pda.map_overlay.visible)
	pda.close_map()
	check("free walking: Close works again", not pda.map_overlay.visible)
	if pda.dev_mode:
		pda._dev_back_ms = 0
		pda.dev_back()
		await frames(4)
		check("dev back: holding screen → walk phase (map open, locked, moves on)", pda.tour_phase == "move" and pda.map_overlay.visible
			and pda.map_locked_open and pda.map_moves_enabled() and pda.screen_index == 1)
	# the "next" hook: a hold screen shows CONTINUE once the scene has an "after"
	pda.scene["after"] = "intro:home_bunk"
	(pda.screens[2]["end"] as Dictionary).erase("exit")   # a hold without an exit door
	pda._dev_stop_chapter()
	pda.screen_index = -1
	pda.enter_screen(2)
	await key(KEY_SPACE)
	await frames(2)
	check("next hook: with \"after\" set, the holding screen offers CONTINUE", pda.stage.continue_button.visible)
	pda.queue_free()
	await frames(3)
	# debug shots used on the PC
	await spawn()
	pda.queue_free()
	await frames(2)


func test_intro_blocks_moves() -> void:
	var intro = (load("res://scenes/intro.tscn") as PackedScene).instantiate()
	root.add_child(intro)
	current_scene = intro
	await frames(4)
	intro.ensure_vessel_map()
	intro.vessel_map["click_to_move"] = true
	intro.map_overlay.show()
	intro._full_map.room_clicked.emit("ready_room")
	await frames(2)
	check("intro: map clicks never move the player (intro still blocks map input)", intro.vessel_map["current"] == "stasis_15"
		and not intro._allow_map_moves())
	intro.queue_free()
	await frames(2)
