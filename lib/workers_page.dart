import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'worker_detail_page.dart';
import 'services/connectivity_service.dart';
import 'services/offline_queue_service.dart';
import 'services/cache_service.dart';
import 'services/auth_service.dart';
import 'package:uuid/uuid.dart';

class WorkersPage extends StatefulWidget {
  final String obraId;
  final String obraNombre;
  /// Perfil del usuario autenticado, pasado desde ObrasPage.
  final PerfilUsuario? perfil;

  const WorkersPage({
    super.key,
    required this.obraId,
    required this.obraNombre,
    this.perfil,
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

  // Verifica si el usuario puede escribir en esta obra específica
  // (Se resuelve al cargar la página para supervisores)
  bool _canWriteThisObra = false;

  PerfilUsuario? get perfil => widget.perfil ?? AuthService.instance.perfil;

  @override
  void initState() {
    super.initState();
    _loadWorkers();
    _resolveWritePermission();
    searchCtrl.addListener(_applyFilter);

    ConnectivityService.instance.start(
      intervalSeconds: 10,
      onSyncComplete: () {
        if (mounted) _loadWorkersSilent();
      },
      onStatusChange: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    ConnectivityService.instance.stop();
    super.dispose();
  }

  /// Resuelve si puede escribir en esta obra.
  /// ADMIN: siempre sí.
  /// SUPERVISOR: consulta obra_usuarios.
  /// READONLY: siempre no.
  Future<void> _resolveWritePermission() async {
    final p = perfil;
    if (p == null) { setState(() => _canWriteThisObra = false); return; }
    if (p.isAdmin) { setState(() => _canWriteThisObra = true); return; }
    if (p.isReadonly) { setState(() => _canWriteThisObra = false); return; }

    // SUPERVISOR: verificar membresía
    final canWrite = await AuthService.instance.canWriteObra(widget.obraId);
    if (mounted) setState(() => _canWriteThisObra = canWrite);
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
        final rut    = (t['rut'] ?? '').toString().toLowerCase();
        return nombre.contains(q) || rut.contains(q);
      }).toList();
    });
  }

  /// Recarga sin mostrar spinner — para actualizaciones automáticas en background
  Future<void> _loadWorkersSilent() async {
    try {
      final raw = await supabase
          .from('trabajador_obras')
          .select('trabajadores(*)')
          .eq('obra_id', widget.obraId)
          .order('created_at', ascending: true);

      final data = (raw as List)
          .map((e) => e['trabajadores'] as Map<String, dynamic>)
          .where((t) => t['activo'] == true)
          .toList();

      if (mounted) {
        setState(() {
          trabajadores = data;
          _applyFilter();
        });
      }
    } catch (_) {
      // Fallo silencioso — no interrumpir al usuario
    }
  }

  Future<void> _loadWorkers() async {
    setState(() { loading = true; error = null; offlineMode = false; });

    try {
      // Consulta a través de la tabla intermedia trabajador_obras.
      // Trae los trabajadores activos asignados a ESTA obra.
      // El RLS de trabajadores filtra además por can_access_trabajador().
      final raw = await supabase
          .from('trabajador_obras')
          .select('cargo, trabajadores!inner(trabajador_id, nombre, rut, estado)')
          .eq('obra_id', widget.obraId)
          .eq('activo', true)
          .eq('trabajadores.estado', 'ACTIVO')
          .order('trabajadores(nombre)')
          .timeout(const Duration(seconds: 12));

      // Aplanar: combinar campos de trabajador con cargo específico de la obra
      final data = (raw as List).map((row) {
        final t = Map<String, dynamic>.from(row['trabajadores'] as Map);
        if (row['cargo'] != null) t['cargo'] = row['cargo'];
        return t;
      }).toList();

      await CacheService.setJson('trabajadores_activos', data,
          obraId: widget.obraId);

      setState(() { trabajadores = data; filtrados = data; });
    } catch (e) {
      final cached = CacheService.getJson('trabajadores_activos',
          obraId: widget.obraId);

      if (cached is List) {
        final data = cached.map((x) => x as Map).toList();
        setState(() {
          trabajadores = data;
          filtrados    = data;
          offlineMode  = true;
        });
      } else {
        setState(() => error =
            'Sin conexión y sin caché local de trabajadores.\n'
            'Abre esta pantalla una vez con internet para cachear.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

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

      final enviadas   = resultado['enviadas']   ?? 0;
      final errores    = resultado['errores']     ?? 0;
      final pendientes = resultado['pendientes']  ?? 0;

      final msg = (enviadas == 0 && errores == 0)
          ? 'Sin entregas pendientes de sincronización.'
          : 'Sync terminado — '
            '✅ $enviadas enviada${enviadas != 1 ? 's' : ''}'
            '${errores > 0 ? ' · ❌ $errores error${errores != 1 ? 'es' : ''}' : ''}'
            '${pendientes > 0 ? ' · ⏳ $pendientes pendiente${pendientes != 1 ? 's' : ''}' : ''}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
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

  /// Muestra el menú de opciones para agregar un trabajador.
  void _showAgregarMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Agregar trabajador',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF0D2148),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2148).withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add_outlined,
                      color: Color(0xFF0D2148)),
                ),
                title: const Text('Nuevo trabajador',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Crear uno que aún no existe en el sistema'),
                onTap: () {
                  Navigator.pop(context);
                  _crearTrabajador();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE87722).withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.group_add_outlined,
                      color: Color(0xFFE87722)),
                ),
                title: const Text('Agregar existente',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Asignar un trabajador ya registrado a esta obra'),
                onTap: () {
                  Navigator.pop(context);
                  _agregarTrabajadorExistente();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Busca trabajadores existentes que no están en esta obra y permite asignarlos.
  Future<void> _agregarTrabajadorExistente() async {
    // IDs ya en la obra
    final enObraIds = trabajadores
        .map((t) => (t['trabajador_id'] ?? '').toString())
        .toSet();

    List<dynamic> disponibles = [];
    try {
      final todos = await supabase
          .from('trabajadores')
          .select('trabajador_id, nombre, rut')
          .eq('estado', 'ACTIVO')
          .order('nombre');

      disponibles = (todos as List)
          .where((t) => !enObraIds.contains(t['trabajador_id'].toString()))
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cargar trabajadores: $e')));
      }
      return;
    }

    if (disponibles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Todos los trabajadores del sistema ya están en esta obra.')),
        );
      }
      return;
    }

    // Diálogo de búsqueda y selección
    if (!mounted) return;
    final seleccionado = await showDialog<Map>(
      context: context,
      builder: (ctx) => _DialogSeleccionarTrabajador(
          trabajadores: disponibles),
    );

    if (seleccionado == null || !mounted) return;

    final cargoCtrl = TextEditingController();
    // Pedir cargo opcional
    final cargoConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Asignar ${seleccionado['nombre']}'),
        content: TextField(
          controller: cargoCtrl,
          decoration: const InputDecoration(
            labelText: 'Cargo en esta obra (opcional)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Asignar'),
          ),
        ],
      ),
    );

    if (cargoConfirm != true || !mounted) return;

    try {
      await supabase.from('trabajador_obras').insert({
        'trabajador_id': seleccionado['trabajador_id'],
        'obra_id': widget.obraId,
        'activo': true,
        'cargo': cargoCtrl.text.trim().isEmpty ? null : cargoCtrl.text.trim(),
      });
      _loadWorkers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${seleccionado['nombre']} asignado a ${widget.obraNombre}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al asignar: $e')),
        );
      }
    }
  }

  /// Crea un nuevo trabajador. Solo accesible si _canWriteThisObra.
  Future<void> _crearTrabajador() async {
    final nombreCtrl = TextEditingController();
    final rutCtrl    = TextEditingController();
    final cargoCtrl  = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo trabajador'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rutCtrl,
                decoration: const InputDecoration(
                  labelText: 'RUT (ej: 12.345.678-9) *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cargoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Cargo (ej: Maestro, Ayudante)',
                  border: OutlineInputBorder(),
                ),
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
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final nombre = nombreCtrl.text.trim();
    final rut    = rutCtrl.text.trim();
    if (nombre.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre es obligatorio')));
      }
      return;
    }
    if (rut.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El RUT es obligatorio')));
      }
      return;
    }

    try {
      final trabajadorId = const Uuid().v4();

      // 1) Crear trabajador con UUID generado en cliente
      await supabase.from('trabajadores').insert({
        'trabajador_id': trabajadorId,
        'nombre': nombre,
        'rut':    rut,
        'estado': 'ACTIVO',
      });

      // 2) Asignar a esta obra
      await supabase.from('trabajador_obras').insert({
        'trabajador_id': trabajadorId,
        'obra_id':       widget.obraId,
        'activo':        true,
        'cargo': cargoCtrl.text.trim().isEmpty ? null : cargoCtrl.text.trim(),
      });

      _loadWorkers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear trabajador: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pendientesCount = OfflineQueueService.listPending()
        .where((e) => e.status != 'SENT')
        .length;
    final isOnline = ConnectivityService.instance.isOnline;
    final p = perfil;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.obraNombre,
                style: const TextStyle(fontSize: 16)),
            if (p != null)
              Text(
                p.nombre,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: loading ? null : _loadWorkers,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
          ),

          // Botón sync: solo para usuarios que pueden escribir
          if (_canWriteThisObra)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: syncing
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.sync),
                  onPressed: syncing ? null : _syncManual,
                  tooltip: 'Sincronizar entregas offline',
                ),
                if (pendientesCount > 0 && !syncing)
                  Positioned(
                    right: 6, top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.orange, shape: BoxShape.circle),
                      child: Text('$pendientesCount',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),

          // Indicador online/offline
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
                      child: const Text('Reintentar')),
                ],
              ),
            )
          : Column(
              children: [
                // Banner offline
                if (offlineMode || !isOnline)
                  _Banner(
                    color: Colors.grey.shade200,
                    icon: Icons.cloud_off,
                    iconColor: Colors.grey,
                    text: 'Modo OFFLINE: mostrando desde caché local.',
                  ),

                // Banner pendientes de sync
                if (pendientesCount > 0 && _canWriteThisObra)
                  _Banner(
                    color: Colors.orange.shade50,
                    icon: Icons.sync,
                    iconColor: Colors.orange,
                    text: '$pendientesCount entrega${pendientesCount != 1 ? 's' : ''} '
                        'pendiente${pendientesCount != 1 ? 's' : ''}. '
                        '${isOnline ? 'Sincronizando automáticamente...' : 'Se enviará al recuperar conexión.'}',
                  ),

                // Banner solo lectura
                if (p?.isReadonly == true)
                  _Banner(
                    color: Colors.blue.shade50,
                    icon: Icons.visibility,
                    iconColor: Colors.blue,
                    text: 'Modo solo lectura. No puedes realizar entregas.',
                  ),

                // Buscador
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar por nombre o RUT',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                // Contador
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '${filtrados.length} trabajador${filtrados.length != 1 ? 'es' : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: filtrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.person_off,
                                  size: 48, color: Colors.black26),
                              const SizedBox(height: 12),
                              Text(
                                offlineMode
                                    ? 'Sin trabajadores en caché.'
                                    : 'Sin trabajadores en esta obra.',
                                style: const TextStyle(
                                    color: Colors.black54),
                              ),
                              if (_canWriteThisObra) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _crearTrabajador,
                                  icon: const Icon(Icons.person_add),
                                  label: const Text('Crear primer trabajador'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadWorkers,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: filtrados.length,
                            itemBuilder: (context, index) {
                              final t = filtrados[index];
                              final inicial = (t['nombre'] ?? '?')
                                  .toString()
                                  .substring(0, 1)
                                  .toUpperCase();
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF0D2148),
                                  child: Text(
                                    inicial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  t['nombre'] ?? 'Sin nombre',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0D2148),
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (t['rut'] != null) t['rut'],
                                    if (t['cargo'] != null) t['cargo'],
                                  ].join(' · '),
                                  style: const TextStyle(
                                    color: Color(0xFF6B7A99),
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFF6B7A99),
                                ),
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => WorkerDetailPage(
                                        obraId: widget.obraId,
                                        obraNombre: widget.obraNombre,
                                        trabajadorId: t['trabajador_id'],
                                        trabajadorNombre:
                                            t['nombre'] ?? '',
                                        trabajadorRut: t['rut'] ?? '',
                                        canWrite:  _canWriteThisObra,
                                        moduloEpp: perfil?.moduloEpp ?? true,
                                      ),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                              ));
                            },
                          ),
                        ),
                ),
              ],
            ),

      // FAB: solo ADMIN o SUPERVISOR de esta obra
      floatingActionButton: _canWriteThisObra
          ? FloatingActionButton(
              onPressed: _showAgregarMenu,
              tooltip: 'Agregar trabajador',
              child: const Icon(Icons.person_add),
            )
          : null,
    );
  }
}

