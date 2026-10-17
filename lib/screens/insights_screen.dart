import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ai_client.dart';
import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../theme/sakura_theme.dart';

/// Phase D — personal feedback. Numbers from `/api/insights` turned
/// into plain-language patterns by [buildInsights] (rule-based, no ML).
class InsightsScreen extends StatefulWidget {
  /// True when hosted inside a shell hub tab: suppresses the back
  /// chevron (it would otherwise pop the whole shell route).
  final bool embedded;

  const InsightsScreen({super.key, this.embedded = false});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _api = BloomApi();
  Insights? _data;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchInsights();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      // Trust rule: the card below IS the message — no snackbar spam.
      setState(() {
        _data = null;
        _loading = false;
        _offline = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final tips = data == null ? <String>[] : buildInsights(data);
    final maxFocus = data == null || data.focusDays.isEmpty
        ? 1
        : data.focusDays
            .map((d) => d.minutes)
            .reduce((a, b) => a > b ? a : b)
            .clamp(1, 1 << 30);

    return Scaffold(
      backgroundColor: SakuraColors.background,
      appBar: AppBar(
        backgroundColor: SakuraColors.background,
        elevation: 0,
        leading: widget.embedded
            ? null
            : GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分析',
              style: SakuraTheme.display(
                fontSize: 22,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: SakuraColors.primary,
                letterSpacing: 3.2,
              ),
            ),
            Text(
              'INSIGHTS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3.2,
                fontWeight: FontWeight.w600,
                color: SakuraColors.inkFaint,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _offline
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration:
                            SakuraTheme.cardDecoration(),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: SakuraColors.primary
                                    .withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(LucideIcons.cloudOff,
                                  size: 22,
                                  color: SakuraColors.primary),
                            ),
                            const SizedBox(height: 12),
                            Text("You're offline",
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: SakuraColors.ink)),
                            const SizedBox(height: 6),
                            Text(
                                'Connect to load your patterns — they stay on the server.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.55,
                                    color: SakuraColors.inkSoft)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : data == null
              ? Center(
                  child: Text('Could not load insights.',
                      style:
                          TextStyle(color: SakuraColors.inkSoft)),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding:
                        const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: _Stat(
                                  label: 'FOCUS 7D',
                                  value:
                                      '${data.focusMinutes7}m')),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _Stat(
                                  label: 'STREAK',
                                  value:
                                      '${data.streakCurrent}d')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _NarrativeCard(
                        tips: tips,
                        done: data.byTag.fold<int>(
                            0, (a, s) => a + s.done),
                        streak: data.streakCurrent,
                        focusMinutes: data.focusMinutes7,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration:
                            SakuraTheme.cardDecoration(),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'YOUR PATTERNS',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 2.2,
                                fontWeight: FontWeight.w600,
                                color: SakuraColors.inkFaint,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...tips.map(
                              (t) => Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 10),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                        LucideIcons.sparkles,
                                        size: 13,
                                        color:
                                            SakuraColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        t,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          height: 1.45,
                                          color: SakuraColors.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration:
                            SakuraTheme.cardDecoration(),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'COMPLETION BY TAG',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 2.2,
                                fontWeight: FontWeight.w600,
                                color: SakuraColors.inkFaint,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (data.byTag.isEmpty)
                              Text(
                                  'No tags yet.',
                                  style: TextStyle(
                                      color: SakuraColors
                                          .inkSoft))
                            else
                              ...data.byTag.map(
                                (s) => Padding(
                                  padding:
                                      const EdgeInsets.only(
                                          bottom: 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              s.name,
                                              style:
                                                  TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight
                                                        .w600,
                                                color: SakuraColors
                                                    .ink,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${s.done}/${s.total} · ${(100 * s.rate).round()}%',
                                            style:
                                                TextStyle(
                                              fontSize: 11,
                                              color: SakuraColors
                                                  .inkSoft,
                                              fontFeatures: const [
                                                FontFeature
                                                    .tabularFigures()
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(
                                                5),
                                        child:
                                            LinearProgressIndicator(
                                          value: s.rate,
                                          minHeight: 6,
                                          backgroundColor:
                                              SakuraColors
                                                  .primarySoft,
                                          valueColor:
                                              AlwaysStoppedAnimation<
                                                      Color>(
                                                  SakuraColors
                                                      .primary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration:
                            SakuraTheme.cardDecoration(),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FOCUS THIS WEEK (MIN)',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 2.2,
                                fontWeight: FontWeight.w600,
                                color: SakuraColors.inkFaint,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (data.focusDays.isEmpty)
                              Text(
                                  'No sessions yet.',
                                  style: TextStyle(
                                      color: SakuraColors
                                          .inkSoft))
                            else
                              SizedBox(
                                height: 110,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: data.focusDays.map(
                                    (d) {
                                      final h =
                                          8 + 84 * (d.minutes / maxFocus);
                                      return Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${d.minutes}',
                                              style:
                                                  TextStyle(
                                                fontSize: 10,
                                                color: SakuraColors
                                                    .inkSoft,
                                                fontFeatures: const [
                                                  FontFeature
                                                      .tabularFigures()
                                                ],
                                              ),
                                            ),
                                            const SizedBox(
                                                height: 4),
                                            Container(
                                              height: h,
                                              margin:
                                                  const EdgeInsets
                                                      .symmetric(
                                                      horizontal:
                                                          4),
                                              decoration:
                                                  BoxDecoration(
                                                color: d.minutes ==
                                                        0
                                                    ? SakuraColors
                                                        .heat0
                                                    : SakuraColors
                                                        .primary,
                                                borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                            6),
                                              ),
                                            ),
                                            const SizedBox(
                                                height: 4),
                                            Text(
                                              d.date.substring(5),
                                              style:
                                                  TextStyle(
                                                fontSize: 8,
                                                color: SakuraColors
                                                    .inkFaint,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ).toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
              color: SakuraColors.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: SakuraColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Week's story: 2-3 sentence Bloom-tone narrative over the stats.
/// Server upgrades prose (Flash-Lite); offline uses the local template.
/// Cached per calendar week so it costs at most one call a week.
class _NarrativeCard extends StatefulWidget {
  final List<String> tips;
  final int done;
  final int streak;
  final int focusMinutes;

  const _NarrativeCard({
    required this.tips,
    required this.done,
    required this.streak,
    required this.focusMinutes,
  });

  @override
  State<_NarrativeCard> createState() => _NarrativeCardState();
}

class _NarrativeCardState extends State<_NarrativeCard> {
  String? _text;
  bool _loading = true;

  static String _weekKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final dayOfYear = d.difference(DateTime(d.year)).inDays + 1;
    final week = (dayOfYear / 7).ceil();
    return 'ai_narrative_${d.year}W$week';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _weekKey();
      if (!refresh) {
        final cached = prefs.getString(key);
        if (cached != null && cached.isNotEmpty) {
          if (mounted) setState(() => _text = cached);
        }
      }
      if (mounted && (_text == null || refresh)) {
        final text = await AiClient().narrative(
          widget.tips,
          done: widget.done,
          streak: widget.streak,
          focusMinutes: widget.focusMinutes,
        );
        await prefs.setString(key, text);
        if (mounted) setState(() => _text = text);
      }
    } catch (_) {
      if (mounted && _text == null) {
        setState(() => _text = narrativeLocal(widget.tips,
            done: widget.done,
            streak: widget.streak,
            focusMinutes: widget.focusMinutes));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "WEEK'S STORY",
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w600,
                  color: SakuraColors.inkFaint,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _loading ? null : () => _load(refresh: true),
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  button: true,
                  label: 'Refresh insights',
                  child: Icon(
                    LucideIcons.refreshCw,
                    size: 13,
                    color: SakuraColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading && _text == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SakuraColors.primary,
                  ),
                ),
              ),
            )
          else
            Text(
              _text ?? '',
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: SakuraColors.ink,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'told by Bloom',
            style: TextStyle(
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
              color: SakuraColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
