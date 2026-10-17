import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/focus_controller.dart';
import '../screens/focus_timer_screen.dart';
import '../theme/sakura_theme.dart';
import 'motion.dart';

/// Persistent countdown bar above the bottom nav. Visible on every tab
/// while a session runs — the timer survives navigation because
/// [FocusController] is app-wide, not per-screen.
class FocusMiniPlayer extends StatelessWidget {
  const FocusMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FocusController.instance,
      builder: (context, _) {
        final fc = FocusController.instance;
        final note = fc.notice;
        if (note != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Another frame may have consumed it first (ticks rebuild
            // every second) — show exactly once.
            if (FocusController.instance.notice == null) return;
            FocusController.instance.consumeNotice();
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(note)));
          });
        }
        if (!fc.active) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            SakuraPageRoute(
                builder: (_) => const FocusTimerScreen()),
          ),
          child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SakuraColors.primary,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: SakuraColors.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.timer,
                  size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fc.task?.title ?? 'Focusing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    // Per-second digits: listens to the tick notifier
                    // alone, so the row/title/icons rebuild only on
                    // structural changes (start/pause/finish), not every
                    // second.
                    ValueListenableBuilder<int>(
                      valueListenable: FocusController.instance.tickListenable,
                      builder: (context, _, __) => Text(
                        '${formatCountdown(fc.remaining)} · ${fc.mode}${fc.paused ? ' · paused' : ''}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () =>
                    fc.paused ? fc.resume() : fc.pause(),
                child: Semantics(
                  button: true,
                  label: fc.paused ? 'Resume session' : 'Pause session',
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                        fc.paused
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        size: 22,
                        color: Colors.white),
                  ),
                ),
              ),
              GestureDetector(
                onTap: fc.busy ? null : () => fc.finish(),
                child: Semantics(
                  button: true,
                  label: 'Finish session',
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.check_circle_outline,
                        size: 22, color: Colors.white),
                  ),
                ),
              ),
              GestureDetector(
                onTap: fc.busy ? null : () => fc.abandon(),
                child: Semantics(
                  button: true,
                  label: 'Abandon session',
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.cancel_outlined,
                        size: 20, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
