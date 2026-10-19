import 'dart:math';

/// Pure-Dart game math for Daily Bloom. No Flutter imports so it stays
/// unit-testable and reusable from the notifier, widgets, and server
/// tuning scripts.
///
/// Levels: 1..100, exponential cost.
/// Ranks: Seedling 1-10, Sprout 11-25, Bonsai 26-45, Lotus 46-70,
/// Sakura Bloom 71-100.
enum BloomRank { seedling, sprout, bonsai, lotus, sakura }

/// Variable reward from a daily ritual.
class MysteryReward {
  final int tokens;
  final bool isCritical;

  const MysteryReward(this.tokens, {this.isCritical = false});
}

/// Tunables in one place — balance the whole game here.
abstract class BloomEngine {
  static const int maxLevel = 100;

  /// 15-minute window: completions inside it build the Flow Combo.
  static const Duration comboWindow = Duration(minutes: 15);

  /// Base XP per task before combo bonus.
  static const int baseTaskXp = 50;

  /// Odds: 70% → 10, 25% → 50, 5% → 250 (Critical Bloom).
  static MysteryReward rollMysteryBloom([Random? random]) {
    final r = (random ?? Random()).nextDouble();
    if (r < 0.70) return const MysteryReward(10);
    if (r < 0.95) return const MysteryReward(50);
    return const MysteryReward(250, isCritical: true);
  }

  /// XP needed to go from [level] to [level + 1].
  /// Exponential: 100 * 1.12^(level-1). L1→120ish, L100→~8M.
  static int xpToNext(int level) {
    if (level >= maxLevel) return 0;
    final l = level.clamp(1, maxLevel - 1);
    return (100 * pow(1.12, l - 1)).round();
  }

  /// Total cumulative XP required to *reach* [level] from 0.
  static int totalXpForLevel(int level) {
    var total = 0;
    for (var l = 1; l < level.clamp(1, maxLevel); l++) {
      total += xpToNext(l);
    }
    return total;
  }

  /// Highest level whose cumulative cost is <= [totalXp].
  static int levelForTotalXp(int totalXp) {
    var acc = 0;
    for (var l = 1; l <= maxLevel; l++) {
      final need = xpToNext(l);
      if (need == 0) return maxLevel;
      if (acc + need > totalXp) return l;
      acc += need;
    }
    return maxLevel;
  }

  /// 0..1 progress inside the current level.
  static double progressInLevel(int totalXp) {
    final level = levelForTotalXp(totalXp);
    if (level >= maxLevel) return 1.0;
    final base = totalXpForLevel(level);
    final need = xpToNext(level);
    if (need <= 0) return 1.0;
    return ((totalXp - base) / need).clamp(0.0, 1.0);
  }

  /// Thematic rank for a level.
  static BloomRank rankForLevel(int level) {
    if (level <= 10) return BloomRank.seedling;
    if (level <= 25) return BloomRank.sprout;
    if (level <= 45) return BloomRank.bonsai;
    if (level <= 70) return BloomRank.lotus;
    return BloomRank.sakura;
  }

  /// Display name for a rank.
  static String rankName(BloomRank rank) {
    switch (rank) {
      case BloomRank.seedling:
        return 'Seedling';
      case BloomRank.sprout:
        return 'Sprout';
      case BloomRank.bonsai:
        return 'Bonsai';
      case BloomRank.lotus:
        return 'Lotus';
      case BloomRank.sakura:
        return 'Sakura Bloom';
    }
  }

  /// Kanji accent for the badge (minimalist, single glyph).
  static String rankKanji(BloomRank rank) {
    switch (rank) {
      case BloomRank.seedling:
        return '種';
      case BloomRank.sprout:
        return '芽';
      case BloomRank.bonsai:
        return '盆';
      case BloomRank.lotus:
        return '蓮';
      case BloomRank.sakura:
        return '桜';
    }
  }

  /// Ring intricacy 1..5 for the badge border.
  static int rankIntricacy(BloomRank rank) => rank.index + 1;

  /// Combo bonus on top of [baseXp]: +10 per chain step, +50 at 3+.
  /// Keeps early chaining rewarding without runaway inflation.
  static int xpForCombo(int baseXp, int comboCount) {
    if (comboCount >= 3) return baseXp + 50;
    if (comboCount == 2) return baseXp + 10;
    return baseXp;
  }
}
