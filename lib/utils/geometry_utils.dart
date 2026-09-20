import 'dart:convert';
import 'package:latlong2/latlong.dart';

class GeometryUtils {
  static List<LatLng> geometryToPoints(dynamic geometry) {
    if (geometry == null) return [];

    if (geometry is String) {
      try {
        final decoded = jsonDecode(geometry);
        return geometryToPoints(decoded);
      } catch (_) {
        return [];
      }
    }

    if (geometry is Map) {
      final coordinates = geometry['coordinates'];
      if (coordinates is! List) return [];

      final type = geometry['type']?.toString().toLowerCase();

      if (type == 'linestring') {
        return coordinates
            .map(coordinateToLatLng)
            .whereType<LatLng>()
            .toList();
      } else if (type == 'multilinestring') {
        final points = <LatLng>[];
        for (final line in coordinates) {
          if (line is List) {
            points.addAll(line.map(coordinateToLatLng).whereType<LatLng>());
          }
        }
        return points;
      }
    }

    return [];
  }

  static LatLng? coordinateToLatLng(dynamic coordinate) {
    if (coordinate is! List ||
        coordinate.length < 2 ||
        coordinate[0] is! num ||
        coordinate[1] is! num) {
      return null;
    }
    return LatLng(
      (coordinate[1] as num).toDouble(),
      (coordinate[0] as num).toDouble(),
    );
  }
}