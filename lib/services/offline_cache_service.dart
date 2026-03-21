import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Servicio de caché offline para TrazApp.
/// Guarda en Hive todo lo necesario para operar sin conexión:
/// perfil, obras, trabajadores por obra, catálogo EPP, bodegas.
/// Se actualiza automáticamente cada vez que hay conexión.
class OfflineCacheService {
  static const _boxName = 'trazapp_offline_cache';
  static const _keyPerfil       = 'perfil';
  static const _keyObras        = 'obras';
  static const _keyCatalogo     = 'catalogo_epp';
  static const _keyBodegas      = 'bodegas';
  static const _keyTrabajadores = 'trabajadores_obra_'; // + obraId
  static const _keyUltimaSync   = 'ultima_sync';

  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  static Box get _b {
    if (_box == null) throw StateError('OfflineCacheService.init() no fue llamado');
    return _box!;
  }

  // ─── GUARDAR ─────────────────────────────────────────────

  static Future<void> guardarPerfil(Map<String, dynamic> perfil) async {
    await _b.put(_keyPerfil, jsonEncode(perfil));
  }

  static Future<void> guardarObras(List<Map<String, dynamic>> obras) async {
    await _b.put(_keyObras, jsonEncode(obras));
  }

  static Future<void> guardarCatalogo(List<Map<String, dynamic>> items) async {
    await _b.put(_keyCatalogo, jsonEncode(items));
  }

  static Future<void> guardarBodegas(List<Map<String, dynamic>> bodegas) async {
    await _b.put(_keyBodegas, jsonEncode(bodegas));
  }

  static Future<void> guardarTrabajadores(
      String obraId, List<Map<String, dynamic>> trabajadores) async {
    await _b.put('$_keyTrabajadores$obraId', jsonEncode(trabajadores));
  }

  static Future<void> marcarSync() async {
    await _b.put(_keyUltimaSync, DateTime.now().toIso8601String());
  }

  // ─── LEER ────────────────────────────────────────────────

  static Map<String, dynamic>? getPerfil() {
    final raw = _b.get(_keyPerfil);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  static List<Map<String, dynamic>> getObras() {
    final raw = _b.get(_keyObras);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
  }

  static List<Map<String, dynamic>> getCatalogo() {
    final raw = _b.get(_keyCatalogo);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
  }

  static List<Map<String, dynamic>> getBodegas() {
    final raw = _b.get(_keyBodegas);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
  }

  static List<Map<String, dynamic>> getTrabajadores(String obraId) {
    final raw = _b.get('$_keyTrabajadores$obraId');
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)));
  }

  static DateTime? getUltimaSync() {
    final raw = _b.get(_keyUltimaSync);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static bool get tieneCacheValido => getPerfil() != null;

  /// Descripción legible de cuándo fue la última sync
  static String get descripcionSync {
    final ts = getUltimaSync();
    if (ts == null) return 'Sin sincronización previa';
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'Sincronizado hace un momento';
    if (diff.inHours < 1) return 'Sincronizado hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Sincronizado hace ${diff.inHours} h';
    return 'Sincronizado hace ${diff.inDays} días';
  }
}