class_name ItemTable
extends RefCounted

## Pure rank normalization, row interpolation, and seeded weighted selection.

const PREVIOUS_ITEM_WEIGHT_MULTIPLIER: float = 0.5


## Maps a one-based rank in any field size onto the inclusive 0..1 interval.
static func normalize_rank(rank: int, kart_count: int) -> float:
	if kart_count <= 1:
		return 0.0
	return clampf(float(rank - 1) / float(kart_count - 1), 0.0, 1.0)


## Interpolates adjacent table rows and halves the previous item's weight.
static func interpolated_weights(
	table: ItemTableData, rank_normalized: float, previous_id: StringName,
) -> PackedFloat32Array:
	if table == null or not table.is_valid_table():
		push_error("ItemTable requires a valid ItemTableData resource")
		return PackedFloat32Array()
	var row_position: float = clampf(rank_normalized, 0.0, 1.0) * float(table.rows.size() - 1)
	var lower_index: int = floori(row_position)
	var upper_index: int = mini(lower_index + 1, table.rows.size() - 1)
	var blend: float = row_position - float(lower_index)
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(table.item_ids.size())
	for item_index: int in range(table.item_ids.size()):
		var weight: float = lerpf(
			table.rows[lower_index][item_index],
			table.rows[upper_index][item_index],
			blend,
		)
		if table.item_ids[item_index] == previous_id:
			weight *= PREVIOUS_ITEM_WEIGHT_MULTIPLIER
		weights[item_index] = weight
	return weights


## Picks one item id from the interpolated weights using only the injected RNG.
static func pick(
	table: ItemTableData, rank_normalized: float, previous_id: StringName,
	rng: RandomNumberGenerator,
) -> StringName:
	if rng == null:
		push_error("ItemTable.pick requires an injected RNG")
		return &""
	var weights: PackedFloat32Array = interpolated_weights(table, rank_normalized, previous_id)
	var total: float = 0.0
	for weight: float in weights:
		total += weight
	if total <= 0.0:
		push_error("ItemTable.pick requires at least one positive item weight")
		return &""
	var roll: float = rng.randf() * total
	var cumulative: float = 0.0
	for item_index: int in range(weights.size()):
		cumulative += weights[item_index]
		if roll < cumulative:
			return table.item_ids[item_index]
	return table.item_ids[table.item_ids.size() - 1]
