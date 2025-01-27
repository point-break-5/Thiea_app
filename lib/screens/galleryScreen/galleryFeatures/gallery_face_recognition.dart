import 'package:flutter/material.dart';
import 'dart:io';
import 'package:thiea_app/models/photoMetadata.dart';
import 'package:thiea_app/models/photo_cluster.dart';
import 'package:thiea_app/models/faceData.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class PeopleTab extends StatelessWidget {
  final List<PhotoMetadata> allPhotos;
  final Map<String, List<String>> faceClusters; // Add this
  final Function(PersonCluster cluster) onShowPersonDetails;
  final bool isProcessingFaces;

  const PeopleTab({
    Key? key,
    required this.allPhotos,
    required this.faceClusters,
    required this.onShowPersonDetails,
    this.isProcessingFaces = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isProcessingFaces) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Processing faces...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Directly use precomputed clusters
    if (faceClusters.isEmpty) {
      return const Center(
        child: Text(
          'No face clusters found',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final List<PersonCluster> personClusters =
        faceClusters.entries.map((entry) {
      final clusterId = entry.key;
      final faceIds = entry.value;
      final clusterPhotos = allPhotos
          .where((photo) => photo.faces.any((face) => faceIds.contains(face.id)))
          .toList();
      clusterPhotos.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      final representativePhoto = _findBestRepresentativePhoto(clusterPhotos);

      return PersonCluster(
        id: clusterId,
        name: _generatePersonName(clusterId, faceIds.length),
        representativePhoto: representativePhoto,
        photoCount: clusterPhotos.length,
        photos: clusterPhotos,
      );
    }).toList();

    personClusters.sort((a, b) => b.photoCount.compareTo(a.photoCount));

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${personClusters.length} People Found',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: personClusters.length,
              itemBuilder: (context, index) {
                final cluster = personClusters[index];
                return GestureDetector(
                  onTap: () => onShowPersonDetails(cluster),
                  child: Card(
                    color: Colors.grey[900],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 4,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12)),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(cluster.representativePhoto.path),
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withOpacity(0.7),
                                        ],
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          cluster.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '${cluster.photoCount} photos',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
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
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  PhotoMetadata _findBestRepresentativePhoto(List<PhotoMetadata> photos) {
    // Sort photos by face quality criteria
    final sortedPhotos = photos.toList()
      ..sort((a, b) {
        // Get the best face from each photo
        final faceA = _getBestFace(a.faces);
        final faceB = _getBestFace(b.faces);

        // Compare face qualities
        final qualityA = _calculateFaceQuality(faceA);
        final qualityB = _calculateFaceQuality(faceB);

        return qualityB.compareTo(qualityA);
      });

    return sortedPhotos.first;
  }

  FaceData _getBestFace(List<FaceData> faces) {
    return faces.reduce((a, b) {
      final qualityA = _calculateFaceQuality(a);
      final qualityB = _calculateFaceQuality(b);
      return qualityA > qualityB ? a : b;
    });
  }

  double _calculateFaceQuality(FaceData face) {
    double quality = 0.0;

    // Prefer faces looking more directly at the camera
    final headAngleY = face.headAngle['y'] ?? 0.0;
    quality += 1.0 - (headAngleY.abs() / 45.0).clamp(0.0, 1.0);

    // Prefer smiling faces
    quality += face.smiling;

    // Prefer faces with more detected landmarks
    quality += face.landmarks.length / FaceLandmarkType.values.length;

    return quality;
  }

  String _generatePersonName(String clusterId, int faceCount) {
    // Extract tracking ID if available
    if (clusterId.startsWith('tracking_')) {
      return 'Person ${clusterId.split('_')[1]}';
    }

    // Generate a consistent name based on cluster ID
    final hash = clusterId.hashCode.abs();
    return 'Person ${(hash % 1000) + 1}';
  }
}

