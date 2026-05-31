"""Cross-source + within-source dedup — Phase 2 pass-through.

Phase 5 replaces this with the spatial+name dedup described in spec §4 step 4
(within 100 m AND token_set_ratio >= 0.7; user-pin priority). For Phase 2
only one source runs, so there is nothing to dedup against.
"""

from __future__ import annotations

from collections.abc import Iterable, Iterator
from typing import Any

from importer.candidate import Candidate


def dedup(
    candidates: Iterable[Candidate],
    *,
    # TODO(Phase 5): narrow to list[Candidate] or list[UserPin] once the
    # user-pin type stabilizes.
    existing_user_pins: list[Any],
) -> Iterator[Candidate]:
    yield from candidates
