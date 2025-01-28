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
import 'dart:collection';
import 'dart:async';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

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
  static DateTime? lastFetched;
  static const numberOfImages = 300;
  static const int _chunkSize = 25;

  final LinkedHashMap<String, String> _filePathCache = LinkedHashMap(
    equals: (a, b) => a == b,
    hashCode: (key) => key.hashCode,
  );

  final Map<String, DateTime> _modificationDateCache = {};

  Timer? _cacheClearTimer;

  Future<List<AssetEntity>> fetchGalleryImages() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) return [];

    _debouncedClearCache();

    final albums = await PhotoManager.getAssetPathList(
      filterOption: FilterOptionGroup(
        orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
      type: RequestType.image,
    );

    if (albums.isEmpty) return [];

    final recentAlbum = albums.first;

    final totalCount = await recentAlbum.assetCountAsync;
    final pageSize = min(totalCount, numberOfImages);

    final allAssets = await recentAlbum.getAssetListPaged(
      page: 0,
      size: pageSize,
      // size: 50,
    );

    if (lastFetched != null) {
      final processedAssets =
          await _processAssetsInParallelOptimized(allAssets);
      updateLastFetched();
      return processedAssets;
    } else {
      updateLastFetched();
      return allAssets;
    }
  }

  Future<List<AssetEntity>> _processAssetsInParallelOptimized(
      List<AssetEntity> assets) async {
    if (lastFetched == null) return assets;

    final List<AssetEntity?> results = List.filled(assets.length, null);
    final chunks = _splitIntoChunks(assets, _chunkSize);

    await Future.wait(
      chunks.mapIndexed((chunkIndex, chunk) async {
        await Future.wait(
          chunk.mapIndexed((innerIndex, asset) async {
            try {
              final globalIndex = chunkIndex * _chunkSize + innerIndex;
              results[globalIndex] = await _processAssetOptimized(asset);
            } catch (e) {
              print("Error processing asset: $e");
            }
          }),
        );
      }),
    );

    return results.whereType<AssetEntity>().toList(growable: false);
  }

  Future<AssetEntity?> _processAssetOptimized(AssetEntity asset) async {
    if (lastFetched == null) return asset;

    try {
      if (_modificationDateCache.containsKey(asset.id)) {
        return _modificationDateCache[asset.id]!.isAfter(lastFetched!)
            ? asset
            : null;
      }

      if (_filePathCache.containsKey(asset.id)) {
        final file = File(_filePathCache[asset.id]!);
        if (await file.exists()) {
          final modDate = await _getFileModificationDate(file);
          return modDate.isAfter(lastFetched!) ? asset : null;
        }
      }

      final file = await asset.file;
      if (file != null) {
        _filePathCache[asset.id] = file.path;
        final modDate = await _getFileModificationDate(file);
        _modificationDateCache[asset.id] = modDate;
        return modDate.isAfter(lastFetched!) ? asset : null;
      }
    } catch (e) {
      print("Error processing asset ${asset.id}: $e");
    }
    return null;
  }

  Future<DateTime> _getFileModificationDate(File file) async {
    return compute(
      (String path) => File(path).lastModifiedSync(),
      file.path,
    );
  }

  List<List<T>> _splitIntoChunks<T>(List<T> list, int chunkSize) {
    final int len = list.length;
    final chunks = List<List<T>>.generate(
      (len + chunkSize - 1) ~/ chunkSize,
      (i) => list.sublist(
        i * chunkSize,
        min((i + 1) * chunkSize, len),
      ),
      growable: false,
    );
    return chunks;
  }

  Future<XFile> convertAssetToXFile(AssetEntity asset) async {
    try {
      if (_filePathCache.containsKey(asset.id)) {
        final cachedPath = _filePathCache[asset.id]!;
        final file = File(cachedPath);
        if (await file.exists()) {
          return XFile(cachedPath);
        }
      }

      final file = await asset.file;
      if (file == null) throw Exception("Failed to get file from asset");

      _filePathCache[asset.id] = file.path;
      return XFile(file.path);
    } catch (e) {
      throw Exception("Error converting asset to XFile: $e");
    }
  }

  void _debouncedClearCache() {
    _cacheClearTimer?.cancel();
    _cacheClearTimer = Timer(Duration(minutes: 5), () async {
      if (lastFetched == null ||
          DateTime.now().difference(lastFetched!) > Duration(minutes: 30)) {
        await PhotoManager.clearFileCache();
        _modificationDateCache.clear();

        if (_filePathCache.length > 500) {
          final entriesToKeep = _filePathCache.entries.take(200);
          _filePathCache.clear();
          entriesToKeep.forEach((entry) {
            _filePathCache[entry.key] = entry.value;
          });
        }
      }
    });
  }

  void updateLastFetched() {
    lastFetched = DateTime.now();
  }

  void dispose() {
    _cacheClearTimer?.cancel();
    _filePathCache.clear();
    _modificationDateCache.clear();
  }
}
