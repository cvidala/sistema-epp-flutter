import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

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
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
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
    if (_isProcessing || _captured) return;
    _isProcessing = true;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted || _captured) return;

      // Filtrar falsos positivos: el rostro debe ocupar al menos 15% del ancho
      // de la imagen y estar centrado (no en los bordes)
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
          // Face just appeared — start hold timer
          _faceSeenAt = DateTime.now();
          _iniciarProgressTimer();
          if (mounted) setState(() => _statusText = 'Rostro detectado — no te muevas');
        } else {
          // Check if held long enough
          final elapsed = DateTime.now().difference(_faceSeenAt!);
          if (elapsed >= _holdDuration) {
            _captured = true;
            _progressTimer?.cancel();
            await _controller!.stopImageStream();
            if (mounted) setState(() { _holdProgress = 1.0; _statusText = '✓ Capturando...'; });
            await _capturar();
          }
        }
      } else if (validFaces.isEmpty) {
        // Face lost — reset
        if (_faceSeenAt != null) {
          _faceSeenAt = null;
          _progressTimer?.cancel();
          _progressTimer = null;
          if (mounted) {
            setState(() {
              _holdProgress = 0.0;
              _statusText = 'Posiciona tu rostro en el óvalo';
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
      if (mounted) Navigator.pop(context, compressed);
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
          // Preview de cámara
          if (_controller != null && _controller!.value.isInitialized)
            Center(child: CameraPreview(_controller!))
          else
            const Center(
                child: CircularProgressIndicator(color: Colors.white)),

          // Óvalo guía + overlay oscuro + arco de progreso
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

    // Overlay oscuro con agujero oval
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
        overlayPath, Paint()..color = Colors.black.withOpacity(0.55));

    // Borde base del óvalo
    final borderColor = faceDetected
        ? const Color(0xFF4ADE80).withOpacity(0.5)
        : Colors.white.withOpacity(0.85);

    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Arco de progreso verde
    if (holdProgress > 0) {
      final progressPaint = Paint()
        ..color = const Color(0xFF4ADE80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round;

      // Dibujar arco desde la parte superior, sentido horario
      canvas.drawArc(
        ovalRect,
        -math.pi / 2,               // start: arriba
        2 * math.pi * holdProgress, // sweep: progreso
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
