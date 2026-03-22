import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Captura datos forenses en el momento de la firma:
/// - Coordenadas GPS (lat, lng, precisión)
/// - Timestamp GPS (del receptor, no del sistema)
/// - Modelo y OS del dispositivo
///
/// Si el permiso GPS es denegado o hay error, los campos de GPS
/// quedan null — la entrega igual se registra (captura degradada).
class ForensicService {
  static final _deviceInfo = DeviceInfoPlugin();

  static Future<Map<String, dynamic>> capture() async {
    final result = <String, dynamic>{
      'captured_at': DateTime.now().toUtc().toIso8601String(),
    };

    // ── GPS ────────────────────────────────────────────────
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12),
            ),
          );
          result['gps_lat']          = position.latitude;
          result['gps_lng']          = position.longitude;
          result['gps_accuracy_m']   = position.accuracy;
          result['gps_altitude_m']   = position.altitude;
          result['gps_captured_at']  =
              position.timestamp.toUtc().toIso8601String();
        } else {
          result['gps_error'] = 'permission_denied';
        }
      } else {
        result['gps_error'] = 'service_disabled';
      }
    } catch (e) {
      result['gps_error'] = e.toString();
      debugPrint('[ForensicService] GPS error: $e');
    }

    // ── Device info ────────────────────────────────────────
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        result['device_model']        = info.model;
        result['device_brand']        = info.brand;
        result['device_manufacturer'] = info.manufacturer;
        result['device_os_version']   = 'Android ${info.version.release}';
        result['device_sdk']          = info.version.sdkInt;
        result['device_id_android']   = info.id; // build fingerprint ID
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        result['device_model']      = info.model;
        result['device_brand']      = 'Apple';
        result['device_os_version'] = 'iOS ${info.systemVersion}';
        result['device_id_ios']     = info.identifierForVendor;
      }
    } catch (e) {
      result['device_error'] = e.toString();
      debugPrint('[ForensicService] Device info error: $e');
    }

    debugPrint('[ForensicService] Captured: $result');
    return result;
  }

  /// Retorna true si los datos forenses tienen GPS válido.
  static bool hasValidGps(Map<String, dynamic>? forensics) {
    if (forensics == null) return false;
    return forensics['gps_lat'] != null && forensics['gps_lng'] != null;
  }
}
