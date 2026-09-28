// lib/navigation/route_navigation.dart
//
// Pure Dart navigation logic (without Flutter widgets):
//  - assembles a route from lines returned by route_with_points_directed
//  - calculates turn-by-turn instructions (left/right/...)
//  - maps GPS location to the route (remaining distance, time, next instruction)
//  - detects if the user is off-route

import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const Distance _distance = Distance();

// Conversion of degrees to meters (approximate, for short distances).
const double _metersPerDegree = 111195;

// How far ahead/back we look when calculating the turn direction.
const double _lookAroundMeters = 15;

// ---------------------------------------------------------------------------
// Instructions
// ---------------------------------------------------------------------------

enum TurnType {
  depart,
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
  arrive,
}

class Maneuver {
  const Maneuver({
    required this.type,
    required this.atMeters,
    required this.roadName,
  });

  final TurnType type;

  /// Distance from the start of the route where the maneuver takes place.
  final double atMeters;

  /// Name of the road being turned onto ('' if unnamed).
  final String roadName;

  String get text {
    final on = roadName.isEmpty ? '' : ' onto $roadName';
    return switch (type) {
      TurnType.depart =>
        roadName.isEmpty ? 'Depart' : 'Depart onto $roadName',
      TurnType.straight =>
        roadName.isEmpty ? 'Continue straight' : 'Continue on $roadName',
      TurnType.slightLeft => 'Slight left$on',
      TurnType.left => 'Turn left$on',
      TurnType.sharpLeft => 'Sharp left$on',
      TurnType.slightRight => 'Slight right$on',
      TurnType.right => 'Turn right$on',
      TurnType.sharpRight => 'Sharp right$on',
      TurnType.uTurn => 'Make a u-turn$on',
      TurnType.arrive => 'You have arrived',
    };
  }
}

// ---------------------------------------------------------------------------
// Route Progress
// ---------------------------------------------------------------------------

class RouteProgress {
  const RouteProgress({
    required this.snapped,
    required this.alongM,
    required this.offRouteM,
    required this.remainingM,
    required this.remainingS,
    required this.next,
    required this.toNextM,
  });

  /// User location snapped to the route.
  final LatLng snapped;

  /// Meters traveled from the start of the route.
  final double alongM;

  /// Distance off the route in meters.
  final double offRouteM;

  final double remainingM;
  final double remainingS;

  /// Nearest upcoming maneuver (null if none remaining).
  final Maneuver? next;
  final double toNextM;
}

// ---------------------------------------------------------------------------
// Route Data
// ---------------------------------------------------------------------------

class _Step {
  _Step({
    required this.name,
    required this.durationS,
    required this.startIdx,
    required this.endIdx,
  });

  final String name;
  final double durationS;
  final int startIdx;
  final int endIdx;
}

class _Hit {
  _Hit(this.snapped, this.alongM, this.distanceM);
  final LatLng snapped;
  final double alongM;
  final double distanceM;
}

class RouteData {
  RouteData._({
    required this.points,
    required this.cumulative,
    required this.maneuvers,
    required List<_Step> steps,
  }) : _steps = steps;

  /// Full route as a single continuous polyline in driving direction.
  final List<LatLng> points;

  /// cumulative[i] = distance in meters from start to points[i].
  final List<double> cumulative;

  final List<Maneuver> maneuvers;
  final List<_Step> _steps;

  double get totalMeters => cumulative.last;
  double get totalSeconds => _steps.fold(0.0, (sum, s) => sum + s.durationS);

  /// Assembles route from route_with_points_directed RPC rows.
  /// Returns null if rows do not contain usable geometry.
  static RouteData? tryParse(List<Map> rows) {
    final sorted = [...rows]
      ..sort((a, b) => _asDouble(a['seq']).compareTo(_asDouble(b['seq'])));

    final points = <LatLng>[];
    final steps = <_Step>[];

    for (final row in sorted) {
      final line = parseGeometry(row['geom']);
      if (line.length < 2) continue;

      // Avoid duplicating shared point when connecting segments.
      final skip =
          points.isNotEmpty && _distance(points.last, line.first) < 2 ? 1 : 0;
      final startIdx = skip == 1 ? points.length - 1 : points.length;
      points.addAll(line.skip(skip));

      steps.add(
        _Step(
          name: (row['name'] ?? '').toString(),
          durationS: _asDouble(row['cost']),
          startIdx: startIdx,
          endIdx: points.length - 1,
        ),
      );
    }

    if (points.length < 2 || steps.isEmpty) return null;

    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(cumulative.last + _distance(points[i - 1], points[i]));
    }

