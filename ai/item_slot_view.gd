class_name ItemSlotView
extends RefCounted

## Read-only value API consumed by AIItemBrain. The base remains a safe empty
## view; Phase 7 binds one persistent view to each concrete ItemSlot node.

func has_item() -> bool:
	return false


func get_category() -> ItemData.ItemCategory:
	return ItemData.ItemCategory.PROJECTILE


func get_item_id() -> StringName:
	return &""
