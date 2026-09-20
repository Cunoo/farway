import 'dart:async';
import 'dart:math' as math;

import 'package:farway/navigation/destination_search.dart';
import 'package:farway/navigation/route_navigation.dart';
import 'package:farway/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({super.key});

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  static const _homeLocation = LatLng(63.4305, 10.3951);
  static const _simulationStep = 0.0001;
  static const _useSimulatedLocation = true;

  // Navigacia
  static const _offRouteThresholdM = 30.0; // od tejto vzdialenosti sme mimo trasy
  static const _offRouteUpdates = 3; // kolko po sebe iducich aktualizacii
  static const _rerouteCooldown = Duration(seconds: 8);
  static const _arrivalThresholdM = 15.0;

  final _mapController = MapController();

  LatLng? _currentCoords;
  double _heading = 0;
  bool _loading = true;
  bool _mapReady = false;
  String? _error;
  LatLng? _routeDestination;
  List<List<LatLng>> _routeLines = [];
  bool _routeLoading = false;
  StreamSubscription<Position>? _positionSubscription;

  // Stav navigacie
  RouteData? _route;
  RouteProgress? _progress;
  int _offRouteCount = 0;
  DateTime? _lastReroute;

  String? get _mapTilesUrl {
    final styleUrl = dotenv.env['PUBLIC_MAPTILER_DARK_TILE_URL'];
    final key = dotenv.env['PUBLIC_MAPTILER_KEY'];
    if (styleUrl == null || key == null || styleUrl.isEmpty || key.isEmpty) {
      return null;
    }
    return styleUrl.replaceFirst('style.json?key=', '{z}/{x}/{y}.png?key=') +
        key;
  }

  @override
  void initState() {
    super.initState();
    _refreshLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_mapTilesUrl == null) {
      setState(() {
        _loading = false;
        _error = 'MapTiler URL or key is missing';
      });
      return;
    }

    if (_useSimulatedLocation) {
      _setCurrentPosition(
        Position(
          latitude: _homeLocation.latitude,
          longitude: _homeLocation.longitude,
          timestamp: DateTime.now(),
          accuracy: 1,
          altitude: 0,
          altitudeAccuracy: 1,
          heading: 0,
          headingAccuracy: 1,
          speed: 0,
          speedAccuracy: 1,
          floor: null,
          isMocked: true,
        ),
      );
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are disabled');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _setCurrentPosition(position);

      _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(_setCurrentPosition);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setCurrentPosition(Position position) {
    if (!mounted) return;
    setState(() {
      _currentCoords = LatLng(position.latitude, position.longitude);
      if (position.heading >= 0) _heading = position.heading;
    });
    if (_mapReady) _mapController.move(_currentCoords!, 15);
    _updateNavigation();
  }

  void _moveSimulated(String direction) {
    if (!_useSimulatedLocation) return;
    final headingOffset = switch (direction) {
      'up' => 0.0,
      'right' => 45.0,
      'down' => 180.0,
      _ => -45.0,
    };
    final nextHeading = (_heading + headingOffset + 360) % 360;
    final previous = _currentCoords ?? _homeLocation;
    final angle = nextHeading * math.pi / 180;
    final latitudeStep = _simulationStep * math.cos(angle);
    final longitudeStep =
        _simulationStep *
        math.sin(angle) /
        math.cos(previous.latitude * math.pi / 180);
    final nextCoords = LatLng(
      previous.latitude + latitudeStep,
      previous.longitude + longitudeStep,
    );

    setState(() {
      _heading = nextHeading;
      _currentCoords = nextCoords;
    });
    if (_mapReady) _mapController.move(nextCoords, 15);
    _updateNavigation();
  }

  Future<void> _openDestinationSearch() async {
    final origin = _currentCoords ?? _homeLocation;
    final result = await showDestinationSearch(context, origin: origin);
    if (result == null || !mounted) return;
    debugPrint('Vybraná ulica: ${result.name} (${result.point})');
    await _fetchRoute(origin, result.point);
  }

  // ---------------------------------------------------------------------
  // Navigacia
  // ---------------------------------------------------------------------

  Future<void> _onMapTap(TapPosition _, LatLng destination) async {
    final start = _currentCoords ?? _homeLocation;
    debugPrint('Klik na mape: start=$start, ciel=$destination');
    await _fetchRoute(start, destination);
  }

  /// Nacita trasu z databazy. Pri [reroute] = true ostane stara trasa
  /// zobrazena, kym nepride nova.
  Future<void> _fetchRoute(
    LatLng start,
    LatLng destination, {
    bool reroute = false,
  }) async {
    if (_routeLoading) return;

    setState(() {
      _routeDestination = destination;
      _routeLoading = true;
      if (!reroute) {
        _route = null;
        _progress = null;
        _routeLines = [];
      }
    });
    if (reroute) _lastReroute = DateTime.now();

    try {
      final result = await Supabase.instance.client
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
      debugPrint('route_with_points_directed vratil ${rows.length} riadkov.');

      final route = RouteData.tryParse(rows);
      if (!mounted) return;

      if (route == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trasu sa nepodarilo nájsť.')),
        );
        return;
      }

      setState(() {
        _route = route;
        _progress = route.project(start);
        _routeLines = [route.points];
        _offRouteCount = 0;
      });
      debugPrint(
        'Trasa: ${formatDistance(route.totalMeters)}, '
        '${formatDuration(route.totalSeconds)}, '
        '${route.maneuvers.length} pokynov.',
      );
    } catch (error) {
      debugPrint('Chyba pri volaní route_with_points_directed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigáciu sa nepodarilo načítať: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  /// Vola sa pri kazdej zmene polohy.
  void _updateNavigation() {
    final route = _route;
    final position = _currentCoords;
    if (route == null || position == null || _routeLoading) return;

    final progress = route.project(
      position,
      hintMeters: _progress?.alongM ?? 0,
    );

    if (progress.remainingM < _arrivalThresholdM) {
      _finishNavigation();
      return;
    }

    _offRouteCount = progress.offRouteM > _offRouteThresholdM
        ? _offRouteCount + 1
        : 0;
    setState(() => _progress = progress);

    final destination = _routeDestination;
    final last = _lastReroute;
    final cooledDown =
        last == null || DateTime.now().difference(last) > _rerouteCooldown;

    if (_offRouteCount >= _offRouteUpdates &&
        destination != null &&
        cooledDown) {
      _offRouteCount = 0;
      debugPrint('Mimo trasy (${progress.offRouteM.round()} m), prepočítavam.');
      _fetchRoute(position, destination, reroute: true);
    }
  }

  void _finishNavigation() {
    _cancelNavigation();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ste v cieli.')));
  }

  void _cancelNavigation() {
    setState(() {
      _route = null;
      _progress = null;
      _routeLines = [];
      _routeDestination = null;
      _offRouteCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _WorldLoading();
    if (_error != null || _mapTilesUrl == null) {
      return _WorldError(
        message: _error ?? 'MapTiler URL or key is missing',
        onRetry: _refreshLocation,
      );
    }

    final markerPosition = _currentCoords ?? _homeLocation;
    final route = _route;
    final progress = _progress;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _homeLocation,
              initialZoom: 15,
              onTap: _onMapTap,
              onMapReady: () {
                _mapReady = true;
                if (_currentCoords != null) {
                  _mapController.move(_currentCoords!, 15);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _mapTilesUrl!,
                userAgentPackageName: 'com.farway.app',
              ),
              PolylineLayer(
                polylines: [
                  for (final line in _routeLines)
                    Polyline(points: line, color: Colors.red, strokeWidth: 5),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: markerPosition,
                    width: 44,
                    height: 44,
                    child: Transform.rotate(
                      angle: _heading * math.pi / 180,
                      child: const Icon(
                        Icons.navigation,
                        color: Color(0xff1479ff),
                        size: 42,
                      ),
                    ),
                  ),
                  if (_routeDestination != null)
                    Marker(
                      point: _routeDestination!,
                      width: 32,
                      height: 32,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            right: 20,
            child: _MapButton(
              icon: Icons.directions,
              onPressed: _openDestinationSearch,
            ),
          ),
          if (route != null && progress != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 16,
              right: 84,
              child: _NavigationPanel(
                progress: progress,
                offRoute: progress.offRouteM > _offRouteThresholdM,
                rerouting: _routeLoading,
                onCancel: _cancelNavigation,
              ),
            ),
          if (_routeLoading)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 110,
              left: 20,
              child: const CircularProgressIndicator(color: Colors.red),
            ),
          Positioned(
            left: 16,
            bottom: 24,
            child: _DebugDPad(onMove: _moveSimulated),
          ),
          Positioned(
            right: 20,
            bottom: 24,
            child: _MapButton(
              icon: Icons.my_location,
              onPressed: _currentCoords == null || !_mapReady
                  ? null
                  : () => _mapController.move(_currentCoords!, 15),
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 8,
            child: Text(
              '© MapTiler © OpenStreetMap',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.progress,
    required this.offRoute,
    required this.rerouting,
    required this.onCancel,
  });

  final RouteProgress progress;
  final bool offRoute;
  final bool rerouting;
  final VoidCallback onCancel;

  static IconData _iconFor(TurnType type) => switch (type) {
    TurnType.depart => Icons.straight,
    TurnType.straight => Icons.straight,
    TurnType.slightLeft => Icons.turn_slight_left,
    TurnType.left => Icons.turn_left,
    TurnType.sharpLeft => Icons.turn_sharp_left,
    TurnType.slightRight => Icons.turn_slight_right,
    TurnType.right => Icons.turn_right,
    TurnType.sharpRight => Icons.turn_sharp_right,
    TurnType.uTurn => Icons.u_turn_left,
    TurnType.arrive => Icons.flag,
  };

  @override
  Widget build(BuildContext context) {
    final next = progress.next;
    final title = next == null
        ? 'Ste v cieli'
        : '${formatDistance(progress.toNextM)} · ${next.text}';
    final status = offRoute || rerouting
        ? 'Mimo trasy, prepočítavam…'
        : 'Zostáva ${formatDistance(progress.remainingM)} · '
              '${formatDuration(progress.remainingS)}';

    return Material(
      color: AppColors.surface.withValues(alpha: 0.95),
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Icon(
              _iconFor(next?.type ?? TurnType.arrive),
              color: AppColors.teal,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.close, color: AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({this.label, this.icon, required this.onPressed});

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.white,
    elevation: 4,
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: icon != null
              ? Icon(icon, color: AppColors.teal)
              : Text(
                  label!,
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    ),
  );
}

class _DebugDPad extends StatelessWidget {
  const _DebugDPad({required this.onMove});

  final ValueChanged<String> onMove;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _DPadButton(icon: Icons.keyboard_arrow_up, onPressed: () => onMove('up')),
      Row(
        children: [
          _DPadButton(
            icon: Icons.keyboard_arrow_left,
            onPressed: () => onMove('left'),
          ),
          const SizedBox(width: 4),
          _DPadButton(
            icon: Icons.keyboard_arrow_right,
            onPressed: () => onMove('right'),
          ),
        ],
      ),
      _DPadButton(
        icon: Icons.keyboard_arrow_down,
        onPressed: () => onMove('down'),
      ),
    ],
  );
}

class _DPadButton extends StatelessWidget {
  const _DPadButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    height: 36,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: AppColors.white),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface.withValues(alpha: 0.9),
      ),
    ),
  );
}

class _WorldLoading extends StatelessWidget {
  const _WorldLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.background,
    body: Center(child: CircularProgressIndicator(color: AppColors.teal)),
  );
}

class _WorldError extends StatelessWidget {
  const _WorldError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}