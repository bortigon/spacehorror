extends SceneTree
## Ready room items round (headless):
##   godot --headless --audio-driver Dummy --path . --script res://tools/ready_test.gd
## Empty inventory, keycard, map locks (error / unlock / label reveal), RESTRICTED on click only,
## suit (Put on, 1 hr, fade, worn figure), airlock warning, drop / pick up, HUD heights, hours spent
## and refused, coffee pot, the inventory walkthrough, the intro HUD. Pixels: look at it in the editor.

const SCENE := "res://scenes/authored/excursion1_prep.tscn"
const HoloWindowScript := preload("res://ui/holo_window.gd")
const NEW_SCENE := "res://scenes/authored/new_scene_2.tscn"

var fails := 0
var passes := 0
var pda


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if ok:
		passes += 1
	else:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func wait_s(sec: float) -> void:
	await create_timer(sec).timeout


func spawn(scene_path := SCENE, screen := 2) -> void:
	pda = (load(scene_path) as PackedScene).instantiate()
	root.add_child(pda)
	current_scene = pda
	await frames(3)
	pda.enter_screen(screen)
	await frames(2)
	pda.stage.skip_typing(true)
	await frames(2)
	pda._ensure_windows()
	pda.windows.set_animated(false)


func drop_scene() -> void:
	pda.queue_free()
	await frames(2)


func left() -> bool:
	return str(pda.stage.text_label.get_parsed_text()).contains("isn't written") or not str(pda.scene_file_path).ends_with("excursion1_prep.tscn")


func figure_col(chr) -> Color:
	return chr.FIGURE_SUIT if chr.suit_worn else chr.FIGURE_COLOR


func take_from_locker(id: String) -> void:
	pda.stage.open_act("locker")
	await frames(2)
	pda.windows.container.select_id(id)
	pda.windows.container.action_buttons[0].pressed.emit()
	await frames(2)
	pda.windows.close_all(true)
	await frames(2)


func _init() -> void:
	PdaScreen.tutorials_enabled = false
	await frames(1)
	await test_empty_and_keycard()
	await test_locks()
	await test_suit()
	await test_airlock_warning()
	await test_drop()
	await test_hud_and_hours()
	await test_coffee()
	await test_tutorial()
	await test_intro_hud()
	print("READY %d pass, %d fail" % [passes, fails])
	quit(1 if fails else 0)


func test_empty_and_keycard() -> void:
	await spawn()
	check("inventory starts empty (nothing in the list, 15 empty cells)", pda.inventory.is_empty())
	pda.show_inv()
	await frames(2)
	var chr = pda.windows.character
	check("character grid: 3 x 5 cells, none filled", chr.slots.size() == 15 and chr.filled_ids().is_empty())
	pda.windows.close_all(true)
	await take_from_locker("airlock_keycard")
	check("AIRLOCK KEYCARD taken: in inventory, 1 hr spent, id airlock_keycard, flagged taken",
		pda.inventory.has(&"airlock_keycard") and pda.time_blocks == 7 and pda.item_ever_taken("airlock_keycard"))
	pda.show_inv()
	await frames(2)
	var found := false
	for sl: Control in chr.slots:
		if not sl.item.is_empty() and str(sl.item["label"]) == "AIRLOCK KEYCARD":
			found = true
	check("keycard shows on the character screen by its exact name", found)
	await drop_scene()


func click_lock(key: String) -> void:
	# a real click through the minimap: the lock must be hit-testable where it is drawn
	var mm = pda._mini_map
	var r: Rect2 = mm.door_rect_local(key)
	var hit: String = mm.door_at(r.get_center())
	check("minimap: the lock of %s can be hit where it is drawn" % key, hit == key or hit == key.split("|")[1] + "|" + key.split("|")[0])
	mm.door_clicked.emit(hit if hit != "" else key)
	await frames(2)


