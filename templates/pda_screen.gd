class_name PdaScreen
extends Control
## PDA SCREEN TEMPLATE: the REC-7 running CLAIMSIDE OS.
##
## Every chapter is an inherited scene of res://templates/pda_screen.tscn whose root
## script extends this one and only supplies data in _setup_story():
##
##   extends "res://templates/pda_screen.gd"
##   func _setup_story() -> void:
##       passages = { &"deck_fore": { "title": "Fore", "body": "...", "choices": [...] } }
##       dossiers = { ... }   items = { ... }   deck = { ... }
##       start_passage = &"deck_fore"
##
## PC landscape layout (960x540):
##   Screen (shader) > Backdrop > Frame > SafeArea
##     Header (OS / COMMS / hourglass / journal btn)
##     Body: left tab rail | MainCol (title + views)
##       LogView is HBox: StoryText | Choices (right column)
##   ChapterPlate > JournalPopup > PauseMenu > audio players
##
## PC controls: 1-9 choices, Q/E or Tab cycle tabs, Esc closes map/dossier then pause,
## M / click minimap opens vessel map, F11 / Alt+Enter fullscreen, Space/Enter advances.
##
## ---------------------------------------------------------------- DATA FORMATS
## passages[id] = {
##     "title":    "LOCKER ROOM",          # location title above the text (Oxanium)
##     "os_line":  "ASPECT: HOME",         # header system line (Plex Mono, forced to CAPS)
##     "comms":    ["LINE ONE", "LINE 2"], # optional companion lines in the header
##     "body":     "Prose with [[dossier_id|green link]] and {flag:x?shown if x|else}.",
##     "on_enter": ["arm_window:12"],      # ops run every time the passage is entered
##     "map_room": "stasis_15",             # optional: vessel-map room you are in here
##     "choices":  [ { "label": "Take the lamp",
##                     "goto": "next_passage",   # optional; no goto = stay and redraw
##                     "ops": ["give_item:worklamp"],
##                     "time_cost": 1,           # optional; only shown once window_armed
##                     "if": "!has_worklamp" } ],# optional condition (see below)
## }
## dossiers[id] = { "title": "SS Orison", "filed": "CLAIMS BRIEF", "body": "bbcode..." }
## items[id]    = { "label": "Worklamp", "desc": "Issued. 1 cell.", "dossier": "worklamp" }
## deck = { "aspect": "HOME", "os_line": "ASPECT: HOME / ...", "hint": "...",
##          "rooms": [ { "id": "home_bunk", "label": "BUNK", "pos": Vector2(0.5, 0.2),
##                       "goto": "home_bunk", "time_cost": 0, "if": "" } ],
##          "links": [ ["home_bunk", "home_lock"] ] }   # pos is 0..1 inside the map area
##
## ---------------------------------------------------------------- TEXT MARKUP
##   [[id|Label]]          green dossier link (tapping it opens + files the dossier)
##   {flag:x?A|B}          A if flag x is set, else B ("|B" optional, "!x" negates).
##                         A/B may contain links but not "|" or "}" (no nesting).
##   {v:name}              value of vars["name"], e.g. {v:callsign}, {v:blocks}
## Conditions ("if" on choices/rooms): "flag", "!flag", "a,b" (all must hold).
## give_item:x also sets flag "has_x".
##
## ---------------------------------------------------------------- OPS
##   set_flag:x  clear_flag:x  set_var:name=value  give_item:x  take_item:x
##   unlock_dossier:x  open_dossier:x  arm_window:12  spend:2  goto:passage
##   open_tab:deck  open_tab_once:deck  lock_tab:deck  unlock_tab:deck
##   plate:TITLE|SUBTITLE  toast:TEXT
##   map_explore:id  map_set_room:id  map_unlock_room:id  map_lock_room:id
##   map_unlock_door:a|b  map_lock_door:a|b  open_map
##   checkpoint                      save a retry point (state + current passage)
##   die  /  die:MESSAGE|RETRY       death screen (see DEATH SCREEN); RETRY = passage id,
##                                   "checkpoint", or empty (last checkpoint, else this passage)
##   An op may also be a Dictionary: {"die": {"message": "...", "heading": "...",
##   "retry": "home_bunk", "retry_label": "RETRY"}}  (other keys run as "key:value").
##   scene:ID  /  scene:ID/SCREEN     open a Scene Writer scene (story/scenes/ID.json)
##   go:TARGET                       any link target (see SCENE LINKS)
##   anything else is passed to _custom_op(name, arg) for chapter scripts.
##
## ---------------------------------------------------------------- UI SOUNDS
##   SfxOpen  = assets/sounds/UI-4.mp3  green link tapped / dossier popup opens / plate
##   SfxClose = assets/sounds/UI-6.mp3  dossier popup closes
##   SfxTap   = assets/sounds/UI-1.mp3  choice, tab, deck room, confirm buttons
##
## ---------------------------------------------------------------- DEBUG
## Arguments after "--" on the command line (also usable from Project Settings >
## Run > Main Run Args):  --jump=passage_id  --tab=deck  --popup=dossier_id
##                        --flags=a,b  --callsign=NAME  --plate  --map_demo  --open_map
##                        --map_hover=room_id (highlight a room in the open map)
##                        --shot=path [--shot_delay=1.2]
## Chapter scripts prepare sensible state for a jump in _debug_prepare().
##
## ---------------------------------------------------------------- UI RULE: PINNED RESPONSE
## After EVERY player response a NEW screen opens with the question (dim) and the chosen
## response ("> YES", accent) pinned at the top; the next text / VO types out below it.
##   pin_response(question, response) / clear_pin() / pinned_header_bb(q_bb, r_bb)
## The story runner does this automatically in choose(): the passage's optional "prompt"
## (or a choice's "pin_question") is the question, "> " + choice label is the response.
## Set pin_choices = false on a chapter to turn it off. The intro overlay (THAW / MEMORY
## EXAMINATION) uses the same builder for its pinned header (scenes/intro.gd).
##
## ---------------------------------------------------------------- DEATH SCREEN
## show_death(message, retry_label, retry_target, heading) hides EVERY UI layer (header,
## overlays, chapter HUDs) so only the background + screen shader remain, and centres the
## heading, message and RETRY. retry_target: Callable, passage id, "checkpoint" or null.
## Defaults: DEATH_HEADING / DEATH_MESSAGE / DEATH_RETRY. Hook: _on_death_shown().
## RETRY: click, Space, Enter or 1. Esc still pauses.
##
## ---------------------------------------------------------------- DEV BACK (debug builds only)
## dev_mode = OS.is_debug_build() (never in release exports; --nodev turns it off).
## Every screen pushes a snapshot (flags, vars, items, window, map, O2, pin, passage +
## _snapshot_extra()) with dev_push_screen(label, reenter). Mouse wheel UP (not over a text
## panel that can still scroll up) = dev_back(): stops chapter audio/timers
## (_dev_stop_chapter), restores the previous snapshot and re-enters that screen from the start.
## Passages push automatically in goto() (skip with "no_history": true).
##
## ---------------------------------------------------------------- SCENE LINKS
## go_target(target) moves between chapters / Scene Writer scenes. Targets:
##   "scene:ID" / "scene:ID/SCREEN"  Scene Writer scene (built scenes/authored/ID.tscn, else the
##                                   generic templates/authored_scene.tscn runner)
##   "intro:PASSAGE"                 a passage of scenes/intro.tscn (e.g. intro:home_bunk)
##   "tscn:res://path.tscn"          any scene file
##   "PASSAGE" / "passage:PASSAGE"   a passage of this chapter
## Flags, vars, items, filed dossiers and O2 carry over to the next scene (PdaScreen.carry).
## Scene Writer guide: docs/SCENE_WRITER.md.
##
## ---------------------------------------------------------------- OXYGEN
## set_o2(level 0..100, danger 0..1) drives every O2Bar (header + chapter overlays).
## refill_o2(seconds) tweens back to 100% calm. vars["o2"] mirrors the level.

signal passage_entered(id: StringName)
signal plate_tapped
signal died(message: String)
signal death_retried
## Click-to-move on the full map moved the player to room_id (see map_try_move).
signal map_moved(room_id: String)

enum Tab { LOG, DECK, LOCKER, KIT }

const LINK_COLOR := "#6fbf73"
const TAB_NAMES: Array[String] = ["log", "deck", "locker", "kit"]
const CHOICE_MIN_HEIGHT := 36.0
const ROOM_SIZE := Vector2(170, 44)
const HOURGLASS_COLOR := Color(0.93, 0.72, 0.38)
const DECK_LINK_COLOR := Color(0.3, 0.52, 0.34)
const PIN_QUESTION_COLOR := "#5f8f69"
const PIN_RESPONSE_COLOR := "#dff7e2"
const DEATH_HEADING := "SIGNAL LOST"
const DEATH_MESSAGE := "OPERATOR DECEASED"
const DEATH_RETRY := "RETRY"
const DEATH_COLOR := Color("#e07040")
const DEV_HISTORY_MAX := 64

## Passage shown by _begin() when the chapter doesn't override it.
@export var start_passage: StringName = &""
## Loop and start the Ambience player on ready (sets loop on the stream in code).
@export var ambience_autoplay := true
## Fade the LOG in and play one shader sweep (only visible with auto_loop off) on goto().
@export var animate_passage_change := true
## UI rule: pin the chosen choice (and the passage "prompt") at the top of the next screen.
@export var pin_choices := true
## Show the OXYGEN bar in the header.
@export var show_o2_in_header := true

# ---- story data: chapter scripts fill these in _setup_story() ----
var passages: Dictionary = {}
var dossiers: Dictionary = {}
var items: Dictionary = {}
var deck: Dictionary = {}
## Vessel schematic (rooms/doors/current). Chapters usually call ensure_vessel_map().
var vessel_map: Dictionary = {}
## Map refusal / move messages (in-world, shown in the map's info line).
const MAP_MSG_HERE := "YOU ARE HERE"
const MAP_MSG_NO_PASSAGE := "NO ACCESSIBLE PASSAGE"
const MAP_MSG_KEYCARD := "KEYCARD REQUIRED"
const MAP_MSG_RESTRICTED := "RESTRICTED"
const MAP_MSG_COLOR := Color(0.95, 0.66, 0.3)
const MAP_MSG_SECONDS := 2.2
const MAP_MOVE_SFX := "res://assets/sounds/dooropen.mp3"
var map_locked_open := false            # walkthrough: the full map can't be closed
var map_hint := ""                      # shown in the map info line when nothing is hovered
var map_last_message := ""              # last refusal / move message (tests)
var _map_msg_token := 0
var _map_msg_until := 0
var _map_move_player: AudioStreamPlayer

