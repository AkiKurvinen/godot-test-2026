extends CharacterBody3D
# Attach this script to your character's root node (CharacterBody3D).
# Expected child nodes:
#   AnimationPlayer  - with animations named "Walk", "Jump", "Push"
#   Camera3D         - direct child, used as a free-floating 3rd person orbit camera
# Expected Input Map actions:
#   move_forward, move_backwards, strafe_left, strafe_right, jump, action

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $Camera3D

# --- Movement ---
@export var speed: float = 5.0
@export var sprint_multiplier: float = 2.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 10.0  # how fast the character turns to face movement

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Camera (free orbiting 3rd person) ---
@export var mouse_sensitivity: float = 0.003
@export var keyboard_look_speed_deg: float = 120.0  # degrees/sec, for arrow-key look
@export var camera_distance: float = 6.0
@export var camera_height: float = 2.0
@export var min_pitch_deg: float = -60.0
@export var max_pitch_deg: float = 70.0
@export var zoom_step: float = 0.5
@export var min_camera_distance: float = 2.0
@export var max_camera_distance: float = 12.0

var camera_yaw: float = 0.0
var camera_pitch: float = deg_to_rad(2.0)

# Track whether Jump is currently playing so movement anim doesn't interrupt it.
var is_jumping: bool = false

# We track action states ourselves instead of trusting Input directly.
# Reason: holding Ctrl and pressing W (Ctrl+W) is intercepted as a shortcut
# by the OS/window manager on some platforms, which can eat the key-up
# event for W. That leaves Input's internal state (and is_action_pressed)
# thinking W is still held, so the character keeps walking forever.
# Tracking our own dict + clearing it on focus loss avoids that.
var _actions_down: Dictionary = {}

const TRACKED_ACTIONS := [
	"move_forward", "move_backwards", "move_left", "move_right", "action",
	"move_fast",
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
	"action": KEY_F,
	"move_fast": KEY_SHIFT,
}


func _ensure_default_action(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)


func _ready() -> void:
	for action in DEFAULT_ACTION_KEYS:
		_ensure_default_action(action, DEFAULT_ACTION_KEYS[action])

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Make sure Walk loops. You can also set this in the Animation panel
	# by setting the animation's Loop Mode to "Linear Loop" instead.
	if anim_player.has_animation("Walk"):
		anim_player.get_animation("Walk").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("Run"):
		anim_player.get_animation("Run").loop_mode = Animation.LOOP_LINEAR

	# Jump and Push should NOT loop — they play once.
	if anim_player.has_animation("Jump"):
		anim_player.get_animation("Jump").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("Push"):
		anim_player.get_animation("Push").loop_mode = Animation.LOOP_NONE

	anim_player.animation_finished.connect(_on_animation_finished)

	# Browser tab-close/pointer-lock safety net and alt-tab cursor handling
	# now live in browser_input_fixes.gd — add that script to a Node3D
	# anywhere in the scene tree instead of handling it here.

	# Position the camera correctly on the first frame instead of waiting a tick.
	_update_camera()


func _notification(what: int) -> void:
	# If the window/app loses focus (e.g. Alt-Tab), any keys currently marked
	# "down" may never get a matching key-up event. Force-clear them so
	# movement stops.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_actions_down.clear()


func _unhandled_input(event: InputEvent) -> void:
	# Orbit the camera with mouse motion while the mouse is captured.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * mouse_sensitivity
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

	for action in TRACKED_ACTIONS:
		if InputMap.has_action(action) and event.is_action(action):
			_actions_down[action] = event.is_pressed()

	# Let the player free the mouse with Esc, and re-capture on click.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Releasing focus/mouse is a common moment for stuck keys too.
		_actions_down.clear()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Mouse wheel zooms the camera in/out.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clamp(camera_distance - zoom_step, min_camera_distance, max_camera_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clamp(camera_distance + zoom_step, min_camera_distance, max_camera_distance)


func _is_action_down(action: String) -> bool:
	return _actions_down.get(action, false)


func _physics_process(delta: float) -> void:
	# --- Gravity ---
	if not is_on_floor():
		velocity.y -= gravity * delta

	# --- Jump ---
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_play_once("Jump")

	# --- Camera-relative movement input ---
	# Positive = forward / right respectively.
	var input_forward := 0.0
	if _is_action_down("move_forward"):
		input_forward += 1.0
	if _is_action_down("move_backwards"):
		input_forward -= 1.0
	var input_strafe := 0.0
	if _is_action_down("move_right"):
		input_strafe += 1.0
	if _is_action_down("move_left"):
		input_strafe -= 1.0

	var cam_basis := camera.global_transform.basis
	var cam_forward := -cam_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var move_dir := (cam_forward * input_forward + cam_right * input_strafe)
	var current_speed := speed
	if _is_action_down("move_fast"):
		current_speed *= sprint_multiplier

	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed

		# Rotate the character to face the direction it's moving.
		var target_yaw := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * rotation_speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)

	move_and_slide()


func _process(delta: float) -> void:
	# Arrow keys let the player look around without a mouse.
	var look_step := deg_to_rad(keyboard_look_speed_deg) * delta
	if _is_action_down("ui_left"):
		camera_yaw += look_step
	if _is_action_down("ui_right"):
		camera_yaw -= look_step
	if _is_action_down("ui_up"):
		camera_pitch += look_step
	if _is_action_down("ui_down"):
		camera_pitch -= look_step
	camera_pitch = clamp(camera_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

	_update_camera()
	_update_animation()


func _update_camera() -> void:
	# Orbit around a pivot above the character, independent of the
	# character's own rotation, so turning the body doesn't spin the camera.
	var pivot: Vector3 = global_position + Vector3.UP * camera_height
	var offset := Vector3(0.0, 0.0, camera_distance)
	offset = offset.rotated(Vector3.RIGHT, camera_pitch)
	offset = offset.rotated(Vector3.UP, camera_yaw)
	camera.global_position = pivot + offset
	camera.look_at(pivot, Vector3.UP)


func _update_animation() -> void:
	# Jump takes priority — don't let movement/push animations override it.
	if is_jumping:
		return

	if _is_action_down("action"):
		_play_once("Push")
		return

	var is_moving := _is_action_down("move_forward") \
		or _is_action_down("move_backwards") \
		or _is_action_down("move_left") \
		or _is_action_down("move_right")

	if is_moving:
		var movement_animation := "Run" if _is_action_down("move_fast") \
			and anim_player.has_animation("Run") else "Walk"
		if anim_player.current_animation != movement_animation or not anim_player.is_playing():
			anim_player.play(movement_animation)
	else:
		if anim_player.current_animation != "":
			anim_player.stop()


func _play_once(anim_name: String) -> void:
	if anim_name == "Jump":
		is_jumping = true
	anim_player.play(anim_name)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Jump":
		is_jumping = false
