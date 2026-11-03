import 'package:flutter/material.dart';

import 'package:lucide_flutter/lucide_flutter.dart';
import '../theme/sakura_theme.dart';

/// Consistent empty state used across screens (no tasks, no results, no
/// habits, no inbox). Matches the app's warm "sakura" aesthetic:
/// soft background card, muted ink, one soft primary accent, and an
/// optional tappable action.
class EmptyState extends StatelessWidget {
  /// Short, human title (e.g. 'Nothing here yet').
  final String title;

  /// One-line explanation of why the list is empty.
  final String subtitle;

  /// Optional action (e.g. 'New goal' button). If null, only informational.
  final Widget? action;

  /// When true, swaps ink→primary for light backgrounds.
  final bool invert;

  const EmptyState({
    super.key,
    required this.title,
    this.subtitle = '',
    this.action,
    this.invert = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = invert ? SakuraColors.primary : SakuraColors.ink;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Card(
          elevation: invert ? 0 : 1,
          clipBehavior: Clip.hardEdge,
          color: invert ? SakuraColors.primarySoft : SakuraColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: invert
                ? BorderSide.none
                : BorderSide(color: SakuraColors.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: invert
                        ? SakuraColors.primary
                        : SakuraColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.file,
                    size: 22,
                    color: invert
                        ? SakuraColors.primarySoft
                        : SakuraColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: SakuraColors.inkSoft,
                      height: 1.4,
                    ),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: 16),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
