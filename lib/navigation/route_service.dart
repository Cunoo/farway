import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/geometry_utils.dart';

class RouteService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<List<LatLng>>> fetchRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final result = await _client
        .rpc(
          'route_with_points_directed',
          params: {
            'p_start_lon': start.longitude,
            'p_start_lat': start.latitude,
            'p_end_lon': destination.longitude,
            'p_end_lat': destination.latitude,
          },
        )
        .timeout(const Duration(seconds: 10));

    final rows = result is List ? result.whereType<Map>().toList() : <Map>[];
    final lines = <List<LatLng>>[];

    for (final row in rows) {
      final line = GeometryUtils.geometryToPoints(row['geom']);
      if (line.length >= 2) lines.add(line);
    }

    return lines;
  }
}