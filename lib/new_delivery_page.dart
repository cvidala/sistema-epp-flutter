import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'evidence_service.dart';
import 'models/evaluacion_entrega.dart';
import 'services/entrega_service.dart';
import 'dart:async';
import 'services/offline_queue_service.dart';
import 'services/cache_service.dart';

class NewDeliveryPage extends StatefulWidget {
  final String obraId;
  final String obraNombre;
  final String trabajadorId;
  final String trabajadorNombre;
  final String trabajadorRut;

  const NewDeliveryPage({
    super.key,
    required this.obraId,
    required this.obraNombre,
    required this.trabajadorId,
    required this.trabajadorNombre,
    required this.trabajadorRut,
  });

  @override
  State<NewDeliveryPage> createState() => _NewDeliveryPageState();
}

class _NewDeliveryPageState extends State<NewDeliveryPage> {
  Timer? _evalDebounce;
  bool _evalEnCurso = false;
  bool _evalPendiente = false;
  bool soloPendientes = false;

  // ✅ FIX: flag modo offline
  bool modoOffline = false;

  final _entregaService = EntregaService();

  EvaluacionEntrega? evaluacionActual;
  String estadoActual = 'OK';
  bool evaluando = false;

  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  List<dynamic> bodegas = [];
  String? bodegaId;

  List<dynamic> epps = [];

  final Map<String, int> carrito = {};

  Uint8List? evidenciaBytes;
  String? evidenciaNombre;
  Uint8List? firmaBytes;       // PNG de la firma del trabajador
  final SignatureController _firmaCtrl = SignatureController(
    penStrokeWidth: 3,
    penColor: const Color(0xFF0D2148),
    exportBackgroundColor: Colors.white,
  );

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ✅ FIX: dispose() fuera de _eppRow(), en el lugar correcto
  @override
  void dispose() {
    _firmaCtrl.dispose();
    _evalDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // ✅ _loadInit() dispara el semáforo al terminar, ya con modoOffline correcto.
    // NO llamar _recalcularSemaforo() aquí: modoOffline todavía es false en este punto.
    _loadInit();
  }

  // ─────────────────────────────────────────────
  // LOAD INIT — con cache online/offline blindado
  // ─────────────────────────────────────────────
  Future<void> _loadInit() async {
    setState(() {
      loading = true;
      error = null;
      modoOffline = false;
    });

    try {
      debugPrint('[_loadInit] INICIO');

      debugPrint('[_loadInit] consultando bodegas...');
      final b = await supabase
          .from('bodegas')
          .select()
          .or('obra_id.eq.${widget.obraId},obra_id.is.null')
          .order('created_at')
          .timeout(const Duration(seconds: 12));
      debugPrint('[_loadInit] bodegas OK: ${(b as List).length}');

      debugPrint('[_loadInit] consultando catalogo_epp...');
      final c = await supabase
          .from('catalogo_epp')
          .select()
          .eq('activo', true)
          .order('nombre')
          .timeout(const Duration(seconds: 12));
      debugPrint('[_loadInit] catalogo OK: ${(c as List).length}');

      // ✅ Guardar en cache para uso offline futuro
      await CacheService.setJson('bodegas', b, obraId: widget.obraId);
      await CacheService.setJson('catalogo_epp', c, obraId: widget.obraId);

      if (!mounted) return;
      setState(() {
        bodegas = b;
        epps = c;
        if (bodegas.isNotEmpty) bodegaId = bodegas.first['bodega_id'];
        modoOffline = false;
      });

      debugPrint('[_loadInit] FIN OK');

      // ✅ Semáforo inicial solo cuando hay conexión, DESPUÉS de confirmar modoOffline=false
      if (mounted) _programarEvaluacionSemaforo();
    } catch (e) {
      debugPrint('[_loadInit] ERROR: $e');

      // ✅ Fallback offline: leer desde cache local
      final bCached = CacheService.getJson('bodegas', obraId: widget.obraId);
      final cCached = CacheService.getJson('catalogo_epp', obraId: widget.obraId);

      if (bCached is List && cCached is List) {
        debugPrint('[_loadInit] Cargando desde cache offline');
        if (!mounted) return;
        setState(() {
          bodegas = bCached.map((x) => Map<String, dynamic>.from(x as Map)).toList();
          epps = cCached.map((x) => Map<String, dynamic>.from(x as Map)).toList();
          if (bodegas.isNotEmpty) bodegaId = bodegas.first['bodega_id'];
          modoOffline = true;
          estadoActual = 'OFFLINE';
          evaluacionActual = null;
          error = null; // ✅ No mostrar rojo si hay cache
        });
      } else {
        // Sin cache: mostrar error claro con instrucción
        if (!mounted) return;
        setState(() => error =
            'Sin conexión y sin cache local.\nAbre esta pantalla una vez con internet para cargar bodegas y catálogo.');
      }
    } finally {
      if (!mounted) return;
      setState(() => loading = false);
      debugPrint('[_loadInit] loading=false');
    }
  }

