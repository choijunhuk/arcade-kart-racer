class_name ItemSlotView
extends RefCounted

## Read-only value API consumed by AIItemBrain. The base remains a safe empty
## view; Phase 7 binds one persistent view to each concrete ItemSlot node.

var _slot: ItemSlot


## Binds this persistent view to one kart-owned slot.
func bind(slot: ItemSlot) -> void:
	_slot = slot

func has_item() -> bool:
	return _slot != null and _slot.has_item()


func get_category() -> ItemData.ItemCategory:
	return _slot.get_category() if _slot != null else ItemData.ItemCategory.PROJECTILE


func get_item_id() -> StringName:
	return _slot.get_item_id() if _slot != null else &""
