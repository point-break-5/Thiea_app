import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:math';
import 'package:flutter/foundation.dart'; // For compute
import 'package:untitled/photo_cluster.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:collection/collection.dart';
import 'package:untitled/screens/image_preview.dart';
import 'package:exif/exif.dart';
import 'package:untitled/image_optimizer.dart';
import 'package:photo_manager/photo_manager.dart';

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
  late TabController _tabController;
  late List<ImageWithDate> filteredImages;
  bool isSearching = false;
  bool isSelecting = false;
  String currentCategory = 'Recent';
  String currentView = 'grid';
  DateTime? searchDate;
  Set<String> selectedImages = {};
  Set<String> favoriteImages = {};
  TextEditingController searchController = TextEditingController();
  ScrollController scrollController = ScrollController();
  String? selectedFilter;
  bool _showScrollToTop = false;
  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  bool _hasMoreImages = true;
  int _currentPage = 0;
  Map<String, List<ImageWithDate>> _loadedImages = {};
  Map<String, List<ImageWithDate>> categorizedImages = {};
  double _scrollThreshold = 0.8;
  bool _isProcessingFaces = false;
  List<PhotoMetadata> _allPhotos = [];
  String sortBy = 'date';
  bool sortAscending = false;
  final imageOptimizer = ImageOptimizer();
  final GalleryManager _galleryManager = GalleryManager();

  final List<String> viewTabs = ['Photos', 'Albums', 'People', 'Places'];

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
        });
        print('Metadata loaded: ${_allPhotos.length} photos'); // Debug
      }
    } catch (e) {
      print('Error loading metadata: $e');
    }
  }

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
    _loadData();
    _initializeGallery();
  }

  //Gallery Access Start
  Future<void> _initializeGallery() async {
    try {
      final assets = await _galleryManager.fetchGalleryImages();
      final xFiles = await Future.wait(assets.map(_galleryManager.convertAssetToXFile));

      setState(() {
        widget.images.addAll(xFiles); // Populate images
        _initializeImagesWithRetry(); // Refresh display
      });
    } catch (e) {
      print("Error initializing gallery: $e");
    }
  }
  //Gallery Access End

  Future<void> _loadData() async {
    await _loadMetadata();
    await _loadPreferences();
    await _processFacesForAllPhotos();

    if (mounted) {
      setState(() {
        currentCategory = 'Recent';
        _initializeImages();
      });
    }
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

  String _generatePersonName(String clusterId, int faceCount) {
    // Extract tracking ID if available
    if (clusterId.startsWith('tracking_')) {
      return 'Person ${clusterId.split('_')[1]}';
    }

    // Generate a consistent name based on cluster ID
    final hash = clusterId.hashCode.abs();
    return 'Person ${(hash % 1000) + 1}';
  }

  // Helper function to get the best face from a list
  FaceData _getBestFace(List<FaceData> faces) {
    return faces.reduce((a, b) {
      final qualityA = _calculateFaceQuality(a);
      final qualityB = _calculateFaceQuality(b);
      return qualityA > qualityB ? a : b;
    });
  }

  // Helper function to calculate face quality
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

  Future<void> _initializeImagesWithRetry([int retryCount = 3]) async {
    try {
      List<ImageWithDate> imagesWithDates = [];
      List<Future<ImageWithDate>> imageLoadingTasks = [];

      // Create async tasks for image loading
      for (var file in widget.images) {
        imageLoadingTasks.add(_loadImageWithMetadata(file));
      }

      // Await and collect results
      imagesWithDates = await Future.wait(imageLoadingTasks);

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
        await Future.delayed(const Duration(seconds: 1));
        await _initializeImagesWithRetry(retryCount - 1);
      }
    }
  }

  Future<ImageWithDate> _loadImageWithMetadata(XFile file) async {
    try {
      final fileExists = await File(file.path).exists();
      if (!fileExists) throw Exception("File not found");

      final fileDate = await File(file.path).lastModified();
      final compressedPath =
          await imageOptimizer.compress(file.path); // Compress for thumbnails

      return ImageWithDate(file: XFile(compressedPath), date: fileDate);
    } catch (e) {
      print('Error loading image ${file.path}: $e');
      throw e;
    }
  }

  Future<void> _processFacesForAllPhotos() async {
    setState(() {
      _isProcessingFaces = true;
    });

    try {
      List<PhotoMetadata> updatedPhotos = [];

      for (XFile image in widget.images) {
        print('Processing faces for: ${image.path}');
        final faces = await FaceRecognitionManager.detectFaces(image.path);
        print('Found ${faces.length} faces in ${path.basename(image.path)}');

        // Find existing metadata for the image
        final existingMetadata = _allPhotos.firstWhere(
          (photo) => photo.path == image.path,
          orElse: () => PhotoMetadata(
            path: image.path,
            dateTime: File(image.path).lastModifiedSync(),
            faces: [],
          ),
        );

        // Create a new PhotoMetadata with updated faces, preserving other fields
        final updatedMetadata = PhotoMetadata(
          path: existingMetadata.path,
          dateTime: existingMetadata.dateTime,
          location: existingMetadata.location,
          placeName: existingMetadata.placeName,
          filter: existingMetadata.filter,
          faces: faces,
        );

        updatedPhotos.add(updatedMetadata);
      }

      // Save the updated metadata
      final directory = await getExternalStorageDirectory();
      final String metadataPath =
          '${directory!.path}/MyCameraApp/metadata.json';
      final file = File(metadataPath);

      await file.writeAsString(
        json.encode(updatedPhotos.map((p) => p.toJson()).toList()),
      );

      setState(() {
        _allPhotos = updatedPhotos;
        _isProcessingFaces = false;
      });

      // Print clustering results for debugging
      final clusters = FaceRecognitionManager.clusterFaces(_allPhotos);
      print('\nFace Clusters:');
      clusters.forEach((clusterId, faceIds) {
        print('$clusterId: ${faceIds.length} faces');
        faceIds.forEach((faceId) {
          final face =
              FaceRecognitionManager.allFaces[faceId]; // Updated reference
          if (face != null) {
            print('  - Face $faceId (Tracking ID: ${face.trackingId})');
          } else {
            print('  - Face $faceId not found in allFaces map');
          }
        });
      });
    } catch (e) {
      print('Error processing faces: $e');
      setState(() {
        _isProcessingFaces = false;
      });
    }
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

  Widget _buildPeopleTab() {
    if (_isProcessingFaces) {
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

    // Filter photos to only include those with faces
    final photosWithFaces =
        _allPhotos.where((photo) => photo.faces.isNotEmpty).toList();

    if (photosWithFaces.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.face, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No faces found in your photos',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Take some photos of people to see them here',
              style:
                  TextStyle(color: Colors.grey.withOpacity(0.7), fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Get clusters of faces
    final faceClusters = FaceRecognitionManager.clusterFaces(_allPhotos);

    if (faceClusters.isEmpty) {
      return const Center(
        child: Text(
          'No face clusters found',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Create PersonCluster objects
    final List<PersonCluster> personClusters =
        faceClusters.entries.map((entry) {
      final clusterId = entry.key;
      final faceIds = entry.value;
      final clusterPhotos = photosWithFaces
          .where(
              (photo) => photo.faces.any((face) => faceIds.contains(face.id)))
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
                  onTap: () => _showPersonDetailsScreen(cluster),
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

  void _showPersonPhotos(List<String> faceIds) {
    final personPhotos = _allPhotos
        .where((photo) => photo.faces.any((face) => faceIds.contains(face.id)))
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GalleryScreen(
          images: personPhotos.map((p) => XFile(p.path)).toList(),
          onDelete: widget.onDelete,
          onShare: widget.onShare, // Add this
          onInfo: widget.onInfo, // Add this
        ),
      ),
    );
  }

  Widget _buildPlacesTab() {
    if (_allPhotos.isEmpty) {
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

    // Filter photos with location data
    final photosWithLocation = _allPhotos
        .where((photo) =>
            photo.location != null && (photo.placeName?.isNotEmpty ?? false))
        .toList();

    if (photosWithLocation.isEmpty) {
      return Center(
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
                  onTap: () => _showLocationCluster(clusterKey, photos),
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

  Widget _buildSearchResults() {
    if (searchController.text.isEmpty && searchDate == null) {
      return CustomScrollView(
        slivers: _buildPhotoGrid(),
      );
    }

    List<ImageWithDate> searchResults = filteredImages;
    if (searchResults.isEmpty) {
      return const Center(
        child: Text(
          'No photos found',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(1),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: searchResults.length,
      itemBuilder: (context, index) {
        final image = searchResults[index];
        final originalIndex = widget.images.indexWhere(
          (img) => img.path == image.file.path,
        );
        return _buildPhotoItem(image.file, originalIndex);
      },
    );
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

  List<Widget> _buildPhotoGrid() {
    final images = _loadedImages[currentCategory] ?? [];

    // If no images and not loading more, show a simple Sliver message
    if (images.isEmpty && !_isLoadingMore) {
      return [
        const SliverToBoxAdapter(
          child: Center(
            child: Text(
              'No photos in this category',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ];
    }

    // Group images by month/year
    final groupedImages = groupBy(
      images,
      (ImageWithDate image) {
        return DateFormat('MMMM yyyy').format(image.date);
      },
    );

    return [
      // EXAMPLE: "Library" title
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Library',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
            ],
          ),
        ),
      ),

      // A grid of the images themselves (recent photos)
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index >= images.length) return null;
              return _buildPhotoItem(images[index].file, index);
            },
            childCount: images.length,
          ),
        ),
      ),

      // Grouped by month/year
      for (var entry in groupedImages.entries) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              entry.key,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= entry.value.length) return null;
                final image = entry.value[index];
                return _buildPhotoItem(image.file, index);
              },
              childCount: entry.value.length,
            ),
          ),
        ),
      ],

      if (_isLoadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ),
    ];
  }

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

  void _scrollToTop() {
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildPhotoItem(XFile image, int index) {
    final isSelected = selectedImages.contains(image.path);
    return GestureDetector(
      onTap: () {
        if (isSelecting) {
          setState(() {
            if (isSelected) {
              selectedImages.remove(image.path);
              if (selectedImages.isEmpty) {
                isSelecting = false;
              }
            } else {
              selectedImages.add(image.path);
            }
          });
        } else {
          _showImageDetails(ImageWithDate(
            file: image,
            date: File(image.path).lastModifiedSync(),
          ));
        }
      },
      onLongPress: () {
        if (!isSelecting) {
          setState(() {
            isSelecting = true;
            selectedImages.add(image.path);
          });
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: image.path,
            child: Image.file(
              File(image.path),
              fit: BoxFit.cover,
            ),
          ),
          if (isSelecting)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? Colors.blue : Colors.black45,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Center(
                        child: Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  void _switchCategory(String newCategory) {
    setState(() {
      currentCategory = newCategory;
      _currentPage = 0;
      _hasMoreImages = true;
      _loadedImages.clear();
    });
    _loadMoreImages();
  }

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

  // Add this helper method to create metadata
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
      final currentLocation = await PhotoManagerV2.getCurrentLocation();
      if (currentLocation != null) {
        location = await PhotoManagerV2.getPlaceName(currentLocation);
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

  // Add this method to handle image updates
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

  // Add this method to save metadata changes
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

  Widget _buildMonthItem(DateTime month) {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.grey[900],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(_getFirstImageForMonth(month).path),
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
              children: [
                Text(
                  DateFormat('MMMM').format(month),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  DateFormat('yyyy').format(month),
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
                      child: _buildPhotosTab(),
                    ),
                    Container(
                      key: const PageStorageKey('albums'),
                      child: _buildAlbumsTab(),
                    ),
                    Container(
                      key: const PageStorageKey('people'),
                      child: _buildPeopleTab(),
                    ),
                    Container(
                      key: const PageStorageKey('places'),
                      child: _buildPlacesTab(),
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

  Widget _buildPhotosTab() {
    if (isSearching) {
      return _buildSearchResults();
    }

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // Years Section
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Years',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  child: const Row(
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.blue, size: 20),
                    ],
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),

        // Years Grid
        SliverToBoxAdapter(
          child: SizedBox(
            height: 120,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _getYears().length,
              itemBuilder: (context, index) {
                final year = _getYears()[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildYearItem(year),
                );
              },
            ),
          ),
        ),

        // Months Section
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Months',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  child: const Row(
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.blue, size: 20),
                    ],
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),

        // Months Grid
        SliverToBoxAdapter(
          child: SizedBox(
            height: 200,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _getMonths().length,
              itemBuilder: (context, index) {
                final month = _getMonths()[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildMonthItem(month),
                );
              },
            ),
          ),
        ),

        // Main Photos Grid
        ...(_buildPhotoGrid()),

        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildYearItem(DateTime year) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GalleryScreen(
              images: categorizedImages[DateFormat('MMMM yyyy').format(year)]!
                  .map((img) => img.file)
                  .toList(),
              onDelete: widget.onDelete,
              onShare: widget.onShare,
              onInfo: widget.onInfo,
            ),
          ),
        );
      },
      child: Container(
        width: 90,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[900],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(_getFirstImageForYear(year).path),
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
              left: 8,
              bottom: 8,
              child: Text(
                DateFormat('yyyy').format(year),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

class PhotoManagerV2 {
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
      return assetFiles.where((entry) {
        final file = entry['file'] as File?;
        if (file != null) {
          final modificationDate = file.lastModifiedSync();
          return modificationDate.isAfter(lastFetched!);
        }
        return false;
      }).map((entry) => entry['asset'] as AssetEntity).toList();
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
