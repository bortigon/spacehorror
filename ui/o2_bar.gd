class_name O2Bar
extends Control
## Header OXYGEN readout: "O2" + 20 tick segments + "NN%". Plex Mono, phosphor palette.
## danger 0 = calm (green, static). danger > 0 = amber -> red, glow pulse that speeds up,
## and a flash each time a tick drops. PdaScreen.set_o2() drives every registered bar.

const TICKS := 20
const COL_OK := Color(0.49, 0.85, 0.5, 1)
const COL_AMBER := Color(0.93, 0.62, 0.3, 1)
const COL_RED := Color(0.9, 0.18, 0.14, 1)
const COL_EMPTY := Color(0.2, 0.3, 0.24, 0.55)
const COL_LABEL := Color(0.56, 0.8, 0.6, 1)

var level := 100.0        # 0..100 as displayed
var danger := 0.0         # 0..1
var _flash := 0.0
var _t := 0.0
var _font: Font
var _last_tick := TICKS


func _init() -> void:
	custom_minimum_size = Vector2(200, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _ready() -> void:
	_font = load("res://assets/fonts/IBMPlexMono-SemiBold.ttf")


func set_state(new_level: float, new_danger: float) -> void:
	level = clampf(new_level, 0.0, 100.0)
	danger = clampf(new_danger, 0.0, 1.0)
	var tick := filled_ticks()
	if tick < _last_tick and danger > 0.0:
		_flash = 1.0
	_last_tick = tick
	queue_redraw()


func filled_ticks() -> int:
	return int(ceil(level / 100.0 * TICKS - 0.001))


func percent_text() -> String:
	return "%d%%" % int(round(level))


func _process(delta: float) -> void:
	if danger > 0.0 or _flash > 0.0:
		_t += delta * lerpf(1.2, 4.5, danger)
		_flash = maxf(0.0, _flash - delta * 5.0)
		queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var fs := 12
	var h := size.y
	var base_y := h * 0.5 + fs * 0.36
	var pulse := 0.0
	var col := COL_OK
	if danger > 0.0:
		pulse = 0.5 + 0.5 * sin(_t * TAU)
		col = COL_AMBER.lerp(COL_RED, clampf(danger * 1.2 - 0.1, 0.0, 1.0))
		col = col.lightened(0.35 * _flash + 0.15 * pulse * danger)
	var label_col := COL_LABEL if danger <= 0.0 else col
	draw_string(_font, Vector2(0, base_y), "O2", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)
	var pct_w := 40.0
	var x0 := 24.0
	var x1 := size.x - pct_w - 6.0
	draw_string(_font, Vector2(size.x - pct_w, base_y), percent_text(), HORIZONTAL_ALIGNMENT_RIGHT, pct_w, fs, label_col)
	var bar := Rect2(x0, h * 0.5 - 5.0, x1 - x0, 10.0)
	if danger > 0.0:
		var glow := Color(col.r, col.g, col.b, (0.10 + 0.30 * pulse) * danger + 0.35 * _flash)
		draw_rect(bar.grow(3.0), glow)
	draw_rect(bar.grow(1.0), Color(0.02, 0.05, 0.035, 0.9))
	var n := filled_ticks()
	var seg_w := (bar.size.x - (TICKS - 1) * 2.0) / TICKS
	for i in TICKS:
		var r := Rect2(bar.position.x + i * (seg_w + 2.0), bar.position.y, seg_w, bar.size.y)
		draw_rect(r, col if i < n else COL_EMPTY)
