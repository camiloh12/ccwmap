import 'package:flutter/foundation.dart';

import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/mappers/pin_mapper.dart';
import 'package:ccwmap/domain/models/map_item.dart';

/// Drives bbox-on-demand reads:
/// - Calls `get_pins_in_view` for the supplied viewport.
/// - Persists [MapItemPin]s to local DB with `cachedAt = now`.
/// - Exposes [MapItemCluster]s through [clusters] for the map screen.
/// - LRU-evicts oldest non-mine cached pins when row count > [cacheRowLimit].
///
/// Works for anonymous callers — the RPC is open to `anon` (cf. migration
/// 008 § 7 GRANT). When unauthenticated, [userIdProvider] returns null and
/// "non-mine" effectively means "everything", which is the right semantics.
class ViewportPinsManager {
  final RemoteDataSourceInterface remote;
  final PinDao pinDao;
  final PinTombstoneDao tombstoneDao;
  final FetchedBboxDao fetchedBboxDao;
  final String? Function() userIdProvider;
  final int cacheRowLimit;

  final ValueNotifier<List<MapItemCluster>> clusters =
      ValueNotifier<List<MapItemCluster>>(const []);

  /// Bumped on every fetch. After the remote call returns, the manager checks
  /// whether its generation is still current — if a newer fetch superseded it,
  /// the result is dropped before any local writes or notifier updates.
  int _fetchGeneration = 0;

  ViewportPinsManager({
    required this.remote,
    required this.pinDao,
    required this.tombstoneDao,
    required this.fetchedBboxDao,
    required this.userIdProvider,
    this.cacheRowLimit = 20000,
  });

  /// Single bbox fetch + cache write + LRU. Returns the generation it ran
  /// under so callers can correlate logs across concurrent fetches.
  Future<int> fetch({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
  }) async {
    final generation = ++_fetchGeneration;
    final items = await remote.getPinsInView(
      swLat: swLat,
      swLng: swLng,
      neLat: neLat,
      neLng: neLng,
      zoom: zoom,
      currentUserId: userIdProvider(),
    );

    if (generation != _fetchGeneration) {
      // A newer fetch started before this one returned. Drop result.
      return generation;
    }

    final now = DateTime.now().toUtc();
    final tombstoned = await tombstoneDao.getAllTombstonedPinIds();

    final pinsToWrite = <PinEntity>[];
    final clustersOut = <MapItemCluster>[];
    int pinRowCount = 0;
    for (final item in items) {
      switch (item) {
        case MapItemPin(:final pin):
          if (tombstoned.contains(pin.id)) continue;
          pinsToWrite.add(PinMapper.toCachedEntity(pin, cachedAt: now));
          pinRowCount++;
        case MapItemCluster():
          clustersOut.add(item);
      }
    }

    if (pinsToWrite.isNotEmpty) {
      await pinDao.upsertCachedPins(pinsToWrite);
    }

    final myId = userIdProvider();
    if (myId != null) {
      await pinDao.evictOldestCachedNonMine(
        myUserId: myId,
        maxRows: cacheRowLimit,
      );
    }

    await fetchedBboxDao.recordFetch(
      swLat: swLat,
      swLng: swLng,
      neLat: neLat,
      neLng: neLng,
      zoom: zoom,
      fetchedAt: now,
      pinCount: pinRowCount,
    );

    // Second defensive check: a newer fetch may have landed during the
    // DB await chain above. DB writes are idempotent (upsert + LRU
    // re-converges), but `clusters.value` is replace-semantics — racing
    // it would render a stale cluster set. The primary serialization
    // lives in BboxRequestDebouncer (Task 9, 500 ms debounce); this
    // check is a defensive belt-and-suspenders.
    if (generation != _fetchGeneration) return generation;
    clusters.value = clustersOut;
    return generation;
  }

  /// Drop every cached non-mine pin and clear the bbox log. Used by the
  /// pathological-cache fallback on app start.
  Future<void> reset() async {
    final myId = userIdProvider();
    if (myId != null) {
      await pinDao.deleteAllCachedNonMinePins(myId);
    }
    await fetchedBboxDao.pruneOlderThan(
      DateTime.now().toUtc().add(const Duration(days: 365)),
    );
    clusters.value = const [];
  }

  /// Cleanup invoked when the user signs out. We need to drop the prior
  /// user's bbox cache (their pins now look "non-mine" to the new session
  /// state) BEFORE [userIdProvider] starts returning null, because
  /// [reset]'s eviction is keyed off the current user id — at sign-out
  /// time Supabase has already cleared the session, so the provider
  /// returns null and [reset] would skip the delete entirely.
  ///
  /// Pass the departing user's id explicitly to sidestep that race.
  Future<void> resetForSignedOutUser(String formerUserId) async {
    await pinDao.deleteAllCachedNonMinePins(formerUserId);
    await fetchedBboxDao.pruneOlderThan(
      DateTime.now().toUtc().add(const Duration(days: 365)),
    );
    clusters.value = const [];
  }

  void dispose() {
    clusters.dispose();
  }
}
