extends "res://templates/pda_screen.gd"
## INTRO: stasis thaw VO → MEMORY EXAMINATION (memorytest VO) → home ship tutorial.
## Home is for literacy; the wreck is for prices. Nothing here costs time.
##
## Beats: thaw (shipwelcome VO + YES/NO) > exam (name, NO loop, O2 death) > home_bunk > home_lock >
## home_airlock > BOARDING 1 plate.
##
## ALL PROSE AND DOSSIER FACTS BELOW ARE DRAFT PLACEHOLDER WRITING.
## Thaw VO on-screen text matches David’s script (typo "unlinkely" → "unlikely").

# ---- placeholder names: swap here ----
const WRECK_NAME := "SS Orison"
const HOME_SHIP := "Moth"
const COMPANION := "COMMS"
const COMPANY_NAME := "CLAIMSIDE SALVAGE UNDERWRITERS"
const DEFAULT_CALLSIGN := "OPERATOR"   # after the exam everyone calls you OPERATOR
const WINDOW_BLOCKS := 12

const SPACE_TEX := preload("res://assets/space.png")
const AMBIENT_DUCK_DB := -8.0

const ERROR_COLOR := "#e07040"
const ERROR_SCRAMBLE := "#%&@!?/\\|<>*$01"
const DIM_COLOR := "#5f8f69"
const ECHO_COLOR := "#cfe8d4"
const TYPE_FRACTION := 0.85   # a fragment finishes typing at 85% of its spoken span
const GLITCH_SECONDS := 0.35  # ERROR scrambles this long as it is typed, then settles
const EXAM_HEADER := "STASIS THAW // MEMORY EXAMINATION"

## ---- THAW VO CUES (edit by hand) ----------------------------------------------
## [start_seconds, "text", end_seconds]. Text starting with "+" continues the previous
## paragraph (joined with a space); anything else starts a new paragraph.
## Measured 2026-09-28 from the WAVs: start = ffmpeg silencedetect silence_end
## (noise=-35dB, d=0.25), end = next silence_start; fragment/sentence mapping checked
## against faster-whisper base.en word timestamps. On-screen text follows David's script
## (the VO says "and FOR error standard months"; the script/screen says "and ERROR").
const THAW_CUES_MAIN: Array = [
	[0.00, "Hello, OPERATOR.", 1.04],
	[1.82, "The REC-7 corporation is pleased to inform you", 5.09],
	[5.54, "+that you have successfully survived stasis for", 8.25],
	[8.79, "+ERROR standard years and", 10.70],
	[11.30, "+ERROR standard months.", 13.22],
	[13.89, "The current date is ERROR.", 15.99],
	[16.79, "It is likely you are experiencing disorientation and memory loss.", 20.84],
	[21.37, "+Please observe the device attached to your left arm.", 24.40],
	[25.43, "+This is your Task and Record Module,", 28.12],
	[28.60, "+also dubbed", 29.37],
	[29.79, "+\"TRM-CUFF.\"", 30.37],
	[31.11, "Are you observing the TRM-CUFF now?", 33.33],
]
const THAW_CUES_YES: Array = [
	[0.69, "Good,", 1.04],
	[1.52, "+then we will proceed with stasis thaw memory protocols.", 5.18],
]
const THAW_CUES_NO: Array = [
	[0.54, "This is unlikely,", 1.44],
	[1.72, "+as you selected \"NO\" on your TRM-CUFF.", 4.12],
	[4.73, "+If you had not been observing it,", 6.22],
	[6.50, "+you would have been incapable of selecting this response.", 9.67],
	[10.16, "+We will now proceed with stasis thaw and memory protocols.", 13.40],
]

enum ThawPhase { IDLE, MAIN, CHOICES, REPLY, DONE,
	EXAM_VO, EXAM_WAIT, EXAM_NAME, EXAM_CHOICES, EXAM_DEATH, EXAM_DEAD, EXAM_BLACK }

@onready var thaw: Control = %Thaw
@onready var thaw_status: Label = %ThawStatus
@onready var thaw_scroll: ScrollContainer = %ThawScroll
@onready var thaw_text: RichTextLabel = %ThawText
@onready var thaw_choices: VBoxContainer = %ThawChoices
@onready var exam_continue: Button = %ExamContinue
@onready var exam_name_box: VBoxContainer = %ExamNameBox
@onready var exam_name_edit: LineEdit = %ExamNameEdit
@onready var exam_name_confirm: Button = %ExamNameConfirm
@onready var thaw_pin: RichTextLabel = %ThawPin
@onready var thaw_choices_header: Label = %ThawChoicesHeader
@onready var exam_name_hint: Label = %ExamNameHint
@onready var exam_fx: ColorRect = %ExamVignette
@onready var voice_exam: AudioStreamPlayer = %VoiceExam
@onready var voice_main: AudioStreamPlayer = %VoiceMain
@onready var voice_yes: AudioStreamPlayer = %VoiceYes
@onready var voice_no: AudioStreamPlayer = %VoiceNo

var _thaw_phase: int = ThawPhase.IDLE
var _thaw_cues: Array = []            # cues of the section now playing
var _thaw_voice: AudioStreamPlayer = null
var _thaw_t := 0.0                    # section clock (seconds into the current WAV)
var _thaw_len := 0.0                  # section length (WAV length)
var _thaw_forced := -1                # fragments <= this index are shown complete
var _thaw_skip_until := 0.0           # real-time window in which a press skips
var _thaw_hold := 0.0
var _thaw_beat := -1.0                # countdown after a reply ends
var _thaw_wall := 0.0                 # real-time clock for the settled ERROR flicker
var _thaw_main_done_bb := ""          # main text (bbcode) kept above a reply
var _thaw_echo := ""                  # "> YES" / "> NO"
var _thaw_last_bb := ""
var _thaw_choice_btns: Array[Button] = []
var _thaw_seek_at := -1.0
var _thaw_force_choice := ""
var _thaw_freeze := false            # --thaw_freeze: hold the clock at --thaw_at (screenshots)

# ---- memory examination state ----
var _exam_streams: Dictionary = {}    # key -> AudioStream
var _exam_after: Callable             # runs when the current exam VO section ends
var _exam_events: Array = []          # [[time, Callable, fired], ...] inside a section
var _exam_name := ""                  # what the player typed
var _exam_no := 0                     # NO answers in the current loop
var _exam_o2_t := 0.0                 # seconds into the oxygen countdown
var _exam_o2_frozen := -1.0           # --exam_o2=S freezes the countdown at S
var _exam_fx_amount := 0.0
var _exam_fx_target := 0.0
var _exam_fx_black := 0.0
var _exam_beat_t := 0.0
var _exam_heart: AudioStreamPlayer
var _exam_door: AudioStreamPlayer     # airlockdoor.mp3 / dooropen.mp3 (David's existing SFX)
var _exam_lowpass_idx := -1
var _exam_dbg: Dictionary = {}


var _thaw_ambience_base_db := 0.0
var _exam_prefix_bb := ""             # finished clips of a multi-clip screen (kept above)
var _exam_last_skipped := false       # the section that just ended was skipped
var _exam_pick_fn: Callable           # Q2 / know-more / Q3 choice handler (index); Q1 uses _exam_answer
var _exam_video: VideoStreamPlayer    # KNOW_MORE_VIDEO hook
var _exam_black: ColorRect            # final fade to black (whole game)
var _exam_black_tween: Tween
var _exam_icon_row: HBoxContainer      # example icons (Q3 examples screens)
var _exam_icon_boxes: Array[Panel] = []
var _exam_icon_times: Array = []
var _exam_icon_shown: Array = []
var _exam_icons_final := false
var _exam_icon_sfx: AudioStreamPlayer
var _exam_icon_measure: RichTextLabel   # hidden copy of thaw_text: finished-text height
var _exam_icon_ids: Array = []
## Example icon art lookup (defaults from MemoryExam; a runtime / test override is possible).
var icon_art: Dictionary = MemoryExam.ICON_ART.duplicate()
var icon_art_dir: String = MemoryExam.ICON_ART_DIR
var _exam_icon_layout_key := ""
var _exam_icon_final_text_h := 0.0
var _exam_icon_sfx_count := 0
var know_more_video := MemoryExam.KNOW_MORE_VIDEO   # hooks (tests may override)
var after_exam_target := MemoryExam.AFTER_EXAM
var after_exam_dry_run := false         # tests: record the AFTER_EXAM target instead of leaving
var exam_left_to := ""
var _exam_card: Label                   # "ONE HOUR LATER" time card on the black
var _exam_card_t0 := 0


func _setup_story() -> void:
	move_child(thaw, safe_area.get_index() + 1)
	thaw.hide()
	thaw.gui_input.connect(_on_thaw_gui_input)
	thaw_choices.hide()
	_exam_setup()
	# Prefer theme mono for OS-voice body.
	var mono: Font = thaw_status.get_theme_font("font", "OsLabel")
	if mono:
		thaw_text.add_theme_font_override("normal_font", mono)
		thaw_text.add_theme_font_override("bold_font", mono)

	_thaw_ambience_base_db = ambience.volume_db

	var dbg := _read_debug_args()
	if dbg.has("thaw_at"):
		_thaw_seek_at = float(str(dbg["thaw_at"]))
	if dbg.has("thaw_choice"):
		_thaw_force_choice = str(dbg["thaw_choice"]).to_lower()
	_thaw_freeze = dbg.has("thaw_freeze") or dbg.has("exam_freeze")
	_exam_dbg = dbg

	vars["callsign"] = DEFAULT_CALLSIGN
	vars["wreck"] = WRECK_NAME
	vars["tug"] = HOME_SHIP
	set_tab_locked(Tab.DECK, true)
	start_passage = &"thaw"
	ensure_vessel_map()  # REC-7 vessel schematic (data/vessel.gd); you wake in STASIS-15
	_setup_intro_hud()   # read-only minimap + O2 bar on the THAW / EXAM overlay

	dossiers = {
		&"orison": {
			"title": "{v:wreck}",
			"filed": "CLAIMS BRIEF // CLAIMSIDE",
			"body": "[b]Class:[/b] bulk hauler\n"
				+ "[b]Tonnage:[/b] 38,400 t\n"
				+ "[b]Last ping:[/b] 211 days ago, transponder only\n"
				+ "[b]Distress:[/b] none logged\n\n"
				+ "No distress. No crew response to hail. Claim is open to the operator "
				+ "of record, split per contract.",
		},
		&"worklamp": {
			"title": "Worklamp",
			"filed": "ISSUED // 1 CELL",
			"body": "Company issue, scuffed at the grip. One cell, charged.\n\n"
				+ "There is no second cell. Dark rooms take longer without it.",
		},
	}
	items = {
		&"worklamp": {"label": "Worklamp", "desc": "issued, 1 cell", "dossier": "worklamp"},
	}
	deck = {
		"aspect": "HOME",
		"os_line": "ASPECT: HOME / TWO COMPARTMENTS MAPPED",
		"rooms": [
			{"id": "home_bunk", "label": "BUNK", "pos": Vector2(0.5, 0.16)},
			{"id": "home_lock", "label": "LOCK", "pos": Vector2(0.5, 0.48)},
			{"id": "home_airlock", "label": "AIRLOCK", "pos": Vector2(0.5, 0.8)},
		],
		"links": [["home_bunk", "home_lock"], ["home_lock", "home_airlock"]],
	}
	passages = {
		&"thaw": {
			"title": "STASIS THAW",
			"os_line": "OPERATOR: UNASSIGNED",
			"map_room": "stasis_15",
			"no_history": true,   # the THAW overlay records its own screens
			"on_enter": ["thaw_start"],
		},
		&"exam": {
			"title": "MEMORY EXAMINATION",
			"os_line": "OPERATOR: UNASSIGNED",
			"map_room": "stasis_15",
			"no_history": true,
			"on_enter": ["exam_start"],
		},
		&"home_bunk": {
			"title": "BUNK",
			"os_line": "{v:callsign} // ASPECT: HOME",
			"map_room": "stasis_15",
			"comms": [
				"MORNING, {v:callsign}. CONTACT HOLDING.",
				"{flag:!asked_any?ASK ME NOW. IT GETS BUSY LATER.|}",
				"{flag:asked_split?SIXTY-FORTY. THE COMPANY TAKES THE SIXTY.|}",
				"{flag:asked_quiet?NO BEACON. NO CHATTER. JUST MASS ON THE SCOPE.|}",
			],
			"body": "You wake with your knees against the bulkhead and the heater ticking. "
				+ "The {v:tug} smells of coffee left on too long.\n\n"
				+ "The scope over the fold-down table shows one contact. It has not moved all night.\n\n"
				+ "The tag beside it reads [[orison|{v:wreck}]]. No lights. No voice. "
				+ "Just a name the claims office wants back.",
			"choices": [
				{"label": "Ask about the salvage split", "ops": ["set_flag:asked_split", "set_flag:asked_any"], "if": "!asked_any"},
				{"label": "Ask about the quiet contact", "ops": ["set_flag:asked_quiet", "set_flag:asked_any"], "if": "!asked_any"},
				{"label": "Finish the coffee. Go down to the lock.", "goto": "home_lock", "if": "asked_any"},
			],
		},
		&"home_lock": {
			"title": "LOCKER ROOM",
			"os_line": "{v:callsign} // ASPECT: HOME",
			"body": "The lock is three steps wide. Suit lockers on one side, a steel counter on the other, "
				+ "the airlock hatch at the far end.\n\n"
				+ "{flag:asked_split?The clerk's note is still taped to the counter, the percentages circled twice.|}"
				+ "{flag:asked_quiet?Someone has written on the counter in marker, small and careful: no beacon.|}\n\n"
				+ "{flag:has_worklamp?The hook by the suit rack is empty. Your [[worklamp|worklamp]] is clipped to your chest.|"
				+ "Your [[worklamp|worklamp]] hangs on its hook by the suit rack.}",
			"choices": [
				{"label": "Take the lamp", "ops": ["give_item:worklamp", "clear_flag:left_lamp", "set_flag:lamp_decided", "unlock_tab:deck", "open_tab_once:deck"], "if": "!has_worklamp"},
				{"label": "Leave it on the hook", "ops": ["set_flag:left_lamp", "set_flag:lamp_decided", "unlock_tab:deck", "open_tab_once:deck"], "if": "!has_worklamp,!left_lamp"},
				{"label": "Walk to the airlock", "ops": ["open_tab:deck"], "if": "lamp_decided"},
			],
		},
		&"home_airlock": {
			"title": "AIRLOCK",
			"os_line": "SALVAGE WINDOW ARMED  //  {v:blocks} BLOCKS",
			"on_enter": ["arm_window:%d" % WINDOW_BLOCKS],
			"body": "The inner hatch seals behind you. Through the port, the [[orison|{v:wreck}]] fills the glass "
				+ "edge to edge, close enough to see where the paint gave up.\n\n"
				+ "Once you cycle the lock, you will not be back aboard the {v:tug} until the window closes "
				+ "or you call the tug.",
			"choices": [
				{"label": "Cycle the lock and board", "time_cost": 0,
					"ops": ["arm_window:%d" % WINDOW_BLOCKS, "set_flag:boarded", "plate:BOARDING 1|{v:wreck}  //  WINDOW {v:blocks}"]},
				{"label": "Check KIT again", "ops": ["open_tab:kit"]},
				{"label": "Read the claims brief again", "ops": ["open_dossier:orison"]},
			],
		},
	}


