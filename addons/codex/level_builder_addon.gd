@tool
extends EditorPlugin

var builder:LevelBuilder #currently selected LevelBuilder node

#Buttons
var button_array:Array[Button]


func _enter_tree() -> void: #when plugin enabled
	add_autoload_singleton("Codex", "res://addons/codex/globals/lb_global.gd") #add global script

func _exit_tree() -> void: #when plugin disabled
	remove_autoload_singleton("Codex") #remove global script

func _handles(object: Object) -> bool: #when node selected
	return object is LevelBuilder #return true if selected object is a level builder

func _edit(object: Object) -> void:
	if not object: #if object is invalid (determined in handles)
		return
	
	builder = object #update builder to currently selected


func _make_visible(visible: bool) -> void:
	if visible: #if builder selected
		_remove_all_buttons()
		_add_button("+", _do_setup)
		_add_button("Build Level Geometry", _build_level)
		_add_button("Save Output To File", _save_to_file)
	else: #if builder deselected
		_remove_all_buttons()


func _add_button(text:String, press_function:Callable) -> void:
	var button:Button = Button.new()
	button.text = text #set text
	button.focus_mode = Control.FOCUS_NONE #disable focus
	button.flat = true #makes it look nicer
	button.pressed.connect(press_function) #connect to desired callable
	
	button_array.append(button) #add to array
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, button) #add to toolbar

func _remove_all_buttons() -> void: #removes the build button
	for b:Button in button_array: #go through all buttons
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, b) #remove from toolbar
		b.queue_free() #delete button
	
	button_array = [] #empty array


func _build_level() -> void: #when build button pressed
	if builder != null: #if there is a valid builder
		builder._build_geometry() #trigger builder


func _add_node_3d(node_name:String, node_parent:Node) -> Node3D:
	#Stop if setup already exists
	if node_parent.has_node(node_name): 
		print("Node '" + node_name +"' already exists")
		return null #return nothing
	
	#Create Node3D
	var n:Node3D = Node3D.new()
	n.name = node_name
	node_parent.add_child(n)
	n.set_owner(node_parent)
	
	print("Created node: '" + node_name + "'")
	
	return n #return Node3D


func _add_initial_geo(parent:Node) -> void:
	if !builder.scene_root: return
	
	#Create LevelChunk
	var chunk:LevelChunk = LevelChunk.new()
	chunk.name = "LevelChunk"
	parent.add_child(chunk)
	chunk.set_owner(builder.scene_root)
	
	#Create LevelTile
	var tile:LevelTile = LevelTile.new()
	tile.name = "LevelTile"
	chunk.add_child(tile)
	tile.set_owner(builder.scene_root)


func _do_setup() -> void:
	var parent:Node = builder.get_parent() #get LevelBuilder parent
	print(parent.name)
	
	#Stop if has no parent
	if !parent: #if parent == null
		push_error("LevelBuilder has no parent node")
		return
	
	builder.scene_root = parent #set scene root
	
	await get_tree().process_frame
	
	var geo:Node3D = _add_node_3d("Geometry", parent)
	if geo:
		geo.global_position.y += 7 #7 metres above output folder
		builder.geometry_folder = geo #set geo folder
		_add_initial_geo(geo) #add LevelChunk and LevelTile
	
	var output:Node3D = _add_node_3d("Output", parent)
	if output:
		builder.output_folder = output #set output folder


func _save_to_file() -> void:
	builder.save_geometry_to_file()
