import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/background_music.dart';
import '../data/habit_store.dart';
import '../data/profile_name.dart';
import '../data/reminders.dart';
import '../data/simple_mode.dart';
import '../data/task_repository.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_mark.dart';
import '../widgets/motion.dart';

/// First-launch onboarding — three calm slides that explain the loop
/// (plant → complete → grow). Completion persists
/// [seenKey] so it only ever shows once; auth_gate renders it before
/// AppShell on first run.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  /// Allows guest onboarding to have its own completion state instead of
  /// inheriting a signed-in account's device-level flag.
  final String completionKey;

  /// SharedPreferences flag written when the user reaches the end (or
  /// taps Skip).
  static const seenKey = 'bloom_onboarding_seen_v1';

  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.completionKey = seenKey,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageNotifier = ValueNotifier<int>(0);
  int get _page => _pageNotifier.value;

  // Step 4 personalization — all optional; Skip never seeds anything.
  String _name = '';
  String _firstTask = '';
  int _focusIndex = 0;
  bool _wantReminder = false;
  bool _simpleMode = true;

  @override
  void initState() {
    super.initState();
    BackgroundMusic.start();
  }

  @override
  void dispose() {
    _pageNotifier.dispose();
    super.dispose();
  }

  Future<void> _finish({bool personalize = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
       await prefs.setBool(widget.completionKey, true);
    } catch (_) {}
    if (personalize) {
      // Name powers the home greeting; the chosen focus plants one tiny
      // starter ritual (idempotent — the store dedupes by name).
      await ProfileName.write(_name);
      if (_firstTask.trim().isNotEmpty) {
        try {
          await TaskRepository.instance.createTask(
            title: _firstTask.trim(),
            folder: 'Productivity',
            tag: 'General',
          );
        } catch (_) {}
      }
      if (_focusIndex < RitualPresets.presets.length) {
        try {
          await HabitStore.instance.load();
          await HabitStore.instance
              .applyPreset(RitualPresets.presets[_focusIndex]);
        } catch (_) {}
      }
      await SimpleMode.instance.setEnabled(_simpleMode);
      if (_wantReminder) {
        // The willing moment: one permission prompt, right after value.
        await ReminderService.instance.setEnabled(true);
      }
    }
    widget.onDone();
  }

  Widget _buildStep(int page) {
    Widget step;
    switch (page) {
      case 0:
        step = const _Slide(
          icon: LucideIcons.flower,
          title: 'Welcome to Daily Bloom',
          subtitle: 'Complete tasks. See proof. Grow.',
          useLogo: true,
        );
      case 1:
        step = const _Slide(
          icon: LucideIcons.flame,
          title: 'Complete tasks → grow your heatmap',
          subtitle: 'Every finished bloom paints a square and earns XP.',
          showHeatmap: true,
        );
      case 2:
        step = const _Slide(
          icon: LucideIcons.sparkles,
          title: 'Set intentions → build streaks → collect blooms',
          subtitle: 'Small steps, tended daily, become a garden.',
        );
      case 3:
        step = _PersonalizeStep(
          name: _name,
          firstTask: _firstTask,
          focusIndex: _focusIndex,
          reminderOn: _wantReminder,
          simpleOn: _simpleMode,
          onName: (v) => setState(() => _name = v),
          onFirstTask: (v) => setState(() => _firstTask = v),
          onFocus: (i) => setState(() => _focusIndex = i),
          onReminder: (v) => setState(() => _wantReminder = v),
          onSimple: (v) => setState(() => _simpleMode = v),
        );
      default:
        return const SizedBox.shrink();
    }
    return KeyedSubtree(
      key: ValueKey<int>(page),
      child: step,
    );
  }

  void _next() {
    if (_page >= 3) {
      _finish(personalize: true);
      return;
    }
    _pageNotifier.value = _pageNotifier.value + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _OnboardingBackdrop()),
          SafeArea(
            child: Column(
              children: [
                Entrance(
                  delayMs: 40,
                  rise: 6,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _pageNotifier,
                    builder: (context, page, _) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: page < 3
                              ? TextButton(
                                  onPressed: () => _finish(personalize: false),
                                  child: Text(
                                    'Skip',
                                    style: TextStyle(
                                      color: SakuraColors.inkFaint,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : const SizedBox(height: 40),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _pageNotifier,
                    builder: (context, page, _) {
                      return AnimatedSwitcher(
                        duration: AppMotion.pageTurn,
                        // New slides come in from the right, the old one
                        // leaves to the left. AnimatedSwitcher plays the old
                        // child's animation in reverse, so its begin offset has
                        // to be negative — otherwise both pages fly in from the
                        // same edge and cross over each other.
                        transitionBuilder: (child, animation) {
                          final childPage =
                              (child.key as ValueKey<int>?)?.value;
                          final outgoing =
                              childPage != null && childPage != page;
                          final tween = Tween<Offset>(
                            begin: Offset(outgoing ? -1.15 : 1.15, 0),
                            end: Offset.zero,
                          );
                          return SlideTransition(
                            position: tween.animate(
                              CurvedAnimation(
                                  parent: animation, curve: Curves.easeOut),
                            ),
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: _buildStep(page),
                      );
                    },
                  ),
                ),
                // Dots: Wrap, not Row — at 1.3x text scale with a narrow
                // viewport the 4 pills + margins exceed the line width and a
                // Row throws a 60px RenderFlex overflow (web log).
                Entrance(
                  delayMs: 220,
                  rise: 10,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _pageNotifier,
                    builder: (context, page, _) {
                      return Wrap(
                        alignment: WrapAlignment.center,
                        runSpacing: 8,
                        children: List.generate(4, (i) {
                          final active = i == page;
                          return AnimatedContainer(
                            duration: AppMotion.nav,
                            curve: AppMotion.tapCurve,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: active
                                  ? SakuraColors.primary
                                  : SakuraColors.navInactive,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Entrance(
                  delayMs: 300,
                  rise: 14,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _pageNotifier,
                    builder: (context, page, _) {
                      final last = page >= 3;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SizedBox(
                          width: double.infinity,
                          child: Semantics(
                            button: true,
                            label: last ? 'Enter my garden' : 'Next',
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: SakuraColors.primary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _next,
                              child: Text(
                                last ? 'Enter my garden' : 'Next',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool showHeatmap;
  final bool useLogo;

  const _Slide({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showHeatmap = false,
    this.useLogo = false,
  });

  Color _heat(int i) {
    switch (i) {
      case 1:
        return SakuraColors.heat1;
      case 2:
        return SakuraColors.heat2;
      case 3:
        return SakuraColors.heat3;
      default:
        return SakuraColors.heat4;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scrollable with a centred min-height: tall slides (the heatmap, long
    // titles) and large text scales scroll instead of overflowing the short
    // viewport between the Skip row and the dots. The max width keeps line
    // lengths readable on tablets and desktop.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 380,
                minHeight: (constraints.maxHeight - 16).clamp(0.0, 1e6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SakuraColors.surface,
              border: Border.all(
                color: SakuraColors.primary.withValues(alpha: 0.16),
              ),
              boxShadow: [
                BoxShadow(
                  color: SakuraColors.ink.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: useLogo
                  ? const BloomMark(size: 48)
                  : Icon(icon, size: 38, color: SakuraColors.primary),
            ),
          ),
          const SizedBox(height: 24),
          if (showHeatmap) ...[
            Semantics(
              label: 'Contribution heatmap preview',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < 35; i++)
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _heat(i % 5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              height: 1.3,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: SakuraColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: SakuraColors.inkSoft,
            ),
          ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Step 4 — make it yours. All optional: name powers the greeting, the
/// focus chip plants one matching starter ritual, and the two switches
/// are the willing-moment asks (permission + calm). Scrollable so the
/// keyboard never buries the CTA.
class _PersonalizeStep extends StatelessWidget {
  /// Chip labels — the first three mirror [RitualPresets.presets] order;
  /// the last one plants nothing.
  static const labels = [
    'Calm mornings',
    'Deep work',
    'Strong body',
    'No rituals',
  ];

  final String name;
  final String firstTask;
  final int focusIndex;
  final bool reminderOn;
  final bool simpleOn;
  final ValueChanged<String> onName;
  final ValueChanged<String> onFirstTask;
  final ValueChanged<int> onFocus;
  final ValueChanged<bool> onReminder;
  final ValueChanged<bool> onSimple;

  const _PersonalizeStep({
    required this.name,
    required this.firstTask,
    required this.focusIndex,
    required this.reminderOn,
    required this.simpleOn,
    required this.onName,
    required this.onFirstTask,
    required this.onFocus,
    required this.onReminder,
    required this.onSimple,
  });

  Widget _chip(BuildContext context, int i) {
    final active = i == focusIndex;
    return Semantics(
      button: true,
      selected: active,
      label: labels[i],
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onFocus(i),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.nav,
          curve: AppMotion.tapCurve,
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? SakuraColors.primary.withValues(alpha: 0.14)
              : SakuraColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  active ? SakuraColors.primary : SakuraColors.cardBorder),
        ),
          child: Text(
            labels[i],
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? SakuraColors.primary : SakuraColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: SakuraColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11.5, color: SakuraColors.inkSoft)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: SakuraColors.primary,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          const SizedBox(height: 8),
          Text(
            'Make it yours',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: SakuraColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'All optional — you can change these later in Settings.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, height: 1.4, color: SakuraColors.inkSoft),
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: onName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'What should we call you?',
              hintText: 'Your name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: onFirstTask,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'What is the single most important thing today?',
              hintText: 'e.g. Meditate 10 mins',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'What are you tending?',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SakuraColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'We\'ll plant a tiny starter ritual to match.',
            style: TextStyle(fontSize: 11.5, color: SakuraColors.inkSoft),
          ),
          const SizedBox(height: 10),
          Wrap(
            children: [for (var i = 0; i < labels.length; i++) _chip(context, i)],
          ),
          const SizedBox(height: 10),
          _switchRow(
            icon: LucideIcons.bell,
            title: 'Daily nudge',
            subtitle: 'A gentle reminder at 9:00 — you pick the hour later.',
            value: reminderOn,
            onChanged: onReminder,
          ),
          _switchRow(
            icon: LucideIcons.moon,
            title: 'Simple mode',
            subtitle: 'A calmer home — power tools stay hidden until wanted.',
            value: simpleOn,
            onChanged: onSimple,
          ),
          const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}


/// Soft animated backdrop so opening onboarding feels alive (drifting blooms).
class _OnboardingBackdrop extends StatefulWidget {
  const _OnboardingBackdrop();

  @override
  State<_OnboardingBackdrop> createState() => _OnboardingBackdropState();
}

class _OnboardingBackdropState extends State<_OnboardingBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
      _c.value = 0.5;
    } else if (_c.value == 0.0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_c.value);
          final a = 0.10 + 0.06 * t;
          final b = 0.08 + 0.05 * (1 - t);
          return Stack(
            children: [
              Positioned(
                top: -40 + 24 * t,
                left: -30 + 18 * (1 - t),
                child: _GlowBlob(
                  size: 220,
                  color: SakuraColors.primary.withValues(alpha: a),
                ),
              ),
              Positioned(
                top: 120 - 16 * t,
                right: -50 + 20 * t,
                child: _GlowBlob(
                  size: 180,
                  color: SakuraColors.heatPeak.withValues(alpha: b),
                ),
              ),
              Positioned(
                bottom: -30 + 20 * (1 - t),
                left: 40 + 30 * t,
                child: _GlowBlob(
                  size: 200,
                  color: SakuraColors.primarySoft.withValues(alpha: a * 0.9),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
