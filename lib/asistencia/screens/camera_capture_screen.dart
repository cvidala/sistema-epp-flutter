import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Resultado de la pantalla de captura.
/// [esFallback] = true cuando la detección biométrica no completó y
/// el trabajador debe identificarse por PIN alternativo.
class CameraResult {
  final Uint8List fotoBytes;
  final bool esFallback;
  final String? fallbackMotivo; // 'face_timeout' | 'face_not_detected'

  const CameraResult({
    required this.fotoBytes,
    this.esFallback = false,
    this.fallbackMotivo,
  });
}

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  CameraDescription? _frontCamera;
  bool _isProcessing = false;
  bool _captured = false;
  String _statusText = 'Posiciona tu rostro en el óvalo';

  // Hold-to-capture state
  DateTime? _faceSeenAt;
  double _holdProgress = 0.0;
  Timer? _progressTimer;
  static const _holdDuration = Duration(seconds: 2);

  // Fallback: 3 intentos fallidos O 20 segundos (ORD. 1140/27 §2)
  int _intentosFallidos = 0;
  static const _maxIntentos  = 3;
  static const _timeoutTotal = Duration(seconds: 20);
  Timer? _fallbackTimer;
  bool _fallbackTriggered = false;
  int _segundosRestantes = 20;
  Timer? _countdownTimer;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: false,
      enableClassification: false,
      enableLandmarks: false,
      enableTracking: false,
    ),
  );

  @override
  void initState() {
    super.initState();
    _iniciarCamara();
    _iniciarTimerFallback();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _fallbackTimer?.cancel();
    _countdownTimer?.cancel();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  void _iniciarTimerFallback() {
    // Countdown visual
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _captured || _fallbackTriggered) { t.cancel(); return; }
      setState(() => _segundosRestantes = (_segundosRestantes - 1).clamp(0, 20));
    });
    // Timer principal de 20s
    _fallbackTimer = Timer(_timeoutTotal, () {
      if (!_captured && !_fallbackTriggered) _triggerFallback('face_timeout');
    });
  }

  Future<void> _iniciarCamara() async {
    try {
      final cameras = await availableCameras();
      _frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        _frontCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {});
      _controller!.startImageStream(_procesarFrame);
    } catch (e) {
      if (mounted) setState(() => _statusText = 'Error de cámara: $e');
    }
  }

  void _procesarFrame(CameraImage image) async {
    if (_isProcessing || _captured || _fallbackTriggered) return;
    _isProcessing = true;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted || _captured || _fallbackTriggered) return;

      final validFaces = faces.where((face) {
        final box = face.boundingBox;
        if (box.width < image.width * 0.15) return false;
        final cx = box.center.dx;
        final cy = box.center.dy;
        if (cx < image.width * 0.15 || cx > image.width * 0.85) return false;
        if (cy < image.height * 0.15 || cy > image.height * 0.85) return false;
        return true;
      }).toList();

      if (validFaces.isNotEmpty) {
        if (_faceSeenAt == null) {
          _faceSeenAt = DateTime.now();
          _iniciarProgressTimer();
          if (mounted) setState(() => _statusText = 'Rostro detectado — no te muevas');
        } else {
          final elapsed = DateTime.now().difference(_faceSeenAt!);
          if (elapsed >= _holdDuration) {
            _captured = true;
            _progressTimer?.cancel();
            _fallbackTimer?.cancel();
            _countdownTimer?.cancel();
            await _controller!.stopImageStream();
            if (mounted) setState(() { _holdProgress = 1.0; _statusText = '✓ Capturando...'; });
            await _capturar();
          }
        }
      } else if (validFaces.isEmpty) {
        if (_faceSeenAt != null) {
          // Contar intento fallido si el rostro se había detectado con progreso significativo
          if (_holdProgress > 0.3) {
            _intentosFallidos++;
            if (_intentosFallidos >= _maxIntentos && !_fallbackTriggered) {
              _triggerFallback('face_not_detected');
              return;
            }
          }
          _faceSeenAt = null;
          _progressTimer?.cancel();
          _progressTimer = null;
          if (mounted) {
            setState(() {
              _holdProgress = 0.0;
              _statusText = _intentosFallidos > 0
                  ? 'Intento $_intentosFallidos/$_maxIntentos — reposiciona tu rostro'
                  : 'Posiciona tu rostro en el óvalo';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[Camera] Error procesando frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Activa el fallback: captura una foto del estado actual (evidencia)
  /// y retorna con esFallback = true.
  Future<void> _triggerFallback(String motivo) async {
    if (_fallbackTriggered || _captured) return;
    _fallbackTriggered = true;
    _progressTimer?.cancel();
    _fallbackTimer?.cancel();
    _countdownTimer?.cancel();

    if (mounted) {
      setState(() => _statusText = 'Abriendo identificación alternativa...');
    }

    try {
      await _controller?.stopImageStream();
      final xfile = await _controller?.takePicture();
      if (xfile == null) {
        if (mounted) Navigator.pop(context, null);
        return;
      }
      final bytes = await xfile.readAsBytes();
      final compressed = await _comprimirFoto(bytes);
      if (mounted) {
        Navigator.pop(context, CameraResult(
          fotoBytes:      compressed,
          esFallback:     true,
          fallbackMotivo: motivo,
        ));
      }
    } catch (e) {
      debugPrint('[Camera] Error en fallback: $e');
      if (mounted) Navigator.pop(context, null);
    }
  }

  void _iniciarProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted || _captured || _faceSeenAt == null) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_faceSeenAt!).inMilliseconds;
      final progress = (elapsed / _holdDuration.inMilliseconds).clamp(0.0, 1.0);
      setState(() {
        _holdProgress = progress;
        if (progress > 0.1) _statusText = 'Mantén el rostro quieto...';
      });
    });
  }

  InputImage? _buildInputImage(CameraImage image) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    final rotation =
        InputImageRotationValue.fromRawValue(_frontCamera?.sensorOrientation ?? 0) ??
            InputImageRotation.rotation0deg;
    final bytes = image.planes.fold<List<int>>(
      [],
      (acc, plane) => acc..addAll(plane.bytes),
    );
    return InputImage.fromBytes(
      bytes: Uint8List.fromList(bytes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Future<void> _capturar() async {
    try {
      final xfile = await _controller!.takePicture();
      final bytes = await xfile.readAsBytes();
      final compressed = await _comprimirFoto(bytes);
      if (mounted) Navigator.pop(context, CameraResult(fotoBytes: compressed));
    } catch (e) {
      debugPrint('[Camera] Error capturando: $e');
      if (mounted) {
        _captured = false;
        _faceSeenAt = null;
        setState(() {
          _holdProgress = 0.0;
          _statusText = 'Error al capturar. Inténtalo de nuevo.';
        });
        await _controller!.startImageStream(_procesarFrame);
      }
    }
  }

  Future<Uint8List> _comprimirFoto(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();

    int targetW, targetH;
    if (w >= h) {
      targetW = w > 400 ? 400 : w;
      targetH = (h * targetW / w).round().clamp(1, 400);
    } else {
      targetH = h > 400 ? 400 : h;
      targetW = (w * targetH / h).round().clamp(1, 400);
    }

    return await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: targetW,
      minHeight: targetH,
      quality: 80,
    );
  }

  @override
  Widget build(BuildContext context) {
    final faceDetected = _faceSeenAt != null || _holdProgress > 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            Center(child: CameraPreview(_controller!))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          CustomPaint(
            painter: _FaceOvalPainter(
              holdProgress: _holdProgress,
              faceDetected: faceDetected,
            ),
          ),

          // Texto de estado
          Positioned(
            bottom: 50,
            left: 16,
            right: 16,
            child: Text(
              _statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: faceDetected ? const Color(0xFF4ADE80) : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),

          // Countdown timer — visible cuando quedan ≤10s
          if (_segundosRestantes <= 10 && !_fallbackTriggered)
            Positioned(
              top: 48,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _segundosRestantes <= 5
                      ? Colors.red.withValues(alpha: 0.85)
                      : Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_segundosRestantes s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // Botón cancelar
          Positioned(
            top: 48,
            left: 16,
            child: IconButton(
              onPressed: () => Navigator.pop(context, null),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceOvalPainter extends CustomPainter {
  final double holdProgress;
  final bool faceDetected;

  const _FaceOvalPainter({
    required this.holdProgress,
    required this.faceDetected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.68,
      height: size.height * 0.46,
    );

    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
        overlayPath, Paint()..color = Colors.black.withValues(alpha: 0.55));

    final borderColor = faceDetected
        ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.85);

    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    if (holdProgress > 0) {
      final progressPaint = Paint()
        ..color = const Color(0xFF4ADE80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        ovalRect,
        -math.pi / 2,
        2 * math.pi * holdProgress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceOvalPainter oldDelegate) =>
      oldDelegate.holdProgress != holdProgress ||
      oldDelegate.faceDetected != faceDetected;
}
