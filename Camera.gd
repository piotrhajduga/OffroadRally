extends Camera

export (NodePath) var follow_this_path = null
export (Vector3) var target_distance = Vector3(-15.0,10.0,0.0)

export var camera_speed = 5.0

var follow_this = null
var last_lookat

func _ready():
	follow_this = get_node(follow_this_path)
	last_lookat = follow_this.global_transform.origin

func _process(delta):
	var target_pos = follow_this.global_transform.origin + target_distance.rotated(Vector3(0.0,1.0,0.0),follow_this.rotation.y)
	
	global_transform.origin = global_transform.origin.linear_interpolate(target_pos, delta * camera_speed)
	
	last_lookat = last_lookat.linear_interpolate(follow_this.global_transform.origin, delta * camera_speed)
	look_at(last_lookat, Vector3(0.0, 1.0, 0.0))