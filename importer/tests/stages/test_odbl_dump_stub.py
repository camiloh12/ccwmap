from pathlib import Path

import pytest

from importer.stages.odbl_dump import dump_osm_pins


def test_odbl_dump_is_noop_when_no_osm_pins(tmp_path: Path) -> None:
    result = dump_osm_pins(out_dir=tmp_path, applied_source_counts={"hifld_courts": 100})
    assert result is None
    assert list(tmp_path.iterdir()) == []


def test_odbl_dump_raises_for_osm_pins(tmp_path: Path) -> None:
    with pytest.raises(NotImplementedError):
        dump_osm_pins(out_dir=tmp_path, applied_source_counts={"osm": 50})
