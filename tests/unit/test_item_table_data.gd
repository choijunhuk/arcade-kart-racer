extends GutTest

const TABLE_PATH: String = "res://data/item_tables/default_8_karts.tres"
const RANK_COUNT: int = 8
const EXPECTED_ROW_TOTAL: float = 100.0


func test_default_table_contains_all_eight_rank_rows() -> void:
	var table: ItemTableData = load(TABLE_PATH) as ItemTableData

	assert_not_null(table)
	assert_eq(table.rows.size(), RANK_COUNT)


func test_every_rank_row_sums_to_one_hundred() -> void:
	var table: ItemTableData = load(TABLE_PATH) as ItemTableData

	for rank_index: int in range(RANK_COUNT):
		assert_almost_eq(
			table.row_total(rank_index),
			EXPECTED_ROW_TOTAL,
			0.001,
			"Rank %d weights must total 100" % (rank_index + 1),
		)


func test_every_row_matches_the_item_identifier_count() -> void:
	var table: ItemTableData = load(TABLE_PATH) as ItemTableData

	for rank_index: int in range(RANK_COUNT):
		assert_eq(table.rows[rank_index].size(), table.item_ids.size())
