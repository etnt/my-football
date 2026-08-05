import '../../core/api/football_api_client.dart';
import '../../core/storage/cache_store.dart';
import '../../models/league.dart';
import '../../models/team_standing.dart';

/// Fetches standings, backed by a TTL cache to conserve the daily quota.
///
/// * Within [_ttl], the cached table is returned without any API call.
/// * On a network/API failure, any previously cached table (even if stale) is
///   returned so the app stays useful offline.
class StandingsRepository {
  StandingsRepository({required this.client, required this.cache});

  static const _ttl = Duration(hours: 6);

  final FootballApiClient client;
  final CacheStore cache;

  String _cacheKey(int leagueId, int season) => 'standings_${leagueId}_$season';

  Future<List<TeamStanding>> getStandings({
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
      final fresh =
          await client.getStandings(leagueId: league.id, season: season);
      await cache.writeJson(key, fresh.map((e) => e.toJson()).toList());
      return fresh;
    } catch (_) {
      // Fall back to any cached copy (possibly stale) before surfacing errors.
      final cached = cache.readJson(key);
      if (cached != null) return _decode(cached.data);
      rethrow;
    }
  }

  List<TeamStanding> _decode(Object? data) {
    final list = (data as List?) ?? const [];
    return list
        .map((e) => TeamStanding.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
