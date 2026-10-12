extends SceneTree
# Scene outline (headless):
#   godot --headless --audio-driver Dummy --path <project> --script res://tools/order_test.gd
# story/SCENE_ORDER.md is CHAPTER / SCENE / SUBSCENE. NEXT moves one subscene.
# Nothing after ready_room shows "The next scene isn't written."

const Order := preload("res://ui/scene_order.gd")
const EXCURSION := "res://scenes/authored/excursion1_prep.tscn"
const NEW_SCENE := "res://scenes/authored/new_scene_2.tscn"

var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func wait_s(sec: float) -> void:
	await create_timer(sec).timeout


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var disk := FileAccess.get_file_as_string("res://story/SCENE_ORDER.md")
	var doc := Order.parse(disk)
	var chs: Array = doc["chapters"]
	check("one chapter, PROLOGUE, with its note", chs.size() == 1
		and str(chs[0]["title"]) == "PROLOGUE"
		and str(chs[0]["note"]) == "Still on this ship, before they leave.")
	var scenes: Array = chs[0]["scenes"]
	check("scenes are INTRO then READY ROOM", scenes.size() == 2
		and str(scenes[0]["title"]) == "INTRO" and str(scenes[1]["title"]) == "READY ROOM")
	var intro: Array = scenes[0]["screens"]
	var room: Array = scenes[1]["screens"]
	check("INTRO subscenes run until the ready-room move", intro.size() == 4
		and str(intro[0]["target"]) == "intro:thaw" and str(intro[0]["label"]) == "STASIS THAW"
		and str(intro[1]["target"]) == "intro:exam"
		and str(intro[2]["target"]) == "scene:excursion1_prep/map"
		and str(intro[3]["target"]) == "scene:excursion1_prep/brief")
	check("READY ROOM subscene is ready_room", room.size() == 1
		and str(room[0]["target"]) == "scene:new_scene_2/ready_room"
		and str(room[0]["label"]) == "READY ROOM")
	check("round trip keeps the file", Order.render(doc) == disk)
	check("no chapter 1 yet", not disk.contains("CHAPTER 1"))
	check("sample_scene is not on the live list", not disk.contains("sample_scene"))

	var flat: Array = Order.flat_screens()
	check("NEXT thaw → exam", Order.next_after("intro:thaw") == "intro:exam")
	check("NEXT exam → map", Order.next_after("intro:exam") == "scene:excursion1_prep/map")
	check("NEXT map → brief", Order.next_after("scene:excursion1_prep/map") == "scene:excursion1_prep/brief")
	check("NEXT brief → ready_room", Order.next_after("scene:excursion1_prep/brief") == "scene:new_scene_2/ready_room")
	check("NEXT ready_room is nowhere", Order.next_after("scene:new_scene_2/ready_room") == "")
	var menu: Array = Order.menu_rows()
	check("menu buttons are the scenes, opening the first subscene", menu.size() == 2
		and str(menu[0]["label"]) == "INTRO" and str(menu[0]["target"]) == "intro:thaw"
		and str(menu[1]["label"]) == "READY ROOM" and str(menu[1]["target"]) == "scene:new_scene_2/ready_room")

	var sample := "note\n## PROLOGUE\nA note.\n### INTRO\n- intro:thaw — STASIS THAW\n  - not a screen\n### READY ROOM\n- scene:excursion1_prep/brief -- BRIEF\n- scene:excursion1_prep/map — MAP\n"
	var parsed: Array = Order.flat_screens(Order.parse(sample))
	check("parser: note, indent, and -- label", parsed.size() == 3
		and str(Order.parse(sample)["chapters"][0]["note"]) == "A note."
		and str(parsed[1]["label"]) == "BRIEF" and str(parsed[1]["screen"]) == "brief")
	check("NEXT of the last screen in a sample is empty", Order.next_after_in(parsed, "scene:excursion1_prep/map") == "")

	var added := Order.place_in(disk, "CHAPTER 1", "AIRLOCK", "airlock", "arrive", "ARRIVE")
	var added_flat: Array = Order.flat_screens(Order.parse(added))
	check("adding a chapter is a list edit", added.contains("## CHAPTER 1") and added.contains("### AIRLOCK")
		and str(added_flat.back()["target"]) == "scene:airlock/arrive"
		and Order.next_after_in(added_flat, "scene:new_scene_2/ready_room") == "scene:airlock/arrive")
	var moved := Order.move_in(disk, "excursion1_prep", "brief", -1)
	var moved_flat: Array = Order.flat_screens(Order.parse(moved))
	check("Earlier swaps brief in front of map inside INTRO", str(moved_flat[2]["screen"]) == "brief"
		and str(moved_flat[3]["screen"]) == "map")
	check("list edits did not touch the file", FileAccess.get_file_as_string("res://story/SCENE_ORDER.md") == disk)

	PdaScreen.tutorials_enabled = false
	var pda = (load(NEW_SCENE) as PackedScene).instantiate()
	root.add_child(pda)
	current_scene = pda
	await process_frame
	await process_frame
	pda.enter_screen(0)
	pda.stage.skip_typing(true)
	await process_frame
	check("ready room is a hold with no CONTINUE (the way on is the airlock door)", str(pda.current_screen().get("id", "")) == "ready_room"
		and pda.stage.end_type() == "hold" and not pda.stage.continue_button.visible and pda.exit_door_key() == "ready_room|airlock")
	pda.vars["suit_worn"] = true
	pda._leave_through_exit()
	await process_frame
	check("end of the list shows the unwritten screen and stays put", str(current_scene.scene_file_path).ends_with("new_scene_2.tscn")
		and str(pda.stage.text_label.text).contains("The next scene isn't written."))

	Order.override_text = disk + "- scene:excursion1_prep/ready_room — READY ROOM 2\n"
	pda.enter_screen(0)
	pda.stage.skip_typing(true)
	await process_frame
	pda._leave_through_exit()
	await process_frame
	await wait_s(0.4)
	check("NEXT opens the following screen", current_scene != null
		and str(current_scene.scene_file_path).ends_with("excursion1_prep.tscn")
		and str(current_scene.current_screen().get("id", "")) == "ready_room")
	Order.override_text = ""
	if current_scene:
		current_scene.queue_free()

	print("ORDER TEST DONE: %d fails" % fails)
	quit(fails)
