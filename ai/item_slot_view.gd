class_name ItemSlotView
extends RefCounted

## Read-only view of a kart's item slot handed to `AIItemBrain`. This is the
## null implementation: it always reports "no item", so Phase 6 AI can never
## actually try to use an item that does not exist yet. Phase 7's real
## `ItemSlot` should expose the same shape so `AIItemBrain` needs no changes.
## TODO(phase-7): replace call sites with a real ItemSlot-backed view.

func has_item() -> bool:
	return false


func get_category() -> StringName:
	return &""
