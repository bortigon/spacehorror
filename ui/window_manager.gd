extends Control
## WINDOW MANAGER: the layer that holds the character screen and the container window.
## It lives inside the game screen (templates/pda_screen.gd creates it), draws above the story, and
## while any window is up it eats mouse clicks so the story underneath cannot be clicked.
##
##   toggle_character()     TAB / C / I and the INV tab. The character screen works on its own.
##   open_container(id, spec)  a container act was clicked: the container window opens and the
##                          character screen opens beside it (side by side, the pair centred).
##   close_container()      EXIT / Esc. Closes the container; the character screen goes with it only
##                          if it was opened automatically by the container. A character screen the
##                          player opened themselves stays until they close it.
##   close_top()            Esc: the container if one is up, otherwise the character screen.
##   take(act_id, item_id)  Take button / drag-and-drop: the item leaves the container (its cell is
##                          empty) and `item_taken` tells the host to put it in the inventory.
##
## DRAGGING (our own, not Godot's drag and drop): press an item and move a few pixels and it STICKS to
## the cursor.
##   inventory item -> over the container window: it is stored in the container (`store_cb`).
##   container item -> over the character screen: it is taken (same as the Take button).
##   inventory item -> out of every window: the windows hide while the item is out; letting go over the
##                      room / map calls `world_release(item, pos)` (the host drops it, or uses it on
##                      what is under the cursor, e.g. a keycard on a lock).
##   back over a window, Esc or a right click: the item returns.

signal item_taken(act_id: String, item: Dictionary)
signal item_action(act_id: String, action: String, item: Dictionary)
signal character_changed(open: bool)
signal container_changed(open: bool)
signal station_changed(open: bool)
## Character screen buttons: "drop" / "wear" with the item dictionary.
signal character_action(action: String, item: Dictionary)
signal station_option(station_id: String, option_id: String)
## An inventory item was let go outside the windows: the host drops it or uses it on a target.
signal world_release(item: Dictionary, pos: Vector2)
## The drag started / ended (the host can hide hints...). `dropped` is what happened to the item.
signal drag_changed(active: bool)

const CharacterScript := preload("res://ui/character_screen.gd")
const ContainerScript := preload("res://ui/container_window.gd")
const StationScript := preload("res://ui/station_window.gd")
const LogScript := preload("res://ui/log_window.gd")

const Icons := preload("res://ui/item_icons.gd")
signal log_changed(open: bool)
const GAP := 14.0
const DIM_ALPHA := 0.5

var host: Control                    # PdaScreen (inventory, items, vars, play_sfx)
var character: Control
var container: Control
var station: Control                 # COFFEE POT and other picture + options windows
var logw: Control                    # the LOG pop-up (opens on its own: the other windows close)
## Callable(pos) -> String: "" over plain room / map, else a target id ("door:a|b", "marker:x").
## The cursor label then reads "USE <ITEM>" instead of "DROP <ITEM>".
var target_cb: Callable
## Callable(hours) -> String: "" if the action can be afforded, else the short refusal message.
var afford_cb: Callable
## Callable(item) -> Array of character-screen buttons ("wear", "drop") for an inventory item.
var item_actions_cb: Callable
var _sec: Control                    # the secondary window of the moment: container or station
## Callable(act_id, item) -> bool. Default: the item id is in host.inventory.
var taken_check: Callable
var container_act := ""
## Callable(act_id, item) -> bool: the host moves an inventory item into the container's state.
var store_cb: Callable
var drag: Dictionary = {}            # {item, source, hidden}: an item stuck to the cursor
var _ghost: Control
var _prev_filter := Control.MOUSE_FILTER_STOP
var _char_auto := false              # the character screen was opened by a container
var _dim: ColorRect


func _init() -> void:
	name = "Windows"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # click-eater (only while visible)
	visible = false
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.0, 0.03, 0.01, 1.0)
	_dim.modulate.a = 0.0
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	character = CharacterScript.new()
	character.name = "CharacterScreen"
	add_child(character)
	container = ContainerScript.new()
	container.name = "ContainerWindow"
	add_child(container)
	station = StationScript.new()
	station.name = "StationWindow"
	add_child(station)
	logw = LogScript.new()
	logw.name = "LogWindow"
	add_child(logw)
	logw.exit_requested.connect(close_log)
	logw.closed.connect(_on_window_closed)
	_sec = container
	station.exit_requested.connect(close_station)
	station.option_pressed.connect(func(sid: String, oid: String) -> void: station_option.emit(sid, oid))
	station.closed.connect(_on_window_closed)
	character.item_action.connect(func(a: String, it: Dictionary) -> void: character_action.emit(a, it))
	character.close_requested.connect(close_character)
	character.item_drag_started.connect(_on_drag_started)
	container.item_drag_started.connect(_on_drag_started)
	container.exit_requested.connect(close_container)
	container.take_requested.connect(_on_take_requested)
	container.action_requested.connect(func(a: String, act: String, it: Dictionary) -> void:
		item_action.emit(a, act, it))
	character.closed.connect(_on_window_closed)
	container.closed.connect(_on_window_closed)