func _custom_op(op_name: String, _arg: String) -> bool:
	if op_name == "thaw_start":
		_thaw_begin_main()
		return true
	if op_name == "exam_start":
		_exam_debug_entry()
		return true
	return false


func _on_passage_entered(id: StringName) -> void:
	if id == &"home_airlock":
		set_backdrop(SPACE_TEX, 0.14)
	elif id != &"thaw" and id != &"exam":
		set_backdrop(null)


# ======================================================== THAW / VO
## First screen: REC-7 stasis-thaw VO with synced typewriter text, YES/NO, reply,
## then the MEMORY EXAMINATION (below). Text is a pure function of the section clock,
## which follows the voice player's playback position (own clock if audio is silent).

func _thaw_overlay_open() -> void:
	safe_area.hide()
	journal_button.hide()
	set_backdrop(SPACE_TEX, 0.12)
	thaw_status.text = "REC-7 // STASIS THAW"
	thaw_scroll.show()
	thaw_choices.hide()
	_exam_hide_widgets()
	thaw.show()


func _thaw_begin_main() -> void:
	_thaw_overlay_open()
	_thaw_main_done_bb = ""
	_thaw_echo = ""
	dev_push_screen("THAW", _thaw_begin_main)
	if _thaw_force_choice != "":
		# --thaw_choice: jump straight to a reply (main text shown complete).
		_thaw_start_section(THAW_CUES_MAIN, voice_main, ThawPhase.MAIN, -1.0, false)
		_thaw_end_main()
		_thaw_pick(_thaw_force_choice != "no", maxf(_thaw_seek_at, 0.0))
		return
	_thaw_start_section(THAW_CUES_MAIN, voice_main, ThawPhase.MAIN, maxf(_thaw_seek_at, 0.0), true)


func _thaw_start_section(cues: Array, voice: AudioStreamPlayer, phase: int, from: float, play: bool, len_override := -1.0) -> void:
	_thaw_cues = cues
	_thaw_voice = voice
	_thaw_phase = phase
	if len_override > 0.0:
		_thaw_len = len_override
	else:
		_thaw_len = voice.stream.get_length() if voice and voice.stream else _cue_end(cues.size() - 1) + 0.5
	_thaw_t = maxf(from, 0.0)
	_thaw_forced = -1
	_thaw_skip_until = 0.0
	_thaw_hold = 0.0
	_thaw_beat = -1.0
	if play and voice and _thaw_t < _thaw_len - 0.02:
		_duck_ambience(true)
		voice.stream_paused = false
		voice.play(clampf(_thaw_t, 0.0, maxf(_thaw_len - 0.05, 0.0)))
		_thaw_log("play %s from %.2f" % [voice.name, _thaw_t])
	_thaw_render()
	# Seek past the end (or freeze at the end) → finish the section so choices / next screen appear.
	if _thaw_t >= _thaw_len - 0.02:
		if phase == ThawPhase.MAIN:
			_thaw_end_main()
		elif phase == ThawPhase.REPLY:
			_thaw_end_reply(true)
		elif phase == ThawPhase.EXAM_VO:
			_exam_section_done(true)


func _cue_start(i: int) -> float:
	return float(_thaw_cues[i][0])


func _cue_end(i: int) -> float:
	var c: Array = _thaw_cues[i]
	if c.size() > 2:
		return float(c[2])
	if i + 1 < _thaw_cues.size():
		return float(_thaw_cues[i + 1][0]) - 0.2
	return float(c[0]) + 2.0


func _cue_text(i: int) -> String:
	return str(_thaw_cues[i][1]).trim_prefix("+")


## 0..1 typed fraction of fragment i at the current clock.
func _cue_fraction(i: int) -> float:
	if i <= _thaw_forced:
		return 1.0
	var st := _cue_start(i)
	if _thaw_t < st:
		return 0.0
	var span := maxf(0.15, (_cue_end(i) - st) * TYPE_FRACTION)
	return clampf((_thaw_t - st) / span, 0.0, 1.0)


## Index of the fragment currently mid-type, or -1.
func _thaw_typing_index() -> int:
	for i in _thaw_cues.size():
		var f := _cue_fraction(i)
		if f > 0.0 and f < 1.0:
			return i
	return -1


func _process(delta: float) -> void:
	_thaw_wall += delta
	if _thaw_phase == ThawPhase.IDLE or _thaw_phase == ThawPhase.DONE:
		return
	if pause_menu.visible:
		return  # clock frozen; voice is stream_paused (see show_pause)
	if _thaw_phase == ThawPhase.EXAM_BLACK:
		return
	_exam_fx_tick(delta)
	if _thaw_phase == ThawPhase.EXAM_DEATH:
		_exam_death_tick(delta)
		_thaw_render()
		return
	if _thaw_phase in [ThawPhase.CHOICES, ThawPhase.EXAM_WAIT, ThawPhase.EXAM_NAME,
			ThawPhase.EXAM_CHOICES, ThawPhase.EXAM_DEAD]:
		_thaw_render()  # keeps the settled ERROR flicker / name glitch alive
		return

	if _thaw_freeze:
		if _thaw_phase == ThawPhase.EXAM_VO:
			_exam_fire_events()   # frozen debug shots still get door locks / fx cues up to t
		_thaw_render()
		return
	# Section clock follows the audio when it is really playing.
	if _thaw_voice and _thaw_voice.playing and not _thaw_voice.stream_paused:
		var pos := _thaw_voice.get_playback_position() + AudioServer.get_time_since_last_mix()
		_thaw_t = pos if pos > 0.01 else _thaw_t + delta
	else:
		_thaw_t += delta

	# Hold Space/Enter to skip the rest of the section.
	if Input.is_action_pressed("advance") and get_viewport().gui_get_focus_owner() == null:
		_thaw_hold += delta
		if _thaw_hold > 0.6:
			_thaw_hold = 0.0
			_thaw_skip_section()
			return
	else:
		_thaw_hold = 0.0

	if _thaw_beat >= 0.0:
		_thaw_beat -= delta
		if _thaw_beat < 0.0:
			_exam_begin()
		return

	_exam_fire_events()
	if _thaw_t >= _thaw_len:
		if _thaw_phase == ThawPhase.MAIN:
			_thaw_end_main()
		elif _thaw_phase == ThawPhase.REPLY:
			_thaw_end_reply(false)
		elif _thaw_phase == ThawPhase.EXAM_VO:
			_exam_section_done(false)
		return
	_thaw_render()


## Builds the bbcode for the current section and pushes it only when it changed.
func _thaw_render() -> void:
	_exam_icons_update()
	var bb := _thaw_body_bb()
	if _exam_heading != "":
		bb = "[font=res://assets/fonts/Oxanium-SemiBold.ttf][font_size=20][color=%s]%s[/color][/font_size][/font]\n\n%s" \
			% [ECHO_COLOR, _escape_bb(_exam_heading), bb]
	# UI rule: question + response pinned above the new text (own label, never scrolls away)
	var pin := _thaw_pin_bb()
	if pin != _thaw_last_pin:
		_thaw_last_pin = pin
		thaw_pin.text = pin
		thaw_pin.visible = pin != ""
	if _thaw_phase == ThawPhase.EXAM_DEATH or (_exam_fx_amount > 0.05 and _thaw_phase != ThawPhase.EXAM_DEAD):
		bb = "[shake rate=18.0 level=%d connected=1]%s[/shake]" % [int(2 + _exam_fx_amount * 9.0), bb]
	if bb == _thaw_last_bb:
		return
	_thaw_last_bb = bb
	thaw_text.text = bb
	thaw_scroll.set_deferred("scroll_vertical", 100000)


## Body text of the screen: finished earlier clips (_exam_prefix_bb) + the section now typing.
func _thaw_body_bb() -> String:
	var paras: PackedStringArray = PackedStringArray()
	var first_cont := false
	for i in _thaw_cues.size():
		var f := _cue_fraction(i)
		if f <= 0.0:
			continue
		var frag := _fragment_bb(i, f)
		var cont := str(_thaw_cues[i][1]).begins_with("+")
		if cont and not paras.is_empty():
			paras[paras.size() - 1] += " " + frag
		else:
			if paras.is_empty():
				first_cont = cont
			paras.append(frag)
	var bb := "\n\n".join(paras)
	if _exam_prefix_bb == "":
		return bb
	if bb == "":
		return _exam_prefix_bb
	return _exam_prefix_bb + (" " if first_cont else "\n\n") + bb


## Fragment i typed to fraction f, ERROR words glitched while typing and settled after.
func _fragment_bb(i: int, f: float) -> String:
	var text := _cue_text(i)
	var n := int(ceil(text.length() * f)) if f < 1.0 else text.length()
	var out := ""
	var k := 0
	var st := _cue_start(i)
	var span := maxf(0.15, (_cue_end(i) - st) * TYPE_FRACTION)
	while k < n:
		var e := text.find("ERROR", k)
		if e < 0 or e >= n:
			out += _escape_bb(text.substr(k, n - k))
			break
		out += _escape_bb(text.substr(k, e - k))
		# time this ERROR began typing, used for the scramble window
		var t_e := st + span * float(e) / float(maxi(text.length(), 1))
		var shown := mini(5, n - e)
		var glitch := i > _thaw_forced and (_thaw_t - t_e) < GLITCH_SECONDS
		var word := ""
		if glitch or shown < 5:
			for _c in shown:
				word += ERROR_SCRAMBLE[randi() % ERROR_SCRAMBLE.length()]
		else:
			word = "ERROR"
			# subtle settled flicker: one character, ~70 ms, every ~5 s, staggered per word
			if fmod(_thaw_wall + float(i) * 1.7 + float(e) * 0.3, 5.3) < 0.07:
				var at := int(fmod(float(i + e), 5.0))
				word = word.substr(0, at) + ERROR_SCRAMBLE[randi() % ERROR_SCRAMBLE.length()] + word.substr(at + 1)
		out += "[color=%s][b]%s[/b][/color]" % [ERROR_COLOR, _escape_bb(word)]
		k = e + shown
	return out


