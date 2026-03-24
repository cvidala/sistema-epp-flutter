import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SolicitudEppPage extends StatefulWidget {
  final String obraId;
  final String obraNombre;
  final String trabajadorId;
  final String trabajadorNombre;
  final String trabajadorRut;
  /// Nombre del supervisor que registra la solicitud
  final String supervisorNombre;

  const SolicitudEppPage({
    super.key,
    required this.obraId,
    required this.obraNombre,
    required this.trabajadorId,
    required this.trabajadorNombre,
    required this.trabajadorRut,
    required this.supervisorNombre,
  });

  @override
  State<SolicitudEppPage> createState() => _SolicitudEppPageState();
}

class _SolicitudEppPageState extends State<SolicitudEppPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Catálogo EPP disponible
  List<Map<String, dynamic>> _catalogo = [];

  // Items seleccionados: epp_id → cantidad
  final Map<String, int> _seleccionados = {};

  final TextEditingController _obsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCatalogo();
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogo() async {
    try {
      final data = await supabase
          .from('catalogo_epp')
          .select('epp_id, nombre')
          .eq('activo', true)
          .order('nombre')
          .timeout(const Duration(seconds: 12));
      setState(() {
        _catalogo = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar catálogo: $e';
        _loading = false;
      });
    }
  }

  void _setCantidad(String eppId, int delta) {
    setState(() {
      final current = _seleccionados[eppId] ?? 0;
      final next = current + delta;
      if (next <= 0) {
        _seleccionados.remove(eppId);
      } else {
        _seleccionados[eppId] = next;
      }
    });
  }

  Future<void> _guardar() async {
    if (_seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un ítem EPP')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final items = _seleccionados.entries.map((e) {
        final nombre = _catalogo
            .firstWhere((c) => c['epp_id'] == e.key,
                orElse: () => {'nombre': ''})['nombre'];
        return {
          'epp_id': e.key,
          'nombre': nombre,
          'cantidad': e.value,
        };
      }).toList();

      await supabase.from('solicitudes_epp').insert({
        'obra_id': widget.obraId,
        'trabajador_id': widget.trabajadorId,
        'trabajador_rut': widget.trabajadorRut,
        'trabajador_nombre': widget.trabajadorNombre,
        'supervisor_nombre': widget.supervisorNombre,
        'items': items,
        'observacion':
            _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
        'estado': 'pendiente',
      }).timeout(const Duration(seconds: 15));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Solicitud enviada a bodega'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _error = 'Error al guardar: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitud EPP a bodega'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Encabezado con datos del trabajador
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  color: Colors.blue.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.trabajadorNombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'RUT: ${widget.trabajadorRut}  •  ${widget.obraNombre}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                // Lista de catálogo
                Expanded(
                  child: _catalogo.isEmpty
                      ? const Center(
                          child: Text('No hay ítems EPP en el catálogo'))
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: _catalogo.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final item = _catalogo[i];
                            final id = item['epp_id'] as String;
                            final nombre = item['nombre'] as String;
                            final cantidad = _seleccionados[id] ?? 0;
                            return ListTile(
                              title: Text(nombre),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    color: Colors.red.shade400,
                                    onPressed: cantidad > 0
                                        ? () => _setCantidad(id, -1)
                                        : null,
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      cantidad.toString(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: cantidad > 0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: cantidad > 0
                                            ? Colors.blue.shade700
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    color: Colors.blue.shade600,
                                    onPressed: () => _setCantidad(id, 1),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Observación + botón guardar
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 6,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _obsCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Observación (opcional)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Resumen items seleccionados
                      if (_seleccionados.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${_seleccionados.length} tipo(s) • '
                            '${_seleccionados.values.fold(0, (a, b) => a + b)} unidad(es)',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _guardar,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        label: Text(_saving ? 'Enviando...' : 'Enviar solicitud'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
