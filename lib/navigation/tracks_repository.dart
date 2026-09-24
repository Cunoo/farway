// lib/navigation/services/tracks_repository.dart

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads and parses the current user's previously-cleared road geometries
/// (the "blue lines" drawn on the map) from Supabase.
class TracksRepository {
  const TracksRepository();

  Future<List<List<LatLng>>> fetchHistoricalTracks() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];

    final dynamic response = await Supabase.instance.client.rpc(
      'get_user_cleared_geometries',
      params: {'p_user_id': userId},
    );

    final geometriesList = _extractGeometries(response);

    final lines = <List<LatLng>>[];
    for (final item in geometriesList) {
      if (item is Map) {
        final points = _parseGeoJsonCoordinates(item['coordinates']);
        if (points.isNotEmpty) lines.add(points);
      }
    }
    return lines;
  }

  List<dynamic> _extractGeometries(dynamic response) {
    const key = 'get_user_cleared_geometries';
    if (response is List) {
      if (response.isNotEmpty &&
          response.first is Map &&
          response.first.containsKey(key)) {
        return response.first[key] as List? ?? [];
      }
      return response;
    }
    if (response is Map && response.containsKey(key)) {
      return response[key] as List? ?? [];
    }
    return [];
  }

  /// Handles both `LineString` (2 nested levels) and `MultiLineString`
  /// (3 nested levels) GeoJSON coordinate arrays.
  List<LatLng> _parseGeoJsonCoordinates(dynamic coords) {
    final result = <LatLng>[];
    if (coords is! List) return result;

    final isMulti = coords.isNotEmpty &&
        coords.first is List &&
        coords.first.isNotEmpty &&
        coords.first.first is List;

    void addPt(dynamic pt) {
      if (pt is List && pt.length >= 2) {
        final lon = pt[0];
        final lat = pt[1];
        if (lon is num && lat is num) {
          // Flutter latlong2 expects order: (lat, lon)
          result.add(LatLng(lat.toDouble(), lon.toDouble()));
        }
      }
    }

    if (isMulti) {
      for (final line in coords) {
        if (line is List) {
          for (final pt in line) {
            addPt(pt);
          }
        }
      }
    } else {
      for (final pt in coords) {
        addPt(pt);
      }
    }

    return result;
  }
}
