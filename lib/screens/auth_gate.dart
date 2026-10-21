import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_store.dart';
import '../data/background_music.dart';
import '../data/haptics.dart';
import '../data/tap_sound.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/motion.dart';
import '../widgets/petal_rain.dart';
import 'app_shell.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Route guard — the only place that decides login vs app.
///
/// - Listens to [FirebaseAuth.authStateChanges] (the Firebase stream) AND
///   [AuthStore] (for the DB user profile). Both must be present to show the app.
/// - While the stored session is being verified, shows a calm sakura splash.
/// - Logout can never be bypassed with the back button (no named routes to pop).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// null until the first-launch flag has been read. While null and the
  /// user is logged in we keep showing the splash — never a flash of the
  /// app before onboarding.
  bool? _onboardingSeen;

  /// Whether a guest session has been established (persisted locally).
  bool? _guestMode;

  @override
  void initState() {
    super.initState();
    AuthStore.instance.restore();
    _loadOnboarding();
    _loadGuestMode();
  }

  Future<void> _loadOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _onboardingSeen =
            prefs.getBool(OnboardingScreen.seenKey) ?? false;
      });
    } catch (_) {
      // Prefs unavailable (unlikely): don't trap the user in onboarding.
      if (mounted) setState(() => _onboardingSeen = true);
    }
  }

  Future<void> _loadGuestMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _guestMode = prefs.getBool('bloom_guest_mode_v1') ?? false;
      });
    } catch (_) {
      if (mounted) setState(() => _guestMode = false);
    }
  }

  /// Enter as guest: persist the flag, mark onboarding seen, open the shell.
  Future<void> _enterGuest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bloom_guest_mode_v1', true);
      // Guests see onboarding too - don't skip it.
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _guestMode = true;
      _onboardingSeen = true;
    });
  }

    /// Firebase's own stream is the ground truth for identity.
  /// Falls back to logged-out when Firebase isn't initialised — that only
  /// happens in widget tests (production always runs Firebase.initializeApp
  /// in main() first), so this never masks a real failure.
  static Stream<User?> _authState() {
    try {
      return FirebaseAuth.instance.authStateChanges();
    } catch (_) {
      return Stream<User?>.value(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authState(),
      builder: (context, snapshot) {
        // Firebase still initialising.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _splash();
        }

        final firebaseUser = snapshot.data;

        // ---------- Signed in ----------
        if (firebaseUser != null) {
          return ListenableBuilder(
            listenable: AuthStore.instance,
            builder: (context, _) {
              final auth = AuthStore.instance;
              if (auth.isLoggedIn) {
                // Auth succeeded: drop the Login/Signup routes pushed over
                // the gate (one clean swap to the app) and retire the local
                // guest flag so a later logout lands on the welcome gate —
                // not an empty guest shell. Runs on every rebuild, but the
                // predicate below stops instantly on the app's own routes.
                final nav = Navigator.of(context);
                if (nav.canPop() || _guestMode == true) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    nav.popUntil((r) =>
                        r.isFirst ||
                        (r.settings.name != 'login' &&
                            r.settings.name != 'signup'));
                    if (_guestMode == true) {
                      setState(() => _guestMode = false);
                    }
                  });
                }
              }
              if (!auth.isReady) return _splash();
              if (!auth.isLoggedIn) return const LoginScreen();
              // First run: onboard before the shell.
              if (_onboardingSeen == null) return _splash();
              if (!_onboardingSeen!) {
                return OnboardingScreen(
                  onDone: () => setState(() => _onboardingSeen = true),
                );
              }
              return const AppShell();
            },
          );
        }

        // ---------- Not signed in ----------
        // Already a guest → go straight to the shell.
        if (_guestMode == true) {
          return const AppShell(guest: true);
        }

        // First-time or returning non-guest: show the welcome gate so the
        // user sees value before being asked for credentials.
        return WelcomeGate(
          onGuest: _enterGuest,
          onSignIn: onSignIn,
        );
      },
    );
  }

  void onSignIn() {
    Navigator.of(context).push(
      SakuraPageRoute(
        settings: const RouteSettings(name: 'login'),
        builder: (_) => const LoginScreen(),
      ),
    );
      // Once auth succeeds the gate pops this named route itself.
  }

  /// Themed splash: resolves through the active Sakura theme so cold
  /// starts never flash the default light Scaffold in Midnight.
  Widget _splash() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: reduce ? Duration.zero : AppMotion.entrance,
          curve: AppMotion.entranceCurve,
          builder: (context, t, _) {
            return Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.92 + 0.08 * t,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '日常',
                      style: SakuraTheme.display(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: SakuraColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'COMPLETE TASKS · SEE PROOF · GROW',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w700,
                        color: SakuraColors.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SakuraColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Welcome screen shown before any credential is requested.
///
/// Presents the core value ("one task, one timer, one focus") and lets the
/// user continue as guest or sign in. Signing in simply closes this screen;
/// the StreamBuilder above detects the new Firebase user and routes to AppShell.
class WelcomeGate extends StatefulWidget {
  final VoidCallback onGuest;
  final VoidCallback onSignIn;

  const WelcomeGate({
    super.key,
    required this.onGuest,
    required this.onSignIn,
  });

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  @override
  void initState() {
    super.initState();
    // A single welcome tick as the cascade begins — keeps the haptic
    // language in sync with the entrance animation.
    AppHaptics.select();
    // Soft welcome blip + resume the opt-in background loop; both are
    // guarded and no-op when disabled/headless.
    TapSound.tap();
    BackgroundMusic.start();
  }

  @override
  Widget build(BuildContext context) {
    final onGuest = widget.onGuest;
    final onSignIn = widget.onSignIn;
    return PetalRain(
      child: Scaffold(
        backgroundColor: SakuraColors.background,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 40),
                Entrance(
                  delayMs: 80,
                  child: Text(
                    '日常',
                    style: SakuraTheme.display(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
                      color: SakuraColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Entrance(
                  delayMs: 160,
                  child: Text(
                    'Daily Bloom',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: SakuraColors.ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Entrance(
                  delayMs: 220,
                  child: Text(
                    'One task. One timer. One focus.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: SakuraColors.inkSoft,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Entrance(
                  delayMs: 300,
                  child: Text(
                    'Start without an account. Add up to 3 tasks as a guest — '
                    'create a free account anytime to sync across devices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Entrance(
                  delayMs: 380,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Pressable(
                        child: FilledButton.icon(
                          onPressed: onGuest,
                          icon: const Icon(Icons.person_outline, size: 18),
                          label: const Text(
                            'Continue as Guest',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: SakuraColors.primary,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Entrance(
                  delayMs: 440,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Pressable(
                        child: OutlinedButton.icon(
                          onPressed: onSignIn,
                          icon: const Icon(Icons.login, size: 18),
                          label: const Text(
                            'Sign In',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SakuraColors.primary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: SakuraColors.primary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
