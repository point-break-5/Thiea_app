import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:thiea_app/screens/imagePreview/image_preview.dart';

class GalleryPhotosTab extends StatelessWidget {
  final bool isSearching;
  final List<ImageWithDate> filteredImages;
  final List<ImageWithDate> images;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final Function() loadMoreImages;
  final Function(ImageWithDate) onShowImageDetails;
  final List<DateTime> years;
  final List<DateTime> months;
  final XFile Function(DateTime) getFirstImageForYear;
  final XFile Function(DateTime) getFirstImageForMonth;
  final String currentCategory;
  final Function() tabController;
  final bool isSelecting;
  final Function(String) onToggleSelect;
  final Set<String> selectedImages;
  final Function(DateTime, DateTime) getDateAlbum;

  const GalleryPhotosTab({
    Key? key,
    required this.isSearching,
    required this.filteredImages,
    required this.images,
    required this.scrollController,
    required this.isLoadingMore,
    required this.loadMoreImages,
    required this.onShowImageDetails,
    required this.years,
    required this.months,
    required this.getFirstImageForYear,
    required this.getFirstImageForMonth,
    required this.currentCategory,
    required this.tabController,
    required this.isSelecting,
    required this.onToggleSelect,
    required this.selectedImages,
    required this.getDateAlbum,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () {
                    tabController();
                  },
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
              itemCount: years.length,
              itemBuilder: (context, index) {
                final year = years[index];
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
                  onPressed: () {
                    tabController();
                  },
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
              itemCount: months.length,
              itemBuilder: (context, index) {
                final month = months[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildMonthItem(month),
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              getAlbumName(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),

        // Main Photos Grid
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final image = images[index];
              return _buildPhotoItem(image);
            },
            childCount: images.length,
          ),
        ),

        if (isLoadingMore)
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

  Widget _buildPhotoItem(ImageWithDate image) {
    final isSelected = selectedImages.contains(image.file.path);

    return GestureDetector(
      onTap: () {
        if (isSelecting) {
          onToggleSelect(image.file.path);
        } else {
          onShowImageDetails(image);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Display the image
          Image.file(
            File(image.file.path),
            fit: BoxFit.cover,
          ),
          if (isSelecting)
            // Add a checkbox for selection
            Positioned(
              top: 8,
              right: 8,
              child: Checkbox(
                value: isSelected,
                onChanged: (value) {
                  onToggleSelect(image.file.path);
                },
                checkColor: Colors.white,
                activeColor: Colors.blue,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildYearItem(DateTime year) {
    return GestureDetector(
      onTap: () {
        getDateAlbum(DateTime(0), year);
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
              File(getFirstImageForYear(year).path),
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

  Widget _buildMonthItem(DateTime month) {
    return GestureDetector(
      onTap: () {
        getDateAlbum(month, DateTime(0));
      },
      child: Container(
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
              File(getFirstImageForMonth(month).path),
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
      ),
    );
  }

  Widget _buildSearchResults() {
    if (filteredImages.isEmpty) {
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
      itemCount: filteredImages.length,
      itemBuilder: (context, index) {
        final image = filteredImages[index];
        return _buildPhotoItem(image);
      },
    );
  }

  String getAlbumName() {
    if (currentCategory == 'All Photos') {
      return 'All Photos';
    } else if (currentCategory == 'Favorites') {
      return 'Favorites';
    } else {
      return currentCategory;
    }
  }
}
