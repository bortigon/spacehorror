extends SceneTree
## Character screen + container window (headless):
##   godot --headless --audio-driver Dummy --path . --script res://tools/window_test.gd
## Covers: the container act opens the container window AND the character screen (pair centred, 25 % /
## 75 % split), TAB / C / I toggle, Take + drag-and-drop move the item into the inventory (flags, hours),
## EXIT / Esc closing rules, story input blocked, non-container acts and old files unchanged, and the
## open / close animation phases + timing. Pixels cannot be checked here: look at it in the editor.

const SCENE := "res://scenes/authored/excursion1_prep.tscn"
const NEW_SCENE := "res://scenes/authored/new_scene_2.tscn"
const StageScript := preload("res://ui/story_stage.gd")
const SceneData := preload("res://ui/story_scene.gd")
const CharScript := preload("res://ui/character_screen.gd")
const ContScript := preload("res://ui/container_window.gd")

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

## The locker asks "Searching the locker will take 1 hr. Are you sure?" first: answer Yes and wait out the fade.
func open_locker() -> void:
	pda.stage.open_act("locker")
	await frames(2)
	if pda.confirm_box != null and pda.confirm_box.visible:
		pda.confirm_box.answer(true)
		await create_timer(1.15).timeout
		pda.stage.open_act("locker")      # searching does not open it: click the searched locker again
		await frames(2)



