extends ColorRect
## HOLO FX OVERLAY: the windows' hologram look (shaders/holo_window.gdshader: drifting scanlines, a soft
## rolling band, a faint flicker, the odd glitch row) for things that are not holo windows: the
## full map page and the minimap. Sits on top of its parent, ignores the mouse, only adds light.
##   var fx := preload("res://ui/holo_fx.gd").new(); parent.add_child(fx)

const FX_SHADER := "res://shaders/holo_window.gdshader"
const IDLE_FX := 0.5          # same strength as ui/holo_window.gd

var mat: ShaderMaterial
var _t := 0.0
var _seed := 0.0
var _glitch_left := 0.0
var _glitch_next := 3.0


func _init() -> void:
	name = "HoloFx"
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mat = ShaderMaterial.new()
	mat.shader = load(FX_SHADER)
	material = mat
	_seed = randf() * 100.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_glitch_next -= delta
	if _glitch_left <= 0.0 and _glitch_next <= 0.0:
		_glitch_left = randf_range(0.06, 0.16)
		_glitch_next = randf_range(3.0, 7.0)
	_glitch_left -= delta
	mat.set_shader_parameter("flicker", (0.5 + 0.5 * sin(_t * 31.0)) * IDLE_FX * 2.0)
	mat.set_shader_parameter("glitch", 1.0 if _glitch_left > 0.0 else 0.0)
	mat.set_shader_parameter("scan_offset", _t * 1.6)
	mat.set_shader_parameter("glitch_seed", _seed + floorf(_t * 12.0))
	var p := get_parent() as CanvasItem
	if p != null:
		# the same faint alpha flicker as a settled holo window
		var f := 1.0 - IDLE_FX * (0.045 - 0.03 * sin(_t * 23.0) - 0.015 * sin(_t * 57.3 + 1.3))
		p.self_modulate.a = clampf(f, 0.8, 1.0)
