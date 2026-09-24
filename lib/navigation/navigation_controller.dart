// lib/navigation/controllers/navigation_controller.dart

import 'package:farway/navigation/route_navigation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown by [NavigationController.fetchRoute] when the backend returns no
/// usable route between the two points.
class RouteNotFoundException implements Exception {}

/// What the UI should do after [NavigationController.updateForPosition].
class NavigationUpdate {
  const NavigationUpdate({this.arrived = false, this.shouldReroute = false});

  final bool arrived;
  final bool shouldReroute;
}

/// Encapsulates route fetching, progress tracking, off-route detection and
/// automatic rerouting for guided (turn-by-turn) navigation. Free-mode
/// driving does not use this controller at all.
class NavigationController {
  NavigationController({
    this.offRouteThresholdM = 30.0,
    this.offRouteUpdatesRequired = 3,
    this.rerouteCooldown = const Duration(seconds: 8),
    this.arrivalThresholdM = 15.0,
  });

  final double offRouteThresholdM;
  final int offRouteUpdatesRequired;
  final Duration rerouteCooldown;
  final double arrivalThresholdM;

  RouteData? route;
  RouteProgress? progress;
  LatLng? destination;
  bool isLoading = false;

  int _offRouteCount = 0;
  DateTime? _lastReroute;

  /// Fetches (or re-fetches, when [reroute] is true) a route from [start] to
  /// [destinationPoint]. On reroute, the previous [route]/[progress] are left
  /// in place until the new ones arrive. Throws [RouteNotFoundException] if
  /// the backend can't find a route, or the underlying network/RPC error
  /// otherwise.
  Future<void> fetchRoute(
    LatLng start,
    LatLng destinationPoint, {
    bool reroute = false,
  }) async {
    if (isLoading) return;

    destination = destinationPoint;
    isLoading = true;
    if (!reroute) {
      route = null;
      progress = null;
    } else {
      _lastReroute = DateTime.now();
    }

    try {
      final result = await Supabase.instance.client
          .rpc(
            'route_with_points_directed',
            params: {
              'p_start_lon': start.longitude,
              'p_start_lat': start.latitude,
              'p_end_lon': destinationPoint.longitude,
              'p_end_lat': destinationPoint.latitude,
            },
          )
          .timeout(const Duration(seconds: 10));

      final rows =
          result is List ? result.whereType<Map>().toList() : <Map>[];
      final parsed = RouteData.tryParse(rows);
      if (parsed == null) throw RouteNotFoundException();

      route = parsed;
      progress = parsed.project(start);
      _offRouteCount = 0;
    } finally {
      isLoading = false;
    }
  }

  /// Recomputes [progress] for the current [position] and decides whether
  /// the caller has arrived or should trigger a reroute. Does nothing (and
  /// returns an empty update) while [route] is null or a fetch is in
  /// progress.
  NavigationUpdate updateForPosition(LatLng position) {
    final currentRoute = route;
    if (currentRoute == null || isLoading) {
      return const NavigationUpdate();
    }

    final newProgress = currentRoute.project(
      position,
      hintMeters: progress?.alongM ?? 0,
    );
    progress = newProgress;

    if (newProgress.remainingM < arrivalThresholdM) {
      return const NavigationUpdate(arrived: true);
    }

    _offRouteCount =
        newProgress.offRouteM > offRouteThresholdM ? _offRouteCount + 1 : 0;

    final lastReroute = _lastReroute;
    final cooledDown = lastReroute == null ||
        DateTime.now().difference(lastReroute) > rerouteCooldown;

    final shouldReroute = _offRouteCount >= offRouteUpdatesRequired &&
        destination != null &&
        cooledDown;
    if (shouldReroute) _offRouteCount = 0;

    return NavigationUpdate(shouldReroute: shouldReroute);
  }

  /// The remaining route polyline, trimmed to start at the vehicle's current
  /// snapped-to-road position. Used to draw the "remaining" red line.
  List<LatLng> trimmedRouteLine() {
    final currentRoute = route;
    final currentProgress = progress;
    if (currentRoute == null || currentProgress == null) return [];

    int startIndex = 0;
    for (int i = 0; i < currentRoute.cumulative.length; i++) {
      if (currentRoute.cumulative[i] >= currentProgress.alongM) {
        startIndex = (i - 1).clamp(0, currentRoute.cumulative.length);
        break;
      }
    }
    return [currentProgress.snapped, ...currentRoute.points.skip(startIndex)];
  }

  void reset() {
    route = null;
    progress = null;
    destination = null;
    isLoading = false;
    _offRouteCount = 0;
    _lastReroute = null;
  }
}