func _escape_bb(t: String) -> String:
	return t.replace("[", "[lb]")


# ---------------------------------------------------------------- section ends

func _thaw_stop_voice(reason: String) -> void:
	for p: AudioStreamPlayer in [voice_main, voice_yes, voice_no, voice_exam]:
		if p and (p.playing or p.stream_paused):
			_thaw_log("stop %s at %.2f (%s)" % [p.name, p.get_playback_position(), reason])
			p.stop()
		if p:
			p.stream_paused = false
	_duck_ambience(false)


func _thaw_end_main() -> void:
	if _thaw_phase != ThawPhase.MAIN:
		return
	_thaw_stop_voice("main end")
	_thaw_forced = _thaw_cues.size() - 1
	_thaw_t = maxf(_thaw_t, _thaw_len)
	_thaw_phase = ThawPhase.CHOICES
	_thaw_render()
	_thaw_show_choices()


func _thaw_end_reply(skipped: bool) -> void:
	if _thaw_phase != ThawPhase.REPLY:
		return
	_thaw_stop_voice("reply skip" if skipped else "reply end")
	_thaw_forced = _thaw_cues.size() - 1
	_thaw_render()
	_exam_wait(_exam_begin)   # reply screen ends on CONTINUE like every exam screen


func _thaw_skip_section() -> void:
	if _thaw_phase == ThawPhase.MAIN:
		_thaw_end_main()
	elif _thaw_phase == ThawPhase.REPLY:
		_thaw_end_reply(true)
	elif _thaw_phase == ThawPhase.EXAM_VO:
		_exam_section_done(true)


# ---------------------------------------------------------------- YES / NO

func _thaw_show_choices() -> void:
	for c in _thaw_choice_btns:
		c.queue_free()
	_thaw_choice_btns.clear()
	thaw_choices_header.text = MemoryExam.RESPONSE_HEADER
	_add_thaw_choice(1, "YES", true)
	_add_thaw_choice(2, "NO", false)
	thaw_choices.show()
	_thaw_log("choices shown")


func _add_thaw_choice(n: int, label: String, yes: bool) -> void:
	var b := Button.new()
	b.theme_type_variation = &"ChoiceButton"
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(220, 34)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(_on_thaw_choice.bind(yes))
	thaw_choices.add_child(b)
	_thaw_choice_btns.append(b)


func _on_thaw_choice(yes: bool) -> void:
	_thaw_pick(yes, 0.0)


func _thaw_pick(yes: bool, from: float) -> void:
	if _thaw_phase != ThawPhase.CHOICES:
		return  # guards double clicks / key + click in the same frame
	play_sfx(&"tap")
	for c in _thaw_choice_btns:
		c.disabled = true
		c.queue_free()
	_thaw_choice_btns.clear()
	thaw_choices.hide()
	flags.erase("thaw_said_yes")
	flags.erase("thaw_said_no")
	flags["thaw_said_yes" if yes else "thaw_said_no"] = true
	# UI rule: NEW screen with the question + response pinned on top, reply types below.
	_thaw_main_done_bb = _escape_bb(_cue_text(_thaw_cues.size() - 1))  # "Are you observing…?"
	_thaw_echo = "> " + ("YES" if yes else "NO")
	_thaw_last_bb = ""
	thaw_text.text = ""   # new screen: nothing of the old text survives
	_thaw_log("choice " + ("YES" if yes else "NO"))
	dev_push_screen("THAW > " + ("YES" if yes else "NO"), _thaw_reenter_reply.bind(yes))
	_thaw_start_section(THAW_CUES_YES if yes else THAW_CUES_NO, voice_yes if yes else voice_no,
		ThawPhase.REPLY, from, true)


## Dev back into a THAW reply screen.
func _thaw_reenter_reply(yes: bool) -> void:
	_thaw_overlay_open()
	_thaw_cues = THAW_CUES_MAIN
	_thaw_phase = ThawPhase.CHOICES
	_thaw_pick(yes, 0.0)


# ======================================================== MEMORY EXAMINATION
## Runs after the THAW reply (THAW reply screen ends on CONTINUE). Screens:
##   1  Welcome + assess + warning (memorytest1 0.9-19.2 s) → CONTINUE
##   2  heading "Memory Examination" + "1) Do you remember your name?" → name field
##   3  pinned "1) Do you remember your name?" / "> <name>" (name scrambles into ERROR as the
##      VO reaches "The name ERROR") + "The name ERROR is not…" → YES/NO
## Every answer opens a NEW screen with the question + response pinned (PdaScreen UI rule).
## NO1 → NO2 → NO3 (YES/NO again after each) → NO4 (red edges creep in with the VO) → QTE:
## one "NO WAIT, I UNDERSTAND" button in the choice slot, draining timer inside it, O2 bar
## ticking down in the header → recovery screen (O2 refills, red fades). Expiry → generic
## template death screen (show_death) → RETRY replays screen 3 (VO + typewriter) → YES/NO.
## YES (or the recovery) → CONTINUE → Questions 2 + 3 (see QUESTIONS 2 + 3) → fade to black.
## Every screen is recorded for the
## dev-only mouse-wheel BACK (dev_push_screen; see the template's DEV BACK notes).
## Cue text/timings live in data/memory_exam.gd (MemoryExam). All VO on the Voice bus.

var _exam_next: Callable              # what CONTINUE runs
var _exam_screen := 0
var _exam_started := false
var _exam_seek := -1.0                # --exam_at: one-shot seek into the next exam section
var _exam_question := ""              # most recent question line (pinned above answers)
var _exam_heading := ""               # heading typed above screen 2
var _exam_pin_name := false           # pinned response is the (glitching) typed name
var _exam_name_settled := false       # typed name already became ERROR (retry)
var _exam_name_el := -99.0            # seconds since the name started to scramble
var _exam_name_wall := 0.0
var _exam_err_t := 0.0                # screen-3 clock time when "ERROR" is typed/spoken
var _exam_red := 0.0                  # red edge vignette 0..1
var _exam_red_mode := ""              # "" | no4 | death | recover
var _exam_recover_p := 0.0
var _exam_recover_red0 := 0.0
var _exam_recover_o20 := 0.0
var _exam_recover_d0 := 0.0
var _exam_qte_btn: Button
var _exam_qte_fill: ColorRect
var _exam_qte_bar: ColorRect
var _exam_pulse := 0.0
var _exam_dub_t := -1.0
var _thaw_last_pin := ""
var hud_map: ShipMapView              # read-only overlay minimap (bottom-right)
var hud_map_frame: VBoxContainer
var hud_o2: O2Bar                     # overlay O2 bar (same spot as the header one)


func _exam_setup() -> void:
	var mono: Font = thaw_status.get_theme_font("font", "OsLabel")
	exam_name_edit.max_length = MemoryExam.NAME_MAX
	exam_name_edit.placeholder_text = "NAME"
	if mono:
		exam_name_edit.add_theme_font_override("font", mono)
		thaw_pin.add_theme_font_override("normal_font", mono)
		thaw_pin.add_theme_font_override("bold_font", mono)
	exam_name_edit.add_theme_font_size_override("font_size", 18)
	exam_name_edit.text_submitted.connect(_exam_submit_name)
	if "keep_editing_on_text_submit" in exam_name_edit:
		exam_name_edit.set("keep_editing_on_text_submit", true)   # a rejected Enter keeps typing
	exam_name_confirm.pressed.connect(_exam_submit_name.bind(""))
	exam_continue.pressed.connect(_exam_continue_pressed)
	# Keyboard is handled in _input/_on_advance; these buttons never take focus (no double fire).
	for b: Button in [exam_continue, exam_name_confirm]:
		b.focus_mode = Control.FOCUS_NONE
	exam_continue.text = MemoryExam.CONTINUE_LABEL
	exam_name_confirm.text = MemoryExam.SUBMIT_LABEL
	exam_name_hint.text = ""
	exam_name_hint.hide()          # only the blank-name validation message ever shows here
	exam_name_box.custom_minimum_size.x = 400.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/suffocate.gdshader")
	exam_fx.material = mat
	exam_fx.hide()
	_exam_heart = AudioStreamPlayer.new()
	_exam_heart.name = "ExamHeart"
	_exam_heart.bus = &"Sfx"
	_exam_heart.stream = sfx_tap.stream   # UI-1.mp3 pitched way down = heartbeat (no new audio)
	_exam_heart.volume_db = 3.0
	add_child(_exam_heart)
	_exam_door = AudioStreamPlayer.new()
	_exam_door.name = "ExamDoor"
	_exam_door.bus = &"Sfx"
	_exam_door.volume_db = -6.0   # sits under the VO
	add_child(_exam_door)
	_exam_hide_widgets()


## Overlay HUD: read-only minimap bottom-right (where the main screen's minimap sits) and an
## O2 bar top-right (where the header O2 bar sits). Both above the FX layer, mouse-transparent.
func _setup_intro_hud() -> void:
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
	lbl.name = "HudMapHeader"
	lbl.theme_type_variation = &"OsLabelDim"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = "%s // MAP" % str(vessel_map.get("title", Vessel.VESSEL_TITLE)).to_upper()
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
	thaw.add_child(hud_map_frame)
	register_map_view(hud_map)
	hud_o2 = O2Bar.new()
	hud_o2.name = "HudO2"
	hud_o2.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud_o2.offset_left = -264.0
	hud_o2.offset_right = -64.0
	hud_o2.offset_top = 10.0
	hud_o2.offset_bottom = 26.0
	thaw.add_child(hud_o2)
	register_o2_bar(hud_o2)


func _exam_hide_widgets() -> void:
	for c in [exam_continue, exam_name_box]:
		c.hide()


func _exam_stream(key: String) -> AudioStream:
	if _exam_streams.has(key):
		return _exam_streams[key]
	var path: String = key if key.begins_with("res://") else {
		"main": MemoryExam.STREAM_MAIN, "yes": MemoryExam.STREAM_YES,
		"no1": MemoryExam.STREAM_NO1, "no2": MemoryExam.STREAM_NO2,
		"no3": MemoryExam.STREAM_NO3, "no4": MemoryExam.STREAM_NO4,
		"recover": MemoryExam.STREAM_RECOVER,
	}.get(key, "")
	var st: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		st = load(path) as AudioStream
	_exam_streams[key] = st
	return st


## Cues for a section with no recording: typewriter at a normal reading pace.
func _exam_silent_cues(cues: Array) -> Array:
	var out: Array = []
	var t := 0.3
	for c: Array in cues:
		var txt := str(c[1])
		var dur := maxf(0.4, float(txt.length()) / MemoryExam.NO_VO_SILENT_CPS / TYPE_FRACTION)
		out.append([t, txt, t + dur])
		t += dur + 0.35
	return out


## Plays [from, to] of a memorytest WAV with its cues (to < 0 = whole file). Silent fallback
## if the WAV is missing. `after` runs when the section ends (naturally, skipped or complete).
func _exam_play(key: String, cues: Array, from: float, to: float, after: Callable,
		events: Array = [], complete := false) -> void:
	var st := _exam_stream(key)
	var voice: AudioStreamPlayer = voice_exam
	if st == null:
		cues = _exam_silent_cues(cues)
		voice = null
		from = 0.0
		to = float(cues[cues.size() - 1][2]) + 0.4
		_thaw_log("exam %s: no recording, silent typewriter" % key)
	else:
		if voice_exam.stream != st:
			voice_exam.stop()
			voice_exam.stream = st
		if to <= 0.0:
			to = st.get_length()
	_exam_after = after
	_exam_events = []
	for e: Array in events:
		_exam_events.append([float(e[0]), e[1], false])
	var at := from
	if complete:
		at = to
	elif _exam_seek >= 0.0:
		at = clampf(_exam_seek, 0.0, to)
		_exam_seek = -1.0
	_thaw_start_section(cues, voice, ThawPhase.EXAM_VO, at, true, to)


func _exam_fire_events(all := false) -> void:
	if _thaw_phase != ThawPhase.EXAM_VO and not all:
		return
	for e: Array in _exam_events:
		if not e[2] and (all or _thaw_t >= float(e[0])):
			e[2] = true
			(e[1] as Callable).call()


