@tool
extends Node

# --- MESH BUILDING DATA ---

const CUBE_VERTICES:Array[Vector3]=[ #every single vertex required to make a cube
	Vector3(0, 0, 0), #0 - left, bottom, back
	Vector3(1, 0, 0), #1 - right, bottom, back
	Vector3(1, 1, 0), #2 - right, top, back
	Vector3(1, 1, 1), #3 - right, top, front
	Vector3(0, 1, 1), #4 - left, top, front
	Vector3(0, 0, 1), #5 - left, bottom, front
	Vector3(1, 0, 1), #6 - right, bottom, front
	Vector3(0, 1, 0), #7 - left, top, back
]
const FACE_INDEX:Array=[ #vertex positions for all faces
	[4, 3, 6, 5], #Front
	[2, 7, 0, 1,], #Back
	[7, 4, 5, 0,], #Left
	[3, 2, 1, 6,], #Right
	[5, 6, 1, 0,], #Bottom
	[7, 2, 3, 4,], #Top
]
enum Face { #used for ease of access on face index
	FRONT,
	BACK,
	LEFT,
	RIGHT,
	BOTTOM,
	TOP
}

func new_face(st:SurfaceTool, world_scale:Vector3, face:int, normal:Vector3, offset:Vector3, colour:Color=Color(1.0,1.0,1.0), shape:TileShape=TileShape.new()) -> void:
	var vertex_array:PackedVector3Array = [] #array of vertices to create
	
	if shape == null: #if no shape data
		return #stop this function
	
	var shape_offset:Vector3 = shape.sh_offset #default shape offset
	var tex_offset:Vector3 = shape_offset+shape.texture_offset #texture offset + shape offset
	var shape_dimensions:Vector3 = shape.sh_dimensions #default shape dimensions
	
	for n in FACE_INDEX[face]: #go through each vertex array element in face
		vertex_array.append((((CUBE_VERTICES[n]*shape_dimensions)+offset)*world_scale)+(shape_offset*world_scale)) #append vertex coords to array
	
	var scale_factor:Vector3=Vector3.ONE #world scale thing
	if shape.ignore_world_scale: #if ignores world scale
		scale_factor = world_scale #cancel out world scale
	
	var uv_min:Vector2 = Vector2.ZERO #equivalent of UV 0, 0
	var uv_max:Vector2 = Vector2.ONE #equivalent of UV 1, 1
	
	if shape.stretch_textures: #if should stretch textures
		shape_dimensions = Vector3.ONE #default shape
		tex_offset = shape.texture_offset #remove shape offset from texture offset
	
	##THANKS TO RAT KING FOR THE TEXTURE UV FIX:
	##https://itch.io/profile/ratking
	
	match face: #setting uvs for tiles
		Face.TOP:
			uv_min.x = tex_offset.x*scale_factor.x
			uv_max.x = (shape_dimensions.x+tex_offset.x)*scale_factor.x
			uv_min.y = tex_offset.z*scale_factor.z
			uv_max.y = (shape_dimensions.z+tex_offset.z)*scale_factor.z
		Face.BOTTOM:
			uv_min.x = tex_offset.x*scale_factor.x
			uv_max.x = (shape_dimensions.x+tex_offset.x)*scale_factor.x
			uv_min.y = 1.0-(shape_dimensions.z+tex_offset.z)*scale_factor.z
			uv_max.y = 1.0-tex_offset.z*scale_factor.z
		Face.LEFT:
			uv_min.x = tex_offset.z*scale_factor.z
			uv_max.x = (shape_dimensions.z+tex_offset.z)*scale_factor.z
			uv_min.y = 1.0-(shape_dimensions.y+tex_offset.y)*scale_factor.y
			uv_max.y = 1.0-tex_offset.y*scale_factor.y
		Face.RIGHT:
			uv_min.x = 1.0-(shape_dimensions.z+tex_offset.z)*scale_factor.z
			uv_max.x = 1.0-tex_offset.z*scale_factor.z
			uv_min.y = 1.0-(shape_dimensions.y+tex_offset.y)*scale_factor.y
			uv_max.y = 1.0-tex_offset.y*scale_factor.y
		Face.FRONT:
			uv_min.x = tex_offset.x*scale_factor.x
			uv_max.x = (shape_dimensions.x+tex_offset.x)*scale_factor.x
			uv_min.y = 1.0-(shape_dimensions.y+tex_offset.y)*scale_factor.y
			uv_max.y = 1.0-tex_offset.y*scale_factor.y
		Face.BACK:
			uv_min.x = 1.0-(shape_dimensions.x+tex_offset.x)*scale_factor.x
			uv_max.x = 1.0-tex_offset.x*scale_factor.x
			uv_min.y = 1.0-(shape_dimensions.y+tex_offset.y)*scale_factor.y
			uv_max.y = 1.0-tex_offset.y*scale_factor.y
	
	#multiply uvs by texture scale
	uv_max *= shape.texture_scale
	uv_min *= shape.texture_scale
	
	#Uvs per vertex
	var uvs: PackedVector2Array = [
		#uv_min is equivalent to 0
		#uv_max is equivalent to 1
		Vector2(uv_min.x, uv_min.y),
		Vector2(uv_max.x, uv_min.y),
		Vector2(uv_max.x, uv_max.y),
		Vector2(uv_min.x, uv_max.y)
		]
	
	if shape.flip_faces: #inverted faces
		vertex_array.reverse() #reversing array to invert faces
		uvs.reverse() #reversing array to match vertices
		normal *= -1 #flipping normal
	
	var colours:PackedColorArray = [colour, colour, colour, colour] #colours per vertex
	var normals:PackedVector3Array = [normal, normal, normal, normal] #normals per vertex
	
	st.add_triangle_fan(vertex_array, uvs, colours, [], normals) #add face
