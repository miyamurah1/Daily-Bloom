import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gentle UI tap sounds: one tiny bundled blip for Plant / Done / tabs.
/// Same contract as [SessionSound] and [AmbientSound]:
/// - Bundled asset, fully offline, ~5KB, copyright-free (synthesized).
/// - Default ON (taps are confirmations, not ambience — rain stays opt-in).
/// - Best-effort and test-safe: never throws into callers.
/// - One shared player, low volume, no overlap stacking.
class TapSound {
  static const _kEnabled = 'bloom_tap_sound_v1';

  static AudioPlayer? _player;
  static bool _enabled = true;
  static bool _loaded = false;

  static bool get enabled => _enabled;

  /// Load the persisted toggle. Called at boot; cheap prefs read.
  /// Default true — first run taps softly unless the user opts out.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? true;
    } catch (_) {}
    _loaded = true;
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } catch (_) {}
    if (!value) await stop();
  }

  /// Play the soft blip once. No-op when disabled, headless, or offline.
  static Future<void> tap() async {
    if (!_enabled) return;
    try {
      WidgetsBinding.instance;
      _player ??= AudioPlayer();
      await _player!.setVolume(0.35);
      await _player!.play(AssetSource('sounds/tap.wav'));
    } catch (_) {
      // No binding / asset / player — haptics already carried it.
    }
  }

  static Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
