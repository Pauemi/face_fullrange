import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

// Importa tu servicio de detección facial
import 'package:facedetection_blazefull/services/face_detector.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:csv/csv.dart';

const List<String> SUPPORTED_FORMATS = ['jpg', 'jpeg', 'png'];
const int MIN_WIDTH = 100;
const int MIN_HEIGHT = 100;
const int MAX_WIDTH = 2000;
const int MAX_HEIGHT = 2000;

/// Clase para almacenar las anotaciones de WiderFace
class WiderFaceAnnotation {
  final String imagePath;
  final List<Map<String, double>> boxes;

  WiderFaceAnnotation({
    required this.imagePath,
    required this.boxes,
  });
}

/// Clase para realizar evaluaciones de detección facial
class FaceDetectionEvaluator {
  final FaceDetectorService _detector;
  final String _datasetPath;
  final String _annotationsPath;
  final String _outputPath;

  // Mapa que guarda las anotaciones por imagen
  final Map<String, WiderFaceAnnotation> _annotations = {};

  // Para llevar estadísticas de validaciones
  int totalValid = 0;
  int totalInvalid = 0;
  final List<String> _failedImages = [];

  FaceDetectionEvaluator({
    required FaceDetectorService detector,
    required String datasetPath,
    required String annotationsPath,
    required String outputPath,
  })  : _datasetPath = datasetPath,
        _annotationsPath = annotationsPath,
        _outputPath = outputPath,
        _detector = detector; // Usar el detector que llega por parámetro

  /// Inicializa el servicio y carga las anotaciones
  Future<void> init() async {
    print('🚀 Iniciando evaluador de detección facial...');
    print('📁 Rutas configuradas:');
    print('   - Dataset: $_datasetPath');
    print('   - Anotaciones: $_annotationsPath');
    print('   - Resultados: $_outputPath');

    // Crear directorio de resultados si no existe
    final resultsDir = Directory(_outputPath);
    if (!await resultsDir.exists()) {
      print('📁 Creando directorio de resultados...');
      await resultsDir.create(recursive: true);
    }

    print('⚙️ Inicializando detector...');
    await _detector.init();
    print('✅ Detector inicializado');

    // Cargar anotaciones
    await _loadAnnotations();
  }

  /// Carga las anotaciones de WiderFace desde un archivo de texto
  Future<void> _loadAnnotations() async {
    print('📑 Cargando anotaciones...');
    try {
      print('   📂 Intentando cargar anotaciones como asset...');
      final content = await rootBundle.loadString(_annotationsPath);
      print('   ✅ Archivo cargado');
      print('   📄 Tamaño del contenido: ${content.length} bytes');

      final lines = content.split('\n');
      print('   ✓ Total de líneas: ${lines.length}');

      int i = 0;
      while (i < lines.length) {
        final imagePath = lines[i++].trim();
        if (imagePath.isEmpty || imagePath.startsWith('#')) continue;

        final numFaces = int.parse(lines[i++].trim());
        final boxes = <Map<String, double>>[];

        for (int j = 0; j < numFaces; j++) {
          final parts = lines[i++]
              .trim()
              .split(RegExp(r'\s+'))
              .map((e) => double.parse(e))
              .toList();

          // En WiderFace: x1, y1, w, h, (otros)
          // Nos quedamos con x, y, width, height
          boxes.add({
            'x': parts[0],
            'y': parts[1],
            'width': parts[2],
            'height': parts[3],
          });
        }

        _annotations[imagePath] =
            WiderFaceAnnotation(imagePath: imagePath, boxes: boxes);
      }

      print('✅ Anotaciones cargadas: ${_annotations.length} imágenes');
    } catch (e) {
      print('❌ Error cargando anotaciones: $e');
      rethrow;
    }
  }

  /// Verifica si el formato de la imagen es soportado.
  bool isSupportedFormat(String imagePath) {
    final extension =
        path.extension(imagePath).toLowerCase().replaceAll('.', '');
    return SUPPORTED_FORMATS.contains(extension);
  }

  /// Verifica si las dimensiones de la imagen están dentro de los límites permitidos.
  bool isValidSize(int width, int height) {
    return width >= MIN_WIDTH &&
        height >= MIN_HEIGHT &&
        width <= MAX_WIDTH &&
        height <= MAX_HEIGHT;
  }

