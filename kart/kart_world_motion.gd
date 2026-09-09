class_name KartWorldMotion
extends CharacterBody3D

## World-only movement proxy for a ghost whose visible kart has layer/mask zero.
## It has no kart/bump layer and cannot enter pickups, hazards, or another kart.


## Copies the kart's body shape and retains CharacterBody's ordinary slide solver.
func setup(kart: KartController) -> void:
	collision_layer = 0
	collision_mask = 1
	top_level = true
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = (kart.get_node("CollisionShape3D") as CollisionShape3D).shape
	add_child(collision)
	safe_margin = kart.safe_margin
	floor_snap_length = kart.floor_snap_length


## Applies exactly the same world slide calculation, then copies its result back.
func move_kart(kart: CharacterBody3D) -> void:
	global_transform = kart.global_transform
	velocity = kart.velocity
	up_direction = kart.up_direction
	move_and_slide()
	kart.global_transform = global_transform
	kart.velocity = velocity
