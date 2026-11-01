import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/fixtures/fixtures_repository.dart';
import 'package:my_football/features/predictions/prediction_input.dart';
import 'package:my_football/features/predictions/prediction_repository.dart';
import 'package:my_football/features/predictions/prediction_result.dart';
import 'package:my_football/features/standings/standings_repository.dart';
import 'package:my_football/models/fixture.dart';
import 'package:my_football/models/league.dart';
import 'package:my_football/models/team_standing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adapter that always fails, modelling an unreachable API without network.
class _FailingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, error: 'network down (test)');
  }
}

FootballApiClient _failingClient() {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = _FailingAdapter();
  return FootballApiClient(dio: dio);
}

class _FakeStandingsRepository extends StandingsRepository {
  _FakeStandingsRepository(SharedPreferences prefs, {required this.rows})
    : super(client: _failingClient(), cache: CacheStore(prefs));

  final List<TeamStanding> rows;
  int calls = 0;

  @override
  Future<List<TeamStanding>> getStandings({
    required League league,
    required int season,
    bool forceRefresh = false,
  }) async {
    calls++;
    return rows;
  }
}

class _FakeFixturesRepository extends FixturesRepository {
  _FakeFixturesRepository(SharedPreferences prefs, {required this.events})
    : super(client: _failingClient(), cache: CacheStore(prefs));

  final List<Fixture> events;
  int calls = 0;

  @override
  Future<List<Fixture>> getSeasonEvents({
    required League league,
    required int season,
    bool forceRefresh = false,
  }) async {
    calls++;
    return events;
  }
}

TeamStanding _row({
  required int id,
  required String name,
  int rank = 1,
  int played = 7,
  int points = 14,
  int goalsDiff = 5,
  String form = '',
}) {
  return TeamStanding(
    rank: rank,
    teamId: id,
    teamName: name,
    teamLogo: '',
    points: points,
    goalsDiff: goalsDiff,
    played: played,
    win: 4,
    draw: 2,
    lose: 1,
    form: form,
  );
}

/// An upcoming fixture: Arsenal (1) vs Chelsea (2) in 7 days.
Fixture _fixture({int id = 100}) {
  return Fixture(
    id: id,
    dateUtc: DateTime.now().toUtc().add(const Duration(days: 7)),
    statusShort: 'NS',
    statusLong: '',
    elapsed: null,
    homeId: 1,
    homeName: 'Arsenal',
    homeLogo: '',
    awayId: 2,
    awayName: 'Chelsea',
    awayLogo: '',
    homeGoals: null,
    awayGoals: null,
  );
}

/// A finished 2–0 home win for team [homeId] some days before kick-off.
Fixture _result({
  required int id,
  required int homeId,
  required int daysBeforeKickoff,
  required DateTime kickoffUtc,
}) {
  final date = kickoffUtc.subtract(Duration(days: daysBeforeKickoff));
  return Fixture(
    id: id,
    dateUtc: date,
    statusShort: 'FT',
    statusLong: '',
    elapsed: null,
    homeId: homeId,
    homeName: 'Team $homeId',
    homeLogo: '',
    awayId: homeId + 50,
    awayName: 'Team ${homeId + 50}',
    awayLogo: '',
    awayGoals: 0,
    homeGoals: 2,
  );
}

Future<PredictionRepository> _repository(
  SharedPreferences prefs, {
  List<TeamStanding>? table,
  List<Fixture>? events,
}) async {
  return PredictionRepository(
    standings: _FakeStandingsRepository(prefs, rows: table ?? []),
    fixtures: _FakeFixturesRepository(prefs, events: events ?? []),
  );
}

