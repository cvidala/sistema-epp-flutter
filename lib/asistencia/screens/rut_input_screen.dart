import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../services/forensic_service.dart';
import '../models/asistencia_pendiente.dart';
import '../services/asistencia_hive_service.dart';
import '../services/asistencia_sync_service.dart';
import '../services/asistencia_upload_service.dart';
import 'camera_capture_screen.dart';

// ── Tipos de marcaje ───────────────────────────────────────────────
const _tipos = [
  _TipoMarcaje('Entrada',             '🟢', Color(0xFF166534), Color(0xFFdcfce7)),
  _TipoMarcaje('Salida',              '🔴', Color(0xFF991b1b), Color(0xFFfee2e2)),
  _TipoMarcaje('Salida a Colación',   '🟡', Color(0xFF92400e), Color(0xFFffedd5)),
  _TipoMarcaje('Entrada de Colación', '🔵', Color(0xFF1e40af), Color(0xFFdbeafe)),
  _TipoMarcaje('Permiso Especial',    '🔵', Color(0xFF5b21b6), Color(0xFFede9fe)),
];

class _TipoMarcaje {
  final String label;
  final String emoji;
  final Color textColor;
  final Color bgColor;
  const _TipoMarcaje(this.label, this.emoji, this.textColor, this.bgColor);
}

// ── RUT Formatter ──────────────────────────────────────────────────
class _RutFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String raw = newValue.text
        .replaceAll('.', '')
        .replaceAll('-', '')
        .toUpperCase();
    if (raw.isEmpty) return newValue.copyWith(text: '');

    String dv = '';
    String body = raw;
    if (raw.length > 1) {
      dv = raw[raw.length - 1];
      body = raw.substring(0, raw.length - 1);
    }

    String formatted = '';
    for (int i = 0; i < body.length; i++) {
      if (i > 0 && (body.length - i) % 3 == 0) formatted += '.';
      formatted += body[i];
    }
    if (dv.isNotEmpty) formatted += '-$dv';

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ── Validador de formato RUT (sin verificar dígito verificador) ────
// Solo comprueba estructura: cuerpo 1-8 dígitos + DV dígito o K
bool _validarFormato(String rut) {
  final clean = rut
      .replaceAll('.', '')
      .replaceAll('-', '')
      .replaceAll(' ', '')
      .toUpperCase();
  if (clean.length < 2) return false;
  final body = clean.substring(0, clean.length - 1);
  final dv   = clean[clean.length - 1];
  return RegExp(r'^\d{1,8}$').hasMatch(body) && RegExp(r'^[\dK]$').hasMatch(dv);
}

// Normaliza RUT para enviar a la BD: sin puntos, sin espacios, sin guión, mayúsculas
// Así coincide con cualquier formato que esté guardado en la BD
String _rutLimpio(String rut) =>
    rut.replaceAll('.', '').replaceAll('-', '').replaceAll(' ', '').toUpperCase();

