class Location {
  final double latitude;
  final double longitude;

  Location({required this.latitude, required this.longitude});

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  static Location fromJson(Map<String, dynamic> json) {
    return Location(
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
    );
  }
}