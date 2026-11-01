import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/predictions/prediction_providers.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/features/team/team_detail_screen.dart';
import 'package:my_football/features/team/team_providers.dart';
import 'package:my_football/features/team/team_repository.dart';
import 'package:my_football/models/fixture.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTeamRepository extends TeamRepository {
  _FakeTeamRepository({
    required this.fixtures,
    required SharedPreferences prefs,
  }) : super(
         client: FootballApiClient(
           dio: Dio(BaseOptions(baseUrl: 'https://example.test')),
         ),
         cache: CacheStore(prefs),
       );

  final List<Fixture> fixtures;

  @override
  Future<List<Fixture>> getSeasonFixtures({
    required int teamId,
    required int leagueId,
    required int season,
    bool forceRefresh = false,
  }) async => fixtures;
}

Fixture _fixture({
  required int id,
  required DateTime dateUtc,
  required bool finished,
  required String opponent,
}) {
  return Fixture(
    id: id,
    dateUtc: dateUtc,
    statusShort: finished ? 'FT' : 'NS',
    statusLong: '',
    elapsed: null,
    homeId: 1,
    homeName: 'Arsenal',
    homeLogo: '',
    awayId: id + 100,
    awayName: opponent,
    awayLogo: '',
    homeGoals: finished ? 2 : null,
    awayGoals: finished ? 1 : null,
  );
}

Fixture _resultFixture({
  required int id,
  required DateTime dateUtc,
  required String result,
}) {
  // Team 1 is always home; craft the score so the result matches.
  final homeWins = result == 'W';
  final draw = result == 'D';
  return Fixture(
    id: id,
    dateUtc: dateUtc,
    statusShort: 'FT',
    statusLong: '',
    elapsed: null,
    homeId: 1,
    homeName: 'Arsenal',
    homeLogo: '',
    awayId: id + 100,
    awayName: 'Opponent $id',
    awayLogo: '',
    homeGoals: draw ? 1 : (homeWins ? 2 : 0),
    awayGoals: draw ? 1 : (homeWins ? 0 : 1),
  );
}

void main() {
  testWidgets('shows every result and upcoming fixture for the season', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // ListView builds children lazily, so make the test surface tall enough
    // that every fixture tile is materialised without scrolling.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository = _FakeTeamRepository(
      prefs: prefs,
      fixtures: [
        for (var i = 0; i < 6; i++)
          _fixture(
            id: i + 1,
            dateUtc: DateTime.utc(2025, 8, i + 1),
            finished: true,
            opponent: 'Finished ${i + 1}',
          ),
        for (var i = 0; i < 6; i++)
          _fixture(
            id: i + 21,
            dateUtc: DateTime.utc(2026, 1, i + 1),
            finished: false,
            opponent: 'Upcoming ${i + 1}',
          ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [teamRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: TeamDetailScreen(
            teamId: 1,
            leagueId: 4328,
            teamName: 'Arsenal',
            teamLogo: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Recent results'), findsNothing);

    for (var i = 1; i <= 6; i++) {
      expect(find.text('Finished $i'), findsOneWidget);
      expect(find.text('Upcoming $i'), findsOneWidget);
    }
  });

  testWidgets('form strip shows the last five results oldest to newest', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Chronological results: L, L, W, D, W (oldest to newest).
    final results = ['L', 'L', 'W', 'D', 'W'];
    final repository = _FakeTeamRepository(
      prefs: prefs,
      fixtures: [
        for (var i = 0; i < results.length; i++)
          _resultFixture(
            id: i + 1,
            dateUtc: DateTime.utc(2025, 8, i + 1),
            result: results[i],
          ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [teamRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: TeamDetailScreen(
            teamId: 1,
            leagueId: 4328,
            teamName: 'Arsenal',
            teamLogo: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('L'), findsNWidgets(2));
    expect(find.text('W'), findsNWidgets(2));
    expect(find.text('D'), findsOneWidget);

    // The badges read oldest-to-newest left to right: L, L, W, D, W.
    double dx(Finder f) => tester.getTopLeft(f).dx;
    final lLeft = dx(find.text('L').first);
    final lRight = dx(find.text('L').last);
    final wLeft = dx(find.text('W').first);
    final wRight = dx(find.text('W').last);
    final d = dx(find.text('D'));

    // Both losses sit left of both wins.
    expect(lLeft, lessThan(wLeft));
    expect(lRight, lessThan(wLeft));
    // The draw sits between the two wins (position 4 of 5).
    expect(wLeft, lessThan(d));
    expect(d, lessThan(wRight));
    // And the newest result (rightmost badge) is a win.
    expect(wRight, greaterThan(d));
  });

  testWidgets('long pressing an upcoming match opens the prediction sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // A dynamic future date: a fixed date would eventually fall in the past
    // and silently lose the long press (REQ-001 names this screen too).
    final kickoff = DateTime.now().toUtc().add(const Duration(days: 7));
    final repository = _FakeTeamRepository(
      prefs: prefs,
      fixtures: [
        _fixture(
          id: 21,
          dateUtc: kickoff,
          finished: false,
          opponent: 'Upcoming 1',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teamRepositoryProvider.overrideWithValue(repository),
          predictionProvider((
            fixtureId: 21,
            leagueId: 4328,
            season: 2026,
          )).overrideWith((ref) async => _prediction()),
        ],
        child: const MaterialApp(
          home: TeamDetailScreen(
            teamId: 1,
            leagueId: 4328,
            teamName: 'Arsenal',
            teamLogo: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Upcoming 1'));
    await tester.pumpAndSettle();

    expect(find.text('Why this estimate?'), findsOneWidget);
    expect(
      find.text('Estimate based on table and form. Not betting advice.'),
      findsOneWidget,
    );
  });
}

PredictionResult _prediction() {
  return const PredictionResult(
    pHome: 0.52,
    pDraw: 0.24,
    pAway: 0.24,
    displayPercents: {Outcome.home: 52, Outcome.draw: 24, Outcome.away: 24},
    verdict: Verdict.homeWin,
    isSlight: false,
    reasons: [
      PredictionReason(
        factor: 'table',
        favours: PredictionFavour.home,
        text: 'Arsenal are 1st, Upcoming 1 are 8th.',
      ),
    ],
    missingNotes: [],
    completeness: Completeness.full,
    formulaVersion: 'v1',
  );
}