  /// Verifica si la imagen no está corrupta intentando decodificarla.
  Future<bool> isImageCorrupted(Uint8List bytes) async {
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (result) => completer.complete(result));
      final decodedImage = await completer.future;
      return decodedImage.width > 0 && decodedImage.height > 0;
    } catch (e) {
      return false;
    }
  }

  /// Evalúa una imagen específica y retorna un mapa con resultados y métricas
  Future<Map<String, dynamic>> evaluateImage(String imagePath) async {
    try {
      print('\n📸 Evaluando imagen: $imagePath');
      final annotation = _annotations[imagePath];
      final groundTruth = annotation?.boxes ?? [];

      // Construir la ruta del asset
      final assetPath = '$_datasetPath$imagePath';
      print('   📂 Cargando imagen desde asset: $assetPath');

      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      print('   ✅ Imagen cargada como asset: ${bytes.length} bytes');

      // Validaciones
      if (!isSupportedFormat(imagePath)) {
        throw FormatException('Formato de imagen no soportado.');
      }
      if (!await isImageCorrupted(bytes)) {
        throw Exception('Imagen está corrupta o no se puede decodificar.');
      }

      // Decodificar imagen para obtener dimensiones
      final imageCompleter = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (result) => imageCompleter.complete(result));
      final image = await imageCompleter.future;
      final imageWidth = image.width;
      final imageHeight = image.height;

      if (!isValidSize(imageWidth, imageHeight)) {
        throw Exception('Dimensiones de la imagen fuera de los límites permitidos.');
      }

      // Realizar detección
      final stopwatch = Stopwatch()..start();
      final detections = await _detector.detectFaces(bytes);
      final processingTime = stopwatch.elapsedMilliseconds;
      stopwatch.stop();

      print('   ✓ Detectados ${detections.length} rostros en ${processingTime}ms');
      print('   ✓ Ground truth: ${groundTruth.length} rostros');

      // Normalizar ground truth para IoU (x, y, width, height) [0..1]
      final normalizedGroundTruth = groundTruth.map((gt) {
        return {
          'x': gt['x']! / imageWidth,
          'y': gt['y']! / imageHeight,
          'width': gt['width']! / imageWidth,
          'height': gt['height']! / imageHeight,
        };
      }).toList();

      // Normalizar detecciones para IoU (misma escala)
      final normalizedDetections = detections.map((d) {
        return {
          'score': d.score,
          'bbox': {
            'x': d.xMin,
            'y': d.yMin,
            'width': d.width,
            'height': d.height,
          }
        };
      }).toList();

      // Calcular métricas por imagen
      final metrics = _computeImageMetrics(normalizedGroundTruth, normalizedDetections);

      return {
        'image_path': imagePath,
        'validation_status': 'Valid',
        'ground_truth': normalizedGroundTruth,
        'detections': normalizedDetections,
        'processing_time_ms': processingTime,
        'metrics': metrics,
      };
    } catch (assetError) {
      print('   ⚠️ Error cargando asset o validando imagen: $assetError');
      // Intentar cargar como archivo local
      final localFile = File(path.join(_datasetPath, imagePath));
      if (await localFile.exists()) {
        try {
          final bytes = await localFile.readAsBytes();
          print('   ✅ Imagen cargada desde archivo local: ${bytes.length} bytes');

          // Validaciones
          if (!isSupportedFormat(imagePath)) {
            throw FormatException('Formato de imagen no soportado.');
          }
          if (!await isImageCorrupted(bytes)) {
            throw Exception('Imagen está corrupta o no se puede decodificar.');
          }

          final imageCompleter = Completer<ui.Image>();
          ui.decodeImageFromList(bytes, (result) => imageCompleter.complete(result));
          final image = await imageCompleter.future;
          final imageWidth = image.width;
          final imageHeight = image.height;

          if (!isValidSize(imageWidth, imageHeight)) {
            throw Exception('Dimensiones de la imagen fuera de los límites permitidos.');
          }

          final annotation = _annotations[imagePath];
          final groundTruth = annotation?.boxes ?? [];

          // Realizar detección (sin cronometrar o tú decides)
          final detections = await _detector.detectFaces(bytes);
          final processingTime = 0; // O podrías medirlo igual

          print(
              '   ✓ Detectados ${detections.length} rostros en ${processingTime}ms');
          print('   ✓ Ground truth: ${groundTruth.length} rostros');

          // Normalizar
          final normalizedGroundTruth = groundTruth.map((gt) {
            return {
              'x': gt['x']! / imageWidth,
              'y': gt['y']! / imageHeight,
              'width': gt['width']! / imageWidth,
              'height': gt['height']! / imageHeight,
            };
          }).toList();

          final normalizedDetections = detections.map((d) {
            return {
              'score': d.score,
              'bbox': {
                'x': d.xMin,
                'y': d.yMin,
                'width': d.width,
                'height': d.height,
              }
            };
          }).toList();

          // Calcular métricas
          final metrics = _computeImageMetrics(normalizedGroundTruth, normalizedDetections);

          return {
            'image_path': imagePath,
            'validation_status': 'Valid',
            'ground_truth': normalizedGroundTruth,
            'detections': normalizedDetections,
            'processing_time_ms': processingTime,
            'metrics': metrics,
          };
        } catch (localError) {
          print('   ❌ Error al cargar desde archivo local: $localError');
          _failedImages.add(imagePath);
          throw Exception('Invalid: $localError');
        }
      } else {
        _failedImages.add(imagePath);
        throw Exception('No se pudo cargar la imagen ni como asset ni como archivo local.');
      }
    } 
  }

  /// Función para calcular las métricas de detección por imagen (IoU >= 0.5)
  Map<String, dynamic> _computeImageMetrics(
    List<Map<String, double>> groundTruth,
    List<Map<String, dynamic>> detections,
  ) {
    // Si no hay ground truth ni detecciones, devolvemos métricas vacías
    if (groundTruth.isEmpty && detections.isEmpty) {
      return {
        'true_positives': 0,
        'false_positives': 0,
        'false_negatives': 0,
        'true_negatives': 0,
        'precision': 0.0,
        'recall': 0.0,
        'specificity': 0.0,
        'f1_score': 0.0,
        'ious': [],
        'average_iou': 0.0,
      };
    }

    final matchedGT = List<bool>.filled(groundTruth.length, false);
    int tp = 0;
    int fp = 0;
    final List<double> iouList = [];

    for (final det in detections) {
      // Para cada detección, buscamos la mejor coincidencia IoU en las ground truth
      double bestIoU = 0.0;
      int bestIndex = -1;

      for (int i = 0; i < groundTruth.length; i++) {
        if (matchedGT[i]) continue; // si ya se usó esa GT en otro match
        final iou = _calculateIoU(det['bbox'], groundTruth[i]);
        if (iou > bestIoU) {
          bestIoU = iou;
          bestIndex = i;
        }
      }

      // Revisamos si la mejor coincidencia es >= 0.5
      if (bestIoU >= 0.5 && bestIndex >= 0) {
        tp++;
        matchedGT[bestIndex] = true;
        iouList.add(bestIoU);
      } else {
        // No matcheó con ninguna ground truth
        fp++;
      }
    }

    // Las ground truth que quedaron sin matchear son falsos negativos
    final fn = matchedGT.where((m) => !m).length;

    // Para object detection, típicamente TN se omite o se define distinto;
    // aquí lo dejaremos en 0 para cada imagen.
    int tn = 0;

    // Cálculo de métricas clásicas
    final precision = (tp + fp) > 0 ? tp / (tp + fp) : 0.0;
    final recall = (tp + fn) > 0 ? tp / (tp + fn) : 0.0;
    // specificity = TN / (TN + FP); en detection no siempre hace sentido
    final specificity = (tn + fp) > 0 ? tn / (tn + fp) : 0.0;
    final f1 = (precision + recall) > 0 ? 2 * (precision * recall) / (precision + recall) : 0.0;

    final avgIoU = iouList.isNotEmpty
        ? iouList.reduce((a, b) => a + b) / iouList.length
        : 0.0;

    return {
      'true_positives': tp,
      'false_positives': fp,
      'false_negatives': fn,
      'true_negatives': tn,
      'precision': precision,
      'recall': recall,
      'specificity': specificity,
      'f1_score': f1,
      'ious': iouList,
      'average_iou': avgIoU,
    };
  }

  /// Calcula el IoU (Intersection Over Union) entre dos cajas normalizadas
  double _calculateIoU(Map<String, dynamic> box1, Map<String, double> box2) {
    final xA = math.max(box1['x'] as double, box2['x'] as double);
    final yA = math.max(box1['y'] as double, box2['y'] as double);
    final xB = math.min(
      (box1['x'] as double) + (box1['width'] as double),
      (box2['x'] as double) + (box2['width'] as double),
    );
    final yB = math.min(
      (box1['y'] as double) + (box1['height'] as double),
      (box2['y'] as double) + (box2['height'] as double),
    );

    if (xB <= xA || yB <= yA) return 0.0; // no solapan

    final intersection = (xB - xA) * (yB - yA);
    final area1 = (box1['width'] as double) * (box1['height'] as double);
    final area2 = (box2['width'] as double) * (box2['height'] as double);
    final union = area1 + area2 - intersection;

    if (union <= 0) return 0.0;
    return intersection / union;
  }

  /// Ejecuta la evaluación sobre todas las imágenes anotadas
  Future<void> runEvaluation(
      void Function(String) onProgress, void Function(String) onComplete) async {
    print('\n🏃 Iniciando evaluación...');
    final results = <Map<String, dynamic>>[];
    int processed = 0;
    int failed = 0;
    final totalImages = _annotations.length;

    print('📊 Total de imágenes a procesar: $totalImages');

    for (final imagePath in _annotations.keys) {
      try {
        final result = await evaluateImage(imagePath);
        results.add(result);
        processed++;

        if (result['validation_status'] == 'Valid') {
          totalValid++;
        } else {
          totalInvalid++;
          failed++;
          _failedImages.add(imagePath);
        }

        final progress = ((processed / totalImages) * 100).toStringAsFixed(1);
        onProgress(
            'Progreso: $progress% ($processed/$totalImages) - Fallidas: $failed');
      } catch (e) {
        failed++;
        _failedImages.add(imagePath);
        results.add({
          'image_path': imagePath,
          'validation_status': 'Failed',
          'error': e.toString()
        });
        print('❌ Error procesando $imagePath: $e');
      }
    }
    print('CSV guardado en $_outputPath');
    print('\n📊 Resumen:');
    print('- Imágenes procesadas: $processed');
    print('- Imágenes fallidas: $failed');
    print('- Imágenes válidas: $totalValid');
    print('- Imágenes inválidas: $totalInvalid');

    try {
      // Crear directorio de salida si no existe
    final outputDir = Directory(_outputPath);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
      print('📁 Creando directorio de salida: ${outputDir.absolute.path}');
    }
    } catch (e) {
      print('❌ Error creando directorio de salida: $e');
    }
    
    
    // Generar archivo CSV con marca de tiempo
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final csvPath = path.join(_outputPath, 'evaluation_results_$timestamp.csv');

    try {
          await _writeResultsToCSV(csvPath, results);
          print('\n💾 Archivo CSV guardado en:');
          print(File(csvPath).absolute.path);
    } catch (e) {
      print('❌ Error guardando CSV: $e');
    }

    onComplete('✅ Evaluación completada. Resultados guardados en: $csvPath');
  }

  /// Escribe los resultados por imagen en un CSV
  Future<void> _writeResultsToCSV(
      String outputPath, List<Map<String, dynamic>> results) async {
    final csvFile = File(outputPath);
    final List<List<dynamic>> rows = [];

    // Cabecera con todas las columnas requeridas
    rows.add([
      'image_path',
      'ground_truth',
      'detected',
      'average_iou',
      'true_pos',
      'false_pos',
      'false_neg',
      'true_neg',
      'precision',
      'recall',
      'specificity',
      'f1_score',
      'processing_time_ms'
    ]);

    for (final result in results) {
      if (result['validation_status'] == 'Valid') {
        final metrics = result['metrics'] as Map<String, dynamic>;
        final gtCount = (result['ground_truth'] as List).length;
        final detCount = (result['detections'] as List).length;
        final avgIoU = metrics['average_iou'] as double;

        rows.add([
          result['image_path'],
          gtCount,
          detCount,
          avgIoU.toStringAsFixed(3),          // IoU promedio
          metrics['true_positives'],
          metrics['false_positives'],
          metrics['false_negatives'],
          metrics['true_negatives'],
          (metrics['precision'] as double).toStringAsFixed(3),
          (metrics['recall'] as double).toStringAsFixed(3),
          (metrics['specificity'] as double).toStringAsFixed(3),
          (metrics['f1_score'] as double).toStringAsFixed(3),
          result['processing_time_ms'] ?? 0
        ]);
      } else {
        // Imagen inválida
        rows.add([
          result['image_path'],
          0, // ground truth
          0, // detected
          0.0, // avgIou
          0, // TP
          0, // FP
          0, // FN
          0, // TN
          0.0, // precision
          0.0, // recall
          0.0, // specificity
          0.0, // f1
          0 // tiempo
        ]);
      }
    }

    final csvData = const ListToCsvConverter().convert(rows);
    await csvFile.writeAsString(csvData);
  }
}
