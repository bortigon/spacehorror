# Space Horror (PC build)

Desktop/landscape rebuild of the phone prototype (`phone-space-horror`). Target: **Godot 4.6.x**
(Compatibility renderer). The project name lives in one place: `project.godot` > `config/name`.

## Title screen (boot scene)
`scenes/title.tscn` + `title.gd` is the main scene (`project.godot` > `run/main_scene`): the REC-7 logo
(`assets/rec7_logo.png`, its dark background keyed out by a small shader so it sits on the CRT
`screen_refresh` background), a dim `REC-7 // TRM-CUFF` caption, and **PLAY** / **QUIT** (standard
220x38 buttons from `pda_theme.tres`, UI-1 tap on click like the PDA buttons, no key hints).
PLAY fades out and, in a debug build, opens the mission select (`scenes/mission_select.tscn`):
one button per scene in `story/SCENE_ORDER.md` (**INTRO**, **READY ROOM**), then **BACK**. BACK returns to the title. There is
no QUIT here. A release build never shows the menu: PLAY still opens `scenes/intro.tscn` (the stasis thaw).
Adding a scene to the list adds its button. Subscenes are not buttons. No separate dev-skip label.
Debug builds: any debug arg the title does not use (`--jump=…`, `--thaw_at=…`, `--boot=…`,
`--skip_title`, …) skips the title and this menu and goes straight to the intro, so the debug args
below work unchanged. Title-only args: `--shot=PATH [--shot_delay=1.2]`,
`--title_hover=play|quit` (hover look for screenshots), `--nodev`.

## Layout (960x540 base, canvas_items stretch, aspect keep)
- Header strip: OS lines (Plex Mono), COMMS lines (amber), OXYGEN bar (`O2 ▮▮▮… NN%`), hourglass + blocks (armed only), LOCKER button.
- Left rail: LOG / DECK / LOCKER / KIT tabs (Oxanium).
- Centre: location title (Oxanium) + story text (Plex Sans, ~70-75 chars per line).
- Right column: ACTIONS choices (keys 1-9, no number shown), amber `N BLK` tags once the window is armed.
- Left rail: tabs only (no key legend).
- Dossier popup: centred modal (500x300) over a light dim; Esc / click outside / Close.
- Pause menu (Esc): Resume / Fullscreen / Quit.

## Controls
| Key | Action |
|---|---|
| 1-9 (and numpad) | pick choice N (LOG tab) |
| Q / Shift+Tab | previous PDA tab |
| E / Tab | next PDA tab |
| Esc | close dossier; otherwise open/close pause menu |
| F11, Alt+Enter | toggle fullscreen |
| Space / Enter / click | THAW: finish the current line; press again (or hold ~0.6 s) to skip the VO section. Also dismisses plates. |
| 1 / 2 | THAW and MEMORY EXAMINATION YES / NO (also clickable, focusable) |
| Space / Enter / 1 / click | EXAM: CONTINUE between screens; NO WAIT, I UNDERSTAND during the O2 countdown. Death screen: RETRY |
| Typing + Enter | EXAM name field (max 20 chars, blank rejected). While typing, every hotkey (1-9, M, Space, Q/E) goes into the field; Esc still opens the pause menu |
| M | open / close the vessel map (also click the minimap under ACTIONS). Blocked during THAW / MEMORY EXAMINATION (the minimap there is read-only) |
| Arrow keys | move keyboard focus (first press focuses the first choice / YES) |
| Mouse | click choices / tabs / green words / minimap; pointing-hand cursor + underline on links |
| Mouse wheel UP | DEV ONLY (debug/editor runs): back one screen (see Dev back). Wheel down does nothing |

Input actions (`choice_1..9`, `tab_next`, `tab_prev`, `toggle_fullscreen`, `advance`, `pause_menu`)
are registered in code by `PdaScreen._ensure_input_map()` so they always exist; you can also add
them in Project Settings > Input Map and the code will leave your bindings alone and only add missing keys.

