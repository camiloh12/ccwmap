"""ODbL share-alike compliance — Phase 2 stub.

The dump is only relevant for OSM-sourced rows (license: ODbL). Phase 6 adds
the OSM source; this stub keeps the pipeline interface stable until then.
"""

from __future__ import annotations

import logging
from pathlib import Path

logger = logging.getLogger(__name__)


def dump_osm_pins(
    *,
    out_dir: Path,
    applied_source_counts: dict[str, int],
) -> Path | None:
    osm_count = applied_source_counts.get("osm", 0)
    if osm_count == 0:
        logger.info("odbl_dump: no OSM rows applied; nothing to dump.")
        return None
    # Phase 6 will replace this body entirely; the raise is a safety net so a
    # partially-wired OSM source fails loudly rather than silently no-op'ing.
    raise NotImplementedError("ODbL dump generator is added in Phase 6.")
