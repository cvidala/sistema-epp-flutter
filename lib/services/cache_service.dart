import 'dart:convert';
import 'package:hive/hive.dart';

class CacheService {
  static const _boxName = 'cache_api';

  static Future<void> init() async {
    await Hive.openBox<String>(_boxName);
  }

  static String _k(String key, {String? obraId}) => obraId == null ? key : '$key:$obraId';

  static Future<void> setJson(String key, Object value, {String? obraId}) async {
    final box = Hive.box<String>(_boxName);
    await box.put(_k(key, obraId: obraId), jsonEncode(value));
  }

  static dynamic getJson(String key, {String? obraId}) {
    final box = Hive.box<String>(_boxName);
    final raw = box.get(_k(key, obraId: obraId));
    if (raw == null) return null;
    return jsonDecode(raw);
  }
}
