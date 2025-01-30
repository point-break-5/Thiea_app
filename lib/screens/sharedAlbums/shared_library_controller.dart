// shared_library_controller.dart
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import './shared_library_model.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';


// message.dart

// This enum defines the different types of messages we can show
enum MessageType {
  success,
  error;

  // Helper method to get the appropriate color based on message type
  Color get color {
    switch (this) {
      case MessageType.success:
        return Colors.green.withOpacity(0.3);
      case MessageType.error:
        return Colors.red.withOpacity(0.3);
    }
  }
}

// This class represents a message that can be shown to the user
class AppMessage {
  final String text;
  final MessageType type;

  // Constructor requires both text and type
  const AppMessage({
    required this.text,
    required this.type,
  });

  // Factory constructor for creating success messages
  factory AppMessage.success(String text) {
    return AppMessage(
      text: text,
      type: MessageType.success,
    );
  }

  // Factory constructor for creating error messages
  factory AppMessage.error(String text) {
    return AppMessage(
      text: text,
      type: MessageType.error,
    );
  }
}

class SharedLibraryController extends GetxController {
  final supabase = Supabase.instance.client;
  final RxList<SharedLibrary> libraries = <SharedLibrary>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isUploading = false.obs;
  final Uuid _uuid = Uuid();
  final _messageController = StreamController<AppMessage>.broadcast();
  Stream<AppMessage> get messageStream => _messageController.stream;

  void _handleError(String message, dynamic error) {
    print('$message: $error');
    // Use the factory constructor for creating error messages
    _messageController.add(AppMessage.error('$message: $error'));
  }

  void _showSuccessMessage(String message) {
    print('Success: $message');
    // Use the factory constructor for creating success messages
    _messageController.add(AppMessage.success(message));
  }

  void onInit() {
    super.onInit();
    print('SharedLibraryController initialized');
    // Initializations if any
  }

  @override
  void onClose() {
    print('SharedLibraryController disposed');
    // Cleanup if any
    super.onClose();
  }

  Future<void> loadSharedLibraries(String firebaseUid) async {
    print('Loading shared libraries for Firebase UID: $firebaseUid');
    try {
      isLoading.value = true;
      print('isLoading set to true');

      if (firebaseUid.isEmpty) {
        print('Firebase UID is empty');
        throw Exception('Firebase UID cannot be empty');
      }

      print('Fetching profile from Supabase...');
      final profileResponse = await supabase
          .from('profiles')
          .select('id')
          .eq('firebase_uid', firebaseUid)
          .maybeSingle();

      if (profileResponse == null) {
        print('Profile not found for Firebase UID: $firebaseUid');
        throw Exception('Profile not found');
      }

      final profileId = profileResponse['id'];
      print('Profile ID found: $profileId');

      print('Fetching shared libraries from Supabase...');
      final librariesResponse = await supabase
          .from('shared_libraries')
          .select('''
            id,
            status,
            created_at,
            sender:profiles!sender_id (
              id,
              email,
              full_name,
              avatar_url
            ),
            photos:shared_photos (
              photo:photos (
                id,
                public_url,
                filename,
                storage_path
              )
            )
          ''')
          .eq('receiver_id', profileId)
          .order('created_at', ascending: false);

      print('Parsing shared libraries...');
      libraries.value = (librariesResponse as List)
          .map((json) => SharedLibrary.fromJson(json))
          .toList();
      print('Loaded ${libraries.length} shared libraries');
    } catch (e) {
      print('Error in loadSharedLibraries: $e');
      _handleError('Error loading libraries', e);
    } finally {
      isLoading.value = false;
      print('isLoading set to false');
    }
  }

