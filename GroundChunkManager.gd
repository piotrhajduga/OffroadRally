tool
extends Node

var GroundChunk = preload("res://GroundChunk.gd")

signal updated
signal queue_empty
signal chunk_created

export (OpenSimplexNoise) var ground_noise setget set_ground_noise

func set_ground_noise(ground_noise_in):
	ground_noise = ground_noise_in
	emit_signal("updated")

export (float) var ground_noise_scale = 1.0 setget set_ground_noise_scale

func set_ground_noise_scale(ground_noise_scale_in):
	ground_noise_scale = ground_noise_scale_in
	emit_signal("updated")

export (int) var chunk_size = 16 setget set_chunk_size

func set_chunk_size(size):
	chunk_size = size
	emit_signal("updated")

export var max_height = 8.0 setget set_max_height

func set_max_height(height):
	max_height = height
	emit_signal("updated")

func ensure_chunk(chunk_pos : Vector2, important : bool = false):
	if Engine.editor_hint:
		var chunk_data = _create_chunk_data(chunk_pos)
		call_deferred("emit_signal", "chunk_created", chunk_pos, chunk_data)
	else:
		chunks_mutex.lock()
		var exists = chunks.has(chunk_pos)
		chunks_mutex.unlock()
		if !exists:
			queue_mutex.lock()
			if important:
				queue.push_front(chunk_pos)
			else:
				queue.push_back(chunk_pos)
			queue_mutex.unlock()
			creator_semaphore.post()

var chunks_mutex = Mutex.new()
var chunks = []

var creator_semaphore = Semaphore.new()
var queue_mutex = Mutex.new()
var queue = []
var threads = []

var exit_mutex = Mutex.new()
var exit = false

export (int) var thread_count = 1

func _ready():
	if !Engine.editor_hint:
		for i in range(thread_count):
			_start_thread()

func _exit_tree():
	if !Engine.editor_hint:
		call_deferred("_close_threads")

func _start_thread():
	var chunk_creator_thread = Thread.new()
	var err = chunk_creator_thread.start(self, "_chunk_creator_thread", null, 0)
	if err == 0:
		threads.append(chunk_creator_thread)
	else:
		print("Cannot create chunk creator thread. Thread.start returned: ", err)

func _chunk_creator_thread(userdata):
	#print_debug("[thread] started")
	while true:
		creator_semaphore.wait()
		exit_mutex.lock()
		if exit: break
		exit_mutex.unlock()
		
		queue_mutex.lock()
		var chunk_pos = queue.pop_front()
		var empty = queue.empty()
		queue_mutex.unlock()
		
		if empty: call_deferred("emit_signal", "queue_empty")
		
		chunks_mutex.lock()
		chunks.append(chunk_pos)
		chunks_mutex.unlock()
		
		#print_debug("[thread] creating chunk")
		var chunk_data = _create_chunk_data(chunk_pos)
		
		call_deferred("emit_signal", "chunk_created", chunk_pos, chunk_data)
	#print_debug("[thread] finished")
	return 0

func _create_chunk_data(chunk_pos):
	var lmb = LodMeshBuilder.new(chunk_size, ground_noise, ground_noise_scale, max_height)
	var chunk_data = {}
	chunk_data[GroundChunk.LOD.HIGH] = lmb.build(chunk_pos, 3)
	chunk_data[GroundChunk.LOD.MEDIUM] = lmb.build(chunk_pos, 6)
	chunk_data[GroundChunk.LOD.LOW] = lmb.build(chunk_pos, 12)
	return chunk_data

func _remove_chunk(chunk_pos):
	chunks_mutex.lock()
	chunks.erase(chunk_pos)
	chunks_mutex.unlock()

func _close_threads():
	exit_mutex.lock()
	exit = true
	exit_mutex.unlock()
	creator_semaphore.post()
	while !threads.empty():
		var thread = threads.pop_front()
		thread.wait_to_finish()

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
	
	var origin : Vector2
	var subdivision : float
	
	func build(origin_in : Vector2, subdivision_in : float):
		origin = origin_in
		subdivision = subdivision_in
		
		fill_arrays()
		
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_NORMAL] = normal_arr
		arrays[Mesh.ARRAY_TEX_UV] = uv_arr
		arrays[Mesh.ARRAY_VERTEX] = vertex_arr
		arrays[Mesh.ARRAY_INDEX] = index_arr
		
		return arrays
	
	func set_height_and_normal(idx : int):
		var point3d = vertex_arr[idx]
		var point = origin + Vector2(point3d.x, point3d.z)
		
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
