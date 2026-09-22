import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/api/sportsdb_v2_client.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/lineups/lineup_sheet.dart';
import 'package:my_football/features/stats/player_stats_repository.dart';
import 'package:my_football/features/stats/stats_providers.dart'
    show playerStatsRepositoryProvider;
import 'package:my_football/models/fixture.dart';
import 'package:my_football/models/lineup_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves canned JSON per path so the sheet's player drill-down runs offline.
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

/// Issue #8 — the line-up sheet: XI/substitutes sections per team, the
/// home/away toggle for match entry points, the empty state for competitions
/// without coverage, and tap-through to the player info sheet.
void main() {
  Fixture fixtureFor() => Fixture.fromJson(const {
        'idEvent': '2267073',
        'strTimestamp': '2025-08-15T19:00:00',
        'strStatus': 'Match Finished',
        'intHomeScore': '4',
        'intAwayScore': '2',
        'idHomeTeam': '133602',
        'strHomeTeam': 'Liverpool',
        'strHomeTeamBadge': '',
        'idAwayTeam': '134301',
        'strAwayTeam': 'Bournemouth',
        'strAwayTeamBadge': '',
        'intRound': '1',
      });

  List<LineupPlayer> lineupFor() => const [
        LineupPlayer(
          playerId: 34145506,
          name: 'Mohamed Salah',
          teamId: 133602,
          teamName: 'Liverpool',
          position: 'Right Winger',
          squadNumber: '11',
          isHome: true,
          isSubstitute: false,
          imageUrl: '',
        ),
        LineupPlayer(
          playerId: 34145111,
          name: 'Alisson Becker',
          teamId: 133602,
          teamName: 'Liverpool',
          position: 'Goalkeeper',
          squadNumber: '1',
          isHome: true,
          isSubstitute: false,
          imageUrl: '',
        ),
        LineupPlayer(
          playerId: 34145999,
          name: 'Federico Chiesa',
          teamId: 133602,
          teamName: 'Liverpool',
          position: 'Striker',
          squadNumber: '14',
          isHome: true,
          isSubstitute: true,
          imageUrl: '',
        ),
        LineupPlayer(
          playerId: 34146000,
          name: 'Opponent Keeper',
          teamId: 134301,
          teamName: 'Bournemouth',
          position: 'Goalkeeper',
          squadNumber: '1',
          isHome: false,
          isSubstitute: false,
          imageUrl: '',
        ),
      ];

  const searchBody = '''
  {
    "player": [
      {"idPlayer": "34145506", "strPlayer": "Mohamed Salah", "strTeam": "Liverpool", "strSport": "Soccer", "strPosition": "Forward"}
    ]
  }
  ''';

  const lookupBody = '''
  {
    "players": [
      {"idPlayer": "34145506", "strPlayer": "Mohamed Salah", "strTeam": "Liverpool", "strSport": "Soccer", "strPosition": "Forward", "strNumber": "11", "strSide": "Left"}
    ]
  }
  ''';

  Future<Widget> buildHost(
    WidgetTester tester,
    Widget sheet, {
    List<LineupPlayer> lineup = const [],
  }) async {
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
    final repo = PlayerStatsRepository(v1: v1, v2: v2, cache: CacheStore(prefs));

    // A tall surface so the whole line-up fits inside the sheet's 80% cap.
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    return ProviderScope(
      overrides: [
        lineupProvider.overrideWith((ref, eventId) async => lineup),
        playerStatsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: Scaffold(body: sheet)),
    );
  }

  testWidgets('shows the starting XI and substitutes for the pinned team',
      (tester) async {
    await tester.pumpWidget(
      await buildHost(tester, LineupSheet(fixture: fixtureFor(), teamId: 133602),
          lineup: lineupFor()),
    );
    await tester.pumpAndSettle();

    // XI rows (sorted by squad number) with their positions…
    expect(find.text('Starting XI'), findsOneWidget);
    expect(find.text('Alisson Becker'), findsOneWidget);
    expect(find.text('Goalkeeper'), findsOneWidget);
    expect(find.text('Mohamed Salah'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // squad number badge
    // …and the substitute section.
    expect(find.text('Substitutes'), findsOneWidget);
    expect(find.text('Federico Chiesa'), findsOneWidget);
    // The other team's players never show.
    expect(find.text('Opponent Keeper'), findsNothing);
    // Pinned-team entry point has no toggle.
    expect(find.byType(SegmentedButton<int>), findsNothing);
  });

  testWidgets('a match entry point toggles between the two teams',
      (tester) async {
    await tester.pumpWidget(
      await buildHost(tester, LineupSheet(fixture: fixtureFor()), lineup: lineupFor()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    expect(find.text('Mohamed Salah'), findsOneWidget);
    expect(find.text('Opponent Keeper'), findsNothing);

    // Switch to the away side.
    await tester.tap(find.text('Bournemouth'));
    await tester.pumpAndSettle();

    expect(find.text('Opponent Keeper'), findsOneWidget);
    expect(find.text('Mohamed Salah'), findsNothing);
  });

  testWidgets('an uncovered match explains itself', (tester) async {
    await tester.pumpWidget(
      await buildHost(tester, LineupSheet(fixture: fixtureFor())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No lineup data is available for this match.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a line-up player opens the player info sheet',
      (tester) async {
    await tester.pumpWidget(
      await buildHost(tester, LineupSheet(fixture: fixtureFor(), teamId: 133602),
          lineup: lineupFor()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mohamed Salah'));
    await tester.pumpAndSettle();

    // The player sheet opened on top of the line-up sheet.
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Forward'), findsOneWidget);
    expect(find.text('Squad number'), findsOneWidget); // enriched (#7)
  });
}
