extends CharacterBody3D

@export var speed = 5.0
@export var sprint_multiplier = 2.0
@export var jump_velocity = 4.5
@export var mouse_sensitivity = 0.003
@export var keyboard_look_speed_deg = 120.0  # degrees/sec, for arrow-key look

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera = $Camera3D

# We track action states ourselves instead of trusting Input directly.
# Reason: holding Ctrl and pressing W (Ctrl+W) is intercepted as a shortcut
# by the OS/window manager on some platforms, which can eat the key-up
# event for W. That leaves Input's internal state (and is_action_pressed)
# thinking W is still held, so the character keeps walking forever.
# Tracking our own dict + clearing it on focus loss avoids that.
var _actions_down: Dictionary = {}

const TRACKED_ACTIONS := [
	"move_forward", "move_backwards", "move_left", "move_right", "move_fast",
	"ui_left", "ui_right", "ui_up", "ui_down",
]

# Used to auto-create any of these actions that are missing from the
# project's Input Map, so the character still works out of the box.
const DEFAULT_ACTION_KEYS := {
	"move_forward": KEY_W,
	"move_backwards": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"move_fast": KEY_SHIFT,
}


func _ensure_default_action(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)


func _ready():
	for action in DEFAULT_ACTION_KEYS:
		_ensure_default_action(action, DEFAULT_ACTION_KEYS[action])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	# If the window/app loses focus (e.g. Alt-Tab), any keys currently marked
	# "down" may never get a matching key-up event. Force-clear them so
	# movement stops.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_actions_down.clear()


func _unhandled_input(event):
	# Look around (only while mouse is captured)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

	for action in TRACKED_ACTIONS:
		if InputMap.has_action(action) and event.is_action(action):
			_actions_down[action] = event.is_pressed()

	# Release mouse on Esc
	if event.is_action_pressed("ui_cancel") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Releasing focus/mouse is a common moment for stuck keys too.
		_actions_down.clear()

	# Re-capture mouse on click (only if it was released)
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _is_action_down(action: String) -> bool:
	return _actions_down.get(action, false)


func _process(delta):
	# Arrow keys let the player look around without a mouse.
	var look_step = deg_to_rad(keyboard_look_speed_deg) * delta
	if _is_action_down("ui_left"):
		rotate_y(look_step)
	if _is_action_down("ui_right"):
		rotate_y(-look_step)
	if _is_action_down("ui_up"):
		camera.rotate_x(look_step)
	if _is_action_down("ui_down"):
		camera.rotate_x(-look_step)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))


func _physics_process(delta):
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Get movement input
	var input_dir := Vector2.ZERO
	if _is_action_down("move_forward"):
		input_dir.y -= 1
	if _is_action_down("move_backwards"):
		input_dir.y += 1
	if _is_action_down("move_left"):
		input_dir.x -= 1
	if _is_action_down("move_right"):
		input_dir.x += 1
	input_dir = input_dir.normalized()
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var current_speed = speed
	if _is_action_down("move_fast"):
		current_speed *= sprint_multiplier

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
