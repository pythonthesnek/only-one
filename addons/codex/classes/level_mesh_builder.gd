@tool
@icon("icons/LevelBuilder.svg")
##Generates optimised geometry out of all LevelTile-derived nodes. Intended for editor use only.
class_name LevelBuilder
extends Node

const INVIS_MATERIAL = preload("res://addons/codex/materials/material_invis_wall.tres")
const NODRAW_MATERIAL = preload("res://addons/codex/materials/material_nodraw.tres")
const FILEPATH = "res://codex_layouts"

@export var filename:String = "" : set = _set_filename
##Node where final geometry is stored.
@export var output_folder:Node3D
##Node that contains level geometry (LevelTiles and LevelChunks).
@export var geometry_folder:Node3D
##The scene root (used to determine ownership).
@export var scene_root:Node

@export_group("General")
##Tile size in metres.
@export var world_scale:Vector3=Vector3(2.0,2.0,2.0)
##Colour multiplier for each face, can be used for cheap shading effect.
@export var face_shading:FaceShading
##If true, will make all tiles have flipped faces on build. Useful for indoor levels.
@export var force_flip_faces:bool=false
##If true, will disable all warnings for overlapping tiles of different shapes.
@export var disable_overlap_warning:bool=false

@export_group("Automatic Culling")
##If true, will automatically cull faces that aren't enclosed. Best for indoor levels. Outdoor levels can still be made
## if invisible tiles or cull tiles are placed around outdoor areas of the level.
##Do not use for levels made of tiles with flipped faces.
@export var interior_mode:bool=false
##The distance (in tiles) that will be scanned before deciding to cull a face.
##Lower values are less accurate but may result in faster build times.
@export var scan_radius:int=30
##The height level at which bottom faces will be culled. Used for level borders. 
@export var cull_bottom:int = -10000 : set = _set_cull_bottom
##The height level at which top faces will be culled. Used for level borders
@export var cull_top:int = 10000 : set = _set_cull_top

@export_group("Baked Lighting")
##If true, generates a UV2 to use for lightmap generation.
@export var use_uv2:bool=false
##Lightmap detail. Lower values are more detailed but will take longer to bake.
@export_range(0.01, 1.0) var light_map_texel_size:float=0.2


var chunk_array:Array[LevelChunk]

var geometry_array:Array[Object] #array of all LevelTile nodes in geometry folder and subfolders
var bounding_box:Array[Vector3] #coordinate range containing all geometry
var chunkpos:Vector3i #position of current chunk
var chunk_size:Vector3i = Vector3i.ZERO #size of chunks on each axis

var material_array:Array[Material] #array of all used materials
var current_material:Material #current material for mesh iteration
var shape:TileShape #current shape iteration for face building

var st:SurfaceTool = SurfaceTool.new() #mesher

var mesh_count:int #how many meshes have been created, used for naming
var face_count:int #for manual optimisation purposes
var scans:int = 0 #amount of cull scans done for auto culling
var has_crashed:bool=false #stops construction if true

var message_array:Array[String] #a list of messages to print once geometry is generaed

#other projection axes to check as well as main axis when calculating interior face culling
const X_SUB_ARRAY:Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN] #left/right
const Y_SUB_ARRAY:Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT] #up/down
const Z_SUB_ARRAY:Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT] #forward/back

func _error(error:String) -> void: #error message function
	push_error("Couldn't build level geometry ("+error+").")
func _queue_message(mess:String) -> void: #queue messages for later printing
	if !message_array.has(mess): #Ensures no repeat messages
		message_array.append(mess)


func _set_filename(text: String) -> void:
	#Format filename correctly
	text = text.to_lower() #force to lowercase
	text = text.replace(" ", "_") #remove spaces
	text = text.split(".")[0] #remove any user-added file extensions
	text = text.validate_filename() #make appropriate for filename
	
	filename = text #update filename

