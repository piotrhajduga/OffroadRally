tool
extends CollisionShape

export (NodePath) var car_body_node setget set_car_body
var car_body : Spatial

func set_car_body(new_car_body_node):
	car_body_node = new_car_body_node
	car_body = get_node_or_null(car_body_node)
	if Engine.editor_hint:
		call_deferred("_update")

export (NodePath) var collision_mesh_node setget set_collision_mesh
var collision_mesh : MeshInstance

func set_collision_mesh(new_collision_mesh_node):
	collision_mesh_node = new_collision_mesh_node
	collision_mesh = get_node_or_null(collision_mesh_node)
	if Engine.editor_hint:
		call_deferred("_update")

func _update():
	if collision_mesh != null:
		set_shape(collision_mesh.mesh.create_convex_shape())
	if car_body != null:
		transform = car_body.transform

# Called when the node enters the scene tree for the first time.
func _ready():
	if Engine.editor_hint:
		call_deferred("_update")
	else:
		car_body = get_node_or_null(car_body_node)
		collision_mesh = get_node_or_null(collision_mesh_node)
		_update()

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