func _exam_section_done(skipped: bool) -> void:
	if _thaw_phase != ThawPhase.EXAM_VO:
		return
	_thaw_stop_voice("exam skip" if skipped else "exam end")
	_exam_last_skipped = skipped
	_thaw_forced = _thaw_cues.size() - 1
	_thaw_t = maxf(_thaw_t, _thaw_len)
	_exam_fire_events(true)
	for i in _thaw_cues.size():
		var txt := _cue_text(i)
		if txt.begins_with("Please indicate"):
			_exam_question = txt   # newest question line → pinned above the next answer
	_thaw_render()
	var next := _exam_after
	_exam_after = Callable()
	if next.is_valid():
		next.call()


# ---------------------------------------------------------------- flow

func _exam_open() -> void:
	safe_area.hide()
	journal_button.hide()
	set_backdrop(SPACE_TEX, 0.12)
	thaw_status.text = EXAM_HEADER
	thaw.show()
	thaw_choices.hide()
	_exam_reset_fx()


## Entry from the THAW reply screen's CONTINUE.
func _exam_begin() -> void:
	_thaw_beat = -1.0
	if _exam_started:
		return
	_exam_started = true
	_thaw_stop_voice("to exam")
	_thaw_log("memory examination")
	_exam_open()
	_exam_no = 0
	_exam_show_screen(1)


## UI rule: a fresh screen with `question` (bbcode, dim) + `response` ("> NO") pinned on top.
func _exam_page(question_bb := "", response := "") -> void:
	_thaw_main_done_bb = question_bb
	_thaw_echo = response
	_exam_pin_name = false
	_exam_heading = ""
	_exam_prefix_bb = ""
	_exam_stop_video()
	_exam_icons_hide()
	_thaw_last_bb = ""
	thaw_text.text = ""   # new screen: nothing of the old text survives
	_thaw_last_pin = ""
	thaw_pin.text = ""
	thaw_pin.hide()
	_exam_clear_choices()
	_exam_hide_widgets()
	thaw_scroll.show()


func _exam_show_screen(n: int, complete := false) -> void:
	n = clampi(n, 1, 3)
	_exam_screen = n
	dev_push_screen("EXAM %d" % n, _exam_reenter.bind(_exam_show_screen.bind(n, false)))
	_exam_page()
	var cues: Array
	var after: Callable
	match n:
		1:
			cues = MemoryExam.CUES_SCREEN1
			after = _exam_wait.bind(_exam_show_screen.bind(2, false))
		2:
			cues = MemoryExam.CUES_NAME_Q
			_exam_heading = MemoryExam.HEADING_NAME
			after = _exam_show_name
		_:
			cues = MemoryExam.CUES_ERROR
			_thaw_main_done_bb = _escape_bb(MemoryExam.NAME_QUESTION)
			_exam_pin_name = true
			_exam_question = "Please indicate that you understand."
			var c0: Array = cues[0]
			var txt := str(c0[1])
			_exam_err_t = float(c0[0]) + (float(c0[2]) - float(c0[0])) * TYPE_FRACTION \
				* float(txt.find("ERROR")) / float(txt.length())
			_exam_name_el = -99.0
			_exam_name_wall = _thaw_wall
			after = _exam_show_choices
	var w: Array = MemoryExam.WINDOWS[n - 1]
	_thaw_log("exam screen %d" % n)
	_exam_play("main", cues, float(w[0]), float(w[1]), after, [], complete)


func _exam_wait(next: Callable) -> void:
	_thaw_phase = ThawPhase.EXAM_WAIT
	_exam_next = next
	exam_continue.show()


func _exam_continue_pressed() -> void:
	if _thaw_phase != ThawPhase.EXAM_WAIT or pause_menu.visible:
		return
	play_sfx(&"tap")
	exam_continue.hide()
	var next := _exam_next
	_exam_next = Callable()
	if next.is_valid():
		next.call()


# ---------------------------------------------------------------- name entry

func _exam_show_name() -> void:
	_thaw_phase = ThawPhase.EXAM_NAME
	exam_name_box.show()
	exam_name_hint.hide()
	if _exam_dbg.has("exam_name") and exam_name_edit.text == "":
		exam_name_edit.text = str(_exam_dbg["exam_name"]).substr(0, MemoryExam.NAME_MAX)
	exam_name_edit.caret_column = exam_name_edit.text.length()
	_exam_focus_name.call_deferred()
	_thaw_log("exam name entry")


## Focus + edit mode (Godot 4.4+ LineEdits stop editing after Enter).
func _exam_focus_name() -> void:
	if _thaw_phase != ThawPhase.EXAM_NAME or not exam_name_edit.is_visible_in_tree():
		return
	exam_name_edit.grab_focus()
	if exam_name_edit.has_method("edit"):
		exam_name_edit.call("edit")


func _exam_submit_name(_t: String = "") -> void:
	if _thaw_phase != ThawPhase.EXAM_NAME or pause_menu.visible:
		return
	var nm := exam_name_edit.text.strip_edges()
	if nm == "":
		exam_name_hint.text = MemoryExam.NAME_EMPTY
		exam_name_hint.add_theme_color_override("font_color", Color(ERROR_COLOR))
		exam_name_hint.show()
		exam_name_edit.text = ""
		play_sfx(&"close")
		_exam_focus_name.call_deferred()
		_thaw_log("exam name rejected (empty)")
		return
	play_sfx(&"tap")
	_exam_name = nm.substr(0, MemoryExam.NAME_MAX)
	vars["typed_name"] = _exam_name
	exam_name_edit.release_focus()
	exam_name_box.hide()
	_exam_name_settled = false
	_thaw_log("exam name '%s'" % _exam_name)
	_exam_show_screen(3)


## Seconds since the pinned name began to scramble (<0 = still showing the name).
## Follows the screen-3 VO clock (deterministic, synced to "The name ERROR"); once the VO is
## over or skipped it continues on the wall clock (the name still shows NAME_MIN_HOLD first).
func _exam_name_elapsed() -> float:
	if _exam_name_settled:
		return 99.0
	if _thaw_phase == ThawPhase.EXAM_VO and _exam_screen == 3:
		_exam_name_el = _thaw_t - _exam_err_t
		_exam_name_wall = _thaw_wall
		return _exam_name_el
	return maxf(_exam_name_el, -MemoryExam.NAME_MIN_HOLD) + (_thaw_wall - _exam_name_wall)


## The typed name: shown plainly, scrambles, settles into amber ERROR.
func _exam_name_bb() -> String:
	var el := _exam_name_elapsed()
	var nm := _exam_name if _exam_name != "" else "?"
	var scr := MemoryExam.NAME_SCRAMBLE_SEC
	if el < 0.0:
		return _escape_bb(nm)
	if el < scr:
		var p := el / scr
		var n := int(round(lerpf(float(nm.length()), 5.0, p)))
		var w := ""
		for i in n:
			if p > 0.75 and i < 5 and randf() < p:
				w += "ERROR"[i]
			elif i < nm.length() and randf() > p * 1.3:
				w += nm[i]
			else:
				w += ERROR_SCRAMBLE[randi() % ERROR_SCRAMBLE.length()]
		var col := Color(PIN_RESPONSE_COLOR).lerp(Color(ERROR_COLOR), clampf(p * 1.5, 0.0, 1.0))
		return "[color=#%s]%s[/color]" % [col.to_html(false), _escape_bb(w)]
	var word := "ERROR"
	if fmod(_thaw_wall + 0.9, 5.3) < 0.07:
		var at := randi() % 5
		word = word.substr(0, at) + ERROR_SCRAMBLE[randi() % ERROR_SCRAMBLE.length()] + word.substr(at + 1)
	return "[color=%s]%s[/color]" % [ERROR_COLOR, _escape_bb(word)]


## Pinned header bbcode for the current screen ("" = none).
func _thaw_pin_bb() -> String:
	var resp := ""
	if _exam_pin_name:
		resp = "> " + _exam_name_bb()
	elif _thaw_echo != "":
		resp = _escape_bb(_thaw_echo)
	if _thaw_main_done_bb == "" and resp == "":
		return ""
	return pinned_header_bb(_thaw_main_done_bb, resp)


# ---------------------------------------------------------------- YES / NO loop

func _exam_clear_choices() -> void:
	for c in _thaw_choice_btns:
		c.disabled = true
		c.queue_free()
	_thaw_choice_btns.clear()
	for c in thaw_choices.get_children():
		if c.has_meta("exam_spacer"):
			c.queue_free()
	_exam_qte_btn = null
	_exam_pick_fn = Callable()
	thaw_choices.hide()


