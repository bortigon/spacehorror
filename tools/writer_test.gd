extends SceneTree
# Scene Writer test (headless):
#   godot --headless --audio-driver Dummy --path <project> --script res://tools/writer_test.gd
# Markup parser + timing, JSON load / validate, the plugin's builder (builds the sample scene),
# VO auto-timing, the Scene Writer panel (without the editor), and the built sample scene running:
# typing, CONTINUE, choices with the pinned response, red edges, shake, ERROR glitch, VO,
# O2 countdown (press + expire), death + RETRY, links to other scenes / the intro.

const SceneData := preload("res://ui/story_scene.gd")
const Markup := preload("res://ui/story_markup.gd")
const Builder := preload("res://addons/scene_writer/scene_builder.gd")
const VoTiming := preload("res://addons/scene_writer/vo_timing.gd")
const PanelScript := preload("res://addons/scene_writer/writer_panel.gd")
const StageScript := preload("res://ui/story_stage.gd")
const SAMPLE := "res://tools/fixtures/writer_demo.json"
const Order := preload("res://ui/scene_order.gd")
const AMBER := "#e07040"

var fails := 0
var pda


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
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


func wait_s(sec: float) -> void:
	await create_timer(sec).timeout


func frames(n: int) -> void:
	for _i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	test_markup()
	await test_act_click()
	await test_act_stack()
	test_data()
	test_build()
	test_vo_timing()
	await test_panel()
	await test_runtime()
	print("DONE fails=%d" % fails)
	quit(fails)


# ---------------------------------------------------------------- markup

func test_markup() -> void:
	var m = Markup.new().parse("Hello [error]ERROR[/error] and [error=ERROR]ALEX[/error].\n[shake=9]shaky[/shake][pause=1.0] end\n+joined\n\nA [b]bold[/b] [notatag] word")
	check("markup: 4 cue lines (blank line skipped, + joins)", m.line_count == 4)
	check("markup: no warnings", m.warnings.is_empty())
	m.time_by_speed(40.0)
	var e0: Dictionary = m.errs[0]
	var e1: Dictionary = m.errs[1]
	var t_mid := float(m.chars[int(e0["first"]) + 2]["t"])
	var bb: String = m.render(t_mid, 1.0)
	check("error: scrambles (amber) while typing", bb.contains(AMBER) and not bb.contains("ERROR"))
	var t0_last := float(m.chars[int(e0["last"])]["t"])
	bb = m.render(t0_last + 0.1, 1.0)
	var err_at := bb.find("[color=%s]" % AMBER)
	check("error: still glitching just after typing", err_at >= 0 and not bb.substr(err_at, 40).contains("ERROR"))
	bb = m.render(t0_last + Markup.GLITCH_SECONDS + 0.05, 1.0)
	check("error: settles into amber bold word", bb.contains("[color=%s][b]ERROR[/b][/color]" % AMBER))
	var t1_last := float(m.chars[int(e1["last"])]["t"])
	bb = m.render(t1_last + 0.1, 1.0)
	check("error=X: original text shown first", bb.contains("ALEX"))
	bb = m.render(t1_last + Markup.MORPH_HOLD + Markup.MORPH_SECONDS + 0.05, 1.0)
	check("error=X: becomes the replacement in amber", not bb.contains("ALEX") and bb.count("[b]ERROR[/b]") == 2)
	bb = m.render(m.duration + 5.0, 1.0)
	check("shake span: level 9 bbcode", bb.contains("[shake rate=18.0 level=9 connected=1]shaky[/shake]"))
	check("+ line joins the paragraph", bb.contains(" end joined"))
	check("bold tag", bb.contains("[b]bold[/b]"))
	check("unknown [tag] shown literally", bb.contains("[lb]notatag]"))
	var ky := -1
	for i in m.chars.size():
		if m.chars[i]["c"] == "y" and int(m.chars[i]["shake"]) == 9:
			ky = i
	check("pause=1.0 delays the next character by ~1 s",
		ky > 0 and float(m.chars[ky + 1]["t"]) - float(m.chars[ky]["t"]) >= 1.0)
	check("last_line = shown line with + joined", m.last_line() == "A bold [notatag] word")
	check("typed prefix only", not m.render(0.4, 1.0).contains("and"))
	var c = Markup.new().parse("One two.\nThree four five.")
	c.time_by_cues([[1.0, 2.0], [3.0, 4.0]], 40.0)
	check("cues: line 1 starts at its cue", absf(float(c.line_starts[0]) - (1.0 + 0.85 / 8.0)) < 0.01)
	check("cues: line 1 done at 85% of its span", absf(float(c.line_ends[0]) - 1.85) < 0.01)
	check("cues: line 2 starts at cue 2", float(c.line_starts[1]) > 3.0 and float(c.line_starts[1]) < 3.1)
	check("cues: duration = last cue end", absf(c.duration - 4.0) < 0.01)
	var c2 = Markup.new().parse("Cued.\nNot cued line.")
	c2.time_by_cues([[0.0, 1.0]], 20.0)
	check("cues: extra lines continue at the screen speed", float(c2.line_starts[1]) >= 1.3 and c2.duration > 1.3 + 14.0 / 20.0)
	var w = Markup.new().parse("open [error]never closed")
	check("unclosed [error] reported", not w.warnings.is_empty())
	var ex = Markup.new().parse("The [expo]airlock is dark[/expo].")
	ex.time_by_speed(80.0)
	var exb: String = ex.render(ex.duration + 1.0, 1.0)
	check("expo: serif font markup", exb.contains("[font=%s]airlock is dark[/font]" % Markup.EXPO_FONT) and ex.warnings.is_empty())
	var act = Markup.new().parse("Open the [act=locker]LOCKER[/act].")
	act.time_by_speed(80.0)
	var actb: String = act.render(act.duration + 1.0, 1.0)
	check("act: clickable url, plain word kept", actb.contains("[url href=act:locker underline=never]") and not actb.contains("[url=") and actb.contains("[b][u]LOCKER[/u][/b]") and act.warnings.is_empty())
	var spaced = Markup.new().parse("Go [act=locker] locker[/act] now.")
	spaced.time_by_speed(200.0)
	var sb: String = spaced.render(spaced.duration + 1.0, 1.0)
	check("act: underline does not include a leading space",
		sb.contains("[b][u]LOCKER[/u][/b]") and not sb.contains("[u] ") and not sb.contains("[u] L")
		and sb.contains(" [url href=act:locker underline=never]") and not sb.contains("[url="))
	var low = Markup.new().parse("[act= locker]locker [/act]")
	low.time_by_speed(200.0)
	var lb: String = low.render(low.duration + 1.0, 1.0)
	check("act: word is bold capitals, trailing space stays outside, id ignores the space",
		lb.contains("[url href=act:locker underline=never]") and not lb.contains("[url=") and lb.contains("[b][u]LOCKER[/u][/b]")
		and lb.ends_with(" ") and not lb.contains("[u]LOCKER [/u]"))
	var g = Markup.new().parse("[error level=10]HELLO[/error]")
	g.time_by_speed(200.0)
	var wild := 0
	for i in 12:
		var gb: String = g.render(g.duration + 1.0, float(i) * 0.17)
		if not gb.contains("[b]HELLO[/b]"):
			wild += 1
	check("error level 10 is hard to read", int(g.errs[0]["level"]) == 10 and wild >= 8)
	var calm = Markup.new().parse("[error level=0]HELLO[/error]")
	calm.time_by_speed(200.0)
	check("error level 0 settles like a plain error tag",
		calm.render(calm.duration + 1.0, 1.0).contains("[color=%s][b]HELLO[/b][/color]" % AMBER))
	var morph = Markup.new().parse("[error=DEMON delay=1.2]soul[/error]")
	morph.time_by_speed(80.0)
	var t_last := float(morph.chars[int(morph.errs[0]["last"])]["t"])
	check("error delay: original text stays readable", morph.render(t_last + 0.2, 1.0).contains("soul"))
	var later: String = morph.render(t_last + 1.2 + Markup.MORPH_SECONDS + 0.05, 1.0)
	check("error delay: glitch text overwrites it", later.contains("[b]DEMON[/b]") and not later.contains("soul"))
	var old_tag = Markup.new().parse("[error=ERROR]Alex[/error]")
	check("error=WORD still means the glitch text, level 0", str(old_tag.errs[0]["to"]) == "ERROR" and int(old_tag.errs[0]["level"]) == 0 and float(old_tag.errs[0]["delay"]) < 0.0)


