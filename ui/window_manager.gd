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

signal item_taken(act_id: String, item: Dictionary)
signal item_action(act_id: String, action: String, item: Dictionary)
signal character_changed(open: bool)
signal container_changed(open: bool)
signal station_changed(open: bool)
## Character screen buttons: "drop" / "wear" with the item dictionary.
signal character_action(action: String, item: Dictionary)
signal station_option(station_id: String, option_id: String)

const CharacterScript := preload("res://ui/character_screen.gd")
const ContainerScript := preload("res://ui/container_window.gd")
const StationScript := preload("res://ui/station_window.gd")
const GAP := 14.0
const DIM_ALPHA := 0.5

var host: Control                    # PdaScreen (inventory, items, vars, play_sfx)
var character: Control
var container: Control
var station: Control                 # COFFEE POT and other picture + options windows
## Callable(hours) -> String: "" if the action can be afforded, else the short refusal message.
var afford_cb: Callable
## Callable(item) -> Array of character-screen buttons ("wear", "drop") for an inventory item.
var item_actions_cb: Callable
var _sec: Control                    # the secondary window of the moment: container or station
## Callable(act_id, item) -> bool. Default: the item id is in host.inventory.
var taken_check: Callable
var container_act := ""
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
	_sec = container
	station.exit_requested.connect(close_station)
	station.option_pressed.connect(func(sid: String, oid: String) -> void: station_option.emit(sid, oid))
	station.closed.connect(_on_window_closed)
	character.item_action.connect(func(a: String, it: Dictionary) -> void: character_action.emit(a, it))
	character.close_requested.connect(close_character)
	character.can_drop_cb = _can_drop
	character.drop_cb = _drop
	container.exit_requested.connect(close_container)
	container.take_requested.connect(_on_take_requested)
	container.action_requested.connect(func(a: String, act: String, it: Dictionary) -> void:
		item_action.emit(a, act, it))
	character.closed.connect(_on_window_closed)
	container.closed.connect(_on_window_closed)


func setup(p_host: Control) -> void:
	host = p_host
	set_process(false)


## Turns window animation on / off for both windows (tests, reduced motion).
func set_animated(on: bool) -> void:
	character.animate = on
	container.animate = on
	station.animate = on


# ---------------------------------------------------------------- state

func any_open() -> bool:
	return character.wants_open() or container.wants_open() or station.wants_open()


func any_visible() -> bool:
	return not character.is_closed() or not container.is_closed() or not station.is_closed()


func station_is_open() -> bool:
	return station.wants_open()


func character_open() -> bool:
	return character.wants_open()


func container_open() -> bool:
	return container.wants_open()


## Which window Esc would close: "container", "character" or "".
func top_window() -> String:
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


func close_top() -> void:
	match top_window():
		"station":
			close_station()
		"container":
			close_container()
		"character":
			close_character()


## Closes everything at once, no animation (new screen, death, tests).
func close_all(instant := true) -> void:
	_char_auto = false
	if instant:
		var was_c: bool = container.wants_open()
		var was_h: bool = character.wants_open()
		var was_s: bool = station.wants_open()
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
	_sfx(&"tap")
	return true


func _on_take_requested(act_id: String, item: Dictionary) -> void:
	take(act_id, str(item.get("id", "")))


func _can_drop(data: Variant) -> bool:
	if not (data is Dictionary) or str((data as Dictionary).get("kind", "")) != "container_item":
		return false
	var it: Dictionary = container.find_item(str((data as Dictionary).get("id", "")))
	return container.wants_open() and not it.is_empty() and not bool(it.get("taken", false)) \
		and "take" in (it.get("actions", ["take"]) as Array)


func _drop(data: Variant) -> void:
	if _can_drop(data):
		take(container.act_id, str((data as Dictionary).get("id", "")))


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
			entry["wear_hours"] = int(it.get("wear_hours", 1))
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
	if not any_visible():
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
	_dim.modulate.a = maxf(character.open_amount, maxf(container.open_amount, station.open_amount)) * DIM_ALPHA


func _sfx(kind: StringName) -> void:
	if host != null and host.has_method("play_sfx"):
		host.play_sfx(kind)
