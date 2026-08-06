import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/api/sportsdb_v2_client.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:my_football/features/stats/player_stats_repository.dart';
import 'package:my_football/models/league.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adapter that returns a canned body chosen by request path.
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.bodyFor);

  /// Maps a request path to the JSON body to return. Return null for 404-ish.
  final String? Function(String path) bodyFor;

  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final body = bodyFor(options.path) ?? '{}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

FootballApiClient _v1With(_RoutingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://v1.test'))
    ..httpClientAdapter = adapter
    ..options.validateStatus = (status) => status != null && status < 500;
  return FootballApiClient(apiKey: 'p', dio: dio);
}

SportsDbV2Client _v2With(_RoutingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://v2.test'))
    ..httpClientAdapter = adapter
    ..options.headers = {'X-API-KEY': 'p'}
    ..options.validateStatus = (status) => status != null && status < 500;
  return SportsDbV2Client(apiKey: 'p', dio: dio);
}

/// A finished season-events feed with two FT matches and one not-started one.
const _seasonEvents = '''
{
  "events": [
    {"idEvent": "1", "strStatus": "FT", "intHomeScore": "2", "intAwayScore": "1", "intRound": "1"},
    {"idEvent": "2", "strStatus": "FT", "intHomeScore": "1", "intAwayScore": "1", "intRound": "1"},
    {"idEvent": "3", "strStatus": "NS", "intRound": "2"}
  ]
}
''';

const _timeline1 = '''
{
  "lookup": [
    {"strTimeline": "Goal", "strTimelineDetail": "Normal Goal", "strPlayer": "Haaland", "strAssist": "Foden", "strTeam": "Man City"},
    {"strTimeline": "Goal", "strTimelineDetail": "Penalty", "strPlayer": "Haaland", "strAssist": "", "strTeam": "Man City"},
    {"strTimeline": "Goal", "strTimelineDetail": "Own Goal", "strPlayer": "Defender", "strTeam": "Man City"},
    {"strTimeline": "Card", "strTimelineDetail": "Yellow Card", "strPlayer": "Rodri", "strTeam": "Man City"}
  ]
}
''';

const _timeline2 = '''
{
  "lookup": [
    {"strTimeline": "Goal", "strTimelineDetail": "Normal Goal", "strPlayer": "Salah", "strAssist": "Foden", "strTeam": "Liverpool"},
    {"strTimeline": "Goal", "strTimelineDetail": "Normal Goal", "strPlayer": "Haaland", "strAssist": "", "strTeam": "Man City"},
    {"strTimeline": "Card", "strTimelineDetail": "Yellow Card", "strPlayer": "Rodri", "strTeam": "Man City"},
    {"strTimeline": "Card", "strTimelineDetail": "Red Card", "strPlayer": "Rodri", "strTeam": "Man City"}
  ]
}
''';

void main() {
  late CacheStore cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheStore(await SharedPreferences.getInstance());
  });

  PlayerStatsRepository buildRepo(_RoutingAdapter v2Adapter) {
    return PlayerStatsRepository(
      v1: _v1With(_RoutingAdapter((path) {
        if (path.contains('eventsseason.php')) return _seasonEvents;
        return '{}';
      })),
      v2: _v2With(v2Adapter),
      cache: cache,
      // No throttling in tests.
      minRequestInterval: Duration.zero,
    );
  }

  String? timelineFor(String path) {
    if (path.endsWith('/1')) return _timeline1;
    if (path.endsWith('/2')) return _timeline2;
    return '{}';
  }

  test('aggregates scorers and assists across finished matches', () async {
    final v2Adapter = _RoutingAdapter(timelineFor);
    final repo = buildRepo(v2Adapter);

    StatsProgress? last;
    await repo.aggregate(
      league: League.premierLeague,
      season: 2025,
      isCancelled: () => false,
      onProgress: (p) => last = p,
    );

    expect(last, isNotNull);
    // Only the two FT matches are processed (the NS one is skipped).
    expect(last!.total, 2);
    expect(last!.processed, 2);

    final scorers = {for (final s in last!.board.scorers) s.player: s};
    // Haaland: 2 (match 1) + 1 (match 2) = 3, one of which is a penalty.
    expect(scorers['Haaland']!.value, 3);
    expect(scorers['Haaland']!.penalties, 1);
    expect(scorers['Haaland']!.team, 'Man City');
    expect(scorers['Salah']!.value, 1);
    expect(scorers['Salah']!.team, 'Liverpool');
    // Own goal is excluded from the scorers board.
    expect(scorers.containsKey('Defender'), isFalse);

    final assists = {for (final a in last!.board.assists) a.player: a};
    expect(assists['Foden']!.value, 2);
    expect(assists['Foden']!.team, isNotNull);

    final cards = {for (final c in last!.board.cards) c.player: c};
    // Rodri: yellow (match 1) + yellow + red (match 2) = 3 total.
    expect(cards['Rodri']!.value, 3);
    expect(cards['Rodri']!.yellows, 2);
    expect(cards['Rodri']!.reds, 1);
    expect(cards['Rodri']!.team, 'Man City');
  });

  test('reuses the per-event cache instead of re-fetching', () async {
    final v2Adapter = _RoutingAdapter(timelineFor);
    final repo = buildRepo(v2Adapter);

    await repo.aggregate(
      league: League.premierLeague,
      season: 2025,
      isCancelled: () => false,
      onProgress: (_) {},
    );
    final firstRunCalls = v2Adapter.calls;
    expect(firstRunCalls, 2); // one timeline call per finished match

    // Second run should hit the cache for both events → no new v2 calls.
    await repo.aggregate(
      league: League.premierLeague,
      season: 2025,
      isCancelled: () => false,
      onProgress: (_) {},
    );
    expect(v2Adapter.calls, firstRunCalls);
  });
}
