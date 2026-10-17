import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Share-to-app inbox: text shared from other apps (Android share sheet
/// → Daily Bloom) lands here and becomes a prefilled quick-add.
///
/// Delivery is prefs-stashed (single-shot) so even a cold start —
/// share → login → home — still hands the text over exactly once.
/// Fully test/web-safe: the platform channel simply never answers there.
class ShareInbox extends ChangeNotifier {
  static const _kPending = 'bloom_shared_text_v1';

  static final ShareInbox instance = ShareInbox._();
  ShareInbox._();

  StreamSubscription<List<SharedMediaFile>>? _sub;
  bool _initialized = false;
  String? _pending;

  /// Text waiting to become a task (null = nothing pending).
  String? get pending => _pending;

  /// Wire once (home's initState). The stream replays the initial share
  /// on cold start, so [_lastDelivered] dedupes the double delivery.
  void init() {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) return;
    // Restore a stash from a previous cold start (native sticky state
    // may have been consumed already).
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_kPending);
      if (saved != null && saved.isNotEmpty && _pending == null) {
        _lastDelivered = saved;
        _pending = saved;
        notifyListeners();
      }
    }).catchError((_) {});
    try {
      _sub = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen(_onMedia, onError: (_) {});
      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then(_onMedia)
          .catchError((_) {});
    } catch (_) {}
  }

  /// Same content twice in one session = one delivery (the stream
  /// replays the initial share; a real second share of identical text
  /// works again after an app restart).
  String? _lastDelivered;

  Future<void> _onMedia(List<SharedMediaFile> files) async {
    final text = files
        .where((f) => f.type == SharedMediaType.text)
        .map((f) => f.path.trim())
        .where((s) => s.isNotEmpty)
        .join('\n');
    if (text.isEmpty || text == _lastDelivered) return;
    _lastDelivered = text;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPending, text);
    } catch (_) {}
    // Sticky native state must be cleared or every relaunch replays it.
    try {
      await ReceiveSharingIntent.instance.reset();
    } catch (_) {}
    _pending = text;
    notifyListeners();
  }

  /// Take the pending text (single-shot — clears memory + prefs).
  Future<String?> take() async {
    final p = _pending;
    _pending = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPending);
    } catch (_) {}
    return (p == null || p.isEmpty) ? null : p;
  }

  @visibleForTesting
  void debugReset() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
    _pending = null;
    _lastDelivered = null;
  }
}
