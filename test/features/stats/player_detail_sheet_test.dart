import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/api/sportsdb_v2_client.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/stats/player_detail_sheet.dart';
import 'package:my_football/features/stats/player_stats.dart';
import 'package:my_football/features/stats/player_stats_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves canned JSON per path so the sheet's lookup flow runs offline.
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.bodyFor);

  final String? Function(String path) bodyFor;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      bodyFor(options.path) ?? '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// Issue #7 — tapping a leaderboard row opens the player sheet; it must show
/// the enriched profile (fields only `lookupplayer.php` carries) when
/// available, and stay quiet about fields that don't exist.
void main() {
  const searchBody = '''
  {
    "player": [
      {
        "idPlayer": "34169116",
        "strPlayer": "Erling Haaland",
        "strTeam": "Manchester City",
        "strSport": "Soccer",
        "strPosition": "Forward",
        "strNationality": "Norway",
        "dateBorn": "2000-07-21"
      }
    ]
  }
  ''';

  const lookupBody = '''
  {
    "players": [
      {
        "idPlayer": "34169116",
        "strPlayer": "Erling Haaland",
        "strTeam": "Manchester City",
        "strSport": "Soccer",
        "strPosition": "Forward",
        "strNationality": "Norway",
        "dateBorn": "2000-07-21",
        "strBirthLocation": "Leeds, England",
        "strHeight": "195 cm",
        "strWeight": "192 lbs",
        "strNumber": "9",
        "strStatus": "Active",
        "strSigning": "€185M",
        "strWage": "£525,000 per week",
        "strSide": "Left",
        "strTeam2": "Norway",
        "strPlayerAlternate": "Erling Braut Håland",
        "strInstagram": "www.instagram.com/erling.haaland/",
        "strDescriptionEN": "Norwegian striker."
      }
    ]
  }
  ''';

  Future<PlayerStatsRepository> repoWith(String? lookupBody) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = _RoutingAdapter((path) {
      if (path.contains('searchplayers.php')) return searchBody;
      if (path.contains('lookupplayer.php')) return lookupBody;
      return '{}';
    });
    final v1 = FootballApiClient(
      apiKey: 'p',
      dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter,
    );
    final v2 = SportsDbV2Client(
      apiKey: 'p',
      dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter
        ..options.headers = {'X-API-KEY': 'p'},
    );
    return PlayerStatsRepository(v1: v1, v2: v2, cache: CacheStore(prefs));
  }

  Future<void> openSheet(WidgetTester tester, PlayerStatsRepository repo) async {
    // A tall surface so the whole profile fits inside the sheet's 80% cap and
    // every row is built (the sheet's ListView builds lazily).
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPlayerDetailSheet(
                context,
                repo,
                const StatLine('Erling Haaland', 3, team: 'Manchester City'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the enriched profile fields (issue #7)', (tester) async {
    await openSheet(tester, await repoWith(lookupBody));

    // New fields only the full lookup carries…
    expect(find.text('Squad number'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('National team'), findsOneWidget);
    expect(find.text('Norway'), findsWidgets); // nationality + national team
    expect(find.text('Preferred foot'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Signed for'), findsOneWidget);
    expect(find.text('€185M'), findsOneWidget);
    expect(find.text('Wage'), findsOneWidget);
    expect(find.text('£525,000 per week'), findsOneWidget);
    expect(find.text('Also known as'), findsOneWidget);
    expect(find.text('Erling Braut Håland'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    // Birthplace/height now actually have values…
    expect(find.text('Birthplace'), findsOneWidget);
    expect(find.text('Leeds, England'), findsOneWidget);
    // …and Born is human-formatted.
    expect(find.text('21 Jul 2000'), findsOneWidget);
    // Bio comes through too.
    expect(find.text('Norwegian striker.'), findsOneWidget);
  });

  testWidgets('hides rows the player has no data for, and boring statuses',
      (tester) async {
    await openSheet(tester, await repoWith(null)); // lookup adds nothing

    expect(find.text('Squad number'), findsNothing);
    expect(find.text('Wage'), findsNothing);
    expect(find.text('Signed for'), findsNothing);
    expect(find.text('Preferred foot'), findsNothing);
    expect(find.text('Instagram'), findsNothing);
    // "Active" is the default status — not worth a row.
    expect(find.text('Status'), findsNothing);
    // Basics still render from the search hit.
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Nationality'), findsOneWidget);
    expect(find.text('21 Jul 2000'), findsOneWidget);
  });
}
