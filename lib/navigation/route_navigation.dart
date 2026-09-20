// lib/navigation/route_navigation.dart
//
// Cista Dart logika navigacie (bez Flutter widgetov):
//  - zlozi trasu z riadkov, ktore vracia route_with_points_directed
//  - vypocita pokyny na odbocenie (vlavo/vpravo/...)
//  - priradi GPS polohu k trase (zostavajuca vzdialenost, cas, dalsi pokyn)
//  - zisti, ci je pouzivatel mimo trasy

import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const Distance _distance = Distance();

// Prepocet stupnov na metre (priblizne, pre kratke vzdialenosti).
const double _metersPerDegree = 111195;

// Ako daleko dopredu/dozadu sa pozerame pri vypocte smeru odbocky.
const double _lookAroundMeters = 15;

// ---------------------------------------------------------------------------
// Pokyny
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

  /// Vzdialenost od zaciatku trasy, kde sa pokyn vykona.
  final double atMeters;

  /// Nazov ulice, na ktoru sa odbocuje ('' ak nema nazov).
  final String roadName;

  String get text {
    final on = roadName.isEmpty ? '' : ' na $roadName';
    return switch (type) {
      TurnType.depart =>
        roadName.isEmpty ? 'Vyrazte' : 'Vyrazte po $roadName',
      TurnType.straight =>
        roadName.isEmpty ? 'Pokračujte rovno' : 'Pokračujte po $roadName',
      TurnType.slightLeft => 'Mierne doľava$on',
      TurnType.left => 'Odbočte doľava$on',
      TurnType.sharpLeft => 'Ostro doľava$on',
      TurnType.slightRight => 'Mierne doprava$on',
      TurnType.right => 'Odbočte doprava$on',
      TurnType.sharpRight => 'Ostro doprava$on',
      TurnType.uTurn => 'Otočte sa$on',
      TurnType.arrive => 'Ste v cieli',
    };
  }
}

// ---------------------------------------------------------------------------
// Postup po trase
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

  /// Poloha pouzivatela premietnuta na trasu.
  final LatLng snapped;

  /// Kolko metrov od zaciatku trasy uz presiel.
  final double alongM;

  /// Ako daleko od trasy je (metre).
  final double offRouteM;

  final double remainingM;
  final double remainingS;

  /// Najblizsi nasledujuci pokyn (null, ak uz nie je ziadny).
  final Maneuver? next;
  final double toNextM;
}

// ---------------------------------------------------------------------------
// Trasa
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

  /// Cela trasa ako jedna suvisla ciara v smere jazdy.
  final List<LatLng> points;

  /// cumulative[i] = vzdialenost v metroch od zaciatku trasy po points[i].
  final List<double> cumulative;

  final List<Maneuver> maneuvers;
  final List<_Step> _steps;

  double get totalMeters => cumulative.last;
  double get totalSeconds => _steps.fold(0.0, (sum, s) => sum + s.durationS);

  /// Zlozi trasu z riadkov RPC route_with_points_directed.
  /// Vrati null, ak riadky neobsahuju pouzitelnu geometriu.
  static RouteData? tryParse(List<Map> rows) {
    final sorted = [...rows]
      ..sort((a, b) => _asDouble(a['seq']).compareTo(_asDouble(b['seq'])));

    final points = <LatLng>[];
    final steps = <_Step>[];

    for (final row in sorted) {
      final line = parseGeometry(row['geom']);
      if (line.length < 2) continue;

      // Ak sa usek napaja na koniec predchadzajuceho, spolocny bod nevkladame 2x.
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

  /// Premietne polohu na trasu a vypocita postup.
  ///
  /// [hintMeters] je posledny znamy postup: hladame najprv len v okoli neho,
  /// aby sa poloha neprilepila na iny usek, ak trasa prechadza tym istym
  /// miestom dvakrat.
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

      // Lokalna rovinna sustava v metroch so stredom v polohe pouzivatela.
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
  // Pokyny na odbocenie
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
      final j = steps[i].startIdx; // index bodu, kde sa useky stretavaju
      final k = _walk(pts, j, -1);
      final m = _walk(pts, j, 1);
      if (k == j || m == j) continue;

      final angle = _normalize(
        _bearing(pts[j], pts[m]) - _bearing(pts[k], pts[j]),
      );
      final type = _classify(angle);

      final nameChanged =
          steps[i].name.isNotEmpty && steps[i].name != steps[i - 1].name;

      // Rovno po tej istej ulici nie je potrebny pokyn.
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

  /// Ide od bodu [from] v smere [dir] (+1 / -1), kym nie je aspon
  /// _lookAroundMeters daleko. Ak sa nedostane dost daleko, vrati posledny bod.
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

  /// Smer z bodu a do bodu b v stupnoch (0 = sever, v smere hodinovych ruciciek).
  static double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitudeInRad;
    final lat2 = b.latitudeInRad;
    final dLon = b.longitudeInRad - a.longitudeInRad;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x) * 180 / math.pi;
  }

  /// Uhol do rozsahu (-180, 180].
  static double _normalize(double degrees) {
    var x = degrees % 360; // v Darte je vysledok vzdy >= 0
    if (x > 180) x -= 360;
    return x;
  }
}

// ---------------------------------------------------------------------------
// Pomocne funkcie
// ---------------------------------------------------------------------------

double _asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

/// Prevedie GeoJSON (text alebo mapu) na zoznam bodov.
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