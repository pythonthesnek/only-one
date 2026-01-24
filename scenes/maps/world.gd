extends Node3D


@onready var hit_rect: TextureRect = $UI/HitRect
@onready var spawns: Node3D = $Map/Spawns
@onready var navigation_region_3d: NavigationRegion3D = $Map/NavigationRegion3D

var demon = load("res://scenes/entities/demon.tscn")
var instance


func _ready() -> void:
	randomize()


func _on_player_player_hit() -> void:
	hit_rect.visible = true
	await get_tree().create_timer(0.2).timeout
	hit_rect.visible = false


func _get_random_child(parent_node):
	var random_id = randi() % parent_node.get_child_count()
	return parent_node.get_child(random_id)

func _on_demon_spawn_timer_timeout() -> void:
	var spawn_point = _get_random_child(spawns).global_position
	instance = demon.instantiate()
	instance.position = spawn_point
	navigation_region_3d.add_child(instance)
