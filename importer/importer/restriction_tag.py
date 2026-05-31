"""Python mirror of `lib/domain/models/restriction_tag.dart`.

Order and names must match exactly — these strings are written verbatim into
Postgres `restriction_tag_type` enum values, and the app reads them back via
`RestrictionTag.fromString`.
"""

from enum import Enum


class RestrictionTag(str, Enum):
    FEDERAL_PROPERTY = "FEDERAL_PROPERTY"
    AIRPORT_SECURE = "AIRPORT_SECURE"
    STATE_LOCAL_GOVT = "STATE_LOCAL_GOVT"
    SCHOOL_K12 = "SCHOOL_K12"
    COLLEGE_UNIVERSITY = "COLLEGE_UNIVERSITY"
    BAR_ALCOHOL = "BAR_ALCOHOL"
    HEALTHCARE = "HEALTHCARE"
    PLACE_OF_WORSHIP = "PLACE_OF_WORSHIP"
    SPORTS_ENTERTAINMENT = "SPORTS_ENTERTAINMENT"
    PRIVATE_PROPERTY = "PRIVATE_PROPERTY"
