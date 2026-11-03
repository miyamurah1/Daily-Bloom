import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/haptics.dart';
import '../data/session_sound.dart';
import '../data/tap_sound.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/google_button.dart';
import '../widgets/apple_button.dart';
import '../widgets/motion.dart';
import '../widgets/petal_rain.dart';
import '../widgets/trust_dialog.dart';

/// Signup — same Sakura card style as login. Uses Firebase Auth.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  bool _googleBusy = false;
  bool _appleBusy = false;
  String? _error;

  bool get _appleAvailable =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
      await AuthStore.instance.signup(
        email: _email.text,
        password: _password.text,
        name: _name.text,
      );
      // Let the OS/browser offer to save the new credential now.
      TextInput.finishAutofillContext();
      // Firebase keeps the new session. AuthGate removes this route and
      // presents onboarding directly, so account creation is one continuous
      // flow instead of signup → logout → login.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not create account — try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignUp() async {
    AppHaptics.tap();
    await TapSound.tap();
    setState(() {
      _error = null;
      _googleBusy = true;
    });
    try {
      final signedIn = await AuthStore.instance.signInWithGoogle();
      TextInput.finishAutofillContext();
      if (!signedIn) return;
      SessionSound.chime();
      await ThemeStore.instance.sync(() => BloomApi().fetchStore());
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

  Future<void> _appleSignUp() async {
    AppHaptics.tap();
    await TapSound.tap();
    setState(() {
      _error = null;
      _appleBusy = true;
    });
    try {
      final signedIn = await AuthStore.instance.signInWithApple();
      if (!signedIn) return;
      SessionSound.chime();
      await ThemeStore.instance.sync(() => BloomApi().fetchStore());
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Apple sign-in failed — try again.');
    } finally {
      if (mounted) setState(() => _appleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: SafeArea(
        child: PetalRain(
          petalCount: 10,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Back affordance ───────────────────────────────────
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: SakuraColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: SakuraColors.cardBorder),
                    ),
                    child: Tooltip(
                      message: 'Back',
                      child: Icon(LucideIcons.arrowLeft,
                          size: 18, color: SakuraColors.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Header ────────────────────────────────────────────
                Entrance(
                  delayMs: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.85, end: 1.0),
                        duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                            ? Duration.zero
                            : AppMotion.entrance,
                        curve: AppMotion.entranceCurve,
                        builder: (context, scale, child) => Transform.scale(
                          scale: scale,
                          alignment: Alignment.centerLeft,
                          child: child,
                        ),
                        child: Text(
                          '日常',
                          style: SakuraTheme.display(
                            fontSize: 30,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.primary,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'JOIN THE BLOOM',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 3.2,
                          fontWeight: FontWeight.w600,
                          color: SakuraColors.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your account — start growing your garden.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: SakuraColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // ── Signup card ───────────────────────────────────────
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
                      // Name (optional)
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Name (optional)',
                          hintText: 'e.g. Sakura',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

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
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Password (min 8 characters)',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(_obscure
                                ? LucideIcons.eyeOff
                                : LucideIcons.eye),
                            onPressed: () => setState(
                                () => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => AuthStore.validatePassword(
                            v ?? '',
                            isSignup: true),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 12),

                      // Confirm password
                      TextFormField(
                        controller: _confirmPassword,
                        obscureText: _obscureConfirm,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscureConfirm
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(_obscureConfirm
                                ? LucideIcons.eyeOff
                                : LucideIcons.eye),
                            onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (v != _password.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _submit(),
                      ),

                      // Terms note: both documents are available before the
                      // user submits an account or shares any data.
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('By creating an account you agree to our ',
                              style: TextStyle(
                                  fontSize: 11, color: SakuraColors.inkFaint)),
                          TextButton(
                            onPressed: () => showPrivacyPolicy(context),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                minimumSize: const Size(0, 36)),
                            child: const Text('Privacy Policy'),
                          ),
                          Text(' and ',
                              style: TextStyle(
                                  fontSize: 11, color: SakuraColors.inkFaint)),
                          TextButton(
                            onPressed: () => showTermsOfUse(context),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                minimumSize: const Size(0, 36)),
                            child: const Text('Terms of Use'),
                          ),
                          const Text('.', style: TextStyle(fontSize: 11)),
                        ],
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: Color(0xFFD33A4E), fontSize: 13)),
                      ],
                      const SizedBox(height: 16),

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
                              : const Text('Create account',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── OR divider ──────────────────────────────────
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

                      // Google Sign-Up button
                      GoogleButton(
                        busy: _googleBusy,
                               disabled: _busy || _appleBusy,
                               onTap: _googleSignUp,
                             ),
                             if (_appleAvailable) ...[
                               const SizedBox(height: 10),
                               AppleButton(
                                 busy: _appleBusy,
                                 disabled: _busy || _googleBusy,
                                 onTap: _appleSignUp,
                               ),
                             ],
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
                          child: Text('Already have an account? ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: SakuraColors.inkSoft)),
                        ),
                        GestureDetector(
                          onTap: (_busy || _googleBusy)
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(
                            'Log in',
                            style: TextStyle(
                                color: SakuraColors.primary,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ], // outer Column children
          ), // outer Column
        ), // SingleChildScrollView
      ), // PetalRain
    ), // SafeArea
  ); // Scaffold
  } // build
} // class
