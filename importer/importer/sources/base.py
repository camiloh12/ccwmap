"""Abstract base for source modules."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Iterator
from typing import ClassVar

from importer.candidate import Candidate


class Source(ABC):
    SOURCE_NAME: ClassVar[str]

    @abstractmethod
    def fetch(self, *, refetch: bool = False) -> None:
        """Download (or skip if cached) the upstream dataset to local cache."""

    @abstractmethod
    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        """Yield one Candidate per upstream record; respect state_filter when set."""
