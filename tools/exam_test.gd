extends SceneTree
## Memory Examination Questions 2 + 3 (headless):
##   godot --headless --audio-driver Dummy --path . --script res://tools/exam_test.gd
## Covers: Q2 wrong answers → back to Q2, Insurance → know more YES/NO → Q3, both Q3 paths,
## every screen fits 960x540 without scrolling, final CONTINUE fades to black and holds,
## dev back (wheel up) through every new screen, cue data vs clip lengths, hooks,
## example icon squares (count, EX labels, gap under the finished text, never moving, art override),
## a UI-2 blip per square on BOTH example screens, the ONE HOUR LATER card + AFTER_EXAM hook.

var pda
var fails := 0
var passes := 0
var _hint_re := RegEx.create_from_string("\\[|\\bSPACE\\b|\\bESC\\b|\\bENTER\\b|\\bCLICK|\\bHOVER|\\bTABS\\b|\\bPRESS\\b|MAX \\d+ CHAR")
var yes_rect := Rect2()

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

func wheel_up() -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP
		e.pressed = pressed
		e.position = Vector2(480, 20)
		Input.parse_input_event(e)
		await process_frame
	await process_frame
	pda._dev_back_ms = 0   # allow the next flick straight away

func wait_s(sec: float) -> void:
	await create_timer(sec).timeout

func frames(n := 3) -> void:
	for _i in n:
		await process_frame

func skip() -> void:
	for _i in 6:
		if pda._thaw_phase != pda.ThawPhase.EXAM_VO:
			break
		await key(KEY_SPACE)
	await frames()

func pinned(q: String, r: String) -> bool:
	return pda.thaw_pin.visible and pda.thaw_pin.text.contains(q) and pda.thaw_pin.text.contains(r)

func body() -> String:
	return pda.thaw_text.get_parsed_text()

func stream_is(name: String) -> bool:
	return pda.voice_exam.stream != null and pda.voice_exam.stream.resource_path.ends_with(name)

func waiting() -> bool:
	return pda._thaw_phase == pda.ThawPhase.EXAM_WAIT and pda.exam_continue.visible

func choosing(n: int) -> bool:
	return pda._thaw_phase == pda.ThawPhase.EXAM_CHOICES and pda._thaw_choice_btns.size() == n

