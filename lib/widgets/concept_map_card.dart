import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../theme/sakura_theme.dart';

/// One dismissible "welcome to your garden" card for first-run Home.
///
/// Three tiny steps, taught by doing — not five rows of reading.
/// Shown until dismissed (the caller persists that); never pops up
/// on its own after that.
class ConceptMapCard extends StatelessWidget {
  final VoidCallback onDismiss;

  const ConceptMapCard({super.key, required this.onDismiss});

  static const _steps = [
    (LucideIcons.sun, 'Set one intention', 'a single focus for today.'),
    (LucideIcons.timer, 'Focus for 25 minutes', 'one session, one task.'),
    (LucideIcons.flower2, 'Bloom it done', 'tap done, watch XP grow.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SakuraColors.primary.withValues(alpha: 0.10),
            SakuraColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SakuraColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: SakuraColors.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.sparkles,
                  size: 14,
                  color: SakuraColors.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Welcome to your garden',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: SakuraColors.ink,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  button: true,
                  label: 'Dismiss',
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.x,
                      size: 16,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Three tiny steps. Two minutes to your first bloom.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: SakuraColors.inkSoft,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                  bottom: i == _steps.length - 1 ? 0 : 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SakuraColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: SakuraColors.cardBorder),
                    ),
                    child: Icon(_steps[i].$1,
                        size: 14, color: SakuraColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${i + 1}. ${_steps[i].$2} — ',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                              color: SakuraColors.ink,
                            ),
                          ),
                          TextSpan(
                            text: _steps[i].$3,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: SakuraColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
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
