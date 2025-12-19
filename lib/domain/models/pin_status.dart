enum PinStatus {
  ALLOWED,
  UNCERTAIN,
  NO_GUN;

  int get colorCode {
    switch (this) {
      case PinStatus.ALLOWED:
        return 0;
      case PinStatus.UNCERTAIN:
        return 1;
      case PinStatus.NO_GUN:
        return 2;
    }
  }

  String get displayName {
    switch (this) {
      case PinStatus.ALLOWED:
        return 'Allowed';
      case PinStatus.UNCERTAIN:
        return 'Uncertain';
      case PinStatus.NO_GUN:
        return 'No Guns';
    }
  }

  PinStatus next() {
    switch (this) {
      case PinStatus.ALLOWED:
        return PinStatus.UNCERTAIN;
      case PinStatus.UNCERTAIN:
        return PinStatus.NO_GUN;
      case PinStatus.NO_GUN:
        return PinStatus.ALLOWED;
    }
  }

  static PinStatus fromColorCode(int code) {
    switch (code) {
      case 0:
        return PinStatus.ALLOWED;
      case 1:
        return PinStatus.UNCERTAIN;
      case 2:
        return PinStatus.NO_GUN;
      default:
        throw ArgumentError('Invalid color code: $code');
    }
  }
}
