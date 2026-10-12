class_name MemoryExam
extends RefCounted
## MEMORY EXAMINATION VO cues + script text.
## Measured 2026-09-28: ffmpeg silencedetect (noise=-35dB, d=0.25) + faster-whisper base.en.
## On-screen text follows David's script (typos fixed — see NOTES). "+" continues a paragraph.

## Tunables
const O2_SECONDS := 10.0          # death countdown before termination
const NAME_MAX := 20
const NAME_SCRAMBLE_SEC := 0.5    # pinned typed name scrambles into ERROR over this long
const NAME_MIN_HOLD := 0.6        # if the VO is skipped, the name still shows this long first
const RED_NO4_START := 0.06       # red edge vignette at the start of the NO4 VO...
const RED_NO4_END := 0.55         # ...at its end (synced to the VO clock)
const RED_O2_END := 1.0           # ...and at 0% O2
const NO_VO_SILENT_CPS := 28.0    # chars/sec if a section has no WAV (none currently)
const BEAT_SLOW := 1.05           # heartbeat interval at the start of the O2 countdown (s)
const BEAT_FAST := 0.42           # ...and at the end

## Streams (res paths)
const STREAM_MAIN := "res://assets/sounds/memorytest1.wav"    # welcome…please indicate
const STREAM_RECOVER := "res://assets/sounds/memorytest1C.wav" # oxygen restored
const STREAM_YES := "res://assets/sounds/memorytestA.wav"     # Acknowledged, Operator.
const STREAM_NO1 := "res://assets/sounds/memorytestB1.wav"
const STREAM_NO2 := "res://assets/sounds/memorytestB2.wav"
const STREAM_NO3 := "res://assets/sounds/memorytestB3.wav"
const STREAM_NO4 := "res://assets/sounds/memorytestB4.wav"

## NOTES / VO vs script (report these):
## - Script "asses" → screen "assess" (VO already says assess).
## - VO (memorytest1 ~25.9s) says "the name you have on file"; script says "we have on file" → screen follows script ("we").
## - VO B3: "you'll be referred"; script: "you will be referred" → screen follows script.
## - VO B3 omits quotes around OPERATOR; screen keeps script quotes.
## - VO B4: "Goodbye, operator." / script "Good bye, operator." → screen "Good bye, Operator."
## - VO A is ~1.48s; whisper misheard it; energy envelope matches "Acknowledged, Operator."
## - memorytest1C is the recovery line after "NO WAIT I UNDERSTAND" (not the ERROR block).
## - Screen 2 shows David's rewording "1) Do you remember your name?" while the VO says
##   "First question. Do you remember your name?".
## - No separate WAV for the button label / death notice — those are silent UI (placeholder death text).

## Screens 1-3 play windows of memorytest1.wav: [from, to] seconds (to < 0 = end of file).
const WINDOWS: Array = [[0.9, 19.2], [19.2, 22.9], [22.9, -1.0]]

## Screen 1 — Welcome + assess + warning (one screen, VO plays through, then CONTINUE)
const CUES_SCREEN1: Array = [
	[1.09, "Welcome to the Memory Examination.", 3.16],
	[3.94, "The Memory Examination will assess the extent of memory loss you may have experienced.", 8.22],
	[8.97, "+Warning:", 9.32],
	[9.72, "+Failing to remember your position as a REC-7 employee does not release you from your contract,", 12.87],
	[13.33, "+and you will still be expected to perform your duties as assigned.", 18.73],
]
## Screen 2 — heading + David's new question wording, typed while the VO says
## "First question." (19.47-20.30) / "Do you remember your name?" (21.11-22.51). Then the name box.
const HEADING_NAME := "Memory Examination"
const CUES_NAME_Q: Array = [
	[19.47, "1)", 20.30],
	[21.11, "+Do you remember your name?", 22.51],
]
const NAME_QUESTION := "1) Do you remember your name?"   # pinned above the typed name on screen 3
## Screen 3 — pinned "1) Do you remember your name?" / "> <typed name>" (the name scrambles into
## ERROR as the VO reaches "The name ERROR"), then this text + YES/NO.
const CUES_ERROR: Array = [
	[23.64, "The name ERROR is not the name we have on file.", 26.77],
	[27.39, "+All further communication will now refer to you as OPERATOR.", 30.92],
	[31.88, "Please indicate that you understand.", 33.40],
]

