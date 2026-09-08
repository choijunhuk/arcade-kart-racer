class_name BoostItem
extends ItemBase

## Instant item boost translated from ItemData into BoostController input.


## Requests the data-defined boost and completes immediately.
func activate(_frame: InputFrame) -> void:
	var spec: BoostSpecData = BoostSpecData.new()
	spec.id = data.id
	spec.speed_mult = data.power
	spec.accel_mult = data.power
	spec.duration = data.duration
	spec.ignores_offroad = true
	owner_kart.request_boost(spec, &"item_boost")
	expire()
