tool
extends Spatial

export (int) var chunk_radius_game = 4

export (int) var chunk_radius_editor = 2 setget set_chunk_radius_editor

func set_chunk_radius_editor(chunk_radius_editor_in):
	chunk_radius_editor = chunk_radius_editor_in
	if Engine.editor_hint:
		call_deferred("_recreate_chunks")

func _recreate_chunks():
	for chunk in $GroundChunks.get_children():
		chunk._remove()
	call_deferred("_ensure_chunks", Vector2())

func _add_chunk(chunk):
	$GroundChunks.add_child(chunk)
	chunk.set_car(car)

export (NodePath) var car_node
var car : Node

# Called when the node enters the scene tree for the first time.
func _ready():
	$GroundChunkManager.connect("chunk_created", self, "_add_chunk")
	if Engine.editor_hint:
		$GroundChunkManager.connect("updated", self, "_recreate_chunks")
	
	if !Engine.editor_hint:
		car = get_node(car_node)
		car.connect("moved", self, "_on_car_moved")
		call_deferred("_on_car_moved", car.global_transform.origin)
	else:
		call_deferred("_ensure_chunks", Vector2())

func _exit_tree():
	if Engine.editor_hint:
		$GroundChunkManager.disconnect("updated", self, "_recreate_chunks")
	$GroundChunkManager.disconnect("chunk_created", self, "_add_chunk")
	$GroundChunkManager.disconnect("chunk_removed", self, "_on_chunk_remove")

func _on_car_moved(car_pos):
	if not Engine.editor_hint:
		var chunk_size = $GroundChunkManager.chunk_size
		var car_chunk = Vector2(int(car_pos.x / chunk_size), int(car_pos.z / chunk_size)) * chunk_size
		car_chunk.x = chunk_size * int(car_pos.x / chunk_size)
		car_chunk.y = chunk_size * int(car_pos.z / chunk_size)
		_ensure_chunks(car_chunk)

func _ensure_chunks(car_chunk : Vector2):
	var radius = chunk_radius_game
	var chunk_size = $GroundChunkManager.chunk_size
	if Engine.editor_hint:
		radius = chunk_radius_editor
	for i in range(-radius,radius+1):
		for j in range(-radius,radius+1):
			$GroundChunkManager.ensure_chunk(car_chunk+chunk_size*Vector2(i,j), (i==0 and j==0))