const CUES_YES: Array = [
	[0.00, "Acknowledged, Operator.", 1.40],
]
const CUES_NO1: Array = [
	[0.00, "Answering \"NO\" is not a valid option.", 2.72],
	[3.39, "+Please try again.", 4.42],
]
const CUES_NO2: Array = [
	[0.00, "Operator:", 0.58],
	[0.90, "+Your understanding is vital to the continuance of the Memory Examination.", 5.00],
]
const CUES_NO3: Array = [
	[0.00, "The REC-7 corporation regrets to inform you that severe brain damage may inhibit your ability to understand this simple premise.", 8.41],
	[8.94, "+Since you can't remember your name, you will be referred to as \"OPERATOR.\"", 13.83],
	[14.36, "+Please indicate in the affirmative if you understand this.", 17.69],
]
const CUES_NO4: Array = [
	[0.00, "It seems the brain damage from stasis is severe.", 2.47],
	[3.73, "+The REC-7 corporation will now lock all doors to this stasis chamber and cut off oxygen.", 10.07],
	[10.87, "+The REC-7 corporation would like to remind you that your employment contract specifies that in the case of severe brain damage, the corporation is within its rights to terminate both your employment and existence.", 24.42],
	[25.30, "+Your body will be unceremoniously ejected into space.", 28.72],
	[29.31, "+Good bye, Operator.", 30.65],
]
const CUES_RECOVER: Array = [
	[0.00, "Good.", 0.49],
	[1.22, "+Basic understanding that you will be called Operator is imperative to the success of your mission.", 7.88],
	[8.49, "+Oxygen will be restored.", 10.12],
]

## UI copy (no VO). No key names anywhere: the game shows no tutorials / key hints.
## The death screen is the generic PdaScreen one (show_death defaults).
const RESPONSE_HEADER := "RESPONSE"
const QTE_HEADER := "RESPONSE  //  WINDOW CLOSING  %.1fs"
const NAME_EMPTY := "FIELD REQUIRED // A NAME CANNOT BE BLANK"
const UNDERSTAND_LABEL := "NO WAIT, I UNDERSTAND"
const CONTINUE_LABEL := "CONTINUE"
const SUBMIT_LABEL := "SUBMIT"


## ============================================================ QUESTIONS 2 + 3
## Recorded 2026-09-28 (14:43-15:24). Cue times measured like Q1: ffmpeg silencedetect
## (noise=-35dB, d=0.25) for starts/ends, faster-whisper small.en word timestamps where a
## sentence has no pause. [start, "text", end] in seconds of that clip; "+" joins the paragraph.
## On-screen text = David's script (typo "asses" → "assess").
##
## VO vs script (recording differs; the screen follows the script):
## - memorytest2 says "Question two," where the screen types "2)".
## - memorytest3 has no "Question three" — the screen still shows "3)".
## - memorytest2B: the first word sounds like "Any machinery"; script "Heavy machinery".
## - memorytest2C has no "Would you like to know more?" (own clip wouldyouliketoknowmore.wav);
##   the script's "(THIS IS A LINK TO A VIDEO)" is a note → KNOW_MORE_VIDEO hook below.
## - memorytest3A: "the Policy Holder WILL be entitled" (script: "would"); "lost" may be heard as
##   "loss"; no "(CED)" spoken (YES text shows it, per the script).
## - memorytest3A is one clip for both answers; YES plays good.wav ("Good.") first.
## - EXAMPLES_COVERED: "outside the Omega cluster" (script: "outside of the").
## - memorytestcomplete: "Memory test(s) complete" — screen "Memory Test Complete."

const HEADING_EXAM := "Memory Examination"     # typed above each question (same as Q1)