## Same construction as the THAW YES/NO buttons: every response (incl. the QTE) sits in the
## same RESPONSE slot at the same size.
func _exam_make_choice(n: int, label: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ChoiceButton"
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(220, 34)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	thaw_choices.add_child(b)
	_thaw_choice_btns.append(b)
	return b


func _exam_show_choices() -> void:
	_exam_clear_choices()
	_thaw_phase = ThawPhase.EXAM_CHOICES
	for pair: Array in [[1, "YES", true], [2, "NO", false]]:
		var b := _exam_make_choice(pair[0], pair[1])
		b.pressed.connect(_exam_answer.bind(pair[2]))
	thaw_choices_header.text = MemoryExam.RESPONSE_HEADER
	thaw_choices.show()
	_thaw_log("exam choices (NO so far: %d)" % _exam_no)


func _exam_answer(yes: bool) -> void:
	if _thaw_phase != ThawPhase.EXAM_CHOICES or pause_menu.visible:
		return
	play_sfx(&"tap")
	_exam_settle_name()
	if yes:
		flags["exam_said_yes"] = true
		_thaw_log("exam YES")
		_exam_enter_yes()
		return
	vars["exam_no_count"] = int(vars.get("exam_no_count", 0)) + 1
	_thaw_log("exam NO %d" % mini(_exam_no + 1, 4))
	_exam_enter_no(mini(_exam_no + 1, 4))


## Dev back re-entry for exam screens: overlay up, calm O2, then rebuild the screen.
func _exam_reenter(fn: Callable) -> void:
	_exam_open()
	_exam_started = true
	if o2_level < 99.9:
		refill_o2(0.8)
	fn.call()


func _exam_enter_yes() -> void:
	dev_push_screen("EXAM > YES", _exam_reenter.bind(_exam_enter_yes))
	_exam_page(_escape_bb(_exam_question), "> YES")
	_exam_play("yes", MemoryExam.CUES_YES, 0.0, -1.0, _exam_wait.bind(_q2_show.bind(false, false)))


## NO k screen: pinned question + "> NO", then that NO reply (NO4 → O2 countdown).
func _exam_enter_no(k: int, complete := false) -> void:
	_exam_no = k
	dev_push_screen("EXAM > NO%d" % k, _exam_reenter.bind(_exam_enter_no.bind(k, false)))
	_exam_page(_escape_bb(_exam_question), "> NO")
	_exam_play_no(k, complete)


func _exam_settle_name() -> void:
	if _exam_pin_name:
		_exam_name_settled = true


func _exam_play_no(k: int, complete := false) -> void:
	var cues: Array = [MemoryExam.CUES_NO1, MemoryExam.CUES_NO2, MemoryExam.CUES_NO3, MemoryExam.CUES_NO4][k - 1]
	if k < 4:
		_exam_play("no%d" % k, cues, 0.0, -1.0, _exam_show_choices, [], complete)
		return
	# NO4: red edges creep in with the VO, doors lock as the line is spoken, colour drains.
	_exam_red_mode = "no4"
	var events := [
		[3.73, _exam_lock_doors],
		[10.07, func() -> void: _exam_fx_target = 0.18],
		[25.30, func() -> void: _exam_fx_target = 0.3],
	]
	_exam_play("no4", cues, 0.0, -1.0, _exam_death_start, events, complete)


func _exam_lock_doors() -> void:
	run_op("map_lock_door:stasis_15|ready_room")
	flags["stasis_sealed"] = true
	_exam_door_sfx("res://assets/sounds/airlockdoor.mp3", sfx_close, 0.5)


## Plays a door SFX from assets/sounds if present, else a pitched-down UI sound.
func _exam_door_sfx(path: String, fallback: AudioStreamPlayer, pitch: float) -> void:
	if ResourceLoader.exists(path):
		_exam_door.stream = load(path)
		_exam_door.play()
	else:
		_exam_sfx(fallback, pitch)


func _exam_unlock_doors() -> void:
	if has_flag("stasis_sealed"):
		run_op("map_unlock_door:stasis_15|ready_room")
		flags.erase("stasis_sealed")


func _exam_sfx(p: AudioStreamPlayer, pitch: float) -> void:
	p.pitch_scale = pitch
	p.play()
	get_tree().create_timer(1.5).timeout.connect(_exam_sfx_reset.bind(p))


func _exam_sfx_reset(p: AudioStreamPlayer) -> void:
	if is_instance_valid(p):
		p.pitch_scale = 1.0


# ---------------------------------------------------------------- O2 countdown (QTE)

## Called when the NO4 section ends. The NO4 text stays on screen; the QTE takes the choice slot.
func _exam_death_start() -> void:
	_thaw_phase = ThawPhase.EXAM_DEATH
	_thaw_voice = null
	_thaw_forced = _thaw_cues.size() - 1
	if not has_flag("stasis_sealed"):
		_exam_lock_doors()
	_exam_o2_t = clampf(_exam_o2_frozen if _exam_o2_frozen >= 0.0 else 0.0, 0.0, MemoryExam.O2_SECONDS)
	_exam_beat_t = 0.2
	_exam_red_mode = "death"
	_exam_set_lowpass(true)
	stop_o2_tween()
	_exam_show_qte()
	var frac := _exam_o2_t / MemoryExam.O2_SECONDS
	_exam_fx_target = lerpf(0.35, 1.0, frac)
	_exam_fx_amount = maxf(_exam_fx_amount, _exam_fx_target if _exam_o2_frozen >= 0.0 else 0.3)
	_exam_death_ui(frac)
	_thaw_render()
	_thaw_log("exam O2 countdown (%.1fs)" % MemoryExam.O2_SECONDS)


func _exam_show_qte() -> void:
	_exam_clear_choices()
	var b := _exam_make_choice(1, MemoryExam.UNDERSTAND_LABEL)
	b.name = "QteButton"
	b.pressed.connect(_exam_understood_pressed)
	# Draining timer lives INSIDE the button: faint fill + solid 3 px strip along the bottom.
	_exam_qte_fill = ColorRect.new()
	_exam_qte_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exam_qte_bar = ColorRect.new()
	_exam_qte_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(_exam_qte_fill)
	b.add_child(_exam_qte_bar)
	# Empty second row (NO's height): keeps the RESPONSE header and the QTE button exactly where the
	# header / first (YES) button sit on a normal two-answer screen.
	var spacer := Control.new()
	spacer.set_meta("exam_spacer", true)
	spacer.custom_minimum_size = b.custom_minimum_size
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thaw_choices.add_child(spacer)
	_exam_qte_btn = b
	thaw_choices.show()


func _exam_death_tick(delta: float) -> void:
	if _exam_o2_frozen < 0.0:
		_exam_o2_t += delta
	var frac := clampf(_exam_o2_t / MemoryExam.O2_SECONDS, 0.0, 1.0)
	_exam_fx_target = lerpf(0.35, 1.0, frac)
	# heartbeat: lub-dub, faster as the air runs out
	_exam_beat_t -= delta
	if _exam_beat_t <= 0.0:
		_exam_beat_t = lerpf(MemoryExam.BEAT_SLOW, MemoryExam.BEAT_FAST, frac)
		_exam_heart.pitch_scale = 0.42
		_exam_heart.play()
		_exam_pulse = 1.0
		_exam_dub_t = 0.17
	if _exam_dub_t >= 0.0:
		_exam_dub_t -= delta
		if _exam_dub_t < 0.0:
			_exam_heart.pitch_scale = 0.36
			_exam_heart.play()
			_exam_pulse = 0.7
	_exam_death_ui(frac)
	if frac >= 1.0 and _exam_o2_frozen < 0.0:
		_exam_die()


## O2 bar ticks down in 5 % steps (20 ticks over O2_SECONDS); QTE fill drains smoothly.
func _exam_death_ui(frac: float) -> void:
	var left := 1.0 - frac
	var stepped := ceilf(left * O2Bar.TICKS - 0.0001) / O2Bar.TICKS * 100.0
	set_o2(stepped, lerpf(0.35, 1.0, frac))
	var c := Color(ERROR_COLOR).lerp(Color("#d8352a"), frac)
	if is_instance_valid(_exam_qte_btn):
		var sz := _exam_qte_btn.size
		_exam_qte_fill.position = Vector2.ZERO
		_exam_qte_fill.size = Vector2(sz.x * left, sz.y)
		_exam_qte_fill.color = Color(c.r, c.g, c.b, 0.16)
		_exam_qte_bar.position = Vector2(0, sz.y - 3.0)
		_exam_qte_bar.size = Vector2(sz.x * left, 3.0)
		_exam_qte_bar.color = c
	thaw_choices_header.text = MemoryExam.QTE_HEADER % (MemoryExam.O2_SECONDS * left)


func _exam_understood_pressed() -> void:
	if _thaw_phase != ThawPhase.EXAM_DEATH or pause_menu.visible:
		return
	play_sfx(&"tap")
	flags["exam_understood"] = true
	_thaw_log("exam NO WAIT, I UNDERSTAND at %.2fs" % _exam_o2_t)
	_exam_enter_recover()


func _exam_reenter_recover() -> void:
	_exam_open()
	_exam_started = true
	_exam_red = MemoryExam.RED_O2_END * 0.7
	_exam_fx_amount = 0.6
	_exam_enter_recover()


## Recovery screen: pinned "> NO WAIT, I UNDERSTAND", O2 refills + red fades with the VO.
func _exam_enter_recover() -> void:
	dev_push_screen("EXAM > NO WAIT, I UNDERSTAND", _exam_reenter_recover)
	_exam_heart.stop()
	_exam_set_lowpass(false)
	_exam_o2_frozen = -1.0
	stop_o2_tween()
	_exam_page(_escape_bb(_exam_question), "> NO WAIT, I UNDERSTAND")
	_exam_fx_target = 0.45
	_exam_red_mode = "recover"
	_exam_recover_p = 0.0
	_exam_recover_red0 = _exam_red
	_exam_recover_o20 = o2_level
	_exam_recover_d0 = o2_danger
	var events := [
		[8.49, func() -> void:
			_exam_fx_target = 0.0
			_exam_unlock_doors()
			_exam_door_sfx("res://assets/sounds/dooropen.mp3", sfx_open, 0.6)],
	]
	_exam_play("recover", MemoryExam.CUES_RECOVER, 0.0, -1.0, _exam_wait.bind(_q2_show.bind(false, false)), events)


var _exam_die_tween: Tween


func _exam_die(instant := false) -> void:
	_thaw_phase = ThawPhase.EXAM_DEAD
	vars["exam_died_count"] = int(vars.get("exam_died_count", 0)) + 1
	_exam_heart.stop()
	_exam_clear_choices()
	set_o2(0.0, 1.0)
	_thaw_log("exam TERMINATED (deaths: %d)" % int(vars["exam_died_count"]))
	if instant:
		_exam_show_dead()
		return
	_exam_die_tween = create_tween()
	_exam_die_tween.tween_property(self, "_exam_fx_black", 1.0, 1.4)
	_exam_die_tween.tween_callback(_exam_show_dead)


## Generic template death screen (PdaScreen.show_death); RETRY replays exam screen 3.
func _exam_show_dead() -> void:
	_exam_die_tween = null
	_thaw_phase = ThawPhase.EXAM_DEAD
	set_o2(0.0, 1.0)
	_exam_sfx(sfx_close, 0.35)
	show_death(DEATH_MESSAGE, DEATH_RETRY, _exam_retry)
	_exam_reset_fx()   # the overlay is hidden now; RETRY starts clean


func _on_death_shown() -> void:
	if _exam_heart:
		_exam_heart.stop()
	_exam_set_lowpass(false)
	_thaw_stop_voice("death screen")
	if _thaw_phase != ThawPhase.IDLE and _thaw_phase != ThawPhase.DONE:
		_thaw_phase = ThawPhase.EXAM_DEAD


## RETRY: O2 / red / doors reset, then screen 3 ("The name ERROR…") replays its VO and
## typewriter from the start (the pinned name is already ERROR), then YES/NO at NO1.
func _exam_retry() -> void:
	_thaw_log("exam RETRY")
	_exam_open()
	_exam_started = true
	refill_o2(1.0)
	_exam_unlock_doors()
	_exam_no = 0
	_exam_name_settled = true
	_exam_show_screen(3)


# ---------------------------------------------------------------- dev back (template DEV BACK)

func _snapshot_extra() -> Dictionary:
	return {"exam_name": _exam_name, "exam_no": _exam_no, "exam_question": _exam_question,
		"exam_settled": _exam_name_settled, "exam_started": _exam_started, "exam_screen": _exam_screen}


func _restore_extra(d: Dictionary) -> void:
	if d.is_empty():
		return
	_exam_name = str(d["exam_name"])
	_exam_no = int(d["exam_no"])
	_exam_question = str(d["exam_question"])
	_exam_name_settled = bool(d["exam_settled"])
	_exam_started = bool(d["exam_started"])
	_exam_screen = int(d["exam_screen"])


## Stops every intro voice, timer (O2 countdown, fades) and effect; overlay down.
func _dev_stop_chapter() -> void:
	if _exam_die_tween:
		_exam_die_tween.kill()
		_exam_die_tween = null
	_thaw_stop_voice("dev back")
	if _exam_door:
		_exam_door.stop()
	_exam_reset_fx()
	_exam_clear_choices()
	_exam_hide_widgets()
	_exam_prefix_bb = ""
	_exam_stop_video()
	_exam_icons_hide()
	_exam_black_clear()
	exam_name_edit.release_focus()
	_exam_after = Callable()
	_exam_next = Callable()
	_exam_events = []
	_exam_o2_t = 0.0
	_exam_seek = -1.0
	_thaw_seek_at = -1.0
	_thaw_force_choice = ""
	_thaw_freeze = false
	_thaw_beat = -1.0
	_thaw_cues = []
	_thaw_voice = null
	_thaw_phase = ThawPhase.IDLE
	_thaw_last_bb = ""
	thaw_text.text = ""   # new screen: nothing of the old text survives
	_thaw_last_pin = ""
	thaw_pin.text = ""
	thaw_pin.hide()
	thaw.hide()
	safe_area.show()
	journal_button.show()
	set_backdrop(null)


# ---------------------------------------------------------------- effects

func _exam_reset_fx() -> void:
	_exam_fx_amount = 0.0
	_exam_fx_target = 0.0
	_exam_fx_black = 0.0
	_exam_red = 0.0
	_exam_red_mode = ""
	_exam_pulse = 0.0
	_exam_o2_frozen = -1.0
	if _exam_heart:
		_exam_heart.stop()
	_exam_set_lowpass(false)
	thaw.move_child(exam_fx, 1)   # above the text column, below the HUD (minimap / O2)
	exam_fx.hide()


func _exam_fx_tick(delta: float) -> void:
	_exam_fx_amount = move_toward(_exam_fx_amount, _exam_fx_target, delta * 0.35)
	_exam_pulse = maxf(0.0, _exam_pulse - delta * 3.0)
	match _exam_red_mode:
		"no4":
			if _thaw_phase == ThawPhase.EXAM_VO and _thaw_len > 0.0:
				_exam_red = lerpf(MemoryExam.RED_NO4_START, MemoryExam.RED_NO4_END,
					clampf(_thaw_t / _thaw_len, 0.0, 1.0))
		"death":
			var frac := clampf(_exam_o2_t / MemoryExam.O2_SECONDS, 0.0, 1.0)
			_exam_red = lerpf(MemoryExam.RED_NO4_END, MemoryExam.RED_O2_END, frac)
		"recover":
			# O2 refills + red fades with the recovery VO; finishes smoothly if skipped.
			if _thaw_phase == ThawPhase.EXAM_VO and _thaw_len > 0.5:
				_exam_recover_p = maxf(_exam_recover_p, clampf((_thaw_t - 0.5) / (_thaw_len - 0.5), 0.0, 1.0))
			else:
				_exam_recover_p = move_toward(_exam_recover_p, 1.0, delta * 1.25)
			var k := ease(_exam_recover_p, 0.6)
			_exam_red = _exam_recover_red0 * (1.0 - k)
			set_o2(lerpf(_exam_recover_o20, 100.0, k), lerpf(_exam_recover_d0, 0.0, k))
			if _exam_recover_p >= 1.0:
				_exam_red_mode = ""
		_:
			_exam_red = move_toward(_exam_red, 0.0, delta)
	var on := _exam_fx_amount > 0.002 or _exam_fx_black > 0.002 or _exam_red > 0.002
	exam_fx.visible = on
	if on:
		var mat := exam_fx.material as ShaderMaterial
		mat.set_shader_parameter("amount", _exam_fx_amount)
		mat.set_shader_parameter("black", _exam_fx_black)
		mat.set_shader_parameter("pulse", _exam_pulse)
		mat.set_shader_parameter("red", _exam_red)
		# keep the RESPONSE slot (YES/NO or the QTE button) legible under the effects
		var kr := Vector4.ZERO
		if thaw_choices.is_visible_in_tree():
			var vr := get_viewport_rect().size
			var gr := Rect2(thaw_choices_header.global_position, thaw_choices_header.get_minimum_size())
			for b in _thaw_choice_btns:
				if is_instance_valid(b) and b.is_visible_in_tree():
					gr = gr.merge(b.get_global_rect())
			gr = gr.grow(6.0)
			kr = Vector4(gr.position.x / vr.x, gr.position.y / vr.y, gr.size.x / vr.x, gr.size.y / vr.y)
		mat.set_shader_parameter("keep_rect", kr)


## Muffles the ship ambience (Music bus) while the air is going. Removed afterwards.
func _exam_set_lowpass(on: bool) -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	if on and _exam_lowpass_idx < 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 650.0
		AudioServer.add_bus_effect(bus, lp)
		_exam_lowpass_idx = AudioServer.get_bus_effect_count(bus) - 1
	elif not on and _exam_lowpass_idx >= 0:
		if _exam_lowpass_idx < AudioServer.get_bus_effect_count(bus):
			AudioServer.remove_bus_effect(bus, _exam_lowpass_idx)
		_exam_lowpass_idx = -1


# ---------------------------------------------------------------- QUESTIONS 2 + 3
## After "Acknowledged, Operator." → CONTINUE:
##   Q2  heading + "2) Do you remember the mission…" → 3 answers. Wrong → pinned reply →
##       CONTINUE → Q2 again (no punishment, vars.exam_q2_wrong += 1). "Insurance?" → pinned
##       "Correct. …" + "Would you like to know more?" → YES (video hook / placeholder) or NO.
##   Q3  heading + "3) Do you remember your function…" → YES/NO (flag exam_remembered_function)
##       → CLAIM OPERATOR screen (pinned answer) → "Would you like to know more?" YES → covered
##       examples (5 icons EX1-1..5) → NOT covered examples (4 icons EX2-1..4) → SPACE MADNESS; NO → SPACE MADNESS
##       (pinned > NO) → special note → complete → docked → last CONTINUE fades to black.
## Text, cues and clips live in data/memory_exam.gd. Every screen is dev_push_screen'ed.

## Plays several clips on one screen, one after another; earlier text stays. A skip finishes
## the whole screen.
func _exam_play_parts(parts: Array, after: Callable, complete := false) -> void:
	_exam_prefix_bb = ""
	_exam_play_part(parts, 0, after, complete)


func _exam_play_part(parts: Array, i: int, after: Callable, complete: bool) -> void:
	var p: Array = parts[i]
	var nxt := after if i == parts.size() - 1 else _exam_part_done.bind(parts, i, after, complete)
	_exam_play(str(p[0]), p[1], float(p[2]), float(p[3]), nxt, [], complete)


func _exam_part_done(parts: Array, i: int, after: Callable, complete: bool) -> void:
	_exam_prefix_bb = _thaw_body_bb()
	_exam_play_part(parts, i + 1, after, complete or _exam_last_skipped)


## Generic RESPONSE list (same buttons/slot as YES/NO). Long labels widen the whole set equally.
func _exam_show_choice_list(labels: Array, handler: Callable) -> void:
	_exam_clear_choices()
	_thaw_phase = ThawPhase.EXAM_CHOICES
	var w := 220.0
	var made: Array[Button] = []
	for i in labels.size():
		var b := _exam_make_choice(i + 1, str(labels[i]))
		b.pressed.connect(_exam_pick.bind(i))
		made.append(b)
		var font := b.get_theme_font("font")
		if font:
			var sb := b.get_theme_stylebox("normal")
			var pad := (sb.get_minimum_size().x if sb else 16.0) + 12.0
			w = maxf(w, ceilf(font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				b.get_theme_font_size("font_size")).x + pad))
	for b in made:
		b.custom_minimum_size.x = w
	_exam_pick_fn = handler
	thaw_choices_header.text = MemoryExam.RESPONSE_HEADER
	thaw_choices.show()
	_thaw_log("exam choices: %s" % ", ".join(PackedStringArray(labels)))


