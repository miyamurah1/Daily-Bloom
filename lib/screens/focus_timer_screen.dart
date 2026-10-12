import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/ambient_sound.dart';
import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/focus_controller.dart';
import '../data/focus_quotes.dart';
import '../data/mock_data.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';

/// Full-screen digital timer — black stage, orange seven-seg style digits,
/// − / + / fullscreen icons top-right, green Set Timer button.
///
/// Source of truth stays [FocusController] (lib/data/focus_controller.dart:24);
/// this screen is a view over it: idle shows the preset, running shows the
/// live countdown. Tapping anywhere appropriate never duplicates server rows.
class FocusTimerScreen extends StatefulWidget {
  final Task? task;

  /// Shared-element tag matching the source timer chip
  /// (`home-focus-<id>` etc.). Null = plain push, no flight.
  final String? heroTag;
  const FocusTimerScreen({super.key, this.task, this.heroTag});

  @override
  State<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends State<FocusTimerScreen> {
  static const _green = Color(0xFF3CB86B);

  int _presetMin = 25;
  String _mode = 'focus';
  bool _immersive = false;
  List<Subtask> _subs = [];
  String? _selectedSubId;
  FocusHistory? _history;
  late String _quote;
  bool _ambientOn = false;

  Task? get _task => widget.task ?? FocusController.instance.task;

  Subtask? get _selectedSub {
    for (final s in _subs) {
      if (s.id == _selectedSubId) return s;
    }
    return null;
  }

  /// Tap the zen line → a fresh API quote. Guarded against overlap;
  /// offline simply falls back to a local line.
  bool _quoteBusy = false;

  Future<void> _shuffleQuote() async {
    if (_quoteBusy) return;
    setState(() => _quoteBusy = true);
    final fresh = await fetchRandomQuote(notEqualTo: _quote);
    if (!mounted) return;
    setState(() {
      _quote = fresh;
      _quoteBusy = false;
    });
  }

  static String _shortSub(String s) =>
      s.length <= 28 ? s : '${s.substring(0, 27)}…';

  @override
  void initState() {
    super.initState();
    // One quote per day per mode — stable all day, fresh tomorrow.
    _quote = focusQuoteFor(DateTime.now(), _mode);
    _loadContext();
    AmbientSound.load().then((_) {
      if (mounted) setState(() => _ambientOn = AmbientSound.enabled);
    });
  }

  Future<void> _toggleAmbient() async {
    final next = !_ambientOn;
    await AmbientSound.setEnabled(next);
    if (!mounted) return;
    setState(() => _ambientOn = next);
    // If a session runs, the wash follows immediately.
    final fc = FocusController.instance;
    if (fc.active && !fc.paused && next) {
      await AmbientSound.sync(playing: true);
    }
  }

  /// Subtasks to focus on + session totals for the reward streak.
  Future<void> _loadContext() async {
    final task = widget.task ?? FocusController.instance.task;
    if (task == null) return;
    try {
      final results = await Future.wait([
        BloomApi().fetchSubtasks(task.id),
        BloomApi().fetchTaskFocus(task.id),
      ]);
      if (!mounted) return;
      setState(() {
        _subs = (results[0] as List<Subtask>)
            .where((s) => !s.done)
            .toList();
        _history = results[1] as FocusHistory;
      });
    } catch (_) {
      // Offline: chips and streak simply stay hidden.
    }
  }

  @override
  void dispose() {
    if (_immersive) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    SystemChrome.setEnabledSystemUIMode(
      _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// − / + : idle adjusts the preset in 5-min steps; running nudges the
  /// live countdown by 1 min (standard timer-app behavior).
  void _step(int dir) {
    final fc = FocusController.instance;
    if (!fc.active) {
      setState(() => _presetMin = (_presetMin + dir * 5).clamp(5, 180));
      return;
    }
    fc.adjustTime(Duration(minutes: dir));
  }

  Future<void> _setTimer() async {
    final task = _task;
    try {
      final sub = task == null ? null : _selectedSub;
      await FocusController.instance.start(
        task: task,
        minutes: _presetMin,
        mode: _mode,
        subtaskTitle: _mode == 'focus' ? sub?.title : null,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AuthException
              ? e.message
              : 'Could not start timer: $e')));
    }
  }

  Future<void> _pickDuration() async {
    if (FocusController.instance.active) return;
    const options = [5, 10, 15, 25, 50];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Duration',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: options
                  .map((m) => ChoiceChip(
                        label: Text('$m min'),
                        selected: _presetMin == m,
                        selectedColor: SakuraColors.primary,
                        onSelected: (_) {
                          Navigator.of(ctx).pop(m);
                        },
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _presetMin = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListenableBuilder(
          // Structural changes only (start/pause/finish/adjust). The
          // per-second tick is scoped to the digit label below, so the
          // top bar, history row, chips and buttons don't rebuild every
          // second while a session runs.
          listenable: FocusController.instance,
          builder: (context, _) {
            final fc = FocusController.instance;
            return Column(
              children: [
                // Top bar: back + task mode on the left, − / + / expand right.
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Tooltip(
                          message: 'Back',
                          child: Icon(LucideIcons.arrowLeft,
                              color: Colors.white70),
                        ),
                        onPressed: () =>
                            Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _mode == 'focus'
                                  ? 'FOCUS SESSION'
                                  : 'BREAK',
                              style: TextStyle(
                                  color: SakuraColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.2),
                            ),
                            if (_task != null)
                              widget.heroTag == null
                                  ? Text(
                                      _task!.title,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 13),
                                    )
                                  : Hero(
                                      tag: widget.heroTag!,
                                      flightShuttleBuilder: (
                                        flightContext,
                                        animation,
                                        direction,
                                        fromContext,
                                        toContext,
                                      ) {
                                        final eased =
                                            CurvedAnimation(
                                          parent: animation,
                                          curve: AppMotion
                                              .heroCurve,
                                        );
                                        return FadeTransition(
                                          opacity: eased,
                                          child: ScaleTransition(
                                            scale: eased,
                                            child: (direction ==
                                                    HeroFlightDirection
                                                        .push
                                                ? toContext.widget
                                                : fromContext
                                                    .widget),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        _task!.title,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 13),
                                      ),
                                    )
                            else
                              const Text(
                                'Free Deep Work — no task attached',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13),
                              ),
                          ],
                        ),
                      ),
                      _topIcon(LucideIcons.minus,
                          () => _step(-1)),
                      const SizedBox(width: 10),
                      _topIcon(LucideIcons.plus,
                          () => _step(1)),
                      const SizedBox(width: 10),
                      _topIcon(
                          _immersive
                              ? LucideIcons.minimize2
                              : LucideIcons.maximize2,
                          _toggleImmersive),
                    ],
                  ),
                ),
                // Reward streak: finished sessions on this task.
                if (_history != null &&
                    _history!.completedCount > 0)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Row(
                      children: [
                        Icon(LucideIcons.flame,
                            size: 14,
                            color: SakuraColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          '${_history!.completedCount} sessions · ${_history!.totalMinutes} min earned',
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              letterSpacing: 1.6),
                        ),
                      ],
                    ),
                  ),
                // Which subtask is this session for?
                if (!fc.active && _subs.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 10, 0, 0),
                    child: SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _subs.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                        itemBuilder: (ctx, i) {
                          final s = _subs[i];
                          final sel =
                              _selectedSubId == s.id;
                          return GestureDetector(
                            onTap: () => setState(() =>
                                _selectedSubId =
                                    sel ? null : s.id),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8),
                              decoration: BoxDecoration(
                                color: sel
                                    ? SakuraColors.primary
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(17),
                                border: Border.all(
                                    color: sel
                                        ? SakuraColors.primary
                                        : Colors.white24),
                              ),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(
                                        maxWidth: 160),
                                child: Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: sel
                                          ? Colors.black
                                          : Colors.white60,
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.w600),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (fc.active && fc.subtaskTitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'ON "${_shortSub(fc.subtaskTitle!)}"',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 1.6),
                    ),
                  ),
                // Ambient wash: opt-in rain loop under the session.
                // Silent by default — a focus screen never starts audio
                // uninvited.
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: GestureDetector(
                    onTap: _toggleAmbient,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _ambientOn
                              ? LucideIcons.cloudRain
                              : LucideIcons.cloud,
                          size: 13,
                          color: _ambientOn
                              ? SakuraColors.primary
                              : Colors.white38,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _ambientOn ? 'RAIN ON' : 'RAIN OFF',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w700,
                            color: _ambientOn
                                ? SakuraColors.primary
                                : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                // Digits — clean mono face, soft glow, tap for presets.
                // Scoped tick: only this label rebuilds each second.
                ValueListenableBuilder<int>(
                  valueListenable: FocusController.instance.tickListenable,
                  builder: (context, _, __) {
                    final digits = fc.active
                        ? formatCountdown(fc.remaining)
                        : '${_presetMin.toString().padLeft(2, '0')}:00';
                    return GestureDetector(
                      onTap: _pickDuration,
                      child: Text(
                        digits,
                        style: GoogleFonts.shareTechMono(
                          fontSize:
                              MediaQuery.of(context).size.width * 0.19,
                          height: 1.0,
                          letterSpacing: 3.2,
                          color: SakuraColors.primary,
                          shadows: [
                            Shadow(
                                color: SakuraColors.primary
                                    .withValues(alpha: 0.2),
                                blurRadius: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  fc.active ? 'REMAINING' : 'TAP TIME TO CHANGE',
                  style: const TextStyle(
                      color: Colors.white30,
                      fontSize: 10,
                      letterSpacing: 3.2),
                ),
                const SizedBox(height: 10),
                // Focus / break toggle (idle only).
                if (!fc.active)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _modeChip('focus'),
                      const SizedBox(width: 10),
                      _modeChip('break'),
                    ],
                  )
                else
                  Text(
                    fc.paused ? 'PAUSED' : 'IN SESSION',
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 3.2),
                  ),
                const Spacer(flex: 2),
                // Primary green button: Set Timer idle, Pause/Resume live.
                if (!fc.active)
                  SizedBox(
                    width: 190,
                    height: 52,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5),
                      ),
                      onPressed:
                          fc.busy ? null : _setTimer,
                      child: fc.busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Text('Set Timer'),
                    ),
                  )
                else ...[
                  SizedBox(
                    width: 190,
                    height: 52,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5),
                      ),
                      onPressed: () => fc.paused
                          ? fc.resume()
                          : fc.pause(),
                      child: Text(
                          fc.paused ? 'Resume' : 'Pause'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: fc.busy
                            ? null
                            : () => fc.finish(),
                        icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: Colors.white70),
                        label: const Text('Finish',
                            style: TextStyle(
                                color: Colors.white70)),
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        onPressed: fc.busy
                            ? null
                            : () => fc.abandon(),
                        icon: const Icon(
                            Icons.cancel_outlined,
                            size: 18,
                            color: Colors.white38),
                        label: const Text('Abandon',
                            style: TextStyle(
                                color: Colors.white38)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // Daily zen line — tap for a fresh one. Quiet motivation
                // pinned to the bottom; API quote or local fallback.
                GestureDetector(
                  onTap: _shuffleQuote,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: AppMotion.toggle,
                          switchInCurve: AppMotion.toggleCurve,
                          switchOutCurve: AppMotion.toggleCurve,
                          child: Text(
                            '“$_quote”',
                            key: ValueKey<String>(
                                '$_mode-$_quote'),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                              height: 1.6,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _quoteBusy
                                  ? Icons.hourglass_empty
                                  : Icons.refresh_rounded,
                              size: 11,
                              color: Colors.white24,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'tap for another line',
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 10,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 3),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 1.2),
        ),
        child: Icon(icon, size: 19, color: Colors.white70),
      ),
    );
  }

  Widget _modeChip(String value) {
    final selected = _mode == value;
    return GestureDetector(
      onTap: () => setState(() {
        _mode = value;
        _quote = focusQuoteFor(DateTime.now(), value);
      }),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? SakuraColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? SakuraColors.primary : Colors.white24),
        ),
        child: Text(
          value == 'focus' ? 'Focus' : 'Break',
          style: TextStyle(
              color: selected ? Colors.black : Colors.white54,
              fontWeight: FontWeight.w700,
              fontSize: 13),
        ),
      ),
    );
  }
}
