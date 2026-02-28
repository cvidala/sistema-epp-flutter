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

  // catálogo: epp_id -> nombre
  Map<String, String> eppIdToNombre = {};

  // stock: epp_id -> saldo
  Map<String, int> stock = {};

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
      final b = await supabase.from('bodegas').select().order('created_at');
      final c = await supabase
          .from('catalogo_epp')
          .select('epp_id,nombre')
          .eq('activo', true)
          .order('nombre');

      eppIdToNombre = {
        for (final e in c) (e['epp_id'] as String): (e['nombre'] as String)
      };

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
      stock = {};
    });

    try {
      final movs = await supabase
          .from('stock_movimientos')
          .select('epp_id,tipo,cantidad')
          .eq('bodega_id', bodegaId!)
          .order('created_at');

      final Map<String, int> tmp = {};
      for (final m in movs) {
        final eppId = (m['epp_id'] ?? '').toString();
        final tipo = (m['tipo'] ?? '').toString();
        final cant = (m['cantidad'] ?? 0) as int;

        final delta = (tipo == 'ENTRADA')
            ? cant
            : (tipo == 'SALIDA')
                ? -cant
                : cant; // AJUSTE: por ahora lo tratamos como +cant

        tmp[eppId] = (tmp[eppId] ?? 0) + delta;
      }

      setState(() => stock = tmp);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  String _bodegaNombre() {
    if (bodegaId == null) return '';
    for (final b in bodegas) {
      if (b['bodega_id'] == bodegaId) {
        return (b['nombre'] ?? '').toString();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (loading && bodegas.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
                  builder: (_) => StockEntryPage(initialBodegaId: bodegaId),
                ),
              );
              _loadStock(); // recarga al volver
            },
          ),
          IconButton(onPressed: _loadStock, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: error != null
            ? Text('Error: $error')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: bodegaId,
                    items: bodegas
                        .map<DropdownMenuItem<String>>((b) => DropdownMenuItem(
                              value: b['bodega_id'],
                              child: Text(b['nombre'] ?? 'Bodega'),
                            ))
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
                  Text(
                    'Saldo actual · ${_bodegaNombre()}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: eppIdToNombre.length,
                      itemBuilder: (context, index) {
                        final eppId = eppIdToNombre.keys.elementAt(index);
                        final nombre = eppIdToNombre[eppId] ?? eppId;
                        final saldo = stock[eppId] ?? 0;

                        return ListTile(
                          title: Text(nombre),
                          trailing: Text(
                            saldo.toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: saldo < 0 ? Colors.red : null,
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
