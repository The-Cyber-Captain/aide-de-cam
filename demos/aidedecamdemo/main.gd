extends Control

const WATCH_RETRY_INTERVAL: float = 2.0
const WAIT_INTERVAL: float = 0.25
const RELAYOUT_DEBOUNCE_INTERVAL: float = 0.1
const FILENAME: String = "user://camera_capabilities.json"

# Global font fit bounds
const FONT_MIN: int = 20
const FONT_MAX: int = 45

# Tolerances / safety padding
const EPS: float = 0.5
const EXTRA_BOTTOM_PX: int = 8 # helps avoid last-line clipping at the very bottom

var _relayout_ticket: int = 0

var status_string: String = "":
	set(new_string):
		status_string = new_string
		var label: Label = get_node_or_null("%StatusLabel")
		if label != null:
			%StatusLabel.text = "Status: %s" % [new_string]


func _ready() -> void:
	status_string = "Aide-De-Cam plugin not detected"
	resized.connect(_on_main_resized)
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
		# make text invisible (for reset)
		lab.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0, 0.0))
		lab.text = str(cam_lines[idx] + "\n----END-OF-LINE----")

	# IMPORTANT: clear prior run's min-size/scroll/font overrides so layout doesn't "ratchet"
	_reset_panel_layout_state(panels)

	# Frame 1: layout settles (sizes become meaningful)
	await get_tree().process_frame

	# Choose & apply global font size (includes initial overflow enforcement)
	var chosen_size: int = _pick_global_font_size_for_panels(panels, FONT_MIN, FONT_MAX)
	var refined_size: int = await _refine_global_font_size_for_panels(panels, FONT_MIN, chosen_size)
	_apply_global_font_and_overflow(panels, refined_size)

	# Frame 2: font size + min-size can affect layout, especially on Android
	await get_tree().process_frame

	# Enforce overflow again using final geometry
	_enforce_scroll_overflow(panels)


func _on_main_resized() -> void:
	# Debounce frequent resize events and reflow with final viewport geometry.
	_relayout_ticket += 1
	_relayout_visible_panels_deferred()


func _relayout_visible_panels_deferred() -> void:
	var ticket: int = _relayout_ticket
	await get_tree().create_timer(RELAYOUT_DEBOUNCE_INTERVAL).timeout
	if ticket != _relayout_ticket:
		return

	var panels: Array[Node] = %GridContainer.get_children()
	if panels.is_empty():
		return

	_reset_panel_layout_state(panels)
	await get_tree().process_frame

	var chosen_size: int = _pick_global_font_size_for_panels(panels, FONT_MIN, FONT_MAX)
	var refined_size: int = await _refine_global_font_size_for_panels(panels, FONT_MIN, chosen_size)
	_apply_global_font_and_overflow(panels, refined_size)
	await get_tree().process_frame

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


func _apply_margin_constants_from_theme(mc: MarginContainer, custom_theme: Theme) -> void:
	if custom_theme == null:
		return

	var left: int = custom_theme.get_constant("margin_left", "MarginContainer")
	var right: int = custom_theme.get_constant("margin_right", "MarginContainer")
	var top: int = custom_theme.get_constant("margin_top", "MarginContainer")
	var bottom: int = custom_theme.get_constant("margin_bottom", "MarginContainer")

	mc.add_theme_constant_override("margin_left", left)
	mc.add_theme_constant_override("margin_right", right)
	mc.add_theme_constant_override("margin_top", top)
	mc.add_theme_constant_override("margin_bottom", bottom)


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
	_apply_margin_constants_from_theme(mc, pan.theme)

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
# Font fitting + overflow behavior
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


func _entry_needed_height_for_font(sc: ScrollContainer, lab: Label, font: Font, font_size: int) -> float:
	# Conservative measurement: consider both no-scrollbar width and scrollbar-present width.
	var wrap_w_no_bar: float = max(sc.size.x, 1.0)
	var wrap_w_with_bar: float = max(wrap_w_no_bar - _vscroll_thickness(sc), 1.0)

	var s_no_bar: Vector2 = _measure_wrapped_size(font, font_size, lab.text, wrap_w_no_bar)
	var s_with_bar: Vector2 = _measure_wrapped_size(font, font_size, lab.text, wrap_w_with_bar)

	var needed_y: float = max(s_no_bar.y, s_with_bar.y)
	needed_y += float(font.get_descent(font_size)) + float(EXTRA_BOTTOM_PX)
	return needed_y


func _entry_needed_height_post_layout(vb: VBoxContainer, lab: Label) -> float:
	# Ground-truth fallback using engine layout result after font override.
	var vb_min_h: float = vb.get_combined_minimum_size().y
	var lab_min_h: float = lab.get_combined_minimum_size().y
	return max(vb_min_h, lab_min_h) + float(EXTRA_BOTTOM_PX)


