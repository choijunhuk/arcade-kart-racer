class_name ItemTableData
extends Resource

const EXPECTED_WEIGHT_TOTAL: float = 100.0

@export var item_ids: Array[StringName] = []
@export var rows: Array[PackedFloat32Array] = []


## Returns the sum of all item weights for a zero-based rank row.
func row_total(rank_index: int) -> float:
	if rank_index < 0 or rank_index >= rows.size():
		push_error("Item table rank index out of range: %d" % rank_index)
		return 0.0
	var total: float = 0.0
	for weight: float in rows[rank_index]:
		total += weight
	return total


## Reports whether every row matches the item count and totals exactly 100.
func is_valid_table() -> bool:
	if item_ids.is_empty() or rows.is_empty():
		return false
	for rank_index: int in range(rows.size()):
		if rows[rank_index].size() != item_ids.size():
			return false
		if not is_equal_approx(row_total(rank_index), EXPECTED_WEIGHT_TOTAL):
			return false
	return true
