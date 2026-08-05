import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../features/settings/settings_screen.dart';
import 'message_view.dart';

/// Turns an error into a friendly message. When the API key is missing it
/// offers a shortcut into Settings.
class ApiErrorView extends StatelessWidget {
  const ApiErrorView({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final apiError = error is ApiException ? error as ApiException : null;
    final isMissingKey = apiError?.isMissingKey ?? false;

    return MessageView(
      icon: isMissingKey ? Icons.key_off : Icons.error_outline,
      text: apiError?.message ?? 'Something went wrong.',
      action: isMissingKey
          ? FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            )
          : null,
    );
  }
}
