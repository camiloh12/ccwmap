part of 'database.dart';

@DriftAccessor(tables: [FetchedBboxes])
class FetchedBboxDao extends DatabaseAccessor<AppDatabase>
    with _$FetchedBboxDaoMixin {
  FetchedBboxDao(super.db);

  Future<void> recordFetch({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required DateTime fetchedAt,
    required int pinCount,
  }) async {
    await into(fetchedBboxes).insert(
      FetchedBboxesCompanion.insert(
        swLat: swLat,
        swLng: swLng,
        neLat: neLat,
        neLng: neLng,
        zoom: zoom,
        fetchedAt: fetchedAt.millisecondsSinceEpoch,
        pinCount: pinCount,
      ),
    );
  }

  Future<List<FetchedBboxEntity>> getAll() => select(fetchedBboxes).get();

  Future<void> pruneOlderThan(DateTime threshold) async {
    await (delete(fetchedBboxes)..where(
          (t) =>
              t.fetchedAt.isSmallerThanValue(threshold.millisecondsSinceEpoch),
        ))
        .go();
  }
}
