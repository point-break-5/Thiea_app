import 'package:image/image.dart' as img;

class ImageFilter {
  final String name;
  final Function(img.Image) apply;

  ImageFilter({required this.name, required this.apply});
}
class FilterMatrix {
  final String name;
  final List<double> matrix;

  FilterMatrix({required this.name, required this.matrix});
}

class Filters {
  static final FilterMatrix normal = FilterMatrix(
    name: 'Normal',
    matrix: [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0
    ],
  );

  static final FilterMatrix sepia = FilterMatrix(
    name: 'Sepia',
    matrix: [
      0.393, 0.769, 0.189, 0, 0,
      0.349, 0.686, 0.168, 0, 0,
      0.272, 0.534, 0.131, 0, 0,
      0, 0, 0, 1, 0
    ],
  );

  static final FilterMatrix grayscale = FilterMatrix(
    name: 'Grayscale',
    matrix: [
      0.2126, 0.7152, 0.0722, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
      0, 0, 0, 1, 0
    ],
  );

  static final FilterMatrix vintage = FilterMatrix(
    name: 'Vintage',
    matrix: [
      0.9, 0.5, 0.1, 0, 0,
      0.3, 0.8, 0.1, 0, 0,
      0.2, 0.3, 0.5, 0, 0,
      0, 0, 0, 1, 0
    ],
  );

  static final List<FilterMatrix> availableFilters = [
    normal,
    sepia,
    grayscale,
    vintage,
  ];
}
