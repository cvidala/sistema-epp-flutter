import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'worker_detail_page.dart';
import 'services/connectivity_service.dart'; // ✅ NUEVO
import 'services/device_id_service.dart';    // ✅ NUEVO
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
  bool syncing = false;
  String? error;

  List<dynamic> trabajadores = [];
  List<dynamic> filtrados = [];

  @override
  void initState() {
    super.initState();
    _loadWorkers();
    searchCtrl.addListener(_applyFilter);

    // ✅ Iniciar monitoreo de conectividad con sync automático
    ConnectivityService.instance.start(
      intervalSeconds: 10,
      onSyncComplete: () {
        if (mounted) {
          _loadWorkers();
          setState(() {}); // refresca badge pendientes
        }
      },
      onStatusChange: () {
        if (mounted) setState(() {}); // refresca banner offline/online
      },
    );
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    // ✅ Detener monitoreo al salir
    ConnectivityService.instance.stop();
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

      await CacheService.setJson('trabajadores_activos', data,
          obraId: widget.obraId);

      setState(() {
        trabajadores = data;
        filtrados = data;
      });
    } catch (e) {
      final cached = CacheService.getJson('trabajadores_activos',
          obraId: widget.obraId);

      if (cached is List) {
        final data = cached.map((x) => x as Map).toList();
        setState(() {
          trabajadores = data;
          filtrados = data;
          offlineMode = true;
          error = null;
        });
      } else {
        setState(() => error =
            'Sin conexión y sin cache local de trabajadores.\n'
            'Abre esta pantalla una vez con internet para cachear.');
      }
    } finally {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  // ✅ Sync manual — delega a ConnectivityService (mismo SyncService + DeviceIdService real)
  Future<void> _syncManual() async {
    if (syncing) return;
    setState(() => syncing = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sincronizando entregas offline...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final resultado = await ConnectivityService.instance.syncManual();

      if (!mounted) return;

      final enviadas = resultado['enviadas'] ?? 0;
      final errores = resultado['errores'] ?? 0;
      final pendientes = resultado['pendientes'] ?? 0;

      String msg;
      if (enviadas == 0 && errores == 0) {
        msg = 'Sin entregas pendientes de sincronización.';
      } else {
        msg = 'Sync terminado — '
            '✅ $enviadas enviada${enviadas != 1 ? 's' : ''}'
            '${errores > 0 ? ' · ❌ $errores error${errores != 1 ? 'es' : ''}' : ''}'
            '${pendientes > 0 ? ' · ⏳ $pendientes pendiente${pendientes != 1 ? 's' : ''}' : ''}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al sincronizar: $e')),
      );
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final pendientesCount = OfflineQueueService.listPending()
        .where((e) => e.status != 'SENT')
        .length;

    // Estado de conectividad real desde ConnectivityService
    final isOnline = ConnectivityService.instance.isOnline;

    return Scaffold(
      appBar: AppBar(
        title: Text('Trabajadores · ${widget.obraNombre}'),
        actions: [
          IconButton(
            onPressed: loading ? null : _loadWorkers,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
          ),

          // ✅ Botón sync con badge de pendientes y spinner durante sync
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: syncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync),
                onPressed: syncing ? null : _syncManual,
                tooltip: 'Sincronizar entregas offline',
              ),
              if (pendientesCount > 0 && !syncing)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$pendientesCount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // ✅ Indicador visual online/offline en AppBar
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: isOnline ? Colors.greenAccent : Colors.grey,
              size: 20,
            ),
          ),
        ],
      ),

      body: error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadWorkers,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Banner offline
                if (offlineMode || !isOnline)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    color: Colors.grey.shade200,
                    child: const Row(
                      children: [
                        Icon(Icons.cloud_off,
                            size: 16, color: Colors.grey),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Modo OFFLINE: mostrando trabajadores desde caché local.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Banner pendientes con mensaje contextual
                if (pendientesCount > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    color: Colors.orange.shade50,
                    child: Row(
                      children: [
                        const Icon(Icons.sync,
                            size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$pendientesCount entrega${pendientesCount != 1 ? 's' : ''} '
                            'pendiente${pendientesCount != 1 ? 's' : ''} de sincronización. '
                            '${isOnline ? 'Sincronizando automáticamente...' : 'Se enviará al recuperar conexión.'}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                // DeviceId (útil para soporte en terreno; quitar en prod si no se necesita)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_android,
                          size: 13, color: Colors.black38),
                      const SizedBox(width: 4),
                      Text(
                        'Device: ${DeviceIdService.deviceId.substring(0, 8)}...',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black38),
                      ),
                    ],
                  ),
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
                  child: filtrados.isEmpty
                      ? Center(
                          child: Text(offlineMode
                              ? 'Sin trabajadores en caché.'
                              : 'Sin trabajadores activos.'),
                        )
                      : ListView.builder(
                          itemCount: filtrados.length,
                          itemBuilder: (context, index) {
                            final t = filtrados[index];
                            return ListTile(
                              title: Text(t['nombre'] ?? 'Sin nombre'),
                              subtitle: Text(t['rut'] ?? ''),
                              trailing:
                                  const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => WorkerDetailPage(
                                      obraId: widget.obraId,
                                      obraNombre: widget.obraNombre,
                                      trabajadorId:
                                          t['trabajador_id'],
                                      trabajadorNombre:
                                          t['nombre'] ?? '',
                                      trabajadorRut: t['rut'] ?? '',
                                    ),
                                  ),
                                );
                                if (mounted) setState(() {});
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