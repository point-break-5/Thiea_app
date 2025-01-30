import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

class ImageOptimizer {
  static final ImageOptimizer _instance = ImageOptimizer._internal();
  factory ImageOptimizer() => _instance;
  ImageOptimizer._internal();

  final Map<String, Uint8List> _memoryCache = {};
  static const int maxMemoryCacheSize = 100;

  Future<File> _xFileToFile(XFile xFile) async {
    final file = File(xFile.path);
    if (await file.exists()) {
      return file;
    }
    // If file doesn't exist, create it from XFile data
    final bytes = await xFile.readAsBytes();
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<File> generateThumbnail(XFile image) async {
    final thumbnailDir = await _getThumbnailDir();
    final thumbnailPath =
        '${thumbnailDir.path}/${path.basename(image.path)}_thumb.jpg';
    final thumbnailFile = File(thumbnailPath);

    if (await thumbnailFile.exists()) {
      return thumbnailFile;
    }

    try {
      final originalFile = await _xFileToFile(image);
      final result = await FlutterImageCompress.compressAndGetFile(
        originalFile.absolute.path,
        thumbnailPath,
        quality: 70,
        minWidth: 300,
        minHeight: 300,
      );

      if (result == null) {
        // If compression fails, return original file
        return originalFile;
      }

      return File(result.path);
    } catch (e) {
      print('Error generating thumbnail: $e');
      // Return original file if thumbnail generation fails
      return File(image.path);
    }
  }

  Future<Directory> _getThumbnailDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final thumbnailDir = Directory('${appDir.path}/thumbnails');
    if (!await thumbnailDir.exists()) {
      await thumbnailDir.create(recursive: true);
    }
    return thumbnailDir;
  }

  Future<Uint8List?> loadOptimizedImage(XFile image,
      {bool useCache = true}) async {
    if (useCache && _memoryCache.containsKey(image.path)) {
      return _memoryCache[image.path];
    }

    try {
      final thumbnail = await generateThumbnail(image);
      final bytes = await thumbnail.readAsBytes();

      if (useCache) {
        _addToMemoryCache(image.path, bytes);
      }

      return bytes;
    } catch (e) {
      print('Error loading optimized image: $e');
      return null;
    }
  }

  Future<String> compress(String imagePath) async {
    try {
      final compressedDir = await _getCompressedDir();
      final compressedPath =
          '${compressedDir.path}/${path.basename(imagePath)}_compressed.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        imagePath,
        compressedPath,
        quality: 1, 
      );

      if (result == null) {
        throw Exception("Compression failed");
      }

      return result.path;
    } catch (e) {
      print('Error compressing image $imagePath: $e');
      rethrow;
    }
  }

  Future<Directory> _getCompressedDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final compressedDir = Directory('${appDir.path}/compressed');
    if (!await compressedDir.exists()) {
      await compressedDir.create(recursive: true);
    }
    return compressedDir;
  }

  void _addToMemoryCache(String key, Uint8List value) {
    if (_memoryCache.length >= maxMemoryCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = value;
  }

  void clearCache() {
    _memoryCache.clear();
  }
}
