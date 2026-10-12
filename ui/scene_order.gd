extends RefCounted
## Play order, read from story/SCENE_ORDER.md when a screen's ending is NEXT.
## Reordering the file does not need a Build. A new scene still needs one Build.
##
## Three levels, lines at column 0 only:
##   ## Chapter title
##   ### Scene title          (one debug-menu button; opens the first subscene)
##   - intro:<id> — note      (a subscene in scenes/intro.gd)
##   - scene:<id>/<screen> — note   (a Scene Writer subscene)
## Words after " — " (or " -- ") are a note. Indented lines are ignored.
## A plain line under a chapter, before its first scene, is that chapter's note.
##
## NEXT ("order:next") advances to the next subscene. No later subscene means the
## runner shows a one-line screen: the next scene isn't written.

const PATH := "res://story/SCENE_ORDER.md"
const SENTINEL := "order:next"
const UNWRITTEN := "The next scene isn't written."

## Tests set this to a whole document. Empty = read PATH.
static var override_text := ""
## Tests set this so a save stays in override_text and does not touch the file.
static var memory_only := false


static func text() -> String:
	if override_text != "":
		return override_text
	if not FileAccess.file_exists(PATH):
		push_error("SceneOrder: missing %s" % PATH)
		return ""
	return FileAccess.get_file_as_string(PATH)


static func save_text(body: String) -> void:
	if memory_only:
		override_text = body
		return
	if body == text():
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("SceneOrder: cannot write %s" % PATH)
		return
	f.store_string(body)


static func chapters() -> Array:
	return parse(text())["chapters"]


## {header, chapters: [{title, note, scenes: [{title, screens: [{kind, id, screen, label, target}]}]}]}
static func parse(src: String) -> Dictionary:
	var header := ""
	var chs: Array = []
	var chapter: Dictionary = {}
	var scene: Dictionary = {}
	var seen_chapter := false
	for raw in src.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		if raw.begins_with("### "):
			if chapter.is_empty():
				continue
			scene = {"title": raw.substr(4).strip_edges(), "screens": []}
			(chapter["scenes"] as Array).append(scene)
			continue
		if raw.begins_with("## "):
			chapter = {"title": raw.substr(3).strip_edges(), "note": "", "scenes": []}
			chs.append(chapter)
			scene = {}
			seen_chapter = true
			continue
		if not seen_chapter:
			header += raw + "\n"
			continue
		if raw.begins_with("- "):
			var screen := _screen_from_line(raw.substr(2).strip_edges())
			if not screen.is_empty() and not scene.is_empty():
				(scene["screens"] as Array).append(screen)
			continue
		if raw.strip_edges() == "" or not scene.is_empty() or chapter.is_empty():
			continue
		var note := raw.strip_edges()
		chapter["note"] = note if str(chapter["note"]) == "" else str(chapter["note"]) + "\n" + note
	return {"header": header, "chapters": chs}


static func render(doc: Dictionary) -> String:
	var header := str(doc.get("header", ""))
	if header == "":
		header = _default_header()
	if not header.ends_with("\n"):
		header += "\n"
	var out := header.rstrip("\n") + "\n"
	for ch in doc.get("chapters", []):
		out += "\n## %s\n" % str(ch.get("title", "")).strip_edges()
		var note := str(ch.get("note", "")).strip_edges()
		if note != "":
			out += note + "\n"
		for sc in ch.get("scenes", []):
			out += "\n### %s\n" % str(sc.get("title", "")).strip_edges()
			for s in sc.get("screens", []):
				var label := str(s.get("label", "")).strip_edges()
				var target := str(s.get("target", ""))
				if label == "":
					out += "- %s\n" % target
				else:
					out += "- %s — %s\n" % [target, label]
	if not out.ends_with("\n"):
		out += "\n"
	return out


static func flat_screens(doc: Dictionary = {}) -> Array:
	var chs: Array = doc.get("chapters", []) if not doc.is_empty() else chapters()
	var out: Array = []
	for ch in chs:
		for sc in ch.get("scenes", []):
			for s in sc.get("screens", []):
				var row: Dictionary = (s as Dictionary).duplicate()
				row["chapter"] = str(ch.get("title", ""))
				row["scene"] = str(sc.get("title", ""))
				out.append(row)
	return out