func setup(p_host: Control) -> void:
	host = p_host
	set_process(false)
	set_process_input(false)


## Turns window animation on / off for both windows (tests, reduced motion).
func set_animated(on: bool) -> void:
	character.animate = on
	container.animate = on
	station.animate = on
	logw.animate = on


# ---------------------------------------------------------------- state

func any_open() -> bool:
	return character.wants_open() or container.wants_open() or station.wants_open() or logw.wants_open()


func any_visible() -> bool:
	return not character.is_closed() or not container.is_closed() or not station.is_closed() or not logw.is_closed()


func log_open() -> bool:
	return logw.wants_open()


func station_is_open() -> bool:
	return station.wants_open()


func character_open() -> bool:
	return character.wants_open()


func container_open() -> bool:
	return container.wants_open()


## Which window Esc would close: "container", "character" or "".
func top_window() -> String:
	if logw.wants_open():
		return "log"
	if station.wants_open():
		return "station"
	if container.wants_open():
		return "container"
	if character.wants_open():
		return "character"
	return ""


# ---------------------------------------------------------------- character screen

func toggle_character() -> void:
	if character.wants_open():
		close_character()
	else:
		open_character(false)


func open_character(auto := false) -> void:
	if character.wants_open():
		return
	refresh()
	_char_auto = auto
	_show_layer()
	_layout(true, container.wants_open() or station.wants_open())
	character.open()
	_sfx(&"open")
	character_changed.emit(true)


func close_character() -> void:
	if not character.wants_open():
		return
	_char_auto = false
	character.close()
	_layout(false, container.wants_open() or station.wants_open())
	_sfx(&"close")
	character_changed.emit(false)


# ---------------------------------------------------------------- container

func open_container(act_id: String, spec: Dictionary) -> void:
	if container.wants_open():
		container.close_now()
	if station.wants_open():
		station.close_now()
		station_changed.emit(false)
	_sec = container
	container_act = act_id
	var chk := taken_check if taken_check.is_valid() else _default_taken
	container.configure(act_id, spec, func(it: Dictionary) -> bool: return bool(chk.call(act_id, it)))
	_show_layer()
	_layout(true, true)
	if not character.wants_open():
		refresh()
		_char_auto = true
		character.open()
		character_changed.emit(true)
	container.open()
	_sfx(&"open")
	container_changed.emit(true)


func close_container() -> void:
	if not container.wants_open():
		return
	container.close()
	container_changed.emit(false)
	if _char_auto and character.wants_open():
		_char_auto = false
		character.close()
		character_changed.emit(false)
	_layout(character.wants_open(), false)
	_sfx(&"close")


## Opens a station window (coffee pot): alone in the middle, or beside the character screen if the
## player already has it open. `provider` is the station's state callable (see station_window.gd).
func open_station(station_id: String, spec: Dictionary, provider: Callable) -> void:
	if container.wants_open():
		container.close_now()
		container_changed.emit(false)
	if station.wants_open():
		station.close_now()
	_sec = station
	station.configure(station_id, spec, provider)
	_show_layer()
	_layout(character.wants_open(), true)
	station.open()
	_sfx(&"open")
	station_changed.emit(true)


func close_station() -> void:
	if not station.wants_open():
		return
	station.close()
	station_changed.emit(false)
	_layout(character.wants_open(), false)
	_sfx(&"close")


func refresh_station() -> void:
	if station.wants_open():
		station.refresh()


## The LOG pop-up: alone in the middle (the other windows close first). `select` = entry id to show.
func open_log(entries: Array, select := "") -> void:
	if character.wants_open() or container.wants_open() or station.wants_open():
		close_all(true)
	logw.configure(entries, select)
	if logw.wants_open():
		return
	_show_layer()
	var vp := size if size.x > 0.0 else Vector2(960, 540)
	logw.move_to(((vp - logw.panel_size) * 0.5).round())
	logw.open()
	_sfx(&"open")
	log_changed.emit(true)


func close_log() -> void:
	if not logw.wants_open():
		return
	logw.close()
	_sfx(&"close")
	log_changed.emit(false)


