import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';

/// Compact, animated inline error for auth screens.
///
/// Replaces the old full-width red paragraph: short user-facing copy, a
/// warning icon, and an optional retry action that sits beside the message
/// instead of adding another row of centred text.
class AuthErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AuthErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final reduce = AppMotion.reduced(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduce ? Duration.zero : AppMotion.toggle,
      curve: AppMotion.toggleCurve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: child,
        ),
      ),
      child: Container(
        key: const ValueKey('auth-error'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: error.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: error.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(LucideIcons.circleAlert, size: 15, color: error),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: SakuraColors.ink,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 4),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: error,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  retryLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