func _validate_save_folder() -> void:
	var d:DirAccess = DirAccess.open("res://")
	
	if !d.dir_exists_absolute(FILEPATH):
		d.make_dir_absolute(FILEPATH)
		print("Created folder "+FILEPATH)

func _update_owners_recursive(origin:Node, current:Node) -> void:
	for n:Node in current.get_children():
		n.set_owner(origin)
		_update_owners_recursive(origin, n)

func save_geometry_to_file() -> void:
	if !filename.is_valid_filename():
		push_error("Filename '" + filename + "' is invalid")
		return
	if filename.is_empty():
		push_error("No filename given")
		return
	if !output_folder or !scene_root:
		push_error("LevelBuilder not properly configured -- cannot save")
		return
	
	_validate_save_folder() #create save folder
	
	
	#Pack output folder into PackedScene
	var temp_name:String = output_folder.name #save old name
	output_folder.name = "layout_"+filename #set name for saving
	_update_owners_recursive(output_folder, output_folder) #set owner for scene packing
	
	var ps:PackedScene = PackedScene.new()
	ps.pack(output_folder)
	
	#Saving File
	var path:String = FILEPATH + "/layout_" + filename + ".tscn"
	ResourceSaver.save(ps, path)
	
	print("Saved output geometry to '" + path + "'")
	
	output_folder.name = temp_name
	_update_owners_recursive(scene_root, output_folder) #set owner back to normal


func _set_cull_top(v:int)->void:
	v = max(v, cull_bottom+1) #can't go lower than cull_bottom
	cull_top = v
func _set_cull_bottom(v:int)->void:
	v = min(v, cull_top-1) #can't go higher than cull_top
	cull_bottom = v

func _build_geometry() -> void:
	#Reset all key values
	face_count = 0
	scans = 0
	message_array = []
	has_crashed = false
	chunk_size = Vector3i.ZERO
	mesh_count = 0
	
	#Errors
	if output_folder == null:
		_error("no output folder specified")
		return
	if geometry_folder == null:
		_error("no geometry folder specified")
		return
	if output_folder == geometry_folder:
		_error("geometry and output folders are identical")
		return
	if geometry_folder.get_child_count() == 0:
		_error("geometry folder is empty")
		return
	if scene_root == null:
		_error("no scene root specified")
		return
	
	for ch in output_folder.get_children(): #clear output folder
		ch.free() #instant free to avoid name duplicates
	await get_tree().process_frame
	
	chunk_array = [] #clear array
	geometry_array = [] #clear array
	if not _append_chunks(): #get all valid geometry
		return #if crashed, stop
	
	print("\nFound "+str(chunk_array.size())+" chunks.") #print tile amount
	
	print("Found "+str(geometry_array.size())+" tiles.") #print tile amount
	
	_calculate_bounding_box() #used for chunk sizing
	#and massively increases performance when doing auto culling
	
	if not _calculate_materials(): #get all materials
		return #if crashed, stop
	
	#Calculating chunk size
	var bbmin:Vector3 = bounding_box[0] #bounding box min
	var bbmax:Vector3 = bounding_box[1] #bounding box max
	
	#Generate meshes for each chunk
	for ch in chunk_array:
		await get_tree().process_frame
		if not await _generate_meshes(ch): #build meshes
			return #if an error occurred, stop
	
	#Success message
	print("Successfully built level geometry with "+str(face_count)+" faces.")
	
	geometry_array = [] #clear geometry array to save memory
	chunk_array = [] #clear chunk array
	material_array = [] #clear material array to save memory
	
	for mess in message_array: #cycle through message array
		print(mess) #print all messages
	message_array = [] #clear message array to save memory
	
	if interior_mode:
		print(str(scans) + " cull scans performed.") #amount of scans performed

