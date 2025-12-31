import '../models/poi.dart';
import '../../data/datasources/overpass_api_client.dart';

/// Repository for fetching Points of Interest
abstract class PoiRepository {
  /// Fetches POIs within the given geographic bounds
  ///
  /// Returns cached data if available and valid, otherwise fetches from API.
  /// On API error, returns stale cached data or empty list.
  Future<List<Poi>> getPOIs(OverpassBounds bounds);
}
