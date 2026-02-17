extends Control

const WATCH_RETRY_INTERVAL: float = 2.0
const WAIT_INTERVAL: float = 0.25
const FILENAME: String = "user://camera_capabilities.json"

# Global font fit bounds
const FONT_MIN: int = 60
const FONT_MAX: int = 70

# If true: only enable scrolling when we hit FONT_MIN and still overflow.
# If false: enable scrolling any time overflow occurs.
const ONLY_SCROLL_AT_MIN: bool = true

# If true: when all panels have same viewport size, binary-search only the "worst" line.
const OPTIMIZE_USING_WORST_LINE: bool = true

# Tolerances / safety padding
const EPS: float = 0.5
const EXTRA_BOTTOM_PX: int = 8 # helps avoid last-line clipping at the very bottom

var status_string: String = "":
	set(new_string):
		status_string = new_string
		var label: Label = get_node_or_null("%StatusLabel")
		if label != null:
			%StatusLabel.text = "Status: %s" % [new_string]


func _ready() -> void:
	status_string = "Aide-De-Cam plugin not detected"
	_watch_for_plugin()


func _watch_for_plugin() -> void:
	if AideDeCam.is_plugin_available():
		AideDeCam.capabilities_updated.connect(_display_capabilties_from_file)
		status_string = "Connected to singleton"
		return

	status_string = "Aide-De-Cam plugin not detected"
	await get_tree().create_timer(WATCH_RETRY_INTERVAL).timeout
	_watch_for_plugin()


func _display_capabilties_from_file() -> void:
	await get_tree().create_timer(WAIT_INTERVAL).timeout
	status_string = "displaying json"

	var return_dic: Dictionary = _parse_capabilities_json()
	if return_dic.is_empty():
		status_string = "Error: empty file!?"
		return

	var _nl: Label = get_node_or_null("%RigNameLabel")
	var _il: Label = get_node_or_null("%RigInfoLabel")
	var _gc: GridContainer = get_node_or_null("%GridContainer")
	if _nl == null or _il == null or _gc == null:
		status_string = "Error: UI sections missing"
		return

	%RigNameLabel.text = "Rig: " + str(return_dic["line_device"])
	%RigInfoLabel.text = "Info: " + str(return_dic["line_system"])

	var camera_lines_v: Variant = return_dic["camera_lines"]
	var camera_lines: Array = camera_lines_v if typeof(camera_lines_v) == TYPE_ARRAY else []
	var camera_count: int = camera_lines.size()

	%GridContainer.columns = _calc_grid_columns(camera_count)

	var existing_panels: Array[Node] = %GridContainer.get_children()

	if existing_panels.size() > camera_count:
		for i: int in range(existing_panels.size(), camera_count, -1):
			existing_panels[i - 1].queue_free()
			existing_panels.pop_back()
	elif existing_panels.size() < camera_count:
		for i: int in range(existing_panels.size(), camera_count):
			_create_and_add_grid_panel()
		existing_panels = %GridContainer.get_children()

	status_string = "Camera lines # %d" % [camera_count]
	_populate_camera_panels(camera_lines, existing_panels)

	var ts_ms_v: Variant = return_dic["timestamp_ms"]
	var ts_ms: int = int(ts_ms_v)
	status_string = "Info queried %s" % [
		Time.get_datetime_string_from_unix_time(int(ts_ms / 1000.0), true)
	]


func _populate_camera_panels(cam_lines: Array, panels: Array[Node]) -> void:
	for idx: int in range(0, cam_lines.size()):
		var lab: Label = _get_label_from_panel(panels[idx])
		lab.text = str(cam_lines[idx]+"\n------\n")

	# IMPORTANT: clear prior run's min-size/scroll/font overrides so layout doesn't "ratchet"
	_reset_panel_layout_state(panels)

	# Frame 1: layout settles (sizes become meaningful)
	await get_tree().process_frame

	# Choose & apply global font size (includes initial overflow enforcement)
	_pick_global_font_size_for_panels(panels, FONT_MIN, FONT_MAX)

	# Frame 2: font size + min-size can affect layout, especially on Android
	await get_tree().process_frame

	# Enforce overflow again using final geometry
	_enforce_scroll_overflow(panels)


func _reset_panel_layout_state(panels: Array[Node]) -> void:
	for p: Node in panels:
		var sc: ScrollContainer = _get_scroll_from_panel(p)
		var vb: VBoxContainer = _get_vb_from_panel(p)
		var lab: Label = _get_label_from_panel(p)

		# Clear old min-size forcing
		lab.custom_minimum_size.y = 0
		vb.custom_minimum_size.y = 0

		# Disable scrolling while we recompute
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

		# Clear old font size override so measurement/layout isn't biased
		lab.remove_theme_font_size_override("font_size")


