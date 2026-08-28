import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/api_exception.dart';
import 'package:my_football/core/api/sportsdb_v2_client.dart';

/// Minimal [HttpClientAdapter] returning a canned body + status.
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

SportsDbV2Client _clientWith(_FakeAdapter adapter, {String apiKey = 'p'}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter
    ..options.headers = {'X-API-KEY': apiKey}
    ..options.validateStatus = (status) => status != null && status < 500;
  return SportsDbV2Client(apiKey: apiKey, dio: dio);
}

void main() {
  group('SportsDbV2Client.getLiveScores', () {
    const liveBody = '''
    {
      "livescore": [
        {
          "idEvent": "500",
          "strTimestamp": "2026-08-06T19:00:00",
          "strStatus": "2H",
          "strProgress": "67",
          "idHomeTeam": "40",
          "strHomeTeam": "Arsenal",
          "strHomeTeamBadge": "a.png",
          "idAwayTeam": "34",
          "strAwayTeam": "Chelsea",
          "strAwayTeamBadge": "c.png",
          "intHomeScore": "1",
          "intAwayScore": "0"
        }
      ]
    }
    ''';

    test('parses the livescore feed and hits /livescore/{league}', () async {
      final adapter = _FakeAdapter(body: liveBody);
      final client = _clientWith(adapter);

      final matches = await client.getLiveScores(leagueId: 4328);

      expect(matches, hasLength(1));
      final m = matches.first;
      expect(m.homeName, 'Arsenal');
      expect(m.awayName, 'Chelsea');
      expect(m.homeGoals, 1);
      expect(m.awayGoals, 0);
      expect(m.progress, '67');
      expect(adapter.lastOptions?.path, '/livescore/4328');
    });

    test('returns empty list when livescore is missing', () async {
      final client = _clientWith(_FakeAdapter(body: '{}'));

      final matches = await client.getLiveScores(leagueId: 4328);

      expect(matches, isEmpty);
    });

    test('throws when the key is rejected (401)', () async {
      final client = _clientWith(_FakeAdapter(body: '{}', statusCode: 401));

      expect(
        () => client.getLiveScores(leagueId: 4328),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws a rate-limit error on 429', () async {
      final client = _clientWith(_FakeAdapter(body: '{}', statusCode: 429));

      expect(
        () => client.getLiveScores(leagueId: 4328),
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

  group('SportsDbV2Client.getEventTimeline', () {
    const timelineBody = '''
    {
      "lookup": [
        {
          "idEvent": "1",
          "strTimeline": "Goal",
          "strTimelineDetail": "Normal Goal",
          "strPlayer": "Erling Haaland",
          "strAssist": "Phil Foden",
          "strTeam": "Manchester City",
          "intTime": "23"
        },
        {
          "idEvent": "1",
          "strTimeline": "Goal",
          "strTimelineDetail": "Penalty",
          "strPlayer": "Erling Haaland",
          "strAssist": ""
        },
        {
          "idEvent": "1",
          "strTimeline": "Card",
          "strTimelineDetail": "Yellow Card",
          "strPlayer": "Rodri",
          "strTeam": "Manchester City"
        },
        {
          "idEvent": "1",
          "strTimeline": "Card",
          "strTimelineDetail": "Red Card",
          "strPlayer": "Some Defender",
          "strTeam": "Everton"
        },
        {
          "idEvent": "1",
          "strTimeline": "Goal",
          "strTimelineDetail": "Own Goal",
          "strPlayer": "Some Defender"
        }
      ]
    }
    ''';

    test('parses goal rows and flags penalties/own goals', () async {
      final adapter = _FakeAdapter(body: timelineBody);
      final client = _clientWith(adapter);

      final timeline = await client.getEventTimeline(eventId: 1);
      final goals = timeline.goals;

      expect(adapter.lastOptions?.path, '/lookup/event_timeline/1');
      expect(goals, hasLength(3));

      expect(goals[0].scorer, 'Erling Haaland');
      expect(goals[0].assist, 'Phil Foden');
      expect(goals[0].team, 'Manchester City');
      expect(goals[0].minute, 23);
      expect(goals[0].penalty, isFalse);

      expect(goals[1].penalty, isTrue);
      expect(goals[1].assist, isNull);

      expect(goals[2].ownGoal, isTrue);
    });

    test('parses card rows and flags reds', () async {
      final client = _clientWith(_FakeAdapter(body: timelineBody));

      final cards = (await client.getEventTimeline(eventId: 1)).cards;

      expect(cards, hasLength(2));
      expect(cards[0].player, 'Rodri');
      expect(cards[0].team, 'Manchester City');
      expect(cards[0].red, isFalse);
      expect(cards[1].player, 'Some Defender');
      expect(cards[1].red, isTrue);
    });

    test('returns an empty timeline when lookup is missing', () async {
      final client = _clientWith(_FakeAdapter(body: '{}'));

      final timeline = await client.getEventTimeline(eventId: 1);
      expect(timeline.goals, isEmpty);
      expect(timeline.cards, isEmpty);
    });
  });
}
