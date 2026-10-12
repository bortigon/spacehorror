extends "res://templates/pda_screen.gd"
## AUTHORED SCENE RUNNER: plays a scene written with the Scene Writer (story/scenes/<id>.json).
##
## Built scenes (scenes/authored/<id>.tscn) are inherited scenes of pda_screen.tscn with this
## script and `scene_path` set. templates/authored_scene.tscn is the same runner with no path:
## it plays PdaScreen.next_authored (set by go_target("scene:<id>")).
##
## Every screen opens on a StoryStage (ui/story_stage.gd) over the PDA background; the O2 bar
## and the read-only minimap sit top-right / bottom-right like the intro. After a choice or the
## countdown button, the next screen opens with the question + the response pinned at the top.
## Death endings use the generic death screen (show_death). Format: docs/SCENE_WRITER.md.
##
## Scene "ui": "game" puts the stage inside the main game UI instead (header + O2, tab rail,
## title = scene title, minimap; the full map opens). "fade_in" fades the scene in from black.
## "map_tour" ending: HIGHLIGHT + TIP walkthrough of the full map (ui/map_tour.gd), then
## (move_to) the player clicks rooms to move until they reach that room ("on_arrive" ops run
## on the still-open map, e.g. map_restrict_room). "hold" ending: the scene stops there
## (CONTINUE only when the end / scene has a next target).
##
## Debug args (after "--"): --screen=ID  --at=SECONDS  --freeze  --complete  --pick=N
##                          --qte_left=SECONDS  --no_fade  --open_map
##                          --open_window=character|ACT_ID (container window pair / character screen)
##                          --tour_step=N|move  --map_room=ID  --map_click=ID
##                          --tutorial_step=N (start the inventory walkthrough at tip N; windows
##                          opened with --open_window and --no_tutorial skip it)
##                          (plus the template's --shot / --die / ...)

const StageScript := preload("res://ui/story_stage.gd")
const SceneData := preload("res://ui/story_scene.gd")
const DEATH_BEAT := 1.2          # seconds between a death screen's text and SIGNAL LOST
const ARRIVE_WAIT := 0.9         # walkthrough: seconds on the map after reaching move_to
const ARRIVE_OPS_AT := 0.6       # ... with "on_arrive" ops: they run this long after arriving
const ARRIVE_OPS_WAIT := 2.4     # ... and the map closes this long after arriving
const UNSUITED_WARNING := "Warning: Going on Excursion without a suit is inadvisable. Do you wish to proceed anyway?"

@export_file("*.json") var scene_path := ""

var scene: Dictionary = {}
var screens: Array = []
var stage: StoryStage
var overlay: Control
var hud_o2: O2Bar
var hud_map: ShipMapView
var hud_map_frame: VBoxContainer
var screen_index := -1
var _prev_index := -1
var _death_beat := -1.0
var load_error := ""
var game_ui := false                   # scene "ui": "game"
var fade_rect: ColorRect               # scene "fade_in": black that fades out at the start
var _fade_tween: Tween
var tour: MapTour                      # map walkthrough (HIGHLIGHT + TIP)
var guide_phase := ""                  # "" | "tip": the inventory walkthrough (screen "tutorial")
var guide_step := 0
var guide_id := ""
var _guide_steps: Array = []
var tour_phase := ""                   # "" | "tip" | "move" | "arrived"
var tour_step := 0                     # 0-based tip index
var _tour_pending: Variant = null      # tip index (int) or "move" to open after the text
var _tour_token := 0
var _skip_record := false
var _dbg: Dictionary = {}


func _setup_story() -> void:
	var path := scene_path if scene_path != "" else next_authored
	next_authored = ""
	if path == "":
		load_error = "No scene to play (scene_path is empty)."
	else:
		scene = SceneData.load_file(path)
		if scene.is_empty():
			load_error = SceneData.last_error
	screens = scene.get("screens", [])
	passages = {&"authored": {"title": str(scene.get("title", "")), "no_history": true, "body": ""}}
	start_passage = &"authored"
	game_ui = str(scene.get("ui", "stage")) == "game"
	ensure_vessel_map()
	_build_overlay()
	map_moved.connect(_on_map_moved)
	map_door_activated.connect(_on_door_activated)
	if float(scene.get("fade_in", 0.0)) > 0.0:
		fade_rect = ColorRect.new()
		fade_rect.name = "SceneFade"
		fade_rect.color = Color.BLACK
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(fade_rect)
		move_child(fade_rect, pause_menu.get_index())   # over everything but the pause menu
	var bg := str(scene.get("background", ""))
	if bg != "" and ResourceLoader.exists(bg):
		set_backdrop(load(bg) as Texture2D, float(scene.get("background_alpha", 0.12)))
	var amb := str(scene.get("ambience", ""))
	if amb != "" and ResourceLoader.exists(amb):
		ambience.stop()
		ambience.stream = load(amb) as AudioStream
		_start_ambience()


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.name = "Authored"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	move_child(overlay, safe_area.get_index() + 1)
	stage = StageScript.new()
	stage.name = "Stage"
	stage.base_speed = float(scene.get("speed", 40))
	stage.text_filter = func(s: String) -> String: return _apply_vars(_apply_conditions(s))
	stage.choice_filter = func(c: Dictionary) -> bool: return check_condition(str(c.get("if", "")))
	overlay.add_child(stage)
	stage.continue_pressed.connect(_on_continue)
	stage.choice_pressed.connect(_on_choice)
	stage.qte_pressed.connect(_on_qte_pressed)
	stage.qte_expired.connect(_on_qte_expired)
	stage.qte_tick.connect(_on_qte_tick)
	stage.typing_done.connect(_on_typing_done)
	stage.action_taken.connect(_on_action)
	stage.act_is_done = _act_already_done
	stage.container_handler = _open_container
	stage.act_opened.connect(_on_act_opened)
	if game_ui:
		_embed_stage()
	elif bool(scene.get("show_hud", true)):
		_build_hud()


## "ui": "game": the stage replaces the story text of the LOG tab; the main UI (header + O2,
## tab rail, title, ACTIONS column with the minimap) stays around it.
func _embed_stage() -> void:
	overlay.remove_child(stage)
	stage.set_embedded(true)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = story_text.size_flags_stretch_ratio
	log_view.add_child(stage)
	log_view.move_child(stage, story_text.get_index())
	story_text.hide()
	var header := log_view.get_node_or_null("ChoicesCol/ChoicesHeader") as Control
	if header:
		header.hide()   # no ACTIONS list here: the stage has its own CONTINUE


