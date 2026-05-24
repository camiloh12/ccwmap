from pathlib import Path

from importer.stages.odbl_dump import dump_osm_pins


def test_odbl_dump_is_noop_when_no_osm_pins(tmp_path: Path) -> None:
    result = dump_osm_pins(out_dir=tmp_path, applied_source_counts={"hifld_courts": 100})
    assert result is None
    assert list(tmp_path.iterdir()) == []
