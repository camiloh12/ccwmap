import 'package:ccwmap/data/datasources/supabase_remote_data_source.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps unique violation', () {
    final e = PostgrestException(message: 'duplicate key', code: '23505');
    expect(mapReportInsertError(e), isA<ReportAlreadyFiledException>());
  });

  test('maps limit', () {
    final e = PostgrestException(
      message: 'report_limit_exceeded: at most 10 reports per 24 hours',
      code: 'P0001',
    );
    expect(mapReportInsertError(e), isA<ReportLimitReachedException>());
  });

  test('maps pin_not_found', () {
    final e = PostgrestException(message: 'pin_not_found', code: 'P0002');
    expect(mapReportInsertError(e), isA<ReportedPinGoneException>());
  });

  test('maps pin_not_found when PostgREST returns another code', () {
    final e = PostgrestException(message: 'pin_not_found', code: '500');
    expect(mapReportInsertError(e), isA<ReportedPinGoneException>());
  });

  test('passes other errors through', () {
    final e = PostgrestException(message: 'boom', code: '42P01');
    expect(identical(mapReportInsertError(e), e), isTrue);
  });
}