## UI RULE: no tutorials / key hints (whole game)
The game never tells the player which key does what: no footer hint lines, no `[Space]` /
`[Enter]` / `[Esc]` / `[1-9]` / `[M]` in labels or buttons, no number prefixes on choices, no
helper lines ("MAX 20 CHARACTERS…", "HOVER A ROOM…", "CLICK A COMPARTMENT…"). The bindings above
all still work; players discover them. Gameplay text stays (blank-name validation message,
the WINDOW CLOSING timer). key_test scans every visible label/button/tooltip for hint words.

## UI RULE: pinned response (whole game)
After **every** player response a NEW screen opens with the question and the chosen response pinned
at the top — question dim (`PIN_QUESTION_COLOR`), response in accent bold (`PIN_RESPONSE_COLOR`,
e.g. `> YES`) — and only then does that screen type out the next text / play the next VO.
- Story runner (`PdaScreen`): on by default (`pin_choices = true`). `choose()` pins
  `"> " + label`, plus the passage's `"prompt"` (or the choice's own `"pin_question"`) as the dim
  question line; `render_passage()` draws it above the passage text. Arriving at a passage any other
  way (goto, jump, load) clears the pin. API: `pin_response(q, r)`, `clear_pin()`, `pinned_header_bb()`.
- Intro overlay (`scenes/intro.gd`): `ThawPin` label above the text column. THAW (`Are you observing
  the TRM-CUFF now?` / `> YES|NO`), exam name (`1) Do you remember your name?` / `> <name→ERROR>`),
  each YES/NO answer, NO1-NO4 (pinned question = the most recent "Please indicate…" line), and the
  recovery screen (`> NO WAIT, I UNDERSTAND`). `_exam_page(question_bb, response)` opens such a screen.
- Screens that are not the result of a response (exam screen 1, screen 2) have no pin.

## Oxygen bar
`ui/o2_bar.gd` (`O2Bar`): 20 stepped ticks, Plex Mono `O2` label + `NN%`. Lives in the main header
(`show_o2_in_header`) and, during THAW / EXAM, in the same top-right spot of the overlay (both are
kept in sync). `set_o2(level 0..1, danger 0..1)` (also sets `vars.o2`), `refill_o2(seconds)` smooth
tween, `stop_o2_tween()`. Danger > 0 shifts amber → red with a glow pulse that speeds up as it gets
low, and flashes when a tick drops. Exam: 100% normally, drops 5% per 0.5 s during the 10 s countdown,
refills with the recovery VO, 0% at death, refilled on RETRY.

## Death screen (template, reusable)
`show_death(message := "OPERATOR DECEASED", retry_label := "RETRY", retry_target = null,
heading := "SIGNAL LOST")` hides every UI layer (header, O2 bar, overlays, chapter HUDs, pinned
text, choices) so only the background + screen-refresh shader remain, and centres heading +
message + RETRY (click / Space / Enter / 1; Esc still pauses; presses in the first 0.35 s are
ignored). `retry_target`: a Callable (called), a passage id (goto, O2 refilled), `"checkpoint"`
(last `checkpoint` op), or null (last checkpoint if any, else the current passage).
Hook `_on_death_shown()`; signals `died(message)`, `death_retried`. `hide_death()`, `is_dead()`.
Story ops: `"checkpoint"`, `"die"`, `"die:MESSAGE|RETRY|RETRY_LABEL|HEADING"`, or a Dictionary op
`{"die": {"message": "Hull breach", "retry": "home_lock", "retry_label": "RETRY", "heading": "SIGNAL LOST"}}`.
The Memory Examination uses it with the defaults; RETRY replays exam screen 3 ("The name ERROR…")
with its VO and typewriter from the start, O2 / red edges / door reset.

## Dev back (debug builds only)
`dev_mode = OS.is_debug_build()` (editor runs and debug exports; never in release exports;
`--nodev` turns it off for testing). Every screen records a snapshot (flags, vars, items,
dossiers, window, tab locks, vessel map, O2, pinned response, passage + the chapter's
`_snapshot_extra()`) via `dev_push_screen(label, reenter)`: story passages in `goto()` (and a
choice without goto, which is a new pinned screen), and every THAW / EXAM screen in
`scenes/intro.gd` (THAW, THAW > YES/NO, EXAM 1-3, EXAM > NO1-4, > YES, recovery, DEATH).
Mouse wheel UP = `dev_back()`: stops all chapter VO / O2 countdown / fades / red edges
(`_dev_stop_chapter()`), restores the previous snapshot and re-enters that screen with its VO and
typewriter from the start. Logs `DEV BACK -> <screen>`. Wheel up over a text panel that can still
scroll up scrolls it instead (no modifier needed); one step per 0.3 s. Passages can opt out with
`"no_history": true` (the THAW / EXAM overlay records its own screens).

