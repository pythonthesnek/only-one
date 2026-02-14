@tool
##Material used for LevelTile nodes. Supports custom material properties.
class_name LevelMaterial
extends StandardMaterial3D

@export_group("--- LEVEL TOOLS ---")
##Properties used to differentiate surface materials in collision detection.
@export var material_properties:MaterialProperties=MaterialProperties.new()

func _init() -> void:
	vertex_color_use_as_albedo = true #for face shading
	
	# DEPRECATED - default values for this material
	
	#diffuse_mode = DIFFUSE_LAMBERT
	#specular_mode = SPECULAR_DISABLED
	#metallic_specular = 0.0
	#texture_filter = TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
