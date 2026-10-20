import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal guest-mode task store.
///
/// Tasks added while not signed in are persisted here under a separate
/// SharedPreferences key so they never collide with synced tasks. When the
/// user later signs in, [migrateToSynced] can copy them into the main
/// [TaskRepository]. The store is capped at 3 tasks — the guest limit —
/// after which the UI prompts the user to create an account.
class GuestStore {
  static const _kGuestTasks = 'bloom_guest_tasks_v1';

  static final GuestStore instance = GuestStore._();
  GuestStore._();

  /// Cached guest tasks (id, title, done). Kept small — max 3 entries.
  List<Map<String, dynamic>> _tasks = [];

  /// Number of guest tasks currently stored.
  int get count => _tasks.length;

  /// Whether the guest limit (3) has been reached.
  bool get atLimit => _tasks.length >= 3;

  /// All guest tasks, newest first.
  List<Map<String, dynamic>> get tasks => List.unmodifiable(_tasks);

  /// Load from SharedPreferences. Call once at boot.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kGuestTasks);
      if (raw != null && raw.isNotEmpty) {
        _tasks = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).cast<Map<String, dynamic>>(),
        );
      }
    } catch (_) {
      _tasks = [];
    }
  }

  /// Add a guest task. Returns false if the guest limit would be exceeded.
  Future<bool> add({
    required String id,
    required String title,
    String folder = 'Personal',
  }) async {
    if (atLimit) return false;
    _tasks = [
      ..._tasks,
      {'id': id, 'title': title, 'folder': folder, 'done': false},
    ]..sort((a, b) => (a['done'] as bool) ? 1 : -1);
    await _persist();
    return true;
  }

  /// Toggle a guest task's done state.
  Future<void> toggle(String id, bool done) async {
    _tasks = _tasks.map((t) {
      if (t['id'] == id) {
        return Map<String, dynamic>.from(t)..['done'] = done;
      }
      return t;
    }).toList();
    await _persist();
  }

  /// Remove a guest task.
  Future<void> remove(String id) async {
    _tasks = _tasks.where((t) => t['id'] != id).toList();
    await _persist();
  }

  /// Clear all guest tasks (called on logout / leave-guest).
  Future<void> clear() async {
    _tasks = [];
    await _persist();
  }

  /// Returns the guest tasks as [Task]-compatible maps for the main repo.
  ///
  /// Call this after sign-in to offer migration. Returns the (possibly
  /// empty) task list — including when the guest limit was reached, because
  /// those 3 tasks are exactly what must be carried over. Clearing happens
  /// separately via [clear] after a successful migration.
  List<Map<String, dynamic>> migrateCandidates() {
    return List.unmodifiable(_tasks);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGuestTasks, jsonEncode(_tasks));
    } catch (_) {}
  }
}