# ---------------------------------------------------------------- data


func test_act_click() -> void:
	var m := Markup.new().parse("[act=locker]locker[/act]")
	m.time_by_speed(200.0)
	var bb := str(m.render(m.duration + 1.0, 1.0))
	var re := RegEx.new()
	re.compile("\\[url href=([^\\]\\s]+)")
	var found := re.search(bb)
	var href := found.get_string(1) if found != null else ""
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.selection_enabled = false
	rtl.scroll_active = false
	rtl.position = Vector2.ZERO
	rtl.size = Vector2(400, 80)
	rtl.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(rtl)
	# Same tag the game draws. tooltip repeats href so the engine option parser can be
	# read in headless (a [url=...] value ignores options, so a contaminated id would not come back).
	if href != "":
		rtl.text = bb.replace("[url href=%s underline=never]" % href, "[url href=%s underline=never tooltip=%s]" % [href, href])
	else:
		rtl.text = bb
	await frames(1)
	var tip := ""
	for y in range(0, 36, 2):
		for x in range(0, 160, 4):
			var hit := str(rtl.get_tooltip(Vector2(x, y)))
			if hit != "":
				tip = hit
				break
		if tip != "":
			break
	var shown := str(rtl.get_parsed_text())
	rtl.queue_free()
	await frames(1)
	var id := href.substr(4) if href.begins_with("act:") else href
	check("act click meta is exactly locker", href == "act:locker" and tip == "act:locker" and id == "locker"
		and shown == "LOCKER"
		and not href.contains("underline") and not tip.contains("underline") and not id.contains("underline")
		and not bb.contains("[url="))

func test_act_stack() -> void:
	var stage := StageScript.new()
	root.add_child(stage)
	var advanced := [0]
	stage.continue_pressed.connect(func() -> void: advanced[0] += 1)
	stage.play({
		"heading": "READY ROOM",
		"text": "See the [act=locker] locker[/act] now.",
		"speed": 200,
		"end": {"type": "continue", "goto": "next"},
		"acts": {
			"locker": {
				"text": "Inside the locker. [act=bag]bag[/act] too.",
				"choices": [
					{"label": "Take bag of chips?", "hours": 1, "item": "chips"},
					{"label": "Wait (2 hrs)", "hours": 2, "item": ""},
					{"label": "Nap", "hours": 3, "item": ""},
				],
			},
			"bag": {"text": "A bag of chips.", "choices": []},
			"empty": {"text": "Nothing authored.", "choices": []},
		},
	})
	stage.skip_typing(true)
	await frames(2)
	var shown := str(stage.text_label.get_parsed_text())
	check("act stack: parent shows the word in capitals", shown.contains("LOCKER") and not shown.contains(" locker"))
	stage.open_act("locker")
	stage.skip_typing(true)
	await frames(2)
	shown = str(stage.text_label.get_parsed_text())
	check("act stack: clicking replaces the body", shown.contains("Inside the locker") and not shown.contains("See the"))
	check("act stack: hour suffix is 1 hr, 2 hrs is not doubled, 3 hrs, Back is last",
		stage.choice_buttons.size() == 4
		and stage.choice_buttons[0].text == "Take bag of chips? (1 hr)"
		and stage.choice_buttons[1].text == "Wait (2 hrs)"
		and stage.choice_buttons[2].text == "Nap (3 hrs)"
		and stage.choice_buttons[3].text == "Back")
	stage.open_act("bag")
	stage.skip_typing(true)
	await frames(2)
	check("act stack: inner act replaces again", str(stage.text_label.get_parsed_text()).contains("A bag of chips"))
	check("act stack: Back exists with zero authored choices",
		stage.choice_buttons.size() == 1 and stage.choice_buttons[0].text == "Back")
	stage.choice_buttons[0].pressed.emit()
	stage.skip_typing(true)
	await frames(2)
	check("act stack: Back returns one level", str(stage.text_label.get_parsed_text()).contains("Inside the locker")
		and stage.choice_buttons.size() == 4 and stage.choice_buttons[3].text == "Back")
	stage.choice_buttons[0].pressed.emit()
	await frames(1)
	check("act stack: taken choice stays disabled", stage.choice_buttons[0].disabled
		and stage.choice_buttons[0].text.contains("already taken"))
	stage.choice_buttons[3].pressed.emit()
	stage.skip_typing(true)
	await frames(2)
	shown = str(stage.text_label.get_parsed_text())
	check("act stack: Back restores the parent text and does not advance",
		shown.contains("See the") and shown.contains("LOCKER") and advanced[0] == 0 and stage.continue_button.visible)
	stage.open_act("missing")
	await frames(1)
	var missing := str(stage.text_label.get_parsed_text())
	check("act stack: missing act does not crash", missing.contains("The act \"missing\" isn't written.")
		and not missing.contains("underline")
		and stage.choice_buttons.size() == 0)
	stage.queue_free()
	await frames(1)