# ---- runtime state ----
var flags: Dictionary = {}
var vars: Dictionary = {"callsign": "operator", "blocks": 0}
var inventory: Array[StringName] = []
var unlocked: Array[StringName] = []
var window_blocks := 0
var window_max := 12
const TIME_BLOCK_MAX := 8
var time_blocks := TIME_BLOCK_MAX
var time_blocks_live := false
var excursion_chrome := false
var time_bar: HBoxContainer
var inv_button: Button
var inv_view: Control
var inv_grid: GridContainer
var inv_detail: Label
const INV_PLACEHOLDERS := [
	{"id": "sealant", "label": "SEALANT", "desc": "Not issued."},
	{"id": "ration", "label": "RATION", "desc": "Not issued."},
	{"id": "patch", "label": "PATCH", "desc": "Not issued."},
	{"id": "tape", "label": "TAPE", "desc": "Not issued."},
]
const TAB_INV := 4
var current_id: StringName = &""
var current_tab: int = Tab.LOG
var locked_tabs: Dictionary = {}

var _os_line_base := ""
var _toast_token := 0
var _pending_goto: StringName = &""
var _after: Array[Callable] = []
var _deck_buttons: Dictionary = {}
var _link_re := RegEx.new()
var _cond_re := RegEx.new()
var _var_re := RegEx.new()

@onready var screen: ColorRect = %Screen
@onready var backdrop: TextureRect = %Backdrop
@onready var safe_area: MarginContainer = %SafeArea
@onready var os_name_label: Label = %OsName
@onready var os_line_label: Label = %OsLine
@onready var comms_label: Label = %CommsLine
@onready var hourglass: HBoxContainer = %Hourglass
@onready var hourglass_icon: Control = %HourglassIcon
@onready var time_label: Label = %TimeLabel
@onready var title_label: Label = %Title
@onready var log_view: BoxContainer = %LogView  # HBox on PC: story | choices
@onready var story_text: RichTextLabel = %StoryText
@onready var choices_box: VBoxContainer = %Choices
@onready var deck_view: VBoxContainer = %DeckView
@onready var deck_aspect: Label = %DeckAspect
@onready var deck_hint: Label = %DeckHint
@onready var deck_map: Control = %DeckMap
@onready var locker_view: VBoxContainer = %LockerView
@onready var locker_list: VBoxContainer = %LockerList
@onready var kit_view: VBoxContainer = %KitView
@onready var kit_list: VBoxContainer = %KitList
@onready var tab_buttons: Array[Button] = [%TabLog, %TabDeck, %TabLocker, %TabKit]
@onready var plate: Control = %ChapterPlate
@onready var plate_title: Label = %PlateTitle
@onready var plate_sub: Label = %PlateSub
@onready var plate_hint: Label = %PlateHint
@onready var journal_button: TextureButton = %JournalButton
@onready var popup: Control = %JournalPopup
@onready var dim: ColorRect = %Dim
@onready var popup_meta: Label = %PopupMeta
@onready var popup_title: Label = %PopupTitle
@onready var popup_body: RichTextLabel = %PopupBody
@onready var close_button: Button = %CloseButton
@onready var ambience: AudioStreamPlayer = %Ambience
@onready var sfx_open: AudioStreamPlayer = %SfxOpen
@onready var sfx_close: AudioStreamPlayer = %SfxClose
@onready var sfx_tap: AudioStreamPlayer = %SfxTap
@onready var pause_menu: Control = %PauseMenu
@onready var resume_button: Button = %ResumeButton
@onready var fullscreen_button: Button = %FullscreenButton
@onready var quit_button: Button = %QuitButton
@onready var mini_map_host: Control = %MiniMapHost
@onready var mini_map_frame: VBoxContainer = %MiniMapFrame
@onready var mini_map_header: Label = %MiniMapHeader
@onready var map_overlay: Control = %MapOverlay
@onready var map_dim: ColorRect = %MapDim
@onready var map_host: Control = %MapHost
@onready var map_title: Label = %MapTitle
@onready var map_subtitle: Label = %MapSubtitle
@onready var map_info: Label = %MapInfo
@onready var map_close_button: Button = %MapCloseButton

var _choice_buttons: Array[Button] = []
var pinned_question := ""     # plain text (dim line)
var pinned_response := ""     # plain text ("> YES")
var _pin_keep := false
var o2_level := 100.0
var o2_danger := 0.0
var o2_bar: O2Bar             # header instance
var _o2_bars: Array[O2Bar] = []
var _o2_tween: Tween
var _extra_maps: Array[ShipMapView] = []
var _mini_map: ShipMapView
var _full_map: ShipMapView
var _link_hovering := false
# death screen
var death_screen: Control
var death_heading: Label
var death_message: Label
var death_retry_button: Button
var _death_target: Variant = null
var _death_hidden: Array = []        # [[CanvasItem, was_visible], ...]
var _death_shown_ms := 0
var _checkpoint: Dictionary = {}
# dev back
var dev_mode := false
var _history: Array = []             # [{label, state, reenter}, ...]
var _dev_back_ms := -10000
# scene links (static: survive change_scene_to_file)
static var carry: Dictionary = {}          # flags / vars / items / dossiers / O2 for the next scene
static var next_passage := ""              # passage the next chapter opens at ("intro:home_bunk")
static var next_authored := ""             # JSON the generic authored runner should play
static var next_screen := ""               # screen id inside that JSON
## Debug args (--jump, --screen, ...) belong to the scene the game started in. After a
## change_scene only --shot (at its original time) and --nodev carry over.
static var _debug_used := false
static var _shot_at_ms := -1


func _ready() -> void:
	_ensure_input_map()
	var args := _read_debug_args()
	dev_mode = OS.is_debug_build() and not args.has("nodev")
	_link_re.compile("\\[\\[(\\w+)\\|([^\\]]+)\\]\\]")
	_cond_re.compile("\\{flag:(!?)(\\w+)\\?([^|}]*)(?:\\|([^}]*))?\\}")
	_var_re.compile("\\{v:(\\w+)\\}")

	story_text.meta_clicked.connect(_on_meta_clicked)
	popup_body.meta_clicked.connect(_on_meta_clicked)
	journal_button.pressed.connect(_on_journal_button)
	close_button.pressed.connect(close_popup)
	dim.gui_input.connect(_on_dim_input)
	plate.gui_input.connect(_on_plate_input)
	hourglass_icon.draw.connect(_draw_hourglass)
	deck_map.draw.connect(_draw_deck_links)
	deck_map.resized.connect(_layout_deck)
	for i in tab_buttons.size():
		tab_buttons[i].pressed.connect(_on_tab_pressed.bind(i))
		tab_buttons[i].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	journal_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resume_button.pressed.connect(hide_pause)
	fullscreen_button.pressed.connect(toggle_fullscreen)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	for b in [resume_button, fullscreen_button, quit_button]:
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for rtl: RichTextLabel in [story_text, popup_body]:
		rtl.meta_hover_started.connect(_on_meta_hover.bind(rtl, true))
		rtl.meta_hover_ended.connect(_on_meta_hover.bind(rtl, false))

	popup.hide()
	plate.hide()
	pause_menu.hide()
	map_overlay.hide()
	comms_label.hide()
	_update_hourglass()
	_apply_safe_area()
	_start_ambience()
	_update_fullscreen_label()
	_setup_maps()
	_setup_o2()
	_setup_death()

	_setup_story()
	_apply_carry()
	_refresh_tab_buttons()
	if not _debug_start(_read_debug_args()):
		if next_passage != "" and passages.has(StringName(next_passage)):
			var p := StringName(next_passage)
			next_passage = ""
			_debug_prepare(p)
			goto(p)
		else:
			next_passage = ""
			_begin()
	_debug_used = true


# ======================================================== VIRTUAL HOOKS

## Chapters fill passages / dossiers / items / deck / flags here.
func _setup_story() -> void:
	pass


## Called once after setup (unless a debug --jump is given). Default: go to start_passage.
func _begin() -> void:
	if start_passage != &"":
		goto(start_passage)
	elif not passages.is_empty():
		goto(StringName(str(passages.keys()[0])))


## Called after every goto(), once the passage is on screen.
func _on_passage_entered(_id: StringName) -> void:
	pass


## Handle chapter-specific ops. Return true if handled.
func _custom_op(_op_name: String, _arg: String) -> bool:
	return false


## Set flags/items so a debug --jump=<id> lands in a believable state.
func _debug_prepare(_jump_id: StringName) -> void:
	pass


## Extra debug args for chapters (e.g. --plate). Runs after jump/tab/popup.
func _debug_extra(_args: Dictionary) -> void:
	pass


## The death screen just opened (stop chapter timers / heartbeat here).
func _on_death_shown() -> void:
	pass


## Chapter state that belongs in a dev-back / checkpoint snapshot.
func _snapshot_extra() -> Dictionary:
	return {}


func _restore_extra(_d: Dictionary) -> void:
	pass


## Dev back: stop the chapter's VO, timers, effects and overlays before a snapshot is restored.
func _dev_stop_chapter() -> void:
	pass


# ======================================================== PUBLIC API

## Location title above the story text ("BUNK", "LOCKER ROOM").
func set_title(text: String) -> void:
	title_label.text = text.to_upper()


## Header system line. OS register: always caps.
func set_os_line(text: String) -> void:
	_os_line_base = format_os(text)
	os_line_label.text = _current_os_line()


## Header companion lines (empty array hides them).
func set_comms(lines: Array) -> void:
	var shown := PackedStringArray()
	for l in lines:
		var s := format_os(str(l)).strip_edges()
		if s != "":
			shown.append("COMMS> " + s)
	comms_label.text = "\n".join(shown)
	comms_label.visible = not shown.is_empty()


