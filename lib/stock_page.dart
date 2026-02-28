import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'stock_entry_page.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  List<dynamic> bodegas = [];
  String? bodegaId;

  // Lista completa desde vw_stock_semaforo
  List<Map<String, dynamic>> stockItems = [];

  @override
  void initState() {
    super.initState();
    _loadInit();
  }

  Future<void> _loadInit() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final b = await supabase
          .from('bodegas')
          .select()
          .order('created_at')
          .timeout(const Duration(seconds: 12));

      setState(() {
        bodegas = b;
        if (bodegas.isNotEmpty) bodegaId = bodegas.first['bodega_id'];
      });

      await _loadStock();
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _loadStock() async {
    if (bodegaId == null) return;

    setState(() {
      loading = true;
      error = null;
      stockItems = [];
    });

    try {
      // ✅ Consulta a la vista vw_stock_semaforo filtrada por bodega
      final data = await supabase
          .from('vw_stock_semaforo')
          .select()
          .eq('bodega_id', bodegaId!)
          .order('nombre')
          .timeout(const Duration(seconds: 12));

      setState(() {
        stockItems = (data as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  String _bodegaNombre() {
    for (final b in bodegas) {
      if (b['bodega_id'] == bodegaId) return (b['nombre'] ?? '').toString();
    }
    return '';
  }

  // ─────────────────────────────────────────────
  // SEMÁFORO: color, ícono, etiqueta
  // ─────────────────────────────────────────────
  Color _colorEstado(String estado) {
    switch (estado) {
      case 'CRITICO':
        return Colors.red;
      case 'ADVERTENCIA':
        return Colors.orange;
      case 'OK':
        return Colors.green;
      default:
        return Colors.grey; // SIN_UMBRAL
    }
  }

  IconData _iconEstado(String estado) {
    switch (estado) {
      case 'CRITICO':
        return Icons.warning_rounded;
      case 'ADVERTENCIA':
        return Icons.warning_amber_rounded;
      case 'OK':
        return Icons.check_circle;
      default:
        return Icons.radio_button_unchecked; // SIN_UMBRAL
    }
  }

  // ─────────────────────────────────────────────
  // RESUMEN: contadores por estado
  // ─────────────────────────────────────────────
  Widget _buildResumenBanner() {
    final criticos = stockItems
        .where((x) => x['estado_semaforo'] == 'CRITICO')
        .length;
    final advertencias = stockItems
        .where((x) => x['estado_semaforo'] == 'ADVERTENCIA')
        .length;

    if (criticos == 0 && advertencias == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: criticos > 0
            ? Colors.red.withOpacity(0.08)
            : Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: criticos > 0 ? Colors.red : Colors.orange,
        ),
      ),
      child: Row(
        children: [
          Icon(
            criticos > 0 ? Icons.warning_rounded : Icons.warning_amber_rounded,
            color: criticos > 0 ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                if (criticos > 0)
                  '🔴 $criticos EPP${criticos != 1 ? 's' : ''} en stock crítico',
                if (advertencias > 0)
                  '🟡 $advertencias EPP${advertencias != 1 ? 's' : ''} con stock bajo',
              ].join('  ·  '),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: criticos > 0 ? Colors.red : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // MODAL: configurar umbral para un EPP
  // ─────────────────────────────────────────────
  Future<void> _showUmbralDialog(Map<String, dynamic> item) async {
    final nombre = (item['nombre'] ?? '').toString();
    final eppId = (item['epp_id'] ?? '').toString();
    final umbralCrit = (item['umbral_critico'] ?? 0) as int;
    final umbralAdv = (item['umbral_advertencia'] ?? 3) as int;

    final critCtrl =
        TextEditingController(text: umbralCrit.toString());
    final advCtrl =
        TextEditingController(text: umbralAdv.toString());

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Umbral de stock · $nombre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Define los umbrales mínimos para las alertas de stock.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: critCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '🔴 Umbral crítico (stock ≤ este valor)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: advCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '🟡 Umbral advertencia (stock ≤ este valor)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ejemplo: crítico = 2, advertencia = 5\n'
              'Si quedan 2 o menos → 🔴. Si quedan 3-5 → 🟡.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    critCtrl.dispose();
    advCtrl.dispose();

    if (guardado != true || !mounted) return;

    final crit = int.tryParse(critCtrl.text.trim()) ?? 0;
    final adv = int.tryParse(advCtrl.text.trim()) ?? 3;

    if (adv < crit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'El umbral de advertencia debe ser mayor al crítico.')),
      );
      return;
    }

    try {
      await supabase.rpc('upsert_stock_umbral', params: {
        'p_bodega_id': bodegaId,
        'p_epp_id': eppId,
        'p_umbral_critico': crit,
        'p_umbral_advertencia': adv,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Umbral guardado para $nombre')),
      );

      await _loadStock(); // refresca semáforo
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar umbral: $e')),
      );
    }
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (loading && bodegas.isEmpty) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    // Ordenar: CRITICO primero, luego ADVERTENCIA, luego OK, luego SIN_UMBRAL
    final ordenEstado = {
      'CRITICO': 0,
      'ADVERTENCIA': 1,
      'OK': 2,
      'SIN_UMBRAL': 3,
    };
    final itemsOrdenados = [...stockItems]..sort((a, b) {
        final oa =
            ordenEstado[a['estado_semaforo'] ?? 'SIN_UMBRAL'] ?? 3;
        final ob =
            ordenEstado[b['estado_semaforo'] ?? 'SIN_UMBRAL'] ?? 3;
        if (oa != ob) return oa.compareTo(ob);
        return (a['nombre'] ?? '').toString().compareTo(
              (b['nombre'] ?? '').toString(),
            );
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock por Bodega'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Ingresar stock',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      StockEntryPage(initialBodegaId: bodegaId),
                ),
              );
              _loadStock();
            },
          ),
          IconButton(
            onPressed: _loadStock,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $error',
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadInit,
                    child: const Text('Reintentar'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selector de bodega
                  DropdownButtonFormField<String>(
                    value: bodegaId,
                    items: bodegas
                        .map<DropdownMenuItem<String>>(
                          (b) => DropdownMenuItem(
                            value: b['bodega_id'],
                            child: Text(b['nombre'] ?? 'Bodega'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      setState(() => bodegaId = v);
                      await _loadStock();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Bodega',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Banner resumen de alertas
                  _buildResumenBanner(),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Saldo actual · ${_bodegaNombre()}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      // Hint configurar umbrales
                      TextButton.icon(
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Configurar umbrales',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Toca el ícono ⚙ de cada EPP para configurar su umbral.'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Loading spinner inline (no bloquea toda la pantalla)
                  if (loading)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (itemsOrdenados.isEmpty)
                    const Expanded(
                      child: Center(
                          child: Text('Sin movimientos de stock.')),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: itemsOrdenados.length,
                        itemBuilder: (context, index) {
                          final item = itemsOrdenados[index];
                          final nombre =
                              (item['nombre'] ?? '').toString();
                          final codigo =
                              (item['codigo'] ?? '').toString();
                          final saldo =
                              (item['saldo'] ?? 0) as int;
                          final estado =
                              (item['estado_semaforo'] ?? 'SIN_UMBRAL')
                                  .toString();
                          final umbralCrit =
                              item['umbral_critico'] as int?;
                          final umbralAdv =
                              item['umbral_advertencia'] as int?;

                          final color = _colorEstado(estado);
                          final icon = _iconEstado(estado);

                          return Card(
                            // Borde de color según estado
                            shape: estado != 'SIN_UMBRAL' &&
                                    estado != 'OK'
                                ? RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    side: BorderSide(
                                        color: color, width: 1.5),
                                  )
                                : null,
                            child: ListTile(
                              // ✅ Semáforo a la izquierda
                              leading: Icon(icon, color: color, size: 28),

                              title: Text(
                                nombre,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  if (codigo.isNotEmpty)
                                    Text(codigo,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black45)),
                                  if (umbralCrit != null)
                                    Text(
                                      'Umbrales: 🔴 ≤$umbralCrit  🟡 ≤$umbralAdv',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black45),
                                    )
                                  else
                                    const Text(
                                      'Sin umbral configurado',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.black38),
                                    ),
                                ],
                              ),
                              isThreeLine: true,

                              // ✅ Saldo destacado + botón configurar
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Saldo con color según estado
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.12),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(color: color),
                                    ),
                                    child: Text(
                                      '$saldo',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Botón configurar umbral
                                  IconButton(
                                    icon: const Icon(Icons.tune,
                                        size: 20),
                                    tooltip: 'Configurar umbral',
                                    onPressed: () =>
                                        _showUmbralDialog(item),
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