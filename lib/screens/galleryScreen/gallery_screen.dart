import 'package:flutter/material.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:math';
import 'package:thiea_app/models/photoMetadata.dart';
import 'package:thiea_app/models/photo_cluster.dart';
import 'package:collection/collection.dart';
import 'package:thiea_app/screens/imagePreview/image_preview.dart';
import 'package:exif/exif.dart';
import 'package:thiea_app/models/image_optimizer.dart';
import 'package:thiea_app/screens/galleryScreen/galleryFeatures/gallery_util.dart';
import 'package:thiea_app/screens/galleryScreen/galleryFeatures/gallery_face_recognition.dart';
import 'package:thiea_app/screens/galleryScreen/galleryFeatures/gallery_places.dart';
import 'package:thiea_app/screens/galleryScreen/galleryFeatures/gallery_photos.dart';

part 'gallery_screen_constants.dart';

class GalleryScreen extends StatefulWidget {
  final List<XFile> images;
  final Function(int) onDelete;
  final Function(String) onShare; // Add this
  final Function(String) onInfo; // Add this

  const GalleryScreen({
    Key? key,
    required this.images,
    required this.onDelete,
    required this.onShare, // Add this
    required this.onInfo, // Add this
  }) : super(key: key);

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 30;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
    scrollController = ScrollController();
    _tabController = TabController(length: viewTabs.length, vsync: this);
    filteredImages = []; // Initialize filteredImages

    // Add listeners
    searchController.addListener(_handleSearch);
    scrollController.addListener(_handleScroll);

