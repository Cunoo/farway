import 'package:farway/navigation/route_navigation.dart';
import 'package:farway/navigation/route_service.dart';
import 'package:latlong2/latlong.dart';

class RouteNotFoundException implements Exception {}

class NavigationUpdate {
  const NavigationUpdate({this.arrived = false, this.shouldReroute = false});

  final bool arrived;
  final bool shouldReroute;
}

class NavigationController {
  NavigationController({
    RouteService? routeService,
    this.offRouteThresholdM = 30.0,
    this.offRouteUpdatesRequired = 3,
    this.rerouteCooldown = const Duration(seconds: 8),
    this.arrivalThresholdM = 15.0,
  }) : _routeService = routeService ?? RouteService();

  final RouteService _routeService;
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

  Future<void> fetchRoute(
    LatLng start,
    LatLng destinationPoint, {
    bool reroute = false,
    bool avoidMotorways = false,
    bool avoidTolls = false,
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
      // call to RouteService to fetch the route data
      final parsed = await _routeService.fetchRouteData(
        start: start,
        destination: destinationPoint,
        avoidMotorways: avoidMotorways,
        avoidTolls: avoidTolls,
      );

      if (parsed == null) throw RouteNotFoundException();

      route = parsed;
      progress = parsed.project(start);
      _offRouteCount = 0;
    } finally {
      isLoading = false;
    }
  }

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