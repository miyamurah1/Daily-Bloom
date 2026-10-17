import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/game.dart';
import 'data/ambient_sound.dart';
import 'data/tap_sound.dart';
import 'data/api_client.dart';
import 'data/auth_store.dart';
import 'data/crash_reports.dart';
import 'data/energy_store.dart';
import 'data/reminders.dart';
import 'data/simple_mode.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'theme/sakura_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase before anything else. Guarded: without
  // generated options (CI) or network, auth degrades to offline mode
  // instead of killing startup.
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}

  // First-frame-critical restores — all independent SharedPreferences
  // reads plus the font warm-up, run CONCURRENTLY. Serial awaits used
  // to cost ~8 platform round-trips before the first frame; this costs
  // one (the slowest single item). The font wait is capped short: an
  // offline cold start must never sit on a network timeout — missing
  // Inter falls back to the system face and swaps in when ready.
  // Every loader degrades internally; the outer guard is belt-and-braces.
  try {
    await Future.wait([
    // Paint the last-used theme before the first frame — no flash.
    ThemeStore.instance.preload(),
    // Mindful gamification: restore XP / tokens / streak.
    GamificationStateNotifier.instance.load(),
    // Energy labels are local-first: cards never flash unlabeled.
    EnergyStore.instance.load(),
    // Ambient preference is local-only; the wash stays off until a
    // session starts it.
    AmbientSound.load(),
    // Gentle tap sounds: on by default (confirmations, not ambience).
    TapSound.load(),
    // Simple mode (calm home) — restores before any door renders.
    SimpleMode.instance.load(),
    // Reminder preference restores silently; scheduling re-arms inside
    // init below (the OS drops alarms on reboot/update).
    ReminderService.instance.load(),
    // Warm the Inter weights first paint uses (400/600/700/800).
    GoogleFonts.pendingFonts([
      GoogleFonts.inter(fontWeight: FontWeight.w400),
      GoogleFonts.inter(fontWeight: FontWeight.w600),
      GoogleFonts.inter(fontWeight: FontWeight.w700),
      GoogleFonts.inter(fontWeight: FontWeight.w800),
    ]).timeout(const Duration(milliseconds: 1200)),
  ]);
  } catch (_) {}
  GamificationStateNotifier.instance.markDailyActive(null, true);
  // Keep tomorrow's nudge copy truthful: the daily body tracks the live
  // streak, so re-arm the (cheap, inexact) alarm on every change.
  GamificationStateNotifier.onStreakChanged =
      () => ReminderService.instance.scheduleDaily();
  // Notification plumbing (timezone + plugin + alarm re-arm) is needed
  // by nothing on the first frame — run it alongside first paint
  // instead of delaying it. Best-effort inside; degrades to no-op.
  unawaited(ReminderService.instance.init());

  // Crash reporting: Sentry wraps runApp when a DSN was baked in
  // AND the user left the Settings toggle on. Otherwise plain runApp.
  await CrashReports.init(() async {
    runApp(const DailyBloomApp());
  });
  // Restore profile from Firebase auth state. If already signed in, the
  // listener in AuthStore.restore() fires immediately and syncs the theme.
  AuthStore.instance.restore().then((_) {
    if (AuthStore.instance.isLoggedIn) {
      ThemeStore.instance.sync(() => BloomApi().fetchStore());
    }
  });
}

/// Daily Bloom root — Sakura theme + AuthGate.
///
/// AuthGate shows LoginScreen when logged out, AppShell when logged in.
/// The whole MaterialApp rebuilds when the theme changes (live skins).
class DailyBloomApp extends StatelessWidget {
  const DailyBloomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (_, __) => MaterialApp(
        title: 'Daily Bloom',
        debugShowCheckedModeBanner: false,
        theme: SakuraTheme.buildTheme(),
        // Cap system text scaling at 1.3x: the layout stays legible for
        // accessibility without the sub-12px labels blowing out cards.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
            ),
            child: child!,
          );
        },
        home: const AuthGate(),
      ),
    );
  }
}