func test_locks() -> void:
	await spawn()
	var mm = pda._mini_map
	check("before: AIR LOCK has no name on the map, STBD HOLD neither, no RESTRICTED stamp",
		pda._map_room_label("airlock") == "UNCHARTED COMPARTMENT" and pda._map_room_label("stbd_hold") == "UNCHARTED COMPARTMENT"
		and not pda.map_room_restricted("stbd_hold"))
	# no card: exact message, error sound state, no label reveal
	await click_lock("ready_room|airlock")
	check("airlock lock, no card: exactly \"Requires Airlock Keycard\" (banner + error line), door still locked, no label",
		pda.map_last_error == "Requires Airlock Keycard" and pda._mini_banner.text == "Requires Airlock Keycard" and pda._mini_banner.visible
		and pda.map_door_between("ready_room", "airlock")["state"] == "locked" and pda._map_room_label("airlock") == "UNCHARTED COMPARTMENT"
		and not mm.unlocking("ready_room|airlock"))
	# restricted side: click reveals the label
	await click_lock("ready_room|stbd_hold")
	check("restricted lock click: \"Requires Restricted Keycard\" + RESTRICTED stamp appears now",
		pda.map_last_error == "Requires Restricted Keycard" and pda.map_room_restricted("stbd_hold")
		and mm.room_restricted("stbd_hold") and mm.stamp_age("stbd_hold") < 1.5
		and pda.map_door_between("ready_room", "stbd_hold")["state"] == "locked" and pda.vessel_map["rooms"]["stbd_hold"]["state"] == "unexplored")
	pda.give_item(&"airlock_keycard")
	await click_lock("ready_room|airlock")
	var key := "ready_room|airlock"
	check("with the card: lock animates (unlocking), door open, flag persisted, label AIR LOCK revealed",
		mm.unlocking(key) and pda.map_door_between("ready_room", "airlock")["state"] == "open" and pda.has_flag("door_open_ready_room_airlock")
		and pda._map_room_label("airlock") == "AIR LOCK" and pda.map_last_error == "Requires Restricted Keycard")
	await wait_s(1.0)
	check("animation ends: lock gone, open doorway drawn", not mm.unlocking(key) and mm.unlock_age(key) >= mm.UNLOCK_TIME)
	var carried: Dictionary = {"flags": pda.flags.duplicate(true), "vars": pda.vars.duplicate(true), "inventory": Array(pda.inventory),
		"map": pda.vessel_map.duplicate(true), "o2": 100.0}
	await drop_scene()
	PdaScreen.carry = carried   # what change_scene hands to the next scene
	await spawn()
	check("carried to the next scene: door stays open, AIR LOCK named, RESTRICTED stays",
		pda.map_door_between("ready_room", "airlock")["state"] == "open" and pda._map_room_label("airlock") == "AIR LOCK"
		and pda.map_room_restricted("stbd_hold"))
	await drop_scene()
	# state is saved in game state: a scene with the flag set shows the door open
	await spawn()
	pda.flags["door_open_ready_room_airlock"] = true
	pda.flags["room_revealed_airlock"] = true
	pda.enter_screen(2)
	await frames(3)
	check("persisted: re-entering the screen keeps the airlock door open and named",
		pda.map_door_between("ready_room", "airlock")["state"] == "open" and pda._map_room_label("airlock") == "AIR LOCK")
	await drop_scene()


func test_suit() -> void:
	await spawn()
	await take_from_locker("suit")
	check("suit taken: 1 hr (8 -> 7)", pda.inventory.has(&"suit") and pda.time_blocks == 7)
	pda.show_inv()
	await frames(2)
	var chr = pda.windows.character
	var before: Color = figure_col(chr)
	chr.select_id("suit")
	await frames(2)
	var labels: Array = []
	for b: Button in chr.action_buttons:
		labels.append(b.text)
	check("selecting SUIT offers Put on (1 hr) and Drop", labels.size() == 2 and str(labels[0]) == "Put on (1 hr)"
		and str(labels[1]) == "Drop")
	chr.action_buttons[0].pressed.emit()
	await frames(2)
	check("Put on? prompt first (nothing spent yet) with the 1 hr cost and a cancel", chr.confirm_text != "" and chr.confirm_text == "Put on? (1 hr)"
		and pda.time_blocks == 7 and pda.inventory.has(&"suit") and chr.action_buttons.size() == 2 and chr.action_buttons[1].text == "CANCEL")
	chr.action_buttons[1].pressed.emit()   # cancel
	await frames(2)
	check("cancel: nothing happens", pda.time_blocks == 7 and pda.inventory.has(&"suit") and not pda.suit_is_worn() and chr.confirm_text == "")
	chr.select_id("suit")
	chr.action_buttons[0].pressed.emit()
	await frames(2)
	chr.action_buttons[0].pressed.emit()   # confirm
	await frames(2)
	check("confirmed: 1 hr spent (7 -> 6), the screen fades out", pda.time_blocks == 6 and pda.suit_fade_busy() and pda._suit_fade.visible)
	await wait_s(PdaScreen.SUIT_FADE_IN + 0.12)
	check("when dark: suit left the inventory, suit_worn true", not pda.inventory.has(&"suit") and pda.suit_is_worn()
		and pda.flags.get("suit_worn", false) and pda._suit_fade.color.a > 0.9)
	await wait_s(PdaScreen.SUIT_FADE_HOLD + PdaScreen.SUIT_FADE_OUT + 0.25)
	check("fade ends and input is released", not pda.suit_fade_busy() and not pda._suit_fade.visible)
	var after: Color = figure_col(chr)
	check("figure turns from black to a green shade (placeholder art)", before.v < 0.15 and after.g > after.r + 0.1 and after.g > after.b
		and chr.suit_worn and chr.filled_ids().is_empty())
	check("the zipper sound exists", ResourceLoader.exists("res://assets/sounds/zipper.wav") and ResourceLoader.exists("res://assets/sounds/error.wav")
		and ResourceLoader.exists("res://assets/sounds/unlock.wav"))
	check("the worn suit cannot be dropped and the container shows it as taken", not pda.drop_item(&"suit") and pda.item_ever_taken("suit"))
	await drop_scene()


