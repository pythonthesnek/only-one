@icon("res://addons/codex/classes/icons/LevelChunk.svg")
##Chunk of level tiles.
class_name LevelChunk extends Node3D

##If true, will generate collision mesh.
@export var enable_collisions:bool=true
##Collision layer(s) that this chunk will occupy.
@export_flags_3d_physics var collision_layer:int=1
##Collision layer(s) that this chunk will collide with.
@export_flags_3d_physics var collision_mask:int=1
