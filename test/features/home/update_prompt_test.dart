import 'dart:async';

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/home/update_prompt.dart';

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
