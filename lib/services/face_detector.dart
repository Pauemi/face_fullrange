// lib/services/face_detector.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:facedetection_blazefull/ml/anchors.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../ml/detection.dart';
import '../ml/post_process.dart';
import '../ml/utilities.dart'; // Importa las utilidades

const int MODEL_INPUT_SIZE = 192;
const int NUM_BOXES = 2304;
const double MIN_SCORE_THRESH = 0.5; // Ajustado
const double MIN_SUPPRESSION_THRESHOLD = 0.5; // Ajustado

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
      _interpreter =
          await Interpreter.fromAsset('assets/models/face_detection_full_range.tflite');

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
    if (!_initialized) throw Exception('Not initialized');

    // 1. Decode image with proper orientation
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) return [];

    // 2. No need for color space conversion as decodeImage already returns RGB
    final rgbImage = decodedImage;
    
    // 3. Apply image enhancement
    final enhancedImage = _enhanceImage(rgbImage);
    
    // 4. Resize with proper aspect ratio preservation
    final resizedTuple = resizeWithLetterboxing(enhancedImage, 192, 192);
    final resizedImage = resizedTuple.item1;
    final padX = resizedTuple.item2;
    final padY = resizedTuple.item3;

    // 5. Normalize with proper scaling
    final input4D = _prepareInputTensor(resizedImage);

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

    // Logs de salidas crudas
    print('🔍 Salidas crudas - Boxes: ${outputArray1[0].length}, Scores: ${outputArray2[0].length}');
    if (outputArray1[0].isNotEmpty && outputArray1[0][0].isNotEmpty) {
      print('📦 Ejemplo de Box Raw: ${outputArray1[0][0].sublist(0, 4)}');
    }
    if (outputArray2[0].isNotEmpty && outputArray2[0][0].isNotEmpty) {
      print('📈 Ejemplo de Score Raw: ${outputArray2[0][0][0]}');
    }

    // Post-procesar con los parámetros del modelo
    final detections = decodeFullRange(
      boxesRaw: outputArray1,
      scoresRaw: outputArray2,
      anchors: _anchors!,
      scoreThreshold: MIN_SCORE_THRESH,
      iouThreshold: MIN_SUPPRESSION_THRESHOLD,
    );

    // Ajustar las detecciones para remover el letterbox usando padX y padY
    final adjustedDetections = detections.map((detection) {
      // Calcula la escala basado en letterboxing
      double scale = math.min(192 / decodedImage.width, 192 / decodedImage.height);
      double scaledWidth = decodedImage.width * scale;
      double scaledHeight = decodedImage.height * scale;

      // Remover el padding aplicado por letterboxing
      double xMin = (detection.xMin * 192 - padX) / scaledWidth;
      double yMin = (detection.yMin * 192 - padY) / scaledHeight;
      double width = detection.width * 192 / scaledWidth;
      double height = detection.height * 192 / scaledHeight;

      // Asegurarse de que las coordenadas estén en el rango [0,1]
      xMin = xMin.clamp(0.0, 1.0);
      yMin = yMin.clamp(0.0, 1.0);
      width = width.clamp(0.0, 1.0 - xMin);
      height = height.clamp(0.0, 1.0 - yMin);

      return Detection(
        score: detection.score,
        xMin: xMin,
        yMin: yMin,
        width: width,
        height: height,
      );
    }).toList();

    return adjustedDetections;
  }

  img.Image _enhanceImage(img.Image image) {
    // Apply contrast enhancement
    return img.adjustColor(
      image,
      contrast: 1.1,
      brightness: 1.0,
      saturation: 1.0,
    );
  }

  List<List<List<List<double>>>> _prepareInputTensor(img.Image image) {
    final input = List.generate(1, (_) => 
      List.generate(192, (_) => 
        List.generate(192, (_) => 
          List<double>.filled(3, 0.0))));

    for (int y = 0; y < 192; y++) {
      for (int x = 0; x < 192; x++) {
        final pixel = image.getPixel(x, y);
        // Normalize to [-1,1] with proper scaling
        input[0][y][x][0] = ((pixel.r - 127.5) / 127.5);
        input[0][y][x][1] = ((pixel.g - 127.5) / 127.5);
        input[0][y][x][2] = ((pixel.b - 127.5) / 127.5);
      }
    }
    return input;
  }
}