    return RouteData._(
      points: points,
      cumulative: cumulative,
      maneuvers: _buildManeuvers(points, cumulative, steps),
      steps: steps,
    );
  }

  /// Projects position onto the route and calculates progress.
  ///
  /// [hintMeters] is the last known progress: search around it first
  /// to prevent snapping to overlapping route segments.
  RouteProgress project(LatLng position, {double hintMeters = 0}) {
    var hit = _nearest(position, hintMeters - 50, hintMeters + 400);
    if (hit == null || hit.distanceM > 40) {
      hit = _nearest(position, double.negativeInfinity, double.infinity)!;
    }

    final remainingM = math.max(0.0, totalMeters - hit.alongM);

    var remainingS = 0.0;
    for (final s in _steps) {
      final startM = cumulative[s.startIdx];
      final endM = cumulative[s.endIdx];
      final len = endM - startM;
      if (len <= 0) continue;
      if (hit.alongM <= startM) {
        remainingS += s.durationS;
      } else if (hit.alongM < endM) {
        remainingS += s.durationS * (endM - hit.alongM) / len;
      }
    }

    Maneuver? next;
    for (final m in maneuvers) {
      if (m.atMeters > hit.alongM + 5) {
        next = m;
        break;
      }
    }

    return RouteProgress(
      snapped: hit.snapped,
      alongM: hit.alongM,
      offRouteM: hit.distanceM,
      remainingM: remainingM,
      remainingS: remainingS,
      next: next,
      toNextM: next == null ? 0 : math.max(0.0, next.atMeters - hit.alongM),
    );
  }

  _Hit? _nearest(LatLng p, double minM, double maxM) {
    _Hit? best;
    final cosLat = math.cos(p.latitudeInRad);

    for (var i = 0; i < points.length - 1; i++) {
      if (cumulative[i + 1] < minM || cumulative[i] > maxM) continue;

      // Local planar coordinate system in meters centered at user position.
      final ax = (points[i].longitude - p.longitude) * cosLat * _metersPerDegree;
      final ay = (points[i].latitude - p.latitude) * _metersPerDegree;
      final bx =
          (points[i + 1].longitude - p.longitude) * cosLat * _metersPerDegree;
      final by = (points[i + 1].latitude - p.latitude) * _metersPerDegree;

      final dx = bx - ax;
      final dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0).toDouble();

      final px = ax + t * dx;
      final py = ay + t * dy;
      final dist = math.sqrt(px * px + py * py);

      if (best == null || dist < best.distanceM) {
        best = _Hit(
          LatLng(
            points[i].latitude + t * (points[i + 1].latitude - points[i].latitude),
            points[i].longitude +
                t * (points[i + 1].longitude - points[i].longitude),
          ),
          cumulative[i] + t * (cumulative[i + 1] - cumulative[i]),
          dist,
        );
      }
    }
    return best;
  }

  // -------------------------------------------------------------------------
  // Turn Maneuvers
  // -------------------------------------------------------------------------

  static List<Maneuver> _buildManeuvers(
    List<LatLng> pts,
    List<double> cum,
    List<_Step> steps,
  ) {
    final result = <Maneuver>[
      Maneuver(type: TurnType.depart, atMeters: 0, roadName: steps.first.name),
    ];

    for (var i = 1; i < steps.length; i++) {
      final j = steps[i].startIdx; // index of junction point
      final k = _walk(pts, j, -1);
      final m = _walk(pts, j, 1);
      if (k == j || m == j) continue;

      final angle = _normalize(
        _bearing(pts[j], pts[m]) - _bearing(pts[k], pts[j]),
      );
      final type = _classify(angle);

      final nameChanged =
          steps[i].name.isNotEmpty && steps[i].name != steps[i - 1].name;

      // Straight continuation on the same road requires no maneuver.
      if (type == TurnType.straight && !nameChanged) continue;

      result.add(
        Maneuver(type: type, atMeters: cum[j], roadName: steps[i].name),
      );
    }

    result.add(
      Maneuver(type: TurnType.arrive, atMeters: cum.last, roadName: ''),
    );
    return result;
  }

  /// Walks from [from] in direction [dir] (+1 / -1) until at least
  /// _lookAroundMeters away. Returns last point if limit not reached.
  static int _walk(List<LatLng> pts, int from, int dir) {
    var i = from;
    while (true) {
      final next = i + dir;
      if (next < 0 || next >= pts.length) return i;
      i = next;
      if (_distance(pts[from], pts[i]) >= _lookAroundMeters) return i;
    }
  }

  static TurnType _classify(double angle) {
    final a = angle.abs();
    final right = angle > 0;
    if (a < 25) return TurnType.straight;
    if (a < 60) return right ? TurnType.slightRight : TurnType.slightLeft;
    if (a < 130) return right ? TurnType.right : TurnType.left;
    if (a < 170) return right ? TurnType.sharpRight : TurnType.sharpLeft;
    return TurnType.uTurn;
  }

  /// Bearing from point a to point b in degrees (0 = north, clockwise).
  static double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitudeInRad;
    final lat2 = b.latitudeInRad;
    final dLon = b.longitudeInRad - a.longitudeInRad;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x) * 180 / math.pi;
  }

  /// Normalizes angle to range (-180, 180].
  static double _normalize(double degrees) {
    var x = degrees % 360; // Dart modulo is always >= 0
    if (x > 180) x -= 360;
    return x;
  }
}

// ---------------------------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------------------------

double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

/// Converts GeoJSON (string or map) to list of points.
List<LatLng> parseGeometry(dynamic geometry) {
  if (geometry is String) {
    try {
      return parseGeometry(jsonDecode(geometry));
    } catch (_) {
      return [];
    }
  }
  if (geometry is! Map) return [];

  final coordinates = geometry['coordinates'];
  if (coordinates is! List) return [];

  final type = geometry['type']?.toString().toLowerCase();
  if (type == 'linestring') {
    return coordinates.map(_toLatLng).whereType<LatLng>().toList();
  }
  if (type == 'multilinestring') {
    return [
      for (final line in coordinates)
        if (line is List) ...line.map(_toLatLng).whereType<LatLng>(),
    ];
  }
  return [];
}

LatLng? _toLatLng(dynamic c) {
  if (c is! List || c.length < 2 || c[0] is! num || c[1] is! num) return null;
  return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
}

/// 180 -> "180 m", 1450 -> "1.5 km"
String formatDistance(double meters) {
  if (meters < 1000) {
    final rounded =
        meters < 100 ? (meters / 5).round() * 5 : (meters / 10).round() * 10;
    return '$rounded m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// 45 s -> "1 min", 4200 s -> "1 h 10 min"
String formatDuration(double seconds) {
  final minutes = math.max(1, (seconds / 60).ceil());
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '$h h ${m.toString().padLeft(2, '0')} min';
}