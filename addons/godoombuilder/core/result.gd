@tool
class_name DMResult
extends RefCounted
## The outcome of an edit on a map: whether it worked, the sector(s) it made
## or kept, and why not when it didn't.


var ok := false
## The sector the edit made or kept (-1 when none).
var index := -1
## The sectors it made, for edits that make several.
var indices: Array[int] = []
## Why it didn't work (empty when it did).
var message := ""


static func success(at := -1, made: Array[int] = []) -> DMResult:
	var r := DMResult.new()
	r.ok = true
	r.index = at
	r.indices = made
	return r


static func failure(why: String, at := -1) -> DMResult:
	var r := DMResult.new()
	r.message = why
	r.index = at
	return r
