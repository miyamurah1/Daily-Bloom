import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/habit_store.dart';
import '../data/mock_data.dart';
import '../data/weekly_review.dart';
import '../theme/sakura_theme.dart';
import '../widgets/share_card.dart';

/// Weekly review: Mon–Sun numbers with one honest verdict.
///
/// Built client-side from the same endpoints as History + Insights
/// (done tasks, `/api/insights`, local habit logs) — no new API.
/// Offline shows an honest empty card, never last week's numbers as
/// if they were fresh.
class ReviewScreen extends StatefulWidget {
  /// True when hosted inside a shell hub tab: suppresses the back
  /// chevron (it would otherwise pop the whole shell route).
  final bool embedded;

  const ReviewScreen({super.key, this.embedded = false});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _api = BloomApi();
  WeeklyReview? _data;
  bool _loading = true;
  bool _offline = false;

  bool get _shareable {
    final d = _data;
    return !_loading && !_offline && d != null && !d.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.fetchTasks(status: 'done', withDetails: false),
        _api.fetchInsights(),
      ]);
      if (!mounted) return;
      setState(() {
        _data = buildWeeklyReview(
          done: results[0] as List<Task>,
          ins: results[1] as Insights,
          habits: HabitStore.instance.habits,
        );
        _loading = false;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      setState(() {
        _data = null;
        _loading = false;
        _offline = true;
      });
    }
  }

  Future<void> _sharePreview() async {
    final data = _data;
    if (data == null || data.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _SharePreview(data: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: SakuraColors.background,
      appBar: AppBar(
        backgroundColor: SakuraColors.background,
        elevation: 0,
        leading: widget.embedded
            ? null
            : GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Semantics(
            button: true,
            label: 'Back',
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SakuraColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: SakuraColors.cardBorder),
              ),
              child: Icon(LucideIcons.arrowLeft,
                  size: 18, color: SakuraColors.ink),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '週',
              style: TextStyle(
                fontSize: 22,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: SakuraColors.primary,
                letterSpacing: 3.2,
              ),
            ),
            Text(
              'WEEKLY REVIEW · ${reviewWeekLabel().toUpperCase()}',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3.2,
                fontWeight: FontWeight.w600,
                color: SakuraColors.inkFaint,
              ),
            ),
          ],
        ),
        actions: [
          if (_shareable)
            GestureDetector(
              onTap: _sharePreview,
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin:
                    const EdgeInsets.only(right: 20, top: 12, bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: SakuraColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: SakuraColors.cardBorder),
                ),
                child: Icon(LucideIcons.share2,
                    size: 14, color: SakuraColors.primary),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (_offline)
                    _OfflineCard(onRetry: _load)
                  else if (data == null)
                    const _EmptyCard(
                      title: 'Nothing to review',
                      body:
                          'Could not load this week. Pull to retry.',
                    )
                  else if (data.isEmpty)
                    _EmptyCard(
                      title: 'A quiet week',
                      body: data.verdict,
                    )
                  else ...[
                    _VerdictCard(text: data.verdict),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _Stat(
                                label: 'DONE',
                                value: '${data.doneCount}')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _Stat(
                                label: 'FOCUS',
                                value: '${data.focusMinutes}m')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _Stat(
                                label: 'ACTIVE DAYS',
                                value: '${data.activeDays}')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StandoutsCard(data: data),
                    const SizedBox(height: 12),
                    _StreakCard(data: data),
                  ],
                ],
              ),
            ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final String text;
  const _VerdictCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THE VERDICT',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
              color: SakuraColors.inkFaint,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              height: 1.55,
              fontWeight: FontWeight.w600,
              color: SakuraColors.ink,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _StandoutsCard extends StatelessWidget {
  final WeeklyReview data;
  const _StandoutsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (data.bestDay != null && data.bestDayCount >= 2) {
      rows.add(_row(LucideIcons.flame, 'Best day',
          '${data.bestDay} · ${data.bestDayCount} done'));
    }
    if (data.topTag != null) {
      rows.add(_row(LucideIcons.tag, 'Top tag',
          '${data.topTag} · ${(100 * data.topTagRate).round()}%'));
    }
    if (data.habitsTotal > 0) {
      rows.add(_row(
          LucideIcons.sprout,
          'Habits',
          data.habitsKept == data.habitsTotal
              ? 'Every habit kept (${data.habitsTotal})'
              : '${data.habitsKept} of ${data.habitsTotal} kept'));
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STANDOUTS',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
              color: SakuraColors.inkFaint,
            ),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text('Nothing stood out yet.',
                style: TextStyle(color: SakuraColors.inkSoft))
          else
            ...rows,
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: SakuraColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13, color: SakuraColors.inkSoft)),
          ),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SakuraColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final WeeklyReview data;
  const _StreakCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SakuraTheme.cardDecoration(),
      child: Row(
        children: [
          Icon(LucideIcons.flame, size: 16, color: SakuraColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data.streakCurrent > 0
                  ? '${data.streakCurrent}-day streak · best ${data.streakBest} (30d)'
                  : data.streakBest > 1
                      ? 'Streak paused · best ${data.streakBest} (30d)'
                      : 'No streak yet — today is day one.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: SakuraColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String body;
  const _EmptyCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SakuraColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.calendarDays,
                size: 22, color: SakuraColors.primary),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SakuraColors.ink)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, height: 1.55, color: SakuraColors.inkSoft)),
        ],
      ),
    );
  }
}

