// Basic smoke test for the app skeleton.

import 'dart:typed_data';

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_football/app.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/providers/app_providers.dart';
import 'package:my_football/providers/update_provider.dart';

/// Returns an empty table so the smoke test never touches the network.
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

class _FakeReleaseChecker extends ReleaseChecker {
  _FakeReleaseChecker()
    : super(owner: 'etnt', repo: 'my-football', currentVersion: '1.2.0');

  int calls = 0;

  @override
  Future<UpdateCheckResult> check() async {
    calls++;
    return const UpToDate();
  }
}

void main() {
  testWidgets('App renders the standings screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final checker = _FakeReleaseChecker();
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
    await tester.pump();

    expect(find.textContaining('My Football'), findsOneWidget);
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('Matches'), findsOneWidget);

    // Let the standings future and post-frame update check settle.
    await tester.pumpAndSettle();
    expect(checker.calls, 1);
    expect(find.text('Update available'), findsNothing);
  });
}