func test_airlock_warning() -> void:
	await spawn()
	pda.flags["door_open_ready_room_airlock"] = true
	pda.map_set_door_state("ready_room|airlock", "open")
	pda.give_item(&"airlock_keycard")
	pda._refresh_maps()
	await frames(2)
	var key: String = pda.exit_door_key()
	check("the exit is the airlock door; it reacts to clicks once open", key == "ready_room|airlock" and pda._map_click_doors().has(key))
	var scene_before: String = str(pda.scene_file_path)
	pda._mini_map.door_clicked.emit(key)
	await frames(2)
	check("not suited: warning with exact text, Yes / No",
		pda.confirm_box != null and pda.confirm_box.visible and pda.confirm_box.text_label.text == pda.UNSUITED_WARNING
		and pda.UNSUITED_WARNING == "Warning: Going on Excursion without a suit is inadvisable. Do you wish to proceed anyway?"
		and pda.confirm_box.yes_button.text.to_upper() == "YES" and pda.confirm_box.no_button.text.to_upper() == "NO")
	pda.confirm_box.no_button.pressed.emit()
	await frames(2)
	check("No: stays, no flag", not pda.confirm_box.visible and pda.screen_index == 2 and not pda.has_flag("went_without_suit")
		and str(pda.scene_file_path) == scene_before)
	pda._mini_map.door_clicked.emit(key)
	await frames(2)
	pda.confirm_box.yes_button.pressed.emit()
	await frames(2)
	check("Yes: went_without_suit recorded, suit_worn false, the scene moves on (its normal ending)",
		pda.has_flag("went_without_suit") and not pda.suit_is_worn() and not bool(pda.vars.get("suit_worn", false)) and left())
	await drop_scene()
	# suited: no warning
	await spawn()
	pda.map_set_door_state("ready_room|airlock", "open")
	pda.vars["suit_worn"] = true
	pda._mini_map.door_clicked.emit("ready_room|airlock")
	await frames(2)
	check("suited: no warning, goes straight on, no went_without_suit", (pda.confirm_box == null or not pda.confirm_box.visible)
		and not pda.has_flag("went_without_suit") and left())
	await drop_scene()


