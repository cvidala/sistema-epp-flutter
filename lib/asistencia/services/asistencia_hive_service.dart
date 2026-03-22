import 'package:hive_flutter/hive_flutter.dart';
import '../models/asistencia_pendiente.dart';

class AsistenciaHiveService {
  static const _boxName = 'asistencias_pendientes';
  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  static Box get _b {
    assert(_box != null, 'AsistenciaHiveService.init() no fue llamado');
    return _box!;
  }

  static Future<void> guardar(AsistenciaPendiente a) async {
    await _b.put(a.id, a.toMap());
  }

  static List<AsistenciaPendiente> listarPendientes() {
    return _b.values
        .map((v) => AsistenciaPendiente.fromMap(v as Map))
        .where((a) => a.status == 'pendiente' || a.status == 'subiendo')
        .toList();
  }

  static List<AsistenciaPendiente> listarTodas() {
    return _b.values
        .map((v) => AsistenciaPendiente.fromMap(v as Map))
        .toList();
  }

  static Future<void> actualizarStatus(String id, String status) async {
    final v = _b.get(id);
    if (v == null) return;
    final a = AsistenciaPendiente.fromMap(v as Map);
    a.status = status;
    await _b.put(id, a.toMap());
  }

  static Future<void> incrementarIntento(String id, String error) async {
    final v = _b.get(id);
    if (v == null) return;
    final a = AsistenciaPendiente.fromMap(v as Map);
    a.intentos++;
    a.ultimoError = error;
    if (a.intentos >= 3) a.status = 'fallida';
    await _b.put(id, a.toMap());
  }

  static Future<void> marcarEnviada(String id) async =>
      actualizarStatus(id, 'enviada');

  static Future<void> eliminar(String id) async => _b.delete(id);
}
