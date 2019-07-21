tool
extends Spatial

var GroundChunk = preload("res://GroundChunk.tscn")

export(Material) var material setget set_material

func set_material(material_in):
	material = material_in
	if Engine.editor_hint:
		for child in get_children():
			child.set_material(material)

export (OpenSimplexNoise) var ground_noise setget set_ground_noise

func set_ground_noise(ground_noise_in):
	ground_noise = ground_noise_in
	for child in get_children():
		child.set_noise(ground_noise)

export (float) var ground_noise_scale = 1.0 setget set_ground_noise_scale

func set_ground_noise_scale(ground_noise_scale_in):
	ground_noise_scale = ground_noise_scale_in
	for child in get_children():
		child.set_noise_scale(ground_noise_scale)

export (int) var chunk_size = 16 setget set_chunk_size

func set_chunk_size(size):
	chunk_size = size
	call_deferred("_recreate_chunks")

export var max_height = 8.0 setget set_max_height

func set_max_height(height):
	max_height = height
	call_deferred("_recreate_chunks")

var chunks_mutex = Mutex.new()
var chunks = {}

func create_chunk(chunk_pos):
	var chunk = GroundChunk.instance()
	chunk.set_noise(ground_noise)
	chunk.set_noise_scale(ground_noise_scale)
	chunk.set_chunk_size(chunk_size)
	chunk.set_max_height(max_height)
	chunk.set_material(material)
	chunk.set_chunk_pos(chunk_pos)
	return chunk

func _recreate_chunks():
	for chunk in get_children():
		_on_chunk_destroy(chunk)
	_create_chunks()

func _update_children():
	for chunk in chunks.values():
		chunk._update()

func _create_chunks():
	chunks_mutex.lock()
	for i in range(-2,3):
		for j in range(-2,3):
			_create_chunk(car_chunk+chunk_size*Vector2(i,j))
	chunks_mutex.unlock()

func _create_chunk(chunk_pos):
	chunks[chunk_pos] = create_chunk(chunk_pos)
	_add_chunk(chunks[chunk_pos])

func _add_chunk(chunk):
	add_child(chunk)
	chunk.set_car(car)
	chunk.connect("destroy", self, "_on_chunk_destroy", [], CONNECT_ONESHOT | CONNECT_DEFERRED)

func _on_chunk_destroy(chunk):
	var chunk_pos = chunk.get_chunk_pos()
	if chunk_pos == null:
		chunk_pos = Vector2(chunk.global_tranform.origin.x, chunk.global_tranform.origin.z)
	if chunks.has(chunk_pos):
		chunks_mutex.lock()
		chunks.erase(chunk_pos)
		chunks_mutex.unlock()
		remove_child(chunk)
		chunk.free()

var chunk_creator_semaphore = Semaphore.new()
var chunk_creator_mutex = Mutex.new()
var chunk_creator_queue = []
var chunk_creator_thread : Thread

func _chunk_creator_thread(userdata):
	#print_debug("[thread] started")
	while true:
		chunk_creator_semaphore.wait()
		
		chunk_creator_mutex.lock()
		var chunk_pos = chunk_creator_queue.pop_back()
		chunk_creator_mutex.unlock()
		
		if chunk_pos == null:
			break
		
		#print_debug("[thread] creating chunk")
		var chunk = create_chunk(chunk_pos)
		
		chunks_mutex.lock()
		chunks[chunk_pos] = chunk
		chunks_mutex.unlock()
		
		call_deferred("_add_chunk", chunk)
	#print_debug("[thread] finished")
	return 0

export (NodePath) var car_node
var car : Node

var car_chunk = Vector2()

# Called when the node enters the scene tree for the first time.
func _ready():
	if Engine.editor_hint:
		ground_noise.connect("changed", self, "_recreate_chunks")
		call_deferred("_recreate_chunks")
	else:
		car = get_node(car_node)
		call_deferred("update_chunk_pos")
		call_deferred("run_chunk_creator_thread")

func run_chunk_creator_thread():
	chunk_creator_thread = Thread.new()
	print_debug("Starting chunk creator thread")
	chunk_creator_thread.start(self, "_chunk_creator_thread", null, 0)
	print_debug("Is chunk creator thread running? ", chunk_creator_thread.is_active())

func _exit_tree():
	chunk_creator_mutex.lock()
	chunk_creator_queue.push_front(null)
	chunk_creator_mutex.unlock()
	chunk_creator_semaphore.post()
	if chunk_creator_thread != null:
		chunk_creator_thread.wait_to_finish()
	if Engine.editor_hint:
		ground_noise.disconnect("changed", self, "_recreate_chunks")

func _physics_process(delta):
	if not Engine.editor_hint:
		var car_pos = car.global_transform.origin
		if car_chunk.distance_to(Vector2(car_pos.x,car_pos.z)) > chunk_size/8:
			car_chunk.x = chunk_size * int(car_pos.x / chunk_size)
			car_chunk.y = chunk_size * int(car_pos.z / chunk_size)
			update_chunk_pos()

func update_chunk_pos():
	for i in range(-4,5):
		for j in range(-4,5):
			update_chunk(car_chunk+chunk_size*Vector2(i,j))

func update_chunk(chunk_pos):
	if !chunks.has(chunk_pos):
		call_deferred("queue_create_chunk", chunk_pos)

func queue_create_chunk(chunk_pos):
	chunk_creator_mutex.lock()
	chunk_creator_queue.push_front(chunk_pos)
	chunk_creator_mutex.unlock()
	chunk_creator_semaphore.post()
