// lib/navigation/world.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:farway/navigation/destination_search.dart';
import 'package:farway/navigation/free_mode_controller.dart';
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

  // Navigation settings
  static const _offRouteThresholdM = 30.0; // distance threshold considered off-route
  static const _offRouteUpdates = 3; // consecutive updates required
  static const _rerouteCooldown = Duration(seconds: 8);
  static const _arrivalThresholdM = 15.0;
  double _actualDrivenMeters = 0.0;
  LatLng? _lastRecordedPosition;
  final List<List<double>> _actualTracklog = [];
  static const _tracklogMinDistanceM = 8.0; // minimum movement in meters for a new tracklog point
  LatLng? _lastTracklogLatLng;
  List<List<LatLng>> _historicalLines = [];
  final FreeModeController _freeController = FreeModeController();

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

  // Navigation state
  RouteData? _route;
  RouteProgress? _progress;
  int _offRouteCount = 0;
  DateTime? _lastReroute;
  bool _navigationStarted = false; // New state: waiting for navigation start confirmation
  bool _isFinishing = false;

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

  Future<void> _fetchHistoricalTracks() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final dynamic response = await Supabase.instance.client.rpc(
        'get_user_cleared_geometries',
        params: {'p_user_id': userId},
      );

      List<dynamic> geometriesList = [];
      if (response is List) {
        if (response.isNotEmpty &&
            response.first is Map &&
            response.first.containsKey('get_user_cleared_geometries')) {
          geometriesList =
              response.first['get_user_cleared_geometries'] as List? ?? [];
        } else {
          geometriesList = response;
        }
      } else if (response is Map &&
          response.containsKey('get_user_cleared_geometries')) {
        geometriesList =
            response['get_user_cleared_geometries'] as List? ?? [];
      }

      final lines = <List<LatLng>>[];
      for (final item in geometriesList) {
        if (item is Map) {
          final points = _parseGeoJsonCoordinates(item['coordinates']);
          if (points.isNotEmpty) lines.add(points);
        }
      }
      setState(() => _historicalLines = lines);
      debugPrint('Loaded blue lines count: ${_historicalLines.length}');
    } catch (e) {
      debugPrint('Error loading cleared roads: $e');
    }
  }

  List<LatLng> _parseGeoJsonCoordinates(dynamic coords) {
    final result = <LatLng>[];
    if (coords is! List) return result;

    // Detect if MultiLineString (3 nested levels) or LineString (2 nested levels)
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

  Future<void> _handleTripCompletion() async {
    if (_isFinishing || _route == null) return;
    setState(() => _isFinishing = true);

    try {
      // 1. Get data from existing state in _WorldState
      final double distanceKm = _actualDrivenMeters / 1000.0;
      final int durationSeconds = _route!.totalSeconds.round();
      
      // _actualTracklog already stores [lat, lon], send directly
      final tracklogJson = _actualTracklog;

      // 2. Call Supabase RPC function
      final response = await Supabase.instance.client.rpc(
        'save_trip_and_calculate_xp',
        params: {
          'p_distance_km': distanceKm,
          'p_duration_seconds': durationSeconds,
          'p_tracklog': tracklogJson,
        },
      );

      debugPrint('Trip finished, RPC result: $response');

      // 3. Immediately load newly created blue lines on the map
      await _fetchHistoricalTracks();

      // 4. UI state cleanup
      if (mounted) {
        _resetNavigation();
      }
    } catch (e) {
      debugPrint('Error finishing trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving route: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFinishing = false);
    }
  }

  void _setCurrentPosition(Position position) {
    if (!mounted) return;
    
    final currentLatLng = LatLng(position.latitude, position.longitude);

    setState(() {
      _currentCoords = currentLatLng;
      if (position.heading >= 0) _heading = position.heading;

      if (_navigationStarted || _freeController.isFreeMode) {
        if (_lastRecordedPosition != null) {
          final distance = const Distance().as(
            LengthUnit.Meter,
            _lastRecordedPosition!,
            currentLatLng,
          );
          if (distance > 0 && distance < 150) { 
            _actualDrivenMeters += distance;
          }
        }
        _lastRecordedPosition = currentLatLng;

        if (_lastTracklogLatLng == null ||
          const Distance().as(LengthUnit.Meter, _lastTracklogLatLng!, currentLatLng) >= _tracklogMinDistanceM) {
          _actualTracklog.add([currentLatLng.latitude, currentLatLng.longitude]);
          _lastTracklogLatLng = currentLatLng;
        }
      }
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

    // Calculate and record driven distance
    final stepDist = const Distance()(previous, nextCoords);
    _actualDrivenMeters += stepDist;

    if (_navigationStarted || _freeController.isFreeMode) {
      if (_lastTracklogLatLng == null ||
          const Distance().as(LengthUnit.Meter, _lastTracklogLatLng!, nextCoords) >= _tracklogMinDistanceM) {
        _actualTracklog.add([nextCoords.latitude, nextCoords.longitude]);
        _lastTracklogLatLng = nextCoords;
      }
    }

    setState(() {
      _currentCoords = nextCoords;
      _heading = nextHeading;
    });
    
    _updateNavigation();
  }

  Future<void> _openDestinationSearch() async {
    final origin = _currentCoords ?? _homeLocation;
    final result = await showDestinationSearch(context, origin: origin);
    if (result == null || !mounted) return;
    debugPrint('Selected street: ${result.name} (${result.point})');
    await _fetchRoute(origin, result.point);
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
        actualDrivenMeters: _actualDrivenMeters,
        actualTracklog: _actualTracklog,
      );

      debugPrint('Free mode ended, XP/result: $response');
      await _fetchHistoricalTracks();

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Exploration finished!', style: TextStyle(color: AppColors.white)),
            content: Text(
              'Driven ${(_actualDrivenMeters / 1000).toStringAsFixed(2)} km in free mode.',
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

  /// Loads route from database. If [reroute] = true, old route remains
  /// visible until the new one arrives.
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
        _navigationStarted = false; // Reset start flag on new route
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
      debugPrint('route_with_points_directed returned ${rows.length} rows.');

      final route = RouteData.tryParse(rows);
      if (!mounted) return;

      if (route == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route not found.')),
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
        'Route: ${formatDistance(route.totalMeters)}, '
        '${formatDuration(route.totalSeconds)}, '
        '${route.maneuvers.length} maneuvers.',
      );
    } catch (error) {
      debugPrint('Error calling route_with_points_directed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load navigation: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  /// Called on every position update.
  void _updateNavigation() {
    if (_freeController.isFreeMode) return;
    final route = _route;
    final position = _currentCoords;
    if (route == null || position == null || _routeLoading) return;

    final progress = route.project(
      position,
      hintMeters: _progress?.alongM ?? 0,
    );

    // Calculate red line trimming behind vehicle if navigation is active
    List<List<LatLng>> updatedLines = _routeLines;
    if (_navigationStarted) {
      int startIndex = 0;
      for (int i = 0; i < route.cumulative.length; i++) {
        if (route.cumulative[i] >= progress.alongM) {
          startIndex = math.max(0, i - 1);
          break;
        }
      }
      updatedLines = [[progress.snapped, ...route.points.skip(startIndex)]];
    }

    setState(() {
      _progress = progress;
      if (_navigationStarted) {
        _routeLines = updatedLines;
      }
    });

    // Do not evaluate arrival or rerouting until navigation has been started
    if (!_navigationStarted) return;

    if (progress.remainingM < _arrivalThresholdM) {
      _finishNavigation();
      return;
    }

    _offRouteCount = progress.offRouteM > _offRouteThresholdM
        ? _offRouteCount + 1
        : 0;

    final destination = _routeDestination;
    final last = _lastReroute;
    final cooledDown =
        last == null || DateTime.now().difference(last) > _rerouteCooldown;

    if (_offRouteCount >= _offRouteUpdates &&
        destination != null &&
        cooledDown) {
      _offRouteCount = 0;
      debugPrint('Off route (${progress.offRouteM.round()} m), rerouting.');
      _fetchRoute(position, destination, reroute: true);
    }
  }

  Future<void> _finishNavigation() async {
    if (_route == null || _isFinishing) return;
    _isFinishing = true;
    
    final distanceKm = _actualDrivenMeters / 1000.0;
    
    try {
      debugPrint('PAYLOAD CHECK -> distance: $distanceKm, duration: ${_route!.totalSeconds}, tracklog: $_actualTracklog');

      final response = await Supabase.instance.client.rpc(
        'save_trip_and_calculate_xp',
        params: {
          'p_distance_km': distanceKm,
          'p_duration_seconds': _route!.totalSeconds.round(),
          'p_tracklog': _actualTracklog,
        },
      );

      int earnedXp = 0;
      double newClearedKm = 0.0;

      if (response is List && response.isNotEmpty) {
        final row = response.first;
        earnedXp = (row['earned_xp'] as num?)?.toInt() ?? 0;
        newClearedKm = (row['new_cleared_km'] as num?)?.toDouble() ?? 0.0;
      }

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Trip finished!', style: TextStyle(color: AppColors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earned XP: +$earnedXp', style: const TextStyle(color: AppColors.tealLight)),
                const SizedBox(height: 6),
                Text('New discovered km: ${newClearedKm.toStringAsFixed(2)} km', style: const TextStyle(color: AppColors.white)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(); // close dialog
                  _resetNavigation(); // clear route and reset state instead of popping root page
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

  void _resetNavigation() {
    setState(() {
      _route = null;
      _progress = null;
      _routeLines = [];
      _routeDestination = null;
      _offRouteCount = 0;
      _navigationStarted = false;
      _isFinishing = false;
      
      _actualDrivenMeters = 0.0;
      _lastRecordedPosition = null;
      _lastTracklogLatLng = null;
      _actualTracklog.clear();
    });
  }

  Future<void> _cancelNavigation() async {
    // If user hasn't started yet or drove less than 300 meters, cancel without prompt
    if (!_navigationStarted || _actualDrivenMeters < 300) {
      _resetNavigation();
      return;
    }

    // If sufficient distance covered, ask user what to do
    final distanceKm = (_actualDrivenMeters / 1000.0).toStringAsFixed(2);

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'End trip?',
          style: TextStyle(color: AppColors.white),
        ),
        content: Text(
          'You traveled $distanceKm km. Do you want to save this portion of the route and claim XP?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard', style: TextStyle(color: AppColors.danger)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('save'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Save & Claim XP', style: TextStyle(color: AppColors.background)),
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
          Positioned(
            top: MediaQuery.paddingOf(context).top + 70,
            right: 20,
            child: _MapButton(
              icon: _freeController.isFreeMode ? Icons.stop : Icons.explore,
              onPressed: _freeController.isFreeMode
                  ? _handleFreeModeCompletion
                  : _startFreeModeSession,
            ),
          ),
          // Show top navigation panel only if navigation has started
          if (route != null && progress != null && _navigationStarted)
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
            
          // Hide D-Pad and location controls during route preview mode
          if (_route == null || _navigationStarted) ...[
            Positioned(
              left: 16,
              bottom: 24,
              child: _DebugDPad(onMove: _moveSimulated),
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Free City Exploration',
                            style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Traveled: ${(_actualDrivenMeters / 1000).toStringAsFixed(2)} km',
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _handleFreeModeCompletion,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.teal,
                              foregroundColor: AppColors.background,
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('End Exploration', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // Show bottom sheet for route preview and XP estimation (before start)
          if (route != null && !_navigationStarted)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _RouteSummaryPanel(
                route: route,
                onStart: () {
                  setState(() => _navigationStarted = true);
                  if (_currentCoords != null && _mapReady) {
                    _mapController.move(_currentCoords!, 17); // Zoom closer on start
                  }
                },
                onCancel: _cancelNavigation,
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

// ---------------------------------------------------------------------
// Map UI widgets
// ---------------------------------------------------------------------

class _RouteSummaryPanel extends StatelessWidget {
  const _RouteSummaryPanel({
    required this.route,
    required this.onStart,
    required this.onCancel,
  });

  final RouteData route;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // Estimated XP calculation: min = 1 XP/km (traveled all), max = 2 XP/km (all new)
    final distanceKm = route.totalMeters / 1000;
    final minXp = (distanceKm * 1).round();
    final maxXp = (distanceKm * 2).round();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: AppColors.surface,
        elevation: 16,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryItem(
                      icon: Icons.route,
                      value: formatDistance(route.totalMeters),
                      label: 'Distance',
                    ),
                    _SummaryItem(
                      icon: Icons.timer,
                      value: formatDuration(route.totalSeconds),
                      label: 'Estimate',
                    ),
                    _SummaryItem(
                      icon: Icons.star_rounded,
                      value: '$minXp - $maxXp XP',
                      label: 'Reward',
                      iconColor: Colors.amber,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: onStart,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.teal,
                          foregroundColor: AppColors.background,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Start Navigation',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = AppColors.teal,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
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
        ? 'You have arrived'
        : '${formatDistance(progress.toNextM)} · ${next.text}';
    final status = offRoute || rerouting
        ? 'Off route, rerouting…'
        : 'Remaining ${formatDistance(progress.remainingM)} · '
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