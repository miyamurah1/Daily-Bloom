import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-week arc: three tiny prompts, one per day, that convert a
/// curious install into a habit loop.
///
/// 1. Plant three tasks.
/// 2. Run your first Plan my day.
/// 3. Commit — stake one day's XP.
///
/// Local-first, offline, never repeats once finished. Each screen calls
/// [FirstWeekArc.report] on the matching milestone; the card checks
/// what's still open on every Home build.
class FirstWeekArc {
  static const _kDay = 'first_arc_day';
  static const _kPlanted = 'first_arc_planted';
  static const _kPlanned = 'first_arc_planned';
  static const _kStaked = 'first_arc_staked';

  static final FirstWeekArc instance = FirstWeekArc._();
  FirstWeekArc._();

  bool _planted = false;
  bool _planned = false;
  bool _staked = false;
  bool _loaded = false;

  bool get planted => _planted;
  bool get planned => _planned;
  bool get staked => _staked;

  /// Which arc step to show next, or null when the arc is complete.
  /// 0 = plant (need 3+ tasks), 1 = plan, 2 = stake.
  int? get nextStep {
    if (!_planted) return 0;
    if (!_planned) return 1;
    if (!_staked) return 2;
    return null;
  }

  bool get isComplete => nextStep == null;

  /// The concrete ask behind [nextStep].
  String get prompt {
    switch (nextStep) {
      case 0:
        return 'Plant 3 blooms — everything starts here.';
      case 1:
        return 'Tap Plan my day — let Bloom pick top 3.';
      case 2:
        return 'Feeling it? Stake your plan for XP.';
      default:
        return '';
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _planted = prefs.getBool(_kPlanted) ?? false;
      _planned = prefs.getBool(_kPlanned) ?? false;
      _staked = prefs.getBool(_kStaked) ?? false;
      _loaded = true;
    } catch (_) {
      _loaded = true;
    }
  }

  /// Record a milestone. Idempotent; each flag sticks once true.
  Future<void> report(FirstWeekStep step) async {
    _loaded = true;
    switch (step) {
      case FirstWeekStep.planted:
        _planted = true;
      case FirstWeekStep.planned:
        _planned = true;
      case FirstWeekStep.staked:
        _staked = true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_planted) await prefs.setBool(_kPlanted, true);
      if (_planned) await prefs.setBool(_kPlanned, true);
      if (_staked) await prefs.setBool(_kStaked, true);
    } catch (_) {}
  }

  /// Records this device's first launch day (diagnostics for future arcs).
  Future<void> markFirstLaunchIfNeeded(DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      if (prefs.getString(_kDay) == null) {
        await prefs.setString(_kDay, key);
      }
    } catch (_) {}
  }

  /// Fresh slate for a new account: the next account replays the arc
  /// from step 0 instead of inheriting a finished one.
  Future<void> resetForNewAccount() async {
    _planted = false;
    _planned = false;
    _staked = false;
    _loaded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPlanted);
      await prefs.remove(_kPlanned);
      await prefs.remove(_kStaked);
    } catch (_) {}
  }

  /// Test seam: wipe to a fresh-arc state.
  @visibleForTesting
  void debugReset() {
    _planted = false;
    _planned = false;
    _staked = false;
    _loaded = false;
  }
}

enum FirstWeekStep { planted, planned, staked }