## O2 bar top-right + read-only minimap bottom-right (same spots as the intro overlay).
func _build_hud() -> void:
	hud_map_frame = VBoxContainer.new()
	hud_map_frame.name = "HudMap"
	hud_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_map_frame.add_theme_constant_override("separation", 3)
	hud_map_frame.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hud_map_frame.offset_left = -294.0
	hud_map_frame.offset_right = -14.0
	hud_map_frame.offset_top = -179.0
	hud_map_frame.offset_bottom = -10.0
	hud_map_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud_map_frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var lbl := Label.new()
	lbl.theme_type_variation = &"OsLabelDim"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = "%s // MAP" % str(vessel_map.get("title", "VESSEL")).to_upper()
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var host := Control.new()
	host.custom_minimum_size = Vector2(0, 150)
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_map = ShipMapView.new()
	hud_map.name = "HudMiniMap"
	hud_map.compact = true
	hud_map.interactive = false
	hud_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(hud_map)
	hud_map_frame.add_child(lbl)
	hud_map_frame.add_child(host)
	overlay.add_child(hud_map_frame)
	register_map_view(hud_map)
	hud_o2 = O2Bar.new()
	hud_o2.name = "HudO2"
	hud_o2.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud_o2.offset_left = -264.0
	hud_o2.offset_right = -64.0
	hud_o2.offset_top = 8.0
	hud_o2.offset_bottom = 8.0 + O2Bar.TOTAL_H
	overlay.add_child(hud_o2)
	register_o2_bar(hud_o2)


func _begin() -> void:
	_show_frame()
	if screens.is_empty():
		stage.play({"heading": "SCENE WRITER", "text": "This scene could not be played.\n" +
			(load_error if load_error != "" else "It has no screens."), "end": {"type": "death"}},
			{"title": "REC-7 // SCENE ERROR", "complete": true})
		push_error("AuthoredScene: " + (load_error if load_error != "" else "no screens"))
		return
	var d := _read_debug_args()
	_dbg = d
	if game_ui and not vars.has("rail_tabs"):
		# started straight here (debug mission select): sensible buttons. The onboarding screen of
		# EXCURSION 1 // PREP replaces this with STA only when it runs.
		var tabs := ["sta", "map"]
		if str(scene.get("id", "")) == "airlock" or has_flag("searched_locker"):
			tabs.insert(1, "inv")
		vars["rail_tabs"] = tabs
	# Mission select sets this carry flag to open the map walkthrough already finished:
	# tour overlay gone, map open, waiting for the move_to click. Consumed here.
	var tour_move := has_flag("dev_tour_move")
	if tour_move:
		flags.erase("dev_tour_move")
	if game_ui:
		goto(&"authored")   # title, OS line, LOG tab
	var want := str(d.get("screen", next_screen))
	next_screen = ""
	if tour_move and want == "":
		for i in screens.size():
			var end: Dictionary = (screens[i] as Dictionary).get("end", {})
			if str(end.get("type", "")) == "map_tour":
				want = str((screens[i] as Dictionary).get("id", ""))
				break
	var idx := maxi(0, find_screen(want)) if want != "" else 0
	if want.is_valid_int() and find_screen(want) < 0:
		idx = clampi(int(want) - 1, 0, screens.size() - 1)
	if idx > 0:
		_debug_prepare_screens(idx)
	if d.has("map_room"):
		map_set_room(StringName(str(d["map_room"])))   # before a --map_click on a walk phase
	if d.has("tour_step"):
		var ts := str(d["tour_step"])
		_tour_pending = "move" if ts == "move" else maxi(0, int(ts) - 1)
	elif tour_move:
		_tour_pending = "move"   # same path as --tour_step=move: tips do not replay
	enter_screen(idx)
	if d.has("map_room"):
		map_set_room(StringName(str(d["map_room"])))
	if d.has("open_map"):
		open_map()
		if d.has("map_click") and tour_phase == "":
			var mc := str(d["map_click"])
			d.erase("map_click")
			map_try_move(mc)   # free walking (outside a walkthrough): moves or shows the refusal
	if d.has("open_window"):
		# --open_window=character | <container act id>, for layout checks (with --shot).
		stage.skip_typing(true)
		if str(d["open_window"]) == "character":
			show_inv()
		else:
			stage.open_act(str(d["open_window"]))
	_start_fade(not d.has("no_fade") and idx == 0)
	if d.has("complete"):
		stage.skip_typing()
	if d.has("pick"):
		stage.skip_typing()
		stage.pick(int(str(d["pick"])))
	if d.has("at"):
		stage.seek(float(str(d["at"])))
	if d.has("qte_left"):
		stage.skip_typing()
		stage.qte_seek(float(str(d["qte_left"])))
	if d.has("freeze"):
		stage.frozen = true


## Debug --screen jump past earlier screens: apply their state ops (map / flags / vars / items /
## O2) so the jumped-to screen looks like it does in play. Navigation ops are skipped.
func _debug_prepare_screens(idx: int) -> void:
	for k in mini(idx, screens.size()):
		for op: Variant in (screens[k] as Dictionary).get("on_enter", []):
			var n := str(op).get_slice(":", 0).strip_edges()
			if n.begins_with("map_") or n in ["o2_full", "set_flag", "clear_flag", "set_var", "give_item",
					"take_item", "unlock_dossier", "lock_tab", "unlock_tab"]:
				run_op(op)
	_after.clear()


func find_screen(id: String) -> int:
	for i in screens.size():
		if str(screens[i].get("id", "")) == id:
			return i
	return -1


func current_screen() -> Dictionary:
	return screens[screen_index] if screen_index >= 0 and screen_index < screens.size() else {}


