enum RestrictionTag {
  FEDERAL_PROPERTY,
  AIRPORT_SECURE,
  STATE_LOCAL_GOVT,
  SCHOOL_K12,
  COLLEGE_UNIVERSITY,
  BAR_ALCOHOL,
  HEALTHCARE,
  PLACE_OF_WORSHIP,
  SPORTS_ENTERTAINMENT,
  PRIVATE_PROPERTY;

  String get displayName {
    switch (this) {
      case RestrictionTag.FEDERAL_PROPERTY:
        return 'Federal Property';
      case RestrictionTag.AIRPORT_SECURE:
        return 'Airport Secure Area';
      case RestrictionTag.STATE_LOCAL_GOVT:
        return 'State/Local Government';
      case RestrictionTag.SCHOOL_K12:
        return 'School (K-12)';
      case RestrictionTag.COLLEGE_UNIVERSITY:
        return 'College/University';
      case RestrictionTag.BAR_ALCOHOL:
        return 'Bar/Alcohol Establishment';
      case RestrictionTag.HEALTHCARE:
        return 'Healthcare Facility';
      case RestrictionTag.PLACE_OF_WORSHIP:
        return 'Place of Worship';
      case RestrictionTag.SPORTS_ENTERTAINMENT:
        return 'Sports/Entertainment Venue';
      case RestrictionTag.PRIVATE_PROPERTY:
        return 'Private Property';
    }
  }

  static RestrictionTag? fromString(String? value) {
    if (value == null) return null;
    try {
      return RestrictionTag.values.firstWhere(
        (tag) => tag.name == value,
      );
    } catch (e) {
      return null;
    }
  }
}
