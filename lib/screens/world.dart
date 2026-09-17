import 'dart:async';
import 'dart:math' as math;

import 'package:farway/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({super.key});

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  static const _homeLocation = LatLng(63.4305, 10.3951);
  static const _simulationStep = 0.0001;
  static const _useSimulatedLocation = true;

  final _mapController = MapController();
  final _testRoute = const [
    LatLng(63.4305, 10.3951),
    LatLng(63.4306, 10.3952),
    LatLng(63.4308, 10.3954),
    LatLng(63.4310, 10.3956),
  ];

  LatLng? _currentCoords;
  double _heading = 0;
  int _routeIndex = 0;
  bool _loading = true;
  bool _mapReady = false;
  String? _error;
  StreamSubscription<Position>? _positionSubscription;

  String? get _mapTilesUrl {
    final styleUrl = dotenv.env['PUBLIC_MAPTILER_DARK_TILE_URL'];
    final key = dotenv.env['PUBLIC_MAPTILER_KEY'];
    if (styleUrl == null || key == null || styleUrl.isEmpty || key.isEmpty) return null;
    return styleUrl.replaceFirst('style.json?key=', '{z}/{x}/{y}.png?key=') + key;
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

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are disabled');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _setCurrentPosition(position);

      if (!_useSimulatedLocation) {
        _positionSubscription?.cancel();
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
        ).listen(_setCurrentPosition);
      }
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
    final longitudeStep = _simulationStep * math.sin(angle) / math.cos(previous.latitude * math.pi / 180);
    final nextCoords = LatLng(previous.latitude + latitudeStep, previous.longitude + longitudeStep);

    setState(() {
      _heading = nextHeading;
      _currentCoords = nextCoords;
    });
    if (_mapReady) _mapController.move(nextCoords, 15);
  }

  void _moveForward() {
    if (_routeIndex >= _testRoute.length - 1) return;
    setState(() {
      _routeIndex++;
      _currentCoords = _testRoute[_routeIndex];
    });
    if (_mapReady) _mapController.move(_currentCoords!, 15);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _WorldLoading();
    if (_error != null || _mapTilesUrl == null) {
      return _WorldError(message: _error ?? 'MapTiler URL or key is missing', onRetry: _refreshLocation);
    }

    final markerPosition = _currentCoords ?? _homeLocation;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _homeLocation,
              initialZoom: 15,
              onMapReady: () {
                _mapReady = true;
                if (_currentCoords != null) _mapController.move(_currentCoords!, 15);
              },
            ),
            children: [
              TileLayer(urlTemplate: _mapTilesUrl!, userAgentPackageName: 'com.farway.app'),
              MarkerLayer(
                markers: [
                  Marker(
                    point: markerPosition,
                    width: 44,
                    height: 44,
                    child: Transform.rotate(
                      angle: _heading * math.pi / 180,
                      child: const Icon(Icons.navigation, color: Color(0xff1479ff), size: 42),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(top: MediaQuery.paddingOf(context).top + 12, right: 20, child: _MapButton(label: 'Z', onPressed: _moveForward)),
          Positioned(left: 16, bottom: 24, child: _DebugDPad(onMove: _moveSimulated)),
          Positioned(
            right: 20,
            bottom: 24,
            child: _MapButton(
              icon: Icons.my_location,
              onPressed: _currentCoords == null || !_mapReady ? null : () => _mapController.move(_currentCoords!, 15),
            ),
          ),
          const Positioned(left: 8, bottom: 8, child: Text('© MapTiler © OpenStreetMap', style: TextStyle(color: Colors.white, fontSize: 10))),
        ],
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
                  : Text(label!, style: const TextStyle(color: AppColors.teal, fontSize: 22, fontWeight: FontWeight.bold)),
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
          Row(children: [
            _DPadButton(icon: Icons.keyboard_arrow_left, onPressed: () => onMove('left')),
            const SizedBox(width: 4),
            _DPadButton(icon: Icons.keyboard_arrow_right, onPressed: () => onMove('right')),
          ]),
          _DPadButton(icon: Icons.keyboard_arrow_down, onPressed: () => onMove('down')),
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
          style: IconButton.styleFrom(backgroundColor: AppColors.surface.withValues(alpha: 0.9)),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ]),
          ),
        ),
      );
}