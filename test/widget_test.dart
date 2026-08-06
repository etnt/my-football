// Basic smoke test for the app skeleton.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_football/app.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/providers/app_providers.dart';

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

void main() {
  testWidgets('App renders the standings screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _EmptyAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          footballApiClientProvider
              .overrideWithValue(FootballApiClient(dio: dio)),
        ],
        child: const MyFootballApp(),
      ),
    );
    await tester.pump();

    expect(find.textContaining('My Football'), findsOneWidget);
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('Matches'), findsOneWidget);

    // Let the standings future settle so no timers outlive the test.
    await tester.pumpAndSettle();
  });
}