func test_data() -> void:
	var d := SceneData.load_file(SAMPLE)
	check("sample loads (4 screens)", (d.get("screens", []) as Array).size() == 4)
	var probs := SceneData.validate(d)
	var errs := probs.filter(func(p: Dictionary) -> bool: return p["level"] == "error")
	check("sample validates with no errors (%d notes)" % probs.size(), errs.is_empty())
	for p: Dictionary in probs:
		print("   note: ", p["msg"])
	var all_text := ""
	var has := {}
	for s: Dictionary in d["screens"]:
		all_text += str(s["text"])
		has["red_" + str(s["red"]["mode"])] = true
		has["end_" + str(s["end"]["type"])] = true
		if int(s["shake"]) > 0:
			has["screen_shake"] = true
		if str(s["vo"]["clip"]) != "" and not (s["vo"]["cues"] as Array).is_empty():
			has["vo_cues"] = true
		if not (s["sfx"] as Array).is_empty():
			has["sfx"] = true
	var every := all_text.contains("[error]") and all_text.contains("[error=") and all_text.contains("[shake") \
		and all_text.contains("[pause=")
	for k in ["red_static", "red_ramp", "red_off", "end_continue", "end_choices", "end_death", "end_qte", "screen_shake", "vo_cues", "sfx"]:
		every = every and has.has(k)
	check("sample uses every effect + every ending", every)
	var bad: Dictionary = d.duplicate(true)
	bad["screens"][1]["end"]["choices"][0]["goto"] = "nowhere"
	bad["screens"][0]["text"] = ""
	bad["screens"][0]["heading"] = ""
	bad["screens"][2]["vo"]["clip"] = "res://assets/sounds/missing.wav"
	bad["screens"][3]["end"] = {"type": "continue", "goto": "next"}
	bad["after"] = ""
	var msgs := PackedStringArray()
	for p: Dictionary in SceneData.validate(bad):
		msgs.append("%s|%s" % [p["level"], p["msg"]])
	var joined := "\n".join(msgs)
	check("validate: missing screen target", joined.contains("error|") and joined.contains("no screen called \"nowhere\""))
	check("validate: empty screen", joined.contains("warning|Screen 1 (wake) is empty."))
	check("validate: missing voice clip", joined.contains("voice clip not found"))
	check("validate: last screen continues into nothing", joined.contains("this is the last screen"))
	var dup: Dictionary = d.duplicate(true)
	dup["screens"][1]["id"] = "wake"
	check("validate: duplicate screen ids", str(SceneData.validate(dup)).contains("Two screens are called"))
	var norm := SceneData.normalize({"id": "My Scene!", "speed": "55", "screens": [{"text": "x", "end": {"type": "bogus"}}]})
	check("normalize: id sanitized, speed cast, bad end -> continue",
		norm["id"] == "my_scene" and norm["speed"] == 55 and norm["screens"][0]["end"]["type"] == "continue")
	var card := SceneData.normalize_screen({"id": "later", "end": {"type": "transition", "card": "ONE HOUR LATER", "goto": "next"}})
	check("normalize: transition keeps the card text", card["end"]["type"] == "transition" and card["end"]["card"] == "ONE HOUR LATER")


# ---------------------------------------------------------------- builder

func test_build() -> void:
	var before := FileAccess.get_file_as_string(SAMPLE)
	var d := SceneData.load_file(SAMPLE)
	var res := Builder.build(d)
	check("builder: sample builds (%s)" % res["message"], bool(res["ok"]))
	check("builder: JSON rewrite is identical (stable format)", FileAccess.get_file_as_string(SAMPLE) == before)
	var tscn := FileAccess.get_file_as_string(str(res["tscn"]))
	check("builder: tscn inherits the template + authored script + scene_path",
		tscn.contains("res://templates/pda_screen.tscn") and tscn.contains("res://templates/authored_scene.gd")
		and tscn.contains("scene_path = \"res://story/scenes/writer_demo.json\""))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://story/scenes/writer_demo.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://scenes/authored/writer_demo.tscn"))
	var bad := d.duplicate(true)
	bad["screens"][0]["end"]["goto"] = "missing_screen"
	bad["id"] = "writer_test_bad"
	var r2 := Builder.build(bad)
	check("builder: refuses to build with errors", not bool(r2["ok"]) and not FileAccess.file_exists(SceneData.json_path("writer_test_bad")))


# ---------------------------------------------------------------- VO auto-time

func test_vo_timing() -> void:
	# [clip, measured cues (MemoryExam), from, to, strict?]  Not strict: B4 has an unscripted sound at
	# 2.8 s + a reverb tail before line 4; screen 1's last two lines are spoken at very different
	# speeds, so the length-weighted fit picks the wrong pause there. David checks + edits by hand.
	var total_lines := 0
	var total_close := 0
	for case: Array in [["res://assets/sounds/memorytestB4.wav", MemoryExam.CUES_NO4, 0.0, -1.0, false],
			["res://assets/sounds/memorytestB3.wav", MemoryExam.CUES_NO3, 0.0, -1.0, true],
			["res://assets/sounds/memorytestB1.wav", MemoryExam.CUES_NO1, 0.0, -1.0, true],
			["res://assets/sounds/memorytestB2.wav", MemoryExam.CUES_NO2, 0.0, -1.0, true],
			["res://assets/sounds/memorytest1C.wav", MemoryExam.CUES_RECOVER, 0.0, -1.0, true],
			["res://assets/sounds/memorytest1.wav", MemoryExam.CUES_SCREEN1, 0.9, 19.2, false],
			["res://assets/sounds/memorytest1.wav", MemoryExam.CUES_ERROR, 22.9, -1.0, true]]:
		var ref: Array = case[1]
		var lines := PackedStringArray()
		for r: Array in ref:
			lines.append(str(r[1]).trim_prefix("+"))
		var cues := VoTiming.auto_time(str(case[0]), ref.size(), float(case[2]), float(case[3]), lines)
		var worst := 0.0
		var close := 0
		if cues.size() == ref.size():
			for i in ref.size():
				var e := maxf(absf(float(cues[i][0]) - float(ref[i][0])), absf(float(cues[i][1]) - float(ref[i][2])))
				worst = maxf(worst, e)
				if e <= 0.3:
					close += 1
		else:
			worst = 99.0
		var label := "%s %s" % [str(case[0]).get_file(), "" if float(case[2]) == 0.0 else "(%.1f-%.1f s)" % [case[2], case[3]]]
		print("   auto-time %s: %s (worst %.2fs, %d/%d lines within 0.3 s) %s" % [label, str(cues), worst, close, ref.size(), VoTiming.last_error])
		total_lines += ref.size()
		total_close += close
		check("auto-time %s: one cue per line" % label, cues.size() == ref.size())
		if bool(case[4]):
			check("auto-time %s: every line within 0.3 s of the measured cues" % label, worst <= 0.3)
	check("auto-time: %d/%d lines within 0.3 s over David's 7 VO windows (>= 75%%)" % [total_close, total_lines],
		total_close * 4 >= total_lines * 3)
	var sp := VoTiming.spread(PackedStringArray(["short", "a much longer line of text"]), 0.0, 10.0)
	check("spread evenly: 2 cues inside the clip, longer line gets more time",
		sp.size() == 2 and float(sp[1][1]) <= 10.0 and (float(sp[1][1]) - float(sp[1][0])) > (float(sp[0][1]) - float(sp[0][0])))
	check("auto-time refuses mp3 with a clear message", VoTiming.auto_time("res://assets/sounds/UI-4.mp3", 1).is_empty()
		and VoTiming.last_error.contains("wav"))


# ---------------------------------------------------------------- panel (no editor)

