tool
extends StaticBody

signal remove

export(Material) var material setget set_material

func set_material(material_in):
	material = material_in

export(OpenSimplexNoise) var noise setget set_noise

func set_noise(noise_in):
	noise = noise_in

export(float) var noise_scale = 1.0 setget set_noise_scale

func set_noise_scale(noise_scale_in):
	noise_scale = noise_scale_in

export var chunk_size = 16 setget set_chunk_size

func set_chunk_size(chunk_size_in):
	chunk_size = chunk_size_in

export var max_height = 8 setget set_max_height

func set_max_height(max_height_in):
	max_height = max_height_in

enum LOD {HIGH,MEDIUM,LOW}
export (String) var lod = LOD.HIGH setget set_lod

func set_lod(lod_in):
	lod = lod_in
	match lod:
		LOD.HIGH:
			$HighLOD.set_visible(true)
			$MediumLOD.set_visible(false)
			$LowLOD.set_visible(false)
		LOD.MEDIUM:
			$HighLOD.set_visible(false)
			$MediumLOD.set_visible(true)
			$LowLOD.set_visible(false)
		LOD.LOW:
			$HighLOD.set_visible(false)
			$MediumLOD.set_visible(false)
			$LowLOD.set_visible(true)

const MARGIN = Vector2(0.1,0.1)

export var collision = true setget set_collision

func set_collision(collision_in):
	collision = collision_in
	$CollisionShape.set_disabled(!collision)
	$CollisionShape.set_visible(collision)

var car : Node setget set_car

func set_car(car_node):
	car = car_node
	if !Engine.editor_hint and car != null:
		car.connect("moved", self, "_on_car_moved")
		call_deferred("_on_car_moved", car.global_transform.origin)

var chunk_pos : Vector2 setget set_chunk_pos, get_chunk_pos

func set_chunk_pos(new_pos : Vector2):
	chunk_pos = new_pos

func get_chunk_pos():
	return chunk_pos

func _on_car_moved(new_pos : Vector3):
	var distance = Vector2(new_pos.x, new_pos.z).distance_to(chunk_pos)
	var lod
	if distance < chunk_size:
		lod = LOD.HIGH
	elif distance < chunk_size*2:
		lod = LOD.MEDIUM
	elif distance < chunk_size*5:
		lod = LOD.LOW
	elif distance > chunk_size*6:
		call_deferred("_remove")
		return
	set_lod(lod)
	set_collision(distance < chunk_size)
	set_visible(distance < chunk_size*5)

var chunk_data

func set_data(data):
	chunk_data = data

# Called when the node enters the scene tree for the first time.
func _ready():
	global_transform.origin = Vector3(chunk_pos.x, 0, chunk_pos.y)
	call_deferred("_set_children")

func _get_mesh_from_arrays(arrays):
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _set_children():
	$HighLOD.set_mesh(_get_mesh_from_arrays(chunk_data[LOD.HIGH]))
	var mesh : Mesh = _get_mesh_from_arrays(chunk_data[LOD.MEDIUM])
	$MediumLOD.set_mesh(mesh)
	$CollisionShape.set_shape(mesh.create_trimesh_shape())
	$LowLOD.set_mesh(_get_mesh_from_arrays(chunk_data[LOD.LOW]))
	$HighLOD.material_override = material
	$MediumLOD.material_override = material
	$LowLOD.material_override = material

func _remove():
	emit_signal("remove", self)