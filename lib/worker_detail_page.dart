import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import 'new_delivery_page.dart';
import 'services/cache_service.dart';
import 'services/offline_queue_service.dart';

class WorkerDetailPage extends StatefulWidget {
  final String obraId;
  final String obraNombre;
  final String trabajadorId;
  final String trabajadorNombre;
  final String trabajadorRut;
  final bool canWrite;
  final bool moduloEpp;

  const WorkerDetailPage({
    super.key,
    required this.obraId,
    required this.obraNombre,
    required this.trabajadorId,
    required this.trabajadorNombre,
    required this.trabajadorRut,
    this.canWrite  = true,
    this.moduloEpp = true,
  });

  @override
  State<WorkerDetailPage> createState() => _WorkerDetailPageState();
}

class _WorkerDetailPageState extends State<WorkerDetailPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;
  bool modoOffline = false;

  List<dynamic> entregas = [];
  List<dynamic> entregasOfflinePendientes = [];
  Map<String, String> eppIdToNombre = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  String get _cacheKeyEntregas =>
      'entregas_${widget.trabajadorId}_${widget.obraId}';

  Future<void> _loadAll() async {
    setState(() {
      loading = true;
      error = null;
      modoOffline = false;
    });

    try {
      final catalogo = await supabase
          .from('catalogo_epp')
          .select('epp_id,nombre')
          .eq('activo', true)
          .timeout(const Duration(seconds: 12));

      eppIdToNombre = {
        for (final e in catalogo as List)
          (e['epp_id'] as String): (e['nombre'] as String)
      };

      await CacheService.setJson('catalogo_epp_nombres', catalogo);

      final data = await supabase
          .from('entregas_epp')
          .select(
              'event_id, created_at, items, bodega_id, evidencia_foto_url, evidencia_hash, firma_url')
          .eq('trabajador_id', widget.trabajadorId)
          .eq('obra_id', widget.obraId)
          .order('created_at', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 12));

      await CacheService.setJson(_cacheKeyEntregas, data);

      setState(() {
        entregas = data;
        entregasOfflinePendientes = _getEntregasPendientesLocales();
      });
    } catch (e) {
      debugPrint('[WorkerDetail] Error online: $e');

      final cachedCatalogo = CacheService.getJson('catalogo_epp_nombres');
      final cachedEntregas = CacheService.getJson(_cacheKeyEntregas);

      if (cachedCatalogo is List) {
        eppIdToNombre = {
          for (final item in cachedCatalogo)
            if (item is Map)
              (item['epp_id'] ?? '').toString():
                  (item['nombre'] ?? '').toString()
        };
      }

      if (cachedEntregas is List) {
        setState(() {
          entregas = cachedEntregas;
          modoOffline = true;
          entregasOfflinePendientes = _getEntregasPendientesLocales();
          error = null;
        });
      } else {
        setState(() {
          modoOffline = true;
          entregasOfflinePendientes = _getEntregasPendientesLocales();
          error = null;
        });
      }
    } finally {
      setState(() => loading = false);
    }
  }

  List<dynamic> _getEntregasPendientesLocales() {
    return OfflineQueueService.listPending()
        .where((e) =>
            e.status != 'SENT' &&
            e.trabajadorId == widget.trabajadorId &&
            e.obraId == widget.obraId)
        .map((e) => {
              'event_id': e.localEventId,
              'created_at': e.createdAtClientIso,
              'items': e.items,
              'bodega_id': e.bodegaId,
              'evidencia_foto_url': '',
              'evidencia_hash': e.evidenciaHash,
              'firma_url': '',
              '_offline': true,
              '_status': e.status,
              '_evidenciaLocalPath': e.evidenciaLocalPath,
              '_firmaLocalPath': e.firmaLocalPath ?? '',
            })
        .toList();
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd-MM-yyyy HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  String _itemsToText(dynamic items) {
    if (items is! List) return '';
    final parts = <String>[];
    for (final it in items) {
      final eppId = (it['epp_id'] ?? '').toString();
      final cant = (it['cantidad'] ?? 1).toString();
      final nombre = eppIdToNombre[eppId] ?? eppId;
      parts.add('$nombre x$cant');
    }
    return parts.join(', ');
  }

  int _itemsCount(dynamic items) {
    if (items is! List) return 0;
    return items.fold(0, (sum, it) => sum + ((it['cantidad'] ?? 1) as int));
  }

  String _buildWhatsappMessage(Map<String, dynamic> e) {
    final eventId = (e['event_id'] ?? '').toString();
    final createdAt = _formatDate((e['created_at'] ?? '').toString());
    final itemsText = _itemsToText(e['items']);
    final url = (e['evidencia_foto_url'] ?? '').toString();

    return [
      '✅ Entrega EPP registrada',
      'Evento: $eventId',
      'Fecha: $createdAt',
      'Obra: ${widget.obraNombre}',
      'Trabajador: ${widget.trabajadorNombre} (${widget.trabajadorRut})',
      'Detalle: $itemsText',
      if (url.isNotEmpty) 'Evidencia: $url',
      '—',
      'Comprobante PDF disponible en el sistema (buscar por Evento).',
    ].join('\n');
  }

  List<List<String>> _itemsToRows(dynamic items) {
    if (items is! List) return [];
    final rows = <List<String>>[];
    for (final it in items) {
      final eppId = (it['epp_id'] ?? '').toString();
      final cant = (it['cantidad'] ?? 1).toString();
      final nombre = eppIdToNombre[eppId] ?? eppId;
      rows.add([nombre, cant]);
    }
    return rows;
  }

  void _showEvidenceDialog({
    required String eventId,
    String? url,
    String? hash,
    String? firmaUrl,
    String? evidenciaLocalPath,
    String? firmaLocalPath,
  }) {
    final shortId = eventId.length > 16 ? eventId.substring(0, 16) + '…' : eventId;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_outlined,
                          color: Color(0xFF0D2148), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          shortId,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0D2148),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Evidencia foto
                  const Text('Fotografía de evidencia',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF6B7A99))),
                  const SizedBox(height: 8),
                  if (evidenciaLocalPath != null && evidenciaLocalPath.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(evidenciaLocalPath),
                          fit: BoxFit.cover, width: double.infinity),
                    )
                  else if (url != null && url.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Text('No se pudo cargar'))),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F6FA),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Sin fotografía registrada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF6B7A99))),
                    ),

                  // Firma
                  const SizedBox(height: 16),
                  const Text('Firma del trabajador',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF6B7A99))),
                  const SizedBox(height: 8),
                  if (firmaLocalPath != null && firmaLocalPath.isNotEmpty)
                    Container(
                      width: double.infinity,
                      height: 110,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDDE2EE)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.file(File(firmaLocalPath),
                            fit: BoxFit.contain),
                      ),
                    )
                  else if (firmaUrl != null && firmaUrl.isNotEmpty)
                    Container(
                      width: double.infinity,
                      height: 110,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFDDE2EE)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(firmaUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Center(child: Text('No se pudo cargar'))),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F6FA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Sin firma registrada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF6B7A99))),
                    ),

                  // Hash
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'SHA-256: ${(hash == null || hash.isEmpty) ? "—" : hash}',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF6B7A99),
                          fontFamily: 'monospace'),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printPdfForEntrega(Map<String, dynamic> entrega) async {
    final eventId = (entrega['event_id'] ?? '').toString();
    final createdAtIso = (entrega['created_at'] ?? '').toString();
    final createdAtFmt = _formatDate(createdAtIso);
    final items = entrega['items'];
    final url = (entrega['evidencia_foto_url'] ?? '').toString();
    final hash = (entrega['evidencia_hash'] ?? '').toString();

    pw.ImageProvider? evidenceImage;
    if (url.isNotEmpty) {
      try {
        evidenceImage = await networkImage(url);
      } catch (_) {
        evidenceImage = null;
      }
    }

    final doc = pw.Document();
    final rows = _itemsToRows(items);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text('Comprobante de Entrega EPP',
              style: pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Evento: $eventId'),
          pw.Text('Fecha: $createdAtFmt'),
          pw.SizedBox(height: 12),
          pw.Text('Obra: ${widget.obraNombre}'),
          pw.Text('Trabajador: ${widget.trabajadorNombre}'),
          pw.Text('RUT: ${widget.trabajadorRut}'),
          pw.SizedBox(height: 16),
          pw.Text('Detalle de entrega',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text('Sin ítems.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['EPP', 'Cantidad'],
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(),
              cellHeight: 24,
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1),
              },
            ),
          pw.SizedBox(height: 16),
          pw.Text('Evidencia',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (evidenceImage != null)
            pw.ClipRRect(
              horizontalRadius: 8,
              verticalRadius: 8,
              child: pw.Image(evidenceImage,
                  height: 260, fit: pw.BoxFit.cover),
            )
          else
            pw.Text(url.isEmpty
                ? 'Sin evidencia.'
                : 'No se pudo cargar la imagen de evidencia.'),
          pw.SizedBox(height: 12),
          pw.Text(
              'Hash (SHA-256): ${hash.isEmpty ? "—" : hash}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 18),
          pw.Divider(),
          pw.Text(
            'Documento generado digitalmente.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'EPP-$eventId.pdf',
    );
  }

  Future<void> _goNewDelivery() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewDeliveryPage(
          obraId: widget.obraId,
          obraNombre: widget.obraNombre,
          trabajadorId: widget.trabajadorId,
          trabajadorNombre: widget.trabajadorNombre,
          trabajadorRut: widget.trabajadorRut,
        ),
      ),
    );
    _loadAll();
  }

  // ─────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final todasEntregas = [
      ...entregasOfflinePendientes,
      ...entregas,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trabajadorNombre),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: (widget.canWrite && widget.moduloEpp)
          ? FloatingActionButton.extended(
              onPressed: _goNewDelivery,
              icon: const Icon(Icons.add),
              label: const Text('Nueva entrega'),
            )
          : null,
      body: Column(
        children: [
          // ── Banners ─────────────────────────────────
          if (modoOffline)
            _InfoBanner(
              color: Colors.grey.shade100,
              icon: Icons.cloud_off,
              iconColor: Colors.grey,
              text: 'Sin conexión — datos desde caché local.',
            ),
          if (entregasOfflinePendientes.isNotEmpty)
            _InfoBanner(
              color: Colors.orange.shade50,
              icon: Icons.sync,
              iconColor: Colors.orange,
              text: '${entregasOfflinePendientes.length} entrega(s) pendiente(s) de sincronización.',
            ),

          // ── Header trabajador ────────────────────────
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEAEEF6)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF0D2148),
                  child: Text(
                    widget.trabajadorNombre.isNotEmpty
                        ? widget.trabajadorNombre[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.trabajadorNombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF0D2148),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.trabajadorRut,
                        style: const TextStyle(
                            color: Color(0xFF6B7A99), fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 13, color: Color(0xFF6B7A99)),
                          const SizedBox(width: 3),
                          Text(
                            widget.obraNombre,
                            style: const TextStyle(
                                color: Color(0xFF6B7A99), fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D2148).withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${todasEntregas.length} entregas',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D2148),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Título sección ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const Text(
                  'Historial de entregas',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF0D2148),
                  ),
                ),
                const Spacer(),
                Text(
                  'últimas 50',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),

          // ── Lista ────────────────────────────────────
          Expanded(
            child: todasEntregas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 52, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          modoOffline
                              ? 'Sin entregas en caché local.'
                              : 'Sin entregas registradas.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: todasEntregas.length,
                    itemBuilder: (context, index) {
                      final e = Map<String, dynamic>.from(todasEntregas[index]);
                      final eventId = (e['event_id'] ?? '').toString();
                      final createdAt =
                          _formatDate((e['created_at'] ?? '').toString());
                      final itemsText = _itemsToText(e['items']);
                      final itemsCount = _itemsCount(e['items']);
                      final url = (e['evidencia_foto_url'] ?? '').toString();
                      final hash = (e['evidencia_hash'] ?? '').toString();
                      final firmaUrl = (e['firma_url'] ?? '').toString();
                      final isOffline = e['_offline'] == true;
                      final offlineStatus = (e['_status'] ?? '').toString();
                      final evidenciaLocalPath =
                          (e['_evidenciaLocalPath'] ?? '').toString();
                      final firmaLocalPath =
                          (e['_firmaLocalPath'] ?? '').toString();

                      return _EntregaCard(
                        eventId: eventId,
                        fecha: createdAt,
                        itemsText: itemsText,
                        itemsCount: itemsCount,
                        hasPhoto: url.isNotEmpty || evidenciaLocalPath.isNotEmpty,
                        hasFirma: firmaUrl.isNotEmpty || firmaLocalPath.isNotEmpty,
                        isOffline: isOffline,
                        offlineStatus: offlineStatus,
                        onTapVer: () => _showEvidenceDialog(
                          eventId: eventId,
                          url: url.isEmpty ? null : url,
                          hash: hash.isEmpty ? null : hash,
                          firmaUrl: firmaUrl.isEmpty ? null : firmaUrl,
                          evidenciaLocalPath: evidenciaLocalPath.isEmpty
                              ? null
                              : evidenciaLocalPath,
                          firmaLocalPath:
                              firmaLocalPath.isEmpty ? null : firmaLocalPath,
                        ),
                        onTapPdf: isOffline
                            ? null
                            : () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Generando PDF: $eventId')));
                                await _printPdfForEntrega(e);
                              },
                        onTapCopy: isOffline
                            ? null
                            : () async {
                                final msg = _buildWhatsappMessage(e);
                                await Clipboard.setData(
                                    ClipboardData(text: msg));
                                if (!mounted) return;
                                // ignore: use_build_context_synchronously
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Mensaje copiado. Pégalo en WhatsApp.')),
                                );
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CARD DE ENTREGA — estilo dashboard
// ─────────────────────────────────────────────────────────────
class _EntregaCard extends StatelessWidget {
  final String eventId;
  final String fecha;
  final String itemsText;
  final int itemsCount;
  final bool hasPhoto;
  final bool hasFirma;
  final bool isOffline;
  final String offlineStatus;
  final VoidCallback onTapVer;
  final VoidCallback? onTapPdf;
  final VoidCallback? onTapCopy;

  const _EntregaCard({
    required this.eventId,
    required this.fecha,
    required this.itemsText,
    required this.itemsCount,
    required this.hasPhoto,
    required this.hasFirma,
    required this.isOffline,
    required this.offlineStatus,
    required this.onTapVer,
    this.onTapPdf,
    this.onTapCopy,
  });

  @override
  Widget build(BuildContext context) {
    // ID corto: si empieza por EPP- mostrarlo tal cual, si es UUID tomar primeros 8 chars
    final shortId = eventId.startsWith('EPP-')
        ? eventId
        : (eventId.length > 8 ? eventId.substring(0, 8).toUpperCase() : eventId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOffline
              ? Colors.orange.shade300
              : const Color(0xFFEAEEF6),
          width: isOffline ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTapVer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Fila superior: ID + badges + estado offline ──
              Row(
                children: [
                  // Icono estado
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isOffline
                          ? Colors.orange.withAlpha(25)
                          : const Color(0xFF0D2148).withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isOffline ? Icons.sync : Icons.check_circle_outline,
                      size: 20,
                      color: isOffline
                          ? Colors.orange
                          : const Color(0xFF0D2148),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shortId,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF0D2148),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          fecha,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6B7A99)),
                        ),
                      ],
                    ),
                  ),
                  if (isOffline)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Text(
                        offlineStatus,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF0F2F8)),
              const SizedBox(height: 10),

              // ── Detalle items ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 15, color: Color(0xFF6B7A99)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      itemsText.isEmpty ? 'Sin ítems' : itemsText,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF3D4A63)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE87722).withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$itemsCount ud.',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE87722),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Fila inferior: indicadores + acciones ──
              Row(
                children: [
                  // Badge foto
                  _MiniTag(
                    icon: hasPhoto ? Icons.photo_camera : Icons.photo_camera_outlined,
                    label: 'Foto',
                    active: hasPhoto,
                  ),
                  const SizedBox(width: 6),
                  // Badge firma
                  _MiniTag(
                    icon: hasFirma ? Icons.draw : Icons.draw_outlined,
                    label: 'Firma',
                    active: hasFirma,
                  ),
                  const Spacer(),
                  // Botones acción
                  _ActionBtn(
                    icon: Icons.visibility_outlined,
                    tooltip: 'Ver evidencia',
                    onTap: onTapVer,
                  ),
                  if (onTapPdf != null) ...[
                    const SizedBox(width: 4),
                    _ActionBtn(
                      icon: Icons.picture_as_pdf_outlined,
                      tooltip: 'PDF',
                      onTap: onTapPdf!,
                    ),
                  ],
                  if (onTapCopy != null) ...[
                    const SizedBox(width: 4),
                    _ActionBtn(
                      icon: Icons.share_outlined,
                      tooltip: 'Compartir',
                      onTap: onTapCopy!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _MiniTag(
      {required this.icon, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 13,
            color: active ? const Color(0xFF0D2148) : Colors.grey.shade400),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
              fontSize: 11,
              color: active ? const Color(0xFF0D2148) : Colors.grey.shade400),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6FA),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: const Color(0xFF0D2148)),
        ),
      ),
    );
  }
}

// Banner informativo reutilizable
class _InfoBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Color iconColor;
  final String text;

  const _InfoBanner({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: color,
      child: Row(
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: Color(0xFF3D4A63))),
          ),
        ],
      ),
    );
  }
}
