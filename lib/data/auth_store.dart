import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'analytics.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'account_wipe.dart';
import 'guest_store.dart';
import 'profile_name.dart';
import 'task_repository.dart';

/// Logged-in user profile (mirrors the backend's `publicUser()` shape).
class AuthUser {
  final String id;
  final String email;
  final String displayName;
  final String avatarLabel;
  final String activeTheme;

  const AuthUser({
    required this.id,
    required this.email,
    this.displayName = '',
    this.avatarLabel = '禅',
    this.activeTheme = 'midnight',
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: '${j['id']}',
        email: '${j['email']}',
        displayName: '${j['display_name'] ?? ''}',
        avatarLabel: '${j['avatar_label'] ?? '禅'}',
        activeTheme: '${j['active_theme'] ?? 'midnight'}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'avatar_label': avatarLabel,
        'active_theme': activeTheme,
      };
}

/// Thrown when the Firebase session is bad/expired.
class AuthExpiredException implements Exception {
  final String message;
  const AuthExpiredException([this.message = 'session expired']);
  @override
  String toString() => message;
}

/// Thrown for expected auth failures (wrong password, email taken, ...).
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Single source of truth for login state.
///
/// - Uses Firebase Auth as the identity provider (email/password + Google).
/// - On every Firebase sign-in, calls the backend to upsert the DB user row.
/// - [BloomApi] calls [getIdToken] to get a fresh Firebase ID token for the
///   `Authorization: Bearer …` header — Firebase rotates it automatically.
/// - [AuthGate] listens to [FirebaseAuth.instance.authStateChanges()] which
///   is re-emitted here via [ChangeNotifier].
class AuthStore extends ChangeNotifier {
  static const _kUser = 'bloom_user_v2'; // new key to avoid stale JWT data
  static const _kLastEmail = 'bloom_last_email_v1';

  /// Web OAuth client ID for Google sign-in (from google-services.json →
  /// oauth_client type 3). google_sign_in on Android falls back to
  /// R.string.default_web_client_id, which only exists when the
  /// google-services Gradle plugin is applied — this project ships neither
  /// that file nor that plugin, so without this explicit ID the ID token
  /// has no audience and every Google sign-in fails.
  static const googleWebClientId =
      '789612027996-nri9p33e5djdd56atjmlqou5fi9mcq9o.apps.googleusercontent.com';

  /// One shared client so sign-in and sign-out run with identical options.
  static GoogleSignIn _googleClient() =>
      GoogleSignIn(serverClientId: googleWebClientId);

  static const String baseUrl = String.fromEnvironment(
    'BLOOM_API',
    defaultValue: 'http://localhost:8080',
  );

  AuthStore._();
  static final AuthStore instance = AuthStore._();

  AuthUser? _user;
  bool _ready = false;

  /// While true, the authStateChanges listener ignores events. Signup sets
  /// this: creating a Firebase user signs it in immediately, but signup
  /// must NOT grant app access — the session is dropped right after and
  /// the user logs in explicitly. Without the guard the listener would
  /// sync a profile for the transient session and flash the app open.
  bool _ignoreAuthEvents = false;

  AuthUser? get user => _user;
  bool get isLoggedIn => FirebaseAuth.instance.currentUser != null && _user != null;
  bool get isReady => _ready;

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? validateEmail(String v) {
    if (v.trim().isEmpty) return 'Email is required';
    if (!_emailRe.hasMatch(v.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? validatePassword(String v, {bool isSignup = false}) {
    if (v.isEmpty) return 'Password is required';
    if (isSignup && v.length < 8) return 'Use at least 8 characters';
    return null;
  }

  /// Get a fresh Firebase ID token to attach to API requests.
  /// Firebase auto-refreshes it when it expires (<1 hour lifetime).
  Future<String?> getIdToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  /// Auth headers for [BloomApi] — uses a fresh Firebase ID token.
  Future<Map<String, String>> get authHeaders async {
    final token = await getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Remember the last signed-in address so the login form can prefill it.
  Future<void> _rememberEmail(String? email) async {
    final address = email?.trim() ?? '';
    if (address.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastEmail, address);
    } catch (_) {}
  }

  /// Last signed-in address for login prefill (null on first run / prefs fail).
  static Future<String?> readLastEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kLastEmail);
    } catch (_) {
      return null;
    }
  }