## Briefly replaces the OS line (e.g. "FILED: SS ORISON"), then restores it.
func os_toast(msg: String, seconds := 2.5) -> void:
	_toast_token += 1
	var token := _toast_token
	os_line_label.text = format_os(msg)
	await get_tree().create_timer(seconds).timeout
	if token == _toast_token and is_inside_tree():
		os_line_label.text = _current_os_line()


func set_backdrop(tex: Texture2D, alpha := 0.3) -> void:
	backdrop.texture = tex
	backdrop.modulate.a = alpha
	backdrop.visible = tex != null


func goto(id: StringName) -> void:
	if not passages.has(id):
		push_error("PdaScreen: no passage '%s'" % id)
		return
	current_id = id
	_pending_goto = &""
	if not _pin_keep:
		clear_pin()
	_pin_keep = false
	var p: Dictionary = passages[id]
	if not bool(p.get("no_history", false)):
		dev_push_screen(String(id), _dev_reenter_passage.bind(id))
	var enter_ops: Array = p.get("on_enter", [])
	for op in enter_ops:
		run_op(op)
	_pending_goto = &""
	render_passage()
	show_tab(Tab.LOG, false)
	if animate_passage_change:
		log_view.modulate.a = 0.0
		create_tween().tween_property(log_view, "modulate:a", 1.0, 0.3)
		refresh()
	if p.has("map_room"):
		map_set_room(StringName(str(p["map_room"])))
	passage_entered.emit(id)
	_on_passage_entered(id)
	_flush_after()


## Redraws the current passage from data + flags (used after choices without goto).
func render_passage() -> void:
	var p: Dictionary = passages.get(current_id, {})
	set_title(str(p.get("title", "")))
	set_os_line(str(p.get("os_line", default_os_line())))
	var comms: Variant = p.get("comms", [])
	if comms is String:
		set_comms([comms])
	else:
		set_comms(comms as Array)
	var body := format_text(str(p.get("body", "")))
	if pinned_response != "":
		body = pinned_header_bb(_escape_pin(pinned_question), _escape_pin(pinned_response)) + "\n\n" + body
	story_text.text = body
	story_text.scroll_to_line(0)
	_build_choices(p.get("choices", []))


## OS line used when a passage has none.
func default_os_line() -> String:
	return "OPERATOR: {v:callsign}"


func choose(choice: Dictionary) -> void:
	play_sfx(&"tap")
	if pin_choices:
		var cur: Dictionary = passages.get(current_id, {})
		var q := str(choice.get("pin_question", cur.get("prompt", "")))
		pin_response(_apply_vars(q) if q != "" else "", "> " + str(choice.get("label", "")))
		_pin_keep = true
	var cost := int(choice.get("time_cost", 0))
	if cost > 0 and is_window_armed():
		spend_blocks(cost)
	_pending_goto = StringName(str(choice.get("goto", "")))
	var ops: Array = choice.get("ops", [])
	for op in ops:
		run_op(op)
	var target := _pending_goto
	_pending_goto = &""
	if target != &"":
		goto(target)  # goto flushes deferred UI ops
	else:
		_pin_keep = false
		_rerender_screen(current_id)
		_flush_after()


## A choice without goto still opens a NEW screen (UI rule): same passage, pinned response.
func _rerender_screen(id: StringName) -> void:
	current_id = id
	dev_push_screen("%s %s" % [id, pinned_response], _rerender_screen.bind(id))
	render_passage()
	if current_tab != Tab.LOG:
		show_tab(Tab.LOG, false)


# ---------------------------------------------------------------- pinned response (UI rule)

