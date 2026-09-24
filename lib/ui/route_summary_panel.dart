// lib/ui/route_summary_panel.dart

import 'package:farway/navigation/route_navigation.dart';
import 'package:farway/ui/app_colors.dart';
import 'package:flutter/material.dart';

/// Bottom sheet shown after a route is found but before the user has
/// confirmed they want to start navigating: distance/ETA/XP estimate plus
/// Start/Cancel actions.
class RouteSummaryPanel extends StatelessWidget {
  const RouteSummaryPanel({
    super.key,
    required this.route,
    required this.onStart,
    required this.onCancel,
  });

  final RouteData route;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // Estimated XP: min = 1 XP/km (all previously traveled), max = 2 XP/km
    // (all newly discovered).
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
