// lib/homepage.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ml/detection.dart';
import '../services/face_detector.dart';
import '../widgets/face_detection_painter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Uint8List? _imageBytes;
  ui.Image? _image;
  Size? _imageSize;
  List<Detection> _detections = [];
  final FaceDetectorService _faceDetector = FaceDetectorService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
  }

  Future<void> _initializeDetector() async {
    await _faceDetector.init();
    setState(() {
      _initialized = true;
    });
  }

  Future<void> _loadImage(Uint8List bytes) async {
    print('🔄 Iniciando carga de imagen');
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    final image = await completer.future;
    print('📱 Imagen decodificada: ${image.width}x${image.height}');
    setState(() {
      _image = image;
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    });
    print('💾 Estado actualizado con nueva imagen');
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _detections = [];
        });
        
        await _loadImage(bytes);
        
        if (_initialized) {
          try {
            print('🔍 Iniciando detección de rostros');
            final detections = await _faceDetector.detectFaces(bytes);
            setState(() {
              _detections = detections;
            });
            print('✅ Detección completada: ${detections.length} rostros encontrados');
          } catch (e) {
            print('❌ Error en detección: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al detectar rostros: $e')),
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error al seleccionar imagen: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detección de Rostros'),
        backgroundColor: Colors.green,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _imageBytes == null
              ? const Text(
                "Selecciona una imagen para comenzar",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                )
              : Text(
                'Número de rostros detectados: ${_detections.length}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: _imageSize?.aspectRatio ?? 1,
                    child: Container(
                      width: double.infinity,
                      child: _imageBytes == null
                        ? const Center(
                            child: Icon(Icons.image, size: 200, color: Colors.grey)
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                _imageBytes!,
                                fit: BoxFit.contain,
                              ),
                              if (_image != null && _detections.isNotEmpty)
                                CustomPaint(
                                  size: Size.infinite,
                                  painter: FaceDetectionPainter(
                                    image: _image!,
                                    detections: _detections,
                                    originalSize: _imageSize!,
                                  ),
                                ),
                            ],
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tomar Foto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.image),
                  label: const Text('Galería'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