## Debug mission-select rows: one per scene that has a subscene, in list order.
## The button opens that scene's first subscene.
static func menu_rows() -> Array:
	var out: Array = []
	var seen := {}
	for ch in chapters():
		for sc in ch.get("scenes", []):
			var subs: Array = sc.get("screens", [])
			if subs.is_empty():
				continue
			var first: Dictionary = subs[0]
			var label := str(sc.get("title", "")).strip_edges()
			if label == "":
				label = str(first.get("id", ""))
			if seen.has(label):
				label = "%s (%s)" % [label, str(ch.get("title", ""))]
			seen[label] = true
			var row: Dictionary = first.duplicate()
			row["label"] = label
			row["chapter"] = str(ch.get("title", ""))
			row["scene"] = str(sc.get("title", ""))
			out.append(row)
	return out


## The go_target of the screen after current ("intro:thaw" or "scene:id/screen"). "" if current is last or missing.
static func next_after(current: String) -> String:
	return next_after_in(flat_screens(), current)


static func next_after_in(list: Array, current: String) -> String:
	var found := false
	for e in list:
		if found:
			return str(e.get("target", ""))
		if str(e.get("target", "")) == current.strip_edges():
			found = true
	return ""


static func locate(file_id: String, screen_id: String) -> Dictionary:
	var want := "scene:%s/%s" % [file_id, screen_id]
	for s in flat_screens():
		if str(s.get("target", "")) == want:
			return s
	return {}


## Chapter and scene of the first screen of this Scene Writer file, or {}.
static func locate_file(file_id: String) -> Dictionary:
	var prefix := "scene:%s/" % file_id
	for s in flat_screens():
		if str(s.get("target", "")).begins_with(prefix):
			return s
	return {}


static func place(chapter: String, scene_title: String, file_id: String, screen_id: String, label: String) -> void:
	save_text(place_in(text(), chapter, scene_title, file_id, screen_id, label))


static func place_in(src: String, chapter: String, scene_title: String, file_id: String, screen_id: String, label: String) -> String:
	var doc := parse(src)
	_detach(doc, "scene:%s/%s" % [file_id, screen_id])
	var ch := _ensure_chapter(doc, chapter)
	var sc := _ensure_scene(ch, scene_title)
	(sc["screens"] as Array).append(_authored(file_id, screen_id, label))
	return render(doc)


## Insert this screen just after another screen in the same scene. Appends if the anchor is missing.
static func insert_after(chapter: String, scene_title: String, file_id: String, screen_id: String, label: String, after_screen_id: String) -> void:
	save_text(insert_after_in(text(), chapter, scene_title, file_id, screen_id, label, after_screen_id))


static func insert_after_in(src: String, chapter: String, scene_title: String, file_id: String, screen_id: String, label: String, after_screen_id: String) -> String:
	var doc := parse(src)
	var target := "scene:%s/%s" % [file_id, screen_id]
	_detach(doc, target)
	var ch := _ensure_chapter(doc, chapter)
	var sc := _ensure_scene(ch, scene_title)
	var screens: Array = sc["screens"]
	var row := _authored(file_id, screen_id, label)
	var anchor := "scene:%s/%s" % [file_id, after_screen_id]
	var at := screens.size()
	for i in screens.size():
		if str(screens[i].get("target", "")) == anchor:
			at = i + 1
			break
	screens.insert(at, row)
	return render(doc)


static func remove_screen(file_id: String, screen_id: String) -> void:
	save_text(remove_in(text(), file_id, screen_id))


static func remove_in(src: String, file_id: String, screen_id: String) -> String:
	var doc := parse(src)
	if not _detach(doc, "scene:%s/%s" % [file_id, screen_id]):
		return src
	return render(doc)


## Move a screen earlier (dir -1) or later (dir 1) inside its scene. No-op at the edge or if it is not listed.
static func move_screen(file_id: String, screen_id: String, dir: int) -> void:
	save_text(move_in(text(), file_id, screen_id, dir))


static func move_target(target: String, dir: int) -> void:
	save_text(move_target_in(text(), target, dir))


static func move_target_in(src: String, target: String, dir: int) -> String:
	var doc := parse(src)
	for ch in doc["chapters"]:
		for sc in ch.get("scenes", []):
			var screens: Array = sc["screens"]
			for i in screens.size():
				if str(screens[i].get("target", "")) != target:
					continue
				var j := i + dir
				if j < 0 or j >= screens.size():
					return src
				var tmp: Variant = screens[i]
				screens[i] = screens[j]
				screens[j] = tmp
				return render(doc)
	return src


