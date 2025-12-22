import '../../domain/models/pin.dart';
import '../../domain/repositories/pin_repository.dart';
import '../database/database.dart';
import '../mappers/pin_mapper.dart';

/// Implementation of PinRepository using local Drift database
/// This is the local-only version - sync will be added in Iteration 10
class PinRepositoryImpl implements PinRepository {
  final PinDao _pinDao;

  PinRepositoryImpl(this._pinDao);

  @override
  Stream<List<Pin>> watchPins() {
    return _pinDao.watchAllPins().map((entities) {
      return entities.map((entity) => PinMapper.fromEntity(entity)).toList();
    });
  }

  @override
  Future<List<Pin>> getPins() async {
    final entities = await _pinDao.getAllPins();
    return entities.map((entity) => PinMapper.fromEntity(entity)).toList();
  }

  @override
  Future<Pin?> getPinById(String id) async {
    final entity = await _pinDao.getPinById(id);
    if (entity == null) return null;
    return PinMapper.fromEntity(entity);
  }

  @override
  Future<void> addPin(Pin pin) async {
    final entity = PinMapper.toEntity(pin);
    await _pinDao.insertPin(entity);
  }

  @override
  Future<void> updatePin(Pin pin) async {
    final entity = PinMapper.toEntity(pin);
    await _pinDao.updatePin(entity);
  }

  @override
  Future<void> deletePin(String id) async {
    await _pinDao.deletePin(id);
  }
}