func close_top() -> void:
	match top_window():
		"log":
			close_log()
		"station":
			close_station()
		"container":
			close_container()
		"character":
			close_character()


## Closes everything at once, no animation (new screen, death, tests).
func close_all(instant := true) -> void:
	_char_auto = false
	if not drag.is_empty():
		_end_drag()
	if instant:
		var was_c: bool = container.wants_open()
		var was_h: bool = character.wants_open()
		var was_s: bool = station.wants_open()
		var was_l: bool = logw.wants_open()
		logw.close_now()
		if was_l:
			log_changed.emit(false)
		container.close_now()
		character.close_now()
		station.close_now()
		if was_s:
			station_changed.emit(false)
		if was_c:
			container_changed.emit(false)
		if was_h:
			character_changed.emit(false)
		_hide_layer()
	else:
		close_log()
		close_station()
		close_container()
		close_character()


# ---------------------------------------------------------------- taking items

func take(act_id: String, item_id: String) -> bool:
	if not container.wants_open() or act_id != container.act_id:
		return false
	var it: Dictionary = container.find_item(item_id)
	if it.is_empty() or bool(it.get("taken", false)):
		return false
	var hrs := int(it.get("hours", 0))
	if hrs > 0 and afford_cb.is_valid():
		var why := str(afford_cb.call(hrs))
		if why != "":
			notice(why, "container")
			_sfx(&"close")
			return false
	container.mark_taken(item_id)
	item_taken.emit(act_id, it.duplicate(true))
	refresh()
	character.select_id(item_id)
	_sfx(&"loot")     # each item looted (dragged into the inventory)
	return true


func _on_take_requested(act_id: String, item: Dictionary) -> void:
	take(act_id, str(item.get("id", "")))


# ---------------------------------------------------------------- dragging

func drag_active() -> bool:
	return not drag.is_empty()


func drag_item() -> Dictionary:
	return drag.get("item", {})


func drag_hidden() -> bool:
	return bool(drag.get("hidden", false))


func _on_drag_started(source: String, slot: Control, pos: Vector2) -> void:
	if not drag.is_empty() or slot == null or slot.item.is_empty():
		return
	begin_drag(source, slot.item.duplicate(true), pos)


## Moves the stuck item as if the mouse moved there (tests).
func move_drag(pos: Vector2) -> void:
	if drag.is_empty():
		return
	_place_ghost(pos)
	_update_drag_hide(pos)
	_refresh_ghost_mode(pos)


## Starts a drag by hand (the slot signals do this; tests too).
func begin_drag(source: String, item: Dictionary, pos: Vector2) -> void:
	if not drag.is_empty() or item.is_empty():
		return
	drag = {"item": item, "source": source, "hidden": false}
	if _ghost == null:
		_ghost = _make_ghost()
		add_child(_ghost)
	_set_ghost(item)
	_ghost.show()
	_place_ghost(pos)
	_prev_filter = mouse_filter
	set_process_input(true)
	drag_changed.emit(true)
	_update_drag_hide(pos)
	_refresh_ghost_mode(pos)


## The item on the cursor: its code-drawn icon (if it has one) + a label. Over a window the label is
## the item's name; out over the room it reads "DROP <ITEM>" (letting go drops it), over a lock or
## another target "USE <ITEM>".
func _make_ghost() -> Control:
	var root := Control.new()
	root.name = "DragGhost"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 100
	var icon := Control.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = Vector2(28, 28)
	icon.draw.connect(func() -> void:
		Icons.draw_icon(icon, str(icon.get_meta("item_id", "")), Rect2(Vector2.ZERO, icon.size)))
	root.add_child(icon)
	var l := Label.new()
	l.name = "Text"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(0.03, 0.13, 0.05))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.52, 0.86, 0.45, 0.95)
	bg.border_color = Color(0.82, 1.0, 0.78)
	bg.set_border_width_all(1)
	bg.content_margin_left = 6
	bg.content_margin_right = 6
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", bg)
	var f := load("res://assets/fonts/IBMPlexMono-SemiBold.ttf")
	if f:
		l.add_theme_font_override("font", f)
	root.add_child(l)
	return root


func _set_ghost(item: Dictionary) -> void:
	var icon: Control = _ghost.get_node("Icon")
	var iid := str(item.get("icon", item.get("id", "")))
	icon.set_meta("item_id", iid)
	icon.visible = Icons.has_icon(iid)
	icon.queue_redraw()
	_set_ghost_mode("")


