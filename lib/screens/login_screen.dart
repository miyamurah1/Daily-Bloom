import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/haptics.dart';
import '../data/session_sound.dart';
import '../data/tap_sound.dart';
import '../theme/sakura_theme.dart';
import '../widgets/motion.dart';
import '../widgets/petal_rain.dart';
import 'signup_screen.dart';

/// Login screen — Sakura design language (日常 header style).
/// Supports email/password and Google Sign-In via Firebase Auth.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _googleBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Theme moment: the singing-bowl greets the login screen (soft) with
    // one gentle buzz, so the screen feels alive from the first frame.
    SessionSound.chime(volume: 0.6);
    AppHaptics.tap();
    // The form remembers your last signed-in address.
    AuthStore.readLastEmail().then((address) {
      if (address != null &&
          address.isNotEmpty &&
          mounted &&
          _email.text.isEmpty) {
        setState(() => _email.text = address);
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    AppHaptics.tap();
    await TapSound.tap();
    setState(() => _busy = true);
    try {
      await AuthStore.instance.login(
        email: _email.text,
        password: _password.text,
      );
      // Let the OS/browser offer to save the credential now.
      TextInput.finishAutofillContext();
      // You're in — the app's signature bowl marks the moment.
      SessionSound.chime();
      // Pull account's equipped skin; AuthGate swaps to AppShell automatically.
      await ThemeStore.instance.sync(() => BloomApi().fetchStore());
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not sign in — check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    AppHaptics.tap();
    await TapSound.tap();
    setState(() {
      _error = null;
      _googleBusy = true;
    });
    try {
      final signedIn = await AuthStore.instance.signInWithGoogle();
      TextInput.finishAutofillContext();
      if (!signedIn) return; // Picker cancelled — no error, no sync.
      // Real sign-in — celebrate before AuthGate swaps screens.
      SessionSound.chime();
      await ThemeStore.instance.sync(() => BloomApi().fetchStore());
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Google sign-in failed — try again.');
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _email.text.trim());
    var busy = false;
    String? error;
    String? success;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> send() async {
            AppHaptics.tap();
            await TapSound.tap();
            final email = emailCtrl.text.trim();
            if (AuthStore.validateEmail(email) != null) {
              setSheet(() => error = 'Enter a valid email address first');
              return;
            }
            setSheet(() {
              busy = true;
              error = null;
              success = null;
            });
            try {
              await AuthStore.instance.sendPasswordReset(email);
              setSheet(() => success =
                  'Reset email sent to $email — check your inbox (and spam folder).');
              AppHaptics.confirm();
            } on AuthException catch (e) {
              setSheet(() => error = e.message);
            } catch (_) {
              setSheet(() => error = 'Could not send email — try again.');
            } finally {
              setSheet(() => busy = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: SakuraColors.cardBorder,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text('Reset password',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: SakuraColors.ink)),
                const SizedBox(height: 4),
                Text(
                    "Enter your email and we'll send a reset link via Firebase.",
                    style: TextStyle(
                        fontSize: 12.5, color: SakuraColors.inkSoft)),
                const SizedBox(height: 14),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      border: OutlineInputBorder()),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(
                          color: Color(0xFFD33A4E), fontSize: 13)),
                ],
                if (success != null) ...[
                  const SizedBox(height: 10),
                  Text(success!,
                      style: TextStyle(
                          color: SakuraColors.navActive, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: SakuraColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: busy
                      ? null
                      : success != null
                          ? () => Navigator.of(ctx).pop()
                          : send,
                  child: busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(success != null ? 'Done' : 'Send reset link'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _goSignup() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    AppHaptics.tap();
    await TapSound.tap();
    final result = await navigator.push(
      SakuraPageRoute(builder: (_) => const SignupScreen()),
    );
    // Signup pops with no result on success — the new account is already
    // signed in and AuthGate swaps to the app on its own. A returned
    // string (legacy hand-back) still pre-fills the email field.
    if (result is String && result.isNotEmpty && mounted) {
      _email.text = result;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Account created — log in to continue.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: SafeArea(
        child: PetalRain(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── App header ────────────────────────────────────────
                  Entrance(
                    delayMs: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '日常',
                          style: SakuraTheme.display(
                            fontSize: 30,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.primary,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'WELCOME BACK',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 3.2,
                            fontWeight: FontWeight.w600,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Do small tasks daily — watch your streak bloom.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: SakuraColors.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your daily companion for focused tasks and growing habits.',
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.3,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No pressure. No noise. Just one small win at a time.',
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Login card ────────────────────────────────────────
                  Entrance(
                    delayMs: 120,
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: SakuraTheme.cardDecoration(),
                      child: Form(
                        key: _form,
                        child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Log in to your bloom',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: SakuraColors.ink),
                            ),
                            const SizedBox(height: 16),

                            // Email
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textCapitalization: TextCapitalization.none,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'you@example.com',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  AuthStore.validateEmail(v ?? ''),
                            ),
                            const SizedBox(height: 12),

                            // Password
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  icon: Icon(_obscure
                                      ? LucideIcons.eyeOff
                                      : LucideIcons.eye),
                                  onPressed: () {
                                    AppHaptics.select();
                                    setState(
                                        () => _obscure = !_obscure);
                                  },
                                ),
                              ),
                              validator: (v) =>
                                  AuthStore.validatePassword(v ?? ''),
                              onFieldSubmitted: (_) => _submit(),
                            ),

                            // ── Forgot password — front and center ─────────
                            // Not buried in the footer: sits exactly where
                            // the user is looking when the password fails.
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: (_busy || _googleBusy)
                                    ? null
                                    : _forgotPassword,
                                icon: Icon(LucideIcons.keyRound,
                                    size: 14,
                                    color: (_busy || _googleBusy)
                                        ? SakuraColors.inkFaint
                                        : SakuraColors.primary),
                                label: Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: (_busy || _googleBusy)
                                        ? SakuraColors.inkFaint
                                        : SakuraColors.primary,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  // Comfortable 44pt+ tap target.
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  minimumSize: const Size(0, 44),
                                  foregroundColor: SakuraColors.primary,
                                  backgroundColor:
                                      SakuraColors.primary.withValues(
                                          alpha: 0.06),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),

                            if (_error != null) ...[
                              const SizedBox(height: 4),
                              Text(_error!,
                                  style: const TextStyle(
                                      color: Color(0xFFD33A4E),
                                      fontSize: 13)),
                            ],
                            const SizedBox(height: 16),

                            // Log in button
                            Pressable(
                              enabled: !_busy && !_googleBusy,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: SakuraColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                ),
                                onPressed: (_busy || _googleBusy)
                                    ? null
                                    : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Text('Log in',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700)),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // ── OR divider ─────────────────────────────
                            Row(
                              children: [
                                Expanded(
                                    child: Divider(
                                        color: SakuraColors.cardBorder)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Text('or',
                                      style: TextStyle(
                                          color: SakuraColors.inkFaint,
                                          fontSize: 12)),
                                ),
                                Expanded(
                                    child: Divider(
                                        color: SakuraColors.cardBorder)),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Google Sign-In button
                            _GoogleButton(
                              busy: _googleBusy,
                              disabled: _busy,
                              onTap: _googleSignIn,
                            ),
                          ],
                        ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Footer links ──────────────────────────────────────
                  Entrance(
                    delayMs: 300,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text('New here? ',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: SakuraColors.inkSoft)),
                            ),
                            GestureDetector(
                              onTap: (_busy || _googleBusy)
                                  ? null
                                  : _goSignup,
                              child: Text(
                                'Create an account',
                                style: TextStyle(
                                    color: SakuraColors.primary,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        // (Forgot password lives directly under the
                        // password field above — one tap away, never
                        // buried under the fold.)
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Google Sign-In button ──────────────────────────────────────────────────

class _GoogleButton extends StatelessWidget {
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  const _GoogleButton({
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: InkWell(
        onTap: (busy || disabled) ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          decoration: BoxDecoration(
            color: SakuraColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SakuraColors.cardBorder, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                // Google "G" logo in brand colours
                _GoogleLogo(),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Continue with Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SakuraColors.ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw quadrant arcs in Google's brand colours.
    // Blue (top-right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r),
        -1.5708, 1.5708, true, paint);
    // Red (top-left)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r),
        3.1416, 1.5708, true, paint);
    // Yellow (bottom-left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r),
        1.5708, 1.5708, true, paint);
    // Green (bottom-right)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r),
        0, 1.5708, true, paint);

    // White inner circle (the "G" cutout effect).
    paint.color = Colors.white;
    canvas.drawCircle(center, r * 0.58, paint);

    // Blue "G" bar on the right side.
    paint.color = const Color(0xFF4285F4);
    final barRect = Rect.fromLTWH(
        center.dx, center.dy - r * 0.22, r * 0.9, r * 0.44);
    canvas.drawRect(barRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
