import 'package:supabase_flutter/supabase_flutter.dart';

class FreeModeController {
  bool _isFreeMode = false;
  final Stopwatch _stopwatch = Stopwatch();

  bool get isFreeMode => _isFreeMode;
  int get elapsedSeconds => _stopwatch.elapsed.inSeconds;

  /// Start free mode
  void start() {
    _isFreeMode = true;
    _stopwatch.reset();
    _stopwatch.start();
  }

  /// Stop/pause free mode
  void stop() {
    _isFreeMode = false;
    _stopwatch.stop();
  }

  /// Full reset of the state
  void reset() {
    _isFreeMode = false;
    _stopwatch.reset();
  }

  /// Finish, send data to Supabase and clean up
  Future<dynamic> finishAndSave({
    required double actualDrivenMeters,
    required List<List<double>> actualTracklog,
  }) async {
    final double distanceKm = actualDrivenMeters / 1000.0;
    // Safety check against 0 seconds on instant click
    const int minDuration = 1;
    final int durationSeconds = elapsedSeconds > 0 ? elapsedSeconds : minDuration;

    final response = await Supabase.instance.client.rpc(
      'save_trip_and_calculate_xp',
      params: {
        'p_distance_km': distanceKm,
        'p_duration_seconds': durationSeconds,
        'p_tracklog': actualTracklog,
      },
    );

    stop();
    return response;
  }
}