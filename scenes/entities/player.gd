extends CharacterBody3D

var speed
const WALK_SPEED = 8.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 4.8
const SENSITIVITY = 0.004

var direction

#bob variables
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

#fov variables
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = 9.8

# Weapon vars
@export var shotgun_damage = 5

# Signals
signal player_hit
var dead: bool = false

@onready var gun_anim = $Head/Camera3D/shotgun/AnimationPlayer
@onready var shotgun_ray: Node3D = $Head/Camera3D/shotgun/RayCast3D
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var decal: Decal = $Head/Camera3D/shotgun/Decal

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-40), deg_to_rad(60))


func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and dead == false:
		velocity.y = JUMP_VELOCITY
	
	
	# Handle Sprint.
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("left", "right", "up", "down")
	direction = (head.transform.basis * transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if is_on_floor() and dead == false:
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)
	
	# Head bob
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)
	
	# FOV
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	# Shooting
	if Input.is_action_just_pressed("shoot") and !gun_anim.is_playing():
		shoot()
		gun_anim.play("shoot")
	
	move_and_slide()
	


func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos


func hit():
	emit_signal("player_hit")


#func _on_player_hit() -> void:
	#head.global_position.y = -10
	#camera.rotation.z = deg_to_rad(15)


# Random spread in degrees
var spread = 3
# Number of projectiles per shot
var number_of_pellets = 8

func shoot():
	# Run this code for each pellet
	for i in range(number_of_pellets):
		# Calculate random pitch and yaw, roll is always 0
		var pitch = randf_range(-spread, spread)
		var yaw = randf_range(-spread, spread)
		var random_spread = Vector3(pitch, yaw, 0)
		# Rotate the raycast node
		shotgun_ray.set_rotation_degrees(random_spread)
		# Save the impact position
		if (
			shotgun_ray.is_colliding()
		):
			# vars
			var bullet_target_pos = shotgun_ray.global_transform * shotgun_ray.target_position
			var obj = shotgun_ray.get_collider()
			var nrml = shotgun_ray.get_collision_normal()
			var pt = shotgun_ray.get_collision_point()
			BulletDecalPool.spawn_bullet_decal(pt, nrml, obj, shotgun_ray.global_basis)
			if (
				obj.has_method("deal_damage")
			):
				obj.deal_damage(shotgun_damage)
			#var shotgun_decal = decal.instantiate()
			#shotgun_decal.global_position = shotgun_ray.get_collider().position()
		
		
		# The important part: update the raycast immediately
		shotgun_ray.force_raycast_update()
