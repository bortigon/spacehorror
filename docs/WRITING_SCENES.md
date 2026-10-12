# Writing a scene

This is how to write a screen in the Scene Writer, put it on the story list, and play the next screen.

The technical reference is still `docs/SCENE_WRITER.md`. This page is the short version.

## Open it

1. Open this project in Godot 4.6.
2. The plugin is already on. If the tab is missing: **Project → Project Settings → Plugins**, enable **Scene Writer**.
3. Click **Scene Writer** at the top, next to 2D, 3D, Script, and Game.

Across the top: **New**, a scene list, **Open**, **Save**, **Build**, **Play**.

The left column is the scene. The middle column is the screen you are writing. The right column is a preview.

**Ambience** lists `assets/sounds/ambiance` (or **(game default)**). **Narration** lists `assets/sounds/narration` and is this screen's voice clip, so the screen plays it with the text. Drag a wav, mp3, or ogg onto either dropdown. If the file is not already in that folder, Scene Writer copies it in and selects it. Older clips such as `Exursion1prep.wav` can stay in `assets/sounds` and are still chosen under **Voice clip**.

## 1. Write a scene

1. Press **New**.
2. **Scene id** is the file name. Use letters, numbers, and underscores, like `ready_room_next`. Godot will clean anything else.
3. **Title** is the dim line at the top of the scene, like `READY ROOM`.
4. Turn on **Main game UI (tab rail + map)** if this scene should look like EXCURSION 1 PREP (header, oxygen, tabs, the map). Leave it off for a full-screen story page.
5. The first screen is already there. Its text starts as "Write your first screen here." Replace that.
6. More subscenes: in **SCREENS**, pick the **Chapter** and **Scene**, then **Add**. **Earlier** / **Later** change their order on the list. **Next screen** inside one file is still the order of screens in that file.

**Screen id** is a short name for that screen (`s1`, `lights`). **Heading** is an optional big line above the text.

Write the text in the big box. One line is one sentence. A blank line starts a new paragraph.

Tags that work, the same ones printed under the box:

| You type | What the player sees |
|---|---|
| `[error]word[/error]` | that word glitches, then settles |
| `[error level=6]word[/error]` | same glitch, intensity 0–10. Level 0 is the normal ERROR look. Level 10 is hard to read |
| `[error=ERROR]name[/error]` | "name" stays readable, then becomes ERROR |
| `[error=DEMON delay=1.5]voice[/error]` | "voice" stays readable for 1.5 seconds, then becomes DEMON |
| `[expo]The room is cold.[/expo]` | that sentence in the exposition serif (IBM Plex Serif) |
| `[act=locker]LOCKER[/act]` | that word is clickable. It opens the act named on the screen: a text swap with options and Back, or a container window |
| `[shake]text[/shake]` | that text shakes |
| `[pause=1.0]` | typing waits 1 second |
| `[b]bold[/b]` `[i]italic[/i]` | bold, italic |
| `{v:callsign}` | the player's callsign (OPERATOR, after the exam) |
| `{flag:some_flag?yes text\|no text}` | one or the other, depending on a flag set earlier |

There are buttons for the common tags: **ERROR glitch**, **Level** (0–10), a delay in seconds, **Becomes:**, **Shake**, **Pause**, **Bold**, **Italic**, **Exposition**, **Interactable**, **Remove effects**. Select the words first. **Exposition** is for describing a room before dialogue or an action.

**Interactable** wraps the selection as `[act=id]...[/act]`. The id box next to the button is the tag (default `locker`). **Add action** writes that id's menu onto the screen: a label, an hour cost, an item id, and **Required**. In play, clicking the word opens those actions. Finishing one marks it done. The hour number is shown on the button. It spends blocks only after a later scene arms the hour bar. Put the suit on the locker with **Required** if the screen's continue ending has `require` set to that item.

**Container** (tick the box in the ACT section) turns an act into a window instead of a text swap. Clicking the green word opens a window in the middle of the screen with the character screen beside it. Window title is the name at the top-left, the act's text is the description under it (the left quarter of the window), and **Grid** is how many columns and rows of cells the window has. **Add item** adds a row: **id** (the inventory item and its `has_<id>` flag), **label** (the name on the cell and the button), **hours**, **Required**, and a **detail** line (shown when the item is highlighted, and as its hover tip). The player clicks an item and presses **Take LABEL (1 hr)**, or drags it onto the character screen. The hour cost is shown, and only spent after a later scene arms the hour bar. EXIT, the X on the character screen, or Esc closes it. Back is not used for containers. Untick the box to turn it back into the old text-swap act.

**Pinned question** is optional. After the player answers, the next screen shows that question and their answer at the top. If you leave it blank, the game uses the last line of this screen.

**Screen ends with** is how the player leaves this screen:

