class_name BoostPad
extends Area3D

@export var tuning: PhysicsTuning = preload("res://data/tuning/physics_default.tres")


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	($ArrowMesh as MeshInstance3D).visible = false
	var paint: StandardMaterial3D = PrimitiveArt.material(Color(0.1, 0.9, 1.0), true)
	for row: int in range(3):
		for side: int in [-1, 1]:
			var arrow: MeshInstance3D = PrimitiveArt.add_box(self, Vector3(1.5, 0.08, 0.2), Vector3(float(side) * 0.55, 0.12, float(row - 1) * 0.8), paint)
			arrow.rotation.y = float(side) * -PI * 0.25


func _on_body_entered(body: Node3D) -> void:
	if body is KartController:
		(body as KartController).request_boost(tuning.boost_pad_boost, &"boost_pad")
		EventBus.item_defense_triggered.emit(body)
