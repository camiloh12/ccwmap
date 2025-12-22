import 'package:drift/drift.dart';

// Stub implementation - should never be used as platform-specific versions will be loaded
LazyDatabase openConnection() {
  throw UnsupportedError(
    'No suitable database implementation was found on this platform.',
  );
}