const STREAM_Q2 := "res://assets/sounds/memorytest2.wav"
const Q2_QUESTION := "2) Do you remember the mission of the REC-7 Corporation?"   # pinned above answers
const CUES_Q2: Array = [
	[0.00, "2)", 0.82],
	[1.42, "+Do you remember the mission of the REC-7 Corporation?", 4.50],
]
## Q2 answers, top to bottom. Wrong ones reply, then CONTINUE returns to Q2 (all three again).
const Q2_ANSWERS: Array = [
	{"label": "To make the universe a better place?", "correct": false,
		"stream": "res://assets/sounds/memorytest2A.wav", "cues": [
			[0.00, "While there is no doubt the REC-7 Corporation improves the universe,", 4.40],
			[4.60, "+this is not our primary mission.", 6.30],
		]},
	{"label": "Heavy machinery for mining colonies?", "correct": false,
		"stream": "res://assets/sounds/memorytest2B.wav", "cues": [
			[0.00, "Heavy machinery for mining colonies is not a product that the REC-7 Corporation offers.", 5.70],
		]},
	{"label": "Insurance?", "correct": true,
		"stream": "res://assets/sounds/memorytest2C.wav", "cues": [
			[1.24, "Correct.", 1.85],
			[2.37, "+The REC-7 Corporation", 3.90],
			[4.25, "+provides premium insurance policies to other corporations operating across the known universe.", 10.30],
		]},
]
## "Would you like to know more?" — its own clip, typed as a new paragraph under "Correct. …".
const STREAM_KNOW_MORE := "res://assets/sounds/wouldyouliketoknowmore.wav"
const KNOW_MORE_QUESTION := "Would you like to know more?"
const CUES_KNOW_MORE: Array = [
	[0.00, "Would you like to know more?", 1.15],
]
## >>> VIDEO HOOK: put the REC-7 video here as a Theora .ogv, e.g. "res://assets/video/rec7.ogv".
## Empty (or missing file) = the placeholder text below. The video plays in the text area after
## "> YES"; CONTINUE (or Space) goes on to Question 3.
const KNOW_MORE_VIDEO := ""
## PLACEHOLDER (no recording): shown after "> YES" while there is no video.
const CUES_ARCHIVE_PLACEHOLDER: Array = [
	[0.0, "ARCHIVE FILE UNAVAILABLE", 0.0],
	[0.0, "REC-7 corporate briefing: WHO WE INSURE. This file could not be retrieved from the TRM-CUFF archive.", 0.0],
]

const STREAM_Q3 := "res://assets/sounds/memorytest3.wav"
const Q3_QUESTION := "3) Do you remember your function as an employee of the REC-7 Corporation?"
const CUES_Q3: Array = [
	[0.00, "3)", 0.10],
	[0.10, "+Do you remember your function as an employee of the REC-7 Corporation?", 4.20],
]

const STREAM_GOOD := "res://assets/sounds/good.wav"
const STREAM_FUNCTION := "res://assets/sounds/memorytest3A.wav"
const CUES_GOOD: Array = [
	[0.00, "Good.", 0.50],
]
## memorytest3A (whole clip, one paragraph — fits one screen): both answers. YES plays "Good."
## (own clip) first and shows "(CED)" (script); NO does not.
const CUES_FUNCTION_YES: Array = [
	[0.00, "+You are a CLAIM OPERATOR.", 1.67],
	[2.24, "+Your function is to investigate insurance claims for REC-7 Policy Holders.", 7.82],
	[8.50, "+Most often, this involves lost or derelict space ships,", 12.29],
	[12.66, "+missing persons, or missing cargo.", 15.00],
	[15.68, "+You must assess whether CATASTROPHIC ECONOMIC DAMAGE (CED) has occurred,", 20.16],
	[20.58, "+and if so, determine whether the nature of the CATASTROPHIC ECONOMIC DAMAGE", 25.62],
	[25.93, "+is covered by the REC-7 Insurance Policy Agreement.", 29.51],
	[30.19, "+If the cause is covered, then the Policy Holder would be entitled to a massive monetary payout.", 36.60],
]
const CUES_FUNCTION_NO: Array = [
	[0.00, "You are a CLAIM OPERATOR.", 1.67],
	[2.24, "+Your function is to investigate insurance claims for REC-7 Policy Holders.", 7.82],
	[8.50, "+Most often, this involves lost or derelict space ships,", 12.29],
	[12.66, "+missing persons, or missing cargo.", 15.00],
	[15.68, "+You must assess whether CATASTROPHIC ECONOMIC DAMAGE has occurred,", 20.16],
	[20.58, "+and if so, determine whether the nature of the CATASTROPHIC ECONOMIC DAMAGE", 25.62],
	[25.93, "+is covered by the REC-7 Insurance Policy Agreement.", 29.51],
	[30.19, "+If the cause is covered, then the Policy Holder would be entitled to a massive monetary payout.", 36.60],
]

