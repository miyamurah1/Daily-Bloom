import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// End-of-session chime: the bundled singing-bowl bell at full volume
/// plus a heavy haptic — audible even where the old system-alert tone
/// was swallowed (silent/vibrate Android, Windows).
///
/// Best-effort and test-safe: every step is guarded, so missing assets,
/// headless tests, and offline runs degrade to haptics, then to nothing.
/// Never throws into callers.
abstract class SessionSound {
  /// Created lazily inside [chime]'s guarded block: audioplayers touches
  /// platform channels at construction, which throws without a binding
  /// (plain unit tests) — so construction itself must be guarded.
  static AudioPlayer? _player;

  /// Play the bundled bell at [volume] (1.0 = full) + heavy haptic. Guarded at
  /// every step: asset, system tone, and vibrator each degrade silently.
  static Future<void> chime({double volume = 1.0}) async {
    try {
      // Touching the player without a binding (plain unit tests) throws
      // in an async gap that try/catch cannot see — so check first.
      WidgetsBinding.instance;
      _player ??= AudioPlayer();
      await _player!.setVolume(volume);
      await _player!.play(AssetSource('sounds/bell.wav'));
    } catch (_) {
      // No binding, or asset/player unavailable — fall back below.
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {
        // No system tone available either.
      }
    }
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // Desktop / test harness without a vibrator.
    }
  }

  /// Test seam: reports whether the bundled asset played without error.
  /// Never used in production paths.
  static Future<bool> debugPlayAsset() async {
    try {
      WidgetsBinding.instance;
      await AudioPlayer().play(AssetSource('sounds/bell.wav'));
      return true;
    } catch (_) {
      return false;
    }
  }
}
