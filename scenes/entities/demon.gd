extends CharacterBody3D

var player = null

@export var SPEED = 4.0
const ATTACK_RANGE = 2.5

@export var player_path:= "/root/World/Map/NavigationRegion3D/Player"

@onready var head: Node3D = $"../Player/Head"
@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D


var attack_animations = ["animation1", "animation2", "animation3"]


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	player = get_node(player_path)
	animated_sprite.play("animation4")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	velocity = Vector3.ZERO	
	
	nav_agent.set_target_position(player.global_transform.origin)
	var next_nav_point = nav_agent.get_next_path_position()
	
	velocity = (next_nav_point - global_transform.origin).normalized() * SPEED
	
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
	move_and_slide()
	
	if (
		global_position.distance_to(player.global_position) > ATTACK_RANGE
	):
		animated_sprite.play(attack_animations.pick_random())

	#print(animated_sprite.get_frame())
	
	if animated_sprite.get_frame() == 4:
		player.hit()
