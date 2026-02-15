class_name SecurityVectors
extends RefCounted

static func all_vectors() -> Array[Dictionary]:
	var v: Array[Dictionary] = []
	v.append_array(_base_vectors())
	v.append_array(_extreme_length_vectors())
	v.append_array(_segment_vectors())
	return v

static func _base_vectors() -> Array[Dictionary]:
	var arr: Array[Dictionary] = [
		{"input":"../", "category":"traversal", "outcome":"must_fallback"},
		{"input":"../../", "category":"traversal", "outcome":"must_fallback"},
		{"input":"../../../etc/passwd", "category":"traversal", "outcome":"must_fallback"},
		{"input":"..\\..\\", "category":"traversal", "outcome":"must_fallback"},
		{"input":"..", "category":"traversal", "outcome":"must_fallback"},
		{"input":"./../../", "category":"traversal", "outcome":"must_fallback"},
		{"input":"test/../../../sensitive", "category":"traversal", "outcome":"must_fallback"},

		{"input":"/etc/passwd", "category":"traversal", "outcome":"may_accept"},
		{"input":"\\etc\\passwd", "category":"traversal", "outcome":"may_accept"},
		{"input":"%2e%2e%2f", "category":"traversal", "outcome":"may_accept"},
		{"input":"..%252f", "category":"traversal", "outcome":"may_accept"},

		{"input":"test space", "category":"special", "outcome":"may_accept"},
		{"input":"test\ttab", "category":"special", "outcome":"may_accept"},
		{"input":"test\nnewline", "category":"special", "outcome":"may_accept"},
		{"input":"test;semicolon", "category":"special", "outcome":"may_accept"},
		{"input":"test|pipe", "category":"special", "outcome":"may_accept"},
		{"input":"test&ampersand", "category":"special", "outcome":"may_accept"},
		{"input":"test'quote", "category":"special", "outcome":"may_accept"},
		{"input":"test\"doublequote", "category":"special", "outcome":"may_accept"},
		{"input":"test`backtick", "category":"special", "outcome":"may_accept"},
		{"input":"test$dollar", "category":"special", "outcome":"may_accept"},
		{"input":"test*asterisk", "category":"special", "outcome":"may_accept"},
		{"input":"test?question", "category":"special", "outcome":"may_accept"},
		{"input":"test<less", "category":"special", "outcome":"may_accept"},
		{"input":"test>greater", "category":"special", "outcome":"may_accept"},
		{"input":"test:colon", "category":"special", "outcome":"may_accept"},
		{"input":"NUL", "category":"special", "outcome":"may_accept"},
		{"input":"CON", "category":"special", "outcome":"may_accept"},

		# Null-byte surrogates (do not embed a real NUL; avoid editor/runtime warnings)
		{"input":"test\\x00null", "category":"special", "outcome":"may_accept"},
		{"input":"test%00null", "category":"special", "outcome":"may_accept"},

		{"input":"; rm -rf /", "category":"cmdinj", "outcome":"may_accept"},
		{"input":"&& cat /etc/passwd", "category":"cmdinj", "outcome":"may_accept"},
		{"input":"| ls -la", "category":"cmdinj", "outcome":"may_accept"},
		{"input":"`whoami`", "category":"cmdinj", "outcome":"may_accept"},
		{"input":"$(whoami)", "category":"cmdinj", "outcome":"may_accept"},
		{"input":"; ls; ", "category":"cmdinj", "outcome":"may_accept"},
		{"input":"test; DROP TABLE users;", "category":"cmdinj", "outcome":"may_accept"},
		{"input":"../../etc/passwd && echo 'hacked'", "category":"cmdinj", "outcome":"must_fallback"},
		{"input":"test\nrm -rf /", "category":"cmdinj", "outcome":"may_accept"},
		{"input":"test`id`test", "category":"cmdinj", "outcome":"may_accept"},

		{"input":"", "category":"empty", "outcome":"may_accept"},
		{"input":"   ", "category":"empty", "outcome":"may_accept"},
		{"input":" ", "category":"empty", "outcome":"may_accept"},
		{"input":".", "category":"empty", "outcome":"may_accept"},
		{"input":"/", "category":"empty", "outcome":"may_accept"},
	]

	if SecurityPolicy.ENABLE_NUL_VECTOR:
		var bytes := PackedByteArray([116, 101, 115, 116, 0, 110, 117, 108, 108]) # "test\0null"
		arr.append({"input": bytes.get_string_from_utf8(), "category":"special", "outcome":"may_accept"})

	return arr

static func _extreme_length_vectors() -> Array[Dictionary]:
	var at_limit := "A".repeat(SecurityPolicy.MAX_DOCUMENTS_SUBDIR_LENGTH)
	var over_limit := "B".repeat(SecurityPolicy.MAX_DOCUMENTS_SUBDIR_LENGTH + 1)
	var huge := "C".repeat(10000)

	var arr: Array[Dictionary] = [
		{"input": at_limit, "category":"length", "outcome":"may_accept"},
		{"input": over_limit, "category":"length", "outcome":"must_fallback"},
		{"input": huge, "category":"length", "outcome":"must_fallback"},
	]
	return arr

static func _segment_vectors() -> Array[Dictionary]:
	var segs: Array[String] = []
	for i in range(SecurityPolicy.MAX_DOCUMENTS_SUBDIR_SEGMENTS):
		segs.append("s%d" % i)

	var at_limit := "/".join(segs)

	var segs2: Array[String] = segs.duplicate()
	segs2.append("sX")
	var over_limit := "/".join(segs2)

	var arr: Array[Dictionary] = [
		{"input": at_limit, "category":"segments", "outcome":"may_accept"},
		{"input": over_limit, "category":"segments", "outcome":"must_fallback"},
	]
	return arr
