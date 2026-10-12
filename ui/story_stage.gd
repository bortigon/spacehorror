@tool
class_name StoryStage
extends Control
## SCENE WRITER STAGE: plays ONE screen of a Scene Writer scene — pinned question/response,
## heading, typewriter text with [error]/[shake]/[pause] effects, whole-screen shake, red edges
## (off / static / ramp over the text), VO with cue lines, SFX, and the ending (CONTINUE,
## choices, or the O2 countdown button). Death endings are shown by the owner (typing_done),
## and so is the map walkthrough ("map_tour"). "hold" shows nothing (or CONTINUE when the
## owner passes opts.hold_next = true).
##
## Same layout as the intro's STASIS THAW / MEMORY EXAMINATION overlay. Used by
## templates/authored_scene.gd in game and by the Scene Writer preview in the editor.
## The stage never shows key hints; choices / countdown share one slot and one button size.

signal typing_done
signal continue_pressed
signal choice_pressed(index: int)
signal qte_pressed
signal qte_expired
signal qte_tick(left: float)      # 1 → 0 while the O2 countdown runs
signal action_taken(act_id: String, action: Dictionary)

const Markup := preload("res://ui/story_markup.gd")
const SceneData := preload("res://ui/story_scene.gd")

const TEXT_COLOR := Color(0.56, 0.8, 0.6)
const HEADING_COLOR := Color("#cfe8d4")
const PIN_QUESTION_COLOR := "#5f8f69"
const PIN_RESPONSE_COLOR := "#dff7e2"
const ERROR_COLOR := Color("#e07040")
const MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"
const MONO_BOLD := "res://assets/fonts/IBMPlexMono-SemiBold.ttf"
const HEADING_FONT := "res://assets/fonts/Oxanium-SemiBold.ttf"
const SHADER := "res://shaders/suffocate.gdshader"
const HEART_SFX := "res://assets/sounds/UI-1.mp3"
const RESPONSE_HEADER := "RESPONSE"
const QTE_HEADER := "RESPONSE  //  WINDOW CLOSING  %.1fs"
const CONTINUE_LABEL := "CONTINUE"
const BUTTON_SIZE := Vector2(220, 34)
const RED_FADE := 0.8            # red edges fade out at this rate on a screen with red "off"
const QTE_RED_END := 1.0
const BEAT_SLOW := 1.05
const BEAT_FAST := 0.42

var status_label: Label
var pin_label: RichTextLabel
var heading_label: Label
var scroll: ScrollContainer
var text_label: RichTextLabel
var choices_box: VBoxContainer
var choices_header: Label
var continue_button: Button
var fx: ColorRect
var card: ColorRect
var card_label: Label
var voice: AudioStreamPlayer
var heart: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []

var screen: Dictionary = {}
var markup: RefCounted            # StoryMarkup
var clock := 0.0                  # screen clock (VO clip seconds when cues are used)
var clock_start := 0.0
var wall := 0.0
var playing := false
var paused := false
var frozen := false               # debug/preview: hold the clock
var ending_shown := false
var red := 0.0                    # red edge amount now (0..1), carried between screens
var suffocate := 0.0              # desaturate / vignette amount (O2 countdown)
var shake_level := 0
var audio_enabled := true
var base_speed := 40.0
var text_filter: Callable         # raw text → text (the game fills {v:..} / {flag:..})
var choice_filter: Callable       # choice → bool (the game checks "if")

var qte_active := false
var qte_total := 10.0
var qte_left := 0.0
var qte_button: Button
var _qte_fill: ColorRect
var _qte_bar: ColorRect
var _qte_red0 := 0.0
var _beat_t := 0.0
var _dub_t := -1.0
var _pulse := 0.0

var embedded := false             # inside the main game UI (no margins / status line)
var hold_next := false            # "hold" ending shows CONTINUE (the scene has a next target)
var _box: MarginContainer
var _rule: HSeparator

