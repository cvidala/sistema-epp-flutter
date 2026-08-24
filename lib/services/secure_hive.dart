import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provee el [HiveAesCipher] compartido para cifrar en reposo las boxes de
/// Hive que guardan PII (RUT, nombres, fotos, GPS, forensics) en el dispositivo.
///
/// La clave AES-256 se genera una vez por instalación y se guarda en el
/// almacenamiento seguro del SO (Keychain en iOS, Keystore/EncryptedSharedPrefs
/// en Android), nunca en la propia caché de Hive.
class SecureHive {
  static const _keyName = 'hive_encryption_key_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static HiveAesCipher? _cipher;

  /// Devuelve el cipher compartido, generando y persistiendo la clave la
  /// primera vez. Cacheado en memoria para las siguientes aperturas de box.
  static Future<HiveAesCipher> cipher() async {
    final cached = _cipher;
    if (cached != null) return cached;

    List<int> key;
    final stored = await _storage.read(key: _keyName);
    if (stored == null) {
      key = Hive.generateSecureKey(); // 256-bit seguro
      await _storage.write(key: _keyName, value: base64Encode(key));
    } else {
      key = base64Decode(stored);
    }

    final cipher = HiveAesCipher(key);
    _cipher = cipher;
    return cipher;
  }

  /// Solo para tests: fija un cipher determinístico y evita el acceso a
  /// flutter_secure_storage (que no tiene plugin nativo en `flutter test`).
  /// Llamar en el setUp antes de inicializar servicios que abren boxes.
  @visibleForTesting
  static void debugSetTestCipher([List<int>? key]) {
    _cipher = HiveAesCipher(key ?? List<int>.filled(32, 7));
  }
}
