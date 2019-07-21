tool
extends StaticBody

signal destroy

export(Material) var material setget set_material

func set_material(material_in):
	material = material_in
	if Engine.editor_hint:
		call_deferred("_update_material")

func _update_material():
	$HighLOD.material_override = material
	$MediumLOD.material_override = material
	$LowLOD.material_override = material

export(OpenSimplexNoise) var noise setget set_noise

func set_noise(noise_in):
	noise = noise_in
	if Engine.editor_hint:
		call_deferred("_update")
		if !noise.is_connected("changed", self, "_update"):
			noise.connect("changed", self, "_update", [], CONNECT_DEFERRED)

export(float) var noise_scale = 1.0 setget set_noise_scale

func set_noise_scale(noise_scale_in):
	noise_scale = noise_scale_in
	if Engine.editor_hint:
		call_deferred("_update")

export var chunk_size = 16 setget set_chunk_size

func set_chunk_size(chunk_size_in):
	chunk_size = chunk_size_in
	if Engine.editor_hint:
		call_deferred("_update")

export var max_height = 8 setget set_max_height

func set_max_height(max_height_in):
	max_height = max_height_in
	if Engine.editor_hint:
		call_deferred("_update")

enum LOD {HIGH,MEDIUM,LOW}
export (LOD) var lod = LOD.HIGH setget set_lod

func set_lod(lod_in):
	lod = lod_in
	if Engine.editor_hint:
		call_deferred("update_chunk")

const MARGIN = Vector2(0.1,0.1)

export var collision = true setget set_collision

func set_collision(collision_in):
	collision = collision_in
	if Engine.editor_hint:
		call_deferred("update_chunk")

var car : Node setget set_car

func set_car(car_node):
	car = car_node
	if !Engine.editor_hint and car != null:
		car.connect("car_moved", self, "_on_car_moved")
		call_deferred("_on_car_moved", car.global_transform.origin)

var chunk_pos : Vector2 setget set_chunk_pos, get_chunk_pos

func set_chunk_pos(new_pos : Vector2):
	if new_pos == null:
		return
	chunk_pos = new_pos
	if Engine.editor_hint:
		call_deferred("_update")

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
		emit_signal("destroy", self)
	set_lod(lod)
	set_collision(distance < chunk_size)
	set_visible(distance < chunk_size*5)
	call_deferred("update_chunk")

# Called when the node enters the scene tree for the first time.

var lmb : LodMeshBuilder

func _ready():
	if Engine.editor_hint:
		call_deferred("_update")
	else:
		_update()

func _exit_tree():
	if Engine.editor_hint and noise != null:
		noise.disconnect("changed", self, "_update")

func _update():
	global_transform.origin = Vector3(chunk_pos.x, 0, chunk_pos.y)
	lmb = LodMeshBuilder.new(chunk_size, noise, noise_scale, max_height)
	create_lods()
	_update_material()
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
	var origin = Vector3(chunk_pos.x, 0, chunk_pos.y)
	var mesh = lmb.build(origin, 2)
	$HighLOD.set_mesh(lmb.build(origin, 1))
	$MediumLOD.set_mesh(mesh)
	$LowLOD.set_mesh(lmb.build(origin, 4))
	$CollisionShape.set_shape(mesh.create_trimesh_shape())

