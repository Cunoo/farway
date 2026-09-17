import 'dart:math' as math;

class XpProgress {
  const XpProgress({required this.xp, required this.nextLevelXp, required this.percentage});

  final int xp;
  final int nextLevelXp;
  final int percentage;
}

int _getXpForLevel(int level) {
  if (level <= 1) return 0;
  final safeLevel = level > 1000 ? 1000 : level;
  return (20 * math.pow(safeLevel - 1, 1.65)).floor();
}

XpProgress calculateXpProgress({num totalXp = 0, num currentLevel = 1}) {
  final safeXp = totalXp.isFinite ? totalXp.clamp(0, double.infinity).toInt() : 0;
  final safeLevel = currentLevel.isFinite ? currentLevel.clamp(1, 1000).toInt() : 1;

  if (safeLevel >= 1000) {
    return const XpProgress(xp: 0, nextLevelXp: 0, percentage: 100);
  }

  final currentLevelBaseXp = _getXpForLevel(safeLevel);
  final nextLevelBaseXp = _getXpForLevel(safeLevel + 1);
  final xp = (safeXp - currentLevelBaseXp).clamp(0, double.infinity).toInt();
  final nextLevelXp = (nextLevelBaseXp - currentLevelBaseXp).clamp(1, double.infinity).toInt();
  final percentage = ((xp / nextLevelXp) * 100).floor().clamp(0, 100);

  return XpProgress(xp: xp, nextLevelXp: nextLevelXp, percentage: percentage);
}