## Making a new chapter
1. Scene > New Inherited Scene > `res://templates/pda_screen.tscn`.
2. Attach a script that starts with `extends "res://templates/pda_screen.gd"` and fill
   `passages / dossiers / items / deck` in `_setup_story()` (see `scenes/intro.gd`).
3. Hooks: `_setup_story`, `_begin`, `_on_passage_entered`, `_custom_op`, `_debug_prepare`,
   `_debug_extra`, `_on_death_shown`, `_snapshot_extra` / `_restore_extra` / `_dev_stop_chapter`
   (dev back), and (PC) `_on_advance` for Space/Enter. If you override `_input`, call `super(event)`.

## Scene Writer (write scenes without code)
Editor plugin `addons/scene_writer/` (enabled in project.godot): a **Scene Writer** tab next to
2D / 3D / Script. Write a title + screens (typewriter text with `[error]`, `[error=ERROR]`, `[shake]`,
`[pause=1.0]`), red edges, whole-screen shake, optional VO with cue times (Auto-time from pauses /
Spread evenly), sounds, and an ending (CONTINUE / choices / death / O2 countdown / map walkthrough /
hold). Scene options: **Main game UI** (`"ui": "game"`: the screens type inside the main UI — header +
O2, tab rail, title, minimap — instead of the full-screen stage) and **Fade in** (`"fade_in"` seconds
from black). Live preview with the game's fonts and effects. **Build** writes `story/scenes/<id>.json` + `scenes/authored/<id>.tscn`
(inherits the template, script `templates/authored_scene.gd`); **Play** runs it.
Link into it from any passage with the op `scene:<id>` (or `go:scene:<id>/<screen>`); authored
scenes link back with `intro:home_bunk` etc. Full guide: **docs/SCENE_WRITER.md**. How to write a scene and hook it up: **docs/WRITING_SCENES.md**. Play order: **story/SCENE_ORDER.md** (chapter / scene / subscene, **NEXT**).
Authored-scene debug args: `--screen=ID --at=S --freeze --complete --pick=N --qte_left=S --no_fade
--open_map --tour_step=N|move --map_room=ID --map_click=ID` (`--open_map --map_click=ID` outside a
walkthrough = one free-walking click, e.g. a refusal shot; `--screen` past earlier screens applies
their map / flag / O2 ops, so the jumped-to screen looks like it does in play).

## Debug args (Project Settings > Run > Main Run Args, or after `--` on the command line)
They skip the title screen (see Title screen); `--skip_title` alone = the normal intro start.
`--jump=id` (default start is `thaw`) `--tab=deck --popup=dossier_id --plate`
`--boot=exam` (alias `--boot=callsign`: skip the THAW VO → exam name screen) `--lamp_step`
`--flags=a,b --callsign=NAME --pause --shot=C:/path/out.png [--shot_delay=1.2]`
`--thaw_at=SECONDS` seek VO/reveal; `--thaw_choice=yes|no` jump to a reply;
`--thaw_freeze` hold the reveal clock at `--thaw_at` (screenshots).
`--map_demo` mixed vessel-map states; `--open_map` open the full schematic;
`--map_hover=room_id` highlight a room in the open map.
MEMORY EXAMINATION (with `--jump=exam`): `--exam_screen=1|2|3|choices|yes|qte|death|dead|retry|recover`
(1 welcome, 2 name entry, 3 pinned name glitch + ERROR text; `qte`/`death` = O2 countdown, `dead` =
death screen, `retry` = screen 3 replaying as after RETRY), `--exam_no=1..4` (that NO reply, with its pinned question), `--exam_o2=S` (O2
countdown frozen at S seconds; S >= 10 = termination screen), `--exam_name=Text` (typed name / prefilled field), `--exam_at=S` (seek inside the section's WAV,
absolute seconds), `--exam_freeze` (hold that clock; the name glitch follows it).
Questions 2 + 3: `--exam_screen=q2|q2again|q2wrong1|q2wrong2|q2correct|archive|q3|q3yes|q3no|function|covered|not_covered|space_madness|space_madness_no|special_note|complete|docked|black`
(`covered` = pinned `> YES` like the real YES path, `space_madness_no` = pinned `> NO`; `--exam_at=S --exam_freeze` works here too,
(`--exam_complete` = that screen already finished; `--exam_yes` = YES variant of a later screen).
e.g. `--exam_screen=covered --exam_at=14.5 --exam_freeze` = two icon squares shown).

