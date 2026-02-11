class_name TouchButt
extends Button

var _touch_armed := false
const TOUCH_SLOP_PX := 12.0

# Cache theme items so we can swap them in/out cheaply.
@onready var _sb_pressed: StyleBox = get_theme_stylebox("pressed")
@onready var _sb_normal: StyleBox  = get_theme_stylebox("normal")
@onready var _sb_hover: StyleBox   = get_theme_stylebox("hover")

@onready var _fc_pressed: Color = get_theme_color("font_pressed_color")
@onready var _fc_normal: Color  = get_theme_color("font_color")
@onready var _fc_hover: Color   = get_theme_color("font_hover_color")

func _set_touch_visual_pressed(on: bool) -> void:
	if on:
		# Force the pressed look while finger is down.
		add_theme_stylebox_override("normal", _sb_pressed)
		add_theme_stylebox_override("hover", _sb_pressed) # prevents hover artifact during touch
		add_theme_color_override("font_color", _fc_pressed)
		add_theme_color_override("font_hover_color", _fc_pressed)
	else:
		# Revert to whatever the theme normally does.
		add_theme_stylebox_override("normal", _sb_normal)
		add_theme_stylebox_override("hover", _sb_hover)
		add_theme_color_override("font_color", _fc_normal)
		add_theme_color_override("font_hover_color", _fc_hover)

func _gui_input(event: InputEvent) -> void:
	if disabled:
		return

	if event is InputEventScreenTouch:
		var local_pos : Vector2 = event.position # in _gui_input: local-to-control coords

		if event.pressed:
			_touch_armed = Rect2(Vector2.ZERO, size).has_point(local_pos)
			if _touch_armed:
				_set_touch_visual_pressed(true)
				button_down.emit() # optional, but matches normal button behavior
				accept_event()
		else:
			var inside := Rect2(Vector2.ZERO, size).grow(TOUCH_SLOP_PX).has_point(local_pos)

			if _touch_armed:
				_set_touch_visual_pressed(false)
				button_up.emit() # optional

				if inside:
					pressed.emit()

				accept_event()

			_touch_armed = false
