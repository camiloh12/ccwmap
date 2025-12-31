import '../../domain/models/poi.dart';
import 'overpass_api_client.dart';

/// In-memory cache for POI data with LRU eviction
class PoiCache {
  static const Duration _cacheValidity = Duration(minutes: 30);
  static const int _maxCacheEntries = 20;

  final Map<String, _CachedPOIs> _cache = {};
  final List<String> _accessOrder = []; // For LRU tracking

  /// Gets cached POIs for the given bounds, or null if not cached or expired
  List<Poi>? getCached(OverpassBounds bounds) {
    final key = _generateKey(bounds);
    final cached = _cache[key];

    if (cached == null) {
      return null;
    }

    // Check if cache is still valid
    final age = DateTime.now().difference(cached.cachedAt);
    if (age > _cacheValidity) {
      // Expired, remove from cache
      _cache.remove(key);
      _accessOrder.remove(key);
      return null;
    }

    // Update access order for LRU
    _updateAccessOrder(key);

    return cached.pois;
  }

  /// Caches POIs for the given bounds
  void cache(OverpassBounds bounds, List<Poi> pois) {
    final key = _generateKey(bounds);

    // Add to cache
    _cache[key] = _CachedPOIs(
      pois: pois,
      cachedAt: DateTime.now(),
    );

    // Update access order
    _updateAccessOrder(key);

    // Enforce max cache size (LRU eviction)
    if (_cache.length > _maxCacheEntries) {
      final oldestKey = _accessOrder.first;
      _cache.remove(oldestKey);
      _accessOrder.removeAt(0);
    }
  }

  /// Removes expired cache entries
  void clearOld() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    _cache.forEach((key, cached) {
      final age = now.difference(cached.cachedAt);
      if (age > _cacheValidity) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }
  }

  /// Clears all cached data
  void clearAll() {
    _cache.clear();
    _accessOrder.clear();
  }

  /// Generates a cache key from bounds (rounded to 2 decimal places)
  String _generateKey(OverpassBounds bounds) {
    final rounded = bounds.rounded(2);
    return '${rounded.south},${rounded.west},${rounded.north},${rounded.east}';
  }

  /// Updates access order for LRU (most recently used goes to end)
  void _updateAccessOrder(String key) {
    _accessOrder.remove(key); // Remove if exists
    _accessOrder.add(key); // Add to end (most recent)
  }

  /// Gets the current cache size
  int get size => _cache.length;

  /// Checks if cache is empty
  bool get isEmpty => _cache.isEmpty;
}

/// Container for cached POI data
class _CachedPOIs {
  final List<Poi> pois;
  final DateTime cachedAt;

  _CachedPOIs({
    required this.pois,
    required this.cachedAt,
  });
}
