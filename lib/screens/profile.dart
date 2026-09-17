import 'package:farway/api/profile_api.dart';
import 'package:farway/auth/service/auth_service.dart';
import 'package:farway/ui/app_colors.dart';
import 'package:farway/utils/level_utils.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _profileApi = ProfileApi();
  final _authService = AuthService();
  late Future<Map<String, dynamic>?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _profileApi.getProfile();
  }

  Future<void> _logout() async {
    try {
      await _authService.logoutUser();
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {
                _profileFuture = _profileApi.getProfile();
              }),
            );
          }

          return _ProfileContent(
            profile: snapshot.data ?? const {},
            onLogout: _logout,
          );
        },
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile, required this.onLogout});

  final Map<String, dynamic> profile;
  final VoidCallback onLogout;

  int _number(String key, [int fallback = 0]) {
    final value = profile[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  String _text(String key, [String fallback = '']) {
    final value = profile[key];
    return value == null || '$value' == 'null' ? fallback : '$value';
  }

  @override
  Widget build(BuildContext context) {
    final username = _text('username', 'Pilot');
    final level = _number('level', 1);
    final totalXp = _number('total_xp');
    final xpProgress = calculateXpProgress(totalXp: totalXp, currentLevel: level);
    final streakDays = _number('streakDays', _number('streak_days', 1));
    final clearedKm = _text('global_cleared_km', '0.0');
    final drivenKm = _text('global_driven_km', '0.0');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _ProfileHeader(
          username: username,
          level: level,
          currentXp: xpProgress.xp,
          nextLevelXp: xpProgress.nextLevelXp,
          progress: xpProgress.percentage / 100,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _StatCard(label: 'CLEARED', value: clearedKm, unit: 'km²', icon: Icons.radar)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(label: 'EXPLORED', value: drivenKm, unit: 'km', icon: Icons.map_outlined)),
          ],
        ),
        const SizedBox(height: 12),
        _StreakCard(days: streakDays),
        const SizedBox(height: 20),
        _AchievementsCard(achievements: profile['achievements']),
        const SizedBox(height: 20),
        const Text('// ACTIVE_VEHICLE', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'monospace')),
        const SizedBox(height: 8),
        _VehicleCard(profile: profile),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.power_settings_new, color: AppColors.danger),
          label: const Text('TERMINATE_SESSION'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.username, required this.level, required this.currentXp, required this.nextLevelXp, required this.progress});

  final String username;
  final int level;
  final int currentXp;
  final int nextLevelXp;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('// PILOT_PROFILE', style: TextStyle(color: AppColors.teal, fontFamily: 'monospace', fontSize: 11)),
          const SizedBox(height: 16),
          Row(
            children: [
              const CircleAvatar(radius: 34, backgroundColor: AppColors.avatar, child: Icon(Icons.person, color: AppColors.tealLight, size: 36)),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('@$username', style: const TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text('TACTICAL RECON  •  LVL $level', style: const TextStyle(color: AppColors.tealLight, fontFamily: 'monospace', fontSize: 11)),
              ]),
            ],
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('XP PROGRESS', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'monospace', fontSize: 11)),
            Text('$currentXp / $nextLevelXp XP', style: const TextStyle(color: AppColors.teal, fontFamily: 'monospace', fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress, minHeight: 10, backgroundColor: AppColors.surface, color: AppColors.teal)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.unit, required this.icon});

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.panel, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          Icon(icon, color: AppColors.teal, size: 28),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: AppColors.teal, fontFamily: 'monospace', fontSize: 10)),
          const SizedBox(height: 4),
          Text('$value $unit', style: const TextStyle(color: AppColors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
      );
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.streakBorder), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          const Icon(Icons.local_fire_department, color: AppColors.orange, size: 36),
          const SizedBox(width: 14),
          const Text('ACTIVE STREAK\n', style: TextStyle(color: AppColors.orange, fontFamily: 'monospace', fontSize: 11)),
          Text('$days DAYS', style: const TextStyle(color: AppColors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 20)),
        ]),
      );
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final vehicle = profile['vehicle'] is Map ? Map<String, dynamic>.from(profile['vehicle'] as Map) : <String, dynamic>{};
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      tileColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
      leading: const Icon(Icons.directions_car, color: AppColors.teal, size: 30),
      title: Text('${vehicle['brand'] ?? 'Standard Vehicle'}', style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
      subtitle: Text('${vehicle['color'] ?? 'undefined'}', style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'monospace')),
      trailing: const Text('MODS', style: TextStyle(color: AppColors.tealLight, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({required this.achievements});

  final dynamic achievements;

  @override
  Widget build(BuildContext context) {
    final items = achievements is List ? achievements : const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('// UNLOCKED_BADGES', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'monospace', fontSize: 12)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (index) {
            final item = index < items.length && items[index] is Map ? Map<String, dynamic>.from(items[index] as Map) : <String, dynamic>{};
            final unlocked = item['unlocked'] == true;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: index == 3 ? 0 : 8),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                decoration: BoxDecoration(
                  color: unlocked ? AppColors.badgePanel : AppColors.background,
                  border: Border.all(color: unlocked ? AppColors.teal : AppColors.darkBorder),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Icon(unlocked ? Icons.emoji_events_outlined : Icons.lock_outline, color: unlocked ? AppColors.teal : AppColors.locked, size: 22),
                  const SizedBox(height: 6),
                  Text(unlocked ? '${item['name'] ?? 'Badge'}' : '???', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'monospace', fontSize: 9)),
                ]),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mutedWhite)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}