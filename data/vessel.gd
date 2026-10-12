@tool
class_name Vessel
extends RefCounted
## THE REC-7 VESSEL: name + ship schematic data (rooms, doors, starting state).
##
## >>> Rename the ship here (ONE place). Everything on screen reads these constants. <<<
const VESSEL_NAME := "ABEYANCE"
const VESSEL_PREFIX := "RSV"            # "REC-7 Stasis Vessel" (placeholder registry prefix)
const VESSEL_TITLE := VESSEL_PREFIX + " " + VESSEL_NAME   # "RSV ABEYANCE"
## Alternates floated to David: CONTINUANCE, SURETY, LONG TENANCY, DEFERRAL, VIGIL.

## ---------------------------------------------------------------- SCHEMATIC
## Geometry is in the pixel space of David's mockup (dev files/mapmockup.png, 241x240):
## every corner below was measured off that image, so the layout is his, just cleaned up.
## Rooms: "label" (shown once explored), "poly" (corners, clockwise), "state":
##   "explored"   seen: green, labelled
##   "unexplored" known shape, not yet visited: dark, no label
##   "locked"     can't go yet: dark with a lock icon
##   + "known": true  = the name is known but the room is not explored: dark, label shown dim
##   + "restricted": true = off limits: dark, red outline + a RESTRICTED stamp (pops in when set
##     with map_restrict_room); clicking it on the map answers RESTRICTED
## Doors: "a"/"b" room ids, "pos" centre of the doorway, "axis" "h" (door in a
## horizontal wall) or "v" (vertical wall), "state" "open" | "locked".
##   A door is drawn once one side is explored, or when "known": true.
## Moving (outside the intro): with "click_to_move" on, clicking a room next to the current
## one through an OPEN door moves you there and explores it (PdaScreen.map_try_move).
## Story ops (see PdaScreen): map_explore:id  map_set_room:id  map_lock_room:id
##   map_unlock_room:id  map_unlock_door:a|b  map_lock_door:a|b  open_map
##   map_know_room:id  map_know_door:a|b  map_moves:on|off  map_restrict_room:id
##   map_unrestrict_room:id
## LOCKED DOORS WITH A CARD: a locked door can carry
##   "key": item id the player must hold ("airlock_keycard"), "key_name": its exact display name
##   ("Airlock Keycard"; the click message reads "Requires Airlock Keycard"), "behind": the room
##   it leads to, and optionally "fail": "restrict" (clicking the lock WITHOUT the card reveals the
##   RESTRICTED stamp on the room behind it). The lock icons on the maps are clickable
##   (PdaScreen.map_door_click): with the card the lock shakes, pops open and the open doorway
##   replaces it, and the room behind becomes "known" (its name shows). To add another card, give a
##   door its own "key" / "key_name" (e.g. "restricted_keycard" / "Restricted Keycard") and make an
##   item with that id.
static func default_map() -> Dictionary:
	return {
		"title": VESSEL_TITLE,
		"subtitle": "REC-7 STASIS VESSEL // DECK SCHEMATIC",
		"current": "stasis_3",
		"rooms": {
			# Bright green trapezoid at the bottom of the mockup. Starting room.
			"stasis_3": {
				"label": "STASIS-3",
				"poly": [Vector2(73, 197), Vector2(176, 197), Vector2(160, 232), Vector2(89, 232)],
				"state": "explored",
			},
			# Big pale-green room above stasis (the mockup labelled it COMMISSARY; David: it is the
			# READY ROOM). One click from STASIS-3 through the open door. EXCURSION 1 PREP makes
			# its name known (map_know_room) before you have been there.
			"ready_room": {
				"label": "READY ROOM",
				"poly": [Vector2(45, 111), Vector2(201, 111), Vector2(201, 194), Vector2(45, 194)],
				"state": "unexplored",
			},
			# Grey L on the left of the mockup (block top-left, narrow run down the hull, room
			# beside the ready room). Was the placeholder PORT ACCESS; now the AIRLOCK: a named dark
			# room behind the ready room's port door (padlocked, as in the mockup).
			"airlock": {
				"label": "AIR LOCK",   # shown once the door is unlocked (the room is nameless before that)
				"poly": [Vector2(6, 24), Vector2(55, 24), Vector2(55, 87), Vector2(16, 87),
					Vector2(16, 111), Vector2(42, 111), Vector2(42, 194), Vector2(6, 194)],
				"state": "unexplored",
			},
			# Unlabelled grey room right of the ready room (runs off the mockup's frame).
			# Its lock tells the player it is RESTRICTED when they try the door (see "fail" below).
			"stbd_hold": {
				"label": "STBD HOLD",
				"poly": [Vector2(204, 111), Vector2(234, 111), Vector2(234, 194), Vector2(204, 194)],
				"state": "unexplored",
			},
			# Unlabelled grey wedges either side of stasis (tapered aft hull).
			"aft_port": {
				"label": "AFT PORT",
				"poly": [Vector2(6, 197), Vector2(34, 197), Vector2(12, 232), Vector2(6, 232)],
				"state": "unexplored",
			},
			"aft_stbd": {
				"label": "AFT STBD",
				"poly": [Vector2(206, 197), Vector2(234, 197), Vector2(234, 229)],
				"state": "unexplored",
			},
		},
		"doors": [
			# Open doorway drawn at the top of STASIS-3 in the mockup.
			{"a": "stasis_3", "b": "ready_room", "pos": Vector2(121, 195.5), "axis": "h", "state": "open"},
			# Doorways on the ready room's left and right walls, padlocked as in the mockup
			# (KEYCARD REQUIRED): port side = AIRLOCK, starboard side = STBD HOLD (RESTRICTED).
			{"a": "ready_room", "b": "airlock", "pos": Vector2(43.5, 150), "axis": "v", "state": "locked",
				"key": "airlock_keycard", "key_name": "Airlock Keycard", "behind": "airlock"},
			{"a": "ready_room", "b": "stbd_hold", "pos": Vector2(202.5, 150), "axis": "v", "state": "locked",
				"key": "restricted_keycard", "key_name": "Restricted Keycard", "behind": "stbd_hold", "fail": "restrict"},
		],
	}