## Question (dim) + response (accent, bold) as bbcode. Either part may be empty.
func pinned_header_bb(question_bb: String, response_bb: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if question_bb != "":
		lines.append("[color=%s]%s[/color]" % [PIN_QUESTION_COLOR, question_bb])
	if response_bb != "":
		lines.append("[color=%s][b]%s[/b][/color]" % [PIN_RESPONSE_COLOR, response_bb])
	return "\n".join(lines)


func pin_response(question: String, response: String) -> void:
	pinned_question = question
	pinned_response = response


func clear_pin() -> void:
	pinned_question = ""
	pinned_response = ""


func _escape_pin(t: String) -> String:
	return t.replace("[", "[lb]")


# ---------------------------------------------------------------- oxygen

func _setup_o2() -> void:
	o2_bar = O2Bar.new()
	o2_bar.name = "O2Bar"
	var header := %Header as HBoxContainer
	header.add_child(o2_bar)
	header.move_child(o2_bar, hourglass.get_index())
	o2_bar.visible = show_o2_in_header
	register_o2_bar(o2_bar)


func register_o2_bar(bar: O2Bar) -> void:
	if not _o2_bars.has(bar):
		_o2_bars.append(bar)
	bar.set_state(o2_level, o2_danger)


## level 0..100, danger 0 (calm) .. 1 (critical: red, fast pulse).
func set_o2(level: float, danger := 0.0) -> void:
	o2_level = clampf(level, 0.0, 100.0)
	o2_danger = clampf(danger, 0.0, 1.0)
	vars["o2"] = int(round(o2_level))
	for b in _o2_bars:
		if is_instance_valid(b):
			b.set_state(o2_level, o2_danger)


## Smoothly back to 100% and calm.
func refill_o2(seconds := 1.2) -> void:
	if _o2_tween:
		_o2_tween.kill()
	var from := o2_level
	var dz := o2_danger
	_o2_tween = create_tween()
	_o2_tween.tween_method(func(k: float) -> void: set_o2(lerpf(from, 100.0, k), lerpf(dz, 0.0, k)),
		0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _o2_refilling() -> bool:
	return _o2_tween != null and _o2_tween.is_valid() and _o2_tween.is_running()


func stop_o2_tween() -> void:
	if _o2_tween:
		_o2_tween.kill()
		_o2_tween = null


## Extra read-only map views (e.g. an overlay minimap) kept in sync with vessel_map.
func register_map_view(v: ShipMapView) -> void:
	if not _extra_maps.has(v):
		_extra_maps.append(v)
	if not vessel_map.is_empty():
		v.set_map(vessel_map)


func run_op(op: Variant) -> void:
	if op is Dictionary:
		for k in (op as Dictionary):
			_run_dict_op(str(k), (op as Dictionary)[k])
		return
	var parts := str(op).split(":", true, 1)
	var op_name := parts[0].strip_edges()
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	match op_name:
		"set_flag":
			flags[arg] = true
		"clear_flag":
			flags.erase(arg)
		"set_var":
			var kv := arg.split("=", true, 1)
			vars[kv[0]] = kv[1] if kv.size() > 1 else ""
		"give_item":
			give_item(StringName(arg))
		"take_item":
			take_item(StringName(arg))
		"unlock_dossier":
			unlock_dossier(StringName(arg))
		"open_dossier":
			_after.append(open_dossier.bind(StringName(arg)))
		"arm_window":
			arm_window(int(arg) if arg != "" else 12)
		"spend":
			spend_blocks(int(arg))
		"goto":
			_pending_goto = StringName(arg)
		"open_tab":
			_after.append(show_tab.bind(tab_from_name(arg)))
		"open_tab_once":
			if not has_flag("seen_tab_" + arg):
				flags["seen_tab_" + arg] = true
				_after.append(show_tab.bind(tab_from_name(arg)))
		"lock_tab":
			set_tab_locked(tab_from_name(arg), true)
		"unlock_tab":
			set_tab_locked(tab_from_name(arg), false)
		"plate":
			var pt := arg.split("|", true, 1)
			_after.append(show_plate.bind(format_os(pt[0]), format_os(pt[1]) if pt.size() > 1 else ""))
		"toast":
			os_toast(arg)
		"map_explore":
			map_explore(StringName(arg))
		"map_set_room":
			map_set_room(StringName(arg))
		"map_unlock_room":
			map_set_room_state(StringName(arg), "unexplored")
		"map_lock_room":
			map_set_room_state(StringName(arg), "locked")
		"map_unlock_door":
			map_set_door_state(arg, "open")
		"map_lock_door":
			map_set_door_state(arg, "locked")
		"open_map":
			_after.append(open_map)
		"map_know_room":
			map_know_room(StringName(arg))
		"map_know_door":
			map_know_door(arg)
		"map_restrict_room":
			map_restrict_room(StringName(arg), true)
		"map_unrestrict_room":
			map_restrict_room(StringName(arg), false)
		"o2_full":
			stop_o2_tween()
			set_o2(100.0, 0.0)
		"map_moves":
			ensure_vessel_map()
			vessel_map["click_to_move"] = arg.to_lower() in ["on", "true", "1", ""]
		"checkpoint":
			save_checkpoint()
		"scene":
			_after.append(go_target.bind("scene:" + arg))
		"go":
			_after.append(go_target.bind(arg))
		"die":
			var dp := arg.split("|", true)
			_run_dict_op("die", {"message": dp[0] if dp.size() > 0 else "",
				"retry": dp[1] if dp.size() > 1 else "",
				"retry_label": dp[2] if dp.size() > 2 else "",
				"heading": dp[3] if dp.size() > 3 else ""})
		_:
			if not _custom_op(op_name, arg):
				push_warning("PdaScreen: unknown op '%s'" % op)


## Dictionary ops: {"die": {...}} or {"name": "arg"} (= "name:arg").
func _run_dict_op(key: String, val: Variant) -> void:
	if key == "die":
		var d: Dictionary = val if val is Dictionary else {"message": str(val)}
		var msg := str(d.get("message", ""))
		var label := str(d.get("retry_label", ""))
		var heading := str(d.get("heading", ""))
		var retry: Variant = d.get("retry", null)
		_after.append(show_death.bind(format_os(msg) if msg != "" else DEATH_MESSAGE,
			label if label != "" else DEATH_RETRY, retry if str(retry) != "" else null,
			format_os(heading) if heading != "" else DEATH_HEADING))
		return
	run_op("%s:%s" % [key, str(val)] if val != null and str(val) != "" else key)


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


## "" = true; "a,!b" = a set and b not set.
func check_condition(cond: String) -> bool:
	if cond.strip_edges() == "":
		return true
	for part in cond.split(",", false):
		var f := part.strip_edges()
		var negate := f.begins_with("!")
		if negate:
			f = f.substr(1)
		if has_flag(f) == negate:
			return false
	return true


func give_item(id: StringName) -> void:
	if id not in inventory:
		inventory.append(id)
	flags["has_" + str(id)] = true
	if current_tab == Tab.KIT:
		_rebuild_kit()
	if current_tab == TAB_INV:
		_rebuild_inv()


func take_item(id: StringName) -> void:
	inventory.erase(id)
	flags.erase("has_" + str(id))


func unlock_dossier(id: StringName) -> void:
	if id in unlocked or not dossiers.has(id):
		return
	unlocked.append(id)
	var d: Dictionary = dossiers[id]
	os_toast("FILED: " + format_os(str(d.get("title", id))))
	if current_tab == Tab.LOCKER:
		_rebuild_locker()


func is_window_armed() -> bool:
	return has_flag("window_armed")


func arm_window(blocks: int) -> void:
	flags["window_armed"] = true
	window_max = maxi(blocks, 1)
	window_blocks = blocks
	vars["blocks"] = window_blocks
	_update_hourglass()


func spend_blocks(n: int) -> void:
	window_blocks = maxi(0, window_blocks - n)
	vars["blocks"] = window_blocks
	_update_hourglass()


# ---------------------------------------------------------------- text

## Wraps a word as a green, bold dossier link (for building strings in code).
func j(id: String, label: String) -> String:
	return "[url=dossier:%s][b][color=%s]%s[/color][/b][/url]" % [id, LINK_COLOR, label]


## Prose: links, then flag conditionals, then variables.
func format_text(src: String) -> String:
	var s := _link_re.sub(src, j("$1", "$2"), true)
	s = _apply_conditions(s)
	return _apply_vars(s)


## OS register: conditionals + variables, all caps, no bbcode.
func format_os(src: String) -> String:
	return _apply_vars(_apply_conditions(src)).to_upper()


func _apply_conditions(src: String) -> String:
	var s := src
	var matches := _cond_re.search_all(s)
	matches.reverse()
	for m in matches:
		var on := has_flag(m.get_string(2)) != (m.get_string(1) == "!")
		var rep := m.get_string(3) if on else m.get_string(4)
		s = s.substr(0, m.get_start()) + rep + s.substr(m.get_end())
	return s


func _apply_vars(src: String) -> String:
	var s := src
	var matches := _var_re.search_all(s)
	matches.reverse()
	for m in matches:
		s = s.substr(0, m.get_start()) + str(vars.get(m.get_string(1), "")) + s.substr(m.get_end())
	return s


# ---------------------------------------------------------------- dossiers

func open_dossier(id: StringName) -> void:
	if not dossiers.has(id):
		push_warning("PdaScreen: no dossier '%s'" % id)
		return
	unlock_dossier(id)
	var d: Dictionary = dossiers[id]
	popup_meta.text = format_os(str(d.get("filed", "DOSSIER")))
	popup_title.text = _apply_vars(str(d.get("title", id)))
	popup_body.text = format_text(str(d.get("body", "")))
	popup_body.scroll_to_line(0)
	play_sfx(&"open")
	popup.show()


func close_popup() -> void:
	if popup.visible:
		play_sfx(&"close")
	popup.hide()


func _on_meta_clicked(meta: Variant) -> void:
	var s := str(meta)
	for prefix in ["dossier:", "journal:"]:
		if s.begins_with(prefix):
			open_dossier(StringName(s.trim_prefix(prefix)))
			return


func _on_dim_input(event: InputEvent) -> void:
	if _is_press(event):
		close_popup()


func _on_journal_button() -> void:
	play_sfx(&"tap")
	if excursion_chrome:
		show_inv()
	else:
		show_tab(Tab.LOCKER)


# ---------------------------------------------------------------- tabs

func tab_from_name(tab_name: String) -> int:
	var i := TAB_NAMES.find(tab_name.to_lower())
	return i if i >= 0 else Tab.LOG


func set_tab_locked(tab: int, locked: bool) -> void:
	if locked:
		locked_tabs[tab] = true
	else:
		locked_tabs.erase(tab)
	if is_node_ready():
		_refresh_tab_buttons()


func show_tab(tab: int, click := false) -> void:
	if locked_tabs.has(tab):
		return
	if click:
		play_sfx(&"tap")
	current_tab = tab
	if inv_view:
		inv_view.hide()
	if inv_button:
		inv_button.theme_type_variation = &"TabButton"
	log_view.visible = tab == Tab.LOG
	deck_view.visible = tab == Tab.DECK
	locker_view.visible = tab == Tab.LOCKER
	kit_view.visible = tab == Tab.KIT
	match tab:
		Tab.DECK:
			_rebuild_deck()
		Tab.LOCKER:
			_rebuild_locker()
		Tab.KIT:
			_rebuild_kit()
	_refresh_tab_buttons()
	os_line_label.text = _current_os_line()
	_refresh_maps()


func _on_tab_pressed(tab: int) -> void:
	show_tab(tab, true)


func _refresh_tab_buttons() -> void:
	for i in tab_buttons.size():
		var b := tab_buttons[i]
		b.disabled = locked_tabs.has(i)
		b.theme_type_variation = &"TabButtonActive" if i == current_tab else &"TabButton"


func _current_os_line() -> String:
	if current_tab == Tab.DECK and deck.has("os_line"):
		return format_os(str(deck["os_line"]))
	return _os_line_base



# ---------------------------------------------------------------- excursion hours / inventory

## Main game UI only: LOG + INV, and the 8-hour bar. Intro tabs stay as they are.
func set_excursion_chrome(on: bool) -> void:
	excursion_chrome = on
	if not is_node_ready():
		return
	_ensure_time_bar()
	_ensure_inv()
	time_bar.visible = on
	inv_button.visible = on
	for i in [Tab.DECK, Tab.LOCKER, Tab.KIT]:
		tab_buttons[i].visible = not on
	if on:
		journal_button.tooltip_text = "Inventory"
		if current_tab in [Tab.DECK, Tab.LOCKER, Tab.KIT]:
			show_tab(Tab.LOG)
	else:
		journal_button.tooltip_text = "Locker (L)"
		if inv_view:
			inv_view.hide()
		if current_tab == TAB_INV:
			show_tab(Tab.LOG)
	_refresh_time_bar()


func arm_time_blocks() -> void:
	time_blocks_live = true
	time_blocks = TIME_BLOCK_MAX
	_refresh_time_bar()


## Returns false until a later scene calls arm_time_blocks(). The bar still shows the cost.
func spend_time_blocks(n: int) -> bool:
	if not time_blocks_live or n < 1 or n > time_blocks:
		return false
	time_blocks -= n
	_refresh_time_bar()
	return true


func _ensure_time_bar() -> void:
	if time_bar:
		return
	time_bar = HBoxContainer.new()
	time_bar.name = "TimeBlocks"
	time_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_bar.add_theme_constant_override("separation", 3)
	time_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := Label.new()
	cap.text = "HRS"
	cap.theme_type_variation = &"OsLabelDim"
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_bar.add_child(cap)
	for _i in TIME_BLOCK_MAX:
		var cell := ColorRect.new()
		cell.custom_minimum_size = Vector2(10, 16)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		time_bar.add_child(cell)
	var header := hourglass.get_parent()
	header.add_child(time_bar)
	header.move_child(time_bar, hourglass.get_index())
	_refresh_time_bar()


func _refresh_time_bar() -> void:
	if time_bar == null:
		return
	var i := 0
	for c in time_bar.get_children():
		if c is ColorRect:
			(c as ColorRect).color = Color(0.45, 0.82, 0.48) if i < time_blocks else Color(0.12, 0.16, 0.13)
			i += 1


func _ensure_inv() -> void:
	if inv_view:
		return
	var tabs := tab_buttons[0].get_parent()
	inv_button = Button.new()
	inv_button.name = "TabInv"
	inv_button.text = "INV"
	inv_button.custom_minimum_size = Vector2(0, 42)
	inv_button.theme_type_variation = &"TabButton"
	inv_button.focus_mode = Control.FOCUS_NONE
	inv_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	inv_button.pressed.connect(show_inv)
	tabs.add_child(inv_button)
	tabs.move_child(inv_button, tab_buttons[0].get_index() + 1)
	inv_view = PanelContainer.new()
	inv_view.name = "InvView"
	inv_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inv_view.mouse_filter = Control.MOUSE_FILTER_STOP
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.015, 0.04, 0.02, 0.94)
	box_style.border_color = Color(0.44, 0.75, 0.45)
	box_style.set_border_width_all(1)
	box_style.set_content_margin_all(12)
	inv_view.add_theme_stylebox_override("panel", box_style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inv_view.add_child(col)
	var head := Label.new()
	head.text = "INV"
	head.theme_type_variation = &"TitleLabel"
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	inv_grid = GridContainer.new()
	inv_grid.columns = 4
	inv_grid.add_theme_constant_override("h_separation", 8)
	inv_grid.add_theme_constant_override("v_separation", 8)
	inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inv_grid)
	inv_detail = Label.new()
	inv_detail.theme_type_variation = &"OsLabel"
	inv_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_detail.text = ""
	col.add_child(inv_detail)
	log_view.get_parent().add_child(inv_view)
	inv_view.hide()


func show_inv() -> void:
	if not excursion_chrome:
		return
	_ensure_inv()
	current_tab = TAB_INV
	log_view.hide()
	deck_view.hide()
	locker_view.hide()
	kit_view.hide()
	inv_view.show()
	inv_button.theme_type_variation = &"TabButtonActive"
	_refresh_tab_buttons()
	_rebuild_inv()
	os_line_label.text = _current_os_line()


func _rebuild_inv() -> void:
	if inv_grid == null:
		return
	for c in inv_grid.get_children():
		c.queue_free()
	var seen := {}
	for ph: Dictionary in INV_PLACEHOLDERS:
		seen[str(ph["id"])] = true
		var owned := StringName(str(ph["id"])) in inventory
		var desc := str(items.get(StringName(str(ph["id"])), {}).get("desc", ph["desc"])) if owned else str(ph["desc"])
		_add_inv_cell(str(ph["label"]), desc, owned)
	for id in inventory:
		if seen.has(str(id)):
			continue
		var it: Dictionary = items.get(id, {})
		_add_inv_cell(str(it.get("label", id)), str(it.get("desc", "")), true)


func _add_inv_cell(label: String, desc: String, owned: bool) -> void:
	var b := Button.new()
	b.theme_type_variation = &"ChoiceButton"
	b.custom_minimum_size = Vector2(120, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.text = label
	b.tooltip_text = label if desc == "" else "%s\n%s" % [label, desc]
	b.modulate = Color(1, 1, 1, 1) if owned else Color(1, 1, 1, 0.45)
	b.pressed.connect(func() -> void:
		inv_detail.text = b.tooltip_text.replace("\n", " — "))
	inv_grid.add_child(b)


# ---------------------------------------------------------------- choices

func _build_choices(list: Array) -> void:
	for old in choices_box.get_children():
		old.queue_free()
	_choice_buttons.clear()
	var idx := 0
	for entry in list:
		var choice: Dictionary = entry
		if not check_condition(str(choice.get("if", ""))):
			continue
		idx += 1
		var show_cost := is_window_armed() and choice.has("time_cost")
		var b := Button.new()
		b.theme_type_variation = &"ChoiceButtonCost" if show_cost else &"ChoiceButton"
		b.text = _apply_vars(_apply_conditions(str(choice.get("label", "..."))))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, CHOICE_MIN_HEIGHT)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.focus_mode = Control.FOCUS_ALL
		if show_cost:
			b.add_child(_cost_label(int(choice.get("time_cost", 0))))
		b.pressed.connect(choose.bind(choice))
		choices_box.add_child(b)
		_choice_buttons.append(b)
	_fit_minimap.call_deferred()


func _cost_label(cost: int) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"ChoiceCost"
	l.text = "%d BLK" % cost
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	l.offset_left = -70.0
	l.offset_right = -10.0
	return l



# ---------------------------------------------------------------- vessel map
## Ship schematic lives in vessel_map (default: data/vessel.gd). Rooms/doors change through
## the map_* ops so story passages can explore rooms and unlock doors.

## Load the default REC-7 schematic if the chapter hasn't set one yet.
func ensure_vessel_map() -> void:
	if vessel_map.is_empty():
		vessel_map = Vessel.default_map()
	_refresh_maps()


func _setup_maps() -> void:
	_mini_map = ShipMapView.new()
	_mini_map.name = "MiniMap"
	_mini_map.compact = true
	_mini_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mini_map.map_clicked.connect(open_map)
	mini_map_host.add_child(_mini_map)
	_full_map = ShipMapView.new()
	_full_map.name = "FullMap"
	_full_map.show_legend = true
	_full_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_map.room_hovered.connect(_on_map_room_hovered)
	_full_map.room_clicked.connect(_on_full_map_room_clicked)
	map_host.add_child(_full_map)
	map_close_button.pressed.connect(close_map)
	map_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	map_dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_map()
	)
	mini_map_frame.visible = false
	mini_map_header.mouse_filter = Control.MOUSE_FILTER_STOP
	mini_map_header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mini_map_header.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open_map()
	)
	(choices_box.get_parent() as Control).resized.connect(_fit_minimap)