const STREAM_COVERED := "res://assets/sounds/memorytestEXAMPLES_COVERED.wav"
const CUES_COVERED: Array = [
	[0.88, "Examples of incidents covered by the REC-7 Policy Agreement include, but are not limited to:", 7.09],
	[7.63, "+collisions with ships, stations, or rocks not due to pilot error;", 12.54],
	[13.27, "+fire and explosions due to faulty machinery;", 15.79],
	[16.45, "+defensive action against alien species;", 19.02],
	[19.59, "+any pirate action outside of the Omega cluster;", 22.22],
	[22.89, "+or contact with previously undocumented disease or infection.", 26.20],
]
const STREAM_NOT_COVERED := "res://assets/sounds/memorytestEXAMPLES_NOT_COVERED.wav"
## memorytestEXAMPLES_NOT_COVERED is split at the pause before "NOTE:" (17.49-18.22 s):
## the examples screen plays 0 - NOT_COVERED_SPLIT, the SPACE MADNESS screen plays the rest.
const NOT_COVERED_SPLIT := 17.85
const CUES_NOT_COVERED: Array = [
	[0.00, "Examples of incidents NOT covered by the REC-7 Policy Agreement include, but are not limited to:", 6.13],
	[6.71, "+mutiny of the crew,", 7.65],
	[8.25, "+aggressive action toward alien species,", 10.51],
	[11.04, "+deviation from flight plans,", 12.64],
	[13.01, "+or willing interaction with space anomalies - unrecorded or recorded.", 17.49],
]
const CUES_SPACE_MADNESS: Array = [
	[18.22, "NOTE:", 18.62],
	[19.07, "+The REC-7 corporation does not believe that SPACE MADNESS is an actual medical condition.", 24.71],
	[25.26, "+As such, it will not be considered an excuse for aberrant behavior.", 29.33],
	[29.97, "+Any claim that involves SPACE MADNESS will be denied.", 33.19],
]

## ---- Example icons (one square per example) -------------------------------------
## Each examples screen shows one square per id in its ICONS_* list (count = list length), left to
## right in a centred row just under the finished text. Until art exists each square is a placeholder
## outline labelled with its id: EX1-n = covered screen (A), EX2-n = NOT covered screen (B).
## ICON_TIMES_*: second in that screen's clip when each square appears (= the example is spoken);
## must have the same length as the ICONS_* list.
##
## ADDING ART (either way works; an ICON_ART path wins over the file convention):
##   1. Drop an image named after the id into ICON_ART_DIR, e.g. res://assets/icons/EX1-3.png
##      (.png, .webp, .svg or .jpg; let Godot import it). It is picked up automatically.
##   2. Or set a path in ICON_ART, e.g. "EX1-3": "res://art/icons/pirates.png".
## When art is found the id label and the placeholder outline/fill are hidden and the texture fills
## the square (aspect kept, centred). Same animation, timing and blip.
const ICON_ART_DIR := "res://assets/icons/"
const ICON_ART_EXTS: Array = ["png", "webp", "svg", "jpg"]
const ICON_ART: Dictionary = {
	"EX1-1": "",   # collisions with ships, stations or rocks
	"EX1-2": "",   # fire and explosions due to faulty machinery
	"EX1-3": "",   # defensive action against alien species
	"EX1-4": "",   # pirate action outside of the Omega cluster
	"EX1-5": "",   # previously undocumented disease or infection
	"EX2-1": "",   # mutiny of the crew
	"EX2-2": "",   # aggressive action toward alien species
	"EX2-3": "",   # deviation from flight plans
	"EX2-4": "",   # willing interaction with space anomalies
}
## Covered (A): 5 examples, one square each.
const ICONS_COVERED: Array = ["EX1-1", "EX1-2", "EX1-3", "EX1-4", "EX1-5"]
const ICON_TIMES_COVERED: Array = [7.63, 13.27, 16.45, 19.59, 22.89]
## NOT covered (B): 4 examples, one square each.
const ICONS_NOT_COVERED: Array = ["EX2-1", "EX2-2", "EX2-3", "EX2-4"]
const ICON_TIMES_NOT_COVERED: Array = [6.71, 8.25, 11.04, 13.01]
const ICON_TEXT_GAP := 10.0        # px from the last line of the FINISHED text to the squares
const ICON_LABEL_SIZE := 9         # px, id label inside a placeholder square
const ICON_SIZE := 64.0            # px (960x540 layout), squares
const ICON_GAP := 28.0             # px between squares
const ICON_RISE := 10.0            # px each square rises while it fades in
const ICON_APPEAR_SECONDS := 0.4
## One quiet techie blip per icon (UI-2.mp3: unused elsewhere, ~0.4 s). Sfx bus, well under the VO.
const ICON_SFX := "res://assets/sounds/UI-2.mp3"
const ICON_SFX_DB := -12.0

