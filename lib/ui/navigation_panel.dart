// lib/ui/navigation_panel.dart

import 'package:farway/navigation/route_navigation.dart';
import 'package:farway/ui/app_colors.dart';
import 'package:flutter/material.dart';

/// Top status panel shown during an active turn-by-turn navigation session:
/// next maneuver, remaining distance/time, off-route/rerouting status, and a
/// cancel button.
class NavigationPanel extends StatelessWidget {
  const NavigationPanel({
    super.key,
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
