class_name JsonSchemaValidator
extends RefCounted

const SUPPORTED_KEYS := {
	"$ref": true, "$defs": true,
	"type": true, "properties": true, "required": true, "additionalProperties": true,
	"minProperties": true,
	"minLength": true, "minimum": true,
	"items": true, "minItems": true, "maxItems": true,
	"const": true, "enum": true,
	"oneOf": true, "allOf": true, "not": true,
	"if": true, "then": true,
	"$schema": true, "$id": true, "title": true, "description": true
}

var resolver: JsonSchemaResolver

func _init(_resolver: JsonSchemaResolver) -> void:
	resolver = _resolver

func validate(instance: Variant, schema: Dictionary) -> Dictionary:
	var r := {
		"valid": true,
		"error_kind": "",
		"errors": [],
		"unsupported_keywords": []
	}
	_validate_node(instance, schema, "", "#", r)
	if r["unsupported_keywords"].size() > 0:
		r["valid"] = false
		r["error_kind"] = "unsupported_schema"
	elif r["errors"].size() > 0:
		r["valid"] = false
		r["error_kind"] = "validation_failed"
	return r

func _validate_node(inst: Variant, sch: Dictionary, path: String, sch_path: String, out: Dictionary) -> void:
	if typeof(sch) != TYPE_DICTIONARY:
		out["errors"].append(JsonSchemaErrors.err(path, sch_path, "Schema node is not an object"))
		return

	for k in sch.keys():
		if not SUPPORTED_KEYS.has(k) and not out["unsupported_keywords"].has(k):
			out["unsupported_keywords"].append(k)

	if sch.has("$ref"):
		var ref_str := String(sch["$ref"])
		var target := resolver.resolve_ref(ref_str)
		if target.is_empty():
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/$ref", "Unresolvable/unsupported $ref: %s" % ref_str))
			return
		_validate_node(inst, target, path, ref_str, out)
		return

	if sch.has("allOf"):
		var arr: Array = sch["allOf"]
		for i in range(arr.size()):
			_validate_node(inst, arr[i], path, sch_path + "/allOf/%d" % i, out)

	if sch.has("oneOf"):
		var arr: Array = sch["oneOf"]
		var matches := 0
		for i in range(arr.size()):
			var tmp := {"errors": [], "unsupported_keywords": []}
			_validate_node(inst, arr[i], path, sch_path + "/oneOf/%d" % i, tmp)
			if tmp["unsupported_keywords"].size() == 0 and tmp["errors"].size() == 0:
				matches += 1
		if matches != 1:
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/oneOf", "oneOf expected exactly 1 match; got %d" % matches))
		return

	if sch.has("not"):
		var tmp2 := {"errors": [], "unsupported_keywords": []}
		_validate_node(inst, sch["not"], path, sch_path + "/not", tmp2)
		if tmp2["unsupported_keywords"].size() == 0 and tmp2["errors"].size() == 0:
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/not", "not subschema matched (should fail)"))
			return

	if sch.has("if") and sch.has("then"):
		var tmp3 := {"errors": [], "unsupported_keywords": []}
		_validate_node(inst, sch["if"], path, sch_path + "/if", tmp3)
		if tmp3["unsupported_keywords"].size() == 0 and tmp3["errors"].size() == 0:
			_validate_node(inst, sch["then"], path, sch_path + "/then", out)

	if sch.has("type"):
		var t := String(sch["type"])
		if not _check_type(inst, t):
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/type", "Expected type %s" % t))
			return

	if sch.has("const"):
		if not _deep_equal(inst, sch["const"]):
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/const", "const mismatch"))
			return

	if sch.has("enum"):
		var ok := false
		for v in sch["enum"]:
			if _deep_equal(inst, v):
				ok = true
				break
		if not ok:
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/enum", "value not in enum"))
			return

	if typeof(inst) == TYPE_STRING and sch.has("minLength") and inst.length() < int(sch["minLength"]):
		out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/minLength", "minLength violated"))
		return

	if typeof(inst) in [TYPE_INT, TYPE_FLOAT] and sch.has("minimum") and float(inst) < float(sch["minimum"]):
		out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/minimum", "minimum violated"))
		return

	if typeof(inst) == TYPE_ARRAY:
		if sch.has("minItems") and inst.size() < int(sch["minItems"]):
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/minItems", "minItems violated"))
			return
		if sch.has("maxItems") and inst.size() > int(sch["maxItems"]):
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/maxItems", "maxItems violated"))
			return
		if sch.has("items"):
			for i in range(inst.size()):
				_validate_node(inst[i], sch["items"], path + "/%d" % i, sch_path + "/items", out)

	if typeof(inst) == TYPE_DICTIONARY:
		if sch.has("minProperties") and inst.keys().size() < int(sch["minProperties"]):
			out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/minProperties", "minProperties violated"))
			return

		if sch.has("required"):
			for req in sch["required"]:
				if not inst.has(req):
					out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/required", "Missing required key: %s" % String(req)))

		if sch.has("properties"):
			var props: Dictionary = sch["properties"]
			for k in inst.keys():
				var ks := String(k)
				if props.has(ks):
					_validate_node(inst[k], props[ks], path + "/" + ks, sch_path + "/properties/" + ks, out)
				else:
					if sch.has("additionalProperties") and sch["additionalProperties"] == false:
						out["errors"].append(JsonSchemaErrors.err(path, sch_path + "/additionalProperties", "Unexpected key: %s" % ks))

func _check_type(v: Variant, t: String) -> bool:
	match t:
		"object": return typeof(v) == TYPE_DICTIONARY
		"array": return typeof(v) == TYPE_ARRAY
		"string": return typeof(v) == TYPE_STRING
		"boolean": return typeof(v) == TYPE_BOOL
		"integer":
			if typeof(v) == TYPE_INT: return true
			if typeof(v) == TYPE_FLOAT: return is_equal_approx(v, int(v))
			return false
		"number": return typeof(v) in [TYPE_INT, TYPE_FLOAT]
		_: return false

func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
			return float(a) == float(b)
		return false
	if typeof(a) == TYPE_DICTIONARY:
		if a.keys().size() != b.keys().size(): return false
		for k in a.keys():
			if not b.has(k): return false
			if not _deep_equal(a[k], b[k]): return false
		return true
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _deep_equal(a[i], b[i]): return false
		return true
	return a == b
