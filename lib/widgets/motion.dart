import 'dart:async';

import 'package:flutter/material.dart';

import '../data/haptics.dart';
import '../theme/app_motion.dart';

/// Staggered entrance for lists: fades + rises in after [delayMs].
/// Wrap headers, cards, and list rows. Delete the wrapper to revert.
/// Set [animate] false for rows past the first screenful — they appear
/// instantly instead of stacking timers (mobile jank fix).
///
/// Pass [onceKey] for list rows: the first mount with that key animates,
/// every later mount in the session renders instantly. Tab switches,
/// rebuilds, and scroll-recycling then feel instant while first paint
/// keeps its cascade. New items (new keys) still delight once.
class Entrance extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final double rise;
  final bool animate;
  final String? onceKey;

  /// Keys that already played their entrance this session.
  static final Set<String> _playedOnce = {};

  const Entrance({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.rise = AppMotion.entranceRise,
    this.animate = true,
    this.onceKey,
  });

  /// Test-only: clear the session-once memory.
  @visibleForTesting
  static void debugResetOnceKeys() => _playedOnce.clear();

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> {
  bool _shown = false;
  Timer? _timer;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _shown = true;
      _resolved = true;
      return;
    }
    // Session-once rows replay as instant: the cascade is a first-paint
    // delight, not a every-rebuild tax.
    final once = widget.onceKey;
    if (once != null && Entrance._playedOnce.contains(once)) {
      _shown = true;
      _resolved = true;
      return;
    }
    if (widget.delayMs <= 0) {
      _shown = true;
      _resolved = true;
      if (once != null) Entrance._playedOnce.add(once);
      return;
    }
    _timer = Timer(Duration(milliseconds: widget.delayMs), () {
      if (once != null) Entrance._playedOnce.add(once);
      if (mounted) setState(() => _shown = true);
    });
  }

  // MediaQuery may only be read after initState (didChangeDependencies
  // is the first legal point) — reading it in initState threw an
  // assertion inside ListView keep-alive children (goals screen).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    // Respect reduced-motion: appear instantly, no timers.
    final mq = MediaQuery.maybeOf(context);
    if (mq != null && mq.disableAnimations) {
      _timer?.cancel();
      _timer = null;
      _shown = true;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Animate off, or zero delay: render the bare child — no lingering
    // AnimatedOpacity/AnimatedSlide wrappers to lay out on every rebuild.
    if (!widget.animate) return widget.child;
    if (!_shown) {
      return Opacity(
        opacity: 0,
        child: Transform.translate(
          offset: Offset(0, widget.rise / 100),
          child: widget.child,
        ),
      );
    }
    if (widget.delayMs <= 0) return widget.child;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: AppMotion.entrance,
      curve: AppMotion.entranceCurve,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : Offset(0, widget.rise / 100),
        duration: AppMotion.entrance,
        curve: AppMotion.entranceSlideCurve,
        child: widget.child,
      ),
    );
  }
}

/// Stagger helper: first [maxAnimated] children animate with a
/// [stepMs] cascade, the rest render instantly. Use for task lists
/// so a 30-item Done column doesn't stack 30 timers on first paint.
class Stagger {
  static int delayFor(int index,
      {int stepMs = 40, int maxMs = 200, int maxAnimated = 8}) {
    if (index >= maxAnimated) return -1; // -1 = no animation
    return (index * stepMs).clamp(0, maxMs);
  }

  static Widget item({
    required int index,
    required Widget child,
    int stepMs = 40,
    int maxAnimated = AppMotion.staggerMaxAnimated,
  }) {
    final d = delayFor(index, stepMs: stepMs, maxAnimated: maxAnimated);
    if (d < 0) return child;
    return Entrance(delayMs: d, child: child);
  }
}

/// Shimmer skeleton: premium loading placeholder that feels instant.
/// Grey blocks pulse via one controller — cheaper than N spinners and
/// reads as "content is coming" on mobile.
class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 8,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: AppMotion.shimmer,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced-motion: hold a static shimmer block.
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: SakuraColorsShimmer.base(context),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: 0.10 + 0.12 * _c.value),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.25, 0.5, 0.75],
          ),
        ),
      ),
    );
  }
}

class SakuraColorsShimmer {
  static Color base(BuildContext context) {
    // Cheap brightness check without importing the theme (avoids cycles).
    final b = Theme.of(context).brightness;
    return b == Brightness.dark
        ? const Color(0xFF2A2440)
        : const Color(0xFFF1E8EC);
  }
}

/// Bouncy press: springy 0.94 squash with haptic tick. Drop-in
/// replacement for [Pressable] where you want extra juice
/// (primary CTAs, bloom button, bottom-nav icons).
class BouncePress extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final bool haptic;

  const BouncePress(
      {super.key, required this.child, this.enabled = true, this.haptic = true});

  @override
  State<BouncePress> createState() => _BouncePressState();
}

class _BouncePressState extends State<BouncePress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!widget.enabled) return;
        setState(() => _down = true);
        // Tick on press-down (not release): the finger gets its
        // confirmation the instant it lands, matching the squash.
        AppHaptics.tap();
      },
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      behavior: HitTestBehavior.translucent,
      child: AnimatedScale(
        scale: _down ? AppMotion.pressScale : 1.0,
        duration: AppMotion.press,
        curve: AppMotion.pressCurve,
        child: widget.child,
      ),
    );
  }
}

/// Press physics: squashes to 0.96 while held. Visual only — it takes
/// no tap itself, so the inner button owns the gesture (no double-fire).
/// Remove to revert.
class Pressable extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const Pressable({super.key, required this.child, this.enabled = true});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.enabled) {
          setState(() => _down = true);
          AppHaptics.tap();
        }
      },
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      behavior: HitTestBehavior.translucent,
      child: AnimatedScale(
        scale: _down ? AppMotion.tapScale : 1.0,
        duration: AppMotion.tap,
        curve: AppMotion.tapCurve,
        child: widget.child,
      ),
    );
  }
}

/// Rolling integer counter: tweens from the previous value to the new
/// one (600ms ease-out) so XP / token tallies read as "growing" instead
/// of snapping. First paint animates up from zero.
class AnimatedInt extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String Function(int value)? formatter;
  final Duration duration;

  const AnimatedInt({
    super.key,
    required this.value,
    this.style,
    this.formatter,
    this.duration = AppMotion.shimmer,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, v, _) => Text(
        formatter?.call(v) ?? '$v',
        style: style,
      ),
    );
  }
}

/// Fast app route: 220ms fade + 0.97→1 scale in, 200ms ease-out.
/// Replaces the stock 300ms slide for pushed screens so both push
/// and back-pop feel instant, with less per-frame repaint than a
/// sliding parallax on web. Implicit animations only.
class SakuraPageRoute<T> extends PageRouteBuilder<T> {
  SakuraPageRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: AppMotion.pageEnter,
          reverseTransitionDuration: AppMotion.pageExit,
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            final eased = CurvedAnimation(
              parent: animation,
              curve: AppMotion.pageCurve,
              reverseCurve: AppMotion.pageReverseCurve,
            );
            final scale =
                Tween<double>(begin: AppMotion.pageScaleFrom, end: 1.0)
                    .animate(eased);
            return FadeTransition(
              opacity: eased,
              child: ScaleTransition(scale: scale, child: child),
            );
          },
        );
}