`--choose=N` press choice N right after `--jump` (runner pinned-response check).
`--die[=MESSAGE]` open the generic death screen. `--nodev` disable dev back (mouse wheel) in a debug run.

`--shot` saves the rendered frame to a PNG after the delay and quits (layout checks).
Debug args belong to the scene the run starts in: after a scene change (e.g. the exam → EXCURSION 1
PREP) only `--shot` (at its original time) and `--nodev` carry over, so
`--jump=exam --exam_screen=black --shot=… --shot_delay=12` captures the new chapter.
Audio buses: Master → Music (ambience), Sfx, Voice (VO). Ambience ducks −8 dB while VO plays.

## Vessel map
The REC-7 vessel schematic is data-driven (`data/vessel.gd` + `ui/ship_map_view.gd`).
Rename the ship in **one place**: `Vessel.VESSEL_NAME` / `VESSEL_TITLE`.
Ops: `map_explore:id`, `map_set_room:id`, `map_lock_room:id`, `map_unlock_room:id`,
`map_unlock_door:a|b`, `map_lock_door:a|b`, `open_map`, `map_know_room:id` (name known, not explored:
dark room with a dim label), `map_know_door:a|b` (door drawn before either side is explored),
`map_moves:on|off` (click-to-move), `map_restrict_room:id` / `map_unrestrict_room:id` (RESTRICTED:
dark room, red outline + a RESTRICTED stamp that pops in (scale + fade + red flash) on every map view;
the legend gains RESTRICTED), `o2_full`. Passages may set `"map_room": "stasis_3"`.
Rooms: STASIS-3 (start, explored), **READY ROOM** (the big room above STASIS-3; the mockup called it
COMMISSARY), **AIRLOCK** (the grey L on the left; was PORT ACCESS, then briefly READY ROOM), STBD HOLD,
AFT PORT, AFT STBD. Doors: STASIS-3 | READY ROOM open (one click), READY ROOM | AIRLOCK **locked**,
READY ROOM | STBD HOLD **locked** (both padlocked as in the mockup: KEYCARD REQUIRED).
**Click-to-move** (`vessel_map.click_to_move`, set by `map_moves:on`): clicking a room on the full map
moves you there if it is next to your room through an OPEN door (explored, dot moves, quiet door
sound, signal `map_moved(id)`); otherwise the info line shows `NO ACCESSIBLE PASSAGE` (no door),
`KEYCARD REQUIRED` (locked door / room), `RESTRICTED` (restricted room) or `YOU ARE HERE`, in amber, and you stay put
(`map_try_move`, `map_move_refusal`). The intro never moves the player (`_allow_map_moves()` = false).
`map_lock_open(true)` keeps the full map open (no Close button; M / Esc / clicking outside ignored).
The ship state (`vessel_map`) now carries across scene changes with flags / vars / items / O2.
Minimap sits under ACTIONS (collapses when many choices need the column); full map is a modal (M / Esc).
Extra read-only views: `ShipMapView.interactive = false` (mouse ignored) + `register_map_view(view)`
so they refresh with the ship state. The intro overlay shows one bottom-right (RSV ABEYANCE,
STASIS-3 current) during THAW / EXAM; the NO4 door lock / recovery unlock is visible on it.

