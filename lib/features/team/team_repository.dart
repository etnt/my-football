import '../../core/api/football_api_client.dart';
import '../../core/storage/cache_store.dart';
import '../../models/fixture.dart';

/// Fetches a team's fixtures for a whole season in a single request, cached
/// with a short TTL. The season list is split into recent/upcoming in the UI.
class TeamRepository {
  TeamRepository({required this.client, required this.cache});

  static const _ttl = Duration(minutes: 30);

  final FootballApiClient client;
  final CacheStore cache;

  String _cacheKey(int teamId, int season) => 'team_fixtures_${teamId}_$season';

  Future<List<Fixture>> getSeasonFixtures({
    required int teamId,
    required int season,
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(teamId, season);

    if (!forceRefresh) {
      final cached = cache.readJson(key);
      if (cached != null && cached.isFresh(_ttl)) {
        return _decode(cached.data);
      }
    }

    try {
      final fresh = await client.getFixtures(teamId: teamId, season: season);
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