func _calc_grid_columns(item_count: int) -> int:
	return ceili(sqrt(item_count))


func _create_and_add_grid_panel() -> void:
	var pan: Panel = Panel.new()
	pan.theme = preload("res://themes/cam_panel_theme.tres")
	pan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pan.clip_contents = true

	var mc: MarginContainer = MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.clip_contents = true
	pan.add_child(mc)
	mc.owner = pan

	var sc: TouchScroll = TouchScroll.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.clip_contents = true

	sc.get_v_scroll_bar().custom_minimum_size.x = 24
	sc.get_h_scroll_bar().custom_minimum_size.y = 24

	mc.add_child(sc)
	sc.owner = mc

	# Critical: ScrollContainer should have a container as its direct child.
	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(vb)
	vb.owner = sc

	var lab: Label = Label.new()
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size = Vector2i(128, 0) # y set dynamically when needed
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(lab)
	lab.owner = vb

	%GridContainer.add_child(pan)
	pan.owner = %GridContainer


# -------------------------
# JSON parsing (strict-safe; same as earlier)
# -------------------------

func _parse_capabilities_json() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(FILENAME)
	if text.is_empty():
		push_error("Empty file: %s" % FILENAME)
		return {}

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON in: %s" % FILENAME)
		return {}

	var root: Dictionary = parsed as Dictionary

	var manufacturer: String = str(root.get("device_manufacturer", "unknown"))
	var model: String = str(root.get("device_model", "unknown"))
	var android_version: String = str(root.get("android_version", "unknown"))
	var line_device: String = "%s %s (Android %s)" % [manufacturer, model, android_version]

	var sdk: int = int(root.get("sdk_version", -1))
	var perm: bool = bool(root.get("camera_permission_granted", false))

	var cc_v: Variant = root.get("concurrent_camera_support", null)

	var cc_supported: bool = false
	var max_cc: int = 0
	var combos: Array = []
	var cc_note: String = ""

	if cc_v == null:
		cc_note = " | concurrent=unknown"
	elif typeof(cc_v) == TYPE_DICTIONARY:
		var cc: Dictionary = cc_v as Dictionary
		cc_supported = bool(cc.get("supported", false))
		max_cc = int(cc.get("max_concurrent_cameras", 0))

		var combos_v: Variant = cc.get("camera_id_combinations", [])
		combos = combos_v if typeof(combos_v) == TYPE_ARRAY else []

		var cc_err: Variant = cc.get("error", "")
		if cc_err != null and str(cc_err) != "":
			cc_note = " | concurrent_error=%s" % str(cc_err)
	elif typeof(cc_v) == TYPE_STRING:
		cc_note = " | concurrent=%s" % str(cc_v)
	else:
		cc_note = " | concurrent=unexpected_type(%s)" % str(typeof(cc_v))

	var combos_str: String = ""
	if cc_supported:
		var joined: String = _safe_join_combo_arrays(combos)
		if not joined.is_empty():
			combos_str = ", combos=" + joined

	var line_system: String = "SDK %d | camera_permission=%s | concurrent=%s (max=%d)%s%s" % [
		sdk, str(perm), str(cc_supported), max_cc, combos_str, cc_note
	]

	var timestamp_ms: int = int(root.get("timestamp_ms", 0))

	var camera_lines: Array[String] = []

	var cameras_v: Variant = root.get("cameras", [])
	var cameras: Array = cameras_v if typeof(cameras_v) == TYPE_ARRAY else []

	for camv: Variant in cameras:
		if typeof(camv) != TYPE_DICTIONARY:
			continue
		var cam: Dictionary = camv as Dictionary

		var cam_id: String = str(cam.get("camera_id", "unknown"))
		var facing: String = str(cam.get("facing", "unknown"))
		var hw: String = str(cam.get("hardware_level", "unknown"))
		var logical: bool = bool(cam.get("is_logical_multi_camera", false))

		var sensor_v: Variant = cam.get("sensor", {})
		var sensor: Dictionary = sensor_v as Dictionary if typeof(sensor_v) == TYPE_DICTIONARY else {}

		var pa_w: Variant = sensor.get("pixel_array_width", null)
		var pa_h: Variant = sensor.get("pixel_array_height", null)
		var phys_w: Variant = sensor.get("physical_width_mm", null)
		var phys_h: Variant = sensor.get("physical_height_mm", null)
		var iso_min: Variant = sensor.get("iso_min", null)
		var iso_max: Variant = sensor.get("iso_max", null)

		var focal_v: Variant = cam.get("focal_lengths", [])
		var focal_lengths: Array = focal_v if typeof(focal_v) == TYPE_ARRAY else []

		var ap_v: Variant = cam.get("apertures", [])
		var apertures: Array = ap_v if typeof(ap_v) == TYPE_ARRAY else []

		var warn_v: Variant = cam.get("warnings", [])
		var warnings: Array = warn_v if typeof(warn_v) == TYPE_ARRAY else []

		var parts: Array[String] = []
		parts.append("facing=%s" % facing)
		parts.append("hw=%s" % hw)
		parts.append("logical=%s" % str(logical))

		if pa_w != null and pa_h != null:
			parts.append("pixel_array=%sx%s" % [str(pa_w), str(pa_h)])
		if phys_w != null and phys_h != null:
			parts.append("sensor_mm=%sx%s" % [str(phys_w), str(phys_h)])
		if iso_min != null and iso_max != null:
			parts.append("iso=%s-%s" % [str(iso_min), str(iso_max)])

		if focal_lengths.size() > 0:
			parts.append("focal_lengths=%s" % _safe_join_any(focal_lengths, ", "))
		if apertures.size() > 0:
			parts.append("apertures=%s" % _safe_join_any(apertures, ", "))
		if warnings.size() > 0:
			parts.append("warnings=%s" % _safe_join_any(warnings, "; "))

		camera_lines.append("Camera id=%s\n\n" % cam_id + " | ".join(parts))

	return {
		"line_device": line_device,
		"line_system": line_system,
		"camera_lines": camera_lines,
		"timestamp_ms": timestamp_ms
	}