- **CONTINUE button** — one button. **CONTINUE goes to** says where.
- **Transition (time card)** — a black card, like ONE HOUR LATER. **Card text** is the line (for example ONE HOUR LATER). It fades in, holds, and fades out, then **Then goes to** (NEXT is the next subscene). Keys do nothing while the card is up.
- **Choices** — press **Add choice**. Each row is the words on the button, then a dropdown of where it goes. **ops (optional)** is for things like `set_flag:saw_the_note`. You can ignore ops until you need them.
- **Hold (the scene stops here)** — the scene waits. See the next section.
- **Death** and **O2 countdown (quick-time)** are for a fail state and a timer. **Map walkthrough (HIGHLIGHT + TIP)** is the map lesson. You do not need those for an ordinary scene.

**Next screen** in any of those dropdowns means the next screen in this file. **NEXT** means the next subscene in `story/SCENE_ORDER.md`.

Press **Build** when you want the game to have it. Build saves the scene and writes the file the game runs. **Save** only writes the text file. **Play** runs this scene on its own, from the first screen, not from the title.

## 2. The SCREENS list

**SCREENS** lists the whole outline, not just the scene in the dropdowns. Click a chapter or a scene (PROLOGUE, INTRO, READY ROOM) to fold or open it. The chapter and scene you are in start open.

Double-click a subscene such as brief to open that Scene Writer file and select that screen. The scene you were editing is saved first, with no prompt. If it has no id, or saving would replace a different file, nothing is saved and your text stays. thaw and exam are intro passages in scenes/intro.gd. They show in the list, and double-click tells you there is no Scene Writer file. Sample Scene is not on the story list, so it sits under NOT ON THE LIST and does not add a debug-menu button.

- **Chapter** — PROLOGUE is the one that exists. **New chapter…** then **Chapter name** adds one (Chapter 1 does not exist yet).
- **Scene** — the scenes in that chapter. PROLOGUE has **INTRO** and **READY ROOM**. Those two names are the debug menu buttons. **New scene…** then **Scene name** adds one.
- The rows under a scene are its **subscenes**.

PROLOGUE is still on this ship, before they leave.

**INTRO** runs until the player moves into the ready room. Its subscenes are thaw, exam, then excursion1_prep's brief and map.

**READY ROOM** is the ready_room subscene only.

**Add** asks Chapter, Scene, or Subscene. Chapter and Scene ask for a name and append it to the list (a scene goes under the chapter selected above). Subscene is a new screen in the open file, under that scene. Drag a chapter, scene, or subscene to reorder it; drop a subscene on a scene to move it there. The list saves immediately, and NEXT follows the new order with no Build. **Undo** (or Ctrl+Z, unless you are typing) puts back the last list change, up to 20 of them. **Earlier** / **Later** reorder subscenes in that scene. **On the list** puts the screen you are editing into the chapter and scene shown above, or takes it off.

**When it ends** = **NEXT** follows the next subscene on the list. You do not type the next id. Reordering does not need a Build. A new scene file still needs one **Build**.

If this subscene is the last one, **NEXT** shows one line: "The next scene isn't written." Nothing crashes.

ready_room is a Hold. **When it ends** on EXCURSION 1 PREP is **NEXT**, and nothing is listed after ready_room, so CONTINUE there shows that line.

### Add the next subscene yourself

Nothing below is already in the project.

1. **New**. **Scene id** `airlock`. **Title** `AIRLOCK`. Turn on **Main game UI (tab rail + map)**. **When it ends** is already **NEXT**. Leave it.
2. **Screen id** `arrive`. **Heading** `AIRLOCK`.
3. In **SCREENS**: **Chapter** → **New chapter…**, **Chapter name** `CHAPTER 1`. **Scene** → **New scene…**, **Scene name** `AIRLOCK`. **Add** (or check **On the list** if the screen is already written).
4. **Build** once.
5. Do not edit excursion1_prep. Its **When it ends** is already **NEXT**. The ready room's CONTINUE opens your subscene. The debug menu gains a **AIRLOCK** button because that scene is on the list.

You can edit `story/SCENE_ORDER.md` instead. A chapter is `## `, a scene is `### `, a subscene is `- scene:airlock/arrive — AIRLOCK` or `- intro:thaw — STASIS THAW`.

## 3. The debug mission select

One button per **scene**, then **BACK**. Right now that is **INTRO** and **READY ROOM**.

**INTRO** starts the intro at its first subscene (thaw). **READY ROOM** opens the ready_room subscene. Thaw, exam, brief, and map are not separate buttons. They are subscenes of INTRO.

**BACK** returns to the title.

The menu is for debug runs only. A release PLAY goes straight into the thaw and never shows the menu. Command-line debug args skip the title and the menu.

The tree shows only this outline. A file in `story/scenes` with no line here is not listed.
