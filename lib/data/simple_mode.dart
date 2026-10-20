import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Calm default for focus: hides power tools (Board, Rules) until the
/// user asks for them. Opt-in — onboarding offers it, Settings can flip
/// it; existing accounts keep every door until they say otherwise.
class SimpleMode extends ChangeNotifier {
  static const _kEnabled = 'bloom_simple_mode_v1';

  static final SimpleMode instance = SimpleMode._();
  SimpleMode._();

  bool _enabled = true; // calm default for new installs; stored value wins after load
  bool _loaded = false;

  bool get enabled => _enabled;

  /// Load the persisted toggle. Called at boot; cheap prefs read.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? true;
    } catch (_) {}
    _loaded = true;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } catch (_) {}
    notifyListeners();
  }

  @visibleForTesting
  void debugReset(bool value) {
    _enabled = value;
    // Unloaded, so a following load() re-reads prefs (fresh-boot sim).
    _loaded = false;
    notifyListeners();
  }
}
