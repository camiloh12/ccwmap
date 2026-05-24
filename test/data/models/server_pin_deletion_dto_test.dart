import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses pin_deletions SELECT row', () {
    final dto = ServerPinDeletionDto.fromJson({
      'pin_id': 'pin-1',
      'deleted_at': '2026-05-16T12:00:00Z',
      'original_created_by': 'me',
    });
    expect(dto.pinId, 'pin-1');
    expect(dto.deletedAt, DateTime.utc(2026, 5, 16, 12));
  });
}
