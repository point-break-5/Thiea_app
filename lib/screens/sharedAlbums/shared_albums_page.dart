// shared_library_screen.dart
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import './shared_library_controller.dart';
import './shared_library_model.dart'; // Import models

class SharedLibraryScreen extends StatefulWidget {
  final String userId;

  const SharedLibraryScreen({
    Key? key,
    required this.userId, // firebase id
  }) : super(key: key);

  @override
  State<SharedLibraryScreen> createState() => _SharedLibraryScreenState();
}

class _SharedLibraryScreenState extends State<SharedLibraryScreen> {

  final TextEditingController _emailController = TextEditingController();
  final List<XFile> _selectedXFiles = []; // Store XFile objects
  final ImagePicker _picker = ImagePicker();
  late final SharedLibraryController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(SharedLibraryController());

    // Set up message listener after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.messageStream.listen((message) {
        if (mounted && context != null) {
          _showMessage(message);
        }
      });
    });

    controller.loadSharedLibraries(widget.userId);
  }

  void _showMessage(AppMessage message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    // Hide any existing snackbars to prevent overlap
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message.text,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: message.type.color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        duration: const Duration(seconds: 3),
        // Add dismiss action for better user experience
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }


  /// Updated _selectImages function to properly handle XFile objects
  Future<void> _selectImages() async {
    try {
      final List<XFile>? images = await _picker.pickMultiImage();
      if (images != null && images.isNotEmpty) {
        setState(() {
          _selectedXFiles.addAll(images);
        });
      }
    } catch (e) {
      print('Error selecting images: $e');
      Get.snackbar(
        'Error',
        'Failed to select images. Please try again.',
        backgroundColor: Colors.red.withOpacity(0.3),
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  /// Convert XFile to File when needed, e.g., before uploading
  List<File> get _selectedImages =>
      _selectedXFiles.map((xfile) => File(xfile.path)).toList();

  void _showCreateLibraryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
        const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Create Shared Library',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Receiver Email',
                        labelStyle:
                        TextStyle(color: Colors.white.withOpacity(0.7)),
                        enabledBorder: OutlineInputBorder(
                          borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                          const BorderSide(color: Colors.white),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        fillColor: Colors.white.withOpacity(0.1),
                        filled: true,
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _selectImages,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: Text(
                          'Select Images (${_selectedXFiles.length})'), // Updated count
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            _emailController.clear();
                            setState(() {
                              _selectedXFiles.clear();
                            });
                            Get.back();
                          },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Obx(() => ElevatedButton(
                          onPressed: controller.isUploading.value
                              ? null
                              : () async {
                            String email =
                            _emailController.text.trim();
                            if (email.isEmpty) {
                              Get.snackbar(
                                'Error',
                                'Please enter receiver email',
                                backgroundColor:
                                Colors.red.withOpacity(0.3),
                                colorText: Colors.white,
                                snackPosition: SnackPosition.BOTTOM,
                              );
                              return;
                            }

                            if (_selectedXFiles.isEmpty) {
                              Get.snackbar(
                                'Error',
                                'Please select at least one image',
                                backgroundColor:
                                Colors.red.withOpacity(0.3),
                                colorText: Colors.white,
                                snackPosition: SnackPosition.BOTTOM,
                              );
                              return;
                            }

                            await controller.createSharedLibrary(
                              senderFirebaseUid: widget.userId,
                              receiverEmail: email,
                              images: _selectedImages,
                            );

                            if (!controller.isUploading.value) {
                              _emailController.clear();
                              setState(() {
                                _selectedXFiles.clear();
                              });
                              Get.back();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            Colors.blue.withOpacity(0.7),
                          ),
                          child: controller.isUploading.value
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Text(
                            'Share',
                            style: TextStyle(color: Colors.white),
                          ),
                        )),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
        const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Shared Libraries',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => controller
                                  .loadSharedLibraries(widget.userId),
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white),
                            ),
                            IconButton(
                              onPressed: _showCreateLibraryDialog,
                              icon:
                              const Icon(Icons.add, color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Library List
                  Expanded(
                    child: Obx(() {
                      if (controller.isLoading.value) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        );
                      }

                      if (controller.libraries.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.photo_library_outlined,
                                size: 48,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No shared libraries yet',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Create one by clicking the + button',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: () =>
                            controller.loadSharedLibraries(widget.userId),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: controller.libraries.length,
                          itemBuilder: (context, index) {
                            final library = controller.libraries[index];
                            return Card(
                              color: Colors.white.withOpacity(0.1),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    // Sender info
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Colors.white
                                              .withOpacity(0.2),
                                          backgroundImage:
                                          library.sender.avatarUrl != null
                                              ? NetworkImage(
                                              library.sender.avatarUrl!)
                                              : null,
                                          child: library.sender.avatarUrl ==
                                              null
                                              ? const Icon(
                                            Icons.person,
                                            color: Colors.white,
                                          )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                library.sender.fullName ??
                                                    library.sender.email,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight:
                                                  FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                'Shared ${library.photos.length} photos · ${timeago.format(library.createdAt)}',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.7),
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (library.status ==
                                            LibraryStatus.pending)
                                          ElevatedButton(
                                            onPressed: () => controller
                                                .acceptLibrary(
                                              library.id,
                                              widget.userId,
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green
                                                  .withOpacity(0.7),
                                              padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                            ),
                                            child: const Text(
                                              'Accept',
                                              style: TextStyle(
                                                  color: Colors.white),
                                            ),
                                          )
                                        else
                                          Container(
                                            padding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue
                                                  .withOpacity(0.3),
                                              borderRadius:
                                              BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              library.status.statusText,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight:
                                                FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),

                                    // Photo preview
                                    if (library.photos.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        height: 80,
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: library.photos.length,
                                          itemBuilder:
                                              (context, photoIndex) {
                                            final photo =
                                            library.photos[photoIndex];
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 8),
                                              child: ClipRRect(
                                                borderRadius:
                                                BorderRadius.circular(8),
                                                child: Image.network(
                                                  photo.publicUrl,
                                                  width: 80,
                                                  height: 80,
                                                  fit: BoxFit.cover,
                                                  loadingBuilder: (context,
                                                      child,
                                                      loadingProgress) {
                                                    if (loadingProgress ==
                                                        null) {
                                                      return child;
                                                    }
                                                    return Container(
                                                      width: 80,
                                                      height: 80,
                                                      color: Colors.white
                                                          .withOpacity(
                                                          0.1),
                                                      child: const Center(
                                                        child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color:
                                                          Colors.white,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  errorBuilder: (context,
                                                      error, stackTrace) {
                                                    return Container(
                                                      width: 80,
                                                      height: 80,
                                                      color: Colors.white
                                                          .withOpacity(
                                                          0.1),
                                                      child: const Icon(
                                                        Icons.broken_image,
                                                        color:
                                                        Colors.white,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ),

                  // Close button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: () => Get.back(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
