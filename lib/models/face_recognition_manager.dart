import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:path/path.dart' as path;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:thiea_app/models/faceData.dart';
import 'package:thiea_app/models/photoMetadata.dart';

class FaceRecognitionManager {
  // Initialize the face detector with desired options.
  static final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.1, // Detect faces at varying distances
    ),
  );

  /// A map to store all detected faces with their IDs as keys.
  static Map<String, FaceData> allFaces = {};

  /// Detects faces in the given image and returns a list of FaceData.
  static Future<List<FaceData>> detectFaces(String imagePath) async {
    try {
      final File imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        print('Image file does not exist: $imagePath');
        return [];
      }

      final InputImage inputImage = InputImage.fromFilePath(imagePath);
      final List<Face> faces = await _faceDetector.processImage(inputImage);
      print('Detected ${faces.length} faces in $imagePath');

      return await Future.wait(faces.map((face) async {
        final String id = await _generateFaceId(face, imagePath);

        // Collect all available landmarks
        Map<FaceLandmarkType, Point<int>> landmarks = {};
        for (final entry in FaceLandmarkType.values) {
          final landmark = face.landmarks[entry];
          if (landmark != null) {
            landmarks[entry] = Point(
              landmark.position.x.toInt(),
              landmark.position.y.toInt(),
            );
          }
        }

        // Debug information
        print('Face ID: $id');
        print('Landmarks found: ${landmarks.length}');
        print('Smiling probability: ${face.smilingProbability}');
        print('Head angles: X=${face.headEulerAngleX}, Y=${face.headEulerAngleY}, Z=${face.headEulerAngleZ}');

        return FaceData(
          id: id,
          boundingBox: face.boundingBox,
          landmarks: landmarks,
          headAngle: {
            'x': face.headEulerAngleX ?? 0.0,
            'y': face.headEulerAngleY ?? 0.0,
            'z': face.headEulerAngleZ ?? 0.0,
          },
          smiling: face.smilingProbability ?? 0.0,
          trackingId: face.trackingId,
        );
      }));
    } catch (e, stackTrace) {
      print('Error in face detection: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Clusters faces based on similarity and returns a map of cluster IDs to face IDs.
  static Map<String, List<String>> clusterFaces(List<PhotoMetadata> allPhotos) {
    Map<String, List<String>> clusters = {};
    allFaces = {}; // Reset the map before processing

    // First pass: Collect all faces
    for (var photo in allPhotos) {
      for (var face in photo.faces) {
        allFaces[face.id] = face;
      }
    }

    // Initialize clusters with tracking IDs
    Map<int?, List<String>> trackingClusters = {};
    for (var face in allFaces.values) {
      if (face.trackingId != null) {
        trackingClusters.putIfAbsent(face.trackingId, () => []).add(face.id);
      }
    }

    // Merge tracking clusters based on similarity
    List<List<String>> mergedClusters = [];
    trackingClusters.values.forEach((trackingCluster) {
      bool addedToExisting = false;

      for (var existingCluster in mergedClusters) {
        if (_shouldMergeClusters(trackingCluster, existingCluster, allFaces)) {
          existingCluster.addAll(trackingCluster);
          addedToExisting = true;
          break;
        }
      }

      if (!addedToExisting) {
        mergedClusters.add([...trackingCluster]);
      }
    });

    // Handle faces without tracking IDs
    List<String> unclusteredFaceIds = allFaces.keys
        .where((id) => !mergedClusters.any((cluster) => cluster.contains(id)))
        .toList();

    for (var faceId in unclusteredFaceIds) {
      var face = allFaces[faceId]!;
      bool addedToExisting = false;

      for (var cluster in mergedClusters) {
        if (_shouldAddToCluster(face, cluster, allFaces)) {
          cluster.add(faceId);
          addedToExisting = true;
          break;
        }
      }

      if (!addedToExisting) {
        mergedClusters.add([faceId]);
      }
    }

    // Assign unique cluster IDs and populate the clusters map
    for (var i = 0; i < mergedClusters.length; i++) {
      clusters['person_$i'] = mergedClusters[i];
    }

    // Debugging: Print clustering results
    print('\nClustering Results:');
    clusters.forEach((clusterId, faceIds) {
      print('$clusterId: ${faceIds.length} faces');
      faceIds.forEach((faceId) {
        final face = allFaces[faceId];
        if (face != null) {
          print('  - Face $faceId (Tracking ID: ${face.trackingId})');
        } else {
          print('  - Face $faceId not found in allFaces map');
        }
      });
    });

    return clusters;
  }

  /// Determines whether two clusters should be merged based on face similarity.
  static bool _shouldMergeClusters(
      List<String> cluster1,
      List<String> cluster2,
      Map<String, FaceData> allFaces,
      ) {
    int matchCount = 0;
    int comparisons = 0;

    for (var id1 in cluster1) {
      for (var id2 in cluster2) {
        var face1 = allFaces[id1]!;
        var face2 = allFaces[id2]!;
        if (_areFacesSimilar(face1, face2)) {
          matchCount++;
        }
        comparisons++;
      }
    }

    // Require at least 30% of face pairs to match for merging
    return comparisons > 0 && (matchCount / comparisons) >= 0.3;
  }

  /// Determines whether a face should be added to an existing cluster based on similarity.
  static bool _shouldAddToCluster(
      FaceData face,
      List<String> cluster,
      Map<String, FaceData> allFaces,
      ) {
    int matchCount = 0;

    for (var clusteredFaceId in cluster) {
      var clusteredFace = allFaces[clusteredFaceId]!;
      if (_areFacesSimilar(face, clusteredFace)) {
        matchCount++;
      }
    }

    // Require matching with at least 25% of faces in the cluster
    return matchCount >= (cluster.length * 0.25);
  }

  /// Determines whether two faces are similar based on landmarks, size, and angles.
  static bool _areFacesSimilar(FaceData face1, FaceData face2) {
    // Ignore extreme head angles
    if (_hasExtremeHeadAngle(face1) || _hasExtremeHeadAngle(face2)) {
      return false;
    }

    // Calculate various similarity scores
    double landmarkSimilarity = _calculateLandmarkSimilarity(face1.landmarks, face2.landmarks);
    double sizeSimilarity = _calculateSizeSimilarity(face1.boundingBox, face2.boundingBox);
    double angleCompatibility = _calculateAngleCompatibility(face1.headAngle, face2.headAngle);

    // Debugging: Print similarity scores
    print('Comparing faces ${face1.id} and ${face2.id}:');
    print('  Landmark similarity: $landmarkSimilarity');
    print('  Size similarity: $sizeSimilarity');
    print('  Angle compatibility: $angleCompatibility');

    // Define thresholds for similarity
    return landmarkSimilarity > 0.6 &&
        sizeSimilarity > 0.5 &&
        angleCompatibility > 0.7;
  }

  /// Checks if a face has extreme head angles.
  static bool _hasExtremeHeadAngle(FaceData face) {
    const double threshold = 35.0; // Degrees
    return (face.headAngle['y']?.abs() ?? 0) > threshold ||
        (face.headAngle['x']?.abs() ?? 0) > threshold;
  }

  /// Calculates similarity based on facial landmarks.
  static double _calculateLandmarkSimilarity(
      Map<FaceLandmarkType, Point<int>> landmarks1,
      Map<FaceLandmarkType, Point<int>> landmarks2,
      ) {
    if (landmarks1.isEmpty || landmarks2.isEmpty) return 0.0;

    double totalDistance = 0;
    int comparisons = 0;

    // Normalize coordinates based on face size
    var bounds1 = _getLandmarkBounds(landmarks1);
    var bounds2 = _getLandmarkBounds(landmarks2);

    for (var type in FaceLandmarkType.values) {
      final point1 = landmarks1[type];
      final point2 = landmarks2[type];

      if (point1 != null && point2 != null) {
        // Normalize points to 0-1 range
        double x1 = (point1.x - bounds1.left) / bounds1.width;
        double y1 = (point1.y - bounds1.top) / bounds1.height;
        double x2 = (point2.x - bounds2.left) / bounds2.width;
        double y2 = (point2.y - bounds2.top) / bounds2.height;

        double distance = sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2));
        totalDistance += distance;
        comparisons++;
      }
    }

    if (comparisons == 0) return 0.0;
    return 1.0 - (totalDistance / comparisons).clamp(0.0, 1.0);
  }

  /// Calculates the bounding rectangle for facial landmarks.
  static Rect _getLandmarkBounds(Map<FaceLandmarkType, Point<int>> landmarks) {
    var points = landmarks.values.toList();
    if (points.isEmpty) return Rect.zero;

    int minX = points.map((p) => p.x).reduce(min);
    int maxX = points.map((p) => p.x).reduce(max);
    int minY = points.map((p) => p.y).reduce(min);
    int maxY = points.map((p) => p.y).reduce(max);

    return Rect.fromLTWH(
      minX.toDouble(),
      minY.toDouble(),
      (maxX - minX).toDouble(),
      (maxY - minY).toDouble(),
    );
  }

  /// Calculates similarity based on the size of the bounding boxes.
  static double _calculateSizeSimilarity(Rect box1, Rect box2) {
    double area1 = box1.width * box1.height;
    double area2 = box2.width * box2.height;
    double smallerArea = min(area1, area2);
    double largerArea = max(area1, area2);
    return smallerArea / largerArea;
  }

  /// Calculates compatibility based on head angles.
  static double _calculateAngleCompatibility(
      Map<String, double> angle1,
      Map<String, double> angle2,
      ) {
    double maxAngleDiff = 0.0;

    for (var axis in ['x', 'y', 'z']) {
      double diff = (angle1[axis] ?? 0.0) - (angle2[axis] ?? 0.0);
      maxAngleDiff = max(maxAngleDiff, diff.abs());
    }

    return 1.0 - (maxAngleDiff / 180.0).clamp(0.0, 1.0);
  }

  /// Generates a unique ID for a face based on image path and tracking ID.
  static Future<String> _generateFaceId(Face face, String imagePath) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    final trackingComponent = face.trackingId ?? random;
    return '${path.basename(imagePath)}_${timestamp}_$trackingComponent';
  }
}
