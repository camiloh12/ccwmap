import 'dart:async';

import 'package:ccwmap/data/sync/bbox_request_debouncer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BboxRequestDebouncer', () {
    test('fires the callback once after the debounce interval', () {
      fakeAsync((async) {
        int callCount = 0;
        final d = BboxRequestDebouncer(
          interval: const Duration(milliseconds: 500),
          onFire: () async => callCount++,
        );

        d.tick();
        d.tick();
        d.tick();

        async.elapse(const Duration(milliseconds: 400));
        expect(callCount, 0);
        async.elapse(const Duration(milliseconds: 200));
        expect(callCount, 1);
      });
    });

    test('cancel() aborts pending callbacks', () {
      fakeAsync((async) {
        int callCount = 0;
        final d = BboxRequestDebouncer(
          interval: const Duration(milliseconds: 500),
          onFire: () async => callCount++,
        );

        d.tick();
        async.elapse(const Duration(milliseconds: 200));
        d.cancel();
        async.elapse(const Duration(seconds: 2));

        expect(callCount, 0);
      });
    });

    test(
      'in-flight onFire continues to completion; abandonment is the caller responsibility',
      () async {
        // Real-async test because we want to observe Future scheduling, not
        // synthetic time.
        //
        // Timer.cancel() in tick() only cancels *pending* timers — it does
        // not cancel an in-flight async callback. So both onFire calls run
        // to completion and both increments fire. The abandonment semantic
        // belongs to the caller: ViewportPinsManager (Task 10) reads
        // `currentGeneration` before and after its own work and drops the
        // result if the generation changed. This test pins the debouncer's
        // own narrow contract: it does not (and should not) interrupt the
        // user-supplied async work.
        final completer = Completer<void>();
        int finishedCalls = 0;
        final d = BboxRequestDebouncer(
          interval: const Duration(milliseconds: 1),
          onFire: () async {
            await completer.future;
            finishedCalls++;
          },
        );

        d.tick();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // At this point onFire #1 is awaiting completer.future.

        final genBeforeSecondTick = d.currentGeneration;
        d.tick(); // bumps the generation
        expect(
          d.currentGeneration,
          greaterThan(genBeforeSecondTick),
          reason:
              'tick() must bump currentGeneration so callers can detect supersession',
        );

        completer
            .complete(); // onFire #1 now resolves; Timer for #2 fires shortly after.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Both onFire bodies ran to completion — the debouncer does not
        // interrupt in-flight work. Caller (Task 10) uses currentGeneration
        // to decide whether to honor the result.
        expect(finishedCalls, 2);
      },
    );
  });
}
