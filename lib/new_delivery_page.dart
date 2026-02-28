import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
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


    final _entregaService = EntregaService();

    EvaluacionEntrega? evaluacionActual;
    String estadoActual = 'OK'; // OK | WARNING | BLOQUEO
    bool evaluando = false;

  
    final supabase = Supabase.instance.client;

    bool loading = true;
    String? error;

    List<dynamic> bodegas = [];
    String? bodegaId;

    List<dynamic> epps = [];

    // epp_id -> cantidad
    final Map<String, int> carrito = {};

    // Evidencia (Web: archivo imagen)
    Uint8List? evidenciaBytes;
    String? evidenciaNombre;

    final TextEditingController _searchCtrl = TextEditingController();
    String _searchQuery = '';


    @override
        void initState() {
        super.initState();

        // ✅ Cargar datos base (bodegas + catálogo EPP)
        _loadInit();

        // ✅ Semáforo proactivo (no bloquea; items inicialmente vacío)
        WidgetsBinding.instance.addPostFrameCallback((_) {
            _recalcularSemaforo();
        });
        }

    int _countCriticos() {
        final d = evaluacionActual?.detalle;
        final crit = d?['pendientes_criticos'];
        return (crit is List) ? crit.length : 0;
        }

        int _countNoCriticos() {
        final d = evaluacionActual?.detalle;
        final noCrit = d?['pendientes_no_criticos'];
        return (noCrit is List) ? noCrit.length : 0;
        }

        String? _severidadPendientePorEppId(String eppId) {
            final d = evaluacionActual?.detalle;
            if (d == null) return null;

            final crit = d['pendientes_criticos'];
            if (crit is List) {
                for (final it in crit) {
                if (it is Map && it['epp_id']?.toString() == eppId) {
                    return 'CRITICO';
                }
                }
            }

            final noCrit = d['pendientes_no_criticos'];
            if (noCrit is List) {
                for (final it in noCrit) {
                if (it is Map && it['epp_id']?.toString() == eppId) {
                    return 'ADVERTENCIA';
                }
                }
            }

            return null;
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



        Set<String> _criticosEppIds() {
        final d = evaluacionActual?.detalle;
        final out = <String>{};

        final crit = d?['pendientes_criticos'];
        if (crit is List) {
            for (final it in crit) {
            if (it is Map && it['epp_id'] != null) {
                out.add(it['epp_id'].toString());
            }
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
            if (it is Map && it['epp_id'] != null) {
                out.add(it['epp_id'].toString());
            }
            }
        }

        final noCrit = d['pendientes_no_criticos'];
        if (noCrit is List) {
            for (final it in noCrit) {
            if (it is Map && it['epp_id'] != null) {
                out.add(it['epp_id'].toString());
            }
            }
        }

        return out;
        }



Future<void> _loadInit() async {
  setState(() {
    loading = true;
    error = null;
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

    // ✅ si estás usando cache_service, guarda acá (opcional)
    // await CacheService.setJson('bodegas', b, obraId: widget.obraId);
    // await CacheService.setJson('catalogo_epp', c, obraId: widget.obraId);

    if (!mounted) return;
    setState(() {
      bodegas = b;
      epps = c;
      if (bodegas.isNotEmpty) bodegaId = bodegas.first['bodega_id'];
    });

    debugPrint('[_loadInit] FIN OK');
  } catch (e) {
    debugPrint('[_loadInit] ERROR: $e');

    // ✅ si implementaste cache offline, aquí va el fallback
    // final bCached = CacheService.getJson('bodegas', obraId: widget.obraId);
    // final cCached = CacheService.getJson('catalogo_epp', obraId: widget.obraId);
    // if (bCached is List && cCached is List) { ... } else { setState(() => error = ...); }

    if (!mounted) return;
    setState(() => error = e.toString());
  } finally {
    if (!mounted) return;
    setState(() => loading = false);
    debugPrint('[_loadInit] loading=false');
  }
}


  String _genEventId() {
    final now = DateTime.now();
    final rnd = Random().nextInt(9000) + 1000;
    return 'EPP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}-${rnd}';
  }

  Future<void> _pickEvidence() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      setState(() {
        evidenciaBytes = result.files.single.bytes!;
        evidenciaNombre = result.files.single.name;
      });
    }
  }

  // -----------------------------
  // PASO C - Pre-check (Paso 1)
  // -----------------------------
  Future<Map<String, dynamic>> _evaluarEntregaV2(List<Map<String, dynamic>> items) async {
    final resp = await supabase.rpc('evaluar_entrega_v2', params: {
      'p_obra_id': widget.obraId,
      'p_trabajador_id': widget.trabajadorId,
      'p_items': items, // Supabase Flutter serializa a json
    });

    // Dependiendo del SDK, puede venir como Map o como List con 1 elemento.
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

  Future<void> _recalcularSemaforo() async {
  print('➡️ recalcularSemaforo() INICIO');// prints para ver herrores
  
  final items = carrito.entries
      .where((e) => e.value > 0)
      .map((e) => {'epp_id': e.key, 'cantidad': e.value})
      .toList()
      .cast<Map<String, dynamic>>();

    print('Items enviados a RPC: $items');// prints para ver herrores

  // ✅ Si no hay items, igual evaluamos (estado inicial proactivo)
        try {
        setState(() => evaluando = true);

        final evaluacion = await _evaluarEntregaV2(items); // items puede ser []
        final accion = (evaluacion['accion'] ?? 'OK').toString();

        setState(() {
            estadoActual = accion;
            evaluacionActual = EvaluacionEntrega(
            estado: accion,
            detalle: evaluacion,
            );
        });
        } catch (_) {
        // fallback seguro si RPC no acepta []
        setState(() => estadoActual = 'OK');
        } finally {
        setState(() => evaluando = false);
        }
  }
  String _declaracionAutomatica() {
    // Texto “tipo” del documento (MVP) – puedes afinarlo luego
    return 'Declaro haber recibido en forma gratuita los EPP indicados para la obra "${widget.obraNombre}". '
        'Además, declaro haber sido informado e instruido sobre su uso correcto, cuidado y obligación de utilizarlos '
        'según el procedimiento de seguridad vigente en la faena.';
  }

  List<Widget> _renderPendientes(List<dynamic> pendientes) {
    if (pendientes.isEmpty) {
      return [const Text('Sin pendientes.')];
    }
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
            Expanded(
              child: Text('$codigo - $nombre ($estado)$extra'),
            ),
          ],
        ),
      );
    }).toList();
  }

  Future<bool> _dialogBloqueo(List<dynamic> criticos) async {
    // Bloqueo: solo botón Volver
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

    Future<void> _encolarEntregaOffline(List<Map<String, dynamic>> items) async {
        if (bodegaId == null) throw Exception('Selecciona una bodega.');
        if (evidenciaBytes == null) throw Exception('No hay evidencia para offline');

        // 1) Guardar evidencia en el dispositivo (archivo local)
        // (Vamos a implementar saveEvidenceOffline en evidence_service.dart)
        final localPath = await EvidenceService.saveEvidenceOffline(
            bytes: evidenciaBytes!,
            filenameHint: evidenciaNombre ?? 'evidencia.jpg',
        );

        // 2) Hash evidencia (ya lo vienes usando en online)
        final evidenciaHash = EvidenceService.hashBytes(evidenciaBytes!);

        // 3) Crear ID local para idempotencia (en tu cola)
        final localEventId = OfflineQueueService.newLocalEventId();

        // 4) Crear registro de outbox
        final e = OfflineEntrega(
            localEventId: localEventId,
            createdAtClientIso: DateTime.now().toIso8601String(),
            scope: 'obra', // MVP: cadena por obra
            obraId: widget.obraId,
            trabajadorId: widget.trabajadorId,
            bodegaId: bodegaId!, // ya validado arriba
            items: items,
            evidenciaLocalPath: localPath,
            evidenciaHash: evidenciaHash,
        );

        // 5) Encolar
        await OfflineQueueService.enqueue(e);
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

    // Evidencia obligatoria para reemplazar papel (según tu decisión MVP)
    if (evidenciaBytes == null) {
      setState(() => error = 'Debes agregar evidencia (imagen) antes de guardar.');
      return;
    }

    setState(() {
      error = null;
      loading = true;
    });

    try {
      // -----------------------------
      // PASO C (Paso 1): Pre-check
      // -----------------------------
      final evaluacion = await _evaluarEntregaV2(items);
      final accion = (evaluacion['accion'] ?? 'OK').toString();

      final pendientesCrit = (evaluacion['pendientes_criticos'] as List?) ?? const [];
      final pendientesWarn = (evaluacion['pendientes_no_criticos'] as List?) ?? const [];

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

      // -----------------------------
      // Documento (pág. 66+):
      // Declaración automática + validación simple (click)
      // -----------------------------
      final declaracion = _declaracionAutomatica();
      final acepta = await _dialogDeclaracion(declaracion);
      if (!acepta) {
        setState(() => loading = false);
        return;
      }

      // Desde aquí: flujo actual (evidencia -> insert -> stock)
      final eventId = _genEventId();
      final userId = supabase.auth.currentUser?.id;

      // 1) Subir evidencia a Storage + hash
      final evidenciaHash = EvidenceService.hashBytes(evidenciaBytes!);
      final path = 'epp/$eventId.jpg';

      await supabase.storage.from('evidencias').uploadBinary(
            path,
            evidenciaBytes!,
            fileOptions: const FileOptions(upsert: false),
          );

      final evidenciaUrl = supabase.storage.from('evidencias').getPublicUrl(path);

      // 2) Guardar entrega
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

        // Opcional (requiere columnas en DB):
        'evaluacion': evaluacion,
        'declaracion_text': declaracion,
        'validacion_tipo': 'CLICK',
      };

      await supabase.from('entregas_epp').insert(payloadEntrega);

      // 3) Descontar stock (SALIDA) por cada item
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Entrega registrada: $eventId')),
      );

      Navigator.of(context).pop(true);

    } catch (e) {
        // ✅ Fallback offline: encolar si falla online
        try {
            await _encolarEntregaOffline(items); // nueva función
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin conexión: entrega guardada OFFLINE (pendiente de sincronización).')),
            );

            Navigator.of(context).pop(true);
            return;
        } catch (e2) {
            // si incluso el offline falla, mostramos error original
            setState(() => error = 'Online falló: $e\nOffline falló: $e2');
        }
        } finally {
        setState(() => loading = false);
        }


  }

