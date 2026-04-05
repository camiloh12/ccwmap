import 'package:ccwmap/domain/models/poi.dart';
import 'package:ccwmap/domain/repositories/poi_repository.dart';
import 'package:ccwmap/data/datasources/overpass_api_client.dart';

class FakePoiRepository implements PoiRepository {
  @override
  Future<List<Poi>> getPOIs(OverpassBounds bounds) async => [];
}
