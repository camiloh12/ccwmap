import 'package:drift/drift.dart';

// Conditional imports for platform-specific database implementations
import 'database_connection.dart'
    if (dart.library.html) 'database_connection_web.dart'
    if (dart.library.io) 'database_connection_io.dart';

part 'database.g.dart';
part 'pin_dao.dart';
part 'sync_queue_dao.dart';
part 'pin_tombstone_dao.dart';

@DataClassName('PinEntity')
class Pins extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  IntColumn get status => integer()();
  TextColumn get restrictionTag => text().nullable()();
  BoolColumn get hasSecurityScreening => boolean().withDefault(const Constant(false))();
  BoolColumn get hasPostedSignage => boolean().withDefault(const Constant(false))();
  TextColumn get createdBy => text().nullable()();
  IntColumn get createdAt => integer()(); // milliseconds since epoch
  IntColumn get lastModified => integer()(); // milliseconds since epoch
  TextColumn get photoUri => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get votes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncQueueEntity')
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get pinId => text()();
  TextColumn get operationType => text()(); // CREATE, UPDATE, DELETE
  IntColumn get timestamp => integer()(); // milliseconds since epoch
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Persistent tombstones for pins the user deleted locally.
///
/// Defense-in-depth against the download phase re-inserting a pin that was
/// just deleted locally. Under the current RLS policy (any authenticated
/// user can delete any pin) the remote DELETE normally succeeds and the pin
/// disappears from later downloads naturally, so tombstones are not
/// strictly required. They're kept to handle mid-cycle failures: if a
/// DELETE succeeds on the client but the server-side row survives (network
/// glitch, future RLS policy change, race with another client recreating
/// the row), the tombstone still prevents the ghost from reappearing on
/// this device.
///
/// Tombstones are consulted on every download pass, so a locally-deleted
/// pin stays deleted across sync cycles and app restarts (on native —
/// the web build uses in-memory storage, so tombstones are per-session
/// there).
@DataClassName('PinTombstoneEntity')
class PinTombstones extends Table {
  TextColumn get pinId => text()();
  IntColumn get deletedAt => integer()(); // milliseconds since epoch

  @override
  Set<Column> get primaryKey => {pinId};
}

@DriftDatabase(
  tables: [Pins, SyncQueue, PinTombstones],
  daos: [PinDao, SyncQueueDao, PinTombstoneDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Constructor for testing with in-memory database
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(pinTombstones);
          }
        },
      );

  static LazyDatabase _openConnection() {
    return openConnection();
  }
}
