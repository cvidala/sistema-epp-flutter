import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// Genera un UUID único por instalación de la app y lo persiste en Hive.
/// No cambia aunque el usuario cierre sesión o cambie de cuenta.
/// Es el identificador real del dispositivo físico en terreno.
class DeviceIdService {
  static const _boxName = 'device_config';
  static const _keyDeviceId = 'device_id';
  static const _uuid = Uuid();

  static Future<void> init() async {
    await Hive.openBox<String>(_boxName);

    // Si no existe aún, generar y guardar uno nuevo
    final box = Hive.box<String>(_boxName);
    if (box.get(_keyDeviceId) == null) {
      final newId = _uuid.v4();
      await box.put(_keyDeviceId, newId);
    }
  }

  /// Retorna el deviceId persistente de esta instalación.
  static String get deviceId {
    final box = Hive.box<String>(_boxName);
    // Nunca debería ser null si init() se llamó en main()
    return box.get(_keyDeviceId) ?? 'device-fallback';
  }
}