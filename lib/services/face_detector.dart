import 'dart:typed_data';

// Paquete para decodificar la imagen a nivel de Dart
import 'package:facedetection_blazefull/ml/anchors.dart';
import 'package:image/image.dart' as img;
// Paquete tflite_flutter para cargar e invocar el modelo
import 'package:tflite_flutter/tflite_flutter.dart';

// Estos archivos asume que existen en tu proyecto
import '../ml/detection.dart';
import '../ml/post_process.dart';

const int MODEL_INPUT_SIZE = 192;
const int NUM_BOXES = 2304;
const double MIN_SCORE_THRESH = 0.6;

/// Servicio que se encarga de cargar el modelo face_detection_full_range.tflite
/// y ejecutar el post-procesado (anchors, decodificación, NMS).
class FaceDetectorService {
  Interpreter? _interpreter;
  List<Anchor>? _anchors;
  bool _initialized = false;

  /// Inicializa el servicio:
  /// 1) Carga el modelo TFLite desde assets
  /// 2) Genera la lista de anclas (anchors) una sola vez
  Future<void> init() async {
    try {
      print('🔄 Iniciando FaceDetectorService');
      _interpreter = await Interpreter.fromAsset('assets/models/face_detection_full_range.tflite');
      
      // Usar las opciones definidas en anchors.dart
      final anchorOpts = getFullRangeOptions();
      _anchors = generateSSDAnchors(anchorOpts);

      if (_anchors!.length != NUM_BOXES) {
        throw Exception('Número incorrecto de anclas: ${_anchors!.length} (esperado: $NUM_BOXES)');
      }

      _initialized = true;
      print('✅ FaceDetectorService inicializado con ${_anchors!.length} anclas');
    } catch (e) {
      print('❌ Error al inicializar FaceDetectorService: $e');
      rethrow;
    }
  }

  /// Detecta rostros en una imagen dada (en bytes).
  ///
  /// Retorna una lista de [Detection] con coordenadas normalizadas [0..1].
  Future<List<Detection>> detectFaces(Uint8List imageBytes) async {
    if (!_initialized || _interpreter == null || _anchors == null) {
      throw Exception('FaceDetectorService no está inicializado');
    }

    // 1) Decodificar la imagen en memoria
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      // Si no se pudo decodificar como imagen
      return [];
    }

    // 2) Redimensionar a 192x192
    final resized = img.copyResize(
      decodedImage,
      width: 192,
      height: 192,
    );

    // 3) Crear el tensor 4D de entrada: [1,192,192,3]
    //    con normalización en [-1..1]
    final input4D = List.generate(
      1,
      (_) => List.generate(
        192,
        (_) => List.generate(
          192,
          (_) => List<double>.filled(3, 0.0),
        ),
      ),
    );

    for (int h = 0; h < 192; h++) {
      for (int w = 0; w < 192; w++) {
        // Obtén el pixel
        final pixel = resized.getPixel(w, h);
        // El pixel es un int ARGB en package:image
        // Extraer canales:
        final r = pixel.r;
        final g = pixel.g; 
        final b = pixel.b;

        // Normalizar en [-1..1]
        input4D[0][h][w][0] = (r / 127.5) - 1.0;
        input4D[0][h][w][1] = (g / 127.5) - 1.0;
        input4D[0][h][w][2] = (b / 127.5) - 1.0;
      }
    }

    // Preparar buffers de salida con el número correcto de cajas
    var outputArray1 = List.generate(
      1,
      (_) => List.generate(NUM_BOXES, (_) => List<double>.filled(16, 0.0)),
    );
    var outputArray2 = List.generate(
      1,
      (_) => List.generate(NUM_BOXES, (_) => List<double>.filled(1, 0.0)),
    );
    final outputs = {
      0: outputArray1,
      1: outputArray2,
    };

    // Ejecutar inferencia
    _interpreter!.runForMultipleInputs([input4D], outputs);

    // Post-procesar con los parámetros del modelo
    final detections = decodeFullRange(
      boxesRaw: outputArray1,
      scoresRaw: outputArray2,
      anchors: _anchors!,
      scoreThreshold: MIN_SCORE_THRESH,
      iouThreshold: 0.3,
    );

    return detections;
  }
}