func _refresh_maps() -> void:
	if not is_node_ready() or _mini_map == null:
		return
	mini_map_frame.visible = not vessel_map.is_empty()
	if vessel_map.is_empty():
		return
	_mini_map.set_map(vessel_map)
	_full_map.set_map(vessel_map)
	for v in _extra_maps:
		if is_instance_valid(v):
			v.set_map(vessel_map)
	mini_map_header.text = "%s // MAP" % str(vessel_map.get("title", Vessel.VESSEL_TITLE)).to_upper()
	map_title.text = str(vessel_map.get("title", Vessel.VESSEL_TITLE)).to_upper()
	map_subtitle.text = str(vessel_map.get("subtitle", "DECK SCHEMATIC")).to_upper()
	_on_map_room_hovered(_full_map.hovered_id)


## The minimap shares the ACTIONS column: hide its drawing when choices need the space
## (the header stays as a clickable "// MAP" line).
func _fit_minimap() -> void:
	if not is_node_ready() or vessel_map.is_empty():
		return
	mini_map_host.visible = true
	var col := choices_box.get_parent() as Control
	var need := 0.0
	for b in _choice_buttons:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			need += b.get_combined_minimum_size().y + 6.0
	var header_h := 22.0
	var free := col.size.y - header_h - need - mini_map_frame.get_combined_minimum_size().y - 12.0
	mini_map_host.visible = free >= 0.0


func _map_room_label(id: String) -> String:
	var room: Dictionary = (vessel_map.get("rooms", {}) as Dictionary).get(id, {})
	if room.is_empty():
		return "-"
	if str(room.get("state", "")) == "explored" or bool(room.get("known", false)):
		return str(room.get("label", id)).to_upper()
	return "UNCHARTED COMPARTMENT"


func _on_map_room_hovered(id: String) -> void:
	if Time.get_ticks_msec() < _map_msg_until:
		return   # a refusal / move message is showing
	map_info.remove_theme_color_override("font_color")
	var here := str(vessel_map.get("current", ""))
	var line := "YOU ARE HERE: %s" % _map_room_label(here)
	if map_hint != "" and id == "":
		line = map_hint
	if id != "":
		var st := str(((vessel_map.get("rooms", {}) as Dictionary).get(id, {}) as Dictionary).get("state", ""))
		var st_text: String = {"explored": "EXPLORED", "unexplored": "NOT EXPLORED", "locked": "LOCKED // NO ACCESS"}.get(st, st.to_upper())
		if map_room_restricted(id):
			st_text = MAP_MSG_RESTRICTED
		line = "%s  //  %s" % [_map_room_label(id), st_text]
	map_info.text = line


func open_map() -> void:
	ensure_vessel_map()
	if map_overlay.visible or plate.visible:
		return
	if popup.visible:
		popup.hide()
	_refresh_maps()
	map_overlay.show()
	play_sfx(&"open")
	if map_close_button.visible:
		map_close_button.grab_focus()


func close_map() -> void:
	if not map_overlay.visible or map_locked_open:
		return
	map_overlay.hide()
	play_sfx(&"close")


## Walkthrough: keep the full map open (no Close button, dim / M / Esc don't close it).
func map_lock_open(on: bool) -> void:
	map_locked_open = on
	map_close_button.visible = not on


## Name known, not explored: the room stays dark but shows its label.
func map_know_room(room_id: StringName) -> void:
	var room := _map_room(room_id)
	if room.is_empty():
		return
	room["known"] = true
	_refresh_maps()


## Door drawn even though neither side has been explored.
func map_know_door(arg: String) -> void:
	ensure_vessel_map()
	var parts := arg.split("|", false)
	if parts.size() < 2:
		return
	var a := parts[0].strip_edges()
	var b := parts[1].strip_edges()
	for d: Dictionary in vessel_map.get("doors", []):
		var da := str(d.get("a", ""))
		var db := str(d.get("b", ""))
		if (da == a and db == b) or (da == b and db == a):
			d["known"] = true
	_refresh_maps()


## RESTRICTED: the room stays dark with a red outline + RESTRICTED stamp; moving there is refused.
## Newly restricted rooms pop the stamp in on every visible map view (ShipMapView.pop_stamp).
func map_restrict_room(room_id: StringName, on := true) -> void:
	var room := _map_room(room_id)
	if room.is_empty():
		return
	var was := bool(room.get("restricted", false))
	room["restricted"] = on
	_refresh_maps()
	if on and not was:
		var views: Array = [_mini_map, _full_map]
		views.append_array(_extra_maps)
		for v: Variant in views:
			if is_instance_valid(v):
				(v as ShipMapView).pop_stamp(String(room_id))


func map_room_restricted(room_id: String) -> bool:
	return bool(((vessel_map.get("rooms", {}) as Dictionary).get(room_id, {}) as Dictionary).get("restricted", false))


func map_moves_enabled() -> bool:
	return bool(vessel_map.get("click_to_move", false))


## The door between two rooms ({} if none).
func map_door_between(a: String, b: String) -> Dictionary:
	for d: Dictionary in vessel_map.get("doors", []):
		var da := str(d.get("a", ""))
		var db := str(d.get("b", ""))
		if (da == a and db == b) or (da == b and db == a):
			return d
	return {}


## "" if the player can move from the current room to room_id, else the refusal message.
func map_move_refusal(room_id: String) -> String:
	var rooms: Dictionary = vessel_map.get("rooms", {})
	if not rooms.has(room_id):
		return MAP_MSG_NO_PASSAGE
	var here := str(vessel_map.get("current", ""))
	if room_id == here:
		return MAP_MSG_HERE
	if map_room_restricted(room_id):
		return MAP_MSG_RESTRICTED
	var door := map_door_between(here, room_id)
	if door.is_empty():
		return MAP_MSG_NO_PASSAGE
	if str(door.get("state", "open")) != "open" or str((rooms[room_id] as Dictionary).get("state", "")) == "locked":
		return MAP_MSG_KEYCARD
	return ""


## Click-to-move: next room through an open door → move there (explored, dot moved).
## Otherwise an in-world refusal in the map's info line. Returns true if the player moved.
func map_try_move(room_id: String) -> bool:
	ensure_vessel_map()
	var why := map_move_refusal(room_id)
	if why != "":
		map_message(why)
		play_sfx(&"close")
		return false
	map_set_room(StringName(room_id))
	map_message("MOVED TO: %s" % _map_room_label(room_id), false)
	_play_move_sfx()
	map_moved.emit(room_id)
	return true


func _on_full_map_room_clicked(room_id: String) -> void:
	if map_moves_enabled() and map_overlay.visible and _allow_map_moves():
		map_try_move(room_id)


## Chapters that must never move the player from the map (the intro) return false.
func _allow_map_moves() -> bool:
	return true


## Temporary line in the map's info bar (amber for refusals), then back to normal.
func map_message(text: String, warn := true) -> void:
	map_last_message = text
	_map_msg_token += 1
	var token := _map_msg_token
	_map_msg_until = 0
	map_info.text = text
	if warn:
		map_info.add_theme_color_override("font_color", MAP_MSG_COLOR)
	else:
		map_info.remove_theme_color_override("font_color")
	_map_msg_until = Time.get_ticks_msec() + int(MAP_MSG_SECONDS * 1000.0)
	await get_tree().create_timer(MAP_MSG_SECONDS).timeout
	if token == _map_msg_token and is_inside_tree():
		_map_msg_until = 0
		_on_map_room_hovered(_full_map.hovered_id if _full_map else "")