## Memory Examination (after the THAW reply)
Script + measured cue times: `data/memory_exam.gd` (`MemoryExam`, editable `[start, "text", end]` lists,
same format as the THAW cues). VO: `assets/sounds/memorytest1.wav` (screens 1-5, played in windows
`MemoryExam.WINDOWS`), `memorytestA` (YES), `memorytestB1..B4` (NO1..NO4), `memorytest1C` (recovery).
A section whose WAV is missing still types out at `NO_VO_SILENT_CPS`.
THAW reply (pinned `> YES|NO`) → CONTINUE, then:
1. Welcome + "The Memory Examination will assess… Warning: … duties as assigned." (one screen, VO
   plays through) → CONTINUE.
2. Heading "Memory Examination" + "1) Do you remember your name?" + name field.
3. Pinned `1) Do you remember your name?` / `> <typed name>` — the name scrambles into ERROR when the
   VO reaches "The name ERROR" — then "The name ERROR is not the name we have on file… Please
   indicate that you understand." + YES/NO.
NO1 → NO2 → NO3 (each a new pinned screen, YES/NO again after each) → NO4: STASIS-3 door locks,
red vignette creeps in from the edges with the NO4 VO (`RED_NO4_START..RED_NO4_END`), then the O2
countdown (`MemoryExam.O2_SECONDS` = 10 s; red keeps intensifying to `RED_O2_END`). The only response
is NO WAIT, I UNDERSTAND, built exactly like the YES/NO buttons and sitting in the YES slot of the
RESPONSE list (220x34); its timer drains inside the button (faint fill + 3 px strip) and the header
reads `WINDOW CLOSING n.ns`. The shader keeps that slot legible (`keep_rect`). Pressing it → pinned
recovery screen → door unlocks, O2 refills and the red fades with the recovery VO → CONTINUE.
Timer expiry → O2 0% → fade → generic death screen (SIGNAL LOST / OPERATOR DECEASED) → RETRY
(screen 3 replays VO + typewriter, NO count restarts at NO1).
YES anywhere (or the recovery) → "Acknowledged, Operator." → CONTINUE → Question 2:
4. Heading + "2) Do you remember the mission of the REC-7 Corporation?" (`memorytest2`) + 3 answers.
   Wrong → pinned `> answer` + reply (`memorytest2A` / `2B`) → CONTINUE → Q2 again (all three answers,
   no punishment; `vars.exam_q2_wrong`). "Insurance?" → pinned "Correct. …" (`memorytest2C`) then
   "Would you like to know more?" (`wouldyouliketoknowmore`) → YES / NO.
   YES → pinned screen playing `MemoryExam.KNOW_MORE_VIDEO` (**video hook**: set a Theora `.ogv` path;
   empty = placeholder text "ARCHIVE FILE UNAVAILABLE") → CONTINUE → Q3. NO → Q3 pinned `> NO`.
5. Heading + "3) Do you remember your function…" (`memorytest3`) → YES / NO (flag
   `exam_remembered_function`). YES: pinned `> YES`, "Good." (`good.wav`) + the CLAIM OPERATOR paragraph
   (`memorytest3A`, with "(CED)"); NO: pinned `> NO`, same paragraph without "Good."/"(CED)".