## mode: "" (over a window: the name), "drop" or "use".
func _set_ghost_mode(mode: String) -> void:
	if _ghost == null or drag.is_empty():
		return
	var name_text := str((drag["item"] as Dictionary).get("label", (drag["item"] as Dictionary).get("id", ""))).to_upper()
	var l: Label = _ghost.get_node("Text")
	match mode:
		"drop":
			l.text = "DROP " + name_text
		"use":
			l.text = "USE " + name_text
		_:
			l.text = name_text
	drag["mode"] = mode
	var icon: Control = _ghost.get_node("Icon")
	l.position = Vector2(32, 6) if icon.visible else Vector2.ZERO
	l.reset_size()


## What the cursor label says now: the item name, "DROP <ITEM>" or "USE <ITEM>".
func ghost_text() -> String:
	return (_ghost.get_node("Text") as Label).text if _ghost != null else ""


func _refresh_ghost_mode(pos: Vector2) -> void:
	if drag.is_empty():
		return
	var mode := ""
	if str(drag.get("source", "")) == "character" and window_at(pos) == "":
		mode = "drop"
		if target_cb.is_valid() and str(target_cb.call(pos)) != "":
			mode = "use"
	if mode != str(drag.get("mode", "?")):
		_set_ghost_mode(mode)


func _place_ghost(pos: Vector2) -> void:
	_ghost.position = pos - global_position + Vector2(10, 8)


func ghost_position() -> Vector2:
	return _ghost.global_position if _ghost != null else Vector2.ZERO


func ghost_visible() -> bool:
	return _ghost != null and _ghost.visible and drag_active()


## Which open window the screen point is over: "character", "container", "station" or "".
func window_at(pos: Vector2) -> String:
	if character.wants_open() and Rect2(character.global_position, character.panel_size).has_point(pos):
		return "character"
	if container.wants_open() and Rect2(container.global_position, container.panel_size).has_point(pos):
		return "container"
	if station.wants_open() and Rect2(station.global_position, station.panel_size).has_point(pos):
		return "station"
	return ""


## STICKY: an inventory item dragged out of every window. The windows CLOSE, the item stays on the
## cursor, and letting go of the button does nothing: the next left CLICK acts (room / map = drop,
## a lock or other target = use). Esc or a right click returns it to the inventory.
func drag_sticky() -> bool:
	return bool(drag.get("sticky", false))