static func move_in(src: String, file_id: String, screen_id: String, dir: int) -> String:
	return move_target_in(src, "scene:%s/%s" % [file_id, screen_id], dir)


static func rename_screen(file_id: String, old_id: String, new_id: String) -> void:
	save_text(rename_in(text(), file_id, old_id, new_id))


static func rename_in(src: String, file_id: String, old_id: String, new_id: String) -> String:
	var doc := parse(src)
	var old_t := "scene:%s/%s" % [file_id, old_id]
	var found := false
	for ch in doc["chapters"]:
		for sc in ch.get("scenes", []):
			for s in sc.get("screens", []):
				if str(s.get("target", "")) != old_t:
					continue
				s["id"] = file_id
				s["screen"] = new_id
				s["target"] = "scene:%s/%s" % [file_id, new_id]
				if str(s.get("label", "")) == old_id:
					s["label"] = new_id
				found = true
	return render(doc) if found else src


static func set_label(file_id: String, screen_id: String, label: String) -> void:
	save_text(set_label_in(text(), file_id, screen_id, label))


static func set_label_in(src: String, file_id: String, screen_id: String, label: String) -> String:
	var doc := parse(src)
	var target := "scene:%s/%s" % [file_id, screen_id]
	for ch in doc["chapters"]:
		for sc in ch.get("scenes", []):
			for s in sc.get("screens", []):
				if str(s.get("target", "")) != target:
					continue
				if str(s.get("label", "")) == label:
					return src
				s["label"] = label
				return render(doc)
	return src


static func _screen_from_line(body: String) -> Dictionary:
	if body == "":
		return {}
	var label := ""
	var token := body
	for sep in [" — ", " -- "]:
		var at := body.find(sep)
		if at >= 0:
			token = body.substr(0, at).strip_edges()
			label = body.substr(at + sep.length()).strip_edges()
			break
	token = token.split(" ", false)[0]
	if token.begins_with("intro:"):
		var id := token.substr(6).strip_edges()
		if id == "" or id.contains("/"):
			return {}
		return {"kind": "intro", "id": id, "screen": "", "label": label, "target": "intro:" + id}
	if token.begins_with("scene:"):
		var rest := token.substr(6).strip_edges()
		var id := rest.get_slice("/", 0).strip_edges()
		var screen := rest.get_slice("/", 1).strip_edges() if rest.contains("/") else ""
		if id == "":
			return {}
		var target := "scene:%s/%s" % [id, screen] if screen != "" else "scene:" + id
		return {"kind": "scene", "id": id, "screen": screen, "label": label, "target": target}
	return {}


static func _authored(file_id: String, screen_id: String, label: String) -> Dictionary:
	return {
		"kind": "scene",
		"id": file_id,
		"screen": screen_id,
		"label": label.strip_edges(),
		"target": "scene:%s/%s" % [file_id, screen_id],
	}


static func _detach(doc: Dictionary, target: String) -> bool:
	var found := false
	for ch in doc["chapters"]:
		for sc in ch.get("scenes", []):
			var screens: Array = sc["screens"]
			for i in range(screens.size() - 1, -1, -1):
				if str(screens[i].get("target", "")) == target:
					screens.remove_at(i)
					found = true
	return found


static func move_subscene(target: String, chapter: String, scene_title: String, anchor: String, after: bool) -> void:
	save_text(move_subscene_in(text(), target, chapter, scene_title, anchor, after))


static func move_subscene_in(src: String, target: String, chapter: String, scene_title: String, anchor: String, after: bool) -> String:
	if target == "" or chapter.strip_edges() == "" or scene_title.strip_edges() == "":
		return src
	if target == anchor and not after:
		return src
	var doc := parse(src)
	var dest: Dictionary = {}
	for ch in doc["chapters"]:
		if str(ch.get("title", "")) != chapter.strip_edges():
			continue
		for sc in ch.get("scenes", []):
			if str(sc.get("title", "")) == scene_title.strip_edges():
				dest = sc
				break
	if dest.is_empty():
		return src
	var row := _take_screen(doc, target)
	if row.is_empty():
		return src
	var screens: Array = dest["screens"]
	var at := screens.size()
	if anchor != "" and anchor != target:
		for i in screens.size():
			if str(screens[i].get("target", "")) == anchor:
				at = i + 1 if after else i
				break
	screens.insert(at, row)
	return render(doc)


static func move_scene(from_chapter: String, from_scene: String, to_chapter: String, anchor_scene: String, after: bool) -> void:
	save_text(move_scene_in(text(), from_chapter, from_scene, to_chapter, anchor_scene, after))