func _exam_pick(i: int) -> void:
	if _thaw_phase != ThawPhase.EXAM_CHOICES or pause_menu.visible or not _exam_pick_fn.is_valid():
		return
	if i < 0 or i >= _thaw_choice_btns.size():
		return
	play_sfx(&"tap")
	var fn := _exam_pick_fn
	_exam_pick_fn = Callable()
	fn.call(i)


func _q2_labels() -> Array:
	var out: Array = []
	for a: Dictionary in MemoryExam.Q2_ANSWERS:
		out.append(str(a["label"]))
	return out


## Q2 question. again=true: back after a wrong answer (text shown at once, no VO replay).
func _q2_show(complete := false, again := false) -> void:
	_exam_screen = 4
	dev_push_screen("EXAM Q2" + (" (again)" if again else ""), _exam_reenter.bind(_q2_show.bind(false, again)))
	_exam_page()
	_exam_heading = MemoryExam.HEADING_EXAM
	_thaw_log("exam Q2" + (" again" if again else ""))
	_exam_play(MemoryExam.STREAM_Q2, MemoryExam.CUES_Q2, 0.0, -1.0,
		_exam_show_choice_list.bind(_q2_labels(), _q2_answer), [], complete or again)


func _q2_answer(i: int) -> void:
	var a: Dictionary = MemoryExam.Q2_ANSWERS[i]
	if not bool(a["correct"]):
		vars["exam_q2_wrong"] = int(vars.get("exam_q2_wrong", 0)) + 1
	else:
		flags["exam_q2_correct"] = true
	_thaw_log("exam Q2 answer %d (%s)" % [i + 1, "correct" if bool(a["correct"]) else "wrong"])
	_q2_enter_answer(i)


## Pinned "2) …" / "> answer", then that reply. Wrong → CONTINUE → Q2; right → know more?
func _q2_enter_answer(i: int, complete := false) -> void:
	var a: Dictionary = MemoryExam.Q2_ANSWERS[i]
	_exam_screen = 5
	dev_push_screen("EXAM Q2 > %s" % str(a["label"]), _exam_reenter.bind(_q2_enter_answer.bind(i, false)))
	_exam_page(_escape_bb(MemoryExam.Q2_QUESTION), "> " + str(a["label"]))
	if not bool(a["correct"]):
		_exam_play(str(a["stream"]), a["cues"], 0.0, -1.0, _exam_wait.bind(_q2_show.bind(false, true)), [], complete)
		return
	_exam_play_parts([[str(a["stream"]), a["cues"], 0.0, -1.0],
		[MemoryExam.STREAM_KNOW_MORE, MemoryExam.CUES_KNOW_MORE, 0.0, -1.0]],
		_exam_show_choice_list.bind(["YES", "NO"], _know_more_answer), complete)


func _know_more_answer(i: int) -> void:
	if i == 0:
		flags["exam_know_more"] = true
		_archive_enter()
	else:
		flags.erase("exam_know_more")
		_q3_show(MemoryExam.KNOW_MORE_QUESTION, "> NO")


## "> YES" to know more: KNOW_MORE_VIDEO if set, else the placeholder text. CONTINUE → Q3.
func _archive_enter(complete := false) -> void:
	_exam_screen = 6
	dev_push_screen("EXAM Q2 > KNOW MORE", _exam_reenter.bind(_archive_enter.bind(false)))
	_exam_page(_escape_bb(MemoryExam.KNOW_MORE_QUESTION), "> YES")
	var vpath := know_more_video.strip_edges()
	var vs: VideoStream = null
	if vpath != "" and ResourceLoader.exists(vpath):
		vs = load(vpath) as VideoStream
	if vs:
		_exam_play_video(vs)
		_exam_wait(_q3_show.bind("", ""))
		return
	_exam_play("", MemoryExam.CUES_ARCHIVE_PLACEHOLDER, 0.0, -1.0, _exam_wait.bind(_q3_show.bind("", "")), [], complete)


func _exam_play_video(vs: VideoStream) -> void:
	if _exam_video == null:
		_exam_video = VideoStreamPlayer.new()
		_exam_video.name = "ExamVideo"
		_exam_video.expand = true
		_exam_video.custom_minimum_size = Vector2(538, 303)
		_exam_video.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_exam_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_exam_video.bus = &"Voice"
		thaw_scroll.get_parent().add_child(_exam_video)
		thaw_scroll.get_parent().move_child(_exam_video, thaw_scroll.get_index() + 1)
	thaw_scroll.hide()
	_exam_video.stream = vs
	_exam_video.show()
	_exam_video.play()
	_duck_ambience(true)
	_thaw_log("exam know-more video %s" % vs.resource_path)


func _exam_stop_video() -> void:
	if _exam_video and _exam_video.visible:
		_exam_video.stop()
		_exam_video.hide()
		thaw_scroll.show()
		_duck_ambience(false)


## Q3 question, optionally pinned under the know-more answer ("> NO").
func _q3_show(pin_q := "", pin_r := "", complete := false) -> void:
	_exam_screen = 7
	dev_push_screen("EXAM Q3", _exam_reenter.bind(_q3_show.bind(pin_q, pin_r, false)))
	_exam_page(_escape_bb(pin_q) if pin_q != "" else "", pin_r)
	_exam_heading = MemoryExam.HEADING_EXAM
	_thaw_log("exam Q3")
	_exam_play(MemoryExam.STREAM_Q3, MemoryExam.CUES_Q3, 0.0, -1.0,
		_exam_show_choice_list.bind(["YES", "NO"], _q3_answer), [], complete)


func _q3_answer(i: int) -> void:
	if i == 0:
		flags["exam_remembered_function"] = true
	else:
		flags.erase("exam_remembered_function")
	_thaw_log("exam Q3 " + ("YES" if i == 0 else "NO"))
	_tail_show(0)


## TAIL_SCREENS[k]; screen 0 is pinned with the Q3 answer, pin_q / pin_r pin a know-more answer.
## CONTINUE → k + 1 (the last one fades to black), or a know-more YES/NO (see TAIL_SCREENS).
## from_dev: re-entered by dev back → example icons start in their final state.
func _tail_show(k: int, complete := false, pin_q := "", pin_r := "", from_dev := false) -> void:
	var list: Array = MemoryExam.TAIL_SCREENS
	k = clampi(k, 0, list.size() - 1)
	var scr: Dictionary = list[k]
	_exam_screen = 10 + k
	dev_push_screen("EXAM %s" % str(scr["id"]).to_upper(), _exam_reenter.bind(_tail_show.bind(k, false, pin_q, pin_r, true)))
	var yes := has_flag("exam_remembered_function")
	if k == 0:
		_exam_page(_escape_bb(MemoryExam.Q3_QUESTION), "> YES" if yes else "> NO")
	elif pin_q != "":
		_exam_page(_escape_bb(pin_q), pin_r)
	else:
		_exam_page()
	var parts: Array = (scr["parts_yes"] if yes and scr.has("parts_yes") else scr["parts"]).duplicate()
	_thaw_log("exam %s" % str(scr["id"]))
	if scr.has("know_more"):
		parts.append([MemoryExam.STREAM_KNOW_MORE, MemoryExam.CUES_KNOW_MORE, 0.0, -1.0])
		_exam_play_parts(parts, _exam_show_choice_list.bind(["YES", "NO"], _tail_know_more.bind(k)), complete)
		return
	var next := _exam_fade_to_black if k == list.size() - 1 else _tail_show.bind(k + 1, false)
	_exam_play_parts(parts, _exam_wait.bind(next), complete)
	# Icons AFTER the clip has started: the section clock (_thaw_t) now belongs to THIS screen.
	# (Set up before it, the previous screen's clock — e.g. 26 s at the end of the covered
	# examples — marked every square as already shown, so screen B never played its blips.)
	if scr.has("icons"):
		_exam_icons_setup(scr["icons"], scr["icon_times"], from_dev or complete)