func _go_sticky() -> void:
	drag["sticky"] = true
	drag["hidden"] = true
	_char_auto = false
	for w: Control in [character, container, station]:
		if w.wants_open():
			w.close_now()
	character_changed.emit(false)
	container_changed.emit(false)
	station_changed.emit(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	drag_changed.emit(true)


func _update_drag_hide(pos: Vector2) -> void:
	if drag_sticky():
		return
	if str(drag.get("source", "")) == "character" and window_at(pos) == "":
		_go_sticky()
		return
	# an inventory item leaves the windows: they hide and only the item stays on the cursor
	var hide := false
	if hide == bool(drag.get("hidden", false)):
		return
	drag["hidden"] = hide
	character.set_drag_hidden(hide)
	container.set_drag_hidden(hide)
	station.set_drag_hidden(hide)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if hide else _prev_filter


func _input(event: InputEvent) -> void:
	if drag.is_empty():
		return
	if event is InputEventMouseMotion:
		var pos := (event as InputEventMouseMotion).global_position
		_place_ghost(pos)
		_update_drag_hide(pos)
		_refresh_ghost_mode(pos)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and drag_sticky():
			if mb.pressed:
				release_drag(mb.global_position)     # the click acts: drop / use
			get_viewport().set_input_as_handled()  # letting go of the drag does nothing
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			release_drag(mb.global_position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel_drag()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			cancel_drag()
			get_viewport().set_input_as_handled()


## The item goes back where it came from (Esc, right click).
func cancel_drag() -> void:
	if drag.is_empty():
		return
	var was_sticky := drag_sticky()
	_end_drag()
	if was_sticky and not any_visible():
		_hide_layer()     # the windows were closed: the item is simply back in the inventory
	refresh()
	_sfx(&"close")


func _end_drag() -> void:
	drag = {}
	if _ghost != null:
		_ghost.hide()
	character.set_drag_hidden(false)
	container.set_drag_hidden(false)
	station.set_drag_hidden(false)
	mouse_filter = _prev_filter
	set_process_input(false)
	drag_changed.emit(false)
	if not any_visible():
		_hide_layer()     # a sticky drag closed the windows: nothing left to show


## Let go at `pos` (screen coordinates). Returns what happened: "stored", "taken", "world", "returned".
func release_drag(pos: Vector2) -> String:
	if drag.is_empty():
		return ""
	var item: Dictionary = drag["item"]
	var source := str(drag["source"])
	var over := window_at(pos)
	_end_drag()
	var result := "returned"
	if source == "character":
		if over == "container" and container.accepts_drops:
			if not container.store_item(_container_entry(item)):
				notice("NO ROOM", "container")
				_sfx(&"close")
			elif store_cb.is_valid() and bool(store_cb.call(container.act_id, item)):
				result = "stored"
				_sfx(&"drop")     # dropped into a container
			else:
				container.mark_taken(str(item.get("id", "")))   # the host refused: undo
		elif over == "":
			result = "world"
			world_release.emit(item, pos)
	elif source == "container":
		if over == "character":
			result = "taken" if take(container.act_id, str(item.get("id", ""))) else "returned"
	refresh()
	return result


## The inventory entry as a container item.
func _container_entry(item: Dictionary) -> Dictionary:
	return {"id": str(item.get("id", "")), "label": str(item.get("label", "")).to_upper(),
		"detail": str(item.get("detail", "")), "hours": 0, "required": false, "actions": ["take"], "extra": true}


func _default_taken(_act_id: String, it: Dictionary) -> bool:
	if host == null:
		return false
	var id := str(it.get("id", ""))
	return id != "" and StringName(id) in host.inventory


# ---------------------------------------------------------------- contents

## A short message inside a window: which = "container" | "character" | "station" | "" (the top one).
func notice(text: String, which := "") -> void:
	if which == "":
		which = top_window()
	match which:
		"station":
			station.show_notice(text)
		"container":
			container.show_notice(text)
		_:
			character.show_notice(text)


## Rebuilds the character screen from the host's state (call after the inventory changes).
func refresh() -> void:
	if host == null:
		return
	character.set_name_text(player_name())
	character.set_suit_worn(bool(host.vars.get("suit_worn", false)))
	character.set_slots(inventory_entries())


func player_name() -> String:
	if host == null:
		return "NAME"
	var typed := str(host.vars.get("typed_name", "")).strip_edges()
	if typed != "":
		return typed.to_upper()
	var call := str(host.vars.get("callsign", "")).strip_edges()
	return call.to_upper() if call != "" else "NAME"


## What the player carries, in pick-up order. The grid starts COMPLETELY EMPTY: no placeholder items.
func inventory_entries() -> Array:
	var out: Array = []
	if host == null:
		return out
	for id in host.inventory:
		var it: Dictionary = host.items.get(id, {})
		var entry := {"id": str(id), "label": str(it.get("label", id)).to_upper(), "detail": str(it.get("desc", ""))}
		var acts: Array = ["drop"]
		if item_actions_cb.is_valid():
			acts = item_actions_cb.call(entry)
		entry["actions"] = acts
		if "wear" in acts:
			entry["wear_hours"] = int(it.get("wear_hours", 0))
		out.append({"item": entry, "dim": false})
	return out


# ---------------------------------------------------------------- layout + frame

func _show_layer() -> void:
	visible = true
	set_process(true)


func _hide_layer() -> void:
	visible = false
	set_process(false)
	_dim.modulate.a = 0.0


func _on_window_closed() -> void:
	if not any_visible() and drag.is_empty():
		_hide_layer()


## Centres the windows that are (about to be) up: one alone in the middle, a pair side by side
## centred as a pair. A window that is already showing slides to its new spot.
func _layout(want_char: bool, want_cont: bool) -> void:
	var vp := size if size.x > 0.0 else Vector2(960, 540)
	var cs: Vector2 = character.panel_size
	var ks: Vector2 = _sec.panel_size
	if want_char and want_cont:
		var x0 := roundf((vp.x - (cs.x + GAP + ks.x)) * 0.5)
		character.move_to(Vector2(x0, roundf((vp.y - cs.y) * 0.5)))
		_sec.move_to(Vector2(x0 + cs.x + GAP, roundf((vp.y - ks.y) * 0.5)))
	else:
		if want_char:
			character.move_to(Vector2(roundf((vp.x - cs.x) * 0.5), roundf((vp.y - cs.y) * 0.5)))
		if want_cont:
			_sec.move_to(Vector2(roundf((vp.x - ks.x) * 0.5), roundf((vp.y - ks.y) * 0.5)))


func _process(_delta: float) -> void:
	_dim.modulate.a = 0.0 if drag_hidden() else \
		maxf(maxf(character.open_amount, logw.open_amount), maxf(container.open_amount, station.open_amount)) * DIM_ALPHA


func _sfx(kind: StringName) -> void:
	if host != null and host.has_method("play_sfx"):
		host.play_sfx(kind)
