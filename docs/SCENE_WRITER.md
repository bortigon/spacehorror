# Scene Writer — write scenes without code (or AI)

Short version (write a scene, put it next in the game, tag it for the debug mission select): **docs/WRITING_SCENES.md**.

The Scene Writer is a tab inside the Godot editor. You type a scene (title, screens of text, effects,
choices, death, voice lines), watch it in a live preview, and press **Build**. It writes:

| File | What it is |
|---|---|
| `story/scenes/<id>.json` | Your scene as plain text data. The game reads this. You can also edit it by hand. |
| `scenes/authored/<id>.tscn` | A Godot scene built from the PDA template that plays the JSON. Never edit it — Build rewrites it. |

Everything follows the game's UI rules automatically: after every response a NEW screen opens with the
question and your chosen response pinned at the top, there are no key hints anywhere, and the O2
countdown button sits exactly where (and is exactly as big as) the first choice button.

---

## 1. Open the tool

1. Open the project in Godot (4.6 or the Steam 4.7 editor — both work).
2. The plugin is already switched on. If you don't see it: **Project → Project Settings → Plugins**,
   tick **Scene Writer** → *Enable*.
3. Click **Scene Writer** in the top bar (next to 2D, 3D, Script, Game, AssetLib).

The tab has three columns:

* **Left — SCENE:** id, title, **Dev skip**, text speed, background, ambience, HUD, what happens when the scene
  ends, and the **SCREENS** list (Add / Duplicate / Delete / Up / Down).
* **Middle — SCREEN:** the selected screen: text + effect buttons, **Dev skip**, effects, voice, sounds, ending.
* **Right — PREVIEW + CHECKS:** the screen rendered with the real game fonts and effects, and a list
  of problems (click a problem to jump to its screen).

Top bar: **New**, the scene list + **Open**, **Save**, **Build**, **Play**, and a status line.

---

## 2. Write a scene, step by step

1. **New.** Type a **Scene id** — this becomes the file name, e.g. `cargo_bay` (only a–z, 0–9 and `_`;
   anything else is fixed for you).
2. **Title** — shown dim at the top of every screen, e.g. `REC-7 // CARGO BAY`.
3. **Text speed** — how fast text types, in characters per second (38–45 feels like the intro).
   The number next to the slider is the live value.
4. Optional: **Background** (e.g. `assets/space.png`) and **Background dim** (how visible it is),
   **Ambience** (a looping sound; "game default" = the ship hum), **Show O2 bar + minimap**.
   **Main game UI (tab rail + map)** — on: the screens type inside the game's main UI (header with
   O2, LOG / DECK / LOCKER / KIT tabs, the scene **Title** in the title bar, the minimap under the
   story; the full map opens) instead of the full-screen story stage. Needed for a map walkthrough.
   **Fade in (s)** — the scene fades in from black when it opens (0 = no fade); the text starts
   typing once the fade is done.
5. **When it ends** — where the game goes after the last screen if that screen just says
   "Next screen", and where a Hold goes if its **CONTINUE goes to** is left on "(stop here / When it ends)".
   **New** sets this to **NEXT**: the next subscene in `story/SCENE_ORDER.md` (chapter / scene / subscene;
   see `docs/WRITING_SCENES.md`). **SCREENS** is that list: **Chapter**, **Scene**, then the subscenes.
   **Add** puts a new subscene there. **Earlier** / **Later** reorder it. **On the list** files the open screen under the scene you picked. Reordering does not need a Build. A new scene still
   needs one Build. If nothing follows, the game shows "The next scene isn't written."
6. Write the first screen in the big text box. **One line per sentence** (or per voice line).
   An empty line makes a paragraph gap.
7. **Add** more screens. Click a screen in the list to edit it. **Up/Down** reorders,
   **Duplicate** copies (handy for "same screen, different ending").
