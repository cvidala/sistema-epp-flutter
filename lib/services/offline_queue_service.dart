import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class OfflineEntrega {
  OfflineEntrega({
    required this.localEventId,
    required this.createdAtClientIso,
    required this.scope,
    required this.obraId,
    required this.trabajadorId,
    required this.bodegaId,
    required this.items,
    required this.evidenciaLocalPath, // path local (mobile) o bytesBase64 si web
    required this.evidenciaHash,
    this.evidenciaRemotePath,
    this.prevHash,
    this.hash,
    this.status = 'PENDING', // PENDING | UPLOADING | SENT | ERROR
    this.lastError,
    this.attempts = 0,
  });

  final String localEventId; // uuid string
  final String createdAtClientIso;
  final String scope; // 'obra' o 'obra_trabajador'
  final String obraId;
  final String trabajadorId;
  final String bodegaId;

  final List<Map<String, dynamic>> items;

  final String evidenciaLocalPath;
  final String evidenciaHash;
  String? evidenciaRemotePath;

  String? prevHash;
  String? hash;

  String status;
  String? lastError;
  int attempts;

  Map<String, dynamic> toMap() => {
        'localEventId': localEventId,
        'createdAtClientIso': createdAtClientIso,
        'scope': scope,
        'obraId': obraId,
        'trabajadorId': trabajadorId,
        'bodegaId': bodegaId,
        'items': items,
        'evidenciaLocalPath': evidenciaLocalPath,
        'evidenciaHash': evidenciaHash,
        'evidenciaRemotePath': evidenciaRemotePath,
        'prevHash': prevHash,
        'hash': hash,
        'status': status,
        'lastError': lastError,
        'attempts': attempts,
      };

  static OfflineEntrega fromMap(Map<String, dynamic> m) => OfflineEntrega(
        localEventId: m['localEventId'],
        createdAtClientIso: m['createdAtClientIso'],
        scope: m['scope'],
        obraId: m['obraId'],
        trabajadorId: m['trabajadorId'],
        bodegaId: m['bodegaId'],
        items: (m['items'] as List).map((x) => Map<String, dynamic>.from(x)).toList(),
        evidenciaLocalPath: m['evidenciaLocalPath'],
        evidenciaHash: m['evidenciaHash'],
        evidenciaRemotePath: m['evidenciaRemotePath'],
        prevHash: m['prevHash'],
        hash: m['hash'],
        status: m['status'] ?? 'PENDING',
        lastError: m['lastError'],
        attempts: (m['attempts'] ?? 0) as int,
      );
}

class OfflineQueueService {
  static const _boxName = 'outbox_entregas';
  static const _uuid = Uuid();

  static Future<void> init() async {
    // abrir caja
    await Hive.openBox<String>(_boxName);
  }

  static String newLocalEventId() => _uuid.v4();

  static Future<void> enqueue(OfflineEntrega e) async {
    final box = Hive.box<String>(_boxName);
    await box.put(e.localEventId, jsonEncode(e.toMap()));
  }

  static List<OfflineEntrega> listPending() {
    final box = Hive.box<String>(_boxName);
    final out = <OfflineEntrega>[];
    for (final k in box.keys) {
      final raw = box.get(k);
      if (raw == null) continue;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final e = OfflineEntrega.fromMap(m);
      if (e.status != 'SENT') out.add(e);
    }
    // FIFO por createdAtClient
    out.sort((a, b) => a.createdAtClientIso.compareTo(b.createdAtClientIso));
    return out;
  }

  static Future<void> update(OfflineEntrega e) async {
    final box = Hive.box<String>(_boxName);
    await box.put(e.localEventId, jsonEncode(e.toMap()));
  }

  static Future<void> markSent(String localEventId) async {
    final box = Hive.box<String>(_boxName);
    final raw = box.get(localEventId);
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final e = OfflineEntrega.fromMap(m);
    e.status = 'SENT';
    e.lastError = null;
    await update(e);
  }
}