var choice_buttons: Array[Button] = []
var _choice_index: Array[int] = []
var _sfx_events: Array = []       # [[time, stream, fired], ...]
var _use_voice_clock := false
var _vo_to := -1.0
var _last_bb := ""
var _stream_cache: Dictionary = {}
var _card_t := -1.0
var _card_sent := false
var _meta_click := ""
var act_done: Dictionary = {}
var act_is_done: Callable
var act_hours_live := false
## Callable(act_id: String, spec: Dictionary): the owner shows a container act as a window
## (templates/pda_screen.gd). Without one (the Scene Writer preview) a container reads as the old
## function: its text, one option per item, and Back.
var container_handler: Callable
var _act_stack: Array[String] = []
var _in_act := false
var _unwritten := ""


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var box := MarginContainer.new()
	box.name = "StageBox"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("margin_left", 112)
	box.add_theme_constant_override("margin_top", 34)
	box.add_theme_constant_override("margin_right", 310)
	box.add_theme_constant_override("margin_bottom", 40)
	add_child(box)
	_box = box
	var col := VBoxContainer.new()
	col.name = "StageCol"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)

	status_label = Label.new()
	status_label.name = "Status"
	status_label.theme_type_variation = &"OsLabelDim"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status_label)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	_rule = rule

	var mono: Font = load(MONO) if ResourceLoader.exists(MONO) else null
	var mono_b: Font = load(MONO_BOLD) if ResourceLoader.exists(MONO_BOLD) else mono
	pin_label = _rtl("Pin")
	pin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin_label.hide()
	col.add_child(pin_label)

	heading_label = Label.new()
	heading_label.name = "Heading"
	if ResourceLoader.exists(HEADING_FONT):
		heading_label.add_theme_font_override("font", load(HEADING_FONT))
	heading_label.add_theme_font_size_override("font_size", 20)
	heading_label.add_theme_color_override("font_color", HEADING_COLOR)
	heading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading_label.hide()
	col.add_child(heading_label)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # no editor-theme panel in the preview
	col.add_child(scroll)
	text_label = _rtl("Text")
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(text_label)
	text_label.meta_clicked.connect(_on_text_meta)
	for r: RichTextLabel in [pin_label, text_label]:
		if mono:
			r.add_theme_font_override("normal_font", mono)
		if mono_b:
			r.add_theme_font_override("bold_font", mono_b)

	choices_box = VBoxContainer.new()
	choices_box.name = "Choices"
	choices_box.add_theme_constant_override("separation", 6)
	choices_box.hide()
	col.add_child(choices_box)
	choices_header = Label.new()
	choices_header.name = "ChoicesHeader"
	choices_header.theme_type_variation = &"OsLabelDim"
	choices_header.text = RESPONSE_HEADER
	choices_box.add_child(choices_header)

	continue_button = Button.new()
	continue_button.name = "Continue"
	continue_button.text = CONTINUE_LABEL
	continue_button.custom_minimum_size = Vector2(220, 38)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	continue_button.focus_mode = Control.FOCUS_NONE
	continue_button.pressed.connect(func() -> void:
		if playing and ending_shown and not paused:
			continue_pressed.emit())
	continue_button.hide()
	col.add_child(continue_button)

	fx = ColorRect.new()
	fx.name = "Fx"
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER)
		fx.material = mat
	fx.hide()
	add_child(fx)

	card = ColorRect.new()
	card.name = "TimeCard"
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.color = Color.BLACK
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.hide()
	add_child(card)
	card_label = Label.new()
	card_label.name = "TimeCardLabel"
	card_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MemoryExam.CARD_FONT):
		card_label.add_theme_font_override("font", load(MemoryExam.CARD_FONT))
	card_label.add_theme_font_size_override("font_size", MemoryExam.CARD_FONT_SIZE)
	card_label.add_theme_color_override("font_color", MemoryExam.CARD_COLOR)
	card.add_child(card_label)

	voice = AudioStreamPlayer.new()
	voice.name = "Voice"
	voice.bus = &"Voice" if AudioServer.get_bus_index("Voice") >= 0 else &"Master"
	add_child(voice)
	heart = AudioStreamPlayer.new()
	heart.name = "Heart"
	heart.bus = &"Sfx" if AudioServer.get_bus_index("Sfx") >= 0 else &"Master"
	heart.volume_db = 3.0
	add_child(heart)
	for k in 3:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % k
		p.bus = heart.bus
		add_child(p)
		_sfx_pool.append(p)


