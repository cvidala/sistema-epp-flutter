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

  const WorkerDetailPage({
    super.key,
    required this.obraId,
    required this.obraNombre,
    required this.trabajadorId,
    required this.trabajadorNombre,
    required this.trabajadorRut,
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
  List<dynamic> entregasOfflinePendientes = []; // ✅ entregas en cola local
  Map<String, String> eppIdToNombre = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ─────────────────────────────────────────────────────
  // CLAVE DEL HISTORIAL: clave de cache por trabajador
  // ─────────────────────────────────────────────────────
  String get _cacheKeyEntregas =>
      'entregas_${widget.trabajadorId}_${widget.obraId}';

  Future<void> _loadAll() async {
    setState(() {
      loading = true;
      error = null;
      modoOffline = false;
    });

    try {
      // 1) Catálogo EPP (con timeout)
      final catalogo = await supabase
          .from('catalogo_epp')
          .select('epp_id,nombre')
          .eq('activo', true)
          .timeout(const Duration(seconds: 12));

      eppIdToNombre = {
        for (final e in catalogo as List)
          (e['epp_id'] as String): (e['nombre'] as String)
      };

      // ✅ Guardar catálogo en cache
      await CacheService.setJson('catalogo_epp_nombres', catalogo);

      // 2) Historial de entregas (con timeout)
      final data = await supabase
          .from('entregas_epp')
          .select(
              'event_id, created_at, items, bodega_id, evidencia_foto_url, evidencia_hash')
          .eq('trabajador_id', widget.trabajadorId)
          .eq('obra_id', widget.obraId)
          .order('created_at', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 12));

      // ✅ Guardar historial en cache
      await CacheService.setJson(_cacheKeyEntregas, data);

      setState(() {
        entregas = data;
        entregasOfflinePendientes = _getEntregasPendientesLocales();
      });
    } catch (e) {
      debugPrint('[WorkerDetail] Error online: $e');

      // ✅ Fallback: leer desde cache
      final cachedCatalogo =
          CacheService.getJson('catalogo_epp_nombres');
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
          error = null; // ✅ no mostrar rojo si hay cache
        });
      } else {
        setState(() {
          modoOffline = true;
          entregasOfflinePendientes = _getEntregasPendientesLocales();
          // Si no hay cache de entregas, mostramos lista vacía con aviso offline
          // pero no error rojo
          error = null;
        });
      }
    } finally {
      setState(() => loading = false);
    }
  }

  // ─────────────────────────────────────────────────────
  // Entregas en cola local (offline pendientes)
  // ─────────────────────────────────────────────────────
  List<dynamic> _getEntregasPendientesLocales() {
    return OfflineQueueService.listPending()
        .where((e) =>
            e.status != 'SENT' &&
            e.trabajadorId == widget.trabajadorId &&
            e.obraId == widget.obraId)
        .map((e) => {
              'event_id': '${e.localEventId} (PENDIENTE SYNC)',
              'created_at': e.createdAtClientIso,
              'items': e.items,
              'bodega_id': e.bodegaId,
              'evidencia_foto_url': '',
              'evidencia_hash': e.evidenciaHash,
              '_offline': true, // marker
              '_status': e.status,
            })
        .toList();
  }

  // ─────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────
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

  void _showEvidenceDialog(String eventId, String? url, String? hash) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Evidencia · $eventId'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (url == null || url.isEmpty)
                  const Text('Sin evidencia registrada.')
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(url),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Hash (SHA-256):\n${(hash == null || hash.isEmpty) ? "—" : hash}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
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
            pw.Table.fromTextArray(
              headers: const ['EPP', 'Cantidad'],
              data: rows,
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold),
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
            'Documento generado digitalmente (MVP).',
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
    // ✅ Siempre recargar historial al volver de nueva entrega
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

    // Lista combinada: primero pendientes offline, luego sincronizadas
    final todasEntregas = [
      ...entregasOfflinePendientes,
      ...entregas,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trabajadorNombre),
        actions: [
          IconButton(
              onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goNewDelivery,
        icon: const Icon(Icons.add),
        label: const Text('Nueva entrega'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Banner offline
            if (modoOffline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off, size: 18, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Modo OFFLINE: mostrando datos en caché local.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            Text('RUT: ${widget.trabajadorRut}'),
            const SizedBox(height: 8),
            Text('Obra: ${widget.obraNombre}'),
            const SizedBox(height: 16),

            // ✅ Contador pendientes offline si hay
            if (entregasOfflinePendientes.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync,
                        size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${entregasOfflinePendientes.length} entrega(s) pendiente(s) de sincronización.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            const Text(
              'Historial (últimas 50):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: todasEntregas.isEmpty
                  ? Center(
                      child: Text(modoOffline
                          ? 'Sin entregas en caché local.'
                          : 'Sin entregas registradas.'),
                    )
                  : ListView.builder(
                      itemCount: todasEntregas.length,
                      itemBuilder: (context, index) {
                        final e = Map<String, dynamic>.from(
                            todasEntregas[index]);
                        final eventId =
                            (e['event_id'] ?? '').toString();
                        final createdAt = _formatDate(
                            (e['created_at'] ?? '').toString());
                        final itemsText = _itemsToText(e['items']);
                        final url =
                            (e['evidencia_foto_url'] ?? '').toString();
                        final hash =
                            (e['evidencia_hash'] ?? '').toString();
                        final isOffline = e['_offline'] == true;
                        final offlineStatus =
                            (e['_status'] ?? '').toString();

                        return Card(
                          // ✅ Borde naranja para pendientes offline
                          shape: isOffline
                              ? RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  side: const BorderSide(
                                      color: Colors.orange, width: 1.5),
                                )
                              : null,
                          child: ListTile(
                            title: Row(
                              children: [
                                Expanded(child: Text(eventId)),
                                if (isOffline)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.orange.withOpacity(0.15),
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      border: Border.all(
                                          color: Colors.orange),
                                    ),
                                    child: Text(
                                      offlineStatus,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text('$createdAt\n$itemsText'),
                            isThreeLine: true,
                            onTap: isOffline
                                ? null
                                : () => _showEvidenceDialog(
                                      eventId,
                                      url.isEmpty ? null : url,
                                      hash.isEmpty ? null : hash,
                                    ),
                            trailing: isOffline
                                ? const Icon(Icons.sync,
                                    color: Colors.orange)
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Ver evidencia',
                                        icon: Icon(
                                          url.isNotEmpty
                                              ? Icons.photo_camera
                                              : Icons
                                                  .photo_camera_outlined,
                                        ),
                                        onPressed: () =>
                                            _showEvidenceDialog(
                                          eventId,
                                          url.isEmpty ? null : url,
                                          hash.isEmpty ? null : hash,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'PDF',
                                        icon: const Icon(
                                            Icons.picture_as_pdf),
                                        onPressed: () async {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Generando PDF: $eventId')));
                                          await _printPdfForEntrega(e);
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'Copiar mensaje WhatsApp',
                                        icon: const Icon(Icons.copy),
                                        onPressed: () async {
                                          final msg =
                                              _buildWhatsappMessage(e);
                                          await Clipboard.setData(
                                              ClipboardData(text: msg));
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Mensaje copiado. Pégalo en WhatsApp.')));
                                        },
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}