void main() {
  late SharedPreferences prefs;
  late League league;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    league = League.premierLeague;
  });

  test('missing fixture throws PredictionUnavailable', () async {
    final repository = await _repository(
      prefs,
      table: [
        _row(id: 1, name: 'Arsenal'),
        _row(id: 2, name: 'Chelsea'),
      ],
      events: [_fixture(id: 100)],
    );
    await expectLater(
      repository.build(league: league, season: 2026, fixtureId: 999),
      throwsA(
        isA<PredictionUnavailable>().having(
          (e) => e.reason,
          'reason',
          'This match is no longer in the cached season data.',
        ),
      ),
    );
  });

  test('missing home team throws PredictionUnavailable (REQ-007)', () async {
    final repository = await _repository(
      prefs,
      // Chelsea only; Arsenal is missing from the table.
      table: [_row(id: 2, name: 'Chelsea')],
      events: [_fixture()],
    );
    await expectLater(
      repository.build(league: league, season: 2026, fixtureId: 100),
      throwsA(
        isA<PredictionUnavailable>().having(
          (e) => e.reason,
          'reason',
          'Arsenal is not in the selected league table.',
        ),
      ),
    );
  });

  test('missing away team throws PredictionUnavailable (REQ-007)', () async {
    final repository = await _repository(
      prefs,
      table: [_row(id: 1, name: 'Arsenal')],
      events: [_fixture()],
    );
    await expectLater(
      repository.build(league: league, season: 2026, fixtureId: 100),
      throwsA(isA<PredictionUnavailable>()),
    );
  });

  test('derived season-event form is preferred from 3 results on', () async {
    final kickoff = DateTime.now().toUtc().add(const Duration(days: 7));
    final repository = await _repository(
      prefs,
      table: [
        _row(id: 1, name: 'Arsenal', form: 'WWDWW'),
        _row(id: 2, name: 'Chelsea', form: 'LLWDL'),
      ],
      events: [
        _fixture(),
        _result(id: 1, homeId: 1, daysBeforeKickoff: 7, kickoffUtc: kickoff),
        _result(id: 2, homeId: 1, daysBeforeKickoff: 14, kickoffUtc: kickoff),
        _result(id: 3, homeId: 1, daysBeforeKickoff: 21, kickoffUtc: kickoff),
      ],
    );
    final input = await repository.build(
      league: league,
      season: 2026,
      fixtureId: 100,
    );
    expect(input.home.formSource, FormSource.seasonEvents);
    expect(input.home.formOrdered, isTrue);
    expect(input.home.form, ['W', 'W', 'W']); // newest first
  });

  test('falls back to strForm with fewer than 3 derived results', () async {
    final kickoff = DateTime.now().toUtc().add(const Duration(days: 7));
    final repository = await _repository(
      prefs,
      table: [
        _row(id: 1, name: 'Arsenal', form: 'WWDWW'),
        _row(id: 2, name: 'Chelsea', form: 'LLWDL'),
      ],
      events: [
        _fixture(),
        // Only two derived results, so the season-event source is not used.
        _result(id: 1, homeId: 1, daysBeforeKickoff: 7, kickoffUtc: kickoff),
        _result(id: 2, homeId: 1, daysBeforeKickoff: 14, kickoffUtc: kickoff),
      ],
    );
    final input = await repository.build(
      league: league,
      season: 2026,
      fixtureId: 100,
    );
    expect(input.home.formSource, FormSource.standingsForm);
    // The strForm order is unknown (TASK-019), so it is not treated as
    // newest-first data.
    expect(input.home.formOrdered, isFalse);
    expect(input.home.form, ['W', 'W', 'D', 'W', 'W']);
  });

  test('no form anywhere yields the none source (REQ-006)', () async {
    final repository = await _repository(
      prefs,
      table: [
        _row(id: 1, name: 'Arsenal'),
        _row(id: 2, name: 'Chelsea'),
      ],
      events: [_fixture()],
    );
    final input = await repository.build(
      league: league,
      season: 2026,
      fixtureId: 100,
    );
    expect(input.home.formSource, FormSource.none);
    expect(input.home.form, isEmpty);
  });

  test('league average ppg comes from the played rows', () async {
    final repository = await _repository(
      prefs,
      table: [
        _row(id: 1, name: 'Arsenal', played: 7, points: 21),
        _row(id: 2, name: 'Chelsea', played: 7, points: 7),
      ],
      events: [_fixture()],
    );
    final input = await repository.build(
      league: league,
      season: 2026,
      fixtureId: 100,
    );
    expect(input.leagueAvgPpg, closeTo(2.0, 0.0001));
  });

  test(
    'a standings API failure still yields the cached rows (REQ-008)',
    () async {
      final cache = CacheStore(prefs);
      const key = 'standings_4328_2026';
      await cache.writeJson(key, [
        const TeamStanding(
          rank: 1,
          teamId: 1,
          teamName: 'Arsenal',
          teamLogo: '',
          points: 21,
          goalsDiff: 9,
          played: 7,
          win: 7,
          draw: 0,
          lose: 0,
          form: '',
        ).toJson(),
        const TeamStanding(
          rank: 2,
          teamId: 2,
          teamName: 'Chelsea',
          teamLogo: '',
          points: 7,
          goalsDiff: -2,
          played: 7,
          win: 2,
          draw: 1,
          lose: 4,
          form: '',
        ).toJson(),
      ]);

      // The real repository with an unreachable API: it must fall back to the
      // cached table instead of failing the prediction.
      final repository = PredictionRepository(
        standings: StandingsRepository(client: _failingClient(), cache: cache),
        fixtures: _FakeFixturesRepository(prefs, events: [_fixture()]),
      );
      final input = await repository.build(
        league: league,
        season: 2026,
        fixtureId: 100,
      );
      expect(input.home.name, 'Arsenal');
      expect(input.away.name, 'Chelsea');
    },
  );

  test('makes exactly one call to each repository (REQ-008)', () async {
    final standings = _FakeStandingsRepository(
      prefs,
      rows: [
        _row(id: 1, name: 'Arsenal'),
        _row(id: 2, name: 'Chelsea'),
      ],
    );
    final fixtures = _FakeFixturesRepository(prefs, events: [_fixture()]);
    final repository = PredictionRepository(
      standings: standings,
      fixtures: fixtures,
    );
    await repository.build(league: league, season: 2026, fixtureId: 100);
    expect(standings.calls, 1);
    expect(fixtures.calls, 1);
  });
}