static func move_scene_in(src: String, from_chapter: String, from_scene: String, to_chapter: String, anchor_scene: String, after: bool) -> String:
	if from_chapter.strip_edges() == "" or from_scene.strip_edges() == "" or to_chapter.strip_edges() == "":
		return src
	if from_chapter == to_chapter and from_scene == anchor_scene:
		return src
	var doc := parse(src)
	var moving: Dictionary = {}
	for ch in doc["chapters"]:
		if str(ch.get("title", "")) != from_chapter:
			continue
		var scenes: Array = ch["scenes"]
		for i in scenes.size():
			if str(scenes[i].get("title", "")) != from_scene:
				continue
			moving = scenes[i]
			scenes.remove_at(i)
			break
	if moving.is_empty():
		return src
	var dest: Dictionary = {}
	for ch in doc["chapters"]:
		if str(ch.get("title", "")) == to_chapter:
			dest = ch
			break
	if dest.is_empty():
		return src
	var scenes: Array = dest["scenes"]
	var at := scenes.size()
	if anchor_scene != "":
		for i in scenes.size():
			if str(scenes[i].get("title", "")) == anchor_scene:
				at = i + 1 if after else i
				break
	scenes.insert(at, moving)
	return render(doc)


static func move_chapter(title: String, anchor: String, after: bool) -> void:
	save_text(move_chapter_in(text(), title, anchor, after))


static func move_chapter_in(src: String, title: String, anchor: String, after: bool) -> String:
	if title.strip_edges() == "" or title == anchor:
		return src
	var doc := parse(src)
	var moving: Dictionary = {}
	var chs: Array = doc["chapters"]
	for i in chs.size():
		if str(chs[i].get("title", "")) != title:
			continue
		moving = chs[i]
		chs.remove_at(i)
		break
	if moving.is_empty():
		return src
	var at := chs.size()
	if anchor != "":
		for i in chs.size():
			if str(chs[i].get("title", "")) == anchor:
				at = i + 1 if after else i
				break
	chs.insert(at, moving)
	return render(doc)


static func _take_screen(doc: Dictionary, target: String) -> Dictionary:
	for ch in doc["chapters"]:
		for sc in ch.get("scenes", []):
			var screens: Array = sc["screens"]
			for i in screens.size():
				if str(screens[i].get("target", "")) != target:
					continue
				var row: Dictionary = screens[i]
				screens.remove_at(i)
				return row
	return {}


static func add_chapter(title: String) -> void:
	var name := title.strip_edges()
	if name == "":
		return
	save_text(add_chapter_in(text(), name))


static func add_chapter_in(src: String, title: String) -> String:
	var doc := parse(src)
	_ensure_chapter(doc, title)
	return render(doc)


static func add_scene(chapter: String, title: String) -> void:
	var ch := chapter.strip_edges()
	var name := title.strip_edges()
	if ch == "" or name == "":
		return
	save_text(add_scene_in(text(), ch, name))


static func add_scene_in(src: String, chapter: String, title: String) -> String:
	var doc := parse(src)
	var ch := _ensure_chapter(doc, chapter)
	_ensure_scene(ch, title)
	return render(doc)


static func _ensure_chapter(doc: Dictionary, title: String) -> Dictionary:
	var want := title.strip_edges()
	for ch in doc["chapters"]:
		if str(ch.get("title", "")) == want:
			return ch
	var ch := {"title": want, "note": "", "scenes": []}
	(doc["chapters"] as Array).append(ch)
	return ch


static func _ensure_scene(ch: Dictionary, title: String) -> Dictionary:
	var want := title.strip_edges()
	for sc in ch["scenes"]:
		if str(sc.get("title", "")) == want:
			return sc
	var sc := {"title": want, "screens": []}
	(ch["scenes"] as Array).append(sc)
	return sc


static func _default_header() -> String:
	return """# Story outline

Play order. The title screen is not on this list.

Three levels: a chapter (`## `), a scene (`### `), then its subscenes (`- intro:` or `- scene:`). NEXT walks the subscenes in order. The debug menu has one button per scene, and opens that scene's first subscene. Reordering does not need a Build. A new scene file still needs one Build.

Words after \" — \" are a note. A line under a chapter, before its first scene, is a note. Indented lines are ignored.

Scene Writer: Chapter, Scene, then the subscenes. Add, Earlier, Later, On the list.
"""
