import '../../core/api/football_api_client.dart';
import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';
import '../../models/league.dart';

/// Fetches a team's fixtures for a season by pulling the team's league season
/// events (shared cache key with [FixturesRepository]) and filtering by team.
///
/// Note: on the free key the league only exposes ~15 events, so a team will
/// typically have 0-2 matches here.
class TeamRepository {
  TeamRepository({required this.client, required this.cache});

  static const _ttl = Duration(minutes: 30);

  final FootballApiClient client;
  final CacheStore cache;

  /// Shared with [FixturesRepository] so we reuse a single network call.
  String _cacheKey(int leagueId, int season) => 'season_events_${leagueId}_$season';

  Future<List<Fixture>> getSeasonFixtures({
    required int teamId,
    required int leagueId,
    required int season,
    bool forceRefresh = false,
  }) async {
    final events = await _seasonEvents(
      leagueId: leagueId,
      season: season,
      forceRefresh: forceRefresh,
    );
    final matches = events
        .where((e) => e.homeId == teamId || e.awayId == teamId)
        .toList()
      ..sort((a, b) => b.dateUtc.compareTo(a.dateUtc));
    return matches;
  }

  Future<List<Fixture>> _seasonEvents({
    required int leagueId,
    required int season,
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(leagueId, season);

    if (!forceRefresh) {
      final cached = cache.readJson(key);
      if (cached != null && cached.isFresh(_ttl)) {
        return _decode(cached.data);
      }
    }

    try {
      final fresh = await client.getSeasonEvents(
        leagueId: leagueId,
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
}
