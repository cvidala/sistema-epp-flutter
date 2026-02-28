import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'workers_page.dart';
import 'stock_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/offline_queue_service.dart';
import 'services/cache_service.dart';
import 'services/device_id_service.dart'; // ✅ NUEVO

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Hive solo una vez
  await Hive.initFlutter();

  // ✅ Inicializar servicios en orden
  await OfflineQueueService.init();
  await CacheService.init();
  await DeviceIdService.init(); // ✅ NUEVO — genera/recupera deviceId persistente

  await Supabase.initialize(
    url: 'https://ppltpmmtdnprgauwnytf.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBwbHRwbW10ZG5wcmdhdXdueXRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNTM0NzIsImV4cCI6MjA4NTgyOTQ3Mn0.WsRKOEYNzU-tRrL3p6I_ip-AAQmNCgfVKEdockq_gE8',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPP MVP',
      theme: ThemeData(useMaterial3: true),
      home: const LoginGate(),
    );
  }
}

class LoginGate extends StatelessWidget {
  const LoginGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginPage();
    return const ObrasPage();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ObrasPage()),
      );
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _login,
                child: Text(loading ? 'Entrando...' : 'Entrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ObrasPage extends StatefulWidget {
  const ObrasPage({super.key});

  @override
  State<ObrasPage> createState() => _ObrasPageState();
}

class _ObrasPageState extends State<ObrasPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;
  List<dynamic> obras = [];

  @override
  void initState() {
    super.initState();
    _loadObras();
  }

  Future<void> _loadObras() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final data = await supabase
          .from('obras')
          .select()
          .order('created_at')
          .timeout(const Duration(seconds: 12));
      setState(() => obras = data);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Obras'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StockPage()),
              );
            },
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: error != null
          ? Center(child: Text('Error: $error'))
          : ListView.builder(
              itemCount: obras.length,
              itemBuilder: (context, index) {
                final o = obras[index];
                return ListTile(
                  title: Text(o['nombre'] ?? 'Sin nombre'),
                  subtitle: Text(o['direccion'] ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkersPage(
                          obraId: o['obra_id'],
                          obraNombre: o['nombre'] ?? '',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadObras,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}