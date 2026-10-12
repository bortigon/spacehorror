extends Control
## TITLE SCREEN (boot scene): REC-7 logo, PLAY, QUIT.
## PLAY fades out and, in a debug build, opens the mission select. A release build opens
## the game exactly as before (scenes/intro.tscn, the stasis thaw). QUIT closes the app.
##
## Debug builds only (editor runs / debug exports; release exports ignore all of this):
##   any debug arg the title does not use (--jump=exam, --thaw_at=…, --boot, --skip_title, …)
##   skips the title and goes straight to the intro, which reads the same args as before.
##   Title-only args: --shot=PATH [--shot_delay=1.2] (save the frame, quit),
##   --title_hover=play|quit (show a button in its hover look, for screenshots), --nodev.

const GAME_SCENE := "res://scenes/intro.tscn"
const MISSION_SCENE := "res://scenes/mission_select.tscn"
const TITLE_ARGS := ["shot", "shot_delay", "title_hover", "nodev"]
const FADE_IN := 0.6
const FADE_OUT := 0.35

@onready var content: Control = %Content
@onready var logo: TextureRect = %Logo
@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton
@onready var sfx_tap: AudioStreamPlayer = %SfxTap

## Tests set this to false: QUIT then only sets quit_requested instead of closing the app.
var allow_quit := true
var quit_requested := false
var leaving := false
var skipped_to_game := false
## Debug builds open the mission select. Tests set this false to check the release path.
var dev_menu := true


func _ready() -> void:
	dev_menu = OS.is_debug_build()
	play_button.pressed.connect(_on_play)
	quit_button.pressed.connect(_on_quit)
	var d := _read_debug_args()
	if _wants_game(d):
		skipped_to_game = true
		content.modulate.a = 0.0
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	content.modulate.a = 0.0
	create_tween().tween_property(content, "modulate:a", 1.0, FADE_IN)
	if d.has("title_hover"):
		var b := quit_button if str(d["title_hover"]) == "quit" else play_button
		_show_hover(b)
	if d.has("shot"):
		_shot(str(d["shot"]), float(str(d.get("shot_delay", "1.2"))))


func _on_play() -> void:
	if leaving:
		return
	leaving = true
	_play_tap()
	play_button.disabled = true
	quit_button.disabled = true
	var dest := MISSION_SCENE if dev_menu else GAME_SCENE
	var tw := create_tween()
	tw.tween_property(content, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(dest))


func _on_quit() -> void:
	if leaving:
		return
	leaving = true
	_play_tap()
	quit_requested = true
	if allow_quit:
		await get_tree().create_timer(0.12).timeout   # let the click sound start
		get_tree().quit()


func _play_tap() -> void:
	if sfx_tap.stream != null and sfx_tap.is_inside_tree():
		sfx_tap.play()


func _exit_tree() -> void:
	sfx_tap.stop()


# ---------------------------------------------------------------- debug

func _read_debug_args() -> Dictionary:
	var d := {}
	if not OS.is_debug_build():
		return d   # release exports ignore every debug arg
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.trim_prefix("--").split("=", true, 1)
		d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return d


## True when the run was started with intro/debug args (e.g. --jump=exam): skip the title.
func _wants_game(d: Dictionary) -> bool:
	for k: String in d:
		if not TITLE_ARGS.has(k):
			return true
	return false


func _show_hover(b: Button) -> void:
	b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover"))
	b.add_theme_color_override("font_color", b.get_theme_color("font_hover_color"))


func _shot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		var err := img.save_png(path)
		print("SHOT %s -> %s (%dx%d)" % [error_string(err), path, img.get_width(), img.get_height()])
	get_tree().quit()
