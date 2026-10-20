import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/profile_name.dart';
import '../data/simple_mode.dart';
import '../game/gamification_state.dart';
import '../screens/search_screen.dart';
import '../theme/sakura_theme.dart';
import 'currency_explainer.dart';
import 'motion.dart';

/// Custom AppBar — Daily Bloom title + date subtitle + token pill.
///
/// Matches design: 日常 / DAILY BLOOM on the left,
/// token balance + STORE chips on the right. When [greetingName] is set,
/// the subtitle becomes a time-aware greeting ("GOOD MORNING, MAYA") —
/// the cheapest warmth in the app.
class DailyBloomAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final int tokens;
  final String? greetingName;
  final VoidCallback? onStoreTap;
  final VoidCallback? onLogoutTap;
  final VoidCallback? onSettingsTap;

  const DailyBloomAppBar(
      {super.key,
      this.tokens = 450,
      this.greetingName,
      this.onStoreTap,
      this.onLogoutTap,
      this.onSettingsTap});

  @override
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEE, MMM d').format(DateTime.now());

    return SafeArea(
      bottom: false,
      // Narrow phones (< 400): tighter gutters, icon-only store
      // action, date suffix hidden — the fixed brand + pills would
      // otherwise overflow the bar on small widths.
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 400;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                narrow ? 12 : 20, 12, narrow ? 12 : 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '日常',
                        // Decorative wordmark: keep its optical size stable
                        // at large system text scales (the functional labels
                        // below still scale).
                        textScaler: TextScaler.noScaling,
                        style: SakuraTheme.display(
                          fontSize: 30,
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          color: SakuraColors.primary,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              greetingName == null ||
                                      greetingName!.trim().isEmpty
                                  ? 'DAILY BLOOM'
                                  : ProfileName.greeting(greetingName!)
                                      .toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 3.2,
                                fontWeight: FontWeight.w600,
                                color: SakuraColors.inkFaint,
                              ),
                            ),
                          ),
                          if (!narrow) ...[
                            SizedBox(width: narrow ? 6 : 8),
                            Flexible(
                              child: Text(
                                '•  $today',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w500,
                                  color: SakuraColors.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Search is always visible — never buried in overflow.
                Semantics(
                  button: true,
                  label: 'Search tasks',
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      SakuraPageRoute(builder: (_) => const SearchScreen()),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: EdgeInsets.all(narrow ? 5 : 7),
                      decoration: BoxDecoration(
                        color: SakuraColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: SakuraColors.cardBorder),
                      ),
                      child: Tooltip(
                        message: 'Search tasks',
                        child: Icon(LucideIcons.search,
                            size: 14, color: SakuraColors.inkSoft),
                      ),
                    ),
                  ),
                ),
                // The theme shop is an Advanced surface: hidden in Simple
                // Mode, still one toggle away in Settings.
                if (!SimpleMode.instance.enabled) ...[
                  SizedBox(width: narrow ? 6 : 8),
                  narrow
                      ? GestureDetector(
                          onTap: onStoreTap,
                          child: Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: EdgeInsets.all(narrow ? 5 : 7),
                            decoration: BoxDecoration(
                              color: SakuraColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: SakuraColors.cardBorder),
                            ),
                            child: Tooltip(
                              message: 'Open store',
                              child: Icon(LucideIcons.store,
                                  size: 14, color: SakuraColors.inkSoft),
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: onStoreTap,
                          child: _Pill(
                            child: Text(
                              'STORE',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700,
                                color: SakuraColors.inkSoft,
                              ),
                            ),
                          ),
                        ),
                ],
                const SizedBox(width: 6),
                const _TokenPill(),
                if (onLogoutTap != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onLogoutTap,
                    child: Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: EdgeInsets.all(narrow ? 5 : 7),
                      decoration: BoxDecoration(
                        color: SakuraColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: SakuraColors.cardBorder),
                      ),
                      child: Tooltip(
                        message: 'Log out',
                        child: Icon(LucideIcons.logOut,
                            size: 14, color: SakuraColors.inkSoft),
                      ),
                    ),
                  ),
                ],
                if (onSettingsTap != null) ...[
                  SizedBox(width: narrow ? 6 : 8),
                  GestureDetector(
                    onTap: onSettingsTap,
                    child: Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: EdgeInsets.all(narrow ? 5 : 7),
                      decoration: BoxDecoration(
                        color: SakuraColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: SakuraColors.cardBorder),
                      ),
                      child: Tooltip(
                        message: 'Settings',
                        child: Icon(LucideIcons.settings,
                            size: 14, color: SakuraColors.inkSoft),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Pill({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: SakuraColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SakuraColors.cardBorder),
        ),
        child: child,
      ),
    );
  }
}

/// Token pill with a first-run dot: until the currency explainer has
/// been opened once, a 6px dot says "tap me". Persisted, so it never
/// nags twice. Defaults to seen (no dot flash before prefs load).
class _TokenPill extends StatefulWidget {
  const _TokenPill();

  static const seenKey = 'bloom_currency_seen_v1';

  @override
  State<_TokenPill> createState() => _TokenPillState();
}

class _TokenPillState extends State<_TokenPill> {
  bool _seen = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _seen = prefs.getBool(_TokenPill.seenKey) ?? false);
    } catch (_) {}
  }

  Future<void> _open(BuildContext context) async {
    if (!_seen) {
      setState(() => _seen = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_TokenPill.seenKey, true);
      } catch (_) {}
    }
    if (!context.mounted) return;
    showCurrencyExplainer(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GamificationStateNotifier.instance,
      builder: (context, _) => Semantics(
        button: true,
        excludeSemantics: true,
        label:
            '${GamificationStateNotifier.instance.tokens} tokens. Show what coins mean.',
        child: _Pill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
            if (!_seen)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: SakuraColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            Icon(
              LucideIcons.diamond,
              size: 11,
              color: SakuraColors.primary,
            ),
            const SizedBox(width: 5),
            AnimatedInt(
              value: GamificationStateNotifier.instance.tokens,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SakuraColors.primary,
                fontFeatures: const [
                  FontFeature.tabularFigures()
                ],
              ),
            ),
          ],
        ),
        onTap: () => _open(context),
      ),
      ),
    );
  }
}
