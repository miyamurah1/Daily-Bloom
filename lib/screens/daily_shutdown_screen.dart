import 'package:flutter/material.dart';

/// Evening shutdown ritual: gives the user permission to stop working.
///
/// Shows when the user has completed their planned items for the day.
/// The screen dims to a twilight palette and the FAB is locked with a
/// gentle override for emergencies.
class DailyShutdownScreen extends StatelessWidget {
  final VoidCallback? onOverride;

  const DailyShutdownScreen({super.key, this.onOverride});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.nightlight_round, size: 64, color: Colors.amber),
              const SizedBox(height: 24),
              const Text(
                'Your work is done.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Close the app and be present with your evening.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'The garden rests until morning.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white54,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 48),
              if (onOverride != null)
                TextButton(
                  onPressed: onOverride,
                  child: const Text(
                    'Override (emergency)',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