  Future<void> createSharedLibrary({
    required String senderFirebaseUid,
    required String receiverEmail,
    required List<File> images,
  }) async {
    print('Creating shared library with receiver email: $receiverEmail');
    try {
      if (images.isEmpty) {
        print('No images selected for sharing');
        throw Exception('No images selected');
      }
      if (!_isValidEmail(receiverEmail)) {
        print('Invalid receiver email: $receiverEmail');
        throw Exception('Invalid email address');
      }

      isUploading.value = true;
      print('isUploading set to true');

      print('Fetching sender profile...');
      final senderProfile = await _retryOperation(
            () => supabase
            .from('profiles')
            .select('id')
            .eq('firebase_uid', senderFirebaseUid)
            .single(),
        maxAttempts: 3,
      );

      final senderId = senderProfile['id'];
      print('Sender ID: $senderId');

      print('Handling receiver profile...');
      final receiverId = await _handleReceiverProfile(receiverEmail);
      print('Receiver ID: $receiverId');

      print('Inserting shared library into Supabase...');
      final libraryResponse = await supabase.from('shared_libraries').insert({
        'sender_id': senderId,
        'receiver_id': receiverId,
        'status': LibraryStatus.pending.toJson(),
        'created_at': DateTime.now().toIso8601String(),
      }).select('id').single();

      final libraryId = libraryResponse['id'];
      print('Shared Library ID: $libraryId');

      print('Uploading photos...');
      await _uploadPhotos(images, senderId, libraryId);
      print('All photos uploaded successfully');

      _showSuccessMessage('Library shared successfully');
      print('Success message shown to user');

      print('Reloading shared libraries...');
      await loadSharedLibraries(senderFirebaseUid);
    } catch (e) {
      print('Error in createSharedLibrary: $e');
      _handleError('Error creating library', e);
    } finally {
      isUploading.value = false;
      print('isUploading set to false');
    }
  }

  Future<void> acceptLibrary(String libraryId, String receiverFirebaseUid) async {
    print('Accepting library with ID: $libraryId');
    try {
      print('Fetching library details...');
      final library = await supabase
          .from('shared_libraries')
          .select()
          .eq('id', libraryId)
          .single();
          print(library);


      if (library['status'] == LibraryStatus.accepted.toJson()) {
        print('Library already accepted: $libraryId');
        throw Exception('Library already accepted');
      }

 
      // Add debug print to see the current user
      final user = supabase.auth.currentUser;
      print('Current user: ${user?.id}');

      print('Updating library status to accepted...');
      
      try {


        final response = await supabase
            .from('shared_libraries')
            .update({
              'status': 'accepted'            })
            .eq('id', libraryId)
            .select();
        
        print('Update response: $response');
        
        if (response == null || response.isEmpty) {
          throw Exception('Update failed - check RLS policies');
        }
      } catch (updateError) {
        print('Detailed update error: $updateError');
        throw updateError;
      }

      // Verify the update worked
      final verifyLibrary = await supabase
          .from('shared_libraries')
          .select()
          .eq('id', libraryId)
          .single();
      print('Verified library status: ${verifyLibrary['status']}');

      print('Fetching photos associated with the library...');
      final photosResponse = await supabase
          .from('shared_photos')
          .select('photo:photos (id, public_url, filename, storage_path)')
          .eq('library_id', libraryId);

      final photos = (photosResponse as List)
          .map((item) => SharedPhoto.fromJson(item['photo']))
          .toList();
      print('Found ${photos.length} photos to download');

      print('Downloading photos...');
      await _downloadPhotos(photos);
      print('All photos downloaded successfully');

      print('Reloading shared libraries...');
      await loadSharedLibraries(receiverFirebaseUid);
      print('Shared libraries reloaded');

      Get.snackbar(
        'Success',
        'Library accepted and photos downloaded',
        backgroundColor: Colors.green.withOpacity(0.3),
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
      print('Success snackbar shown to user');
    } catch (e) {
      print('Error in acceptLibrary: $e');
      _handleError('Error accepting library', e);
    }
  }

  // Helper Methods
  Future<void> _uploadPhotos(
      List<File> images, String senderId, String libraryId) async {
    print('Starting photo upload...');
    for (var i = 0; i < images.length; i++) {
      var image = images[i];
      print('Uploading image ${i + 1}/${images.length}: ${image.path}');
      try {
        final photoId = _uuid.v4();
        final ext = image.path.split('.').last.toLowerCase();

        if (!['jpg', 'jpeg', 'png', 'gif'].contains(ext)) {
          print('Unsupported file type for image: $ext');
          throw Exception('Unsupported file type: $ext');
        }

        final storagePath = 'photos/$photoId.$ext';
        print('Uploading to storage path: $storagePath');

        await supabase.storage
            .from('photos')
            .upload(
          storagePath,
          image,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: false,
          ),
        );
        print('Image uploaded to storage');

        final publicUrl =
        supabase.storage.from('photos').getPublicUrl(storagePath);
        print('Public URL obtained: $publicUrl');

        print('Creating photo record in Supabase...');
        await _createPhotoRecord(photoId, image, storagePath, publicUrl, senderId, libraryId);
        print('Photo record created successfully');
      } catch (e) {
        print('Error uploading photo ${image.path}: $e');
        _handleError('Error uploading photo', e);
      }
    }
    print('Photo upload process completed');
  }

