class_name JsonSchemaErrors
extends RefCounted

static func err(path: String, schema_path: String, msg: String) -> Dictionary:
	return {"path": path, "schema_path": schema_path, "message": msg}
