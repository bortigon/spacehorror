@tool
extends EditorPlugin
## SCENE WRITER: main-screen tab ("Scene Writer" next to 2D / 3D / Script / AssetLib).
## Enable it in Project > Project Settings > Plugins. Guide: docs/SCENE_WRITER.md.
##
## Screenshot helpers (box / CI only), after "--" on the editor command line:
##   --scene_writer_open=<id> [--scene_writer_screen=N] [--scene_writer_replay=SECONDS] [--scene_writer_scroll=PX]
##   [--scene_writer_shot=PATH.png] [--scene_writer_preview_shot=PATH.png] [--scene_writer_quit]

const PanelScript := preload("res://addons/scene_writer/writer_panel.gd")

var panel: Control


func _enter_tree() -> void:
	panel = PanelScript.new()
	panel.name = "SceneWriter"
	panel.editor_plugin = self
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)
	var d := _args()
	if d.has("scene_writer_open"):
		_auto.call_deferred(d)


func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible
		if visible:
			panel.on_shown()


func _get_plugin_name() -> String:
	return "Scene Writer"


func _get_plugin_icon() -> Texture2D:
	var base := EditorInterface.get_base_control()
	if base and base.has_theme_icon(&"RichTextEffect", &"EditorIcons"):
		return base.get_theme_icon(&"RichTextEffect", &"EditorIcons")
	return base.get_theme_icon(&"Script", &"EditorIcons") if base else null


func _args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene_writer"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return d


func _auto(d: Dictionary) -> void:
	await get_tree().create_timer(float(d.get("scene_writer_wait", "3"))).timeout
	EditorInterface.set_main_screen_editor("Scene Writer")
	var ok: bool = panel.open_scene(str(d["scene_writer_open"]))
	print("SCENE WRITER open %s: %s, %d screens" % [d["scene_writer_open"], "OK" if ok else "FAILED",
		(panel.data.get("screens", []) as Array).size()])
	if d.has("scene_writer_screen"):
		panel.select_screen(int(d["scene_writer_screen"]) - 1)
	if d.has("scene_writer_scroll"):
		await get_tree().process_frame
		panel.scroll_screen_column(int(d["scene_writer_scroll"]))
	var delay := 1.5
	if d.has("scene_writer_replay"):
		panel.replay_preview()
		delay = float(d["scene_writer_replay"])
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	if d.has("scene_writer_shot"):
		var img := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		var err := img.save_png(str(d["scene_writer_shot"]))
		print("SCENE WRITER SHOT %s -> %s (%dx%d)" % [error_string(err), d["scene_writer_shot"], img.get_width(), img.get_height()])
	if d.has("scene_writer_preview_shot"):
		var pimg: Image = panel.preview_image()
		if pimg:
			var perr := pimg.save_png(str(d["scene_writer_preview_shot"]))
			print("SCENE WRITER PREVIEW SHOT %s -> %s" % [error_string(perr), d["scene_writer_preview_shot"]])
	if d.has("scene_writer_quit"):
		get_tree().quit()
