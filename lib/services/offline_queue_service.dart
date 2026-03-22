import 'dart:convert';
import 'dart:math';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// Estados: PENDING → UPLOADING → SENT
///                           ↘ ERROR (con backoff exponencial, máx 5 intentos)
///                                ↘ FAILED (abandono permanente)
class OfflineEntrega {
  OfflineEntrega({
    required this.localEventId,
    required this.createdAtClientIso,
    required this.scope,
    required this.obraId,
    required this.trabajadorId,
    required this.bodegaId,
    required this.items,
    required this.evidenciaLocalPath,
    required this.evidenciaHash,
    this.firmaLocalPath,
    this.firmaHash,
    this.forensics,
    this.evidenciaRemotePath,
    this.prevHash,
    this.hash,
    this.status = 'PENDING',
    this.lastError,
    this.attempts = 0,
    this.maxAttempts = 5,
    this.nextRetryAt,
  });

  final String localEventId;
  final String createdAtClientIso;
  final String scope;
  final String obraId;
  final String trabajadorId;
  final String bodegaId;

  final List<Map<String, dynamic>> items;

  final String evidenciaLocalPath;
  final String evidenciaHash;

  // Firma
  String? firmaLocalPath;
  String? firmaHash; // SHA-256 de los bytes de la firma (para integridad)

  // Datos forenses: GPS + device info
  Map<String, dynamic>? forensics;

  String? evidenciaRemotePath;

  // Hash chain
  String? prevHash;
  String? hash;

  // Estado de sync
  String status;
  String? lastError;
  int attempts;
  int maxAttempts;
  String? nextRetryAt; // ISO — no reintentar antes de esta fecha

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
        'firmaLocalPath': firmaLocalPath,
        'firmaHash': firmaHash,
        'forensics': forensics,
        'evidenciaRemotePath': evidenciaRemotePath,
        'prevHash': prevHash,
        'hash': hash,
        'status': status,
        'lastError': lastError,
        'attempts': attempts,
        'maxAttempts': maxAttempts,
        'nextRetryAt': nextRetryAt,
      };

  static OfflineEntrega fromMap(Map<String, dynamic> m) => OfflineEntrega(
        localEventId: m['localEventId'],
        createdAtClientIso: m['createdAtClientIso'],
        scope: m['scope'],
        obraId: m['obraId'],
        trabajadorId: m['trabajadorId'],
        bodegaId: m['bodegaId'],
        items: (m['items'] as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList(),
        evidenciaLocalPath: m['evidenciaLocalPath'],
        evidenciaHash: m['evidenciaHash'],
        firmaLocalPath: m['firmaLocalPath'] as String?,
        firmaHash: m['firmaHash'] as String?,
        forensics: m['forensics'] != null
            ? Map<String, dynamic>.from(m['forensics'] as Map)
            : null,
        evidenciaRemotePath: m['evidenciaRemotePath'],
        prevHash: m['prevHash'],
        hash: m['hash'],
        status: m['status'] ?? 'PENDING',
        lastError: m['lastError'],
        attempts: (m['attempts'] ?? 0) as int,
        maxAttempts: (m['maxAttempts'] ?? 5) as int,
        nextRetryAt: m['nextRetryAt'] as String?,
      );

  /// Calcula el delay de backoff para el próximo reintento.
  /// Fórmula: min(2^(attempts-1), 60) minutos.
  Duration get backoffDelay {
    final minutes = min(pow(2, attempts - 1).toInt(), 60);
    return Duration(minutes: minutes);
  }

  bool get isFailed => status == 'FAILED';
  bool get isPermanentlyFailed => isFailed || attempts >= maxAttempts;
}

class OfflineQueueService {
  static const _boxName = 'outbox_entregas';
  static const _uuid = Uuid();

  static Future<void> init() async {
    await Hive.openBox<String>(_boxName);
  }

  static String newLocalEventId() => _uuid.v4();

  static Future<void> enqueue(OfflineEntrega e) async {
    final box = Hive.box<String>(_boxName);
    await box.put(e.localEventId, jsonEncode(e.toMap()));
  }

  /// Retorna entregas pendientes de sync, respetando backoff.
  /// Excluye: SENT, FAILED, y ERRORs cuyo nextRetryAt aún no llegó.
  static List<OfflineEntrega> listPending() {
    final box = Hive.box<String>(_boxName);
    final now = DateTime.now();
    final out = <OfflineEntrega>[];

    for (final k in box.keys) {
      final raw = box.get(k);
      if (raw == null) continue;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final e = OfflineEntrega.fromMap(m);

      if (e.status == 'SENT' || e.status == 'FAILED') continue;

      // ERROR con backoff activo: no reintentar aún
      if (e.status == 'ERROR' && e.nextRetryAt != null) {
        final retryTime = DateTime.tryParse(e.nextRetryAt!);
        if (retryTime != null && retryTime.isAfter(now)) continue;
      }

      out.add(e);
    }

    out.sort((a, b) => a.createdAtClientIso.compareTo(b.createdAtClientIso));
    return out;
  }

  /// Todas las entregas incluyendo SENT y FAILED (para mostrar en UI).
  static List<OfflineEntrega> listAll() {
    final box = Hive.box<String>(_boxName);
    final out = <OfflineEntrega>[];
    for (final k in box.keys) {
      final raw = box.get(k);
      if (raw == null) continue;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      out.add(OfflineEntrega.fromMap(m));
    }
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
    e.nextRetryAt = null;
    await update(e);
  }

  /// Marca como FAILED permanente (sin más reintentos automáticos).
  static Future<void> markFailed(String localEventId, String reason) async {
    final box = Hive.box<String>(_boxName);
    final raw = box.get(localEventId);
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final e = OfflineEntrega.fromMap(m);
    e.status = 'FAILED';
    e.lastError = reason;
    await update(e);
  }
}
