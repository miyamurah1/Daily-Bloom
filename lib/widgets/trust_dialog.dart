import 'package:flutter/material.dart';

import '../theme/sakura_theme.dart';

Future<void> showTrustDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Text(
          body,
          style: TextStyle(color: SakuraColors.inkSoft, height: 1.55),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Close', style: TextStyle(color: SakuraColors.primary)),
        ),
      ],
    ),
  );
}

Future<void> showPrivacyPolicy(BuildContext context) => showTrustDialog(
      context,
      title: 'Privacy Policy',
      body:
          'Daily Bloom stores your tasks and account data to provide the service. '
          'Task content stays local unless you enable cloud sync or choose an '
          'AI feature. External AI requests are always opt-in and can be '
          'disabled in Settings. We do not sell task content or use it for '
          'advertising. You can export or delete your account from Settings.',
    );

Future<void> showTermsOfUse(BuildContext context) => showTrustDialog(
      context,
      title: 'Terms of Use',
      body:
          'Use Daily Bloom for personal organization. Keep your account secure '
          'and review important information before relying on reminders or '
          'automation. You may export your data and delete your account at any '
          'time from Settings.',
    );
