import 'package:flutter/material.dart';
import 'dart:io';
import 'package:thiea_app/models/photoMetadata.dart';
import 'package:thiea_app/models/photo_cluster.dart';

class PlacesTab extends StatelessWidget {
  final List<PhotoMetadata> allPhotos;
  final Function(String clusterKey, List<PhotoMetadata>) onShowLocationCluster;

  const PlacesTab({
    Key? key,
    required this.allPhotos,
    required this.onShowLocationCluster,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (allPhotos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.place, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No photos with location data',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Take some photos with location data to see them organized by place',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final photosWithLocation = allPhotos
        .where((photo) =>
            photo.location != null && (photo.placeName?.isNotEmpty ?? false))
        .toList();

    if (photosWithLocation.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No location data available',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Enable location services and take photos to see them organized by place',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final locationClusters =
        LocationClusterManager.clusterByLocation(photosWithLocation);

    if (locationClusters.isEmpty) {
      return const Center(
        child: Text(
          'No location-date clusters found',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${locationClusters.length} Places',
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
                childAspectRatio: 1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: locationClusters.length,
              itemBuilder: (context, index) {
                final clusterKey = locationClusters.keys.elementAt(index);
                final photos = locationClusters[clusterKey]!;

                return GestureDetector(
                  onTap: () => onShowLocationCluster(clusterKey, photos),
                  child: Card(
                    color: Colors.grey[900],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(photos.first.path),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    LocationClusterManager
                                        .getClusterDisplayName(clusterKey),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${photos.length} photos',
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
