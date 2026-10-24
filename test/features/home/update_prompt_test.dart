import 'dart:async';

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/home/update_prompt.dart';
import 'package:url_launcher/url_launcher.dart';

class _FakeChecker extends ReleaseChecker {
  _FakeChecker(this.result)
    : super(owner: 'etnt', repo: 'my-football', currentVersion: '1.0.0');

  final UpdateCheckResult result;
  int calls = 0;

  @override
  Future<UpdateCheckResult> check() async {
    calls++;
    return result;
  }
}

const _updateInfo = UpdateInfo(
  latestVersion: '1.2.0',
  currentVersion: '1.0.0',
  releasePageUrl: 'https://github.com/etnt/my-football/releases/tag/v1.2.0',
  releaseNotes: 'Faster scores.',
);

Future<List<UpdateInfo>> _showPrompt(
  WidgetTester tester,
  _FakeChecker checker,
) async {
  final launched = <UpdateInfo>[];
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: const SizedBox.shrink())),
  );
  final context = tester.element(find.byType(Scaffold));
  unawaited(
    maybeShowUpdateDialog(
      context,
      checker: checker,
      onUpdate: (info) async => launched.add(info),
    ),
  );
  await tester.pumpAndSettle();
  return launched;
}

void main() {
  group('launchReleasePageUrl', () {
    UpdateInfo infoWith(String url) => UpdateInfo(
      latestVersion: '1.2.0',
      currentVersion: '1.0.0',
      releasePageUrl: url,
      releaseNotes: null,
    );

    test('does not launch a non-https URL', () async {
      var called = 0;
      Future<bool> launcher(
        Uri uri, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        called++;
        return true;
      }

      await launchReleasePageUrl(
        infoWith('http://github.com/etnt/my-football/releases/tag/v1.2.0'),
        launcher: launcher,
      );
      expect(called, 0);
    });

    test('launches an https URL with the external mode', () async {
      final uris = <Uri>[];
      final modes = <LaunchMode>[];
      Future<bool> launcher(
        Uri uri, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        uris.add(uri);
        modes.add(mode);
        return true;
      }

      await launchReleasePageUrl(
        infoWith('https://github.com/etnt/my-football/releases/tag/v1.2.0'),
        launcher: launcher,
      );
      expect(uris, [
        Uri.parse('https://github.com/etnt/my-football/releases/tag/v1.2.0'),
      ]);
      expect(modes, [LaunchMode.externalApplication]);
    });

    test('does not launch an unparseable URL', () async {
      var called = 0;
      Future<bool> launcher(
        Uri uri, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        called++;
        return true;
      }

      await launchReleasePageUrl(infoWith('::: not a url'), launcher: launcher);
      expect(called, 0);
    });

    test('swallows launcher exceptions', () async {
      Future<bool> launcher(
        Uri uri, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        throw Exception('no browser available');
      }

      // Must complete without throwing.
      await launchReleasePageUrl(
        infoWith('https://github.com/etnt/my-football/releases/tag/v1.2.0'),
        launcher: launcher,
      );
    });
  });

  group('release notes formatting', () {
    Future<String> shownNotes(WidgetTester tester, String notes) async {
      final checker = _FakeChecker(
        UpdateAvailable(
          UpdateInfo(
            latestVersion: '1.2.0',
            currentVersion: '1.0.0',
            releasePageUrl: _updateInfo.releasePageUrl,
            releaseNotes: notes,
          ),
        ),
      );
      await _showPrompt(tester, checker);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .where(
            (text) =>
                text != 'Update available' &&
                text != 'Later' &&
                text != 'Update now' &&
                !text.startsWith('Version '),
          )
          .toList();
      return texts.single;
    }

    testWidgets('strips common GitHub Markdown syntax', (tester) async {
      final shown = await shownNotes(
        tester,
        '# Heading\n'
        '**bold** and *italic* and `code`\n'
        '- item one\n'
        '* item two\n'
        'See [the release](https://example.com/release) for details.',
      );

      expect(
        shown,
        'Heading\nbold and italic and code\nitem one\nitem two\n'
        'See the release for details.',
      );
    });

    testWidgets('truncates by runes so emoji surrogate pairs are never split', (
      tester,
    ) async {
      // 299 ASCII runes, then an emoji (a surrogate pair), then filler. A
      // code-unit cut at 300 would leave a lone surrogate at the end.
      const emoji = '😀';
      final notes = '${'a' * 299}$emoji${'b' * 50}';
      final shown = await shownNotes(tester, notes);

      expect(shown, '${'a' * 299}$emoji…');
    });

    testWidgets('truncated text never ends in a lone surrogate', (
      tester,
    ) async {
      // Put the emoji right at the code-unit cut point (code unit 300).
      final notes = '${'a' * 299}😀${'b' * 50}';
      final shown = await shownNotes(tester, notes);

      // No unpaired surrogate code units in the truncated result.
      final runes = shown.runes.toList();
      for (final rune in runes) {
        final isSurrogate = rune >= 0xD800 && rune <= 0xDFFF;
        expect(
          isSurrogate,
          isFalse,
          reason: 'lone surrogate U+${rune.toRadixString(16)}',
        );
      }
      expect(shown.runes.length, lessThanOrEqualTo(301)); // 300 + ellipsis.
      expect(shown.endsWith('…'), isTrue);
    });

    testWidgets('notes within the limit are shown as-is', (tester) async {
      final shown = await shownNotes(tester, 'Short notes.');
      expect(shown, 'Short notes.');
    });

    testWidgets('keeps blank lines before headings and lists', (tester) async {
      final shown = await shownNotes(
        tester,
        'Intro\n\n## Changes\n\n- one\n- two',
      );

      expect(shown, 'Intro\n\nChanges\n\none\ntwo');
    });

    testWidgets('leaves text like "#1 priority" unchanged', (tester) async {
      final shown = await shownNotes(tester, '#1 priority fix');
      expect(shown, '#1 priority fix');
    });
  });

  testWidgets('new release shows versions and release notes', (tester) async {
    final checker = _FakeChecker(const UpdateAvailable(_updateInfo));
    await _showPrompt(tester, checker);

    expect(checker.calls, 1);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('1.2.0 is available'), findsOneWidget);
    expect(find.textContaining('you have 1.0.0'), findsOneWidget);
    expect(find.text('Faster scores.'), findsOneWidget);
  });

  testWidgets('Update now passes the release to the open strategy', (
    tester,
  ) async {
    final checker = _FakeChecker(const UpdateAvailable(_updateInfo));
    final launched = await _showPrompt(tester, checker);

    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(launched, [_updateInfo]);
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('Later closes the prompt without opening the release', (
    tester,
  ) async {
    final checker = _FakeChecker(const UpdateAvailable(_updateInfo));
    final launched = await _showPrompt(tester, checker);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.text('Update available'), findsNothing);
  });

  for (final entry in <String, UpdateCheckResult>{
    'UpToDate': const UpToDate(),
    'CheckSkipped': const CheckSkipped(),
    'CheckError': CheckError(Exception('offline')),
  }.entries) {
    testWidgets('${entry.key} remains silent', (tester) async {
      final checker = _FakeChecker(entry.value);
      await _showPrompt(tester, checker);

      expect(checker.calls, 1);
      expect(find.text('Update available'), findsNothing);
      expect(find.text('Later'), findsNothing);
      expect(find.text('Update now'), findsNothing);
    });
  }
}
