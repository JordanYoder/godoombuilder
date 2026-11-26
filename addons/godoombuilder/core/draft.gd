@tool
class_name DMDraft
extends Resource
## A polygon that was being drawn and left unfinished. It's saved with the map
## (shown in red in the editor) so it can be continued later; it builds no
## geometry.


## The points placed so far, in drawing order (map X/Z).
@export var points := PackedVector2Array()
## The height it was being drawn at.
@export var height := 0.0


static func make(pts: PackedVector2Array, h: float) -> DMDraft:
	var d := DMDraft.new()
	d.points = pts.duplicate()
	d.height = h
	return d


func duplicate_draft() -> DMDraft:
	return make(points, height)


## The same points (in either direction) at the same height.
func same_as(other: DMDraft) -> bool:
	if other == null or not is_equal_approx(height, other.height):
		return false
	if points == other.points:
		return true
	var back := other.points.duplicate()
	back.reverse()
	return points == back
