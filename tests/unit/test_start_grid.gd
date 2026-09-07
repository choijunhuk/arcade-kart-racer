extends GutTest

## Spec §15.2: staggered 2-column grid generator used to pad tracks authored
## with fewer than the required StartGrid markers.


func test_generate_staggers_left_and_right_behind_the_anchor() -> void:
	var anchor: Transform3D = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var slots: Array[Transform3D] = StartGrid.generate(anchor, 4)
	assert_eq(slots.size(), 4)
	# Forward is -Z; slots must be behind the anchor (positive Z growing by row).
	assert_almost_eq(slots[0].origin.z, 0.0, 0.01)
	assert_gt(slots[2].origin.z, slots[0].origin.z)
	# Even/odd indices sit on opposite sides of the anchor's X axis.
	assert_lt(slots[0].origin.x, 0.0)
	assert_gt(slots[1].origin.x, 0.0)


func test_generate_preserves_anchor_orientation() -> void:
	var anchor: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(5.0, 0.0, 5.0))
	var slots: Array[Transform3D] = StartGrid.generate(anchor, 2)
	for slot: Transform3D in slots:
		assert_almost_eq(slot.basis.get_euler().y, anchor.basis.get_euler().y, 0.001)