  // ─────────────────────────────────────────────
  // SEMÁFORO — con guard offline
  // ─────────────────────────────────────────────

  // ✅ FIX: guard modoOffline
  void _programarEvaluacionSemaforo() {
    if (modoOffline) return; // No RPC en offline
    _evalDebounce?.cancel();
    _evalDebounce = Timer(const Duration(milliseconds: 350), () async {
      await _recalcularSemaforoSeguro();
    });
  }

  Future<void> _recalcularSemaforoSeguro() async {
    if (_evalEnCurso) {
      _evalPendiente = true;
      return;
    }
    _evalEnCurso = true;
    try {
      await _recalcularSemaforo();
    } finally {
      _evalEnCurso = false;
      if (_evalPendiente) {
        _evalPendiente = false;
        _programarEvaluacionSemaforo();
      }
    }
  }

  Future<void> _recalcularSemaforo() async {
    // ✅ FIX: guard modoOffline
    if (modoOffline) {
      setState(() => estadoActual = 'OFFLINE');
      return;
    }

    debugPrint('➡️ recalcularSemaforo() INICIO');

    final items = carrito.entries
        .where((e) => e.value > 0)
        .map((e) => {'epp_id': e.key, 'cantidad': e.value})
        .toList()
        .cast<Map<String, dynamic>>();

    debugPrint('Items enviados a RPC: $items');

    try {
      setState(() => evaluando = true);
      final evaluacion = await _evaluarEntregaV2(items);
      final accion = (evaluacion['accion'] ?? 'OK').toString();
      setState(() {
        estadoActual = accion;
        evaluacionActual = EvaluacionEntrega(
          estado: accion,
          detalle: evaluacion,
        );
      });
    } catch (_) {
      setState(() => estadoActual = 'OK');
    } finally {
      setState(() => evaluando = false);
    }
  }

  // ─────────────────────────────────────────────
  // RPC evaluar_entrega_v2
  // ─────────────────────────────────────────────
  Future<Map<String, dynamic>> _evaluarEntregaV2(
      List<Map<String, dynamic>> items) async {
    final resp = await supabase.rpc('evaluar_entrega_v2', params: {
      'p_obra_id': widget.obraId,
      'p_trabajador_id': widget.trabajadorId,
      'p_items': items,
    });

    if (resp is Map<String, dynamic>) return Map<String, dynamic>.from(resp);

    if (resp is List && resp.isNotEmpty) {
      final first = resp.first;
      if (first is Map && first.containsKey('evaluar_entrega_v2')) {
        return Map<String, dynamic>.from(first['evaluar_entrega_v2'] as Map);
      }
      if (first is Map<String, dynamic>) return Map<String, dynamic>.from(first);
    }

    throw Exception('Respuesta inesperada de evaluar_entrega_v2: $resp');
  }

  // ─────────────────────────────────────────────
  // HELPERS DE ESTADO
  // ─────────────────────────────────────────────

  int _countCriticos() {
    final crit = evaluacionActual?.detalle?['pendientes_criticos'];
    return (crit is List) ? crit.length : 0;
  }

  int _countNoCriticos() {
    final noCrit = evaluacionActual?.detalle?['pendientes_no_criticos'];
    return (noCrit is List) ? noCrit.length : 0;
  }

