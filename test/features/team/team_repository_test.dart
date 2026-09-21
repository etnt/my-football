import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/team/team_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.body});

  final String body;
  RequestOptions? lastOptions;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test('returns all current-season matches for the selected team', () async {
    const body = '''
    {
      "events": [
        {
          "idEvent": "100",
          "strTimestamp": "2025-08-11T19:00:00",
          "strStatus": "FT",
          "idHomeTeam": "34",
          "strHomeTeam": "Arsenal",
          "idAwayTeam": "40",
          "strAwayTeam": "Girona",
          "intHomeScore": "2",
          "intAwayScore": "1"
        },
        {
          "idEvent": "101",
          "strTimestamp": "2025-09-11T19:00:00",
          "strStatus": "FT",
          "idHomeTeam": "50",
          "strHomeTeam": "Chelsea",
          "idAwayTeam": "34",
          "strAwayTeam": "Arsenal",
          "intHomeScore": "0",
          "intAwayScore": "3"
        },
        {
          "idEvent": "102",
          "strTimestamp": "2025-10-11T19:00:00",
          "strStatus": "NS",
          "idHomeTeam": "34",
          "strHomeTeam": "Arsenal",
          "idAwayTeam": "60",
          "strAwayTeam": "Liverpool"
        },
        {
          "idEvent": "103",
          "strTimestamp": "2025-07-11T19:00:00",
          "strStatus": "FT",
          "idHomeTeam": "70",
          "strHomeTeam": "Leeds",
          "idAwayTeam": "80",
          "strAwayTeam": "Everton",
          "intHomeScore": "1",
          "intAwayScore": "1"
        }
      ]
    }
    ''';

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = _FakeAdapter(body: body);
    final client = FootballApiClient(
      apiKey: 'premium123',
      dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter,
    );
    final repository = TeamRepository(
      client: client,
      cache: CacheStore(prefs),
    );

    final fixtures = await repository.getSeasonFixtures(
      teamId: 34,
      leagueId: 4328,
      season: 2025,
    );

    expect(fixtures.map((fixture) => fixture.id), [102, 101, 100]);
    expect(adapter.lastOptions?.path, '/premium123/eventsseason.php');
    expect(adapter.lastOptions?.queryParameters, {
      'id': 4328,
      's': '2025-2026',
    });
  });

  test(
      'calendar-year leagues (Allsvenskan) query a single-year season '
      '(issue #6)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = _RoutingAdapter({
      '/premium123/lookupleague.php':
          '{"leagues":[{"idLeague":"4347","strLeague":"Swedish Allsvenskan",'
          '"strCurrentSeason":"2026"}]}',
      '/premium123/eventsseason.php':
          '{"events":[{"idEvent":"900","strTimestamp":"2026-04-05T17:30:00",'
          '"strStatus":"FT","idHomeTeam":"34","strHomeTeam":"Mjällby",'
          '"idAwayTeam":"40","strAwayTeam":"Sirius","intHomeScore":"1",'
          '"intAwayScore":"0"}]}',
    });
    final client = FootballApiClient(
      apiKey: 'premium123',
      dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter,
    );
    final repository = TeamRepository(
      client: client,
      cache: CacheStore(prefs),
    );

    final fixtures = await repository.getSeasonFixtures(
      teamId: 34,
      leagueId: 4347,
      season: 2026,
    );

    // The season lookup happens first, then the events call — with the
    // single-year season string Allsvenskan actually supports.
    expect(adapter.requests, [
      '/premium123/lookupleague.php',
      '/premium123/eventsseason.php',
    ]);
    expect(adapter.lastOptions?.queryParameters, {'id': 4347, 's': '2026'});
    expect(fixtures.single.id, 900);
  });
}

/// Serves a canned body per request path, so both the season lookup and the
/// events call can be exercised in one test.
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.bodies);

  final Map<String, String> bodies;
  final List<String> requests = [];
  RequestOptions? lastOptions;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.path);
    lastOptions = options;
    return ResponseBody.fromString(
      bodies[options.path] ?? '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
