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
	await frames(1)
	pda = (load(SCENE) as PackedScene).instantiate()
	root.add_child(pda)
	current_scene = pda
	await frames(3)
	pda.enter_screen(2)
	await frames(2)
	pda.stage.skip_typing(true)
	await frames(2)
	check("ready room: 8 blocks visible, spend refused", pda.time_bar.visible and pda.time_blocks == 8
		and not pda.time_blocks_live and pda.spend_time_blocks(1) == false and pda.time_blocks == 8)
	var shown: String = pda.stage.text_label.get_parsed_text()
	var bb: String = pda.stage.text_label.text
	check("ready room: locker word is bold capitals, underline has no leading space",
		shown.contains("LOCKER") and shown.contains("does not spend them")
		and bb.contains("[url href=act:locker underline=never]") and not bb.contains("[url=")
		and bb.contains("[b][u]LOCKER[/u][/b]") and not bb.contains("[u] "))
	pda.stage.continue_button.pressed.emit()
	await frames(2)
	check("without the suit, continue stays", pda.screen_index == 2 and pda.stage.heading_label.text == "READY ROOM"
		and pda.os_line_label.text.contains("SUIT REQUIRED")
		and not str(pda.stage.text_label.get_parsed_text()).contains("isn't written"))
	pda.stage.open_act("locker")
	pda.stage.skip_typing(true)
	await frames(2)
	var labels: Array = []
	for b in pda.stage.choice_buttons:
		labels.append((b as Button).text)
	check("locker replaces the screen: suit, lantern, Back",
		str(pda.stage.text_label.get_parsed_text()).contains("The locker is in front of you")
		and labels.size() == 3
		and str(labels[0]) == "SUIT (1 hr)"
		and str(labels[1]) == "LANTERN (1 hr)"
		and str(labels[2]) == "Back"
		and pda.stage.choice_buttons[0].custom_minimum_size.is_equal_approx(Vector2(220, 34)))
	pda.stage.choice_buttons[2].pressed.emit()
	pda.stage.skip_typing(true)
	await frames(2)
	check("Back restores the ready room text", pda.screen_index == 2
		and str(pda.stage.text_label.get_parsed_text()).contains("does not spend them")
		and str(pda.stage.text_label.get_parsed_text()).contains("LOCKER")
		and pda.stage.continue_button.visible)
	pda.stage.open_act("locker")
	pda.stage.skip_typing(true)
	await frames(2)
	pda.stage.choice_buttons[0].pressed.emit()
	await frames(2)
	check("suit taken, hours still 8, row marked taken", pda.inventory.has(&"suit") and pda.time_blocks == 8
		and pda.stage.choice_buttons[0].disabled
		and str(pda.stage.choice_buttons[0].text).contains("already taken"))
	pda.stage.choice_buttons[1].pressed.emit()
	await frames(2)
	check("lantern taken, hours still not spent", pda.inventory.has(&"lantern") and pda.time_blocks == 8)
	pda.show_inv()
	await frames(2)
	var tip := ""
	var saw_lantern := false
	for b in pda.inv_grid.get_children():
		if b is Button and (b as Button).text == "SUIT":
			tip = (b as Button).tooltip_text
			(b as Button).pressed.emit()
		if b is Button and (b as Button).text == "LANTERN":
			saw_lantern = true
	check("INV grid: placeholders plus suit and lantern, tooltip on click", pda.inv_grid.get_child_count() == 6
		and pda.inv_view.visible and saw_lantern and tip.contains("Required to leave")
		and pda.inv_detail.text.contains("Required to leave"))
	pda.arm_time_blocks()
	var spent: bool = pda.spend_time_blocks(1)
	var dim := 0
	for c in pda.time_bar.get_children():
		if c is ColorRect and (c as ColorRect).color.g < 0.3:
			dim += 1
	check("armed bar spends one block", pda.time_blocks_live and spent and pda.time_blocks == 7 and dim == 1)
	pda.queue_free()
	await frames(2)
	print("INV %d pass, %d fail" % [passes, fails])
	quit(1 if fails else 0)