  String? _severidadPendientePorEppId(String eppId) {
    final d = evaluacionActual?.detalle;
    if (d == null) return null;

    final crit = d['pendientes_criticos'];
    if (crit is List) {
      for (final it in crit) {
        if (it is Map && it['epp_id']?.toString() == eppId) return 'CRITICO';
      }
    }

    final noCrit = d['pendientes_no_criticos'];
    if (noCrit is List) {
      for (final it in noCrit) {
        if (it is Map && it['epp_id']?.toString() == eppId) return 'ADVERTENCIA';
      }
    }

    return null;
  }

  Set<String> _criticosEppIds() {
    final d = evaluacionActual?.detalle;
    final out = <String>{};
    final crit = d?['pendientes_criticos'];
    if (crit is List) {
      for (final it in crit) {
        if (it is Map && it['epp_id'] != null) out.add(it['epp_id'].toString());
      }
    }
    return out;
  }

  Set<String> _pendientesEppIds() {
    final d = evaluacionActual?.detalle;
    if (d == null) return {};
    final out = <String>{};

    final crit = d['pendientes_criticos'];
    if (crit is List) {
      for (final it in crit) {
        if (it is Map && it['epp_id'] != null) out.add(it['epp_id'].toString());
      }
    }

    final noCrit = d['pendientes_no_criticos'];
    if (noCrit is List) {
      for (final it in noCrit) {
        if (it is Map && it['epp_id'] != null) out.add(it['epp_id'].toString());
      }
    }

    return out;
  }

  // ─────────────────────────────────────────────
  // WIDGETS SEMÁFORO / CHECKLIST
  // ─────────────────────────────────────────────

