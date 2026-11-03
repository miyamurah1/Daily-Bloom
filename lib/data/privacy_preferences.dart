import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled privacy choices for network features that are not needed
/// for the core offline task loop.
class PrivacyPreferences extends ChangeNotifier {
  static const _kExternalAi = 'bloom_privacy_external_ai_v1';

  static final PrivacyPreferences instance = PrivacyPreferences._();
  PrivacyPreferences._();

  bool _externalAi = false;
  bool _loaded = false;

  bool get externalAiAllowed => _externalAi;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Explicit opt-in: local heuristics remain available when disabled.
      _externalAi = prefs.getBool(_kExternalAi) ?? false;
    } catch (_) {}
    _loaded = true;
  }

  Future<void> setExternalAiAllowed(bool value) async {
    _externalAi = value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kExternalAi, value);
    } catch (_) {}
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _externalAi = false;
    _loaded = false;
    notifyListeners();
  }
}