  /// Called once at startup: restore cached profile and listen for Firebase
  /// auth state changes. Firebase handles token validation and refresh.
  Future<void> restore() async {
    try {
      // Load cached profile for instant UI paint before network.
      final prefs = await SharedPreferences.getInstance();
      final rawUser = prefs.getString(_kUser);
      if (rawUser != null) {
        try {
          _user = AuthUser.fromJson(jsonDecode(rawUser) as Map<String, dynamic>);
        } catch (_) {
          _user = null;
        }
      }

      // Listen to Firebase auth state — fires immediately with current user.
      FirebaseAuth.instance.authStateChanges().listen((firebaseUser) async {
        if (_ignoreAuthEvents) return;
        if (firebaseUser == null) {
          _user = null;
          await _clearPersisted();
          _ready = true;
          notifyListeners();
        } else {
          // Account switch guard: every store persists under global keys,
          // so a different Firebase identity must start from a clean
          // device or the new account inherits the old one's tasks/XP.
          // Same-account cold starts skip the wipe (offline data stays).
          final cached = _user;
          final sameAccount = cached != null &&
              cached.email.toLowerCase() ==
                  (firebaseUser.email ?? '').toLowerCase();
          // Guest tasks live in the repository's local cache, which the
          // account-switch wipe below destroys (memory + disk). Copy them
          // into GuestStore — a key the wipe spares — so
          // _migrateGuestTasks can carry them into the account after the
          // profile sync, without racing the wipe.
          if (TaskRepository.instance.guestMode) {
            await GuestStore.instance.replaceAll(
              TaskRepository.instance.tasks
                  .map((t) => {
                        'id': t.id,
                        'title': t.title,
                        'folder': t.folder,
                        'done': t.status == 'done',
                      })
                  .toList(),
            );
          }

          if (!sameAccount) {
            await clearAccountData();
          }
          // Sync profile from the backend (upserts DB row with Firebase UID).
          try {
            _user = await _syncProfile(firebaseUser);
            await _persistUser();
          } catch (_) {
            // Offline cold start: keep the cached profile when it belongs
            // to this Firebase user; otherwise synthesize a fallback from
            // the on-device Firebase identity so AuthGate lets the user
            // into their cached data instead of bouncing to Login.
            final cached = _user;
            final sameUser = cached != null &&
                cached.email.toLowerCase() ==
                    (firebaseUser.email ?? '').toLowerCase();
            if (!sameUser) {
              _user = AuthUser(
                id: 'offline-${firebaseUser.uid}',
                email: firebaseUser.email ?? '',
                displayName: firebaseUser.displayName ?? '',
              );
              await _persistUser();
            }
          }
          await _migrateGuestTasks();

          _ready = true;
          notifyListeners();
        }
      });
    } catch (_) {
      _user = null;
      _ready = true;
      notifyListeners();
    }
  }