## Opens screen i (a NEW screen: pinned question / response at the top when given).
func enter_screen(i: int, pin_q := "", pin_r := "") -> void:
	if i < 0 or i >= screens.size():
		push_warning("AuthoredScene: no screen %d" % i)
		return
	_death_beat = -1.0
	if windows != null:
		windows.close_all(true)   # a new screen never starts under an open window
	if i != screen_index:
		_prev_index = screen_index
	screen_index = i
	var scr: Dictionary = screens[i]
	current_id = &"authored"
	if not _skip_record:
		dev_push_screen(screen_label(i), _reenter_screen.bind(i, pin_q, pin_r, _prev_index))
	_skip_record = false
	_show_frame()
	overlay.show()
	for op: Variant in scr.get("on_enter", []):
		run_op(op)
	var end: Dictionary = scr.get("end", {})
	var hold_target := _order_target(str(end.get("goto", "")) if str(end.get("goto", "")) != "" else str(scene.get("after", "")))
	if str(end.get("exit", "")) != "":
		hold_target = ""   # the way out is the door on the map, not a CONTINUE button
	if bool(scr.get("onboarding", false)) and onboarding_active():
		set_rail_tabs(["sta"])        # EXCURSION 1 // PREP: the menu starts with STA only, no minimap
	stage.play(scr, {"speed": scene.get("speed", 40), "title": "" if is_room_screen(i) else scene.get("title", ""),
		"pin_q": pin_q, "pin_r": pin_r, "hold_next": hold_target != ""})
	_refresh_maps()   # the screen's markers (LOCKER, COFFEE POT) and clickable door
	set_title("" if is_room_screen(i) else str(scene.get("title", "")))   # A) no scene title over a room
	if str(end.get("type", "")) == "map_tour" and str(scr.get("text", "")).strip_edges() == "" \
			and str(scr.get("heading", "")).strip_edges() == "":
		stage.skip_typing(true)   # nothing to type: the walkthrough opens straight away
	refresh(0.6)
	_flush_after()


## A room screen (READY ROOM, STASIS-3, AIR LOCK: a hold whose on_enter puts the player in a room)
## shows only its heading, not the scene title above it (no "NEW SCENE" over READY ROOM).
func is_room_screen(i: int) -> bool:
	if i < 0 or i >= screens.size():
		return false
	var scr: Dictionary = screens[i]
	if str((scr.get("end", {}) as Dictionary).get("type", "")) != "hold":
		return false
	for op: Variant in scr.get("on_enter", []):
		if str(op).begins_with("map_set_room:"):
			return true
	return false


# ---------------------------------------------------------------- ROOM TRANSITION
## Every room change (the walkthrough's first walk into the READY ROOM, READY ROOM <-> STASIS-3, out
## through the air lock): fade to black with ROOM_TRANSITION_SFX, the new room is set up while it is
## dark, then it fades back in and the room text starts TYPING fresh (held until the fade is gone).
const ROOM_TRANSITION_SFX := "res://assets/sounds/dooropen.mp3"
const AIRLOCK_TRANSITION_SFX := "res://assets/sounds/airlockdoor.mp3"
var room_transitions := 0     # how many ran (tests)


func room_transition(mid: Callable, sfx := ROOM_TRANSITION_SFX) -> void:
	room_transitions += 1
	if map_overlay.visible and not map_locked_open:
		map_overlay.hide()
	fade_through(_transition_dark.bind(mid), sfx, -4.0, _transition_done)


func _transition_dark(mid: Callable) -> void:
	mid.call()
	if stage != null:
		stage.frozen = true      # typing waits for the fade-in


func _transition_done() -> void:
	if stage != null and not _dbg.has("freeze"):
		stage.frozen = false


func screen_label(i: int) -> String:
	return "%s/%s" % [scene.get("id", "?"), (screens[i] as Dictionary).get("id", i)]


## Stage mode: the story stage over the PDA background. Game mode: the main UI around it.
func _show_frame() -> void:
	safe_area.visible = game_ui
	journal_button.visible = false      # the little menu button is gone from the game HUD (Esc = pause menu)
	if game_ui:
		set_excursion_chrome(true)
		stage.act_hours_live = time_blocks_live


func _start_fade(on: bool) -> void:
	if fade_rect == null:
		return
	if _fade_tween:
		_fade_tween.kill()
	if not on:
		fade_rect.hide()
		return
	fade_rect.show()
	fade_rect.modulate.a = 1.0
	var hold_text := not stage.frozen
	var hold_voice := hold_text and stage.voice.playing
	if hold_text:
		stage.frozen = true    # the text (and its voice clip) start once the scene is visible
	if hold_voice:
		stage.voice.stream_paused = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "modulate:a", 0.0, float(scene.get("fade_in", 0.0)))
	_fade_tween.tween_callback(func() -> void:
		fade_rect.hide()
		if hold_voice and not stage.paused:
			stage.voice.stream_paused = false
		if hold_text and not _dbg.has("freeze"):
			stage.frozen = false)


func _reenter_screen(i: int, pin_q: String, pin_r: String, prev: int) -> void:
	screen_index = -1
	enter_screen(i, pin_q, pin_r)
	_prev_index = prev


const SceneOrder := preload("res://ui/scene_order.gd")


## "order:next" always counts as a destination: the next screen, or the unwritten screen.
func _order_target(t: String) -> String:
	if t.strip_edges() == SceneOrder.SENTINEL:
		return SceneOrder.SENTINEL
	return t


func _show_unwritten() -> void:
	stage.play({
		"heading": "",
		"text": SceneOrder.UNWRITTEN,
		"speed": 0,
		"end": {"type": "hold", "goto": ""},
	}, {"title": str(scene.get("title", "")), "complete": true, "hold_next": false})


## "order:next" opens the next screen in story/SCENE_ORDER.md. Same scene stays loaded.
## Nothing after this screen: one line, "The next scene isn't written."
func _follow_order(pin_q: String, pin_r: String) -> void:
	var here := "scene:%s/%s" % [str(scene.get("id", "")), str(current_screen().get("id", ""))]
	var t := SceneOrder.next_after(here)
	if t == "":
		_show_unwritten()
		return
	if t.begins_with("scene:"):
		var rest := t.substr(6)
		var sid := rest.get_slice("/", 0)
		var scr := rest.get_slice("/", 1) if rest.contains("/") else ""
		if sid == str(scene.get("id", "")):
			var idx := 0 if scr == "" else find_screen(scr)
			if scr == "" or idx >= 0:
				enter_screen(idx, pin_q, pin_r)
				return
	stage.stop()
	go_target(t)


