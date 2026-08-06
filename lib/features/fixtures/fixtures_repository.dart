import '../../core/api/football_api_client.dart';
import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';
import '../../models/league.dart';

/// Whether we're showing recent results or upcoming matches.
enum FixturesMode { results, upcoming }

/// Fetches league fixtures with a short TTL cache. On TheSportsDB we fetch the
/// season's events once (shared cache key) and split them into recent results
/// and upcoming matches. Falls back to any cached copy on failure.
///
/// Note: on the free key `eventsseason` only returns the first ~15 events of a
/// season, so both lists are limited.
class FixturesRepository {
  FixturesRepository({required this.client, required this.cache});

  static const _ttl = Duration(minutes: 30);

  final FootballApiClient client;
  final CacheStore cache;

  /// Shared cache key so results/upcoming/team views reuse one network call.
  String _cacheKey(int leagueId, int season) => 'season_events_${leagueId}_$season';

  Future<List<Fixture>> getFixtures({
    required League league,
    required int season,
    required FixturesMode mode,
    bool forceRefresh = false,
  }) async {
    final events = await _seasonEvents(
      league: league,
      season: season,
      forceRefresh: forceRefresh,
    );
    return _split(events, mode);
  }

  Future<List<Fixture>> _seasonEvents({
    required League league,
    required int season,
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(league.id, season);

    if (!forceRefresh) {
      final cached = cache.readJson(key);
      if (cached != null && cached.isFresh(_ttl)) {
        return _decode(cached.data);
      }
    }

    try {
      final fresh = await client.getSeasonEvents(
        leagueId: league.id,
        season: apiSeason(season),
      );
      await cache.writeJson(key, fresh.map((e) => e.toJson()).toList());
      return fresh;
    } catch (_) {
      final cached = cache.readJson(key);
      if (cached != null) return _decode(cached.data);
      rethrow;
    }
  }

  List<Fixture> _decode(Object? data) {
    final list = (data as List?) ?? const [];
    return list
        .map((e) => Fixture.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<Fixture> _split(List<Fixture> events, FixturesMode mode) {
    if (mode == FixturesMode.results) {
      // Newest first, so the latest matchweek shows at the top.
      return events.where((e) => e.isFinished).toList()
        ..sort(_byRoundThenDate(descending: true));
    }
    // Soonest first for upcoming fixtures.
    return events.where((e) => !e.isFinished).toList()
      ..sort(_byRoundThenDate(descending: false));
  }

  /// Orders by round (matchweek) first, then kick-off within a round. Events
  /// without a round fall back to date ordering.
  int Function(Fixture, Fixture) _byRoundThenDate({required bool descending}) {
    return (a, b) {
      final ra = a.round;
      final rb = b.round;
      if (ra != null && rb != null && ra != rb) {
        return descending ? rb.compareTo(ra) : ra.compareTo(rb);
      }
      return descending
          ? b.dateUtc.compareTo(a.dateUtc)
          : a.dateUtc.compareTo(b.dateUtc);
    };
  }
}