## "Would you like to know more?" after a tail screen: YES / NO → that screen, pinned.
func _tail_know_more(i: int, k: int) -> void:
	var km: Dictionary = (MemoryExam.TAIL_SCREENS[k] as Dictionary)["know_more"]
	if i == 0:
		flags["exam_heard_examples"] = true
	else:
		flags.erase("exam_heard_examples")
	_thaw_log("exam examples: " + ("YES" if i == 0 else "NO"))
	_tail_show(_tail_index(str(km["yes" if i == 0 else "no"])), false, MemoryExam.KNOW_MORE_QUESTION,
		"> YES" if i == 0 else "> NO")


# ---------------------------------------------------------------- example icons
## One square per id in the screen's ICONS_* list, in a centred row placed JUST under where the
## FINISHED text ends (measured on a hidden copy of the text label, so the row sits in its final
## spot from the first frame and never moves while the text types or when CONTINUE appears).
## Each fades in while rising ICON_RISE px into place when the VO reaches its time (driven by the
## section clock, so pause, seek, freeze and skip all agree), with one quiet ICON_SFX blip.
## Placeholder = outline + dim id label (EX1-1…); art from ICON_ART / ICON_ART_DIR replaces both
## (see MemoryExam "ADDING ART"). Examples screens are single-clip screens; the row follows the
## current clip's finished text.

func _exam_icons_build() -> void:
	if _exam_icon_row:
		return
	# hidden measuring copy of the body label (same font, size, width rules), made before the row
	_exam_icon_measure = thaw_text.duplicate() as RichTextLabel
	_exam_icon_measure.name = "ExamIconsMeasure"
	_exam_icon_measure.visible = false
	_exam_icon_measure.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	thaw_text.add_child(_exam_icon_measure)
	_exam_icon_row = HBoxContainer.new()
	_exam_icon_row.name = "ExamIcons"
	_exam_icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_exam_icon_row.add_theme_constant_override("separation", int(MemoryExam.ICON_GAP))
	_exam_icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thaw_text.add_child(_exam_icon_row)
	thaw_text.resized.connect(func() -> void: _exam_icon_layout_key = "")
	_exam_icon_sfx = AudioStreamPlayer.new()
	_exam_icon_sfx.name = "ExamIconSfx"
	_exam_icon_sfx.bus = &"Sfx"
	_exam_icon_sfx.volume_db = MemoryExam.ICON_SFX_DB
	if ResourceLoader.exists(MemoryExam.ICON_SFX):
		_exam_icon_sfx.stream = load(MemoryExam.ICON_SFX) as AudioStream
	add_child(_exam_icon_sfx)
	_exam_icon_row.hide()


## Art for an icon id: icon_art[id] (= MemoryExam.ICON_ART) if that file exists, else
## icon_art_dir/<id>.<ext> (= res://assets/icons/EX1-1.png …) if it exists, else "" (placeholder).
func exam_icon_art_path(id: String) -> String:
	var path := str(icon_art.get(id, ""))
	if path != "" and _art_exists(path):
		return path
	for ext in MemoryExam.ICON_ART_EXTS:
		var p := icon_art_dir.path_join("%s.%s" % [id, ext])
		if _art_exists(p):
			return p
	return ""


static func _art_exists(p: String) -> bool:
	return ResourceLoader.exists(p) or FileAccess.file_exists(p)


func exam_icon_art(id: String) -> Texture2D:
	var p := exam_icon_art_path(id)
	if p == "":
		return null
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	var img := Image.load_from_file(p)   # a raw, not (yet) imported file
	return ImageTexture.create_from_image(img) if img else null


func _exam_icon_make(id: String) -> Control:
	var green := Color(0.56, 0.8, 0.6)
	var art := exam_icon_art(id)
	var slot := Control.new()
	slot.name = id
	slot.custom_minimum_size = Vector2(MemoryExam.ICON_SIZE, MemoryExam.ICON_SIZE + MemoryExam.ICON_RISE)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sq := Panel.new()
	sq.name = "Square"
	sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sq.size = Vector2(MemoryExam.ICON_SIZE, MemoryExam.ICON_SIZE)
	if art:
		sq.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(green, 0.07)
		sb.border_color = Color(green, 0.8)
		sb.set_border_width_all(1)
		sq.add_theme_stylebox_override("panel", sb)
	var tex := TextureRect.new()
	tex.name = "Icon"
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.texture = art
	tex.visible = art != null
	sq.add_child(tex)
	var tag := Label.new()
	tag.name = "Tag"
	tag.text = id
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mono: Font = thaw_status.get_theme_font("font", "OsLabel")
	if mono:
		tag.add_theme_font_override("font", mono)
	tag.add_theme_font_size_override("font_size", MemoryExam.ICON_LABEL_SIZE)
	tag.add_theme_color_override("font_color", Color(green, 0.45))
	tag.visible = art == null
	sq.add_child(tag)
	slot.add_child(sq)
	return slot


func _exam_icons_setup(ids: Array, times: Array, final: bool) -> void:
	_exam_icons_build()
	for c in _exam_icon_row.get_children():
		_exam_icon_row.remove_child(c)
		c.queue_free()
	_exam_icon_boxes.clear()
	_exam_icon_ids = ids.duplicate()
	_exam_icon_times = times.duplicate()
	_exam_icon_shown = []
	_exam_icons_final = final
	for id in ids:
		var slot := _exam_icon_make(str(id))
		_exam_icon_row.add_child(slot)
		_exam_icon_boxes.append(slot.get_node("Square") as Panel)
		_exam_icon_shown.append(final)
	_exam_icon_layout_key = ""
	_exam_icon_row.show()
	_exam_icons_update()


## 0..1 appear progress of icon i on the section clock.
func _exam_icon_progress(i: int) -> float:
	if _exam_icons_final or i >= _exam_icon_times.size():
		return 1.0
	return clampf((_thaw_t - float(_exam_icon_times[i])) / MemoryExam.ICON_APPEAR_SECONDS, 0.0, 1.0)


## Body bbcode once every cue of the current clip has finished typing.
func _exam_final_body_bb() -> String:
	var forced := _thaw_forced
	_thaw_forced = _thaw_cues.size() - 1
	var bb := _thaw_body_bb()
	_thaw_forced = forced
	return bb


## Row just under the finished text: top of the squares = finished text height + ICON_TEXT_GAP.
func _exam_icons_layout() -> void:
	var w: float = thaw_text.size.x
	var key := "%.1f|%d|%d|%s" % [w, _thaw_cues.size(), _exam_prefix_bb.length(),
		str(_thaw_cues[0][1]) if not _thaw_cues.is_empty() else ""]
	if key == _exam_icon_layout_key:
		return
	_exam_icon_layout_key = key
	_exam_icon_measure.size = Vector2(w, 0.0)
	_exam_icon_measure.text = _exam_final_body_bb()
	_exam_icon_final_text_h = float(_exam_icon_measure.get_content_height())
	_exam_icon_row.size = Vector2(w, MemoryExam.ICON_SIZE + MemoryExam.ICON_RISE)
	_exam_icon_row.position = Vector2(0.0, _exam_icon_final_text_h + MemoryExam.ICON_TEXT_GAP)


func _exam_icons_update() -> void:
	if _exam_icon_row == null or not _exam_icon_row.visible:
		return
	_exam_icons_layout()
	for i in _exam_icon_boxes.size():
		var p := _exam_icon_progress(i)
		var k := ease(p, 0.5)   # ease-out
		var sq := _exam_icon_boxes[i]
		sq.modulate.a = k
		sq.position.y = MemoryExam.ICON_RISE * (1.0 - k)
		if p > 0.0 and not _exam_icon_shown[i]:
			_exam_icon_shown[i] = true
			# only when it appears in time with the VO (not all at once on a skip / seek)
			if _thaw_phase == ThawPhase.EXAM_VO and _thaw_t - float(_exam_icon_times[i]) < 0.25 \
					and _exam_icon_sfx.stream and not _thaw_freeze:
				_exam_icon_sfx.play()
				_exam_icon_sfx_count += 1


func _exam_icons_hide() -> void:
	if _exam_icon_row:
		_exam_icon_row.hide()
		_exam_icon_sfx.stop()


func _tail_index(id: String) -> int:
	var list: Array = MemoryExam.TAIL_SCREENS
	for k in list.size():
		if str((list[k] as Dictionary)["id"]) == id:
			return k
	return -1


# ---------------------------------------------------------------- fade to black

## Final CONTINUE: everything fades to black over FADE_BLACK_SECONDS, holds AFTER_EXAM_HOLD,
## shows the AFTER_EXAM_CARD ("ONE HOUR LATER"), then MemoryExam.AFTER_EXAM opens
## (scene:excursion1_prep, which fades in from black). Empty AFTER_EXAM = stay black.
func _exam_fade_to_black(instant := false) -> void:
	dev_push_screen("EXAM END (BLACK)", _exam_reenter.bind(_exam_fade_to_black.bind(true)))
	_exam_clear_choices()
	_exam_hide_widgets()
	_thaw_stop_voice("exam end")
	flags["exam_complete"] = true
	_exam_wrap_up()
	_thaw_phase = ThawPhase.EXAM_BLACK
	if _exam_black == null:
		_exam_black = ColorRect.new()
		_exam_black.name = "ExamFadeBlack"
		_exam_black.color = Color.BLACK
		_exam_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_exam_black.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_exam_black)
	move_child(_exam_black, pause_menu.get_index())   # over everything but the pause menu
	_exam_black.show()
	if _exam_black_tween:
		_exam_black_tween.kill()
	var secs := 0.0 if instant else MemoryExam.FADE_BLACK_SECONDS
	_exam_black.modulate.a = 1.0 if instant else 0.0
	_exam_black_tween = create_tween().set_parallel(true)
	_exam_black_tween.tween_property(_exam_black, "modulate:a", 1.0, maxf(secs, 0.01))
	_exam_black_tween.tween_property(ambience, "volume_db", -60.0, maxf(secs, 0.01))
	_exam_black_tween.chain().tween_interval(MemoryExam.AFTER_EXAM_HOLD)
	_exam_black_tween.chain().tween_callback(_exam_after_black)
	_thaw_log("exam fade to black")


## The intro never moves the player from the map (click-to-move is for later chapters).
func _allow_map_moves() -> bool:
	return false


func _exam_after_black() -> void:
	_exam_black_tween = null
	var t := after_exam_target.strip_edges()
	if t == "" or _thaw_phase != ThawPhase.EXAM_BLACK:
		return   # hold on black: nothing comes after the exam yet
	if MemoryExam.AFTER_EXAM_CARD != "":
		_exam_show_card()
		return
	_exam_go_after(t)


## "ONE HOUR LATER" centred on the black: fade in, hold, fade out, then AFTER_EXAM.
func _exam_show_card() -> void:
	if _exam_card == null:
		_exam_card = Label.new()
		_exam_card.name = "ExamTimeCard"
		_exam_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_exam_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_exam_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_exam_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(MemoryExam.CARD_FONT):
			_exam_card.add_theme_font_override("font", load(MemoryExam.CARD_FONT))
		_exam_card.add_theme_font_size_override("font_size", MemoryExam.CARD_FONT_SIZE)
		_exam_card.add_theme_color_override("font_color", MemoryExam.CARD_COLOR)
		_exam_black.add_child(_exam_card)
	_exam_card.text = MemoryExam.AFTER_EXAM_CARD
	_exam_card.modulate.a = 0.0
	_exam_card.show()
	_exam_card_t0 = Time.get_ticks_msec()
	_thaw_log("exam card: %s" % MemoryExam.AFTER_EXAM_CARD)
	_exam_black_tween = create_tween()
	_exam_black_tween.tween_property(_exam_card, "modulate:a", 1.0, MemoryExam.CARD_FADE_IN)
	_exam_black_tween.tween_interval(MemoryExam.CARD_HOLD)
	_exam_black_tween.tween_property(_exam_card, "modulate:a", 0.0, MemoryExam.CARD_FADE_OUT)
	_exam_black_tween.tween_interval(MemoryExam.CARD_AFTER)
	_exam_black_tween.tween_callback(func() -> void:
		_exam_black_tween = null
		_exam_card.hide()
		if _thaw_phase == ThawPhase.EXAM_BLACK:
			_exam_go_after(after_exam_target.strip_edges()))


func _exam_go_after(t: String) -> void:
	if after_exam_dry_run:
		exam_left_to = t   # tests: stop here instead of changing scene
		return
	var id := StringName(t.trim_prefix("passage:"))
	if passages.has(id):
		ambience.volume_db = _thaw_ambience_base_db
		_exam_leave(id)
		_exam_black_tween = create_tween()
		_exam_black_tween.tween_property(_exam_black, "modulate:a", 0.0, 0.8)
		_exam_black_tween.tween_callback(_exam_black.hide)
		return
	go_target(t)