var material_faces_in_chunk:int = 0 #faces counted for this chunk
func _generate_meshes(chunk:LevelChunk) -> bool: #function to create meshes and collisions etc
	#Add a Node3D for each chunk
	var chunk_node:Node3D = Node3D.new()
	chunk_node.name = chunk.name
	output_folder.add_child(chunk_node)
	chunk_node.set_owner(scene_root)
	
	for m in material_array: #make a different mesh for each material
		material_faces_in_chunk = 0 #start count over
		
		st = SurfaceTool.new() #refresh surface tool
		st.begin(Mesh.PRIMITIVE_TRIANGLES) #enable surface tool
		
		current_material = m #iterates through all tiles that are using this material
		
		if not await _cycle_tiles(chunk): #go through all tiles
			return false #if crashed, stop
		
		if has_crashed: #made true by certain error conditions in other functions
			return false #if crashed, stop
		
		#Finalising the mesh
		if material_faces_in_chunk > 0: #if any faces were generated
			st.generate_tangents() #generate tangents for normal maps
			st.set_material(m) #set mesh material
			var mesh:Mesh = st.commit() #finalise mesh
			
			if mesh.get_surface_count() > 0: #If there are faces. Prevents crashes when doing chunking
				#Visual Mesh Generation
				if use_uv2: #if uv2 enabled
					mesh.lightmap_unwrap(output_folder.global_transform, light_map_texel_size) #create uv2
					_queue_message("Generated UV2 with a texel size of "+str(light_map_texel_size)) #uv2 success message
				
				var meshinstance:Node3D = MeshInstance3D.new() #create new mesh
				if m != INVIS_MATERIAL: #if not invisible wall
					meshinstance.mesh = mesh
					meshinstance.name = "Mesh"+"%03d"%mesh_count #consistent mesh naming to avoid lightmap dependency errors
				else: #if invisible wall
					meshinstance = Node3D.new() #turn it into a node instead of a mesh
					meshinstance.name = "InvisibleWalls"
				
				chunk_node.add_child(meshinstance) #add meshinstance node
				meshinstance.set_owner(scene_root) #adds to editor
				
				#Collision Generation
				var should_generate_collider:bool = chunk.enable_collisions #set this to main value
				
				if should_generate_collider: #if collisions should be generated
					#Generating static body to house collider
					var staticbody:StaticBody3D = StaticBody3D.new()
					
					#Addding special LevelMaterial properties
					if m is LevelMaterial:
						#Get MaterialProperties info and add to StaticBody
						staticbody.physics_material_override = m.material_properties.physics_material #physics
						staticbody.set_meta(&"material_id", m.material_properties.material_id) #mID
					
					#Setting up collision info
					staticbody.collision_layer = chunk.collision_layer
					staticbody.collision_mask = chunk.collision_mask
					meshinstance.add_child(staticbody) #add the staticbody
					
					#Generating actual collision shape to parent to static body
					var collision_shape:CollisionShape3D = CollisionShape3D.new()
					collision_shape.shape = mesh.create_trimesh_shape() #generate collision shape from mesh
					staticbody.add_child(collision_shape) #add collision shape to the staticbody
					
					staticbody.set_owner(scene_root) #adds to editor
					collision_shape.set_owner(scene_root) #adds to editor
				
				mesh_count += 1 #mesh count for naming purposes
		else:
			st = null #remove reference to surfacetool
		
		await get_tree().process_frame #fires per-material to help performance
	
	return true


func _append_chunks() -> bool:
	for c in geometry_folder.get_children():
		if c is LevelChunk:
			if !_append_geometry(c, c): #iterate through all children
				return false #crashed
			
			chunk_array.append(c) #add chunk to array
		else:
			_error("geometry folder has non-LevelChunk nodes as immediate children -- please parent all children of the geometry folder to a LevelChunk node")
			return false #crashed
	
	return true #good to go

