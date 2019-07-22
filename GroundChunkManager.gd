tool
extends Node

signal updated
signal queue_empty
signal chunk_created
signal chunk_removed

export(PackedScene) var GroundChunk setget set_ground_chunk_class

func set_ground_chunk_class(chunk_class : PackedScene):
	GroundChunk = chunk_class
	emit_signal("updated")

export(Material) var material setget set_material

func set_material(material_in):
	material = material_in
	emit_signal("updated")

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
		var chunk = _create_chunk_instance(chunk_pos)
		chunk.connect("remove", self, "_remove_chunk")
		chunks.append(chunk_pos)
		emit_signal("chunk_created", chunk)
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
		
		#print_debug("[thread] creating chunk")
		var chunk = _create_chunk_instance(chunk_pos)
		chunk.connect("remove", self, "_remove_chunk")
		
		chunks_mutex.lock()
		chunks.append(chunk_pos)
		chunks_mutex.unlock()
		
		call_deferred("emit_signal", "chunk_created", chunk)
	#print_debug("[thread] finished")
	return 0

func _create_chunk_instance(chunk_pos):
	var chunk = GroundChunk.instance()
	chunk.set_noise(ground_noise)
	chunk.set_noise_scale(ground_noise_scale)
	chunk.set_chunk_size(chunk_size)
	chunk.set_max_height(max_height)
	chunk.set_material(material)
	chunk.set_chunk_pos(chunk_pos)
	return chunk

func _remove_chunk(chunk):
	if chunk != null:
		chunks_mutex.lock()
		chunks.erase(chunk.get_chunk_pos())
		chunks_mutex.unlock()
		emit_signal("chunk_removed", chunk)

func _close_threads():
	exit_mutex.lock()
	exit = true
	exit_mutex.unlock()
	creator_semaphore.post()
	while !threads.empty():
		var thread = threads.pop_front()
		thread.wait_to_finish()