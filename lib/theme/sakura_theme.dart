import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Full palette for one store theme. The server catalog (ids, names,
/// prices) mirrors these 1:1 — pixels here, prices there.
class AppThemeData {
  final String id;
  final String name;
  final String label;
  final List<Color> preview;

  final Color background;
  final Color surface;
  final Color surfacePink;
  final Color cardBorder;

  final Color ink;
  final Color inkSoft;
  final Color inkFaint;

  final Color primary;
  final Color primaryDark;
  final Color primarySoft;

  final Color tagBg;
  final Color tagText;

  final Color heat0;
  final Color heat1;
  final Color heat2;
  final Color heat3;
  final Color heat4;
  final Color heatPeak;

  final Color navActive;
  final Color navInactive;

  /// True for dark palettes (Midnight Tokyo). Drives whether
  /// [SakuraTheme] builds from [ThemeData.dark] (proper contrast for
  /// native pickers, dialogs, menus, tooltips) or [ThemeData.light].
  final bool isDark;

  const AppThemeData({
    required this.id,
    required this.name,
    required this.label,
    required this.preview,
    required this.background,
    required this.surface,
    required this.surfacePink,
    required this.cardBorder,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.tagBg,
    required this.tagText,
    required this.heat0,
    required this.heat1,
    required this.heat2,
    required this.heat3,
    required this.heat4,
    required this.heatPeak,
    required this.navActive,
    required this.navInactive,
    this.isDark = false,
  });
}

/// The store themes. Midnight Tokyo is the default dark baseline
/// (#14121E, near #120D1C); Edo stays free and always owned.
abstract class AppThemes {
  static const sakura = AppThemeData(
    id: 'edo',
    name: 'Edo Period',
    label: 'CLASSIC',
    preview: [Color(0xFFE8DCC8), Color(0xFF2D3A4A)],
    background: Color(0xFFFAF9F6),
    surface: Colors.white,
    surfacePink: Color(0xFFFFF2F5),
    cardBorder: Color(0xFFD9A6B2),
    ink: Color(0xFF2D2D2D),
    inkSoft: Color(0xFF5E5357),
    inkFaint: Color(0xFF756A6F),
    primary: Color(0xFFC41E3A),
    primaryDark: Color(0xFF9E1430),
    primarySoft: Color(0xFFFBE3E8),
    tagBg: Color(0xFFFFEDF1),
    tagText: Color(0xFFB01E44),
    heat0: Color(0xFFE7C2CC),
    heat1: Color(0xFFD98AA0),
    heat2: Color(0xFFCC6A88),
    heat3: Color(0xFFD92B4B),
    heat4: Color(0xFF8E0F2B),
    heatPeak: Color(0xFFFFC107),
    navActive: Color(0xFFC41E3A),
    navInactive: Color(0xFF9A7580),
  );

  static const midnight = AppThemeData(
    id: 'midnight',
    name: 'Midnight Tokyo',
    label: 'MODERN',
    isDark: true,
    preview: [Color(0xFF1A1033), Color(0xFF4A1E4F)],
    background: Color(0xFF14121E),
    surface: Color(0xFF1E1A2E),
    surfacePink: Color(0xFF2A2338),
    cardBorder: Color(0xFF6B608F),
    ink: Color(0xFFF2EFFA),
    inkSoft: Color(0xFFA79FC4),
    inkFaint: Color(0xFFA79FC4),
    primary: Color(0xFFE84A6B),
    primaryDark: Color(0xFFB52A4D),
    primarySoft: Color(0xFF3A2340),
    tagBg: Color(0xFF2E2140),
    tagText: Color(0xFFF08CA8),
    heat0: Color(0xFF35304D),
    heat1: Color(0xFF7A3D62),
    heat2: Color(0xFFA03E74),
    heat3: Color(0xFFD8557F),
    heat4: Color(0xFFF4719E),
    heatPeak: Color(0xFFFFC107),
    navActive: Color(0xFFE84A6B),
    navInactive: Color(0xFF9A90BB),
  );

  static const kyoto = AppThemeData(
    id: 'kyoto',
    name: 'Kyoto Garden',
    label: 'NATURE',
    preview: [Color(0xFF2D4A2B), Color(0xFF7A9B5A)],
    background: Color(0xFFF3F5EA),
    surface: Color(0xFFFDFEFA),
    surfacePink: Color(0xFFEFF4E2),
    cardBorder: Color(0xFF9CAF86),
    ink: Color(0xFF2A3325),
    inkSoft: Color(0xFF556044),
    inkFaint: Color(0xFF5F6D55),
    primary: Color(0xFF3E7C4F),
    primaryDark: Color(0xFF2A5A38),
    primarySoft: Color(0xFFE3EDD6),
    tagBg: Color(0xFFE9F1DF),
    tagText: Color(0xFF355E2B),
    heat0: Color(0xFFD4DDBE),
    heat1: Color(0xFFA3B87F),
    heat2: Color(0xFF7D9C5F),
    heat3: Color(0xFF4E8A4C),
    heat4: Color(0xFF2A5A38),
    heatPeak: Color(0xFFFFC107),
    navActive: Color(0xFF3E7C4F),
    navInactive: Color(0xFF75805F),
  );

  static const ocean = AppThemeData(
    id: 'ocean',
    name: 'Kamogawa Blue',
    label: 'OCEAN',
    preview: [Color(0xFF12395B), Color(0xFF3E92CC)],
    background: Color(0xFFF0F5FA),
    surface: Color(0xFFFBFDFF),
    surfacePink: Color(0xFFE3EEF7),
    cardBorder: Color(0xFF8AA9C4),
    ink: Color(0xFF1E2A38),
    inkSoft: Color(0xFF5D7285),
    inkFaint: Color(0xFF4E6579),
    primary: Color(0xFF1565A0),
    primaryDark: Color(0xFF0D476E),
    primarySoft: Color(0xFFD6E7F5),
    tagBg: Color(0xFFE0EDF8),
    tagText: Color(0xFF0F5A90),
    heat0: Color(0xFFBDD2E5),
    heat1: Color(0xFF8FB6D4),
    heat2: Color(0xFF4E8ABA),
    heat3: Color(0xFF2A6FA5),
    heat4: Color(0xFF0D476E),
    heatPeak: Color(0xFFFFC107),
    navActive: Color(0xFF1565A0),
    navInactive: Color(0xFF5F7D95),
  );

  static AppThemeData byId(String id) {
    switch (id) {
      case 'midnight':
        return midnight;
      case 'ocean':
        return ocean;
      case 'kyoto':
        return kyoto;
      case 'edo':
      default:
        return sakura;
    }
  }
}

/// Palette facade the whole app already uses. These were `static const`;
/// they are now getters over the active theme, so every screen re-skins
/// when [ThemeStore] notifies. (That is why `const` usages of these had
/// to go — const widgets never rebuild.)
///
/// Migration path: [SakuraThemeExtension] now carries the same palette
/// inside [ThemeData], so new code should read `context.bloom` (a
/// [Theme.of] lookup, injectable in tests) instead of this global.
/// This class stays as a thin shim so the existing ~870 call sites keep
/// working while migrating gradually.
abstract class SakuraColors {
  static AppThemeData _active = AppThemes.midnight;
  static AppThemeData get active => _active;
  static void setActive(AppThemeData t) => _active = t;

  static Color get background => _active.background;
  static Color get surface => _active.surface;
  static Color get surfacePink => _active.surfacePink;
  static Color get cardBorder => _active.cardBorder;

  static Color get ink => _active.ink;
  static Color get inkSoft => _active.inkSoft;
  static Color get inkFaint => _active.inkFaint;

  static Color get primary => _active.primary;
  static Color get primaryDark => _active.primaryDark;
  static Color get primarySoft => _active.primarySoft;

  static Color get tagBg => _active.tagBg;
  static Color get tagText => _active.tagText;

  static Color get heat0 => _active.heat0;
  static Color get heat1 => _active.heat1;
  static Color get heat2 => _active.heat2;
  static Color get heat3 => _active.heat3;
  static Color get heat4 => _active.heat4;
  static Color get heatPeak => _active.heatPeak;

  static Color get navActive => _active.navActive;
  static Color get navInactive => _active.navInactive;

  /// Preferred accessor for new code: `context.bloom.primary` instead of
  /// `SakuraColors.primary`. Falls back to the active global when no
  /// [SakuraThemeExtension] is in the tree (e.g. legacy tests).
  static AppThemeData of(BuildContext context) =>
      Theme.of(context).extension<SakuraThemeExtension>()?.data ?? _active;
}

/// Idiomatic accessor: `context.bloom` — a [Theme.of] lookup over
/// [SakuraThemeExtension], so widget tests can inject any palette via
/// `ThemeData(extensions: [...])` without touching globals.
extension SakuraContext on BuildContext {
  AppThemeData get bloom => SakuraColors.of(this);
}

/// Owns the equipped theme: device preference for instant paint,
/// server value as the source of truth after login.
class ThemeStore extends ChangeNotifier {
  static const _kTheme = 'bloom_theme';

  ThemeStore._();
  static final ThemeStore instance = ThemeStore._();

  String themeId = 'edo';

  /// Before runApp: paint the last-used theme with zero flash.
  Future<void> preload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _apply(prefs.getString(_kTheme) ?? 'edo', notify: false);
    } catch (_) {
      _apply('edo', notify: false);
    }
  }

  /// After login/restore: server wins, then persist locally.
  /// Takes the API client as a parameter to avoid a
  /// theme → api → auth → theme import cycle.
  Future<void> sync(Future<StoreState> Function() loadStore) async {
    try {
      final store = await loadStore();
      _apply(store.active, notify: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTheme, themeId);
    } catch (_) {
      // Offline: keep whatever is painted.
    }
  }

  Future<void> equip(
      Future<void> Function() equipRemote, String id) async {
    _previewTimer?.cancel();
    _previewRestore = null;
    await equipRemote();
    _apply(id, notify: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTheme, themeId);
    } catch (_) {}
  }

  void resetToDefault() {
    _previewTimer?.cancel();
    _previewRestore = null;
    _apply('edo', notify: true);
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kTheme, themeId))
        .catchError((_) => false);
  }

  Timer? _previewTimer;
  String? _previewRestore;

  /// Temporarily paints [id] for [duration], then restores the theme that
  /// was active before the FIRST preview began — so rapidly previewing
  /// several skins always returns to the real equipped theme. Never
  /// persisted: a preview is a look, not an equip.
  void preview(String id, {Duration duration = const Duration(seconds: 5)}) {
    _previewRestore ??= themeId;
    _previewTimer?.cancel();
    _apply(id, notify: true);
    _previewTimer = Timer(duration, () {
      final restore = _previewRestore ?? themeId;
      _previewRestore = null;
      _apply(restore, notify: true);
    });
  }

  void _apply(String id, {required bool notify}) {
    themeId = AppThemes.byId(id).id;
    SakuraColors.setActive(AppThemes.byId(id));
    if (notify) notifyListeners();
  }
}