func test_panel() -> void:
	Order.memory_only = true
	Order.override_text = FileAccess.get_file_as_string("res://story/SCENE_ORDER.md")
	var panel = PanelScript.new()
	panel.size = Vector2(1500, 850)
	root.add_child(panel)
	await frames(3)
	var rows0 := "\n".join(panel.list_row_texts())
	check("panel: opens the first listed scene, outline only", panel.data.get("id", "") == "excursion1_prep"
		and "thaw" in rows0 and not rows0.contains("NOT ON THE LIST") and not rows0.contains("wake"))
	check("panel: demo fixture is not a story scene", panel.open_file(SAMPLE) and panel.data.get("id", "") == "writer_demo"
		and not SceneData.list_scenes().has("writer_demo") and not SceneData.list_scenes().has("sample_scene"))
	panel.select_screen(1)
	await frames(2)
	check("panel: opening / selecting is not an edit", not panel.dirty)
	check("panel: screen text in the editor", panel.text_edit.text.contains("[error=ERROR]ALEX[/error]"))
	panel.text_edit.select(0, 0, 0, 5)
	panel._wrap("[shake]", "[/shake]")
	await frames(1)
	check("panel: Shake wraps the selection", str(panel.data["screens"][1]["text"]).begins_with("[shake]REC-7[/shake]"))
	panel.text_edit.select(0, 7, 0, 12)
	panel._wrap("[error]", "[/error]")
	check("panel: ERROR wraps the selection", str(panel.data["screens"][1]["text"]).begins_with("[shake]REC-7[/shake][error]") or
		str(panel.data["screens"][1]["text"]).contains("[error]"))
	check("panel: edits mark the scene unsaved", panel.dirty)
	panel.add_screen()
	check("panel: Add screen", panel.cur == 2 and (panel.data["screens"] as Array).size() == 5
		and str(panel.data["screens"][2]["id"]) == "s5")
	panel.move_screen(1)
	check("panel: Down moves the screen", panel.cur == 3 and str(panel.data["screens"][3]["id"]).begins_with("s"))
	panel.delete_screen()
	check("panel: Delete screen", (panel.data["screens"] as Array).size() == 4
		and not str(panel.data["screens"]).contains("s5"))
	panel._run_checks()
	check("panel: checks list shown in the dock", panel.checks.text.contains("No problems") or panel.checks.text.contains("note"))
	panel.open_file(SAMPLE)   # discard the test edits
	panel.select_screen(2)
	panel.replay_preview()
	await wait_s(0.4)
	print("   preview state: typing=%s clock=%.2f dur=%.2f voice=%s" % [panel.stage.is_typing(), panel.stage.clock, panel.stage.markup.duration, panel.stage.voice.playing])
	check("panel: preview stage plays the screen", panel.stage.playing and panel.stage.text_label.text.length() > 0)
	panel.stage.press()
	await frames(2)
	check("panel: preview shows the O2 countdown button", panel.stage.qte_active and is_instance_valid(panel.stage.qte_button))
	# map walkthrough + hold endings, main game UI / fade in (EXCURSION 1 PREP)
	check("panel: sample is a stage scene (Main game UI off, no fade)", not panel.ui_check.button_pressed and panel.fade_spin.value == 0.0)
	if panel.open_scene("excursion1_prep"):
		await frames(2)
		check("panel: excursion1_prep → Main game UI on, fade in 1.5 s", panel.ui_check.button_pressed and is_equal_approx(panel.fade_spin.value, 1.5))
		check("panel: excursion When it ends is NEXT", str(panel.data.get("after", "")) == "order:next")
		var has_next := false
		for i in panel.after_pick.item_count:
			if panel.after_pick.get_item_text(i) == "NEXT" and str(panel.after_pick.get_item_metadata(i)) == "order:next":
				has_next = true
		check("panel: When it ends offers NEXT", has_next)
		check("panel: Add menu is Chapter, Scene, or Subscene", panel.add_menu != null
			and panel.add_menu.get_item_text(0) == "Chapter" and panel.add_menu.get_item_text(1) == "Scene"
			and panel.add_menu.get_item_text(2) == "Subscene")
		check("panel: Chapter, Scene, On the list, Earlier, Later", panel.chapter_pick != null
			and panel.scene_outline_pick != null and panel.on_list != null
			and panel.outline_earlier.text == "Earlier" and panel.outline_later.text == "Later"
			and panel.chapter_pick.get_item_text(panel.chapter_pick.item_count - 1) == "New chapter…"
			and panel.scene_outline_pick.get_item_text(panel.scene_outline_pick.item_count - 1) == "New scene…")
		check("panel: brief is a subscene of PROLOGUE / INTRO", panel.on_list.button_pressed
			and panel.chapter_pick.get_item_text(panel.chapter_pick.selected) == "PROLOGUE"
			and panel.scene_outline_pick.get_item_text(panel.scene_outline_pick.selected) == "INTRO")
		var intro_ids := PackedStringArray()
		for ch in Order.chapters():
			if str(ch.get("title", "")) != "PROLOGUE":
				continue
			for sc in ch.get("scenes", []):
				if str(sc.get("title", "")) != "INTRO":
					continue
				for sub in sc.get("screens", []):
					var sid := str(sub.get("screen", ""))
					intro_ids.append(sid if sid != "" else str(sub.get("id", "")))
		var intro_lines := PackedStringArray()
		for t in panel.list_row_texts():
			var line := t.strip_edges()
			for sid in intro_ids:
				if line == sid or line.begins_with(sid + " ") or line.begins_with(sid + "  "):
					intro_lines.append(line)
					break
		var map_line := ""
		for line in intro_lines:
			if line.begins_with("map"):
				map_line = line
		check("panel: INTRO subscenes follow the outline", intro_lines.size() == intro_ids.size() and intro_ids.size() >= 1
			and (map_line == "" or map_line.ends_with("[map]")))
		check("panel: READY ROOM scene row is collapsible", "READY ROOM" in "\n".join(panel.list_row_texts()))
		var ready_i := -1
		for i in panel.scene_outline_pick.item_count:
			if panel.scene_outline_pick.get_item_text(i) == "READY ROOM":
				ready_i = i
		panel.scene_outline_pick.select(ready_i)
		panel._on_scene_picked(ready_i)
		await frames(1)
		var ready_sub := ""
		for ch in Order.chapters():
			if str(ch.get("title", "")) != "PROLOGUE":
				continue
			for sc in ch.get("scenes", []):
				if str(sc.get("title", "")) != "READY ROOM":
					continue
				var subs: Array = sc.get("screens", [])
				if not subs.is_empty():
					var sid := str(subs[0].get("screen", ""))
					ready_sub = sid if sid != "" else str(subs[0].get("id", ""))
		var ready_line := ""
		for t in panel.list_row_texts():
			var line := t.strip_edges()
			if ready_sub != "" and (line == ready_sub or line.begins_with(ready_sub + " ")):
				ready_line = line
		check("panel: READY ROOM lists its subscene from the outline", ready_sub != "" and ready_line.begins_with(ready_sub))
		var ready_row := -1
		for i in panel.screen_list.item_count:
			var meta = panel.screen_list.get_item_metadata(i)
			if meta is Dictionary and str(meta.get("kind", "")) == "scene" and str(meta.get("kind_row", "")) != "sub" and str(meta.get("scene", "")) == "READY ROOM":
				ready_row = i
				break
		panel._on_subscene_row(ready_row)
		await frames(1)
		var folded := true
		for t in panel.list_row_texts():
			var line := t.strip_edges()
			if ready_sub != "" and (line == ready_sub or line.begins_with(ready_sub + " ")):
				folded = false
		check("panel: clicking READY ROOM folds its subscene", ready_row >= 0 and folded)
		panel._on_subscene_row(ready_row)
		await frames(1)
		panel.scene_outline_pick.select(0)
		Order.memory_only = true
		Order.override_text = FileAccess.get_file_as_string("res://story/SCENE_ORDER.md")
		panel.chapter_pick.select(panel.chapter_pick.item_count - 1)
		panel.chapter_name.text = "CHAPTER 1"
		panel.scene_outline_pick.select(panel.scene_outline_pick.item_count - 1)
		panel.scene_name.text = "AIRLOCK"
		panel.on_list.button_pressed = false
		panel.on_list.button_pressed = true
		check("panel: On the list can place a screen under a new chapter", Order.override_text.contains("## CHAPTER 1")
			and Order.override_text.contains("### AIRLOCK")
			and Order.override_text.contains("scene:excursion1_prep/brief"))
		panel.add_chapter_named("CHAPTER 9")
		panel.add_chapter_named("CHAPTER 9")
		var ch9 := 0
		for line in Order.override_text.split("\n"):
			if line == "## CHAPTER 9":
				ch9 += 1
		check("panel: Add chapter appends it once and selects it", ch9 == 1
			and panel.chapter_pick.get_item_text(panel.chapter_pick.selected) == "CHAPTER 9"
			and "CHAPTER 9" in "\n".join(panel.list_row_texts()))
		panel.add_scene_named("DOCK")
		check("panel: Add scene puts DOCK under CHAPTER 9 and selects it", Order.override_text.contains("## CHAPTER 9")
			and Order.override_text.contains("### DOCK")
			and panel.scene_outline_pick.get_item_text(panel.scene_outline_pick.selected) == "DOCK")
		var menu_labels := PackedStringArray()
		for row in Order.menu_rows():
			menu_labels.append(str(row.get("label", "")))
		check("panel: an empty scene is not a debug-menu button", not menu_labels.has("DOCK") and menu_labels.has("INTRO") and menu_labels.has("READY ROOM"))
		panel.add_chapter_named("")
		check("panel: a blank chapter name does not add one", ch9 == 1)
		panel._apply_drop({"kind_row": "sub", "kind": "intro", "target": "intro:thaw", "chapter": "PROLOGUE", "scene": "INTRO"},
			{"kind_row": "sub", "kind": "scene", "target": "scene:excursion1_prep/map", "chapter": "PROLOGUE", "scene": "INTRO"}, true)
		check("panel: drag subscene places thaw after map", Order.next_after("scene:excursion1_prep/map") == "intro:thaw"
			and Order.next_after("intro:exam") == "scene:excursion1_prep/map")
		panel._apply_drop({"kind": "scene", "chapter": "PROLOGUE", "scene": "READY ROOM"},
			{"kind": "scene", "chapter": "PROLOGUE", "scene": "INTRO"}, false)
		var prologue_scenes := PackedStringArray()
		for ch in Order.chapters():
			if str(ch.get("title", "")) != "PROLOGUE":
				continue
			for sc in ch.get("scenes", []):
				prologue_scenes.append(str(sc.get("title", "")))
		check("panel: drag scene places READY ROOM before INTRO", prologue_scenes.size() >= 2
			and prologue_scenes[0] == "READY ROOM" and prologue_scenes.find("INTRO") > 0)
		panel._apply_drop({"kind": "chapter", "chapter": "CHAPTER 9"},
			{"kind": "chapter", "chapter": "PROLOGUE"}, false)
		check("panel: drag chapter places CHAPTER 9 first", str(Order.chapters()[0].get("title", "")) == "CHAPTER 9")
		var frozen := Order.override_text
		panel._apply_drop({"kind": "chapter", "chapter": "NOT ON THE LIST"}, {"kind": "chapter", "chapter": "PROLOGUE"}, false)
		check("panel: drag ignores rows that are not on the list", Order.override_text == frozen)
		check("panel: Undo button sits with Add and Delete", panel.undo_button != null and panel.undo_button.text == "Undo")
		panel._list_undo.clear()
		var undo_base := Order.override_text
		panel.add_chapter_named("UNDO CHAPTER")
		check("panel: add chapter shows on the list", Order.override_text.contains("## UNDO CHAPTER")
			and "UNDO CHAPTER" in "\n".join(panel.list_row_texts()))
		var kept_heading := str(panel._cur_screen().get("heading", ""))
		panel._cur_screen()["heading"] = kept_heading + "ZZ"
		panel.undo_list()
		check("panel: Undo restores the outline and the tree", Order.override_text == undo_base
			and not ("UNDO CHAPTER" in "\n".join(panel.list_row_texts())))
		check("panel: Undo does not revert screen text", str(panel._cur_screen().get("heading", "")) == kept_heading + "ZZ")
		panel._cur_screen()["heading"] = kept_heading
		var del_n := (panel.data["screens"] as Array).size()
		var del_id := str(panel.data["screens"][panel.cur].get("id", ""))
		panel.delete_screen()
		check("panel: delete takes the subscene off the file and the list", (panel.data["screens"] as Array).size() == del_n - 1
			and not Order.override_text.contains("scene:excursion1_prep/" + del_id))
		panel.undo_list()
		check("panel: Undo restores a deleted subscene", (panel.data["screens"] as Array).size() == del_n
			and str(panel.data["screens"][panel.cur].get("id", "")) == del_id
			and Order.override_text == undo_base)
		var add_n := (panel.data["screens"] as Array).size()
		panel.add_screen()
		check("panel: add subscene grows the file and the list", (panel.data["screens"] as Array).size() == add_n + 1
			and Order.override_text != undo_base)
		panel.undo_list()
		check("panel: Undo removes that subscene from the file and the list", (panel.data["screens"] as Array).size() == add_n
			and Order.override_text == undo_base)
		panel._apply_drop({"kind": "chapter", "chapter": "CHAPTER 9"}, {"kind": "chapter", "chapter": "PROLOGUE"}, true)
		check("panel: drag moved CHAPTER 9", str(Order.chapters()[0].get("title", "")) != "CHAPTER 9")
		panel.undo_list()
		check("panel: Undo restores a drag reorder", Order.override_text == undo_base
			and str(Order.chapters()[0].get("title", "")) == "CHAPTER 9")
		panel.add_chapter_named("UNDO KEY")
		var typed := Order.override_text
		panel.text_edit.grab_focus()
		await frames(1)
		var key := InputEventKey.new()
		key.keycode = KEY_Z
		key.physical_keycode = KEY_Z
		key.ctrl_pressed = true
		key.pressed = true
		panel._shortcut_input(key)
		check("panel: Ctrl+Z while typing does not undo the list", Order.override_text == typed)
		panel.screen_list.grab_focus()
		await frames(1)
		panel._shortcut_input(key)
		check("panel: Ctrl+Z on the list undoes the last list change", Order.override_text == undo_base)
		panel._list_undo.clear()
		for i in 21:
			panel.add_chapter_named("UNDO %02d" % i)
		check("panel: the list undo stack keeps 20", panel._list_undo.size() == 20)
		for i in 20:
			panel.undo_list()
		check("panel: twenty undos leave only the oldest add", Order.override_text.contains("## UNDO 00")
			and not Order.override_text.contains("## UNDO 01") and panel._list_undo.is_empty())
		panel.undo_list()
		check("panel: Undo with an empty stack leaves the list alone", Order.override_text.contains("## UNDO 00")
			and panel.status_label.text.contains("Nothing"))
		panel.dirty = false
		Order.memory_only = false
		Order.override_text = ""
		panel.open_scene("excursion1_prep")
		panel.select_screen(1)
		await frames(2)
		var tip_rows: int = panel.tour_box.get_child_count()
		check("panel: walkthrough ending shows 7 tip rows, walk-to READY ROOM, prompt",
			panel.end_mode.get_item_text(panel.end_mode.selected).begins_with("Map walkthrough") and panel.end_panels["map_tour"].visible
			and tip_rows == 7 and str(panel.tour_move.get_item_metadata(panel.tour_move.selected)) == "ready_room"
			and panel.tour_prompt.text == "Please proceed to the READY ROOM.")
		var row0: HBoxContainer = panel.tour_box.get_child(0)
		check("panel: tip row = number, target dropdown, text", (row0.get_child(0) as Label).text == "1/7"
			and str((row0.get_child(1) as OptionButton).get_item_metadata((row0.get_child(1) as OptionButton).selected)) == "map"
			and (row0.get_child(2) as LineEdit).text.begins_with("This is your TRM-CUFF Map."))
		check("panel: On arrival ops empty (the RESTRICTED stamp now waits for the lock click)", panel.tour_arrive.text == "")
		check("panel: not dirty after opening", not panel.dirty)
		panel.tour_arrive.text_changed.emit("map_restrict_room:stbd_hold, map_know_room:airlock")
		check("panel: editing On arrival writes a list", panel.data["screens"][1]["end"]["on_arrive"]
			== ["map_restrict_room:stbd_hold", "map_know_room:airlock"] and panel.dirty)
		panel.add_tip()
		await frames(1)
		check("panel: Add tip", (panel.data["screens"][1]["end"]["tips"] as Array).size() == 8 and panel.dirty)
		var hold_i := -1
		for i in (panel.data["screens"] as Array).size():
			if str(panel.data["screens"][i]["end"]["type"]) == "hold":
				hold_i = i
		if hold_i < 0:
			panel.select_screen((panel.data["screens"] as Array).size() - 1)
			panel._set_end_type("hold")
		else:
			panel.select_screen(hold_i)
		await frames(2)
		check("panel: hold ending panel", panel.end_panels["hold"].visible and not panel.end_panels["map_tour"].visible)
		var saw_expo := false
		var stack: Array = [panel]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is Button and (node as Button).text == "Exposition":
				saw_expo = true
			for child in node.get_children():
				stack.append(child)
		check("panel: Exposition sits with Bold and Italic", saw_expo)
		var saw_act := false
		stack = [panel]
		while not stack.is_empty():
			var node2: Node = stack.pop_back()
			if node2 is Button and (node2 as Button).text == "Interactable":
				saw_act = true
			for child in node2.get_children():
				stack.append(child)
		check("panel: Interactable control, default tag locker", saw_act and panel.act_id_edit.text == "locker")
		panel.select_screen(2)
		await frames(1)
		check("panel: ready room act is the locker container, suit, lantern, keycard rows", panel.act_box.get_child_count() == 3
			and bool(panel.data["screens"][2]["acts"]["locker"]["container"])
			and str(panel.data["screens"][2]["acts"]["locker"]["items"][0]["id"]) == "suit"
			and str(panel.data["screens"][2]["acts"]["locker"]["items"][1]["id"]) == "lantern"
			and str(panel.data["screens"][2]["acts"]["locker"]["items"][2]["id"]) == "airlock_keycard"
			and str(panel.act_text_edit.text).contains("The locker is in front of you")
			and str(panel.data["screens"][2]["acts"]["coffee"]["station"]) == "coffee")
		check("panel: Container box ticked, title / grid fields shown, Back note hidden, button says Add item",
			panel.act_container_check.button_pressed and panel.act_container_box.visible and panel.act_title_edit.text == "LOCKER"
			and int(panel.act_cols_spin.value) == 3 and int(panel.act_rows_spin.value) == 3 and not panel.act_back_note.visible
			and panel.act_add_button.text == "Add item")
		var item_row: Node = panel.act_box.get_child(0)
		check("panel: item row has id, label, hours, Required, detail",
			item_row.find_child("ItemId", true, false) != null and (item_row.find_child("ItemLabel", true, false) as LineEdit).text == "SUIT"
			and int((item_row.find_child("ItemHours", true, false) as SpinBox).value) == 1
			and not (item_row.find_child("ItemRequired", true, false) as CheckBox).button_pressed
			and (item_row.find_child("ItemDetail", true, false) as LineEdit).text.begins_with("Pressure suit."))
		(item_row.find_child("ItemDetail", true, false) as LineEdit).text_changed.emit("Needed to go outside.")
		panel.act_title_edit.text_changed.emit("LOCKER 1")
		panel.act_cols_spin.value = 4
		check("panel: editing detail / title / grid writes the data", str(panel.data["screens"][2]["acts"]["locker"]["items"][0]["detail"]) == "Needed to go outside."
			and str(panel.data["screens"][2]["acts"]["locker"]["title"]) == "LOCKER 1"
			and int(panel.data["screens"][2]["acts"]["locker"]["grid"]["cols"]) == 4)
		(item_row.find_child("ItemDetail", true, false) as LineEdit).text_changed.emit("Required to leave.")
		panel.act_title_edit.text_changed.emit("LOCKER")
		panel.act_cols_spin.value = 3
		var saw_back := false
		var note_stack: Array = [panel]
		while not note_stack.is_empty():
			var note_n: Node = note_stack.pop_back()
			if note_n is Label and str((note_n as Label).text).contains("Back is added automatically"):
				saw_back = true
			for child in note_n.get_children():
				note_stack.append(child)
		check("panel: Back is automatic and not an edited row", saw_back)
		var kept := str(panel.text_edit.text)
		var last: int = int(panel.text_edit.get_line_count()) - 1
		panel.text_edit.select(0, 0, last, panel.text_edit.get_line(last).length())
		panel._wrap("[act=locker]", "[/act]")
		check("panel: Interactable wraps the selection", str(panel.text_edit.text).begins_with("[act=locker]")
			and str(panel.text_edit.text).ends_with("[/act]"))
		panel.text_edit.text = kept
		panel._set_screen("text", kept)
		panel._add_act_action()
		check("panel: Add item writes a container item", (panel.data["screens"][2]["acts"]["locker"]["items"] as Array).size() == 4
			and str(panel.data["screens"][2]["acts"]["locker"]["items"][3]["actions"]) == "[\"take\"]")
		var actions: Array = panel.data["screens"][2]["acts"]["locker"]["items"]
		actions.pop_back()
		panel._rebuild_act_editor()
		check("panel: saved JSON keeps the container shape", SceneData.to_json(panel.data).contains("\"container\": true")
			and SceneData.to_json(panel.data).contains("\"items\"") and not SceneData.to_json(panel.data).contains("\"choices\""))
		# a plain function act on another screen: Back note + Add option, then convert to a container and back
		panel.select_screen(0)
		await frames(1)
		panel.act_id_edit.text = "crate"
		panel._add_act_action()
		await frames(1)
		var crate: Dictionary = panel.data["screens"][0]["acts"]["crate"]
		check("panel: a new act is a function: Back note shown, no container fields, Add option", not crate.has("container")
			and (crate["choices"] as Array).size() == 1 and panel.act_back_note.visible and not panel.act_container_box.visible
			and panel.act_add_button.text == "Add option" and not panel.act_container_check.button_pressed)
		panel.act_container_check.button_pressed = true
		await frames(1)
		crate = panel.data["screens"][0]["acts"]["crate"]
		check("panel: ticking Container converts the option to an item and shows the window fields", bool(crate["container"])
			and not crate.has("choices") and (crate["items"] as Array).size() == 1 and str(crate["items"][0]["label"]) == "Option"
			and panel.act_container_box.visible and not panel.act_back_note.visible and panel.act_box.get_child_count() == 1)
		panel.act_container_check.button_pressed = false
		await frames(1)
		crate = panel.data["screens"][0]["acts"]["crate"]
		check("panel: unticking converts back to a function (no data lost)", not crate.has("container") and not crate.has("items")
			and (crate["choices"] as Array).size() == 1 and panel.act_back_note.visible)
		(panel.data["screens"][0]["acts"] as Dictionary).erase("crate")
		if (panel.data["screens"][0]["acts"] as Dictionary).is_empty():
			(panel.data["screens"][0] as Dictionary).erase("acts")
		panel.act_id_edit.text = "locker"
		panel.select_screen(2)
		await frames(1)
		check("panel: ERROR level runs from Level 0 to Level 10", panel.error_level.get_item_text(0) == "Level 0"
			and panel.error_level.get_item_text(10) == "Level 10" and panel.error_level.item_count == 11)
		check("panel: default ERROR tag is unchanged", panel._error_open("") == "[error]" and panel._error_open("ERROR") == "[error=ERROR]")
		panel.error_level.select(10)
		panel.error_delay.value = 1.5
		check("panel: Level and delay are written into the tag", panel._error_open("DEMON") == "[error=DEMON level=10 delay=1.5]")
		panel.error_level.select(0)
		panel.error_delay.value = Markup.MORPH_HOLD
		panel.select_screen(0)
		panel._set_end_type("transition")
		panel.card_edit.text = "ONE HOUR LATER"
		panel.card_edit.text_changed.emit(panel.card_edit.text)
		check("panel: Transition card text and Then goes to", panel.end_mode.get_item_text(panel.end_mode.selected) == "Transition (time card)"
			and panel.end_panels["transition"].visible and str(panel.data["screens"][0]["end"]["card"]) == "ONE HOUR LATER"
			and str(panel.data["screens"][0]["end"]["goto"]) == "next")
		panel.replay_preview()
		await frames(2)
		var font: Font = panel.stage.card_label.get_theme_font("font")
		check("panel: time card uses the exam card font and is fading in", panel.stage.card.visible
			and panel.stage.card_label.text == "ONE HOUR LATER"
			and font != null and str(font.resource_path) == "res://assets/fonts/Oxanium-SemiBold.ttf"
			and panel.stage.card_label.modulate.a < 0.95)
		var stayed := int(panel.cur)
		panel.stage.press()
		await frames(2)
		check("panel: keys do nothing during the time card", panel.cur == stayed and panel.stage.card.visible)
		panel.stage._card_t = MemoryExam.CARD_FADE_IN + MemoryExam.CARD_HOLD + MemoryExam.CARD_FADE_OUT + MemoryExam.CARD_AFTER
		await frames(2)
		check("panel: the time card continues to the next subscene", panel.cur == stayed + 1)
		panel.select_screen(0)
		panel._set_end_type("map_tour")
		check("panel: switching an ending to Map walkthrough starts with one tip", str(panel.data["screens"][0]["end"]["type"]) == "map_tour"
			and (panel.data["screens"][0]["end"]["tips"] as Array).size() == 1)
		panel._set_end_type("hold")
		check("panel: switching to Hold", str(panel.data["screens"][0]["end"]["type"]) == "hold")
		panel.dirty = false   # discard (nothing saved)
	else:
		check("panel: opens excursion1_prep", false)
	# Double-click opens a JSON screen and saves first. Intro passages do not.
	var kept_text := str(panel.text_edit.text)
	panel.data["id"] = ""
	panel.dirty = true
	panel._open_listed_subscene({"kind": "scene", "id": "excursion1_prep", "screen": "brief", "target": "scene:excursion1_prep/brief"})
	check("panel: no id does not discard the open text", str(panel.data.get("id", "")) == "" and panel.text_edit.text == kept_text
		and panel.status_label.text.contains("no id"))
	panel.open_file(SAMPLE)
	panel.dirty = false
	panel.data["id"] = "zz_nav_test"
	panel.data["title"] = "ZZ NAV"
	panel.dirty = true
	panel._open_listed_subscene({"kind": "scene", "id": "excursion1_prep", "screen": "brief", "target": "scene:excursion1_prep/brief"})
	check("panel: double-click brief saves, then opens excursion1_prep", panel.data.get("id", "") == "excursion1_prep"
		and str(panel.data["screens"][panel.cur]["id"]) == "brief"
		and FileAccess.file_exists("res://story/scenes/zz_nav_test.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://story/scenes/zz_nav_test.json"))
	panel._open_listed_subscene({"kind": "intro", "id": "thaw", "target": "intro:thaw"})
	check("panel: double-click intro passage does not open a file", panel.data.get("id", "") == "excursion1_prep"
		and panel.status_label.text.contains("intro"))
	panel._open_listed_subscene({"kind": "scene", "id": "excursion1_prep", "screen": "map", "target": "scene:excursion1_prep/map"})
	check("panel: double-click map stays on excursion1_prep", panel.data.get("id", "") == "excursion1_prep"
		and str(panel.data["screens"][panel.cur]["id"]) == "map")
	# Script reload: old dock stays, new dropdown vars are null. Must not touch .selected on Nil,
	# and must rebuild Chapter / Scene plus the subscenes from the list.
	panel.chapter_pick = null
	panel.scene_outline_pick = null
	panel.on_list = null
	check("panel: missing chapter dropdown does not crash", panel._chosen_chapter() == "" and panel._chosen_scene() == "")
	panel._ensure_ui()
	await frames(2)
	var chs := []
	for i in panel.chapter_pick.item_count:
		chs.append(panel.chapter_pick.get_item_text(i))
	var blob := ""
	for i in panel.screen_list.item_count:
		blob += panel.screen_list.get_item_text(i) + "\n"
	check("panel: stale dock rebuilds Chapter = PROLOGUE and lists subscenes",
		panel.chapter_pick != null and chs.has("PROLOGUE") and panel.scene_outline_pick.item_count > 1
		and ("thaw" in blob or "brief" in blob or "ready_room" in blob))
	var amb_ok: bool = str(panel.amb_pick.get_item_text(0)) == "(game default)"
	for i in panel.amb_pick.item_count:
		var meta := str(panel.amb_pick.get_item_metadata(i))
		if meta != "" and not meta.begins_with("res://assets/sounds/ambiance/"):
			amb_ok = false
	check("panel: Ambience lists only assets/sounds/ambiance", amb_ok and panel.narr_pick.get_item_text(0) == "(no narration)")
	var src := "res://assets/sounds/zz_audio_drop.wav"
	var narr := "res://assets/sounds/narration/zz_audio_drop.wav"
	var amb := "res://assets/sounds/ambiance/zz_audio_drop.wav"
	var out := FileAccess.open(src, FileAccess.WRITE)
	out.store_string("x")
	out.close()
	panel._assign_dropped("narration", PackedStringArray([src]))
	check("panel: drop onto Narration copies into the folder and plays as the voice clip",
		FileAccess.file_exists(narr) and str(panel._cur_screen()["vo"]["clip"]) == narr
		and str(panel.narr_pick.get_item_metadata(panel.narr_pick.selected)) == narr)
	panel._assign_dropped("ambiance", PackedStringArray([src]))
	check("panel: drop onto Ambience copies into the ambiance folder",
		FileAccess.file_exists(amb) and str(panel.data.get("ambience", "")) == amb)
	for extra in [src, narr, amb, narr + ".import", amb + ".import", src + ".import"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(extra))
	Order.memory_only = false
	Order.override_text = ""
	panel.queue_free()
	await frames(2)