/// Widget auxiliar para banners informativos uniformes.
class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Color iconColor;
  final String text;

  const _Banner({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: color,
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────
// Diálogo de búsqueda y selección de trabajador existente
// ─────────────────────────────────────────────────────────────
class _DialogSeleccionarTrabajador extends StatefulWidget {
  final List<dynamic> trabajadores;
  const _DialogSeleccionarTrabajador({required this.trabajadores});

  @override
  State<_DialogSeleccionarTrabajador> createState() =>
      _DialogSeleccionarTrabajadorState();
}

class _DialogSeleccionarTrabajadorState
    extends State<_DialogSeleccionarTrabajador> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _filtrados = [];

  @override
  void initState() {
    super.initState();
    _filtrados = widget.trabajadores;
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtrados = q.isEmpty
          ? widget.trabajadores
          : widget.trabajadores.where((t) {
              final nombre = (t['nombre'] ?? '').toString().toLowerCase();
              final rut = (t['rut'] ?? '').toString().toLowerCase();
              return nombre.contains(q) || rut.contains(q);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seleccionar trabajador',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF0D2148),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre o RUT…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: _filtrados.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Sin resultados.',
                          style: TextStyle(color: Color(0xFF6B7A99))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filtrados.length,
                      itemBuilder: (_, i) {
                        final t = _filtrados[i];
                        final inicial = (t['nombre'] ?? '?')
                            .toString()
                            .substring(0, 1)
                            .toUpperCase();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF0D2148),
                            child: Text(inicial,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                          title: Text(t['nombre'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0D2148))),
                          subtitle: Text(t['rut'] ?? '',
                              style: const TextStyle(
                                  color: Color(0xFF6B7A99), fontSize: 13)),
                          onTap: () => Navigator.of(context)
                              .pop(Map<String, dynamic>.from(t)),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