/// Store catalog entry (price + ownership come from the server).
class StoreState {
  final int balance;
  final String active;
  final List<StoreTheme> themes;

  const StoreState(
      {this.balance = 450, this.active = 'edo', this.themes = const []});

  factory StoreState.fromJson(Map<String, dynamic> j) => StoreState(
        balance: (j['balance'] as num?)?.toInt() ?? 450,
        active: '${j['active'] ?? 'edo'}',
        themes: j['themes'] is List
            ? (j['themes'] as List)
                .map((e) =>
                    StoreTheme.fromJson(e as Map<String, dynamic>))
                .toList()
            : [],
      );
}

class StoreTheme {
  final String id;
  final String name;
  final String label;
  final int price;
  final bool owned;

  const StoreTheme({
    required this.id,
    required this.name,
    required this.label,
    this.price = 0,
    this.owned = false,
  });

  factory StoreTheme.fromJson(Map<String, dynamic> j) => StoreTheme(
        id: '${j['id']}',
        name: '${j['name']}',
        label: '${j['label'] ?? ''}',
        price: (j['price'] as num?)?.toInt() ?? 0,
        owned: j['owned'] is bool
            ? j['owned'] as bool
            : '${j['owned']}'.toLowerCase() == 'true',
      );
}

abstract class SakuraTheme {
  static ThemeData? _cachedLight;
  static String? _cachedThemeId;

