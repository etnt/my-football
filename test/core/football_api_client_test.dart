import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/api_exception.dart';
import 'package:my_football/core/api/football_api_client.dart';

/// Minimal [HttpClientAdapter] that returns a canned body + status, so we can
/// exercise the client without any network access.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.body, this.statusCode = 200});

  final String body;
  final int statusCode;
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
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

FootballApiClient _clientWith(_FakeAdapter adapter, {String? apiKey}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter
    ..options.validateStatus = (status) => status != null && status < 500;
  return FootballApiClient(apiKey: apiKey, dio: dio);
}

void main() {
  group('FootballApiClient.getStandings', () {
    const standingsBody = '''
    {
      "table": [
        {
          "intRank": "1",
          "idTeam": "133613",
          "strTeam": "Manchester City",
          "strBadge": "c.png",
          "intPoints": "89",
          "intGoalDifference": "61",
          "strForm": "WWDWW",
          "intPlayed": "38",
          "intWin": "28",
          "intDraw": "5",
          "intLoss": "5"
        },
        {
          "intRank": "2",
          "idTeam": "133604",
          "strTeam": "Arsenal",
          "strBadge": "a.png",
          "intPoints": "84",
          "intGoalDifference": "45",
          "strForm": "WLWWW",
          "intPlayed": "38",
          "intWin": "26",
          "intDraw": "6",
          "intLoss": "6"
        }
      ]
    }
    ''';

    test('parses the league table', () async {
      final client = _clientWith(_FakeAdapter(body: standingsBody));

      final table =
          await client.getStandings(leagueId: 4328, season: '2023-2024');

      expect(table, hasLength(2));
      expect(table.first.teamName, 'Manchester City');
      expect(table.first.points, 89);
      expect(table[1].teamName, 'Arsenal');
    });

    test('uses the free key in the path and sends l/s query params', () async {
      final adapter = _FakeAdapter(body: standingsBody);
      final client = _clientWith(adapter);

      await client.getStandings(leagueId: 4328, season: '2023-2024');

      expect(adapter.lastOptions?.path, '/123/lookuptable.php');
      expect(adapter.lastOptions?.queryParameters['l'], 4328);
      expect(adapter.lastOptions?.queryParameters['s'], '2023-2024');
    });

    test('uses a premium key in the path when provided', () async {
      final adapter = _FakeAdapter(body: standingsBody);
      final client = _clientWith(adapter, apiKey: 'premium123');

      await client.getStandings(leagueId: 4328, season: '2023-2024');

      expect(adapter.lastOptions?.path, '/premium123/lookuptable.php');
    });

    test('returns empty list when the table is null', () async {
      final client = _clientWith(_FakeAdapter(body: '{"table": null}'));

      final table =
          await client.getStandings(leagueId: 4328, season: '2023-2024');

      expect(table, isEmpty);
    });
  });

  group('FootballApiClient.getSeasonEvents', () {
    const eventsBody = '''
    {
      "events": [
        {
          "idEvent": "100",
          "strTimestamp": "2023-08-11T19:00:00",
          "strStatus": "FT",
          "idHomeTeam": "40",
          "strHomeTeam": "Liverpool",
          "strHomeTeamBadge": "l.png",
          "idAwayTeam": "34",
          "strAwayTeam": "Newcastle",
          "strAwayTeamBadge": "n.png",
          "intHomeScore": "2",
          "intAwayScore": "1"
        },
        {
          "idEvent": "101",
          "strTimestamp": "2023-08-19T14:00:00",
          "strStatus": "NS",
          "idHomeTeam": "42",
          "strHomeTeam": "Arsenal",
          "idAwayTeam": "47",
          "strAwayTeam": "Tottenham",
          "intHomeScore": null,
          "intAwayScore": null
        }
      ]
    }
    ''';

    test('parses events with and without scores', () async {
      final adapter = _FakeAdapter(body: eventsBody);
      final client = _clientWith(adapter);

      final events =
          await client.getSeasonEvents(leagueId: 4328, season: '2023-2024');

      expect(events, hasLength(2));
      expect(events.first.homeName, 'Liverpool');
      expect(events.first.isFinished, isTrue);
      expect(events.first.hasScore, isTrue);
      expect(events.first.homeGoals, 2);

      expect(events[1].isFinished, isFalse);
      expect(events[1].hasScore, isFalse);
      expect(events[1].homeGoals, isNull);

      expect(adapter.lastOptions?.path, '/123/eventsseason.php');
      expect(adapter.lastOptions?.queryParameters['id'], 4328);
      expect(adapter.lastOptions?.queryParameters['s'], '2023-2024');
    });

    test('returns empty list when events is missing', () async {
      final client = _clientWith(_FakeAdapter(body: '{}'));

      final events =
          await client.getSeasonEvents(leagueId: 4328, season: '2023-2024');

      expect(events, isEmpty);
    });
  });

  group('FootballApiClient error handling', () {
    test('throws a rate-limit ApiException on HTTP 429', () async {
      final client = _clientWith(_FakeAdapter(body: '{}', statusCode: 429));

      expect(
        () => client.getStandings(leagueId: 4328, season: '2023-2024'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Rate limit'),
          ),
        ),
      );
    });
  });

  group('FootballApiClient.getTeamLastEvents', () {
    const lastBody = '''
    {
      "results": [
        {
          "idEvent": "200",
          "strTimestamp": "2023-08-11T19:00:00",
          "strStatus": "FT",
          "idHomeTeam": "40",
          "strHomeTeam": "Girona",
          "idAwayTeam": "34",
          "strAwayTeam": "Arsenal",
          "intHomeScore": "1",
          "intAwayScore": "2"
        }
      ]
    }
    ''';

    test('parses the results key and hits eventslast.php', () async {
      final adapter = _FakeAdapter(body: lastBody);
      final client = _clientWith(adapter, apiKey: 'premium123');

      final events = await client.getTeamLastEvents(teamId: 133604);

      expect(events, hasLength(1));
      expect(events.first.homeName, 'Girona');
      expect(events.first.awayName, 'Arsenal');
      expect(adapter.lastOptions?.path, '/premium123/eventslast.php');
      expect(adapter.lastOptions?.queryParameters['id'], 133604);
    });

    test('returns empty list when results is missing', () async {
      final client = _clientWith(_FakeAdapter(body: '{}'), apiKey: 'p');

      final events = await client.getTeamLastEvents(teamId: 1);

      expect(events, isEmpty);
    });
  });

  group('FootballApiClient.getTeamNextEvents', () {
    const nextBody = '''
    {
      "events": [
        {
          "idEvent": "300",
          "strTimestamp": "2026-08-20T19:00:00",
          "strStatus": "NS",
          "idHomeTeam": "34",
          "strHomeTeam": "Arsenal",
          "idAwayTeam": "40",
          "strAwayTeam": "Leeds",
          "intHomeScore": null,
          "intAwayScore": null
        }
      ]
    }
    ''';

    test('parses the events key and hits eventsnext.php', () async {
      final adapter = _FakeAdapter(body: nextBody);
      final client = _clientWith(adapter, apiKey: 'premium123');

      final events = await client.getTeamNextEvents(teamId: 133604);

      expect(events, hasLength(1));
      expect(events.first.awayName, 'Leeds');
      expect(events.first.hasScore, isFalse);
      expect(adapter.lastOptions?.path, '/premium123/eventsnext.php');
      expect(adapter.lastOptions?.queryParameters['id'], 133604);
    });
  });
}