8. Pick how each screen ends (section **ENDING**, see §4).
9. Watch the **PREVIEW**: it shows the finished screen while you type. **Replay** plays it from the
   start with typing, voice and effects; **Skip** finishes the typing (like Space in the game). You
   can click the preview's buttons — the preview follows choices / CONTINUE to the next screen.
10. **Save** (writes the JSON) or **Build** (saves + makes the .tscn). **Play** builds and runs it.

Nothing is lost if you switch tabs. If you open or start another scene with unsaved changes, the tool
asks first.

---

## 3. Effects

### Text effects (buttons above the text box)
Select some text, then press a button. The button wraps your selection in a short tag. You can also
type the tags yourself.

| Button | Tag you get | What the player sees |
|---|---|---|
| **ERROR glitch** | `[error]CORRUPTED[/error]` | The word scrambles (`#%&@!?`) while it types, then settles in amber, with a tiny flicker every few seconds. Works on any word, not just ERROR. |
| **Becomes:** `ERROR` | `[error=ERROR]ALEX[/error]` | "ALEX" types normally, stays for a moment, then scrambles into "ERROR" (the name effect from the Memory Examination). Change the word in the box next to the button. |
| **Shake** (level) | `[shake]text[/shake]` or `[shake=12]text[/shake]` | Shaky text. Level 1–20 (default 6). |
| **Pause** (seconds) | `[pause=1.0]` | Typing stops for that long at that spot. |
| **Bold / Italic** | `[b]…[/b]` / `[i]…[/i]` | Bold / italic. |
| **Remove effects** | — | Removes the tags inside the selection. |

Also:
* **Empty line** = paragraph gap. **New line** = line break.
* A line that **starts with `+`** stays in the same paragraph as the line above (it's still its own
  voice cue — useful when a voice line splits a sentence).
* `{v:callsign}` inserts a game value (e.g. OPERATOR). `{flag:x?shown if x|shown if not}` works too.
* Any other `[` is shown as a normal character.
* Tags are coloured green in the text box; problems like a missing `[/error]` show up in CHECKS.