// Paso 3
  Color _colorEstado(String estado) {
  switch (estado) {
    case 'OK':
      return Colors.green;

    case 'WARNING':
      return Colors.orange;

    case 'BLOQUEO':
      return Colors.red;

    if (estado == 'OFFLINE') return Colors.grey;
    
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

    if (estado == 'OFFLINE') return Icons.cloud_off;

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
        return 'OFFLINE';

    default:
        return 'Sin evaluación';
  }
}

String? _mensajePrincipalEvaluacion() {
  final d = evaluacionActual?.detalle;
  if (d == null) return null;

  // Prioridad: errors (BLOQUEO) -> warnings (WARNING)
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

  // Mensaje opcional desde la evaluación (si existe)
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
              if (msg != null && msg.trim().isNotEmpty)
                Text(
                  msg,
                  style: const TextStyle(fontSize: 13),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

// paso 4
List<Map<String, dynamic>> _extraerChecklistDesdeEvaluacion() {
  final d = evaluacionActual?.detalle;
  if (d == null) return [];

  final List<Map<String, dynamic>> out = [];

  // 🔴 Críticos (BLOQUEO)
  final criticos = d['pendientes_criticos'];
  if (criticos is List) {
    for (final it in criticos) {
      if (it is Map) {
        out.add({
          'severidad': 'CRITICO',
          'nombre': (it['nombre'] ?? it['codigo'] ?? 'EPP').toString(),
          'estado': (it['estado'] ?? 'PENDIENTE').toString(),
          'codigo': it['codigo']?.toString(),
          'vence_el': it['vence_el'],
          'dias_restantes': it['dias_restantes'],
        });
      }
    }
  }

  // 🟡 No críticos (WARNING)
  final noCriticos = d['pendientes_no_criticos'];
  if (noCriticos is List) {
    for (final it in noCriticos) {
      if (it is Map) {
        out.add({
          'severidad': 'NO_CRITICO',
          'nombre': (it['nombre'] ?? it['codigo'] ?? 'EPP').toString(),
          'estado': (it['estado'] ?? 'PENDIENTE').toString(),
          'codigo': it['codigo']?.toString(),
          'vence_el': it['vence_el'],
          'dias_restantes': it['dias_restantes'],
        });
      }
    }
  }

  return out;
}


IconData _iconChecklistEstado(String estado) {
  final s = estado.toUpperCase();
  if (s.contains('OK') || s.contains('CUMPLE')) return Icons.check_circle;
  if (s.contains('VENC') || s.contains('EXP')) return Icons.timer_off;
  if (s.contains('FALT') || s.contains('PEND')) return Icons.cancel;
  if (s.contains('WARN')) return Icons.warning_amber_rounded;
  return Icons.help_outline;
}

Color _colorChecklistEstado(String estado) {
  final s = estado.toUpperCase();
  if (s.contains('OK') || s.contains('CUMPLE')) return Colors.green;
  if (s.contains('WARN')) return Colors.orange;
  if (s.contains('VENC') || s.contains('EXP')) return Colors.red;
  if (s.contains('FALT') || s.contains('PEND')) return Colors.red;
  return Colors.grey;
}

Widget _buildChecklistCard() {
  final checklist = _extraerChecklistDesdeEvaluacion();

  String? warningMsg;
  final w = evaluacionActual?.detalle['warnings'];
  if (w is List && w.isNotEmpty && w.first is Map) {
    warningMsg = (w.first['message'] ?? '').toString();
  }

  if (checklist.isEmpty) {
    // Si hay warning global pero sin pendientes listados, lo mostramos igual
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

          final esCritico = severidad == 'CRITICO';
          final color = esCritico ? Colors.red : Colors.orange;
          final icon = esCritico ? Icons.block : Icons.warning_amber_rounded;

          String extra = '';
          if (estado.toUpperCase().contains('VENCE') || estado.toUpperCase().contains('VENC')) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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


//--------------------- FIN PASO 4 --------------------------------

// ✅ Debounce: programar evaluación (UNA sola vez en el State)
void _programarEvaluacionSemaforo() {
  _evalDebounce?.cancel();
  _evalDebounce = Timer(const Duration(milliseconds: 350), () async {
    await _recalcularSemaforoSeguro();
  });
}

// ✅ Evita carreras: si ya está evaluando, deja 1 evaluación pendiente
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
                    final current = carrito[id] ?? 0;
                    final next = current - 1;
                    if (next <= 0) {
                      carrito.remove(id);
                    } else {
                      carrito[id] = next;
                    }
                  });
                  _programarEvaluacionSemaforo();
                },
              ),
              Text(
                qty.toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  setState(() {
                    carrito[id] = (carrito[id] ?? 0) + 1;
                  });
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

  @override
    void dispose() {
    _evalDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
    }

}


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
                Text('Error: $error', style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    setState(() => error = null);
                    _loadInit();
                  },
                  child: const Text('Volver'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ PASO 5: arriba de todo (solo cuando NO hay error)
                _buildSemaforoCard(),
                const SizedBox(height: 10),
                _buildChecklistCard(),
                const SizedBox(height: 14),

                Text('Obra: ${widget.obraNombre}'),
                const SizedBox(height: 4),
                Text('Trabajador: ${widget.trabajadorNombre} (${widget.trabajadorRut})'),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: bodegaId,
                  items: bodegas
                      .map<DropdownMenuItem<String>>(
                        (b) => DropdownMenuItem<String>(
                          value: b['bodega_id'] as String?,
                          child: Text((b['nombre'] ?? 'Bodega').toString()),
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

                // Evidencia
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: Text(
                      evidenciaBytes == null
                          ? 'Agregar evidencia (imagen)'
                          : 'Evidencia cargada: ${evidenciaNombre ?? "imagen"}',
                    ),
                    onPressed: _pickEvidence,
                  ),
                ),

                const SizedBox(height: 16),
                const Text(
                  'Selecciona EPP y cantidad:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                //-------------------------------------------------------
                //final critCount = _countCriticos();
                //final warnCount = _countNoCriticos();

                Row(
                children: [
                    Switch(
                    value: soloPendientes,
                    onChanged: (v) => setState(() => soloPendientes = v),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                    child: Text(
                        'Mostrar solo pendientes',
                        style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    ),

                    // 🔴 Badge críticos
                    if (critCount > 0)
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.red),
                        ),
                        child: Text(
                        '🔴 $critCount',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                    ),

                    if (critCount > 0 && warnCount > 0) const SizedBox(width: 8),

                    // 🟡 Badge warnings
                    if (warnCount > 0)
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.orange),
                        ),
                        child: Text(
                        '🟡 $warnCount',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                    ),
                ],
                ),
                const SizedBox(height: 8),
                //-------------------------------------------------------------------

                TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
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


                Expanded(
                    child: Builder(
                        builder: (context) {
                        final pendientes = _pendientesEppIds();
                        final criticos = _criticosEppIds();

                        // 1) Base: lista completa o solo pendientes
                        final List<Map<String, dynamic>> lista = (soloPendientes)
                            ? epps
                                .where((x) => pendientes.contains(x['epp_id'].toString()))
                                .map((x) => Map<String, dynamic>.from(x))
                                .toList()
                            : epps.map((x) => Map<String, dynamic>.from(x)).toList();

                        // 2) Orden (solo si está el filtro de pendientes)
                        if (soloPendientes) {
                            lista.sort((a, b) {
                            final aId = a['epp_id'].toString();
                            final bId = b['epp_id'].toString();

                            final aCrit = criticos.contains(aId) ? 0 : 1;
                            final bCrit = criticos.contains(bId) ? 0 : 1;

                            if (aCrit != bCrit) return aCrit.compareTo(bCrit);

                            final aNom = (a['nombre'] ?? '').toString().toLowerCase();
                            final bNom = (b['nombre'] ?? '').toString().toLowerCase();
                            return aNom.compareTo(bNom);
                            });
                        }

                        // 3) BUSCADOR (aplicar SIEMPRE después de construir lista)
                        final q = _searchQuery.trim().toLowerCase();
                        if (q.isNotEmpty) {
                            lista.retainWhere((x) {
                            final nombre = (x['nombre'] ?? '').toString().toLowerCase();
                            final codigo = (x['codigo'] ?? '').toString().toLowerCase(); // si no existe, queda ''
                            return nombre.contains(q) || codigo.contains(q);
                            });
                        }

                        // 4) Vacío
                        if (lista.isEmpty) {
                            final msg = soloPendientes
                                ? (q.isEmpty
                                    ? 'No hay EPP pendientes según reglas actuales.'
                                    : 'Sin resultados en pendientes para tu búsqueda.')
                                : (q.isEmpty ? 'No hay EPP en el catálogo.' : 'Sin resultados para tu búsqueda.');

                            return Center(child: Text(msg));
                        }

                        // 5) OJO: renderiza "lista", NO "epps"
                        return ListView.builder(
                            itemCount: lista.length,
                            itemBuilder: (context, index) => _eppRow(lista[index]),
                        );
                        },
                    ),
                    ),



                const SizedBox(height: 12),

                // ✅ PASO 6: botón proactivo (bloqueo real)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (estadoActual == 'BLOQUEO' || evaluando) ? null : _guardar,
                    child: Text(
                      (estadoActual == 'BLOQUEO')
                          ? 'Bloqueado'
                          : (evaluando ? 'Evaluando...' : 'Guardar entrega'),
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}
}