func _append_geometry(folder:Object, chunk:LevelChunk) -> bool: #goes through all folders and subfolders to find tiles
	for t in folder.get_children(): #iterate through folder
		if t is LevelChunk:
			_error("chunk '"+str(t.name)+"' is the descendant of another chunk ('"+str(folder.name)+"') -- chunk hierarchies are not supported")
			return false #crashed
		
		if t is LevelTile: #if a tile
			t.chunk_owner = chunk #update chunk ownership reference
			geometry_array.append(t) #add tile to array
			if t.get_child_count() > 0: #if there are children
				for ch in t.get_children(): #get children
					if ch is LevelTile: #if is a tile
						_error(str(t.name)+" has a child tile")
						return false #stops geometry building
		else: #if not a tile
			#allows infinite subfolders
			if t.get_child_count() > 0: #if has children
				var _result:bool = _append_geometry(t, chunk) #cycle through subfolder children
	
	return true #geometry is clear to begin

func _calculate_bounding_box() -> void:
	bounding_box = [Vector3(10000, 10000, 10000), Vector3(-10000, -10000, -10000)] #absurd values to begin with
	#[0] = min and [1] = max
	
	for t in geometry_array: #for every tile in geometry array
		#checking one axis at a time gives a more accurate result
		if t.global_position.x < bounding_box[0].x: #setting min x
			bounding_box[0].x = t.global_position.x
		if t.global_position.y < bounding_box[0].y: #setting min y
			bounding_box[0].y = t.global_position.y
		if t.global_position.z < bounding_box[0].z: #setting min y
			bounding_box[0].z = t.global_position.z
		
		if t.global_position.x > bounding_box[1].x: #setting max x
			bounding_box[1].x = t.global_position.x
		if t.global_position.y > bounding_box[1].y: #setting max y
			bounding_box[1].y = t.global_position.y
		if t.global_position.z > bounding_box[1].z: #setting max y
			bounding_box[1].z = t.global_position.z
	
	#adding padding to bounding box
	bounding_box[0] -= Vector3.ONE
	bounding_box[1] += Vector3.ONE

func _calculate_materials() -> bool: #gathers all materials so that mesh separation can occur
	material_array = [] #clear material array
	
	for t in geometry_array: #iterate through all tiles
		if t.internal_material == null: #if has no material
			_error(str(t.name)+" is missing material")
			return false
		
		if t.global_position != floor(t.global_position): #if non-integer position value
			_error(str(t.name)+" has a non-integer position value")
			return false
		if t.rotation != Vector3.ZERO: #if rotated
			_error(str(t.name)+" has a non-zero rotation value")
			return false
		if t.scale != Vector3.ONE: #if scaled
			_error(str(t.name)+" has a non-standard scale value")
			return false
		
		if !t is LevelTileCull: #if not a cull tile
			if !material_array.has(t.internal_material): #if material is not already added
				material_array.append(t.internal_material) #add material to array
			for m in t.material_overrides: #going through extra materials
				if !material_array.has(m) and m != null: #if material is not already added
					material_array.append(m) #add material to array
		
	print("Found "+str(material_array.size())+" materials.")
	
	return true #continue the geometry building

func _in_chunk(chunk:LevelChunk, tile:LevelTile)->bool:
	return tile.chunk_owner == chunk

