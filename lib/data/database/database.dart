import 'package:drift/drift.dart';

// Conditional imports for platform-specific database implementations
import 'database_connection.dart'
    if (dart.library.html) 'database_connection_web.dart'
    if (dart.library.io) 'database_connection_io.dart';

part 'database.g.dart';
part 'pin_dao.dart';
part 'sync_queue_dao.dart';

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

@DriftDatabase(tables: [Pins, SyncQueue], daos: [PinDao, SyncQueueDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Constructor for testing with in-memory database
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return openConnection();
  }
}