func test_drop() -> void:
	await spawn()
	var mm = pda._mini_map
	for id in [&"airlock_keycard", &"lantern", &"suit"]:
		pda.give_item(id)
	pda.show_inv()
	await frames(2)
	var chr = pda.windows.character
	chr.select_id("lantern")
	var labels: Array = []
	for b: Button in chr.action_buttons:
		labels.append(b.text)
	check("every item offers Drop (the suit also Put on)", labels == ["Drop"])
	chr.action_buttons[0].pressed.emit()
	await frames(2)
	check("Drop: out of inventory, free (no hours), a green LANTERN box on the map in the ready room",
		not pda.inventory.has(&"lantern") and pda.time_blocks == 8 and pda.dropped_in("ready_room").size() == 1
		and mm.markers().any(func(m: Dictionary) -> bool: return str(m["kind"]) == "drop" and str(m["label"]) == "LANTERN"))
	# click the dropped box to pick it up
	var id := ""
	for m: Dictionary in mm.markers():
		if str(m["kind"]) == "drop":
			id = str(m["id"])
	pda.windows.close_all(true)
	await frames(2)
	var rc: Rect2 = mm.marker_rect_local(id)
	check("the dropped box is hit-testable", id != "" and mm.marker_at(rc.get_center()) == id)
	mm.marker_clicked.emit(id)
	await frames(2)
	check("click: picked up, free, gone from the map", pda.inventory.has(&"lantern") and pda.time_blocks == 8 and pda.dropped_in("ready_room").is_empty()
		and not mm.markers().any(func(m: Dictionary) -> bool: return str(m["kind"]) == "drop"))
	# many items: no overlaps, not onto LOCKER / COFFEE POT
	for n in 9:
		var iid := StringName("junk%d" % n)
		pda.items[iid] = {"label": "JUNK %d" % n, "desc": "x"}
		pda.give_item(iid)
		pda.drop_item(iid)
	pda.drop_item(&"lantern")
	pda.drop_item(&"airlock_keycard")
	await frames(2)
	var rects: Array = []
	var fixed: Array = []
	var shown := 0
	var piles := 0
	for m: Dictionary in mm.markers():
		var r: Rect2 = mm.marker_rect_local(str(m["id"]))
		if str(m["kind"]) == "act":
			fixed.append(r)
		else:
			rects.append(r)
			if str(m["kind"]) == "pile":
				piles += 1
			else:
				shown += 1
	var clean := true
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			clean = clean and not (rects[i] as Rect2).intersects(rects[j])
		for f: Rect2 in fixed:
			clean = clean and not (rects[i] as Rect2).intersects(f)
	check("11 dropped items: shown in a row, no overlaps, nothing on LOCKER / COFFEE POT, the rest in a PILE (%d shown, %d pile)" % [shown, piles],
		clean and fixed.size() == 2 and piles == 1 and shown == PdaScreen.DROP_SLOTS - 1 and pda.dropped_in("ready_room").size() == 11)
	var pile_id := ""
	for m: Dictionary in mm.markers():
		if str(m["kind"]) == "pile":
			pile_id = str(m["id"])
	mm.marker_clicked.emit(pile_id)
	await frames(2)
	check("PILE opens a FLOOR window listing all of them, pick-ups free", pda.windows.container_open()
		and pda.windows.container.title_label.text == "FLOOR" and pda.windows.container.items.size() == 11)
	var c = pda.windows.container
	c.select_id(str(c.items[0]["id"]))
	c.action_buttons[0].pressed.emit()
	await frames(2)
	check("pick up from the floor window: free, inventory grows, 10 left", pda.time_blocks == 8 and pda.inventory.size() == 2 and pda.dropped_in("ready_room").size() == 10)
	pda.windows.close_all(true)
	var saved: Dictionary = (pda.vars["dropped"] as Dictionary).duplicate(true)
	check("dropped items are in game state per room (vars.dropped.ready_room)", saved.has("ready_room") and (saved["ready_room"] as Array).size() == 10)
	await drop_scene()