## Embedded in the main game UI (the story column of the LOG tab): no stage margins and no
## status line / rule (the game's own header and title show where you are).
func set_embedded(on: bool) -> void:
	embedded = on
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		_box.add_theme_constant_override(m, 0 if on else {"margin_left": 112, "margin_top": 34,
			"margin_right": 310, "margin_bottom": 40}[m])
	_rule.visible = not on
	status_label.visible = not on and status_label.text != ""


func _rtl(n: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.name = n
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_color_override("default_color", TEXT_COLOR)
	r.add_theme_constant_override("line_separation", 3)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	r.add_theme_font_size_override("italics_font_size", 14)
	r.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	# Act words draw their own [u] on the letters. The url underline starts early, so it stays off.
	r.meta_underlined = false
	return r


# ======================================================== PLAY

## Plays a screen dictionary (normalized StoryScene screen).
## opts: speed (scene default), title, pin_q, pin_r, complete (show finished, no audio).
func play(scr: Dictionary, opts: Dictionary = {}) -> void:
	stop()
	screen = scr
	wall = 0.0
	ending_shown = false
	status_label.text = str(opts.get("title", "")).to_upper()
	status_label.visible = status_label.text != "" and not embedded
	hold_next = bool(opts.get("hold_next", false))
	set_pin(str(opts.get("pin_q", "")), str(opts.get("pin_r", "")))
	var head := _filter(str(scr.get("heading", "")))
	heading_label.text = head
	heading_label.visible = head != ""
	markup = Markup.new().parse(_filter(str(scr.get("text", ""))))
	var cps := float(scr.get("speed", 0))
	if cps <= 0.0:
		cps = float(opts.get("speed", base_speed))
	var vo: Dictionary = scr.get("vo", {})
	var clip := str(vo.get("clip", ""))
	var cues: Array = vo.get("cues", [])
	var stream: AudioStream = _stream(clip) if audio_enabled and not bool(opts.get("complete", false)) else null
	_use_voice_clock = false
	if clip != "" and not cues.is_empty():
		markup.time_by_cues(cues, cps)
		clock_start = float(vo.get("from", 0.0))
		_use_voice_clock = stream != null
	else:
		markup.time_by_speed(cps)
		clock_start = 0.0
	clock = clock_start
	_vo_to = float(vo.get("to", -1.0))
	if stream and _vo_to <= 0.0:
		_vo_to = stream.get_length()
	_sfx_events.clear()
	for e: Dictionary in scr.get("sfx", []):
		var at := 0.0
		if e.has("at"):
			at = clock_start + float(e["at"])
		else:
			at = markup.line_start(int(e.get("line", 1)))
		_sfx_events.append([at, str(e.get("clip", "")), false])
	shake_level = int(scr.get("shake", 0))
	_clear_choices()
	continue_button.hide()
	_last_bb = "-"
	playing = true
	paused = false
	_hide_card()
	_act_stack.clear()
	_in_act = false
	_unwritten = ""
	act_done.clear()
	scroll.show()
	if str((scr.get("end", {}) as Dictionary).get("type", "")) == "transition":
		heading_label.hide()
		text_label.text = ""
		_last_bb = ""
		scroll.hide()
		pin_label.hide()
		_begin_card(str((scr.get("end", {}) as Dictionary).get("card", "")))
	if bool(opts.get("complete", false)):
		skip_typing(true)
		clock = markup.duration + 3.0
		red = _red_target(1.0)
	elif stream:
		voice.stream = stream
		voice.play(float(vo.get("from", 0.0)))
	_render()
	_update_fx()


## Stops audio / countdown. The stage keeps showing what it had.
func stop() -> void:
	playing = false
	qte_active = false
	_hide_card()
	voice.stop()
	voice.stream_paused = false
	heart.stop()
	for p in _sfx_pool:
		p.stop()


func set_paused(p: bool) -> void:
	paused = p
	voice.stream_paused = p and voice.playing


## Pinned header: question (dim) + response (accent). Either may be empty.
func set_pin(q: String, r: String) -> void:
	var lines := PackedStringArray()
	if q != "":
		lines.append("[color=%s]%s[/color]" % [PIN_QUESTION_COLOR, Markup.esc(q)])
	if r != "":
		lines.append("[color=%s][b]%s[/b][/color]" % [PIN_RESPONSE_COLOR, Markup.esc(r)])
	pin_label.text = "\n".join(lines)
	pin_label.visible = not lines.is_empty()


## Space / Enter / click: first press finishes the text, next press = CONTINUE / countdown button.
func press() -> void:
	if not playing or paused:
		return
	if _card_t >= 0.0:
		return
	if _in_act:
		if not ending_shown:
			skip_typing()
		return
	if not ending_shown:
		skip_typing()
		return
	match end_type():
		"continue":
			continue_pressed.emit()
		"hold":
			if hold_next:
				continue_pressed.emit()
		"qte":
			_qte_press()


## Keys 1-9 (1-based). Picks the n-th visible choice, or the countdown button with 1.
func pick(n: int) -> void:
	if not playing or paused or not ending_shown:
		return
	if _in_act:
		if n >= 1 and n <= choice_buttons.size() and not choice_buttons[n - 1].disabled:
			choice_buttons[n - 1].pressed.emit()
		return
	if end_type() == "qte":
		if n == 1:
			_qte_press()
		return
	if n >= 1 and n <= choice_buttons.size():
		choice_pressed.emit(_choice_index[n - 1])


func skip_typing(silent := false) -> void:
	if markup == null:
		return
	clock = maxf(clock, markup.duration)
	voice.stop()
	for e: Array in _sfx_events:
		e[2] = true
	if str((screen.get("red", {}) as Dictionary).get("mode", "off")) != "off":
		red = _red_target(1.0)      # a skipped ramp lands on its end value
	_render()
	if not ending_shown:
		_show_ending(silent)


## Debug / preview: jump the clock `sec` seconds into the screen.
func seek(sec: float) -> void:
	clock = clock_start + sec
	for e: Array in _sfx_events:
		e[2] = float(e[0]) <= clock
	if voice.playing:
		voice.seek(clock if _use_voice_clock else float((screen.get("vo", {}) as Dictionary).get("from", 0.0)) + sec)
	_render()


func is_typing() -> bool:
	return playing and not ending_shown


func end_type() -> String:
	return str((screen.get("end", {}) as Dictionary).get("type", "continue"))


## The question pinned above the next screen after a response.
func question_text() -> String:
	var q := _filter(str(screen.get("question", "")))
	if q.strip_edges() != "":
		return q.strip_edges()
	return markup.last_line() if markup else ""


func reset_fx() -> void:
	red = 0.0
	suffocate = 0.0
	_pulse = 0.0
	_update_fx()


func _filter(s: String) -> String:
	return text_filter.call(s) if text_filter.is_valid() else s


func _stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not _stream_cache.has(path):
		_stream_cache[path] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _stream_cache[path]



func _begin_card(text: String) -> void:
	var line := text.strip_edges()
	card_label.text = line if line != "" else " "
	card_label.modulate.a = 0.0
	card.show()
	_card_t = 0.0
	_card_sent = false
	ending_shown = true


func _hide_card() -> void:
	_card_t = -1.0
	_card_sent = false
	if card:
		card.hide()


## Same fade as the exam's ONE HOUR LATER card: in, hold, out.
func card_alpha(t: float) -> float:
	if t < MemoryExam.CARD_FADE_IN:
		return clampf(t / MemoryExam.CARD_FADE_IN, 0.0, 1.0)
	if t < MemoryExam.CARD_FADE_IN + MemoryExam.CARD_HOLD:
		return 1.0
	var out_t := t - MemoryExam.CARD_FADE_IN - MemoryExam.CARD_HOLD
	if out_t < MemoryExam.CARD_FADE_OUT:
		return clampf(1.0 - out_t / MemoryExam.CARD_FADE_OUT, 0.0, 1.0)
	return 0.0


# ======================================================== FRAME

func _process(delta: float) -> void:
	if not playing or paused:
		return
	wall += delta
	if _card_t >= 0.0:
		if not frozen:
			_card_t += delta
		card_label.modulate.a = card_alpha(_card_t)
		var done_at := MemoryExam.CARD_FADE_IN + MemoryExam.CARD_HOLD + MemoryExam.CARD_FADE_OUT + MemoryExam.CARD_AFTER
		if _card_t >= done_at and not _card_sent:
			_card_sent = true
			card.hide()
			continue_pressed.emit()
		_update_fx()
		return
	if not frozen:
		if _use_voice_clock and voice.playing:
			clock = voice.get_playback_position()
		else:
			clock += delta
		if voice.playing and _vo_to > 0.0 and voice.get_playback_position() >= _vo_to:
			voice.stop()
	for e: Array in _sfx_events:
		if not e[2] and clock >= float(e[0]):
			e[2] = true
			_play_sfx(str(e[1]))
	if qte_active:
		_qte_process(delta)
	else:
		var tgt := _red_target(_progress())
		if str((screen.get("red", {}) as Dictionary).get("mode", "off")) == "ramp":
			red = tgt
		else:
			red = move_toward(red, tgt, delta * RED_FADE)
		suffocate = move_toward(suffocate, 0.0, delta * 0.6)
		_pulse = maxf(0.0, _pulse - delta * 3.0)
	_render()
	if not ending_shown and markup and clock >= markup.duration:
		_show_ending()
	_update_fx()


## Typing progress 0..1 across the screen's text.
func _progress() -> float:
	if markup == null or markup.duration <= clock_start + 0.01:
		return 1.0
	return clampf((clock - clock_start) / (markup.duration - clock_start), 0.0, 1.0)


func _red_target(p: float) -> float:
	var r: Dictionary = screen.get("red", {})
	match str(r.get("mode", "off")):
		"static":
			return float(r.get("from", 0.0))
		"ramp":
			return lerpf(float(r.get("from", 0.0)), float(r.get("to", 0.0)), p)
	return 0.0


func _render() -> void:
	if markup == null:
		return
	var bb: String = markup.render(clock, wall)
	if shake_level > 0 and bb != "":
		bb = "[shake rate=18.0 level=%d connected=1]%s[/shake]" % [shake_level, bb]
	if _unwritten != "":
		bb += "\n[color=#e07040]%s[/color]" % Markup.esc(_unwritten)
	if bb == _last_bb:
		return
	_last_bb = bb
	text_label.text = bb
	scroll.set_deferred("scroll_vertical", 100000)


func _play_sfx(path: String) -> void:
	var st := _stream(path)
	if st == null or not audio_enabled:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = st
			p.play()
			return
	_sfx_pool[0].stream = st
	_sfx_pool[0].play()


func _update_fx() -> void:
	var on := red > 0.002 or suffocate > 0.002
	fx.visible = on
	if not on or fx.material == null:
		return
	var mat := fx.material as ShaderMaterial
	mat.set_shader_parameter("amount", suffocate)
	mat.set_shader_parameter("black", 0.0)
	mat.set_shader_parameter("pulse", _pulse)
	mat.set_shader_parameter("red", red)
	# keep the RESPONSE slot legible under the effects
	var kr := Vector4.ZERO
	if choices_box.is_visible_in_tree() and size.x > 0.0:
		var gr := Rect2(choices_header.global_position - global_position, choices_header.size)
		for b in choice_buttons:
			if is_instance_valid(b):
				gr = gr.merge(Rect2(b.global_position - global_position, b.size))
		gr = gr.grow(6.0)
		kr = Vector4(gr.position.x / size.x, gr.position.y / size.y, gr.size.x / size.x, gr.size.y / size.y)
	mat.set_shader_parameter("keep_rect", kr)



func _on_text_meta(meta: Variant) -> void:
	var link := str(meta)
	if link.begins_with("act:"):
		_meta_click = link
		open_act(link.substr(4))


func open_act(act_id: String) -> void:
	var id := act_id.strip_edges().to_lower()
	if id == "":
		return
	var spec := _act_spec(id)
	if spec.is_empty():
		_unwritten = "The act \"%s\" isn't written." % id
		_last_bb = ""
		_render()
		return
	_unwritten = ""
	if (bool(spec.get("container", false)) or spec.has("station")) and container_handler.is_valid():
		container_handler.call(id, spec)
		return
	_act_stack.append(id)
	_in_act = true
	_begin_text(str(spec.get("text", "")))


## Back is not authored. It replays the caller (the previous act, or the screen) and does not advance.
func act_back() -> void:
	if _act_stack.is_empty():
		return
	_act_stack.pop_back()
	_unwritten = ""
	if _act_stack.is_empty():
		_in_act = false
		_begin_text(str(screen.get("text", "")))
	else:
		_in_act = true
		_begin_text(str(_act_spec(str(_act_stack.back())).get("text", "")))


func _begin_text(src: String) -> void:
	voice.stop()
	for p in _sfx_pool:
		p.stop()
	ending_shown = false
	markup = Markup.new().parse(_filter(src))
	markup.time_by_speed(_screen_cps())
	clock_start = 0.0
	clock = 0.0
	_use_voice_clock = false
	_vo_to = -1.0
	_sfx_events.clear()
	shake_level = 0 if _in_act else int(screen.get("shake", 0))
	_clear_choices()
	continue_button.hide()
	choices_header.text = RESPONSE_HEADER
	choices_header.show()
	_last_bb = "-"
	playing = true
	scroll.show()
	_render()


func _screen_cps() -> float:
	var cps := float(screen.get("speed", 0))
	if cps <= 0.0:
		cps = base_speed
	return cps


func _act_spec(act_id: String) -> Dictionary:
	var spec := _raw_act_spec(act_id)
	if spec.has("station") and not container_handler.is_valid():
		return {"text": str(spec.get("text", "")), "choices": []}
	if bool(spec.get("container", false)) and not container_handler.is_valid():
		return SceneData.container_as_function(spec)
	return spec


## True when the act is a container (acts with "container": true).
func is_container(act_id: String) -> bool:
	var spec := _raw_act_spec(act_id)
	return bool(spec.get("container", false)) or spec.has("station")


func _raw_act_spec(act_id: String) -> Dictionary:
	var raw: Variant = screen.get("acts", {})
	var id := act_id.strip_edges().to_lower()
	if raw is Dictionary:
		var acts: Dictionary = raw
		if acts.has(id) and acts[id] is Dictionary:
			return acts[id]
		for k: Variant in acts.keys():
			if str(k).to_lower() == id and acts[k] is Dictionary:
				return acts[k]
		return {}
	if raw is Array:
		for a: Variant in raw:
			if a is Dictionary and str((a as Dictionary).get("id", "")).to_lower() == id:
				var body: Dictionary = (a as Dictionary).duplicate(true)
				if str(body.get("text", "")) == "":
					body["text"] = str(body.get("title", ""))
				if not body.has("choices"):
					body["choices"] = body.get("actions", [])
				return body
	return {}


func _show_act_choices() -> void:
	_clear_choices()
	var act_id := str(_act_stack.back()) if not _act_stack.is_empty() else ""
	var spec := _act_spec(act_id)
	var choices: Array = spec.get("choices", [])
	if choices.is_empty() and spec.has("actions") and spec.get("actions", []) is Array:
		choices = spec.get("actions", [])
	for action: Variant in choices:
		if not (action is Dictionary):
			continue
		var ad: Dictionary = action
		var done := _act_row_done(act_id, ad)
		var b := _make_button(choice_button_text(ad, done))
		b.disabled = done
		b.pressed.connect(_take_act.bind(act_id, ad))
	var back := _make_button("Back")
	back.pressed.connect(act_back)
	choices_header.text = ""
	choices_header.hide()
	choices_box.show()


## 1 -> "1 hr", anything else -> "N hrs". No suffix when the label already says it.
func choice_button_text(action: Dictionary, done: bool) -> String:
	var label := str(action.get("label", action.get("id", ""))).strip_edges()
	if label == "":
		label = "..."
	if done:
		if "already taken" in label.to_lower():
			return label
		return "%s (already taken)" % label
	var hrs := int(action.get("hours", 0))
	if hrs > 0 and not _label_has_hour_text(label):
		return "%s (%s)" % [label, _hour_text(hrs)]
	return label


func _hour_text(hrs: int) -> String:
	if hrs == 1:
		return "1 hr"
	return "%d hrs" % hrs


func _label_has_hour_text(label: String) -> bool:
	var low := label.to_lower()
	return low.contains(" hr)") or low.contains(" hrs)") or low.ends_with(" hr") or low.ends_with(" hrs")


func _act_key(act_id: String, action: Dictionary) -> String:
	var id := str(action.get("id", "")).strip_edges()
	if id == "":
		id = str(action.get("item", "")).strip_edges()
	if id == "":
		id = str(action.get("label", ""))
	return "%s/%s" % [act_id, id]


func _act_row_done(act_id: String, action: Dictionary) -> bool:
	var key := _act_key(act_id, action)
	if bool(act_done.get(key, false)):
		return true
	if act_is_done.is_valid() and bool(act_is_done.call(act_id, action)):
		act_done[key] = true
		return true
	return false


func _take_act(act_id: String, action: Dictionary) -> void:
	if _act_row_done(act_id, action):
		return
	act_done[_act_key(act_id, action)] = true
	action_taken.emit(act_id, action)
	if _in_act:
		_show_act_choices()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _meta_click != "":
				_meta_click = ""
				accept_event()
				return
			press()
			accept_event()


# ======================================================== ENDINGS

func _show_ending(_silent := false) -> void:
	ending_shown = true
	if _in_act:
		_show_act_choices()
		typing_done.emit()
		return
	choices_header.show()
	var end: Dictionary = screen.get("end", {})
	match end_type():
		"continue":
			continue_button.show()
		"hold":
			continue_button.visible = hold_next
		"choices":
			_clear_choices()
			var list: Array = end.get("choices", [])
			for i in list.size():
				var c: Dictionary = list[i]
				if choice_filter.is_valid() and not bool(choice_filter.call(c)):
					continue
				var b := _make_button(_filter(str(c.get("label", ""))))
				b.pressed.connect(func() -> void:
					if playing and not paused:
						choice_pressed.emit(i))
				_choice_index.append(i)
			choices_header.text = RESPONSE_HEADER
			choices_header.show()
			choices_box.show()
		"qte":
			_start_qte(end)
	typing_done.emit()


func _clear_choices() -> void:
	for b in choice_buttons:
		if is_instance_valid(b):
			b.queue_free()
	choice_buttons.clear()
	_choice_index.clear()
	for c in choices_box.get_children():
		if c.has_meta("qte_spacer"):
			c.queue_free()
	qte_button = null
	qte_active = false
	choices_box.hide()


## Same construction for every response (choices and the countdown button): same slot, same size.
func _make_button(label: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ChoiceButton"
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = BUTTON_SIZE
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE     # keys are handled by the owner (no double fire)
	choices_box.add_child(b)
	choice_buttons.append(b)
	return b


func _start_qte(end: Dictionary) -> void:
	_clear_choices()
	qte_total = maxf(1.0, float(end.get("seconds", 10.0)))
	qte_left = qte_total
	_qte_red0 = red
	var b := _make_button(_filter(str(end.get("label", ""))))
	b.name = "QteButton"
	b.clip_text = true
	b.pressed.connect(_qte_press)
	_qte_fill = ColorRect.new()
	_qte_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qte_bar = ColorRect.new()
	_qte_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(_qte_fill)
	b.add_child(_qte_bar)
	# empty second row: the header and the button sit exactly where a two-choice screen has them
	var spacer := Control.new()
	spacer.set_meta("qte_spacer", true)
	spacer.custom_minimum_size = BUTTON_SIZE
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choices_box.add_child(spacer)
	qte_button = b
	qte_active = true
	_beat_t = 0.0
	choices_box.show()
	_qte_ui()


func _qte_press() -> void:
	if not qte_active or paused:
		return
	qte_active = false
	heart.stop()
	qte_pressed.emit()


## Debug / preview: set the seconds left on the countdown.
func qte_seek(left: float) -> void:
	if qte_active:
		qte_left = clampf(left, 0.0, qte_total)
		_qte_process(0.0)


func _qte_process(delta: float) -> void:
	if not frozen:
		qte_left = maxf(0.0, qte_left - delta)
	var frac := 1.0 - qte_left / qte_total      # 0 → 1 as the air runs out
	red = lerpf(_qte_red0, QTE_RED_END, frac)
	suffocate = lerpf(0.35, 1.0, frac) * 0.8
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	if not frozen and delta > 0.0:
		_beat_t -= delta
		if _beat_t <= 0.0:
			_beat_t = lerpf(BEAT_SLOW, BEAT_FAST, frac)
			_heartbeat(0.42)
			_pulse = 1.0
			_dub_t = 0.17
		if _dub_t >= 0.0:
			_dub_t -= delta
			if _dub_t < 0.0:
				_heartbeat(0.36)
				_pulse = 0.7
	_qte_ui()
	qte_tick.emit(qte_left / qte_total)
	if qte_left <= 0.0 and not frozen and qte_active:
		qte_active = false
		heart.stop()
		qte_expired.emit()


func _heartbeat(pitch: float) -> void:
	if not audio_enabled:
		return
	if heart.stream == null and ResourceLoader.exists(HEART_SFX):
		heart.stream = load(HEART_SFX)
	heart.pitch_scale = pitch
	heart.play()


func _qte_ui() -> void:
	var left := qte_left / qte_total
	var c := ERROR_COLOR.lerp(Color("#d8352a"), 1.0 - left)
	if is_instance_valid(qte_button):
		var sz := qte_button.size
		if sz.x <= 0.0:
			sz = BUTTON_SIZE
		_qte_fill.position = Vector2.ZERO
		_qte_fill.size = Vector2(sz.x * left, sz.y)
		_qte_fill.color = Color(c.r, c.g, c.b, 0.16)
		_qte_bar.position = Vector2(0, sz.y - 3.0)
		_qte_bar.size = Vector2(sz.x * left, 3.0)
		_qte_bar.color = c
	choices_header.text = QTE_HEADER % qte_left
