import 'dart:async';

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter/material.dart';

const _maxReleaseNotesLength = 300;

/// Checks for a newer release and prompts only when one is available.
///
/// The release checker handles network and API failures as result values. The
/// context may be disposed while the check is running, so it is checked before
/// displaying any UI.
Future<void> maybeShowUpdateDialog(
  BuildContext context, {
  required ReleaseChecker checker,
  required Future<void> Function(UpdateInfo info) onUpdate,
}) async {
  final result = await checker.check();
  if (!context.mounted) return;

  switch (result) {
    case UpdateAvailable(:final info):
      final releaseNotes = info.releaseNotes?.trim();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version ${info.latestVersion} is available '
                '(you have ${info.currentVersion}).',
              ),
              if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _truncateReleaseNotes(releaseNotes),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(onUpdate(info));
              },
              child: const Text('Update now'),
            ),
          ],
        ),
      );
    case UpToDate():
    case CheckSkipped():
    case CheckError():
      return;
  }
}

String _truncateReleaseNotes(String notes) {
  if (notes.length <= _maxReleaseNotesLength) return notes;
  return '${notes.substring(0, _maxReleaseNotesLength).trimRight()}…';
}
