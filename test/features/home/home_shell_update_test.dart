import 'dart:async';
import 'dart:typed_data';

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/app.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/providers/app_providers.dart';
import 'package:my_football/providers/update_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns empty payloads so no view inside [HomeShell] touches the network.
class _EmptyAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"table": [], "events": []}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// Fake checker whose `check()` calls are counted; the returned result can be
/// resolved later via [complete] so a test can unmount the app mid-check.
class _FakeReleaseChecker extends ReleaseChecker {
  _FakeReleaseChecker(this.result)
    : super(owner: 'etnt', repo: 'my-football', currentVersion: '1.2.0');

  final UpdateCheckResult result;
  final _pending = Completer<UpdateCheckResult>();
  int calls = 0;

  @override
  Future<UpdateCheckResult> check() async {
    calls++;
    return _pending.future;
  }

  void complete() {
    if (!_pending.isCompleted) _pending.complete(result);
  }
}

Future<void> _pumpApp(WidgetTester tester, _FakeReleaseChecker checker) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _EmptyAdapter();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        footballApiClientProvider.overrideWithValue(
          FootballApiClient(dio: dio),
        ),
        releaseCheckerProvider.overrideWithValue(checker),
      ],
      child: const MyFootballApp(),
    ),
  );
}

void main() {
  const updateInfo = UpdateInfo(
    latestVersion: '1.2.0',
    currentVersion: '1.2.0',
    releasePageUrl: 'https://github.com/etnt/my-football/releases/tag/v1.2.0',
  );

  testWidgets('the update check runs exactly once per launch', (tester) async {
    final checker = _FakeReleaseChecker(const UpToDate());
    await _pumpApp(tester, checker);
    await tester.pump();
    await tester.pump();

    expect(checker.calls, 1);
    checker.complete();
    await tester.pumpAndSettle();
    expect(checker.calls, 1);
  });

  testWidgets('UpdateAvailable shows the update prompt', (tester) async {
    final checker = _FakeReleaseChecker(const UpdateAvailable(updateInfo));
    await _pumpApp(tester, checker);
    await tester.pump();
    checker.complete();
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
  });

  testWidgets('CheckSkipped stays silent', (tester) async {
    final checker = _FakeReleaseChecker(const CheckSkipped());
    await _pumpApp(tester, checker);
    await tester.pump();
    checker.complete();
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
    expect(find.text('Update now'), findsNothing);
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('unmounting mid-check does not throw', (tester) async {
    final checker = _FakeReleaseChecker(const UpdateAvailable(updateInfo));
    await _pumpApp(tester, checker);
    await tester.pump();
    expect(checker.calls, 1);

    // Replace the app so the shell (and its context) is disposed while the
    // check is still pending.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    checker.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Update available'), findsNothing);
  });
}