func _cycle_tiles(chunk:LevelChunk,main:bool=true,vec_compare:Vector3=Vector3.ZERO,from:LevelTile=null) -> bool: #go through all tiles to check surrounds
	if not main: #if checking adjacent face
		if vec_compare.y <= cull_bottom+geometry_folder.global_position.y \
		or vec_compare.y >= cull_top+geometry_folder.global_position.y: #if outside of bounds
			return false
	
	for t in geometry_array: #iterate through all tiles
		if main: #main tile loop
			if _in_chunk(chunk, t): #if in current chunk
				if (t.internal_material == current_material or t.material_overrides.has(current_material)): #if has current material
					shape = t._generate_shape() #get tile shape data
					var original_dimensions:Array[Vector3] = [shape.sh_dimensions, shape.sh_offset] #orignal shape to revert to
					var shading:FaceShading #face shading data
					var uses_shading:bool=true #if uses shading
					if t.ignore_shading or face_shading == null and t.shading_override == null: #white shading
						uses_shading = false #doesn't use shading
						shading = FaceShading.new() #create a new FaceShading resource
						shading.front = Color.WHITE #set all sides to white
						shading.back = Color.WHITE
						shading.left = Color.WHITE
						shading.right = Color.WHITE
						shading.top = Color.WHITE
						shading.bottom = Color.WHITE
					elif t.shading_override != null: #if has a shading override
						shading = t.shading_override #custom tile-only shading
					else: #if no special shading
						shading = face_shading #default global shading
					
					if force_flip_faces:
						shape.flip_faces = true #turn flip faces on
					
					if shape.flip_faces and uses_shading: #flipping shading for flipped tiles
						var new_shading:FaceShading = FaceShading.new() #new temp variable
						new_shading.top = shading.bottom #flip shading around
						new_shading.bottom = shading.top
						new_shading.left = shading.right
						new_shading.right = shading.left
						new_shading.front = shading.back
						new_shading.back = shading.front
						shading = new_shading #update original variable
					
					var tile_faces:int = 0
					var tilepos:Vector3 = t.global_position-geometry_folder.global_position #corrects for offset
					
					for f in 6: #for each face
						#reset dimensions for each face
						shape.sh_dimensions = original_dimensions[0]
						shape.sh_offset = original_dimensions[1]
						
						if t.material_overrides[f] == null and t.internal_material == current_material \
						or t.material_overrides[f] == current_material \
						and t.material_overrides[f] != NODRAW_MATERIAL: #if face has default mat or mat is special
							match f:
								Codex.Face.RIGHT:
									#Checking faces
									if await _cycle_tiles(chunk, false, t.global_position+Vector3.RIGHT, t): #if right tile is empty
										if await _cull_scan(t, t.global_position, Vector3.RIGHT, X_SUB_ARRAY):
											Codex.new_face(st, world_scale, Codex.Face.RIGHT, 
											Vector3.RIGHT, tilepos, shading.right, shape)
											tile_faces += 1
								Codex.Face.LEFT:
									if await _cycle_tiles(chunk, false, t.global_position+Vector3.LEFT, t): #if left tile is empty
										if await _cull_scan(t, t.global_position, Vector3.LEFT, X_SUB_ARRAY):
											Codex.new_face(st, world_scale, Codex.Face.LEFT, 
											Vector3.LEFT, tilepos, shading.left, shape)
											tile_faces += 1
								Codex.Face.FRONT:
									if await _cycle_tiles(chunk, false, t.global_position+Vector3.BACK, t): #if forward tile is empty
										if await _cull_scan(t, t.global_position, Vector3.BACK, Z_SUB_ARRAY):
											Codex.new_face(st, world_scale, Codex.Face.FRONT, 
											Vector3.BACK, tilepos, shading.front, shape)
											tile_faces += 1
								Codex.Face.BACK:
									if await _cycle_tiles(chunk, false, t.global_position+Vector3.FORWARD, t): #if back tile is empty
										if await _cull_scan(t, t.global_position, Vector3.FORWARD, Z_SUB_ARRAY):
											Codex.new_face(st, world_scale, Codex.Face.BACK, 
											Vector3.FORWARD, tilepos, shading.back, shape)
											tile_faces += 1
								Codex.Face.TOP:
									if await _cycle_tiles(chunk, false, t.global_position+Vector3.UP, t): #if up tile is empty
										if await _cull_scan(t, t.global_position, Vector3.UP, Y_SUB_ARRAY):
											Codex.new_face(st, world_scale, Codex.Face.TOP, 
											Vector3.UP, tilepos, shading.top, shape)
											tile_faces += 1
								Codex.Face.BOTTOM:
									if await _cycle_tiles(chunk, false, t.global_position+Vector3.DOWN, t): #if up tile is empty
										if await _cull_scan(t, t.global_position, Vector3.DOWN, Y_SUB_ARRAY):
											Codex.new_face(st, world_scale, Codex.Face.BOTTOM, 
											Vector3.DOWN, tilepos, shading.bottom, shape)
											tile_faces += 1
					
					face_count += tile_faces #add faces on this tile to total face count
					material_faces_in_chunk += tile_faces #add to chunk count
					
					await get_tree().process_frame #Await once per tile
		
		else: #individual tile face check
			if from == null:
				_error("from == null")
				return false
			
			if t.global_position == from.global_position: #overlapping tiles
				if t != from: #if overlapper is not self
					if t.sh_offset == from.sh_offset and t.sh_dimensions == from.sh_dimensions: #if both same shape
						_error(str(t.name)+" is overlapping with "+str(from.name)+" and is same shape")
						has_crashed = true #causes geometry to stop building
						return false
					else:
						if !disable_overlap_warning: #ignore message if ignore us enabled
							var message:String = "-"+str(t.name)+" is overlapping with "+str(from.name)+" but is a different shape."
							
							_queue_message(message)
							_queue_message("	Avoid doing this unintentionally. Only use for advanced shapes.")
							_queue_message("	Disable this warning on LevelBuilder node")
			
			if t.global_position == vec_compare: #if there is a tile here
				#Checking tiles of irregular size
				var vec_dir:Vector3=vec_compare-from.global_position #direction vector
				
				#Inverted half-wall support
				if t.flip_faces and from.flip_faces or force_flip_faces: #if flipped faces
					for axis in 3: #x, y, z
						if t.sh_dimensions[axis] < from.sh_dimensions[axis] or t.sh_offset[axis] > from.sh_offset[axis]: #if other is irregular shape
							#invert other irregular shape for face
							shape.sh_dimensions[axis] = from.sh_dimensions[axis]-t.sh_dimensions[axis] #opposite of shape
							if t.sh_offset[axis] <= from.sh_offset[axis]: #if adjacent is below
								shape.sh_offset[axis] = from.sh_offset[axis]+t.sh_dimensions[axis] #fill top
							else: #if adjacent is above
								shape.sh_offset[axis] = from.sh_offset[axis] #fill bottom
				
				#Checking if same sized tiles are touching in same axis or not
				match vec_dir:
					Vector3.FORWARD: #negative dir
						if from.sh_offset.z != 0: #if separate from wall
							return true #draw face
						else: #if adjacent is separate from wall
							if t.sh_dimensions.z+t.sh_offset.z < 1:
								return true #draw face
					Vector3.BACK: #positive dir
						if from.sh_dimensions.z+from.sh_offset.z < 1: #if separate from wall
							return true #draw face
						else: #if adjacent is separate from wall
							if t.sh_offset.z != 0:
								return true #draw face
					
					Vector3.LEFT: #negative dir
						if from.sh_offset.x != 0: #if separate from wall
							return true #draw face
						else: #if adjacent is separate from wall
							if t.sh_dimensions.x+t.sh_offset.x < 1:
								return true #draw face
					Vector3.RIGHT: #positive dir
						if from.sh_dimensions.x+from.sh_offset.x < 1: #if separate from wall
							return true #draw face
						else: #if adjacent is separate from wall
							if t.sh_offset.x != 0:
								return true #draw face
					
					Vector3.DOWN: #negative dir
						if from.sh_offset.y != 0: #if separate from wall
							return true #draw face
						else: #if adjacent is separate from wall
							if t.sh_dimensions.y+t.sh_offset.y < 1:
								return true #draw face
					Vector3.UP: #positive dir
						if from.sh_dimensions.y+from.sh_offset.y < 1: #if separate from wall
							return true #draw face
						else: #if adjacent is separate from wall
							if t.sh_offset.y != 0:
								return true #draw face
				
				#Checking if other face obscures the current face
				#The obscured face will be culled while the other is shown
				if vec_dir.y != 0: #up or down
					#if not enclosed within bounds of other tile
					if !(from.sh_offset.x >= t.sh_offset.x \
					and from.sh_offset.x+from.sh_dimensions.x <= t.sh_offset.x+t.sh_dimensions.x) \
					or !(from.sh_offset.z >= t.sh_offset.z \
					and from.sh_offset.z+from.sh_dimensions.z <= t.sh_offset.z+t.sh_dimensions.z):
						return true #draw face
				elif vec_dir.x != 0: #left or right
					#if not enclosed within bounds of other tile
					if !(from.sh_offset.y >= t.sh_offset.y \
					and from.sh_offset.y+from.sh_dimensions.y <= t.sh_offset.y+t.sh_dimensions.y) \
					or !(from.sh_offset.z >= t.sh_offset.z \
					and from.sh_offset.z+from.sh_dimensions.z <= t.sh_offset.z+t.sh_dimensions.z):
						return true #draw face
				elif vec_dir.z != 0: #forward or backward
					#if not enclosed within bounds of other tile
					if !(from.sh_offset.y >= t.sh_offset.y \
					and from.sh_offset.y+from.sh_dimensions.y <= t.sh_offset.y+t.sh_dimensions.y) \
					or !(from.sh_offset.x >= t.sh_offset.x \
					and from.sh_offset.x+from.sh_dimensions.x <= t.sh_offset.x+t.sh_dimensions.x):
						return true #draw face
				
				if !t.alpha or t.alpha and from.alpha: #if not invis or both are invis
					return false #do not draw
	
	return true #there was no tile here

