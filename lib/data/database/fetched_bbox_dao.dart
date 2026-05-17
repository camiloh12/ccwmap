part of 'database.dart';

@DriftAccessor(tables: [FetchedBboxes])
class FetchedBboxDao extends DatabaseAccessor<AppDatabase>
    with _$FetchedBboxDaoMixin {
  FetchedBboxDao(super.db);
}
