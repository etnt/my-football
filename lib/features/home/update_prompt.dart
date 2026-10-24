import 'dart:async';

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _maxReleaseNotesLength = 300;

/// Opens the release page URL in an external browser.
///
/// The URL is guarded: it must parse successfully and use the secure `https`
/// scheme, otherwise the launcher is never called. Any launcher exception is
/// swallowed so a failed browser launch can never interrupt the app.
Future<void> launchReleasePageUrl(
  UpdateInfo info, {
  Future<bool> Function(Uri uri, {LaunchMode mode})? launcher,
}) async {
  final uri = Uri.tryParse(info.releasePageUrl);
  if (uri == null || uri.scheme != 'https') return;

  try {
    await (launcher ?? launchUrl)(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // A failed browser launch must not interrupt the app.
  }
}

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
  // Strip common GitHub Markdown syntax (headings, emphasis, inline code,
  // links and list markers) before truncating the dialog text.
  final String stripped = _stripMarkdown(notes);

  // Use code points (runes) instead of UTF-16 code units to prevent emojis or
  // other surrogate pairs from being split in half at the cut point.
  final runes = stripped.runes;
  if (runes.length <= _maxReleaseNotesLength) return stripped;

  return '${String.fromCharCodes(runes.take(_maxReleaseNotesLength)).trimRight()}…';
}

/// Removes common GitHub Markdown syntax from the given text.
String _stripMarkdown(String notes) {
  String result = notes;

  // Link syntax: [text](url) -> text
  result = result.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );

  // Heading markers: remove leading # symbols at the start of a line.
  result = result.replaceAllMapped(
    RegExp(r'(^|\n)[ \t]*#+[ \t]+'),
    (match) => match.group(1) ?? '',
  );

  // List markers: remove leading -, *, or + at the start of a line. This must
  // run before the italic-marker removal so `* item` keeps its indentation.
  result = result.replaceAllMapped(
    RegExp(r'(^|\n)[ \t]*[-*+][ \t]+'),
    (match) => match.group(1) ?? '',
  );

  // Bold and italic markers.
  result = result.replaceAll(RegExp(r'\*\*'), '');
  result = result.replaceAll(RegExp(r'__'), '');
  result = result.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');

  // Inline code backticks.
  result = result.replaceAll(RegExp(r'`'), '');

  return result;
}
