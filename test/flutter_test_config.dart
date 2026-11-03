import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:daily_bloom/data/task_repository.dart';
import 'package:daily_bloom/game/gamification_state.dart';
import 'package:daily_bloom/theme/sakura_theme.dart';

/// Global widget-test bootstrap.
///
/// - GoogleFonts (Inter + Zen Kaku Gothic New) fetches over HTTP at
///   runtime; widget tests have no network, so text themes would fall back
///   after the test already ran. Disable the fetch seam for every test —
///   production keeps the real brand pairing.
/// - The repository's background outbox-retry loop would leave a pending
///   timer at the end of tests that go offline; disable it here (its own
///   tests opt back in).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SakuraTheme.useGoogleFonts = false;
  TaskRepository.autoRetry = false;
  GamificationStateNotifier.timersEnabled = false;
  // The repository is a production singleton, but each Flutter test should
  // start with a clean in-memory cache and a fresh injectable API seam.
  setUp(() {
    TaskRepository.instance.debugReset();
  });
  await testMain();
}
