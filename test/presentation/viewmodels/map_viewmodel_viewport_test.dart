import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/data/repositories/pin_repository_impl.dart';
import 'package:ccwmap/data/services/blocklist_service.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/data/sync/viewport_pins_manager.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRemote implements RemoteDataSourceInterface {
  List<MapItem> bboxResult = [];
  int bboxCalls = 0;

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required String? currentUserId,
  }) async {
    bboxCalls++;
    return bboxResult;
  }

  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  }) async =>
      [];

  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  }) async =>
      [];

  @override
  Future<void> insertPin(SupabasePinDto pin) async {}
  @override
  Future<void> updatePin(SupabasePinDto pin) async {}
  @override
  Future<void> deletePin(String id) async {}
  @override
  Future<SupabasePinDto?> getPinById(String id) async => null;
}

class _AlwaysOnline implements NetworkMonitor {
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get isOnlineStream => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NullModeration implements ModerationRepository {
  @override
  Future<Set<String>> fetchBlocklist() async => const {};
  @override
  Future<void> blockUser(String id) async {}
  @override
  Future<void> unblockUser(String id) async {}
  @override
  Future<void> submitPinReport({
    required String pinId,
    required ReportReason reason,
    String? note,
  }) async {}
}

void main() {
  test('onCameraIdle dispatches debounced bbox fetch and publishes clusters',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final remote = _FakeRemote();
    remote.bboxResult = [
      const MapItemCluster(
        centroidLat: 30,
        centroidLng: -95,
        count: 5,
        dominantStatus: PinStatus.ALLOWED,
        dominantRestrictionTag: null,
      ),
    ];
    final vpm = ViewportPinsManager(
      remote: remote,
      pinDao: db.pinDao,
      tombstoneDao: db.pinTombstoneDao,
      fetchedBboxDao: db.fetchedBboxDao,
      userIdProvider: () => null,
    );
    final repo = PinRepositoryImpl(
      db.pinDao,
      db.syncQueueDao,
      db.pinTombstoneDao,
    );
    final vm = MapViewModel(
      repo,
      _AlwaysOnline(),
      BlocklistService(_NullModeration()),
      viewportPinsManager: vpm,
      bboxDebounce: const Duration(milliseconds: 50),
    );

    vm.onCameraIdle(
      swLat: 30,
      swLng: -96,
      neLat: 32,
      neLng: -94,
      zoom: 8,
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(remote.bboxCalls, 1);
    expect(vm.viewportClusters.value, hasLength(1));
  });
}