# ---------------------------------------------------------------- runtime

func spawn(path: String):
	var sc = (load(path) as PackedScene).instantiate()
	root.add_child(sc)
	current_scene = sc
	await frames(3)
	return sc


func stage_text() -> String:
	return pda.stage.text_label.text


func test_runtime() -> void:
	PdaScreen.next_authored = SAMPLE
	pda = await spawn(SceneData.RUNNER_SCENE)
	check("run: overlay up, PDA chrome hidden", pda.overlay.visible and not pda.safe_area.visible)
	check("run: first screen playing", pda.screen_index == 0 and pda.stage.playing and pda.stage.is_typing())
	check("run: title on the status line", pda.stage.status_label.text == "SAMPLE SCENE // SCENE WRITER DEMO")
	check("run: heading shown", pda.stage.heading_label.visible and pda.stage.heading_label.text == "Sample Scene")
	check("run: HUD O2 + minimap", pda.hud_o2 != null and pda.hud_map != null)
	await wait_s(0.6)
	check("run: typewriter partially typed", stage_text().length() > 5 and not stage_text().contains("Then nothing"))
	await key(KEY_SPACE)
	check("run: Space finishes the text", not pda.stage.is_typing() and stage_text().contains("Then nothing"))
	check("run: inline shake span", stage_text().contains("level=6 connected=1]knocks twice"))
	check("run: CONTINUE shown", pda.stage.continue_button.visible)
	check("run: no key hints on the stage", not stage_text().contains("SPACE") and not pda.stage.continue_button.text.contains("["))
	await key(KEY_SPACE)
	check("run: CONTINUE -> screen 2, no pin", pda.screen_index == 1 and not pda.stage.pin_label.visible)
	await key(KEY_SPACE)
	await wait_s(0.5)
	check("run: red static ~0.15", absf(pda.stage.red - 0.15) < 0.02 and pda.stage.fx.visible)
	check("run: ERROR glitch settled + name became ERROR", stage_text().contains("[color=%s][b]CORRUPTED[/b]" % AMBER)
		and stage_text().contains("[b]ERROR[/b]") and not stage_text().contains("ALEX"))
	check("run: 2 choices", pda.stage.choice_buttons.size() == 2)
	var choice_rect: Rect2 = pda.stage.choice_buttons[0].get_global_rect()
	await key(KEY_1)
	check("run: choice 1 -> vent screen", pda.screen_index == 2)
	check("run: pinned question + response", pda.stage.pin_label.visible and pda.stage.pin_label.text.contains("Do you want to continue?")
		and pda.stage.pin_label.text.contains("&gt; YES") or pda.stage.pin_label.text.contains("> YES"))
	check("run: choice ops ran", pda.has_flag("sample_said_yes"))
	check("run: VO clip loaded", pda.stage.voice.stream != null)
	await wait_s(0.3)
	check("run: whole-screen shake", stage_text().begins_with("[shake rate=18.0 level=3"))
	var red_early: float = pda.stage.red
	await key(KEY_SPACE)
	await frames(2)
	check("run: red ramp grows with the text (%.2f -> %.2f)" % [red_early, pda.stage.red], red_early < 0.3 and pda.stage.red > 0.5)
	check("run: O2 countdown button", pda.stage.qte_active and is_instance_valid(pda.stage.qte_button))
	await frames(2)
	var qr: Rect2 = pda.stage.qte_button.get_global_rect()
	check("run: countdown button = same size + place as choice 1 (%s vs %s)" % [qr, choice_rect],
		qr.position.distance_to(choice_rect.position) < 1.0 and qr.size.distance_to(choice_rect.size) < 1.0)
	check("run: countdown header", pda.stage.choices_header.text.begins_with("RESPONSE  //  WINDOW CLOSING"))
	await wait_s(1.0)
	check("run: O2 drains in steps", pda.o2_level < 100.0 and fmod(pda.o2_level, 5.0) < 0.01)
	pda.stage.qte_seek(0.05)
	await wait_s(0.3)
	check("run: too late -> death screen", pda.is_dead() and pda.death_message.text.contains("OXYGEN DEPLETED"))
	await wait_s(0.45)
	await key(KEY_SPACE)
	check("run: RETRY -> same screen again", not pda.is_dead() and pda.screen_index == 2 and pda.overlay.visible)
	await key(KEY_SPACE)
	await frames(2)
	await key(KEY_1)
	await wait_s(0.5)
	var sc = current_scene
	check("run: in time -> intro:home_bunk", sc != null and sc.get_script().resource_path == "res://scenes/intro.gd"
		and sc.current_id == &"home_bunk")
	check("run: flags carried to the intro", sc != null and sc.has_flag("sample_said_yes"))

	# death ending + RETRY target
	sc.queue_free()
	await frames(2)
	PdaScreen.next_screen = "file"
	PdaScreen.next_authored = SAMPLE
	pda = await spawn(SceneData.RUNNER_SCENE)
	check("run: next_screen opens the given screen", pda.screen_index == 1)
	await key(KEY_SPACE)
	await key(KEY_2)
	check("run: choice 2 -> death screen text, pin > NO", pda.screen_index == 3 and pda.stage.pin_label.text.contains("NO"))
	await key(KEY_SPACE)
	check("run: death waits a beat", not pda.is_dead())
	await wait_s(1.6)
	check("run: death screen with the written message", pda.is_dead() and pda.death_message.text == "SAMPLE ENDING // THE FILE WAS CLOSED"
		and pda.death_heading.text == "SIGNAL LOST")
	await wait_s(0.4)
	await key(KEY_ENTER)
	check("run: RETRY -> retry screen (file)", not pda.is_dead() and pda.screen_index == 1)
	if pda.dev_mode:
		await key(KEY_SPACE)
		await key(KEY_2)
		var before: int = pda.screen_index
		pda.dev_back()
		await frames(2)
		check("run: dev back returns to the previous screen", before == 3 and pda.screen_index == 1)

	# link: scene:<id>/<screen>
	pda.go_target("scene:excursion1_prep/map")
	await wait_s(0.4)
	pda = current_scene
	check("run: go_target scene:excursion1_prep/map", pda.get_script().resource_path == "res://templates/authored_scene.gd"
		and str(pda.current_screen().get("id", "")) == "map")
	pda.queue_free()
	await frames(2)
	# generic runner with next_authored (no built .tscn needed)
	PdaScreen.next_authored = SAMPLE
	pda = await spawn(SceneData.RUNNER_SCENE)
	check("run: generic runner plays next_authored", pda.screens.size() == 4 and pda.screen_index == 0)
	pda.queue_free()
	await frames(2)
