import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/data/services/blocklist_service.dart';
import '../../fakes/fake_moderation_repository.dart';

void main() {
  group('BlocklistService', () {
    late FakeModerationRepository fakeRepo;
    late BlocklistService service;

    setUp(() {
      fakeRepo = FakeModerationRepository();
      service = BlocklistService(fakeRepo);
    });

    test('starts empty', () {
      expect(service.blocked, isEmpty);
      expect(service.isBlocked('abc'), isFalse);
    });

    test('refresh loads remote blocklist', () async {
      fakeRepo.remoteBlocklist = {'user-1', 'user-2'};
      await service.refresh();
      expect(service.blocked, equals({'user-1', 'user-2'}));
      expect(service.isBlocked('user-1'), isTrue);
    });

    test('block updates remote + cache + notifies', () async {
      var notifyCount = 0;
      service.addListener(() => notifyCount++);

      await service.block('target-user');

      expect(fakeRepo.remoteBlocklist, contains('target-user'));
      expect(service.isBlocked('target-user'), isTrue);
      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('unblock updates remote + cache + notifies', () async {
      fakeRepo.remoteBlocklist = {'u1'};
      await service.refresh();
      expect(service.isBlocked('u1'), isTrue);

      var notifyCount = 0;
      service.addListener(() => notifyCount++);

      await service.unblock('u1');

      expect(fakeRepo.remoteBlocklist, isNot(contains('u1')));
      expect(service.isBlocked('u1'), isFalse);
      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('clear empties the cache without touching remote', () async {
      fakeRepo.remoteBlocklist = {'u1'};
      await service.refresh();
      expect(service.isBlocked('u1'), isTrue);

      service.clear();
      expect(service.blocked, isEmpty);
      expect(fakeRepo.remoteBlocklist, equals({'u1'})); // unchanged
    });
  });
}