## Follows a target: "next" / "" = next screen in this scene (or the scene's "after" at the end),
## a screen id, "order:next" = the next screen in story/SCENE_ORDER.md,
## or any go_target() link (scene:, intro:, tscn:, passage).
func go(target: String, pin_q := "", pin_r := "") -> void:
	var t := target.strip_edges()
	if t == SceneOrder.SENTINEL:
		_follow_order(pin_q, pin_r)
		return
	if t == "" or t == "next":
		if screen_index + 1 < screens.size():
			enter_screen(screen_index + 1, pin_q, pin_r)
		elif str(scene.get("after", "")) != "":
			go(str(scene["after"]))
		else:
			push_warning("AuthoredScene: end of scene '%s' and no \"after\" target" % scene.get("id", ""))
		return
	var idx := find_screen(t)
	if idx >= 0:
		enter_screen(idx, pin_q, pin_r)
		return
	stage.stop()
	go_target(t)


## An act with a "log" key (RSV ABEYANCE) files its text as a LOG entry once discovered. In the game
## UI it opens the LOG pop-up on that entry instead of replacing the story text (_open_container);
## elsewhere (no windows) it still reads as a function with Back.
func _on_act_opened(_act_id: String, spec: Dictionary) -> void:
	_file_act_log(_act_id, spec)


func _file_act_log(act_id: String, spec: Dictionary) -> String:
	var lg: Variant = spec.get("log", null)
	if not (lg is Dictionary):
		return ""
	var eid := str((lg as Dictionary).get("id", act_id))
	file_log_entry(eid, str((lg as Dictionary).get("title", eid.to_upper())), str(spec.get("text", "")),
		str((lg as Dictionary).get("filed", "SHIP LOG")), str((lg as Dictionary).get("category", "SHIP")))
	return eid


func _on_action(_act_id: String, action: Dictionary) -> void:
	var hrs := int(action.get("hours", 0))
	var why := hours_refusal(hrs)
	if why != "":
		os_toast(why)   # not enough hours: nothing happens
		return
	var item := str(action.get("item", "")).strip_edges()
	if item != "":
		var id := StringName(item)
		var prev: Dictionary = items.get(id, {})
		prev["label"] = str(action.get("label", item))
		prev["desc"] = str(action.get("detail", ""))
		items[id] = prev
		mark_item_taken(item)
		give_item(id)
	if hrs > 0:
		spend_hours(hrs)
	stage.act_hours_live = time_blocks_live


## A container act ("container": true) opens the window pair: character screen + this container.
## A container with "search": {"hours": 1, "text": "..."} asks first (Yes / No); Yes spends the hours,
## fades out and back, and opens the window. Every opening is a new search and costs the hours again.
## A station act ("station": "coffee") opens its own window (the coffee pot).
func _open_container(act_id: String, spec: Dictionary) -> void:
	_ensure_windows()
	if spec.has("log") and not bool(spec.get("container", false)):
		open_log(_file_act_log(act_id, spec))     # RSV ABEYANCE: the LOG pop-up on that entry
		return
	if spec.has("station"):
		open_station(act_id, spec)
		return
	if _suit_busy or (confirm_box != null and confirm_box.visible):
		return
	var search: Variant = spec.get("search", null)
	if search is Dictionary and int((search as Dictionary).get("hours", 0)) > 0:
		_ask_search(act_id, spec, search as Dictionary)
		return
	_show_container(act_id, spec)


func _show_container(act_id: String, spec: Dictionary) -> void:
	windows.taken_check = _container_item_in_inventory
	var sp := spec.duplicate(true)
	var extras := container_extras(act_id)      # what the player put in earlier
	if not extras.is_empty():
		var list: Array = sp.get("items", [])
		list.append_array(extras)
		sp["items"] = list
	play_sfx(&"tap")
	windows.open_container(act_id, sp)
	if not tab_revealed("inv"):
		reveal_tab("inv")         # the first locker opening earns the INV button (turns on like a hologram)
	maybe_start_tutorial("drag")      # the first container window: how to take things (then the inventory tips)


## A container is paid for ONCE: after the first search (flag searched_<act>) it opens for free.
func _ask_search(act_id: String, spec: Dictionary, search: Dictionary) -> void:
	if has_flag("searched_" + act_id):
		_show_container(act_id, spec)
		return
	var hrs := int(search.get("hours", 1))
	var text := str(search.get("text", "Searching will take %s. Are you sure?" % PdaScreen.hours_label(hrs)))
	ask_confirm(text, _search_yes.bind(act_id, spec, hrs))     # no tip before answering (it interrupted)


func _search_yes(act_id: String, spec: Dictionary, hrs: int) -> void:
	var why := hours_refusal(hrs)
	if why != "":
		os_toast(why)     # not enough hours: nothing happens
		play_sfx(&"close")
		return
	spend_hours(hrs)
	flags["searched_" + act_id] = true    # paid once: later openings are free, no prompt
	stage.act_hours_live = time_blocks_live
	# the search takes the hour (fade), the LOCKER marker loses its orange border, and THEN the time
	# tips explain what was spent. Nothing opens: the player clicks the (searched, free) locker again.
	fade_through(_refresh_maps, "", -4.0, func() -> void: maybe_start_tutorial("time"))


func _container_item_in_inventory(_act_id: String, item: Dictionary) -> bool:
	if bool(item.get("extra", false)):
		return false      # put in by the player: it is in the container now
	return item_ever_taken(str(item.get("id", "")).strip_edges())


## Taking an item from a container: same flags / items / hours as the old act choices. The hours are
## really spent (the ready room arms the hour blocks); too few left = refused before this runs.
func _on_container_item_taken(act_id: String, item: Dictionary) -> void:
	if act_id == FLOOR_ACT:
		super(act_id, item)
		return
	if bool(item.get("extra", false)):
		_forget_extra(act_id, str(item.get("id", "")))
	_on_action(act_id, {"label": str(item.get("label", "")), "hours": int(item.get("hours", 0)),
		"item": str(item.get("id", "")), "detail": str(item.get("detail", "")),
		"required": bool(item.get("required", false))})


func _act_already_done(_act_id: String, action: Dictionary) -> bool:
	var item := str(action.get("item", "")).strip_edges()
	return item != "" and item_ever_taken(item)


# ---------------------------------------------------------------- map markers + the exit door