  // ✅ FIX: casos OFFLINE antes de default, sin if sueltos dentro de switch
  Color _colorEstado(String estado) {
    switch (estado) {
      case 'OK':
        return Colors.green;
      case 'WARNING':
        return Colors.orange;
      case 'BLOQUEO':
        return Colors.red;
      case 'OFFLINE':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _iconEstado(String estado) {
    switch (estado) {
      case 'OK':
        return Icons.check_circle;
      case 'WARNING':
        return Icons.warning_amber_rounded;
      case 'BLOQUEO':
        return Icons.block;
      case 'OFFLINE':
        return Icons.cloud_off;
      default:
        return Icons.help_outline;
    }
  }

  String _tituloEstado(String estado) {
    switch (estado) {
      case 'OK':
        return 'Cumplimiento OK';
      case 'WARNING':
        return 'Cumplimiento con advertencias';
      case 'BLOQUEO':
        return 'Bloqueo por incumplimiento';
      case 'OFFLINE':
        return 'Modo Offline';
      default:
        return 'Sin evaluación';
    }
  }

  String? _mensajePrincipalEvaluacion() {
    final d = evaluacionActual?.detalle;
    if (d == null) return null;

    final errs = d['errors'];
    if (errs is List && errs.isNotEmpty && errs.first is Map) {
      final m = (errs.first['message'] ?? '').toString();
      if (m.trim().isNotEmpty) return m;
    }

    final warns = d['warnings'];
    if (warns is List && warns.isNotEmpty && warns.first is Map) {
      final m = (warns.first['message'] ?? '').toString();
      if (m.trim().isNotEmpty) return m;
    }

    return null;
  }

  Widget _buildSemaforoCard() {
    final color = _colorEstado(estadoActual);
    final msg = _mensajePrincipalEvaluacion();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconEstado(estadoActual), color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _tituloEstado(estadoActual),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    if (evaluando)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (modoOffline)
                  const Text(
                    'Validación de cumplimiento no disponible sin conexión.\nSe aplicará al sincronizar.',
                    style: TextStyle(fontSize: 12),
                  )
                else if (msg != null && msg.trim().isNotEmpty)
                  Text(msg, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipSeveridad(String severidad) {
    final esCritico = severidad == 'CRITICO';
    final color = esCritico ? Colors.red : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        severidad,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _extraerChecklistDesdeEvaluacion() {
    final d = evaluacionActual?.detalle;
    if (d == null) return [];

    final List<Map<String, dynamic>> out = [];

    final criticos = d['pendientes_criticos'];
    if (criticos is List) {
      for (final it in criticos) {
        if (it is Map) {
          out.add({
            'severidad': 'CRITICO',
            'nombre': (it['nombre'] ?? it['codigo'] ?? 'EPP').toString(),
            'estado': (it['estado'] ?? 'PENDIENTE').toString(),
            'codigo': it['codigo']?.toString(),
            'vence_por': it['vence_por']?.toString(),
            'vence_el': it['vence_el'],
            'dias_restantes': it['dias_restantes'],
            'usos_restantes': it['usos_restantes'],
            'usos_acumulados': it['usos_acumulados'],
          });
        }
      }
    }

    final noCriticos = d['pendientes_no_criticos'];
    if (noCriticos is List) {
      for (final it in noCriticos) {
        if (it is Map) {
          out.add({
            'severidad': 'NO_CRITICO',
            'nombre': (it['nombre'] ?? it['codigo'] ?? 'EPP').toString(),
            'estado': (it['estado'] ?? 'PENDIENTE').toString(),
            'codigo': it['codigo']?.toString(),
            'vence_por': it['vence_por']?.toString(),
            'vence_el': it['vence_el'],
            'dias_restantes': it['dias_restantes'],
            'usos_restantes': it['usos_restantes'],
            'usos_acumulados': it['usos_acumulados'],
          });
        }
      }
    }

    return out;
  }

  Widget _buildChecklistCard() {
    // ✅ En modo offline no mostramos checklist (no hay evaluación)
    if (modoOffline) return const SizedBox.shrink();

    final checklist = _extraerChecklistDesdeEvaluacion();

    String? warningMsg;
    final w = evaluacionActual?.detalle?['warnings'];
    if (w is List && w.isNotEmpty && w.first is Map) {
      warningMsg = (w.first['message'] ?? '').toString();
    }

    if (checklist.isEmpty) {
      if (warningMsg != null && warningMsg.trim().isNotEmpty) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Text(warningMsg, style: const TextStyle(fontSize: 13)),
        );
      }
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: const Text(
          'Checklist: sin pendientes para esta entrega.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Checklist obligatorio (según reglas de la obra)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          if (warningMsg != null && warningMsg.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(warningMsg, style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(height: 10),
          ...checklist.map((it) {
            final severidad = (it['severidad'] ?? 'NO_CRITICO').toString();
            final nombre = (it['nombre'] ?? 'EPP').toString();
            final estado = (it['estado'] ?? 'PENDIENTE').toString();
            final dias = it['dias_restantes'];
            final venceEl = it['vence_el'];
            final usoRestantes = it['usos_restantes'];
            final usoAcumulados = it['usos_acumulados'];
            final vencePor = (it['vence_por'] ?? '').toString();

            final esCritico = severidad == 'CRITICO';
            final color = esCritico ? Colors.red : Colors.orange;
            final icon = esCritico ? Icons.block : Icons.warning_amber_rounded;

            // ✅ Detalle según tipo de vencimiento
            String extra = '';
            if (vencePor == 'USO' || vencePor == 'AMBOS') {
              if (usoAcumulados != null) extra += ' · $usoAcumulados usos acumulados';
              if (usoRestantes != null) extra += ' · $usoRestantes usos restantes';
            }
            if (vencePor == 'FECHA' || vencePor == 'AMBOS') {
              if (dias != null) extra += ' · $dias días restantes';
              if (venceEl != null) extra += ' · vence: $venceEl';
            }
            if (extra.isEmpty &&
                (estado.toUpperCase().contains('VENC'))) {
              if (dias != null) extra = ' · $dias días';
              if (venceEl != null) extra += ' · vence: $venceEl';
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$nombre ($estado)$extra',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: color),
                    ),
                    child: Text(
                      esCritico ? 'CRÍTICO' : 'ADVERTENCIA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DIÁLOGOS
  // ─────────────────────────────────────────────

  List<Widget> _renderPendientes(List<dynamic> pendientes) {
    if (pendientes.isEmpty) return [const Text('Sin pendientes.')];
    return pendientes.map((p) {
      final m = Map<String, dynamic>.from(p as Map);
      final codigo = (m['codigo'] ?? '').toString();
      final nombre = (m['nombre'] ?? '').toString();
      final estado = (m['estado'] ?? '').toString();
      final venceEl = m['vence_el']?.toString();
      final dias = m['dias_restantes']?.toString();
      final extra = (venceEl != null && venceEl.isNotEmpty)
          ? ' • vence: $venceEl${dias != null ? ' ($dias días)' : ''}'
          : '';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(child: Text('$codigo - $nombre ($estado)$extra')),
          ],
        ),
      );
    }).toList();
  }

  Future<bool> _dialogBloqueo(List<dynamic> criticos) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Entrega bloqueada'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Faltan o están vencidos EPP obligatorios en modo BLOQUEO que no estás entregando:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ..._renderPendientes(criticos),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Volver'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<bool> _dialogWarning(List<dynamic> warns) async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Entrega con observación'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aún quedan EPP obligatorios pendientes (modo WARNING). Puedes continuar, pero quedará registrado.',
              ),
              const SizedBox(height: 12),
              ..._renderPendientes(warns),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuar igual'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<bool> _dialogDeclaracion(String declaracion) async {
    bool acepta = false;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Declaración del trabajador'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(declaracion),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: acepta,
                  onChanged: (v) => setLocal(() => acepta = v ?? false),
                  title: const Text('Confirmo y acepto la declaración'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nota: Esta confirmación (click) actúa como firma electrónica simple para el MVP.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Volver'),
            ),
            ElevatedButton(
              onPressed: acepta ? () => Navigator.of(ctx).pop(true) : null,
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    return proceed ?? false;
  }

  // ─────────────────────────────────────────────
  // OFFLINE QUEUE
  // ─────────────────────────────────────────────

  Future<void> _encolarEntregaOffline(
      List<Map<String, dynamic>> items) async {
    if (bodegaId == null) throw Exception('Selecciona una bodega.');
    if (evidenciaBytes == null) throw Exception('No hay evidencia para offline');

    final localPath = await EvidenceService.saveEvidenceOffline(
      bytes: evidenciaBytes!,
      filenameHint: evidenciaNombre ?? 'evidencia.jpg',
    );

    final evidenciaHash = EvidenceService.hashBytes(evidenciaBytes!);
    final localEventId = OfflineQueueService.newLocalEventId();

    final e = OfflineEntrega(
      localEventId: localEventId,
      createdAtClientIso: DateTime.now().toIso8601String(),
      scope: 'obra',
      obraId: widget.obraId,
      trabajadorId: widget.trabajadorId,
      bodegaId: bodegaId!,
      items: items,
      evidenciaLocalPath: localPath,
      evidenciaHash: evidenciaHash,
    );

    await OfflineQueueService.enqueue(e);
  }

  // ─────────────────────────────────────────────
  // GUARDAR
  // ─────────────────────────────────────────────

  String _genEventId() {
    final now = DateTime.now();
    final rnd = Random().nextInt(9000) + 1000;
    return 'EPP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}-$rnd';
  }

  String _declaracionAutomatica() {
    return 'Declaro haber recibido en forma gratuita los EPP indicados para la obra "${widget.obraNombre}". '
        'Además, declaro haber sido informado e instruido sobre su uso correcto, cuidado y obligación de utilizarlos '
        'según el procedimiento de seguridad vigente en la faena.';
  }

  Future<void> _pickEvidence() async {
    final picker = ImagePicker();
    final photo  = await picker.pickImage(
      source: ImageSource.camera,   // ← solo cámara, sin galería
      imageQuality: 80,             // compresión razonable
      preferredCameraDevice: CameraDevice.rear,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    setState(() {
      evidenciaBytes  = bytes;
      evidenciaNombre = photo.name;
    });
  }

  /// Muestra un dialog con el canvas de firma táctil.
  /// El trabajador firma con el dedo y se guarda como PNG.
  Future<void> _mostrarPanelFirma() async {
    _firmaCtrl.clear();
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Firma del trabajador'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'El trabajador debe firmar con el dedo en el recuadro.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF0D2148), width: 2),
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Signature(
                    controller: _firmaCtrl,
                    height: 180,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Limpiar'),
                onPressed: () => _firmaCtrl.clear(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar firma'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (_firmaCtrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes firmar antes de confirmar.')),
        );
      }
      return;
    }

    final png = await _firmaCtrl.toPngBytes();
    if (png != null) {
      setState(() => firmaBytes = png);
    }
  }

  Future<void> _guardar() async {
    if (bodegaId == null) {
      setState(() => error = 'Selecciona una bodega.');
      return;
    }

    final items = carrito.entries
        .where((e) => e.value > 0)
        .map((e) => {'epp_id': e.key, 'cantidad': e.value})
        .toList()
        .cast<Map<String, dynamic>>();

    if (items.isEmpty) {
      setState(() => error = 'Selecciona al menos un EPP y cantidad.');
      return;
    }

    if (evidenciaBytes == null) {
      setState(() =>
          error = 'Debes agregar evidencia (imagen) antes de guardar.');
      return;
    }

    if (firmaBytes == null) {
      setState(() => error = 'Debes registrar la firma del trabajador.');
      return;
    }

    setState(() {
      error = null;
      loading = true;
    });

    try {
      // ✅ Si estamos offline, saltar directo a cola (sin intentar RPC)
      if (modoOffline) {
        final declaracion = _declaracionAutomatica();
        final acepta = await _dialogDeclaracion(declaracion);
        if (!acepta) {
          setState(() => loading = false);
          return;
        }
        await _encolarEntregaOffline(items);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Sin conexión: entrega guardada OFFLINE (pendiente de sincronización).')),
        );
        Navigator.of(context).pop(true);
        return;
      }

      // ── Flujo ONLINE ──────────────────────────────
      final evaluacion = await _evaluarEntregaV2(items);
      final accion = (evaluacion['accion'] ?? 'OK').toString();

      final pendientesCrit =
          (evaluacion['pendientes_criticos'] as List?) ?? const [];
      final pendientesWarn =
          (evaluacion['pendientes_no_criticos'] as List?) ?? const [];

      if (!mounted) return;

      if (accion == 'BLOQUEO') {
        await _dialogBloqueo(pendientesCrit);
        setState(() => loading = false);
        return;
      }

      if (accion == 'WARNING') {
        final seguir = await _dialogWarning(pendientesWarn);
        if (!seguir) {
          setState(() => loading = false);
          return;
        }
      }

      final declaracion = _declaracionAutomatica();
      final acepta = await _dialogDeclaracion(declaracion);
      if (!acepta) {
        setState(() => loading = false);
        return;
      }

      final eventId = _genEventId();
      final userId = supabase.auth.currentUser?.id;

      final evidenciaHash = EvidenceService.hashBytes(evidenciaBytes!);
      final path = 'epp/$eventId.jpg';

      await supabase.storage.from('evidencias').uploadBinary(
            path,
            evidenciaBytes!,
            fileOptions: const FileOptions(upsert: false),
          );

      final evidenciaUrl =
          supabase.storage.from('evidencias').getPublicUrl(path);

      // Subir firma como PNG separado
      final firmaPath = 'epp/$eventId\_firma.png';
      await supabase.storage.from('evidencias').uploadBinary(
            firmaPath,
            firmaBytes!,
            fileOptions: const FileOptions(upsert: false),
          );
      final firmaUrl =
          supabase.storage.from('evidencias').getPublicUrl(firmaPath);

      final payloadEntrega = <String, dynamic>{
        'event_id': eventId,
        'trabajador_id': widget.trabajadorId,
        'obra_id': widget.obraId,
        'bodega_id': bodegaId,
        'items': items,
        'entregado_por': userId,
        'sync_status': 'ENVIADO',
        'evidencia_foto_url': evidenciaUrl,
        'evidencia_hash': evidenciaHash,
        'firma_url': firmaUrl,
        'evaluacion': evaluacion,
        'declaracion_text': declaracion,
        'validacion_tipo': 'FIRMA_DIGITAL',
      };

      await supabase.from('entregas_epp').insert(payloadEntrega);

      for (final it in items) {
        await supabase.from('stock_movimientos').insert({
          'bodega_id': bodegaId,
          'epp_id': it['epp_id'],
          'tipo': 'SALIDA',
          'cantidad': it['cantidad'],
          'referencia_event_id': eventId,
          'motivo': 'Entrega EPP',
          'created_by': userId,
        });
      }

      // ✅ Registrar uso por cada EPP entregado (para control vence_por=USO/AMBOS)
      try {
        await supabase.rpc('registrar_uso_epp', params: {
          'p_event_id':      eventId,
          'p_trabajador_id': widget.trabajadorId,
          'p_obra_id':       widget.obraId,
          'p_items':         items,
        });
      } catch (usoErr) {
        // No crítico: la entrega ya quedó registrada.
        debugPrint('[guardar] registrar_uso_epp falló (no crítico): $usoErr');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Entrega registrada: \$eventId')));
      Navigator.of(context).pop(true);
    } catch (e) {
      // Fallback offline si el flujo online falla a mitad
      try {
        await _encolarEntregaOffline(items);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Sin conexión: entrega guardada OFFLINE (pendiente de sincronización).')),
        );
        Navigator.of(context).pop(true);
        return;
      } catch (e2) {
        setState(() => error = 'Online falló: $e\nOffline falló: $e2');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ─────────────────────────────────────────────
  // EPP ROW
  // ─────────────────────────────────────────────

  // ✅ FIX: dispose() removido de aquí (está arriba en el State)
  Widget _eppRow(Map<String, dynamic> e) {
    final id = e['epp_id'] as String;
    final nombre = (e['nombre'] ?? '').toString();
    final qty = carrito[id] ?? 0;
    final selected = qty > 0;
    final eppId = e['epp_id'].toString();
    final sev = soloPendientes ? _severidadPendientePorEppId(eppId) : null;

    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(nombre)),
          if (sev != null) ...[
            const SizedBox(width: 8),
            _chipSeveridad(sev),
          ],
        ],
      ),
      trailing: selected
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    setState(() {
                      final next = (carrito[id] ?? 0) - 1;
                      if (next <= 0) {
                        carrito.remove(id);
                      } else {
                        carrito[id] = next;
                      }
                    });
                    _programarEvaluacionSemaforo();
                  },
                ),
                Text(qty.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    setState(() => carrito[id] = (carrito[id] ?? 0) + 1);
                    _programarEvaluacionSemaforo();
                  },
                ),
              ],
            )
          : IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: () {
                setState(() => carrito[id] = 1);
                _programarEvaluacionSemaforo();
              },
            ),
    );
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final critCount = _countCriticos();
    final warnCount = _countNoCriticos();

    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva Entrega EPP')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: (error != null)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Error: $error',
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => error = null);
                      _loadInit();
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  // ✅ Banner offline (visible arriba cuando no hay conexión)
                  if (modoOffline)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 8),
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
                              'Modo OFFLINE: usando datos en caché local.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  _buildSemaforoCard(),
                  const SizedBox(height: 10),
                  _buildChecklistCard(),
                  const SizedBox(height: 14),

                  Text('Obra: ${widget.obraNombre}'),
                  const SizedBox(height: 4),
                  Text(
                      'Trabajador: ${widget.trabajadorNombre} (${widget.trabajadorRut})'),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: bodegaId,
                    items: bodegas
                        .map<DropdownMenuItem<String>>(
                          (b) => DropdownMenuItem<String>(
                            value: b['bodega_id'] as String?,
                            child:
                                Text((b['nombre'] ?? 'Bodega').toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() => bodegaId = v);
                      _programarEvaluacionSemaforo();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Bodega',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(
                        evidenciaBytes == null
                            ? Icons.camera_alt
                            : Icons.check_circle,
                        color: Colors.white,
                      ),
                      label: Text(
                        evidenciaBytes == null
                            ? 'Agregar evidencia (imagen)'
                            : '✓ Evidencia cargada',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: evidenciaBytes == null
                            ? null
                            : Colors.green.shade600,
                      ),
                      onPressed: _pickEvidence,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Botón de firma del trabajador
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(
                        firmaBytes == null
                            ? Icons.draw_outlined
                            : Icons.check_circle,
                        color: Colors.white,
                      ),
                      label: Text(
                        firmaBytes == null
                            ? 'Firma del trabajador'
                            : '✓ Firma registrada',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: firmaBytes == null
                            ? const Color(0xFF0D2148)
                            : Colors.green.shade600,
                      ),
                      onPressed: _mostrarPanelFirma,
                    ),
                  ),

                  // Preview de firma si ya fue capturada
                  if (firmaBytes != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFEAEEF6)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.memory(firmaBytes!, fit: BoxFit.contain),
                      ),
                    ),

                  const SizedBox(height: 16),
                  const Text(
                    'Selecciona EPP y cantidad:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Switch(
                        value: soloPendientes,
                        onChanged: (v) =>
                            setState(() => soloPendientes = v),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Mostrar solo pendientes',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (critCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.red),
                          ),
                          child: Text(
                            '🔴 $critCount',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      if (critCount > 0 && warnCount > 0)
                        const SizedBox(width: 8),
                      if (warnCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: Text(
                            '🟡 $warnCount',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(
                        () => _searchQuery = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      labelText: 'Buscar EPP (nombre o código)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: (_searchQuery.isEmpty)
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 10),

                      ],  // end Column children
                    ),  // end Column
                  ),  // end SliverToBoxAdapter

                  // EPP list as sliver — scrollea junto con el contenido superior
                  Builder(
                    builder: (context) {
                        final pendientes = _pendientesEppIds();
                        final criticos = _criticosEppIds();

                        final List<Map<String, dynamic>> lista =
                            soloPendientes
                                ? epps
                                    .where((x) => pendientes.contains(
                                        x['epp_id'].toString()))
                                    .map((x) =>
                                        Map<String, dynamic>.from(x))
                                    .toList()
                                : epps
                                    .map((x) =>
                                        Map<String, dynamic>.from(x))
                                    .toList();

                        if (soloPendientes) {
                          lista.sort((a, b) {
                            final aId = a['epp_id'].toString();
                            final bId = b['epp_id'].toString();
                            final aCrit = criticos.contains(aId) ? 0 : 1;
                            final bCrit = criticos.contains(bId) ? 0 : 1;
                            if (aCrit != bCrit) return aCrit.compareTo(bCrit);
                            final aNom =
                                (a['nombre'] ?? '').toString().toLowerCase();
                            final bNom =
                                (b['nombre'] ?? '').toString().toLowerCase();
                            return aNom.compareTo(bNom);
                          });
                        }

                        final q = _searchQuery.trim().toLowerCase();
                        if (q.isNotEmpty) {
                          lista.retainWhere((x) {
                            final nombre =
                                (x['nombre'] ?? '').toString().toLowerCase();
                            final codigo =
                                (x['codigo'] ?? '').toString().toLowerCase();
                            return nombre.contains(q) || codigo.contains(q);
                          });
                        }

                        if (lista.isEmpty) {
                          final msg = soloPendientes
                              ? (q.isEmpty
                                  ? 'No hay EPP pendientes según reglas actuales.'
                                  : 'Sin resultados en pendientes para tu búsqueda.')
                              : (q.isEmpty
                                  ? 'No hay EPP en el catálogo.'
                                  : 'Sin resultados para tu búsqueda.');
                          return SliverToBoxAdapter(child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(child: Text(msg)),
                          ));
                        }

                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _eppRow(lista[index]),
                            childCount: lista.length,
                          ),
                        );
                      },
                  ),  // end Builder sliver
                ],  // end slivers
              ),  // end CustomScrollView
      ),
      // ✅ Botón guardar fijo en la parte inferior, respeta barra del sistema
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (estadoActual == 'BLOQUEO' || evaluando)
                  ? null
                  : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: estadoActual == 'BLOQUEO'
                    ? Colors.grey
                    : modoOffline
                        ? Colors.orange
                        : null,
              ),
              child: Text(
                estadoActual == 'BLOQUEO'
                    ? 'Bloqueado'
                    : evaluando
                        ? 'Evaluando...'
                        : modoOffline
                            ? 'Guardar (OFFLINE)'
                            : 'Guardar entrega',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}