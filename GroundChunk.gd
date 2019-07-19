tool
extends StaticBody

export(OpenSimplexNoise) var noise setget set_noise

func set_noise(noise_in):
	noise = noise_in
	if Engine.editor_hint:
		call_deferred("_update")

export(float) var noise_scale = 1.0 setget set_noise_scale

func set_noise_scale(noise_scale_in):
	noise_scale = noise_scale_in
	if Engine.editor_hint:
		call_deferred("_update")

export var chunk_size = 48 setget set_chunk_size

func set_chunk_size(chunk_size_in):
	chunk_size = chunk_size_in
	if Engine.editor_hint:
		call_deferred("_update")

export var max_height = 10 setget set_max_height

func set_max_height(max_height_in):
	max_height = max_height_in
	if Engine.editor_hint:
		call_deferred("_update")

enum LOD {HIGH,MEDIUM,LOW}
export (LOD) var lod = LOD.HIGH setget set_lod

func set_lod(lod_in):
	lod = lod_in
	call_deferred("update_chunk")

const MARGIN = Vector2(0.1,0.1)

export var collision = true setget set_collision

func set_collision(collision_in):
	collision = collision_in
	call_deferred("update_chunk")

var car : Node setget set_car

func set_car(car_node):
	car = car_node
	if !Engine.editor_hint and car != null:
		car.connect("car_moved", self, "_on_car_moved")
		call_deferred("_on_car_moved", car.global_transform.origin)

func _on_car_moved(new_pos : Vector3):
	var chunk_pos = Vector2(global_transform.origin.x, global_transform.origin.z)
	var distance = Vector2(new_pos.x, new_pos.z).distance_to(chunk_pos)
	if distance < chunk_size/2:
		set_collision(true)
		set_lod(LOD.HIGH)
		set_visible(true)
	elif distance < chunk_size:
		set_collision(true)
		set_lod(LOD.MEDIUM)
		set_visible(true)
	elif distance < chunk_size*2:
		set_collision(false)
		set_lod(LOD.MEDIUM)
		set_visible(true)
	elif distance < chunk_size*4:
		set_collision(false)
		set_lod(LOD.LOW)
		set_visible(true)
	else:
		set_collision(false)
		set_visible(false)

# Called when the node enters the scene tree for the first time.
func _ready():
	if Engine.editor_hint:
		call_deferred("_update")
	else:
		_update()

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func _update():
	create_lods()
	update_chunk()

func update_chunk():
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
	$CollisionShape.set_disabled(!collision)
	$CollisionShape.set_visible(collision)

func create_lods():
	var mesh = get_plane_mesh(2)
	$HighLOD.set_mesh(get_plane_mesh(1))
	$MediumLOD.set_mesh(mesh)
	$LowLOD.set_mesh(get_plane_mesh(4))
	$CollisionShape.set_shape(mesh.create_trimesh_shape())

func get_plane_mesh(subdivision):
	var offset = global_transform.origin
	var plane = PlaneMesh.new()
	plane.set_size(Vector2(chunk_size,chunk_size) + MARGIN)
	plane.set_subdivide_depth(round(chunk_size / subdivision))
	plane.set_subdivide_width(round(chunk_size / subdivision))
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_smooth_group(true)
	for vertex in plane.get_faces():
		var noise_probe = (offset + vertex) * noise_scale
		vertex.y = max_height * noise.get_noise_2d(noise_probe.x, noise_probe.z)
		st.add_uv(Vector2())
		st.add_vertex(vertex)
	st.generate_normals()
	st.generate_tangents()
	st.index()
	return st.commit()
