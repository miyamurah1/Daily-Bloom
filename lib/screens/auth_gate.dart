import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_store.dart';
import '../data/guest_store.dart';
import '../data/haptics.dart';
import '../data/task_repository.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_mark.dart';
import '../widgets/google_button.dart';
import '../widgets/motion.dart';
import '../widgets/petal_rain.dart';
import 'app_shell.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'signup_screen.dart';

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
  bool? _guestOnboardingSeen;
  static const _guestOnboardingKey = 'bloom_guest_onboarding_seen_v1';

  /// A newly-entered guest must see the first-run explanation even when a
  /// stale device-level onboarding flag exists from an earlier session.
  bool _guestOnboardingRequired = false;

  /// Small splash floor so fast launches do not flash, without making every
  /// returning user wait through a decorative 1.5 second delay.
  bool _minSplashDone = false;
  String? _seenFirebaseUid;
  bool _onboardingRefreshPending = false;

  /// Last guest flag observed on the repository. Leaving guest mode clears
  /// the repo flag but fires no Firebase auth event, so without this the
  /// gate never re-evaluates and the user stays inside the guest shell.
  bool _lastRepoGuestMode = false;

  @override
  void initState() {
    super.initState();
    AuthStore.instance.restore();
    _loadOnboarding();
    _loadGuestMode();
    _lastRepoGuestMode = TaskRepository.instance.guestMode;
    TaskRepository.instance.addListener(_onRepoGuestModeChanged);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _minSplashDone = true);
    });
  }

  @override
  void dispose() {
    TaskRepository.instance.removeListener(_onRepoGuestModeChanged);
    super.dispose();
  }

  /// Guest mode ended (Settings → leave guest mode): drop back to the
  /// welcome gate immediately. Entering guest is handled by [_enterGuest],
  /// which already sets its own state.
  void _onRepoGuestModeChanged() {
    final guest = TaskRepository.instance.guestMode;
    if (guest == _lastRepoGuestMode) return;
    _lastRepoGuestMode = guest;
    if (guest || !mounted) return;
    if (_guestMode == true) setState(() => _guestMode = false);
  }

  Future<void> _loadOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _onboardingSeen = _guestOnboardingRequired
            ? false
            : (prefs.getBool(OnboardingScreen.seenKey) ?? false);
      });
    } catch (_) {
      // Prefs unavailable (unlikely): don't trap the user in onboarding.
      if (mounted) setState(() => _onboardingSeen = true);
    }
  }

  Future<void> _loadGuestMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guest = prefs.getBool('bloom_guest_mode_v1') ?? false;
      if (guest) {
        // Restore the repository mode before any guest onboarding action can
        // create a task; otherwise the first task could attempt the API.
        await TaskRepository.instance.setGuestMode(true);
        await GuestStore.instance.load();
      }
      if (!mounted) return;
      setState(() {
        _guestMode = guest;
        _guestOnboardingSeen = guest
            ? (prefs.getBool(_guestOnboardingKey) ?? false)
            : true;
      });
    } catch (_) {
      if (mounted) setState(() => _guestMode = false);
    }
  }

  /// Account-scoped data wipes can reset the onboarding flag while AuthGate
  /// itself remains mounted. Re-read it whenever Firebase switches identity
  /// so a new account cannot inherit another account's completed onboarding.
  void _refreshOnboardingForAccount(String uid) {
    if (_seenFirebaseUid == uid || _onboardingRefreshPending) return;
    _seenFirebaseUid = uid;
    _onboardingRefreshPending = true;
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _onboardingSeen = prefs.getBool(OnboardingScreen.seenKey) ?? false;
        _onboardingRefreshPending = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _onboardingRefreshPending = false);
    });
  }

  /// Enter as guest: persist the flag, mark onboarding seen, open the shell.
  Future<void> _enterGuest() async {
    // Set this before awaiting SharedPreferences so a concurrent first-run
    // read cannot win a race and skip the guest onboarding.
    _guestOnboardingRequired = true;
    // A returning guest keeps their tasks and does not replay the intro;
    // a brand-new guest still gets the first-run slides.
    var alreadyOnboarded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      alreadyOnboarded = prefs.getBool(_guestOnboardingKey) ?? false;
      await prefs.setBool('bloom_guest_mode_v1', true);
      await prefs.setBool(_guestOnboardingKey, alreadyOnboarded);
    } catch (_) {}
    await TaskRepository.instance.setGuestMode(true);
    // Restore anything left in the guest store (e.g. after leaving guest
    // mode from Settings without deleting their work).
    await GuestStore.instance.load();
    if (!mounted) return;
    setState(() {
      _guestMode = true;
      _guestOnboardingSeen = alreadyOnboarded;
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
        // Hold the branded splash for ~1.5s on cold start.
        if (!_minSplashDone) return _splash();
        // Firebase still initialising.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _splash();
        }

        final firebaseUser = snapshot.data;

        // ---------- Signed in ----------
        if (firebaseUser != null) {
          _guestOnboardingRequired = false;
          _refreshOnboardingForAccount(firebaseUser.uid);
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
        _seenFirebaseUid = null;
        // Do not flash the welcome gate while a persisted guest session is
        // still being restored. The guest flag must settle before routing,
        // otherwise a returning guest briefly sees the wrong entry screen.
        if (_guestMode == null) return _splash();
        // Live source of truth: if guest mode was cleared (e.g. logout from
        // Settings), TaskRepository.guestMode flips to false and we drop to
        // the welcome gate instead of staying in the guest shell.
        final isGuest = _guestMode == true && TaskRepository.instance.guestMode;
        // Already a guest: returning guests who completed onboarding go
        // straight to the shell; a newly-entered guest gets the same clear
        // first-run explanation as a signed-in user.
        if (isGuest) {
          if (_onboardingSeen == null) return _splash();
          if (_guestOnboardingSeen == null) return _splash();
          if (!_guestOnboardingSeen!) {
            return OnboardingScreen(
              completionKey: _guestOnboardingKey,
              onDone: () => setState(() {
                _guestOnboardingRequired = false;
                _guestOnboardingSeen = true;
                _onboardingSeen = true;
              }),
            );
          }
          return const AppShell(guest: true);
        }

        // First-time or returning non-guest: show the welcome gate so the
        // user sees value before being asked for credentials.
        return WelcomeGate(
          onGuest: _enterGuest,
          onSignIn: onSignIn,
          onCreateAccount: onCreateAccount,
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

  void onCreateAccount() {
    Navigator.of(context).push(
      SakuraPageRoute(
        settings: const RouteSettings(name: 'signup'),
        builder: (_) => const SignupScreen(),
      ),
    );
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
                    // Brand logo — a bloom on a clean surface circle.
                    _PulseLogo(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: SakuraColors.surface,
                          border: Border.all(
                            color:
                                SakuraColors.primary.withValues(alpha: 0.16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  SakuraColors.ink.withValues(alpha: 0.06),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Center(child: BloomMark(size: 58)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'COMPLETE TASKS · SEE PROOF · GROW',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w700,
                        color: SakuraColors.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: 22,
                      height: 22,
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
  final Future<void> Function() onGuest;
  final VoidCallback onSignIn;
  final VoidCallback? onCreateAccount;

  const WelcomeGate({
    super.key,
    required this.onGuest,
    required this.onSignIn,
    this.onCreateAccount,
  });

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  bool _guestBusy = false;
  bool _googleBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    // Only the opt-in background loop resumes here. No tap sound or haptic
    // on mount: browsers block both until the first real gesture, so firing
    // them here only produced console interventions on web.
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  Future<void> _enterGuest() async {
    if (_guestBusy || _googleBusy) return;
    setState(() => _guestBusy = true);
    AppHaptics.select();
    try {
      await widget.onGuest();
    } finally {
      if (mounted) setState(() => _guestBusy = false);
    }
  }

  Future<void> _googleSignIn() async {
    if (_guestBusy || _googleBusy) return;
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    AppHaptics.select();
    try {
      final ok = await AuthStore.instance.signInWithGoogle();
      if (!ok && mounted) {
        // User cancelled the picker — stay on the gate silently.
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Google sign-in failed — try again.');
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSignIn = widget.onSignIn;
    // One primary action per screen: creating an account when the caller
    // offers it, otherwise signing in. Guest and Google are deliberately
    // quieter so a first-time phone user has a single obvious path.
    final busy = _guestBusy || _googleBusy;
    final createAccount = widget.onCreateAccount;
    final primaryLabel =
        createAccount != null ? 'Create a free account' : 'Sign In';
    final primaryIcon = createAccount != null
        ? Icons.person_add_alt_1_outlined
        : Icons.login;
    // One decorative layer only: PetalRain paints behind the content. The
    // previous DynamicBloomBackground wrapper added a second 14s loop whose
    // motes painted *over* the copy and buttons.
    return Scaffold(
        backgroundColor: SakuraColors.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _bgCtrl,
                builder: (context, _) {
                  final reduce =
                      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
                  if (reduce && _bgCtrl.isAnimating) {
                    _bgCtrl.stop();
                  } else if (!reduce && !_bgCtrl.isAnimating) {
                    _bgCtrl.repeat();
                  }
                  final t = reduce ? 0.0 : _bgCtrl.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(SakuraColors.background,
                              SakuraColors.surface, 0.6 + 0.2 * t)!,
                          Color.lerp(SakuraColors.surface,
                              SakuraColors.background, 0.4 + 0.2 * t)!,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            PetalRain(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Entrance(
                            delayMs: 80,
                            child: Semantics(
                              label: 'Daily Bloom logo',
                              image: true,
                              child: _PulseLogo(
                                child: Container(
                                  width: 74,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: SakuraColors.surface,
                                    border: Border.all(
                                      color: SakuraColors.primary
                                          .withValues(alpha: 0.16),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: SakuraColors.ink
                                            .withValues(alpha: 0.06),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: BloomMark(size: 44),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Entrance(
                            delayMs: 160,
                            child: Text(
                              'Daily Bloom',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                color: SakuraColors.ink,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Entrance(
                            delayMs: 220,
                            child: Text(
                              'One task. One timer. One focus.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: SakuraColors.inkSoft,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Entrance(
                            delayMs: 280,
                            child: _ValueBullets(),
                          ),
                          const SizedBox(height: 14),
                          Entrance(
                            delayMs: 360,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Pressable(
                        child: FilledButton.icon(
                          onPressed:
                              busy ? null : (createAccount ?? onSignIn),
                          icon: Icon(primaryIcon, size: 18),
                          label: Text(
                            primaryLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: SakuraColors.primary,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Entrance(
                  delayMs: 420,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Pressable(
                        child: OutlinedButton.icon(
                          onPressed: (_guestBusy || _googleBusy)
                              ? null
                              : _googleSignIn,
                          icon: _googleBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const GoogleLogo(),
                          label: Text(
                            _googleBusy ? 'Signing in…' : 'Continue with Google',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SakuraColors.ink,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                                color: SakuraColors.inkFaint.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Only when creating an account is the primary action;
                // otherwise the primary button already says "Sign In".
                if (createAccount != null) ...[
                  const SizedBox(height: 2),
                  Entrance(
                    delayMs: 480,
                    child: TextButton(
                      onPressed: busy ? null : onSignIn,
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          color: SakuraColors.inkSoft,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Entrance(
                  delayMs: 520,
                  child: TextButton(
                    onPressed: busy ? null : _enterGuest,
                    child: Text(
                      _guestBusy ? 'Starting…' : 'Continue as Guest',
                      style: TextStyle(
                        color: SakuraColors.inkFaint,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'up to 3 tasks, no account needed',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        // Theme error colour (M3 seed) instead of a hardcoded
                        // redAccent that failed AA contrast on Edo and was
                        // invisible-ish on Midnight.
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Try again'),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Free · No credit card · Your data stays yours',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: SakuraColors.inkFaint,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    ),
  );
  }
}

class _PulseLogo extends StatefulWidget {
  const _PulseLogo({required this.child});
  final Widget child;
  @override
  State<_PulseLogo> createState() => _PulseLogoState();
}

class _PulseLogoState extends State<_PulseLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final v = _c.value;
        final scale = 0.94 + 0.06 * (1 - v);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}

class _ValueBullets extends StatelessWidget {
  const _ValueBullets();

  static const _items = <({IconData icon, String title, String subtitle})>[
    (icon: Icons.view_kanban_outlined, title: 'Tasks & Kanban',
     subtitle: 'Organize work into columns you control'),
    (icon: Icons.timer_outlined, title: 'Focus timer',
     subtitle: 'Pomodoro sessions that bloom when you finish'),
    (icon: Icons.local_florist_outlined, title: 'Habits & streaks',
     subtitle: 'Grow a garden one day at a time'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SakuraColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: SakuraColors.cardBorder.withValues(alpha: 0.30),
        ),
        boxShadow: [
          BoxShadow(
            color: SakuraColors.ink.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        children: [
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: SakuraColors.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(item.icon,
                        size: 18, color: SakuraColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: SakuraColors.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: SakuraColors.inkSoft,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