## The acts of this screen that have a "marker" get a labelled green rectangle on the map
## (e.g. LOCKER, COFFEE POT inside the ready room). Clicking it opens the act's window.
func _scene_map_markers() -> Array:
	var out: Array = []
	var acts: Variant = current_screen().get("acts", {})
	if not (acts is Dictionary):
		return out
	for aid: Variant in (acts as Dictionary):
		var spec: Dictionary = (acts as Dictionary)[aid]
		if not (spec.get("marker", null) is Dictionary):
			continue
		var m: Dictionary = spec["marker"]
		var search: Variant = spec.get("search", null)
		var costs := search is Dictionary and int((search as Dictionary).get("hours", 0)) > 0 \
			and not has_flag("searched_" + str(aid))
		out.append({"id": str(aid), "kind": "act", "room": str(m.get("room", "ready_room")), "cost": costs,
			"label": str(m.get("label", spec.get("title", aid))), "rect": m.get("rect", [0.03, 0.05, 0.25, 0.17])})
	return out


func _on_map_station_clicked(id: String) -> void:
	if map_overlay.visible and not map_locked_open:
		close_map()      # clicked on the full map: back to the room text (STA) first, then the act opens
	if stage != null:
		stage.open_act_root(id)


## "end": {"type": "hold", "exit": "door:ready_room|airlock"}: the scene is left through that door.
func exit_door_key() -> String:
	var ex := str((current_screen().get("end", {}) as Dictionary).get("exit", "")).strip_edges()
	if not ex.begins_with("door:"):
		return ""
	var parts := ex.substr(5).split("|", false)
	if parts.size() < 2:
		return ""
	var d := map_door_between(parts[0].strip_edges(), parts[1].strip_edges())
	return ShipMapView.door_key(d) if not d.is_empty() else ""


func _map_click_doors() -> Array:
	var k := exit_door_key()
	if k == "":
		return []
	var parts := k.split("|")
	var d := map_door_between(parts[0], parts[1])
	return [k] if str(d.get("state", "open")) == "open" else []


## The unlocked exit door was clicked: with the suit on the scene moves on; without it the player is
## warned first. Yes = go anyway (flags["went_without_suit"]); No = stay.
func _on_door_activated(key: String) -> void:
	if exit_door_key() == "" or key != exit_door_key():
		return
	if windows_open() or _suit_busy or (confirm_box != null and confirm_box.visible):
		return
	if suit_is_worn():
		_leave_through_exit()
	else:
		ask_confirm(UNSUITED_WARNING, _exit_without_suit)


func _exit_without_suit() -> void:
	flags["went_without_suit"] = true
	vars["went_without_suit"] = true
	_leave_through_exit()


## Leaving through the exit door: a fade to black, then the next scene (it fades in itself).
func _leave_through_exit() -> void:
	var end: Dictionary = current_screen().get("end", {})
	if map_overlay.visible and not map_locked_open:
		close_map()
	leaving = true
	room_transitions += 1        # a ROOM TRANSITION into the next scene (it fades itself back in, typing after)
	fade_through(go.bind(str(end.get("goto", "")) if str(end.get("goto", "")) != "" else str(scene.get("after", ""))),
		AIRLOCK_TRANSITION_SFX)


var leaving := false     # the exit door was taken (the fade is running / the next scene loads)


func _on_continue() -> void:
	if onboarding_blocks():
		return      # the onboarding tips run first: no CONTINUE until they are done
	var end: Dictionary = current_screen().get("end", {})
	play_sfx(&"tap")
	var need := str(end.get("require", "")).strip_edges()
	if need != "" and StringName(need) not in inventory:
		os_toast(need.to_upper() + " REQUIRED")
		return
	if str(end.get("type", "")) == "hold":
		go(str(end.get("goto", "")) if str(end.get("goto", "")) != "" else str(scene.get("after", "")))
		return
	go(str(end.get("goto", "next")))


func _on_choice(index: int) -> void:
	var list: Array = (current_screen().get("end", {}) as Dictionary).get("choices", [])
	if index < 0 or index >= list.size():
		return
	var c: Dictionary = list[index]
	play_sfx(&"tap")
	var q := stage.question_text()
	var r := "> " + _apply_vars(str(c.get("label", "")))
	_pending_goto = &""
	for op: Variant in c.get("ops", []):
		run_op(op)
	var target := str(c.get("goto", "next"))
	if _pending_goto != &"":
		target = str(_pending_goto)
		_pending_goto = &""
	go(target, q, r)
	_flush_after()


func _on_qte_pressed() -> void:
	var end: Dictionary = current_screen().get("end", {})
	play_sfx(&"tap")
	refill_o2(1.5)
	go(str(end.get("goto", "next")), stage.question_text(), "> " + _apply_vars(str(end.get("label", ""))))


func _on_qte_tick(left: float) -> void:
	var stepped := ceilf(left * O2Bar.TICKS - 0.0001) / O2Bar.TICKS * 100.0
	set_o2(stepped, lerpf(0.35, 1.0, 1.0 - left))


func _on_qte_expired() -> void:
	set_o2(0.0, 1.0)
	var end: Dictionary = current_screen().get("end", {})
	_show_death_end(str(end.get("heading", "")), str(end.get("fail_message", "")), str(end.get("retry", "")), screen_index)


func _on_typing_done() -> void:
	if bool(current_screen().get("onboarding", false)) and onboarding_active() and not has_flag("tut_status_done"):
		onboard_phase = "status"
		stage.continue_button.hide()
		maybe_start_tutorial("status")
		return
	if stage.end_type() == "death":
		_death_beat = DEATH_BEAT
	elif stage.end_type() == "map_tour":
		var p: Variant = _tour_pending
		_tour_pending = null
		if p is String and p == "move":
			_tour_begin_move()
		else:
			_tour_show(int(p) if p != null else 0)


