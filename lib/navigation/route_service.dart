import 'package:farway/navigation/route_navigation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<RouteData?> fetchRouteData({
    required LatLng start,
    required LatLng destination,
    bool avoidMotorways = false,
    bool avoidTolls = false,
  }) async {
    final result = await _client
        .rpc(
          'route_with_points_directed',
          params: {
            'p_start_lon': start.longitude,
            'p_start_lat': start.latitude,
            'p_end_lon': destination.longitude,
            'p_end_lat': destination.latitude,
            'p_avoid_motorways': avoidMotorways,
            'p_avoid_tolls': avoidTolls,
          },
        )
        .timeout(const Duration(seconds: 10));

    final rows = result is List ? result.whereType<Map>().toList() : <Map>[];
    return RouteData.tryParse(rows);
  }
  
}