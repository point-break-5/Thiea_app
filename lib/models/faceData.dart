import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceData {
  final String id;
  final String? name;
  final Rect boundingBox;
  final Map<FaceLandmarkType, Point<int>> landmarks;
  final Map<String, double> headAngle;
  final double smiling;
  final int? trackingId;

  FaceData({
    required this.id,
    this.name,
    required this.boundingBox,
    Map<FaceLandmarkType, Point<int>>? landmarks,
    Map<String, double>? headAngle,
    this.smiling = 0.0,
    this.trackingId,
  }) :
        this.landmarks = landmarks ?? {},
        this.headAngle = headAngle ?? {};

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'boundingBox': {
      'left': boundingBox.left,
      'top': boundingBox.top,
      'width': boundingBox.width,
      'height': boundingBox.height,
    },
    'landmarks': landmarks.map((key, value) =>
        MapEntry(key.index.toString(), {'x': value.x, 'y': value.y})),
    'headAngle': headAngle,
    'smiling': smiling,
    'trackingId': trackingId,
  };

  factory FaceData.fromJson(Map<String, dynamic> json) {
    final box = json['boundingBox'] as Map<String, dynamic>;
    return FaceData(
      id: json['id'] as String,
      name: json['name'] as String?,
      boundingBox: Rect.fromLTWH(
        box['left'] as double,
        box['top'] as double,
        box['width'] as double,
        box['height'] as double,
      ),
      landmarks: (json['landmarks'] as Map<String, dynamic>).map((key, value) {
        final point = value as Map<String, dynamic>;
        return MapEntry(
          FaceLandmarkType.values[int.parse(key)],
          Point(point['x'] as int, point['y'] as int),
        );
      }),
      headAngle: Map<String, double>.from(json['headAngle'] as Map),
      smiling: json['smiling'] as double,
      trackingId: json['trackingId'] as int?,
    );
  }
}