6. Both CLAIM OPERATOR screens end with "Would you like to know more?" (`wouldyouliketoknowmore`, same
   clip as Q2) → YES / NO (flag `exam_heard_examples`). Wiring: `"know_more"` in `MemoryExam.TAIL_SCREENS`.
   YES → A: covered examples (`memorytestEXAMPLES_COVERED`, pinned "Would you like to know more?" / `> YES`)
   → CONTINUE → B: NOT covered examples up to "…recorded or recorded." (`memorytestEXAMPLES_NOT_COVERED`
   0 → `NOT_COVERED_SPLIT` = 17.85 s, the pause before "NOTE:") → CONTINUE → SPACE MADNESS screen (same
   WAV from 17.85 s to the end, `CUES_SPACE_MADNESS`, no pin).
   NO → the SPACE MADNESS screen directly, pinned "Would you like to know more?" / `> NO`.
   The WAV is split with from/to times inside the one file (the original stays intact).
   **Icon squares** on A and B: one square per example, count = length of the screen's id list
   (`ICONS_COVERED` = EX1-1..EX1-5 on A, `ICONS_NOT_COVERED` = EX2-1..EX2-4 on B), in a centred row placed
   `ICON_TEXT_GAP` (10 px) under where the FINISHED text ends (measured up front, so the row never moves
   while the text types or when CONTINUE appears). Placeholder = thin green outline, faint fill, dim mono
   id label. Each fades in while rising `ICON_RISE` px over `ICON_APPEAR_SECONDS` when the VO reaches its
   example (`ICON_TIMES_COVERED` / `ICON_TIMES_NOT_COVERED`, seconds into each clip, same length as the id
   list) and plays one quiet blip (`ICON_SFX` = `UI-2.mp3` at `ICON_SFX_DB` = -12 dB, Sfx bus).
   Skip, `--exam_complete`, seeking and dev back show them all in their final state without blips.
   **Adding icon art** (per id, either way; `ICON_ART` wins):
   - drop an image named after the id in `res://assets/icons/` (`EX1-3.png`, or .webp/.svg/.jpg) and let
     Godot import it: it is picked up automatically, or
   - set a path in `MemoryExam.ICON_ART`, e.g. `"EX1-3": "res://art/icons/pirates.png"`.
   With art the id label and the placeholder box are hidden and the texture fills the 64 px square
   (aspect kept); animation, timing and blip stay the same. More / fewer examples: edit the id list and
   its times together (and add the id to `ICON_ART`).
7. Then CONTINUE screens: special note, "Memory Test Complete…", "We are docked…" → CONTINUE → the whole
   game fades to black (`FADE_BLACK_SECONDS` 1.8 s), holds `AFTER_EXAM_HOLD` (1 s), then the time card
   **ONE HOUR LATER** (`AFTER_EXAM_CARD`, centred, Oxanium 24 px dim green) fades in `CARD_FADE_IN`
   (0.9 s), holds `CARD_HOLD` (2.3 s), fades out `CARD_FADE_OUT` (0.9 s), `CARD_AFTER` (0.4 s) of black,
   then **`MemoryExam.AFTER_EXAM` = `"scene:excursion1_prep"`** opens (it fades in from black itself).
   `AFTER_EXAM_CARD = ""` skips the card; `AFTER_EXAM = ""` stays black; a passage id (e.g. `"home_bunk"`)
   fades the black out into that passage.
Afterwards `{v:callsign}` = OPERATOR.
State: `vars.typed_name`, `vars.exam_no_count` (all NOs, all attempts), `vars.exam_died_count`,
`vars.exam_q2_wrong`, flags `exam_understood` (pressed NO WAIT, I UNDERSTAND), `exam_said_yes`,
`exam_q2_correct`, `exam_know_more`, `exam_remembered_function`, `exam_heard_examples`, `exam_done`, `exam_complete`.
Tests: `tools/key_test.gd`, `tools/exam_test.gd` (Q2/Q3, blips on both example screens, ONE HOUR
LATER timing), `tools/writer_test.gd`, `tools/excursion_test.gd`.

## EXCURSION 1 PREP (after the exam)
A Scene Writer scene: `story/scenes/excursion1_prep.json` → `scenes/authored/excursion1_prep.tscn`
(edit the text / tips in the Scene Writer tab or the JSON, then Build). `"ui": "game"`, `"fade_in": 1.5`.
1. **brief** — fades in from black inside the main game UI (title bar `EXCURSION 1 // PREP`, tab rail,
   header O2 full via `o2_full`, minimap). Types the OPERATOR paragraph + "Please proceed to the READY
   ROOM." (own paragraph). Voiced by `assets/sounds/Exursion1prep.wav` (the OPERATOR paragraph; the
   READY ROOM line is not in the clip and types after it). Four cues, one per voiced line (`+` lines keep
   one paragraph): 1.00–6.72, 7.19–8.78, 9.43–14.44, 14.91–17.14 s. The voice (and the typing) wait for
   the fade-in to finish. Its `on_enter` makes the READY ROOM + AIRLOCK names and the two side doors known.