const STREAM_SPECIAL := "res://assets/sounds/specialnotforclaimoperator.wav"
const CUES_SPECIAL: Array = [
	[0.00, "SPECIAL NOTE FOR CLAIM OPERATOR:", 2.17],
	[2.80, "Just as REC-7 Policy Holders would be entitled to MASSIVE MONETARY PAYOUT", 7.88],
	[8.25, "+if the reason for the CATASTROPHIC ECONOMIC DAMAGE is covered in our policy,", 13.01],
	[13.47, "+the CLAIM OPERATOR would receive a SIGNIFICANT MONETARY BONUS", 17.08],
	[17.40, "+for discovering that the reason for the CATASTROPHIC ECONOMIC DAMAGE was NOT covered.", 22.20],
	[23.28, "Do your best, OPERATOR.", 24.99],
]
const STREAM_COMPLETE := "res://assets/sounds/memorytestcomplete.wav"
const CUES_COMPLETE: Array = [
	[0.00, "Memory Test Complete.", 1.30],
	[1.71, "+Congratulations.", 2.72],
	[3.17, "+Your levels of brain damage seem to be within acceptable parameters.", 7.00],
]
const STREAM_DOCKED := "res://assets/sounds/endintromessage.wav"
const CUES_DOCKED: Array = [
	[0.00, "We are docked in position with our next investigation.", 2.90],
	[3.46, "Please take some time to excrete waste, decontaminate yourself, and ingest nutrients.", 9.49],
	[9.94, "+The first EXCURSION is scheduled to take place in one hour.", 13.88],
]

## Screens after the Q3 answer. Each ends on CONTINUE (→ the next screen); the last one fades to
## black. "parts" play one after another on the same screen: [stream, cues, from, to] (to < 0 = end).
## "parts_yes" (optional) replaces "parts" when the player answered YES to Question 3.
## "know_more": {"yes": id, "no": id} ends the screen with "Would you like to know more?" + YES/NO
## (the know-more clip plays after the screen's own clips); the next screen pins the answer.
## "icons" / "icon_times": the 4 example icons (see above).
## Screen 0 is pinned with "3) Do you remember…" / "> YES" or "> NO".
const TAIL_SCREENS: Array = [
	{"id": "function",
		"parts_yes": [[STREAM_GOOD, CUES_GOOD, 0.0, -1.0], [STREAM_FUNCTION, CUES_FUNCTION_YES, 0.0, -1.0]],
		"parts": [[STREAM_FUNCTION, CUES_FUNCTION_NO, 0.0, -1.0]],
		"know_more": {"yes": "covered", "no": "space_madness"}},
	{"id": "covered", "parts": [[STREAM_COVERED, CUES_COVERED, 0.0, -1.0]],
		"icons": ICONS_COVERED, "icon_times": ICON_TIMES_COVERED},
	{"id": "not_covered", "parts": [[STREAM_NOT_COVERED, CUES_NOT_COVERED, 0.0, NOT_COVERED_SPLIT]],
		"icons": ICONS_NOT_COVERED, "icon_times": ICON_TIMES_NOT_COVERED},
	{"id": "space_madness", "parts": [[STREAM_NOT_COVERED, CUES_SPACE_MADNESS, NOT_COVERED_SPLIT, -1.0]]},
	{"id": "special_note", "parts": [[STREAM_SPECIAL, CUES_SPECIAL, 0.0, -1.0]]},
	{"id": "complete", "parts": [[STREAM_COMPLETE, CUES_COMPLETE, 0.0, -1.0]]},
	{"id": "docked", "parts": [[STREAM_DOCKED, CUES_DOCKED, 0.0, -1.0]]},
]

## Final CONTINUE → the whole game fades to black and holds.
const FADE_BLACK_SECONDS := 1.8
## >>> NEXT SCENE HOOK: where the game goes after the black screen (+ AFTER_EXAM_CARD).
## Empty = stay on black.
## Any story target works: "scene:<id>" (a Scene Writer scene), "home_bunk" (a passage in this
## intro), "tscn:res://scenes/x.tscn".
const AFTER_EXAM := "scene:excursion1_prep"
const AFTER_EXAM_HOLD := 1.0   # seconds of black before the card / AFTER_EXAM
## Time card on the black before AFTER_EXAM opens ("" = none): fades in, holds, fades out.
const AFTER_EXAM_CARD := "ONE HOUR LATER"
const CARD_FADE_IN := 0.9
const CARD_HOLD := 2.3
const CARD_FADE_OUT := 0.9
const CARD_AFTER := 0.4        # black after the card, then AFTER_EXAM (the new chapter fades in)
const CARD_FONT := "res://assets/fonts/Oxanium-SemiBold.ttf"
const CARD_FONT_SIZE := 24
const CARD_COLOR := Color(0.56, 0.8, 0.6, 0.85)