class LodMeshBuilder:
	var chunk_size : float
	var max_height : float
	var noise : OpenSimplexNoise
	var noise_scale : float = 1.0
	
	var normal_arr = PoolVector3Array()
	var uv_arr = PoolVector2Array()
	var vertex_arr = PoolVector3Array()
	var index_arr = PoolIntArray()
	
	func _init(chunk_size_in : float, noise_in : OpenSimplexNoise, noise_scale_in : float, max_height_in : float):
		chunk_size = chunk_size_in
		noise = noise_in
		noise_scale = noise_scale_in
		max_height = max_height_in
	
	var origin : Vector3
	var subdivision : float
	
	func build(origin_in : Vector3, subdivision_in : float):
		origin = origin_in
		subdivision = subdivision_in
		
		fill_arrays()
		
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_NORMAL] = normal_arr
		arrays[Mesh.ARRAY_TEX_UV] = uv_arr
		arrays[Mesh.ARRAY_VERTEX] = vertex_arr
		arrays[Mesh.ARRAY_INDEX] = index_arr
		
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
	
	func set_height_and_normal(idx : int):
		var point3d = vertex_arr[idx] + origin
		var point = Vector2(point3d.x, point3d.z)
		
		vertex_arr[idx].y = get_height(point)
		
		var offset = chunk_size / subdivision / 20
		
		var offset0 = Vector2.LEFT * offset + point
		var point0 = Vector3(offset0.x, get_height(offset0), offset0.y)
		
		var offset1 = (Vector2.DOWN+Vector2.RIGHT).normalized() * offset + point
		var point1 = Vector3(offset1.x, get_height(offset1), offset1.y)
		
		var offset2 = (Vector2.UP+Vector2.RIGHT).normalized() * offset + point
		var point2 = Vector3(offset2.x, get_height(offset2), offset2.y)
		
		normal_arr[idx] = (point1-point0).cross(point2-point0).normalized()
	
	func get_height(point : Vector2):
		var noise_probe = point * noise_scale
		return max_height * noise.get_noise_2dv(noise_probe)
	
	func fill_arrays():
		var offset = Vector3(-chunk_size/2, 0, -chunk_size/2)
		var face_count = int(chunk_size / subdivision)
		var face_size = chunk_size / float(face_count)
		var uv_subdivide = float(int(chunk_size / subdivision) + 1)
		
		var back_index_arr = []
		back_index_arr.resize(face_count + 1)
		
		var front_right = null
		var vertex_idx = null
		
		for iy in range(face_count):
			var back_new_index_arr = []
			back_new_index_arr.resize(face_count + 1)
			for ix in range(face_count):
				var ix1 = ix+1
				var iy1 = iy+1
				# FRONT LEFT
				if back_index_arr[ix] != null:
					index_arr.append(back_index_arr[ix])
				elif front_right != null:
					index_arr.append(front_right)
				else:
					vertex_idx = vertex_arr.size()
					vertex_arr.append(Vector3(ix * face_size, 0, iy * face_size) + offset)
					uv_arr.append(Vector2(ix/uv_subdivide, iy/uv_subdivide))
					normal_arr.append(Vector3(0,1,0))
					set_height_and_normal(vertex_idx)
					index_arr.append(vertex_idx)
				# FRONT RIGHT
				if back_index_arr[ix1] != null:
					front_right = back_index_arr[ix1]
					index_arr.append(back_index_arr[ix1])
				else:
					vertex_idx = vertex_arr.size()
					vertex_arr.append(Vector3(ix1 * face_size, 0, iy * face_size) + offset)
					uv_arr.append(Vector2(ix1/uv_subdivide,iy/uv_subdivide))
					normal_arr.append(Vector3(0,1,0))
					set_height_and_normal(vertex_idx)
					front_right = vertex_idx
					index_arr.append(front_right)
				# BACK LEFT
				if back_new_index_arr[ix] == null:
					vertex_idx = vertex_arr.size()
					vertex_arr.append(Vector3(ix * face_size, 0, iy1 * face_size) + offset)
					uv_arr.append(Vector2(ix/uv_subdivide,iy1/uv_subdivide))
					normal_arr.append(Vector3(0,1,0))
					set_height_and_normal(vertex_idx)
					back_new_index_arr[ix] = vertex_idx
				index_arr.append(back_new_index_arr[ix])
				# BACK LEFT
				index_arr.append(back_new_index_arr[ix])
				# FRONT RIGHT
				index_arr.append(front_right)
				# BACK RIGHT
				vertex_idx = vertex_arr.size()
				vertex_arr.append(Vector3(ix1 * face_size, 0, iy1 * face_size) + offset)
				uv_arr.append(Vector2(ix1/uv_subdivide,iy1/uv_subdivide))
				normal_arr.append(Vector3(0,1,0))
				set_height_and_normal(vertex_idx)
				back_new_index_arr[ix1] = vertex_idx
				index_arr.append(back_new_index_arr[ix1])
			back_index_arr = back_new_index_arr
