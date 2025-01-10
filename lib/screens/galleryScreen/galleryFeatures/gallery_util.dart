import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:thiea_app/models/location.dart';
import 'package:thiea_app/models/photoMetadata.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';


class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;

    // Draw vertical lines
    for (int i = 1; i < 3; i++) {
      final double x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (int i = 1; i < 3; i++) {
      final double y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class TimeoutError extends Error {}

class PhotoManagerInternal {
  static Future<List<PhotoMetadata>> getAllMetadata() async {
    try {
      final directory = await getExternalStorageDirectory();
      final String metadataPath =
          '${directory!.path}/MyCameraApp/metadata.json';
      final file = File(metadataPath);

      if (!await file.exists()) {
        return [];
      }

      final String contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents);
      return jsonList.map((json) => PhotoMetadata.fromJson(json)).toList();
    } catch (e) {
      print('Error loading all metadata: $e');
      return [];
    }
  }

  /// Retrieves metadata for a specific image path.
  static Future<PhotoMetadata?> getMetadata(String imagePath) async {
    try {
      final allMetadata = await getAllMetadata();
      return allMetadata.firstWhere((photo) => photo.path == imagePath);
    } catch (e) {
      print('Error retrieving metadata for $imagePath: $e');
      return null;
    }
  }

  static Future<String?> getPlaceName(Location location) async {
    try {
      List<geocoding.Placemark> placemarks =
          await geocoding.placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isNotEmpty) {
        geocoding.Placemark place = placemarks.first;
        List<String> components = [];

        if (place.locality?.isNotEmpty ?? false) {
          components.add(place.locality!);
        } else if (place.subLocality?.isNotEmpty ?? false) {
          components.add(place.subLocality!);
        }

        if (place.administrativeArea?.isNotEmpty ?? false) {
          components.add(place.administrativeArea!);
        } else if (place.subAdministrativeArea?.isNotEmpty ?? false) {
          components.add(place.subAdministrativeArea!);
        }

        if (place.country?.isNotEmpty ?? false) {
          components.add(place.country!);
        }

        // Optionally include postal code for more specificity
        if (place.postalCode?.isNotEmpty ?? false) {
          components.add(place.postalCode!);
        }

        // If all components are empty, return null
        if (components.isEmpty) return null;

        return components.join(', ');
      }
    } catch (e) {
      print('Error getting place name: $e');
    }
    return null;
  }

  static Future<Location?> getCurrentLocation() async {
    try {
      final permission = await checkLocationPermission();
      if (!permission) return null;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('Location request timed out');
          throw TimeoutError();
        },
      );

      return Location(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on TimeoutError {
      print('Location request timed out');
      return null;
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  static Future<bool> checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  static Map<String, List<PhotoMetadata>> categorizeByLocation(
      List<PhotoMetadata> photos) {
    Map<String, List<PhotoMetadata>> categorized = {};

    for (var photo in photos) {
      String category = photo.placeName ?? 'Unknown Location';
      if (!categorized.containsKey(category)) {
        categorized[category] = [];
      }
      categorized[category]!.add(photo);
    }

    // Sort each category by date
    categorized.forEach((key, list) {
      list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    });

    return categorized;
  }

  static Map<String, List<PhotoMetadata>> categorizeByDate(
      List<PhotoMetadata> photos) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));
    final lastMonth = today.subtract(const Duration(days: 30));

    return {
      'Today': photos.where((photo) {
        final photoDate = DateTime(
          photo.dateTime.year,
          photo.dateTime.month,
          photo.dateTime.day,
        );
        return photoDate.isAtSameMomentAs(today);
      }).toList(),
      'Yesterday': photos.where((photo) {
        final photoDate = DateTime(
          photo.dateTime.year,
          photo.dateTime.month,
          photo.dateTime.day,
        );
        return photoDate.isAtSameMomentAs(yesterday);
      }).toList(),
      'Last Week': photos.where((photo) {
        final photoDate = DateTime(
          photo.dateTime.year,
          photo.dateTime.month,
          photo.dateTime.day,
        );
        return photoDate.isAfter(lastWeek) && photoDate.isBefore(yesterday);
      }).toList(),
      'Last Month': photos.where((photo) {
        final photoDate = DateTime(
          photo.dateTime.year,
          photo.dateTime.month,
          photo.dateTime.day,
        );
        return photoDate.isAfter(lastMonth) && photoDate.isBefore(lastWeek);
      }).toList(),
      'Older': photos.where((photo) {
        final photoDate = DateTime(
          photo.dateTime.year,
          photo.dateTime.month,
          photo.dateTime.day,
        );
        return photoDate.isBefore(lastMonth);
      }).toList(),
    };
  }
}

class GalleryManager {
  static DateTime? lastFetched; // To store the last fetched time

  // Fetch images from gallery
  Future<List<AssetEntity>> fetchGalleryImages() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      print("Permission denied");
      return [];
    }

    await PhotoManager.clearFileCache();

    final albums = await PhotoManager.getAssetPathList(
      filterOption: FilterOptionGroup(
        orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
      type: RequestType.image,
    );

    final recentAlbum = albums.first; // Fetch the most recent album
    final allAssets = await recentAlbum.getAssetListPaged(page: 0, size: 50);

    // Fetch files for all assets
    final assetFiles = await Future.wait(allAssets.map((asset) async {
      final file = await asset.file;
      return {'asset': asset, 'file': file};
    }));
    // If there's a lastFetched datetime, filter images after that time
    if (lastFetched != null) {
      updateLastFetched();
      print("CONDITION MET");
      return assetFiles
          .where((entry) {
            final file = entry['file'] as File?;
            if (file != null) {
              final modificationDate = file.lastModifiedSync();
              return modificationDate.isAfter(lastFetched!);
            }
            return false;
          })
          .map((entry) => entry['asset'] as AssetEntity)
          .toList();
    } else {
      updateLastFetched();
      return allAssets;
    }
  }

  // Convert an AssetEntity to XFile
  Future<XFile> convertAssetToXFile(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null) throw Exception("Failed to get file from asset");
    return XFile(file.path);
  }

  // Update lastFetched time
  void updateLastFetched() {
    lastFetched = DateTime.now();
  }
}
