extends Control
## HOLO WINDOW: reusable base for the character screen and the container window.
## Sized to `panel_size`; subclasses fill `body` (also panel_size) in _build_body().
##
## open():  old tube-TV turn-on. A bright dot flashes with static, stretches to a line, then the
##          window expands vertically to full height while the flash and static settle (~0.5 s).
## close(): the same in reverse, a little faster (~0.35 s): collapse to a line, squeeze to a dot,
##          fade out.
## While open the window has a faint hologram look: scanlines drifting, a small alpha flicker,
##          and now and then a brief jitter + colour-band glitch.
##
## Layout: self (fixed panel_size) > _clip (clips; its rect is what the animation resizes) >
## body (never moves relative to the window) + fx (ColorRect with shaders/holo_window.gdshader).
## No AnimationPlayer: one Tween drives a 0..1 "turn-on" value.

signal opened
signal closed

enum State { CLOSED, OPENING, OPEN, CLOSING }

const FX_SHADER := "res://shaders/holo_window.gdshader"
const OPEN_SECONDS := 0.5
const CLOSE_SECONDS := 0.35
## Share of the turn-on value spent on each phase: dot, stretch to a line, expand to full height.
const DOT_END := 0.15
const LINE_END := 0.40
## Strength of the repeating hologram effects (flicker, jitter, scanlines, glitch bands). 1.0 was the
## first version; David asked for 50 % more subtle. The turn-on / turn-off animation is untouched.
const IDLE_FX := 0.5
const DOT_SIZE := Vector2(8.0, 3.0)
const LINE_HEIGHT := 3.0
const MONO := "res://assets/fonts/IBMPlexMono-Regular.ttf"
const MONO_BOLD := "res://assets/fonts/IBMPlexMono-SemiBold.ttf"
const HEADING_FONT := "res://assets/fonts/Oxanium-SemiBold.ttf"

# Placeholder palette (until the 2D art exists). Lighter green window, darker teal grid.
const WIN_BG := Color(0.39, 0.72, 0.30, 0.985)
const WIN_EDGE := Color(0.80, 1.0, 0.78, 0.9)
const GRID_BG := Color(0.12, 0.45, 0.35, 0.96)
const GRID_LINE := Color(0.05, 0.22, 0.17, 1.0)
const INK := Color(0.03, 0.13, 0.05, 1.0)
const INK_DIM := Color(0.06, 0.24, 0.10, 0.85)

var panel_size := Vector2(340, 340)
var state: State = State.CLOSED
var open_amount := 0.0              # 0 closed .. 1 fully open
var base_pos := Vector2.ZERO        # where the window sits (the manager centres it)
var body: Control
var fx: ColorRect
var drag_hidden := false
var animate := true                 # false: open()/close() snap (tests, reduced motion)

var _clip: Control
var _tween: Tween
var _move_tween: Tween
var _mat: ShaderMaterial
var _t := 0.0
var _glitch_left := 0.0
var _glitch_next := 2.5
var _jitter := Vector2.ZERO
var _seed := 0.0
var _mono: Font
var _mono_bold: Font
var _heading: Font


## Call once after setting panel_size (subclasses call it from their own _init).
func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	custom_minimum_size = panel_size
	size = panel_size
	_mono = load(MONO) if ResourceLoader.exists(MONO) else null
	_mono_bold = load(MONO_BOLD) if ResourceLoader.exists(MONO_BOLD) else _mono
	_heading = load(HEADING_FONT) if ResourceLoader.exists(HEADING_FONT) else _mono_bold
	_clip = Control.new()
	_clip.name = "Clip"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	body = Control.new()
	body.name = "Body"
	body.size = panel_size
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(body)
	fx = ColorRect.new()
	fx.name = "HoloFx"
	fx.color = Color.WHITE
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(FX_SHADER):
		_mat = ShaderMaterial.new()
		_mat.shader = load(FX_SHADER)
		fx.material = _mat
	_clip.add_child(fx)
	_build_body()
	_set_clip(Vector2.ZERO)
	set_process(false)