func _play_move_sfx() -> void:
	if not ResourceLoader.exists(MAP_MOVE_SFX):
		play_sfx(&"open")
		return
	if _map_move_player == null:
		_map_move_player = AudioStreamPlayer.new()
		_map_move_player.name = "MapMoveSfx"
		_map_move_player.bus = sfx_open.bus
		_map_move_player.volume_db = -8.0
		add_child(_map_move_player)
	_map_move_player.stream = load(MAP_MOVE_SFX)
	_map_move_player.play()


func _map_room(room_id: StringName) -> Dictionary:
	ensure_vessel_map()
	return (vessel_map.get("rooms", {}) as Dictionary).get(String(room_id), {})


## Marks a room explored (locked rooms stay locked until map_unlock_room).
func map_explore(room_id: StringName) -> void:
	var room := _map_room(room_id)
	if room.is_empty() or str(room.get("state", "")) == "locked":
		return
	room["state"] = "explored"
	_refresh_maps()


## Moves the you-are-here marker (and explores the room).
func map_set_room(room_id: StringName) -> void:
	var room := _map_room(room_id)
	if room.is_empty():
		return
	vessel_map["current"] = String(room_id)
	map_explore(room_id)
	_refresh_maps()


func map_set_room_state(room_id: StringName, state: String) -> void:
	var room := _map_room(room_id)
	if room.is_empty():
		return
	room["state"] = state
	_refresh_maps()


## arg format "a|b" (order-insensitive).
func map_set_door_state(arg: String, state: String) -> void:
	ensure_vessel_map()
	var parts := arg.split("|", false)
	if parts.size() < 2:
		return
	var a := parts[0].strip_edges()
	var b := parts[1].strip_edges()
	for d: Dictionary in vessel_map.get("doors", []):
		var da := str(d.get("a", ""))
		var db := str(d.get("b", ""))
		if (da == a and db == b) or (da == b and db == a):
			d["state"] = state
	_refresh_maps()


## Debug (--map_demo): every legend state on screen at once.
func apply_map_demo() -> void:
	ensure_vessel_map()
	map_set_room(&"stasis_15")
	map_explore(&"ready_room")
	map_explore(&"aft_port")
	map_set_room_state(&"stbd_hold", "locked")
	map_know_room(&"airlock")
	map_set_door_state("ready_room|airlock", "open")
	map_set_door_state("ready_room|stbd_hold", "locked")
	map_set_room(&"ready_room")


# ---------------------------------------------------------------- deck view

func _rebuild_deck() -> void:
	for old in deck_map.get_children():
		old.queue_free()
	_deck_buttons.clear()
	deck_aspect.text = format_os("DECK // ASPECT: " + str(deck.get("aspect", "-")))
	deck_hint.text = format_os(str(deck.get("hint", "")))
	deck_hint.visible = deck_hint.text != ""
	var rooms: Array = deck.get("rooms", [])
	for entry in rooms:
		var room: Dictionary = entry
		if not check_condition(str(room.get("if", ""))):
			continue
		var id := StringName(str(room.get("id", "")))
		var here := id == current_id
		var b := Button.new()
		b.theme_type_variation = &"RoomButtonHere" if here else &"RoomButton"
		var label := format_os(str(room.get("label", id)))
		if here:
			label += "  \u2022  HERE"
		elif is_window_armed() and room.has("time_cost"):
			label += "  \u00b7  %d BLK" % int(room.get("time_cost", 0))
		b.text = label
		b.custom_minimum_size = ROOM_SIZE
		b.size = ROOM_SIZE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_on_room_pressed.bind(room))
		deck_map.add_child(b)
		_deck_buttons[id] = b
	_layout_deck()


func _layout_deck() -> void:
	var rooms: Array = deck.get("rooms", [])
	for entry in rooms:
		var room: Dictionary = entry
		var id := StringName(str(room.get("id", "")))
		if not _deck_buttons.has(id):
			continue
		var b: Button = _deck_buttons[id]
		var pos: Vector2 = room.get("pos", Vector2(0.5, 0.5))
		b.position = (deck_map.size * pos - b.size * 0.5).round()
	deck_map.queue_redraw()


func _draw_deck_links() -> void:
	var links: Array = deck.get("links", [])
	for entry in links:
		var pair: Array = entry
		if pair.size() < 2:
			continue
		var a := StringName(str(pair[0]))
		var z := StringName(str(pair[1]))
		if not (_deck_buttons.has(a) and _deck_buttons.has(z)):
			continue
		var ba: Button = _deck_buttons[a]
		var bz: Button = _deck_buttons[z]
		var ca := ba.position + ba.size * 0.5
		var cz := bz.position + bz.size * 0.5
		var d := cz - ca
		if d.length() < 1.0:
			continue
		# start/end at the button edges so the line never shows through a room
		var start := ca + d * _rect_exit(d, ba.size * 0.5)
		var finish := cz - d * _rect_exit(d, bz.size * 0.5)
		deck_map.draw_dashed_line(start, finish, DECK_LINK_COLOR, 2.0, 8.0)


func _rect_exit(d: Vector2, half: Vector2) -> float:
	var tx := half.x / absf(d.x) if absf(d.x) > 0.001 else INF
	var ty := half.y / absf(d.y) if absf(d.y) > 0.001 else INF
	return minf(tx, ty) + 4.0 / d.length()


func _on_room_pressed(room: Dictionary) -> void:
	play_sfx(&"tap")
	var target := StringName(str(room.get("goto", room.get("id", ""))))
	if target == current_id or target == &"":
		show_tab(Tab.LOG)
		return
	var cost := int(room.get("time_cost", 0))
	if cost > 0 and is_window_armed():
		spend_blocks(cost)
	goto(target)


# ---------------------------------------------------------------- locker + kit

func _rebuild_locker() -> void:
	for old in locker_list.get_children():
		old.queue_free()
	if unlocked.is_empty():
		locker_list.add_child(_empty_label("NOTHING FILED."))
		return
	for id in unlocked:
		var d: Dictionary = dossiers.get(id, {})
		var b := Button.new()
		b.theme_type_variation = &"LockerButton"
		b.text = _apply_vars(str(d.get("title", id)))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, CHOICE_MIN_HEIGHT)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(open_dossier.bind(id))
		locker_list.add_child(b)


func _rebuild_kit() -> void:
	for old in kit_list.get_children():
		old.queue_free()
	if inventory.is_empty():
		kit_list.add_child(_empty_label("NOTHING CARRIED."))
		return
	for id in inventory:
		var it: Dictionary = items.get(id, {})
		var b := Button.new()
		b.theme_type_variation = &"ChoiceButton"
		var desc := str(it.get("desc", ""))
		b.text = str(it.get("label", id)) + ("  \u2014  " + desc if desc != "" else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, CHOICE_MIN_HEIGHT)
		var dossier_id := StringName(str(it.get("dossier", "")))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if dossier_id != &"":
			b.pressed.connect(open_dossier.bind(dossier_id))
		kit_list.add_child(b)


