import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/auth_service.dart';
import 'services/subscription_service.dart';
import 'main.dart' show LoginPage;

/// Pantalla mostrada cuando la suscripción de la organización
/// está inactiva o suspendida según MIRA DEVELOPER.
class SuscripcionBloqueadaPage extends StatelessWidget {
  const SuscripcionBloqueadaPage({super.key});

  Future<void> _logout(BuildContext context) async {
    AuthService.instance.limpiar();
    SubscriptionService.instance.limpiar();
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // bloquea el botón "atrás"
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.block_rounded,
                    size: 44,
                    color: Colors.red.shade700,
                  ),
                ),
                const Text(
                  'Suscripción Inactiva\no Suspendida',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D2148),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tu organización no tiene una suscripción activa a TrazApp. '
                  'Contacta al administrador o al equipo de soporte para '
                  'reactivar el servicio.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
                OutlinedButton.icon(
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0D2148),
                    side: const BorderSide(color: Color(0xFF0D2148)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
