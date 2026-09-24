// lib/navigation/services/trip_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a saved trip, as computed by the `save_trip_and_calculate_xp`
/// RPC.
class TripSaveResult {
  const TripSaveResult({required this.earnedXp, required this.newClearedKm});

  final int earnedXp;
  final double newClearedKm;

  factory TripSaveResult.fromResponse(dynamic response) {
    if (response is List && response.isNotEmpty) {
      final row = response.first;
      return TripSaveResult(
        earnedXp: (row['earned_xp'] as num?)?.toInt() ?? 0,
        newClearedKm: (row['new_cleared_km'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return const TripSaveResult(earnedXp: 0, newClearedKm: 0.0);
  }
}

/// Persists finished trips (guided navigation or free mode) via the
/// `save_trip_and_calculate_xp` Supabase RPC.
class TripRepository {
  const TripRepository();

  Future<TripSaveResult> saveTrip({
    required double distanceKm,
    required int durationSeconds,
    required List<List<double>> tracklog,
  }) async {
    final response = await Supabase.instance.client.rpc(
      'save_trip_and_calculate_xp',
      params: {
        'p_distance_km': distanceKm,
        'p_duration_seconds': durationSeconds,
        'p_tracklog': tracklog,
      },
    );
    return TripSaveResult.fromResponse(response);
  }
}
