import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional ambient wash (brown-noise rain loop) under focus sessions.
///
/// Default OFF and opt-in per toggle — a distraction-free app never
/// starts audio uninvited. When on, the loop follows the session:
/// starts with it, pauses with it, stops on finish/abandon.
///
/// Fully offline (bundled asset), test-safe (binding-guarded, every
/// call caught), and cheap: one looped player at low volume.
class AmbientSound {
  static const _kEnabled = 'bloom_ambient_v1';

  static AudioPlayer? _player;
  static bool _enabled = false;
  static bool _loaded = false;

  static bool get enabled => _enabled;

  /// Load the persisted toggle. Called at boot; cheap prefs read.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
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

  static Future<void> _ensurePlayer() async {
    // Same binding hazard as the chime: construction touches platform
    // channels, so it must stay inside the guarded region.
    WidgetsBinding.instance;
    _player ??= AudioPlayer();
    await _player!.setReleaseMode(ReleaseMode.loop);
    await _player!.setVolume(0.25);
  }

  /// Match the wash to session state. Call on start/resume/pause/
  /// finish/abandon — it figures out the rest.
  static Future<void> sync({required bool playing}) async {
    if (!playing || !_enabled) {
      await stop();
      return;
    }
    try {
      await _ensurePlayer();
      // Restarting an already-playing loop is inaudible for noise;
      // after a pause this begins the wash again from the top.
      await _player!.play(AssetSource('sounds/rain.wav'));
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