### Screen effects (section EFFECTS)
* **Speed override** — this screen types at its own speed ("scene speed" = use the scene's).
* **Whole-screen shake** — the whole text shakes (0 = off, 1–20).
* **Red edges** — red creeping in from the screen edges:
  * **Off** — none (any red from the previous screen fades out smoothly).
  * **Static** — a fixed amount (**Red level**, 0–100 %).
  * **Ramp** — grows from **Red at the start** to **Red at the end** while the text types.
    If the player skips the typing, it jumps to the end value.
* **Pinned question** — after the player answers this screen, the next screen shows this line dim and
  their answer bright at the top. Leave it empty to use the last line of the screen automatically.

### Voice (section VOICE, optional)
1. Pick a **Voice clip** from `assets/sounds`. (Put new recordings in that folder first.)
2. **Play from / to** — use part of a long recording (to = −1 means "to the end").
3. Give each text line its time in the clip, one line per text line: `start - end` in seconds,
   e.g. `1.09 - 3.16`. Each line types across its time, so text and voice stay in sync.
   * **Auto-time from pauses** (WAV only) listens for the pauses in the recording and fills in the
     times for you. It uses the length of each text line to decide which pauses are line breaks.
     On the game's own recordings it lands within 0.3 s for about 8 lines out of 10; the rest
     come out up to a couple of seconds off (usually because the recording has an extra breath or
     word, or two lines are spoken at very different speeds). **Always press Replay and listen**,
     then fix a time by hand if a line is early or late.
   * **Spread evenly** shares the clip between the lines by length (works for MP3/OGG too). Adjust
     by hand after.
   * **Clear times** — no times: the text types at the screen speed while the voice plays.
   * Lines without a time (more text lines than times) type after the last timed line at the screen
     speed. The status line under the box counts lines vs. times.
4. Pressing Space / clicking during the voice finishes the text and stops the voice (same as the
   intro).

### Sounds (section SOUNDS, optional)
**Add sound** → pick a sound, then **when line starts** (line number, 1 = first line) or
**after seconds** (from the start of the screen).

---

## 4. Endings

Pick one in **Screen ends with**:

* **CONTINUE button** — one CONTINUE button → **CONTINUE goes to** (next screen, any screen, another
  scene, or an intro passage). No pinned response after CONTINUE.
* **Choices** — one row per choice: the **choice text**, **where it goes**, and optional **ops**
  (game actions, comma separated, e.g. `set_flag:brave, give_item:worklamp`). **Add choice** adds a
  row, **✕** removes one. The next screen pins the question + "> your choice".
* **Death** — the screen types its text, waits a moment, then shows the game's death screen:
  **Heading** (default SIGNAL LOST), **Message** (default OPERATOR DECEASED), and **RETRY goes to**
  ("the screen before" = the screen whose choice led here, or pick any screen/target).
* **O2 countdown (quick-time)** — after the text, one button (**Button text**) and a timer
  (**Seconds**). The O2 bar drains in steps, the red edges close in, a heartbeat speeds up.
  * Pressed in time → **In time goes to** (next screen gets the pinned "> button text"; O2 refills).
  * Too late → death screen with **Too late message**; **RETRY goes to** ("this screen again" or any
    target).
* **Map walkthrough (HIGHLIGHT + TIP)** — after the screen's text (leave the text empty to open
  it straight away) the full ship map opens and stays open, and the tips play one at a time: the
  rest of the map dims, a pulsing bracket + outline marks the target, and the tip text sits in a small
  panel beside it with CONTINUE (`TIP 1/7`, `TIP 2/7`, …). One row per tip: the **target** dropdown,
  the **tip text**, **✕** removes it; **Add tip** adds one. Targets: *Whole map + you-are-here dot*,
  *All rooms*, *Room: …*, *Door: … / …*.
  * **Then walk to** — a room: after the last tip the dim goes away, clicking rooms moves the player
    (only to a room next door through an open door; otherwise NO ACCESSIBLE PASSAGE / KEYCARD REQUIRED)
    until they reach that room. "(no walking)" = straight on after the last tip.
  * **Walk prompt** — shown in the map's info line while they walk (e.g. "Please proceed to the READY ROOM.").
  * **On arrival (ops)** — state ops (comma-separated) run on the still-open map when they arrive,
    e.g. `map_restrict_room:stbd_hold` pops a RESTRICTED stamp over that room (the ready room no longer uses it: the stamp appears when the player clicks that room's lock). The map then stays
    open a little longer (2.4 s instead of 0.9 s) so the player sees it.
  * **Then goes to** — where the game goes once they arrive (usually Next screen).
  Walkthroughs are tutorials: no pinned response afterwards. Dev back steps through the tips.
* **Hold (the scene stops here)** — the screen types and stays. **CONTINUE goes to** empty = no button
  (a chapter end / placeholder); pick a target (or set the scene's **When it ends**) and a CONTINUE
  button appears — that is the hook for the next chapter.

### Where a target can go
| In the dropdown | In the JSON | Means |
|---|---|---|
| NEXT | `order:next` | the next screen in `story/SCENE_ORDER.md` (nothing after it: "The next scene isn't written.") |
| Next screen | `next` | the next screen in this scene (after the last one: the scene's "When it ends") |
| Screen: vent | `vent` | a screen in this scene |
| Scene: cargo_bay | `scene:cargo_bay` | another Scene Writer scene (`scene:cargo_bay/s3` = start at screen s3) |
| Intro: home_bunk | `intro:home_bunk` | a passage in the intro chapter (home_bunk, home_lock, home_airlock) |
| (by hand) | `tscn:res://scenes/x.tscn` | any Godot scene |

Flags, values (like the callsign), items, O2 and the ship map carry over when the game moves between scenes.

---

## 5. Build and Play

* **Save** — writes `story/scenes/<id>.json` only.
* **Build** — saves, then writes `scenes/authored/<id>.tscn` and refreshes the FileSystem dock.
  Build refuses while CHECKS shows **ERROR** lines (notes are fine). Fix them and Build again.
* **Play** — Build, then runs the built scene (like F6 on that scene).
* Rename = change the **Scene id** and Save/Build — it makes a new file; the old one stays (delete it
  in the FileSystem dock if you don't need it).
* CHECKS looks for: missing targets, empty screens, choice rows without text, missing voice/sound
  files, unclosed tags, more voice times than text lines, a last screen that continues into nothing,
  walkthrough tips without text or with a target that is not on the map, a "walk to" room that does
  not exist, a Hold screen that is not the last one.

---

## 6. Hook your scene into the story

From any passage in a chapter script (e.g. `scenes/intro.gd`), add a choice with the op
`scene:<id>`. Example — in `home_bunk`'s `"choices"`:

```gdscript
{"label": "Check the cargo bay", "ops": ["scene:cargo_bay"]},
```

The game switches to your built scene (keeping flags, callsign, items and O2). To come back, set a
target like `intro:home_bunk` on the last screen (or as the scene's **When it ends**).
From one Scene Writer scene to another, just pick **Scene: …** as a target.
Other ways: the op `go:scene:cargo_bay/s3`, or in code `go_target("scene:cargo_bay")`.

You can also make your scene the first thing the game shows: Project Settings → Application → Run →
Main Scene → `res://scenes/authored/<id>.tscn` (put it back to `res://scenes/title.tscn`, the title screen, afterwards).

Test tip (debug runs): mouse-wheel UP steps back one screen (dev back), same as the intro.

**Dev skip** (the **Dev skip** line on the scene, and the one on a screen) is only for the debug
mission select. Put a button label there and that scene — or that one screen — shows up as a row
the next time you PLAY from the title in a debug build. Blank means not listed. A scene label starts
the scene (`scene:<id>`); a screen label opens that screen (`scene:<id>/<screen>`). The **INTRO** row
is not one of these: it is built into the menu and lands after the map tour, waiting for the READY ROOM
click. Release builds never show the menu.


---

## 7. Hand-editing the JSON

You can open `story/scenes/<id>.json` in any text editor. Keep the quotes and commas; `\n` inside a
text is a new line. Missing fields get their defaults. Example (shortened from the sample):

```json
{
  "format": 1,
  "id": "sample_scene",
  "title": "SAMPLE SCENE // SCENE WRITER DEMO",
  "speed": 38,
  "background": "res://assets/space.png",
  "background_alpha": 0.12,
  "ambience": "",
  "show_hud": true,
  "after": "intro:home_bunk",
  "screens": [
    {
      "id": "file",
      "heading": "",
      "text": "REC-7 has your file open.\nThe name [error=ERROR]ALEX[/error] is not the name we have on file.\nDo you want to continue?",
      "speed": 0,
      "shake": 0,
      "red": {"mode": "static", "from": 0.15, "to": 0.15},
      "vo": {"clip": "", "from": 0.0, "to": -1.0, "cues": []},
      "sfx": [],
      "question": "",
      "end": {"type": "choices", "choices": [
        {"label": "YES", "goto": "vent", "ops": ["set_flag:sample_said_yes"], "if": ""},
        {"label": "NO", "goto": "refuse", "ops": [], "if": ""}
      ]}
    }
  ]
}
```

Field by field:

| Field | Meaning |
|---|---|
| `speed` | characters per second (scene); screen `speed` 0 = use the scene's |
| `shake` | whole-screen shake 0–20 |
| `red` | `mode` off / static / ramp, `from` / `to` 0.0–1.0 |
| `vo` | `clip` (res:// path), `from` / `to` seconds (to −1 = end), `cues` = `[[start, end], …]` one per text line |
| `sfx` | list of `{"clip": "res://…", "line": 2}` or `{"clip": "res://…", "at": 1.5}` |
| `question` | pinned question after a response ("" = last line of the screen) |
| `end` | `{"type": "continue", "goto": "next"}` · `{"type": "choices", "choices": [...]}` · `{"type": "death", "heading": "", "message": "", "retry": ""}` · `{"type": "qte", "label": "", "seconds": 8, "goto": "", "fail_message": "", "retry": ""}` · `{"type": "map_tour", "tips": [{"text": "", "target": "map"}], "move_to": "ready_room", "move_prompt": "", "on_arrive": [], "goto": "next"}` · `{"type": "hold", "goto": ""}` |
| tip `target` | `map` (whole map + you dot) · `rooms` (every room) · `room:<id>` (e.g. `room:stasis_3`) · `door:<a>\|<b>` (e.g. `door:ready_room\|stbd_hold`); room ids are in `data/vessel.gd` |
| scene `ui` | `"stage"` (default, full-screen story stage) or `"game"` (inside the main game UI) |
| scene `fade_in` | seconds of fade from black when the scene opens (0 = none) |
| choice `if` | only show the choice when a flag is set: `"brave"`, `"!brave"`, `"a,b"` |
| screen `on_enter` | (hand-edit only) list of ops run when the screen opens, e.g. `["set_flag:saw_bay"]`. Map / state ops: `map_set_room:id`, `map_explore:id`, `map_know_room:id` (name shown, still dark), `map_know_door:a\|b`, `map_unlock_door:a\|b`, `map_lock_door:a\|b`, `map_moves:on\|off`, `map_restrict_room:id` / `map_unrestrict_room:id`, `o2_full` |
| walkthrough `on_arrive` | ops run when the player reaches `move_to` (same ops as `on_enter`), e.g. `["map_restrict_room:stbd_hold"]` |

### Acts: functions and containers

A screen's `acts` is a dictionary keyed by the id in `[act=id]word[/act]`. Two kinds:

```json
"acts": {
  "bag": {
    "text": "A bag of chips.",
    "choices": [{"label": "Take bag of chips?", "hours": 1, "item": "chips", "detail": "", "required": false}]
  },
  "locker": {
    "container": true,
    "title": "LOCKER",
    "text": "description lines shown under the title",
    "grid": {"cols": 3, "rows": 3},
    "items": [
      {"id": "suit", "label": "SUIT", "hours": 0, "required": false, "detail": "Pressure suit. Put it on before you go outside.", "actions": ["take"]},
      {"id": "lantern", "label": "LANTERN", "hours": 0, "required": false, "detail": "Light.", "actions": ["take"]},
      {"id": "airlock_keycard", "label": "AIRLOCK KEYCARD", "hours": 0, "required": false, "detail": "Opens the airlock door.", "actions": ["take"]}
    ],
    "search": {"hours": 1, "text": "Searching the locker will take 1 hr. Are you sure?"},
    "marker": {"room": "ready_room", "label": "LOCKER", "rect": [0.03, 0.05, 0.24, 0.17]}
  },
  "coffee": {
    "station": "coffee",
    "title": "COFFEE POT",
    "text": "The coffee pot is empty and cold. ...",
    "marker": {"room": "ready_room", "label": "COFFEE POT", "rect": [0.65, 0.05, 0.32, 0.17]}
  },
  "window": {
    "text": "You step over to the window ... the [act=abeyance]RSV ABEYANCE[/act] ...",
    "choices": [],
    "marker": {"room": "ready_room", "label": "WINDOW", "rect": [0.33, 0.05, 0.29, 0.17]}
  },
  "abeyance": {
    "text": "RSV ABEYANCE - The RSV ABEYANCE is ...",
    "choices": [],
    "log": {"id": "abeyance", "title": "RSV ABEYANCE", "filed": "SHIP LOG"}
  }
}
```

- No `container` key: a **function**. Clicking the word replaces the screen text with `text` and shows `choices` plus an automatic Back that returns to the caller's text (functions can nest: WINDOW -> RSV ABEYANCE -> Back -> Back). A function may have a `marker` too (the WINDOW box opens the sub-screen from the map).
- `"log": {"id", "title", "filed", "category"}` on an act: clicking it files a LOG entry once (its `text` is the entry; `vars.log_entries`, also filed as a dossier with a "FILED: <title>" line) and opens the LOG pop-up on it (the story text stays). Without the game UI it reads as a function with Back.
- `"search": {"hours": 1, "text": "..."}` on a container: clicking it asks Yes / No first. Yes spends the hours (every opening is a new search), fades to black and back, then opens the window. The first time any such prompt appears, a 2-step tip runs before the player can answer ("TIP: Some actions require Time." on the "1 hr", "Missions are limited to 8 Hours." on the time bar; flag `tut_time_done`).
- `"container": true`: a **window**. `ui/container_window.gd` opens centred, with the character screen (`ui/character_screen.gd`) beside it. `title` is top-left, `text` is the description under it (the left column, about 40 % of the window, no scroll bar: the font shrinks to fit), the rest is a `cols` x `rows` grid (1–8 each) of the `items`, filled in order (an item may pin a cell with `"slot": n`, 0-based). There is no Back: EXIT / Esc closes it.
- Item: `id` (inventory id; Take sets the flag `has_<id>`, which `require` and the lantern light check), `label` (cell name, description, button `Take LABEL`), `hours` (0 in the ready room: taking is free; if set, shown on the button and really spent from the 8 hour blocks; refused with a short message when too few are left. Blocks are live once a screen runs `arm_hours`, as the ready room does), `required`, `detail` (description + hover tip), `actions` (default `["take"]`). `take` is the only built-in action. Others (`use`, `inspect`, or any name) get a button `Use LABEL` and emit `action_requested` on the container window, so they can be handled later without changing the data.
- Description paragraphs (lines) always show with one empty line between them.
- Drag and drop: drag an item from the container onto the character screen to take it, or from the character screen into the container to put it in (it stays there: `vars.container_items.<act>`; a full grid says NO ROOM). Drag it out of all windows and the windows hide while the item stays on the cursor: let go over the room or map = drop it on the floor; over a lock = use it (the right keycard unlocks, anything else says "That doesn't work."); over a room box (LOCKER, COFFEE POT, WINDOW) = "Nothing happens."; back over a window, Esc or right click = it returns. Chapters can override `_use_item_hook(target, item_id)` for puzzles (targets `door:a|b`, `marker:<id>`).
- An old container written with `choices` instead of `items` still loads (one item per choice). Without a window (the Scene Writer preview) a container reads as the function form.
- `"marker": {"room", "label", "rect": [x, y, w, h]}` on an act adds a green labelled rectangle to that room on the minimap and full map (rect = fractions of the room's bounding box). Clicking it opens the same window as the green word. Dropped items are drawn as a dot with the name beside it (rows at about 27 %, 40 % and 78 % of the room height), so keep boxes in the top 22 %.
- `"station": "coffee"` (instead of `container`) is a **station**: a window of the same hologram style with a picture and code-defined options (`ui/station_window.gd`; the coffee pot is in `templates/pda_screen.gd`: `coffee_provider()` / `coffee_option()`). The Scene Writer shows it as an act it cannot edit; leave it alone. The coffee pot: "Brew coffee (1 hr)" once (fade out and back), then the player has a THERMOS OF COFFEE and the pot says "The pot is empty.". Drinking the thermos (character screen, Drink) makes the next action that takes time 1 hr cheaper (`vars.free_hours`). State: `vars.coffee = {brews, brewed, disabled, ...}`; `coffee_set_disabled(true)` removes the options ("MACHINE DISABLED") for a later pass.
- A `hold` ending with `"exit": "door:ready_room|airlock"` has no CONTINUE: the scene is left by clicking that door on the map once it is open (no suit worn = a Yes / No warning first, `flags.went_without_suit`). `goto` is where it leads (`order:next`).
- Items, the character screen and the map: the character screen offers **Drop** for every item (free; the item sits on the room floor, shown as a dot + name on the map, state `vars.dropped`) and **Put on** for the suit (free, fade + zipper, `vars.suit_worn`, the suit leaves the inventory, the figure turns green). Locked doors in `data/vessel.gd` take `key` (item id), `key_name` (shown as "Requires <key_name>"), `behind` (room named when opened) and `fail: "restrict"` (the RESTRICTED stamp appears when the lock is clicked). Clicking a lock never unlocks it: the keycard has to be dragged onto it. Opened doors are kept in `flags.door_open_<a>_<b>`.
- Round 4: containers have **no Take button** (drag and drop only) and a fixed-size, fixed-font description (scrolls if long). While an inventory item is dragged out over the room the cursor label reads `DROP <ITEM>` (over a lock / room box `USE <ITEM>`). Whenever the map is added to (an item dropped, a door unlocked, a room revealed) the windows close and the full map opens (`show_map_change()`); searching a container does not. Sounds (assets/sounds): loot = `UI-3.mp3`, drop (floor or container) = `UI-5.mp3`, unlock = `unlock.wav` latch + `dooropen.mp3`. Items THERMOS OF COFFEE, SUIT, LANTERN and keycards have code-drawn icons (`ui/item_icons.gd`).
- The **LOG** is a hologram pop-up (`ui/log_window.gd`, opened by the LOG tab and by `log` acts such as RSV ABEYANCE, which select their entry): categories on the left (SHIP, COMPANY, TUTORIALS, any other `category` an act's `log` names), the entry on the right, a "Search Log" bar that filters by title and text, EXIT / Esc. REC-7 Corporation (COMPANY) is listed from the start; a TUTORIALS entry (Map, Containers, Items, Doors, Time, Moving Rooms) appears once its tip has been seen. Tips that run once each: log (first LOG), drag (first container window), drop (right after the first item dropped on the floor), time (first time prompt).
- Round 5, the game tab rail: **STA, INV, LOG, MAP** (top to bottom). STA is the main state: the room text with nothing else up (selecting it closes every window and the full map). INV = character screen, LOG = the LOG pop-up, MAP = the full map. The open screen's tab is lit. TAB (or E) goes down the rail and wraps, Shift+Tab (or Q) goes up; I or C = inventory (beside a container they only toggle the character screen); M = map; Esc closes the top window. Nothing on screen names these keys except the time tutorial's third tip ("TIP: Cycle through your TRM-CUFF by clicking this menu or hitting TAB.", also the TRM-CUFF log entry).
- Sticky drag: an inventory item dragged out of the windows closes them and sticks to the cursor; letting go does nothing, the next CLICK drops it (room / map) or uses it (a lock or target). Esc / right click returns it. Drags between the container and inventory grids are normal drag and drop.

After a hand edit, open the scene in the Scene Writer and press **Build** (or just run it — the built
`.tscn` reads the JSON every time, so text changes show up without rebuilding).

---

## 8. The sample

`tools/fixtures/writer_demo.json` is a test fixture, not a story scene (it is not on the outline and has no built scene).
It uses everything once:

1. **wake** — heading, typewriter at the scene speed, `[pause]`, inline `[shake]`, a sound on line 3,
   CONTINUE.
2. **file** — `[error=ERROR]ALEX[/error]` (name → ERROR), `[error]CORRUPTED[/error]`, static red edges,
   YES / NO choices (YES sets a flag).
3. **vent** — pinned "Do you want to continue? / > YES", voice clip with a cue line, red ramp,
   whole-screen shake, a door sound, then the O2 countdown **SEAL THE VENT** (in time → the intro's
   home_bunk; too late → death, retry this screen).
4. **refuse** — pinned "> NO", red ramp, death screen with its own message, RETRY → **file**.

Open it in the Scene Writer to see how each part is set up, then press **New** for your own scene.

`story/scenes/excursion1_prep.json` (EXCURSION 1 PREP, after the Memory Examination) is a real chapter
that uses the **Main game UI**, **Fade in**, a voiced opening (`Exursion1prep.wav`, 4 cues), a **Map
walkthrough** (7 tips + walk to the READY ROOM + On arrival RESTRICTED) and a **Hold** ending. Edit its text and tips here, then Build.

---

## 9. Limits (for now)

* Auto-time needs a **WAV**; for MP3/OGG use Spread evenly and adjust.
* The preview shows the stage only (no O2 bar / minimap / main game UI / map walkthrough — use
  **Play** for those) and fills `{v:callsign}` with OPERATOR.
* Walkthrough targets and "Then walk to" rooms come from the default ship map (`data/vessel.gd`).
* The intro (thaw + Memory Examination) is still hand-made code; it is not a Scene Writer scene.
* Scenes are linear lists of screens with jumps; there is no visual flowchart.
* Exported builds: `export_presets.cfg` ("Windows Desktop") lists `story/scenes/*.json` under
  "Filters to export non-resource files", so scenes load in the shipped .exe. Keep new JSON scenes in
  `story/scenes/`.

For programmers: `ui/story_markup.gd` (parser/timing), `ui/story_stage.gd` (plays a screen),
`ui/story_scene.gd` (load/validate/save), `templates/authored_scene.gd` (runner),
`ui/map_tour.gd` (map walkthrough), `addons/scene_writer/` (plugin).
Tests: `godot --headless --audio-driver Dummy --script res://tools/writer_test.gd` (and `tools/excursion_test.gd`).

## Round 6 notes
- **Room screens.** A hold screen whose `on_enter` has `map_set_room:<room>` is that room's screen: moving there on the map (click-to-move, `map_moves:on`) opens it, in the same scene, so all state stays. A room left only by walking uses `"end": {"type": "hold", "exit": "room:<back room>"}` (no CONTINUE). Example: `stasis` in the ready room scenes.
- **Containers with a `search` cost** are paid once: flag `searched_<act>` makes later openings free with no prompt.
- **Leaving through the exit door** fades to black, then follows the end's `goto` (READY ROOM → `scene:airlock/airlock`, the placeholder AIR LOCK scene, chapter EXCURSION 1 in SCENE_ORDER.md).
- Unlocking a room stamps its name in on the map (like RESTRICTED). The full map's button is EXIT, bottom right. The character screen has an EXIT button bottom right (the X stays).
- The first drop's tips: tip 1 over the normal screen; the map maximizes only on the last tip.

## Round 7 notes

- Room screens (end `hold` + `map_set_room:`) show no scene title; the heading is the room name.
- ROOM TRANSITION: entering a room screen (map move or tour arrival) fades out/in with `dooropen.mp3`; the text types after. The airlock exit uses `airlockdoor.mp3`.
- Dynamic menu: `vars.rail_tabs` holds the revealed buttons (persisted across scenes). A brief screen with `"onboarding": true` starts with STA only and runs the STATUS → MAP → MENU tips. Dev starts default to STA+MAP (+INV in the airlock or after the locker search).
- Map markers whose act has an unpaid search get an orange border (`cost`).
- All tips are filed in the LOG under TUTORIALS.

## Round 8 notes

- The map schematic (full map + minimap) uses the original dark map background and colours; only the full map's window frame is holo green with the flicker (FX sits behind the content).
- The first LOG tutorial (e.g. via the RSV ABEYANCE link) reveals the LOG button (animated, saved in `vars.rail_tabs`).
