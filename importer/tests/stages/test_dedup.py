from importer.stages.dedup import _matches, _meters_between


def test_meters_between_is_zero_for_same_point():
    assert _meters_between(30.0, -97.0, 30.0, -97.0) == 0.0


def test_meters_between_approximates_one_degree_lat():
    # ~111 km per degree latitude.
    m = _meters_between(30.0, -97.0, 31.0, -97.0)
    assert 110_000 < m < 112_000


def test_matches_true_when_close_and_similar_name():
    assert _matches("Travis County Courthouse", 30.2672, -97.7431,
                    "Travis County Court House", 30.2673, -97.7432) is True


def test_matches_false_when_far_apart():
    assert _matches("Travis County Courthouse", 30.2672, -97.7431,
                    "Travis County Courthouse", 31.0, -97.7431) is False


def test_matches_false_when_names_differ():
    assert _matches("Federal Building", 30.2672, -97.7431,
                    "City Animal Shelter", 30.2673, -97.7432) is False
