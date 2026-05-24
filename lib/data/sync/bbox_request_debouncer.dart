import 'dart:async';

/// Debounces a callback (default 500 ms) and tracks an in-flight generation
/// so that a callback in progress when a new [tick] arrives can be ignored
/// by its caller.
///
/// Usage from [ViewportPinsManager]:
/// ```dart
/// final gen = debouncer.currentGeneration;
/// final items = await remote.getPinsInView(...);
/// if (gen != debouncer.currentGeneration) return; // abandon stale work
/// ```
class BboxRequestDebouncer {
  final Duration interval;
  final Future<void> Function() onFire;

  Timer? _timer;
  int _generation = 0;

  BboxRequestDebouncer({required this.interval, required this.onFire});

  int get currentGeneration => _generation;

  void tick() {
    _generation++;
    _timer?.cancel();
    _timer = Timer(interval, () async {
      try {
        await onFire();
      } catch (_) {
        // Swallow — ViewportPinsManager handles its own errors.
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _generation++; // invalidate any in-flight result
  }

  void dispose() => cancel();
}