# ---------------------------------------------------------------- time tutorial
## The first time the player is asked to spend time (the locker search prompt) a 2-step walkthrough
## runs BEFORE they can answer: "TIP: Some actions require Time." on the "1 hr" in the prompt, then
## "Missions are limited to 8 Hours." on the time bar. After the second step it stops and the player
## chooses Yes or No. It runs once (flag tut_time_done). Same mechanism and look as the map
## walkthrough (ui/map_tour.gd -> ui/guide_tour.gd). Tutorials are exempt from the no-hints rule;
## no hotkeys are named.
##
## Other walkthroughs, each once (flag tut_<id>_done), each also filed in the LOG under TUTORIALS:
##   log   the first LOG pop-up: the list, the search bar, the exit button.
##   drag  the first container window: a ghost item slides from the container grid to the inventory.
##   drop  the first item dropped on the floor (shown right AFTER that drop, over the opened map):
##         a ghost item slides out of the inventory onto the screen, then the new dot on the map.
const TUTORIALS := {
	"time": [
		{"target": "time_spent", "text": "TIP: Some actions require Time."},
		{"target": "time", "text": "Missions are limited to 8 Hours."},
	],
	# EXCURSION 1 // PREP onboarding (screen "onboarding": true): STATUS -> MAP (click the minimap) ->
	# the map walkthrough in the full map -> MENU (the MAP button) -> the walk to the READY ROOM.
	"status": [
		{"target": "sta", "text": "TIP: This is your STATUS screen. It shows details about your current situation."},
	],
	"map_click": [
		{"target": "minimap", "click": true, "text": "TIP: This is your MAP. Click on it to zoom in."},
	],
	"menu": [
		{"target": "map_button", "text": "TIP: You can also find the map here, in your MENU. Click or TAB to cycle through your MENU."},
	],
	"inventory": [
		{"target": "inv_grid", "text": "TIP: This is your Inventory. Items you are holding will be shown here."},
		{"target": "inv_figure", "text": "TIP: This is your Character."},
		{"target": "inv_exit", "text": "TIP: Click EXIT to close."},
	],
	"log": [
		{"target": "log_list", "text": "TIP: This is your LOG. Important information will be stored here."},
		{"target": "log_search", "text": "TIP: The log is searchable."},
		{"target": "log_exit", "text": "TIP: Click here to exit the log."},
	],
	"drag": [
		{"target": "container_grid", "anim": "container_to_inventory",
			"text": "TIP: Take an item from any CONTAINER by dragging and dropping it into your inventory."},
	],
	"drop": [
		{"target": "", "anim": "inventory_to_screen",
			"text": "TIP: Inventory is limited. Sometimes you may need to DROP items. Drag the item off the inventory, then click to drop it."},
		{"target": "map_drop", "open_map": true, "text": "TIP: The item now appears on the map."},
	],
}


# ---- onboarding state
var onboard_phase := ""     # "" | "status" | "map_click" | "tour" | "menu"


func onboarding_active() -> bool:
	return PdaScreen.tutorials_enabled and game_ui and not has_flag("tut_onboard_done") and not _dbg.has("no_tutorial")


## While the onboarding runs on its screen the story CONTINUE is held back.
func onboarding_blocks() -> bool:
	return onboard_phase != "" or (bool(current_screen().get("onboarding", false)) and onboarding_active())


## The hour block the last time cost just dimmed (the time bar, global), for the time tip.
func spent_block_rect() -> Rect2:
	if time_bar == null:
		return Rect2()
	var i := 0
	for c in time_bar.get_children():
		if c is ColorRect:
			if i == time_blocks:
				return (c as ColorRect).get_global_rect().grow(2.0)
			i += 1
	return time_bar.get_global_rect()


func guide_tips() -> Array:
	return _guide_steps


func drop_tip_pending() -> bool:
	return PdaScreen.tutorials_enabled and game_ui and not has_flag("tut_drop_done") and not _dbg.has("no_tutorial") \
		and guide_phase == ""


## Starts the walkthrough `tid` if tutorials are on, this is the game UI and it has not run yet.
func maybe_start_tutorial(tid: String) -> bool:
	if not TUTORIALS.has(tid) or not PdaScreen.tutorials_enabled or not game_ui:
		return false
	if has_flag("tut_%s_done" % tid) or guide_phase != "" or _dbg.has("no_tutorial"):
		return false
	guide_start(tid, int(str(_dbg.get("tutorial_step", "1"))) - 1)
	return true


func guide_start(tid: String, first := 0) -> void:
	if not TUTORIALS.has(tid):
		return
	_guide_steps = TUTORIALS[tid]
	guide_id = tid
	_ensure_windows()
	if guide_tour == null:
		guide_tour = GuideTour.new()
		(guide_tour as GuideTour).continued.connect(guide_next)
		add_child(guide_tour)
	move_child(guide_tour, get_child_count() - 1)    # over the prompt and the windows ...
	move_child(pause_menu, get_child_count() - 1)    # ... under the pause menu
	windows.set_animated(true)
	_guide_show(clampi(first, 0, _guide_steps.size() - 1))


func _guide_show(n: int) -> void:
	guide_phase = "tip"
	guide_step = n
	var st: Dictionary = _guide_steps[n]
	if bool(st.get("open_map", false)):
		show_map_change()     # the last drop tip: now the map maximizes to show the dot
		move_child(guide_tour, get_child_count() - 1)
		move_child(pause_menu, get_child_count() - 1)
	var anim := str(st.get("anim", ""))
	(guide_tour as GuideTour).click_only = bool(st.get("click", false))   # "click it" tips: no CONTINUE
	(guide_tour as GuideTour).show_step(n, _guide_steps.size(), str(st.get("text", "")), _guide_rect.bind(str(st.get("target", ""))),
		_guide_anim.bind(anim) if anim != "" else Callable())


func guide_next() -> void:
	if guide_phase != "tip":
		return
	play_sfx(&"tap")
	if guide_step + 1 < _guide_steps.size():
		_guide_show(guide_step + 1)
	else:
		_guide_finish()


func _guide_finish() -> void:
	guide_phase = ""
	if guide_tour:
		guide_tour.hide()
	flags["tut_%s_done" % guide_id] = true
	match guide_id:
		"status":
			# the minimap and the MAP button turn on, then: click the map
			reveal_tab("map")
			onboard_phase = "map_click"
			await get_tree().create_timer(REVEAL_TIME).timeout
			if is_inside_tree() and onboard_phase == "map_click":
				maybe_start_tutorial("map_click")
		"map_click":
			# zoom in: the map walkthrough (the existing tips) in the full map
			onboard_phase = "tour"
			var mi := -1
			for k in screens.size():
				if str(((screens[k] as Dictionary).get("end", {}) as Dictionary).get("type", "")) == "map_tour":
					mi = k
					break
			if mi >= 0:
				enter_screen(mi)
			else:
				open_map()
		"menu":
			# the onboarding is over: play goes on (the walk to the READY ROOM)
			onboard_phase = ""
			flags["tut_onboard_done"] = true
			_tour_after_tips()
		"drag":
			# the inventory tips follow on the same screen when the character screen is up (not stacked)
			if windows != null and windows.character_open():
				maybe_start_tutorial("inventory")


