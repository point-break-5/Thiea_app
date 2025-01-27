import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:math';
import 'package:thiea_app/models/photoMetadata.dart';
import 'package:thiea_app/models/photo_cluster.dart';
import 'package:thiea_app/screens/imagePreview/image_preview.dart';
import 'package:exif/exif.dart';
import 'package:thiea_app/models/image_optimizer.dart';
import 'package:thiea_app/screens/galleryScreen/galleryFeatures/gallery_util.dart';
import 'package:thiea_app/screens/galleryScreen/galleryFeatures/gallery_face_recognition.dart';
import 'package:thiea_app/screens/galleryScreen/galleryFeatures/gallery_places.dart';
import 'package:thiea_app/screens/galleryScreen/galleryFeatures/gallery_photos.dart';
import 'package:thiea_app/Authentication/login_screen.dart';

part 'gallery_screen_constants.dart';
part 'gallery_widgets.dart';
part 'gallery_helpers.dart';

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
        widget.images.addAll(xFiles);
        _initializeImagesWithRetry();
        currentCategory = 'Recent';
      });
    } catch (e) {
      print("Error initializing gallery: $e");
    }
  }

  Future<void> _loadData({bool forceProcessFaces = false}) async {
    await _loadMetadata(this);
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

      if (newPhotos.isEmpty) {
        print('No new photos to process.');
        return;
      }

      final List<PhotoMetadata> updatedPhotos = [];
      for (XFile image in newPhotos) {
        try {
          final faces = await FaceRecognitionManager.detectFaces(image.path);
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

        // Convert _allPhotos to a serializable format
        final List<dynamic> existingMetadata = _allPhotos
            .map((photo) =>
                photo.toJson()) // Ensure toJson returns Map<String, dynamic>
            .toList();

        existingMetadata.addAll(
          updatedPhotos.map((photo) => photo.toJson()).toList(),
        );

        await file.writeAsString(json.encode(existingMetadata));

        setState(() {
          _allPhotos.addAll(updatedPhotos);
          _faceClustersCalculated = false;
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
    await _updateFaceClusters(this);
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
        _performSearch(searchController.text, this, widget);
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
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (scrollNotification) {
                  if (scrollNotification is ScrollUpdateNotification) {
                    if (scrollNotification.scrollDelta != null) {
                      setState(() {
                        isScrollingUp = scrollNotification.scrollDelta! > 0;
                      });
                    }
                  }
                  return true;
                },
                child: Column(
                  children: [
                    // Add extra padding at the top to avoid obstruction
                    const SizedBox(height: 45),

                    // Search Bar with spacing
                    if (isSearching)
                      Padding(
                        padding: const EdgeInsets.only(
                            top: 70), // Lower the search bar
                        child: _buildSearchBar(
                          this,
                          onInitializeImages: _initializeImages,
                          mounted: mounted,
                          widget: widget,
                        ),
                      ),

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
                              tabController: pingController,
                            ),
                          ),
                          Container(
                            key: const PageStorageKey('albums'),
                            child: _buildAlbumsTab(
                              this,
                              onLoadMoreImages: _loadMoreImages,
                            ),
                          ),
                          Container(
                            key: const PageStorageKey('people'),
                            padding: const EdgeInsets.only(top: 16),
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
                    if (isSelecting)
                      Positioned(
                        bottom:
                            60, // Adjust as needed to appear above bottomNavigationBar
                        left: 0,
                        right: 0,
                        child: _buildBottomBar(
                          this,
                          onShareSelectedImages: _shareSelectedImages,
                          onDeleteSelectedImages: _deleteSelectedImages,
                          onToggleFavorite: _toggleFavorite
                        ),
                      ),
                  ],
                ),
              ),

              // Translucent Top Bar

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 85, // Restrict the height to match the top bar
                  child: Stack(
                    children: [
                      // Backdrop blur for just the area of the bar
                      ClipRect(
                        // Ensures the blur is confined to the bar's area
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                          child: Container(
                            color: Colors.black.withOpacity(
                                0), // Transparent container for the blur effect
                          ),
                        ),
                      ),
                      // The actual bar content
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0),
                          backgroundBlendMode: BlendMode.overlay,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Left side: Library and photo count
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Library",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${widget.images.length} items',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),

                              // Action buttons
                              Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
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
                                    width: 50,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(25),
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
                                            if (!isSelecting) {
                                              selectedImages.clear();
                                            }
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
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(19),
                                    ),
                                    child:
                                        ProfileButton(), // Replace the IconButton with ProfileButton
                                  ),
                                ],
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
        bottomNavigationBar: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          tabs: viewTabs.map((tab) => Tab(text: tab)).toList(),
        ),
      ),
    );
  }

  Future<void> pingController() async {
    _tabController.animateTo(1);
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