func _entries_from_panels(panels: Array[Node]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for p: Node in panels:
		var sc: ScrollContainer = _get_scroll_from_panel(p)
		var vb: VBoxContainer = sc.get_child(0) as VBoxContainer
		var lab: Label = vb.get_child(0) as Label
		entries.append({ "sc": sc, "vb": vb, "lab": lab })
	return entries


func _entries_fit_without_scrollbars(entries: Array[Dictionary], font_size: int) -> bool:
	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		var lab: Label = e["lab"] as Label
		var font: Font = lab.get_theme_font("font")
		var avail_h: float = max(sc.size.y, 1.0)
		var needed_y: float = _entry_needed_height_for_font(sc, lab, font, font_size)
		if needed_y > avail_h + EPS:
			return false
	return true


func _pick_global_font_size_for_panels(panels: Array[Node], min_size: int, max_size: int) -> int:
	var entries: Array[Dictionary] = _entries_from_panels(panels)
	var lo_bound: int = min(min_size, max_size)
	var hi_bound: int = max(min_size, max_size)
	if entries.is_empty():
		return lo_bound

	# Disable scrollbars during fit search so width remains stable.
	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		## make font visible again; watch it shrink to fit.
		sc.get_child(0).get_child(0).remove_theme_color_override("font_color")

	# Rule: largest shared size in [FONT_MIN, FONT_MAX] that fits all panels without scrollbars.
	var lo: int = lo_bound
	var hi: int = hi_bound
	var best: int = lo_bound

	while lo <= hi:
		var mid: int = int ((lo + hi) / 2.0)
		if _entries_fit_without_scrollbars(entries, mid):
			best = mid
			lo = mid + 1
		else:
			hi = mid - 1

	return best


func _apply_font_only_no_scroll(entries: Array[Dictionary], font_size: int) -> void:
	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		var vb: VBoxContainer = e["vb"] as VBoxContainer
		var lab: Label = e["lab"] as Label

		lab.add_theme_font_size_override("font_size", font_size)
		lab.custom_minimum_size.y = 0
		vb.custom_minimum_size.y = 0
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _entries_fit_without_scrollbars_real(entries: Array[Dictionary], font_size: int) -> bool:
	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		var vb: VBoxContainer = e["vb"] as VBoxContainer
		var lab: Label = e["lab"] as Label
		var font: Font = lab.get_theme_font("font")
		var avail_h: float = max(sc.size.y, 1.0)
		var needed_y_estimate: float = _entry_needed_height_for_font(sc, lab, font, font_size)
		var needed_y_real: float = _entry_needed_height_post_layout(vb, lab)
		if max(needed_y_estimate, needed_y_real) > avail_h + EPS:
			return false
	return true


func _refine_global_font_size_for_panels(panels: Array[Node], min_size: int, start_size: int) -> int:
	var entries: Array[Dictionary] = _entries_from_panels(panels)
	if entries.is_empty():
		return min_size

	var specimen_size: int = max(start_size, min_size)
	while specimen_size >= min_size:
		_apply_font_only_no_scroll(entries, specimen_size)
		await get_tree().process_frame
		if _entries_fit_without_scrollbars_real(entries, specimen_size):
			return specimen_size
		specimen_size -= 1

	return min_size


func _apply_global_font_and_overflow(panels: Array[Node], font_size: int) -> void:
	var entries: Array[Dictionary] = _entries_from_panels(panels)
	if entries.is_empty():
		return

	for e: Dictionary in entries:
		var sc: ScrollContainer = e["sc"] as ScrollContainer
		var vb: VBoxContainer = e["vb"] as VBoxContainer
		var lab: Label = e["lab"] as Label
		var font: Font = lab.get_theme_font("font")

		lab.add_theme_font_size_override("font_size", font_size)

		var avail_h: float = max(sc.size.y, 1.0)
		var needed_y_estimate: float = _entry_needed_height_for_font(sc, lab, font, font_size)
		var needed_y_real: float = _entry_needed_height_post_layout(vb, lab)
		var needed_y: float = max(needed_y_estimate, needed_y_real)
		var overflow: bool = needed_y > avail_h + EPS

		if overflow:
			var h: int = ceili(needed_y)
			lab.custom_minimum_size.y = h
			vb.custom_minimum_size.y = h
			sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		else:
			lab.custom_minimum_size.y = 0
			vb.custom_minimum_size.y = 0
			sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _enforce_scroll_overflow(panels: Array[Node]) -> void:
	# Re-apply using the currently selected global size after layout settles.
	if panels.is_empty():
		return

	var entries: Array[Dictionary] = _entries_from_panels(panels)
	if entries.is_empty():
		return

	var font_size: int = (entries[0]["lab"] as Label).get_theme_font_size("font_size")
	_apply_global_font_and_overflow(panels, font_size)


func _process(_delta: float) -> void:
	pass
