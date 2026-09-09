class_name NetProjectiles
extends Node3D

## Presentation-only copies of server projectiles: no Areas, collision or item logic.
var _views: Dictionary[int, Node3D] = {}

## Reuses authored visual children, keyed by server activation id.
func apply(rows: Array[Dictionary], state: NetRaceState) -> void:
	var ids: Array[int] = []
	for row: Dictionary in rows:
		var id: int = int(row["id"])
		ids.append(id)
		if not _views.has(id):
			var data: ItemData = state.item_at(int(row["item"]))
			if data == null or data.scene == null:
				continue
			var source: Node3D = data.scene.instantiate() as Node3D
			var view: Node3D = Node3D.new()
			_copy_visuals(source, view)
			source.free()
			add_child(view)
			_views[id] = view
		_views[id].global_transform = row["pose"]
	for id: int in _views.keys():
		if not ids.has(id):
			_views[id].queue_free()
			_views.erase(id)

func _copy_visuals(source: Node, target: Node3D) -> void:
	for child: Node in source.get_children():
		if child is MeshInstance3D:
			var mesh: MeshInstance3D = MeshInstance3D.new()
			mesh.mesh = (child as MeshInstance3D).mesh
			mesh.material_override = (child as MeshInstance3D).material_override
			mesh.transform = (child as MeshInstance3D).transform
			target.add_child(mesh)
		elif child is Node3D and not child is CollisionObject3D and not child is CollisionShape3D:
			var group: Node3D = Node3D.new()
			group.transform = (child as Node3D).transform
			target.add_child(group)
			_copy_visuals(child, group)
