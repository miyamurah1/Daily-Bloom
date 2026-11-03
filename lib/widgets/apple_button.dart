import 'package:flutter/material.dart';

import '../theme/sakura_theme.dart';

class AppleButton extends StatelessWidget {
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  const AppleButton({
    super.key,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: busy || disabled ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: SakuraColors.ink,
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: BorderSide(color: SakuraColors.cardBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Continue with Apple',
                style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