    // Load initial data
    _loadFaceClusters();
    _loadData();
    _initializeGallery();
  }

  Future<void> _initializeGallery() async {
    try {
      final assets = await _galleryManager.fetchGalleryImages();
      final xFiles =
          await Future.wait(assets.map(_galleryManager.convertAssetToXFile));

      setState(() {
        widget.images.addAll(xFiles); // Populate images
        _initializeImagesWithRetry(); // Refresh display
      });
    } catch (e) {
      print("Error initializing gallery: $e");
    }
  }

  Future<void> _loadData({bool forceProcessFaces = false}) async {
    await _loadMetadata();
    await _loadPreferences();

    final newPhotos =
        widget.images.where((img) => !_knownPhotos.contains(img.path)).toList();
    print('Known photos: ${_knownPhotos.length}');
    print('New photos: ${newPhotos.length}');

    if (forceProcessFaces || _knownPhotos.isEmpty || newPhotos.isNotEmpty) {
      print('Triggering face recognition...');
      await _processFacesForAllPhotos();
    } else {
      print('No new photos to process for face recognition.');
    }

    if (mounted) {
      setState(() {
        currentCategory = 'Recent';
        _initializeImages();
      });
    }
  }

  Future<void> _updateFaceClusters() async {
    if (_faceClustersCalculated) {
      print('Face clusters are already calculated.');
      return;
    }

    setState(() {
      _isProcessingFaces = true;
    });

    try {
      _faceClusters = FaceRecognitionManager.clusterFaces(_allPhotos);
      print('Face Clusters updated: ${_faceClusters.length} clusters');
      _faceClustersCalculated = true;
      await _saveFaceClusters();
    } catch (e) {
      print('Error clustering faces: $e');
    } finally {
      setState(() {
        _isProcessingFaces = false;
      });
    }
  }

  Future<void> _initializeImagesWithRetry([int retryCount = 3]) async {
    try {
      List<ImageWithDate> imagesWithDates = [];

      // Load images with error handling
      for (var file in widget.images) {
        try {
          final fileExists = await File(file.path).exists();
          if (fileExists) {
            final fileDate = await File(file.path).lastModified();
            imagesWithDates.add(ImageWithDate(file: file, date: fileDate));
          }
        } catch (e) {
          print('Error loading image ${file.path}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _sortImagesByCurrentSettings(imagesWithDates);
          _categorizeImages(imagesWithDates);
        });

        await _loadMoreImages();
      }
    } catch (e) {
      print('Error initializing images: $e');
      if (retryCount > 0) {
        // Wait before retrying
        await Future.delayed(const Duration(seconds: 1));
        await _initializeImagesWithRetry(retryCount - 1);
      }
    }
  }

  Future<void> _processFacesForAllPhotos() async {
    setState(() {
      _isProcessingFaces = true;
    });

    try {
      final newPhotos = widget.images
          .where((img) => !_knownPhotos.contains(img.path))
          .toList();

      print('Processing ${newPhotos.length} new photos...');
      if (newPhotos.isEmpty) {
        print('No new photos to process.');
        return;
      }

      final List<PhotoMetadata> updatedPhotos = [];
      for (XFile image in newPhotos) {
        try {
          print('Processing faces for: ${image.path}');
          final faces = await FaceRecognitionManager.detectFaces(image.path);
          print('Found ${faces.length} faces in ${path.basename(image.path)}');

          final existingMetadata = PhotoMetadata(
            path: image.path,
            dateTime: File(image.path).lastModifiedSync(),
            faces: faces,
          );

          updatedPhotos.add(existingMetadata);
          _knownPhotos.add(image.path);
        } catch (e) {
          print('Error processing image ${image.path}: $e');
        }
      }

      if (updatedPhotos.isNotEmpty) {
        print('Saving metadata for ${updatedPhotos.length} photos...');
        final directory = await getExternalStorageDirectory();
        final String metadataPath =
            '${directory!.path}/MyCameraApp/metadata.json';
        final file = File(metadataPath);

        final List<dynamic> existingMetadata =
            _allPhotos.map((photo) => photo.toJson()).toList();
        existingMetadata.addAll(updatedPhotos.map((photo) => photo.toJson()));

        await file.writeAsString(json.encode(existingMetadata));

        setState(() {
          _allPhotos.addAll(updatedPhotos); // Add new photos to in-memory list
          _faceClustersCalculated = false; // Mark clusters for recalculation
        });
      } else {
        print('No new faces detected.');
      }
    } catch (e) {
      print('Error processing faces: $e');
    } finally {
      setState(() {
        _isProcessingFaces = false;
      });
    }

    // Recalculate clusters if needed
    await _updateFaceClusters();
  }

  Future<void> _initializeImages() async {
    List<ImageWithDate> imagesWithDates = widget.images.map((file) {
      final fileDate = File(file.path).lastModifiedSync();
      return ImageWithDate(file: file, date: fileDate);
    }).toList();

    _sortImagesByCurrentSettings(imagesWithDates);
    _categorizeImages(imagesWithDates);
    await _loadMoreImages();
  }

  void _sortImagesByCurrentSettings(List<ImageWithDate> images) {
    switch (sortBy) {
      case 'date':
        images.sort((a, b) => sortAscending
            ? a.date.compareTo(b.date)
            : b.date.compareTo(a.date));
        break;
      case 'name':
        images.sort((a, b) => sortAscending
            ? path.basename(a.file.path).compareTo(path.basename(b.file.path))
            : path.basename(b.file.path).compareTo(path.basename(a.file.path)));
        break;
      case 'size':
        images.sort((a, b) {
          int sizeA = File(a.file.path).lengthSync();
          int sizeB = File(b.file.path).lengthSync();
          return sortAscending
              ? sizeA.compareTo(sizeB)
              : sizeB.compareTo(sizeA);
        });
        break;
    }
  }

  Future<void> _deleteMetadata(String imagePath) async {
    try {
      final directory = await getExternalStorageDirectory();
      final String metadataPath =
          '${directory!.path}/MyCameraApp/metadata.json';
      final file = File(metadataPath);

      if (await file.exists()) {
        final String contents = await file.readAsString();
        final List<dynamic> jsonList = json.decode(contents);

        // Remove metadata for the deleted image
        final updatedMetadata =
            jsonList.where((item) => item['path'] != imagePath).toList();

        // Update metadata file
        await file.writeAsString(json.encode(updatedMetadata));

        // Update in-memory metadata
        setState(() {
          _allPhotos.removeWhere((photo) => photo.path == imagePath);
        });
      }
    } catch (e) {
      print('Error deleting metadata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting metadata: $e')),
        );
      }
    }
  }

  Future<void> _deleteImage(ImageWithDate image) async {
    try {
      final file = File(image.file.path);
      if (await file.exists()) {
        // Find the index in the original images list
        final index =
            widget.images.indexWhere((img) => img.path == image.file.path);

        // Delete the file and its metadata
        await file.delete();
        await _deleteMetadata(image.file.path);

        // Update state
        if (mounted) {
          setState(() {
            // Remove from capturedImages if index is valid
            if (index != -1) {
              widget.onDelete(index);
            }

            // Remove from current category
            if (_loadedImages.containsKey(currentCategory)) {
              _loadedImages[currentCategory]
                  ?.removeWhere((img) => img.file.path == image.file.path);
            }

            // Remove from categorizedImages
            categorizedImages.forEach((key, list) {
              list.removeWhere((img) => img.file.path == image.file.path);
            });

            // Remove from favorites if present
            favoriteImages.remove(image.file.path);

            // Clear selection if in selection mode
            if (selectedImages.contains(image.file.path)) {
              selectedImages.remove(image.file.path);
            }
          });
        }
      }
    } catch (e) {
      print('Error deleting image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting image: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreImages() async {
    if (_isLoadingMore || !_hasMoreImages) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final startIndex = _currentPage * _pageSize;
      final endIndex = startIndex + _pageSize;

      if (currentCategory == 'All Photos') {
        final allImages = categorizedImages['All Photos'] ?? [];
        if (startIndex >= allImages.length) {
          _hasMoreImages = false;
          return;
        }

        final newImages = allImages.sublist(
          startIndex,
          min(endIndex, allImages.length),
        );

        setState(() {
          _loadedImages[currentCategory] = [
            ...(_loadedImages[currentCategory] ?? []),
            ...newImages,
          ];
          _currentPage++;
        });

        // Check if we've loaded all images
        if (endIndex >= allImages.length) {
          _hasMoreImages = false;
        }
      } else {
        // Handle loading for specific categories (e.g., months, years, favorites)
        final categoryImages = categorizedImages[currentCategory] ?? [];
        if (startIndex >= categoryImages.length) {
          _hasMoreImages = false;
          return;
        }

        final newImages = categoryImages.sublist(
          startIndex,
          min(endIndex, categoryImages.length),
        );

        setState(() {
          _loadedImages[currentCategory] = [
            ...(_loadedImages[currentCategory] ?? []),
            ...newImages,
          ];
          _currentPage++;
        });

        if (endIndex >= categoryImages.length) {
          _hasMoreImages = false;
        }
      }
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  void _showPersonDetailsScreen(PersonCluster cluster) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonDetailsScreen(
          cluster: cluster,
          onDeletePhoto: (String photoPath) async {
            final photo = cluster.photos.firstWhere((p) => p.path == photoPath);
            final file = XFile(photoPath);
            final imageWithDate = ImageWithDate(
              file: file,
              date: photo.dateTime,
            );
            await _deleteImage(imageWithDate);
          },
        ),
      ),
    );
  }

  void _categorizeImages(List<ImageWithDate> images) {
    // Reset categories
    categorizedImages = {
      'Recent': images.take(30).toList(),
      'Favorites': images
          .where((img) => favoriteImages.contains(img.file.path))
          .toList(),
      'All Photos': images,
    };

    // Add year-month categories
    for (var image in images) {
      String yearMonth = DateFormat('MMMM yyyy').format(image.date);
      categorizedImages.putIfAbsent(yearMonth, () => []).add(image);
    }

    // Add smart albums
    categorizedImages['Screenshots'] = images
        .where((img) =>
            path.basename(img.file.path).toLowerCase().contains('screenshot'))
        .toList();

    categorizedImages['Videos'] = images
        .where((img) => ['mp4', 'mov', '3gp']
            .contains(path.extension(img.file.path).toLowerCase()))
        .toList();
  }

  // void _showPersonPhotos(List<String> faceIds) {
  //   final personPhotos = _allPhotos
  //       .where((photo) => photo.faces.any((face) => faceIds.contains(face.id)))
  //       .toList();
  //
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(
  //       builder: (context) => GalleryScreen(
  //         images: personPhotos.map((p) => XFile(p.path)).toList(),
  //         onDelete: widget.onDelete,
  //         onShare: widget.onShare, // Add this
  //         onInfo: widget.onInfo, // Add this
  //       ),
  //     ),
  //   );
  // }

  void _showLocationCluster(String clusterKey, List<PhotoMetadata> photos) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GalleryScreen(
          images: photos.map((p) => XFile(p.path)).toList(),
          onDelete: widget.onDelete,
          onShare: widget.onShare, // Add this
          onInfo: widget.onInfo, // Add this
        ),
      ),
    );
  }

  Future<void> _loadPreferences() async {
    // Load saved preferences like favorites, view settings, etc.
    // This would typically use SharedPreferences
    setState(() {
      favoriteImages = <String>{}; // Load from storage
    });
  }

  void _handleSearch() {
    if (!mounted) return;
    setState(() {
      if (searchController.text.isEmpty) {
        _initializeImages();
      } else {
        _performSearch(searchController.text);
      }
    });
  }

  void _handleScroll() {
    if (!mounted) return;
    if (!_isLoadingMore && _hasMoreImages) {
      final maxScroll = scrollController.position.maxScrollExtent;
      final currentScroll = scrollController.position.pixels;
      final threshold = maxScroll * _scrollThreshold;

      if (currentScroll >= threshold) {
        _loadMoreImages();
      }
    }

    setState(() {
      _showScrollToTop = scrollController.position.pixels > 1000;
    });
  }

  Future<void> _showImageInfo(String imagePath) async {
    final fileInfo = File(imagePath);
    final lastModified = fileInfo.lastModifiedSync();
    final fileSize = fileInfo.lengthSync();

    if (mounted) {
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Image Information',
                style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date: ${DateFormat('MMM d, yyyy HH:mm').format(lastModified)}',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'Size: ${(fileSize / 1024).toStringAsFixed(2)} KB',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'Path: $imagePath',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text('Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    }
  }

  // String _getDateLabel(DateTime date) {
  //   // This method can be removed as date labels are no longer needed
  //   return '';
  // }

  Widget _buildAlbumsTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: categorizedImages.length,
      itemBuilder: (context, index) {
        final category = categorizedImages.keys.elementAt(index);
        final images = categorizedImages[category]!;
        if (images.isEmpty) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            setState(() {
              currentCategory = category;
              _loadedImages.clear();
              _currentPage = 0;
              _hasMoreImages = true;
              _loadMoreImages();
              _tabController.animateTo(0); // Switch to Photos tab
            });
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[800]!),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(images.first.file.path),
                  fit: BoxFit.cover,
                ),
                Container(
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
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${images.length} items',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // void _scrollToTop() {
  //   scrollController.animateTo(
  //     0,
  //     duration: const Duration(milliseconds: 500),
  //     curve: Curves.easeInOut,
  //   );
  // }

  // void _switchCategory(String newCategory) {
  //   setState(() {
  //     currentCategory = newCategory;
  //     _currentPage = 0;
  //     _hasMoreImages = true;
  //     _loadedImages.clear();
  //   });
  //   _loadMoreImages();
  // }

  void _sortImages(List<ImageWithDate> images) {
    switch (sortBy) {
      case 'date':
        images.sort((a, b) => sortAscending
            ? a.date.compareTo(b.date)
            : b.date.compareTo(a.date));
        break;
      case 'name':
        images.sort((a, b) => sortAscending
            ? path.basename(a.file.path).compareTo(path.basename(b.file.path))
            : path.basename(b.file.path).compareTo(path.basename(a.file.path)));
        break;
      case 'size':
        images.sort((a, b) {
          int sizeA = File(a.file.path).lengthSync();
          int sizeB = File(b.file.path).lengthSync();
          return sortAscending
              ? sizeA.compareTo(sizeB)
              : sizeB.compareTo(sizeA);
        });
        break;
    }
  }

  void _performSearch(String query) {
    setState(() {
      filteredImages = widget.images
          .map((file) => ImageWithDate(
                file: file,
                date: File(file.path).lastModifiedSync(),
              ))
          .where((img) =>
              path
                  .basename(img.file.path)
                  .toLowerCase()
                  .contains(query.toLowerCase()) ||
              DateFormat('MMMM yyyy')
                  .format(img.date)
                  .toLowerCase()
                  .contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _showImageDetails(ImageWithDate imageWithDate) async {
    // Convert ImageWithDate to ImageWithMetadata
    final metadata = await _createMetadata(imageWithDate);
    final imageWithMetadata = ImageWithMetadata(
      file: imageWithDate.file,
      metadata: metadata,
    );

    final isFavorite = favoriteImages.contains(imageWithDate.file.path);

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.95),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImagePreviewScreen(
          image: imageWithMetadata,
          isFavorite: isFavorite,
          onImageUpdated: (updatedImage) {
            // Handle the updated image
            _handleImageUpdate(updatedImage);
          },
          onFavoriteToggle: () => _toggleFavorite(imageWithDate.file.path),
          onDelete: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.grey[900],
                title: const Text(
                  'Delete Photo?',
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  'This action cannot be undone.',
                  style: TextStyle(color: Colors.grey),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );

            if (confirmed ?? false) {
              await _deleteImage(imageWithDate);
              if (mounted) Navigator.pop(context);
            }
          },
          onShare: () => _shareImage(imageWithDate.file.path),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadMetadata() async {
    try {
      final directory = await getExternalStorageDirectory();
      final String metadataPath =
          '${directory!.path}/MyCameraApp/metadata.json';
      final file = File(metadataPath);

      if (await file.exists()) {
        final String contents = await file.readAsString();
        final List<dynamic> jsonList = json.decode(contents);

        setState(() {
          _allPhotos =
              jsonList.map((json) => PhotoMetadata.fromJson(json)).toList();
          _knownPhotos = _allPhotos.map((photo) => photo.path).toSet();
        });

        print('Metadata loaded: ${_allPhotos.length} photos'); // Debug
      }
    } catch (e) {
      print('Error loading metadata: $e');
    }
  }

  Future<ImageMetadata> _createMetadata(ImageWithDate imageWithDate) async {
    String? location;
    Map<String, String>? exifData;

    try {
      // Load EXIF data
      final bytes = await File(imageWithDate.file.path).readAsBytes();
      final exifData = await readExifFromBytes(bytes);
      final exifMap = exifData
          .toString()
          .split(',')
          .fold<Map<String, String>>({}, (map, item) {
        final parts = item.split('=');
        if (parts.length == 2) {
          map[parts[0].trim()] = parts[1].trim();
        }
        return map;
      });

      // Try to get location from photo metadata
      final currentLocation = await PhotoManagerInternal.getCurrentLocation();
      if (currentLocation != null) {
        location = await PhotoManagerInternal.getPlaceName(currentLocation);
      }

      return ImageMetadata(
        date: imageWithDate.date,
        location: location,
        exifData: exifMap,
        caption: null, // Initial caption is null
      );
    } catch (e) {
      print('Error creating metadata: $e');
      // Return basic metadata if we can't get additional info
      return ImageMetadata(
        date: imageWithDate.date,
        location: null,
        exifData: null,
        caption: null,
      );
    }
  }

  void _handleImageUpdate(ImageWithMetadata updatedImage) async {
    try {
      // Update the image in your state
      setState(() {
        // Update in loaded images
        for (var category in _loadedImages.keys) {
          final index = _loadedImages[category]?.indexWhere(
            (img) => img.file.path == updatedImage.file.path,
          );
          if (index != null && index != -1) {
            final oldImage = _loadedImages[category]![index];
            _loadedImages[category]![index] = ImageWithDate(
              file: updatedImage.file,
              date: updatedImage.metadata.date,
            );
          }
        }

        // Update in categorized images
        for (var category in categorizedImages.keys) {
          final index = categorizedImages[category]?.indexWhere(
            (img) => img.file.path == updatedImage.file.path,
          );
          if (index != null && index != -1) {
            categorizedImages[category]![index] = ImageWithDate(
              file: updatedImage.file,
              date: updatedImage.metadata.date,
            );
          }
        }
      });

      // Save metadata changes
      await _saveMetadataChanges(updatedImage);
    } catch (e) {
      print('Error handling image update: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating image: $e')),
        );
      }
    }
  }

  Future<void> _saveMetadataChanges(ImageWithMetadata updatedImage) async {
    try {
      final directory = await getExternalStorageDirectory();
      final String metadataPath =
          '${directory!.path}/MyCameraApp/metadata.json';
      final file = File(metadataPath);

      List<dynamic> metadata = [];
      if (await file.exists()) {
        final contents = await file.readAsString();
        metadata = json.decode(contents);
      }

      // Find and update or add new metadata
      final index =
          metadata.indexWhere((item) => item['path'] == updatedImage.file.path);

      final newMetadata = {
        'path': updatedImage.file.path,
        'date': updatedImage.metadata.date.toIso8601String(),
        'location': updatedImage.metadata.location,
        'caption': updatedImage.metadata.caption,
        'exifData': updatedImage.metadata.exifData,
      };

      if (index != -1) {
        metadata[index] = newMetadata;
      } else {
        metadata.add(newMetadata);
      }

      await file.writeAsString(json.encode(metadata));
    } catch (e) {
      print('Error saving metadata changes: $e');
      throw Exception('Failed to save metadata changes');
    }
  }

  Future<void> _toggleFavorite(String imagePath) async {
    setState(() {
      if (favoriteImages.contains(imagePath)) {
        favoriteImages.remove(imagePath);
      } else {
        favoriteImages.add(imagePath);
      }
    });
    // Save updated favorites to storage
  }

  Future<void> _shareSelectedImages() async {
    try {
      final files = selectedImages.map((path) => XFile(path)).toList();
      await Share.shareXFiles(
        files,
        text: 'Check out these photos!',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing images: $e')),
        );
      }
    }
  }

  Future<void> _deleteSelectedImages() async {
    final count = selectedImages.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'Delete $count ${count == 1 ? 'Photo' : 'Photos'}?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      for (var imagePath in selectedImages) {
        final index = widget.images.indexWhere((img) => img.path == imagePath);
        if (index != -1) {
          widget.onDelete(index);
          favoriteImages.remove(imagePath);
        }
      }
      setState(() {
        selectedImages.clear();
        isSelecting = false;
      });
      _initializeImages();
    }
  }

  Future<void> _shareImage(String imagePath) async {
    try {
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: 'Check out this photo!',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing image: $e')),
        );
      }
    }
  }

  Widget _buildSearchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: isSearching ? 56 : 0,
      child: Container(
        color: Colors.grey[900],
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus && mounted) {
                    setState(() {
                      isSearching = false;
                    });
                  }
                },
                child: TextField(
                  controller: searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search photos...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[800],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Colors.grey[400],
                    ),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: Colors.grey[400],
                            ),
                            onPressed: () {
                              if (mounted) {
                                setState(() {
                                  searchController.clear();
                                  _initializeImages();
                                });
                              }
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    if (mounted) {
                      setState(() {
                        if (value.isEmpty) {
                          _initializeImages();
                        } else {
                          _performSearch(value);
                        }
                      });
                    }
                  },
                  onSubmitted: (value) {
                    if (mounted) {
                      _performSearch(value);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () {
                if (mounted) {
                  setState(() {
                    isSearching = false;
                    searchController.clear();
                    _initializeImages();
                  });
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    if (isSelecting) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${selectedImages.length} Selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.share_rounded),
                    onPressed:
                        selectedImages.isEmpty ? null : _shareSelectedImages,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    onPressed: selectedImages.isEmpty
                        ? null
                        : () {
                            for (var imagePath in selectedImages) {
                              _toggleFavorite(imagePath);
                            }
                            setState(() {
                              isSelecting = false;
                              selectedImages.clear();
                            });
                          },
                    color: Colors.white,
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed:
                        selectedImages.isEmpty ? null : _deleteSelectedImages,
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  List<DateTime> _getYears() {
    final years = widget.images
        .map((file) {
          final date = File(file.path).lastModifiedSync();
          return DateTime(date.year);
        })
        .toSet()
        .toList();

    years.sort((a, b) => b.compareTo(a)); // Latest year first
    return years;
  }

  List<DateTime> _getMonths() {
    final months = widget.images
        .map((file) {
          final date = File(file.path).lastModifiedSync();
          return DateTime(date.year, date.month);
        })
        .toSet()
        .toList();

    months.sort((a, b) => b.compareTo(a)); // Latest month first
    return months;
  }

  XFile _getFirstImageForYear(DateTime year) {
    return widget.images.firstWhere((file) {
      final date = File(file.path).lastModifiedSync();
      return date.year == year.year;
    }, orElse: () => widget.images.first);
  }

  XFile _getFirstImageForMonth(DateTime month) {
    return widget.images.firstWhere((file) {
      final date = File(file.path).lastModifiedSync();
      return date.year == month.year && date.month == month.month;
    }, orElse: () => widget.images.first);
  }

  @override
  Widget build(BuildContext context) {
    if (!mounted) return const SizedBox.shrink();

    return WillPopScope(
      onWillPop: () async {
        if (isSelecting) {
          setState(() {
            isSelecting = false;
            selectedImages.clear();
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Header Section
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Photos',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(19),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.search, size: 20),
                                color: Colors.white,
                                onPressed: () {
                                  if (mounted) {
                                    setState(() {
                                      isSearching = !isSearching;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(19),
                              ),
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () {
                                  if (mounted) {
                                    setState(() {
                                      isSelecting = !isSelecting;
                                    });
                                  }
                                },
                                child: const Text(
                                  'Select',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.images.length} items',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Tabs
              if (!isSelecting && !isSearching)
                Container(
                  height: 44,
                  margin: const EdgeInsets.only(top: 8),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey[600],
                    indicatorColor: Colors.white,
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: viewTabs.map((tab) => Tab(text: tab)).toList(),
                  ),
                ),

              // Search Bar
              if (isSearching) _buildSearchBar(),

              // Main Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: !isSelecting
                      ? const AlwaysScrollableScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  children: [
                    Container(
                      key: const PageStorageKey('photos'),
                      child: GalleryPhotosTab(
                        isSearching: isSearching,
                        filteredImages: filteredImages,
                        images: _loadedImages[currentCategory] ?? [],
                        scrollController: scrollController,
                        isLoadingMore: _isLoadingMore,
                        loadMoreImages: _loadMoreImages,
                        onShowImageDetails: (imageWithDate) =>
                            _showImageDetails(imageWithDate),
                        years: _getYears(),
                        months: _getMonths(),
                        getFirstImageForYear: _getFirstImageForYear,
                        getFirstImageForMonth: _getFirstImageForMonth,
                        currentCategory: currentCategory,
                      ),
                    ),
                    Container(
                      key: const PageStorageKey('albums'),
                      child: _buildAlbumsTab(),
                    ),
                    Container(
                      key: const PageStorageKey('people'),
                      child: PeopleTab(
                        allPhotos: _allPhotos,
                        faceClusters: _faceClusters,
                        isProcessingFaces: _isProcessingFaces,
                        onShowPersonDetails: _showPersonDetailsScreen,
                      ),
                    ),
                    Container(
                      key: const PageStorageKey('places'),
                      child: PlacesTab(
                        allPhotos: _allPhotos,
                        onShowLocationCluster: _showLocationCluster,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Future<void> _saveFaceClusters() async {
    try {
      final directory = await getExternalStorageDirectory();
      final String clustersPath =
          '${directory!.path}/MyCameraApp/clusters.json';
      final file = File(clustersPath);
      await file.writeAsString(json.encode(_faceClusters));
      print('Face clusters saved to disk.');
    } catch (e) {
      print('Error saving face clusters: $e');
    }
  }

  Future<void> _loadFaceClusters() async {
    try {
      final directory = await getExternalStorageDirectory();
      final String clustersPath =
          '${directory!.path}/MyCameraApp/clusters.json';
      final file = File(clustersPath);

      if (await file.exists()) {
        final String contents = await file.readAsString();
        _faceClusters = Map<String, List<String>>.from(json.decode(contents));
        _faceClustersCalculated = true; // Mark clusters as loaded
        print('Face clusters loaded from disk.');
      }
    } catch (e) {
      print('Error loading face clusters: $e');
    }
  }

  @override
  void dispose() {
    searchController.removeListener(_handleSearch);
    scrollController.removeListener(_handleScroll);
    _tabController.dispose();
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