func _exam_black_clear() -> void:
	if _exam_black_tween:
		_exam_black_tween.kill()
		_exam_black_tween = null
	if _exam_card:
		_exam_card.hide()
	if _exam_black and _exam_black.visible:
		_exam_black.hide()
		ambience.volume_db = _thaw_ambience_base_db


## --exam_screen= q2 | q2wrong1 | q2wrong2 | q2correct | archive | q3 | q3yes | q3no |
## <tail id> (function … docked) | black. --exam_complete shows the screen finished.
func _exam_debug_q23(sc: String, complete: bool) -> bool:
	_exam_question = "Please indicate that you understand."
	match sc:
		"q2":
			_q2_show(complete)
		"q2again":
			_q2_show(false, true)
		"q2wrong1":
			_q2_enter_answer(0, complete)
		"q2wrong2":
			_q2_enter_answer(1, complete)
		"q2correct":
			_q2_enter_answer(2, complete)
		"archive":
			flags["exam_know_more"] = true
			_archive_enter(complete)
		"q3":
			_q3_show("", "", complete)
		"q3yes", "q3no":
			if sc == "q3yes":
				flags["exam_remembered_function"] = true
			_tail_show(0, complete)
		"covered":   # always entered from the know-more YES
			_tail_show(_tail_index("covered"), complete, MemoryExam.KNOW_MORE_QUESTION, "> YES")
		"space_madness_no":
			_tail_show(_tail_index("space_madness"), complete, MemoryExam.KNOW_MORE_QUESTION, "> NO")
		"black":   # the final screen, then its CONTINUE
			_tail_show(MemoryExam.TAIL_SCREENS.size() - 1, true)
			_exam_fade_to_black()
		_:
			var k := _tail_index(sc)
			if k < 0:
				return false
			if _exam_dbg.has("exam_yes"):
				flags["exam_remembered_function"] = true
			_tail_show(k, complete)
	return true


# ---------------------------------------------------------------- finish / debug

## Legacy hand-off (Q1 used to end here): bookkeeping + main UI at home_bunk. The exam now ends
## on the black screen (_exam_fade_to_black); AFTER_EXAM can still lead to a passage.
func _exam_finish() -> void:
	_exam_wrap_up()
	_exam_leave(&"home_bunk")


## Exam result vars / flags (callsign OPERATOR, counts, exam_done).
func _exam_wrap_up() -> void:
	vars["typed_name"] = _exam_name
	vars["exam_no_count"] = int(vars.get("exam_no_count", 0))
	vars["exam_died_count"] = int(vars.get("exam_died_count", 0))
	vars["exam_q2_wrong"] = int(vars.get("exam_q2_wrong", 0))
	vars["callsign"] = DEFAULT_CALLSIGN
	flags["exam_done"] = true
	_thaw_log("exam done: name='%s' no=%d died=%d understood=%s q2_wrong=%d remembered_function=%s" % [_exam_name,
		int(vars["exam_no_count"]), int(vars["exam_died_count"]), str(has_flag("exam_understood")),
		int(vars["exam_q2_wrong"]), str(has_flag("exam_remembered_function"))])


## Overlay down, main UI up, open passage `id`.
func _exam_leave(id: StringName) -> void:
	_exam_reset_fx()
	_exam_unlock_doors()
	_thaw_stop_voice("exam finish")
	_exam_clear_choices()
	if o2_level < 100.0 and _o2_tween == null:
		refill_o2(0.6)
	elif _o2_tween == null:
		set_o2(100.0, 0.0)
	_thaw_phase = ThawPhase.DONE
	thaw.hide()
	safe_area.show()
	journal_button.show()
	set_backdrop(null)
	goto(id)


## --jump=exam [--exam_screen=1|2|3|choices|yes|qte|dead|retry|recover] [--exam_no=1..4]
## [--exam_o2=S] [--exam_name=Text] [--exam_at=S] [--exam_freeze]
func _exam_debug_entry() -> void:
	var d := _exam_dbg
	_exam_open()
	_exam_started = true
	_thaw_phase = ThawPhase.IDLE
	_exam_name = str(d.get("exam_name", "MARLOW")).strip_edges().substr(0, MemoryExam.NAME_MAX)
	vars["typed_name"] = _exam_name
	if d.has("exam_at"):
		_exam_seek = float(str(d["exam_at"]))
	var q_after := {1: "Please indicate that you understand.", 2: "Please indicate that you understand.",
		3: "Please indicate that you understand.", 4: "Please indicate in the affirmative if you understand this."}
	if d.has("exam_o2") or str(d.get("exam_screen", "")) in ["qte", "death", "dead", "recover"]:
		var sc := str(d.get("exam_screen", ""))
		var s := float(str(d.get("exam_o2", "6" if sc == "recover" else "0")))
		if sc == "dead":
			s = MemoryExam.O2_SECONDS
		_exam_no = 4
		vars["exam_no_count"] = 4
		_exam_question = q_after[4]
		_exam_o2_frozen = minf(s, MemoryExam.O2_SECONDS)
		var seek := _exam_seek
		_exam_seek = -1.0
		_exam_enter_no(4, true)          # NO4 text complete → doors lock → QTE
		_exam_seek = seek
		if s >= MemoryExam.O2_SECONDS:
			_exam_die(true)
		elif sc == "recover":
			_exam_fx_amount = 0.85
			_exam_red = lerpf(MemoryExam.RED_NO4_END, MemoryExam.RED_O2_END, s / MemoryExam.O2_SECONDS)
			_exam_understood_pressed()
		return
	if d.has("exam_no"):
		var k := clampi(int(str(d["exam_no"])), 1, 4)
		_exam_no = k
		vars["exam_no_count"] = k
		_exam_question = q_after[k]
		_exam_enter_no(k)
		return
	var sc2 := str(d.get("exam_screen", "1")).to_lower()
	if _exam_debug_q23(sc2, d.has("exam_complete")):
		return
	match sc2:
		"yes":
			_exam_question = q_after[1]
			_exam_enter_yes()
		"retry":   # as after a death: screen 3 replays (VO + typewriter), name already ERROR
			vars["exam_died_count"] = 1
			_exam_retry()
		"choices":
			_exam_show_screen(3, true)
			_exam_name_settled = true
		_:
			_exam_show_screen(clampi(int(sc2), 1, 3))


# ---------------------------------------------------------------- input / pause / audio

func _on_thaw_gui_input(event: InputEvent) -> void:
	if _is_press(event):
		_thaw_press()
		accept_event()


func _on_advance() -> bool:
	if not thaw.visible:
		return false
	if _thaw_phase == ThawPhase.EXAM_BLACK:
		return true   # nothing after the fade yet
	if _thaw_phase in [ThawPhase.MAIN, ThawPhase.REPLY, ThawPhase.EXAM_VO]:
		_thaw_press()
		return true
	if _thaw_phase == ThawPhase.EXAM_WAIT:
		_exam_continue_pressed()
		return true
	if _thaw_phase == ThawPhase.EXAM_DEATH:
		_exam_understood_pressed()
		return true
	return false  # CHOICES: 1/2 or a focused button; EXAM_NAME: LineEdit keeps keys


## First press finishes the line being typed; a second press within 1.5 s skips the section.
func _thaw_press() -> void:
	if pause_menu.visible:
		return
	if _thaw_phase == ThawPhase.EXAM_WAIT:
		_exam_continue_pressed()
		return
	if _thaw_phase == ThawPhase.EXAM_NAME:
		_exam_focus_name()
		return
	if _thaw_phase not in [ThawPhase.MAIN, ThawPhase.REPLY, ThawPhase.EXAM_VO]:
		return
	if _thaw_beat >= 0.0:
		_exam_begin()
		return
	var typing := _thaw_typing_index()
	if typing >= 0 and _thaw_wall > _thaw_skip_until:
		_thaw_forced = maxi(_thaw_forced, typing)
		_thaw_skip_until = _thaw_wall + 1.5
		_thaw_log("press: finish line %d" % typing)
		_thaw_render()
		return
	_thaw_log("press: skip section")
	_thaw_skip_section()


func _overlay_input(event: InputEvent) -> bool:
	if not thaw.visible:
		return false
	if _thaw_phase == ThawPhase.EXAM_BLACK:
		return true
	if _thaw_phase == ThawPhase.EXAM_CHOICES and _exam_pick_fn.is_valid():
		for n in range(1, mini(_thaw_choice_btns.size(), 9) + 1):
			if event.is_action_pressed("choice_%d" % n):
				_exam_pick(n - 1)
				return true
	elif _thaw_phase == ThawPhase.EXAM_CHOICES:
		if event.is_action_pressed("choice_1"):
			_exam_answer(true)
			return true
		if event.is_action_pressed("choice_2"):
			_exam_answer(false)
			return true
	elif _thaw_phase == ThawPhase.EXAM_WAIT and event.is_action_pressed("choice_1"):
		_exam_continue_pressed()
		return true
	elif _thaw_phase == ThawPhase.EXAM_DEATH and event.is_action_pressed("choice_1"):
		_exam_understood_pressed()
		return true
	if _thaw_phase != ThawPhase.CHOICES and _thaw_phase != ThawPhase.EXAM_CHOICES:
		return false
	if _thaw_phase == ThawPhase.EXAM_CHOICES:
		if get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_up")
				or event.is_action_pressed("ui_down")):
			if not _thaw_choice_btns.is_empty():
				_thaw_choice_btns[0].grab_focus()
			return true
		return false
	if event.is_action_pressed("choice_1"):
		_thaw_pick(true, 0.0)
		return true
	if event.is_action_pressed("choice_2"):
		_thaw_pick(false, 0.0)
		return true
	if get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_up")
			or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left")
			or event.is_action_pressed("ui_right")):
		if not _thaw_choice_btns.is_empty():
			_thaw_choice_btns[0].grab_focus()
		return true
	return false


func _on_pause_changed(paused: bool) -> void:
	for p: AudioStreamPlayer in [voice_main, voice_yes, voice_no, voice_exam, _exam_heart, _exam_door]:
		if p and (p.playing or p.stream_paused):
			p.stream_paused = paused
			_thaw_log("%s %s at %.2f" % ["pause" if paused else "resume", p.name, p.get_playback_position()])
	if _exam_video and _exam_video.visible:
		_exam_video.paused = paused
	if not paused and _thaw_phase == ThawPhase.EXAM_NAME:
		_exam_focus_name.call_deferred()


func _duck_ambience(on: bool) -> void:
	var target := _thaw_ambience_base_db + (AMBIENT_DUCK_DB if on else 0.0)
	create_tween().tween_property(ambience, "volume_db", target, 0.4)


func _thaw_log(msg: String) -> void:
	if OS.is_debug_build():
		print("THAW: ", msg)


func _exit_tree() -> void:
	for p: AudioStreamPlayer in [voice_main, voice_yes, voice_no, voice_exam, _exam_heart, _exam_door]:
		if p:
			p.stop()
	_exam_set_lowpass(false)
	super._exit_tree()


# ======================================================== DEBUG

func _debug_prepare(jump_id: StringName) -> void:
	if jump_id != &"thaw" and jump_id != &"exam":
		thaw.hide()
		_thaw_phase = ThawPhase.DONE
	match jump_id:
		&"home_lock":
			flags["asked_split"] = true
			flags["asked_any"] = true
			unlocked.append(&"orison")
		&"home_airlock":
			flags["asked_quiet"] = true
			flags["asked_any"] = true
			flags["lamp_decided"] = true
			flags["seen_tab_deck"] = true
			give_item(&"worklamp")
			unlocked.append(&"orison")
			unlocked.append(&"worklamp")
			set_tab_locked(Tab.DECK, false)


## --thaw_at / --thaw_choice are read in _setup_story (before the thaw starts).
func _debug_extra(args: Dictionary) -> void:
	# --boot=callsign (legacy) / --boot=exam: skip the thaw VO straight to the exam name screen.
	if args.has("boot") and str(args["boot"]) in ["callsign", "exam"] and thaw.visible:
		_thaw_end_main()
		_thaw_stop_voice("boot skip")
		_exam_open()
		_exam_started = true
		_exam_show_screen(2, true)
	if args.has("plate"):
		choose((passages[&"home_airlock"]["choices"] as Array)[0])
	if args.has("lamp_step"):
		choose((passages[&"home_lock"]["choices"] as Array)[0])
