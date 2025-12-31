import 'dart:developer' as developer;
import '../../domain/models/poi.dart';
import '../../domain/repositories/poi_repository.dart';
import '../datasources/overpass_api_client.dart';
import '../datasources/poi_cache.dart';

/// Implementation of PoiRepository that uses Overpass API with caching
class PoiRepositoryImpl implements PoiRepository {
  final OverpassApiClient _apiClient;
  final PoiCache _cache;

  PoiRepositoryImpl({
    required OverpassApiClient apiClient,
    required PoiCache cache,
  })  : _apiClient = apiClient,
        _cache = cache;

  @override
  Future<List<Poi>> getPOIs(OverpassBounds bounds) async {
    // Check cache first
    final cached = _cache.getCached(bounds);
    if (cached != null) {
      developer.log('POI cache hit for bounds: $bounds', name: 'PoiRepository');
      return cached;
    }

    // Cache miss - fetch from API
    try {
      developer.log('Fetching POIs from Overpass API for bounds: $bounds',
          name: 'PoiRepository');

      final pois = await _apiClient.fetchPOIs(bounds);

      // Cache the results
      _cache.cache(bounds, pois);

      developer.log('Fetched and cached ${pois.length} POIs',
          name: 'PoiRepository');

      return pois;
    } on OverpassRateLimitException catch (e) {
      developer.log('Rate limit exceeded: ${e.message}',
          name: 'PoiRepository', level: 900);

      // Return stale cache if available, otherwise empty list
      final staleCache = _cache.getCached(bounds);
      if (staleCache != null) {
        developer.log('Returning stale cache with ${staleCache.length} POIs',
            name: 'PoiRepository');
        return staleCache;
      }

      return [];
    } on OverpassApiException catch (e) {
      developer.log('API error: ${e.message}',
          name: 'PoiRepository', level: 900);

      // Return stale cache if available, otherwise empty list
      final staleCache = _cache.getCached(bounds);
      if (staleCache != null) {
        developer.log('Returning stale cache with ${staleCache.length} POIs',
            name: 'PoiRepository');
        return staleCache;
      }

      return [];
    } catch (e, stackTrace) {
      developer.log('Unexpected error fetching POIs: $e',
          name: 'PoiRepository', error: e, stackTrace: stackTrace, level: 1000);

      // Return stale cache if available, otherwise empty list
      final staleCache = _cache.getCached(bounds);
      if (staleCache != null) {
        developer.log('Returning stale cache with ${staleCache.length} POIs',
            name: 'PoiRepository');
        return staleCache;
      }

      return [];
    }
  }
}
