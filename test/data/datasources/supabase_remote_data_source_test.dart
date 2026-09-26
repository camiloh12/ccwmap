import 'dart:convert';

import 'package:ccwmap/data/datasources/supabase_remote_data_source.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Exercises the real Postgrest request/response path through a mocked HTTP
/// client — the RLS "silent 0 rows" behavior lives in the response shape, so
/// a fake data source can't catch it.
void main() {
  const pinId = '000036d3-cbb7-41b8-bd53-1918f2f92e9e';

  const dto = SupabasePinDto(
    id: pinId,
    name: 'Test Elementary School',
    latitude: 29.76,
    longitude: -95.37,
    status: 1,
    hasSecurityScreening: false,
    hasPostedSignage: false,
    createdAt: '2026-07-06T00:00:00Z',
    lastModified: '2026-07-06T00:00:00Z',
    votes: 0,
  );

  /// Builds a data source whose PATCH (update) and GET (follow-up existence
  /// check) return the given JSON arrays.
  SupabaseRemoteDataSource dataSourceWith({
    required List<Map<String, dynamic>> patchRows,
    required List<Map<String, dynamic>> getRows,
  }) {
    final mock = MockClient((request) async {
      final rows = switch (request.method) {
        'PATCH' => patchRows,
        'GET' => getRows,
        _ => throw StateError('unexpected ${request.method} ${request.url}'),
      };
      return http.Response(
        jsonEncode(rows),
        200,
        headers: {'content-type': 'application/json'},
        request: request, // postgrest reads response.request!
      );
    });
    final client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: mock,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return SupabaseRemoteDataSource(client);
  }

  group('SupabaseRemoteDataSource.updatePin', () {
    test('completes when the update touches the row', () async {
      final ds = dataSourceWith(
        patchRows: [
          {'id': pinId},
        ],
        getRows: [
          {'id': pinId},
        ],
      );

      await expectLater(ds.updatePin(dto), completes);
    });

    test('throws when 0 rows were updated but the row still exists '
        '(RLS silently filtered the UPDATE)', () async {
      final ds = dataSourceWith(
        patchRows: [],
        getRows: [
          {'id': pinId},
        ],
      );

      await expectLater(
        ds.updatePin(dto),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            // MyPinsSync swallows errors mentioning "not found" / "no rows"
            // (treats them as "pin gone"). This error must NOT be swallowed,
            // so it has to avoid those phrases and go through retry instead.
            allOf(
              contains(pinId),
              isNot(contains('not found')),
              isNot(contains('no rows')),
            ),
          ),
        ),
      );
    });

    test('completes when 0 rows were updated because the row is gone '
        '(deleted remotely — nothing left to update)', () async {
      final ds = dataSourceWith(patchRows: [], getRows: []);

      await expectLater(ds.updatePin(dto), completes);
    });
  });
}
