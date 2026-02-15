class_name HarnessTest
extends RefCounted

func id() -> String: return "unnamed"
func group() -> String: return "default"

func run(_runner) -> Dictionary:
	return {"status":"skip","assertions":[],"notes":["not implemented"],"artifacts":{}}