func test_hud_and_hours() -> void:
	await spawn()
	await frames(3)
	var o2h: float = pda.o2_bar.custom_minimum_size.y
	var th: float = pda.time_box.custom_minimum_size.y
	var cell_h: float = (pda.time_bar.get_child(0) as Control).custom_minimum_size.y
	check("HUD: O2 bar and HRS blocks are the same height (%.0f vs %.0f), same bar thickness (%.0f)" % [o2h, th, cell_h],
		o2h == th and cell_h == O2Bar.BAR_H and O2Bar.BAR_H < O2Bar.TOTAL_H)
	check("HUD: HRS label sits BENEATH the blocks, O2 labels beneath their bar",
		pda.time_caption.global_position.y >= pda.time_bar.global_position.y + pda.time_bar.size.y - 0.5
		and pda.time_caption.text == "HRS" and O2Bar.TOTAL_H - O2Bar.BAR_H >= 12.0 and pda.o2_bar.size.y >= O2Bar.TOTAL_H - 0.5)
	check("HUD: 8 blocks, count under them", pda.time_bar.get_child_count() == 8 and pda.time_count_label.text == "8/8")
	# every cost spends; refusal when too little; 0 left
	check("spending API unchanged: spend_time_blocks(1) works once live", pda.time_blocks_live and pda.spend_time_blocks(1) and pda.time_blocks == 7)
	pda.time_blocks = 1
	check("1 left: a 2 hr cost is refused with a message, nothing spent", pda.hours_refusal(2) == "NOT ENOUGH HOURS: 1 LEFT"
		and not pda.spend_time_blocks(2) and pda.time_blocks == 1)
	pda.stage.open_act("locker")
	await frames(2)
	var cont = pda.windows.container
	cont.select_id("suit")
	cont.action_buttons[0].pressed.emit()
	await frames(2)
	check("take with 1 left: allowed, 0 left", pda.inventory.has(&"suit") and pda.time_blocks == 0 and pda.time_count_label.text == "0/8")
	cont.select_id("lantern")
	cont.action_buttons[0].pressed.emit()
	await frames(2)
	check("take with 0 left: refused with \"NO HOURS LEFT\" in the window, item stays, never below zero", not pda.inventory.has(&"lantern")
		and pda.time_blocks == 0 and pda.hours_refusal(1) == "NO HOURS LEFT" and pda.windows.container.notice_label.text == "NO HOURS LEFT"
		and cont.slot_for("lantern") != null)
	pda.windows.close_all(true)
	await frames(2)
	pda.show_inv()
	await frames(2)
	pda.windows.character.select_id("suit")
	pda.windows.character.action_buttons[0].pressed.emit()
	await frames(2)
	pda.windows.character.action_buttons[0].pressed.emit()
	await frames(2)
	check("Put on with 0 left: refused, suit stays in the inventory, not worn", pda.inventory.has(&"suit") and not pda.suit_is_worn()
		and not pda.suit_fade_busy())
	pda.time_blocks_live = false
	check("not live (other scenes): costs are never refused", pda.hours_refusal(5) == "")
	await drop_scene()
	# the ready room arms them from any state
	await spawn()
	pda.time_blocks = 3
	pda.time_blocks_live = false
	pda.enter_screen(2)
	await frames(2)
	check("entering the ready room arms the 8 blocks", pda.time_blocks_live and pda.time_blocks == 8)
	await drop_scene()


func test_coffee() -> void:
	await spawn()
	var mm = pda._mini_map
	check("COFFEE POT + LOCKER are markers inside the ready room on the map", mm.find_marker("coffee").get("label", "") == "COFFEE POT"
		and mm.find_marker("locker").get("label", "") == "LOCKER" and not mm.marker_rect_local("coffee").intersects(mm.marker_rect_local("locker")))
	mm.marker_clicked.emit("coffee")
	await frames(2)
	var st = pda.windows.station
	check("the COFFEE POT marker opens its own window with the only option Brew a Pot (1 hr) + EXIT (same window type, animates)",
		pda.windows.station_is_open() and st.title_label.text == "COFFEE POT" and st.option_buttons.size() == 1
		and st.option_buttons[0].text == "Brew a Pot (1 hr)" and st.exit_button.text.to_upper().contains("EXIT") and st.picture != null
		and st is HoloWindowScript)
	st.option_buttons[0].pressed.emit()
	await frames(2)
	var c: Dictionary = pda.coffee_state()
	check("brew: 1 hr spent (8 -> 7), a pot exists, counters brews 1 / drinks 0, option is now Drink coffee? (1 hr)", pda.time_blocks == 7
		and c["pot"] and c["brews"] == 1 and c["drinks"] == 0 and st.option_buttons.size() == 1 and st.option_buttons[0].text == "Drink coffee? (1 hr)")
	st.option_buttons[0].pressed.emit()
	await frames(2)
	st.option_buttons[0].pressed.emit()
	await frames(2)
	check("drink twice: 2 more hrs (7 -> 5), still offered (infinite pot), drinks 2, no new brew offered", pda.time_blocks == 5 and c["drinks"] == 2
		and c["brews"] == 1 and st.option_buttons[0].text == "Drink coffee? (1 hr)" and not pda.coffee_option("brew") and pda.time_blocks == 5)
	check("counters live in game state (vars.coffee) and flags", pda.vars["coffee"]["drinks"] == 2 and pda.has_flag("coffee_brewed") and pda.has_flag("coffee_drunk"))
	pda.coffee_set_disabled(true)
	await frames(2)
	check("disabled state (later pass): no options, MACHINE DISABLED, drinking refused and free", st.option_buttons.is_empty()
		and pda.coffee_provider()["disabled"] and not pda.coffee_option("drink") and pda.time_blocks == 5)
	pda.coffee_set_disabled(false)
	pda.time_blocks = 0
	await frames(2)
	st.option_buttons[0].pressed.emit()
	await frames(2)
	check("drink with 0 left: refused, \"NO HOURS LEFT\" notice, drinks unchanged", pda.time_blocks == 0 and c["drinks"] == 2
		and st.notice_label.text == "NO HOURS LEFT")
	pda.windows.close_all(true)
	await drop_scene()
	# the green links in the text open the same windows
	await spawn()
	pda.stage.open_act("coffee")
	await frames(2)
	check("the COFFEE POT text link opens the same station window", pda.windows.station_is_open())
	await drop_scene()