func _cull_scan(from:Object, pos:Vector3, axis:Vector3, sub_arrays:Array[Vector3]=[]) -> bool: #only used for auto culling mode
	if not interior_mode: #if disabled
		return true #bypass this function
	else: #if enabled
		var hits:int = 0 #reset hit count
		
		var range:int = _projection_scan(from, pos, axis, scan_radius, true) #get distance to collision
		
		if range > 0: #if collided
			for i in range(1, range): #go through all tiles in normal range
				for a in sub_arrays: #for each scan direction
					hits += _projection_scan(from, pos+(axis*i), a, scan_radius) #send out perpendicular scans
			
			if hits < 4*(range-1): #if any scans didn't detect a surface
				return false #do not draw this face
			else: #if every scan hit a surface
				return true #draw this face
		else: #no hits at all
			return false #do not draw this face

func _projection_scan(from:Object, pos:Vector3, axis:Vector3, range:int, return_dist:bool=false) -> int: #single direction projection
	for i in range(1, range+1): #set y check parameters
		scans += 1 #scan amount counted for user
		
		var vec_compare:Vector3 = pos+(axis*i) #position to check
		#massive optimisation
		if vec_compare.x < bounding_box[0].x or vec_compare.x > bounding_box[1].x \
		or vec_compare.y < bounding_box[0].y or vec_compare.y > bounding_box[1].y:
			return 0 #didn't hit anything
		
		if vec_compare.y <= cull_bottom+geometry_folder.global_position.y \
		or vec_compare.y >= cull_top+geometry_folder.global_position.y: #if outside of cull wall
			if return_dist:
				return i #ray distance
			else:
				return 1 #hit
		
		for t in geometry_array: #go through all tiles
			if t.global_position == vec_compare: #if there is a tile in this spot
				if t is LevelTile:# and !t is LevelTileCull and !t is LevelTileInvisible: #if a solid level tile
					if t != from: #if not the same tile
						if return_dist:
							return i #ray distance
						else:
							return 1 #hit
	
	return 0 #didn't hit
