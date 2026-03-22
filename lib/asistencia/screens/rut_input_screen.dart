import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../services/forensic_service.dart';
import '../models/asistencia_pendiente.dart';
import '../services/asistencia_hive_service.dart';
import '../services/asistencia_sync_service.dart';
import '../services/asistencia_upload_service.dart';
import 'camera_capture_screen.dart';

class RutInputScreen extends StatefulWidget {
  const RutInputScreen({super.key});

  @override
  State<RutInputScreen> createState() => _RutInputScreenState();
}

class _RutInputScreenState extends State<RutInputScreen> {
  final _rutController = TextEditingController();
  final _focusNode = FocusNode();
  bool _cargando = false;
  _ResultStatus? _resultStatus;
  Timer? _resetTimer;
  int _countdown = 3;
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _online = AsistenciaSyncService.instance.isOnline;
    AsistenciaSyncService.instance.start(onStatusChange: () {
      if (mounted) {
        setState(() => _online = AsistenciaSyncService.instance.isOnline);
      }
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _rutController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _limpiarRut(String rut) =>
      rut.replaceAll('.', '').replaceAll(' ', '').toUpperCase();

  bool _rutValido(String rut) {
    final limpio = _limpiarRut(rut);
    return limpio.contains('-') && limpio.length >= 4;
  }

  Future<void> _marcar() async {
    final rut = _limpiarRut(_rutController.text.trim());
    if (!_rutValido(rut)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ingresa un RUT válido. Ejemplo: 12345678-9')),
      );
      return;
    }

    setState(() => _cargando = true);

    // Navega a la cámara y espera la foto comprimida
    final fotoBytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );

    if (!mounted) return;
    if (fotoBytes == null) {
      setState(() => _cargando = false);
      return;
    }

    final forensics = await ForensicService.capture();

    if (_online) {
      await _marcarOnline(rut, fotoBytes, forensics);
    } else {
      await _marcarOffline(rut, fotoBytes, forensics);
    }
  }

  Future<void> _marcarOnline(
      String rut, Uint8List fotoBytes, Map<String, dynamic>? forensics) async {
    try {
      final id = const Uuid().v4();
      await AsistenciaUploadService.subirOnline(
        localEventId: id,
        rut: rut,
        fotoBytes: fotoBytes,
        forensics: forensics,
      );
      _mostrarResultado(_ResultStatus.ok);
    } catch (e) {
      debugPrint('[Marcar] Error online, guardando offline: $e');
      await _guardarOffline(rut, fotoBytes, forensics);
      _mostrarResultado(_ResultStatus.offline);
    }
  }

  Future<void> _marcarOffline(
      String rut, Uint8List fotoBytes, Map<String, dynamic>? forensics) async {
    await _guardarOffline(rut, fotoBytes, forensics);
    _mostrarResultado(_ResultStatus.offline);
  }

  Future<void> _guardarOffline(
      String rut, Uint8List fotoBytes, Map<String, dynamic>? forensics) async {
    final id = const Uuid().v4();
    final dir = await getApplicationDocumentsDirectory();
    final fotoDir = Directory('${dir.path}/asistencias');
    await fotoDir.create(recursive: true);
    final fotoPath = '${fotoDir.path}/$id.jpg';
    await File(fotoPath).writeAsBytes(fotoBytes);
    final hash = sha256.convert(utf8.encode(fotoPath)).toString();

    await AsistenciaHiveService.guardar(AsistenciaPendiente(
      id: id,
      rut: rut,
      fotoLocalPath: fotoPath,
      fotoHash: hash,
      gpsLat: (forensics?['gps_lat'] as num?)?.toDouble(),
      gpsLng: (forensics?['gps_lng'] as num?)?.toDouble(),
      gpsAccuracy: (forensics?['gps_accuracy_m'] as num?)?.toDouble(),
      deviceModel: forensics?['device_model'] as String?,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
    ));
  }

  void _mostrarResultado(_ResultStatus status) {
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _resultStatus = status;
      _countdown = 3;
    });
    _resetTimer?.cancel();
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        setState(() {
          _resultStatus = null;
          _rutController.clear();
        });
        _focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2148),
      body: SafeArea(
        child: Stack(
          children: [
            _buildBody(),
            if (_resultStatus != null) _buildResultOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 48),

          // Título
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'TrazApp',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a3a7c),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Asistencia',
                  style: TextStyle(
                      color: Color(0xFF7EB5FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Estado online/offline
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _online
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _online ? 'En línea' : 'Sin conexión — guardado local',
                style: TextStyle(
                  color: _online
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const Spacer(),

          const Text(
            'Ingresa tu RUT para\nmarcar asistencia',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.4),
          ),

          const SizedBox(height: 28),

          // Campo RUT
          TextField(
            controller: _rutController,
            focusNode: _focusNode,
            autofocus: true,
            keyboardType: TextInputType.visiblePassword,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
            decoration: InputDecoration(
              hintText: '12345678-9',
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.2), fontSize: 24),
              filled: true,
              fillColor: const Color(0xFF1a3a7c),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Color(0xFFE87722), width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.\-kK]')),
            ],
            onSubmitted: (_) {
              if (!_cargando) _marcar();
            },
          ),

          const SizedBox(height: 24),

          // Botón marcar
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _cargando ? null : _marcar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE87722),
                disabledBackgroundColor: const Color(0xFF8B4A15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _cargando
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : const Text(
                      'Marcar Asistencia',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
            ),
          ),

          const Spacer(),

          Text(
            'Sistema de Asistencia — Solo personal autorizado',
            style:
                TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildResultOverlay() {
    final isOk = _resultStatus == _ResultStatus.ok;
    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOk ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
              color: isOk
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFE87722),
              size: 90,
            ),
            const SizedBox(height: 20),
            Text(
              isOk ? 'Asistencia Registrada' : 'Guardada Offline',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                isOk
                    ? 'Tu asistencia fue registrada exitosamente.'
                    : 'Sin conexión. Se sincronizará automáticamente.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 15),
              ),
            ),
            const SizedBox(height: 36),
            Text(
              'Siguiente trabajador en $_countdown...',
              style:
                  TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ResultStatus { ok, offline }
