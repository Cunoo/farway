import 'package:farway/ui/app_colors.dart';
import 'package:flutter/material.dart';

class MapButton extends StatelessWidget {
  const MapButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
  });

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

class DebugDPad extends StatelessWidget {
  const DebugDPad({super.key, required this.onMove});

  final ValueChanged<String> onMove;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          DPadButton(
              icon: Icons.keyboard_arrow_up, onPressed: () => onMove('up')),
          Row(
            children: [
              DPadButton(
                icon: Icons.keyboard_arrow_left,
                onPressed: () => onMove('left'),
              ),
              const SizedBox(width: 4),
              DPadButton(
                icon: Icons.keyboard_arrow_right,
                onPressed: () => onMove('right'),
              ),
            ],
          ),
          DPadButton(
            icon: Icons.keyboard_arrow_down,
            onPressed: () => onMove('down'),
          ),
        ],
      );
}

class DPadButton extends StatelessWidget {
  const DPadButton({super.key, required this.icon, required this.onPressed});

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

class WorldLoading extends StatelessWidget {
  const WorldLoading({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.teal)),
      );
}

class WorldError extends StatelessWidget {
  const WorldError({super.key, required this.message, required this.onRetry});

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