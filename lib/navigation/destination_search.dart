// lib/navigation/destination_search.dart
//
// Vyhladavaci popup, ktory sa vysunie zhora. Pouzivatel zada nazov ulice,
// vysledky sa nacitavaju z databazy (RPC search_streets) a zoradene su
// podla toho, ako daleko su od neho.

import 'dart:async';
import 'dart:math' as math;

import 'package:farway/navigation/route_navigation.dart' show formatDistance;
import 'package:farway/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StreetResult {
  const StreetResult({
    required this.name,
    required this.roadType,
    required this.point,
    required this.distanceM,
  });

  final String name;
  final String roadType;

  /// Cielovy bod (lezi na ceste).
  final LatLng point;

  /// Vzdialenost od pouzivatela v metroch.
  final double distanceM;
}

/// Otvori popup zhora. Vrati vybranu ulicu, alebo null, ak ho pouzivatel zavrel.
Future<StreetResult?> showDestinationSearch(
  BuildContext context, {
  required LatLng origin,
}) {
  return showGeneralDialog<StreetResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Zavrieť',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _DestinationSearch(origin: origin),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _DestinationSearch extends StatefulWidget {
  const _DestinationSearch({required this.origin});

  final LatLng origin;

  @override
  State<_DestinationSearch> createState() => _DestinationSearchState();
}

class _DestinationSearchState extends State<_DestinationSearch> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0; // aby sa starsia odpoved neprepisala novsiu

  String _query = '';
  List<StreetResult> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();

    if (query.length < 2) {
      _requestId++; // zrus pripadne rozbehnute hladanie
      setState(() {
        _query = query;
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _query = query;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    final requestId = ++_requestId;
    setState(() => _loading = true);

    try {
      final response = await Supabase.instance.client
          .rpc(
            'search_streets',
            params: {
              'p_query': query,
              'p_lon': widget.origin.longitude,
              'p_lat': widget.origin.latitude,
              'p_limit': 8,
            },
          )
          .timeout(const Duration(seconds: 8));

      if (!mounted || requestId != _requestId) return;

      final results = <StreetResult>[];
      if (response is List) {
        for (final row in response) {
          if (row is! Map) continue;
          final lon = row['lon'];
          final lat = row['lat'];
          if (lon is! num || lat is! num) continue;
          results.add(
            StreetResult(
              name: (row['name'] ?? '').toString(),
              roadType: (row['road_type'] ?? '').toString(),
              point: LatLng(lat.toDouble(), lon.toDouble()),
              distanceM: (row['distance_m'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
      }

      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      debugPrint('Chyba pri hľadaní ulice: $error');
      setState(() {
        _loading = false;
        _error = 'Hľadanie sa nepodarilo. Skúste to znova.';
      });
    }
  }

  void _select(StreetResult result) => Navigator.of(context).pop(result);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Zvysok obrazovky nad klavesnicou, aby zoznam nikdy netrcal za klavesnicu.
    final maxListHeight = math.max(
      120.0,
      media.size.height - media.viewInsets.bottom - media.padding.top - 140,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: AppColors.surface,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(color: AppColors.white),
                        cursorColor: AppColors.teal,
                        onChanged: _onChanged,
                        onSubmitted: (_) {
                          if (_results.isNotEmpty) _select(_results.first);
                        },
                        decoration: InputDecoration(
                          hintText: 'Kam chcete ísť? Zadajte ulicu',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.teal,
                          ),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.white54,
                                  ),
                                  onPressed: () {
                                    _controller.clear();
                                    _onChanged('');
                                  },
                                ),
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: AppColors.white),
                    ),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 8, right: 8),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.teal,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ..._buildBody(maxListHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(double maxHeight) {
    if (_query.length < 2) {
      return const [_Hint('Zadajte aspoň 2 znaky názvu ulice.')];
    }
    if (_error != null) return [_Hint(_error!, isError: true)];
    if (_results.isEmpty) {
      return [if (!_loading) const _Hint('Nenašla sa žiadna ulica.')];
    }

    return [
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 4, right: 8),
          itemCount: _results.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, color: Colors.white12),
          itemBuilder: (context, index) {
            final result = _results[index];
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.place_outlined, color: AppColors.teal),
              title: Text(
                result.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.white),
              ),
              subtitle: Text(
                '${formatDistance(result.distanceM)} od vás',
                style: const TextStyle(color: Colors.white60),
              ),
              onTap: () => _select(result),
            );
          },
        ),
      ),
    ];
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 8, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: isError ? AppColors.danger : Colors.white60,
          fontSize: 13,
        ),
      ),
    ),
  );
}