  Future<void> _createPhotoRecord(
      String photoId,
      File image,
      String storagePath,
      String publicUrl,
      String senderId,
      String libraryId) async {
    print('Inserting photo record for Photo ID: $photoId');
    final photoResponse = await supabase.from('photos').insert({
      'id': photoId,
      'filename': image.path.split('/').last,
      'storage_path': storagePath,
      'public_url': publicUrl,
      'owner_id': senderId,
      'created_at': DateTime.now().toIso8601String(),
    }).select('id').single();
    print('Photo record inserted with ID: ${photoResponse['id']}');

    print('Inserting shared_photo record...');
    await supabase.from('shared_photos').insert({
      'id': _uuid.v4(),
      'library_id': libraryId,
      'photo_id': photoResponse['id'],
      'created_at': DateTime.now().toIso8601String(),
    });
    print('Shared_photo record inserted');
  }

  Future<String> _handleReceiverProfile(String receiverEmail) async {
    print('Handling receiver profile for email: $receiverEmail');
    final existingReceiver = await supabase
        .from('profiles')
        .select('id')
        .eq('email', receiverEmail)
        .maybeSingle();

    if (existingReceiver != null) {
      print('Existing receiver found with ID: ${existingReceiver['id']}');
      return existingReceiver['id'];
    }

    print('No existing receiver found. Creating new profile...');
    final newReceiver = await supabase.from('profiles').insert({
      'email': receiverEmail,
      'created_at': DateTime.now().toIso8601String(),
    }).select('id').single();
    print('New receiver profile created with ID: ${newReceiver['id']}');

    return newReceiver['id'];
  }


Future<bool> _requestStoragePermission() async {
  if (Platform.isAndroid) {
    if (await _getAndroidVersion() >= 33) {
      // Android 13 and above: Request photos permission
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      // Android 12 and below: Request storage permission
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  } else if (Platform.isIOS) {
    final status = await Permission.photos.request();
    return status.isGranted;
  }
  return false;
}

Future<int> _getAndroidVersion() async {
  if (Platform.isAndroid) {
    return int.parse(await DeviceInfoPlugin().androidInfo
        .then((value) => value.version.release));
  }
  return 0;
}

Future<void> _downloadPhotos(List<SharedPhoto> photos) async {
  print('Starting photo download...');
  
  // Request appropriate permissions
  final hasPermission = await _requestStoragePermission();
  if (!hasPermission) {
    print('Storage permission denied');
    return;
  }
  // Get the DCIM directory
  Directory? dcimDir;
  if (Platform.isAndroid) {
    dcimDir = Directory('/storage/emulated/0/DCIM/MyApp');
  } else if (Platform.isIOS) {
    final Directory documentsDir = await getApplicationDocumentsDirectory();
    dcimDir = Directory('${documentsDir.path}/DCIM/MyApp');
  }
  
  // Create the directory if it doesn't exist
  if (dcimDir != null && !await dcimDir.exists()) {
    await dcimDir.create(recursive: true);
  }
  
  if (dcimDir == null) {
    print('Could not access DCIM directory');
    return;
  }
  
  print('Save directory: ${dcimDir.path}');
  
  for (var i = 0; i < photos.length; i++) {
    var photo = photos[i];
    print('Downloading photo ${i + 1}/${photos.length}: ${photo.publicUrl}');
    
    try {
      final response = await supabase.storage
          .from('photos')
          .download(photo.storagePath);
      print(response);
      final file = File('${dcimDir.path}/${photo.filename}');
      await file.writeAsBytes(response);

      print('Photo downloaded and saved to: ${file.path}');
    } catch (e) {
      print('Error downloading photo ${photo.id}: $e');
      _handleError('Error downloading photo ${photo.id}', e);
    }
  }
  
  print('Photo download process completed');
}

  Future<T> _retryOperation<T>(
      Future<T> Function() operation, {
        int maxAttempts = 3,
        Duration delay = const Duration(seconds: 1),
      }) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        print('Attempt $attempts for operation');
        return await operation();
      } catch (e) {
        print('Attempt $attempts failed: $e');
        if (attempts >= maxAttempts) {
          print('Max attempts reached. Rethrowing exception.');
          rethrow;
        }
        print('Retrying after ${delay * attempts}');
        await Future.delayed(delay * attempts);
      }
    }
  }


  bool _isValidEmail(String email) {
    bool isValid = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);
    print('Validating email "$email": ${isValid ? "Valid" : "Invalid"}');
    return isValid;
  }
}
