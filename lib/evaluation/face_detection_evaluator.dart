import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:permission_handler/permission_handler.dart';

// Importa tu servicio de detección facial
import 'package:facedetection_blazefull/services/face_detector.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

// Definición de formatos soportados y límites de tamaño
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
  final Map<String, WiderFaceAnnotation> _annotations = {};

  // Variables globales para métricas
  int totalTP = 0;
  int totalFP = 0;
  int totalFN = 0;
  int totalTN = 0;

  // Variables para métricas de validación
  int totalValid = 0;
  int totalInvalid = 0;
  int get totalImages => _annotations.length;
  final List<String> _failedImages = [];

  // Add CSV headers
  final List<String> csvHeaders = [
    'Image',
    'True_Positives',
    'False_Positives',
    'False_Negatives',
    'True_Negatives',
    'Precision',
    'Recall',
    'F1_Score',
    'Processing_Time_Ms'
  ];

  final Map<String, ImageMetrics> _results = {};

  FaceDetectionEvaluator({
    required FaceDetectorService detector,
    required String datasetPath,
    required String annotationsPath,
    required String outputPath,
  })  : _detector = detector,
        _datasetPath = datasetPath,
        _annotationsPath = annotationsPath,
        _outputPath = outputPath;

Future<bool> _checkPermissions() async {
    try {
      if (Platform.isIOS) {
        final photosStatus = await Permission.photos.status;
        final storageStatus = await Permission.storage.status;

        if (photosStatus.isDenied) {
          final result = await Permission.photos.request();
          if (!result.isGranted) {
            print('❌ Acceso a fotos denegado');
            return false;
          }
        }

        if (storageStatus.isDenied) {
          final result = await Permission.storage.request();
          if (!result.isGranted) {
            print('❌ Acceso a almacenamiento denegado');
            return false;
          }
        }
      } else if (Platform.isAndroid) {
        final storageStatus = await Permission.storage.status;
        if (storageStatus.isDenied) {
          final result = await Permission.storage.request();
          if (!result.isGranted) {
            print('❌ Acceso a almacenamiento denegado');
            return false;
          }
        }
      }
      
      print('✅ Permisos concedidos');
      return true;
    } catch (e) {
      print('❌ Error al verificar permisos: $e');
      return false;
    }
  }

  /// Inicializa el servicio y carga las anotaciones
  Future<void> init() async {
    print("Solicitando permisos necesarios");
    if (!await _checkPermissions()) {
      throw Exception('Permisos necesarios no concedidos');
    }
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
      print('❌ Error cargando anotaciones:');
      print('   $e');
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

  /// Evalúa una imagen específica y retorna las métricas
  Future<Map<String, dynamic>> evaluateImage(String imagePath) async {
    try {
      print('\n📸 Evaluando imagen: $imagePath');

      // Construir la ruta del asset
      final assetPath = '$_datasetPath$imagePath';
      print('   📂 Cargando imagen desde asset: $assetPath');

      try {
        final stopwatch = Stopwatch()..start(); // Iniciar medición de tiempo

        // Cargar la imagen como asset
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        print('   ✅ Imagen cargada: ${bytes.length} bytes');

        // **Inicio de Validaciones**

        // 1. Validación de Formato
        if (!isSupportedFormat(imagePath)) {
          throw FormatException('Formato de imagen no soportado.');
        }
        print('   ✅ Formato de imagen válido.');

        // 2. Validación de Integridad
        bool notCorrupted = await isImageCorrupted(bytes);
        if (!notCorrupted) {
          throw Exception('Imagen está corrupta o no se puede decodificar.');
        }
        print('   ✅ Imagen no está corrupta.');

        // 3. Decodificar dimensiones para Validación de Tamaño
        final completer = Completer<ui.Image>();
        ui.decodeImageFromList(bytes, (result) => completer.complete(result));
        final image = await completer.future;
        final imageWidth = image.width;
        final imageHeight = image.height;
        print('   ✓ Dimensiones de la imagen: ${imageWidth}x${imageHeight}');

        // 4. Validación de Tamaño
        if (!isValidSize(imageWidth, imageHeight)) {
          throw Exception('Dimensiones de la imagen fuera de los límites permitidos.');
        }
        print('   ✅ Tamaño de imagen válido.');

        // **Fin de Validaciones**

        print('   Ejecutando detección facial...');
        final detections = await _detector.detectFaces(bytes);

        final processingTime = stopwatch.elapsedMilliseconds; // Obtener tiempo
        stopwatch.stop();

        print(
            '   ✓ Detectados ${detections.length} rostros en ${processingTime}ms');

        print('   Obteniendo ground truth...');
        final annotation = _annotations[imagePath];
        final groundTruth = annotation?.boxes ?? [];
        print('   ✓ Ground truth: ${groundTruth.length} rostros');

        // Normalizar coordenadas
        final normalizedGroundTruth = groundTruth
            .map((box) => {
                  'x': box['x']! / imageWidth,
                  'y': box['y']! / imageHeight,
                  'width': box['width']! / imageWidth,
                  'height': box['height']! / imageHeight,
                })
            .toList();

        final normalizedDetections = detections
            .map((d) => {
                  'score': d.score,
                  'bbox': {
                    'x': d.xMin,
                    'y': d.yMin,
                    'width': d.width,
                    'height': d.height,
                  }
                })
            .toList();

        return {
          'image_path': imagePath,
          'validation_status': 'Valid',
          'image_size': {
            'width': imageWidth.toDouble(),
            'height': imageHeight.toDouble(),
          },
          'ground_truth': normalizedGroundTruth,
          'detections': normalizedDetections,
          'processing_time_ms': processingTime, // Agregar tiempo al resultado
        };
      } catch (e) {
        print('   ⚠️ Error cargando asset o validando imagen: $e');
        // Intentar cargar como archivo local
        final file = File(path.join(_datasetPath, imagePath));
        if (await file.exists()) {
          // Almacenar la imagen fallida para mostrarla después
          _failedImages.add(imagePath);
          _failedImages.add(imagePath);
          final bytes = await file.readAsBytes();
          print('   ✅ Imagen cargada desde archivo: ${bytes.length} bytes');

          try {
            // **Inicio de Validaciones para la Imagen Cargada desde Archivo**

            // 1. Validación de Formato
            if (!isSupportedFormat(imagePath)) {
              throw FormatException('Formato de imagen no soportado.');
            }
            print('   ✅ Formato de imagen válido.');

            // 2. Validación de Integridad
            bool notCorrupted = await isImageCorrupted(bytes);
            if (!notCorrupted) {
              throw Exception('Imagen está corrupta o no se puede decodificar.');
            }
            print('   ✅ Imagen no está corrupta.');

            // 3. Decodificar dimensiones para Validación de Tamaño
            final completer = Completer<ui.Image>();
            ui.decodeImageFromList(bytes, (result) => completer.complete(result));
            final image = await completer.future;
            final imageWidth = image.width;
            final imageHeight = image.height;
            print('   ✓ Dimensiones de la imagen: ${imageWidth}x${imageHeight}');

            // 4. Validación de Tamaño
            if (!isValidSize(imageWidth, imageHeight)) {
              throw Exception('Dimensiones de la imagen fuera de los límites permitidos.');
            }
            print('   ✅ Tamaño de imagen válido.');

            // **Fin de Validaciones**

            print('   Ejecutando detección facial...');
            final detections = await _detector.detectFaces(bytes);

            final processingTime = 0; // No se mide el tiempo aquí

            print(
                '   ✓ Detectados ${detections.length} rostros en ${processingTime}ms');

            print('   Obteniendo ground truth...');
            final annotation = _annotations[imagePath];
            final groundTruth = annotation?.boxes ?? [];
            print('   ✓ Ground truth: ${groundTruth.length} rostros');

            // Normalizar coordenadas
            final normalizedGroundTruth = groundTruth
                .map((box) => {
                      'x': box['x']! / imageWidth,
                      'y': box['y']! / imageHeight,
                      'width': box['width']! / imageWidth,
                      'height': box['height']! / imageHeight,
                    })
                .toList();

            final normalizedDetections = detections
                .map((d) => {
                      'score': d.score,
                      'bbox': {
                        'x': d.xMin,
                        'y': d.yMin,
                        'width': d.width,
                        'height': d.height,
                      }
                    })
                .toList();

            return {
              'image_path': imagePath,
              'validation_status': 'Valid',
              'image_size': {
                'width': imageWidth.toDouble(),
                'height': imageHeight.toDouble(),
              },
              'ground_truth': normalizedGroundTruth,
              'detections': normalizedDetections,
              'processing_time_ms': processingTime, // Agregar tiempo al resultado
            };
          } catch (e) {
            // Error al cargar desde archivo local
            print('   ❌ Error al cargar desde archivo local: $e');
            throw Exception('Invalid: $e');
          }
        }
      }
      // If we reach here, both asset and file loading attempts failed
      throw Exception('No se pudo cargar la imagen desde asset ni archivo local');
    } catch (e) {
      print('❌ Error evaluando imagen: $e');
      return {
        'image_path': imagePath,
        'validation_status': 'Invalid',
        'error': e.toString(),
      };
    }
  }

  /// Ejecuta la evaluación sobre todas las imágenes anotadas
  Future<void> runEvaluation(
      void Function(String) onProgress, void Function(String) onComplete) async {
    print('\n🏃 Iniciando evaluación...');
    final results = <Map<String, dynamic>>[];
    int processed = 0;
    int failed = 0;

    try {
      final totalImages = _annotations.length;
      print('📊 Total de imágenes a procesar: $totalImages');

      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-');
      final csvFile =
          File(path.join(_outputPath, 'results_$timestamp.csv'));
      final csvBuffer = StringBuffer();

      // Agregar encabezado con todas las métricas y estado de validación
      csvBuffer.writeln(
          'image_path,validation_status,true_positives,false_positives,false_negatives,true_negatives,precision,recall,specificity,fpr,f1_score,processing_time_ms,ground_truth_boxes,detected_boxes,ious,average_iou');

      for (final imagePath in _annotations.keys) {
        try {
          final result = await evaluateImage(imagePath);
          results.add(result);

          final groundTruthCount = (result['ground_truth'] as List).length;
          final detectionsCount = (result['detections'] as List).length;

          // Inicializar métricas por imagen
          int truePositives = 0;
          int falsePositives = 0;
          int falseNegatives = 0;
          int trueNegatives = 0;

          String validationStatus = result['validation_status'] ?? 'Valid';

          if (groundTruthCount > 0) {
            // Imagen con rostros
            truePositives = _countTruePositives(
              result['ground_truth'] as List,
              result['detections'] as List,
            );
            falsePositives = detectionsCount - truePositives;
            falseNegatives = groundTruthCount - truePositives;
          } else {
            // Imagen sin rostros
            trueNegatives = detectionsCount == 0 ? 1 : 0;
            falsePositives = detectionsCount > 0 ? detectionsCount : 0;
          }

          // Actualizar contadores globales
          totalTP += truePositives;
          totalFP += falsePositives;
          totalFN += falseNegatives;
          totalTN += trueNegatives;

          // Calcular métricas por imagen
          double precision = 0.0;
          double recall = 0.0;
          double specificity = 0.0;
          double fpr = 0.0;
          double f1Score = 0.0;

          if (truePositives + falsePositives > 0) {
            precision = truePositives / (truePositives + falsePositives);
          }

          if (truePositives + falseNegatives > 0) {
            recall = truePositives / (truePositives + falseNegatives);
          }

          if (trueNegatives + falsePositives > 0) {
            specificity = trueNegatives / (trueNegatives + falsePositives);
            fpr = 1 - specificity; // FPR = FP / (FP + TN)
          }

          if (precision + recall > 0) {
            f1Score = 2 * (precision * recall) / (precision + recall);
          }

          final processingTime = result['processing_time_ms'] ?? 0;

          // Calcular IoU promedio para la imagen
          double averageIoU = 0.0;
          int validIoUs = 0;

          for (final detection in result['detections'] as List) {
            double maxIoU = 0.0;
            for (final gt in result['ground_truth'] as List) {
              final iou = _calculateIoU(detection['bbox'], gt);
              if (iou > maxIoU) {
                maxIoU = iou;
              }
            }
            if (maxIoU > 0) {
              averageIoU += maxIoU;
              validIoUs++;
            }
          }

          final finalAverageIoU =
              validIoUs > 0 ? averageIoU / validIoUs : 0.0;

          // Obtener solo el número de cajas
          final groundTruthStr =
              (result['ground_truth'] as List).length.toString();
          final detectionsStr =
              (result['detections'] as List).length.toString();
          final iousStr = (result['detections'] as List).map((d) {
            double maxIoU = 0.0;
            for (final gt in result['ground_truth'] as List) {
              final iou = _calculateIoU(d['bbox'], gt);
              if (iou > maxIoU) {
                maxIoU = iou;
              }
            }
            return maxIoU.toStringAsFixed(3);
          }).join(';');

          // Escribir línea en CSV con el estado de validación
          csvBuffer.writeln(
              '$imagePath,$validationStatus,$truePositives,$falsePositives,$falseNegatives,$trueNegatives,${precision.toStringAsFixed(3)},${recall.toStringAsFixed(3)},${specificity.toStringAsFixed(3)},${fpr.toStringAsFixed(3)},${f1Score.toStringAsFixed(3)},$processingTime,$groundTruthStr,$detectionsStr,"$iousStr",${finalAverageIoU.toStringAsFixed(3)}');

          processed++;
          print('✅ Procesada: $imagePath');

          // Notificar progreso
          onProgress('Procesada $processed de $totalImages imágenes.');

          if (processed % 10 == 0) {
            await csvFile.writeAsString(csvBuffer.toString(),
                mode: FileMode.append);
            print('💾 CSV actualizado: ${csvFile.path}');
            csvBuffer.clear(); // Limpiar el buffer después de escribir
          }

          // Actualizar métricas de validación
          totalValid++;
        } catch (e) {
          print('❌ Error en imagen $imagePath: $e');
          failed++;
          totalInvalid++;

          // Registrar la falla en el CSV
          final validationStatus = 'Invalid: $e';
          csvBuffer.writeln(
              '$imagePath,$validationStatus,,,,,,,,,,,,,,'); // Dejar campos vacíos para métricas

          processed++;
          print('📌 Imagen marcada como inválida: $imagePath');

          // Notificar progreso
          onProgress('Procesada $processed de $totalImages imágenes.');
           if (processed % 10 == 0) {
            await csvFile.writeAsString(csvBuffer.toString(),
                mode: FileMode.append);
            print('💾 CSV actualizado: ${csvFile.path}');
            csvBuffer.clear(); // Limpiar el buffer después de escribir
          }

          continue;
        }
      }

      // Agregar métricas finales al CSV
      final metrics = _calculateMetrics();
      csvBuffer.writeln('\nMétricas Finales');
      csvBuffer.writeln('Total imágenes,${processed}');
      csvBuffer.writeln('Validas,${totalValid}');
      csvBuffer.writeln('Invalidas,${totalInvalid}');
      csvBuffer.writeln('Exitosas,${totalValid - failed}');
      csvBuffer.writeln('Fallidas,$failed');
      csvBuffer.writeln(
          'Precisión,${metrics['precision']?.toStringAsFixed(3)}');
      csvBuffer.writeln(
          'Recall,${metrics['recall']?.toStringAsFixed(3)}');
      csvBuffer.writeln(
          'Especificidad,${metrics['specificity']?.toStringAsFixed(3)}');
      csvBuffer.writeln('FPR,${metrics['fpr']?.toStringAsFixed(3)}');
      csvBuffer.writeln(
          'F1 Score,${metrics['f1_score']?.toStringAsFixed(3)}');

      // Escribir las métricas finales en el CSV
      await csvFile.writeAsString(csvBuffer.toString(),
          mode: FileMode.append);
      print('💾 CSV final guardado en: ${csvFile.path}');

      // Guardar los resultados JSON antes de notificar
      await _saveResults(results, metrics: metrics);

      // Notificar finalización
      onComplete('Evaluación completada. Resultados guardados en ${csvFile.path}');

      print('''
📊 Evaluación completada:
   - Total procesadas: $processed/$totalImages
   - Válidas: $totalValid
   - Invalidas: $totalInvalid
   - Fallidas: $failed
   - Exitosas: ${totalValid - failed}
   - Precisión: ${metrics['precision']?.toStringAsFixed(3)}
   - Recall: ${metrics['recall']?.toStringAsFixed(3)}
   - Especificidad: ${metrics['specificity']?.toStringAsFixed(3)}
   - FPR: ${metrics['fpr']?.toStringAsFixed(3)}
   - F1 Score: ${metrics['f1_score']?.toStringAsFixed(3)}
      ''');
    } catch (e) {
      print('❌ Error durante la evaluación:');
      print(e);
      print(StackTrace.current);
      onComplete('Error durante la evaluación: $e');
      // Show list of failed images if any
      if (_failedImages.isNotEmpty) {
        print('\n⚠️ Imágenes fallidas:');
        for (final failedImage in _failedImages) {
          print('   - $failedImage');
        }
      }
    }
  }

  /// Calcula métricas globales a partir de los contadores totales
  Map<String, double> _calculateMetrics() {
    double precision = 0.0;
    double recall = 0.0;
    double specificity = 0.0;
    double fpr = 0.0;
    double f1Score = 0.0;

    if (totalTP + totalFP > 0) {
      precision = totalTP / (totalTP + totalFP);
    }

    if (totalTP + totalFN > 0) {
      recall = totalTP / (totalTP + totalFN);
    }

    if (totalTN + totalFP > 0) {
      specificity = totalTN / (totalTN + totalFP);
      fpr = 1 - specificity; // FPR = FP / (FP + TN)
    }

    if (precision + recall > 0) {
      f1Score = 2 * (precision * recall) / (precision + recall);
    }

    return {
      'precision': precision,
      'recall': recall,
      'specificity': specificity,
      'fpr': fpr,
      'f1_score': f1Score,
    };
  }

  /// Cuenta los verdaderos positivos comparando ground truth con detecciones
  int _countTruePositives(
      List<dynamic> groundTruth, List<dynamic> detections) {
    int truePositives = 0;
    final matched = List.filled(groundTruth.length, false);

    for (final detection in detections) {
      double maxIoU = 0.0;
      int maxIdx = -1;

      for (int i = 0; i < groundTruth.length; i++) {
        if (matched[i]) continue;
        final gtBox = groundTruth[i];
        final iou = _calculateIoU(detection['bbox'], gtBox);
        if (iou > maxIoU) {
          maxIoU = iou;
          maxIdx = i;
        }
      }

      if (maxIoU >= 0.5 && maxIdx >= 0) {
        // IoU threshold = 0.5
        matched[maxIdx] = true;
        truePositives++;
      }
    }

    return truePositives;
  }

  /// Calcula el Intersection over Union (IoU) entre dos cajas
  double _calculateIoU(Map<String, dynamic> box1, Map<String, dynamic> box2) {
    final xA = math.max(box1['x'] as double, box2['x'] as double);
    final yA = math.max(box1['y'] as double, box2['y'] as double);
    final xB = math.min(
        (box1['x'] as double) + (box1['width'] as double),
        (box2['x'] as double) + (box2['width'] as double));
    final yB = math.min(
        (box1['y'] as double) + (box1['height'] as double),
        (box2['y'] as double) + (box2['height'] as double));

    if (xB <= xA || yB <= yA) return 0.0;

    final intersection = (xB - xA) * (yB - yA);
    final area1 = (box1['width'] as double) * (box1['height'] as double);
    final area2 = (box2['width'] as double) * (box2['height'] as double);
    final union = area1 + area2 - intersection;

    return intersection / union;
  }

  /// Guarda los resultados en un archivo JSON
  Future<void> _saveResults(
    List<Map<String, dynamic>> results, {
    String suffix = '',
    Map<String, double>? metrics,
  }) async {
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'widerface_results${suffix}_$timestamp.json';
    final outputFile = File(path.join(_outputPath, fileName));

    final jsonResults = {
      'timestamp': timestamp,
      'total_images': results.length,
      'model_info': {
        'input_size': 192,
        'score_threshold': 0.5,
        'iou_threshold': 0.5,
      },
      if (metrics != null) 'metrics': metrics,
      'results': results.map((result) {
        // Calcular IoU para cada detección con su ground truth correspondiente
        final detections = result['detections'] as List;
        final groundTruth = result['ground_truth'] as List;
        final ious = <Map<String, dynamic>>[];

        for (final detection in detections) {
          double maxIoU = 0.0;
          Map<String, dynamic>? matchedGT;

          for (final gt in groundTruth) {
            final iou = _calculateIoU(detection['bbox'], gt);
            if (iou > maxIoU) {
              maxIoU = iou;
              matchedGT = gt;
            }
          }

          ious.add({
            'detection': detection,
            'matched_ground_truth': matchedGT,
            'iou': maxIoU,
          });
        }

        return {
          ...result,
          'detailed_matches': ious,
        };
      }).toList(),
    };

    await outputFile
        .writeAsString(JsonEncoder.withIndent('  ').convert(jsonResults));

    print('💾 Resultados guardados en: ${outputFile.path}');
  }

  Future<void> saveResults() async {
    final File csvFile = File(path.join(_outputPath, 'evaluation_results.csv'));
    final IOSink sink = csvFile.openWrite();
    
    // Write headers
    sink.writeln(csvHeaders.join(','));
    
    // Write data rows
    for (var entry in _results.entries) {
      final metrics = entry.value;
      final row = [
        entry.key,                    // Image name
        metrics.truePositives,        // TP
        metrics.falsePositives,       // FP
        metrics.falseNegatives,       // FN
        metrics.trueNegatives,        // TN
        metrics.precision.toStringAsFixed(4),    // Precision
        metrics.recall.toStringAsFixed(4),       // Recall
        metrics.f1Score.toStringAsFixed(4),      // F1
        metrics.processingTime.toStringAsFixed(2) // Time
      ];
      
      sink.writeln(row.join(','));
    }
    
    await sink.flush();
    await sink.close();
  }

}

// Add class to store metrics
class ImageMetrics {
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final int trueNegatives;
  final double precision;
  final double recall;
  final double f1Score;
  final double processingTime;

  ImageMetrics({
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.trueNegatives,
    required this.precision,
    required this.recall,
    required this.f1Score,
    required this.processingTime,
  });
}