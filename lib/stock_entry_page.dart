import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StockEntryPage extends StatefulWidget {
  final String? initialBodegaId;

  const StockEntryPage({super.key, this.initialBodegaId});

  @override
  State<StockEntryPage> createState() => _StockEntryPageState();
}

class _StockEntryPageState extends State<StockEntryPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  List<dynamic> bodegas = [];
  List<dynamic> epps = [];

  String? bodegaId;
  final Map<String, int> cantidades = {};

  final referenciaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInit();
  }

  @override
  void dispose() {
    referenciaCtrl.dispose();
    super.dispose();
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

      final c = await supabase
          .from('catalogo_epp')
          .select()
          .eq('activo', true)
          .order('nombre')
          .timeout(const Duration(seconds: 12));

      setState(() {
        bodegas = b;
        epps = c;

        final ids =
            bodegas.map((x) => x['bodega_id'] as String).toList();
        if (widget.initialBodegaId != null &&
            ids.contains(widget.initialBodegaId)) {
          bodegaId = widget.initialBodegaId;
        } else if (bodegas.isNotEmpty) {
          bodegaId = bodegas.first['bodega_id'];
        }
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _guardarEntrada() async {
    if (bodegaId == null) {
      setState(() => error = 'Selecciona una bodega.');
      return;
    }

    final items = cantidades.entries
        .where((e) => e.value > 0)
        .map((e) => {'epp_id': e.key, 'cantidad': e.value})
        .toList();

    if (items.isEmpty) {
      setState(() => error = 'Ingresa al menos una cantidad.');
      return;
    }

    setState(() {
      error = null;
      loading = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      final ref = referenciaCtrl.text.trim().isEmpty
          ? null
          : referenciaCtrl.text.trim();

      for (final it in items) {
        await supabase.from('stock_movimientos').insert({
          'bodega_id': bodegaId,
          'epp_id': it['epp_id'],
          'tipo': 'ENTRADA',
          'cantidad': it['cantidad'],
          'referencia_event_id': ref,
          'motivo': 'Ingreso de stock',
          'created_by': userId,
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock ingresado correctamente')),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ingreso de Stock')),
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
                    onChanged: (v) => setState(() => bodegaId = v),
                    decoration: const InputDecoration(
                      labelText: 'Bodega',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: referenciaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Referencia (OC / Factura / Guía)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Cantidades a ingresar:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: epps.length,
                      itemBuilder: (context, index) {
                        final e = epps[index];
                        final id = e['epp_id'] as String;
                        final nombre =
                            (e['nombre'] ?? '').toString();
                        final codigo =
                            (e['codigo'] ?? '').toString();

                        return ListTile(
                          title: Text(nombre),
                          subtitle: codigo.isNotEmpty
                              ? Text(codigo,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black45))
                              : null,
                          trailing: SizedBox(
                            width: 80,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '0',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                final n = int.tryParse(v) ?? 0;
                                cantidades[id] = n;
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _guardarEntrada,
                      child: const Text('Registrar entrada'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}