2. **map** — ending `map_tour`: the full map opens (locked open) and the 7 tips play one at a time
   (`ui/map_tour.gd`): everything but the target dimmed, a pulsing amber bracket + outline around it, the
   tip in a small panel beside it (`TIP n/7`, CONTINUE 220x38). Targets: whole map + you dot, STASIS-3,
   STBD HOLD (dark), READY ROOM (dark + named), the STASIS-3 | READY ROOM door, the locked READY ROOM |
   STBD HOLD door, all rooms. Tutorial, so no pinned response. After tip 7 the dim goes, click-to-move
   turns on and the info line reads PLEASE PROCEED TO THE READY ROOM.; one click on the READY ROOM moves
   the player (refusals as above). Reaching it explores it (green) and moves the dot; 0.6 s later the
   walkthrough's `on_arrive` op `map_restrict_room:stbd_hold` pops RESTRICTED over STBD HOLD (door stays
   locked); the map closes 2.4 s after arriving.
3. **ready_room** — heading READY ROOM + a `TODO:` placeholder, ending `hold` (the chapter stops).
   Now (round 3): the room text names WINDOW, LOCKERS and COFFEE POT (green, body font, no exposition
   font); WINDOW opens a sub-screen whose RSV ABEYANCE link files a ship LOG entry; LOCKERS asks
   "Searching the locker will take 1 hr. Are you sure?" (Yes = 1 hr + fade, every search) with a 2-step
   time tip the first time; taking items and putting on the suit are free; the coffee pot brews once
   (1 hr) into a THERMOS OF COFFEE (Drink = next timed action 1 hr cheaper); items drag between the
   windows, out onto the map (dropped = a dot + name) and onto locks (the keycard has to be dragged onto
   the lock; clicking a lock only explains it). The game HUD has no menu button (Esc = pause); the O2
   and HRS bars are the same length. See docs/SCENE_WRITER.md section 7.
   Round 4: the WINDOW text is in the present tense; the LOG is a hologram pop-up with categories,
   search and a 3-step first-time tip; containers are drag-only (no Take); drag / drop tips run once
   with small animations; dropping, unlocking or revealing opens the full map (windows stay closed);
   loot / drop / unlock sounds come from assets/sounds; THERMOS, SUIT, LANTERN, keycards have art.
   Round 5: the rail is STA / INV / LOG / MAP (STA = the room text, TAB cycles down); items dragged
   out of the inventory stick to the cursor and act on the next click.
   Its `on_enter` repeats `map_restrict_room:stbd_hold` (no second pop; keeps `--screen=ready_room`
   jumps right). Afterwards the map: STBD HOLD → RESTRICTED, AIRLOCK → KEYCARD REQUIRED, STASIS-3 open.
   **Next-chapter hook**: set the scene's "When it ends" (`"after"`) or the hold ending's target and the
   holding screen shows CONTINUE.
Map moves stay on for the rest of the chapter (the minimap opens the full map; Close works again).
Dev back steps through every tip, the walk phase and the holding screen.
Death FX: `shaders/suffocate.gdshader` (desaturate + vignette + red edge ring `red` + chromatic wobble +
fade, `keep_rect` = legible RESPONSE slot), text shake,
low-pass on the Music bus, heartbeat = UI-1.mp3 pitched down; doors = airlockdoor.mp3 / dooropen.mp3 (no new audio files); icon squares = UI-2.mp3.

