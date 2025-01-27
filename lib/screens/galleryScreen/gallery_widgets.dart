part of 'gallery_screen.dart';

Widget _buildAlbumsTab(State state,
    {required Future<void> Function() onLoadMoreImages}) {
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
          state.setState(() {
            currentCategory = category;
            _loadedImages.clear();
            _currentPage = 0;
            _hasMoreImages = true;
            onLoadMoreImages();
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

Widget _buildSearchBar(State state,
    {required Future<void> Function() onInitializeImages,
    required bool mounted,
    required GalleryScreen widget}) {
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
                  state.setState(() {
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
                              state.setState(() {
                                searchController.clear();
                                onInitializeImages();
                              });
                            }
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  if (mounted) {
                    state.setState(() {
                      if (value.isEmpty) {
                        onInitializeImages();
                      } else {
                        _performSearch(value, state, widget);
                      }
                    });
                  }
                },
                onSubmitted: (value) {
                  if (mounted) {
                    _performSearch(value, state, widget);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () {
              if (mounted) {
                state.setState(() {
                  isSearching = false;
                  searchController.clear();
                  onInitializeImages();
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

void _performSearch(String query, State state, GalleryScreen widget) {
  state.setState(() {
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

Widget _buildBottomBar(State state,
    {required Future<void> Function() onShareSelectedImages,
    required Future<void> Function() onDeleteSelectedImages,
    required Future<void> Function(String imagePath) onToggleFavorite}) {
  if (isSelecting) {
    return Transform.translate(
      offset: const Offset(0, 0),
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Display the number of selected images
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
                  // Share Button
                  IconButton(
                    icon: const Icon(Icons.share_rounded),
                    onPressed:
                        selectedImages.isEmpty ? null : onShareSelectedImages,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 20),
                  // Favorite Button
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    onPressed: selectedImages.isEmpty
                        ? null
                        : () {
                            for (var imagePath in selectedImages) {
                              onToggleFavorite(imagePath);
                            }
                            state.setState(() {
                              isSelecting = false;
                              selectedImages.clear();
                            });
                          },
                    color: Colors.white,
                  ),
                  const SizedBox(width: 20),
                  // Delete Button
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed:
                        selectedImages.isEmpty ? null : onDeleteSelectedImages,
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  return const SizedBox.shrink();
}