func _safe_join_any(arr: Variant, sep: String = ", ") -> String:
	if arr == null:
		return ""
	if typeof(arr) != TYPE_ARRAY:
		return str(arr)

	var out: Array[String] = []
	var a: Array = arr as Array
	for v: Variant in a:
		out.append(str(v))
	return sep.join(out)


func _safe_join_combo_arrays(arr: Variant) -> String:
	if arr == null or typeof(arr) != TYPE_ARRAY:
		return ""

	var combo_parts: Array[String] = []
	var outer: Array = arr as Array
	for combo_v: Variant in outer:
		if typeof(combo_v) != TYPE_ARRAY:
			continue
		var combo: Array = combo_v as Array
		var ids: Array[String] = []
		for idv: Variant in combo:
			ids.append(str(idv))
		combo_parts.append("[" + ",".join(ids) + "]")

	return "; ".join(combo_parts)


# -------------------------
# Node access (Panel -> MarginContainer -> ScrollContainer -> vb -> Label)
# -------------------------

func _get_scroll_from_panel(p: Node) -> ScrollContainer:
	var mc: MarginContainer = p.get_child(0) as MarginContainer
	return mc.get_child(0) as ScrollContainer


func _get_vb_from_panel(p: Node) -> VBoxContainer:
	var sc: ScrollContainer = _get_scroll_from_panel(p)
	return sc.get_child(0) as VBoxContainer


func _get_label_from_panel(p: Node) -> Label:
	var vb: VBoxContainer = _get_vb_from_panel(p)
	return vb.get_child(0) as Label


# -------------------------
# Font fitting + conservative overflow measurement
# -------------------------

func _measure_wrapped_size(font: Font, font_size: int, text: String, wrap_width: float) -> Vector2:
	if text.is_empty():
		return Vector2.ZERO

	return font.get_multiline_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		wrap_width,
		font_size,
		-1,
		TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
	)


func _vscroll_thickness(sc: ScrollContainer) -> float:
	var vbar: VScrollBar = sc.get_v_scroll_bar()
	return max(vbar.custom_minimum_size.x, vbar.size.x)


func _needed_height_for_scroll_with_size(sc: ScrollContainer, font: Font, font_size: int, text: String, wrap_w_base: float) -> float:
	# Measure with base width AND with "scrollbar present" width (to avoid late-trigger).
	var bar_w: float = _vscroll_thickness(sc)
	var wrap_w: float = max(wrap_w_base, 1.0)
	var wrap_w_with_bar: float = max(wrap_w - bar_w, 1.0)

	var s1: Vector2 = _measure_wrapped_size(font, font_size, text, wrap_w)
	var s2: Vector2 = _measure_wrapped_size(font, font_size, text, wrap_w_with_bar)

	var needed_y: float = max(s1.y, s2.y)

	# Padding tuned for "last line clipped" cases (descent + a few pixels).
	var descent: float = float(font.get_descent(font_size))
	needed_y += descent + float(EXTRA_BOTTOM_PX)

	return needed_y


