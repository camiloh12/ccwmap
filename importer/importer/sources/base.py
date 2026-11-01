"""Abstract base for source modules."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Iterator, Set as AbstractSet
from typing import ClassVar

from importer.candidate import Candidate


class Source(ABC):
    SOURCE_NAME: ClassVar[str]

    # External ids of records the source saw but dropped for a data problem
    # (missing name, no usable coordinate, ...), so the orphan planner can keep
    # the pins they already back. Never includes deliberate exclusions. Valid
    # once `iter_candidates` is exhausted; sources replace it with a fresh set.
    last_unusable_keys: AbstractSet[str] = frozenset()

    @abstractmethod
    def fetch(self, *, refetch: bool = False) -> None:
        """Download (or skip if cached) the upstream dataset to local cache."""

    @abstractmethod
    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        """Yield one Candidate per upstream record; respect state_filter when set."""
