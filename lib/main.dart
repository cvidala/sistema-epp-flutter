import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'obras_page.dart';
import 'services/offline_queue_service.dart';
import 'services/cache_service.dart';
import 'services/device_id_service.dart';
import 'services/auth_service.dart';
import 'services/offline_cache_service.dart';
import 'services/data_cache_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await OfflineQueueService.init();
  await CacheService.init();
  await DeviceIdService.init();
  await OfflineCacheService.init();

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
      title: 'TrazApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D2148),
          primary: const Color(0xFF0D2148),
          secondary: const Color(0xFFE87722),
          surface: Colors.white,
          background: const Color(0xFFF4F6FA),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D2148),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFE87722),
          foregroundColor: Colors.white,
          elevation: 3,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE87722),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            textStyle: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFFDDE2EE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFFDDE2EE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFF0D2148), width: 2),
          ),
          labelStyle: TextStyle(color: Color(0xFF6B7A99)),
          prefixIconColor: Color(0xFF6B7A99),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0xFFEAEEF6)),
          ),
          margin: EdgeInsets.symmetric(vertical: 4),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        dividerColor: const Color(0xFFEAEEF6),
      ),
      home: const LoginGate(),
    );
  }
}

/// Decide si mostrar Login u ObrasPage según sesión activa.
/// Si hay sesión, también carga el perfil antes de navegar.
class LoginGate extends StatefulWidget {
  const LoginGate({super.key});

  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final session = Supabase.instance.client.auth.currentSession;

    // ── Sin sesión guardada → ir al login ──────────────────
    if (session == null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
      return;
    }

    // ── Hay sesión guardada: verificar conectividad ─────────
    final connectivity = await Connectivity().checkConnectivity();
    final hayInternet  = connectivity != ConnectivityResult.none;

    if (hayInternet) {
      // Online: cargar perfil desde Supabase y sincronizar caché
      try {
        await AuthService.instance.cargarPerfil();
        // Sync en segundo plano — no bloquea la navegación
        DataCacheService.sincronizarTodo();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => ObrasPage()),
          );
        }
      } on PerfilNoEncontradoException catch (e) {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => LoginPage(errorInicial: e.message)),
          );
        }
      } catch (e) {
        // Fallo de red inesperado → intentar caché
        await _entrarDesdeCache();
      }
    } else {
      // Offline: entrar con caché local si existe
      await _entrarDesdeCache();
    }
  }

  Future<void> _entrarDesdeCache() async {
    if (!OfflineCacheService.tieneCacheValido) {
      // Nunca se sincronizó → no puede entrar offline
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const LoginPage(
              errorInicial:
                  'Sin conexión y sin datos guardados.\nInicia sesión al menos una vez con internet.',
            ),
          ),
        );
      }
      return;
    }

    // Reconstruir perfil desde caché
    final perfilData = OfflineCacheService.getPerfil()!;
    AuthService.instance.cargarPerfilDesdeCache(perfilData);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ObrasPage(modoOffline: true)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LOGIN PAGE
// ─────────────────────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  final String? errorInicial;
  const LoginPage({super.key, this.errorInicial});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl  = TextEditingController();
  bool loading     = false;
  bool _verPass    = false;
  String? error;

  @override
  void initState() {
    super.initState();
    error = widget.errorInicial;
  }

  Future<void> _login() async {
    setState(() { loading = true; error = null; });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
      );

      // Cargar perfil desde Supabase
      await AuthService.instance.cargarPerfil();

      // Sincronizar caché en segundo plano para futuros usos offline
      DataCacheService.sincronizarTodo();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ObrasPage()),
      );
    } on PerfilNoEncontradoException catch (e) {
      await Supabase.instance.client.auth.signOut();
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D2148), Color(0xFF1A3A6B)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 56),

                // Logo / título
                Container(
                  width: 80, height: 80,
                  margin: const EdgeInsets.only(bottom: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE87722),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE87722).withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.health_and_safety,
                      size: 44, color: Colors.white),
                ),
                const Text(
                  'TrazApp',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gestión de Equipos de Protección Personal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 48),

                // Email field
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.white60),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE87722), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Password field
                TextField(
                  controller: passCtrl,
                  obscureText: !_verPass,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    labelStyle: const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(Icons.lock_outlined, color: Colors.white60),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _verPass ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38,
                      ),
                      onPressed: () => setState(() => _verPass = !_verPass),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE87722), width: 2),
                    ),
                  ),
                  onSubmitted: (_) => loading ? null : _login(),
                ),

                if (error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],

                const Spacer(),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE87722),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Ingresar',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}