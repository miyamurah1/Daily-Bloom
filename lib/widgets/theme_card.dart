import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';

/// Minimalist gamified store card.
///
/// Handles three purchase states without clutter:
/// - unowned → dark price pill (`◆ 500`)
/// - purchasing (`isBusy`) → spinner pill
/// - owned → `EQUIP` or `ACTIVE` pill
///
/// Desire details for the last 10/10:
/// - unowned previews stay blurred behind glass with a "Finish N to
///   unlock" hint — the payoff stays visible but honest.
/// - [AnimatedSwitcher] cross-fades the pill on buy/equip.
/// - [AnimatedScale] does a subtle 1.02x pulse when
///   `owned` flips false → true.
/// - [isLegendary] adds a faint slow-pulsing gold glow.
class ThemeCard extends StatefulWidget {
  final StoreTheme theme;
  final bool isActive;
  final bool isBusy;
  final VoidCallback? onAction;
  final bool isLegendary;

  /// Tapping "PREVIEW" paints this theme for a few seconds without
  /// equipping it. Null hides the button.
  final VoidCallback? onPreview;

  /// Earned progress hint for locked cards ("Finish 3 to unlock").
  /// Null hides the hint (owned / active cards never need it).
  final String? unlockHint;

  const ThemeCard({
    super.key,
    required this.theme,
    required this.isActive,
    this.isBusy = false,
    this.onAction,
    this.isLegendary = false,
    this.onPreview,
    this.unlockHint,
  });

  @override
  State<ThemeCard> createState() => _ThemeCardState();
}

class _ThemeCardState extends State<ThemeCard>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  AnimationController? _glow;
  late Animation<double> _glowOpacity;

  @override
  void initState() {
    super.initState();
    if (widget.isLegendary) _startGlow();
  }

  @override
  void didUpdateWidget(covariant ThemeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Purchase pulse: unowned → owned.
    if (!oldWidget.theme.owned && widget.theme.owned) _pulse();
    // Toggle glow controller with flag.
    if (widget.isLegendary && _glow == null) _startGlow();
    if (!widget.isLegendary && _glow != null) {
      _glow!.dispose();
      _glow = null;
    }
  }

  void _startGlow() {
    final c = AnimationController(
      vsync: this,
      duration: AppMotion.glow,
    )..repeat(reverse: true);
    _glowOpacity = Tween<double>(begin: 0.07, end: 0.20).animate(
      CurvedAnimation(parent: c, curve: AppMotion.settleInCurve),
    );
    _glow = c;
  }

  Future<void> _pulse() async {
    if (!mounted) return;
    setState(() => _scale = 1.02);
    await Future.delayed(AppMotion.tap);
    if (!mounted) return;
    setState(() => _scale = 1.0);
  }

  @override
  void dispose() {
    _glow?.dispose();
    super.dispose();
  }

  /// Stable legendary glow decoration — rasterized once. The pulse rides
  /// a [FadeTransition] layer above it; mutating `BoxShadow.color` per
  /// frame (old code) forced Skia to re-blur 28px at 60×/sec on Store.
  static const BoxDecoration _legendaryGlow = BoxDecoration(
    borderRadius: BorderRadius.all(Radius.circular(26)),
    boxShadow: [
      BoxShadow(
        color: Color(0xFFFFC107),
        blurRadius: 28,
        spreadRadius: 1,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final gradient = AppThemes.byId(t.id).preview;
    final tappable = !widget.isBusy && !widget.isActive;
    final locked = !t.owned;

    Widget face = _face(context, gradient, tappable);

    // Locked: blur the fantasy behind glass + honest unlock hint.
    Widget card = AnimatedScale(
      scale: _scale,
      duration: AppMotion.press,
      curve: AppMotion.pressCurve,
      child: locked
          ? ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                    child: face,
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            widget.unlockHint ??
                                'Finish tasks to unlock this skin',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onPreview != null)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _PreviewButton(
                        name: t.name,
                        onTap: widget.onPreview,
                      ),
                    ),
                ],
              ),
            )
          : face,
    );

    // Slow-pulsing legendary glow. Stack keeps the card opaque while the
    // shadow layer pulses behind it: [FadeTransition] only updates the
    // compositing layer's alpha — the const glow below is never re-blurred.
    final glow = _glow;
    if (widget.isLegendary && glow != null) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _glowOpacity,
              child: const DecoratedBox(decoration: _legendaryGlow),
            ),
          ),
          card,
        ],
      );
    }
    return card;
  }

  /// The glossy preview face (gradient + pill + name).
  Widget _face(BuildContext context, List<Color> gradient, bool tappable) {
    final t = widget.theme;
    return Container(
      height: 190,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradient,
        ),
        border: widget.isActive
            ? Border.all(color: SakuraColors.primary, width: 2.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: SakuraColors.primary.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          if (widget.isLegendary && _glow == null)
            BoxShadow(
              color: const Color(0xFFFFC107).withValues(alpha: 0.12),
              blurRadius: 28,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Stack(
        children: [
          if (widget.onPreview != null)
            Positioned(
              top: 0,
              left: 0,
              child: _PreviewButton(
                name: t.name,
                onTap: widget.onPreview,
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: tappable ? widget.onAction : null,
              behavior: HitTestBehavior.opaque,
              child: AnimatedSwitcher(
                duration: AppMotion.toggle,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: anim, child: child),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerRight,
                  children: [...previous, if (current != null) current],
                ),
                child: _ActionPill(
                  key: ValueKey<String>(
                    widget.isBusy
                        ? 'busy'
                        : widget.isActive
                            ? 'active'
                            : t.owned
                                ? 'equip'
                                : 'price-${t.price}',
                  ),
                  isActive: widget.isActive,
                  isBusy: widget.isBusy,
                  owned: t.owned,
                  price: t.price,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isLegendary)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      '✦ LEGENDARY',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFD54F),
                      ),
                    ),
                  ),
                Text(
                  t.label,
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
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

/// The small pill top-right. Keyed by state so [AnimatedSwitcher] fades
/// between price → spinner → EQUIP → ACTIVE.
class _ActionPill extends StatelessWidget {
  final bool isActive;
  final bool isBusy;
  final bool owned;
  final int price;

  const _ActionPill({
    super.key,
    required this.isActive,
    required this.isBusy,
    required this.owned,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    final label = isActive
        ? 'ACTIVE'
        : owned
            ? 'EQUIP'
            : '◆ $price';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? SakuraColors.primary
            : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: isBusy
          ? const SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}

/// Small "PREVIEW" pill (top-left of a theme card): applies the skin for
/// a few seconds without equipping it.
class _PreviewButton extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const _PreviewButton({required this.name, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Preview $name',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.eye, size: 11, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'PREVIEW',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