## Windows build (shareable .exe)
`export_presets.cfg` has one preset, **Windows Desktop**: x86_64, PCK embedded (one .exe), console
wrapper only for debug exports, product name "Space Horror", version 0.2.0.0 (0.1.0 = before the title screen, 0.1.1 = title screen, 0.2 = ready room items / windows), icon = the project icon
(`icon.svg`, converted by Godot; no rcedit needed). Filters: all resources + `story/scenes/*.json`
(the Scene Writer scenes are read with FileAccess at runtime); `tools/*`, `docs/*`, `addons/*` and `README.md` are left out. `story/SCENE_ORDER.md` is included. Needs the Godot **4.6.3** export templates (Editor > Manage Export Templates, or
`%APPDATA%\Godot\export_templates\4.6.3.stable\`). Export with the 4.6.3 editor (what the tests use):
```
Godot_v4.6.3-stable_win64_console.exe --headless --path "D:\Game Projects\space-horror-pc" --export-release "Windows Desktop" "D:\Game Projects\space-horror-pc-builds\0.2\SpaceHorror.exe"
```
Then zip `SpaceHorror.exe` alone (`SpaceHorror-0.2-windows.zip`). Release exports have no dev back
(`OS.is_debug_build()` is false) and ignore every debug arg (`_read_debug_args()` returns nothing).
The .exe is unsigned: Windows SmartScreen shows "Windows protected your PC" the first time (More info >
Run anyway). Bump the version in the preset (`application/file_version` / `product_version`) and the
output folder for the next build.

## Files
- `scenes/title.*` title screen (boot scene): REC-7 logo, PLAY, QUIT. Debug PLAY opens the mission select; release PLAY opens the intro.
- `scenes/mission_select.*` debug mission select: one button per scene in `story/SCENE_ORDER.md` (INTRO, READY ROOM), then BACK.
- `templates/` PdaScreen template (scene, script, theme).
- `scenes/intro.*` INTRO chapter (STASIS THAW VO → MEMORY EXAMINATION Q1-Q3 → fade to black → ONE HOUR
  LATER → EXCURSION 1 PREP), DRAFT prose.
- `data/memory_exam.gd` exam script text, cue times, tunables (O2 timer, name length, glitch timing).
- `data/vessel.gd` vessel name + schematic. `ui/ship_map_view.gd` map drawer (`interactive` flag,
  `room_clicked`, geometry helpers). `ui/map_tour.gd` HIGHLIGHT + TIP map walkthrough overlay.
- `ui/o2_bar.gd` OXYGEN bar (header + intro overlay).
- `shaders/screen_refresh.gdshader` code-drawn CRT refresh sweep (background `Screen` rect).
- `shaders/suffocate.gdshader` exam oxygen-loss post effect.
- `addons/scene_writer/` Scene Writer editor plugin (`plugin.gd`, `writer_panel.gd` UI,
  `scene_builder.gd` JSON + .tscn builder, `vo_timing.gd` WAV pause detection). Guide: `docs/SCENE_WRITER.md`.
- `ui/story_markup.gd` (StoryMarkup: markup parser / typing times / effect bbcode),
  `ui/story_stage.gd` (StoryStage: plays one authored screen; game + editor preview),
  `ui/story_scene.gd` (StoryScene: load / normalize / validate / save scene JSON).
- `templates/authored_scene.gd` + `.tscn` runner for Scene Writer scenes. `story/scenes/*.json` scene data
  (`excursion1_prep.json` = EXCURSION 1 PREP, `new_scene_2.json` = the ready-room scene on the outline), `scenes/authored/*.tscn` built scenes.
- `tools/key_test.gd` keyboard / intro test, `tools/exam_test.gd` exam Q2/Q3 + examples test, `tools/writer_test.gd` Scene Writer test,
  `tools/excursion_test.gd` EXCURSION 1 PREP + map walkthrough + click-to-move test,
  `tools/title_test.gd` title screen test, `tools/mission_test.gd` mission select test (all headless).
- `assets/rec7_logo.png` REC-7 logo (title screen).
- `assets/fonts` IBM Plex Sans/Mono, Oxanium (+ OFL licenses). `assets/sounds` UI-1..7, shipwelcome*, memorytest*.

Round 6: STASIS-3 walkable from the ready room (placeholder room), locker search paid once, EXIT on inventory and full map (bottom right), AIR LOCK name stamp-in on unlock, placeholder AIR LOCK scene (EXCURSION 1) reached by the airlock door with a fade, drop tips open the map only on the last tip, WINDOW marker on the full map returns to the room text.

Round 7: room screens drop the scene title; every room move is a ROOM TRANSITION (fade + door sound, text types fresh; airlockdoor sound for the airlock); dynamic menu (rail starts STA only in EXCURSION 1 // PREP, MAP/minimap revealed by onboarding, INV earned on the first locker opening, LOG hidden; TAB/hotkeys only reach revealed buttons); onboarding tips STATUS → MAP (click minimap → map tour) → MENU; inventory tutorial (Inventory → Character → EXIT, no X); locker: orange marker until searched, search spends the hour then time tips, click again to open; holo FX + window-green maps; room labels run along the shared door edge (west −90°, east +90°), RESTRICTED stamp too.
