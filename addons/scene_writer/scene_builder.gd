@tool
extends RefCounted
## SCENE WRITER BUILDER: turns a scene dictionary into
##   res://story/scenes/<id>.json   (the data the game reads; hand-editable)
##   res://scenes/authored/<id>.tscn (inherits templates/pda_screen.tscn, script
##                                    templates/authored_scene.gd, scene_path set)
## Works without the editor (tools/writer_test.gd calls it headless).

const SceneData := preload("res://ui/story_scene.gd")


## Returns {ok, json, tscn, problems: Array, message}. Nothing is written if there are errors.
static func build(data: Dictionary) -> Dictionary:
	var d := SceneData.normalize(data)
	var problems := SceneData.validate(d)
	var errors := problems.filter(func(p: Dictionary) -> bool: return p["level"] == "error")
	var res := {"ok": false, "json": SceneData.json_path(str(d["id"])),
		"tscn": SceneData.tscn_path(str(d["id"])), "problems": problems, "message": ""}
	if not errors.is_empty():
		res["message"] = "Not built: fix %d problem%s first." % [errors.size(), "" if errors.size() == 1 else "s"]
		return res
	var err := SceneData.save_file(d)
	if err != OK:
		res["message"] = SceneData.last_error
		return res
	err = write_tscn(str(d["id"]))
	if err != OK:
		res["message"] = "Cannot write %s (%s)" % [res["tscn"], error_string(err)]
		return res
	res["ok"] = true
	res["message"] = "Built %s" % res["tscn"]
	return res


static func tscn_text(id: String) -> String:
	var node_name := id.to_pascal_case() if id != "" else "AuthoredScene"
	return """[gd_scene format=3]

[ext_resource type="PackedScene" path="%s" id="1_base"]
[ext_resource type="Script" path="%s" id="2_script"]

[node name="%s" instance=ExtResource("1_base")]
script = ExtResource("2_script")
scene_path = "%s"
""" % [SceneData.TEMPLATE_SCENE, SceneData.RUNNER_SCRIPT, node_name, SceneData.json_path(id)]


static func write_tscn(id: String) -> Error:
	var path := SceneData.tscn_path(id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var text := tscn_text(id)
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text:
		return OK   # unchanged: keep the file (and its timestamp) as is
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK
