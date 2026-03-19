import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'workers_page.dart';
import 'stock_page.dart';
import 'services/auth_service.dart';
import 'services/offline_cache_service.dart';
import 'services/data_cache_service.dart';
import 'main.dart' show LoginPage;

class ObrasPage extends StatefulWidget {
  final bool modoOffline;
  const ObrasPage({super.key, this.modoOffline = false});

  @override
  State<ObrasPage> createState() => _ObrasPageState();
}

class _ObrasPageState extends State<ObrasPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;
  bool modoOffline = false;
  List<Map<String, dynamic>> obras = [];

  PerfilUsuario? get perfil => AuthService.instance.perfil;

  @override
  void initState() {
    super.initState();
    modoOffline = widget.modoOffline;
    _loadObras();
    // Cuando hay conexión, sincronizar en segundo plano
    if (!modoOffline) DataCacheService.sincronizarTodo();
  }

  Future<void> _loadObras() async {
    setState(() { loading = true; error = null; });

    try {
      if (modoOffline) {
        // Sin conexión: usar caché local
        final cached = OfflineCacheService.getObras();
        setState(() => obras = cached);
      } else {
        // Con conexión: cargar desde Supabase (RLS filtra automáticamente)
        final data = await AuthService.instance.cargarObras();
        setState(() => obras = data);
      }
    } catch (e) {
      // Fallback a caché si falla la red
      final cached = OfflineCacheService.getObras();
      if (cached.isNotEmpty) {
        setState(() { obras = cached; modoOffline = true; });
      } else {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _logout() async {
    AuthService.instance.limpiar();
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Future<void> _crearObra() async {
    final nombreCtrl = TextEditingController();
    final dirCtrl    = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Centro de Costo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del centro *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dirCtrl,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
    if (nombre.isEmpty) return;

    try {
      await supabase.from('obras').insert({
        'nombre': nombre,
        'direccion': dirCtrl.text.trim().isEmpty ? null : dirCtrl.text.trim(),
        'estado': 'ACTIVA',
      });
      _loadObras();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear centro de costo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = perfil;

    final (rolLabel, rolColor) = switch (p?.rol) {
      'ADMIN'      => ('Admin', const Color(0xFF0D2148)),
      'SUPERVISOR' => ('Supervisor', const Color(0xFFE87722)),
      'READONLY'   => ('Lectura', Colors.grey.shade600),
      _            => ('?', Colors.grey),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Centros de Costo'),
        actions: [
          if (p != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Text(
                '${p.nombre.split(' ').first} · $rolLabel',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (p?.canWrite == true && p?.moduloEpp == true)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Stock EPP',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StockPage()),
              ),
            ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),

      body: Column(
        children: [
          // Banner modo offline
          if (modoOffline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFE87722).withOpacity(0.15),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, size: 16, color: Color(0xFFE87722)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modo sin conexión · ${OfflineCacheService.descripcionSync}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE87722),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE87722)))
          : error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text('Error: $error',
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadObras,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : obras.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D2148).withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_off,
                                size: 48, color: Color(0xFF0D2148)),
                          ),
                          const SizedBox(height: 16),
                          const Text('Sin centros de costo asignados.',
                              style: TextStyle(
                                color: Color(0xFF6B7A99),
                                fontSize: 15,
                              )),
                          if (p?.isAdmin == true) ...[
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _crearObra,
                              icon: const Icon(Icons.add),
                              label: const Text('Crear primer centro de costo'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFFE87722),
                      onRefresh: _loadObras,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: obras.length,
                        itemBuilder: (context, index) {
                          final o = obras[index];
                          final estado = o['estado'] ?? 'ACTIVA';
                          final activa = estado == 'ACTIVA';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: activa
                                      ? const Color(0xFF0D2148).withOpacity(0.1)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.location_on,
                                  color: activa
                                      ? const Color(0xFF0D2148)
                                      : Colors.grey,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                o['nombre'] ?? 'Sin nombre',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0D2148),
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: o['direccion'] != null && o['direccion'].toString().isNotEmpty
                                  ? Text(
                                      o['direccion'],
                                      style: const TextStyle(
                                        color: Color(0xFF6B7A99),
                                        fontSize: 13,
                                      ),
                                    )
                                  : null,
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF6B7A99),
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => WorkersPage(
                                      obraId: o['obra_id'],
                                      obraNombre: o['nombre'] ?? '',
                                      perfil: p,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
          ),  // Expanded
        ],
      ),  // Column body

      floatingActionButton: p?.isAdmin == true
          ? FloatingActionButton(
              onPressed: _crearObra,
              tooltip: 'Nuevo centro de costo',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}