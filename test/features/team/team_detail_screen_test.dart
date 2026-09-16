import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/team/team_detail_screen.dart';
import 'package:my_football/features/team/team_providers.dart';
import 'package:my_football/features/team/team_repository.dart';
import 'package:my_football/models/fixture.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTeamRepository extends TeamRepository {
  _FakeTeamRepository({required this.fixtures, required SharedPreferences prefs})
      : super(
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

void main() {
  testWidgets('shows every result and upcoming fixture for the season',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
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
        overrides: [
          teamRepositoryProvider.overrideWithValue(repository),
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

    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Recent results'), findsNothing);

    for (var i = 1; i <= 6; i++) {
      expect(find.text('Finished $i'), findsOneWidget);
      expect(find.text('Upcoming $i'), findsOneWidget);
    }
  });
}