func _scan(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	var t := ""
	if n is Label:
		t = (n as Label).text
	elif n is Button:
		t = (n as Button).text
	elif n is RichTextLabel:
		t = (n as RichTextLabel).get_parsed_text()
	t = t.replace("SPACE MADNESS", "")   # David's script text, not a key name
	if t != "" and _hint_re.search(t) != null:
		out.append("%s: '%s'" % [n.name, t.substr(0, 50)])
	for c in n.get_children():
		_scan(c, out)

## The finished screen fits: no scrolling, buttons inside the 960x540 view, nothing clipped.
func fits(where: String) -> void:
	await frames(4)
	var vr: Rect2 = pda.get_viewport_rect()
	var text_h: float = pda.thaw_text.get_content_height()
	var scroll_h: float = pda.thaw_scroll.size.y
	var ok: bool = text_h <= scroll_h + 1.0 and pda.thaw_scroll.get_v_scroll_bar().max_value <= scroll_h + 1.0
	var bottom := 0.0
	for c: Control in [pda.exam_continue, pda.thaw_choices]:
		if c.is_visible_in_tree():
			bottom = maxf(bottom, c.get_global_rect().end.y)
	ok = ok and bottom <= vr.size.y - 20.0
	var off: Array = []
	_scan(pda, off)
	check("%s: fits 960x540 (text %.0f / %.0f px, bottom %.0f), no key hints %s" % [where, text_h, scroll_h, bottom,
		"" if off.is_empty() else str(off)], ok and off.is_empty())

func alphas() -> Array:
	var out: Array = []
	for sq: Control in pda._exam_icon_boxes:
		out.append(snappedf(sq.modulate.a, 0.01))
	return out

func at_rest() -> bool:
	for sq: Control in pda._exam_icon_boxes:
		if absf(sq.position.y) > 0.01:
			return false
	return true

## n equal squares labelled <prefix>1..n, even gaps, centred under the text, placed just under the
## FINISHED text (predicted height), clear of the minimap and inside the text area.
func icon_layout(where: String, n: int, prefix: String) -> void:
	await frames(3)
	var rects: Array = []
	var labels: Array = []
	for sq: Control in pda._exam_icon_boxes:
		rects.append((sq.get_parent() as Control).get_global_rect())
		var tag := sq.get_node("Tag") as Label
		labels.append(tag.text if tag.visible else "")
	var want: Array = []
	for i in n:
		want.append("%s%d" % [prefix, i + 1])
	var ok: bool = rects.size() == n and labels == want
	for r: Rect2 in rects:
		ok = ok and is_equal_approx(r.size.x, MemoryExam.ICON_SIZE)
	var gaps: Array = []
	for i in rects.size() - 1:
		gaps.append(snappedf((rects[i + 1] as Rect2).position.x - (rects[i] as Rect2).end.x, 0.5))
	for g in gaps:
		ok = ok and g == gaps[0] and g > 8.0
	var row := (rects[0] as Rect2).merge(rects[rects.size() - 1])
	var txt: Rect2 = pda.thaw_text.get_global_rect()
	var centred := absf(row.get_center().x - txt.get_center().x) < 1.0
	var map_left: float = pda.hud_map_frame.get_global_rect().position.x
	var gap: float = row.position.y - (txt.position.y + pda._exam_icon_final_text_h)
	var sq_ok: bool = (pda._exam_icon_boxes[0] as Control).size == Vector2(MemoryExam.ICON_SIZE, MemoryExam.ICON_SIZE)
	check("%s icons: %d x %.0f px squares labelled %s, gaps %s, centred, %.0f px under the finished text, clear of minimap (row %s)"
		% [where, n, MemoryExam.ICON_SIZE, str(labels), str(gaps), gap, str(row)],
		ok and sq_ok and centred and gap >= 8.0 and gap <= 12.0 and row.end.x < map_left - 8.0)

## Finished screen: small gap between the real last text line and the squares, no overlap, squares
## (at rest) fully inside the visible text area and above CONTINUE.
func icon_gap(where: String) -> void:
	await frames(3)
	var txt: Rect2 = pda.thaw_text.get_global_rect()
	var text_end: float = txt.position.y + pda.thaw_text.get_content_height()
	var row := (pda._exam_icon_boxes[0] as Control).get_global_rect()
	for sq: Control in pda._exam_icon_boxes:
		row = row.merge(sq.get_global_rect())
	var gap: float = row.position.y - text_end
	var scroll: Rect2 = pda.thaw_scroll.get_global_rect()
	var btn_top: float = pda.exam_continue.get_global_rect().position.y if pda.exam_continue.visible \
		else pda.thaw_choices.get_global_rect().position.y
	check("%s: squares %.0f px under the last text line (text ends %.0f, squares %.0f-%.0f), no overlap, above CONTINUE (%.0f)"
		% [where, gap, text_end, row.position.y, row.end.y, btn_top],
		gap >= 8.0 and gap <= 12.0 and absf(pda.thaw_text.get_content_height() - pda._exam_icon_final_text_h) < 0.5
		and row.end.y <= scroll.end.y + 0.5 and row.end.y < btn_top - 4.0)

func new_intro() -> void:
	if pda:
		pda.queue_free()
		await process_frame
	pda = load("res://scenes/intro.tscn").instantiate()
	root.add_child(pda)
	await frames(2)

## From the Q1 "Acknowledged, Operator." screen (as after YES).
func start_at_yes() -> void:
	await new_intro()
	pda._thaw_end_main()
	pda._thaw_stop_voice("test")
	pda._exam_open()
	pda._exam_started = true
	pda._exam_name = "ZED"
	pda._exam_question = "Please indicate that you understand."
	pda._exam_enter_yes()
	await frames()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# ---- data sanity: cues ordered and inside their clips ----
	var sets := [[MemoryExam.STREAM_Q2, MemoryExam.CUES_Q2], [MemoryExam.STREAM_KNOW_MORE, MemoryExam.CUES_KNOW_MORE],
		[MemoryExam.STREAM_Q3, MemoryExam.CUES_Q3], [MemoryExam.STREAM_GOOD, MemoryExam.CUES_GOOD],
		[MemoryExam.STREAM_FUNCTION, MemoryExam.CUES_FUNCTION_YES], [MemoryExam.STREAM_FUNCTION, MemoryExam.CUES_FUNCTION_NO], [MemoryExam.STREAM_COVERED, MemoryExam.CUES_COVERED],
		[MemoryExam.STREAM_NOT_COVERED, MemoryExam.CUES_NOT_COVERED], [MemoryExam.STREAM_NOT_COVERED, MemoryExam.CUES_SPACE_MADNESS],
		[MemoryExam.STREAM_SPECIAL, MemoryExam.CUES_SPECIAL],
		[MemoryExam.STREAM_COMPLETE, MemoryExam.CUES_COMPLETE], [MemoryExam.STREAM_DOCKED, MemoryExam.CUES_DOCKED]]
	for a: Dictionary in MemoryExam.Q2_ANSWERS:
		sets.append([a["stream"], a["cues"]])
	var bad: Array = []
	for s: Array in sets:
		var st := load(str(s[0])) as AudioStream
		if st == null:
			bad.append("missing " + str(s[0]))
			continue
		var prev := -1.0
		for c: Array in s[1]:
			if float(c[0]) < prev or float(c[2]) < float(c[0]) or float(c[2]) > st.get_length() + 0.05:
				bad.append("%s %s" % [str(s[0]).get_file(), str(c)])
			prev = float(c[2])
	check("data: 13 new clips load, cues ordered and inside their clip %s" % str(bad), bad.is_empty())

	# ---- Q1 YES → Q2 ----
	await start_at_yes()
	await frames()
	check("viewport is 960x540", pda.get_viewport_rect().size == Vector2(960, 540))
	await skip()
	check("Acknowledged → CONTINUE", waiting())
	pda.exam_continue.pressed.emit()
	await frames()
	check("Q2: new screen, heading + VO memorytest2", pda._exam_screen == 4 and stream_is("memorytest2.wav")
		and pda.voice_exam.playing and not pda.thaw_pin.visible)
	for _w in 20:   # "2)" types while the VO says "Question two," (0.0-0.82 s)
		if body().contains("2)"):
			break
		await wait_s(0.1)
	check("Q2: '2)' types with 'Question two' (at %.2f s)" % pda._thaw_t, body().begins_with("Memory Examination")
		and body().contains("2)") and not body().contains("Do you remember") and pda._thaw_t < 1.4)
	await skip()
	check("Q2: question + 3 answers", body().contains(MemoryExam.Q2_QUESTION) and choosing(3))
	var labels: Array = []
	for b: Button in pda._thaw_choice_btns:
		labels.append(b.text)
	check("Q2: answer labels in script order", labels == ["To make the universe a better place?",
		"Heavy machinery for mining colonies?", "Insurance?"])
	var b0: Button = pda._thaw_choice_btns[0]
	var same := true
	for b: Button in pda._thaw_choice_btns:
		same = same and is_equal_approx(b.size.x, b0.size.x) and is_equal_approx(b.size.y, 34.0) \
			and is_equal_approx(b.global_position.x, b0.global_position.x)
		var f := b.get_theme_font("font")
		same = same and f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x < b.size.x - 8.0
	check("Q2: buttons = choice buttons (34 px, same column), one width, labels not clipped (w=%.0f)" % b0.size.x,
		same and b0.theme_type_variation == &"ChoiceButton" and pda.thaw_choices_header.text == "RESPONSE")
	await fits("Q2 question")

	# ---- wrong answer 1 (key 1) ----
	await key(KEY_1)
	check("Q2 wrong 1: pinned question + > answer", pinned(MemoryExam.Q2_QUESTION, "> To make the universe a better place?")
		and stream_is("memorytest2A.wav") and pda.voice_exam.playing)
	check("Q2 wrong 1: counted", int(pda.vars.get("exam_q2_wrong", 0)) == 1)
	await wait_s(1.0)
	check("Q2 wrong 1: reply types with the VO", body().begins_with("While there is") and not body().contains("mission."))
	await skip()
	check("Q2 wrong 1: reply complete → CONTINUE", body().contains("this is not our primary mission.") and waiting())
	await fits("Q2 wrong 1")
	await key(KEY_SPACE)
	check("Q2 wrong 1 → back to Q2 (3 answers, no pin, no VO replay)", pda._exam_screen == 4 and choosing(3)
		and not pda.thaw_pin.visible and not pda.voice_exam.playing and body().contains(MemoryExam.Q2_QUESTION))
	# ---- wrong answer 2 (click) ----
	var btn2: Button = pda._thaw_choice_btns[1]
	btn2.pressed.emit()
	btn2.pressed.emit()   # double click: one answer
	await frames()
	check("Q2 wrong 2 (click): pinned + memorytest2B, counted once", pinned(MemoryExam.Q2_QUESTION,
		"> Heavy machinery for mining colonies?") and stream_is("memorytest2B.wav") and int(pda.vars["exam_q2_wrong"]) == 2)
	await skip()
	check("Q2 wrong 2: reply text", body().contains("Heavy machinery for mining colonies is not a product") and waiting())
	await fits("Q2 wrong 2")
	pda.exam_continue.pressed.emit()
	await frames()
	check("Q2 wrong 2 → Q2 again", choosing(3) and pda._exam_screen == 4)
	# ---- Insurance ----
	await key(KEY_3)
	check("Q2 Insurance: pinned + memorytest2C", pinned(MemoryExam.Q2_QUESTION, "> Insurance?") and stream_is("memorytest2C.wav")
		and pda.has_flag("exam_q2_correct") and int(pda.vars["exam_q2_wrong"]) == 2)
	# let the first clip end on its own, then the know-more clip plays on the same screen
	pda.voice_exam.seek(10.6)
	pda._thaw_t = 10.6
	await wait_s(0.5)
	check("Q2 Insurance: 'Correct. …' kept, know-more clip plays next", stream_is("wouldyouliketoknowmore.wav")
		and pda.voice_exam.playing and body().contains("Correct. The REC-7 Corporation provides premium insurance policies"))
	await skip()
	check("know more: question as its own paragraph + YES/NO", body().contains("known universe.\n\nWould you like to know more?")
		and choosing(2) and (pda._thaw_choice_btns[0] as Button).text == "YES")
	check("know more: YES/NO keep the 220x34 choice size", is_equal_approx(pda._thaw_choice_btns[0].size.x, 220.0)
		and is_equal_approx(pda._thaw_choice_btns[0].size.y, 34.0))
	yes_rect = (pda._thaw_choice_btns[0] as Button).get_global_rect()
	await fits("Q2 correct + know more")
	# ---- know more YES → placeholder → Q3 ----
	await key(KEY_1)
	check("know more YES: pinned + placeholder text", pinned("Would you like to know more?", "> YES")
		and pda.has_flag("exam_know_more"))
	await skip()
	check("know more YES: ARCHIVE FILE UNAVAILABLE, CONTINUE", body().contains("ARCHIVE FILE UNAVAILABLE") and waiting())
	await fits("know more placeholder")
	await key(KEY_ENTER)
	check("placeholder → Q3 (no pin), VO memorytest3", pda._exam_screen == 7 and stream_is("memorytest3.wav")
		and not pda.thaw_pin.visible)
	await skip()
	check("Q3: heading + '3) Do you remember your function…' + YES/NO", body().begins_with("Memory Examination")
		and body().contains(MemoryExam.Q3_QUESTION) and choosing(2))
	await fits("Q3 question")

	# ---- dev back through the new screens (wheel up) ----
	var hist: PackedStringArray = pda.dev_history_labels()
	check("dev history records every new screen %s" % str(hist), hist.has("EXAM Q2") and hist.has("EXAM Q2 (again)")
		and hist.has("EXAM Q2 > Insurance?") and hist.has("EXAM Q2 > KNOW MORE") and hist.has("EXAM Q3"))
	await wheel_up()
	check("dev back: Q3 → know-more placeholder", pinned("Would you like to know more?", "> YES") and pda._exam_screen == 6)
	await wheel_up()
	check("dev back: → Correct / know more (2C replays)", pinned(MemoryExam.Q2_QUESTION, "> Insurance?")
		and stream_is("memorytest2C.wav") and pda.voice_exam.playing)
	await wheel_up()
	check("dev back: → Q2 again (wrong count restored to 2)", pda._exam_screen == 4 and int(pda.vars["exam_q2_wrong"]) == 2)
	await wheel_up()
	check("dev back: → wrong 2 reply", pinned(MemoryExam.Q2_QUESTION, "> Heavy machinery") and int(pda.vars["exam_q2_wrong"]) == 2)
	await wheel_up()
	await wheel_up()
	check("dev back: → wrong 1 reply (count 1)", pinned(MemoryExam.Q2_QUESTION, "> To make the universe")
		and int(pda.vars["exam_q2_wrong"]) == 1)
	await wheel_up()
	check("dev back: → Q2 first time (count 0, VO)", pda._exam_screen == 4 and int(pda.vars.get("exam_q2_wrong", 0)) == 0
		and stream_is("memorytest2.wav") and pda.voice_exam.playing)
	await wheel_up()
	check("dev back: → Acknowledged, Operator.", pinned("Please indicate that you understand.", "> YES")
		and stream_is("memorytestA.wav"))

	# ---- Insurance → know more NO → Q3 pinned; Q3 YES path to the end ----
	await skip()
	await key(KEY_SPACE)
	await skip()
	await key(KEY_3)
	await skip()
	check("second run: know more YES/NO", choosing(2))
	await key(KEY_2)
	check("know more NO → Q3 pinned '> NO'", pda._exam_screen == 7 and pinned("Would you like to know more?", "> NO")
		and not pda.has_flag("exam_know_more"))
	await skip()
	check("Q3 under the pin: heading + question", body().contains(MemoryExam.Q3_QUESTION) and choosing(2))
	check("Q3 YES/NO in the same slot as the know-more YES/NO", (pda._thaw_choice_btns[0] as Button).get_global_rect().size == yes_rect.size)
	await fits("Q3 question (pinned > NO)")
	await key(KEY_1)
	check("Q3 YES: flag + pinned '3) …' / '> YES' + Good.", pda.has_flag("exam_remembered_function")
		and pinned("3) Do you remember your function", "> YES") and stream_is("good.wav"))
	pda.voice_exam.seek(0.6)
	pda._thaw_t = 0.6
	await frames(6)
	check("Q3 YES: Good. then memorytest3A on the same screen", stream_is("memorytest3A.wav") and body().begins_with("Good."))
	await skip()
	check("Q3 YES: 'Good. You are a CLAIM OPERATOR. … (CED) … payout.' one paragraph", body().begins_with("Good. You are a CLAIM OPERATOR.")
		and body().contains("missing cargo. You must assess whether CATASTROPHIC ECONOMIC DAMAGE (CED) has occurred,")
		and body().contains("massive monetary payout.\n\nWould you like to know more?"))
	check("Q3 YES screen ends with the know-more prompt + YES/NO (no CONTINUE)", choosing(2) and not pda.exam_continue.visible
		and body().ends_with("Would you like to know more?") and (pda._thaw_choice_btns[0] as Button).text == "YES")
	await fits("Q3 YES / function + know more")
	# ---- know more YES → covered examples (5 icons animate) ----
	await key(KEY_1)
	check("examples YES: covered screen pinned 'Would you like to know more?' / '> YES'", pinned("Would you like to know more?", "> YES")
		and stream_is("memorytestEXAMPLES_COVERED.wav") and pda.voice_exam.playing and pda.has_flag("exam_heard_examples"))
	check("covered: 5 icon squares, none shown yet", pda._exam_icon_row.visible and pda._exam_icon_boxes.size() == 5
		and alphas() == [0.0, 0.0, 0.0, 0.0, 0.0])
	await icon_layout("covered", 5, "EX1-")
	var row_y_start: float = pda._exam_icon_row.get_global_rect().position.y
	var sfx0: int = pda._exam_icon_sfx_count
	pda.voice_exam.seek(7.4)
	pda._thaw_t = 7.4
	await wait_s(0.75)
	var a1 := alphas()
	check("covered: square 1 appears with 'collisions…' (%s)" % str(a1), a1[0] > 0.5 and a1[1] == 0.0 and a1[4] == 0.0)
	check("covered: square 1 rising into place", (pda._exam_icon_boxes[0] as Control).position.y < MemoryExam.ICON_RISE)
	check("covered: one quiet techie blip (UI-2, Sfx bus, %.0f dB)" % MemoryExam.ICON_SFX_DB, pda._exam_icon_sfx_count == sfx0 + 1
		and pda._exam_icon_sfx.bus == &"Sfx" and pda._exam_icon_sfx.volume_db <= -10.0
		and pda._exam_icon_sfx.stream.resource_path.ends_with("UI-2.mp3"))
	pda.voice_exam.seek(13.1)
	pda._thaw_t = 13.1
	await wait_s(0.75)
	var a2 := alphas()
	check("covered: square 2 with 'fire and explosions' (%s)" % str(a2), a2[0] == 1.0 and a2[1] > 0.5 and a2[2] == 0.0
		and pda._exam_icon_sfx_count == sfx0 + 2)
	pda.voice_exam.seek(19.4)
	pda._thaw_t = 19.4
	await wait_s(0.75)
	var a4 := alphas()
	check("covered: square 4 with 'pirate action' (own square) (%s)" % str(a4), a4[3] > 0.5 and a4[4] == 0.0
		and pda._exam_icon_sfx_count == sfx0 + 3)
	var row_y_playing: float = pda._exam_icon_row.get_global_rect().position.y
	await skip()
	await frames(3)
	var row_y_done: float = pda._exam_icon_row.get_global_rect().position.y
	check("covered: squares never move (start %.0f, typing %.0f, CONTINUE shown %.0f)" % [row_y_start, row_y_playing, row_y_done],
		absf(row_y_playing - row_y_done) < 0.5 and absf(row_y_start - row_y_done) < 0.5)
	check("covered: skip → all 5 squares in final place, no burst of blips", alphas() == [1.0, 1.0, 1.0, 1.0, 1.0] and at_rest()
		and pda._exam_icon_sfx_count == sfx0 + 3)
	check("covered: text complete → CONTINUE", body().begins_with("Examples of incidents covered") and body().ends_with("undocumented disease or infection.") and waiting())
	await icon_gap("covered")
	await fits("covered (5 icons)")
	# ---- NOT covered examples ----
	await key(KEY_SPACE)
	check("not_covered: new screen, no pin, clip memorytestEXAMPLES_NOT_COVERED 0-%.2f s" % MemoryExam.NOT_COVERED_SPLIT,
		stream_is("memorytestEXAMPLES_NOT_COVERED.wav") and pda.voice_exam.playing and not pda.thaw_pin.visible
		and is_equal_approx(pda._thaw_len, MemoryExam.NOT_COVERED_SPLIT))
	check("not_covered: 4 squares, reset", pda._exam_icon_row.visible and alphas() == [0.0, 0.0, 0.0, 0.0])
	# The bug David heard: arriving from the long covered clip (~25 s), the squares were set up on
	# the OLD clock, all counted as already shown, so B never played a blip.
	check("not_covered: arriving after the long covered screen, no square counted as shown yet (%s)" % str(pda._exam_icon_shown),
		pda._exam_icon_shown == [false, false, false, false] and pda._thaw_t < 1.0)
	await icon_layout("not_covered", 4, "EX2-")
	var nrow_y_start: float = pda._exam_icon_row.get_global_rect().position.y
	var sfx_b0: int = pda._exam_icon_sfx_count
	var b_times: Array = MemoryExam.ICON_TIMES_NOT_COVERED
	for bi in b_times.size():
		# play the clip into each square's cue (a little before it, like the covered screen)
		var from_t := float(b_times[bi]) - 0.3
		pda.voice_exam.seek(from_t)
		pda._thaw_t = from_t
		var heard := false
		for _f in 90:
			await process_frame
			if pda._exam_icon_sfx_count > sfx_b0 + bi:
				heard = pda._exam_icon_sfx.playing
				break
		check("not_covered: square %d plays ONE UI-2 blip in time with the VO (count %d, playing %s, VO t=%.2f)" % [bi + 1,
			pda._exam_icon_sfx_count - sfx_b0, heard, pda._thaw_t],
			pda._exam_icon_sfx_count == sfx_b0 + bi + 1 and heard and pda.voice_exam.playing
			and pda._exam_icon_sfx.stream.resource_path.ends_with("UI-2.mp3") and pda._exam_icon_shown[bi]
			and (bi + 1 >= b_times.size() or not pda._exam_icon_shown[bi + 1]))
		await wait_s(0.15)
		check("not_covered: square %d fading in with its blip (a=%.2f)" % [bi + 1, alphas()[bi]], alphas()[bi] > 0.05)
	await wait_s(0.5)
	check("not_covered: 4 squares, 4 blips (no extra)", pda._exam_icon_sfx_count == sfx_b0 + 4 and alphas() == [1.0, 1.0, 1.0, 1.0])
	await skip()
	check("not_covered: text ends at 'recorded.' (NOTE split off), all 4 squares", body().begins_with("Examples of incidents NOT covered")
		and body().ends_with("unrecorded or recorded.") and not body().contains("NOTE") and alphas() == [1.0, 1.0, 1.0, 1.0]
		and waiting() and not pda.voice_exam.playing)
	check("not_covered: squares never move (start %.0f, CONTINUE shown %.0f)" % [nrow_y_start, pda._exam_icon_row.get_global_rect().position.y],
		absf(nrow_y_start - pda._exam_icon_row.get_global_rect().position.y) < 0.5)
	await icon_gap("not_covered")
	await fits("not_covered (4 icons)")
	# ---- SPACE MADNESS (continuation from YES: no pin) ----
	await key(KEY_SPACE)
	check("space_madness: continuation, no pin, same clip from %.2f s, no icons" % MemoryExam.NOT_COVERED_SPLIT,
		stream_is("memorytestEXAMPLES_NOT_COVERED.wav") and pda.voice_exam.playing and not pda.thaw_pin.visible
		and pda._thaw_t >= MemoryExam.NOT_COVERED_SPLIT - 0.05 and not pda._exam_icon_row.visible)
	await skip()
	check("space_madness: NOTE … SPACE MADNESS … denied. → CONTINUE", body().begins_with("NOTE: The REC-7 corporation")
		and body().ends_with("will be denied.") and waiting())
	await fits("space_madness")
	var tail_checks := [
		["special_note", "specialnotforclaimoperator.wav", "SPECIAL NOTE FOR CLAIM OPERATOR:", "Do your best, OPERATOR."],
		["complete", "memorytestcomplete.wav", "Memory Test Complete. Congratulations.", "acceptable parameters."],
		["docked", "endintromessage.wav", "We are docked in position", "scheduled to take place in one hour."],
	]
	for tc: Array in tail_checks:
		await key(KEY_SPACE)
		check("%s: new screen, no pin, VO %s" % [tc[0], tc[1]], stream_is(tc[1]) and pda.voice_exam.playing
			and not pda.thaw_pin.visible)
		await skip()
		check("%s: text complete → CONTINUE" % tc[0], body().contains(tc[2]) and body().ends_with(tc[3]) and waiting())
		await fits(tc[0])
	# ---- final CONTINUE → fade to black ----
	var amb0: float = pda.ambience.volume_db
	pda.after_exam_dry_run = true   # stop at the hook instead of loading the next chapter
	await key(KEY_SPACE)
	var t_black := Time.get_ticks_msec()
	check("final CONTINUE → fade starts", pda._thaw_phase == pda.ThawPhase.EXAM_BLACK and pda._exam_black.visible
		and pda._exam_black.modulate.a < 0.5)
	check("exam flags: exam_complete + exam_done, vars", pda.has_flag("exam_complete") and pda.has_flag("exam_done")
		and int(pda.vars["exam_q2_wrong"]) == 0 and str(pda.vars["callsign"]) == "OPERATOR")
	await wait_s(0.9)
	var mid: float = pda._exam_black.modulate.a
	check("fade in progress at 0.9 s (a=%.2f)" % mid, mid > 0.2 and mid < 0.9)
	await wait_s(1.3)
	check("black after ~2 s, over everything (HUD too), ambience faded", is_equal_approx(pda._exam_black.modulate.a, 1.0)
		and pda._exam_black.get_index() > pda.thaw.get_index() and pda.ambience.volume_db < amb0 - 30.0)
	check("no time card yet during the black hold", pda._exam_card == null or not pda._exam_card.visible
		or pda._exam_card.modulate.a < 0.05)
	await key(KEY_SPACE)
	await key(KEY_1)
	await key(KEY_M)
	# ---- ONE HOUR LATER card, then AFTER_EXAM (scene:excursion1_prep) ----
	var card_in := MemoryExam.FADE_BLACK_SECONDS + MemoryExam.AFTER_EXAM_HOLD   # card starts fading in
	var card_full := card_in + MemoryExam.CARD_FADE_IN
	var card_out := card_full + MemoryExam.CARD_HOLD
	var card_gone := card_out + MemoryExam.CARD_FADE_OUT
	await wait_s(maxf(0.0, card_in + MemoryExam.CARD_FADE_IN * 0.5 - (Time.get_ticks_msec() - t_black) / 1000.0))
	var a_mid: float = pda._exam_card.modulate.a if pda._exam_card else -1.0
	check("card fading in at %.1f s (a=%.2f)" % [card_in + MemoryExam.CARD_FADE_IN * 0.5, a_mid], a_mid > 0.15 and a_mid < 0.9)
	await wait_s(maxf(0.0, card_full + 0.2 - (Time.get_ticks_msec() - t_black) / 1000.0))
	var card: Label = pda._exam_card
	var cr := card.get_global_rect() if card else Rect2()
	var font_ok := card != null and card.get_theme_font("font").resource_path.ends_with("Oxanium-SemiBold.ttf")
	check("'ONE HOUR LATER' fully shown, centred on the black, title font, keys ignored",
		card != null and card.visible and card.text == "ONE HOUR LATER" and card.modulate.a > 0.95
		and card.is_visible_in_tree() and absf(cr.get_center().x - 480.0) < 2.0 and absf(cr.get_center().y - 270.0) < 2.0
		and card.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and card.vertical_alignment == VERTICAL_ALIGNMENT_CENTER
		and font_ok and pda._thaw_phase == pda.ThawPhase.EXAM_BLACK and not pda.map_overlay.visible and pda.exam_left_to == "")
	check("card is restrained (%d px, dim green)" % card.get_theme_font_size("font_size"), card.get_theme_font_size("font_size") <= 28
		and card.get_theme_color("font_color").g < 0.9)
	check("card holds %.1f s (2-2.5 s)" % MemoryExam.CARD_HOLD, MemoryExam.CARD_HOLD >= 2.0 and MemoryExam.CARD_HOLD <= 2.5)
	await wait_s(maxf(0.0, card_out - 0.2 - (Time.get_ticks_msec() - t_black) / 1000.0))
	check("card still fully shown just before its fade out (a=%.2f)" % card.modulate.a, card.modulate.a > 0.95)
	await wait_s(maxf(0.0, card_out + MemoryExam.CARD_FADE_OUT * 0.5 - (Time.get_ticks_msec() - t_black) / 1000.0))
	check("card fading out (a=%.2f)" % card.modulate.a, card.modulate.a < 0.85 and card.modulate.a > 0.05 and pda.exam_left_to == "")
	await wait_s(maxf(0.0, card_gone + MemoryExam.CARD_AFTER + 0.3 - (Time.get_ticks_msec() - t_black) / 1000.0))
	check("after the card: AFTER_EXAM → scene:excursion1_prep (black stays until the chapter fades in)",
		pda.exam_left_to == "scene:excursion1_prep" and MemoryExam.AFTER_EXAM == "scene:excursion1_prep"
		and not card.visible and pda._exam_black.visible and pda._exam_black.modulate.a > 0.99)
	# ---- dev back from the black ----
	await wheel_up()
	check("dev back: black → docked screen (VO, black gone, ambience back)", not pda._exam_black.visible
		and stream_is("endintromessage.wav") and pda.voice_exam.playing and pda.ambience.volume_db > amb0 - 30.0)
	for id: String in ["complete", "special_note", "space_madness"]:
		await wheel_up()
		check("dev back: → %s" % id, pda._exam_screen == 10 + pda._tail_index(id) and not pda.thaw_pin.visible)
	await wheel_up()
	check("dev back: → not_covered, VO replays, squares in final state", pda._exam_screen == 10 + pda._tail_index("not_covered")
		and pda.voice_exam.playing and pda._thaw_t < 3.0 and alphas() == [1.0, 1.0, 1.0, 1.0])
	await wheel_up()
	check("dev back: → covered (pinned > YES), 5 squares in final state", pda._exam_screen == 10 + pda._tail_index("covered")
		and pinned("Would you like to know more?", "> YES") and alphas() == [1.0, 1.0, 1.0, 1.0, 1.0] and at_rest())
	await wheel_up()
	check("dev back: → Q3 YES screen (pinned, Good.), icons gone", pinned("3) Do you remember your function", "> YES")
		and stream_is("good.wav") and not pda._exam_icon_row.visible)
	await wheel_up()
	check("dev back: → Q3 question (flag cleared)", pda._exam_screen == 7 and not pda.has_flag("exam_remembered_function"))

	# ---- Q3 NO path; know more NO → SPACE MADNESS pinned ----
	await skip()
	await key(KEY_2)
	check("Q3 NO: pinned '> NO', no Good., straight into memorytest3A", pinned("3) Do you remember your function", "> NO")
		and stream_is("memorytest3A.wav") and not pda.has_flag("exam_remembered_function"))
	await skip()
	check("Q3 NO: 'You are a CLAIM OPERATOR.' (no Good.), no '(CED)', know-more prompt", body().begins_with("You are a CLAIM OPERATOR.")
		and body().contains("ECONOMIC DAMAGE has occurred") and not body().contains("(CED)")
		and body().ends_with("Would you like to know more?") and choosing(2))
	await fits("Q3 NO / function + know more")
	await key(KEY_2)
	check("examples NO → SPACE MADNESS pinned 'Would you like to know more?' / '> NO'", pda._exam_screen == 10 + pda._tail_index("space_madness")
		and pinned("Would you like to know more?", "> NO") and stream_is("memorytestEXAMPLES_NOT_COVERED.wav")
		and pda._thaw_t >= MemoryExam.NOT_COVERED_SPLIT - 0.05 and not pda.has_flag("exam_heard_examples")
		and not pda._exam_icon_row.visible)
	await skip()
	check("SPACE MADNESS (from NO): NOTE … denied. → CONTINUE", body().begins_with("NOTE:") and body().ends_with("will be denied.") and waiting())
	await fits("space_madness (pinned > NO)")
	await key(KEY_SPACE)
	check("SPACE MADNESS → special note", stream_is("specialnotforclaimoperator.wav") and not pda.thaw_pin.visible)
	await wheel_up()
	check("dev back: special note → SPACE MADNESS keeps its '> NO' pin", pinned("Would you like to know more?", "> NO"))

	# ---- icon art: ICON_ART path / icons dir convention replace the placeholder ----
	var none_art := true
	for id: String in MemoryExam.ICON_ART.keys():
		none_art = none_art and pda.exam_icon_art_path(id) == ""
	check("icon art: 9 ids (EX1-1..5, EX2-1..4) in ICON_ART, none set / no files yet → placeholders",
		MemoryExam.ICON_ART.size() == 9 and none_art and MemoryExam.ICONS_COVERED.size() == MemoryExam.ICON_TIMES_COVERED.size()
		and MemoryExam.ICONS_NOT_COVERED.size() == MemoryExam.ICON_TIMES_NOT_COVERED.size())
	var art_dir := "user://exam_icons_test"
	DirAccess.make_dir_recursive_absolute(art_dir)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	img.save_png(art_dir.path_join("custom_art.png"))
	img.save_png(art_dir.path_join("EX2-3.png"))
	pda.icon_art["EX1-2"] = art_dir.path_join("custom_art.png")
	pda._tail_show(pda._tail_index("covered"), true)
	await frames(4)
	var art_sq := pda._exam_icon_boxes[1] as Panel
	var plain_sq := pda._exam_icon_boxes[0] as Panel
	check("icon art (ICON_ART path): EX1-2 shows the texture, label + placeholder box hidden; EX1-1 stays a placeholder",
		(art_sq.get_node("Icon") as TextureRect).visible and (art_sq.get_node("Icon") as TextureRect).texture != null
		and not (art_sq.get_node("Tag") as Label).visible and art_sq.get_theme_stylebox("panel") is StyleBoxEmpty
		and (plain_sq.get_node("Tag") as Label).visible and not (plain_sq.get_node("Icon") as TextureRect).visible
		and plain_sq.get_theme_stylebox("panel") is StyleBoxFlat)
	pda.icon_art_dir = art_dir
	pda._tail_show(pda._tail_index("not_covered"), true)
	await frames(4)
	var conv_sq := pda._exam_icon_boxes[2] as Panel
	check("icon art (file convention <icons dir>/EX2-3.png): picked up automatically, label hidden",
		pda.exam_icon_art_path("EX2-3").ends_with("EX2-3.png") and (conv_sq.get_node("Icon") as TextureRect).texture != null
		and not (conv_sq.get_node("Tag") as Label).visible and (pda._exam_icon_boxes[3].get_node("Tag") as Label).visible)
	pda.icon_art = MemoryExam.ICON_ART.duplicate()
	pda.icon_art_dir = MemoryExam.ICON_ART_DIR
	for f in ["custom_art.png", "EX2-3.png"]:
		DirAccess.remove_absolute(art_dir.path_join(f))
	DirAccess.remove_absolute(art_dir)

	# ---- hooks ----
	pda._tail_show(pda._tail_index("docked"), true)
	await frames()
	pda.after_exam_target = "home_bunk"
	pda.after_exam_dry_run = false
	await key(KEY_SPACE)
	await wait_s(MemoryExam.FADE_BLACK_SECONDS + MemoryExam.AFTER_EXAM_HOLD + MemoryExam.CARD_FADE_IN
		+ MemoryExam.CARD_HOLD + MemoryExam.CARD_FADE_OUT + MemoryExam.CARD_AFTER + 1.2)
	check("AFTER_EXAM hook (set to home_bunk): leaves the black into the passage", pda.current_id == &"home_bunk"
		and not pda.thaw.visible and pda.safe_area.visible and not pda._exam_black.visible)
	if ResourceLoader.exists("res://tools/test_assets/exam_test.ogv"):
		await start_at_yes()
		pda.know_more_video = "res://tools/test_assets/exam_test.ogv"
		pda._exam_debug_q23("archive", false)
		await frames(4)
		check("KNOW_MORE_VIDEO hook: video plays in the text area, CONTINUE shown", pda._exam_video != null
			and pda._exam_video.is_playing() and pda._exam_video.is_visible_in_tree() and not pda.thaw_scroll.visible
			and waiting() and pinned("Would you like to know more?", "> YES"))
		await key(KEY_SPACE)
		check("video: CONTINUE → Q3, video stopped", pda._exam_screen == 7 and not pda._exam_video.visible and pda.thaw_scroll.visible)
	else:
		print("SKIP video hook test (no res://tools/test_assets/exam_test.ogv)")
	# ---- NO4 recovery path also continues into Q2 ----
	await new_intro()
	pda._thaw_end_main()
	pda._thaw_stop_voice("test")
	pda._exam_dbg = {"exam_screen": "recover", "exam_o2": "5"}
	pda._exam_debug_entry()
	await frames()
	await skip()
	await wait_s(1.2)
	check("recovery → CONTINUE", waiting())
	await key(KEY_SPACE)
	check("recovery → Q2", pda._exam_screen == 4 and stream_is("memorytest2.wav"))
	print("DONE fails=%d passes=%d" % [fails, passes])
	quit(fails)
