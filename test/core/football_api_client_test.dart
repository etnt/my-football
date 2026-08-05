import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/api_exception.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/models/rate_limit_info.dart';

/// Minimal [HttpClientAdapter] that returns a canned body + headers, so we can
/// exercise the client without any network access.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    required this.body,
    this.extraHeaders = const {},
  });

  final String body;
  final Map<String, List<String>> extraHeaders;
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
        ...extraHeaders,
      },
    );
  }
}

FootballApiClient _clientWith(
  _FakeAdapter adapter, {
  String? apiKey = 'test-key',
  void Function(RateLimitInfo)? onRateLimit,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter;
  return FootballApiClient(apiKey: apiKey, onRateLimit: onRateLimit, dio: dio);
}

void main() {
  group('FootballApiClient.getStandings', () {
    const standingsBody = '''
    {
      "get": "standings",
      "errors": [],
      "results": 1,
      "response": [
        {
          "league": {
            "id": 39,
            "name": "Premier League",
            "standings": [
              [
                {
                  "rank": 1,
                  "team": {"id": 50, "name": "Manchester City", "logo": "c.png"},
                  "points": 89,
                  "goalsDiff": 61,
                  "form": "WWDWW",
                  "all": {"played": 38, "win": 28, "draw": 5, "lose": 5}
                },
                {
                  "rank": 2,
                  "team": {"id": 42, "name": "Arsenal", "logo": "a.png"},
                  "points": 84,
                  "goalsDiff": 45,
                  "form": "WLWWW",
                  "all": {"played": 38, "win": 26, "draw": 6, "lose": 6}
                }
              ]
            ]
          }
        }
      ]
    }
    ''';

    test('extracts the first standings group', () async {
      final client = _clientWith(_FakeAdapter(body: standingsBody));

      final table = await client.getStandings(leagueId: 39, season: 2023);

      expect(table, hasLength(2));
      expect(table.first.teamName, 'Manchester City');
      expect(table.first.points, 89);
      expect(table[1].teamName, 'Arsenal');
    });

    test('sends the api key header and query params', () async {
      final adapter = _FakeAdapter(body: standingsBody);
      final client = _clientWith(adapter);

      await client.getStandings(leagueId: 39, season: 2023);

      expect(adapter.lastOptions?.headers['x-apisports-key'], 'test-key');
      expect(adapter.lastOptions?.queryParameters['league'], 39);
      expect(adapter.lastOptions?.queryParameters['season'], 2023);
    });

    test('captures rate-limit headers on every response', () async {
      RateLimitInfo? captured;
      final adapter = _FakeAdapter(
        body: standingsBody,
        extraHeaders: {
          'x-ratelimit-requests-remaining': ['87'],
          'x-ratelimit-requests-limit': ['100'],
          'X-RateLimit-Remaining': ['9'],
          'X-RateLimit-Limit': ['10'],
        },
      );
      final client = _clientWith(adapter, onRateLimit: (i) => captured = i);

      await client.getStandings(leagueId: 39, season: 2023);

      expect(captured, isNotNull);
      expect(captured!.remainingToday, 87);
      expect(captured!.dailyLimit, 100);
      expect(captured!.remainingMinute, 9);
      expect(captured!.minuteLimit, 10);
      expect(captured!.dailyLabel, '87/100');
    });

    test('returns empty list when there is no standings data', () async {
      final client = _clientWith(
        _FakeAdapter(body: '{"errors": [], "response": []}'),
      );

      final table = await client.getStandings(leagueId: 39, season: 2023);

      expect(table, isEmpty);
    });
  });

  group('FootballApiClient error handling', () {
    test('throws isMissingKey ApiException when no key is set', () async {
      final client = _clientWith(
        _FakeAdapter(body: '{}'),
        apiKey: null,
      );

      expect(
        () => client.getStandings(leagueId: 39, season: 2023),
        throwsA(
          isA<ApiException>().having((e) => e.isMissingKey, 'isMissingKey', true),
        ),
      );
    });

    test('surfaces API "errors" map as an ApiException', () async {
      final client = _clientWith(
        _FakeAdapter(
          body: '{"errors": {"token": "Missing application key."}, '
              '"response": []}',
        ),
      );

      expect(
        () => client.getStandings(leagueId: 39, season: 2023),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Missing application key.'),
          ),
        ),
      );
    });
  });

  group('FootballApiClient.getStatus', () {
    test('parses plan and quota', () async {
      final client = _clientWith(
        _FakeAdapter(
          body: '''
          {
            "errors": [],
            "response": {
              "subscription": {"plan": "Free", "active": true},
              "requests": {"current": 12, "limit_day": 100}
            }
          }
          ''',
        ),
      );

      final status = await client.getStatus();

      expect(status.plan, 'Free');
      expect(status.requestsToday, 12);
      expect(status.remainingToday, 88);
    });
  });

  group('FootballApiClient.getFixtures', () {
    const fixturesBody = '''
    {
      "errors": [],
      "response": [
        {
          "fixture": {
            "id": 100,
            "date": "2023-08-11T19:00:00+00:00",
            "status": {"short": "FT", "long": "Match Finished", "elapsed": 90}
          },
          "teams": {
            "home": {"id": 40, "name": "Liverpool", "logo": "l.png"},
            "away": {"id": 34, "name": "Newcastle", "logo": "n.png"}
          },
          "goals": {"home": 2, "away": 1}
        },
        {
          "fixture": {
            "id": 101,
            "date": "2023-08-19T14:00:00+00:00",
            "status": {"short": "NS", "long": "Not Started", "elapsed": null}
          },
          "teams": {
            "home": {"id": 42, "name": "Arsenal", "logo": "a.png"},
            "away": {"id": 47, "name": "Tottenham", "logo": "t.png"}
          },
          "goals": {"home": null, "away": null}
        }
      ]
    }
    ''';

    test('parses matches with and without scores', () async {
      final client = _clientWith(_FakeAdapter(body: fixturesBody));

      final matches = await client.getFixtures(leagueId: 39, season: 2023);

      expect(matches, hasLength(2));
      expect(matches.first.homeName, 'Liverpool');
      expect(matches.first.isFinished, isTrue);
      expect(matches.first.hasScore, isTrue);
      expect(matches.first.homeGoals, 2);

      expect(matches[1].isFinished, isFalse);
      expect(matches[1].hasScore, isFalse);
      expect(matches[1].homeGoals, isNull);
    });

    test('passes last/next query params', () async {
      final adapter = _FakeAdapter(body: fixturesBody);
      final client = _clientWith(adapter);

      await client.getFixtures(leagueId: 39, season: 2023, last: 20);

      expect(adapter.lastOptions?.queryParameters['last'], 20);
      expect(adapter.lastOptions?.queryParameters.containsKey('next'), isFalse);
    });
  });
}
