import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide background music: one soft looping melody (kalimba over a
/// warm pad, C major, 30s seamless loop) that follows the user across
/// every screen.
///
/// Same contract as [TapSound] / [SessionSound] / [AmbientSound]:
/// - Bundled asset, fully offline, ~1.3MB, copyright-free (synthesized).
/// - Default OFF — a distraction-free app never starts audio uninvited;
///   the Settings toggle opts in, persisted across launches.
/// - Best-effort and test-safe: never throws into callers.
/// - One shared looped player, low volume, no restart-stutter (replays
///   are skipped while already playing).
///
/// Layering: independent of [AmbientSound], which only runs rain during
/// focus sessions — both are quiet enough to coexist, and the music
/// keeps the app alive between sessions.
class BackgroundMusic {
  static const _kEnabled = 'bloom_bgm_v1';

  static AudioPlayer? _player;
  static bool _enabled = false;
  static bool _loaded = false;

  static bool get enabled => _enabled;

  /// Load the persisted toggle. Called at boot; cheap prefs read.
  /// Default false — the loop only ever starts on an explicit opt-in.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
    } catch (_) {}
    _loaded = true;
  }

  /// Flip the toggle. ON starts the loop immediately; OFF stops it.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } catch (_) {}
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  static Future<void> _ensurePlayer() async {
    // Same binding hazard as the other sounds: construction touches
    // platform channels, so it must stay inside the guarded region.
    WidgetsBinding.instance;
    _player ??= AudioPlayer();
    await _player!.setReleaseMode(ReleaseMode.loop);
    // The track is normalized hot for its size; keep it under the
    // conversation level so it never fights the user's attention.
    await _player!.setVolume(0.3);
  }

  /// Begin the loop. No-op when disabled, headless, or already playing
  /// — an in-place restart of a melody is audible, so it is skipped.
  static Future<void> start() async {
    if (!_enabled) return;
    try {
      await _ensurePlayer();
      if (_player!.state == PlayerState.playing) return;
      await _player!.play(AssetSource('sounds/bgm.wav'));
    } catch (_) {
      // No binding / asset / player — silence is the fallback.
    }
  }

  static Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
