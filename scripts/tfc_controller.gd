extends Camera3D
## Free-fly "TFC" style camera for Godot 4.7
## Attach this script directly to a Camera3D node.
##
## Controls:
##   W / A / S / D  -> move forward/left/back/right (relative to view)
##   Mouse          -> look around
##   Space          -> move up
##   Ctrl           -> move down
##   Shift          -> sprint (hold)
##   Esc            -> release mouse capture
##   Left click     -> re-capture mouse

@export var move_speed: float = 8.0
@export var sprint_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.15   # degrees per pixel
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0

var _yaw: float = 0.0
var _pitch: float = 0.0

# We track key states ourselves instead of trusting Input.is_key_pressed().
# Reason: holding Ctrl and pressing W (Ctrl+W) is intercepted as a shortcut
# by the OS/window manager on some platforms, which can eat the key-up
# event for W. That leaves Input's internal state (and is_key_pressed)
# thinking W is still held, so the camera keeps "walking" forever.
# Tracking our own dict + clearing it on focus loss avoids that.
var _keys_down: Dictionary = {}

const TRACKED_KEYS := [
	KEY_W, KEY_A, KEY_S, KEY_D,
	KEY_SPACE, KEY_CTRL, KEY_SHIFT,
]


func _ready() -> void:
	# Initialize yaw/pitch from the camera's current rotation so it doesn't
	# snap when the script starts.
	_yaw = rotation_degrees.y
	_pitch = rotation_degrees.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	# If the window/app loses focus (e.g. Alt-Tab, or a shortcut like
	# Ctrl+W stealing focus), any keys currently marked "down" may never
	# get a matching key-up event. Force-clear them so movement stops.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_keys_down.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, min_pitch, max_pitch)
		rotation_degrees = Vector3(_pitch, _yaw, 0.0)

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode in TRACKED_KEYS:
			_keys_down[key_event.keycode] = key_event.pressed

		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# Releasing focus/mouse is a common moment for stuck keys too.
			_keys_down.clear()

	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _is_down(keycode: Key) -> bool:
	return _keys_down.get(keycode, false)


func _process(delta: float) -> void:
	var input_dir := Vector3.ZERO

	# Forward/back/strafe relative to camera's current facing.
	if _is_down(KEY_W):
		input_dir -= transform.basis.z
	if _is_down(KEY_S):
		input_dir += transform.basis.z
	if _is_down(KEY_A):
		input_dir -= transform.basis.x
	if _is_down(KEY_D):
		input_dir += transform.basis.x

	# Vertical movement in world space (not tied to look pitch).
	if _is_down(KEY_SPACE):
		input_dir += Vector3.UP
	if _is_down(KEY_CTRL):
		input_dir -= Vector3.UP

	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()

	var speed := move_speed
	if _is_down(KEY_SHIFT):
		speed *= sprint_multiplier

	position += input_dir * speed * delta