func _entries_from_panels(panels: Array[Node]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for p: Node in panels:
		var sc: ScrollContainer = _get_scroll_from_panel(p)
		var vb: VBoxContainer = sc.get_child(0) as VBoxContainer
		var lab: Label = vb.get_child(0) as Label
		entries.append({ "sc": sc, "vb": vb, "lab": lab })
	return entries


func _all_same_viewport(entries: Array[Dictionary]) -> bool:
	if entries.is_empty():
		return true

	var first_sc: ScrollContainer = entries[0]["sc"] as ScrollContainer
	var w0: float = first_sc.size.x
	var h0: float = first_sc.size.y

	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		if abs(sc.size.x - w0) > EPS or abs(sc.size.y - h0) > EPS:
			return false

	return true


func _pick_worst_entry_by_length(entries: Array[Dictionary]) -> Dictionary:
	var worst: Dictionary = entries[0]
	var best_len: int = int(((entries[0]["lab"] as Label).text).length())

	for e: Dictionary in entries:
		var l: int = int(((e["lab"] as Label).text).length())
		if l > best_len:
			best_len = l
			worst = e

	return worst


func _pick_global_font_size_for_panels(panels: Array[Node], min_size: int, max_size: int) -> int:
	var entries: Array[Dictionary] = _entries_from_panels(panels)
	if entries.is_empty():
		return max_size

	# Disable scrolling during search to stabilize widths/layout.
	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var font: Font = (entries[0]["lab"] as Label).get_theme_font("font")

	var use_optimized: bool = OPTIMIZE_USING_WORST_LINE and _all_same_viewport(entries)
	var test_entries: Array[Dictionary] = entries
	if use_optimized:
		test_entries = [_pick_worst_entry_by_length(entries)]

	var best: int = min_size
	var lo: int = min_size
	var hi: int = max_size

	while lo <= hi:
		var mid: int = (lo + hi) / 2
		var all_fit: bool = true

		for e: Dictionary in test_entries:
			var sc: ScrollContainer = e["sc"] as ScrollContainer
			var lab: Label = e["lab"] as Label

			# IMPORTANT: use the viewport width (sc.size.x), not lab.size.x, to avoid width jitter across refreshes.
			var wrap_w_base: float = max(sc.size.x, 1.0)
			var avail_h: float = max(sc.size.y, 1.0)

			var needed_y: float = _needed_height_for_scroll_with_size(sc, font, mid, lab.text, wrap_w_base)
			if needed_y > avail_h + EPS:
				all_fit = false
				break

		if all_fit:
			best = mid
			lo = mid + 1
		else:
			hi = mid - 1

	_apply_font_and_overflow(entries, font, best, min_size)
	return best


func _apply_font_and_overflow(entries: Array[Dictionary], font: Font, font_size: int, min_size: int) -> void:
	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		var vb: VBoxContainer = e["vb"] as VBoxContainer
		var lab: Label = e["lab"] as Label

		lab.add_theme_font_size_override("font_size", font_size)

		var wrap_w_base: float = max(sc.size.x, 1.0)
		var avail_h: float = max(sc.size.y, 1.0)

		var needed_y: float = _needed_height_for_scroll_with_size(sc, font, font_size, lab.text, wrap_w_base)
		var overflow: bool = needed_y > avail_h + EPS

		if overflow:
			var h: int = ceili(needed_y)
			lab.custom_minimum_size.y = h
			vb.custom_minimum_size.y = h
		else:
			lab.custom_minimum_size.y = 0
			vb.custom_minimum_size.y = 0

		var allow_scroll: bool = overflow and (not ONLY_SCROLL_AT_MIN or font_size <= min_size)
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if allow_scroll else ScrollContainer.SCROLL_MODE_DISABLED
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _enforce_scroll_overflow(panels: Array[Node]) -> void:
	var entries: Array[Dictionary] = _entries_from_panels(panels)
	if entries.is_empty():
		return

	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		var vb: VBoxContainer = e["vb"] as VBoxContainer
		var lab: Label = e["lab"] as Label

		var font: Font = lab.get_theme_font("font")
		var font_size: int = lab.get_theme_font_size("font_size")

		var wrap_w_base: float = max(sc.size.x, 1.0)
		var avail_h: float = max(sc.size.y, 1.0)

		var needed_y: float = _needed_height_for_scroll_with_size(sc, font, font_size, lab.text, wrap_w_base)
		var overflow: bool = needed_y > avail_h + EPS

		if overflow:
			var h: int = ceili(needed_y)
			lab.custom_minimum_size.y = h
			vb.custom_minimum_size.y = h

			var allow_scroll: bool = (not ONLY_SCROLL_AT_MIN) or (font_size <= FONT_MIN)
			sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if allow_scroll else ScrollContainer.SCROLL_MODE_DISABLED
		else:
			lab.custom_minimum_size.y = 0
			vb.custom_minimum_size.y = 0
			sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _process(_delta: float) -> void:
	pass
