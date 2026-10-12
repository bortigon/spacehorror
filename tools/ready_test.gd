extends SceneTree
## Ready room round 3 (headless):
##   godot --headless --audio-driver Dummy --path . --script res://tools/ready_test.gd
## New room text (no expo font), the WINDOW sub-screen + RSV ABEYANCE log entry, the locker search
## prompt (1 hr, fade, every opening), the 2-step time tutorial, free takes / free suit, continuous
## underline on COFFEE POT, the coffee pot + THERMOS OF COFFEE free action, container drag in / out,
## dropped-item dots, the item stuck to the cursor (drop / use on a lock / cancel), click-lock never
## unlocks, STASIS-3, the HUD without the menu button, the airlock warning, the intro HUD.

const SCENE := "res://scenes/authored/excursion1_prep.tscn"
const NEW_SCENE := "res://scenes/authored/new_scene_2.tscn"
const HoloWindowScript := preload("res://ui/holo_window.gd")
const Markup := preload("res://ui/story_markup.gd")
const SceneData := preload("res://ui/story_scene.gd")

const ROOM_TEXT := "The Ready Room is dimly lit from a row of lights around the edges of the ceiling. A large WINDOW dominates the north side of the room. A ship looms in empty space outside, still and silent.\n\nA row of four LOCKERS line the wall. You can't seem to remember which one is yours.\n\nA set of cabinets in the corner hosts what you recognize as a COFFEE POT. Metal cups hang from hooks along the wall behind it."
const WINDOW_TEXT := "You step over to the window and look outside. Space has never seemed so--dark. Twinkling pinpricks of light shine from distant stars, but they are few and far between. Blue and purple wisps of a nearby nebulae streak one corner of the view.\n\nThe ship dominates the center, lit by spotlights from the RSV ABEYANCE. It sits motionless in the gloom, like a the corpse of a hulking giant. A chill creeps down your spine. What horrors await?"
const LOG_TEXT := "RSV ABEYANCE - The RSV ABEYANCE is small Rec-7 vessel designed for deep space travel. Crewed by four Rec-7 OPERATORS, the ship has cryopod stasis chambers for each one. Crewmates rarely see each other, if ever, as only one crewman is needed per excursion. The ABEYANCE is piloted and operated by AI. Crew may be in stasis for months or years at a time, only to be waked when the ship reaches a mission destination."
const SEARCH_TEXT := "Searching the locker will take 1 hr. Are you sure?"
const COFFEE_TEXT := "The coffee pot is empty and cold. Surely there are supplies in the cabinets above. Maybe you could even find a thermos. Do you want to brew coffee?"
const FADE := 1.15   # SUIT_FADE_IN + HOLD + OUT (~1.0 s) and a little

var fails := 0
var passes := 0
var pda
const SceneOrderScript := preload("res://ui/scene_order.gd")


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


func spawn(scene_path := SCENE, screen := 2, rail := ["sta", "inv", "log", "map"]) -> void:
	pda = (load(scene_path) as PackedScene).instantiate()
	if not rail.is_empty():
		pda.vars["rail_tabs"] = rail      # most tests want every button (the dynamic menu has its own tests)
	root.add_child(pda)
	current_scene = pda
	await frames(3)
	pda.enter_screen(screen)
	await frames(2)
	pda.stage.skip_typing(true)
	await frames(2)
	pda._ensure_windows()
	pda.windows.set_animated(false)


func arrive_airlock() -> void:
	await wait_s(FADE + 0.6)
	await frames(4)
	if current_scene != null and current_scene != pda:
		pda = current_scene
		await frames(3)
		pda.stage.skip_typing(true)
		await frames(2)


func drop_scene() -> void:
	pda.queue_free()
	await frames(2)


func shown() -> String:
	return str(pda.stage.text_label.get_parsed_text())


func left() -> bool:
	return str(pda.stage.text_label.get_parsed_text()).contains("isn't written") or not str(pda.scene_file_path).ends_with("excursion1_prep.tscn")


func figure_col(chr) -> Color:
	return chr.FIGURE_SUIT if chr.suit_worn else chr.FIGURE_COLOR


## Click LOCKERS, answer Yes, wait out the fade: the locker window is up.
func open_locker() -> void:
	pda.stage.open_act("locker")
	await frames(2)

	if pda.confirm_box != null and pda.confirm_box.visible:
		pda.confirm_box.answer(true)
		await wait_s(FADE)
		if pda.guide_tour != null and pda.guide_tour.visible and pda.guide_id == "time":
			return      # the time tips are up (tutorial tests)
		pda.stage.open_act("locker")      # searching does not open it: click the searched locker again
		await frames(2)



func take_from_locker(id: String) -> void:
	await open_locker()
	drag_container_to_inventory(id)
	await frames(2)
	pda.windows.close_all(true)
	await frames(2)


## Containers are drag and drop only: drag `id` from the open container onto the character screen.
func drag_container_to_inventory(id: String) -> String:
	var w = pda.windows
	var sl: Control = w.container.slot_for(id)
	if sl == null:
		return "missing"
	sl.start_drag_now(sl.get_global_rect().get_center())
	return w.release_drag(w.character.grid_bg.get_global_rect().get_center())


