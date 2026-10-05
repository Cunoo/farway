// lib/navigation/world.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:farway/navigation/navigation_controller.dart';
import 'package:farway/navigation/trip_recorder.dart';
import 'package:farway/navigation/destination_search.dart';
import 'package:farway/navigation/free_mode_controller.dart';
import 'package:farway/navigation/route_navigation.dart';
import 'package:farway/navigation/tracks_repository.dart';
import 'package:farway/navigation/trip_repository.dart';
import 'package:farway/ui/app_colors.dart';
import 'package:farway/ui/navigation_panel.dart';
import 'package:farway/ui/route_summary_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ui/world_controls.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({super.key});

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  static const _homeLocation = LatLng(63.4305, 10.3951);
  static const _simulationStep = 0.0001;
  static const _useSimulatedLocation = true;

  final FreeModeController _freeController = FreeModeController();
  final NavigationController _navController = NavigationController();
  final TripRecorder _tripRecorder = TripRecorder();
  final _tracksRepository = const TracksRepository();
  final _tripRepository = const TripRepository();

  final _mapController = MapController();

  LatLng? _currentCoords;
  double _heading = 0;
  bool _loading = true;
  bool _mapReady = false;
  String? _error;
  List<List<LatLng>> _routeLines = [];
  List<List<LatLng>> _historicalLines = [];
  StreamSubscription<Position>? _positionSubscription;

  bool _navigationStarted = false; // waiting for navigation start confirmation
  bool _isFinishing = false;

  bool _avoidMotorways = false;
  bool _avoidTolls = false;

  // Whether the camera should keep re-centering on the user's marker.
  // Turned off automatically as soon as the user drags/pinches the map.
  bool _followUser = true;

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
    _fetchHistoricalTracks();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------

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
      setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setCurrentPosition(Position position) {
    if (!mounted) return;

    final currentLatLng = LatLng(position.latitude, position.longitude);

    if (_navigationStarted || _freeController.isFreeMode) {
      _tripRecorder.recordPosition(currentLatLng);
    }

    setState(() {
      _currentCoords = currentLatLng;
      if (position.heading >= 0) _heading = position.heading;
    });

    if (_mapReady && _followUser) _mapController.move(_currentCoords!, 15);
    _updateNavigation();
  }

  /// Re-centers the camera on the user's marker and turns following back on.
  void _toggleFollowUser() {
    setState(() => _followUser = !_followUser);
    if (_followUser && _currentCoords != null && _mapReady) {
      _mapController.move(_currentCoords!, _mapController.camera.zoom);
    }
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
    final longitudeStep = _simulationStep *
        math.sin(angle) /
        math.cos(previous.latitude * math.pi / 180);
    final nextCoords = LatLng(
      previous.latitude + latitudeStep,
      previous.longitude + longitudeStep,
    );

    if (_navigationStarted || _freeController.isFreeMode) {
      _tripRecorder.recordSimulatedStep(previous, nextCoords);
    }

    setState(() {
      _currentCoords = nextCoords;
      _heading = nextHeading;
    });
    
    if (_mapReady && _followUser) {
      _mapController.move(_currentCoords!, _mapController.camera.zoom);
    }

    _updateNavigation();
  }

  // ---------------------------------------------------------------------
  // Historical tracks
  // ---------------------------------------------------------------------

  Future<void> _fetchHistoricalTracks() async {
    try {
      final lines = await _tracksRepository.fetchHistoricalTracks();
      if (!mounted) return;
      setState(() => _historicalLines = lines);
      debugPrint('Loaded blue lines count: ${_historicalLines.length}');
    } catch (e) {
      debugPrint('Error loading cleared roads: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Trip saving
  // ---------------------------------------------------------------------


  Future<void> _finishNavigation() async {
    if (_navController.route == null || _isFinishing) return;
    _isFinishing = true;

    final distanceKm = _tripRecorder.drivenMeters / 1000.0;

    try {
      debugPrint(
        'PAYLOAD CHECK -> distance: $distanceKm, '
        'duration: ${_navController.route!.totalSeconds}, '
        'tracklog: ${_tripRecorder.tracklog}',
      );

      final result = await _tripRepository.saveTrip(
        distanceKm: distanceKm,
        durationSeconds: _navController.route!.totalSeconds.round(),
        tracklog: _tripRecorder.tracklog,
      );
      await _fetchHistoricalTracks();

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Trip finished!',
                style: TextStyle(color: AppColors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earned XP: +${result.earnedXp}',
                    style: const TextStyle(color: AppColors.tealLight)),
                const SizedBox(height: 6),
                Text(
                  'New discovered km: ${result.newClearedKm.toStringAsFixed(2)} km',
                  style: const TextStyle(color: AppColors.white),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _resetNavigation();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving route: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFinishing = false);
      } else {
        _isFinishing = false;
      }
    }
  }

  void _startFreeModeSession() {
    setState(() {
      _resetNavigation();
      _freeController.start();
    });
  }

  Future<void> _handleFreeModeCompletion() async {
    if (_isFinishing || !_freeController.isFreeMode) return;
    setState(() => _isFinishing = true);

    try {
      final response = await _freeController.finishAndSave(
        actualDrivenMeters: _tripRecorder.drivenMeters,
        actualTracklog: _tripRecorder.tracklog,
      );

      debugPrint('Free mode ended, XP/result: $response');
      await _fetchHistoricalTracks();

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Exploration finished!',
                style: TextStyle(color: AppColors.white)),
            content: Text(
              'Driven ${(_tripRecorder.drivenMeters / 1000).toStringAsFixed(2)} km in free mode.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _resetNavigation();
                    _freeController.reset();
                  });
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving free mode: $e');
    } finally {
      if (mounted) setState(() => _isFinishing = false);
    }
  }

  // ---------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------

  Future<void> _onMapTap(TapPosition _, LatLng destination) async {
    final start = _currentCoords ?? _homeLocation;
    debugPrint('Map tap: start=$start, destination=$destination');
    await _fetchRoute(start, destination);
  }

  Future<void> _openDestinationSearch() async {
    final origin = _currentCoords ?? _homeLocation;
    
    final result = await showDestinationSearch(
      context,
      origin: origin,
      initialAvoidMotorways: _avoidMotorways,
      initialAvoidTolls: _avoidTolls,
    );

    if (result == null || !mounted) return;

    // Aktualizujeme stav vyhýbania sa podľa toho, čo používateľ zvolil vo vyhľadávaní
    setState(() {
      _avoidMotorways = result.avoidMotorways;
      _avoidTolls = result.avoidTolls;
    });

    debugPrint('Selected: ${result.name} (${result.point})');
    await _fetchRoute(origin, result.routePoint ?? result.point);
  }

  /// Loads a route from the database. If [reroute] is true, the previous
  /// route stays visible until the new one arrives.
  Future<void> _fetchRoute(
    LatLng start,
    LatLng destination, {
    bool reroute = false,
  }) async {
    if (_navController.isLoading) return;

    setState(() {
      if (!reroute) {
        _routeLines = [];
        _navigationStarted = false;
      }
    });

    try {
      await _navController.fetchRoute(start, destination, reroute: reroute, avoidMotorways: _avoidMotorways, avoidTolls: _avoidTolls);
      if (!mounted) return;
      setState(() {
        _routeLines = [_navController.route!.points];
      });
      final route = _navController.route!;
      debugPrint(
        'Route: ${formatDistance(route.totalMeters)}, '
        '${formatDuration(route.totalSeconds)}, '
        '${route.maneuvers.length} maneuvers.',
      );
    } on RouteNotFoundException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route not found.')),
        );
      }
    } catch (error) {
      debugPrint('Error calling route_with_points_directed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load navigation: $error')),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  /// Called on every position update.
  void _updateNavigation() {
    if (_freeController.isFreeMode) return;
    final position = _currentCoords;
    if (_navController.route == null || position == null) return;

    final update = _navController.updateForPosition(position);

    setState(() {
      if (_navigationStarted) {
        _routeLines = [_navController.trimmedRouteLine()];
      }
    });

    // Do not evaluate arrival or rerouting until navigation has started.
    if (!_navigationStarted) return;

    if (update.arrived) {
      _finishNavigation();
      return;
    }

    if (update.shouldReroute) {
      final destination = _navController.destination;
      if (destination != null) {
        debugPrint('Off route, rerouting.');
        _fetchRoute(position, destination, reroute: true);
      }
    }
  }

  void _resetNavigation() {
    setState(() {
      _navController.reset();
      _routeLines = [];
      _navigationStarted = false;
      _isFinishing = false;
      _tripRecorder.reset();
    });
  }

  Future<void> _cancelNavigation() async {
    // If the user hasn't started yet, or drove less than 300 meters, cancel
    // without prompting.
    if (!_navigationStarted || _tripRecorder.drivenMeters < 300) {
      _resetNavigation();
      return;
    }

    final distanceKm =
        (_tripRecorder.drivenMeters / 1000.0).toStringAsFixed(2);

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('End trip?', style: TextStyle(color: AppColors.white)),
        content: Text(
          'You traveled $distanceKm km. Do you want to save this portion of the route and claim XP?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child:
                const Text('Discard', style: TextStyle(color: AppColors.danger)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('save'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Save & Claim XP',
                style: TextStyle(color: AppColors.background)),
          ),
        ],
      ),
    );

    if (action == 'save') {
      await _finishNavigation();
    } else if (action == 'discard') {
      _resetNavigation();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const WorldLoading();
    if (_error != null || _mapTilesUrl == null) {
      return WorldError(
        message: _error ?? 'MapTiler URL or key is missing',
        onRetry: _refreshLocation,
      );
    }

    final markerPosition = _currentCoords ?? _homeLocation;
    final route = _navController.route;
    final progress = _navController.progress;
    final routeDestination = _navController.destination;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _homeLocation,
              initialZoom: 15,
              onTap: _onMapTap,
              onPositionChanged: (camera, hasGesture) {
                // Only user-driven drags/pinches (hasGesture == true) should
                // break the follow lock — our own _mapController.move calls
                // report hasGesture == false.
                if (hasGesture && _followUser) {
                  setState(() => _followUser = false);
                }
              },
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
                  // 1. Blue historical roads
                  for (final line in _historicalLines)
                    Polyline(
                      points: line,
                      color: Colors.green.withValues(alpha: 0.5),
                      strokeWidth: 4,
                    ),
                  // 2. Active red route
                  for (final line in _routeLines)
                    Polyline(
                      points: line,
                      color: Colors.red,
                      strokeWidth: 5,
                    ),
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
                  if (routeDestination != null)
                    Marker(
                      point: routeDestination,
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
            child: MapButton(
              icon: Icons.directions,
              onPressed: _openDestinationSearch,
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 70,
            right: 20,
            child: MapButton(
              icon: _freeController.isFreeMode ? Icons.stop : Icons.explore,
              onPressed: _freeController.isFreeMode
                  ? _handleFreeModeCompletion
                  : _startFreeModeSession,
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 128,
            right: 20,
            child: MapButton(
              icon: _followUser ? Icons.gps_fixed : Icons.gps_not_fixed,
              onPressed: _toggleFollowUser,
            ),
          ),
          // Top navigation panel, only once navigation has started.
          if (route != null && progress != null && _navigationStarted)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 16,
              right: 84,
              child: NavigationPanel(
                progress: progress,
                offRoute: progress.offRouteM > _navController.offRouteThresholdM,
                rerouting: _navController.isLoading,
                onCancel: _cancelNavigation,
              ),
            ),

          if (_navController.isLoading)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 110,
              left: 20,
              child: const CircularProgressIndicator(color: Colors.red),
            ),

          // Hide D-Pad and location controls during route preview mode.
          if (route == null || _navigationStarted) ...[
            Positioned(
              left: 16,
              bottom: 24,
              child: DebugDPad(onMove: _moveSimulated),
            ),
            if (_freeController.isFreeMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Material(
                    color: AppColors.surface,
                    elevation: 16,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Free City Exploration',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Traveled: ${(_tripRecorder.drivenMeters / 1000).toStringAsFixed(2)} km',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _handleFreeModeCompletion,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.teal,
                                foregroundColor: AppColors.background,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 32),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('End Exploration',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        
                      ),
                    ),
                  ),
                ),
              ),
              // Spodný panel počas aktívnej navigácie (s tlačidlom na zrušenie/ukončenie)
              if (_navigationStarted && route != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Material(
                      color: AppColors.surface,
                      elevation: 16,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Navigation',
                                      style: TextStyle(
                                        color: AppColors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Distance: ${(_tripRecorder.drivenMeters / 1000).toStringAsFixed(2)} km',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _cancelNavigation,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                  foregroundColor: AppColors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 20),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              // Route preview / XP estimate, before navigation is started.
              if (route != null && !_navigationStarted)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Filter toggles above the route preview
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.95),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FilterChip(
                              label: const Text(
                                'Avoid highways',
                                style: TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              selected: _avoidMotorways,
                              selectedColor: AppColors.teal,
                              backgroundColor: AppColors.background,
                              checkmarkColor: AppColors.background,
                              onSelected: (val) {
                                setState(() => _avoidMotorways = val);
                                final start = _currentCoords ?? _homeLocation;
                                final dest = _navController.destination;
                                if (dest != null) {
                                  _fetchRoute(start, dest, reroute: true);
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            FilterChip(
                              label: const Text(
                                'Avoid tolls',
                                style: TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              selected: _avoidTolls,
                              selectedColor: AppColors.teal,
                              backgroundColor: AppColors.background,
                              checkmarkColor: AppColors.background,
                              onSelected: (val) {
                                setState(() => _avoidTolls = val);
                                final start = _currentCoords ?? _homeLocation;
                                final dest = _navController.destination;
                                if (dest != null) {
                                  _fetchRoute(start, dest, reroute: true);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      
                      // Pôvodný panel s prehľadom
                      RouteSummaryPanel(
                        route: route,
                        onStart: () {
                          setState(() => _navigationStarted = true);
                          if (_currentCoords != null && _mapReady) {
                            _mapController.move(_currentCoords!, 17); // Zoom in
                          }
                        },
                        onCancel: _cancelNavigation,
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}