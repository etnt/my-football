import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/core/api/football_api_client.dart';
import 'package:my_football/core/api/league_season_resolver.dart';
import 'package:my_football/core/storage/cache_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves canned JSON per path so the resolver can be exercised without any
/// network access, and records every request path.
class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter(this.bodies, {this.throwOn = const {}});

  final Map<String, String> bodies;

  /// Paths that simulate a hard network failure.
  final Set<String> throwOn;
  final List<String> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.path);
    if (throwOn.contains(options.path)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      bodies[options.path] ?? '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

LeagueSeasonResolver _resolver(_RoutingAdapter adapter) {
  return LeagueSeasonResolver(
    client: FootballApiClient(
      apiKey: 'premium123',
      dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter,
    ),
    cache: CacheStore(_prefs),
  );
}

late SharedPreferences _prefs;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  group('isCalendarYearFormat', () {
    test('detects a single-year declared season', () {
      expect(isCalendarYearFormat('2026'), isTrue);
      expect(isCalendarYearFormat(' 2026 '), isTrue);
    });

    test('rejects split years and anything unparseable', () {
      expect(isCalendarYearFormat('2026-2027'), isFalse);
      expect(isCalendarYearFormat('26'), isFalse);
      expect(isCalendarYearFormat(''), isFalse);
      expect(isCalendarYearFormat(null), isFalse);
    });
  });

  group('LeagueSeasonResolver.forStartYear', () {
    test('calendar-year league (Allsvenskan) requests a single-year season',
        () async {
      final adapter = _RoutingAdapter({
        '/premium123/lookupleague.php':
            '{"leagues":[{"idLeague":"4347","strLeague":"Swedish Allsvenskan","strCurrentSeason":"2026"}]}',
      });
      final resolver = _resolver(adapter);

      expect(await resolver.forStartYear(leagueId: 4347, startYear: 2026),
          '2026');
      expect(await resolver.usesSplitYears(4347), isFalse);
      expect(adapter.requests, ['/premium123/lookupleague.php']);
    });

    test('split-year league keeps the YYYY-YYYY format', () async {
      final adapter = _RoutingAdapter({
        '/premium123/lookupleague.php':
            '{"leagues":[{"idLeague":"4328","strLeague":"English Premier League","strCurrentSeason":"2026-2027"}]}',
      });
      final resolver = _resolver(adapter);

      expect(await resolver.forStartYear(leagueId: 4328, startYear: 2025),
          '2025-2026');
      expect(await resolver.usesSplitYears(4328), isTrue);
    });

    test('a missing declaration falls back to the split-year guess', () async {
      final resolver = _resolver(_RoutingAdapter({
        '/premium123/lookupleague.php': '{"leagues":[]}',
      }));

      expect(await resolver.forStartYear(leagueId: 4367, startYear: 2026),
          '2026-2027');
      expect(await resolver.usesSplitYears(4367), isTrue);
    });

    test('a lookup failure falls back instead of throwing', () async {
      final adapter = _RoutingAdapter(
        {},
        throwOn: {'/premium123/lookupleague.php'},
      );
      final resolver = _resolver(adapter);

      expect(await resolver.forStartYear(leagueId: 4347, startYear: 2026),
          '2026-2027');
      expect(await resolver.usesSplitYears(4347), isTrue);
    });

    test('the declared format is fetched once and cached', () async {
      final adapter = _RoutingAdapter({
        '/premium123/lookupleague.php':
            '{"leagues":[{"strCurrentSeason":"2026"}]}',
      });
      final resolver = _resolver(adapter);

      await resolver.forStartYear(leagueId: 4347, startYear: 2026);
      await resolver.forStartYear(leagueId: 4347, startYear: 2025);
      await resolver.usesSplitYears(4347);

      expect(adapter.requests, hasLength(1));
    });

    test('a cached empty declaration is reused without re-querying', () async {
      final adapter = _RoutingAdapter({
        '/premium123/lookupleague.php': '{"leagues":[]}',
      });
      final resolver = _resolver(adapter);

      await resolver.forStartYear(leagueId: 4367, startYear: 2026);
      await resolver.forStartYear(leagueId: 4367, startYear: 2025);

      expect(adapter.requests, hasLength(1));
    });

    test('on failure a stale cached declaration is still used', () async {
      SharedPreferences.setMockInitialValues({
        'league_season_4347':
            jsonEncode({'ts': 1, 'data': '2026'}),
      });
      _prefs = await SharedPreferences.getInstance();
      // The lookup fails outright — the (stale) cache must save the day.
      final adapter = _RoutingAdapter(
        {},
        throwOn: {'/premium123/lookupleague.php'},
      );
      final resolver = _resolver(adapter);

      expect(await resolver.forStartYear(leagueId: 4347, startYear: 2026),
          '2026');
    });
  });
}