class _OfflineCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _OfflineCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SakuraColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.cloudOff,
                size: 22, color: SakuraColors.primary),
          ),
          const SizedBox(height: 12),
          Text("You're offline",
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SakuraColors.ink)),
          const SizedBox(height: 6),
          Text('Connect to review your week — numbers stay on the server.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, height: 1.55, color: SakuraColors.inkSoft)),
        ],
      ),
    );
  }
}

/// Plain-text fallback for the share card (web, or image capture
/// unavailable). Same numbers, no pixels.
String shareTextFor(WeeklyReview r) {
  final bits = <String>[
    '${r.doneCount} done',
    '${r.focusMinutes} min focused',
    '${r.activeDays} active days',
  ];
  var out =
      'My week in bloom (${reviewWeekLabel(r.weekStart)}): ${bits.join(' · ')}.';
  if (r.streakCurrent > 0) out += ' ${r.streakCurrent}-day streak.';
  return out;
}

/// WYSIWYG preview: the card in a repaint boundary plus Share / Copy.
/// Capture happens in-dialog (the boundary dies with it); every
/// platform failure degrades to copying the text summary.
class _SharePreview extends StatefulWidget {
  final WeeklyReview data;
  const _SharePreview({required this.data});

  @override
  State<_SharePreview> createState() => _SharePreviewState();
}

class _SharePreviewState extends State<_SharePreview> {
  final _boundary = GlobalKey();
  bool _busy = false;

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ro =
          _boundary.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) throw StateError('no card');
      final image = await ro.toImage(
          pixelRatio: ShareCard.capturePixelRatio);
      final bytes = await image.toByteData(
          format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('no pixels');
      if (kIsWeb) throw UnsupportedError('web has no files');
      final file = await File(
              '${Directory.systemTemp.path}/bloom-week.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: shareTextFor(widget.data),
        ),
      );
    } catch (_) {
      await _copyText();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyText() async {
    try {
      await Clipboard.setData(
          ClipboardData(text: shareTextFor(widget.data)));
    } catch (_) {
      // Clipboard unavailable (some test harnesses) — nothing to do.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Week copied as text.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: _boundary,
            child: ShareCard(review: widget.data),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: SakuraColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _shareImage,
              icon: _busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(LucideIcons.share2, size: 16),
              label: Text(_busy ? 'Preparing…' : 'Share image',
                  style:
                      const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _copyText,
            child: Text('Copy as text instead',
                style: TextStyle(
                    fontSize: 12.5,
                    color: SakuraColors.inkSoft)),
          ),
        ],
      ),
    );
  }
}
