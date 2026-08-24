import 'package:supabase_flutter/supabase_flutter.dart';

/// Resuelve URLs de objetos de Storage guardados como URL pública (legacy) o
/// como path, devolviendo una **signed URL** temporal.
///
/// Preparación para privar los buckets `evidencias` y `fotos-rostro`
/// (Fase 1: solo lecturas). Mientras el bucket siga público, `createSignedUrl`
/// funciona igual; si por alguna razón falla y el valor original es una URL
/// http, se devuelve tal cual como fallback para no romper la visualización.
class StorageUrlService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// TTL por defecto de las signed URLs (segundos). Corto — suficiente para
  /// mostrar en pantalla o embeber una vez en un PDF.
  static const int defaultTtl = 3600;

  /// Extrae el path relativo al [bucket] desde un valor que puede ser:
  /// - URL pública:  `https://.../object/public/<bucket>/<path>`
  /// - URL firmada:  `https://.../object/sign/<bucket>/<path>?token=...`
  /// - path directo: `<path>`
  ///
  /// Devuelve `null` si es una URL http de otro origen que no podemos firmar.
  static String? extractPath(String value, String bucket) {
    if (value.isEmpty) return null;
    for (final marker in ['/object/public/$bucket/', '/object/sign/$bucket/']) {
      final i = value.indexOf(marker);
      if (i != -1) {
        var p = value.substring(i + marker.length);
        final q = p.indexOf('?');
        if (q != -1) p = p.substring(0, q);
        return Uri.decodeComponent(p);
      }
    }
    // No parece URL → asumimos que ya es un path del bucket.
    if (!value.startsWith('http')) return value;
    return null;
  }

  /// Devuelve una signed URL para [value] en [bucket], o `null` si no aplica.
  static Future<String?> signedUrl(
    String? value,
    String bucket, {
    int ttl = defaultTtl,
  }) async {
    if (value == null || value.isEmpty) return null;
    final path = extractPath(value, bucket);
    if (path == null || path.isEmpty) {
      // Valor es una URL http que no pertenece a este bucket: úsala tal cual.
      return value.startsWith('http') ? value : null;
    }
    try {
      return await _sb.storage.from(bucket).createSignedUrl(path, ttl);
    } catch (_) {
      // Fallback durante la transición (bucket aún público).
      return value.startsWith('http') ? value : null;
    }
  }
}