## Global rectangle of what a tip explains (Rect2() = nothing to highlight; the tip is centred).
func _guide_rect(target: String) -> Rect2:
	match target:
		"time_spent":
			return spent_block_rect()
		"sta":
			var r := sta_button.get_global_rect() if sta_button != null else Rect2()
			return r.merge(stage.text_label.get_global_rect()) if stage != null and r.size != Vector2.ZERO else r
		"minimap":
			return mini_map_frame.get_global_rect() if mini_map_frame != null and mini_map_frame.is_visible_in_tree() else Rect2()
		"map_button":
			return map_button.get_global_rect() if map_button != null and map_button.is_visible_in_tree() else Rect2()
		"inv_grid":
			return windows.character.grid_bg.get_global_rect() if windows != null and windows.character_open() else Rect2()
		"inv_figure":
			return windows.character.figure.get_global_rect() if windows != null and windows.character_open() else Rect2()
		"inv_exit":
			return windows.character.exit_button.get_global_rect() if windows != null and windows.character_open() else Rect2()
		"confirm_cost":
			return confirm_box.highlight_rect("1 hr") if confirm_box != null and confirm_box.visible else Rect2()
		"time":
			return time_box.get_global_rect() if time_box != null else Rect2()
		"tab_rail":
			return tab_rail_rect()
		"log_list":
			return windows.logw.list_rect() if windows != null and windows.log_open() else Rect2()
		"log_search":
			return windows.logw.search_rect() if windows != null and windows.log_open() else Rect2()
		"log_exit":
			return windows.logw.exit_rect() if windows != null and windows.log_open() else Rect2()
		"container_grid":
			return windows.container.grid_bg.get_global_rect() if windows != null and windows.container_open() else Rect2()
		"map_drop":
			return _last_drop_rect()
	return Rect2()


## The newest dropped item's dot + name on the full map (global), Rect2() if none is shown.
func _last_drop_rect() -> Rect2:
	if _full_map == null or not _full_map.is_visible_in_tree():
		return Rect2()
	var list := dropped_in(str(vessel_map.get("current", "")))
	if list.is_empty():
		return Rect2()
	var mk := "drop:%s" % str((list.back() as Dictionary).get("uid", ""))
	if _full_map.find_marker(mk).is_empty():
		mk = "pile:%s" % str(vessel_map.get("current", ""))
	var r := _full_map.marker_hit_rect(mk)
	if r.size == Vector2.ZERO:
		return Rect2()
	return Rect2(r.position + _full_map.global_position, r.size)


## The looping hint animation of a tip: {from, to, item, label} in global coordinates.
func _guide_anim(kind: String) -> Dictionary:
	if windows == null:
		return {}
	var vp := get_viewport_rect().size
	match kind:
		"container_to_inventory":
			if not windows.container_open() or not windows.character_open():
				return {}
			var it_id := ""
			for it: Dictionary in windows.container.items:
				if not bool(it.get("taken", false)):
					it_id = str(it.get("id", ""))
					break
			return {"from": windows.container.grid_bg.get_global_rect().get_center(),
				"to": windows.character.grid_bg.get_global_rect().get_center(), "item": it_id, "label": ""}
		"inventory_to_screen":
			# where the character screen sits when it is open alone -> out into the room
			var cs: Vector2 = windows.character.panel_size
			var c := Vector2(vp.x * 0.5, vp.y * 0.5)
			var list := dropped_in(str(vessel_map.get("current", "")))
			var it_id := str((list.back() as Dictionary).get("id", "")) if not list.is_empty() else ""
			var lbl := str((list.back() as Dictionary).get("label", "")) if not list.is_empty() else ""
			var frame := Rect2(c - Vector2(cs.x * 0.75, cs.y * 0.4), Vector2(cs.x * 0.8, cs.y * 0.8))
			return {"frame": frame, "from": frame.get_center(), "to": c + Vector2(cs.x * 0.7, -30.0), "item": it_id,
				"label": ("DROP " + lbl) if lbl != "" else ""}
	return {}


# ---------------------------------------------------------------- map walkthrough

func tour_tips() -> Array:
	return (current_screen().get("end", {}) as Dictionary).get("tips", [])


## Tip n (0-based) over the locked-open full map. Tips after the first are dev-back steps.
func _tour_show(n: int) -> void:
	var tips := tour_tips()
	if tips.is_empty():
		_tour_after_tips()
		return
	n = clampi(n, 0, tips.size() - 1)
	if n > 0:
		dev_push_screen("%s/tip %d" % [screen_label(screen_index), n + 1], _reenter_tour.bind(screen_index, n))
	tour_phase = "tip"
	tour_step = n
	map_hint = ""
	map_lock_open(true)
	open_map()
	if tour == null:
		tour = MapTour.new()
		tour.continued.connect(_tour_next)
		map_overlay.add_child(tour)
	tour.show()
	var tip: Dictionary = tips[n]
	tour.show_tip(_full_map, n, tips.size(), _apply_vars(str(tip.get("text", ""))), str(tip.get("target", "map")))


func _tour_next() -> void:
	if tour_phase != "tip":
		return
	play_sfx(&"tap")
	if tour_step + 1 < tour_tips().size():
		_tour_show(tour_step + 1)
	else:
		_tour_after_tips()


func _tour_after_tips() -> void:
	flags["tut_map_done"] = true      # the map tips were seen (filed in the LOG: Map, Doors, Moving Rooms)
	flags["tut_move_done"] = true
	if onboarding_active() and not has_flag("tut_menu_done") and guide_phase == "":
		# the map minimizes but the walkthrough goes on: the MAP button in the MENU
		onboard_phase = "menu"
		tour_phase = ""
		if tour:
			tour.hide()
		map_lock_open(false)
		close_map()
		maybe_start_tutorial("menu")
		return
	var end: Dictionary = current_screen().get("end", {})
	if str(end.get("move_to", "")) != "":
		dev_push_screen("%s/move" % screen_label(screen_index), _reenter_tour.bind(screen_index, -1))
		_tour_begin_move()
	else:
		_tour_close()
		go(str(end.get("goto", "next")))