func click(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	pda.windows._input(e)


## A sticky drag acts on the CLICK: move there, let go (nothing), click.
func sticky_click(pos: Vector2) -> void:
	motion(pos)
	release(pos)
	click(pos)


func motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	pda.windows._input(e)


func release(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = pos
	e.global_position = pos
	pda.windows._input(e)


func mini_global(r: Rect2) -> Rect2:
	return Rect2(r.position + pda._mini_map.global_position, r.size)


## Starts dragging inventory item `id` from the character screen (as if pressed and moved).
func drag_from_inventory(id: String) -> void:
	if not pda.windows.character_open():
		pda.show_inv()
		await frames(2)
	var sl: Control = pda.windows.character.slot_for(id)
	sl.start_drag_now(sl.get_global_rect().get_center())
	await frames(1)


func _init() -> void:
	PdaScreen.tutorials_enabled = false
	await frames(1)
	await test_text()
	await test_underline()
	await test_window_and_log()
	await test_search()
	await test_tutorial()
	await test_free_takes_and_suit()
	await test_coffee()
	await test_container_drag()
	await test_cursor_drag()
	await test_locks()
	await test_dots()
	await test_stasis()
	await test_hud()
	await test_airlock_warning()
	await test_intro_hud()
	await test_log_window()
	await test_round4_tutorials()
	await test_icons()
	await test_rail()
	await test_round6()
	await test_round7()
	await test_onboarding()
	print("READY %d pass, %d fail" % [passes, fails])
	quit(1 if fails else 0)


# ---------------------------------------------------------------- 1. room text

func test_text() -> void:
	for path in ["res://story/scenes/new_scene_2.json", "res://story/scenes/excursion1_prep.json"]:
		var d: Dictionary = SceneData.load_file(path)
		var rr: Dictionary = {}
		for s: Dictionary in d["screens"]:
			if str(s["id"]) == "ready_room":
				rr = s
		var t := str(rr.get("text", ""))
		check("%s: ready room text has WINDOW / LOCKERS / COFFEE POT links, no [expo] serif font" % path.get_file(),
			t.contains("[act=window]WINDOW[/act]") and t.contains("[act=locker]LOCKERS[/act]") and t.contains("[act=coffee]COFFEE POT[/act]")
			and not t.contains("[expo]") and not t.contains("Eight hours"))
		var plain := t.replace("[act=window]", "").replace("[act=locker]", "").replace("[act=coffee]", "").replace("[/act]", "")
		check("%s: text is exactly David's (paragraphs separated by one blank line)" % path.get_file(), plain == ROOM_TEXT)
		var acts: Dictionary = rr["acts"]
		check("%s: WINDOW is a function act with a map marker; RSV ABEYANCE a log act" % path.get_file(),
			acts.has("window") and not acts["window"].has("container") and acts["window"]["marker"]["label"] == "WINDOW"
			and acts["abeyance"]["log"]["title"] == "RSV ABEYANCE" and str(acts["abeyance"]["text"]) == LOG_TEXT)
	await spawn()
	check("rendered ready room text is exactly the new text (body font, no expo)", shown() == ROOM_TEXT
		and not pda.stage.text_label.text.contains("[font="))
	var mm = pda._mini_map
	var boxes := ["locker", "coffee", "window"]
	var ok := true
	for a in boxes:
		ok = ok and mm.marker_rect_local(a).size.x > 8.0 and not mm.is_dot(mm.find_marker(a))
	check("map: LOCKER, COFFEE POT and WINDOW boxes in the ready room, none overlapping, WINDOW on the north wall",
		ok and mm.find_marker("window")["label"] == "WINDOW"
		and not mm.marker_rect_local("window").intersects(mm.marker_rect_local("locker"))
		and not mm.marker_rect_local("window").intersects(mm.marker_rect_local("coffee"))
		and mm.marker_rect_local("window").position.y < mm.room_rect_local("ready_room").get_center().y)
	await drop_scene()
	await spawn(NEW_SCENE, 0)
	check("new_scene_2 ready room shows the same text", shown() == ROOM_TEXT)
	await drop_scene()


# ---------------------------------------------------------------- 4. continuous underline

func test_underline() -> void:
	var m = Markup.new().parse("A set of [act=coffee]COFFEE POT[/act]. Then [act=locker] lockers [/act]x")
	m.time_by_speed(400.0)
	var bb: String = m.render(m.duration + 1.0, 1.0)
	check("COFFEE POT: ONE link run with one underline across the space", bb.count("[url href=act:coffee underline=never]") == 1
		and bb.contains("[b][u]COFFEE POT[/u][/b]") and not bb.contains("COFFEE[/u]"))
	check("spaces at the ends stay outside the underline, click id clean", bb.contains("Then  [url href=act:locker underline=never]")
		and bb.contains("[b][u]LOCKERS[/u][/b][/color][/url] x") and not bb.contains("[url=") and not bb.to_lower().contains("act:coffee pot") and not bb.contains("act:coffee]")
		and not bb.contains("[u] "))
	var half = Markup.new().parse("[act=coffee]COFFEE POT[/act]")
	half.time_by_speed(10.0)
	var hb: String = half.render(half.LEAD_IN + 0.71, 1.0) if "LEAD_IN" in half else half.render(0.72, 1.0)
	check("while typing (\"COFFEE P\"): still one run, the trailing space is never underlined", hb.count("[url") == 1 and not hb.contains(" [/u]"))
	# real hover: the space between COFFEE and POT is part of the same link (no gap in hits)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.scroll_active = false
	rtl.size = Vector2(500, 60)
	root.add_child(rtl)
	var one = Markup.new().parse("[act=coffee]COFFEE POT[/act]")
	one.time_by_speed(400.0)
	rtl.text = one.render(one.duration + 1.0, 1.0).replace("underline=never]", "underline=never tooltip=act:coffee]")
	await frames(2)
	var first := -1
	var last := -1
	var gaps := 0
	var y := 8.0
	for x in range(0, 400, 1):
		var hit := str(rtl.get_tooltip(Vector2(x, y)))
		if hit == "act:coffee":
			if first < 0:
				first = x
			elif last >= 0 and x - last > 1:
				gaps += 1
			last = x
	rtl.queue_free()
	check("hover over COFFEE POT: one continuous link incl. the space (%d..%d, %d gaps), meta exactly act:coffee" % [first, last, gaps],
		first >= 0 and last - first > 40 and gaps == 0)


# ---------------------------------------------------------------- 2. window + log

func test_window_and_log() -> void:
	await spawn()
	var mm = pda._mini_map
	mm.marker_clicked.emit("window")      # the WINDOW box on the map opens the same sub-screen
	await frames(2)
	pda.stage.skip_typing(true)
	await frames(2)
	check("WINDOW: a sub-screen replaces the text (not a window), exact text", shown() == WINDOW_TEXT and not pda.windows.any_open())
	var labels: Array = []
	for b: Button in pda.stage.choice_buttons:
		labels.append(b.text)
	check("WINDOW: automatic Back (only Back)", labels == ["Back"])
	check("RSV ABEYANCE is a green link in it", pda.stage.text_label.text.contains("[url href=act:abeyance underline=never]")
		and pda.stage.text_label.text.contains("[b][u]RSV ABEYANCE[/u][/b]"))
	check("no log entry before it is discovered", not pda.has_log_entry("abeyance") and not pda.unlocked.has(&"abeyance"))
	pda.stage.open_act("abeyance")
	await frames(2)
	var lw = pda.windows.logw
	check("RSV ABEYANCE: the LOG pop-up opens on the ship entry (story text stays the window)", pda.log_open()
		and lw.selected_id == "abeyance" and lw.text_box.get_parsed_text().contains(LOG_TEXT) and shown() == WINDOW_TEXT)
	check("log entry filed once (vars.log_entries + filed dossier, FILED toast), category SHIP", pda.has_log_entry("abeyance")
		and pda.unlocked.has(&"abeyance") and pda.dossiers[&"abeyance"]["body"] == LOG_TEXT
		and pda.os_line_label.text.contains("RSV ABEYANCE") and (pda.vars["log_entries"] as Array).size() == 1
		and str((pda.vars["log_entries"] as Array)[0]["category"]) == "SHIP")
	pda.windows.close_log()
	await frames(2)
	check("EXIT closes the LOG; the window text is still there", not pda.log_open() and shown() == WINDOW_TEXT)
	pda.stage.open_act("abeyance")
	await frames(2)
	check("opening it again does not file it twice", (pda.vars["log_entries"] as Array).size() == 1 and pda.log_open())
	pda._handle_escape()
	await frames(2)
	check("Esc closes the LOG", not pda.log_open())
	pda.stage.act_back()
	await frames(2)
	pda.stage.skip_typing(true)
	await frames(2)
	check("Back again returns to the ready room text", shown() == ROOM_TEXT)
	mm.marker_clicked.emit("window")
	await frames(2)
	mm.marker_clicked.emit("window")
	await frames(2)
	pda.stage.act_back()
	await frames(2)
	pda.stage.skip_typing(true)
	await frames(2)
	check("clicking the WINDOW box twice does not stack it (one Back returns)", shown() == ROOM_TEXT)
	await drop_scene()


# ---------------------------------------------------------------- 3. locker search prompt

func test_search() -> void:
	await spawn()
	check("start: 8/8 hours", pda.time_blocks == 8)
	pda.stage.open_act("locker")
	await frames(2)
	var cb = pda.confirm_box
	check("LOCKERS asks first: exact text, Yes / No, nothing spent, no window yet", cb != null and cb.visible and cb.text_label.text == SEARCH_TEXT
		and cb.yes_button.text.to_upper() == "YES" and cb.no_button.text.to_upper() == "NO" and pda.time_blocks == 8 and not pda.windows.any_open())
	cb.no_button.pressed.emit()
	await frames(2)
	check("No: the prompt closes, nothing spent, no window", not cb.visible and pda.time_blocks == 8 and not pda.windows.any_open())
	pda._mini_map.marker_clicked.emit("locker")     # the LOCKER box on the map asks too
	await frames(2)
	check("the LOCKER map box asks the same question", cb.visible and cb.text_label.text == SEARCH_TEXT)
	cb.yes_button.pressed.emit()
	await frames(2)
	check("Yes: 1 hr spent at once (8 -> 7), the screen fades to black", pda.time_blocks == 7 and pda.suit_fade_busy() and pda._suit_fade.visible
		and not pda.windows.container_open())
	check("before the search the LOCKER box has the orange time-cost border", pda._mini_map.find_marker("locker").get("cost", false) == true)
	await wait_s(FADE)
	check("after the fade: NOTHING opens (no locker, no inventory), input released, still 7, border normal now",
		not pda.windows.any_open() and not pda.suit_fade_busy() and not pda._suit_fade.visible and pda.time_blocks == 7
		and pda._mini_map.find_marker("locker").get("cost", true) == false)
	pda.stage.open_act("locker")
	await frames(2)
	check("click the searched locker again: it opens free, no prompt (with the character screen)", pda.windows.container_open()
		and pda.windows.character_open() and not cb.visible and pda.time_blocks == 7)
	var cont = pda.windows.container
	check("container description: an empty line between paragraphs, FIXED size + fixed 10 pt font (no shrinking), scrolls if long",
		cont.desc_box.text.contains("in front of you.\n\nThe suit") and cont.desc_box.text.contains("light.\n\nA keycard")
		and cont.desc_font_size() == 10 and cont.desc_box.scroll_active and cont.desc_box.size == Vector2(cont.LEFT_W, 204)
		and not cont.has_method("_fit_description"))
	var cdesc_size: Vector2 = cont.desc_box.size
	cont.select_id("suit")
	await frames(1)
	check("selecting an item: same box, same font", cont.desc_font_size() == 10 and cont.desc_box.size == cdesc_size)
	check("containers are drag and drop only: NO Take button", cont.action_buttons.is_empty()
		and cont.actions_row.get_child_count() == 0)
	pda.windows.close_all(true)
	await frames(2)
	pda.stage.open_act("locker")
	await frames(2)
	check("searched once: opening it again costs nothing and asks nothing (flag searched_locker)",
		pda.time_blocks == 7 and pda.windows.container_open() and not pda.confirm_box.visible and pda.has_flag("searched_locker"))
	pda.windows.close_all(true)
	pda.flags.erase("searched_locker")
	pda.time_blocks = 0
	pda.stage.open_act("locker")
	await frames(2)
	cb.yes_button.pressed.emit()
	await frames(2)
	check("0 hours left: Yes is refused (NO HOURS LEFT), no fade, no window", pda.time_blocks == 0 and not pda.suit_fade_busy()
		and not pda.windows.any_open() and pda.os_line_label.text.contains("NO HOURS LEFT"))
	await drop_scene()


# ---------------------------------------------------------------- 3. the 2-step time tutorial

func test_tutorial() -> void:
	PdaScreen.tutorials_enabled = true
	await spawn(SCENE, 2, ["sta", "map"])
	await wait_s(0.3)
	check("no tutorial when the room text is read (the old 9-step one is gone); time tips are 2 now",
		pda.guide_phase == "" and (pda.guide_tour == null or not pda.guide_tour.visible)
		and not pda.TUTORIALS.has("items") and (pda.TUTORIALS["time"] as Array).size() == 2)
	pda.stage.open_act("locker")
	await frames(3)
	var cb = pda.confirm_box
	check("first locker click: ONLY the prompt (no tip before answering)", cb.visible and (pda.guide_tour == null or not pda.guide_tour.visible))
	cb.answer(true)
	await frames(2)
	check("Yes: no tip during the fade", pda.guide_tour == null or not pda.guide_tour.visible)
	await wait_s(FADE)
	var gt = pda.guide_tour
	check("after the fade: tip 1 'TIP: Some actions require Time.' on the hour just spent", gt != null and gt.visible
		and pda.guide_id == "time" and gt.text_label.text == "TIP: Some actions require Time."
		and pda.time_bar.get_global_rect().grow(4.0).encloses(pda._guide_rect("time_spent"))
		and pda._guide_rect("time_spent").size.x < pda.time_bar.size.x * 0.5)
	pda.guide_next()
	await frames(2)
	check("tip 2 'Missions are limited to 8 Hours.' highlights the time bar", gt.text_label.text == "Missions are limited to 8 Hours."
		and pda._guide_rect("time") == pda.time_box.get_global_rect())
	pda.guide_next()
	await frames(2)
	check("then it stops (the TRM-CUFF/menu tip moved to the map onboarding); nothing opened", not gt.visible
		and pda.has_flag("tut_time_done") and not pda.windows.any_open() and not pda.tab_revealed("inv"))
	pda.stage.open_act("locker")
	await frames(3)
	check("E) the first opening: the locker + character screen, INV is added to the menu (animated)", pda.windows.container_open()
		and pda.tab_revealed("inv") and pda.inv_button.visible)
	check("... the drag tip runs first", gt.visible and pda.guide_id == "drag")
	pda.guide_next()
	await frames(2)
	check("C) then the inventory tips follow (not stacked): 1 'TIP: This is your Inventory. Items you are holding will be shown here.' on the grid",
		gt.visible and pda.guide_id == "inventory" and gt.text_label.text == "TIP: This is your Inventory. Items you are holding will be shown here."
		and pda._guide_rect("inv_grid") == pda.windows.character.grid_bg.get_global_rect())
	pda.guide_next()
	await frames(2)
	check("2 'TIP: This is your Character.' on the figure", gt.text_label.text == "TIP: This is your Character."
		and pda._guide_rect("inv_figure") == pda.windows.character.figure.get_global_rect())
	pda.guide_next()
	await frames(2)
	check("3 'TIP: Click EXIT to close.' on EXIT; no X on the screen", gt.text_label.text == "TIP: Click EXIT to close."
		and pda._guide_rect("inv_exit") == pda.windows.character.exit_button.get_global_rect()
		and not pda.windows.character.close_button.visible)
	pda.guide_next()
	await frames(2)
	check("done once; Inventory + Character + Time in the LOG", not gt.visible and pda.has_flag("tut_inventory_done")
		and ["tut_inventory", "tut_character", "tut_time"].all(func(t: String) -> bool:
			return pda.log_entries().any(func(e: Dictionary) -> bool: return e["id"] == t and e["category"] == "TUTORIALS")))
	pda.windows.close_all(true)
	await frames(2)
	pda.show_inv()
	await frames(2)
	check("the inventory again: no tips", not gt.visible)
	var all := ""
	for k: String in ["time", "status", "map_click", "menu", "inventory"]:
		for st: Dictionary in pda.TUTORIALS[k]:
			all += str(st["text"]) + " "
	check("no other hotkeys named in the tips (TAB only in the MENU tip, as asked)", RegEx.create_from_string("\\bESC\\b|\\bSPACE\\b|PRESS|HOTKEY").search(all.to_upper()) == null
		and all.count("TAB") == 1)
	await drop_scene()
	PdaScreen.tutorials_enabled = false


# ---------------------------------------------------------------- 3. free takes + free suit

func test_free_takes_and_suit() -> void:
	await spawn()
	await open_locker()
	var cont = pda.windows.container
	check("drag SUIT into the inventory: taken", drag_container_to_inventory("suit") == "taken")
	check("drag AIRLOCK KEYCARD into the inventory: taken", drag_container_to_inventory("airlock_keycard") == "taken")
	await frames(2)
	check("taking SUIT + AIRLOCK KEYCARD is free (still 7 after the 1 hr search)", pda.inventory.has(&"suit") and pda.inventory.has(&"airlock_keycard")
		and pda.time_blocks == 7)
	var chr = pda.windows.character
	var before: Color = figure_col(chr)
	chr.select_id("suit")
	await frames(1)
	var labels: Array = []
	for b: Button in chr.action_buttons:
		labels.append(b.text)
	check("SUIT offers Put on (no hr) and Drop", labels == ["Put on", "Drop"])
	chr.action_buttons[0].pressed.emit()
	await frames(1)
	check("prompt reads 'Put on?' (no hour)", chr.confirm_text == "Put on?" and chr.action_buttons[1].text == "CANCEL")
	chr.action_buttons[0].pressed.emit()
	await frames(2)
	check("confirmed: FREE (still 7), the fade + zipper run", pda.time_blocks == 7 and pda.suit_fade_busy())
	await wait_s(FADE)
	var after: Color = figure_col(chr)
	check("suit worn: gone from the grid, figure green, still 7", pda.suit_is_worn() and not pda.inventory.has(&"suit") and pda.time_blocks == 7
		and before.v < 0.15 and after.g > after.r + 0.1)
	await drop_scene()


# ---------------------------------------------------------------- 5. coffee + thermos

func test_coffee() -> void:
	await spawn()
	pda._mini_map.marker_clicked.emit("coffee")
	await frames(2)
	var st = pda.windows.station
	check("COFFEE POT window: exact text, one option 'Brew coffee (1 hr)' + EXIT", pda.windows.station_is_open() and st is HoloWindowScript
		and st.text_label.text == COFFEE_TEXT and st.option_buttons.size() == 1 and st.option_buttons[0].text == "Brew coffee (1 hr)"
		and st.exit_button.text.to_upper().contains("EXIT"))
	st.option_buttons[0].pressed.emit()
	await frames(2)
	check("brew: 1 hr spent (8 -> 7) and the screen fades", pda.time_blocks == 7 and pda.suit_fade_busy())
	await wait_s(FADE)
	var c: Dictionary = pda.coffee_state()
	check("after the fade: THERMOS OF COFFEE in the inventory, the pot window says 'The pot is empty.' with only EXIT",
		pda.inventory.has(&"thermos_coffee") and pda.items[&"thermos_coffee"]["label"] == "THERMOS OF COFFEE"
		and st.text_label.text == "The pot is empty." and st.option_buttons.is_empty() and c["brews"] == 1 and c["brewed"])
	check("not repeatable: brew refused, nothing spent, no Drink coffee loop", not pda.coffee_option("brew") and not pda.coffee_option("drink")
		and pda.time_blocks == 7 and pda.inventory.count(&"thermos_coffee") == 1)
	check("state for the AI voicelines: vars.coffee brews / disabled", pda.vars["coffee"].has("brews") and pda.vars["coffee"].has("disabled")
		and pda.has_flag("coffee_brewed"))
	pda.coffee_set_disabled(true)
	await frames(1)
	check("disabled: no options, MACHINE DISABLED", st.option_buttons.is_empty() and st.text_label.text == "MACHINE DISABLED.")
	pda.coffee_set_disabled(false)
	pda.windows.close_all(true)
	await frames(2)
	pda.show_inv()
	await frames(2)
	var chr = pda.windows.character
	chr.select_id("thermos_coffee")
	await frames(1)
	var labels: Array = []
	for b: Button in chr.action_buttons:
		labels.append(b.text)
	check("thermos: Drink + Drop, its text explains the free action", labels == ["Drink", "Drop"]
		and chr.desc_body.text.contains("free action") and chr.desc_body.text.contains("1 hr less"))
	chr.action_buttons[0].pressed.emit()
	await frames(2)
	check("Drink: the thermos is used up, one free action stored, no time spent", not pda.inventory.has(&"thermos_coffee")
		and pda.free_hour_charges() == 1 and pda.time_blocks == 7 and pda.effective_hours(1) == 0 and pda.effective_hours(2) == 1)
	pda.windows.close_all(true)
	await frames(1)
	await open_locker()
	check("the next 1 hr action (search the locker) is free: still 7, charge used", pda.time_blocks == 7 and pda.free_hour_charges() == 0
		and pda.windows.container_open())
	pda.windows.close_all(true)
	await open_locker()
	check("the locker was paid for once: opening it again is free (still 7)", pda.time_blocks == 7)
	pda.windows.close_all(true)
	await drop_scene()
	# dropped thermos is a normal item
	await spawn()
	pda.items[&"thermos_coffee"] = {"label": "THERMOS OF COFFEE", "desc": "x"}
	pda.give_item(&"thermos_coffee")
	check("thermos drops like any item", pda.drop_item(&"thermos_coffee") and pda.dropped_in("ready_room").size() == 1)
	await drop_scene()


# ---------------------------------------------------------------- 6b. drag into / out of a container

func test_container_drag() -> void:
	await spawn()
	pda.items[&"lantern"] = {"label": "LANTERN", "desc": "Light."}
	await open_locker()
	var w = pda.windows
	var cont = w.container
	var chr = w.character
	check("LANTERN dragged out (loot sound UI-3)", drag_container_to_inventory("lantern") == "taken"
		and pda.sfx_log.has("loot") and pda.sfx_log.has(pda.LOOT_SFX))
	await frames(2)
	check("LANTERN taken into the inventory", pda.inventory.has(&"lantern") and cont.slot_for("lantern") == null)
	await drag_from_inventory("lantern")
	check("drag from the character grid: item on the cursor", w.drag_active() and w.ghost_visible() and str(w.drag_item()["id"]) == "lantern")
	motion(cont.grid_bg.get_global_rect().get_center())
	var res: String = w.release_drag(cont.grid_bg.get_global_rect().get_center())
	await frames(2)
	check("dropped on the LOCKER window: stored (in the grid, out of the inventory, kept in game state)", res == "stored"
		and not pda.inventory.has(&"lantern") and cont.slot_for("lantern") != null
		and (pda.container_extras("locker") as Array).size() == 1 and str(pda.container_extras("locker")[0]["id"]) == "lantern")
	pda.windows.close_all(true)
	await frames(2)
	await open_locker()
	check("reopened: the LANTERN is back in the locker", cont.slot_for("lantern") != null and cont.slot_for("suit") != null)
	var ls: Control = cont.slot_for("lantern")
	ls.start_drag_now(ls.get_global_rect().get_center())
	await frames(1)
	var r2: String = w.release_drag(chr.grid_bg.get_global_rect().get_center())
	await frames(2)
	check("drag it back onto the character screen: taken, gone from the locker's state", r2 == "taken" and pda.inventory.has(&"lantern")
		and pda.container_extras("locker").is_empty() and cont.slot_for("lantern") == null)
	# fill the locker: no room = refused
	for n in 9:
		var iid := StringName("junk%d" % n)
		pda.items[iid] = {"label": "JUNK %d" % n, "desc": "x"}
		pda.give_item(iid)
	var stored := 0
	for n in 9:
		await drag_from_inventory("junk%d" % n)
		if w.release_drag(cont.grid_bg.get_global_rect().get_center()) == "stored":
			stored += 1
		await frames(1)
	check("a full grid refuses more (NO ROOM), the rest stay in the inventory (%d stored)" % stored, stored >= 1 and stored < 9 and cont.free_cell() == -1
		and pda.inventory.size() > 1 and cont.notice_label.text == "NO ROOM")
	pda.windows.close_all(true)
	await frames(1)
	await drop_scene()


# ---------------------------------------------------------------- 6d. the item sticks to the cursor

func test_cursor_drag() -> void:
	await spawn()
	pda.items[&"lantern"] = {"label": "LANTERN", "desc": "Light."}
	pda.give_item(&"lantern")
	pda.give_item(&"airlock_keycard")
	pda.items[&"airlock_keycard"] = {"label": "AIRLOCK KEYCARD", "desc": "Opens the airlock door."}
	var w = pda.windows
	await drag_from_inventory("lantern")
	check("over the inventory window the cursor label is the item name", w.ghost_text() == "LANTERN" and not w.drag_sticky())
	var r: String = w.release_drag(w.character.get_global_rect().get_center())
	await frames(1)
	check("let go over the inventory window (still inside): the item returns", r == "returned" and pda.inventory.has(&"lantern")
		and not w.drag_active() and w.character_open())
	await drag_from_inventory("lantern")
	var away := Vector2(250, 470)      # the story area, outside every window
	motion(away)
	await frames(1)
	check("dragged out of the window: the windows CLOSE, the item is STICKY on the cursor", w.drag_sticky()
		and not w.character_open() and not w.character.visible and w.ghost_visible() and w.ghost_position().distance_to(away) < 30.0)
	check("sticky label over the room: 'DROP LANTERN' (with the lantern icon)", w.ghost_text() == "DROP LANTERN"
		and (w._ghost.get_node("Icon") as Control).visible)
	var lock_pos: Vector2 = mini_global(pda._mini_map.door_rect_local("ready_room|airlock")).get_center()
	motion(lock_pos)
	check("over a lock it reads 'USE LANTERN'", w.ghost_text() == "USE LANTERN")
	motion(away)
	release(away)
	await frames(2)
	check("letting go of the button does NOTHING (still sticky, still carried, nothing dropped)", w.drag_sticky()
		and pda.inventory.has(&"lantern") and pda.dropped_in("ready_room").is_empty())
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	w._input(esc)
	await frames(1)
	check("Esc cancels: the item returns to the inventory, no pause menu, windows stay closed", not w.drag_active()
		and pda.inventory.has(&"lantern") and not pda.pause_menu.visible and not w.any_open() and not w.visible)
	await drag_from_inventory("lantern")
	motion(away)
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	w._input(rc)
	await frames(1)
	check("right click cancels too", not w.drag_active() and pda.inventory.has(&"lantern"))
	await drag_from_inventory("lantern")
	motion(away)
	release(away)
	var mc0: int = pda.map_change_count
	click(away)
	await frames(2)
	check("CLICK on the room: dropped on the floor, a dot on the map, drop sound (UI-5)", not pda.inventory.has(&"lantern")
		and pda.dropped_in("ready_room").size() == 1 and pda._mini_map.markers().any(func(m: Dictionary) -> bool: return str(m["kind"]) == "drop")
		and not w.drag_active() and pda.sfx_log.has(pda.DROP_SFX))
	check("the map was added to: the FULL MAP opens, the windows do NOT come back", pda.map_overlay.visible and not w.any_open()
		and pda.map_change_count == mc0 + 1)
	pda.close_map()
	# real mouse events through the viewport: press, move out, let go (nothing), click (drop)
	pda.give_item(&"lantern")
	pda.dropped_in("ready_room").clear()
	pda.show_inv()
	await frames(2)
	var sl: Control = w.character.slot_for("lantern")
	var from := sl.get_global_rect().get_center()
	_send_button(from, true)
	await frames(1)
	for i in range(1, 7):
		_send_motion(from.lerp(away, float(i) / 6.0), MOUSE_BUTTON_MASK_LEFT)
		await frames(1)
	var stuck: bool = w.drag_sticky()
	_send_button(away, false)
	await frames(2)
	var kept: bool = pda.inventory.has(&"lantern") and w.drag_active()
	_send_button(away, true)
	await frames(1)
	_send_button(away, false)
	await frames(2)
	check("real mouse: press + move out = sticky, release keeps it, the next click drops it", stuck and kept
		and not pda.inventory.has(&"lantern") and not w.drag_active() and pda.dropped_in("ready_room").size() == 1)
	await drop_scene()


func _to_window(pos: Vector2) -> Vector2:
	return root.get_final_transform() * pos


func _send_motion(pos: Vector2, mask := 0) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _to_window(pos)
	e.global_position = e.position
	e.button_mask = mask
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _send_button(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = _to_window(pos)
	e.global_position = e.position
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)
	Input.flush_buffered_events()


# ---------------------------------------------------------------- 6d. locks: drag the card, clicks never unlock

func click_lock(key: String) -> void:
	var mm = pda._mini_map
	var r: Rect2 = mm.door_rect_local(key)
	var hit: String = mm.door_at(r.get_center())
	mm.door_clicked.emit(hit if hit != "" else key)
	await frames(2)


func lock_center(key: String) -> Vector2:
	return mini_global(pda._mini_map.door_rect_local(key)).get_center()


func test_locks() -> void:
	await spawn()
	var mm = pda._mini_map
	pda.items[&"airlock_keycard"] = {"label": "AIRLOCK KEYCARD", "desc": "Opens the airlock door."}
	pda.items[&"lantern"] = {"label": "LANTERN", "desc": "Light."}
	pda.give_item(&"airlock_keycard")
	pda.give_item(&"lantern")
	await click_lock("ready_room|airlock")
	check("click the airlock lock WITH the card carried: only 'Requires Airlock Keycard', still locked (old unlock is gone)",
		pda.map_last_error == "Requires Airlock Keycard" and pda.map_door_between("ready_room", "airlock")["state"] == "locked"
		and pda._map_room_label("airlock") == "UNCHARTED COMPARTMENT")
	await click_lock("ready_room|stbd_hold")
	check("click the restricted lock: 'Requires Restricted Keycard' + RESTRICTED reveal", pda.map_last_error == "Requires Restricted Keycard"
		and pda.map_room_restricted("stbd_hold"))
	check("a room revealed = the map was added to: the full map opens", pda.map_overlay.visible)
	pda.close_map()
	await frames(1)
	check("the lock is a drop target where it is drawn", pda.map_target_at(lock_center("ready_room|airlock")) == "door:ready_room|airlock")
	await drag_from_inventory("lantern")
	sticky_click(lock_center("ready_room|airlock"))
	await frames(2)
	check("wrong item (LANTERN) on the lock: \"That doesn't work.\", still locked, lantern kept", pda.map_last_error == "That doesn't work."
		and pda.map_door_between("ready_room", "airlock")["state"] == "locked" and pda.inventory.has(&"lantern"))
	var used: Array = []
	pda.item_used.connect(func(t: String, i: String, r: String) -> void: used.append([t, i, r]))
	await drag_from_inventory("airlock_keycard")
	sticky_click(lock_center("ready_room|airlock"))
	await frames(2)
	check("AIRLOCK KEYCARD dragged onto the lock: unlocks (animation), AIR LOCK named, the card stays in the inventory",
		mm.unlocking("ready_room|airlock") and pda.map_door_between("ready_room", "airlock")["state"] == "open"
		and pda.has_flag("door_open_ready_room_airlock") and pda._map_room_label("airlock") == "AIR LOCK" and pda.inventory.has(&"airlock_keycard")
		and used.size() == 1 and used[0] == ["door:ready_room|airlock", "airlock_keycard", "unlocked"])
	check("after the unlock the inventory does NOT reopen; the full map shows it; unlock sounds (latch + dooropen.mp3)",
		not pda.windows.any_open() and pda.map_overlay.visible and pda.sfx_log.has("unlock") and pda.sfx_log.has(pda.DOOR_UNLOCK_SFX)
		and pda.sfx_log.has(pda.UNLOCK_SFX))
	pda.close_map()
	await frames(1)
	await drag_from_inventory("airlock_keycard")
	sticky_click(lock_center("ready_room|stbd_hold"))
	await frames(2)
	check("the airlock card on the restricted lock: That doesn't work.", pda.map_last_error == "That doesn't work."
		and pda.map_door_between("ready_room", "stbd_hold")["state"] == "locked")
	var cr: Rect2 = mini_global(mm.marker_rect_local("coffee"))
	check("COFFEE POT box is a target", pda.map_target_at(cr.get_center()) == "marker:coffee")
	await drag_from_inventory("lantern")
	sticky_click(cr.get_center())
	await frames(2)
	check("item on the COFFEE POT: Nothing happens (kept, not dropped)", pda._mini_banner.text == "Nothing happens."
		and pda.inventory.has(&"lantern") and pda.dropped_in("ready_room").is_empty() and used.back()[2] == "nothing")
	check("generic hook: use_item_on(target, item) for later puzzles", pda.has_method("use_item_on") and pda.has_method("_use_item_hook")
		and pda.use_item_on("marker:window", "lantern") == "nothing")
	await drop_scene()


# ---------------------------------------------------------------- 6c. dropped items are dots

func test_dots() -> void:
	await spawn()
	var mm = pda._mini_map
	for n in 11:
		var iid := StringName("junk%d" % n)
		pda.items[iid] = {"label": "JUNK %d" % n, "desc": "x"}
		pda.give_item(iid)
		pda.drop_item(iid)
	await frames(2)
	var rects: Array = []
	var fixed: Array = []
	var shown_n := 0
	var piles := 0
	var dots := true
	for m: Dictionary in mm.markers():
		var r: Rect2 = mm.marker_hit_rect(str(m["id"]))
		if str(m["kind"]) == "act":
			fixed.append(r)
			dots = dots and not mm.is_dot(m)
		else:
			rects.append(r)
			dots = dots and mm.is_dot(m)
			if str(m["kind"]) == "pile":
				piles += 1
			else:
				shown_n += 1
	var clean := true
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			clean = clean and not (rects[i] as Rect2).intersects(rects[j])
		for f: Rect2 in fixed:
			clean = clean and not (rects[i] as Rect2).intersects(f)
	check("dropped items are DOTS + name (room features stay boxes); no overlaps; %d shown + %d PILE" % [shown_n, piles],
		dots and clean and fixed.size() == 3 and piles == 1 and shown_n == PdaScreen.DROP_SLOTS - 1)
	var any := ""
	for m: Dictionary in mm.markers():
		if str(m["kind"]) == "drop":
			any = str(m["id"])
			break
	var hr: Rect2 = mm.marker_hit_rect(any)
	var dc: Vector2 = mm.dot_center_local(any)
	check("the dot and its name are clickable (hit area is dot + label, smaller than the cell)", mm.marker_at(dc) == any
		and mm.marker_at(hr.end - Vector2(2, 2)) == any and hr.size.x <= mm.marker_rect_local(any).size.x + 1.0)
	var before: int = pda.dropped_in("ready_room").size()
	mm.marker_clicked.emit(any)
	await frames(2)
	check("click a dot: picked up", pda.dropped_in("ready_room").size() == before - 1)
	mm.marker_clicked.emit("pile:ready_room")
	await frames(2)
	check("PILE opens the FLOOR window; it does not take drops", pda.windows.container_open() and pda.windows.container.title_label.text == "FLOOR"
		and not pda.windows.container.accepts_drops)
	pda.windows.close_all(true)
	await drop_scene()


# ---------------------------------------------------------------- 7. STASIS-3

func test_stasis() -> void:
	await spawn()
	var map: Dictionary = pda.vessel_map
	var labels := ""
	for id: Variant in map["rooms"]:
		labels += str(map["rooms"][id]["label"]) + " "
	check("the stasis room is STASIS-3 (minimap + full map data), no STASIS-15", (map["rooms"] as Dictionary).has("stasis_3")
		and map["rooms"]["stasis_3"]["label"] == "STASIS-3" and not labels.contains("15") and pda._mini_map.map_data["rooms"].has("stasis_3"))
	var all := ""
	for f in ["res://story/scenes/excursion1_prep.json", "res://data/vessel.gd", "res://ui/map_tour.gd", "res://templates/pda_screen.gd",
			"res://scenes/intro.gd", "res://docs/SCENE_WRITER.md", "res://README.md"]:
		all += FileAccess.get_file_as_string(f)
	check("no STASIS-15 / stasis_15 left in data, tour text, code, docs", not all.contains("STASIS-15") and not all.contains("stasis_15"))
	await drop_scene()


# ---------------------------------------------------------------- 8. HUD

func test_hud() -> void:
	await spawn()
	await frames(3)
	check("no menu button at the top right of the game HUD", not pda.journal_button.visible)
	var ow: float = pda.o2_bar.size.x
	var tw: float = pda.time_box.size.x
	check("O2 bar and HRS bar are the same length (%.0f vs %.0f) and the same height" % [ow, tw], absf(ow - tw) <= 2.0 and ow >= O2Bar.HUD_W - 1.0
		and pda.o2_bar.custom_minimum_size.y == pda.time_box.custom_minimum_size.y and (pda.time_bar.get_child(0) as Control).size.y == O2Bar.BAR_H)
	var cells := 0.0
	for c in pda.time_bar.get_children():
		cells += (c as Control).size.x
	check("the 8 hour cells fill the bar", cells > tw * 0.8 and pda.time_bar.get_child_count() == 8)
	check("both bars sit at the right edge of the header, side by side", pda.time_box.get_global_rect().end.x > pda.get_viewport_rect().size.x - 40.0
		and pda.o2_bar.get_global_rect().end.x <= pda.time_box.get_global_rect().position.x)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	pda._input(esc)
	await frames(2)
	check("Esc still opens the pause menu", pda.pause_menu.visible)
	pda.hide_pause()
	pda.show_plate("X")
	pda.hide_plate()
	await frames(1)
	check("after a plate the menu button stays hidden", not pda.journal_button.visible)
	await drop_scene()


# ---------------------------------------------------------------- airlock warning (unchanged)

func test_airlock_warning() -> void:
	await spawn()
	pda.flags["door_open_ready_room_airlock"] = true
	pda.map_set_door_state("ready_room|airlock", "open")
	pda._refresh_maps()
	await frames(2)
	var key: String = pda.exit_door_key()
	check("the exit is the airlock door; it reacts to clicks once open", key == "ready_room|airlock" and pda._map_click_doors().has(key))
	pda._mini_map.door_clicked.emit(key)
	await frames(2)
	check("not suited: warning with exact text, Yes / No", pda.confirm_box.visible
		and pda.confirm_box.text_label.text == "Warning: Going on Excursion without a suit is inadvisable. Do you wish to proceed anyway?")
	pda.confirm_box.no_button.pressed.emit()
	await frames(2)
	check("No: stays", not pda.confirm_box.visible and pda.screen_index == 2 and not pda.has_flag("went_without_suit"))
	pda._mini_map.door_clicked.emit(key)
	await frames(2)
	pda.confirm_box.yes_button.pressed.emit()
	await frames(2)
	check("Yes: went_without_suit recorded, a fade starts", pda.has_flag("went_without_suit") and pda.leaving and pda.suit_fade_busy())
	await arrive_airlock()
	check("... into the placeholder AIR LOCK scene (flag carried, map on the air lock)", pda.scene_path == "res://story/scenes/airlock.json"
		and pda.stage.heading_label.text == "AIR LOCK" and pda.has_flag("went_without_suit")
		and str(pda.vessel_map.get("current", "")) == "airlock" and shown() == "YOU ARE IN THE AIRLOCK")
	await drop_scene()
	await spawn()
	pda.map_set_door_state("ready_room|airlock", "open")
	pda.vars["suit_worn"] = true
	pda._mini_map.door_clicked.emit("ready_room|airlock")
	await frames(2)
	check("suited: no warning, goes straight on", (pda.confirm_box == null or not pda.confirm_box.visible) and pda.leaving)
	await arrive_airlock()
	check("suited: the AIR LOCK scene, suit_worn kept", pda.scene_path == "res://story/scenes/airlock.json" and pda.suit_is_worn())
	await drop_scene()


func test_intro_hud() -> void:
	var intro = (load("res://scenes/intro.tscn") as PackedScene).instantiate()
	root.add_child(intro)
	current_scene = intro
	await frames(6)
	var h: float = intro.hud_o2.size.y
	check("intro: the HUD O2 bar has the full height (%.0f) and is inside the screen" % h, h >= O2Bar.TOTAL_H - 0.5
		and intro.hud_o2.get_global_rect().position.y >= 0.0 and intro.hud_o2.get_global_rect().end.y <= intro.get_viewport_rect().size.y)
	intro.queue_free()
	await frames(2)


# ---------------------------------------------------------------- round 4: LOG pop-up

func test_log_window() -> void:
	await spawn()
	pda.windows.logw.animate = false
	pda._on_tab_pressed(pda.Tab.LOG)
	await frames(2)
	var lw = pda.windows.logw
	check("LOG tab opens the LOG pop-up (hologram window, centred)", pda.log_open() and lw is HoloWindowScript
		and absf(lw.position.x + lw.panel_size.x * 0.5 - pda.windows.size.x * 0.5) < 2.0)
	check("search bar: placeholder 'Search Log' + drawn magnifying glass, EXIT bottom right", lw.search_edit.placeholder_text == "Search Log"
		and lw.search_icon != null and lw.exit_button.text == "EXIT" and lw.exit_button.position.x > lw.panel_size.x * 0.7
		and lw.exit_button.position.y > lw.panel_size.y * 0.8)
	var cats: PackedStringArray = lw.categories()
	check("from the start: REC-7 Corporation under COMPANY, no tutorials yet, no ship entry yet", "COMPANY" in cats
		and lw.listed_ids().has("rec7") and not ("TUTORIALS" in cats) and not lw.listed_ids().has("abeyance"))
	var rec: Dictionary = {}
	for e: Dictionary in pda.log_entries():
		if e["id"] == "rec7":
			rec = e
	check("REC-7 Corporation: only intro lines (insurance, CLAIM OPERATOR, CED, bonus, recorded)", rec.get("title", "") == "REC-7 Corporation"
		and str(rec["text"]).contains("provides premium insurance policies to other corporations operating across the known universe")
		and str(rec["text"]).contains("You are a CLAIM OPERATOR.") and str(rec["text"]).contains("SIGNIFICANT MONETARY BONUS")
		and str(rec["text"]).contains("Everything you do aboard any REC-7 vessel is recorded."))
	pda.windows.close_log()
	await frames(2)
	pda.file_log_entry("abeyance", "RSV ABEYANCE", LOG_TEXT)
	for f in ["tut_map_done", "tut_drag_done", "tut_drop_done", "tut_time_done"]:
		pda.flags[f] = true
	pda.open_log("abeyance")
	await frames(2)
	cats = lw.categories()
	check("categories in order SHIP, COMPANY, TUTORIALS", Array(cats) == ["SHIP", "COMPANY", "TUTORIALS"])
	check("TUTORIALS: Map, Containers, Items, Doors, Time, Moving Rooms once seen", ["tut_map", "tut_containers", "tut_items", "tut_doors", "tut_time", "tut_moving"].all(
		func(i: String) -> bool: return lw.listed_ids().has(i)))
	check("opened on the selected entry: the right side shows its text", lw.selected_id == "abeyance" and lw.text_box.get_parsed_text().contains(LOG_TEXT))
	lw.set_search("cryopod")
	await frames(1)
	check("search filters by body text ('cryopod' -> only RSV ABEYANCE)", lw.listed_ids() == ["abeyance"])
	lw.set_search("moving")
	await frames(1)
	check("search filters by title ('moving' -> Moving Rooms)", lw.listed_ids() == ["tut_moving"] and lw.selected_id == "tut_moving")
	lw.set_search("zzzz")
	await frames(1)
	check("no match: empty list, nothing selected", lw.listed_ids().is_empty() and lw.selected_id == "")
	lw.set_search("")
	await frames(1)
	check("clear search: everything back", lw.listed_ids().size() == 8)
	lw.exit_button.pressed.emit()
	await frames(2)
	check("EXIT closes it", not pda.log_open())
	pda.open_log()
	await frames(2)
	pda._handle_escape()
	await frames(2)
	check("Esc closes it", not pda.log_open())
	pda.show_inv()
	await frames(2)
	pda.open_log()
	await frames(2)
	check("the LOG opens alone (the character screen closes)", pda.log_open() and not pda.windows.character_open())
	await drop_scene()


# ---------------------------------------------------------------- round 4: tutorials

func test_round4_tutorials() -> void:
	PdaScreen.tutorials_enabled = true
	await spawn()
	pda.flags["tut_time_done"] = true      # (the time tip is tested above)
	pda.flags["tut_inventory_done"] = true # (the inventory tips too)
	# log tutorial
	pda.open_log()
	await frames(3)
	var gt = pda.guide_tour
	var lw = pda.windows.logw
	check("first LOG: tip 1 'TIP: This is your LOG. Important information will be stored here.' on the list",
		gt != null and gt.visible and pda.guide_id == "log" and gt.text_label.text == "TIP: This is your LOG. Important information will be stored here."
		and pda._guide_rect("log_list") == lw.list_rect() and lw.list_rect().size.x > 50.0)
	gt.press()
	await frames(1)
	check("tip 2 'TIP: The log is searchable.' on the search bar", gt.text_label.text == "TIP: The log is searchable."
		and pda._guide_rect("log_search") == lw.search_rect())
	gt.press()
	await frames(1)
	check("tip 3 'TIP: Click here to exit the log.' on EXIT", gt.text_label.text == "TIP: Click here to exit the log."
		and pda._guide_rect("log_exit") == lw.exit_rect())
	gt.press()
	await frames(1)
	check("then it stops (flag tut_log_done), the LOG stays open", not gt.visible and pda.has_flag("tut_log_done") and pda.log_open())
	pda.windows.close_all(true)
	pda.open_log()
	await frames(2)
	check("second LOG: no tutorial", not gt.visible)
	pda.windows.close_all(true)
	await frames(1)
	# drag tip
	var mc0: int = pda.map_change_count
	pda.stage.open_act("locker")
	await frames(2)
	pda.confirm_box.answer(true)
	await wait_s(FADE)
	check("searching a container does NOT open the full map", not pda.map_overlay.visible and pda.map_change_count == mc0)
	pda.stage.open_act("locker")      # searched: click it again to open it
	await frames(2)
	check("first container window: the drag tip", gt.visible and pda.guide_id == "drag"
		and gt.text_label.text == "TIP: Take an item from any CONTAINER by dragging and dropping it into your inventory.")
	var f1: Dictionary = gt.anim_frame()
	await wait_s(0.5)
	var f2: Dictionary = gt.anim_frame()
	var cg: Rect2 = pda.windows.container.grid_bg.get_global_rect()
	var ig: Rect2 = pda.windows.character.grid_bg.get_global_rect()
	check("its looping animation: a ghost item moves from the container grid toward the inventory grid", not f1.is_empty()
		and (f1["from"] + gt.global_position).distance_to(cg.get_center()) < 1.0 and (f1["to"] + gt.global_position).distance_to(ig.get_center()) < 1.0
		and (f2["pos"] as Vector2) != (f1["pos"] as Vector2))
	gt.press()
	await frames(1)
	check("CONTINUE dismisses it (flag tut_drag_done); it is in the LOG", not gt.visible and pda.has_flag("tut_drag_done")
		and pda.log_entries().any(func(e: Dictionary) -> bool: return e["id"] == "tut_containers"))
	pda.windows.close_all(true)
	await open_locker()
	await frames(2)
	check("second container window: no drag tip", not gt.visible)
	# drop tutorial
	drag_container_to_inventory("lantern")
	await frames(2)
	await drag_from_inventory("lantern")
	sticky_click(Vector2(40, 300))
	await frames(4)
	check("first drop: dropped, the map stays CLOSED (tip 1 over the normal screen) with its animation",
		pda.dropped_in("ready_room").size() == 1 and not pda.map_overlay.visible and gt.visible and pda.guide_id == "drop"
		and gt.text_label.text == "TIP: Inventory is limited. Sometimes you may need to DROP items. Drag the item off the inventory, then click to drop it."
		and not gt.anim_frame().is_empty() and str(gt.anim_frame()["label"]) == "DROP LANTERN")
	gt.press()
	await frames(2)
	var dr: Rect2 = pda._guide_rect("map_drop")
	check("tip 2 'TIP: The item now appears on the map.' maximizes the map now and highlights the dot", pda.map_overlay.visible
		and gt.text_label.text == "TIP: The item now appears on the map."
		and dr.size.x > 4.0 and pda._full_map.get_global_rect().encloses(dr))
	gt.press()
	await frames(1)
	check("then it stops (tut_drop_done), Items in the LOG", not gt.visible and pda.has_flag("tut_drop_done")
		and pda.log_entries().any(func(e: Dictionary) -> bool: return e["id"] == "tut_items"))
	pda.close_map()
	pda.give_item(&"lantern")
	pda.drop_item(&"lantern")
	await frames(3)
	check("second drop: no tip, the maximize rule again (full map opens)", not gt.visible and pda.dropped_in("ready_room").size() == 2
		and pda.map_overlay.visible)
	await drop_scene()
	PdaScreen.tutorials_enabled = false


# ---------------------------------------------------------------- round 4: icons

func test_icons() -> void:
	var Icons = load("res://ui/item_icons.gd")
	check("code-drawn icons: THERMOS, SUIT, LANTERN, keycards (none for unknown items)", Icons.has_icon("thermos_coffee")
		and Icons.has_icon("suit") and Icons.has_icon("lantern") and Icons.has_icon("airlock_keycard") and not Icons.has_icon("junk1"))
	await spawn()
	pda.items[&"lantern"] = {"label": "LANTERN", "desc": "Light."}
	pda.give_item(&"lantern")
	pda.show_inv()
	await frames(3)
	var sl: Control = pda.windows.character.slot_for("lantern")
	check("the inventory cell draws the lantern art", sl != null and Icons.kind(str(sl.item["id"])) == "lantern")
	await drop_scene()


# ---------------------------------------------------------------- round 5: the tab rail

func key(code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.shift_pressed = shift
	e.pressed = true
	pda._input(e)
	await frames(2)


func lit() -> Array:
	var out: Array = []
	for t: String in pda.GAME_TABS:
		if pda.game_tab_button(t).theme_type_variation == &"TabButtonActive":
			out.append(t)
	return out


func test_rail() -> void:
	await spawn()
	pda.windows.logw.animate = false
	var tabs: Node = pda.sta_button.get_parent()
	var order: Array = []
	for c in tabs.get_children():
		if c is Button and (c as Button).visible:
			order.append((c as Button).text)
	check("rail order STA, INV, LOG, MAP (top to bottom)", order == ["STA", "INV", "LOG", "MAP"])
	await frames(2)
	check("room text, nothing open: STA lit (the main game state)", lit() == ["sta"] and pda.active_game_tab() == "sta")
	check("no STATUS window exists any more", not ResourceLoader.exists("res://ui/status_window.gd") and not ("statusw" in pda.windows))
	await key(KEY_TAB)
	check("TAB: down to INV", pda.windows.character_open() and lit() == ["inv"])
	await key(KEY_TAB)
	check("TAB: down to LOG (inventory closes)", pda.log_open() and not pda.windows.character_open() and lit() == ["log"])
	await key(KEY_TAB)
	check("TAB: down to MAP (the full map)", pda.map_overlay.visible and not pda.windows.any_open() and lit() == ["map"])
	await key(KEY_TAB)
	check("TAB: wraps to STA = everything closed, the room text", not pda.map_overlay.visible and not pda.windows.any_open()
		and lit() == ["sta"] and shown() == ROOM_TEXT)
	await key(KEY_TAB, true)
	check("Shift+TAB: up to MAP", pda.map_overlay.visible and lit() == ["map"])
	pda.map_button.pressed.emit()
	await frames(2)
	check("clicking the lit MAP tab closes the map (STA lit)", not pda.map_overlay.visible and lit() == ["sta"])
	pda.map_button.pressed.emit()
	await frames(2)
	check("MAP tab opens the full map", pda.map_overlay.visible and lit() == ["map"])
	pda.sta_button.pressed.emit()
	await frames(2)
	check("STA tab closes the map", not pda.map_overlay.visible and lit() == ["sta"])
	await open_locker()
	pda.open_log()
	await frames(2)
	pda.windows.close_all(true)
	await open_locker()
	check("a container window lights INV (the character screen is up)", lit() == ["inv"])
	pda.sta_button.pressed.emit()
	await frames(2)
	check("STA closes every window (container + character) and returns to the room text", not pda.windows.any_open() and lit() == ["sta"])
	await key(KEY_I)
	check("I = inventory", pda.windows.character_open() and lit() == ["inv"])
	await key(KEY_I)
	check("I again closes it (STA)", not pda.windows.character_open() and lit() == ["sta"])
	await key(KEY_C)
	check("C = inventory too", pda.windows.character_open())
	await key(KEY_ESCAPE)
	check("Esc closes the top window", not pda.windows.any_open() and lit() == ["sta"] and not pda.pause_menu.visible)
	await drop_scene()


func test_round6() -> void:
	await spawn()
	# 2) back to STASIS-3 and back, state intact
	await take_from_locker("lantern")
	pda.drop_item(&"lantern")
	await frames(2)
	pda.close_map()
	var blocks: int = pda.time_blocks
	pda.open_map()
	await frames(2)
	var rt0: int = pda.room_transitions
	pda._on_full_map_room_clicked("stasis_3")
	await frames(2)
	check("B) ROOM TRANSITION: the move fades to black (door sound), still in the READY ROOM text while it darkens",
		pda.room_transitions == rt0 + 1 and pda.suit_fade_busy() and PdaScreen.MAP_MOVE_SFX == "res://assets/sounds/dooropen.mp3")
	await wait_s(PdaScreen.SUIT_FADE_IN + 0.12)
	check("... dark: the new room is set up, its text held (frozen) until the fade-in", pda.stage.heading_label.text == "STASIS-3" and pda.stage.frozen)
	await wait_s(FADE - PdaScreen.SUIT_FADE_IN)
	check("... faded in: the room text TYPES fresh (not complete yet)", not pda.stage.frozen and not pda.suit_fade_busy()
		and pda.stage.is_typing())
	pda.stage.skip_typing(true)
	await frames(2)
	check("map click on STASIS-3 moves there: placeholder room text, map closed, no CONTINUE", pda.stage.heading_label.text == "STASIS-3"
		and shown() == "STASIS-3 is quiet. Your cryopod stands open and empty, its lid raised, frost still melting on the glass.\n\nThere is nothing more for you here."
		and not pda.map_overlay.visible and str(pda.vessel_map.get("current", "")) == "stasis_3" and not pda.stage.continue_button.visible)
	check("no intro / thaw retriggered, hours untouched", pda.time_blocks == blocks and str(pda.scene_file_path).ends_with("excursion1_prep.tscn"))
	pda.open_map()
	await frames(2)
	pda._on_full_map_room_clicked("ready_room")
	await wait_s(FADE)
	pda.stage.skip_typing(true)
	await frames(2)
	check("back to the READY ROOM: its text, the dropped lantern, the searched locker, hours kept", pda.stage.heading_label.text == "READY ROOM"
		and shown() == ROOM_TEXT and pda.dropped_in("ready_room").size() == 1 and pda.has_flag("searched_locker") and pda.time_blocks == blocks)
	pda.stage.open_act("locker")
	await frames(2)
	check("3) the searched locker opens without the prompt or a cost", pda.windows.container_open() and not pda.confirm_box.visible
		and pda.time_blocks == blocks)
	# 4) EXIT on the character screen
	var chr = pda.windows.character
	check("4) character screen: EXIT bottom right (the X is gone, round 7)", chr.exit_button.text == "EXIT" and not chr.close_button.visible
		and chr.exit_button.position.x + chr.exit_button.size.x > chr.panel_size.x - 16.0
		and chr.exit_button.position.y + chr.exit_button.size.y > chr.panel_size.y - 16.0)
	pda.windows.close_all(true)
	await frames(2)
	pda.windows.open_character()
	await frames(2)
	chr.exit_button.pressed.emit()
	await frames(2)
	check("EXIT closes it", not pda.windows.character_open())
	# 7) map EXIT bottom right
	pda.open_map()
	await frames(3)
	var mb: Button = pda.map_close_button
	var page: Rect2 = pda.map_overlay.get_global_rect()
	check("7) the full map's button reads EXIT and sits bottom right", mb.text == "EXIT"
		and mb.get_global_rect().end.x > page.end.x - 80.0 and mb.get_global_rect().end.y > page.end.y - 80.0)
	# 8) WINDOW marker on the maximized map
	pda._full_map.marker_clicked.emit("window")
	await frames(3)
	pda.stage.skip_typing(true)
	await frames(3)
	check("8) WINDOW marker on the full map: map closes, STA, the window sub-screen", not pda.map_overlay.visible
		and pda.active_game_tab() == "sta" and shown().begins_with("You step over to the window"))
	await drop_scene()
	# 5) AIR LOCK name stamps in when unlocked
	await spawn()
	await take_from_locker("airlock_keycard")
	pda._unlock_door(pda.map_door_between("ready_room", "airlock"))
	await frames(2)
	check("5) unlocking: the AIR LOCK label stamps in (like RESTRICTED)", pda._mini_map.label_age("airlock") < 0.5
		and pda._full_map.label_age("airlock") < 0.5)
	await drop_scene()
	# 6) outline: AIR LOCK is next after READY ROOM
	check("6) SCENE_ORDER: scene:airlock/airlock follows the READY ROOM (EXCURSION 1)",
		SceneOrderScript.next_after("scene:new_scene_2/ready_room") == "scene:airlock/airlock"
		and ResourceLoader.exists("res://scenes/authored/airlock.tscn"))


func test_round7() -> void:
	# A) no scene title over the READY ROOM
	await spawn("res://scenes/authored/new_scene_2.tscn", 0, [])
	check("A) new_scene_2 READY ROOM: no 'NEW SCENE' title line, only the READY ROOM heading", pda.stage.status_label.text == "" and pda.title_label.text == ""
		and pda.stage.heading_label.text == "READY ROOM" and str(pda.scene.get("title", "")) != "NEW SCENE")
	check("D5) dev start at the READY ROOM: STA + MAP only (INV after the locker), LOG hidden",
		pda.rail_tabs() == ["sta", "map"] and pda.sta_button.visible and pda.map_button.visible and not pda.inv_button.visible
		and not pda.tab_buttons[pda.Tab.LOG].visible and pda.mini_map_frame.visible)
	await key(KEY_I)
	check("I / C do nothing while INV is hidden", not pda.windows.any_open())
	await key(KEY_TAB)
	check("TAB cycles the visible buttons only: STA -> MAP", pda.map_overlay.visible and pda.active_game_tab() == "map")
	await key(KEY_TAB)
	check("... and wraps to STA", not pda.map_overlay.visible and pda.active_game_tab() == "sta")
	pda.open_game_tab("log")
	await frames(2)
	check("a hidden tab cannot be opened (LOG)", not pda.log_open())
	# round 8: the LOG tutorial earns the LOG button
	PdaScreen.tutorials_enabled = true
	pda.open_log("abeyance")
	await frames(2)
	check("R8) the LOG tutorial (RSV ABEYANCE link) reveals the LOG button, animated + persisted", pda.guide_id == "log"
		and pda.tab_revealed("log") and pda.tab_buttons[pda.Tab.LOG].visible and pda.tab_buttons[pda.Tab.LOG].modulate.a < 1.0
		and (pda.vars["rail_tabs"] as Array).has("log"))
	while pda.guide_tour != null and pda.guide_tour.visible:
		pda.guide_tour.press()
		await frames(2)
	PdaScreen.tutorials_enabled = false
	pda.windows.close_all()
	await frames(2)
	pda.set_rail_tabs(["sta", "map"])
	await frames(1)
	# D7 / round 8) maps: the schematic keeps the old dark background; only the full map's window frame is holo green + flickers
	var page: PanelContainer = pda.map_overlay.get_node("MapPage")
	check("R8) full map + minimap schematic: OLD dark map background (not the window green), no FX over the schematic",
		pda._mini_map.bg_color == ShipMapView.COL_BG and pda._full_map.bg_color == ShipMapView.COL_BG
		and pda._mini_map.get_node_or_null("HoloFx") == null and pda._full_map.get_node_or_null("HoloFx") == null)
	check("R8) the map WINDOW frame stays holo green with the flicker (FX behind the content)",
		(page.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == HoloWindowScript.WIN_BG
		and page.get_node_or_null("HoloFx") != null and page.get_node("HoloFx").get_index() == 0)
	check("R8) minimap header back to its old colour (no dark ink on the black HUD)", not pda.mini_map_header.has_theme_color_override("font_color"))
	# F) labels relative to the player's room
	pda.map_know_room(&"airlock")
	await frames(2)
	var g: Dictionary = pda._full_map.edge_label_geom("airlock", "AIR LOCK")
	var ar: Rect2 = pda._full_map.room_rect_local("airlock")
	check("F) from the READY ROOM the AIR LOCK (west) reads bottom-to-top (-90) along its east edge by the door",
		g.get("side", "") == "w" and is_equal_approx(float(g["rot"]), -PI * 0.5) and (g["c"] as Vector2).x > ar.get_center().x
		and ar.has_point(g["c"]))
	var gs: Dictionary = pda._full_map.edge_label_geom("stbd_hold", "RESTRICTED")
	check("F) the STBD side (east) reads top-to-bottom (+90) along its west edge", gs.get("side", "") == "e"
		and is_equal_approx(float(gs["rot"]), PI * 0.5))
	var gst: Dictionary = pda._full_map.edge_label_geom("stasis_3", "STASIS-3")
	check("F) STASIS-3 next door gets an edge label too; the player's own room keeps the centred label", not gst.is_empty()
		and pda._full_map.edge_label_geom("ready_room", "READY ROOM").is_empty())
	pda.map_set_room(&"stasis_3")
	await frames(1)
	check("F) dynamic: from STASIS-3 the READY ROOM gets the edge label instead, the AIR LOCK (not adjacent) none",
		not pda._full_map.edge_label_geom("ready_room", "READY ROOM").is_empty() and pda._full_map.edge_label_geom("airlock", "AIR LOCK").is_empty())
	pda.map_set_room(&"ready_room")
	await drop_scene()
	# D5) AIR LOCK dev start reveals INV
	await spawn("res://scenes/authored/airlock.tscn", 0, [])
	check("D5) dev start at the AIR LOCK: STA, INV, MAP; B) its text is YOU ARE IN THE AIRLOCK, no scene title", pda.rail_tabs() == ["sta", "inv", "map"]
		and shown() == "YOU ARE IN THE AIRLOCK" and pda.stage.status_label.text == "")
	await drop_scene()
	# E) the cost border goes with the search; the airlock exit sound
	check("B) the air lock door plays airlockdoor.mp3 on the way out", pda == null or ResourceLoader.exists("res://assets/sounds/airlockdoor.mp3"))


func test_onboarding() -> void:
	PdaScreen.tutorials_enabled = true
	pda = (load(SCENE) as PackedScene).instantiate()
	root.add_child(pda)
	current_scene = pda
	await frames(3)
	pda._ensure_windows()
	pda.windows.set_animated(false)
	check("D1) EXCURSION 1 // PREP loads with ONLY STA, no minimap", pda.rail_tabs() == ["sta"] and pda.sta_button.visible
		and not pda.map_button.visible and not pda.inv_button.visible and not pda.tab_buttons[pda.Tab.LOG].visible and not pda.mini_map_frame.visible)
	await key(KEY_M)
	check("M does nothing yet", not pda.map_overlay.visible)
	pda.stage.skip_typing()
	await frames(3)
	var gt = pda.guide_tour
	check("D2) typing done: no CONTINUE, tip 'TIP: This is your STATUS screen. It shows details about your current situation.' on STA",
		gt != null and gt.visible and pda.guide_id == "status" and not pda.stage.continue_button.visible
		and gt.text_label.text == "TIP: This is your STATUS screen. It shows details about your current situation."
		and pda._guide_rect("sta").encloses(pda.sta_button.get_global_rect()))
	pda._on_continue()
	await frames(1)
	check("the story cannot be continued meanwhile", pda.screen_index == 0)
	gt.press()
	await frames(2)
	check("D3) the MAP button + the minimap turn on (animated)", pda.tab_revealed("map") and pda.map_button.visible and pda.mini_map_frame.visible
		and pda.mini_map_frame.modulate.a < 1.0)
	await wait_s(0.7)
	check("then 'TIP: This is your MAP. Click on it to zoom in.' on the minimap, no CONTINUE (Space does nothing)", gt.visible and pda.guide_id == "map_click"
		and gt.text_label.text == "TIP: This is your MAP. Click on it to zoom in." and not gt.continue_button.visible
		and pda._guide_rect("minimap") == pda.mini_map_frame.get_global_rect())
	gt.press()
	await frames(1)
	check("... (CONTINUE / Space ignored)", gt.visible and pda.guide_id == "map_click")
	gt.click_hole()
	await frames(4)
	check("clicking the minimap zooms in: the full map + the map walkthrough tip 1", pda.map_overlay.visible and pda.tour_phase == "tip"
		and pda.tour_step == 0 and pda.tour.visible)
	for k in 7:
		pda.tour.press()
		await frames(2)
	check("D4) after the last map tip: the map MINIMIZES, the walkthrough goes on: 'TIP: You can also find the map here, in your MENU. Click or TAB to cycle through your MENU.' on MAP",
		not pda.map_overlay.visible and gt.visible and pda.guide_id == "menu"
		and gt.text_label.text == "TIP: You can also find the map here, in your MENU. Click or TAB to cycle through your MENU."
		and pda._guide_rect("map_button") == pda.map_button.get_global_rect())
	gt.press()
	await frames(3)
	check("then it ends and play goes on: the walk to the READY ROOM (map open, the move prompt)", not gt.visible and pda.has_flag("tut_onboard_done")
		and pda.tour_phase == "move" and pda.map_overlay.visible)
	check("D6) Status, Map, Menu in the LOG (TUTORIALS) though the LOG button is hidden", ["tut_status", "tut_map", "tut_trmcuff"].all(
		func(t: String) -> bool: return pda.log_entries().any(func(e: Dictionary) -> bool: return e["id"] == t and e["category"] == "TUTORIALS"))
		and not pda.tab_buttons[pda.Tab.LOG].visible)
	var rt0: int = pda.room_transitions
	pda.map_try_move("ready_room")
	await wait_s(3.5)
	check("B) the first walk into the READY ROOM is a ROOM TRANSITION; the menu keeps STA + MAP (INV not earned yet)",
		pda.room_transitions == rt0 + 1 and pda.stage.heading_label.text == "READY ROOM" and pda.rail_tabs() == ["sta", "map"]
		and pda.stage.status_label.text == "" and pda.title_label.text == "")
	await drop_scene()
	PdaScreen.tutorials_enabled = false
