import 'dart:async';
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
      if (faces.isNotEmpty && mounted && !_captured) {
        _captured = true;
        if (mounted) setState(() => _statusText = '✓ Rostro detectado...');
        await _controller!.stopImageStream();
        await _capturar();
      }
    } catch (e) {
      debugPrint('[Camera] Error procesando frame: $e');
    } finally {
      _isProcessing = false;
    }
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
        setState(() => _statusText = 'Error al capturar. Inténtalo de nuevo.');
        await _controller!.startImageStream(_procesarFrame);
      }
    }
  }

  /// Redimensiona al máximo 400px en el lado más largo, luego comprime.
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

          // Óvalo guía + overlay oscuro
          CustomPaint(painter: _FaceOvalPainter()),

          // Texto de estado
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'La captura es automática al detectar tu rostro',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
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

    // Borde del óvalo
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