func _empty_label(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"OsLabelDim"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ---------------------------------------------------------------- window / hourglass

func _update_hourglass() -> void:
	hourglass.visible = is_window_armed()
	time_label.text = str(window_blocks)
	hourglass_icon.queue_redraw()


## Vector hourglass (none of the kit fonts has an hourglass glyph). Sand drains with blocks.
func _draw_hourglass() -> void:
	var w := hourglass_icon.size.x
	var h := hourglass_icon.size.y
	var mid := h * 0.5
	var cx := w * 0.5
	var half := cx - 1.0
	var frac := clampf(float(window_blocks) / float(window_max), 0.0, 1.0)
	# upper chamber sand, shrinking toward the neck
	if frac > 0.01:
		var ys := mid - (mid - 3.0) * frac
		var hw := half * (mid - ys) / (mid - 1.0)
		hourglass_icon.draw_colored_polygon(PackedVector2Array([
			Vector2(cx - hw, ys), Vector2(cx + hw, ys), Vector2(cx, mid)]), HOURGLASS_COLOR)
	# lower chamber pile
	if frac < 0.99:
		var yb := (h - 1.0) - (mid - 3.0) * (1.0 - frac)
		var hb := half * (yb - mid) / (mid - 1.0)
		hourglass_icon.draw_colored_polygon(PackedVector2Array([
			Vector2(1.0, h - 1.0), Vector2(w - 1.0, h - 1.0),
			Vector2(cx + hb, yb), Vector2(cx - hb, yb)]), HOURGLASS_COLOR)
	var outline := PackedVector2Array([
		Vector2(1, 1), Vector2(w - 1, 1), Vector2(cx + 1.5, mid), Vector2(w - 1, h - 1),
		Vector2(1, h - 1), Vector2(cx - 1.5, mid), Vector2(1, 1)])
	hourglass_icon.draw_polyline(outline, HOURGLASS_COLOR, 1.5, true)
	hourglass_icon.draw_line(Vector2(0, 0.5), Vector2(w, 0.5), HOURGLASS_COLOR, 1.0)
	hourglass_icon.draw_line(Vector2(0, h - 0.5), Vector2(w, h - 0.5), HOURGLASS_COLOR, 1.0)


# ---------------------------------------------------------------- plate

## Full-screen chapter plate ("BOARDING 1"). Emits plate_tapped when tapped.
func show_plate(title_text: String, sub_text := "", hint_text := "") -> void:
	plate_title.text = title_text
	plate_sub.text = sub_text
	plate_hint.text = hint_text  # optional sub line (no key hints: the game shows no tutorials)
	plate_hint.visible = hint_text != ""
	popup.hide()
	pause_menu.hide()
	journal_button.hide()
	plate.modulate.a = 0.0
	plate.show()
	create_tween().tween_property(plate, "modulate:a", 1.0, 0.6)
	play_sfx(&"open")


func hide_plate() -> void:
	plate.hide()
	journal_button.show()


func _on_plate_input(event: InputEvent) -> void:
	if _is_press(event):
		plate_tapped.emit()


# ---------------------------------------------------------------- audio

func play_sfx(kind: StringName) -> void:
	var p: AudioStreamPlayer = null
	match kind:
		&"open":
			p = sfx_open
		&"close":
			p = sfx_close
		&"tap":
			p = sfx_tap
	if p != null and p.stream != null and p.is_inside_tree():
		p.play()


func _start_ambience() -> void:
	var s := ambience.stream
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	if ambience_autoplay and s != null and not ambience.playing:
		ambience.play()


## Stop streams before the tree goes away (avoids a playback leak warning on quit).
func _exit_tree() -> void:
	for p in [ambience, sfx_open, sfx_close, sfx_tap]:
		(p as AudioStreamPlayer).stop()


# ---------------------------------------------------------------- screen fx

## Plays one refresh sweep. Visible only when the shader's auto_loop is off.
func refresh(duration := 0.8) -> void:
	var mat := screen.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("manual_progress", 0.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("manual_progress", v), 0.0, 1.0, duration)


## Kept for API compatibility with the phone template; desktop has no notch/safe area.
func _apply_safe_area() -> void:
	pass


func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _flush_after() -> void:
	var calls := _after.duplicate()
	_after.clear()
	for c in calls:
		(c as Callable).call()


# ---------------------------------------------------------------- debug

func _read_debug_args() -> Dictionary:
	var d := {}
	if not OS.is_debug_build():
		return d   # release exports ignore every debug arg (--jump, --shot, --screen, ...)
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.trim_prefix("--").split("=", true, 1)
		d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _debug_used:
		var keep := {}
		if d.has("nodev"):
			keep["nodev"] = "1"
		if d.has("shot") and _shot_at_ms >= 0:
			keep["shot"] = d["shot"]
			keep["shot_delay"] = str(maxf(0.05, (_shot_at_ms - Time.get_ticks_msec()) / 1000.0))
		return keep
	return d


func _debug_start(d: Dictionary) -> bool:
	if d.has("shot"):
		_schedule_shot(str(d["shot"]), float(str(d.get("shot_delay", "1.2"))))
	var known := ["jump", "tab", "popup", "flags", "callsign", "plate", "boot", "pause", "thaw_at", "thaw_choice", "thaw_freeze", "map_demo", "open_map", "map_hover",
		"exam_screen", "exam_no", "exam_o2", "exam_name", "exam_at", "exam_freeze", "choose", "die"]
	var any := false
	for k in known:
		if d.has(k):
			any = true
	if not any:
		return false
	if d.has("callsign"):
		vars["callsign"] = str(d["callsign"])
	if d.has("flags"):
		for f in str(d["flags"]).split(",", false):
			flags[f] = true
	if d.has("jump"):
		_debug_prepare(StringName(str(d["jump"])))
		goto(StringName(str(d["jump"])))
	else:
		_begin()
	if d.has("tab"):
		show_tab(tab_from_name(str(d["tab"])))
	if d.has("popup"):
		open_dossier(StringName(str(d["popup"])))
	if d.has("map_demo"):
		ensure_vessel_map()
		apply_map_demo()
	_debug_extra(d)
	if d.has("choose"):  # --choose=2 : press choice 2 on the jumped-to passage (pinned-response check)
		_pick_choice_index(int(str(d["choose"])) - 1)
	if d.has("open_map"):
		open_map()
	if d.has("map_hover") and _full_map:
		_full_map.hovered_id = str(d["map_hover"])
		_full_map.queue_redraw()
		_on_map_room_hovered(_full_map.hovered_id)
	if d.has("die"):  # --die[=MESSAGE] : generic death screen over the jumped-to passage
		show_death(DEATH_MESSAGE if str(d["die"]) == "1" else str(d["die"]).to_upper())
	if d.has("pause"):
		show_pause()
	return true


## --shot=C:/path/file.png : wait, save the rendered frame as PNG, quit. For layout checks.
func _schedule_shot(path: String, delay: float) -> void:
	if _shot_at_ms < 0:
		_shot_at_ms = Time.get_ticks_msec() + int(delay * 1000.0)
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		var err := img.save_png(path)
		print("SHOT %s -> %s (%dx%d)" % [error_string(err), path, img.get_width(), img.get_height()])
	get_tree().quit()


# ======================================================== SCENE LINKS

## Opens another chapter / Scene Writer scene / passage. Returns false if the target is unknown.
func go_target(target: String) -> bool:
	var t := target.strip_edges()
	if t.begins_with("scene:"):
		var rest := t.substr(6)
		var sid := rest.get_slice("/", 0)
		next_authored = "res://story/scenes/%s.json" % sid
		next_screen = rest.get_slice("/", 1) if rest.contains("/") else ""
		var built := "res://scenes/authored/%s.tscn" % sid
		change_scene(built if ResourceLoader.exists(built) else "res://templates/authored_scene.tscn")
		return true
	if t.begins_with("intro:"):
		next_passage = t.substr(6)
		change_scene("res://scenes/intro.tscn")
		return true
	if t.begins_with("tscn:"):
		change_scene(t.substr(5))
		return true
	var id := StringName(t.trim_prefix("passage:"))
	if passages.has(id):
		goto(id)
		return true
	push_warning("PdaScreen: unknown target '%s'" % target)
	return false


## change_scene_to_file with the story state carried over.
func change_scene(path: String) -> void:
	carry = {"flags": flags.duplicate(true), "vars": vars.duplicate(true),
		"inventory": Array(inventory), "unlocked": Array(unlocked), "o2": o2_level,
		"map": vessel_map.duplicate(true)}
	_dev_stop_chapter()
	get_tree().change_scene_to_file.call_deferred(path)


func _apply_carry() -> void:
	if carry.is_empty():
		return
	var c := carry
	carry = {}
	flags.merge(c.get("flags", {}), true)
	vars.merge(c.get("vars", {}), true)
	for it: Variant in c.get("inventory", []):
		if StringName(str(it)) not in inventory:
			inventory.append(StringName(str(it)))
	for dz: Variant in c.get("unlocked", []):
		var dn := StringName(str(dz))
		if dossiers.has(dn) and dn not in unlocked:
			unlocked.append(dn)
	set_o2(float(c.get("o2", 100.0)))
	if c.get("map", {}) is Dictionary and not (c.get("map", {}) as Dictionary).is_empty():
		vessel_map = (c["map"] as Dictionary).duplicate(true)
		_refresh_maps()


# ======================================================== DEATH SCREEN

func _setup_death() -> void:
	death_screen = Control.new()
	death_screen.name = "DeathScreen"
	death_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var cc := CenterContainer.new()
	cc.name = "DeathCenter"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.name = "DeathBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_heading = Label.new()
	death_heading.name = "DeathHeading"
	death_heading.theme_type_variation = &"PauseTitle"
	death_heading.add_theme_color_override("font_color", DEATH_COLOR)
	death_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_message = Label.new()
	death_message.name = "DeathMessage"
	death_message.theme_type_variation = &"OsLabel"
	death_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	death_message.custom_minimum_size = Vector2(480, 0)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_retry_button = Button.new()
	death_retry_button.name = "DeathRetry"
	death_retry_button.custom_minimum_size = Vector2(220, 40)
	death_retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	death_retry_button.focus_mode = Control.FOCUS_NONE   # keys handled in _input (no double fire)
	death_retry_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	death_retry_button.pressed.connect(retry_death)
	for c in [death_heading, death_message, gap, death_retry_button]:
		box.add_child(c)
	cc.add_child(box)
	death_screen.add_child(cc)
	add_child(death_screen)
	move_child(death_screen, pause_menu.get_index())
	death_screen.hide()


## Generic death screen. Hides every other UI layer (only Screen + Backdrop stay), centres
## heading / message / RETRY. retry_target: Callable | passage id | "checkpoint" | null.
func show_death(message := DEATH_MESSAGE, retry_label := DEATH_RETRY, retry_target: Variant = null,
		heading := DEATH_HEADING) -> void:
	if death_screen.visible:
		hide_death()
	popup.hide()
	map_overlay.hide()
	plate.hide()
	_death_target = retry_target
	_death_hidden.clear()
	for c in get_children():
		if c is CanvasItem and c != screen and c != backdrop and c != death_screen and c != pause_menu:
			_death_hidden.append([c, (c as CanvasItem).visible])
			(c as CanvasItem).visible = false
	death_heading.text = heading
	death_message.text = message
	death_message.visible = message != ""
	death_retry_button.text = retry_label
	death_screen.modulate.a = 0.0
	death_screen.show()
	create_tween().tween_property(death_screen, "modulate:a", 1.0, 0.8)
	refresh(1.2)
	_death_shown_ms = Time.get_ticks_msec()
	dev_push_screen("DEATH", show_death.bind(message, retry_label, retry_target, heading))
	_on_death_shown()
	died.emit(message)


func is_dead() -> bool:
	return death_screen != null and death_screen.visible


## Closes the death screen and puts the hidden layers back (no retry action).
func hide_death() -> void:
	if not death_screen.visible:
		return
	death_screen.hide()
	for e: Array in _death_hidden:
		if is_instance_valid(e[0]):
			(e[0] as CanvasItem).visible = e[1]
	_death_hidden.clear()


func retry_death() -> void:
	if not death_screen.visible or pause_menu.visible:
		return
	if Time.get_ticks_msec() - _death_shown_ms < 350:
		return   # a press that was meant for the previous screen
	play_sfx(&"tap")
	var target: Variant = _death_target
	_death_target = null
	hide_death()
	death_retried.emit()
	if target is Callable and (target as Callable).is_valid():
		(target as Callable).call()
	elif (target is String or target is StringName) and str(target) != "" and str(target) != "checkpoint":
		refill_o2(0.8)
		clear_pin()
		goto(StringName(str(target)))
	elif not _checkpoint.is_empty():
		restore_checkpoint()
	else:
		refill_o2(0.8)
		clear_pin()
		goto(current_id)


func save_checkpoint() -> void:
	_checkpoint = {"state": _capture_state(), "id": current_id}


func restore_checkpoint() -> void:
	if _checkpoint.is_empty():
		return
	_apply_state(_checkpoint["state"])
	clear_pin()
	goto(_checkpoint["id"])


# ======================================================== DEV BACK / SNAPSHOTS

func _capture_state() -> Dictionary:
	return {
		"flags": flags.duplicate(true), "vars": vars.duplicate(true),
		"inventory": inventory.duplicate(), "unlocked": unlocked.duplicate(),
		"window_blocks": window_blocks, "window_max": window_max,
		"time_blocks": time_blocks, "time_blocks_live": time_blocks_live,
		"locked_tabs": locked_tabs.duplicate(), "map": vessel_map.duplicate(true),
		# a refill in progress counts as done (screens are recorded at their start)
		"o2": 100.0 if _o2_refilling() else o2_level, "o2_danger": 0.0 if _o2_refilling() else o2_danger,
		"current_id": current_id,
		"pin_q": pinned_question, "pin_r": pinned_response,
		"extra": _snapshot_extra(),
	}


func _apply_state(st: Dictionary) -> void:
	flags = (st["flags"] as Dictionary).duplicate(true)
	vars = (st["vars"] as Dictionary).duplicate(true)
	inventory.assign(st["inventory"])
	unlocked.assign(st["unlocked"])
	window_blocks = int(st["window_blocks"])
	window_max = int(st["window_max"])
	time_blocks = int(st.get("time_blocks", TIME_BLOCK_MAX))
	time_blocks_live = bool(st.get("time_blocks_live", false))
	locked_tabs = (st["locked_tabs"] as Dictionary).duplicate()
	vessel_map = (st["map"] as Dictionary).duplicate(true)
	stop_o2_tween()
	set_o2(float(st["o2"]), float(st["o2_danger"]))
	current_id = st["current_id"]
	pinned_question = str(st["pin_q"])
	pinned_response = str(st["pin_r"])
	_update_hourglass()
	_refresh_time_bar()
	_refresh_tab_buttons()
	_refresh_maps()
	_restore_extra(st["extra"])


## Records the screen that is being entered. `reenter` must rebuild it from the snapshot
## (and call dev_push_screen again). No-op outside dev_mode.
func dev_push_screen(label: String, reenter: Callable) -> void:
	if not dev_mode:
		return
	_history.append({"label": label, "state": _capture_state(), "reenter": reenter})
	if _history.size() > DEV_HISTORY_MAX:
		_history.pop_front()


func dev_history_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for h: Dictionary in _history:
		out.append(str(h["label"]))
	return out


## Steps back one screen: stop everything, restore the previous snapshot, replay that screen.
func dev_back() -> bool:
	if not dev_mode or _history.size() < 2:
		return false
	_history.pop_back()
	var rec: Dictionary = _history.pop_back()
	print("DEV BACK -> %s" % rec["label"])
	hide_death()
	_death_target = null
	popup.hide()
	map_overlay.hide()
	plate.hide()
	stop_o2_tween()
	_toast_token += 1
	_dev_stop_chapter()
	_apply_state(rec["state"])
	(rec["reenter"] as Callable).call()
	return true


func _dev_reenter_passage(id: StringName) -> void:
	_pin_keep = pinned_response != ""
	goto(id)


## Wheel UP = dev back, unless the pointer is over text that can still scroll up.
func _dev_wheel(mb: InputEventMouseButton) -> void:
	if not dev_mode or not mb.pressed or mb.button_index != MOUSE_BUTTON_WHEEL_UP:
		return
	if pause_menu.visible or _wheel_can_scroll_up(get_viewport().gui_get_hovered_control()):
		return
	var now := Time.get_ticks_msec()
	if now - _dev_back_ms < 300:   # one step per wheel flick (trackpads send bursts)
		_handled()
		return
	_dev_back_ms = now
	if dev_back():
		_handled()


func _wheel_can_scroll_up(c: Node) -> bool:
	while c != null:
		if c is ScrollContainer and (c as ScrollContainer).get_v_scroll_bar().value > 0.5:
			return true
		if c is RichTextLabel and (c as RichTextLabel).scroll_active \
				and (c as RichTextLabel).get_v_scroll_bar().value > 0.5:
			return true
		c = c.get_parent()
	return false


# ======================================================== PC CONTROLS

func _ensure_input_map() -> void:
	var defs := {
		"open_map": [KEY_M],
		"choice_1": [KEY_1, KEY_KP_1],
		"choice_2": [KEY_2, KEY_KP_2],
		"choice_3": [KEY_3, KEY_KP_3],
		"choice_4": [KEY_4, KEY_KP_4],
		"choice_5": [KEY_5, KEY_KP_5],
		"choice_6": [KEY_6, KEY_KP_6],
		"choice_7": [KEY_7, KEY_KP_7],
		"choice_8": [KEY_8, KEY_KP_8],
		"choice_9": [KEY_9, KEY_KP_9],
		"tab_next": [KEY_E, KEY_TAB],
		"tab_prev": [KEY_Q],
		"toggle_fullscreen": [KEY_F11],
		"advance": [KEY_SPACE, KEY_ENTER],
		"pause_menu": [KEY_ESCAPE],
	}
	for action in defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for kc in defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = kc
			if not _action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
	# Alt+Enter fullscreen
	if InputMap.has_action("toggle_fullscreen"):
		var alt_enter := InputEventKey.new()
		alt_enter.physical_keycode = KEY_ENTER
		alt_enter.alt_pressed = true
		if not _action_has_event("toggle_fullscreen", alt_enter):
			InputMap.action_add_event("toggle_fullscreen", alt_enter)
	# Shift+Tab prev
	var shift_tab := InputEventKey.new()
	shift_tab.physical_keycode = KEY_TAB
	shift_tab.shift_pressed = true
	if not _action_has_event("tab_prev", shift_tab):
		InputMap.action_add_event("tab_prev", shift_tab)


func _action_has_event(action: String, ev: InputEventKey) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey:
			var k := existing as InputEventKey
			if k.physical_keycode == ev.physical_keycode and k.alt_pressed == ev.alt_pressed and k.shift_pressed == ev.shift_pressed:
				return true
	return false


## Keyboard layer. Uses _input (not _unhandled_input) so Tab cycles PDA tabs instead of
## moving GUI focus. Chapters that override _input must call super(event).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_dev_wheel(event as InputEventMouseButton)
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("toggle_fullscreen"):
		toggle_fullscreen()
		_handled()
		return
	# Typing into a LineEdit (exam name) keeps every other key (1-9, M, Space, Enter...);
	# only Esc still opens the pause menu.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit and focus.is_visible_in_tree():
		if event.is_action_pressed("pause_menu") and not pause_menu.visible:
			focus.release_focus()
			_handle_escape()
			_handled()
		return
	if event.is_action_pressed("pause_menu"):
		_handle_escape()
		_handled()
		return
	if pause_menu.visible:
		return
	if death_screen.visible:
		if event.is_action_pressed("advance") or event.is_action_pressed("choice_1"):
			retry_death()
		_handled()
		return
	if event.is_action_pressed("advance"):
		if plate.visible:
			plate_tapped.emit()
			_handled()
			return
		if _on_advance():
			_handled()
			return
	if not popup.visible and not plate.visible and _overlay_input(event):
		_handled()
		return
	if event.is_action_pressed("open_map"):
		if map_overlay.visible:
			close_map()
		elif safe_area.is_visible_in_tree() and not plate.visible:
			open_map()
		_handled()
		return
	if popup.visible or plate.visible or map_overlay.visible or not safe_area.is_visible_in_tree():
		return
	if event.is_action_pressed("tab_prev"):  # before tab_next: Shift+Tab also matches Tab
		_cycle_tab(-1)
		_handled()
		return
	if event.is_action_pressed("tab_next"):
		_cycle_tab(1)
		_handled()
		return
	for i in range(1, 10):
		if event.is_action_pressed("choice_%d" % i):
			_pick_choice_index(i - 1)
			_handled()
			return
	# First arrow press with nothing focused: focus the first choice (or the active tab).
	if focus == null and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")
			or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		if current_tab == Tab.LOG and not _choice_buttons.is_empty():
			_choice_buttons[0].grab_focus()
		else:
			tab_buttons[current_tab].grab_focus()
		_handled()


func _handled() -> void:
	get_viewport().set_input_as_handled()


## Space/Enter when no plate is up. Chapters return true if they used it (e.g. thaw VO skip).
func _on_advance() -> bool:
	return false


## Keys for a chapter's full-screen overlay (e.g. thaw YES/NO). Return true if used.
func _overlay_input(_event: InputEvent) -> bool:
	return false


## Called when the pause menu opens/closes (chapters pause their own audio/timers).
func _on_pause_changed(_paused: bool) -> void:
	pass


func _handle_escape() -> void:
	if map_overlay.visible and not map_locked_open:
		close_map()
	elif popup.visible:
		close_popup()
	elif pause_menu.visible:
		hide_pause()
	elif plate.visible:
		pass  # Esc does not dismiss plate; Space/click does
	else:
		show_pause()


func show_pause() -> void:
	if plate.visible:
		return
	if map_overlay.visible:
		close_map()
	pause_menu.show()
	_update_fullscreen_label()
	resume_button.grab_focus()
	_on_pause_changed(true)


func hide_pause() -> void:
	if not pause_menu.visible:
		return
	pause_menu.hide()
	_on_pause_changed(false)


func toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_fullscreen_label()


func _update_fullscreen_label() -> void:
	var mode := DisplayServer.window_get_mode()
	var fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	fullscreen_button.text = "Windowed" if fs else "Fullscreen"


func _cycle_tab(dir: int) -> void:
	var start := current_tab
	for _i in TAB_NAMES.size():
		var next := (start + dir) % TAB_NAMES.size()
		if next < 0:
			next += TAB_NAMES.size()
		if not locked_tabs.has(next):
			show_tab(next, true)
			return
		start = next


func _pick_choice_index(i: int) -> void:
	if current_tab != Tab.LOG:
		return
	if i < 0 or i >= _choice_buttons.size():
		return
	var b := _choice_buttons[i]
	if is_instance_valid(b) and not b.disabled:
		b.emit_signal("pressed")


## Pointing-hand cursor + underline while the mouse is over a dossier link.
func _on_meta_hover(_meta: Variant, rtl: RichTextLabel, on: bool) -> void:
	rtl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	rtl.meta_underlined = on
	_link_hovering = on
