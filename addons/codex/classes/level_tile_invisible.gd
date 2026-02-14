@tool
##Used to source invisible collision geometry for the LevelBuilder node. Intended for editor use only.
class_name LevelTileInvisible
extends LevelTile

const MATERIAL = preload("res://addons/codex/materials/material_invis_wall.tres")

func _init() -> void:
	alpha = true