  /// Test seam: Inter needs an HTTP fetch, which widget tests (no
  /// network) cannot do. Tests set this to false for a synchronous
  /// platform text theme; production keeps the brand font.
  @visibleForTesting
  static bool useGoogleFonts = true;

  /// Zen Kaku Gothic New — Japanese titles, brand marks ('日常') and
  /// screen headers. Pairs with Inter for numbers, tables and body copy.
  /// Never throws: falls back to the current text style when fonts
  /// cannot resolve (offline phone, widget test).
  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
    if (!useGoogleFonts) return base;
    try {
      return GoogleFonts.zenKakuGothicNew(textStyle: base);
    } catch (_) {
      return base;
    }
  }

  /// Sakura ink over Inter when fonts resolve, over the platform theme
  /// when they cannot (offline phone, widget test). Never throws.
  ///
  /// Bespoke pairing: Zen Kaku Gothic New for the display / headline /
  /// title voices (brand + section headers), Inter for everything
  /// functional (body, labels, numeric tables).
  static TextTheme _inkTextTheme(TextTheme base) {
    final fallback = base.apply(
      bodyColor: SakuraColors.ink,
      displayColor: SakuraColors.ink,
    );
    if (!useGoogleFonts) return fallback;
    try {
      final inter = GoogleFonts.interTextTheme(base);
      final zen = GoogleFonts.zenKakuGothicNewTextTheme(base);
      return inter
          .copyWith(
            displayLarge: zen.displayLarge,
            displayMedium: zen.displayMedium,
            displaySmall: zen.displaySmall,
            headlineLarge: zen.headlineLarge,
            headlineMedium: zen.headlineMedium,
            headlineSmall: zen.headlineSmall,
            titleLarge: zen.titleLarge,
          )
          .apply(bodyColor: SakuraColors.ink, displayColor: SakuraColors.ink);
    } catch (_) {
      return fallback;
    }
  }

  /// Builds the active [ThemeData]. Named for the store API but no
  /// longer light-only: dark palettes (Midnight Tokyo) construct from
  /// [ThemeData.dark] with a matching [Brightness.dark] color scheme so
  /// native pickers, dialogs, context menus and tooltips keep proper
  /// contrast instead of flashing a white Material surface.
  ///
  /// The palette also ships as a [SakuraThemeExtension] inside
  /// [ThemeData.extensions], so new code reads `context.bloom` (a plain
  /// [Theme.of] lookup, injectable in tests) instead of the
  /// [SakuraColors] global.
  static ThemeData buildTheme() => light();

  static ThemeData light() {
    // Cache per theme id: GoogleFonts.interTextTheme() parses font
    // metadata on every call — rebuilding ThemeData 60x/sec during
    // gamification ticks was a hidden jank source. Now one build
    // per theme swap.
    if (_cachedLight != null && _cachedThemeId == ThemeStore.instance.themeId) {
      return _cachedLight!;
    }
    final active = SakuraColors.active;
    final bool isDark = active.isDark;
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: SakuraColors.primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: SakuraColors.primary,
      surface: SakuraColors.surface,
    );
    _cachedLight = base.copyWith(
      scaffoldBackgroundColor: SakuraColors.background,
      colorScheme: scheme,
      extensions: [SakuraThemeExtension(SakuraColors.active)],
      // Offline-safe: GoogleFonts fetches Inter over HTTP at runtime, so
      // a widget test (or a phone with no signal) awaiting that future
      // fails after the test already passed. Apply Sakura ink over the
      // Inter text theme when it resolves; fall back to the platform
      // text theme with the same ink when it cannot.
      textTheme: _inkTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: SakuraColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: SakuraColors.ink),
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
      ),
      // Native surfaces (date/time pickers, alerts, menus and
      // long-press tooltips) read from these instead of hardcoding
      // white — the real fix behind "true dark mode".
      dialogTheme: DialogThemeData(backgroundColor: SakuraColors.surface),
      bottomSheetTheme:
          BottomSheetThemeData(backgroundColor: SakuraColors.surface),
      popupMenuTheme:
          PopupMenuThemeData(color: SakuraColors.surface),
      datePickerTheme:
          DatePickerThemeData(backgroundColor: SakuraColors.surface),
      timePickerTheme:
          TimePickerThemeData(backgroundColor: SakuraColors.surface),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? SakuraColors.surfacePink : SakuraColors.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          fontSize: 12,
          color: isDark ? SakuraColors.ink : Colors.white,
        ),
      ),
    );
    _cachedThemeId = ThemeStore.instance.themeId;
    return _cachedLight!;
  }

  /// Shared card decoration — rounded + subtle shadow.
  ///
  /// Cached per theme: BoxDecoration + Border + BoxShadow allocate on
  /// every TaskCard build otherwise (60+ cards × 60fps). Callers must
  /// NOT mutate the returned instance.
  static BoxDecoration? _cachedCard;
  static String? _cachedCardThemeId;
  static BoxDecoration cardDecoration() {
    if (_cachedCard != null &&
        _cachedCardThemeId == ThemeStore.instance.themeId) {
      return _cachedCard!;
    }
    _cachedCard = BoxDecoration(
      color: SakuraColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: SakuraColors.cardBorder),
      boxShadow: [
        BoxShadow(
          color: SakuraColors.primary.withValues(alpha: 0.06),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
    _cachedCardThemeId = ThemeStore.instance.themeId;
    return _cachedCard!;
  }

  /// Lighter card for dense lists (Kanban columns, history rows):
  /// no shadow at all — shadows force an extra saveLayer per card and
  /// are the #1 mobile overdraw cost in long lists.
  static BoxDecoration? _cachedFlat;
  static String? _cachedFlatThemeId;
  static BoxDecoration flatCardDecoration() {
    if (_cachedFlat != null &&
        _cachedFlatThemeId == ThemeStore.instance.themeId) {
      return _cachedFlat!;
    }
    _cachedFlat = BoxDecoration(
      color: SakuraColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: SakuraColors.cardBorder),
    );
    _cachedFlatThemeId = ThemeStore.instance.themeId;
    return _cachedFlat!;
  }
}

