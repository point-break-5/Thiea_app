// models.dart
enum LibraryStatus {
  pending,
  accepted,
  rejected;

  String toJson() => name;
  static LibraryStatus fromJson(String json) => values.byName(json);

  // Public getter to obtain status text
  String get statusText => name.toUpperCase();
}

class SharedLibrary {
  final String id;
  final LibraryStatus status;
  final DateTime createdAt;
  final SharedUser sender;
  final List<SharedPhoto> photos;

  SharedLibrary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.sender,
    required this.photos,
  });

  factory SharedLibrary.fromJson(Map<String, dynamic> json) {
    try {
      return SharedLibrary(
        id: json['id'] as String,
        status: LibraryStatus.fromJson(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        sender: SharedUser.fromJson(json['sender'] as Map<String, dynamic>),
        photos: (json['photos'] as List)
            .map((photo) => SharedPhoto.fromJson(photo['photo'] as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      throw FormatException('Error parsing SharedLibrary: $e\nJSON: $json');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.toJson(),
    'created_at': createdAt.toIso8601String(),
    'sender': sender.toJson(),
    'photos': photos.map((p) => {'photo': p.toJson()}).toList(),
  };
}

class SharedUser {
  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;

  SharedUser({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
  });

  factory SharedUser.fromJson(Map<String, dynamic> json) {
    try {
      return SharedUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
    } catch (e) {
      throw FormatException('Error parsing SharedUser: $e\nJSON: $json');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'avatar_url': avatarUrl,
  };
}

class SharedPhoto {
  final String id;
  final String publicUrl;
  final String filename;
  final String storagePath;

  SharedPhoto({
    required this.id,
    required this.publicUrl,
    required this.filename,
    required this.storagePath,
  });

  factory SharedPhoto.fromJson(Map<String, dynamic> json) {
    try {
      return SharedPhoto(
        id: json['id'] as String,
        publicUrl: json['public_url'] as String,
        filename: json['filename'] as String,
        storagePath: json['storage_path'] as String,
      );
    } catch (e) {
      throw FormatException('Error parsing SharedPhoto: $e\nJSON: $json');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'public_url': publicUrl,
    'filename': filename,
    'storage_path': storagePath,
  };
}
