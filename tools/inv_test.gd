extends SceneTree
## Ready room inventory + hour bar (headless):
##   godot --headless --audio-driver Dummy --path . --script res://tools/inv_test.gd

const SCENE := "res://scenes/authored/excursion1_prep.tscn"

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


func _init() -> void:
	PdaScreen.tutorials_enabled = false
	await frames(1)
	pda = (load(SCENE) as PackedScene).instantiate()
	root.add_child(pda)
	current_scene = pda
	await frames(3)
	pda.enter_screen(2)
	await frames(2)
	pda.stage.skip_typing(true)
	await frames(2)
	check("ready room: 8 blocks visible and LIVE (the room arms them), a cost can be spent", pda.time_bar.visible and pda.time_blocks == 8
		and pda.time_blocks_live and pda.hours_refusal(1) == "")
	var shown: String = pda.stage.text_label.get_parsed_text()
	var bb: String = pda.stage.text_label.text
	check("ready room: locker + coffee pot words are bold capitals, underline has no leading space, old cost line gone",
		shown.contains("LOCKER") and shown.contains("COFFEE POT") and not shown.contains("does not spend")
		and bb.contains("[url href=act:locker underline=never]") and bb.contains("[url href=act:coffee underline=never]")
		and not bb.contains("[url=") and bb.contains("[b][u]LOCKER[/u][/b]") and not bb.contains("[u] "))
	check("ready room: no CONTINUE button, nothing about SUIT REQUIRED", not pda.stage.continue_button.visible
		and not pda.os_line_label.text.contains("SUIT REQUIRED"))
	pda._ensure_windows()
	pda.windows.set_animated(false)
	pda.stage.open_act("locker")
	await frames(2)
	var cont = pda.windows.container
	var chr = pda.windows.character
	check("locker opens the container window + character screen (no replacement text, no Back list)",
		pda.windows.container_open() and pda.windows.character_open() and cont.title_label.text == "LOCKER"
		and cont.find_item("suit")["label"] == "SUIT" and cont.find_item("lantern")["hours"] == 1
		and cont.find_item("airlock_keycard")["label"] == "AIRLOCK KEYCARD" and cont.find_item("airlock_keycard")["hours"] == 1
		and pda.stage.choice_buttons.size() == 0)
	cont.exit_button.pressed.emit()
	await frames(2)
	check("EXIT returns to the ready room text", not pda.windows.any_open() and pda.screen_index == 2
		and str(pda.stage.text_label.get_parsed_text()).contains("LOCKER"))
	pda.stage.open_act("locker")
	await frames(2)
	cont.select_id("suit")
	cont.action_buttons[0].pressed.emit()
	await frames(2)
	check("suit taken: 1 hr spent (8 -> 7), cell empty", pda.inventory.has(&"suit") and pda.time_blocks == 7
		and cont.slot_for("suit") == null and cont.find_item("suit")["taken"])
	cont.select_id("lantern")
	cont.action_buttons[0].pressed.emit()
	await frames(2)
	check("lantern taken: another hr (7 -> 6), flags set", pda.inventory.has(&"lantern") and pda.time_blocks == 6
		and pda.has_flag("has_suit") and pda.has_flag("has_lantern"))
	pda.windows.close_all(true)
	pda.show_inv()
	await frames(2)
	var tip := ""
	var saw_lantern := false
	for s2: Control in chr.slots:
		if not s2.item.is_empty() and str(s2.item["label"]) == "SUIT":
			tip = s2.tooltip_text
			s2.pressed.emit(s2)
		if not s2.item.is_empty() and str(s2.item["label"]) == "LANTERN":
			saw_lantern = true
	check("INV opens the character screen: only what was taken (suit, lantern), tooltip + detail on click",
		pda.windows.character_open() and chr.slots.size() == 15 and chr.filled_ids().size() == 2
		and saw_lantern and tip.contains("Pressure suit") and chr.desc_body.text.contains("Pressure suit"))
	var dim := 0
	for c in pda.time_bar.get_children():
		if c is ColorRect and (c as ColorRect).color.g < 0.3:
			dim += 1
	check("the bar shows the 2 spent blocks dim", dim == 2 and pda.time_count_label.text == "6/8")
	pda.queue_free()
	await frames(2)
	print("INV %d pass, %d fail" % [passes, fails])
	quit(1 if fails else 0)