## After the tips: the map stays open, click-to-move is on, the player walks to move_to.
func _tour_begin_move() -> void:
	var end: Dictionary = current_screen().get("end", {})
	tour_phase = "move"
	if tour:
		tour.hide()
	run_op("map_moves:on")
	map_lock_open(true)
	open_map()
	map_hint = _apply_vars(str(end.get("move_prompt", ""))).to_upper()
	_on_map_room_hovered(_full_map.hovered_id)
	if _dbg.has("map_click"):
		var id := str(_dbg["map_click"])
		_dbg.erase("map_click")
		map_try_move(id)


func _on_map_moved(room_id: String) -> void:
	if tour_phase != "move":
		_enter_room_screen(room_id)
		return
	var end: Dictionary = current_screen().get("end", {})
	if room_id != str(end.get("move_to", "")):
		return   # an other room on the way: keep walking
	tour_phase = "arrived"
	_tour_token += 1
	var token := _tour_token
	var ops: Array = end.get("on_arrive", [])
	var wait := ARRIVE_WAIT
	if not ops.is_empty():
		await get_tree().create_timer(ARRIVE_OPS_AT).timeout
		if token != _tour_token or not is_inside_tree() or tour_phase != "arrived":
			return
		for op: Variant in ops:
			run_op(op)
		_flush_after()
		wait = ARRIVE_OPS_WAIT - ARRIVE_OPS_AT
	await get_tree().create_timer(wait).timeout
	if token != _tour_token or not is_inside_tree() or tour_phase != "arrived":
		return
	room_transition(_arrive_now.bind(str(end.get("goto", "next"))), "")    # the walk already played its door sound


## Room moves outside the walkthrough (READY ROOM <-> STASIS-3): the screen of this scene that puts
## the player in that room (its on_enter has "map_set_room:<room>") opens. Same scene, so every bit
## of state (dropped items, locker, coffee, tutorials, hours) stays as it was.
func room_screen_index(room_id: String) -> int:
	for i in screens.size():
		var scr: Dictionary = screens[i]
		var end: Dictionary = scr.get("end", {})
		if str(end.get("type", "")) != "hold":
			continue
		if ("map_set_room:" + room_id) in (scr.get("on_enter", []) as Array):
			return i
	return -1


func _enter_room_screen(room_id: String) -> void:
	var i := room_screen_index(room_id)
	if i < 0 or i == screen_index:
		return
	if map_overlay.visible and not map_locked_open:
		map_overlay.hide()
	room_transition(_enter_room_now.bind(i), "")   # the move already played its door sound (map_try_move)


func _enter_room_now(i: int) -> void:
	var prev := _prev_index
	_skip_record = true      # walking between rooms is not a dev-history step (dev back skips it)
	enter_screen(i)
	_prev_index = prev


func _arrive_now(goto_target: String) -> void:
	_tour_close()
	go(goto_target)


func _tour_close() -> void:
	tour_phase = ""
	map_hint = ""
	if tour:
		tour.hide()
	map_lock_open(false)
	close_map()


## Dev back into the walkthrough: step n (or -1 = the move phase) without a new screen record.
func _reenter_tour(i: int, n: int) -> void:
	_tour_pending = "move" if n < 0 else n
	screen_index = -1
	_skip_record = true
	if n < 0:
		# the move record is pushed by _tour_after_tips; re-push it here as dev_back popped it
		dev_push_screen("%s/move" % screen_label(i), _reenter_tour.bind(i, -1))
	enter_screen(i)


func _process(delta: float) -> void:
	if _death_beat >= 0.0 and not pause_menu.visible:
		_death_beat -= delta
		if _death_beat < 0.0:
			var end: Dictionary = current_screen().get("end", {})
			var fallback := _prev_index if _prev_index >= 0 else screen_index
			_show_death_end(str(end.get("heading", "")), str(end.get("message", "")), str(end.get("retry", "")), fallback)


## Death screen. retry: "" = default (`fallback` screen), a screen id, or any link target.
func _show_death_end(heading: String, message: String, retry: String, fallback: int) -> void:
	_death_beat = -1.0
	stage.stop()
	show_death(format_os(message) if message != "" else DEATH_MESSAGE, DEATH_RETRY,
		_retry.bind(retry, fallback), format_os(heading) if heading != "" else DEATH_HEADING)


func _retry(target: String, fallback: int) -> void:
	stop_o2_tween()
	refill_o2(0.8)
	stage.reset_fx()
	if target.strip_edges() == "":
		screen_index = -1
		enter_screen(clampi(fallback, 0, screens.size() - 1))
	else:
		screen_index = -1
		go(target)


# ---------------------------------------------------------------- template hooks

func _on_advance() -> bool:
	if guide_phase == "tip" and guide_tour and guide_tour.visible:
		guide_tour.press()
		return true
	if tour_phase == "tip" and tour and tour.visible:
		tour.press()
		return true
	if map_overlay.visible:
		return false
	if overlay and overlay.visible and stage.playing:
		stage.press()
		return true
	return false


func _overlay_input(event: InputEvent) -> bool:
	if overlay == null or not overlay.visible:
		return false
	for i in range(1, 10):
		if event.is_action_pressed("choice_%d" % i):
			stage.pick(i)
			return true
	return false


func _on_pause_changed(p: bool) -> void:
	stage.set_paused(p)


func _on_death_shown() -> void:
	_death_beat = -1.0
	stage.stop()


func _dev_stop_chapter() -> void:
	_death_beat = -1.0
	if windows != null:
		windows.close_all(true)
	_tour_token += 1
	_tour_pending = null
	if guide_phase != "":
		guide_phase = ""
		if guide_tour:
			guide_tour.hide()
	if tour_phase != "":
		_tour_close()
	if fade_rect:
		if _fade_tween:
			_fade_tween.kill()
		fade_rect.hide()
		stage.frozen = _dbg.has("freeze")
	if stage:
		stage.stop()
		stage.reset_fx()


func _exit_tree() -> void:
	if stage:
		stage.stop()
	super()
