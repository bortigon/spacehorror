extends RefCounted
## Code-drawn item art (same style as the COFFEE POT picture in ui/station_window.gd: steel greys-greens,
## pale glass edges, a little highlight). Used by the inventory / container cells (ui/inv_slot.gd) and
## by the item stuck to the cursor while dragging (ui/window_manager.gd).
##   (preload "res://ui/item_icons.gd").has_icon(id)              true for THERMOS OF COFFEE, SUIT, LANTERN and keycards
##   (preload "res://ui/item_icons.gd").draw_icon(ci, id, rect)   draws it fitted into rect (square, centred)

const STEEL := Color(0.62, 0.78, 0.68, 1.0)
const STEEL_DARK := Color(0.30, 0.48, 0.40, 1.0)
const EDGE := Color(0.92, 1.0, 0.94, 0.9)
const GLASS := Color(0.78, 1.0, 0.88, 0.22)
const AMBER := Color(0.98, 0.78, 0.38, 1.0)
const COFFEE := Color(0.22, 0.10, 0.04, 0.95)
const ORANGE := Color(0.95, 0.55, 0.25, 1.0)

static func kind(id: String) -> String:
	var k := id.to_lower()
	if k == "thermos_coffee" or k.contains("thermos"):
		return "thermos"
	if k == "suit" or k.ends_with("_suit"):
		return "suit"
	if k == "lantern" or k.contains("lantern"):
		return "lantern"
	if k.contains("keycard"):
		return "keycard"
	return ""


static func has_icon(id: String) -> bool:
	return kind(id) != ""


## Draws the icon for `id` into `r` (art is designed on a 32 x 32 square). false = no icon for it.
static func draw_icon(ci: CanvasItem, id: String, r: Rect2, alpha := 1.0) -> bool:
	var k := kind(id)
	if k == "":
		return false
	var s := minf(r.size.x, r.size.y) / 32.0
	var o := r.position + (r.size - Vector2(32.0, 32.0) * s) * 0.5
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var R := func(x: float, y: float, w: float, h: float) -> Rect2: return Rect2(o + Vector2(x, y) * s, Vector2(w, h) * s)
	var c := func(col: Color) -> Color: return Color(col, col.a * alpha)
	var lw := maxf(1.0, 1.4 * s)
	match k:
		"thermos":
			ci.draw_rect(R.call(11, 3, 10, 4), c.call(STEEL))                  # cap
			ci.draw_rect(R.call(10, 7, 12, 2), c.call(STEEL_DARK))
			ci.draw_rect(R.call(9, 9, 14, 20), c.call(STEEL))                  # body
			ci.draw_rect(R.call(9, 9, 3, 20), c.call(Color(1, 1, 1, 0.22)))    # highlight
			ci.draw_rect(R.call(9, 15, 14, 6), c.call(COFFEE))                 # label band
			ci.draw_rect(R.call(9, 28, 14, 2), c.call(STEEL_DARK))
			ci.draw_rect(R.call(9, 9, 14, 21), c.call(EDGE), false, lw)
			for j in 3:                                                        # steam
				var x := 13.0 + float(j) * 3.0
				ci.draw_line(P.call(x, 2.5), P.call(x + 1.0, 0.5), c.call(Color(1, 1, 1, 0.45)), lw * 0.7, true)
		"suit":
			var torso := PackedVector2Array([P.call(9, 10), P.call(23, 10), P.call(22, 23), P.call(10, 23)])
			ci.draw_colored_polygon(torso, c.call(STEEL))
			ci.draw_circle(P.call(16, 6.5), 5.0 * s, c.call(STEEL_DARK))       # helmet
			ci.draw_circle(P.call(16, 6.5), 3.2 * s, c.call(GLASS * Color(1, 1, 1, 3.0)))
			ci.draw_arc(P.call(16, 6.5), 5.0 * s, 0.0, TAU, 20, c.call(EDGE), lw, true)
			ci.draw_rect(R.call(5, 10, 4, 11), c.call(STEEL_DARK))             # arms
			ci.draw_rect(R.call(23, 10, 4, 11), c.call(STEEL_DARK))
			ci.draw_rect(R.call(10, 23, 5, 8), c.call(STEEL_DARK))             # legs
			ci.draw_rect(R.call(17, 23, 5, 8), c.call(STEEL_DARK))
			ci.draw_rect(R.call(13, 13, 6, 4), c.call(ORANGE))                 # chest panel
			ci.draw_line(P.call(16, 17), P.call(16, 23), c.call(EDGE), lw * 0.8)   # zipper
			ci.draw_polyline(PackedVector2Array([torso[0], torso[1], torso[2], torso[3], torso[0]]), c.call(EDGE), lw, true)
		"lantern":
			ci.draw_arc(P.call(16, 6), 5.0 * s, PI, TAU, 12, c.call(EDGE), lw, true)   # handle
			ci.draw_rect(R.call(10, 6, 12, 3), c.call(STEEL))                  # top
			var glass := R.call(11, 9, 10, 15) as Rect2
			ci.draw_rect(glass, c.call(Color(AMBER, 0.55)))
			ci.draw_circle(glass.get_center(), 3.2 * s, c.call(Color(1.0, 0.95, 0.7, 0.95)))   # light
			ci.draw_rect(glass, c.call(EDGE), false, lw)
			ci.draw_line(P.call(16, 9), P.call(16, 24), c.call(STEEL_DARK), lw)
			ci.draw_rect(R.call(9, 24, 14, 4), c.call(STEEL))                  # base
			ci.draw_rect(R.call(9, 27, 14, 2), c.call(STEEL_DARK))
		"keycard":
			var card := R.call(5, 9, 22, 14) as Rect2
			ci.draw_rect(card, c.call(STEEL))
			ci.draw_rect(R.call(5, 12, 22, 3), c.call(STEEL_DARK))             # stripe
			ci.draw_rect(R.call(8, 17, 6, 4), c.call(AMBER))                   # chip
			ci.draw_rect(R.call(17, 18, 7, 1), c.call(STEEL_DARK))
			ci.draw_rect(R.call(17, 20, 5, 1), c.call(STEEL_DARK))
			ci.draw_circle(P.call(23.5, 11), 1.1 * s, c.call(Color(0.03, 0.13, 0.05)))   # lanyard hole
			ci.draw_rect(card, c.call(EDGE), false, lw)
	return true