## A one-line message inside the window ("NOT ENOUGH HOURS"...). Call make_notice() in _build_body().
var notice_label: Label
var _notice_token := 0


func make_notice(rect: Rect2) -> Label:
	notice_label = make_label("", 10, false, Color(0.50, 0.06, 0.03, 1.0))
	notice_label.name = "Notice"
	notice_label.add_theme_font_override("font", _mono_bold)
	notice_label.position = rect.position
	notice_label.size = rect.size
	notice_label.clip_text = true
	body.add_child(notice_label)
	return notice_label


func show_notice(text: String, seconds := 3.0) -> void:
	if notice_label == null:
		return
	_notice_token += 1
	var token := _notice_token
	notice_label.text = text
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout
	if token == _notice_token and is_instance_valid(notice_label):
		notice_label.text = ""


## Override: add the window's controls to `body` (size panel_size).
func _build_body() -> void:
	pass


## Override: called when the window starts opening (fill / refresh the contents).
func _on_opening() -> void:
	pass


## An item is being dragged out of the windows: hide this one (its state stays) until it comes back.
func set_drag_hidden(on: bool) -> void:
	drag_hidden = on
	if on:
		visible = false
	elif state != State.CLOSED:
		visible = true


func is_closed() -> bool:
	return state == State.CLOSED


func is_open() -> bool:
	return state == State.OPEN or state == State.OPENING


func is_interactive() -> bool:
	return state == State.OPEN


## Whether the window counts as "up" for layout and input (opening or open).
func wants_open() -> bool:
	return state == State.OPENING or state == State.OPEN


func open() -> void:
	if wants_open():
		return
	_on_opening()
	_kill_tween()
	_seed = randf() * 50.0
	visible = not drag_hidden
	state = State.OPENING
	set_process(true)
	if not animate:
		_apply(1.0)
		_finish_open()
		return
	var from := open_amount
	_tween = create_tween()
	_tween.tween_method(_apply, from, 1.0, OPEN_SECONDS * (1.0 - from * 0.5))
	_tween.tween_callback(_finish_open)


func close() -> void:
	if state == State.CLOSED or state == State.CLOSING:
		return
	_kill_tween()
	state = State.CLOSING
	if not animate:
		_apply(0.0)
		_finish_close()
		return
	_tween = create_tween()
	_tween.tween_method(_apply, open_amount, 0.0, CLOSE_SECONDS * maxf(open_amount, 0.2))
	_tween.tween_callback(_finish_close)


## Closes without any animation (screen change, death, tests).
func close_now() -> void:
	_kill_tween()
	if state == State.CLOSED:
		return
	_apply(0.0)
	_finish_close()


func _finish_open() -> void:
	state = State.OPEN
	open_amount = 1.0
	_set_fx(0.0, 0.0)
	opened.emit()


func _finish_close() -> void:
	state = State.CLOSED
	open_amount = 0.0
	visible = false
	set_process(false)
	modulate = Color.WHITE
	position = base_pos
	closed.emit()


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


## Slides to a new resting position (the other window opened or closed).
func move_to(pos: Vector2) -> void:
	base_pos = pos
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	if not animate or state == State.CLOSED:
		position = pos
		return
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", pos, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- the turn-on

## u: 0 = gone, 1 = fully open. Same curve in both directions.
func _apply(u: float) -> void:
	open_amount = u
	var w := panel_size.x
	var h := panel_size.y
	var flash := 0.0
	var noise := 0.0
	var sz := Vector2.ZERO
	var a := 1.0
	if u <= 0.0:
		sz = Vector2.ZERO
		a = 0.0
	elif u < DOT_END:
		var v := u / DOT_END
		sz = DOT_SIZE * Vector2(v, 1.0)
		flash = 1.0
		noise = 0.9
		a = clampf(v * 1.4, 0.0, 1.0)
	elif u < LINE_END:
		var v2 := (u - DOT_END) / (LINE_END - DOT_END)
		sz = Vector2(lerpf(DOT_SIZE.x, w, ease(v2, 0.35)), lerpf(DOT_SIZE.y, LINE_HEIGHT, v2))
		flash = 1.0
		noise = 0.8
	else:
		var v3 := (u - LINE_END) / (1.0 - LINE_END)
		sz = Vector2(w, lerpf(LINE_HEIGHT, h, ease(v3, 0.3)))
		flash = pow(1.0 - v3, 2.2) * 0.95
		noise = (1.0 - v3) * 0.65
	_set_clip(sz)
	_set_fx(flash, noise)
	modulate.a = a if (state == State.OPENING or state == State.CLOSING) else modulate.a


