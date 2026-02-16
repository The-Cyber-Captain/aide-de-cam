## TouchScroll.gd (Godot 4.3+)
## ScrollContainer subclass that supports:
## - Mouse: native behavior (we do NOT consume mouse events)
## - Touch swipe-to-scroll on the content area
## - Touch scrubbing/dragging on the scrollbars themselves
##
## IMPORTANT:
## When a Control receives gui_input, event.position is already in that Control's local space.
## So for scrollbar gui_input we MUST NOT apply extra transforms.

class_name TouchScroll
extends ScrollContainer

@export var swipe_deadzone_px: float = 6.0
@export var swipe_speed: float = 1.0

@onready var vbar: VScrollBar = get_v_scroll_bar()
@onready var hbar: HScrollBar = get_h_scroll_bar()

var _touch_active := false
var _touch_started_on_bar := false
var _last_touch_pos := Vector2.ZERO
var _swiping := false

var _bar_touch_index_v := -1
var _bar_touch_index_h := -1


func _ready() -> void:
	var touch := DisplayServer.is_touchscreen_available()

	if touch:
		vbar.custom_minimum_size.x = 50
		hbar.custom_minimum_size.y = 50
	else:
		vbar.custom_minimum_size.x = 14
		hbar.custom_minimum_size.y = 14

	# Ensure bars can receive/take touch input when visible.
	# (Mouse grabber dragging remains native because we only handle ScreenTouch/ScreenDrag.)
	vbar.mouse_filter = Control.MOUSE_FILTER_STOP
	hbar.mouse_filter = Control.MOUSE_FILTER_STOP

	vbar.gui_input.connect(_on_vbar_gui_input)
	hbar.gui_input.connect(_on_hbar_gui_input)


func _gui_input(event: InputEvent) -> void:
	# Swipe-to-scroll on the content area (ignore if the touch began on scrollbars).
	# event.position here is local to THIS ScrollContainer when delivered via gui_input.
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_active = true
			_swiping = false
			_last_touch_pos = event.position
			_touch_started_on_bar = _touch_hits_scrollbar(_sc_local_to_global(event.position))
			# Don't accept yet; allow taps unless we exceed deadzone.
		else:
			_touch_active = false
			_swiping = false

	elif event is InputEventScreenDrag and _touch_active and not _touch_started_on_bar:
		var delta :Vector2= event.position - _last_touch_pos
		_last_touch_pos = event.position

		if not _swiping and delta.length() >= swipe_deadzone_px:
			_swiping = true

		if _swiping:
			scroll_horizontal -= int(delta.x * swipe_speed)
			scroll_vertical   -= int(delta.y * swipe_speed)
			accept_event()


func _on_vbar_gui_input(event: InputEvent) -> void:
	_handle_bar_touch(event, vbar, true)

func _on_hbar_gui_input(event: InputEvent) -> void:
	_handle_bar_touch(event, hbar, false)


func _handle_bar_touch(event: InputEvent, bar: ScrollBar, vertical: bool) -> void:
	# Only touch events. Leave mouse input alone so native grabber dragging works.
	# In bar.gui_input, event.position is LOCAL TO THE BAR.
	if event is InputEventScreenTouch:
		if event.pressed:
			if vertical:
				_bar_touch_index_v = event.index
			else:
				_bar_touch_index_h = event.index

			_set_scroll_from_bar_local(bar, vertical, event.position)

			# Accept on press to capture this touch so we keep getting drags.
			accept_event()
		else:
			if vertical and event.index == _bar_touch_index_v:
				_bar_touch_index_v = -1
				accept_event()
			elif (not vertical) and event.index == _bar_touch_index_h:
				_bar_touch_index_h = -1
				accept_event()

	elif event is InputEventScreenDrag:
		if vertical:
			if event.index != _bar_touch_index_v:
				return
		else:
			if event.index != _bar_touch_index_h:
				return

		_set_scroll_from_bar_local(bar, vertical, event.position)
		accept_event()


# --- Helpers ---

func _sc_local_to_global(local_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas() * local_pos


func _touch_hits_scrollbar(global_pos: Vector2) -> bool:
	# global_pos is in the same space as get_global_rect().
	return vbar.get_global_rect().has_point(global_pos) or hbar.get_global_rect().has_point(global_pos)


func _set_scroll_from_bar_local(bar: ScrollBar, vertical: bool, bar_local_pos: Vector2) -> void:
	# bar_local_pos is local to the bar.
	var track_len := bar.size.y if vertical else bar.size.x
	if track_len <= 1.0:
		return

	var t := (bar_local_pos.y / track_len) if vertical else (bar_local_pos.x / track_len)
	t = clamp(t, 0.0, 1.0)

	# For ScrollBar/Range, usable max is max_value - page.
	var usable_min := bar.min_value
	var usable_max := bar.max_value - bar.page
	if usable_max < usable_min:
		usable_max = usable_min

	var target : float = lerp(usable_min, usable_max, t)

	# Drive the ScrollContainer directly (most reliable).
	if vertical:
		scroll_vertical = int(target)
	else:
		scroll_horizontal = int(target)
