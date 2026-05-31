from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.normalize import NormalizeStats, normalize


def _c(name: str) -> Candidate:
    return Candidate(
        source="hifld_courts",
        source_external_id="X",
        source_dataset_version="v1",
        name=name,
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.STATE_LOCAL_GOVT,
        state="TX",
    )


def test_normalize_short_name_is_unchanged() -> None:
    stats = NormalizeStats()
    out = list(normalize([_c("Short")], stats=stats))
    assert out[0].name == "Short"
    assert stats.truncations == 0


def test_normalize_long_name_is_truncated_to_60_chars() -> None:
    long_name = "A" * 200
    stats = NormalizeStats()
    out = list(normalize([_c(long_name)], stats=stats))
    assert len(out[0].name) == 60
    assert out[0].name == "A" * 60
    assert stats.truncations == 1
    assert stats.examples == [(long_name, "A" * 60)]


def test_normalize_strips_whitespace() -> None:
    stats = NormalizeStats()
    out = list(normalize([_c("  Foo  ")], stats=stats))
    assert out[0].name == "Foo"
