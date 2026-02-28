import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'new_delivery_page.dart';
import 'worker_detail_page.dart';
import 'services/sync_service.dart';
import 'services/offline_queue_service.dart';
import 'services/cache_service.dart';


class WorkersPage extends StatefulWidget {
  final String obraId;
  final String obraNombre;

  const WorkersPage({
    super.key,
    required this.obraId,
    required this.obraNombre,
  });

  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  final supabase = Supabase.instance.client;
  final searchCtrl = TextEditingController();

  bool loading = true;
  bool offlineMode = false;
  String? error;
  List<dynamic> trabajadores = [];
  List<dynamic> filtrados = [];

  @override
  void initState() {
    super.initState();
    _loadWorkers();
    searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => filtrados = trabajadores);
      return;
    }
    setState(() {
      filtrados = trabajadores.where((t) {
        final nombre = (t['nombre'] ?? '').toString().toLowerCase();
        final rut = (t['rut'] ?? '').toString().toLowerCase();
        return nombre.contains(q) || rut.contains(q);
      }).toList();
    });
  }

  Future<void> _loadWorkers() async {
    setState(() {
      loading = true;
      error = null;
      offlineMode = false;
    });

    try {
      final data = await supabase
          .from('trabajadores')
          .select()
          .eq('estado', 'ACTIVO')
          .order('nombre')
          .timeout(const Duration(seconds: 12));

      // ✅ cachear para modo offline
      await CacheService.setJson('trabajadores_activos', data, obraId: widget.obraId);

      setState(() {
        trabajadores = data;
        filtrados = data;
      });
    } catch (e) {
      // ✅ fallback offline: leer cache
      final cached = CacheService.getJson('trabajadores_activos', obraId: widget.obraId);

      if (cached is List) {
        final data = cached.map((x) => x as Map).toList();

        setState(() {
          trabajadores = data;
          filtrados = data;
          offlineMode = true;
          error = null; // importante: no pintar rojo si hay cache
        });
      } else {
        setState(() => error =
            'Sin conexión y sin cache local de trabajadores.\nAbre esta pantalla una vez con internet para cachear.');
      }
    } finally {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Trabajadores · ${widget.obraNombre}'),
        actions: [
          IconButton(onPressed: _loadWorkers, icon: const Icon(Icons.refresh)),

          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              final client = Supabase.instance.client;

              // MVP deviceId: si no tienes uno persistente, partimos con userId o 'dev'
              final deviceId = client.auth.currentUser?.id ?? 'device-mvp';

              final sync = SyncService(supabase: client, deviceId: deviceId);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sincronizando entregas offline...')),
              );

              await sync.syncOnce();

              final pendientes = OfflineQueueService.listPending().where((e) => e.status != 'SENT').length;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sync terminado. Pendientes: $pendientes')),
              );
            },
          ),
        ],
      ),

      body: error != null
          ? Center(child: Text('Error: $error'))
          : Column(
              children: [
                if (offlineMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: Colors.grey.shade200,
                    child: const Text('Modo OFFLINE: mostrando trabajadores desde cache local.'),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar por nombre o RUT',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtrados.length,
                    itemBuilder: (context, index) {
                      final t = filtrados[index];
                      return ListTile(
                        title: Text(t['nombre'] ?? 'Sin nombre'),
                        subtitle: Text(t['rut'] ?? ''),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                            Navigator.of(context).push(
                                MaterialPageRoute(
                                builder: (_) => WorkerDetailPage(
                                    obraId: widget.obraId,
                                    obraNombre: widget.obraNombre,
                                    trabajadorId: t['trabajador_id'],
                                    trabajadorNombre: t['nombre'] ?? '',
                                    trabajadorRut: t['rut'] ?? '',
                                ),
                                ),
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