/// Carries the Sakura palette inside [ThemeData.extensions] so widgets
/// read it via [Theme.of] (`context.bloom`) instead of the
/// [SakuraColors] global. Injectable in tests:
///
/// ```dart
/// ThemeData(extensions: [SakuraThemeExtension(AppThemes.sakura)])
/// ```
@immutable
class SakuraThemeExtension extends ThemeExtension<SakuraThemeExtension> {
  final AppThemeData data;

  const SakuraThemeExtension(this.data);

  @override
  SakuraThemeExtension copyWith({AppThemeData? data}) =>
      SakuraThemeExtension(data ?? this.data);

  @override
  SakuraThemeExtension lerp(SakuraThemeExtension? other, double t) {
    if (other == null) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    // Interpolate every channel so animated theme swaps glide instead
    // of popping. `id/name/label/preview` follow the target discretely.
    AppThemeData lerpData(AppThemeData a, AppThemeData b) => AppThemeData(
          id: t < 0.5 ? a.id : b.id,
          name: t < 0.5 ? a.name : b.name,
          label: t < 0.5 ? a.label : b.label,
          preview: t < 0.5 ? a.preview : b.preview,
          background: lerpColor(a.background, b.background),
          surface: lerpColor(a.surface, b.surface),
          surfacePink: lerpColor(a.surfacePink, b.surfacePink),
          cardBorder: lerpColor(a.cardBorder, b.cardBorder),
          ink: lerpColor(a.ink, b.ink),
          inkSoft: lerpColor(a.inkSoft, b.inkSoft),
          inkFaint: lerpColor(a.inkFaint, b.inkFaint),
          primary: lerpColor(a.primary, b.primary),
          primaryDark: lerpColor(a.primaryDark, b.primaryDark),
          primarySoft: lerpColor(a.primarySoft, b.primarySoft),
          tagBg: lerpColor(a.tagBg, b.tagBg),
          tagText: lerpColor(a.tagText, b.tagText),
          heat0: lerpColor(a.heat0, b.heat0),
          heat1: lerpColor(a.heat1, b.heat1),
          heat2: lerpColor(a.heat2, b.heat2),
          heat3: lerpColor(a.heat3, b.heat3),
          heat4: lerpColor(a.heat4, b.heat4),
          heatPeak: lerpColor(a.heatPeak, b.heatPeak),
          navActive: lerpColor(a.navActive, b.navActive),
          navInactive: lerpColor(a.navInactive, b.navInactive),
          isDark: t < 0.5 ? a.isDark : b.isDark,
        );
    return SakuraThemeExtension(lerpData(data, other.data));
  }
}