func test_tutorial() -> void:
	PdaScreen.tutorials_enabled = true
	pda = (load(SCENE) as PackedScene).instantiate()
	root.add_child(pda)
	current_scene = pda
	await frames(3)
	pda.enter_screen(2)
	await frames(2)
	pda.stage.skip_typing(true)
	await wait_s(0.3)
	var steps: Array = pda.TUTORIALS["items"]
	check("tutorial: starts by itself after the ready room text (first time), %d steps" % steps.size(),
		pda.guide_phase == "tip" and pda.guide_tour.visible and pda.guide_step == 0 and steps.size() >= 8)
	var all := ""
	var hotkey := RegEx.create_from_string("\\bTAB\\b|\\bC\\b|\\bI\\b|HOTKEY|PRESS")
	var ok_hint := true
	for s: Dictionary in steps:
		all += str(s["text"]) + " "
		ok_hint = ok_hint and hotkey.search(str(s["text"]).to_upper().replace("(1 HR)", "")) == null
	check("tutorial: covers locker, taking, character sheet, hours, time bar, suit, drop and map locks; no hotkeys named",
		ok_hint and all.contains("LOCKER") and all.contains("TAKE") and all.contains("character sheet") and all.contains("hours")
		and all.contains("SUIT") and all.to_lower().contains("dropped") and all.to_lower().contains("padlock") and not all.contains("TAB"))
	var seen := {}
	var visited_targets := true
	for n in steps.size():
		var tip: Dictionary = steps[n]
		seen[str(tip["target"])] = true
		check("tutorial step %d/%d shows its text, highlights %s (%s)" % [n + 1, steps.size(), tip["target"], str(tip["text"]).substr(0, 28)],
			pda.guide_step == n and pda.guide_tour.visible and pda.guide_tour.has_method("show_step"))
		if str(tip["target"]) in ["container", "container_actions"]:
			visited_targets = visited_targets and pda.windows.container_open()
		if str(tip["target"]) == "character":
			visited_targets = visited_targets and pda.windows.character_open()
		await frames(2)
		var r: Rect2 = pda._guide_rect(str(tip["target"]))
		visited_targets = visited_targets and (r.size.x > 4.0 or str(tip["target"]) == "lock")
		pda.guide_next()
		await frames(3)
	check("tutorial: each step's target had a real rectangle, windows opened when explained", visited_targets and seen.has("time") and seen.has("markers"))
	check("tutorial: finished — hidden, windows closed, flag set so it never repeats", pda.guide_phase == "" and not pda.guide_tour.visible
		and not pda.windows.any_open() and pda.has_flag("tut_items_done") and pda.inventory.is_empty())
	pda.enter_screen(2)
	pda.stage.skip_typing(true)
	await wait_s(0.2)
	check("tutorial: not shown again on the second visit", pda.guide_phase == "")
	pda.queue_free()
	await frames(2)
	PdaScreen.tutorials_enabled = false


func test_intro_hud() -> void:
	var intro = (load("res://scenes/intro.tscn") as PackedScene).instantiate()
	root.add_child(intro)
	current_scene = intro
	await frames(6)
	var h: float = intro.hud_o2.size.y
	check("intro: the HUD O2 bar uses the new height (%.0f) and is inside the screen" % h, h >= O2Bar.TOTAL_H - 0.5
		and intro.hud_o2.get_global_rect().position.y >= 0.0 and intro.hud_o2.get_global_rect().end.y <= intro.get_viewport_rect().size.y)
	intro.queue_free()
	await frames(2)
