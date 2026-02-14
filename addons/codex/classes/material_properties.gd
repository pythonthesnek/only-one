##Material properties used for LevelMaterial resource.
class_name MaterialProperties
extends Resource

##ID used to differentiate colliders. Can be used for differentiating footstep sounds, bullet decals, etc.
##Functionality must be added manually. Saved as metadata on StaticBody3D.
@export var material_id:int=0
##Physics material for collider. Can be used to make surfaces have custom physics properties e.g. slippery ice.
##Functionality must be added manually if not using RigidBody physics.
@export var physics_material:PhysicsMaterial