  /// Sign in with email + password via Firebase Auth.
  Future<void> login({required String email, required String password}) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _rememberEmail(email);
      // authStateChanges() listener above handles _user sync + notifyListeners.
      BloomAnalytics.login(method: 'email');
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseMsg(e));
    } catch (_) {
      throw const AuthException('Could not sign in — try again');
    }
  }

  /// Sign up with email + password via Firebase Auth.
  /// Deliberately does NOT sign the new account in: Firebase auto-signs
  /// the created user, so the session is dropped immediately and the
  /// caller routes back to Login. The DB row + seeds are created on the
  /// first explicit login via firebase-sync. Returns the account email so
  /// login can pre-fill it.
  Future<String> signup({
    required String email,
    required String password,
    String name = '',
  }) async {
    _ignoreAuthEvents = true;
    try {
      try {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        // Brand-new Firebase identity: start from a clean device even if
        // a previous account's data survived (upgrade path, missed logout).
        await clearAccountData();
        // Update the Firebase display name immediately.
        if (name.isNotEmpty) {
          await cred.user?.updateDisplayName(name.trim());
        }
        final address = (cred.user?.email ?? email).trim();
        // Drop the auto-sign-in: no direct access to the app from signup.
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        try {
          await _googleClient().signOut();
        } catch (_) {}
        _user = null;
        _ready = true;
        await _clearPersisted();
        notifyListeners();
        BloomAnalytics.signUp(method: 'email');
        return address;
      } finally {
        _ignoreAuthEvents = false;
      }
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseMsg(e));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not create account — try again');
    }
  }

  /// Sign in with Google via Firebase Auth. Returns true when a session was
  /// actually established (false = the account picker was cancelled), so
  /// callers can celebrate only real sign-ins.
  Future<bool> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web: use Firebase popup flow.
        final provider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // Mobile: use google_sign_in package.
        final googleUser = await _googleClient().signIn();
        if (googleUser == null) return false; // User cancelled.
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
      await _rememberEmail(FirebaseAuth.instance.currentUser?.email);
      // authStateChanges() listener handles _user sync + notifyListeners.
      BloomAnalytics.login(method: 'google');
      return true;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseMsg(e));
    } catch (_) {
      throw const AuthException('Google sign-in failed — try again');
    }
  }

  /// Send a password-reset email via Firebase (no custom code needed).
  Future<void> sendPasswordReset(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseMsg(e));
    } catch (_) {
      throw const AuthException('Could not send reset email — try again');
    }
  }

  /// Delete the Firebase account + backend data (Play Store requirement).
  Future<void> deleteAccount() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) throw const AuthExpiredException();
    try {
      // Delete backend data first.
      final headers = await authHeaders;
      final res = await http
          .delete(Uri.parse('$baseUrl/api/auth/account'), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) throw const AuthExpiredException();
      if (res.statusCode != 200) {
        throw AuthException(_msg(res.body, 'Could not delete account — try again'));
      }
      // Then delete the Firebase identity.
      await firebaseUser.delete();
    } on FirebaseAuthException catch (e) {
      // Re-authentication required for sensitive operations.
      throw AuthException(_firebaseMsg(e));
    }
  }

  /// Rename the profile everywhere it is read from: Firebase identity,
  /// the cached AuthUser, and the local ProfileName memory (home greeting,
  /// onboarding, app bar). Best-effort backend push: firebase-sync already
  /// carries display_name, so next login converges even when offline now.
  Future<void> updateDisplayName(String name) async {
    final clean = name.trim().isEmpty ? '' : name.trim();
    try {
      await FirebaseAuth.instance.currentUser?.updateDisplayName(clean);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw AuthException(_firebaseMsg(e));
      }
    } catch (_) {}
    if (_user != null) {
      _user = AuthUser(
        id: _user!.id,
        email: _user!.email,
        displayName: clean,
        avatarLabel: _user!.avatarLabel,
        activeTheme: _user!.activeTheme,
      );
      await _persistUser();
    }
    await ProfileName.write(clean);
    notifyListeners();
  }

  Future<void> logout() async {
    // Best-effort first: GoogleSignIn is unconfigured on web (no
    // google-signin-client_id meta tag), where even instantiating it
    // throws — Firebase sign-out below must still run, or logout
    // silently strands the user logged in.
    try {
      await _googleClient().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    // authStateChanges() listener sets _user = null + notifies.
    // Drop per-account data so the next login starts clean (shared
    // devices, tester switching accounts).
    await clearAccountData();
  }

  // ── Private helpers ─────────────────────────────────────────────────────

  /// Calls POST /api/auth/firebase-sync to upsert the DB row for this
  /// Firebase user. Returns the enriched [AuthUser] from the backend.
  Future<AuthUser> _syncProfile(User firebaseUser) async {
    final token = await firebaseUser.getIdToken();
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/auth/firebase-sync'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({
            'display_name': firebaseUser.displayName ?? '',
            'email': firebaseUser.email ?? '',
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200 || res.statusCode == 201) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return AuthUser.fromJson(j['user'] as Map<String, dynamic>);
    }
    // Fallback: build a minimal AuthUser from Firebase data if backend is down.
    return AuthUser(
      id: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName: firebaseUser.displayName ?? '',
    );
  }

  Future<void> _persistUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (_user != null) {
      await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
    } else {
      await prefs.remove(_kUser);
    }
  }

  /// Carry guest tasks into the synced repo after a successful sign-in.
  ///
  /// Runs once per guest→signed-in transition, guarded by the persisted
  /// guest flag: re-enables syncing on the repository (it was pinned to
  /// guest-only writes), migrates [GuestStore.migrateCandidates] through
  /// [TaskRepository.migrateGuestTasks], then clears the guest store and
  /// drops the flag. Best-effort and silent — a partial migration leaves
  /// the flag set so the next auth event retries, and a failure never
  /// blocks or delays sign-in.
  Future<void> _migrateGuestTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('bloom_guest_mode_v1') != true) return;
      // Authenticated now: without this, createTask would short-circuit
      // into guest-only local writes and nothing would ever sync.
      await TaskRepository.instance.setGuestMode(false);
      await GuestStore.instance.load();
      final candidates = GuestStore.instance
          .migrateCandidates()
          .where((g) => ((g['title'] as String?) ?? '').trim().isNotEmpty)
          .toList();
      if (candidates.isNotEmpty) {
        final migrated =
            await TaskRepository.instance.migrateGuestTasks(candidates);
        // Keep the flag (and the guest store) for a later retry if any
        // entry failed — silently dropping tasks is worse than retrying.
        if (migrated < candidates.length) return;
      }
      await GuestStore.instance.clear();
      await prefs.setBool('bloom_guest_mode_v1', false);
    } catch (_) {
      // Never block sign-in; the next auth event retries the migration.
    }
  }


  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUser);
  }

  static String _firebaseMsg(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password';
      case 'email-already-in-use':
        return 'An account with this email already exists';
      case 'weak-password':
        return 'Password must be at least 6 characters';
      case 'invalid-email':
        return 'Enter a valid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many attempts — wait a moment and try again';
      case 'requires-recent-login':
        return 'For safety, sign in again first, then retry this';
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method';
      default:
        return e.message ?? 'Authentication failed — try again';
    }
  }

  static String _msg(String body, String fallback) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return fallback;
  }
}
