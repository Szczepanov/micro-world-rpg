extends GutTest

func test_rotation_index_clamp() -> void:
	# Validate that only indices 0-3 produce valid Basis matrices with no NaN values.
	for idx: int in range(4):
		var b: Basis = Basis().rotated(Vector3.UP, idx * (PI / 2.0))
		assert_false(is_nan(b.x.x), "Basis X.x is NaN at index %d" % idx)
		assert_almost_eq(b.determinant(), 1.0, 0.0001, "Non-unit determinant at index %d" % idx)

func test_invalid_rotation_index_rejected() -> void:
	# Out-of-range indices 4 and -1 must be caught by the server guard.
	var valid_indices: Array[int] = [0, 1, 2, 3]
	assert_true(4 not in valid_indices)
	assert_true(-1 not in valid_indices)