func key(code: Key, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.shift_pressed = shift
	e.pressed = true
	return e


func press(code: Key, shift := false) -> void:
	pda._input(key(code, shift))


func spawn(scene_path: String, screen: int) -> void:
	pda = (load(scene_path) as PackedScene).instantiate()
	pda.vars["rail_tabs"] = ["sta", "inv", "log", "map"]   # every button (the dynamic menu is tested in ready_test)
	root.add_child(pda)
	current_scene = pda
	await frames(3)
	pda.enter_screen(screen)
	await frames(2)
	pda.stage.skip_typing(true)
	await frames(2)
	pda._ensure_windows()
	pda.windows.set_animated(false)


func drop(node: Node) -> void:
	node.queue_free()
	await frames(2)


func _init() -> void:
	PdaScreen.tutorials_enabled = false   # the walkthrough has its own test (ready_test.gd)
	await frames(1)
	await test_data()
	await test_stage_acts()
	await test_ready_room()
	await test_keys_and_closing()
	await test_real_input()
	await test_animation()
	print("WINDOW %d pass, %d fail" % [passes, fails])
	quit(1 if fails else 0)


# ---------------------------------------------------------------- data

func test_data() -> void:
	for path in ["res://story/scenes/new_scene_2.json", "res://story/scenes/excursion1_prep.json"]:
		var d: Dictionary = SceneData.load_file(path)
		var rr: Dictionary = {}
		for s: Dictionary in d["screens"]:
			if str(s["id"]) == "ready_room":
				rr = s
		var lk: Dictionary = (rr.get("acts", {}) as Dictionary).get("locker", {})
		var items: Array = lk.get("items", [])
		check("data %s: ready room locker is a container with suit + lantern + airlock keycard" % path.get_file(),
			bool(lk.get("container", false)) and str(lk["title"]) == "LOCKER" and items.size() == 3
			and str(items[0]["id"]) == "suit" and not bool(items[0]["required"]) and int(items[0]["hours"]) == 0
			and str(items[1]["id"]) == "lantern" and int(items[1]["hours"]) == 0
			and str(items[2]["id"]) == "airlock_keycard" and str(items[2]["label"]) == "AIRLOCK KEYCARD" and int(items[2]["hours"]) == 0
			and lk["search"]["hours"] == 1 and lk["search"]["text"] == "Searching the locker will take 1 hr. Are you sure?"
			and items[0]["actions"] == ["take"] and int(lk["grid"]["cols"]) == 3 and int(lk["grid"]["rows"]) == 3
			and not str(lk["text"]).contains("does not spend") and not lk.has("choices")
			and str(rr["text"]).contains("[act=locker]LOCKERS[/act]") and str(rr["text"]).contains("[act=coffee]COFFEE POT[/act]")
			and not str(rr["text"]).contains("does not spend"))
		check("data %s: the way out is the airlock door on the map, no SUIT REQUIRED gate" % path.get_file(),
			str((rr["end"] as Dictionary)["type"]) == "hold" and str((rr["end"] as Dictionary)["exit"]) == "door:ready_room|airlock"
			and not (rr["end"] as Dictionary).has("require"))
	var n := SceneData.normalize({"id": "t", "screens": [{"text": "x", "acts": {
		"crate": {"container": true, "title": "CRATE", "text": "d", "grid": {"cols": 99, "rows": 0}, "items": [
			{"label": "Bag of Chips", "hours": "2", "detail": "Salty.", "actions": ["take", "Use", "take"]},
			{"id": "tape", "label": "TAPE", "actions": []}]},
		"old": {"container": true, "text": "o", "choices": [{"label": "SUIT", "hours": 1, "item": "suit", "required": true}]},
		"fn": {"text": "t", "choices": [{"label": "Nap", "hours": 1}]}}}]})
	var acts: Dictionary = n["screens"][0]["acts"]
	var crate: Dictionary = acts["crate"]
	check("normalize: container grid clamped, ids from labels, actions cleaned, default take",
		int(crate["grid"]["cols"]) == 8 and int(crate["grid"]["rows"]) == 1 and crate["items"][0]["id"] == "bag_of_chips"
		and int(crate["items"][0]["hours"]) == 2 and crate["items"][0]["actions"] == ["take", "use"]
		and crate["items"][1]["actions"] == [] and not (acts["old"] as Dictionary).has("choices")
		and acts["old"]["items"][0]["id"] == "suit" and acts["old"]["items"][0]["actions"] == ["take"])
	check("normalize: non-container acts keep the function shape",
		not (acts["fn"] as Dictionary).has("container") and acts["fn"]["choices"][0]["label"] == "Nap")
	var msgs := JSON.stringify(SceneData.validate(SceneData.normalize({"id": "t", "title": "T", "screens": [{"id": "a", "text": "x",
		"end": {"type": "hold"}, "acts": {"c": {"container": true, "grid": {"cols": 1, "rows": 1}, "items": [
			{"id": "a", "label": "A"}, {"id": "a", "label": "B"}]}, "e": {"container": true}}}]})))
	check("validate: too many items, duplicate ids, empty container", msgs.contains("grid only has 1 cells")
		and msgs.contains("two items called") and msgs.contains("has no items"))
	var legacy := SceneData.normalize({"id": "legacy_act", "screens": [{"text": "x", "acts": [
		{"id": "locker", "title": "LOCKER", "actions": [{"id": "suit", "label": "SUIT", "hours": 1, "item": "suit", "required": true}]}]}]})
	var leg: Dictionary = legacy["screens"][0]["acts"]["locker"]
	check("old popup acts still load as functions", not leg.has("container") and leg["choices"][0]["item"] == "suit")


# ---------------------------------------------------------------- stage

func test_stage_acts() -> void:
	var stage := StageScript.new()
	root.add_child(stage)
	var spec_a := {"text": "Closet. [act=crate]crate[/act]", "choices": [{"label": "Nap", "hours": 1, "item": ""}]}
	var crate := {"container": true, "title": "CRATE", "text": "A crate.", "grid": {"cols": 2, "rows": 2},
		"items": [{"id": "tape", "label": "TAPE", "hours": 2, "required": false, "detail": "d", "actions": ["take"]}]}
	stage.play({"heading": "H", "text": "See the [act=closet]closet[/act] and [act=crate]crate[/act].", "speed": 200,
		"end": {"type": "continue", "goto": "next"}, "acts": {"closet": spec_a, "crate": crate}})
	stage.skip_typing(true)
	await frames(2)
	var calls: Array = []
	stage.container_handler = func(id: String, spec: Dictionary) -> void: calls.append([id, spec])
	stage.open_act("closet")
	stage.skip_typing(true)
	await frames(2)
	check("non-container act with a handler set: still replaces the text, option + Back, handler not called",
		calls.is_empty() and str(stage.text_label.get_parsed_text()).contains("Closet.")
		and stage.choice_buttons.size() == 2 and stage.choice_buttons[0].text == "Nap (1 hr)" and stage.choice_buttons[1].text == "Back")
	stage.choice_buttons[1].pressed.emit()
	stage.skip_typing(true)
	await frames(2)
	stage.open_act("crate")
	await frames(2)
	check("container act: handler gets (id, spec), screen text and options stay as they were",
		calls.size() == 1 and calls[0][0] == "crate" and bool((calls[0][1] as Dictionary)["container"])
		and str(stage.text_label.get_parsed_text()).contains("See the") and not stage._in_act and stage.choice_buttons.size() == 0
		and stage.is_container("crate") and not stage.is_container("closet"))
	stage.container_handler = Callable()
	stage.open_act("crate")
	stage.skip_typing(true)
	await frames(2)
	check("container act with no window (Scene Writer preview): reads as the old function",
		str(stage.text_label.get_parsed_text()).contains("A crate.") and stage.choice_buttons.size() == 2
		and stage.choice_buttons[0].text == "TAPE (2 hrs)" and stage.choice_buttons[1].text == "Back")
	stage.queue_free()
	await frames(1)


# ---------------------------------------------------------------- ready room

func test_ready_room() -> void:
	await spawn(SCENE, 2)
	var w = pda.windows
	var cont = w.container
	var chr = w.character
	check("no window is up before the locker is clicked", not w.any_open() and not w.visible and not pda.windows_open())
	await open_locker()
	await frames(2)
	check("locker click: container window AND character screen open", w.container_open() and w.character_open()
		and w.visible and w.mouse_filter == Control.MOUSE_FILTER_STOP)
	check("story text stays, no Back list: it is a window, not a function", not pda.stage._in_act
		and pda.stage.choice_buttons.size() == 0 and str(pda.stage.text_label.get_parsed_text()).contains("LOCKER"))
	var vp := Vector2(960, 540)
	var pair_w: float = chr.panel_size.x + w.GAP + cont.panel_size.x
	check("pair is centred: character left of container, same row, gap between",
		is_equal_approx(chr.base_pos.x, roundf((vp.x - pair_w) * 0.5))
		and is_equal_approx(cont.base_pos.x, chr.base_pos.x + chr.panel_size.x + w.GAP)
		and is_equal_approx(chr.base_pos.y, roundf((vp.y - chr.panel_size.y) * 0.5))
		and is_equal_approx(cont.base_pos.y, roundf((vp.y - cont.panel_size.y) * 0.5))
		and chr.position.is_equal_approx(chr.base_pos) and chr.panel_size.y >= 300 and cont.panel_size.y >= 300)
	check("container: title top-left, description under it in a wider left column (fixed size + font, scrolls if long), grid on the right",
		cont.title_label.text == "LOCKER" and cont.title_label.position.y < cont.desc_box.position.y
		and cont.desc_box.position.x + cont.desc_box.size.x <= cont.grid_bg.position.x
		and cont.desc_box.size.x > cont.panel_size.x * 0.3 and cont.desc_box.scroll_active and cont.desc_font_size() == 10
		and cont.grid_bg.position.x >= cont.panel_size.x * 0.4 and cont.desc_box.text.contains("The locker is in front of you")
		and cont.slots.size() == 9 and cont.slot_for("suit") != null and cont.slot_for("lantern") != null
		and cont.exit_button.position.x + cont.exit_button.size.x > cont.panel_size.x * 0.75
		and cont.exit_button.position.y > cont.grid_bg.position.y + cont.grid_bg.size.y - 2.0)
	check("character: NAME top-left, X top-right, figure left, blank reserved space, 3x5 grid right",
		chr.name_label.text == "OPERATOR" and chr.name_label.position.x < 20.0 and chr.close_button.position.x > chr.panel_size.x * 0.8
		and chr.figure.position.x < chr.grid_bg.position.x and chr.reserved_space.position.y > chr.figure.position.y + 100.0
		and chr.reserved_space.get_child_count() == 0 and chr.slots.size() == 15 and chr.grid_bg.position.x > chr.panel_size.x * 0.3)
	check("character grid starts COMPLETELY EMPTY (no placeholder items, nothing dim)", chr.filled_ids().is_empty()
		and chr.slots.all(func(sl: Control) -> bool: return sl.item.is_empty() and not sl.dim))
	check("no key hints drawn anywhere in the windows", not _has_text(w, ["TAB", "PRESS", "[C]", "[I]"]))

	# selecting an item swaps the buttons
	check("no item highlighted: no action button, EXIT is there", cont.action_buttons.is_empty() and cont.exit_button.visible)
	cont.slot_for("suit").pressed.emit(cont.slot_for("suit"))
	await frames(1)
	check("click highlights SUIT: its detail shows in the left area, NO Take button (drag and drop only)",
		cont.selected_id == "suit" and cont.slot_for("suit").selected and cont.desc_box.text.contains("Pressure suit")
		and cont.action_buttons.is_empty())
	cont.slot_for("lantern").pressed.emit(cont.slot_for("lantern"))
	await frames(1)
	check("highlighting LANTERN swaps the selection (still no button)", cont.action_buttons.is_empty() and cont.selected_id == "lantern"
		and not cont.slot_for("suit").selected)
	cont.select_id("suit")
	cont.do_action("take")
	await frames(2)
	check("take SUIT: in the inventory, flag set, FREE (the 1 hr was the search: 8 -> 7), cell empty, button gone",
		pda.inventory.has(&"suit") and pda.has_flag("has_suit") and pda.time_blocks == 7 and cont.slot_for("suit") == null
		and cont.action_buttons.is_empty() and cont.remaining() == 2 and cont.find_item("suit")["taken"])
	check("character screen now carries SUIT, selected, with its detail", chr.filled_ids() == PackedStringArray(["suit"])
		and chr.selected_id == "suit" and chr.desc_body.text.contains("Pressure suit"))
	# drag and drop LANTERN onto the character grid (our own drag: it sticks to the cursor)
	var ls: Control = cont.slot_for("lantern")
	var target: Control = chr.slots[0]
	ls.start_drag_now(ls.get_global_rect().get_center())
	await frames(1)
	check("drag a container item: it is stuck to the cursor, windows stay up (nothing left them)",
		w.drag_active() and str(w.drag_item()["id"]) == "lantern" and w.ghost_visible() and not w.drag_hidden())
	var res: String = w.release_drag(target.get_global_rect().get_center())
	await frames(2)
	check("drag LANTERN onto the character screen: taken (result taken), free, container keeps the keycard, cell empty",
		res == "taken" and pda.inventory.has(&"lantern") and pda.has_flag("has_lantern") and cont.remaining() == 1 and cont.slot_for("lantern") == null
		and pda.time_blocks == 7 and chr.filled_ids().size() == 2 and not w.drag_active())
	var tips: Array = []
	for s2: Control in chr.slots:
		if not s2.item.is_empty() and not s2.dim:
			tips.append(s2.tooltip_text)
	check("hover tooltips reuse the item detail", tips.size() == 2 and str(tips).contains("Pressure suit") and str(tips).contains("Light."))
	cont.exit_button.pressed.emit()
	await frames(2)
	check("EXIT closes the container and the character screen it opened", not w.container_open() and not w.character_open()
		and cont.is_closed() and chr.is_closed() and not w.visible and w.mouse_filter == Control.MOUSE_FILTER_STOP)
	# reopening: taken items stay taken
	await open_locker()
	await frames(2)
	check("reopen: suit + lantern already taken, cells empty, the keycard is still there", cont.remaining() == 1
		and cont.slot_for("suit") == null and cont.slot_for("airlock_keycard") != null and chr.filled_ids().size() == 2)
	w.close_all(true)
	check("close_all(true) leaves nothing up", not w.any_open() and not w.visible)
	check("no CONTINUE button in the ready room (the exit is the airlock door)", not pda.stage.continue_button.visible)
	await drop(pda)

	# taking costs hours that are really spent, and is refused when there are not enough
	await spawn(SCENE, 2)
	check("ready room arms the 8 hour blocks", pda.time_blocks_live and pda.time_blocks == 8)
	await open_locker()
	await frames(2)
	pda.windows.container.select_id("suit")
	pda.windows.container.do_action("take")
	await frames(2)
	check("Take spends the hour from the bar", pda.time_blocks == 7 and pda.inventory.has(&"suit"))
	await drop(pda)

	# the outline target scene (new_scene_2) behaves the same
	await spawn(NEW_SCENE, 0)
	await open_locker()
	await frames(2)
	check("new_scene_2 ready room: locker opens the window pair with SUIT + LANTERN",
		pda.windows.container_open() and pda.windows.character_open() and pda.windows.container.find_item("lantern").size() > 0)
	await drop(pda)


func _shader_has(snippet: String) -> bool:
	return FileAccess.get_file_as_string("res://shaders/holo_window.gdshader").contains(snippet)


func _has_text(node: Node, words: Array) -> bool:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var t := ""
		if n is Label:
			t = (n as Label).text
		elif n is Button:
			t = (n as Button).text
		elif n is RichTextLabel:
			t = (n as RichTextLabel).get_parsed_text()
		for wd: String in words:
			if t.to_upper().contains(wd.to_upper()) and t != "":
				return true
		for c in n.get_children():
			stack.append(c)
	return false


# ---------------------------------------------------------------- keys + closing

func test_keys_and_closing() -> void:
	await spawn(SCENE, 2)
	var w = pda.windows
	var chr = w.character
	var cont = w.container
	var advanced := [0]
	pda.stage.continue_pressed.connect(func() -> void: advanced[0] += 1)
	var tab_before: int = pda.current_tab
	press(KEY_TAB)
	await frames(1)
	check("TAB from the room text goes down the rail to INV (the character screen)", w.character_open())
	press(KEY_TAB)
	await frames(1)
	check("TAB again moves on to LOG (the character screen closes)", not w.character_open() and pda.log_open())
	w.close_all(true)
	await frames(1)
	for code: Key in [KEY_C, KEY_I]:
		press(code)
		await frames(1)
		var opened: bool = w.character_open() and not w.container_open()
		press(code)
		await frames(1)
		check("key %s toggles the character screen (on, then off), tab stays LOG" % OS.get_keycode_string(code),
			opened and not w.character_open() and pda.current_tab == tab_before and chr.is_closed())
	pda.inv_button.pressed.emit()
	await frames(1)
	check("INV tab opens the same character screen (and shows active)", w.character_open() and chr.name_label.text == "OPERATOR"
		and pda.inv_button.theme_type_variation == &"TabButtonActive")
	pda.inv_button.pressed.emit()
	await frames(1)
	check("INV tab again closes it", not w.character_open() and pda.inv_button.theme_type_variation == &"TabButton")
	pda.vars["typed_name"] = "Marlow"
	press(KEY_I)
	await frames(1)
	check("NAME shows the name from the exam when there is one", chr.name_label.text == "MARLOW")
	press(KEY_ESCAPE)
	await frames(1)
	check("Esc closes the character screen (and does not open the pause menu)", not w.character_open() and not pda.pause_menu.visible)
	pda.vars.erase("typed_name")
	press(KEY_ESCAPE)
	await frames(1)
	check("Esc with no window opens the pause menu as before", pda.pause_menu.visible)
	pda.hide_pause()
	# the player opened the character screen first: it stays when the container closes
	press(KEY_I)
	await frames(1)
	await open_locker()
	await frames(1)
	check("container opens beside an already-open character screen", w.character_open() and w.container_open()
		and not w._char_auto)
	press(KEY_SPACE)
	press(KEY_1)
	press(KEY_M)
	await frames(1)
	check("story keys (Space, 1, M) are blocked while a window is up", advanced[0] == 0 and pda.screen_index == 2
		and not pda.map_overlay.visible and w.container_open())
	press(KEY_C)
	await frames(1)
	check("C with the container up closes only the character screen, container stays and re-centres",
		not w.character_open() and w.container_open()
		and is_equal_approx(cont.base_pos.x, roundf((960.0 - cont.panel_size.x) * 0.5)))
	press(KEY_C)
	await frames(1)
	check("C again brings it back beside the container (player-opened now)", w.character_open() and w.container_open()
		and not w._char_auto and cont.base_pos.x > chr.base_pos.x)
	press(KEY_ESCAPE)
	await frames(1)
	check("Esc closes the topmost window first: the container, the character screen stays",
		not w.container_open() and w.character_open())
	press(KEY_ESCAPE)
	await frames(1)
	check("second Esc closes the character screen", not w.any_open())
	# auto-opened character screen goes with the container on Esc
	await open_locker()
	await frames(1)
	check("container alone auto-opened the character screen", w._char_auto and w.character_open())
	press(KEY_ESCAPE)
	await frames(1)
	check("Esc on that pair closes both", not w.any_open() and not w.visible)
	# click-eater: the layer swallows clicks while up
	await open_locker()
	await frames(1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(20, 20)
	check("click-eater layer is on top of the story and covers the screen", w.visible and w.mouse_filter == Control.MOUSE_FILTER_STOP
		and w.get_index() > pda.safe_area.get_index() and w.get_index() < pda.pause_menu.get_index()
		and w.size.x >= 959.0 and w.size.y >= 539.0)
	w.close_all(true)
	await frames(1)
	# TAB with no window still cycles nothing in the game UI (toggles the screen); intro UI keeps TAB for tabs
	pda.set_excursion_chrome(false)
	press(KEY_TAB)
	await frames(1)
	check("outside the game UI TAB does not open the character screen", not w.character_open())
	pda.set_excursion_chrome(true)
	await drop(pda)


# ---------------------------------------------------------------- real mouse events

func send(e: InputEvent) -> void:
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## Canvas position -> window pixels (the headless window is 1280x720 for a 960x540 canvas).
func to_window(pos: Vector2) -> Vector2:
	return root.get_final_transform() * pos


func mouse_move(pos: Vector2, mask := 0, rel := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = to_window(pos)
	e.global_position = e.position
	e.relative = rel
	e.button_mask = mask
	send(e)


func mouse_button(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = to_window(pos)
	e.global_position = e.position
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	send(e)


func click(pos: Vector2) -> void:
	mouse_move(pos)
	await process_frame
	mouse_button(pos, true)
	await process_frame
	mouse_button(pos, false)
	await process_frame


func test_real_input() -> void:
	await spawn(SCENE, 2)
	var w = pda.windows
	var cont = w.container
	var chr = w.character
	await open_locker()
	await frames(2)
	# a click on the story text under the window must not reach the story
	var advanced := [0]
	pda.stage.continue_pressed.connect(func() -> void: advanced[0] += 1)
	await click(Vector2(20, 300))
	await click(Vector2(480, 505))   # where CONTINUE sits
	check("clicks on the story under the windows are eaten", advanced[0] == 0 and pda.screen_index == 2)
	await click(cont.slot_for("suit").get_global_rect().get_center())
	check("real click on an item highlights it", cont.selected_id == "suit")
	await frames(2)
	cont.do_action("take")     # (no Take button any more; the take path itself is unchanged)
	check("take path moves it to the inventory", pda.inventory.has(&"suit") and cont.slot_for("suit") == null)
	var from: Vector2 = cont.slot_for("lantern").get_global_rect().get_center()
	var to: Vector2 = chr.slots[7].get_global_rect().get_center()
	mouse_move(from)
	await process_frame
	mouse_button(from, true)
	await process_frame
	var prev := from
	for i in range(1, 9):
		var p := from.lerp(to, float(i) / 8.0)
		mouse_move(p, MOUSE_BUTTON_MASK_LEFT, p - prev)
		prev = p
		await process_frame
	var dragging: bool = w.drag_active()
	mouse_button(to, false)
	await frames(2)
	check("real drag of LANTERN onto the character grid takes it", dragging and pda.inventory.has(&"lantern") and cont.remaining() == 1)
	await click(cont.exit_button.get_global_rect().get_center())
	check("real click on EXIT closes the pair", not w.any_open())
	await open_locker()
	await frames(2)
	check("round 7: the character screen has NO X (EXIT closes the pair)", not chr.close_button.visible and w.character_open())
	await drop(pda)


# ---------------------------------------------------------------- animation

func test_animation() -> void:
	var win = ContScript.new()
	win.name = "AnimTest"
	root.add_child(win)
	win.base_pos = Vector2(100, 100)
	win.position = win.base_pos
	win.configure("locker", {"title": "LOCKER", "text": "d", "grid": {"cols": 3, "rows": 3},
		"items": [{"id": "suit", "label": "SUIT", "hours": 1, "actions": ["take"]}]})
	var shader_ok: bool = win.fx.material is ShaderMaterial and (win.fx.material as ShaderMaterial).shader.resource_path == "res://shaders/holo_window.gdshader"
	check("hologram shader is on the window's fx layer", shader_ok and win.fx.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	check("closed window is hidden", win.is_closed() and not win.visible)
	var t0 := Time.get_ticks_msec()
	win.open()
	check("open(): shows right away, state OPENING, nothing interactive yet", win.visible and win.state == win.State.OPENING
		and not win.is_interactive())
	await create_timer(0.085).timeout
	var dot_w: float = win._clip.size.x
	var dot_h: float = win._clip.size.y
	await create_timer(0.09).timeout
	var line_h: float = win._clip.size.y
	var line_w: float = win._clip.size.x
	var flash: float = float((win.fx.material as ShaderMaterial).get_shader_parameter("flash"))
	check("turn-on: starts as a tiny bright dot, stretches to a thin full-ish line (no height yet), flash on",
		dot_w <= 80.0 and dot_h <= 4.5 and line_h <= 4.5 and line_w > dot_w and flash > 0.5 and win.state == win.State.OPENING)
	await win.opened
	var open_ms := Time.get_ticks_msec() - t0
	check("open: ends full size, interactive, no flash left (%d ms)" % open_ms, win.state == win.State.OPEN and win.is_interactive()
		and win._clip.size.is_equal_approx(win.panel_size) and win.body.position == Vector2.ZERO
		and float((win.fx.material as ShaderMaterial).get_shader_parameter("flash")) == 0.0 and open_ms >= 400 and open_ms <= 800)
	check("hologram effects halved: IDLE_FX 0.5, scanlines 0.065, glitch bands 0.14 (were 1.0 / 0.13 / 0.28)", win.IDLE_FX == 0.5
		and _shader_has("scan_strength : hint_range(0.0, 0.6) = 0.065") and _shader_has("glitch * 0.14") and _shader_has("flicker * 0.03"))
	await create_timer(0.3).timeout
	var amin := 1.0
	var jitter_ok := true
	for i in 240:
		await process_frame
		amin = minf(amin, win.modulate.a)
		jitter_ok = jitter_ok and absf(win.position.x - win.base_pos.x) <= 1.3 and win.position.y == win.base_pos.y
	check("hologram: alpha flicker is subtle (never below 0.89 even on the dip, was 0.6)", amin >= 0.89 and win.modulate.a <= 1.0)
	check("hologram: jitter never moves the window more than 1.3 px (was 2.5)", jitter_ok)
	var t1 := Time.get_ticks_msec()
	win.close()
	check("close(): state CLOSING", win.state == win.State.CLOSING and not win.is_interactive())
	await create_timer(0.1).timeout
	var squeeze_h: float = win._clip.size.y
	check("collapse: the window shrinks vertically first", squeeze_h < win.panel_size.y and win.state == win.State.CLOSING)
	await win.closed
	var close_ms := Time.get_ticks_msec() - t1
	check("close: ends hidden and closed (%d ms)" % close_ms, win.is_closed() and not win.visible and close_ms >= 250 and close_ms <= 650
		and win.modulate.a == 1.0 and win.position == win.base_pos)
	check("close is faster than open", close_ms < open_ms)
	win.animate = false
	win.open()
	check("animate=false snaps open", win.state == win.State.OPEN and win._clip.size.is_equal_approx(win.panel_size))
	win.close()
	check("animate=false snaps closed", win.is_closed() and not win.visible)
	var chr = CharScript.new()
	root.add_child(chr)
	chr.animate = false
	chr.open()
	check("character screen shares the base: opens and closes", chr.state == chr.State.OPEN)
	chr.close()
	check("character screen closed", chr.is_closed())
	win.queue_free()
	chr.queue_free()
	await frames(2)
