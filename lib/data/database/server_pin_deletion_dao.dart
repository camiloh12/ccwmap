part of 'database.dart';

@DriftAccessor(tables: [ServerPinDeletions])
class ServerPinDeletionDao extends DatabaseAccessor<AppDatabase>
    with _$ServerPinDeletionDaoMixin {
  ServerPinDeletionDao(super.db);
}
