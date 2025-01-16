import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:facedetection_blazefull/services/face_detector.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class WiderFaceAnnotation {
  final String imagePath;
  final List<Map<String, double>> boxes;

  WiderFaceAnnotation({
    required this.imagePath,
    required this.boxes,
  });
}

class FaceDetectorTest {
  final FaceDetectorService _detector;
  final String _datasetPath;
  final String _annotationsPath;
  final String _outputPath;
  final Map<String, WiderFaceAnnotation> _annotations = {};

  FaceDetectorTest({
    required String datasetPath,
    required String annotationsPath,
    required String outputPath,
  })  : _datasetPath = datasetPath,
        _annotationsPath = annotationsPath,
        _outputPath = outputPath,
        _detector = FaceDetectorService();

  Future<void> init() async {
    print('🚀 Iniciando test de detección facial...');
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

  Future<void> _loadAnnotations() async {
    print('📑 Cargando anotaciones...');
    try {
      print('   📂 Intentando cargar anotaciones como asset...');
      final content = await rootBundle
          .loadString('assets/wider_face_val_bbx_gt.txt');
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
          final parts =
              lines[i++].trim().split(' ').map((e) => double.parse(e)).toList();
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

  Future<Map<String, dynamic>> evaluateImage(String imagePath) async {
    try {
      print('\n📸 Evaluando imagen: $imagePath');

      // Construir la ruta del asset
      final assetPath = 'assets/images/$imagePath';
      print('   📂 Cargando imagen desde asset: $assetPath');

      try {
        final stopwatch = Stopwatch()..start(); // Iniciar medición de tiempo

        // Cargar la imagen como asset
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        print('   ✅ Imagen cargada: ${bytes.length} bytes');

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

        print('   Decodificando dimensiones de imagen...');
        final completer = Completer<ui.Image>();
        ui.decodeImageFromList(bytes, (result) => completer.complete(result));
        final image = await completer.future;
        print('   ✓ Dimensiones: ${image.width}x${image.height}');

        // Obtener dimensiones de la imagen para normalización
        final imageWidth = image.width.toDouble();
        final imageHeight = image.height.toDouble();

        return {
          'image_path': imagePath,
          'image_size': {
            'width': imageWidth,
            'height': imageHeight,
          },
          'ground_truth': groundTruth
              .map((box) => {
                    'x': box['x']! / imageWidth,
                    'y': box['y']! / imageHeight,
                    'width': box['width']! / imageWidth,
                    'height': box['height']! / imageHeight,
                  })
              .toList(),
          'detections': detections
              .map((d) => {
                    'score': d.score,
                    'bbox': {
                      'x': d.xMin,
                      'y': d.yMin,
                      'width': d.width,
                      'height': d.height,
                    }
                  })
              .toList(),
          'processing_time_ms': processingTime, // Agregar tiempo al resultado
        };
      } catch (e) {
        print('   ⚠️ Error cargando asset: $e');
        // Intentar cargar como archivo local
        final file = File(path.join(_datasetPath, imagePath));
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          print('   ✅ Imagen cargada desde archivo: ${bytes.length} bytes');

          print('   Ejecutando detección facial...');
          final detections = await _detector.detectFaces(bytes);
          final annotation = _annotations[imagePath];
          final groundTruth = annotation?.boxes ?? [];

          final completer = Completer<ui.Image>();
          ui.decodeImageFromList(bytes, (result) => completer.complete(result));
          final image = await completer.future;

          final imageWidth = image.width.toDouble();
          final imageHeight = image.height.toDouble();

          return {
            'image_path': imagePath,
            'image_size': {
              'width': imageWidth,
              'height': imageHeight,
            },
            'ground_truth': groundTruth
                .map((box) => {
                      'x': box['x']! / imageWidth,
                      'y': box['y']! / imageHeight,
                      'width': box['width']! / imageWidth,
                      'height': box['height']! / imageHeight,
                    })
                .toList(),
            'detections': detections
                .map((d) => {
                      'score': d.score,
                      'bbox': {
                        'x': d.xMin,
                        'y': d.yMin,
                        'width': d.width,
                        'height': d.height,
                      }
                    })
                .toList(),
          };
        } else {
          throw Exception(
              'No se pudo cargar la imagen ni como asset ni como archivo');
        }
      }
    } catch (e) {
      print('   ❌ Error cargando imagen: $e');
      rethrow;
    }
  }

  Future<void> runEvaluation() async {
    print('\n🏃 Iniciando evaluación...');
    final results = <Map<String, dynamic>>[];
    int processed = 0;
    int failed = 0;

    try {
      final totalImages = _annotations.length;
      print('📊 Total de imágenes a procesar: $totalImages');

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final csvFile = File(path.join(_outputPath, 'results_$timestamp.csv'));
      final csvBuffer = StringBuffer();

      // Agregar encabezado con más métricas
      csvBuffer.writeln(
          'image_path,true_positives,false_positives,false_negatives,precision,recall,f1_score,processing_time_ms,ground_truth_boxes,detected_boxes,ious,average_iou');

      for (final imagePath in _annotations.keys) {
        try {
          final result = await evaluateImage(imagePath);
          results.add(result);

          final groundTruthCount = (result['ground_truth'] as List).length;
          final detectionsCount = (result['detections'] as List).length;
          final truePositives = _countTruePositives(
            result['ground_truth'] as List,
            result['detections'] as List,
          );
          final falsePositives = detectionsCount - truePositives;
          final falseNegatives = groundTruthCount - truePositives;

          final trueNegatives = 0; // Solo relevante si hay imágenes sin rostros
          final precision =
              detectionsCount == 0 ? 0 : truePositives / detectionsCount;
          final recall =
              groundTruthCount == 0 ? 0 : truePositives / groundTruthCount;
          final specificity = trueNegatives == 0
              ? 0
              : trueNegatives / (trueNegatives + falsePositives);
          final fpr = 1 - specificity;
          final f1Score = (precision + recall == 0)
              ? 0
              : (2 * precision * recall) / (precision + recall);
          final processingTime = result['processing_time_ms'] ?? 0;

          // Calcular IoU promedio para la imagen
          double averageIoU = 0.0;
          int validIoUs = 0;

          for (final detection in result['detections'] as List) {
            double maxIoU = 0.0;
            for (final gt in result['ground_truth'] as List) {
              final iou = _calculateIoU(detection['bbox'], gt);
              if (iou > maxIoU) maxIoU = iou;
            }
            if (maxIoU > 0) {
              averageIoU += maxIoU;
              validIoUs++;
            }
          }

          final finalAverageIoU = validIoUs > 0 ? averageIoU / validIoUs : 0.0;

          // Obtener solo el número de cajas
          final groundTruthStr =
              (result['ground_truth'] as List).length.toString();
          final detectionsStr =
              (result['detections'] as List).length.toString();
          final iousStr = (result['detections'] as List).map((d) {
            double maxIoU = 0.0;
            for (final gt in result['ground_truth'] as List) {
              final iou = _calculateIoU(d['bbox'], gt);
              if (iou > maxIoU) maxIoU = iou;
            }
            return maxIoU.toStringAsFixed(3);
          }).join(';');

          // Escribir línea en CSV
          csvBuffer.writeln(
              '$imagePath,$truePositives,$falsePositives,$falseNegatives,${precision.toStringAsFixed(3)},${recall.toStringAsFixed(3)},${f1Score.toStringAsFixed(3)},$processingTime,$groundTruthStr,$detectionsStr,"$iousStr",${finalAverageIoU.toStringAsFixed(3)}');

          processed++;
          print('✅ Procesada: $imagePath');

          if (processed % 10 == 0) {
            await csvFile.writeAsString(csvBuffer.toString());
            print('💾 CSV actualizado: ${csvFile.path}');
          }
        } catch (e) {
          print('❌ Error en imagen $imagePath: $e');
          failed++;
          continue;
        }
      }

      // Agregar métricas finales al CSV
      final metrics = _calculateMetrics(results);
      csvBuffer.writeln('\nMétricas Finales');
      csvBuffer.writeln('Total imágenes,${processed}');
      csvBuffer.writeln('Exitosas,${processed - failed}');
      csvBuffer.writeln('Fallidas,$failed');
      csvBuffer.writeln(
          'Precisión promedio,${metrics['average_precision']?.toStringAsFixed(3)}');
      csvBuffer.writeln(
          'Recall promedio,${metrics['average_recall']?.toStringAsFixed(3)}');
      csvBuffer.writeln(
          'F1 Score promedio,${metrics['average_f1_score']?.toStringAsFixed(3)}');

      await csvFile.writeAsString(csvBuffer.toString());
      print('💾 CSV final guardado en: ${csvFile.path}');

      print('''
📊 Evaluación completada:
   - Total procesadas: $processed/$totalImages
   - Fallidas: $failed
   - Exitosas: ${processed - failed}
   - Precisión promedio: ${metrics['average_precision']?.toStringAsFixed(3)}
   - Recall promedio: ${metrics['average_recall']?.toStringAsFixed(3)}
   - F1 Score promedio: ${metrics['average_f1_score']?.toStringAsFixed(3)}
   ''');

      await _saveResults(results, metrics: metrics);
    } catch (e) {
      print('❌ Error durante la evaluación:');
      print(e);
      print(StackTrace.current);
    }
  }

  Map<String, double> _calculateMetrics(List<Map<String, dynamic>> results) {
    double totalPrecision = 0;
    double totalRecall = 0;
    double totalF1Score = 0;
    int validResults = 0;

    for (final result in results) {
      if (result.containsKey('error')) continue;

      final groundTruth = result['ground_truth'] as List;
      final detections = result['detections'] as List;

      if (groundTruth.isEmpty && detections.isEmpty) continue;

      final truePositives = _countTruePositives(groundTruth, detections);
      final precision =
          detections.isEmpty ? 0 : truePositives / detections.length;
      final recall =
          groundTruth.isEmpty ? 0 : truePositives / groundTruth.length;
      final f1Score = (precision + recall == 0)
          ? 0
          : (2 * precision * recall) / (precision + recall);

      totalPrecision += precision;
      totalRecall += recall;
      totalF1Score += f1Score;
      validResults++;
    }

    return {
      'average_precision': validResults > 0 ? totalPrecision / validResults : 0,
      'average_recall': validResults > 0 ? totalRecall / validResults : 0,
      'average_f1_score': validResults > 0 ? totalF1Score / validResults : 0,
    };
  }

  int _countTruePositives(List<dynamic> groundTruth, List<dynamic> detections) {
    int truePositives = 0;
    final matched = List.filled(groundTruth.length, false);

    for (final detection in detections) {
      final dBox = detection['bbox'];
      var maxIoU = 0.0;
      var maxIdx = -1;

      for (int i = 0; i < groundTruth.length; i++) {
        if (matched[i]) continue;
        final gtBox = groundTruth[i];
        final iou = _calculateIoU(dBox, gtBox);
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

  double _calculateIoU(Map<String, dynamic> box1, Map<String, dynamic> box2) {
    final x1 = math.max(box1['x'] as double, box2['x'] as double);
    final y1 = math.max(box1['y'] as double, box2['y'] as double);
    final x2 = math.min((box1['x'] as double) + (box1['width'] as double),
        (box2['x'] as double) + (box2['width'] as double));
    final y2 = math.min((box1['y'] as double) + (box1['height'] as double),
        (box2['y'] as double) + (box2['height'] as double));

    if (x2 <= x1 || y2 <= y1) return 0.0;

    final intersection = (x2 - x1) * (y2 - y1);
    final area1 = box1['width'] * box1['height'];
    final area2 = box2['width'] * box2['height'];
    final union = area1 + area2 - intersection;

    return intersection / union;
  }

  Future<void> _saveResults(
    List<Map<String, dynamic>> results, {
    String suffix = '',
    Map<String, double>? metrics,
  }) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
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

  Future<void> _saveResultsAsCsv(List<Map<String, dynamic>> results) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'widerface_results_$timestamp.csv';
    final outputFile = File(path.join(_outputPath, fileName));

    // Crear el encabezado del archivo CSV
    final buffer = StringBuffer();
    buffer.writeln(
        'image_path,ground_truth_count,detection_count,tp,fp,fn,precision,recall,processing_time_ms,ground_truth_boxes,detected_boxes,ious');

    for (final result in results) {
      if (result.containsKey('error')) continue;

      final imagePath = result['image_path'];
      final groundTruth = result['ground_truth'] as List;
      final detections = result['detections'] as List;

      final groundTruthStr = groundTruth
          .map((gt) =>
              '(${gt['x'].toStringAsFixed(3)},${gt['y'].toStringAsFixed(3)},${gt['width'].toStringAsFixed(3)},${gt['height'].toStringAsFixed(3)})')
          .join(';');

      final detectionsStr = detections
          .map((d) =>
              '(${d['bbox']['x'].toStringAsFixed(3)},${d['bbox']['y'].toStringAsFixed(3)},${d['bbox']['width'].toStringAsFixed(3)},${d['bbox']['height'].toStringAsFixed(3)})')
          .join(';');

      final ious = <double>[];
      for (final detection in detections) {
        double maxIoU = 0.0;
        for (final gt in groundTruth) {
          final iou = _calculateIoU(detection['bbox'], gt);
          if (iou > maxIoU) maxIoU = iou;
        }
        ious.add(maxIoU);
      }
      final iousStr = ious.map((iou) => iou.toStringAsFixed(3)).join(';');

      final truePositives = _countTruePositives(groundTruth, detections);
      final falsePositives = detections.length - truePositives;
      final falseNegatives = groundTruth.length - truePositives;
      final precision =
          detections.isEmpty ? 0 : truePositives / detections.length;
      final recall =
          groundTruth.isEmpty ? 0 : truePositives / groundTruth.length;
      final processingTime = result['processing_time_ms'] ?? 0;

      // Agregar una fila al CSV
      buffer.writeln(
          '$imagePath,${groundTruth.length},${detections.length},$truePositives,$falsePositives,$falseNegatives,${precision.toStringAsFixed(3)},${recall.toStringAsFixed(3)},$processingTime,"$groundTruthStr","$detectionsStr","$iousStr"');
    }

    // Guardar el archivo CSV
    await outputFile.writeAsString(buffer.toString());
    print('💾 Archivo CSV guardado en: ${outputFile.path}');
  }

  Future<void> runTest() async {
    print('🔍 Iniciando prueba de detección facial...');
    try {
      await runEvaluation();
      print('✅ Prueba de detección facial completada exitosamente.');
    } catch (e) {
      print('❌ Error durante la prueba de detección facial: $e');
    }
  }
}

Future<String> _getResultsDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  final resultsPath = path.join(directory.path, 'test_results');
  await Directory(resultsPath).create(recursive: true);
  return resultsPath;
}

Future<void> requestStoragePermission() async {
  print('📱 Solicitando permisos de almacenamiento...');

  if (Platform.isAndroid) {
    var status = await Permission.manageExternalStorage.status;
    print('   Estado inicial: $status');

    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
      print('   Estado después de solicitud: $status');

      if (!status.isGranted) {
        throw Exception('❌ Se requiere permiso de gestión de almacenamiento.');
      }
    }
    print('✅ Permiso de gestión de almacenamiento otorgado.');
  }
}

Future<String> _getProjectRoot() async {
  // Intentar encontrar la raíz del proyecto buscando el pubspec.yaml
  Directory current = Directory.current;
  while (current.path != current.parent.path) {
    if (await File(path.join(current.path, 'pubspec.yaml')).exists()) {
      print('   📂 Raíz del proyecto encontrada: ${current.path}');
      return current.path;
    }
    current = current.parent;
  }
  throw Exception('No se pudo encontrar la raíz del proyecto');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Face detection evaluation', () async {
    await requestStoragePermission();

    final tester = FaceDetectorTest(
        datasetPath: 'assets/images',
        annotationsPath: 'assets/wider_face_val_bbx_gt.txt',
        outputPath: await _getResultsDirectory());

    await tester.init();
    await tester.runEvaluation();
  });
}
