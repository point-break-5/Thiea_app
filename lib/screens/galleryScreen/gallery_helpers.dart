part of 'gallery_screen.dart';

Future<void> _saveFaceClusters() async {
  try {
    final directory = await getExternalStorageDirectory();
    final String clustersPath = '${directory!.path}/MyCameraApp/clusters.json';

    // Ensure the directory exists
    final clusterDirectory = Directory('${directory.path}/MyCameraApp');
    if (!await clusterDirectory.exists()) {
      await clusterDirectory.create(recursive: true);
    }

    final file = File(clustersPath);

    // Convert _faceClusters map to a serializable format
    final List<Map<String, dynamic>> serializedClusters = _faceClusters.entries
        .map((entry) => {
              'key': entry.key,
              'values': entry.value,
            })
        .toList(); // Explicitly convert to List

    await file.writeAsString(json.encode(serializedClusters));
    print('Face clusters saved to disk.');
  } catch (e) {
    print('Error saving face clusters: $e');
  }
}

Future<void> _loadFaceClusters() async {
  try {
    final directory = await getExternalStorageDirectory();
    final String clustersPath = '${directory!.path}/MyCameraApp/clusters.json';
    final file = File(clustersPath);

    if (await file.exists()) {
      final String contents = await file.readAsString();
      final dynamic jsonData = json.decode(contents);

      if (jsonData is List<dynamic>) {
        _faceClusters = {
          for (var entry in jsonData)
            if (entry is Map<String, dynamic>)
              entry['key'] as String: List<String>.from(entry['values']),
        };
      } else if (jsonData is Map<String, dynamic>) {
        _faceClusters = Map<String, List<String>>.from(jsonData);
      } else {
        _faceClusters = {};
      }

      _faceClustersCalculated = true;
      print('Face clusters loaded from disk.');
    } else {
      _faceClusters = {};
      await _saveFaceClusters();
      print('Clusters file not found. Created an empty clusters file.');
    }
  } catch (e) {
    print('Error loading face clusters: $e');
    _faceClusters = {};
  }
}

Future<void> _updateFaceClusters(State state) async {
  if (_faceClustersCalculated) {
    print('Face clusters are already calculated.');
    return;
  }

  state.setState(() {
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
    state.setState(() {
      _isProcessingFaces = false;
    });
  }
}

void _sortImagesByCurrentSettings(List<ImageWithDate> images) {
  switch (sortBy) {
    case 'date':
      images.sort((a, b) =>
          sortAscending ? a.date.compareTo(b.date) : b.date.compareTo(a.date));
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
        return sortAscending ? sizeA.compareTo(sizeB) : sizeB.compareTo(sizeA);
      });
      break;
  }
}

void _categorizeImages(List<ImageWithDate> images) {
  // Reset categories
  categorizedImages = {
    'Recent': images.take(30).toList(),
    'Favorites':
        images.where((img) => favoriteImages.contains(img.file.path)).toList(),
    'All Photos': images,
  };

  // Add year-month categories
  for (var image in images) {
    String yearMonth = DateFormat('MMMM yyyy').format(image.date);
    String justYear = DateFormat('yyyy').format(image.date);
    categorizedImages.putIfAbsent(yearMonth, () => []).add(image);
    categorizedImages.putIfAbsent(justYear, () => []).add(image);
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

Future<void> _loadMetadata(State state) async {
  try {
    final directory = await getExternalStorageDirectory();
    final String metadataPath = '${directory!.path}/MyCameraApp/metadata.json';
    final file = File(metadataPath);

    if (await file.exists()) {
      final String contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents);
      state.setState(() {
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

Future<ImageMetadata?> _createMetadata(ImageWithDate imageWithDate) async {
  Map<String, String> exifMap = await _loadExifData(imageWithDate.file.path);
  PhotoMetadata defaultData = PhotoMetadata(
    path: imageWithDate.file.path,
    dateTime: imageWithDate.date,
    location: null, 
    placeName: null,
    subLocality: null, 
    filter: null, 
    faces: [], 
  );

  try {
    final existingMetadata = _allPhotos.firstWhere(
      (photo) => photo.path == imageWithDate.file.path,
      orElse: () => defaultData,
    );

    if (existingMetadata != defaultData) {
      debugPrint(
          'Using existing metadata for file: ${imageWithDate.file.path}');
      ImageMetadata temp = ImageMetadata(
        date: existingMetadata.dateTime,
        location: existingMetadata.location != null
            ? '${existingMetadata.location!.latitude}, ${existingMetadata.location!.longitude}'
            : null, 
        exifData: exifMap, 
        caption: null,
        placeName : existingMetadata.placeName ?? 'PlaceHolder',
        subLocation: existingMetadata.subLocality ?? 'PlaceHolder',
      );
      print(existingMetadata.subLocality);
      return temp; 
    } else {
      debugPrint(
          'No existing metadata found for file: ${imageWithDate.file.path}');
    }
    String? location;

    if (location != null) {
      debugPrint('Location for file ${imageWithDate.file.path}: $location');
    } else {
      debugPrint('No location available for file: ${imageWithDate.file.path}');
    }

    return ImageMetadata(
      date: imageWithDate.date,
      location: location,
      exifData: exifMap,
      caption: null,
    );
  } catch (e) {
    debugPrint('Error creating metadata: $e');
    return null;
  }
}

Future<Map<String, String>> _loadExifData(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final exifData = await readExifFromBytes(bytes);

    return exifData.toString().split(',').fold<Map<String, String>>({},
        (map, item) {
      final parts = item.split('=');
      if (parts.length == 2) {
        map[parts[0].trim()] = parts[1].trim();
      }
      return map;
    });
  } catch (e) {
    debugPrint('Error loading EXIF data: $e');
    return {}; // Return an empty map in case of error
  }
}

Future<void> _saveMetadataChanges(ImageWithMetadata updatedImage) async {
  try {
    final directory = await getExternalStorageDirectory();
    final String metadataPath = '${directory!.path}/MyCameraApp/metadata.json';
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

Future<void> _processFacesForAllPhotos(State state,
    {required GalleryScreen widget}) async {
  state.setState(() {
    _isProcessingFaces = true;
  });

  try {
    final newPhotos =
        widget.images.where((img) => !_knownPhotos.contains(img.path)).toList();

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

      state.setState(() {
        _allPhotos.addAll(updatedPhotos);
        _faceClustersCalculated = false;
      });
    } else {
      print('No new faces detected.');
    }
  } catch (e) {
    print('Error processing faces: $e');
  } finally {
    state.setState(() {
      _isProcessingFaces = false;
    });
  }

  // Recalculate clusters if needed
  await _updateFaceClusters(state);
}

Future<void> _loadFavorites(State state) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final List<String>? savedFavorites = prefs.getStringList('favoriteImages');

  state.setState(() {
    if (savedFavorites != null) {
      favoriteImages = savedFavorites.toSet();
    }
  });
}
