import 'package:thiea_app/models/faceData.dart';
import 'package:thiea_app/models/location.dart';

class PhotoMetadata {
  final String path;
  final DateTime dateTime;
  final Location? location;
  final String? placeName;
  final String? filter;
  final List<FaceData> faces;
  final String? subLocality;

  PhotoMetadata({
    required this.path,
    required this.dateTime,
    this.location,
    this.placeName,
    this.filter,
    this.faces = const [],
    this.subLocality,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'dateTime': dateTime.toIso8601String(),
    'location': location?.toJson(),
    'placeName': placeName,
    'subLocality': subLocality,
    'filter': filter,
    'faces': faces.map((face) => face.toJson()).toList(),
  };

  factory PhotoMetadata.fromJson(Map<String, dynamic> json) {
    return PhotoMetadata(
      path: json['path'] as String,
      dateTime: DateTime.parse(json['dateTime'] as String),
      location: json['location'] != null
          ? Location.fromJson(json['location'] as Map<String, dynamic>)
          : null,
      placeName: json['placeName'] as String?,
      subLocality: json['subLocality'] as String?,
      filter: json['filter'] as String?,
      faces: (json['faces'] as List?)
          ?.map((face) => FaceData.fromJson(face as Map<String, dynamic>))
          .toList() ??
          [],
    );
  }
}


// class PhotoMetadata {
//   final String path;
//   final DateTime dateTime;
//   final Location? location;
//   final String? placeName;
//   final String? filter;
//   final List<FaceData> faces;

//   PhotoMetadata({
//     required this.path,
//     required this.dateTime,
//     this.location,
//     this.placeName,
//     this.filter,
//     this.faces = const [],
//   });

//   Map<String, dynamic> toJson() => {
//     'path': path,
//     'dateTime': dateTime.toIso8601String(),
//     'location': location?.toJson(),
//     'placeName': placeName,
//     'filter': filter,
//     'faces': faces.map((face) => face.toJson()).toList(),
//   };

//   factory PhotoMetadata.fromJson(Map<String, dynamic> json) {
//     return PhotoMetadata(
//       path: json['path'] as String,
//       dateTime: DateTime.parse(json['dateTime'] as String),
//       location: json['location'] != null
//           ? Location.fromJson(json['location'] as Map<String, dynamic>)
//           : null,
//       placeName: json['placeName'] as String?,
//       filter: json['filter'] as String?,
//       faces: (json['faces'] as List?)
//           ?.map((face) => FaceData.fromJson(face as Map<String, dynamic>))
//           .toList() ??
//           [],
//     );
//   }
// }