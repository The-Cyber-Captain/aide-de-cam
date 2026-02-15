class_name JsonSchemaResolver
extends RefCounted

var schema_root: Dictionary = {}
var _ref_cache := {}

func load_schema_from_text(json_text: String) -> void:
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Schema JSON did not parse to object")
		schema_root = {}
		return
	schema_root = parsed
	_ref_cache.clear()

func resolve_ref(ref: String) -> Dictionary:
	if _ref_cache.has(ref):
		return _ref_cache[ref]

	if not ref.begins_with("#/"):
		return {}

	var parts = ref.substr(2).split("/")
	var node: Variant = schema_root
	for p in parts:
		p = p.replace("~1", "/").replace("~0", "~")
		if typeof(node) != TYPE_DICTIONARY or not node.has(p):
			return {}
		node = node[p]

	if typeof(node) != TYPE_DICTIONARY:
		return {}

	_ref_cache[ref] = node
	return node