// ── Screen ─────────────────────────────────────────────────────────
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
  Timer? _clockTimer;
  int _countdown = 3;
  bool _online = false;
  int _tipoIndex = 0;
  String? _rutError;
  String _horaActual = '';
  String _fechaActual = '';

  static String _formatHora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  static String _formatFecha(DateTime t) {
    const dias   = ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'];
    const meses  = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
    return '${dias[t.weekday - 1]} ${t.day} de ${meses[t.month - 1]} ${t.year}';
  }

  void _actualizarReloj() {
    final now = DateTime.now();
    setState(() {
      _horaActual = _formatHora(now);
      _fechaActual = _formatFecha(now);
    });
  }

  @override
  void initState() {
    super.initState();
    _actualizarReloj();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _actualizarReloj());
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
    _clockTimer?.cancel();
    _rutController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _marcar() async {
    final rutTexto = _rutController.text.trim();
    final rut = _rutLimpio(rutTexto);

    // Validar formato (estructura solamente, sin verificar DV)
    if (!_validarFormato(rutTexto)) {
      setState(() => _rutError = 'Formato inválido — debe ser 12.345.678-9');
      return;
    }

    setState(() { _rutError = null; _cargando = true; });

    // Verificar existencia en BD (solo si hay conexión)
    if (_online) {
      final existe = await _verificarRutEnBD(rut);
      if (!mounted) return;
      if (!existe) {
        setState(() {
          _cargando = false;
          _rutError = 'RUT no registrado en el sistema';
        });
        return;
      }
    }

    // Ir a cámara
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
    final tipo = _tipos[_tipoIndex].label;

    if (_online) {
      await _marcarOnline(rut, fotoBytes, forensics, tipo);
    } else {
      await _marcarOffline(rut, fotoBytes, forensics, tipo);
    }
  }

  Future<bool> _verificarRutEnBD(String rut) async {
    try {
      final result = await Supabase.instance.client
          .rpc('rut_existe', params: {'p_rut': rut})
          .timeout(const Duration(seconds: 5));
      return result as bool? ?? false;
    } catch (_) {
      return true; // Sin conexión → permitir (se guardará offline)
    }
  }

  Future<void> _marcarOnline(String rut, Uint8List fotoBytes,
      Map<String, dynamic>? forensics, String tipo) async {
    try {
      final id = const Uuid().v4();
      await AsistenciaUploadService.subirOnline(
        localEventId: id,
        rut: rut,
        fotoBytes: fotoBytes,
        forensics: forensics,
        tipo: tipo,
      );
      _mostrarResultado(_ResultStatus.ok);
    } catch (e) {
      debugPrint('[Marcar] Error online, guardando offline: $e');
      await _guardarOffline(rut, fotoBytes, forensics, tipo);
      _mostrarResultado(_ResultStatus.offline);
    }
  }

  Future<void> _marcarOffline(String rut, Uint8List fotoBytes,
      Map<String, dynamic>? forensics, String tipo) async {
    await _guardarOffline(rut, fotoBytes, forensics, tipo);
    _mostrarResultado(_ResultStatus.offline);
  }

  Future<void> _guardarOffline(String rut, Uint8List fotoBytes,
      Map<String, dynamic>? forensics, String tipo) async {
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
      tipo: tipo,
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
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        setState(() {
          _resultStatus = null;
          _rutController.clear();
          _rutError = null;
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
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 32),

          // Logo + título
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('icon_asistencia.png',
                    width: 52, height: 52, fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TrazApp',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  Text('Asistencia Diaria',
                      style: TextStyle(
                          color: Color(0xFF7EB5FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Estado online/offline
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 7, height: 7,
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

          const SizedBox(height: 24),

          // Selector tipo de marcaje
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Tipo de marcaje',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tipos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = _tipos[i];
                final sel = _tipoIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _tipoIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? t.bgColor : const Color(0xFF1a3a7c),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel
                            ? t.textColor.withOpacity(0.4)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '${t.emoji} ${t.label}',
                      style: TextStyle(
                        color: sel ? t.textColor : Colors.white60,
                        fontSize: 12,
                        fontWeight:
                            sel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Campo RUT
          Align(
            alignment: Alignment.centerLeft,
            child: Text('RUT del trabajador',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rutController,
            focusNode: _focusNode,
            autofocus: true,
            keyboardType: TextInputType.visiblePassword,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
            decoration: InputDecoration(
              hintText: '12.345.678-9',
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.2), fontSize: 22),
              filled: true,
              fillColor: _rutError != null
                  ? const Color(0xFF4a1a1a)
                  : const Color(0xFF1a3a7c),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: _rutError != null
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFE87722),
                  width: 2,
                ),
              ),
              errorText: _rutError,
              errorStyle: const TextStyle(
                  color: Color(0xFFFF8080), fontSize: 12),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.\-kK]')),
              _RutFormatter(),
            ],
            onChanged: (_) {
              if (_rutError != null) setState(() => _rutError = null);
            },
            onSubmitted: (_) {
              if (!_cargando) _marcar();
            },
          ),

          const SizedBox(height: 20),

          // Botón marcar
          SizedBox(
            width: double.infinity,
            height: 58,
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

          const SizedBox(height: 24),

          // Reloj grande — hora de marcado
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0a1a3a),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                Text(
                  _horaActual,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fechaActual,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hora de marcado',
                  style: TextStyle(
                    color: const Color(0xFFE87722).withOpacity(0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          Text(
            'Solo personal autorizado — RUT debe estar registrado en el sistema',
            style: TextStyle(
                color: Colors.white.withOpacity(0.25), fontSize: 10),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildResultOverlay() {
    final isOk = _resultStatus == _ResultStatus.ok;
    final tipo = _tipos[_tipoIndex];
    return Container(
      color: Colors.black.withOpacity(0.92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOk ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
              color: isOk ? const Color(0xFF22C55E) : const Color(0xFFE87722),
              size: 80,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: tipo.bgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${tipo.emoji} ${tipo.label}',
                style: TextStyle(
                    color: tipo.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isOk ? 'Asistencia Registrada' : 'Guardada Offline',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            // Hora grande de confirmación
            Text(
              _horaActual,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              _fechaActual,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                isOk
                    ? 'Esta es la hora exacta de tu marcado.'
                    : 'Sin conexión. Se sincronizará automáticamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 13),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Siguiente trabajador en $_countdown...',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ResultStatus { ok, offline }
