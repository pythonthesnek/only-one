@tool
@icon("icons/LevelTile.svg")
##Used to source geometry for the LevelBuilder node. Intended for editor use only.
class_name LevelTile
extends Node3D

##Dimensions of tile shape.
@export var sh_dimensions:Vector3=Vector3.ONE : set = _set_dimensions
##Offset of tile from origin.
@export var sh_offset:Vector3=Vector3.ZERO : set = _set_offset
##If true, inverts face normals. Ideal for making very simple interior levels.
@export var flip_faces:bool=false : set = _set_flip_faces
##If true, will display flipped tiles correctly in the editor. Disabling this may lead to extra readability.
@export var flip_faces_in_editor:bool=true : set = _set_flip_faces_in_editor

##If true, will be added separately as an alpha tile.
@export var alpha:bool=false

@export_group("Materials")
##If true, changing tile shape will stretch the texture.
@export var stretch_textures:bool=false : set = _set_stretch_textures
##If true, will make the texture scale independently from the world scale.
@export var ignore_world_scale:bool=false
##Size of textures.
@export var texture_scale:float=1.0 : set = _set_texture_scale
##3D texture offset.
@export var texture_offset:Vector3=Vector3.ZERO : set = _set_texture_offset
##If true, will make this tile ignore face shading.
@export var ignore_shading:bool=false
##Custom face shading to use only on this tile.
@export var shading_override:FaceShading
##Material for tile. Use LevelMaterial for bonus functionality.
@export var material:Material : set = _set_material
##Material for each face. Leave blank for default material. Recommended to use custom LevelMaterial type.
@export var material_overrides:Array[Material]=[null, null, null, null, null, null]: set = _set_material_overrides

const DEFAULT_MATERIAL = preload("res://addons/codex/materials/material_default.tres")

var internal_material:Material #the actual material applied to the tile
var chunk_owner:LevelChunk #chunk that this tile belongs to - is set by LevelBuilder


func _enter_tree() -> void:
	if Engine.is_editor_hint(): #if in editor
		await _stall()
		_exit_tree() #clear all previous meshes
		#Add and remove meshes
		for n in 6: #one for each face
			var m = MeshInstance3D.new()
			add_child(m)
			m.set_owner(self)
		
		await _stall()
		_update_mesh() #generate mesh

func _stall() -> void: #a slightly more sophisticated process frame
	if is_inside_tree():
		await get_tree().process_frame

func _exit_tree() -> void: #delete children
	if is_inside_tree():
		for ch in get_children():
			ch.free()

func _ready() -> void:
	if !Engine.is_editor_hint(): #if in game
		push_error("Do not include LevelTile nodes in your game levels! Only use output meshes.")

func _set_dimensions(v:Vector3) -> void:
	#Limiting vector extents to be within tile
	v.x = clamp(v.x, 0, 1)
	v.y = clamp(v.y, 0, 1)
	v.z = clamp(v.z, 0, 1)
	sh_dimensions = v
	_set_offset(sh_offset)
func _set_offset(v:Vector3) -> void:
	#Limiting vector extents to be within tile
	v.x = clamp(v.x, 0, 1.0-sh_dimensions.x)
	v.y = clamp(v.y, 0, 1.0-sh_dimensions.y)
	v.z = clamp(v.z, 0, 1.0-sh_dimensions.z)
	sh_offset = v
	_update_mesh()
func _set_flip_faces(v:bool) -> void:
	flip_faces = v
	_update_mesh()
func _set_flip_faces_in_editor(v:bool) -> void:
	flip_faces_in_editor = v
	_update_mesh()
func _set_stretch_textures(v:bool) -> void:
	stretch_textures = v
	_update_mesh()
func _set_texture_scale(v:float) -> void:
	texture_scale = v
	_update_mesh()
func _set_texture_offset(v:Vector3) -> void:
	texture_offset = v
	_update_mesh()
func _set_material_overrides(v:Array[Material]) -> void:
	if v.size() > 6 or v.size() < 6:
		v.resize(6) #forcing array size to 6 to avoid crashes
	
	material_overrides = v
	_update_mesh()

func _set_material_to_default(): #reset material
	if "MATERIAL" in self: #special material for subclasses
		internal_material = get("MATERIAL")
	else: #default material
		internal_material = DEFAULT_MATERIAL

func _update_mesh(): #generate mesh
	var st:SurfaceTool #new mesh data
	
	if material != null: #if custom material applied
		internal_material = material #update internal material
	else:
		_set_material_to_default() #reset material
	
	for f in 6: #6 faces
		st = SurfaceTool.new() #new mesh
		
		st.begin(Mesh.PRIMITIVE_TRIANGLES) #begin construction
		var shape = _generate_shape(true) #get shape data
		
		match f: #generate each face
			Codex.Face.FRONT:
				Codex.new_face(st, Vector3(1,1,1), Codex.Face.FRONT, Vector3.BACK, Vector3.ZERO, Color.WHITE, shape)
			Codex.Face.BACK:
				Codex.new_face(st, Vector3(1,1,1), Codex.Face.BACK, Vector3.FORWARD, Vector3.ZERO, Color.WHITE, shape)
			Codex.Face.TOP:
				Codex.new_face(st, Vector3(1,1,1), Codex.Face.TOP, Vector3.UP, Vector3.ZERO, Color.WHITE, shape)
			Codex.Face.BOTTOM:
				Codex.new_face(st, Vector3(1,1,1), Codex.Face.BOTTOM, Vector3.DOWN, Vector3.ZERO, Color.WHITE, shape)
			Codex.Face.LEFT:
				Codex.new_face(st, Vector3(1,1,1), Codex.Face.LEFT, Vector3.LEFT, Vector3.ZERO, Color.WHITE, shape)
			Codex.Face.RIGHT:
				Codex.new_face(st, Vector3(1,1,1), Codex.Face.RIGHT, Vector3.RIGHT, Vector3.ZERO, Color.WHITE, shape)
		
		if get_child_count() > 0: #if has meshes
			var mesh = st.commit() #create mesh
			var meshinstance = get_child(f) #add mesh to corresponding face
			if meshinstance is MeshInstance3D: #if child is correct type
				meshinstance.mesh = mesh #set mesh
				if material_overrides[f] == null: #if there is no material override
					meshinstance.material_override = internal_material #set to main material
				else: #if there is a material override
					meshinstance.material_override = material_overrides[f] #set to override material

func _generate_shape(from_tile:bool=false) -> TileShape: #generate a new shape resource
	var shape:TileShape = TileShape.new() #new TileShape resource
	shape.sh_dimensions = sh_dimensions
	shape.sh_offset = sh_offset
	shape.ignore_world_scale = ignore_world_scale
	shape.stretch_textures = stretch_textures
	shape.texture_scale = texture_scale
	shape.texture_offset = texture_offset
	if !from_tile or flip_faces_in_editor: #if builder is accessing or flip faces is enabled
		shape.flip_faces = flip_faces
	
	return shape #return the shape data

func _set_material(new_material) -> void: #updating material
	if new_material != null: #if custom material applied
		internal_material = new_material #update internal material
	else:
		_set_material_to_default() #reset material
	
	material = new_material #update material value
	await _stall()
	_update_mesh()
