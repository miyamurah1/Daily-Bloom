import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display metadata for energy levels (single source for card pill +
/// detail segments). Data + labels co-locate here the way action/trigger
/// labels co-locate in `api_client.dart`.
String energyLabel(String level) => switch (level) {
      EnergyStore.low => 'Low',
      EnergyStore.medium => 'Medium',
      EnergyStore.high => 'High',
      _ => '',
    };

IconData energyIcon(String level) => switch (level) {
      EnergyStore.low => LucideIcons.batteryLow,
      EnergyStore.medium => LucideIcons.batteryMedium,
      EnergyStore.high => LucideIcons.batteryFull,
      _ => LucideIcons.batteryMedium,
    };

/// Per-task energy cost: how much juice a task needs (low/medium/high).
///
/// Deliberately CLIENT-side, keyed by task id: the server has no energy
/// column, and a migration isn't this feature. Labels survive refreshes
/// (they never ride the Task payload), work offline, and outlive nothing
/// — orphaned ids (deleted tasks) are pruned whenever a screen hands us
/// its live id set. Small map; a power user's whole board fits in one
/// prefs string.
class EnergyStore extends ChangeNotifier {
  static const storageKey = 'bloom_energy_v1';

  /// Canonical levels. Anything else read back is treated as unset.
  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';

  static bool valid(String? v) =>
      v == low || v == medium || v == high;

  static final EnergyStore instance = EnergyStore._();
  EnergyStore._();

  Map<String, String> _levels = {};
  bool _loaded = false;

  String? levelFor(String taskId) => _levels[taskId];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        _loaded = true;
        notifyListeners();
        return;
      }
      final j = jsonDecode(raw);
      final clean = <String, String>{};
      if (j is Map) {
        j.forEach((k, v) {
          if (v is String && valid(v)) clean['$k'] = v;
        });
      }
      _levels = clean;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setLevel(String taskId, String? level) async {
    if (level != null && !valid(level)) return;
    if (level == null) {
      if (!_levels.containsKey(taskId)) return;
      _levels = Map.of(_levels)..remove(taskId);
    } else {
      if (_levels[taskId] == level) return;
      _levels = Map.of(_levels)..[taskId] = level;
    }
    notifyListeners();
    await persist();
  }

  /// Drop ids no live list references (deleted tasks). Called with the
  /// union of ids a screen already holds — zero extra IO.
  Future<void> prune(Iterable<String> liveIds) async {
    final keep = liveIds.toSet();
    if (_levels.keys.every(keep.contains)) return;
    _levels = Map.of(_levels)..removeWhere((k, _) => !keep.contains(k));
    notifyListeners();
    await persist();
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(_levels));
    } catch (_) {}
  }

  /// Fresh slate for a new account. [load] keeps stale memory when the
  /// key is missing, so the wipe needs this explicit clear.
  Future<void> resetForNewAccount() async {
    _levels = {};
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {}
    notifyListeners();
  }

  @visibleForTesting
  void debugFill([Map<String, String>? levels]) {
    _levels = Map.of(levels ?? const {});
    _loaded = true;
    notifyListeners();
  }

  bool get loaded => _loaded;
}