func _set_clip(sz: Vector2) -> void:
	if _clip == null:
		return
	var pos := ((panel_size - sz) * 0.5).round()
	sz = sz.round()
	_clip.position = pos
	_clip.size = sz
	body.position = -pos


func _set_fx(flash: float, noise: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("flash", flash)
	_mat.set_shader_parameter("noise_amount", noise)


# ---------------------------------------------------------------- hologram idle

func _process(delta: float) -> void:
	_t += delta
	if _mat == null:
		return
	var settled := state == State.OPEN
	if settled:
		# faint alpha flicker: two slow waves + the odd short dip
		# (half of the first version: IDLE_FX = 0.5 scales every repeating effect)
		var f := 1.0 - IDLE_FX * (0.045 - 0.03 * sin(_t * 23.0) - 0.015 * sin(_t * 57.3 + 1.3))
		if fmod(_t * 1.7 + _seed, 6.1) < 0.05:
			f -= 0.12 * IDLE_FX
		modulate.a = clampf(f, 0.8, 1.0)
		_glitch_next -= delta
		if _glitch_left <= 0.0 and _glitch_next <= 0.0:
			_glitch_left = randf_range(0.06, 0.16)
			_glitch_next = randf_range(2.5, 6.0)
		if _glitch_left > 0.0:
			_glitch_left -= delta
			_jitter = Vector2(randf_range(-2.5, 2.5) * IDLE_FX, 0.0) if randf() < 0.7 else Vector2.ZERO
		else:
			_jitter = Vector2.ZERO
		if _move_tween == null or not _move_tween.is_running():
			position = base_pos + _jitter
		_mat.set_shader_parameter("flicker", 0.5 + 0.5 * sin(_t * 31.0))
		_mat.set_shader_parameter("glitch", 1.0 if _glitch_left > 0.0 else 0.0)
	else:
		_mat.set_shader_parameter("glitch", 0.0)
		_mat.set_shader_parameter("flicker", 0.0)
	_mat.set_shader_parameter("scan_offset", _t * 1.6)
	_mat.set_shader_parameter("glitch_seed", _seed + floorf(_t * 12.0))


# ---------------------------------------------------------------- small UI helpers (placeholder art)

func make_label(text: String, size_px: int, heading := false, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _heading if heading else _mono)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l


## Dark-green button on the light window. Same look for TAKE / EXIT / X.
func make_button(text: String, min_size := Vector2(0, 28)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _mono_bold)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", Color(0.80, 1.0, 0.80))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.62, 0.48))
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.05, 0.19, 0.10, 0.97), Color(0.55, 0.85, 0.58)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.09, 0.30, 0.15, 1.0), Color(0.85, 1.0, 0.85)))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.14, 0.40, 0.20, 1.0), Color.WHITE))
	b.add_theme_stylebox_override("disabled", _btn_style(Color(0.10, 0.22, 0.14, 0.7), Color(0.30, 0.45, 0.33)))
	return b


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


func make_panel_bg() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = panel_size
	var s := StyleBoxFlat.new()
	s.bg_color = WIN_BG
	s.border_color = WIN_EDGE
	s.set_border_width_all(2)
	s.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", s)
	return p


func make_grid_bg(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.position = rect.position
	p.size = rect.size
	var s := StyleBoxFlat.new()
	s.bg_color = GRID_BG
	s.border_color = GRID_LINE
	s.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", s)
	return p
