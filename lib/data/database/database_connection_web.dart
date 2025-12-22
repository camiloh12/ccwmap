import 'package:drift/drift.dart';
import 'package:drift/web.dart';

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    // Use in-memory storage for web (demo mode)
    // Note: Data won't persist across page reloads
    print('Web: Using in-memory database (demo mode)');
    return WebDatabase.withStorage(
      DriftWebStorage.volatile(),
    );
  });
}
